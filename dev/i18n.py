"""Outillage de traduction de Platyplus (le français du code est la langue source ; la clé = le texte français).

Fichiers : Locales/<code>.lua (dictionnaires, un `["clé"] = "traduction",` par ligne, triés),
dev/i18n/cles.json (toutes les clés françaises connues : { "clé": "origine" }),
dev/i18n/manque_<code>.json (+ manque_<code>_NN.json : lots de 150 clés au plus, à remplir).

Usage (depuis n'importe où) :
  python -I dev/i18n.py extraire [--reset]      -> charge tout l'addon dans le monde simulé, ouvre toutes les pages d'options,
                                                   la bienvenue et les commandes d'aide, et AJOUTE les clés trouvées à cles.json
                                                   (--reset : repart de zéro)
  python -I dev/i18n.py extraire --verif <code> -> même parcours AVEC le dictionnaire <code> : liste ce qui n'est pas traduit
                                                   (n'écrit pas cles.json)
  python -I dev/i18n.py manque <code>           -> clés de cles.json absentes de Locales/<code>.lua (compte + fichiers de lots)
  python -I dev/i18n.py ajouter <code> <f.json> -> fusionne { "clé fr": "traduction" } dans Locales/<code>.lua (réécrit trié) ;
                                                   REFUSE tout si une traduction change les marqueurs (%d %s %%, |cAARRGGBB, |r,
                                                   |T..|t, |n, retours \\n) ou est vide
  python -I dev/i18n.py verifier                -> contrôle tous les Locales/*.lua (syntaxe, marqueurs, doublons) + couverture

Code de sortie 0 si tout va bien, 1 sinon (la couverture incomplète n'est pas une erreur).
"""
import json
import os
import re
import subprocess
import sys
import tempfile

DEV = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(DEV)
LOCALES = os.path.join(ADDON, "Locales")
I18N = os.path.join(DEV, "i18n")
CLES = os.path.join(I18N, "cles.json")
LUA_PY = os.path.join(DEV, "lua.py")
LANGS = ["enUS", "deDE", "esES", "itIT", "ptBR", "ruRU"]      # frFR = source
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
LOT = 150

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# ---------------------------------------------------------------------------
# Marqueurs à conserver à l'identique dans une traduction
# ---------------------------------------------------------------------------
RE_FMT = re.compile(r"%[-+#0]*\d*(?:\.\d+)?[sdfxXcgi%]")
RE_COLOR = re.compile(r"\|c[0-9a-fA-F]{8}|\|r|\|T.*?\|t|\|n")


def marqueurs(texte):
    """(suite des formats %, multiensemble trié des autres marqueurs)"""
    formats = RE_FMT.findall(texte)
    autres = sorted(RE_COLOR.findall(texte) + ["\\n"] * texte.count("\n"))
    return formats, autres


def erreur_marqueurs(cle, valeur):
    if not isinstance(valeur, str) or valeur.strip() == "":
        return "traduction vide"
    fk, ak = marqueurs(cle)
    fv, av = marqueurs(valeur)
    if fk != fv:
        return f"formats % différents : clé {fk} / traduction {fv}"
    if ak != av:
        return f"codes couleur / retours différents : clé {ak} / traduction {av}"
    return None


# ---------------------------------------------------------------------------
# Lecture / écriture de Locales/<code>.lua
# ---------------------------------------------------------------------------
LUA_ESC = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}


def lua_unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        i += 1
        n = s[i]
        if n.isdigit():
            j = i
            while j < len(s) and j < i + 3 and s[j].isdigit():
                j += 1
            out.append(chr(int(s[i:j])))
            i = j
        elif n in LUA_ESC:
            out.append(LUA_ESC[n])
            i += 1
        else:
            out.append(n)
            i += 1
    return "".join(out)


def lua_escape(s):
    out = []
    for c in s:
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif c == "\n":
            out.append("\\n")
        elif c == "\r":
            out.append("\\r")
        elif c == "\t":
            out.append("\\t")
        elif ord(c) < 32:
            out.append("\\%03d" % ord(c))
        else:
            out.append(c)
    return "".join(out)


RE_LIGNE = re.compile(r'^\s*\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)",?\s*(?:--.*)?$')


def chemin_locale(code):
    return os.path.join(LOCALES, code + ".lua")


