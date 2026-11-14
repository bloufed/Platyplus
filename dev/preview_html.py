"""Transforme les scènes JSON de render_preview.lua en pages HTML qui imitent le rendu de WoW.

Usage : python -I preview_html.py <dossier Media> <dossier des captures>
Les images de l'addon (Media/*.tga) sont découpées (SetTexCoord) et teintées (SetVertexColor) comme dans le jeu.
Les icônes et textures de Blizzard, absentes du disque, sont remplacées par des pastilles de couleur.
"""
import base64
import hashlib
import html
import json
import os
import re
import struct
import sys
import zlib

MEDIA, SHOTS = sys.argv[1], sys.argv[2]
_cache = {}


def tga_datauri(name):
    if name in _cache:
        return _cache[name]
    path = os.path.join(MEDIA, name + ".tga")
    if not os.path.exists(path):
        _cache[name] = None
        return None
    data = open(path, "rb").read()
    idlen, w, h, desc = data[0], data[12] | (data[13] << 8), data[14] | (data[15] << 8), data[17]
    pix = data[18 + idlen:]
    top_left = bool(desc & 0x20)
    raw = bytearray()
    for y in range(h):
        sy = y if top_left else h - 1 - y
        raw.append(0)
        for x in range(w):
            i = (sy * w + x) * 4
            raw += bytes([pix[i + 2], pix[i + 1], pix[i], pix[i + 3]])

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    uri = "data:image/png;base64," + base64.b64encode(png).decode()
    _cache[name] = uri
    return uri


def svg_uri(svg):
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


def icon_placeholder(key):
    hsh = hashlib.md5(key.encode()).hexdigest()
    hue = int(hsh[:2], 16) * 360 // 256
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">'
           '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
           f'<stop offset="0" stop-color="hsl({hue},55%,58%)"/><stop offset="1" stop-color="hsl({(hue + 40) % 360},60%,22%)"/>'
           '</linearGradient></defs><rect width="64" height="64" fill="url(#g)"/>'
           f'<circle cx="22" cy="20" r="14" fill="hsl({hue},80%,85%)" opacity="0.35"/>'
           '<rect x="1" y="1" width="62" height="62" fill="none" stroke="#000" stroke-opacity="0.5" stroke-width="2"/></svg>')
    return svg_uri(svg)


COIN = {"gold": ("#ffe066", "#b8860b"), "silver": ("#f2f2f2", "#8a8a8a"), "copper": ("#f0a868", "#8b4a1c")}


def coin_uri(kind):
    a, b = COIN[kind]
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><defs><radialGradient id="g" cx="0.35" cy="0.35">'
           f'<stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></radialGradient></defs>'
           '<circle cx="16" cy="16" r="14" fill="url(#g)" stroke="#3a2a10" stroke-width="2"/></svg>')
    return svg_uri(svg)


def texture_uri(tex):
    """Renvoie (uri, teintable) ; uri None = blanc uni."""
    t = str(tex).replace("/", "\\")
    low = t.lower()
    m = re.search(r"\\addons\\platyplus\\media\\([a-z0-9_]+)", low)
    if m:
        name = t[m.start(1):m.end(1)]
        for real in os.listdir(MEDIA):
            if real.lower() == name.lower() + ".tga":
                name = real[:-4]
        return tga_datauri(name), True
    if "white8x8" in low:
        return None, True
    if "moneyframe" in low:
        kind = "gold" if "gold" in low else "silver" if "silver" in low else "copper"
        return coin_uri(kind), False
    return icon_placeholder(low), False


def rgba(c, extra=1.0):
    r, g, b = c[0], c[1], c[2]
    a = (c[3] if len(c) > 3 and c[3] is not None else 1) * extra
    return f"rgba({int(r * 255)},{int(g * 255)},{int(b * 255)},{a:.3f})"


TOKEN = re.compile(r"\|c([0-9a-fA-F]{8})|\|r|\|T([^|]*)\|t|\|H[^|]*\|h(.*?)\|h|\|n|\n|([^|\n]+)|(\|)")


