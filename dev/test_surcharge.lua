-- Test : « surcharge » de l'addon DungeonJournal d'Exehn installé à part (ForeverDungeonJournal), version publique
-- de Platyplus (sans le dossier DungeonJournal/). La liste des donjons, « À ton niveau » et le style de Platyplus
-- sont posés sur SA fenêtre par hooksecurefunc / HookScript (DungeonJournalPlus.lua, DungeonJournalSkin.lua).
-- L'addon d'Exehn n'est pas embarqué : ce test en fabrique un faux, minimal, qui expose la même chose que le vrai
-- (espace de noms _G.ForeverDungeonJournal_NS, fenêtre ForeverDungeonJournalFrame construite à PLAYER_LOGIN,
-- réglages ForeverDungeonJournalDB). Le vrai addon, s'il est installé, est essayé par test_surcharge_reel.lua.
-- Usage : python -I dev\lua.py run dev\test_surcharge.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local S = M.state
local function close(a, b) return math.abs(a - b) < 0.02 end

dofile(DEV .. "\\preview_dungeon.lua")(M, def, { level = 24, done = { [214] = true } })
def("C_AddOns", {
    IsAddOnLoaded = function(name) return name == "ForeverDungeonJournal" end,
    GetAddOnMetadata = function(_, field) return field == "Version" and "9.9.9" or nil end,
})
-- comme dans le jeu : la fonction d'origine puis le hook ; refuse ce qui n'est pas une fonction
local hooked = {}
def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = tbl[name]
    if type(orig) ~= "function" then error("hooksecurefunc : " .. tostring(name) .. " n'est pas une fonction") end
    hooked[#hooked + 1] = name
    rawset(tbl, name, function(...) local r = { orig(...) }; hook(...); return unpack(r) end)
end)
-- comme dans le jeu : un cadre fait sur un modèle sécurisé est protégé dès sa création
local protectedFrames = setmetatable({}, { __mode = "k" })
local rawCreateFrame = CreateFrame
def("CreateFrame", function(kind, name, parent, template, ...)
    local fr = rawCreateFrame(kind, name, parent, template, ...)
    if type(template) == "string" and template:find("Secure", 1, true) then protectedFrames[fr] = true end
    return fr
end)
M.impl.IsProtected = function(fr) return protectedFrames[fr] == true, protectedFrames[fr] == true end
def("StaticPopupDialogs", {})
def("DEFAULT_CHAT_FRAME", { AddMessage = function(_, msg) print(msg) end })
def("ReloadUI", function() end)
def("debugprofilestop", function() return os.clock() * 1000 end)
def("LibStub", setmetatable({ GetLibrary = function() return nil end, NewLibrary = function() return {} end },
    { __call = function() return nil end }))
def("PlatyplusDB", { welcomeSeen = true })

---------------------------------------------------------------------------
-- Le faux addon d'Exehn (chargé AVANT Platyplus : OptionalDeps)
---------------------------------------------------------------------------
local X = {}
def("ForeverDungeonJournal_NS", X)
def("ForeverDungeonJournalDB", { lastMode = "bosses", lastQuest = 2 })
X.DB = {
    ["Ragefire Chasm"] = { level = "13-18", quests = {} },
    ["The Deadmines"] = { level = "17-26", quests = { { id = 214 }, { id = 2040 }, { id = 9, repeatable = true } } },
    ["Excavation Site"] = { level = "26-33", quests = {} },
    ["Gnomeregan"] = { level = "29-38", quests = { { id = 2904 } } },
    ["Sealed Vault"] = { level = "40-45", quests = {} },
    ["Coming Soon"] = { level = "60", previewOnly = true },
}
X.ORDER = { "Ragefire Chasm", "The Deadmines", "Excavation Site", "Gnomeregan", "Sealed Vault", "Coming Soon" }
local function theme()
    return {
        frame = { 0.10, 0.07, 0.04, 0.98 }, content = { 0.16, 0.12, 0.07, 0.96 }, border = { 0.47, 0.34, 0.16, 1 },
        header = { 0.20, 0.14, 0.08, 0.96 }, left = { 0.13, 0.10, 0.06, 0.95 }, right = { 0.13, 0.10, 0.06, 0.95 },
        row = { 0.18, 0.13, 0.08, 0.92 }, rowSelected = { 0.40, 0.28, 0.10, 0.96 }, lootRow = { 0.18, 0.13, 0.08, 0.94 },
        title = { 1.00, 0.82, 0.27 }, text = { 0.95, 0.83, 0.53 }, muted = { 0.72, 0.67, 0.58 },
    }
