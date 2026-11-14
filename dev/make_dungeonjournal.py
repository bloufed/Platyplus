"""Intègre DungeonJournal (l'addon ForeverDungeonJournal, par Exehn) dans Platyplus.

Le script recopie l'addon tel quel dans Platyplus/DungeonJournal et ne touche qu'à ce qu'il faut pour qu'il vive
DANS Platyplus :

  * espace de noms : chaque fichier reçoit celui de Platyplus (« ... ») ; sa première ligne de code devient
    « ...; FDJ = FDJ.Dungeon; if FDJ.PpStandby then return end » (sur la même ligne, pour garder les numéros de
    ligne des messages d'erreur). ns.Dungeon est préparé par DungeonJournalGlue.lua (écrit à la main, chargé juste
    avant) ; tout s'arrête si l'addon DungeonJournal séparé est chargé (PpStandby) ;
  * noms globaux : ForeverDungeonJournal* devient PlatyplusDungeon* (cadres, réglages sauvegardés
    PlatyplusDungeonDB / PlatyplusDungeonCharacterDB déclarés dans Platyplus.toc, raccourcis) : rien ne se mélange
    avec l'addon séparé ;
  * chemins des images : Interface\\AddOns\\Platyplus\\DungeonJournal\\Media\\... ;
  * style Platyplus : chaque couleur posée par le journal (SetBackdropColor, SetBackdropBorderColor,
    SetColorTexture, SetTextColor), chaque fond (SetBackdrop), chaque surbrillance (SetHighlightTexture) et
    chaque bouton ou barre de défilement de Blizzard (UIPanelButtonTemplate, UIPanelCloseButton,
    UIPanelScrollFrameTemplate) passe d'abord par FDJ.PpC / PpBackdrop / PpHighlight / PpWidget
    (DungeonJournalGlue.lua). Style éteint : ils rendent ce qu'on leur donne, le journal garde son look ;
  * quelques points d'accroche (PATCHES) pour la liste des donjons de Platyplus et l'accueil ;
  * Systems/VersionCheck.lua n'est pas importé (il annonce sa version au groupe et à la guilde) ;
  * raccourcis : bloc DungeonJournal du Bindings.xml de Platyplus ; bloc « # >>> DungeonJournal » de
    Platyplus.toc, réécrit dans l'ordre du .toc de l'addon.

Usage :
  python -I dev\\make_dungeonjournal.py <dossier ForeverDungeonJournal> <dossier Platyplus>

Le dossier Platyplus/DungeonJournal est entièrement remplacé à chaque import : n'y modifiez rien à la main.
"""
import re
import shutil
import sys
import time
from pathlib import Path

MARKER = "PLATYPLUS.txt"
TOC_BEGIN = "# >>> DungeonJournal"
TOC_END = "# <<< DungeonJournal"
GLUE = "DungeonJournalGlue.lua"
BIND_BEGIN = "<!-- >>> DungeonJournal"
BIND_END = "<!-- <<< DungeonJournal -->"
SV_NAMES = ("PlatyplusDungeonDB", "PlatyplusDungeonCharacterDB")

# fichiers de l'addon laissés de côté (chemins relatifs, avec des /)
SKIP = {"ForeverDungeonJournal.toc", "Bindings.xml", "Systems/VersionCheck.lua"}

