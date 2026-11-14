"""Les deux fenêtres du traducteur, aux couleurs de Platyplus.

- Traductions : par-dessus le jeu, ne prend jamais le clavier au jeu. Déplaçable par le bandeau,
  redimensionnable par le coin. Clic sur un message : y répondre dans sa langue.
- Saisie : s'ouvre avec le raccourci (Ctrl+Entrée) ; on écrit en français, Entrée traduit et copie.
"""
import os
import tkinter as tk
import tkinter.font as tkfont

from . import systeme
from .ia import nom_langue

FOND = "#11141a"
ENTETE = "#191e27"
SAISIE_FOND = "#0b0d12"
TEXTE = "#e8ecf2"
GRIS = "#8a94a6"
ORIGINE = "#6c7586"
BLEU = "#33ccff"
OR = "#ffd133"
ROUGE = "#ff6060"
VERT = "#5ee08a"
SURVOL = "#2a3140"

# couleurs des canaux du jeu
CANAUX = {
    "chuchot": "#ff80ff", "groupe": "#aaaaff", "raid": "#ff7f00", "guilde": "#40ff40", "dire": "#ffffff",
    "general": "#ffc0c0", "commerce": "#ffc0c0", "recherche": "#ffc0c0", "autres": "#ffc0c0", "moi": BLEU,
    "clic": "#6fb8ff",
}
POLICE = "Segoe UI"
MAX_MESSAGES = 80


def _bouton(parent, texte, action, infobulle_cb=None, couleur=GRIS, taille=10):
    b = tk.Label(parent, text=texte, bg=ENTETE, fg=couleur, font=(POLICE, taille), padx=5, cursor="hand2")
    b.bind("<Button-1>", lambda e: action())
    b.bind("<Enter>", lambda e: b.configure(bg=SURVOL, fg=TEXTE))
    b.bind("<Leave>", lambda e: b.configure(bg=ENTETE, fg=b.couleur))
    b.couleur = couleur
    return b


