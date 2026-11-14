"""Traduction avec une petite IA locale, servie par Ollama (http://127.0.0.1:11434).

Rien ne sort du PC : Ollama fait tourner le modèle sur la carte graphique.
"""
import json
import os
import re
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.request
from collections import OrderedDict

from .lexique import est_trivial

HOTE = "http://127.0.0.1:11434"
GARDER_CHARGE = "30m"   # le modèle reste en mémoire vidéo 30 min après le dernier message

LANGUES_FR = {
    "en": "anglais", "es": "espagnol", "de": "allemand", "pt": "portugais", "it": "italien",
    "ru": "russe", "pl": "polonais", "nl": "néerlandais", "fr": "français", "sv": "suédois",
    "tr": "turc", "uk": "ukrainien", "cs": "tchèque", "zh": "chinois", "ko": "coréen", "ja": "japonais",
}
LANGUES_EN = {
    "en": "English", "es": "Spanish", "de": "German", "pt": "Portuguese", "it": "Italian",
    "ru": "Russian", "pl": "Polish", "nl": "Dutch", "fr": "French", "sv": "Swedish",
    "tr": "Turkish", "uk": "Ukrainian", "cs": "Czech", "zh": "Chinese", "ko": "Korean", "ja": "Japanese",
}


def nom_langue(code):
    return LANGUES_FR.get(code, code)


# ----------------------------------------------------------------------------
# Repérage rapide du français (pour ne pas réveiller l'IA pour rien)
# ----------------------------------------------------------------------------
_FR = set("""je tu il elle on nous vous ils elles les des est pas avec pour une mais oui non merci salut ça ca
c'est j'ai qui dans sur mon ma mes ton ta tes du au aux et où bonjour bonsoir quelqu'un vais fais faut peux veux
suis trop bien très aussi encore déjà comme quoi pourquoi parce cherche groupe j'arrive attends attendez moi toi
avez avons sont était fait vas va allez venez viens besoin quelqu'un bonne soirée nuit désolé dsl stp svp mdr
cimer ouais nan bah bref voilà voila quand alors donc rien tout tous toutes peut-être""".split())
_EN = set("""the you is are for and with have has what it to of in my your we they this that can need want just
im i'm its it's dont don't yes be was will get got any anyone guys pls plz lf lfm lfg wts wtb how why where who
there here go going thanks thank sorry good nice bad more one some""".split())
_ES = set("""el los las por para una con alguien hola gracias necesito busco falta tengo puedo quiero eres estoy
vamos bueno pero como donde hay muy también tambien soy""".split())
_DE = set("""ich du der die das und ist nicht mit für wer hat bin suche noch gruppe danke hallo ja nein kann mal
auch wir ihr bitte schon gerne""".split())


def langue_probable(texte):
    """« fr » si le message est très probablement en français, sinon None (on laisse l'IA décider)."""
    mots = re.findall(r"[\w'’]+", texte.lower().replace("’", "'"))
    if not mots:
        return None
    fr = sum(m in _FR for m in mots)
    autres = max(sum(m in _EN for m in mots), sum(m in _ES for m in mots), sum(m in _DE for m in mots))
    if re.search(r"[çœèêàù]", texte.lower()) and fr >= 1 and autres == 0:
        return "fr"
    if fr >= 2 and fr > autres * 2:
        return "fr"
    return None


# ----------------------------------------------------------------------------
# Ollama
# ----------------------------------------------------------------------------
class ErreurIA(Exception):
    pass


def trouver_ollama():
    """Chemin de ollama.exe : dans le PATH, sinon aux emplacements d'installation connus."""
    chemin = shutil.which("ollama")
    if chemin:
        return chemin
    local = os.environ.get("LOCALAPPDATA", "")
    for essai in (
        os.path.join(local, "Programs", "Ollama", "ollama.exe"),
        os.path.join(local, "AMD", "AI_Bundle", "Ollama", "ollama.exe"),
        r"C:\Program Files\Ollama\ollama.exe",
    ):
        if os.path.isfile(essai):
            return essai
    return None