# (fichier, ancien texte, nouveau texte) : appliqués au texte ORIGINAL, chacun doit s'y trouver exactement une fois.
# Les ajouts sont sur la même ligne : les numéros de ligne restent ceux de l'addon.
PATCHES = [
    # la version de l'addon : celle importée (le nom d'addon, devenu PlatyplusDungeon, n'existe pas pour le jeu)
    ("Core/Bootstrap.lua",
     "FDJ.ADDON_NAME = ADDON_NAME",
     'FDJ.ADDON_NAME = ADDON_NAME FDJ.PpVersion = "{version}"'),
    ("Core/Journal.lua",
     'addonVersion = C_AddOns.GetAddOnMetadata("ForeverDungeonJournal", "Version")',
     'addonVersion = "{version}"'),
    ("Core/Journal.lua",
     'addonVersion = GetAddOnMetadata("ForeverDungeonJournal", "Version")',
     'addonVersion = "{version}"'),
    ("Systems/OptionsPanel.lua",
     'pcall(getter, "ForeverDungeonJournal", "Version")',
     'true, "{version}"'),
    ("Systems/SettingsPanel.lua",
     'pcall(getter, "ForeverDungeonJournal", "Version")',
     'true, "{version}"'),
    # une action bloquée par le jeu est maintenant attribuée à Platyplus
    ("Systems/LFGButton.lua",
     'elseif addon == "ForeverDungeonJournal" then',
     'elseif addon == "Platyplus" then'),
    # pages du journal accessibles à Platyplus (liste des donjons à gauche) ; chaque changement de page le prévient
    ("Core/Journal.lua",
     "SelectDungeon = function(name)",
     "FDJ.PpSelectDungeon = function(...) return SelectDungeon(...) end SelectDungeon = function(name)"),
    ("Core/Journal.lua",
     "ShowHomePage = function()",
     "FDJ.PpShowHome = function(...) return ShowHomePage(...) end ShowHomePage = function() FDJ.PpViewChanged()"),
    ("Core/Journal.lua",
     "ShowDungeonPage = function()",
     "ShowDungeonPage = function() FDJ.PpViewChanged()"),
    ("Core/Journal.lua",
     "RefreshAll = function()",
     "RefreshAll = function() FDJ.PpViewChanged()"),
    ("Core/Journal.lua",
     "SetMode = function(mode)",
     "FDJ.PpSetMode = function(...) return SetMode(...) end SetMode = function(mode) FDJ.PpViewChanged()"),
    # les règles du journal pour compter les quêtes d'un donjon (faction, classe, métier) : la liste de gauche
    # compte comme les cartes de l'accueil
    ("Core/Journal.lua",
     "local function QuestMatchesFaction(quest, faction)",
     "local QuestMatchesFaction; FDJ.PpQuestMatchesFaction = function(...) return QuestMatchesFaction(...) end "
     "QuestMatchesFaction = function(quest, faction)"),
    # fin du rafraîchissement de l'accueil : niveau conseillé et progression des quêtes sur les cartes
    ("Core/Journal.lua",
     "    if FDJ.UpdateRPGHeader then pcall(FDJ.UpdateRPGHeader, frame) end",
     "    if FDJ.UpdateRPGHeader then pcall(FDJ.UpdateRPGHeader, frame) end "
     "FDJ.PpAfterHome(homeDungeonCards, shownDungeons)"),
    # langues : le menu du journal ne propose que celles que Platyplus garde en mémoire (DungeonJournalGlue.lua
    # retire les autres au chargement : la langue du jeu, l'anglais, et celle choisie dans le journal)
    ("Core/Journal.lua",
     "local LANGUAGE_CHOICES = {",
     "local LANGUAGE_CHOICES = FDJ.PpLanguages {"),
    # la fenêtre du journal vient d'être construite (connexion) : le style retouche la page de quête une fois
    ("Core/Journal.lua",
     "        CreateMainFrame()",
     "        CreateMainFrame() FDJ.PpAfterBuild()"),
    # liste et page des quêtes : la quête sélectionnée, et un passage du style après chaque dessin (le corps
    # d'origine devient FDJ.PpQuestListBody / PpQuestDetailBody, appelé par la nouvelle fonction)
    ("Core/Journal.lua",
     "SelectQuest = function(index, allowHidden)",
     "FDJ.PpSelectedQuest = function() return selectedQuest end SelectQuest = function(index, allowHidden)"),
    ("Core/Journal.lua",
     "RefreshQuestList = function()",
     'RefreshQuestList = function(...) FDJ.PpQuestListBody(...) FDJ.PpAfterQuests("list") end '
     "FDJ.PpQuestListBody = function()"),
    ("Core/Journal.lua",
     "RefreshQuestDetail = function()",
     'RefreshQuestDetail = function(...) FDJ.PpQuestDetailBody(...) FDJ.PpAfterQuests("detail") end '
     "FDJ.PpQuestDetailBody = function()"),
    # couleurs écrites dans le texte (|cff...) : l'objectif rempli, brun pour le parchemin, et le nom du donjon
    # sous un boss ; le style donne les siennes (FDJ.PpInk rend nil sans style)
    ("Systems/QuestText.lua",
     'finished and ("|cff6e5c40" .. text .. "|r") or text',
     'finished and ((FDJ.PpInk("done") or "|cff6e5c40") .. text .. "|r") or text'),
    ("Core/Journal.lua",
     '"\\n|cffb8ab94" .. DungeonName(boss.fdjDungeon)',
     '"\\n" .. (FDJ.PpInk("muted") or "|cffb8ab94") .. DungeonName(boss.fdjDungeon)'),
    # style Platyplus : pas de parchemin sous les pages (fond sombre, texte clair)
    ("Core/Journal.lua",
     "local function AddClassicParchment(frameObj, alpha, r, g, b)",
     "local function AddClassicParchment(frameObj, alpha, r, g, b) if FDJ.PpNoParchment() then "
     "local t = frameObj:CreateTexture(nil, \"BACKGROUND\", nil, -2) t:Hide() return t end"),
    ("Core/Journal.lua",
     'frame.questParchment:SetTexture("Interface\\\\QuestFrame\\\\QuestBG")',
     'frame.questParchment:SetTexture("Interface\\\\QuestFrame\\\\QuestBG") '
     'if FDJ.PpNoParchment() then frame.questParchment:Hide() end'),
]