class FenetreTraductions:
    def __init__(self, appli, racine):
        self.appli = appli
        self.reglages = appli.reglages
        self.win = racine
        self.win.title("Platyplus · Traduction")
        self.win.configure(bg=FOND)
        self.win.overrideredirect(True)
        self.win.attributes("-topmost", True)
        self.win.attributes("-alpha", self.reglages["opacite"])
        x, y, l, h = self.reglages["position"]
        self.taille_depliee = (l, h)
        self.win.geometry(f"{l}x{h}+{x}+{y}")
        self.visible = True
        self._fondu = None  # disparition en cours (after)
        self.n = 0
        self.debuts = []  # marques de début de chaque message (pour retirer les plus anciens)

        # --- bandeau ---
        self.entete = tk.Frame(self.win, bg=ENTETE, height=26)
        self.entete.pack(fill="x", side="top")
        self.pastille = tk.Label(self.entete, text="●", bg=ENTETE, fg=OR, font=(POLICE, 9), padx=6)
        self.pastille.pack(side="left")
        self.titre = tk.Label(self.entete, text="Traduction", bg=ENTETE, fg=TEXTE, font=(POLICE, 9, "bold"))
        self.titre.pack(side="left")
        self.etat = tk.Label(self.entete, text="démarrage…", bg=ENTETE, fg=GRIS, font=(POLICE, 8), anchor="w", padx=8)
        self.etat.pack(side="left", fill="x", expand=True)
        _bouton(self.entete, "✕", appli.quitter, taille=9).pack(side="right")
        self.b_replier = _bouton(self.entete, "▾", self.basculer_repli, taille=9)
        self.b_replier.pack(side="right")
        self.b_menu = _bouton(self.entete, "⚙", self.ouvrir_menu, taille=10)
        self.b_menu.pack(side="right")
        self.b_pause = _bouton(self.entete, "⏸", appli.basculer_pause, taille=9)
        self.b_pause.pack(side="right")
        for w in (self.entete, self.titre, self.etat, self.pastille):
            w.bind("<ButtonPress-1>", self._debut_glisser)
            w.bind("<B1-Motion>", self._glisser)
            w.bind("<ButtonRelease-1>", self._fin_glisser)

        # --- pied : aide et poignée ---
        self.pied = tk.Frame(self.win, bg=FOND)
        self.pied.pack(fill="x", side="bottom")
        self.aide = tk.Label(self.pied, text="", bg=FOND, fg=ORIGINE, font=(POLICE, 8), anchor="w", padx=8)
        self.aide.pack(side="left", fill="x", expand=True)
        self.poignee = tk.Label(self.pied, text="◢", bg=FOND, fg=ORIGINE, font=(POLICE, 8), cursor="size_nw_se")
        self.poignee.pack(side="right")
        self.poignee.bind("<ButtonPress-1>", self._debut_taille)
        self.poignee.bind("<B1-Motion>", self._taille)
        self.poignee.bind("<ButtonRelease-1>", self._fin_glisser)

        # --- messages ---
        self.texte = tk.Text(self.win, bg=FOND, fg=TEXTE, bd=0, highlightthickness=0, wrap="word",
                             padx=10, pady=4, cursor="arrow", state="disabled", takefocus=0)
        self.texte.pack(fill="both", expand=True)
        # Sous Windows, un clic dans une zone de texte lui donne le clavier (même désactivée) :
        # on coupe ce comportement, sinon un clic sur un message volerait le clavier à la zone d'écriture.
        for evt in ("<Button-1>", "<B1-Motion>", "<Double-Button-1>", "<Triple-Button-1>", "<ButtonRelease-1>"):
            self.texte.bind(evt, lambda e: "break")
        self.appliquer_police()

        self.win.update_idletasks()
        systeme.sans_focus(self.win)
        systeme.coins_arrondis(self.win)
        if self.reglages["repliee"]:
            self.basculer_repli(sauver=False)

    # ------------------------------------------------------------------
    def hwnd(self):
        return systeme.hwnd_de(self.win)

    def appliquer_police(self):
        t = int(self.reglages["taille_texte"])
        petit = max(8, t - 2)
        self.texte.tag_configure("meta", font=(POLICE, petit), foreground=GRIS, spacing1=9)
        self.texte.tag_configure("trad", font=(POLICE, t), foreground=TEXTE, spacing1=1, lmargin1=0, lmargin2=0)
        self.texte.tag_configure("orig", font=(POLICE, petit, "italic"), foreground=ORIGINE, spacing1=1)
        self.texte.tag_configure("info", font=(POLICE, petit, "italic"), foreground=GRIS, spacing1=9)
        self.texte.tag_configure("erreur", font=(POLICE, petit), foreground=ROUGE, spacing1=9)
        for cat, couleur in CANAUX.items():
            self.texte.tag_configure("c_" + cat, foreground=couleur)
        self.texte.tag_configure("nom", foreground="#c8d0dc", font=(POLICE, petit, "bold"))
        self.texte.tag_configure("cliquable")
        self.texte.tag_bind("cliquable", "<Enter>", lambda e: self.texte.configure(cursor="hand2"))
        self.texte.tag_bind("cliquable", "<Leave>", lambda e: self.texte.configure(cursor="arrow"))

    def etat_moteur(self, texte, couleur):
        self.etat.configure(text=texte)
        self.pastille.configure(fg=couleur)

    def mettre_aide(self, texte):
        self.aide.configure(text=texte)

    # ------------------------------------------------------------------
    def _ecrire(self, morceaux):
        """morceaux : [(texte, (tags...))]. Garde la vue en bas si elle y était."""
        en_bas = self.texte.yview()[1] >= 0.999
        self.texte.configure(state="normal")
        self.n += 1
        marque = f"m{self.n}"
        debut = self.texte.index("end-1c")
        self.texte.mark_set(marque, debut)
        self.texte.mark_gravity(marque, "left")
        self.debuts.append(marque)
        if debut != "1.0":
            self.texte.insert("end", "\n")
        for texte, tags in morceaux:
            self.texte.insert("end", texte, tags)
        while len(self.debuts) > MAX_MESSAGES:
            ancienne = self.debuts.pop(0)
            self.texte.delete("1.0", self.debuts[0])
            self.texte.mark_unset(ancienne)
        self.texte.configure(state="disabled")
        if en_bas:
            self.texte.see("end")
        self.appli.activite()  # nouveau message : la fenêtre se montre (et repart pour 20 s)

    def ajouter_recu(self, ligne, resultat):
        cat = ligne.categorie
        tag_rep = f"rep{self.n + 1}"
        langue = resultat.langue
        self.texte.tag_bind(tag_rep, "<Button-1>", lambda e, lg=langue: self.win.after(20, self.appli.ouvrir_saisie, lg))
        meta = ("meta", "cliquable", tag_rep)
        morceaux = [
            (f"[{ligne.canal}] ", meta + ("c_" + cat,)),
            (ligne.auteur, meta + ("nom",)),
            (f"  ·  {nom_langue(langue)}", meta),
            ("\n" + resultat.francais, ("trad", "cliquable", tag_rep)),
        ]
        if self.reglages["montrer_original"]:
            morceaux.append(("\n" + ligne.texte, ("orig", "cliquable", tag_rep)))
        self._ecrire(morceaux)

    def ajouter_envoi(self, francais, traduit, langue):
        morceaux = [
            (f"Toi → {nom_langue(langue)}", ("meta", "c_moi")),
            ("   copié : Ctrl+V dans le chat", ("meta",)),
            ("\n" + traduit, ("trad",)),
        ]
        if self.reglages["montrer_original"]:
            morceaux.append(("\n" + francais, ("orig",)))
        self._ecrire(morceaux)

    def ajouter_info(self, texte, erreur=False):
        self._ecrire([(texte, ("erreur" if erreur else "info",))])

    def effacer(self):
        self.texte.configure(state="normal")
        self.texte.delete("1.0", "end")
        self.texte.configure(state="disabled")
        for m in self.debuts:
            self.texte.mark_unset(m)
        self.debuts = []

    # ------------------------------------------------------------------
    def montrer(self, oui):
        if oui:
            if self._fondu:  # elle était en train de disparaître : on la rend tout de suite
                self.win.after_cancel(self._fondu)
                self._fondu = None
                self.win.attributes("-alpha", self.reglages["opacite"])
            if not self.visible:
                self.win.attributes("-alpha", self.reglages["opacite"])
                self.win.deiconify()
                self.win.attributes("-topmost", True)
                systeme.sans_focus(self.win)
            self.visible = True
        elif self.visible:
            self.visible = False
            self._fondre(1.0)

    def _fondre(self, part):
        """Disparition en fondu (un quart de seconde)."""
        part -= 0.15
        if part <= 0:
            self._fondu = None
            self.win.withdraw()
            self.win.attributes("-alpha", self.reglages["opacite"])
            return
        self.win.attributes("-alpha", self.reglages["opacite"] * part)
        self._fondu = self.win.after(35, self._fondre, part)

    def souris_dessus(self):
        if not self.visible:
            return False
        try:
            x, y = self.win.winfo_pointerxy()
            gx, gy = self.win.winfo_rootx(), self.win.winfo_rooty()
            return gx <= x < gx + self.win.winfo_width() and gy <= y < gy + self.win.winfo_height()
        except tk.TclError:
            return False

    def basculer_repli(self, sauver=True):
        repliee = self.texte.winfo_ismapped()
        x, y = self.win.winfo_x(), self.win.winfo_y()
        if repliee:
            self.taille_depliee = (self.win.winfo_width(), self.win.winfo_height())
            self.texte.pack_forget()
            self.pied.pack_forget()
            self.win.geometry(f"{self.taille_depliee[0]}x26+{x}+{y}")
            self.b_replier.configure(text="▸")
        else:
            self.pied.pack(fill="x", side="bottom")
            self.texte.pack(fill="both", expand=True)
            l, h = self.taille_depliee
            self.win.geometry(f"{l}x{h}+{x}+{y}")
            self.b_replier.configure(text="▾")
            self.texte.see("end")
        if sauver:
            self.reglages["repliee"] = repliee
            self._sauver_position()

    # --- déplacer / redimensionner ---
    def _debut_glisser(self, e):
        self._depart = (e.x_root, e.y_root, self.win.winfo_x(), self.win.winfo_y())

    def _glisser(self, e):
        x0, y0, wx, wy = self._depart
        self.win.geometry(f"+{wx + e.x_root - x0}+{wy + e.y_root - y0}")

    def _debut_taille(self, e):
        self._depart = (e.x_root, e.y_root, self.win.winfo_width(), self.win.winfo_height())

    def _taille(self, e):
        x0, y0, l, h = self._depart
        nl, nh = max(260, l + e.x_root - x0), max(110, h + e.y_root - y0)
        self.win.geometry(f"{nl}x{nh}")

    def _fin_glisser(self, e=None):
        self._sauver_position()

    def _sauver_position(self):
        self.win.update_idletasks()
        l, h = self.taille_depliee if not self.texte.winfo_ismapped() else (self.win.winfo_width(), self.win.winfo_height())
        self.reglages["position"] = [self.win.winfo_x(), self.win.winfo_y(), l, h]

    # --- menu ⚙ ---
    def ouvrir_menu(self):
        a = self.appli
        r = self.reglages
        m = tk.Menu(self.win, tearoff=0, bg=ENTETE, fg=TEXTE, activebackground=SURVOL, activeforeground=TEXTE,
                    selectcolor=BLEU, font=(POLICE, 9), bd=0)
        m.add_command(label="Traduire les messages de :", state="disabled")
        noms = [("chuchot", "Chuchotements"), ("groupe", "Groupe et instance"), ("raid", "Raid"), ("guilde", "Guilde"),
                ("dire", "Dire et crier"), ("general", "Canal Général"), ("commerce", "Canal Commerce"),
                ("recherche", "Recherche de groupe"), ("autres", "Autres canaux")]
        self._vars = []
        for cle, nom in noms:
            v = tk.BooleanVar(value=r["canaux"].get(cle, True))
            self._vars.append(v)
            m.add_checkbutton(label="    " + nom, variable=v, command=lambda c=cle, v=v: a.changer_canal(c, v.get()))
        m.add_separator()
        for cle, nom in (("montrer_original", "Montrer le message d'origine"),
                         ("cacher_hors_du_jeu", "Ne s'afficher que dans le jeu"),
                         ("quitter_avec_le_jeu", "Se fermer avec le jeu")):
            v = tk.BooleanVar(value=r[cle])
            self._vars.append(v)
            m.add_checkbutton(label=nom, variable=v, command=lambda c=cle, v=v: a.changer_reglage(c, v.get()))
        v_disp = tk.BooleanVar(value=bool(r["disparaitre_apres"]))
        self._vars.append(v_disp)
        m.add_checkbutton(label="Se cacher après 20 s sans traduction", variable=v_disp,
                          command=lambda: a.changer_reglage("disparaitre_apres", 20 if v_disp.get() else 0))

        langues = tk.Menu(m, tearoff=0, bg=ENTETE, fg=TEXTE, activebackground=SURVOL, selectcolor=BLEU, font=(POLICE, 9))
        v_langue = tk.StringVar(value=r["langue_par_defaut"])
        self._vars.append(v_langue)
        for code in r["langues"]:
            langues.add_radiobutton(label=nom_langue(code), value=code, variable=v_langue,
                                    command=lambda c=code: a.changer_reglage("langue_par_defaut", c))
        m.add_cascade(label="Écrire par défaut en", menu=langues)

        tailles = tk.Menu(m, tearoff=0, bg=ENTETE, fg=TEXTE, activebackground=SURVOL, selectcolor=BLEU, font=(POLICE, 9))
        v_taille = tk.IntVar(value=int(r["taille_texte"]))
        self._vars.append(v_taille)
        for t in range(9, 18):
            tailles.add_radiobutton(label=str(t), value=t, variable=v_taille, command=lambda t=t: a.changer_reglage("taille_texte", t))
        m.add_cascade(label="Taille du texte", menu=tailles)

        opacites = tk.Menu(m, tearoff=0, bg=ENTETE, fg=TEXTE, activebackground=SURVOL, selectcolor=BLEU, font=(POLICE, 9))
        v_op = tk.IntVar(value=int(round(r["opacite"] * 100)))
        self._vars.append(v_op)
        for p in (50, 60, 70, 80, 90, 100):
            opacites.add_radiobutton(label=f"{p} %", value=p, variable=v_op, command=lambda p=p: a.changer_reglage("opacite", p / 100))
        m.add_cascade(label="Opacité", menu=opacites)

        modeles = tk.Menu(m, tearoff=0, bg=ENTETE, fg=TEXTE, activebackground=SURVOL, selectcolor=BLEU, font=(POLICE, 9))
        v_mod = tk.StringVar(value=r["modele"])
        self._vars.append(v_mod)
        for nom in a.modeles_disponibles():
            modeles.add_radiobutton(label=nom, value=nom, variable=v_mod, command=lambda n=nom: a.changer_modele(n))
        m.add_cascade(label="Modèle d'IA", menu=modeles)

        m.add_separator()
        m.add_command(label="Modifier le lexique…", command=a.ouvrir_lexique)
        m.add_command(label="Recharger le lexique", command=a.recharger_lexique)
        m.add_command(label="Effacer les messages", command=self.effacer)
        m.add_separator()
        m.add_command(label="Quitter le traducteur", command=a.quitter)
        x = self.b_menu.winfo_rootx()
        y = self.b_menu.winfo_rooty() + self.b_menu.winfo_height()
        try:
            m.tk_popup(x, y)
        finally:
            m.grab_release()
        a.activite()  # le compte à rebours repart après le menu
        a.rendre_au_jeu()


