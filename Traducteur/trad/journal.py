"""Lecture du journal du chat de WoW (Logs\\WoWChatLog.txt), écrit par le jeu après /chatlog
(Platyplus l'allume tout seul avec l'option « Traducteur »).

Le format exact des lignes de Forever n'a pas encore été vu : l'analyse accepte
- l'horodatage du journal (« 11/6 01:27:12.345  ») et celui du chat (« 01:27 »),
- les codes de couleur et de lien du jeu (|cff...|r, |Hplayer:...|h[Nom]|h),
- les libellés français et anglais (« [Groupe] Bob : salut », « Bob chuchote : ... », « Bob whispers: ... »).
"""
import os
import re
import time

# ----------------------------------------------------------------------------
# Nettoyage des codes du jeu
# ----------------------------------------------------------------------------
_CODES = [
    (re.compile(r"\|T.*?\|t"), ""),          # icônes
    (re.compile(r"\|A.*?\|a"), ""),          # atlas
    (re.compile(r"\|K.*?\|k"), "?"),         # noms Battle.net codés
    (re.compile(r"\|H.*?\|h"), ""),          # début de lien (le texte du lien reste)
    (re.compile(r"\|h"), ""),
    (re.compile(r"\|c[nN][^:|]*:"), ""),     # couleur nommée (|cnIQ1:)
    (re.compile(r"\|c[0-9a-fA-F]{8}"), ""),
    (re.compile(r"\|r"), ""),
    (re.compile(r"\|4([^:;]*):([^;]*);"), r"\2"),  # pluriels du jeu
    (re.compile(r"\|\|"), "|"),
]

HORODATAGE_JOURNAL = re.compile(r"^\d{1,2}/\d{1,2}(?:/\d{2,4})?\s+\d{1,2}:\d{2}:\d{2}(?:[.,]\d+)?\s+-?\s*")
HORODATAGE_CHAT = re.compile(r"^\[?\d{1,2}:\d{2}(?::\d{2})?\]?\s+")


def nettoyer(texte):
    for motif, rempl in _CODES:
        texte = motif.sub(rempl, texte)
    return texte.replace("\u00a0", " ").replace("\u202f", " ").strip()


# ----------------------------------------------------------------------------
# Analyse d'une ligne
# ----------------------------------------------------------------------------
_NOM = r"\[?(?P<nom>[^\[\]:]+?)\]?(?:-[^\s:\]]+)?"   # « Bob », « [Ry Ne] », « Bob-Royaume »
_DEUX_POINTS = r"\s*:\s?"

FORMES = [
    # chuchotements reçus et envoyés (avant les canaux : « [Bob] chuchote : » commence aussi par un crochet)
    ("chuchot", re.compile(r"^" + _NOM + r"\s+(?:chuchote|whispers)" + _DEUX_POINTS + r"(?P<texte>.*)$")),
    ("envoye", re.compile(r"^(?:À|A|To)\s+" + _NOM + _DEUX_POINTS + r"(?P<texte>.*)$")),
    # dire / crier
    ("dire", re.compile(r"^" + _NOM + r"\s+(?:dit|says|crie|yells)" + _DEUX_POINTS + r"(?P<texte>.*)$")),
    # « [Groupe] [Bob] : salut », « [2. Commerce - Hurlevent] Bob: wts »
    ("canal", re.compile(r"^\[(?P<canal>[^\]]+)\]\s+(?:<[^>]*>\s*)?" + _NOM + _DEUX_POINTS + r"(?P<texte>.*)$")),
]

# nom du canal (en minuscules, sans le numéro) -> catégorie de réglage
CATEGORIES = {
    "groupe": "groupe", "chef de groupe": "groupe", "party": "groupe", "party leader": "groupe",
    "instance": "groupe", "chef d'instance": "groupe", "instance leader": "groupe",
    "raid": "raid", "chef de raid": "raid", "avertissement raid": "raid", "raid leader": "raid", "raid warning": "raid",
    "guilde": "guilde", "officier": "guilde", "guild": "guilde", "officer": "guilde",
    "général": "general", "general": "general",
    "commerce": "commerce", "trade": "commerce", "commerce (services)": "commerce", "services": "commerce",
    "recherchedegroupe": "recherche", "recherche de groupe": "recherche", "lookingforgroup": "recherche",
    "défenselocale": "general", "localdefense": "general", "défense locale": "general",
}

LIBELLES = {
    "groupe": "Groupe", "raid": "Raid", "guilde": "Guilde", "general": "Général", "commerce": "Commerce",
    "recherche": "Recherche", "chuchot": "Chuchot.", "dire": "Dire", "autres": "Canal",
}