class Ollama:
    def __init__(self, hote=HOTE):
        self.hote = hote.rstrip("/")
        self.processus = None  # Ollama lancé par nous (arrêté en quittant)

    def _requete(self, chemin, donnees=None, delai=120):
        url = self.hote + chemin
        corps = None if donnees is None else json.dumps(donnees).encode("utf-8")
        req = urllib.request.Request(url, data=corps, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=delai) as rep:
                return json.loads(rep.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")
            try:
                detail = json.loads(detail).get("error", detail)
            except ValueError:
                pass
            raise ErreurIA(detail) from None
        except (urllib.error.URLError, OSError) as e:
            raise ErreurIA(f"Ollama injoignable ({e})") from None

    def en_marche(self):
        try:
            self._requete("/api/version", delai=2)
            return True
        except ErreurIA:
            return False

    def demarrer(self, attendre=20):
        """Lance « ollama serve » sans fenêtre si Ollama ne tourne pas déjà."""
        if self.en_marche():
            return True
        exe = trouver_ollama()
        if not exe:
            raise ErreurIA("Ollama n'est pas installé (https://ollama.com)")
        drapeaux = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        env = dict(os.environ)
        env.setdefault("OLLAMA_MAX_LOADED_MODELS", "1")  # un seul modèle en mémoire vidéo
        self.processus = subprocess.Popen(
            [exe, "serve"], creationflags=drapeaux, env=env,
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        fin = time.time() + attendre
        while time.time() < fin:
            if self.en_marche():
                return True
            time.sleep(0.3)
        raise ErreurIA("Ollama ne répond pas")

    def arreter(self):
        """Arrête l'Ollama lancé par nous, avec le programme qui fait tourner le modèle (son enfant)."""
        if self.processus and self.processus.poll() is None:
            try:
                subprocess.run(["taskkill", "/PID", str(self.processus.pid), "/T", "/F"], capture_output=True,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), timeout=10)
            except (OSError, subprocess.SubprocessError):
                self.processus.terminate()
        self.processus = None

    def modeles(self):
        return [m.get("name", "") for m in self._requete("/api/tags", delai=5).get("models", [])]

    def a_le_modele(self, modele):
        noms = self.modeles()
        return modele in noms or (":" not in modele and f"{modele}:latest" in noms)

    def telecharger(self, modele, progression=None):
        """Télécharge un modèle ; progression(texte) reçoit l'avancement."""
        corps = json.dumps({"model": modele, "stream": True}).encode("utf-8")
        req = urllib.request.Request(self.hote + "/api/pull", data=corps, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=3600) as rep:
                for ligne in rep:
                    if not ligne.strip():
                        continue
                    info = json.loads(ligne.decode("utf-8"))
                    if info.get("error"):
                        raise ErreurIA(info["error"])
                    if progression:
                        total, fait = info.get("total"), info.get("completed")
                        if total and fait:
                            progression(f"téléchargement du modèle : {fait * 100 // total} %")
                        else:
                            progression(info.get("status", ""))
        except (urllib.error.URLError, OSError) as e:
            raise ErreurIA(f"téléchargement impossible ({e})") from None

    def discuter(self, modele, messages, schema, options=None, delai=60):
        donnees = {
            "model": modele,
            "messages": messages,
            "stream": False,
            "format": schema,
            "keep_alive": GARDER_CHARGE,
            "think": False,
            "options": options or {"temperature": 0.2, "num_predict": 220},
        }
        try:
            rep = self._requete("/api/chat", donnees, delai=delai)
        except ErreurIA as e:
            if "think" not in str(e).lower():
                raise
            donnees.pop("think")  # modèle sans mode « réflexion »
            rep = self._requete("/api/chat", donnees, delai=delai)
        contenu = rep.get("message", {}).get("content", "")
        try:
            return json.loads(contenu)
        except ValueError:
            m = re.search(r"\{.*\}", contenu, re.S)
            if m:
                try:
                    return json.loads(m.group(0))
                except ValueError:
                    pass
            raise ErreurIA(f"réponse illisible : {contenu[:120]!r}") from None


# ----------------------------------------------------------------------------
# Consignes données à l'IA
# ----------------------------------------------------------------------------
CONSIGNE_RECU = """You translate World of Warcraft chat messages into natural French for a French player.
Players type fast: abbreviations, typos, no punctuation, gamer slang. Work out what they MEAN, then write it the way a French player would say it in game chat.
Rules:
- Some words are followed by (= ...): that is their meaning, added to help you. Rely on it, but never copy the "(= ...)" part itself.
- Translate the meaning, not word by word. Silently fix typos.
- Stay short and casual, like chat. Never add explanations, comments or anything that is not in the message.
- French players also say: tank, heal, dps, pull, wipe, loot, drop, farm, stuff, buff, boss, mob, aggro, up, run. Keep those words.
- A dungeon, raid or zone: copy its French name exactly as given in (= ...), then the abbreviation in parentheses if the player used one, e.g. "Cavernes des lamentations (WC)".
- Text inside [square brackets] is an item or quest link: copy it unchanged. Keep player names unchanged.
- "lang": the ISO 639-1 code of the language the player wrote in (en, es, de, pt, it, ru, fr...). Ignore [links] to decide it. Abbreviations alone count as English.
Answer only with JSON: {"lang": "..", "fr": ".."}"""

EXEMPLES_RECU = [
    ("LF2M BFD need heal + dps", {"lang": "en", "fr": "Il manque 2 joueurs pour les Profondeurs de Brassenoire (BFD) : un heal et un dps"}),
    ("any1 got a spare bag? ill pay u", {"lang": "en", "fr": "Quelqu'un aurait un sac en trop ? Je te paie"}),
    ("wtb [Linen Cloth] x20, 1s each, cod ok", {"lang": "en", "fr": "J'achète [Linen Cloth] x20, 1 pièce d'argent l'unité, contre-remboursement ok"}),
    ("alguien para ulda? falta healer y nos vamos", {"lang": "es", "fr": "Quelqu'un pour Uldaman (ulda) ? Il manque un heal et on y va"}),
    ("brb bio dont pull", {"lang": "en", "fr": "Je reviens, pause toilettes, ne pullez pas"}),
]

CONSIGNE_ENVOI = """Translate a French World of Warcraft player's chat message into {langue}.
Write it the way a native {langue}-speaking player would type it in game chat: short, casual, natural.
Rules:
- The answer must be in {langue}.
- Some words are followed by (= ...): that is how players say it in English. Use it when it fits {langue} game chat, but never copy the "(= ...)" part itself.
- Keep the exact meaning. Never add greetings, emojis, comments or anything that is not in the message.
- Dungeons and zones: use the abbreviation players use (WC, SM, BRD...) or the {langue} name.
- Text inside [square brackets] is an item or quest link: copy it unchanged. Keep player names unchanged.
Answer only with JSON: {{"{cle}": ".."}}"""

# Exemples par langue d'arrivée (une petite IA imite très bien un exemple)
EXEMPLES_ENVOI = {
    "en": [
        ("je cherche un groupe pour les cavernes des lamentations, je suis heal", "LFG WC, I'm a healer"),
        ("attendez moi j'arrive dans 2 min", "wait for me, omw, 2 min"),
        ("merci pour le groupe, bonne soirée tout le monde", "ty for the group, have a good evening everyone"),
    ],
    "es": [
        ("je cherche un groupe pour les cavernes des lamentations, je suis heal", "busco grupo para WC, soy healer"),
        ("attendez moi j'arrive dans 2 min", "esperadme, voy en 2 min"),
        ("merci pour le groupe, bonne soirée tout le monde", "gracias por el grupo, buenas noches a todos"),
    ],
    "de": [
        ("je cherche un groupe pour les cavernes des lamentations, je suis heal", "suche Gruppe für WC, bin Heiler"),
        ("attendez moi j'arrive dans 2 min", "wartet auf mich, bin in 2 min da"),
        ("merci pour le groupe, bonne soirée tout le monde", "danke für die Gruppe, schönen Abend noch allen"),
    ],
}

SCHEMA_RECU = {
    "type": "object",
    "properties": {"lang": {"type": "string"}, "fr": {"type": "string"}},
    "required": ["lang", "fr"],
}


def schema_envoi(cle):
    return {"type": "object", "properties": {cle: {"type": "string"}}, "required": [cle]}


def _message_envoi(texte_annote, contexte):
    if contexte:
        return ("Recent chat, for context only: " + " / ".join(contexte[-3:])
                + f"\nFrench message: {texte_annote}")
    return f"French message: {texte_annote}"


# ----------------------------------------------------------------------------
class Resultat:
    def __init__(self, langue, francais, source, duree=0.0):
        self.langue = langue        # code ISO (« en »), « fr » = rien à traduire
        self.francais = francais
        self.source = source        # « lexique », « ia », « cache », « français », « trivial »
        self.duree = duree

    def a_afficher(self):
        return self.source not in ("français", "trivial") and self.langue != "fr" and bool(self.francais)

    def __repr__(self):
        return f"Resultat({self.langue!r}, {self.francais!r}, {self.source}, {self.duree:.2f}s)"


class Traducteur:
    def __init__(self, ollama, lexique, modele):
        self.ollama = ollama
        self.lexique = lexique
        self.modele = modele
        self.cache = OrderedDict()
        self.verrou = threading.Lock()  # une seule requête à la fois vers la carte graphique

    def _memoriser(self, cle, valeur):
        self.cache[cle] = valeur
        self.cache.move_to_end(cle)
        while len(self.cache) > 500:
            self.cache.popitem(last=False)

    def traduire_recu(self, texte):
        texte = texte.strip()
        if est_trivial(texte):
            return Resultat("", "", "trivial")
        if langue_probable(texte) == "fr":
            return Resultat("fr", "", "français")
        cle = ("recu", texte.lower())
        if cle in self.cache:
            r = self.cache[cle]
            return Resultat(r.langue, r.francais, "cache")
        direct = self.lexique.traduction_directe(texte)
        if direct:
            r = Resultat("en", direct, "lexique")
            self._memoriser(cle, r)
            return r
        messages = [{"role": "system", "content": CONSIGNE_RECU}]
        for ex, rep in EXEMPLES_RECU:
            messages.append({"role": "user", "content": self.lexique.annoter(ex)})
            messages.append({"role": "assistant", "content": json.dumps(rep, ensure_ascii=False)})
        messages.append({"role": "user", "content": self.lexique.annoter(texte)})
        debut = time.time()
        with self.verrou:
            rep = self.ollama.discuter(self.modele, messages, SCHEMA_RECU)
        langue = str(rep.get("lang", "")).strip().lower()[:2]
        francais = str(rep.get("fr", "")).strip()
        r = Resultat(langue, francais, "ia", time.time() - debut)
        self._memoriser(cle, r)
        return r

    def traduire_envoi(self, texte, langue, contexte=None):
        """Message en français -> message prêt à coller dans le chat, dans la langue voulue."""
        texte = texte.strip()
        if not texte:
            return ""
        nom = LANGUES_EN.get(langue, langue)
        cle = ("envoi", langue, texte.lower())
        if cle in self.cache:
            return self.cache[cle]
        cle_json = nom.lower()
        messages = [{"role": "system", "content": CONSIGNE_ENVOI.format(langue=nom, cle=cle_json)}]
        for ex, rep in EXEMPLES_ENVOI.get(langue, []):
            messages.append({"role": "user", "content": _message_envoi(self.lexique.annoter(ex, envoi=True), None)})
            messages.append({"role": "assistant", "content": json.dumps({cle_json: rep}, ensure_ascii=False)})
        messages.append({"role": "user", "content": _message_envoi(self.lexique.annoter(texte, envoi=True), contexte)})
        with self.verrou:
            rep = self.ollama.discuter(self.modele, messages, schema_envoi(cle_json))
        sortie = str(rep.get(cle_json, "")).strip().replace("\n", " ")
        sortie = sortie[:255]
        self._memoriser(cle, sortie)
        return sortie

    def prechauffer(self):
        """Charge le modèle en mémoire vidéo pour que la première vraie traduction soit rapide."""
        with self.verrou:
            self.ollama.discuter(self.modele, [{"role": "user", "content": "Say {\"ok\": \"ok\"}"}],
                                 {"type": "object", "properties": {"ok": {"type": "string"}}},
                                 options={"num_predict": 8})