class FenetreSaisie:
    def __init__(self, appli, racine):
        self.appli = appli
        self.top = tk.Toplevel(racine)
        self.top.withdraw()
        self.top.title("Platyplus · Écrire")
        self.top.overrideredirect(True)
        self.top.attributes("-topmost", True)
        self.top.configure(bg=BLEU)
        self.langue = "en"
        self.hwnd_jeu = None
        self.historique = []
        self.pos_histo = 0
        self.occupe = False

        cadre = tk.Frame(self.top, bg=FOND, padx=12, pady=10)
        cadre.pack(fill="both", expand=True, padx=1, pady=1)
        ligne = tk.Frame(cadre, bg=FOND)
        ligne.pack(fill="x")
        tk.Label(ligne, text="Écris en français", bg=FOND, fg=GRIS, font=(POLICE, 9)).pack(side="left")
        self.puce = tk.Label(ligne, text="", bg=ENTETE, fg=BLEU, font=(POLICE, 9, "bold"), padx=8, pady=1, cursor="hand2")
        self.puce.pack(side="right")
        self.puce.bind("<Button-1>", lambda e: self.langue_suivante(1))
        self.champ = tk.Entry(cadre, bg=SAISIE_FOND, fg=TEXTE, insertbackground=TEXTE, relief="flat",
                              font=(POLICE, 13), width=52, highlightthickness=1, highlightbackground=ENTETE,
                              highlightcolor=BLEU)
        self.champ.pack(fill="x", pady=(8, 6), ipady=6)
        self.aide = tk.Label(cadre, text="", bg=FOND, fg=ORIGINE, font=(POLICE, 8), anchor="w", justify="left")
        self.aide.pack(fill="x")
        self.champ.bind("<Return>", lambda e: self.envoyer())
        self.champ.bind("<KP_Enter>", lambda e: self.envoyer())
        self.champ.bind("<Escape>", lambda e: self.fermer())
        self.champ.bind("<Tab>", lambda e: self.langue_suivante(1))
        self.champ.bind("<Shift-Tab>", lambda e: self.langue_suivante(-1))
        self.champ.bind("<Up>", lambda e: self.histo(-1))
        self.champ.bind("<Down>", lambda e: self.histo(1))
        self.top.bind("<FocusOut>", self._perte_focus)
        self.top.update_idletasks()
        systeme.coins_arrondis(self.top)

    def hwnd(self):
        return systeme.hwnd_de(self.top)

    def ouverte(self):
        return self.top.winfo_viewable()

    def _aide_normale(self):
        self.aide.configure(fg=ORIGINE, text="Entrée : traduire et copier   ·   Tab : changer de langue   ·   Échap : fermer")

    def _maj_puce(self):
        self.puce.configure(text=f"→ {nom_langue(self.langue)}  ⇄")

    def langue_suivante(self, sens):
        liste = list(self.appli.reglages["langues"])
        if self.langue not in liste:
            liste.insert(0, self.langue)
        self.langue = liste[(liste.index(self.langue) + sens) % len(liste)]
        self._maj_puce()
        return "break"

    def histo(self, sens):
        if not self.historique:
            return "break"
        self.pos_histo = max(0, min(len(self.historique), self.pos_histo + sens))
        self.champ.delete(0, "end")
        if self.pos_histo < len(self.historique):
            self.champ.insert(0, self.historique[self.pos_histo])
        return "break"

    def ouvrir(self, langue, hwnd_jeu):
        self.langue = langue
        self.hwnd_jeu = hwnd_jeu
        self.occupe = False
        self.pos_histo = len(self.historique)
        self._maj_puce()
        self._aide_normale()
        self.champ.configure(state="normal")
        self.champ.delete(0, "end")
        # au-dessus du chat, au milieu de l'écran du jeu
        self.top.update_idletasks()
        l, h = self.top.winfo_reqwidth(), self.top.winfo_reqheight()
        rect = systeme.rectangle(hwnd_jeu)
        if rect:
            gauche, haut, droite, bas = rect
        else:
            gauche, haut, droite, bas = 0, 0, self.top.winfo_screenwidth(), self.top.winfo_screenheight()
        x = gauche + (droite - gauche - l) // 2
        y = haut + int((bas - haut) * 0.62) - h // 2
        self.top.geometry(f"+{x}+{y}")
        self.top.deiconify()
        self.top.lift()
        self.top.attributes("-topmost", True)
        self.top.update_idletasks()
        systeme.mettre_devant(self.hwnd())
        self.champ.focus_force()
        self.top.after(250, self._verifier_focus, 1)

    def _verifier_focus(self, essai):
        """Windows refuse parfois de donner le clavier : on réessaie, puis on le dit."""
        if not self.ouverte() or systeme.fenetre_devant() == self.hwnd():
            return
        if essai < 3:
            systeme.mettre_devant(self.hwnd())
            self.champ.focus_force()
            self.top.after(250, self._verifier_focus, essai + 1)
        else:
            self.aide.configure(fg=OR, text="Clique dans la zone pour écrire (Échap : fermer).")

    def envoyer(self):
        if self.occupe:
            return "break"
        texte = self.champ.get().strip()
        if not texte:
            self.fermer()
            return "break"
        if not self.historique or self.historique[-1] != texte:
            self.historique.append(texte)
        self.occupe = True
        self.champ.configure(state="disabled")
        self.aide.configure(fg=OR, text=f"traduction en {nom_langue(self.langue)}…")
        self.appli.demander_envoi(texte, self.langue)
        return "break"

    def resultat(self, francais, traduit, erreur=None):
        """Appelé quand la traduction est prête (ou a échoué)."""
        self.occupe = False
        self.champ.configure(state="normal")
        if erreur or not traduit:
            self.aide.configure(fg=ROUGE, text=f"Échec : {erreur or 'réponse vide'}. Réessaie avec Entrée.")
            self.champ.focus_force()
            return
        self.fermer()

    def fermer(self):
        if not self.ouverte():
            return "break"
        self.top.withdraw()
        if self.hwnd_jeu:
            systeme.mettre_devant(self.hwnd_jeu)
        return "break"

    def _perte_focus(self, e):
        # clic ailleurs (dans le jeu) : on ferme sans traduire, sauf pendant une traduction
        if not self.occupe:
            self.top.after(200, self._fermer_si_ailleurs)

    def _fermer_si_ailleurs(self):
        if self.ouverte() and not self.occupe and systeme.fenetre_devant() != self.hwnd():
            self.top.withdraw()


def ouvrir_fichier(chemin):
    try:
        os.startfile(chemin)
    except OSError:
        pass
