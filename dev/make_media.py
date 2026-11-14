"""Génère les images de Platyplus (TGA 32 bits, dimensions en puissance de 2) sans bibliothèque externe (sauf le logo).

Usage : python -I make_media.py <dossier Media> [logo|round|shadow|glow|bar|flare ...]   (sans nom : toutes les images)
  Logo.tga        128x128  tuile bleue = tête d'ornithorynque de face, bec or, plus or au coin (délégué à make_logo.py, Pillow)
  Flare.tga       128x128  étincelle à quatre branches (Sparkles.lua)
  Round.tga        32x32   rectangle arrondi blanc (rayon 8 px), à découper en 9 morceaux
  RoundStroke.tga  32x32   contour arrondi blanc 1,5 px (même découpe)
  Shadow.tga       64x64   ombre douce (coins de 24 px)
  Circle.tga       64x64   disque blanc lissé
  Glow.tga         64x64   halo radial blanc
  Bar.tga         256x32   remplissage de barre (dégradé vertical + reflet)
  Gradient.tga      8x64   dégradé d'opacité de haut en bas
  PlateMask1..4.tga 256x32 masques rectangle arrondi (rayons 3, 5, 7, 11 px) étirés sur les barres des plates (Plates.lua)
"""
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)


def clamp8(v):
    return int(round(max(0.0, min(1.0, v)) * 255))


def write_tga(name, w, h, px):
    """px[y][x] = (r, g, b, a) en 0..1, origine en haut à gauche ; écrit en bas-gauche (standard TGA)."""
    header = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, w & 255, w >> 8, h & 255, h >> 8, 32, 8])
    data = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = px[y][x]
            data += bytes([clamp8(b), clamp8(g), clamp8(r), clamp8(a)])
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(header + bytes(data))
    print("écrit", name, w, "x", h)


def blank(w, h):
    return [[(0.0, 0.0, 0.0, 0.0) for _ in range(w)] for _ in range(h)]


def over(dst, color, alpha):
    """Composition « par-dessus » en alpha non prémultiplié."""
    dr, dg, db, da = dst
    if alpha <= 0:
        return dst
    oa = alpha + da * (1 - alpha)
    if oa <= 0:
        return (0, 0, 0, 0)
    r = (color[0] * alpha + dr * da * (1 - alpha)) / oa
    g = (color[1] * alpha + dg * da * (1 - alpha)) / oa
    b = (color[2] * alpha + db * da * (1 - alpha)) / oa
    return (r, g, b, oa)


SS = 4  # sur-échantillonnage pour lisser les bords


def draw(px, w, h, inside, color, alpha=1.0):
    """inside(u, v) -> bool en coordonnées 0..1 ; color = (r,g,b) ou fonction (u, v) -> (r,g,b)."""
    for y in range(h):
        for x in range(w):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    u = (x + (sx + 0.5) / SS) / w
                    v = (y + (sy + 0.5) / SS) / h
                    if inside(u, v):
                        hits += 1
            if hits:
                cov = hits / (SS * SS)
                c = color((x + 0.5) / w, (y + 0.5) / h) if callable(color) else color
                px[y][x] = over(px[y][x], c, cov * alpha)


def ellipse(cx, cy, rx, ry, angle_deg=0.0):
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)

    def inside(u, v):
        dx, dy = u - cx, v - cy
        x = dx * ca + dy * sa
        y = -dx * sa + dy * ca
        return (x / rx) ** 2 + (y / ry) ** 2 <= 1.0
    return inside


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def ring(cx, cy, r1, r2):
    def inside(u, v):
        d = math.hypot(u - cx, v - cy)
        return r1 <= d <= r2
    return inside


def rect(x1, y1, x2, y2):
    return lambda u, v: x1 <= u <= x2 and y1 <= v <= y2


def mix(c1, c2, t):
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(3))


