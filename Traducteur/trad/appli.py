"""Le traducteur : relie le journal du chat, l'IA et les fenêtres.

Fils d'exécution :
- tkinter (fenêtres) : le fil principal, le seul qui touche aux fenêtres ;
- moteur : démarre Ollama, télécharge le modèle si besoin, le charge en mémoire vidéo ;
- journal : lit les nouvelles lignes du chat ;
- traduction : traduit les messages un par un (chuchotements et groupe d'abord) ;
- surveillance : quelle fenêtre est devant, raccourci clavier (systeme.Surveillance).
"""
import itertools
import os
import queue
import re
import threading
import time
import tkinter as tk
from collections import deque

from . import systeme
from .fenetres import BLEU, GRIS, OR, ROUGE, VERT, FenetreSaisie, FenetreTraductions, ouvrir_fichier
from .ia import ErreurIA, Ollama, Traducteur, nom_langue
from .journal import Suivi, analyser, analyser_copie, chemin_journal_par_defaut, lire_mes_personnages
from .lexique import Lexique
from .reglages import Reglages

PRIORITES = {"chuchot": 0, "groupe": 1, "raid": 1, "guilde": 2, "dire": 3}
TROP_VIEUX = 25  # s : un message de canal public encore en file après ça n'est plus traduit


def normaliser(texte):
    return re.sub(r"\s+", " ", texte).strip().lower()


