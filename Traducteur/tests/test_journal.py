"""Tests sans le jeu ni l'IA :  python -I tests\\test_journal.py"""
import os
import sys
import tempfile

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(ICI))

from trad.journal import Suivi, analyser, analyser_copie, nettoyer  # noqa: E402
from trad.lexique import Lexique, est_trivial  # noqa: E402
from trad.ia import langue_probable  # noqa: E402

echecs = []


def verifier(nom, obtenu, attendu):
    if obtenu != attendu:
        echecs.append(f"{nom}\n   obtenu  : {obtenu!r}\n   attendu : {attendu!r}")


def ligne(brut):
    l = analyser(brut)
    return None if l is None else (l.categorie, l.canal, l.auteur, l.texte, l.envoye)


# --- lignes réelles du chat de Forever (texte reçu par AddMessage, sauvé par ChatPlus) ---
verifier("groupe", ligne("01:27 |Hchannel:PARTY|h[Groupe]|h |Hplayer:Ry Ne:1708:PARTY:|h[|cffc69b6dRy Ne|r]|h : I just want to sleep"),
         ("groupe", "Groupe", "Ry Ne", "I just want to sleep", False))
verifier("chef de groupe", ligne("01:27 |Hchannel:PARTY|h[Chef de groupe]|h |Hplayer:Dizard Vanqueef:1710:PARTY:|h[|cfffff468Dizard Vanqueef|r]|h : xD"),
         ("groupe", "Chef de groupe", "Dizard Vanqueef", "xD", False))
verifier("général", ligne("01:29 |Hchannel:channel:1|h[1. Général - Cavernes des lamentations]|h |Hplayer:Horion Delait:1769:CHANNEL:1|h[|cff0070ddHorion Delait|r]|h : LF 1 tank 1 heal for WC"),
         ("general", "1. Général", "Horion Delait", "LF 1 tank 1 heal for WC", False))
verifier("lien d'objet", ligne("01:36 |Hchannel:channel:1|h[1. Général - Cavernes des lamentations]|h |Hplayer:Galipizza Sotomonte:1880:CHANNEL:1|h[|cfff48cbaGalipizza Sotomonte|r]|h : LF |cnIQ1:|Hitem:6443::::::::17:1486:::::::::|h[Pellejo descarriado]|h|r FARM"),
         ("general", "1. Général", "Galipizza Sotomonte", "LF [Pellejo descarriado] FARM", False))
verifier("questie", ligne("01:34 |Hchannel:PARTY|h[Groupe]|h |Hplayer:Il Basow:1828:PARTY:|h[|cffc69b6dIl Basow|r]|h : |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t Questie : Ramassé |cnIQ1:|Hitem:10441::::::::21:1491:::::::::|h[Eclat luminescent]|h|r"),
         ("groupe", "Groupe", "Il Basow", "Questie : Ramassé [Eclat luminescent]", False))

# --- formats probables du fichier journal (pas encore vus en vrai) ---
verifier("journal groupe", ligne("11/6 01:27:12.345  [Groupe] Ry Ne : I just want to sleep"),
         ("groupe", "Groupe", "Ry Ne", "I just want to sleep", False))
verifier("journal commerce", ligne("11/6/2026 21:03:44.120  [2. Commerce - Hurlevent] Bob-Argent: WTS [Cape] 5s"),
         ("commerce", "2. Commerce", "Bob", "WTS [Cape] 5s", False))
verifier("journal chuchot", ligne("11/6 21:03:44.120  Seventh Zero chuchote : can u inv me"),
         ("chuchot", "Chuchot.", "Seventh Zero", "can u inv me", False))
verifier("journal chuchot crochets", ligne("11/6 21:03:44.120  [Seventh Zero] chuchote : can u inv me"),
         ("chuchot", "Chuchot.", "Seventh Zero", "can u inv me", False))
verifier("whispers", ligne("11/6 21:03:44.120  Seventh Zero whispers: can u inv me"),
         ("chuchot", "Chuchot.", "Seventh Zero", "can u inv me", False))
verifier("envoyé", ligne("11/6 21:03:44.120  À Seventh Zero : sure"),
         ("chuchot", "Chuchot.", "Seventh Zero", "sure", True))
