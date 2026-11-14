"""Réglages du traducteur, gardés dans reglages.json (à côté de Traducteur.pyw).

La plupart se changent depuis le menu ⚙ de la fenêtre ; le fichier sert pour le reste.
"""
import copy
import json
import os

DEFAUTS = {
    "modele": "gemma3:4b",            # petit modèle Ollama (gemma3:12b : plus juste, plus lourd)
    "raccourci": "ctrl+entree",       # ouvre la zone « écrire dans une autre langue » (seulement quand WoW est devant)
    "langue_par_defaut": "en",        # pour écrire, tant que personne d'étranger n'a parlé
    "langues": ["en", "es", "de", "pt", "it", "ru"],  # ordre de la touche Tab dans la zone d'écriture
    "canaux": {                       # quels messages traduire
        "chuchot": True, "groupe": True, "raid": True, "guilde": True, "dire": True,
        "general": True, "commerce": True, "recherche": True, "autres": True,
    },
    "montrer_original": True,         # le message d'origine en petit sous la traduction
    "cacher_hors_du_jeu": True,       # la fenêtre ne s'affiche que quand WoW est devant
    "disparaitre_apres": 20,          # s sans traduction ni envoi avant de se cacher (0 : jamais)
    "quitter_avec_le_jeu": True,      # se ferme (et libère la carte graphique) quand WoW se ferme
    "taille_texte": 11,
    "opacite": 0.9,
    "position": [24, 380, 440, 260],  # x, y, largeur, hauteur de la fenêtre des traductions
    "repliee": False,
    "mes_personnages": [],            # noms à ne jamais traduire (Platyplus note aussi les tiens tout seul)
    "ignorer": ["^Questie\\b", "^<DBM>", "^\\{rt\\d\\}"],  # messages d'addons à ne pas traduire (expressions régulières)
    "fichier_journal": "",            # vide : Logs\\WoWChatLog.txt du jeu
}


class Reglages:
    def __init__(self, chemin):
        self.chemin = chemin
        self.valeurs = copy.deepcopy(DEFAUTS)
        if os.path.isfile(chemin):
            try:
                with open(chemin, encoding="utf-8") as f:
                    lus = json.load(f)
                for cle, val in lus.items():
                    if cle == "canaux" and isinstance(val, dict):
                        self.valeurs["canaux"].update(val)
                    elif cle in DEFAUTS:
                        self.valeurs[cle] = val
            except (OSError, ValueError):
                pass  # fichier abîmé : on repart des valeurs par défaut (il sera réécrit)
        self.sauver()

    def __getitem__(self, cle):
        return self.valeurs[cle]

    def __setitem__(self, cle, val):
        self.valeurs[cle] = val
        self.sauver()

    def sauver(self):
        try:
            temp = self.chemin + ".tmp"
            with open(temp, "w", encoding="utf-8") as f:
                json.dump(self.valeurs, f, ensure_ascii=False, indent=2)
            os.replace(temp, self.chemin)
        except OSError:
            pass
