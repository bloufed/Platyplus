"""Génère Media/Logo.tga (128x128) à partir d'un dessin SVG (dev/logo/*.svg) rendu par Chrome headless.

Usage : python -I make_logo.py <dossier Media> [nom]                 écrit Logo.tga depuis dev/logo/<nom>.svg (défaut : CHOIX)
        python -I make_logo.py <dossier sortie> --planche [noms…]   planche PNG de comparaison (256, 64, 30, 22 px)

Chaque SVG fait 1024x1024 (viewBox 0 0 1024 1024), tout hors du badge transparent. Chrome le rend deux fois
(fond noir, fond blanc) pour retrouver l'alpha exact, puis réduction LANCZOS en alpha prémultiplié (pas de
liseré sombre). Le TGA est écrit à la main (32 bits, origine en bas à gauche), lisible par le jeu et par
dev/preview_html.py.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops

DEV = os.path.dirname(os.path.abspath(__file__))
SVG_DIR = os.path.join(DEV, "logo")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
SIZE = 128
RENDER = 1024
CHOIX = "tuile"
PANEL = (26, 28, 36)
TEXT = (237, 240, 247)


def render(svg_path, bg):
    """Rend le SVG sur un fond uni (#000 ou #fff) et renvoie l'image RGB."""
    svg = open(svg_path, encoding="utf-8").read()
    with tempfile.TemporaryDirectory() as tmp:
        html = os.path.join(tmp, "r.html")
        png = os.path.join(tmp, "r.png")
        with open(html, "w", encoding="utf-8") as f:
            f.write('<!doctype html><html><body style="margin:0;background:%s;overflow:hidden">%s</body></html>' % (bg, svg))
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--window-size=%d,%d" % (RENDER, RENDER), "--screenshot=" + png,
                        "file:///" + html.replace("\\", "/")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return Image.open(png).convert("RGB")


def unpremultiply(pre, alpha):
    """pre = couleur rendue sur noir (prémultipliée), alpha = couche L -> RGBA droit."""
    out = Image.new("RGBA", pre.size)
    pp, pa, po = pre.load(), alpha.load(), out.load()
    w, h = pre.size
    for y in range(h):
        for x in range(w):
            a = pa[x, y]
            if a == 0:
                po[x, y] = (0, 0, 0, 0)
            else:
                r, g, b = pp[x, y]
                k = 255.0 / a
                po[x, y] = (min(255, int(r * k + 0.5)), min(255, int(g * k + 0.5)), min(255, int(b * k + 0.5)), a)
    return out


def render_premultiplied(svg_path):
    """Renvoie (rendu sur noir = couleur prémultipliée, alpha) ; alpha = 1 - (blanc - noir)."""
    black, white = render(svg_path, "#000"), render(svg_path, "#fff")
    alpha = ImageChops.invert(ImageChops.difference(white, black).convert("L"))
    return black, alpha


def downscale(pre, alpha, size):
    """Réduction en prémultiplié puis division : pas de liseré sombre sur les bords."""
    return unpremultiply(pre.resize((size, size), Image.LANCZOS), alpha.resize((size, size), Image.LANCZOS))


def write_tga(path, im):
    w, h = im.size
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, w & 255, w >> 8, h & 255, h >> 8, 32, 8])
    data = bytearray()
    pix = im.load()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = pix[x, y]
            data += bytes([b, g, r, a])
    with open(path, "wb") as f:
        f.write(header + bytes(data))
    print("écrit", path, w, "x", h)


def svg_path(name):
    return os.path.join(SVG_DIR, name + ".svg")


def planche(out_dir, names):
    from PIL import ImageDraw
    cell_w, cell_h = 320, 340
    sheet = Image.new("RGBA", (cell_w * len(names), cell_h), PANEL + (255,))
    for i, name in enumerate(names):
        pre, alpha = render_premultiplied(svg_path(name))
        x0 = i * cell_w
        for size, x, y in ((256, 32, 20), (64, 32, 290), (30, 110, 300), (22, 160, 304)):
            sheet.alpha_composite(downscale(pre, alpha, size), (x0 + x, y))
        ImageDraw.Draw(sheet).text((x0 + 200, 300), name, fill=TEXT)
    path = os.path.join(out_dir, "logo_planche.png")
    sheet.save(path)
    print("écrit", path)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    args = sys.argv[2:]
    if "--planche" in args:
        names = [a for a in args if a != "--planche"] or sorted(f[:-4] for f in os.listdir(SVG_DIR) if f.endswith(".svg"))
        planche(out, names)
    else:
        name = args[0] if args else CHOIX
        pre, alpha = render_premultiplied(svg_path(name))
        write_tga(os.path.join(out, "Logo.tga"), downscale(pre, alpha, SIZE))