verifier("dire", ligne("11/6 21:03:44.120  Bob dit : hello there"), ("dire", "Dire", "Bob", "hello there", False))
verifier("guilde", ligne("21:03 [Guilde] Bob : anyone up for SM?"), ("guilde", "Guilde", "Bob", "anyone up for SM?", False))
verifier("absent", ligne("21:03 [Guilde] <Absent>Bob : brb"), ("guilde", "Guilde", "Bob", "brb", False))

# --- lignes à ignorer ---
for brut in ("Vous avez obtenu : 64 pièces d'argent", "Félicitations, vous avez atteint le |cffFF4E00|Hlevelup:19:LEVEL_UP_TYPE_CHARACTER|h[niveau 19]|h|r !",
             "Votre Force augmente de 1.", "11/6 01:27:12.345  Ry Ne a rejoint le groupe.", ""):
    verifier(f"ignorer {brut[:30]!r}", ligne(brut), None)

verifier("nettoyer", nettoyer("|cffffdd001|r for |cffffdd0088|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t|r"), "1 for 88")

# --- lexique et français ---
lex = Lexique(os.path.join(os.path.dirname(ICI), "lexique.txt"))
verifier("if n'est pas Forgefer", "Forgefer" in lex.indices("what if we wipe"), False)
verifier("IF est Forgefer", "Forgefer" in lex.indices("meet me in IF"), True)
verifier("WC", "Cavernes des lamentations" in lex.indices("lf heal wc"), True)
verifier("argent", "5 pièces d'argent" in lex.indices("wts 5s"), True)
verifier("direct ty", lex.traduction_directe("ty"), "Merci")
verifier("direct brb", lex.traduction_directe("brb"), "Je reviens tout de suite")
verifier("pas direct", lex.traduction_directe("inv me pls I'm a mage"), None)
verifier("lieux français", lex.lieux_francais("on va aux cavernes des lamentations ?"), "Cavernes des lamentations = Wailing Caverns (WC)")
verifier("trivial gg", est_trivial("gg"), True)
verifier("trivial xD", est_trivial("xD"), True)
verifier("pas trivial", est_trivial("gg wp all"), False)
verifier("français", langue_probable("salut tu veux grouper ?"), "fr")
verifier("français 2", langue_probable("je suis pas là, désolé"), "fr")
verifier("anglais", langue_probable("I just want to sleep"), None)
verifier("espagnol", langue_probable("alguien para mara? falta tanque"), None)

# --- suivi du fichier ---
with tempfile.TemporaryDirectory() as d:
    f = os.path.join(d, "WoWChatLog.txt")
    with open(f, "w", encoding="utf-8") as h:
        h.write("ancienne ligne\n")
    s = Suivi(f)
    verifier("début ignoré", s.lire(), [])
    with open(f, "a", encoding="utf-8") as h:
        h.write("ligne 1\nligne 2\nmorc")
    verifier("nouvelles lignes", s.lire(), ["ligne 1", "ligne 2"])
    with open(f, "a", encoding="utf-8") as h:
        h.write("eau\n")
    verifier("ligne coupée", s.lire(), ["morceau"])
    with open(f, "w", encoding="utf-8") as h:
        h.write("après vidage\n")
    verifier("fichier vidé", s.lire(), ["après vidage"])

# --- copie faite dans le jeu après un clic sur [FR] (« Nom › message », écrit par Platyplus) ---
def copie(brut):
    l = analyser_copie(brut)
    return None if l is None else (l.categorie, l.canal, l.auteur, l.texte)


verifier("copie [FR]", copie("Ima Dwaté › ARE YOU"), ("clic", "FR", "Ima Dwaté", "ARE YOU"))
verifier("copie [FR] avec lien", copie("Bob › wts |cffffffff|Hitem:1|h[Linen]|h|r 1s"), ("clic", "FR", "Bob", "wts [Linen] 1s"))
verifier("copie [FR] auteur inconnu", copie("? › hola"), ("clic", "FR", "?", "hola"))
verifier("autre copie : lien web", copie("https://wowhead.com"), None)
verifier("autre copie : tout le chat", copie("Bob › salut\nAnna › hi"), None)
verifier("autre copie : vide", copie("Bob › "), None)

if echecs:
    print(f"{len(echecs)} ÉCHEC(S) :")
    for e in echecs:
        print(" -", e)
    sys.exit(1)
print("tout est bon")
