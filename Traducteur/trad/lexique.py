"""Lexique de joueur (lexique.txt) : abréviations, donjons, zones.

Deux usages :
- donner à l'IA le sens des termes trouvés dans un message (« WC » = Cavernes des lamentations) ;
- traduire tout de suite, sans l'IA, un message qui tient entièrement dans le lexique (« ty », « brb »).
"""
import re
import unicodedata

# Messages qu'on ne traduit pas du tout : tout le monde les comprend.
UNIVERSELS = {
    "gg", "lol", "xd", "ok", "okay", "haha", "hahaha", "hehe", "^^", ":)", ":d", ":(", ";)", ":p", "+1",
    "o/", "\\o", "<3", "x)", "xdd", "mdr", "ggwp", "gg wp",
}

MOT = re.compile(r"[\w'’+/\\^<>:;()]+", re.UNICODE)

SECTION_ENVOI = "pour mes messages"

# « 5s », « 2g », « 30 c » : sommes d'argent
ARGENT = re.compile(r"(?<![\w])(\d+(?:[.,]\d+)?)\s?([gscGSC])(?![\w])")
PIECES = {"g": "pièces d'or", "s": "pièces d'argent", "c": "pièces de cuivre"}


def sans_accents(texte):
    return "".join(c for c in unicodedata.normalize("NFD", texte) if unicodedata.category(c) != "Mn")


def _motif(ecriture):
    """Regex d'une écriture : mots entiers, espaces souples."""
    morceaux = [re.escape(m) for m in ecriture.split()]
    return r"(?<![\w'])" + r"\s+".join(morceaux) + r"(?![\w'])"


class Entree:
    def __init__(self, ecritures, sens, section):
        self.ecritures = ecritures          # telles qu'écrites dans le fichier (sans « ! »)
        self.sens = sens
        self.section = section
        motifs = []
        for brut in ecritures:
            if brut.startswith("!"):
                motifs.append((re.compile(_motif(brut[1:])), brut[1:]))
            else:
                motifs.append((re.compile(_motif(brut), re.IGNORECASE), brut))
        self.motifs = motifs
        self.ecritures = [e.lstrip("!") for e in ecritures]

    def court(self):
        """Le sens sans les précisions : « invite (dans le groupe) » -> « invite »."""
        s = self.sens.split(" ; ")[0]
        s = re.sub(r"\s*\([^)]*\)", "", s).strip()
        s = s.split(" / ")[0].strip()
        return s

    def nom_anglais(self):
        """Pour un lieu : le nom anglais complet et l'abréviation (« Wailing Caverns », « WC »)."""
        sigle = next((e for e in self.ecritures if e.isupper() and len(e) <= 6), None)
        longs = [e for e in self.ecritures if not e.isupper()]
        nom = max(longs, key=len).title() if longs else None
        return nom, sigle

    def nom_francais(self):
        nom = re.split(r"\s*[(;]", self.sens)[0].strip()
        return nom