def markup(text, base_color):
    out, depth = [], 0
    pos = 0
    for m in TOKEN.finditer(text):
        if m.start() != pos:
            out.append(html.escape(text[pos:m.start()]))
        pos = m.end()
        if m.group(1):
            col = m.group(1)[2:]
            out.append(f'<span style="color:#{col}">')
            depth += 1
        elif m.group(0) == "|r":
            if depth:
                out.append("</span>")
                depth -= 1
        elif m.group(2) is not None:
            parts = m.group(2).split(":")
            uri, _ = texture_uri(parts[0])
            size = parts[1] if len(parts) > 1 and parts[1] not in ("", "0") else "1em"
            size = size + "px" if size.isdigit() else size
            out.append(f'<img src="{uri}" style="width:{size};height:{size};vertical-align:middle;margin:0 1px">')
        elif m.group(3) is not None:
            out.append(markup(m.group(3), base_color))
        elif m.group(0) in ("|n", "\n"):
            out.append("<br>")
        elif m.group(4):
            out.append(html.escape(m.group(4)))
        else:
            out.append("|")
    out.append(html.escape(text[pos:]))
    out.append("</span>" * depth)
    return "".join(out)


OUTLINE = "0 0 1px #000,1px 1px 0 #000,-1px -1px 0 #000,1px -1px 0 #000,-1px 1px 0 #000"


def element(e):
    x, y, w, h = e["x"], e["y"], e["w"], e["h"]
    style = [f"left:{x:.1f}px", f"top:{y:.1f}px", f"width:{w:.1f}px", f"height:{h:.1f}px", f"opacity:{e['a']:.3f}"]
    if e.get("clip"):
        cl, ct, cr, cb = e["clip"]
        if x >= cr or x + w <= cl or y >= cb or y + h <= ct:
            return ""
        il, it = max(0, cl - x), max(0, ct - y)
        ir, ib = max(0, x + w - cr), max(0, y + h - cb)
        if il or it or ir or ib:
            style.append(f"clip-path:inset({it:.1f}px {ir:.1f}px {ib:.1f}px {il:.1f}px)")
    if e["kind"] in ("Texture", "MaskTexture"):
        if e["kind"] == "MaskTexture":
            return ""
        tex = e.get("tex")
        if tex == "color":
            c = e.get("color") or [1, 1, 1, 1]
            vc = e.get("vc")
            if vc:
                c = [c[0] * vc[0], c[1] * vc[1], c[2] * vc[2], (c[3] if len(c) > 3 else 1) * (vc[3] if len(vc) > 3 else 1)]
            style.append(f"background:{rgba(c)}")
        elif e.get("tc8") and "gradient" in str(tex).lower():
            # Gradient.tga (opaque en haut -> transparent en bas) tourné par SetTexCoord à 8 valeurs :
            # l'opacité d'un coin vaut 1 - y de sa coordonnée ; on la rend en dégradé CSS
            ulx, uly, llx, lly, urx, ury, lrx, lry = e["tc8"]
            vc = e.get("vc") or [1, 1, 1, 1]
            alpha = vc[3] if len(vc) > 3 else 1
            left, right = 1 - (uly + lly) / 2, 1 - (ury + lry) / 2
            top, bottom = 1 - (uly + ury) / 2, 1 - (lly + lry) / 2
            if abs(left - right) >= abs(top - bottom):
                a0, a1, direction = left, right, "to right"
            else:
                a0, a1, direction = top, bottom, "to bottom"
            style.append(f"background:linear-gradient({direction},{rgba(vc[:3] + [a0 * alpha])},"
                         f"{rgba(vc[:3] + [a1 * alpha])})")
        else:
            uri, tintable = texture_uri(tex)
            vc = e.get("vc") or [1, 1, 1, 1]
            tc = e.get("tc") or [0, 1, 0, 1]
            l, r, t, b = tc
            flip = []
            if r < l:
                l, r = r, l
                flip.append("scaleX(-1)")
            if b < t:
                t, b = b, t
                flip.append("scaleY(-1)")
            bw = w / max(1e-6, (r - l))
            bh = h / max(1e-6, (b - t))
            px, py = -l * bw, -t * bh
            geo = f"{bw:.2f}px {bh:.2f}px"
            posi = f"{px:.2f}px {py:.2f}px"
            plain = all(v > 0.99 for v in vc[:3])
            alpha = vc[3] if len(vc) > 3 else 1
            if uri is None:
                style.append(f"background:{rgba(vc)}")
            elif plain or not tintable:
                style += [f"background-image:url({uri})", f"background-size:{geo}", f"background-position:{posi}",
                          "background-repeat:no-repeat"]
                if alpha < 0.999:
                    style[4] = f"opacity:{e['a'] * alpha:.3f}"
            else:
                style += [f"background-color:{rgba(vc[:3] + [1])}", f"background-image:url({uri})",
                          "background-blend-mode:multiply", f"background-size:{geo}", f"background-position:{posi}",
                          "background-repeat:no-repeat", f"-webkit-mask-image:url({uri})", f"mask-image:url({uri})",
                          f"-webkit-mask-size:{geo}", f"mask-size:{geo}", f"-webkit-mask-position:{posi}",
                          f"mask-position:{posi}", "-webkit-mask-repeat:no-repeat", "mask-repeat:no-repeat"]
                style[4] = f"opacity:{e['a'] * alpha:.3f}"
            if flip:
                style.append("transform:" + " ".join(flip))
        if e.get("desat"):
            style.append("filter:grayscale(1)")
        if e.get("blend") == "ADD":
            style.append("mix-blend-mode:screen")
        return f'<div class="t" style="{";".join(style)}"></div>'
    # texte
    jh = {"LEFT": "flex-start", "RIGHT": "flex-end"}.get(e.get("jh") or "CENTER", "center")
    jv = {"TOP": "flex-start", "BOTTOM": "flex-end"}.get(e.get("jv") or "MIDDLE", "center")
    shadows = []
    if e.get("flags") and "OUTLINE" in str(e["flags"]).upper():
        shadows.append(OUTLINE)
    sh = e.get("shadow")
    if sh:
        shadows.append(f"{sh[0]:.0f}px {-sh[1]:.0f}px 0 rgba(0,0,0,0.9)")
    elif not shadows:
        shadows.append("1px 1px 0 rgba(0,0,0,0.75)")
    style += [f"justify-content:{jh}", f"align-items:{jv}", f"font-size:{e['size']:.1f}px",
              f"color:{rgba(e.get('color') or [1, 1, 1])}", "text-shadow:" + ",".join(shadows)]
    align = {"flex-start": "left", "flex-end": "right"}.get(jh, "center")
    if e.get("wrap"):
        style.append("white-space:normal")
    return (f'<div class="x" style="{";".join(style)}"><span style="text-align:{align}">'
            f"{markup(e['text'], e.get('color'))}</span></div>")


