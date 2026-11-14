"""Écrit de faux messages dans un journal de chat, pour voir le traducteur sans le jeu.

    python -I tests\\faux_chat.py C:\\chemin\\faux_journal.txt [pause_en_secondes]
puis, dans une autre fenêtre :
    pythonw Traducteur.pyw --journal C:\\chemin\\faux_journal.txt --visible
"""
import sys
import time

MESSAGES = [
    "[Groupe] Seventh Zero : im literally falling asleep as we play",
    "[1. Général - Cavernes des lamentations] Horion Delait : LF 1 tank 1 heal for WC",
    "[Groupe] Il Basow : salut, ça va ?",
    "Ry Ne chuchote : can sum1 summ me plz im at the stone",
    "[Guilde] Tasty Rouqui : need 1 more for SM GY then lib, pst",
    "[1. Général - Cavernes des lamentations] Galipizza Sotomonte : alguien para mara? falta tanque",
    "[Groupe] Seventh Zero : gg",
    "[2. Commerce - Hurlevent] Bob : wts [Cape en canevas] 5s cod",
    "[Groupe] Il Basow : |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t Questie : Ramassé [Eclat luminescent]",
    "[Groupe] Seventh Zero : brb",
]


def main(chemin, pause=2.5):
    with open(chemin, "a", encoding="utf-8"):
        pass
    for msg in MESSAGES:
        time.sleep(pause)
        horodatage = time.strftime("%m/%d %H:%M:%S.000").lstrip("0")
        with open(chemin, "a", encoding="utf-8") as f:
            f.write(f"{horodatage}  {msg}\n")
        print(msg)


if __name__ == "__main__":
    main(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 2.5)
