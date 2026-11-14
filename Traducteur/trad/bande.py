"""Lecture de la bande de pixels que Platyplus dessine quand on clique sur [FR] (Traducteur.lua, T.StripCells).

Un add-on ne peut pas parler à un programme : il dessine pendant 0,6 s, en haut à gauche de l'écran du jeu,
des carrés de couleur (3 pixels de côté prévus, rangées de 256). Format :
- carrés 0-2 : balise magenta, vert, magenta ; 3-6 : gris d'étalonnage (niveaux 0, 85, 170, 255) ;
- puis chaque octet en 2 carrés de 4 bits : rouge = 2 bits forts, vert = 2 bits faibles,
  bleu = numéro du carré (depuis le premier octet) modulo 4, pour vérifier l'alignement ;
- octets : numéro du message, longueur (2 octets), texte UTF-8 (« Nom › message »), somme modulo 256.
L'étalonnage rend la lecture juste même si le jeu ou Windows changent un peu les couleurs.
La taille réelle des carrés et la position de la bande sont mesurées sur la balise : si le jeu dessine
l'interface à une autre échelle que prévu (résolution de rendu, échelle de l'interface), on lit quand même.
"""
CELLULE = 3          # côté d'un carré prévu, en pixels de l'écran
LIGNE = 256          # carrés par rangée
ENTETE = 7           # balise + étalonnage
RANGEES_MAX = 3      # 7 + 2 * (4 + 250) carrés au plus
PAS_MAX = 8          # carrés jusqu'à 8 pixels (interface agrandie)
# petite capture faite 10 fois par seconde : le coin où la balise peut être
LARGEUR_GUET, HAUTEUR_GUET = 3 * PAS_MAX + 16, PAS_MAX + 8
# grande capture quand la balise est vue
LARGEUR_MAX = LIGNE * PAS_MAX + 16
HAUTEUR_MAX = RANGEES_MAX * PAS_MAX + 8


class Image:
    """Pixels capturés (BGRA, de haut en bas) d'une zone de l'écran."""

    def __init__(self, brut, largeur, hauteur):
        self.brut, self.largeur, self.hauteur = brut, largeur, hauteur

    def pixel(self, x, y):
        x, y = int(x), int(y)
        if not (0 <= x < self.largeur and 0 <= y < self.hauteur):
            return None
        p = (y * self.largeur + x) * 4
        return self.brut[p + 2], self.brut[p + 1], self.brut[p]


def _magenta(c):
    return c is not None and c[0] > 170 and c[1] < 90 and c[2] > 170


def _vert(c):
    return c is not None and c[0] < 90 and c[1] > 170 and c[2] < 90


def _rose(c):
    """Assez magenta pour mériter un diagnostic si la lecture échoue."""
    return c is not None and c[0] > 140 and c[2] > 140 and c[1] < 110


class Grille:
    """Position (x0, y0) du coin de la bande et taille d'un carré (pas), mesurées sur la balise."""

    def __init__(self, image, x0, y0, pas):
        self.image, self.x0, self.y0, self.pas = image, x0, y0, pas

    def carre(self, i):
        x = self.x0 + ((i % LIGNE) + 0.5) * self.pas
        y = self.y0 + ((i // LIGNE) + 0.5) * self.pas
        return self.image.pixel(x, y)


def trouver(image):
    """La balise magenta-vert-magenta dans le coin : Grille, ou None."""
    for y in range(min(image.hauteur, HAUTEUR_GUET)):
        for x in range(min(image.largeur, LARGEUR_GUET)):
            if not _magenta(image.pixel(x, y)):
                continue
            # longueurs des trois carrés de la balise sur cette rangée de pixels
            fin1 = x
            while _magenta(image.pixel(fin1, y)):
                fin1 += 1
            fin2 = fin1
            while _vert(image.pixel(fin2, y)):
                fin2 += 1
            fin3 = fin2
            while _magenta(image.pixel(fin3, y)):
                fin3 += 1
            m1, v, m2 = fin1 - x, fin2 - fin1, fin3 - fin2
            if not (v and m2) or max(m1, v, m2) - min(m1, v, m2) > 2 or v > PAS_MAX + 1:
                continue
            pas = (fin3 - x) / 3
            # haut du carré : on remonte tant que c'est magenta
            haut = y
            while haut > 0 and _magenta(image.pixel(x + m1 // 2, haut - 1)):
                haut -= 1
            return Grille(image, x, haut, pas)
    return None


def balise(image):
    """Vrai si la bande est affichée."""
    return trouver(image) is not None


def suspect(image):
    """Du magenta dans le coin, sans balise lisible : à garder pour comprendre."""
    for y in range(0, min(image.hauteur, HAUTEUR_GUET), 2):
        for x in range(0, min(image.largeur, LARGEUR_GUET), 2):
            if _rose(image.pixel(x, y)):
                return True
    return False


def lire(image, raison=None):
    """(numéro, texte) si la bande est entière et juste, sinon None (raison[0] dit pourquoi, pour le diagnostic)."""
    def echec(texte):
        if raison is not None:
            raison[:] = [texte]
        return None

    g = trouver(image)
    if g is None:
        return echec("pas de balise")
    etalons = [g.carre(3 + k) for k in range(4)]
    if None in etalons:
        return echec("étalonnage hors de l'image")
    for canal in range(3):
        valeurs = [e[canal] for e in etalons]
        if any(valeurs[k + 1] - valeurs[k] < 30 for k in range(3)):
            return echec(f"étalonnage illisible {etalons}")

    def niveau(valeur, canal):
        return min(range(4), key=lambda k: abs(etalons[k][canal] - valeur))

    def demi(k):
        c = g.carre(ENTETE + k)
        if c is None or niveau(c[2], 2) != k % 4:
            raise ValueError(f"carré {ENTETE + k} décalé {c}")
        return niveau(c[0], 0) * 4 + niveau(c[1], 1)

    def octet(j):
        return demi(2 * j) * 16 + demi(2 * j + 1)

    try:
        numero = octet(0)
        longueur = octet(1) * 256 + octet(2)
        if longueur > 300:
            return echec(f"longueur {longueur}")
        texte = bytes(octet(3 + i) for i in range(longueur))
        somme = octet(3 + longueur)
    except ValueError as e:
        return echec(f"{e} (pas {g.pas:.2f}, coin {g.x0},{g.y0})")
    if (numero + longueur // 256 + longueur % 256 + sum(texte)) % 256 != somme:
        return echec(f"somme fausse (pas {g.pas:.2f})")
    return numero, texte.decode("utf-8", "replace")
