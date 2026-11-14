"""Lecture de la bande de pixels de Platyplus (trad/bande.py) :  python -I tests\\test_bande.py

La bande vient du test de l'add-on (dev\\test_trad.lua), qui la dessine en vrais pixels (768 x 9) dans
%TEMP%\\platyplus_bande.bgra : lancer ce test-là d'abord. Sans ce fichier, seuls les cas sans l'add-on tournent.
"""
import os
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(ICI))

from trad import bande  # noqa: E402

echecs = []
ATTENDU = (1, "Ima Dwaté › ARE YOU")


def verifier(nom, obtenu, attendu):
    if obtenu != attendu:
        echecs.append(f"{nom}\n   obtenu  : {obtenu!r}\n   attendu : {attendu!r}")


def transformer(brut, f):
    """Applique f(valeur) à chaque canal (BGR), alpha gardé."""
    sortie = bytearray(brut)
    for i in range(0, len(sortie), 4):
        for c in range(3):
            sortie[i + c] = max(0, min(255, int(round(f(sortie[i + c])))))
    return bytes(sortie)


def placer(brut, l, h, dx, dy, facteur, L=2100, H=40):
    """L'image posée en (dx, dy) sur un fond, agrandie de `facteur` (plus proche voisin) : interface décalée
    ou rendue à une autre résolution que l'écran."""
    sortie = bytearray(bytes([40, 30, 20, 255]) * (L * H))
    for y in range(H):
        for x in range(L):
            sx, sy = int((x - dx) / facteur), int((y - dy) / facteur)
            if 0 <= sx < l and 0 <= sy < h and x >= dx and y >= dy:
                p, q = (y * L + x) * 4, (sy * l + sx) * 4
                sortie[p:p + 4] = brut[q:q + 4]
    return bande.Image(bytes(sortie), L, H)


fond = bande.Image(bytes([40, 30, 20, 255]) * (200 * 20), 200, 20)
verifier("écran sans bande", bande.lire(fond), None)
verifier("pas de balise", bande.balise(fond), False)
verifier("rien de suspect", bande.suspect(fond), False)

fichier = os.path.join(os.environ.get("TEMP", "."), "platyplus_bande.bgra")
if os.path.isfile(fichier):
    with open(fichier, "rb") as f:
        brut = f.read()
    l, h = 768, 9
    verifier("taille de l'image", len(brut), l * h * 4)
    image = bande.Image(brut, l, h)
    verifier("balise vue", bande.balise(image), True)
    verifier("bande de l'add-on", bande.lire(image), ATTENDU)
    petit = bande.Image(b"".join(brut[y * l * 4:y * l * 4 + bande.LARGEUR_GUET * 4] for y in range(h)),
                        bande.LARGEUR_GUET, h)
    verifier("balise dans la petite capture du guet", bande.balise(petit), True)
    # couleurs un peu changées par le jeu ou l'écran (gamma, luminosité) : l'étalonnage rattrape
    verifier("gamma 0,8", bande.lire(bande.Image(transformer(brut, lambda v: 255 * (v / 255) ** 0.8), l, h)), ATTENDU)
    verifier("plus sombre et délavé", bande.lire(bande.Image(transformer(brut, lambda v: 20 + v * 0.8), l, h)), ATTENDU)
    # position et taille des carrés mesurées sur la balise
    verifier("décalée d'un pixel", bande.lire(placer(brut, l, h, 1, 0, 1)), ATTENDU)
    verifier("décalée de 5 et 2 pixels", bande.lire(placer(brut, l, h, 5, 2, 1)), ATTENDU)
    verifier("interface rendue en 1080 sur un écran 1440 (carrés de 4 px)", bande.lire(placer(brut, l, h, 0, 0, 4 / 3)),
             ATTENDU)
    verifier("carrés de 6 px (échelle 2)", bande.lire(placer(brut, l, h, 0, 0, 2)), ATTENDU)
    raison = []
    abime = bytearray(brut)
    p = (1 * l + (bande.ENTETE + 20) * bande.CELLULE + 1) * 4   # un carré du texte, au centre
    abime[p + 2] = 255 - abime[p + 2]
    verifier("un carré abîmé : refusée", bande.lire(bande.Image(bytes(abime), l, h), raison), None)
    verifier("avec une raison pour le diagnostic", bool(raison), True)
    coupe = bytearray(brut)
    for y in range(h):
        for x in range(3, 6):
            p = (y * l + x) * 4
            coupe[p:p + 4] = bytes([40, 30, 20, 255])
    verifier("balise cassée : rien lu", bande.lire(bande.Image(bytes(coupe), l, h)), None)
    verifier("mais du magenta : suspect (gardé pour le diagnostic)", bande.suspect(bande.Image(bytes(coupe), l, h)), True)
else:
    print("(pas de bande de l'add-on : lance d'abord dev\\test_trad.lua)")

if echecs:
    print(f"{len(echecs)} ÉCHEC(S) :")
    for e in echecs:
        print(" -", e)
    sys.exit(1)
print("tout est bon")