# ---------------------------------------------------------------- logo
def make_logo():
    """Logo.tga est dessiné par make_logo.py (Pillow, sur-échantillonnage) : on le lance tel quel."""
    import subprocess
    subprocess.check_call([sys.executable, "-I", os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_logo.py"), OUT])


# ---------------------------------------------------------------- textures d'interface
def rounded(w, h, r, inset=0.0):
    """Rectangle arrondi en pixels (rayon r), renvoie inside(u, v) en coordonnées 0..1."""
    def inside(u, v):
        x, y = u * w, v * h
        x0, y0, x1, y1 = inset, inset, w - inset, h - inset
        if x < x0 or x > x1 or y < y0 or y > y1:
            return False
        cx = min(max(x, x0 + r), x1 - r)
        cy = min(max(y, y0 + r), y1 - r)
        return math.hypot(x - cx, y - cy) <= r
    return inside


def make_round():
    w = h = 32
    px = blank(w, h)
    draw(px, w, h, rounded(w, h, 8), (1, 1, 1))
    write_tga("Round.tga", w, h, px)

    px = blank(w, h)
    outer, inner = rounded(w, h, 8), rounded(w, h, 6.5, 1.5)
    draw(px, w, h, lambda u, v: outer(u, v) and not inner(u, v), (1, 1, 1))
    write_tga("RoundStroke.tga", w, h, px)


def make_shadow():
    w = h = 64
    px = blank(w, h)
    pad, r = 20.0, 6.0
    for y in range(h):
        for x in range(w):
            cx = min(max(x + 0.5, pad + r), w - pad - r)
            cy = min(max(y + 0.5, pad + r), h - pad - r)
            d = max(0.0, math.hypot(x + 0.5 - cx, y + 0.5 - cy) - r)
            a = 0.55 * math.exp(-(d / 9.0) ** 2)
            px[y][x] = (0, 0, 0, a)
    write_tga("Shadow.tga", w, h, px)


def make_circle_glow():
    w = h = 64
    px = blank(w, h)
    draw(px, w, h, circle(0.5, 0.5, 0.48), (1, 1, 1))
    write_tga("Circle.tga", w, h, px)

    px = blank(w, h)
    for y in range(h):
        for x in range(w):
            d = math.hypot((x + 0.5) / w - 0.5, (y + 0.5) / h - 0.5) / 0.5
            a = max(0.0, 1.0 - d) ** 2
            px[y][x] = (1, 1, 1, a)
    write_tga("Glow.tga", w, h, px)


def make_bar():
    w, h = 256, 32
    px = blank(w, h)
    for y in range(h):
        t = (y + 0.5) / h
        shade = 1.0 - 0.28 * t
        if t < 0.12:
            shade = min(1.0, shade + 0.15)
        for x in range(w):
            px[y][x] = (shade, shade, shade, 1.0)
    write_tga("Bar.tga", w, h, px)

    w, h = 8, 64
    px = blank(w, h)
    for y in range(h):
        a = 1.0 - (y + 0.5) / h
        for x in range(w):
            px[y][x] = (1, 1, 1, a)
    write_tga("Gradient.tga", w, h, px)


# ---------------------------------------------------------------- étincelle
def make_flare():
    """Étincelle à quatre branches (Flare.tga) : coeur lumineux, longues branches fines en croix, branches
    en diagonale plus courtes et très pâles. Blanche : Sparkles.lua la teinte (or, gris)."""
    w = h = 128
    px = blank(w, h)
    for y in range(h):
        for x in range(w):
            u = ((x + 0.5) / w - 0.5) * 2.0   # -1..1, centre = 0
            v = ((y + 0.5) / h - 0.5) * 2.0
            r = math.hypot(u, v)
            core = math.exp(-(r / 0.075) ** 2)
            halo = 0.30 * math.exp(-(r / 0.20) ** 2)
            cross = 0.0
            for along, across in ((u, v), (v, u)):
                length = max(0.0, 1.0 - abs(along)) ** 2.4
                cross += length * math.exp(-(across / 0.016) ** 2)
            diag = 0.0
            for a, b in ((u + v, u - v), (u - v, u + v)):
                along, across = a / math.sqrt(2.0), b / math.sqrt(2.0)
                length = max(0.0, 1.0 - abs(along) / 0.5) ** 2.0
                diag += length * math.exp(-(across / 0.020) ** 2)
            a = min(1.0, core + halo + cross * 0.9 + diag * 0.22)
            px[y][x] = (1, 1, 1, a)
    write_tga("Flare.tga", w, h, px)


def make_plate_mask():
    """Masque des barres de plates : blanc opaque dans un rectangle arrondi, transparent ailleurs. Étiré sur la barre
    (environ 190 x 20 px en jeu) : 256 x 32 garde un rapport proche, les coins restent à peu près ronds."""
    w, h = 256, 32
    for i, r in enumerate((3, 5, 7, 11), 1):          # réglage « Arrondi » 1..4 (0 = coins carrés, pas de masque)
        px = blank(w, h)
        draw(px, w, h, rounded(w, h, r), (1, 1, 1))
        write_tga("PlateMask%d.tga" % i, w, h, px)


GENERATORS = {
    "logo": make_logo,
    "round": make_round,
    "shadow": make_shadow,
    "glow": make_circle_glow,
    "bar": make_bar,
    "flare": make_flare,
    "platemask": make_plate_mask,
}
# sans argument : tout ; sinon seulement les images nommées (python -I make_media.py <dossier> flare)
for name, make in GENERATORS.items():
    if len(sys.argv) <= 2 or name in sys.argv[2:]:
        make()