def lire_locale(code):
    """-> (dict, doublons [(clé, n° ligne)], lignes_inconnues [(n° ligne, texte)])"""
    d, dup, inconnues = {}, [], []
    path = chemin_locale(code)
    if not os.path.exists(path):
        return d, dup, inconnues
    with open(path, encoding="utf-8") as f:
        for n, ligne in enumerate(f, 1):
            ligne = ligne.rstrip("\n")
            m = RE_LIGNE.match(ligne)
            if m:
                k, v = lua_unescape(m.group(1)), lua_unescape(m.group(2))
                if k in d:
                    dup.append((k, n))
                d[k] = v
            elif ligne.strip() and not ligne.lstrip().startswith("--") and not ligne.startswith("local ADDON") \
                    and "ns.AddStrings" not in ligne and ligne.strip() != "})":
                inconnues.append((n, ligne))
    return d, dup, inconnues


def ecrire_locale(code, d):
    lignes = ["local ADDON, ns = ...",
              f"-- Traductions {code} (clé = texte français source). Générées/complétées par dev\\i18n.py : ne pas trier à la main.",
              f'ns.AddStrings("{code}", {{']
    for k in sorted(d):
        lignes.append(f'    ["{lua_escape(k)}"] = "{lua_escape(d[k])}",')
    lignes.append("})")
    with open(chemin_locale(code), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lignes) + "\n")


def lire_cles():
    if not os.path.exists(CLES):
        return {}
    with open(CLES, encoding="utf-8") as f:
        return json.load(f)


def ecrire_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")


def verifier_code(code):
    if code == "frFR":
        sys.exit("frFR est la langue source : pas de dictionnaire.")
    if code not in LANGS:
        sys.exit(f"Langue inconnue : {code} (attendu : {', '.join(LANGS)})")


# ---------------------------------------------------------------------------
# extraire
# ---------------------------------------------------------------------------
NOMS_LANGUES = {"Français", "English", "Deutsch", "Español", "Italiano", "Português", "Русский"}


def technique(cle):
    """Vrai pour ce qui n'est pas du texte à traduire (identifiant, ON/OFF, nom de langue, aucun mot)."""
    s = RE_COLOR.sub("", cle)
    s = RE_FMT.sub("", s).strip()
    if not re.search(r"[^\W\d_]", s):
        return True
    if s in ("ON", "OFF") or s in NOMS_LANGUES:
        return True
    if len(RE_COLOR.findall(cle)) >= 6 and len(s) < 70:
        return True            # assemblage dynamique de morceaux colorés (valeur de statut), pas une phrase
    if re.fullmatch(r"[A-Z0-9_]{6,}", s) or re.fullmatch(r"Platyplus( v?[\d.]+)?", s):
        return True            # nom de liaison (INTERACTMOUSEOVER), marque + version
    if re.fullmatch(r"[A-Za-z0-9_.:/\\\-\[\]*|]+", s) and (re.search(r"[_.\\/:]", s) or re.search(r"[a-z][A-Z]", s)):
        return True
    return False


def lancer_extraction(langue, mode):
    fd, tmp = tempfile.mkstemp(suffix=".json")
    os.close(fd)
    try:
        r = subprocess.run([sys.executable, "-I", LUA_PY, "run", os.path.join(DEV, "i18n_extract.lua"),
                            ADDON, DEV, tmp, langue, mode], capture_output=True, env=ENV, timeout=300, cwd=ADDON)
        out = (r.stdout + r.stderr).decode("utf-8", "replace").splitlines()
        if r.returncode != 0 or not os.path.getsize(tmp):
            print("i18n_extract.lua a échoué :")
            for l in out[-15:]:
                print("   " + l)
            return None, out
        with open(tmp, encoding="utf-8") as f:
            return json.load(f), out
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass


def cmd_extraire(argv):
    if "--verif" in argv:
        i = argv.index("--verif")
        code = argv[i + 1] if i + 1 < len(argv) else ""
        verifier_code(code)
        trouve, out = lancer_extraction(code, "garde")
        if trouve is None:
            return 1
        manque = sorted(k for k in trouve if not technique(k))
        print(f"{code} : {len(manque)} chaîne(s) rencontrée(s) sans traduction")
        for k in manque[:60]:
            print(f"  [{trouve[k] or '?'}] {k[:110]!r}")
        if len(manque) > 60:
            print(f"  … {len(manque) - 60} autre(s)")
        return 0
    trouve, out = lancer_extraction("enUS", "vide")
    if trouve is None:
        return 1
    for l in out:
        if "(ignoré)" in l or "erreurs de chargement" in l:
            print(l)
    anciennes = {} if "--reset" in argv else lire_cles()
    nouvelles = 0
    ignorees = 0
    for k, origine in trouve.items():
        if technique(k):
            ignorees += 1
            continue
        if k not in anciennes:
            anciennes[k] = origine
            nouvelles += 1
    ecrire_json(CLES, anciennes)
    print(f"cles.json : {len(anciennes)} clés ({nouvelles} nouvelle(s), {ignorees} chaîne(s) technique(s) ignorée(s))")
    return 0