end
X.THEMES = { ["The Deadmines"] = theme(), ["Hall of Thanes"] = theme() }
X.L = function(key) return key == "AVAILABLE_FROM_LEVEL" and "À partir du niveau %s" or key end
X.LocalizeDungeonName = function(name) return name == "The Deadmines" and "Les Mortemines" or name end
X.HiddenDungeons = function() return {} end
X.IsDungeonLocked = function(name) return name == "Sealed Vault" end
X.IsQuestFinished = function(id) return id == 214 end
local lockedNotice, opened, selected = nil, {}, nil
X.RPGLockedNotice = function(name) lockedNotice = name end
X.GetSelectedDungeon = function() return selected, 1 end
local headerCalls = 0
X.UpdateRPGHeader = function() headerCalls = headerCalls + 1 end

local STONE = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }
local CARD = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local frame, cards, questRows = nil, {}, {}

local function applyTheme()
    local t = X.THEMES[selected] or X.THEMES["Hall of Thanes"]
    frame:SetBackdropColor(unpack(t.frame))
    frame.contentPanel:SetBackdropColor(unpack(t.content))
    frame.contentPanel:SetBackdropBorderColor(unpack(t.border))
    frame.homePanel:SetBackdropColor(0.16, 0.12, 0.07, 0.96)
    frame.homePanel:SetBackdropBorderColor(0.47, 0.34, 0.16, 1)
    frame.dungeonTitle:SetTextColor(unpack(t.title))
end

local function makeCard(i)
    local card = CreateFrame("Button", nil, frame.homeCardsContent, "BackdropTemplate")
    card:SetBackdrop(CARD)
    card:SetBackdropColor(0.16, 0.12, 0.07, 0.96)
    card:SetBackdropBorderColor(0.47, 0.34, 0.16, 1)
    card.glow = card:CreateTexture(nil, "ARTWORK")
    card.glow:SetColorTexture(1.00, 0.84, 0.25, 0.30)
    card.meta = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    cards[i] = card
    return card
end

local function refreshHome()
    if not (frame and frame.homeCardsContent) then return end
    for i, name in ipairs(X.ORDER) do
        local card = cards[i] or makeCard(i)
        card.dungeonName = name
        card.meta:SetText("LV " .. X.DB[name].level)
        card.meta:SetTextColor(1.00, 0.95, 0.82)
        card:Show()
    end
    if X.UpdateRPGHeader then pcall(X.UpdateRPGHeader, frame) end
end
X.RefreshHomeCards = function()
    if frame and frame:IsShown() and frame.currentView == "home" then refreshHome() end
end

local function showHome()
    frame.contentPanel:Hide()
    frame.homePanel:Show()
    frame.currentView = "home"
    refreshHome()
end

local function refreshQuests()
    for i, need in ipairs({ 14, 31, 20 }) do
        local row = questRows[i]
        if not row then
            row = CreateFrame("Button", nil, frame.questContent)
            row.questIndex = i
            row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.check = row:CreateTexture(nil, "OVERLAY")
            row.check:Hide()
            questRows[i] = row
        end
        row.meta:SetText("À partir du niveau " .. need)
        row.meta:SetTextColor(0.72, 0.67, 0.58)
        row:Show()
    end
    frame.selectedQuestMeta:SetText("À partir du niveau 31")
    frame.questText:SetText("|cff6e5c40Bandeaux : 10/10|r\nTuez Van Cleef")
end

local function selectDungeon(name)
    frame.homePanel:Hide()
    frame.contentPanel:Show()
    frame.currentView = "dungeon"
    selected = name
    frame.dungeonTitle:SetText(name)
    applyTheme()
