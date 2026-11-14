"""Construit dev/logo/mark.svg : ornithorynque qui nage, dessiné par une colonne vertébrale en arc
et un profil d'épaisseurs (bec plat, front, corps, croupe, queue-pagaie). Puis : python -I ../make_logo.py … mark

Usage : python -I make_mark.py   (écrit mark.svg à côté)
"""
import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mark.svg")

# Colonne vertébrale (bec vers la gauche, dos cambré) : points de passage, interpolés en Catmull-Rom
SPINE = [(90, 556), (250, 532), (400, 492), (560, 462), (720, 490), (850, 552), (952, 606)]

# Profil (t, dessus, dessous) : demi-épaisseurs au-dessus et au-dessous de la colonne
TOP = [(0.00, 24), (0.05, 34), (0.18, 38), (0.23, 40), (0.31, 88), (0.38, 108), (0.50, 134), (0.62, 128), (0.73, 96),
       (0.80, 70), (0.88, 64), (0.95, 46), (1.00, 12)]
BOT = [(0.00, 32), (0.05, 50), (0.18, 54), (0.23, 56), (0.31, 92), (0.38, 108), (0.50, 136), (0.62, 132), (0.73, 92),
       (0.80, 60), (0.88, 56), (0.95, 40), (1.00, 10)]
T_BILL = 0.235   # racine du bec (pli)
T_EYE = 0.33


def catmull(points, n):
    """Échantillonne une Catmull-Rom passant par points, n points par segment ; renvoie [(x, y, tangente)]."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            dx = 0.5 * ((-p0[0] + p2[0]) + 2 * (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t + 3 * (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t2)
            dy = 0.5 * ((-p0[1] + p2[1]) + 2 * (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t + 3 * (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t2)
            out.append((x, y, math.atan2(dy, dx)))
    out.append((points[-1][0], points[-1][1], out[-1][2]))
    return out


def smoothstep(a, b, t):
    t = max(0.0, min(1.0, (t - a) / (b - a))) if b > a else 1.0
    return t * t * (3 - 2 * t)


def profile(keys, t):
    """Interpolation lissée entre les clés (t, valeur)."""
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            return v0 + (v1 - v0) * smoothstep(t0, t1, t)
    return keys[-1][1]


def arc_length_param(samples):
    acc, total = [0.0], 0.0
    for (x0, y0, _), (x1, y1, _) in zip(samples, samples[1:]):
        total += math.hypot(x1 - x0, y1 - y0)
        acc.append(total)
    return [a / total for a in acc]


def build():
    samples = catmull(SPINE, 60)
    ts = arc_length_param(samples)
    top, bot = [], []
    for (x, y, ang), t in zip(samples, ts):
        nx, ny = -math.sin(ang), math.cos(ang)       # normale « vers le bas » (y croît vers le bas)
        ht, hb = profile(TOP, t), profile(BOT, t)
        top.append((x - nx * ht, y - ny * ht))
        bot.append((x + nx * hb, y + ny * hb))
    return samples, ts, top, bot


def fmt(points):
    return " ".join("%.1f %.1f" % p for p in points)


def path_from(top, bot, i0, i1):
    """Contour fermé entre les indices i0..i1 : dessus à l'endroit, dessous à l'envers."""
    seg_top = top[i0:i1 + 1]
    seg_bot = list(reversed(bot[i0:i1 + 1]))
    return "M " + fmt(seg_top[:1]) + " L " + fmt(seg_top[1:]) + " L " + fmt(seg_bot) + " Z"


def index_at(ts, t):
    return min(range(len(ts)), key=lambda i: abs(ts[i] - t))


def point_at(samples, ts, top, bot, t, frac):
    """Point à la hauteur frac (-1 = dessous, 0 = colonne, 1 = dessus) à l'abscisse t."""
    i = index_at(ts, t)
    x, y, _ = samples[i]
    if frac >= 0:
        return (x + (top[i][0] - x) * frac, y + (top[i][1] - y) * frac)
    return (x + (bot[i][0] - x) * -frac, y + (bot[i][1] - y) * -frac)


