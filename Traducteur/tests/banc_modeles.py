"""Compare des modèles sur de vrais messages de joueurs.

    python -I tests\\banc_modeles.py qwen3.5:4b gemma4:e4b
"""
import os
import sys
import time

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(ICI))

from trad.ia import Ollama, Traducteur  # noqa: E402
from trad.lexique import Lexique  # noqa: E402

RECUS = [
    # vus dans le chat de Forever
    "LF 1 tank 1 heal for WC",
    "LFM ANACONDA FARM 1st boss WC, 10 slot bag + deviate hides ( 2x 10 slot possiblity, neck also)",
    "tank heal dps for cavern",
    "LF tank/healer for WC quest run",
    "ffs faster",
    "fr",
    "but its elite mob too no ?",
    "nah in front to",
    "im literally falling asleep as we play",
    "so i wont have to to this",
    "LF [Pellejo descarriado] FARM",
    # inventés, dans le même esprit
    "need 1 more for SM GY then lib, pst",
    "can sum1 summ me plz im at the stone",
    "inc 2 adds, im oom",
    "who's ML? hr on the bracers?",
    "wts [Cape en canevas] 5s cod",
    "alguien para mara? falta tanque",
    "suche gruppe für todesminen, bin heiler",
    "brb",
    "ty all gg",
    "nvm found one",
    "u comin to ony tonight?",
    "salut tu veux grouper ?",
]
ENVOIS = [
    ("je cherche un groupe pour les cavernes des lamentations, je suis heal", "en"),
    ("attendez moi j'arrive dans 2 minutes, je finis ma quête", "en"),
    ("quelqu'un peut m'invoquer ? je suis à la pierre", "en"),
    ("merci pour le groupe, bonne nuit", "es"),
    ("c'est où l'entrée de Maraudon ?", "de"),
]


def main(modeles):
    lex = Lexique(os.path.join(os.path.dirname(ICI), "lexique.txt"))
    ol = Ollama()
    ol.demarrer()
    for modele in modeles:
        print(f"\n===== {modele} =====")
        t = Traducteur(ol, lex, modele)
        debut = time.time()
        t.prechauffer()
        print(f"(chargement : {time.time() - debut:.1f} s)")
        total = 0.0
        for msg in RECUS:
            r = t.traduire_recu(msg)
            total += r.duree
            marque = "" if r.a_afficher() else "  [masqué]"
            print(f"  {msg}\n    -> [{r.langue}] {r.francais}  ({r.source}, {r.duree:.2f}s){marque}")
        print(f"  temps IA total : {total:.1f} s")
        for msg, lg in ENVOIS:
            debut = time.time()
            sortie = t.traduire_envoi(msg, lg)
            print(f"  FR> {msg}\n    -> ({lg}) {sortie}  ({time.time() - debut:.2f}s)")
        ol._requete("/api/generate", {"model": modele, "keep_alive": 0})  # libère la carte graphique


if __name__ == "__main__":
    main(sys.argv[1:] or ["qwen3.5:4b"])
