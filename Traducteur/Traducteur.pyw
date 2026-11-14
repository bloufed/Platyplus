"""Traducteur Platyplus : double-clic pour lancer (sans fenêtre noire).

Traduit le chat de WoW avec une petite IA qui tourne sur ton PC (Ollama), et t'aide à répondre
dans la langue des autres joueurs (Ctrl+Entrée dans le jeu). Voir LISEZMOI.txt.

Options pour les tests :  --journal FICHIER   lire un autre journal que Logs\\WoWChatLog.txt
                          --visible           ne jamais se cacher (même hors du jeu)
"""
import os
import sys
import time
import traceback

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ICI)


def main():
    from trad import systeme
    systeme.rendre_net()
    if not systeme.une_seule_instance():
        import tkinter.messagebox as mb
        mb.showinfo("Traducteur Platyplus", "Le traducteur est déjà lancé : il s'affiche quand tu es dans le jeu.")
        return
    from trad.appli import Appli
    appli = Appli(ICI)
    args = sys.argv[1:]
    if "--journal" in args:
        appli.chemin_journal = os.path.abspath(args[args.index("--journal") + 1])
    if "--visible" in args:
        appli.toujours_visible = True  # pour les tests : rien n'est écrit dans reglages.json
    appli.lancer()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        texte = traceback.format_exc()
        with open(os.path.join(ICI, "erreurs.log"), "a", encoding="utf-8") as f:
            f.write(time.strftime("\n--- %Y-%m-%d %H:%M:%S ---\n") + texte)
        try:
            import tkinter.messagebox as mb
            mb.showerror("Traducteur Platyplus", "Le traducteur s'est arrêté sur une erreur.\n"
                         "Détails dans Traducteur\\erreurs.log\n\n" + texte[-600:])
        except Exception:
            pass