class Ligne:
    def __init__(self, categorie, canal, auteur, texte, envoye=False):
        self.categorie = categorie   # clé de réglage : groupe, guilde, chuchot, commerce...
        self.canal = canal           # libellé tel qu'affiché (« Groupe », « 2. Commerce »)
        self.auteur = auteur
        self.texte = texte
        self.envoye = envoye         # chuchotement que j'ai envoyé

    def __repr__(self):
        return f"Ligne({self.categorie!r}, {self.canal!r}, {self.auteur!r}, {self.texte!r}{', envoyé' if self.envoye else ''})"


def categorie_canal(canal):
    nom = re.sub(r"^\d+\.\s*", "", canal).split(" - ")[0].strip().lower()
    return CATEGORIES.get(nom, "autres")


def analyser(brut):
    """Ligne du journal -> Ligne, ou None si ce n'est pas un message de joueur."""
    texte = nettoyer(brut)
    texte = HORODATAGE_JOURNAL.sub("", texte)
    texte = HORODATAGE_CHAT.sub("", texte)
    if not texte:
        return None
    for genre, motif in FORMES:
        m = motif.match(texte)
        if not m:
            continue
        auteur = m.group("nom").strip()
        message = m.group("texte").strip()
        if not auteur or not message:
            return None
        if genre == "canal":
            canal = m.group("canal").strip()
            categorie = categorie_canal(canal)
            libelle = re.sub(r"\s+-\s+.*$", "", canal)  # « 1. Général - Zone » -> « 1. Général »
            return Ligne(categorie, libelle, auteur, message)
        if genre == "chuchot":
            return Ligne("chuchot", "Chuchot.", auteur, message)
        if genre == "envoye":
            return Ligne("chuchot", "Chuchot.", auteur, message, envoye=True)
        return Ligne("dire", "Dire", auteur, message)
    return None


COPIE = re.compile(r"^(?P<nom>[^›\n]{1,60}?) › (?P<texte>.+)$")


def analyser_copie(brut):
    """Texte copié dans le jeu après un clic sur [FR] (« Nom › message », écrit par Platyplus) -> Ligne, sinon None.

    Les autres copies faites dans le jeu (un lien web, tout le chat...) ne sont pas traduites."""
    texte = (brut or "").strip()
    if "\n" in texte or len(texte) > 400:
        return None
    m = COPIE.match(texte)
    if not m:
        return None
    auteur, message = m.group("nom").strip(), nettoyer(m.group("texte"))
    if not message:
        return None
    return Ligne("clic", "FR", auteur or "?", message)


# ----------------------------------------------------------------------------
# Lecture au fil de l'eau
# ----------------------------------------------------------------------------
class Suivi:
    """Lit les nouvelles lignes du fichier à chaque appel de lire() (le début du fichier est ignoré)."""

    def __init__(self, chemin):
        self.chemin = chemin
        self.position = None
        self.reste = b""
        self.derniere_activite = 0.0

    def existe(self):
        return os.path.isfile(self.chemin)

    def lire(self):
        try:
            taille = os.path.getsize(self.chemin)
        except OSError:
            self.position = None
            return []
        if self.position is None:
            self.position = taille  # on ne traduit pas l'historique, seulement ce qui arrive
            return []
        if taille < self.position:  # fichier vidé ou recréé
            self.position = 0
            self.reste = b""
        if taille == self.position:
            return []
        try:
            with open(self.chemin, "rb") as f:
                f.seek(self.position)
                donnees = f.read(taille - self.position)
        except OSError:
            return []
        self.position += len(donnees)
        self.derniere_activite = time.time()
        donnees = self.reste + donnees
        morceaux = donnees.split(b"\n")
        self.reste = morceaux.pop()
        return [m.decode("utf-8", "replace").rstrip("\r") for m in morceaux if m.strip()]


def chemin_journal_par_defaut(dossier_traducteur):
    """Traducteur est dans Interface\\AddOns\\Platyplus : le journal est dans _forever_\\Logs."""
    jeu = os.path.abspath(os.path.join(dossier_traducteur, "..", "..", "..", ".."))
    return os.path.join(jeu, "Logs", "WoWChatLog.txt")


def lire_mes_personnages(dossier_traducteur):
    """Noms de mes personnages, notés par Platyplus dans ses données sauvegardées (PlatyplusDB.tradPersos)."""
    jeu = os.path.abspath(os.path.join(dossier_traducteur, "..", "..", "..", ".."))
    comptes = os.path.join(jeu, "WTF", "Account")
    noms = set()
    if not os.path.isdir(comptes):
        return noms
    for compte in os.listdir(comptes):
        fichier = os.path.join(comptes, compte, "SavedVariables", "Platyplus.lua")
        try:
            with open(fichier, encoding="utf-8", errors="replace") as f:
                contenu = f.read()
        except OSError:
            continue
        m = re.search(r'\["tradPersos"\]\s*=\s*\{(.*?)\n\}', contenu, re.S)
        if m:
            noms.update(re.findall(r'\["([^"]+)"\]\s*=\s*true', m.group(1)))
    return noms
