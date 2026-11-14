"""Aperçus HTML des fenêtres de Platyplus, en une commande (render_preview.lua + preview_html.py).

Usage :
  python -I dev/apercu.py              -> régénère toutes les captures dans dev/apercus
  python -I dev/apercu.py chat dialogue -> ne garde dans la liste affichée que les captures dont le nom contient ces mots

Ensuite : servir le dossier dev/apercus sur le port 8765 (python -m http.server 8765) et ouvrir
http://127.0.0.1:8765/<capture>.html  (?x=&y=&s= pour zoomer sur une zone).
"""
import os
import subprocess
import sys
import time

DEV = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(DEV)
OUT = os.path.join(DEV, "apercus")
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, env=ENV, cwd=DEV)
    out = (r.stdout + r.stderr).decode("utf-8", "replace").splitlines()
    return r.returncode, out


def main(argv):
    t = time.time()
    os.makedirs(OUT, exist_ok=True)
    rc, out = run([sys.executable, "-I", os.path.join(DEV, "lua.py"), "run",
                   os.path.join(DEV, "render_preview.lua"), ADDON, DEV, OUT])
    bad = [l for l in out if "ERREUR" in l or "ECHEC" in l or "traceback" in l]
    if rc or bad:
        print("render_preview.lua a échoué :")
        for l in (bad or out[-15:])[:15]:
            print("   " + l)
        return 1
    rc, out2 = run([sys.executable, "-I", os.path.join(DEV, "preview_html.py"), os.path.join(ADDON, "Media"), OUT])
    if rc:
        print("preview_html.py a échoué :")
        for l in out2[-15:]:
            print("   " + l)
        return 1
    pages = sorted(n[:-5] for n in os.listdir(OUT) if n.endswith(".html"))
    if argv:
        pages = [p for p in pages if any(a.lower() in p.lower() for a in argv)]
    print(f"{len(pages)} capture(s) en {time.time() - t:.1f} s — http://127.0.0.1:8765/<nom>.html")
    print("  " + ", ".join(pages))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