# chemins d'images écrits en dur (texte source Lua : antislashs doublés)
PATH_OLD = "Interface\\\\AddOns\\\\ForeverDungeonJournal\\\\"
PATH_NEW = "Interface\\\\AddOns\\\\Platyplus\\\\DungeonJournal\\\\"

RENAMES = [("ForeverDungeonJournal", "PlatyplusDungeon"), ("FOREVERDUNGEONJOURNAL", "PLATYPLUSDUNGEON")]

# en-têtes : le journal reçoit ns.Dungeon (et s'arrête en veille)
HEADER_A = re.compile(r"^local (\w+), FDJ = \.\.\.[ \t]*(?=\r?$)", re.M)
HEADER_A_NEW = r"local \1, FDJ = ...; FDJ = FDJ.Dungeon; if FDJ.PpStandby then return end"
HEADER_B = re.compile(r"^local FDJ = _G\.ForeverDungeonJournal_NS[ \t]*(?=\r?$)", re.M)
HEADER_B_NEW = "local FDJ = select(2, ...).Dungeon; if FDJ.PpStandby then return end"

# couleurs : X:SetTextColor(a, b, c) -> X:SetTextColor(FDJ.PpC("text", a, b, c)) ; deux niveaux de parenthèses
# dans les arguments (unpack(theme.text), QualityColor(item[4]), (a + b) / 2)
ARGS = r"((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)"
COLOR_KINDS = {"SetBackdropColor": "bg", "SetBackdropBorderColor": "edge", "SetColorTexture": "tex", "SetTextColor": "text"}
COLOR_CALL = re.compile(r":(" + "|".join(COLOR_KINDS) + r")\(" + ARGS + r"\)")
BACKDROP_CALL = re.compile(r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*):SetBackdrop\(")
# surbrillance au survol (lueur dorée de Blizzard) : X:SetHighlightTexture(...) -> FDJ.PpHighlight(X, ...)
HIGHLIGHT_CALL = re.compile(r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*):SetHighlightTexture\(")
# boutons et barres de défilement de Blizzard, repeints dès leur création :
# CreateFrame(..., "UIPanelButtonTemplate") -> FDJ.PpWidget("UIPanelButtonTemplate", CreateFrame(...))
WIDGET_TEMPLATES = ("UIPanelButtonTemplate", "UIPanelCloseButton", "UIPanelScrollFrameTemplate")
# (un niveau de parenthèses permis dans les arguments : CreateFrame("Button", nil, x:GetParent(), "..."))
WIDGET_CALL = re.compile(r"\bCreateFrame\(((?:[^()]|\([^()]*\))*?\"(" + "|".join(WIDGET_TEMPLATES) + r")\"\s*)\)")

BINDINGS_SKELETON = """\
<!-- Platyplus : raccourcis des parties intégrées (Touches > AddOns). Chaque bloc est GÉNÉRÉ par son script
     (dev/make_dungeonjournal.py) : ne pas modifier à la main. -->
<Bindings>
</Bindings>
"""

MARKER_TEXT = """\
Ce dossier est DungeonJournal {version} (l'addon ForeverDungeonJournal, par Exehn),
importé dans Platyplus par dev/make_dungeonjournal.py. Il est entièrement remplacé à chaque import :
n'y modifiez rien à la main, changez plutôt le script, DungeonJournalGlue.lua, DungeonJournalSkin.lua
ou DungeonJournalPlus.lua.

Code et données : Exehn. L'addon n'est accompagné d'aucune licence : il est intégré ici pour un usage
personnel. Pour redistribuer Platyplus avec ce dossier, demandez d'abord l'accord de son auteur.
Les images de Media/ viennent en grande partie de l'art de Blizzard Entertainment.
"""


def fail(msg):
    raise SystemExit("ERREUR : " + msg)


def read(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def toc_entries(toc_text):
    out = []
    for line in toc_text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        out.append(line)
    return out


def only_comments_before(text, pos):
    """Avant l'en-tête : rien que des commentaires et des lignes vides (aucun code ne tourne avant la veille)."""
    head = text[:pos]
    head = re.sub(r"--\[(=*)\[.*?\]\1\]", "", head, flags=re.S)
    for line in head.splitlines():
        line = line.strip()
        if line and not line.startswith("--"):
            return False
    return True


def patch_namespace(rel, text):
    a, b = list(HEADER_A.finditer(text)), list(HEADER_B.finditer(text))
    if len(a) + len(b) != 1:
        fail(f"{rel} : {len(a)} en-tête(s) « local X, FDJ = ... » et {len(b)} « local FDJ = _G... » (il en faut un)")
    m = (a or b)[0]
    if not only_comments_before(text, m.start()):
        fail(f"{rel} : du code avant l'en-tête de l'espace de noms (la veille ne l'arrêterait pas)")
    new = m.expand(HEADER_A_NEW) if a else HEADER_B_NEW
    return text[:m.start()] + new + text[m.end():], m.start()


def patch_colors(rel, text, header_pos):
    counts = {k: 0 for k in COLOR_KINDS}

    def color(m):
        method, args = m.group(1), m.group(2)
        if not args.strip():
            return m.group(0)
        counts[method] += 1
        return f':{method}(FDJ.PpC("{COLOR_KINDS[method]}", {args}))'

    text = COLOR_CALL.sub(color, text)
    backdrops = 0

    def backdrop(m):
        nonlocal backdrops
        backdrops += 1
        return f"FDJ.PpBackdrop({m.group(1)}, "

    text = BACKDROP_CALL.sub(backdrop, text)
    highlights = 0

    def highlight(m):
        nonlocal highlights
        highlights += 1
        return f"FDJ.PpHighlight({m.group(1)}, "

    text = HIGHLIGHT_CALL.sub(highlight, text)
    widgets = 0

    def widget(m):
        nonlocal widgets
        widgets += 1
        return f'FDJ.PpWidget("{m.group(2)}", CreateFrame({m.group(1)}))'

    text = WIDGET_CALL.sub(widget, text)
    counts["highlights"], counts["widgets"] = highlights, widgets
    for tpl in WIDGET_TEMPLATES:
        if len(re.findall(r'"' + tpl + r'"\s*\)', text)) != len(re.findall(r'FDJ\.PpWidget\("' + tpl + r'"', text)):
            fail(f"{rel} : un CreateFrame(..., \"{tpl}\") non relié à FDJ.PpWidget (revoir WIDGET_CALL)")
    if re.search(r":SetHighlightTexture\(", text):
        fail(f"{rel} : un appel :SetHighlightTexture( non relié à FDJ.PpHighlight")
    # tous les appels ont-ils été pris ? (des parenthèses trop imbriquées échapperaient à l'expression)
    for method in COLOR_KINDS:
        left = len(re.findall(r":" + method + r"\((?!FDJ\.PpC\()", text))
        if left:
            fail(f"{rel} : {left} appel(s) :{method}( non reliés à FDJ.PpC (revoir ARGS)")
    if re.search(r":SetBackdrop\(", text):
        fail(f"{rel} : un appel :SetBackdrop( non relié à FDJ.PpBackdrop")
    first = min([p for p in (text.find(h) for h in ("FDJ.PpC(", "FDJ.PpBackdrop(", "FDJ.PpHighlight(", "FDJ.PpWidget("))
                 if p >= 0], default=-1)
    if first >= 0 and first < header_pos:
        fail(f"{rel} : une couleur est posée avant l'en-tête (FDJ n'y existe pas encore)")
    return text, counts, backdrops


def replace_block(text, begin, end, lines, nl, where_before):
    """Remplace le bloc begin ... end (lignes entières) ; s'il manque, l'insère avant la ligne where_before."""
    b, e = text.find(begin), text.find(end)
    block = nl.join(lines) + nl
    if b >= 0 and e >= b:
        line_start = text.rfind(nl, 0, b) + len(nl) if text.rfind(nl, 0, b) >= 0 else 0
        line_end = text.find(nl, e)
        line_end = len(text) if line_end < 0 else line_end + len(nl)
        return text[:line_start] + block + text[line_end:]
    at = text.find(where_before)
    if at < 0:
        fail(f"impossible de placer le bloc {begin!r} (repère {where_before!r} absent)")
    return text[:at] + block + text[at:]


def main():
    if len(sys.argv) != 3:
        fail("usage : python -I dev\\make_dungeonjournal.py <dossier ForeverDungeonJournal> <dossier Platyplus>")
    src, plat = Path(sys.argv[1]), Path(sys.argv[2])
    if not (src / "ForeverDungeonJournal.toc").is_file():
        fail(f"{src} ne contient pas ForeverDungeonJournal.toc")
    if not (plat / "Platyplus.toc").is_file():
        fail(f"{plat} ne contient pas Platyplus.toc")

    toc = read(src / "ForeverDungeonJournal.toc")
    m = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    version = m.group(1) if m else "?"
    entries = [e for e in toc_entries(toc) if e.replace("\\", "/") not in SKIP]

    # 1. dossier Platyplus/DungeonJournal : remplacé en entier, seulement s'il vient de ce script
    dest = plat / "DungeonJournal"
    if dest.exists():
        # (un dossier vide est le reste d'une suppression que Windows n'avait pas finie : on le reprend)
        if not (dest / MARKER).is_file() and any(dest.iterdir()):
            fail(f"{dest} existe mais ne vient pas de ce script ({MARKER} absent) : je n'y touche pas")
        # Windows peut garder un fichier ou un dossier un instant (antivirus, indexation) : plusieurs essais
        for _ in range(25):
            shutil.rmtree(dest, ignore_errors=True)
            if not dest.exists() or not any(dest.iterdir()):
                break
            time.sleep(0.2)
        if dest.exists() and any(dest.iterdir()):
            fail(f"impossible de vider {dest} (un fichier est-il ouvert ?)")

    def ignore(d, names):
        rel = Path(d).relative_to(src).as_posix()
        return [n for n in names if (n if rel == "." else rel + "/" + n) in SKIP]

    # le repère d'abord : si la copie s'interrompt, le prochain import pourra quand même tout remplacer
    dest.mkdir(parents=True, exist_ok=True)
    write(dest / MARKER, MARKER_TEXT.format(version=version))
    shutil.copytree(src, dest, ignore=ignore, dirs_exist_ok=True)

    # 2. fichiers Lua : retouches, chemins, noms, couleurs, espace de noms
    patched = {}
    paths = files = 0
    color_total = {k: 0 for k in COLOR_KINDS}
    color_total["highlights"] = color_total["widgets"] = 0
    backdrop_total = 0
    for path in sorted(dest.rglob("*.lua")):
        rel = path.relative_to(dest).as_posix()
        if rel.startswith("Libs/"):
            continue   # bibliothèques tierces (LibDeflate) : copiées telles quelles, hors de l'espace de noms du journal
        text = read(path)
        for file, old, new in PATCHES:
            if file != rel:
                continue
            found = text.count(old)
            if found != 1:
                fail(f"{rel} : « {old} » trouvé {found} fois au lieu d'une (l'addon a changé : revoir PATCHES)")
            text = text.replace(old, new.replace("{version}", version))
            patched[file] = patched.get(file, 0) + 1
        count = text.count(PATH_OLD)
        if count:
            text = text.replace(PATH_OLD, PATH_NEW)
            paths += count
        for old, new in RENAMES:
            text = text.replace(old, new)
        if "ForeverDungeonJournal" in text or "Interface\\\\AddOns\\\\PlatyplusDungeon" in text:
            fail(f"{rel} : un nom ForeverDungeonJournal ou un chemin d'image a échappé au renommage")
        # (l'en-tête B cherche l'ancien nom : on le remet le temps de le trouver)
        text = text.replace("local FDJ = _G.PlatyplusDungeon_NS", "local FDJ = _G.ForeverDungeonJournal_NS")
        text, header_pos = patch_namespace(rel, text)
        text, counts, backdrops = patch_colors(rel, text, header_pos)
        for k, v in counts.items():
            color_total[k] += v
        backdrop_total += backdrops
        write(path, text)
        files += 1
    for file, old, _ in PATCHES:
        if not (dest / file).is_file():
            fail(f"{file} absent de l'addon (revoir PATCHES)")
    if sum(patched.values()) != len(PATCHES):
        fail("toutes les retouches n'ont pas été appliquées")
    if paths == 0:
        fail("aucun chemin Interface\\AddOns\\ForeverDungeonJournal trouvé : l'addon a changé, vérifier les images")
    for e in entries:
        if not (dest / e.replace("\\", "/")).is_file():
            fail(f"{e} est dans le .toc mais absent du dossier")

    # 3. raccourcis clavier : bloc DungeonJournal du Bindings.xml de Platyplus
    bind = read(src / "Bindings.xml")
    lines = re.findall(r"<Binding .*?</Binding>", bind, re.S)
    if not lines:
        fail("Bindings.xml de l'addon : aucune liaison trouvée")
    lines = ["\t" + re.sub(r"\s+", " ", l).replace("> ", ">").replace(" <", "<") for l in lines]
    for old, new in RENAMES:
        lines = [l.replace(old, new) for l in lines]
    lines = [l.replace('category="Dungeon Journal"', 'category="Journal des donjons"') for l in lines]
    bpath = plat / "Bindings.xml"
    btext = read(bpath) if bpath.is_file() else BINDINGS_SKELETON
    bnl = "\r\n" if "\r\n" in btext else "\n"
    block = [f"\t{BIND_BEGIN} {version} (généré par dev/make_dungeonjournal.py : ne pas modifier à la main) -->"]
    block += lines + ["\t" + BIND_END]
    btext = replace_block(btext, BIND_BEGIN, BIND_END, block, bnl, "</Bindings>")
    write(bpath, btext)

    # 4. bloc DungeonJournal de Platyplus.toc (les réglages sauvegardés doivent y être déclarés)
    ptoc_path = plat / "Platyplus.toc"
    ptoc = read(ptoc_path)
    for sv in SV_NAMES:
        if not re.search(r"^## SavedVariables(PerCharacter)?:.*\b" + sv + r"\b", ptoc, re.M):
            fail(f"Platyplus.toc : déclarez {sv} dans ## SavedVariables / ## SavedVariablesPerCharacter")
    nl = "\r\n" if "\r\n" in ptoc else "\n"
    if ptoc.find(TOC_BEGIN) < 0 or ptoc.find(TOC_END) < ptoc.find(TOC_BEGIN):
        fail(f"Platyplus.toc : ajoutez les lignes « {TOC_BEGIN} » et « {TOC_END} » là où le journal doit se charger")
    block = [f"{TOC_BEGIN} {version} (généré par dev/make_dungeonjournal.py : ne pas modifier à la main)", GLUE]
    block += ["DungeonJournal\\" + e for e in entries] + [TOC_END]
    ptoc = replace_block(ptoc, TOC_BEGIN, TOC_END, block, nl, TOC_BEGIN)
    write(ptoc_path, ptoc)

    size = sum(p.stat().st_size for p in dest.rglob("*") if p.is_file())
    print(f"DungeonJournal {version} importé dans {dest}")
    print(f"  {files} fichiers Lua adaptés, {paths} chemin(s) d'images, retouches : "
          + ", ".join(f"{k} {v}" for k, v in patched.items()))
    print("  couleurs reliées au style : " + ", ".join(f"{k} {v}" for k, v in color_total.items())
          + f", fonds {backdrop_total}")
    print(f"  {len(entries)} fichiers dans le bloc DungeonJournal de Platyplus.toc, {len(lines)} raccourcis")
    print(f"  {size / 1e6:.0f} Mo")


if __name__ == "__main__":
    main()