end
X.OpenBossPage = function(name)
    opened[#opened + 1] = "boss:" .. name
    selectDungeon(name)
    ForeverDungeonJournalDB.lastMode = "bosses"
end
X.OpenQuestPage = function(name)
    opened[#opened + 1] = "quest:" .. name
    selectDungeon(name)
    ForeverDungeonJournalDB.lastMode = "quests"
    refreshQuests()
end
local settingsToggles = 0
X.ToggleSettingsPanel = function()
    settingsToggles = settingsToggles + 1
    local panel = rawget(_G, "ForeverDungeonJournalSettings")
    if not panel then
        panel = CreateFrame("Frame", "ForeverDungeonJournalSettings", UIParent, "BackdropTemplate")
        panel:SetBackdrop(STONE)
        panel:SetBackdropColor(0.10, 0.07, 0.04, 0.98)
        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.title:SetTextColor(1.00, 0.82, 0.27)
        panel:Hide()
    end
    panel:SetShown(not panel:IsShown())
end
def("ForeverDungeonJournal_Toggle", function()
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() and not frame.currentView then showHome() end
end)

local protectedChild
local function build()
    frame = CreateFrame("Frame", "ForeverDungeonJournalFrame", UIParent, "BackdropTemplate")
    frame:SetBackdrop(STONE)
    frame:SetBackdropBorderColor(0.47, 0.34, 0.16, 1)
    frame:SetSize(900, 600)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:Hide()
    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.backButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.backButton:SetScript("OnClick", function() showHome() end)
    local home = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    home:SetBackdrop(STONE)
    frame.homePanel = home
    frame.homeParchment = home:CreateTexture(nil, "BACKGROUND", nil, -2)
    frame.homeParchment:SetTexture("Interface\\QuestFrame\\QuestBG")
    frame.homeScroll = CreateFrame("ScrollFrame", "ForeverDungeonJournalHomeScroll", home, "UIPanelScrollFrameTemplate")
    frame.homeCardsContent = CreateFrame("Frame", nil, frame.homeScroll)
    local content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    content:SetBackdrop(STONE)
    content:Hide()
    frame.contentPanel = content
    -- (parchemin sans champ, comme celui de la page du chemin vers l'entrée)
    local loose = content:CreateTexture(nil, "BACKGROUND", nil, -2)
    loose:SetTexture("Interface\\QuestFrame\\QuestBG")
    frame.looseParchment_ = loose
    frame.dungeonTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.divider = content:CreateTexture(nil, "ARTWORK")
    frame.divider:SetColorTexture(0.47, 0.34, 0.16, 0.90)
    frame.veil = content:CreateTexture(nil, "ARTWORK")
    frame.veil:SetColorTexture(0, 0, 0, 0.42)
    frame.questObjectiveHeader = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.questObjectiveHeader:SetText("Objectif")
    frame.selectedQuestMeta = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.questText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.questText:SetTextColor(0.10, 0.065, 0.025)
    frame.questLeftPanel = CreateFrame("Frame", nil, content, "BackdropTemplate")
    frame.questContent = CreateFrame("Frame", nil, frame.questLeftPanel)
    frame.rarity = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.rarity:SetTextColor(0.12, 1, 0)
    -- un bouton protégé (comme son bouton de recherche de groupe) : Platyplus n'y touche pas
    protectedChild = CreateFrame("Button", nil, content, "SecureActionButtonTemplate")
    protectedChild.label = protectedChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    protectedChild.label:SetTextColor(1.00, 0.82, 0.27)
    applyTheme()
end
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", build)

---------------------------------------------------------------------------
-- Platyplus, version publique (ce que fait le packager : sans le bloc do-not-package)
---------------------------------------------------------------------------
local files, skip = {}, false
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    line = line:gsub("\r", "")
    if line == "#@do-not-package@" then skip = true end
    if not skip then
        local f = line:match("^([%w_%.\\]+%.lua)")
        if f then files[#files + 1] = f end
    end
    if line == "#@end-do-not-package@" then skip = false end
end

section("chargement (ADDON_LOADED) : l'addon séparé est déjà là, sa fenêtre pas encore")
local originals = { OpenBossPage = X.OpenBossPage, OpenQuestPage = X.OpenQuestPage, IsDungeonLocked = X.IsDungeonLocked,
    RefreshHomeCards = X.RefreshHomeCards, GetSelectedDungeon = X.GetSelectedDungeon }
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
check(#M.errors == 0, "chargement et Init sans erreur (" .. #M.errors .. ")")
if #M.errors > 0 then M.report() M.errors = {} end
local P, Skin, T = ns.DungeonPlus, ns.DungeonSkin, ns.THEME
check(ns.Dungeon == nil and not P.Bundled(), "pas de journal intégré")
check(P.Standalone() and P.Available() and P.Overlay() and P.Tunable(), "Standalone, Available, Overlay et Tunable : vrais")
check(Skin.active == true and Skin.external == X, "style Platyplus branché sur l'addon séparé")
local th = X.THEMES["The Deadmines"]
check(close(th.frame[1], T.bg[1]) and close(th.title[1], T.text[1]) and close(th.muted[3], T.dim[3]),
    "ses thèmes par donjon sont réécrits avant qu'il construise sa fenêtre")
check(not P.attached and rawget(_G, "ForeverDungeonJournalFrame") == nil, "fenêtre pas encore construite : Platyplus attend")
local replaced = {}
for name, fn in pairs(originals) do if X[name] ~= fn then replaced[#replaced + 1] = name end end
check(#replaced == 0, "aucune fonction de l'addon remplacée (" .. table.concat(replaced, ", ") .. ")")

---------------------------------------------------------------------------
section("connexion (PLAYER_LOGIN) : il construit sa fenêtre, Platyplus la prend en main à la création")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(1)
check(#M.errors == 0, "PLAYER_LOGIN sans erreur Lua")
if #M.errors > 0 then M.report() M.errors = {} end
local f = frame
check(P.attached == true and Skin.Ext.main == f, "Platyplus est branché sur ForeverDungeonJournalFrame")
check(f.ppWindow == true and f.ppBg ~= nil, "elle a le cadre des fenêtres Platyplus (fond arrondi, ombre)")
check(select(4, f:GetBackdropColor()) == 0 and select(4, f:GetBackdropBorderColor()) == 0, "son fond carré d'origine est transparent")
check(STONE.edgeSize == 1 and STONE.bgFile == "Interface\\Buttons\\WHITE8X8" and f.backdropInfo == STONE,
    "fond aplati sur place (liseré d'un pixel), le cadre garde la même table")
local r, g, b, a = f.homePanel:GetBackdropColor()
check(b > r and r < 0.2 and a == 0.96, "fond brun de l'accueil -> gris bleuté sombre, même opacité")
r, g, b, a = f.homePanel:GetBackdropBorderColor()
check(r == 1 and g == 1 and b == 1 and a < 0.2, "liseré bronze -> filet clair discret")
local dc = S(f.divider).color
check(dc[1] == 1 and dc[2] == 1 and dc[3] == 1 and close(dc[4], 0.10), "filet bronze posé à la construction -> filet clair")
check(S(f.veil).color[1] == 0 and S(f.veil).color[4] == 0.42, "voile noir gardé")
check(not f.homeParchment:IsShown() and not f.looseParchment_:IsShown(), "plus de parchemin (champ connu, et reconnu à son image)")
check(f.closeButton.ppSkinned == true, "croix de fermeture redessinée")
check(f.backButton.ppSkinned == true, "bouton « Donjons » en pastille Platyplus")
local tc = S(f.questText).textColor
check(close(tc[1], T.text[1]) and close(tc[3], T.text[3]), "encre sombre du parchemin -> texte clair")
tc = S(f.rarity).textColor
check(tc[1] == 0.12 and tc[2] == 1 and tc[3] == 0, "vert de qualité gardé")
tc = S(f.dungeonTitle).textColor
check(close(tc[1], T.text[1]), "titre doré -> texte clair de Platyplus")
local oh = f.questObjectiveHeader
check(oh.ppHeader and S(oh).text == "OBJECTIF" and close(S(oh).textColor[1], T.accent[1]) and oh.ppLine ~= nil,
    "titre de section : capitales bleues suivies d'un filet")
oh:SetText("Objectif")
oh:SetTextColor(1, 1, 1)
check(S(oh).text == "OBJECTIF" and close(S(oh).textColor[3], T.accent[3]), "  il le reste quand le journal le réécrit")
oh:Hide()
check(not S(oh.ppLine).shown, "  le filet se cache avec son titre")
oh:Show()
tc = S(protectedChild.label).textColor
check(tc[1] == 1.00 and tc[2] == 0.82 and not protectedChild.ppSkinned, "bouton protégé du journal : pas touché")

---------------------------------------------------------------------------
section("ouverture : accueil, liste des donjons, « À ton niveau »")
P.Toggle()
M.advance(0.5)
check(#M.errors == 0, "ouverture sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
check(f:IsShown() and f.currentView == "home", "/pp donjons ouvre le journal de l'addon séparé, sur l'accueil")
local side = rawget(_G, "PlatyplusDungeonList")
check(side ~= nil and side:IsShown() and S(side).parent == f, "colonne « Donjons » collée à gauche de sa fenêtre")
check(S(f.ppBg.tl).points[1][4] == -P.SIDE_W, "le cadre Platyplus englobe la colonne (une seule fenêtre)")
local rows, home = {}, nil
for _, fr in ipairs(M.allFrames) do
    if rawget(fr, "dungeon") and rawget(fr, "chipText") and fr:IsShown() then rows[fr.dungeon] = fr end
    if rawget(fr, "home") == true then home = fr end
end
local n = 0
for _ in pairs(rows) do n = n + 1 end
check(n == #X.ORDER, "une ligne par donjon (" .. n .. ")")
local dm, soon, vault = rows["The Deadmines"], rows["Excavation Site"], rows["Sealed Vault"]
check(dm and dm.fit == "good" and S(dm.name).text == "Les Mortemines", "Mortemines (17-26) : à ton niveau, nom traduit par l'addon")
check(dm and dm.done == 1 and dm.total == 2 and S(dm.progress).text == "1/2", "quêtes : 1 faite sur 2 (la répétable ne compte pas)")
tc = soon and S(soon.chipText).textColor
check(soon and soon.fit == "soon" and close(tc[1], T.gold[1]) and close(tc[3], T.gold[3]),
    "« bientôt » en or : la colonne est à Platyplus, le style ne la reconvertit pas")
check(vault and vault.locked == true, "donjon verrouillé (mode RPG) : cadenas")
local dmCard, soonCard = cards[2], cards[3]
check(dmCard.ppFit and dmCard.ppFit:IsShown() and S(dmCard.ppFit.text).text == "À ton niveau", "carte des Mortemines : pastille « À ton niveau »")
check(close(S(dmCard.meta).textColor[2], T.good[2]), "  et « LV 17-26 » en vert")
tc = S(soonCard.meta).textColor
check(S(soonCard.ppFit.text).text == "Bientôt" and close(tc[1], T.gold[1]) and close(tc[3], T.gold[3]),
    "carte « Bientôt » : tranche de niveau en or (couleur de Platyplus posée telle quelle)")
check(not (cards[1].ppFit and cards[1].ppFit:IsShown()), "donjon dépassé : pas de pastille")
r, g, b = dmCard:GetBackdropColor()
check(b > r and r < 0.2, "cartes créées à l'ouverture : fond converti")
local gc = S(dmCard.glow).color
check(close(gc[1], T.accent[1]) and close(gc[3], T.accent[3]) and gc[4] == 0.30, "  lueur dorée -> bleu Platyplus (prise en main à la création)")
local hl = dmCard:GetHighlightTexture()
check(S(hl).texture == "color" and S(hl).color[4] == 0.06, "  surbrillance dorée de Blizzard -> voile clair")
check(CARD.edgeSize == 1, "  fond des cartes aplati")

---------------------------------------------------------------------------
section("clic dans la liste")
M.fire(dm, "OnClick", "LeftButton")
M.advance(0.3)
check(opened[#opened] == "boss:The Deadmines" and f.currentView == "dungeon", "un donjon s'ouvre par FDJ.OpenBossPage")
check(dm.selected == true and not home.selected, "sa ligne est surlignée, « Accueil » ne l'est plus")
r, g, b = f.contentPanel:GetBackdropColor()
check(close(r, T.panel[1]) and close(b, T.panel[3]), "page du donjon : fond du thème réécrit")
ForeverDungeonJournalDB.lastMode = "quests"
M.fire(rows["Gnomeregan"], "OnClick", "LeftButton")
M.advance(0.3)
check(opened[#opened] == "quest:Gnomeregan", "depuis l'onglet Quêtes : FDJ.OpenQuestPage (on reste sur les quêtes)")
check(rows["Gnomeregan"].selected and not dm.selected, "la sélection suit")
local count = #opened
M.fire(vault, "OnClick", "LeftButton")
M.advance(0.3)
check(#opened == count and lockedNotice == "Sealed Vault", "donjon verrouillé : rien ne s'ouvre, le journal dit pourquoi")
M.fire(rows["Coming Soon"], "OnClick", "LeftButton")
check(#opened == count, "donjon pas encore connu (aperçu) : rien ne s'ouvre")
check(#M.errors == 0, "clics sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end

section("onglet Quêtes : niveau requis, quête sélectionnée, objectif rempli")
local bars, red = 0, 0
for i, row in ipairs(questRows) do
    if row.ppBar and S(row.ppBar).shown then bars = bars + 1 end
    local c = S(row.meta).textColor
    if close(c[1], T.bad[1]) and close(c[2], T.bad[2]) then red = red + 1 end
end
check(bars == 1 and questRows[2].ppBar and S(questRows[2].ppBar).shown, "barre bleue sur la quête sélectionnée (ForeverDungeonJournalDB.lastQuest)")
check(red == 1, "niveau requis en rouge quand il dépasse ton niveau (31 > 24)")
check(S(f.questText).text:find("|cff6e5c40", 1, true) == nil and S(f.questText).text:find("Bandeaux : 10/10", 1, true) ~= nil,
    "objectif rempli : le brun du parchemin écrit dans le texte devient le vert « fait »")
refreshQuests()
M.advance(0.3)
red = 0
for _, row in ipairs(questRows) do
    local c = S(row.meta).textColor
    if close(c[1], T.bad[1]) and close(c[2], T.bad[2]) then red = red + 1 end
end
check(red == 1, "  et le reste quand le journal redessine sa liste")

section("« Accueil »")
M.fire(home, "OnClick", "LeftButton")
M.advance(0.3)
check(f.currentView == "home" and home.selected and not rows["Gnomeregan"].selected, "ramène aux cartes par le bouton « Donjons » du journal")

---------------------------------------------------------------------------
section("réglages")
ns:Set("dungeonList", false)
M.advance(0.2)
check(not side:IsShown(), "« Liste des donjons » éteint : la colonne disparaît")
ns:Set("dungeonList", true)
M.advance(0.2)
check(side:IsShown(), "rallumé : elle revient")
ns:Set("dungeonFit", false)
M.advance(0.2)
check(not dmCard.ppFit:IsShown(), "« À ton niveau » éteint : plus de pastille")
check(close(S(dmCard.meta).textColor[1], T.text[1]), "  la tranche de niveau reprend la couleur du journal (convertie par le style)")
ns:Set("dungeonFit", true)
M.advance(0.2)
check(dmCard.ppFit:IsShown(), "rallumé : elle revient")

section("fenêtre ouverte à la demande, et filet de sécurité")
X.ToggleSettingsPanel()
M.advance(0.2)
local panel = rawget(_G, "ForeverDungeonJournalSettings")
check(settingsToggles == 1 and panel and panel:IsShown(), "ses réglages s'ouvrent (sa fonction tourne toujours)")
check(panel and panel.ppWindow == true and select(4, panel:GetBackdropColor()) == 0, "  avec le cadre des fenêtres Platyplus")
check(panel and close(S(panel.title).textColor[1], T.text[1]), "  et son titre doré en clair")
check(P.OpenOptions() == true and settingsToggles == 2, "« Ses réglages » (onglet Donjons, /pp donjons options) appelle FDJ.ToggleSettingsPanel")
-- un cadre créé ailleurs puis accroché à la fenêtre : repris par le passage léger
local stray = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
M.impl.SetParent(stray, f.contentPanel)
table.insert(S(f.contentPanel).frames, stray)
M.advance(0.5)
stray:SetBackdrop(CARD)
stray:SetBackdropColor(0.16, 0.12, 0.07, 0.96)
r, g, b = stray:GetBackdropColor()
check(b > r and r < 0.2, "cadre accroché après coup : repris en main (fond converti)")

---------------------------------------------------------------------------
section("onglet Donjons, état, menu de l'icône")
local Pages = ns.Pages
local idx
for i = 1, Pages:Count() do if Pages:GetInfo(i).id == "dungeons" then idx = i end end
ns.UI:Open(); ns.UI:SelectTab(idx); M.advance(0.3)
local page = ns.UI.pages[idx]
check(page ~= nil and #M.errors == 0, "l'onglet Donjons se construit sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
local keys = {}
local function collect(w)
    if type(w) ~= "table" then return end
    if w.opts and w.opts.key then keys[w.opts.key] = true end
    for _, child in ipairs(w.widgets or {}) do collect(child) end
end
collect(page)
check(keys.dungeonList and keys.dungeonFit and keys.dungeonSkin, "les trois réglages y sont de nouveau (liste, « À ton niveau », style)")
ns.UI:Close()
local status = table.concat(P:Status(), "\n")
check(status:find("installé à part", 1, true) and status:find("9.9.9", 1, true), "état : l'addon séparé et sa version")
check(status:find("allumé sur l'addon séparé", 1, true) ~= nil, "  style Platyplus : allumé sur l'addon séparé")
check(#P.Health() == 0 and status:find("surcharge incomplète", 1, true) == nil, "  rien ne manque chez l'addon : pas d'avis")
check(not P.Verified("9.9.9") and P.Verified("2.0.1") and status:find("pas encore vérifiée", 1, true) ~= nil,
    "  version inconnue de Platyplus : dite « pas encore vérifiée »")
local stats = Skin.Ext.stats
check(stats.taken >= 20 and stats.calls > stats.taken and status:find("suivi des cadres du journal", 1, true) ~= nil,
    "  coût du suivi des cadres : " .. stats.taken .. " pris en main sur " .. stats.calls .. " créés (" .. math.floor(stats.ms + 0.5) .. " ms)")
-- le hook de CreateFrame ne s'occupe que du journal : un cadre du jeu ou d'un autre addon n'est pas compté
local takenBefore = stats.taken
CreateFrame("Frame", "SomeOtherAddonFrame", UIParent, "BackdropTemplate")
CreateFrame("Frame", nil, rawget(_G, "SomeOtherAddonFrame"))
CreateFrame("Frame", "ForeverDungeonJournalLike", nil)
check(stats.taken == takenBefore, "  cadres étrangers au journal : écartés sans rien faire")
ns.Launcher:ShowMenu()
check(ns.Launcher.journalRow ~= nil, "menu de l'icône : ligne « Journal des donjons »")
ns.Launcher:HideMenu()

---------------------------------------------------------------------------
section("l'addon change : ce qui manque ne se fait pas, sans erreur, et Platyplus le dit une fois")
f:Hide()
local before = #M.printed
f:Show()
M.advance(0.2)
check(#M.printed == before, "tant que rien ne manque : aucun message à l'ouverture")
X.OpenBossPage, X.OpenQuestPage, X.RPGLockedNotice = nil, nil, nil
M.fire(dm, "OnClick", "LeftButton")
M.fire(vault, "OnClick", "LeftButton")
M.advance(0.3)
f.backButton = nil
M.fire(home, "OnClick", "LeftButton")
f.homeCardsContent, f.homeScroll, f.questContent, f.selectedQuestMeta = nil, nil, nil, nil
X.RefreshHomeCards()
pcall(X.UpdateRPGHeader, f)
X.GetSelectedDungeon, X.HiddenDungeons, X.IsDungeonLocked, X.LocalizeDungeonName = nil, nil, nil, nil
f:Hide(); f:Show()
M.advance(0.5)
check(#M.errors == 0, "aucune erreur Lua (" .. #M.errors .. ")")
if #M.errors > 0 then M.report() M.errors = {} end
local said = table.concat(M.printed, "\n", before + 1)
check(#M.printed == before + 1 and said:find("/pp donjons etat", 1, true) ~= nil, "une seule ligne dans le chat : « le journal a changé »")
f:Hide(); f:Show()
M.advance(0.2)
check(#M.printed == before + 1, "  pas répétée à l'ouverture suivante")
local missing = table.concat(P.Health(), " ")
check(missing:find("FDJ.OpenBossPage", 1, true) and missing:find("backButton", 1, true) and missing:find("homeCardsContent", 1, true),
    "Plus.Health() nomme ce qui manque (" .. #P.Health() .. " noms)")
check(table.concat(P:Status(), "\n"):find("surcharge incomplète", 1, true) ~= nil, "/pp donjons etat le dit aussi")
check(side:IsShown(), "la colonne reste affichée")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
