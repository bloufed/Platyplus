"""Tables de données du client Forever (wago.tools), avec cache local dans AddOns/_ref/wago.

Usage :
  python -I dev/wago.py SpellName "Ivresse de la victoire" --fr   -> lignes dont une colonne contient le texte
  python -I dev/wago.py SpellCooldowns 402927                     -> une valeur exacte (ex. un ID) dans une colonne
  python -I dev/wago.py SpellAuraOptions 2565 --col SpellID       -> seulement dans la colonne SpellID
  python -I dev/wago.py --maj SpellName --fr                      -> force le re-téléchargement

Tables utiles : SpellName, SpellCooldowns (ms), SpellAuraOptions (ProcCharges, CumulativeAura),
SpellMisc, SpellEffect, Item, ItemSparse, Map, AreaTable, Faction.
Le build est fixé ci-dessous ; le changer après une mise à jour du client.
"""
import csv
import io
import os
import sys
import urllib.request

BUILD = "1.60.1.70245"
DEV = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.normpath(os.path.join(DEV, "..", "..", "_ref", "wago"))
LIMITE = 30

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def charger(table, fr, maj):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{table}{'_frFR' if fr else ''}_{BUILD}.csv")
    if maj or not os.path.exists(path):
        url = f"https://wago.tools/db2/{table}/csv?build={BUILD}" + ("&locale=frFR" if fr else "")
        req = urllib.request.Request(url, headers={"User-Agent": "platyplus-dev"})
        with urllib.request.urlopen(req, timeout=180) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as f:
        return list(csv.reader(f))


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    fr = "--fr" in argv
    maj = "--maj" in argv
    col = None
    if "--col" in argv:
        col = argv[argv.index("--col") + 1]
    args = [a for i, a in enumerate(argv) if not a.startswith("--") and (i == 0 or argv[i - 1] != "--col")]
    table, needle = args[0], (args[1] if len(args) > 1 else None)
    rows = charger(table, fr, maj)
    head, rows = rows[0], rows[1:]
    print(" | ".join(head))
    if needle is None:
        print(f"({len(rows)} lignes ; donner un texte ou un ID à chercher)")
        return 0
    idx = [head.index(col)] if col and col in head else range(len(head))
    exact = needle.isdigit()
    n = 0
    for r in rows:
        hit = any((r[i] == needle) if exact else (needle.lower() in r[i].lower()) for i in idx if i < len(r))
        if hit:
            print(" | ".join(r))
            n += 1
            if n >= LIMITE:
                print(f"… (arrêt à {LIMITE} lignes)")
                break
    if not n:
        print("aucune ligne")
    return 0 if n else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
