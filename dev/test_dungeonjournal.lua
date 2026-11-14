-- Test : journal des donjons intégré dans Platyplus (dossier DungeonJournal/, DungeonJournalGlue.lua,
-- DungeonJournalSkin.lua, DungeonJournalPlus.lua, dev/make_dungeonjournal.py)
-- Vérifie l'intégration, pas le journal lui-même (10 000 lignes qui ne tournent vraiment que dans le jeu) :
-- .toc et raccourcis, espace de noms séparé, réglages sauvegardés à part, chemins des images, style Platyplus
-- (couleurs, thèmes, fenêtre), liste des donjons à gauche, « À ton niveau » sur l'accueil, veille quand l'addon
-- DungeonJournal séparé est chargé (et copie de ses réglages), onglet Donjons et /pp donjons.
-- Usage : python -I dev\lua.py run dev\test_dungeonjournal.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local S = M.state

-- guerrier niveau 24 de l'Alliance ; la quête 214 (Bandeaux de soie rouge, Mortemines) est rendue
dofile(DEV .. "\\preview_dungeon.lua")(M, def, { level = 24, done = { [214] = true } })
local standalone = false
def("C_AddOns", {
    IsAddOnLoaded = function(name) return name == "ForeverDungeonJournal" and standalone end,
    GetAddOnMetadata = function() return nil end,
})
def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = rawget(tbl, name)
    if type(orig) ~= "function" then return end
    rawset(tbl, name, function(...) local r = { orig(...) }; hook(...); return unpack(r) end)