class Lexique:
    def __init__(self, chemin=None, texte=None):
        self.entrees = []
        if texte is None:
            with open(chemin, encoding="utf-8") as f:
                texte = f.read()
        section = ""
        for ligne in texte.splitlines():
            ligne = ligne.strip()
            if not ligne:
                continue
            if ligne.startswith("#"):
                m = re.match(r"#\s*---\s*(.+?)\s*---", ligne)
                if m:
                    section = m.group(1).lower()
                continue
            if "=" not in ligne:
                continue
            gauche, sens = ligne.split("=", 1)
            ecritures = [e.strip() for e in gauche.split(" / ") if e.strip()]
            sens = sens.strip()
            if ecritures and sens:
                self.entrees.append(Entree(ecritures, sens, section))
        # pour retrouver une entrée à partir d'une écriture exacte (minuscules)
        self.par_ecriture = {}
        for e in self.entrees:
            for ecr in e.ecritures:
                self.par_ecriture.setdefault(ecr.lower(), e)

    # ------------------------------------------------------------------
    def termes(self, texte, envoi=False):
        """[(terme tel qu'écrit dans le message, entrée)] pour chaque entrée trouvée, sans doublon.

        envoi=False : messages reçus (toutes les sections sauf « pour mes messages ») ;
        envoi=True : un message que j'écris (seulement « pour mes messages »)."""
        trouves = []
        vues = set()
        for e in self.entrees:
            if (e.section == SECTION_ENVOI) != envoi:
                continue
            for motif, _ in e.motifs:
                m = motif.search(texte)
                if m:
                    if id(e) not in vues:
                        vues.add(id(e))
                        trouves.append((m.group(0), e))
                    break
        return trouves

    def indices(self, texte):
        """Texte d'indices pour l'IA : « WC = Cavernes des lamentations (donjon) | ty = merci »."""
        morceaux = [f"{terme} = {e.sens}" for terme, e in self.termes(texte)]
        for m in ARGENT.finditer(texte):
            morceaux.append(f"{m.group(0)} = {m.group(1)} {PIECES[m.group(2).lower()]}")
        return " | ".join(morceaux)

    def annoter(self, texte, envoi=False):
        """Le message avec le sens collé derrière chaque terme connu :
        « LF heal for WC » -> « LF (= cherche (un groupe)) heal (= soigneur) for WC (= Cavernes des lamentations (donjon)) ».
        Une petite IA suit bien mieux une explication placée juste à côté du mot qu'une liste à part."""
        reperes = []  # (début, fin, sens)
        for e in self.entrees:
            if (e.section == SECTION_ENVOI) != envoi:
                continue
            for motif, _ in e.motifs:
                for m in motif.finditer(texte):
                    sens = e.sens if len(e.sens) <= 100 else e.sens.split(" ; ")[0]
                    reperes.append((m.start(), m.end(), sens))
        if envoi:
            for e in self.entrees:
                if e.section not in ("donjons", "villes et zones"):
                    continue
                fr = re.sub(r"^(la |le |les |l')", "", e.nom_francais(), flags=re.IGNORECASE)
                if len(fr) < 4:
                    continue
                nom, sigle = e.nom_anglais()
                anglais = f"{nom} ({sigle})" if nom and sigle else (nom or sigle)
                if not anglais:
                    continue
                motif = re.compile(_motif(sans_accents(fr)), re.IGNORECASE)
                for m in motif.finditer(sans_accents(texte)):  # même longueur : positions valables
                    reperes.append((m.start(), m.end(), anglais))
        else:
            for m in ARGENT.finditer(texte):
                reperes.append((m.start(), m.end(), f"{m.group(1)} {PIECES[m.group(2).lower()]}"))
        # les plus longs d'abord, sans chevauchement
        reperes.sort(key=lambda r: (r[0], -(r[1] - r[0])))
        gardes, fin = [], -1
        for debut, f, sens in reperes:
            if debut >= fin:
                gardes.append((debut, f, sens))
                fin = f
        sortie, pos = [], 0
        for debut, f, sens in gardes:
            sortie.append(texte[pos:f])
            sortie.append(f" (= {sens})")
            pos = f
        sortie.append(texte[pos:])
        return "".join(sortie)

    def indices_envoi(self, texte):
        """Indices pour un message que j'écris en français : lieux en anglais, mots de joueur."""
        morceaux = [self.lieux_francais(texte)]
        morceaux += [f"{terme} = {e.sens}" for terme, e in self.termes(texte, envoi=True)]
        return " | ".join(m for m in morceaux if m)

    def lieux_francais(self, texte):
        """Pour un message à envoyer : les noms français de lieux trouvés, avec leur nom anglais."""
        plat = sans_accents(texte).lower()
        sortie = []
        for e in self.entrees:
            if e.section not in ("donjons", "villes et zones"):
                continue
            fr = e.nom_francais()
            fr_sans_article = re.sub(r"^(la |le |les |l')", "", fr, flags=re.IGNORECASE)
            cle = sans_accents(fr_sans_article).lower()
            if len(cle) >= 4 and cle in plat:
                nom, sigle = e.nom_anglais()
                if nom or sigle:
                    anglais = nom or sigle
                    if nom and sigle:
                        anglais = f"{nom} ({sigle})"
                    sortie.append(f"{fr} = {anglais}")
        return " | ".join(sortie)

    # ------------------------------------------------------------------
    def traduction_directe(self, texte):
        """Traduction sans l'IA si chaque mot du message est dans le lexique (4 mots max), sinon None."""
        mots = MOT.findall(texte.lower())
        if not mots or len(mots) > 4:
            return None
        sens = []
        for mot in mots:
            if mot in UNIVERSELS or mot.isdigit():
                continue
            e = self.par_ecriture.get(mot)
            if e is None or e.section not in ("abréviations de chat",):
                return None
            court = e.court()
            if court not in sens:
                sens.append(court)
        if not sens:
            return None
        phrase = ", ".join(sens)
        return phrase[0].upper() + phrase[1:]


def est_trivial(texte):
    """Rien à traduire : vide, chiffres, smileys, « gg », « lol »..."""
    t = texte.strip().lower()
    if not t:
        return True
    if t in UNIVERSELS:
        return True
    mots = MOT.findall(t)
    if not mots:
        return True  # que de la ponctuation
    return all(m in UNIVERSELS or m.isdigit() or re.fullmatch(r"[\W_]+", m) for m in mots)