def main():
    samples, ts, top, bot = build()
    n = len(samples) - 1
    i_bill = index_at(ts, T_BILL)
    whole = path_from(top, bot, 0, n)
    bill = path_from(top, bot, 0, i_bill + 3)             # déborde sous la tête
    body = path_from(top, bot, i_bill, n)
    ex, ey = point_at(samples, ts, top, bot, T_EYE, 0.45)
    crease_top, crease_bot = top[i_bill], bot[i_bill]
    back_line = "M " + fmt(top[i_bill + 2: n - 8][:1]) + " L " + fmt(top[i_bill + 2: n - 8][1:])
    bill_line = "M " + fmt(top[2: i_bill - 1][:1]) + " L " + fmt(top[2: i_bill - 1][1:])
    nose = point_at(samples, ts, top, bot, 0.05, 0.35)
    # pattes : palmée avant sous le poitrail, arrière plus petite sous la croupe
    fx, fy = point_at(samples, ts, top, bot, 0.40, -0.92)
    bx, by = point_at(samples, ts, top, bot, 0.70, -0.92)

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <radialGradient id="disc" cx="0.40" cy="0.28" r="0.80">
      <stop offset="0" stop-color="#262b36"/>
      <stop offset="0.6" stop-color="#15181f"/>
      <stop offset="1" stop-color="#0a0c10"/>
    </radialGradient>
    <linearGradient id="ring" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="#8ae6ff"/>
      <stop offset="0.5" stop-color="#33ccff"/>
      <stop offset="1" stop-color="#145a86"/>
    </linearGradient>
    <linearGradient id="body" x1="0.3" y1="0" x2="0.6" y2="1">
      <stop offset="0" stop-color="#7ae4ff"/>
      <stop offset="0.45" stop-color="#33c3f5"/>
      <stop offset="1" stop-color="#156fa8"/>
    </linearGradient>
    <linearGradient id="bill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#9aa3b8"/>
      <stop offset="0.5" stop-color="#5a6274"/>
      <stop offset="1" stop-color="#2c313c"/>
    </linearGradient>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="20"/></filter>
    <filter id="softer" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="44"/></filter>
    <filter id="tiny" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="6"/></filter>
    <filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="12"/></filter>
    <clipPath id="clipDisc"><circle cx="512" cy="512" r="442"/></clipPath>
    <path id="whole" d="{whole}"/>
    <path id="billPart" d="{bill}"/>
    <path id="bodyPart" d="{body}"/>
    <clipPath id="clipBody"><use href="#bodyPart"/></clipPath>
    <clipPath id="clipBill"><use href="#billPart"/></clipPath>
  </defs>

  <circle cx="512" cy="528" r="470" fill="#000" opacity="0.45" filter="url(#soft)"/>
  <circle cx="512" cy="512" r="470" fill="url(#ring)"/>
  <circle cx="512" cy="512" r="442" fill="url(#disc)"/>
  <circle cx="512" cy="512" r="442" fill="none" stroke="#000" stroke-opacity="0.6" stroke-width="5"/>
  <circle cx="512" cy="512" r="422" fill="none" stroke="#ffffff" stroke-opacity="0.05" stroke-width="2"/>
  <g clip-path="url(#clipDisc)">
    <ellipse cx="512" cy="96" rx="360" ry="100" fill="#33ccff" opacity="0.16" filter="url(#softer)"/>
  </g>

  <use href="#whole" fill="#000" opacity="0.5" filter="url(#soft)" transform="translate(0 26)"/>

  <!-- pattes palmées -->
  <g fill="#3a4150" stroke="#8a93a8" stroke-opacity="0.45" stroke-width="4" stroke-linejoin="round">
    <path d="M {fx-6:.0f} {fy-26:.0f} c -32 8 -54 32 -46 50 c 20 10 46 8 64 -4 c 18 -12 24 -28 14 -42 z"/>
    <path d="M {bx-4:.0f} {by-20:.0f} c -22 6 -36 24 -30 38 c 14 8 32 6 46 -2 c 12 -10 16 -22 8 -32 z"/>
  </g>

  <!-- bec -->
  <use href="#billPart" fill="url(#bill)"/>
  <g clip-path="url(#clipBill)">
    <path d="{bill_line}" fill="none" stroke="#eef3fa" stroke-opacity="0.6" stroke-width="6" stroke-linecap="round"/>
    <ellipse cx="{nose[0]:.0f}" cy="{nose[1]:.0f}" rx="9" ry="5" fill="#0a0c10" opacity="0.7"/>
    <ellipse cx="{nose[0]+26:.0f}" cy="{nose[1]-5:.0f}" rx="9" ry="5" fill="#0a0c10" opacity="0.7"/>
  </g>

  <!-- corps -->
  <use href="#bodyPart" fill="url(#body)"/>
  <g clip-path="url(#clipBody)">
    <path d="{back_line}" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="40" filter="url(#soft)"/>
    <path d="{back_line}" fill="none" stroke="#d8f6ff" stroke-opacity="0.5" stroke-width="5" filter="url(#tiny)"/>
    <ellipse cx="560" cy="720" rx="360" ry="110" fill="#0a3c5e" opacity="0.6" filter="url(#soft)"/>
    <ellipse cx="900" cy="620" rx="120" ry="90" fill="#0a3c5e" opacity="0.5" filter="url(#soft)"/>
    <path d="M {crease_top[0]:.0f} {crease_top[1]:.0f} Q {crease_top[0]-6:.0f} {(crease_top[1]+crease_bot[1])/2:.0f} {crease_bot[0]:.0f} {crease_bot[1]:.0f}" fill="none" stroke="#0a3c5e" stroke-opacity="0.75" stroke-width="22" filter="url(#tiny)"/>
  </g>
  <circle cx="{ex:.0f}" cy="{ey:.0f}" r="17" fill="#06080c"/>
  <circle cx="{ex+6:.0f}" cy="{ey-6:.0f}" r="5" fill="#ffffff" opacity="0.9"/>

  <!-- plus -->
  <g transform="translate(812 262)">
    <path d="M -44 0 H 44 M 0 -44 V 44" stroke="#33ccff" stroke-width="26" stroke-linecap="round" opacity="0.6" filter="url(#glow)"/>
    <path d="M -42 0 H 42 M 0 -42 V 42" stroke="#e6f8ff" stroke-width="18" stroke-linecap="round"/>
  </g>
</svg>
'''
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(svg)
    print("écrit", OUT)


if __name__ == "__main__":
    main()