end)
def("StaticPopupDialogs", {})
def("DEFAULT_CHAT_FRAME", { AddMessage = function(_, msg) print(msg) end })
def("ReloadUI", function() M.reloaded = true end)
def("debugprofilestop", function() return os.clock() * 1000 end)
-- (GetLibrary/NewLibrary : LibDeflate, apportée par DungeonJournal 2.0, s'enregistre auprès de LibStub)
def("LibStub", setmetatable({ GetLibrary = function() return nil end, NewLibrary = function() return {} end },
    { __call = function() return nil end }))
def("PlatyplusDB", { welcomeSeen = true })
-- ce que le jeu met dans les réglages sauvegardés du journal (un personnage qui l'utilisait déjà)
def("PlatyplusDungeonCharacterDB", { journalMode = "gamer" })

---------------------------------------------------------------------------
-- Fichiers : tout Platyplus et le bloc du journal
---------------------------------------------------------------------------
local files, inBlock, block = {}, false, {}
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    line = line:gsub("\r", "")
    if line:find("^# >>> DungeonJournal") then inBlock = true end
    if line:find("^# <<< DungeonJournal") then inBlock = false end
    local f = line:match("^([%w_%.\\]+%.lua)")
    if f then
        files[#files + 1] = f
        if inBlock then block[#block + 1] = f end
    end
end

section("le .toc")
local toc = io.open(ADDON_DIR .. "\\Platyplus.toc"):read("*a")
check(#block >= 50, "bloc DungeonJournal du .toc : " .. #block .. " fichiers")
check(block[1] == "DungeonJournalGlue.lua", "DungeonJournalGlue.lua chargé juste avant le journal")
check(block[2] == "DungeonJournal\\Core\\Bootstrap.lua", "puis Bootstrap.lua du journal")
local hasVersionCheck = false
for _, f in ipairs(block) do if f:find("VersionCheck") then hasVersionCheck = true end end
check(not hasVersionCheck, "VersionCheck.lua laissé de côté (il annonce sa version au groupe et à la guilde)")
check(toc:find("## SavedVariables:[^\n]*PlatyplusDungeonDB") ~= nil, "PlatyplusDungeonDB déclaré (réglages du journal, compte)")
check(toc:find("## SavedVariablesPerCharacter:[^\n]*PlatyplusDungeonCharacterDB") ~= nil,
    "PlatyplusDungeonCharacterDB déclaré (réglages du journal, personnage)")
check(toc:find("## OptionalDeps:[^\n]*ForeverDungeonJournal") ~= nil,
    "ForeverDungeonJournal dans OptionalDeps : l'addon séparé, s'il est activé, passe avant")
local skinPos, plusPos, lastDJ, uiPages
for i, f in ipairs(files) do
    if f == "DungeonJournalSkin.lua" then skinPos = i end
    if f == "DungeonJournalPlus.lua" then plusPos = i end
    if f:find("^DungeonJournal\\") then lastDJ = i end
    if f == "UIPages.lua" then uiPages = i end
end
check(skinPos and plusPos and lastDJ and skinPos > lastDJ and plusPos > lastDJ and plusPos < uiPages,
    "DungeonJournalSkin.lua et DungeonJournalPlus.lua après le journal, avant UIPages.lua")

section("raccourcis")
local bind = io.open(ADDON_DIR .. "\\Bindings.xml", "rb"):read("*a")
check(bind:find('name="PLATYPLUSDUNGEON_TOGGLE"', 1, true) and bind:find("PlatyplusDungeon_Toggle()", 1, true),
    "raccourci « ouvrir le journal » : PLATYPLUSDUNGEON_TOGGLE")
check(not bind:find("FOREVERDUNGEONJOURNAL", 1, true), "les noms de l'addon séparé ne sont pas repris")
check(bind:find("<!-- >>> DungeonJournal", 1, true), "Bindings.xml : le bloc DungeonJournal")
check(select(2, bind:gsub("<Bindings>", "")) == 1 and select(2, bind:gsub("</Bindings>", "")) == 1, "un seul <Bindings>")

---------------------------------------------------------------------------
section("chargement")
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
check(#M.errors == 0, "tous les fichiers se chargent sans erreur (" .. #M.errors .. ")")
if #M.errors > 0 then M.report() M.errors = {} end
local D = ns.Dungeon
check(type(D) == "table" and type(D.DB) == "table" and type(D.ORDER) == "table" and #D.ORDER >= 30,
    "ns.Dungeon : les données du journal (" .. (D and D.ORDER and #D.ORDER or 0) .. " donjons)")
check(D.PpStandby == false, "pas de veille : l'addon séparé n'est pas chargé")
check(D.PpVersion == "2.0.1", "version importée : " .. tostring(D.PpVersion))
check(rawget(_G, "PlatyplusDungeon_NS") == D, "_G.PlatyplusDungeon_NS : le même espace de noms")
check(ns.DB == nil and ns.ORDER == nil and ns.THEMES == nil and ns.L == nil, "rien du journal dans l'espace de noms de Platyplus")
local stray = {}
for k in pairs(_G) do
    if type(k) == "string" and k:find("ForeverDungeonJournal") then stray[#stray + 1] = k end
end
check(#stray == 0, "aucun nom global ForeverDungeonJournal* créé (" .. table.concat(stray, ", ") .. ")")
check(type(rawget(_G, "PlatyplusDungeon_Toggle")) == "function", "PlatyplusDungeon_Toggle défini (raccourci)")
check(SLASH_PLATYPLUSDUNGEON1 == "/dj", "/dj enregistré")

section("images")
local function exists(gamePath)
    local rel = gamePath:gsub("^Interface\\AddOns\\Platyplus\\", "")
    for _, e in ipairs({ ".tga", ".blp", "" }) do
        local f = io.open(ADDON_DIR .. "\\" .. rel .. e, "rb")
        if f then f:close() return true end
    end
    return false
end
local art = D.DUNGEON_HOME_ART and D.DUNGEON_HOME_ART["Hall of Thanes"]
check(type(art) == "string" and art:find("^Interface\\AddOns\\Platyplus\\DungeonJournal\\Media\\") ~= nil,
    "chemin des images : " .. tostring(art))
check(art and exists(art), "l'image de la Salle des thanes est à ce chemin")
local strayPath = {}
for _, f in ipairs(block) do
    local text = io.open(ADDON_DIR .. "\\" .. f, "rb"):read("*a")
    if text:find("AddOns\\\\ForeverDungeonJournal", 1, true) then strayPath[#strayPath + 1] = f end
end
check(#strayPath == 0, "plus aucun chemin vers l'addon séparé (" .. table.concat(strayPath, ", ") .. ")")

---------------------------------------------------------------------------
section("couleurs du style (avant le chargement des réglages)")
local Skin = ns.DungeonSkin
local function close(a, b) return math.abs(a - b) < 0.02 end
local r, g, b, a = D.PpC("bg", 0.16, 0.12, 0.07, 0.96)
check(r == 0.16 and g == 0.12 and a == 0.96, "style pas encore allumé : la couleur passe telle quelle")

---------------------------------------------------------------------------
section("réglages (ADDON_LOADED)")
M.fireEvent("ADDON_LOADED", "Platyplus")
check(#M.errors == 0, "ADDON_LOADED sans erreur")
check(ns.db.dungeonSkin == true and ns.db.dungeonList == true and ns.db.dungeonFit == true, "trois réglages, allumés par défaut")
check(Skin.active == true and D.PpSkin ~= nil, "style Platyplus allumé")
check(not ns.DungeonPlus.Overlay() and ns.DungeonPlus.Tunable() and Skin.external == nil and Skin.Ext.main == nil,
    "journal intégré : par ses points d'accroche, pas par la surcharge de l'addon séparé")
check((Skin.themes or 0) >= 5, "thèmes des donjons réécrits (" .. tostring(Skin.themes) .. ")")
local T = ns.THEME
local th = D.THEMES["Shadowfang Keep"]
check(close(th.frame[1], T.bg[1]) and close(th.title[1], T.text[1]) and close(th.muted[3], T.dim[3]),
    "thème du Donjon d'Ombrecroc : fond, titres et texte atténué de Platyplus")

section("allègement : langues")
local langs = {}
for lang in pairs(D.Locales) do langs[#langs + 1] = lang end
table.sort(langs)
check(table.concat(langs, ",") == "enUS,frFR", "textes de l'interface : français et anglais seulement (" .. table.concat(langs, ",") .. ")")
local clangs = {}
for lang in pairs(D.ContentLocales) do clangs[#clangs + 1] = lang end
check(#clangs == 1 and D.ContentLocales.frFR ~= nil, "traductions des donjons et quêtes : le français seulement (" .. table.concat(clangs, ",") .. ")")
check(D.ppPruned and D.ppPruned.removed >= 8, "langues retirées : " .. tostring(D.ppPruned and D.ppPruned.removed))
check(D.LocalizeDungeonName("The Deadmines") == "Les Mortemines", "les noms restent traduits (« Les Mortemines »)")
check(D.L("OBJECTIVE") == "Objectif", "les textes de l'interface aussi (« Objectif »)")
local choices = {}
for _, c in ipairs(D.PpLanguageChoices or {}) do choices[#choices + 1] = c.locale end
check(table.concat(choices, ",") == "enUS,frFR", "menu de langue du journal : English, Français (" .. table.concat(choices, ",") .. ")")

section("couleurs du style")
r, g, b, a = D.PpC("bg", 0.16, 0.12, 0.07, 0.96)
local h = Skin.HSV(r, g, b)
check(b > r and h > 180 and h < 260 and a == 0.96 and r < 0.2, "fond brun -> gris bleuté sombre, même opacité")
r, g, b = D.PpC("bg", 0.70, 0.58, 0.39, 1)
check(math.max(r, g, b) < 0.3, "fond clair du parchemin -> fond sombre (texte clair lisible)")
r, g, b = D.PpC("text", 1.00, 0.82, 0.27)
check(close(r, T.text[1]) and close(b, T.text[3]), "texte doré -> texte clair de Platyplus")
r, g, b = D.PpC("text", 0.10, 0.065, 0.025)
check(close(r, T.text[1]), "encre sombre du parchemin -> texte clair")
r, g, b = D.PpC("text", 0.12, 1, 0)
check(r == 0.12 and g == 1 and b == 0, "vert (qualité, quête faite) gardé")
r, g, b = D.PpC("text", 1, 0.5, 0)
check(r == 1 and g == 0.5 and b == 0, "orange légendaire gardé")
r, g, b = D.PpC("edge", 1.00, 0.76, 0.22, 1)
check(close(r, T.accent[1]) and close(b, T.accent[3]), "liseré doré du survol -> bleu Platyplus")
r, g, b, a = D.PpC("edge", 0.34, 0.34, 0.34, 1)
check(r == 1 and g == 1 and b == 1 and a < 0.2, "liseré gris -> filet clair discret")
r, g, b, a = D.PpC("tex", 0, 0, 0, 0.42)
check(r == 0 and a == 0.42, "voile noir gardé")
r, g, b, a = D.PpC("bg", 0.20, 0.78, 1.00, 0.18)
check(r == 0.20 and b == 1.00, "cyan du mode « masquer les donjons » gardé")

---------------------------------------------------------------------------
section("connexion (PLAYER_LOGIN) : le journal construit ses fenêtres")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(1)
check(#M.errors == 0, "PLAYER_LOGIN sans erreur Lua")
if #M.errors > 0 then M.report() M.errors = {} end
local f = rawget(_G, "PlatyplusDungeonFrame")
check(f ~= nil, "fenêtre du journal créée : PlatyplusDungeonFrame")
check(f and f.ppWindow == true and f.ppBg ~= nil, "elle a le cadre des fenêtres Platyplus (fond arrondi, ombre)")
local bdc = { f:GetBackdropColor() }
check(bdc[4] == 0, "son fond carré d'origine est transparent")
local bd = f:GetBackdrop()
check(bd and bd.edgeSize == 1 and bd.bgFile == "Interface\\Buttons\\WHITE8X8", "fond aplati : ni pierre ni bord de Blizzard")
check(f.homeParchment and not f.homeParchment:IsShown(), "pas de parchemin sous l'accueil")
check(f.questParchment and not f.questParchment:IsShown(), "pas de parchemin sous les pages de quête")
check(f.closeButton and f.closeButton.ppSkinned == true, "croix de fermeture redessinée")
check(f.backButton and f.backButton.ppSkinned == true, "bouton « Donjons » en pastille Platyplus")
local bar = f.homeScroll and (f.homeScroll.ScrollBar or rawget(_G, "PlatyplusDungeonHomeScrollScrollBar"))
check(bar == nil or bar.ppSkinned == true, "barre de défilement de l'accueil affinée")

---------------------------------------------------------------------------
section("ouverture : accueil et liste des donjons")
PlatyplusDungeon_Toggle()
M.advance(0.5)
check(#M.errors == 0, "ouverture sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
check(f:IsShown() and f.currentView == "home", "le journal s'ouvre sur l'accueil")
local side = rawget(_G, "PlatyplusDungeonList")
check(side ~= nil and side:IsShown(), "colonne « Donjons » à gauche du journal")
check(side and S(side).parent == f, "collée au journal (elle suit ses déplacements)")
local pt = side and S(side).points[1]
check(pt and pt[1] == "TOPRIGHT" and pt[2] == f and pt[3] == "TOPLEFT", "à gauche, sur toute la hauteur")
check(f.ppBg and S(f.ppBg.tl).points[1][4] == -ns.DungeonPlus.SIDE_W, "le fond de la fenêtre englobe la colonne (une seule fenêtre)")
-- lignes : comme l'accueil du journal (mêmes donjons, même ordre)
local rows = {}
for _, fr in ipairs(M.allFrames) do
    if rawget(fr, "dungeon") and rawget(fr, "chipText") and fr:IsShown() then rows[#rows + 1] = fr end
end
table.sort(rows, function(x, y) return S(x).points[1][5] > S(y).points[1][5] end)
local cards = 0
for _, fr in ipairs(M.allFrames) do
    if rawget(fr, "dungeonName") and rawget(fr, "meta") and fr:IsShown() then cards = cards + 1 end
end
check(#rows == cards and #rows >= 30, "une ligne par donjon de l'accueil (" .. #rows .. " lignes, " .. cards .. " cartes)")
local byName = {}
for _, row in ipairs(rows) do byName[row.dungeon] = row end
local dm, rfc, gnome, bfd = byName["The Deadmines"], byName["Ragefire Chasm"], byName["Gnomeregan"], byName["Blackfathom Deeps"]
check(dm and dm.fit == "good" and S(dm.chipText).text == "17-26", "Mortemines (17-26) : à ton niveau, en vert")
check(dm and close(S(dm.chipText).textColor[2], T.good[2]), "  tranche de niveau en vert")
check(rfc and rfc.fit == "past" and rfc.dimmed, "Gouffre de Ragefeu (13-18) : dépassé, grisé")
check(gnome and gnome.fit == "hard", "Gnomeregan (29-38) : trop dur pour l'instant")
check(byName["Excavation Site: Wetlands"] and byName["Excavation Site: Wetlands"].fit == "soon",
    "Site de fouilles (26-33) : bientôt")
check(dm and dm.done == 1 and dm.total >= 5 and S(dm.progress).text == "1/" .. dm.total,
    "quêtes des Mortemines : 1 faite sur " .. tostring(dm and dm.total))
check(bfd and S(bfd.progress).text == "0/" .. bfd.total, "Profondeurs de Brassenoire : 0/" .. tostring(bfd and bfd.total))
check(rows[1] and rows[1].dungeon == D.ORDER[1], "dans l'ordre du journal (niveaux croissants)")
local P = ns.DungeonPlus
check(P.ShortName("Monastère écarlate : Cathédrale") == "Monastère : Cathédrale"
    and P.ShortName("Hache-tripes : Est") == "Hache-tripes : Est" and P.ShortName("Pic Blackrock inférieur") == "Pic Blackrock inférieur",
    "noms longs abrégés en gardant l'aile (« Monastère : Cathédrale »)")
local sm = byName["Scarlet Monastery: Cathedral"]
check(sm and S(sm.name).text == P.ShortName(S(sm.name).text) and not S(sm.name).text:find("écarlate", 1, true),
    "  dans la liste : « " .. tostring(sm and S(sm.name).text) .. " »")

section("accueil : « À ton niveau »")
local dmCard
for _, fr in ipairs(M.allFrames) do
    if rawget(fr, "dungeonName") == "The Deadmines" and rawget(fr, "meta") then dmCard = fr end
end
check(dmCard and dmCard.ppFit and dmCard.ppFit:IsShown() and S(dmCard.ppFit.text).text == "À ton niveau",
    "carte des Mortemines : pastille « À ton niveau »")
check(dmCard and close(S(dmCard.meta).textColor[2], T.good[2]), "  et « LV 17-26 » en vert")
local counts = dmCard and S(dmCard.counts).text or ""
check(counts:find(dm.done .. "/" .. dm.total, 1, true) ~= nil,
    "la liste compte les quêtes comme la carte du journal (" .. counts:gsub("|T.-|t%s*", "") .. ")")
local rfcCard
for _, fr in ipairs(M.allFrames) do
    if rawget(fr, "dungeonName") == "Ragefire Chasm" and rawget(fr, "meta") then rfcCard = fr end
end
check(rfcCard and not (rfcCard.ppFit and rfcCard.ppFit:IsShown()), "carte du Gouffre de Ragefeu : pas de pastille")
check((f.homeScroll:GetVerticalScroll() or 0) > 0, "l'accueil a défilé jusqu'aux donjons de ton niveau")

---------------------------------------------------------------------------
section("clic dans la liste : un donjon")
M.fire(dm, "OnClick", "LeftButton")
M.advance(0.3)
check(#M.errors == 0, "clic sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
check(f.currentView == "dungeon" and D.GetSelectedDungeon() == "The Deadmines", "les Mortemines s'ouvrent")
check(dm.selected == true and S(dm.sel[1]).shown, "la ligne est surlignée")
local home
for _, fr in ipairs(M.allFrames) do if rawget(fr, "home") == true then home = fr end end
check(home and not home.selected, "« Accueil » ne l'est plus")
M.fire(bfd, "OnClick", "LeftButton")
M.advance(0.3)
check(D.GetSelectedDungeon() == "Blackfathom Deeps" and bfd.selected and not dm.selected,
    "un autre donjon d'un clic, sans repasser par l'accueil")
section("onglet Quêtes : titres, niveau requis, quête sélectionnée")
M.fire(dm, "OnClick", "LeftButton")
M.advance(0.3)
M.fire(f.questsTab, "OnClick", "LeftButton")
M.advance(0.3)
check(#M.errors == 0, "onglet Quêtes sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
local oh = f.questObjectiveHeader
check(oh and oh.ppHeader and S(oh).text == "OBJECTIF", "titre de section en capitales : " .. tostring(oh and S(oh).text))
check(oh and close(S(oh).textColor[1], T.accent[1]) and close(S(oh).textColor[3], T.accent[3]), "  en bleu Platyplus")
check(f.questTurninHeader and S(f.questTurninHeader).text == "À RENDRE À", "accents en capitales : « À RENDRE À »")
check(oh and oh.ppLine and S(oh.ppLine).shown == S(oh).shown, "  suivi d'un filet (montré avec le titre)")
f.questNotesHeader:Hide()
check(not S(f.questNotesHeader.ppLine).shown, "  le filet se cache avec son titre")
local function questRows()
    local out = {}
    for _, row in ipairs({ f.questContent:GetChildren() }) do
        if rawget(row, "questIndex") and row:IsShown() then out[#out + 1] = row end
    end
    return out
end
local qrows = questRows()
local sel = D.PpSelectedQuest()
local bars, okColors = 0, true
for _, row in ipairs(qrows) do
    if row.ppBar and S(row.ppBar).shown then
        bars = bars + 1
        if row.questIndex ~= sel then okColors = false end
    end
end
check(#qrows >= 5 and bars == 1 and okColors, "barre bleue sur la quête sélectionnée seulement (" .. #qrows .. " quêtes)")
-- un donjon au-dessus de ton niveau : les niveaux requis trop hauts en rouge
M.fire(gnome, "OnClick", "LeftButton")
M.advance(0.3)
local red, consistent = 0, true
for _, row in ipairs(questRows()) do
    local need = Skin.RequiredLevel(S(row.meta).text)
    local c = S(row.meta).textColor
    local isRed = close(c[1], T.bad[1]) and close(c[2], T.bad[2])
    if need and need > 24 then red = red + 1 end
    if need and (need > 24) ~= isRed then consistent = false end
end
check(red >= 1 and consistent, "Gnomeregan : niveau requis en rouge quand il dépasse ton niveau (" .. red .. " quête(s))")
check(Skin.RequiredLevel("À partir du niveau 31") == 31, "lecture du niveau dans le texte du journal")

section("allègement : rafales d'événements de quêtes")
local listDraws = 0
local body = D.PpQuestListBody
D.PpQuestListBody = function(...) listDraws = listDraws + 1 return body(...) end
for _ = 1, 10 do M.fireEvent("QUEST_LOG_UPDATE") end
M.advance(0.1)
check(listDraws == 0, "journal ouvert : pas de dessin pendant la rafale")
M.advance(0.5)
check(listDraws == 1, "un seul dessin pour 10 événements (" .. listDraws .. ")")
f:Hide()
listDraws = 0
for _ = 1, 10 do M.fireEvent("QUEST_LOG_UPDATE") M.advance(0.05) end
M.advance(1)
check(listDraws == 0, "journal fermé : aucun dessin (" .. listDraws .. ")")
f:Show()
M.advance(0.3)
check(f.currentView == "dungeon", "rouvert : il reprend où il était")
D.PpQuestListBody = body
check(#M.errors == 0, "sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end

M.fire(home, "OnClick", "LeftButton")
M.advance(0.3)
check(f.currentView == "home" and home.selected and not bfd.selected, "« Accueil » ramène aux cartes")

section("fenêtres secondaires du journal, au style Platyplus")
local windows = 0
for _, step in ipairs({
    { "ToggleSettingsPanel", nil, "PlatyplusDungeonSettings" },
    { "ToggleFavouritesWindow", f, "PlatyplusDungeonFavourites" },
    { "ToggleLootFilterWindow", f, "PlatyplusDungeonLootFilter" },
    { "ShowCopyBox", "texte à copier", "PlatyplusDungeonCopyBox" },
    { "ShowModeChooser", true, "PlatyplusDungeonModeChooser" },
}) do
    local fn = D[step[1]]
    local ok, err = true, nil
    if type(fn) == "function" then ok, err = pcall(fn, step[2]) end
    M.advance(0.2)
    local w = rawget(_G, step[3])
    check(ok and #M.errors == 0, step[1] .. " sans erreur" .. (ok and "" or (" : " .. tostring(err):sub(1, 200))))
    if #M.errors > 0 then M.report() M.errors = {} end
    if w then
        check(w.ppWindow == true and (w:GetBackdrop() == nil or select(4, w:GetBackdropColor()) == 0),
            "  " .. step[3] .. " : cadre des fenêtres Platyplus")
        windows = windows + 1
        w:Hide()
    end
end
check(windows >= 4, "fenêtres secondaires habillées (" .. windows .. ")")

section("réglages de la liste")
ns:Set("dungeonList", false)
M.advance(0.2)
check(not side:IsShown(), "« Liste des donjons » éteint : la colonne disparaît")
ns:Set("dungeonList", true)
M.advance(0.2)
check(side:IsShown(), "rallumé : elle revient")
ns:Set("dungeonFit", false)
M.advance(0.2)
check(not dmCard.ppFit:IsShown(), "« À ton niveau » éteint : plus de pastille sur l'accueil")
ns:Set("dungeonFit", true)
M.advance(0.2)
check(dmCard.ppFit:IsShown(), "rallumé : elle revient")

---------------------------------------------------------------------------
section("onglet Donjons des réglages")
local Pages = ns.Pages
local idx
for i = 1, Pages:Count() do if Pages:GetInfo(i).id == "dungeons" then idx = i end end
check(idx ~= nil, "onglet « Donjons » présent")
ns.UI:Open()
ns.UI:SelectTab(idx)
M.advance(0.3)
local page = ns.UI.pages[idx]
check(page and #page.widgets == 2, "deux cartes : Journal des donjons, À propos (" .. (page and #page.widgets or 0) .. ")")
check(#M.errors == 0, "construction de l'onglet sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
ns.UI:Close()

section("/pp donjons et menu de l'icône")
f:Hide()
SlashCmdList.PLATYPLUS("donjons")
M.advance(0.2)
check(f:IsShown(), "/pp donjons ouvre le journal")
SlashCmdList.PLATYPLUS("donjons")
check(not f:IsShown(), "et le referme")
local before = #M.printed
SlashCmdList.PLATYPLUS("donjons etat")
local said = table.concat(M.printed, "\n", before + 1)
check(said:find("journal des donjons :", 1, true) and said:find("style Platyplus : allumé", 1, true),
    "/pp donjons etat : ce que fait le journal")
check(ns.Launcher and ns.Launcher.ShowMenu, "menu de l'icône disponible")
ns.Launcher:ShowMenu()
local jr = ns.Launcher.journalRow
check(jr and S(jr.label).text == "Journal des donjons", "ligne « Journal des donjons » dans le menu de l'icône")
if jr then M.fire(jr, "OnClick", "LeftButton") end
check(f:IsShown(), "  elle ouvre le journal")
check(#M.errors == 0, "sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end

---------------------------------------------------------------------------
section("veille : l'addon DungeonJournal séparé est chargé")
standalone = true
-- ses réglages sauvegardés (chargés par le jeu avant Platyplus)
def("ForeverDungeonJournalDB", { lastDungeon = "Gnomeregan", favourites = { items = { [2074] = true } } })
def("ForeverDungeonJournalCharacterDB", { journalMode = "rpg", hiddenDungeons = { ["Ragefire Chasm"] = true } })
local ns2 = {}
local frames = #M.allFrames
for _, file in ipairs(block) do
    local chunk = assert(loadfile(ADDON_DIR .. "\\" .. file))
    local ok, err = pcall(chunk, "Platyplus", ns2)
    if not ok then M.errors[#M.errors + 1] = file .. " : " .. tostring(err) end
end
check(#M.errors == 0, "les fichiers du journal se chargent sans rien faire")
check(ns2.Dungeon.PpStandby == true and ns2.Dungeon.DB == nil, "veille : aucune donnée du journal chargée")
local created = 0
for i = frames + 1, #M.allFrames do
    local n = S(M.allFrames[i]).name
    if type(n) == "string" and n:find("^PlatyplusDungeon") then created = created + 1 end
end
check(created == 0, "aucune fenêtre du journal créée")
M.fireEvent("ADDON_LOADED", "Platyplus")
check(type(PlatyplusDungeonDB) == "table" and PlatyplusDungeonDB.lastDungeon == "Gnomeregan"
    and PlatyplusDungeonDB.favourites.items[2074] == true, "réglages et favoris de l'addon séparé copiés pour Platyplus")
check(PlatyplusDungeonDB ~= ForeverDungeonJournalDB, "  une copie (pas la même table)")
check(PlatyplusDungeonCharacterDB.journalMode == "rpg" and PlatyplusDungeonCharacterDB.hiddenDungeons["Ragefire Chasm"],
    "réglages du personnage copiés aussi (mode RPG, donjons masqués)")
ForeverDungeonJournalDB.lastDungeon = "Scholomance"
M.fireEvent("PLAYER_LOGOUT")
check(PlatyplusDungeonDB.lastDungeon == "Scholomance", "copie refaite à la déconnexion (la dernière session compte)")
check(#M.errors == 0, "sans erreur")

---------------------------------------------------------------------------
section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