class Appli:
    def __init__(self, dossier):
        self.dossier = dossier
        self.reglages = Reglages(os.path.join(dossier, "reglages.json"))
        self.chemin_lexique = os.path.join(dossier, "lexique.txt")
        self.lexique = Lexique(self.chemin_lexique)
        self.ollama = Ollama()
        self.trad = Traducteur(self.ollama, self.lexique, self.reglages["modele"])
        self.chemin_journal = self.reglages["fichier_journal"] or chemin_journal_par_defaut(dossier)

        self.file_ui = queue.Queue()          # (fonction, args) à exécuter dans le fil tkinter
        self.file_trad = queue.PriorityQueue()
        self.compteur = itertools.count()
        self.arret = threading.Event()
        self.pause = False
        self.etat_ia = ("démarrage d'Ollama…", OR)
        self.ia_prete = False
        self.journal_vu = False
        self.devant = "autre"
        self.demarrage = time.time()
        self.derniere_activite = self.demarrage
        self.recents_etrangers = deque(maxlen=8)  # (heure, auteur, texte, langue)
        self.mes_envois = {}                      # texte normalisé -> heure (pour ne pas retraduire mes messages)
        self.mes_noms = set()
        self.toujours_visible = False  # --visible (tests) : jamais cachée, ne se ferme pas avec le jeu
        self._charger_mes_noms()
        self._modeles = []

        racine = tk.Tk()
        self.racine = racine
        try:
            racine.iconbitmap(default=os.path.join(dossier, "icone.ico"))
        except tk.TclError:
            pass
        self.fen = FenetreTraductions(self, racine)
        self.saisie = FenetreSaisie(self, racine)
        raccourci = systeme.lire_raccourci(self.reglages["raccourci"])
        self.surveillance = systeme.Surveillance(raccourci, self._prevenir, self._nos_fenetres,
                                                 os.path.join(dossier, "diagnostic"))
        self._hwnds = {self.fen.hwnd(), self.saisie.hwnd()}
        nom_raccourci = self.reglages["raccourci"].replace("entree", "Entrée").replace("ctrl", "Ctrl").replace("maj", "Maj")
        self.fen.mettre_aide(f"clic sur [FR] : traduire  ·  {nom_raccourci} : écrire  ·  clic ici : répondre")
        if raccourci is None:
            self.fen.ajouter_info(f"Raccourci « {self.reglages['raccourci']} » illisible dans reglages.json.", erreur=True)

    # ------------------------------------------------------------------
    # Démarrage / arrêt
    # ------------------------------------------------------------------
    def noter(self, texte):
        """Une ligne dans diagnostic\\traducteur.log (lancement, fermeture et pourquoi)."""
        try:
            dossier = os.path.join(self.dossier, "diagnostic")
            os.makedirs(dossier, exist_ok=True)
            chemin = os.path.join(dossier, "traducteur.log")
            if os.path.isfile(chemin) and os.path.getsize(chemin) > 200_000:
                os.replace(chemin, chemin + ".ancien")
            with open(chemin, "a", encoding="utf-8") as f:
                f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + texte + "\n")
        except OSError:
            pass

    def lancer(self):
        self.noter("lancé")
        self.fen.ajouter_info("Le traducteur est lancé. Il s'affiche par-dessus le jeu.")
        for cible in (self._moteur, self._lire_journal, self._traduire):
            threading.Thread(target=cible, daemon=True).start()
        self.surveillance.start()
        self.racine.after(50, self._boucle_ui)
        self.racine.after(1000, self._boucle_lente)
        self.racine.mainloop()

    def quitter(self, raison="bouton ✕ ou menu Quitter"):
        if self.arret.is_set():
            return
        s = self.surveillance
        self.noter(f"fermé : {raison} (bandes lues : {s.bandes_lues})")
        self.arret.set()
        self.surveillance.arret.set()
        try:
            if self.ollama.processus:
                self.ollama.arreter()
            else:  # Ollama tournait déjà : on libère quand même la mémoire vidéo
                self.ollama._requete("/api/generate", {"model": self.trad.modele, "keep_alive": 0}, delai=3)
        except ErreurIA:
            pass
        self.racine.after(10, self.racine.destroy)

    # ------------------------------------------------------------------
    # Fil tkinter
    # ------------------------------------------------------------------
    def ui(self, fonction, *args):
        """Depuis n'importe quel fil : exécuter fonction(*args) dans le fil des fenêtres."""
        self.file_ui.put((fonction, args))

    def _boucle_ui(self):
        try:
            while True:
                fonction, args = self.file_ui.get_nowait()
                try:
                    fonction(*args)
                except tk.TclError:
                    pass
        except queue.Empty:
            pass
        if not self.arret.is_set():
            self.racine.after(50, self._boucle_ui)

    def _boucle_lente(self):
        """Une fois par seconde : état affiché, visibilité, fermeture avec le jeu."""
        if self.arret.is_set():
            return
        self._maj_etat()
        self._maj_visibilite()
        if (self.reglages["quitter_avec_le_jeu"] and not self.toujours_visible
                and self.surveillance.wow_vu and not self.surveillance.wow_tourne()):
            self._sans_jeu = getattr(self, "_sans_jeu", 0) + 1
            if self._sans_jeu >= 5:
                self.quitter(f"le jeu s'est fermé (processus {self.surveillance.pid_wow})")
                return
        else:
            self._sans_jeu = 0
        if int(time.time()) % 60 == 0:
            self._charger_mes_noms()
        self.racine.after(1000, self._boucle_lente)

    def _maj_etat(self):
        texte, couleur = self.etat_ia
        if self.ia_prete:
            if self.pause:
                texte, couleur = "en pause", GRIS
            elif not os.path.isfile(self.chemin_journal):
                texte, couleur = "en attente du chat : tape /pp trad dans le jeu", OR
            else:
                texte, couleur = f"prêt · {self.trad.modele}", VERT
        self.fen.etat_moteur(texte, couleur)
        self.fen.b_pause.configure(text="▶" if self.pause else "⏸")

    def activite(self):
        """Une traduction, un envoi, un clic sur [FR]... : la fenêtre se montre (fil des fenêtres seulement)."""
        self.derniere_activite = time.time()
        self._maj_visibilite()

    def _maj_visibilite(self):
        if self.toujours_visible:
            self.fen.montrer(True)
            return
        if self.saisie.ouverte():
            self.fen.montrer(True)
            return
        if self.fen.souris_dessus():  # on la regarde ou on la déplace : elle reste
            self.derniere_activite = time.time()
        maintenant = time.time()
        if maintenant - self.demarrage < 8:  # visible quelques secondes au lancement, même hors du jeu
            self.fen.montrer(True)
            return
        dans_le_jeu = not self.reglages["cacher_hors_du_jeu"] or self.devant in ("wow", "nous")
        delai = self.reglages["disparaitre_apres"]
        # pendant que l'IA démarre (ou si elle ne démarre pas), on laisse voir où elle en est
        recente = not delai or not self.ia_prete or maintenant - self.derniere_activite < delai
        self.fen.montrer(dans_le_jeu and recente)

    def _nos_fenetres(self):
        return self._hwnds

    def _prevenir(self, quoi, info):
        """Appelé par la surveillance (autre fil)."""
        if quoi == "devant":
            self.ui(self._devant_change, info)
        elif quoi == "raccourci":
            self.ui(self.ouvrir_saisie, None, info)
        elif quoi == "copie":
            self._copie_du_jeu(info)

    def _devant_change(self, etat):
        self.devant = etat
        self._maj_visibilite()

    def rendre_au_jeu(self):
        if self.surveillance.hwnd_wow:
            systeme.mettre_devant(self.surveillance.hwnd_wow)

    # ------------------------------------------------------------------
    # IA (moteur)
    # ------------------------------------------------------------------
    def _etat(self, texte, couleur):
        self.etat_ia = (texte, couleur)

    def _moteur(self):
        try:
            self._etat("démarrage d'Ollama…", OR)
            self.ollama.demarrer()
            modele = self.trad.modele
            if not self.ollama.a_le_modele(modele):
                self._etat("téléchargement du modèle…", OR)
                self.ui(self.fen.ajouter_info, f"Premier lancement : téléchargement du modèle {modele} (quelques Go)…")
                self.ollama.telecharger(modele, lambda t: self._etat(t, OR))
            self._etat(f"chargement de {modele}…", OR)
            self.trad.prechauffer()
            self._modeles = self.ollama.modeles()
            self.ia_prete = True
            self.ui(self.activite)  # « prêt » reste affiché 20 s
        except ErreurIA as e:
            self._etat(f"IA indisponible : {e}", ROUGE)
            self.ui(self.fen.ajouter_info, f"L'IA ne démarre pas : {e}", True)

    def modeles_disponibles(self):
        noms = [m for m in self._modeles if not m.startswith(("nomic", "mxbai", "all-minilm"))]
        if self.trad.modele not in noms:
            noms.insert(0, self.trad.modele)
        return noms

    def changer_modele(self, nom):
        if nom == self.trad.modele:
            return
        ancien = self.trad.modele
        self.reglages["modele"] = nom
        self.trad.modele = nom
        self.trad.cache.clear()
        self.ia_prete = False
        self.fen.ajouter_info(f"Modèle : {nom}")

        def charger():
            try:
                self.ollama._requete("/api/generate", {"model": ancien, "keep_alive": 0}, delai=5)
            except ErreurIA:
                pass
            self._moteur()
        threading.Thread(target=charger, daemon=True).start()

    # ------------------------------------------------------------------
    # Messages reçus
    # ------------------------------------------------------------------
    def _charger_mes_noms(self):
        noms = {n.lower() for n in self.reglages["mes_personnages"]}
        noms |= {n.lower() for n in lire_mes_personnages(self.dossier)}
        self.mes_noms = noms

    def _est_moi(self, auteur):
        """« Ry » noté par Platyplus, « Ry Ne » dans le chat (Forever ajoute le nom de famille)."""
        auteur = auteur.lower()
        return any(auteur == nom or auteur.startswith(nom + " ") for nom in self.mes_noms)

    def _a_traduire(self, ligne):
        if ligne.envoye:
            return False
        if self._est_moi(ligne.auteur):
            return False
        if not self.reglages["canaux"].get(ligne.categorie, True):
            return False
        cle = normaliser(ligne.texte)
        if cle in self.mes_envois and time.time() - self.mes_envois[cle] < 600:
            return False
        for motif in self.reglages["ignorer"]:
            try:
                if re.search(motif, ligne.texte):
                    return False
            except re.error:
                continue
        return True

    def _copie_du_jeu(self, texte):
        """Ctrl+C dans le jeu après un clic sur [FR] : Platyplus a mis « Nom › message » dans la zone copiée."""
        ligne = analyser_copie(texte)
        if ligne is None:
            return
        cle = normaliser(ligne.texte)
        if cle in self.mes_envois and time.time() - self.mes_envois[cle] < 600:
            return
        self.ui(self.activite)  # la fenêtre revient tout de suite, la traduction suit
        self.file_trad.put((0, next(self.compteur), time.time(), ligne))

    def _lire_journal(self):
        suivi = Suivi(self.chemin_journal)
        while not self.arret.is_set():
            for brut in suivi.lire():
                ligne = analyser(brut)
                if ligne is None or self.pause or not self._a_traduire(ligne):
                    continue
                priorite = PRIORITES.get(ligne.categorie, 5)
                self.file_trad.put((priorite, next(self.compteur), time.time(), ligne))
            time.sleep(0.25)

    def _traduire(self):
        while not self.arret.is_set():
            try:
                priorite, _, quand, ligne = self.file_trad.get(timeout=0.5)
            except queue.Empty:
                continue
            if priorite >= 4 and time.time() - quand > TROP_VIEUX:
                continue  # le canal public va trop vite : on laisse tomber les vieux messages
            while not self.ia_prete and not self.arret.is_set():
                time.sleep(0.3)
            try:
                r = self.trad.traduire_recu(ligne.texte)
            except ErreurIA as e:
                self.ui(self.fen.ajouter_info, f"Traduction impossible : {e}", True)
                continue
            if r.a_afficher():
                self.recents_etrangers.append((time.time(), ligne.auteur, ligne.texte, r.langue))
                self.ui(self.fen.ajouter_recu, ligne, r)
            elif ligne.categorie == "clic":  # demandé par un clic : toujours une réponse
                pourquoi = "déjà en français" if r.source == "français" or r.langue == "fr" else "rien à traduire"
                self.ui(self.fen.ajouter_info, f"{ligne.auteur} : « {ligne.texte} » : {pourquoi}.")

    # ------------------------------------------------------------------
    # Écrire dans une autre langue
    # ------------------------------------------------------------------
    def langue_pour_ecrire(self):
        """La langue du dernier joueur étranger (moins de 15 min), sinon celle des réglages."""
        for quand, _, _, langue in reversed(self.recents_etrangers):
            if time.time() - quand < 900 and langue and langue != "fr":
                return langue
        return self.reglages["langue_par_defaut"]

    def ouvrir_saisie(self, langue=None, hwnd_jeu=None):
        if self.saisie.ouverte():
            return
        self.saisie.ouvrir(langue or self.langue_pour_ecrire(), hwnd_jeu or self.surveillance.hwnd_wow)
        self.activite()

    def demander_envoi(self, texte, langue):
        contexte = [t for quand, _, t, lg in self.recents_etrangers if lg == langue and time.time() - quand < 600]

        def travail():
            if not self.ia_prete:
                self.ui(self.saisie.resultat, texte, "", "l'IA n'est pas encore prête")
                return
            try:
                traduit = self.trad.traduire_envoi(texte, langue, contexte)
            except ErreurIA as e:
                self.ui(self.saisie.resultat, texte, "", str(e))
                return
            self.ui(self._envoi_pret, texte, traduit, langue)
        threading.Thread(target=travail, daemon=True).start()

    def _envoi_pret(self, texte, traduit, langue):
        if traduit and systeme.copier(traduit):
            self.mes_envois[normaliser(traduit)] = time.time()
            self.fen.ajouter_envoi(texte, traduit, langue)
            self.saisie.resultat(texte, traduit)
        else:
            self.saisie.resultat(texte, "", "copie impossible")

    # ------------------------------------------------------------------
    # Menu
    # ------------------------------------------------------------------
    def basculer_pause(self):
        self.pause = not self.pause
        self._maj_etat()

    def changer_canal(self, cle, valeur):
        canaux = dict(self.reglages["canaux"])
        canaux[cle] = valeur
        self.reglages["canaux"] = canaux

    def changer_reglage(self, cle, valeur):
        self.reglages[cle] = valeur
        if cle == "opacite":
            self.racine.attributes("-alpha", valeur)
        elif cle == "taille_texte":
            self.fen.appliquer_police()
        elif cle in ("cacher_hors_du_jeu", "disparaitre_apres"):
            self.activite()

    def ouvrir_lexique(self):
        ouvrir_fichier(self.chemin_lexique)

    def recharger_lexique(self):
        try:
            self.lexique = Lexique(self.chemin_lexique)
            self.trad.lexique = self.lexique
            self.trad.cache.clear()
            self.fen.ajouter_info(f"Lexique rechargé : {len(self.lexique.entrees)} termes.")
        except (OSError, ValueError) as e:
            self.fen.ajouter_info(f"Lexique illisible : {e}", True)
