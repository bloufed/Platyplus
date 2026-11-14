"""Recherche d'API dans le code UI officiel de Forever (copie locale : AddOns/_ref/wow-ui-source, branche forever).

Usage :
  python -I dev/api.py GetUnitAuraInstanceIDs          -> fiche(s) de la doc générée (arguments, retours, drapeaux secrets)
  python -I dev/api.py UNIT_AURA                       -> marche aussi pour les événements, tables, enums
  python -I dev/api.py --code QuestLogQuests_Update    -> où le code de Blizzard l'utilise (20 lignes max)
  python -I dev/api.py --maj                           -> met à jour la copie locale (git pull)

Une API absente de la doc générée (vieilles globales comme GetLootSlotInfo) peut quand même exister :
chercher alors avec --code avant de conclure qu'elle manque.
"""
import os
import re
import subprocess
import sys

DEV = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(DEV, "..", "..", "_ref", "wow-ui-source"))
ADDONS = os.path.join(SRC, "Interface", "AddOns")
DOCS = os.path.join(ADDONS, "Blizzard_APIDocumentationGenerated")

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def rel(p):
    return os.path.relpath(p, SRC).replace("\\", "/")


def fiche(name):
    # « C_Spell.GetSpellCooldown » : la doc range le nom court sous Namespace = "C_Spell"
    want_ns = None
    if "." in name:
        want_ns, name = name.rsplit(".", 1)
    # Name = fonctions, tables, enums ; LiteralName = événements (UNIT_COMBAT…)
    pat = re.compile(r'^\s*(Literal)?Name = "' + re.escape(name) + r'",')
    trouve = 0
    for fn in sorted(os.listdir(DOCS)):
        if not fn.endswith(".lua"):
            continue
        path = os.path.join(DOCS, fn)
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
        ns = next((m.group(1) for l in lines[:12] for m in [re.search(r'Namespace = "([^"]+)"', l)] if m), None)
        if want_ns and ns != want_ns:
            continue
        for i, l in enumerate(lines):
            if not pat.match(l):
                continue
            indent = len(l) - len(l.lstrip("\t"))
            if indent <= 1:  # nom du fichier de doc lui-même
                continue
            # bloc : de la « { » qui ouvre jusqu'à la « } » au même retrait
            start = i
            while start > 0 and lines[start - 1].strip() != "{":
                start -= 1
            open_indent = len(lines[start - 1]) - len(lines[start - 1].lstrip("\t"))
            end = i
            while end < len(lines) - 1:
                end += 1
                s = lines[end]
                if s.strip() in ("}", "},") and len(s) - len(s.lstrip("\t")) == open_indent:
                    break
            trouve += 1
            titre = (ns + "." if ns else "") + name
            print(f"== {titre}   ({rel(path)}:{i + 1})")
            for b in lines[start:end]:
                b = b.strip()
                if b and b not in ("{", "},", "}") and not b.endswith("="):
                    print("   " + b)
    return trouve


def code(name, limite=20):
    n = 0
    for root, dirs, files in os.walk(ADDONS):
        if "Blizzard_APIDocumentationGenerated" in root:
            continue
        for fn in files:
            if not fn.endswith((".lua", ".xml")):
                continue
            path = os.path.join(root, fn)
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    for i, l in enumerate(f, 1):
                        if name in l:
                            print(f"{rel(path)}:{i}: {l.strip()[:160]}")
                            n += 1
                            if n >= limite:
                                print(f"… (arrêt à {limite} lignes)")
                                return n
            except OSError:
                pass
    return n


def main(argv):
    if not os.path.isdir(ADDONS):
        print("Copie locale absente : git clone --depth 1 --single-branch --branch forever "
              "https://github.com/Gethe/wow-ui-source.git \"" + SRC + "\"")
        return 2
    if not argv:
        print(__doc__)
        return 2
    if argv[0] == "--maj":
        return subprocess.call(["git", "-C", SRC, "pull", "--depth", "1", "-q"])
    if argv[0] == "--code":
        found = sum(code(n) for n in argv[1:])
        if not found:
            print("Introuvable dans le code de Blizzard.")
        return 0 if found else 1
    total = 0
    for name in argv:
        k = fiche(name)
        if not k:
            print(f"== {name} : absent de la doc générée ; usages dans le code de Blizzard :")
            k = code(name, 10)
            if not k:
                print("   (aucun : probablement inexistant dans Forever)")
        total += k
    return 0 if total else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