PAGE = """<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Platyplus - {title}</title>
<style>
html,body{{margin:0;background:#0b0d12}}
#scene{{position:relative;width:{w}px;height:{h}px;overflow:hidden;
 background:radial-gradient(ellipse at 30% 25%,#5d7a52 0%,#2f4a33 35%,#1d2b22 65%,#121a16 100%)}}
#scene:before{{content:"";position:absolute;inset:0;background:
 radial-gradient(circle at 70% 70%,rgba(255,220,150,0.10),transparent 40%),
 linear-gradient(180deg,rgba(140,180,220,0.25),transparent 35%)}}
.t,.x{{position:absolute;box-sizing:border-box;pointer-events:none}}
.x{{display:flex;font-family:"Friz Quadrata TT","Trebuchet MS","Segoe UI",sans-serif;line-height:1.15;
 white-space:nowrap;overflow:visible}}
.x img{{display:inline-block}}
</style></head><body><div id="scene">{body}</div>
<script>
// ?x=..&y=..&s=.. : agrandit une zone de l'écran (gros plan pour l'inspection)
var p = new URLSearchParams(location.search), s = parseFloat(p.get("s") || "1");
if (s !== 1) {{
  var sc = document.getElementById("scene");
  sc.style.transformOrigin = "0 0";
  sc.style.transform = "translate(" + (-parseFloat(p.get("x") || 0) * s) + "px," + (-parseFloat(p.get("y") || 0) * s) + "px) scale(" + s + ")";
  document.body.style.overflow = "hidden";
}}
</script></body></html>"""


for name in sorted(os.listdir(SHOTS)):
    if not name.endswith(".json"):
        continue
    scene = json.load(open(os.path.join(SHOTS, name), encoding="utf-8"))
    body = "\n".join(element(e) for e in scene["items"])
    page = PAGE.format(title=name[:-5], w=int(scene["w"]), h=int(scene["h"]), body=body)
    out = os.path.join(SHOTS, name[:-5] + ".html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    print("page", out, len(scene["items"]), "éléments")
