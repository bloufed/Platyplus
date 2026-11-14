"""Vérification complète de Platyplus en une commande, sortie courte.

1. Syntaxe : compile chaque .lua du .toc (Platyplus) et de dev/.
2. Tests : lance dev/test_*.lua et dev/scenario_*.lua en parallèle, n'affiche que le bilan
   (une ligne par test) et, pour un test en échec, ses lignes ECHEC / ERREUR.

Usage (depuis n'importe où) :
  python -I dev/verifier.py                 -> tout
  python -I dev/verifier.py procs chat      -> syntaxe + tests dont le nom contient « procs » ou « chat »
  python -I dev/verifier.py --syntaxe       -> syntaxe seulement
  python -I dev/verifier.py -v procs        -> sortie complète des tests en échec

Code de sortie 0 si tout passe, 1 sinon.
"""
import concurrent.futures
import os
import re
import subprocess
import sys
import time

DEV = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(DEV)
LUA_PY = os.path.join(DEV, "lua.py")
PAS_DES_TESTS = {"perf.lua", "render_preview.lua", "preview_charworld.lua", "wowmock.lua"}
# Lignes qui signalent un problème (les lignes « ok … sans erreur » ne doivent pas compter).
ECHEC = re.compile(r"^\s*(É|E)CHEC|^\s*ERREUR|^\s*--- erreurs : [1-9]|stack traceback")
LIMITE = 15

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")


def fichiers_toc():
    out = []
    with open(os.path.join(ADDON, "Platyplus.toc"), encoding="utf-8-sig", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            line = re.sub(r"\s*\[.*\]\s*$", "", line)
            if line.lower().endswith(".lua"):
                out.append(os.path.join(ADDON, line.replace("/", os.sep)))
    return out


def syntaxe():
    files = fichiers_toc()
    files += [os.path.join(DEV, n) for n in sorted(os.listdir(DEV)) if n.endswith(".lua")]
    files = [f for f in files if os.path.exists(f)]
    t = time.time()
    r = subprocess.run([sys.executable, "-I", LUA_PY, "check", *files], capture_output=True, env=ENV)
    out = r.stdout.decode("utf-8", "replace").splitlines()
    bad = [l for l in out if not l.startswith("OK")]
    if bad:
        print(f"SYNTAXE : {len(bad)} fichier(s) en erreur")
        for l in bad:
            print("  " + l)
    else:
        print(f"SYNTAXE : {len(files)} fichiers OK ({time.time() - t:.1f} s)")
    return not bad


def lancer(path):
    t = time.time()
    try:
        r = subprocess.run([sys.executable, "-I", LUA_PY, "run", path, ADDON, DEV],
                           capture_output=True, env=ENV, timeout=300, cwd=ADDON)
        out = (r.stdout + r.stderr).decode("utf-8", "replace").splitlines()
        rc = r.returncode
    except subprocess.TimeoutExpired:
        out, rc = ["ERREUR : plus de 300 s, test interrompu"], 1
    fails = [l.rstrip() for l in out if ECHEC.search(l)]
    ok = rc == 0 and not fails
    return os.path.basename(path), ok, time.time() - t, fails, out


def main(argv):
    verbeux = "-v" in argv
    seul_syntaxe = "--syntaxe" in argv
    filtres = [a.lower() for a in argv if not a.startswith("-")]
    t0 = time.time()
    ok = syntaxe()
    if seul_syntaxe:
        return 0 if ok else 1
    tests = [os.path.join(DEV, n) for n in sorted(os.listdir(DEV))
             if n.endswith(".lua") and n not in PAS_DES_TESTS and (n.startswith("test_") or n.startswith("scenario_"))]
    if filtres:
        tests = [p for p in tests if any(f in os.path.basename(p).lower() for f in filtres)]
        if not tests:
            print("Aucun test ne correspond à : " + ", ".join(filtres))
            return 1
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 4)) as ex:
        res = list(ex.map(lancer, tests))
    rates = [r for r in res if not r[1]]
    for name, good, dt, fails, out in res:
        if good:
            continue
        print(f"ÉCHEC {name} ({dt:.1f} s)")
        lignes = out if verbeux else fails or out[-LIMITE:]
        for l in lignes[: (None if verbeux else LIMITE)]:
            print("   " + l.strip())
        if not verbeux and len(fails) > LIMITE:
            print(f"   … {len(fails) - LIMITE} autre(s) ligne(s) (relancer avec -v)")
    passes = len(res) - len(rates)
    print(f"TESTS : {passes}/{len(res)} OK en {time.time() - t0:.1f} s"
          + ("" if not rates else " — en échec : " + ", ".join(r[0] for r in rates)))
    return 0 if ok and not rates else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