# ---------------------------------------------------------------------------
# manque
# ---------------------------------------------------------------------------
def cmd_manque(argv):
    if not argv:
        sys.exit("usage : i18n.py manque <code>")
    code = argv[0]
    verifier_code(code)
    cles = lire_cles()
    d, _, _ = lire_locale(code)
    manque = sorted(k for k in cles if k not in d)
    # nettoie d'anciens lots
    if os.path.isdir(I18N):
        for n in os.listdir(I18N):
            if re.fullmatch(rf"manque_{code}(_\d+)?\.json", n):
                os.remove(os.path.join(I18N, n))
    ecrire_json(os.path.join(I18N, f"manque_{code}.json"), {k: "" for k in manque})
    lots = [manque[i:i + LOT] for i in range(0, len(manque), LOT)]
    for n, lot in enumerate(lots, 1):
        ecrire_json(os.path.join(I18N, f"manque_{code}_{n:02d}.json"), {k: "" for k in lot})
    print(f"{code} : {len(cles) - len(manque)}/{len(cles)} traduites, {len(manque)} à traduire"
          + (f" ({len(lots)} lot(s) de {LOT} max dans dev/i18n/manque_{code}_NN.json)" if lots else ""))
    return 0


# ---------------------------------------------------------------------------
# ajouter
# ---------------------------------------------------------------------------
def cmd_ajouter(argv):
    if len(argv) < 2:
        sys.exit("usage : i18n.py ajouter <code> <fichier.json>")
    code, fichier = argv[0], argv[1]
    verifier_code(code)
    with open(fichier, encoding="utf-8-sig") as f:
        neuf = json.load(f)
    if not isinstance(neuf, dict):
        sys.exit("Le fichier JSON doit être un objet { \"clé fr\": \"traduction\" }.")
    erreurs = []
    for k, v in neuf.items():
        e = erreur_marqueurs(k, v)
        if e:
            erreurs.append(f"  {k[:90]!r} : {e}")
    if erreurs:
        print(f"REFUSÉ : {len(erreurs)} traduction(s) incohérente(s) sur {len(neuf)}, rien n'a été écrit :")
        for l in erreurs[:40]:
            print(l)
        if len(erreurs) > 40:
            print(f"  … {len(erreurs) - 40} autre(s)")
        return 1
    # espaces de début / fin de la clé conservés d'office (ex. lignes d'aide indentées)
    for k in list(neuf):
        lead = k[:len(k) - len(k.lstrip())]
        trail = k[len(k.rstrip()):]
        neuf[k] = lead + neuf[k].strip() + trail
    d, _, _ = lire_locale(code)
    ajout = sum(1 for k in neuf if k not in d)
    maj = len(neuf) - ajout
    d.update(neuf)
    ecrire_locale(code, d)
    print(f"{code} : {ajout} ajoutée(s), {maj} remplacée(s), {len(d)} au total")
    return 0


# ---------------------------------------------------------------------------
# verifier
# ---------------------------------------------------------------------------
def cmd_verifier(argv):
    cles = lire_cles()
    problemes = 0
    fichiers = [chemin_locale(c) for c in LANGS if os.path.exists(chemin_locale(c))]
    r = subprocess.run([sys.executable, "-I", LUA_PY, "check", *fichiers], capture_output=True, env=ENV)
    for l in r.stdout.decode("utf-8", "replace").splitlines():
        if not l.startswith("OK"):
            print("SYNTAXE " + l)
            problemes += 1
    bilan = []
    for code in LANGS:
        d, dup, inconnues = lire_locale(code)
        for k, n in dup:
            print(f"{code}: doublon ligne {n} : {k[:80]!r}")
            problemes += 1
        for n, l in inconnues:
            print(f"{code}: ligne {n} non reconnue : {l[:80]!r}")
            problemes += 1
        for k, v in d.items():
            e = erreur_marqueurs(k, v)
            if e:
                print(f"{code}: {k[:80]!r} : {e}")
                problemes += 1
        perimees = sum(1 for k in d if cles and k not in cles)
        couvert = sum(1 for k in cles if k in d)
        bilan.append(f"{code} {couvert}/{len(cles)}" + (f" (+{perimees} hors cles.json)" if perimees else ""))
    print("Couverture : " + " · ".join(bilan))
    print("i18n : " + ("OK" if not problemes else f"{problemes} problème(s)"))
    return 0 if not problemes else 1


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "aide"):
        print(__doc__)
        return 0
    cmd, reste = argv[0], argv[1:]
    table = {"extraire": cmd_extraire, "manque": cmd_manque, "ajouter": cmd_ajouter, "verifier": cmd_verifier}
    if cmd not in table:
        print("Commande inconnue : " + cmd)
        print(__doc__)
        return 1
    return table[cmd](reste)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
