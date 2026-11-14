-- Test : la surcharge sur le VRAI addon DungeonJournal d'Exehn, s'il est installé à côté de Platyplus
-- (AddOns\ForeverDungeonJournal, ou le dossier donné par la variable d'environnement PLATYPLUS_DJ_DIR). L'addon
-- n'est pas dans le dépôt de Platyplus : sans lui, le test ne fait rien (test_surcharge.lua couvre le mécanisme
-- avec un faux addon). Sert surtout à voir, après une mise à jour de l'addon, si Platyplus s'y branche toujours.
-- Version publique de Platyplus (sans le bloc do-not-package), guerrier 24 de l'Alliance.
-- Usage : python -I dev\lua.py run dev\test_surcharge_reel.lua <dossier Platyplus> <dossier dev>
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

local DJ_DIR = os.getenv("PLATYPLUS_DJ_DIR")
if not DJ_DIR or DJ_DIR == "" then DJ_DIR = ADDON_DIR .. "\\..\\ForeverDungeonJournal" end
local tocFile = io.open(DJ_DIR .. "\\ForeverDungeonJournal.toc", "rb")
if not tocFile then
    M.realPrint("  (addon ForeverDungeonJournal absent de " .. DJ_DIR .. " : rien à essayer)")
    M.realPrint("TOUT EST BON")
    return
end
local toc = tocFile:read("*a"):gsub("\r", "")
tocFile:close()
local version = toc:match("## Version:%s*(%S+)") or "?"

dofile(DEV .. "\\preview_dungeon.lua")(M, def, { level = 24, done = { [214] = true } })
def("C_AddOns", {
    IsAddOnLoaded = function(name) return name == "ForeverDungeonJournal" end,
    GetAddOnMetadata = function(_, field) return field == "Version" and version or nil end,
})
def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = tbl[name]
    if type(orig) ~= "function" then error("hooksecurefunc : " .. tostring(name) .. " n'est pas une fonction") end
    rawset(tbl, name, function(...) local r = { orig(...) }; hook(...); return unpack(r) end)
end)
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
def("ForeverDungeonJournalCharacterDB", { journalMode = "gamer" })

---------------------------------------------------------------------------
section("l'addon DungeonJournal " .. version .. " (chargé avant Platyplus)")
local djNS, djFiles, djErrors = {}, 0, {}
for line in toc:gmatch("[^\n]+") do
    local file = line:match("^([%w_%.\\]+%.lua)")
    if file then
        djFiles = djFiles + 1
        local chunk, err = loadfile(DJ_DIR .. "\\" .. file)
        local ok = chunk ~= nil
        if chunk then ok, err = pcall(chunk, "ForeverDungeonJournal", djNS) end
        if not ok then djErrors[#djErrors + 1] = file .. " : " .. tostring(err) end
    end
end
check(#djErrors == 0, djFiles .. " fichiers chargés dans le simulateur" .. (djErrors[1] and (" — " .. djErrors[1]:sub(1, 200)) or ""))
local X = rawget(_G, "ForeverDungeonJournal_NS")
check(type(X) == "table" and type(X.DB) == "table" and type(X.ORDER) == "table" and #X.ORDER >= 30,
    "_G.ForeverDungeonJournal_NS : ses données (" .. (X and X.ORDER and #X.ORDER or 0) .. " donjons)")
check(type(rawget(_G, "ForeverDungeonJournal_Toggle")) == "function", "ForeverDungeonJournal_Toggle : sa fonction d'ouverture")
-- ce dont la surcharge se sert (une absence = la partie correspondante ne se fait plus)
local missing = {}
for _, name in ipairs({ "THEMES", "HiddenDungeons", "IsDungeonLocked", "IsQuestFinished", "LocalizeDungeonName", "L",
    "GetSelectedDungeon", "RefreshHomeCards", "UpdateRPGHeader", "ToggleSettingsPanel", "ToggleFavouritesWindow" }) do
    if X == nil or X[name] == nil then missing[#missing + 1] = name end
end
check(#missing == 0, "fonctions et données attendues sur son espace de noms" .. (#missing > 0 and (" — manquent : " .. table.concat(missing, ", ")) or ""))

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
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(4)
check(#M.errors == 0, "Platyplus : chargement et connexion sans erreur (" .. #M.errors .. ")")
if #M.errors > 0 then M.report() M.errors = {} end

---------------------------------------------------------------------------
section("Platyplus branché sur sa fenêtre")
local P, Skin, T = ns.DungeonPlus, ns.DungeonSkin, ns.THEME
local f = rawget(_G, "ForeverDungeonJournalFrame")
check(f ~= nil, "ForeverDungeonJournalFrame construite à la connexion")
check(P.Overlay() and P.attached == true and Skin.external == X and Skin.Ext.main == f, "liste et style branchés")
-- le contrat de la surcharge (DungeonJournalPlus.lua : CONTRACT_NS, CONTRACT_FRAME) : tout doit être là
local health = P.Health()
check(#health == 0, "Plus.Health() : rien ne manque chez l'addon" .. (#health > 0 and (" — manquent : " .. table.concat(health, ", ")) or ""))
check(P.Verified(version), "version " .. version .. " dans Plus.VERIFIED (sinon : l'y ajouter une fois ce test vert)")
missing = {}
for _, key in ipairs({ "homePanel", "contentPanel", "homeCardsContent", "homeScroll", "backButton", "closeButton",
    "dungeonTitle", "questsTab", "questContent", "selectedQuestMeta", "questObjectiveHeader", "questParchment",
    "homeParchment" }) do
    if not (f and f[key]) then missing[#missing + 1] = key end
end
check(#missing == 0, "champs attendus sur sa fenêtre" .. (#missing > 0 and (" — manquent : " .. table.concat(missing, ", ")) or ""))
check(type(X.OpenBossPage) == "function" and type(X.OpenQuestPage) == "function",
    "FDJ.OpenBossPage et FDJ.OpenQuestPage (posées quand il construit sa fenêtre) : ouvrir un donjon depuis la liste")
check(f.ppWindow == true and select(4, f:GetBackdropColor()) == 0, "cadre des fenêtres Platyplus, fond d'origine transparent")
check(f.closeButton and f.closeButton.ppSkinned and f.backButton and f.backButton.ppSkinned, "croix et bouton « Donjons » redessinés")
check(f.questParchment and not f.questParchment:IsShown() and f.homeParchment and not f.homeParchment:IsShown(), "plus de parchemin")

section("accueil, liste, pastilles")
P.Toggle()
M.advance(1)
check(f:IsShown() and f.currentView == "home" and #M.errors == 0, "ouverture sur l'accueil, sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
local side = rawget(_G, "PlatyplusDungeonList")
check(side ~= nil and side:IsShown(), "colonne « Donjons »")
local rows, home, nrows = {}, nil, 0
for _, fr in ipairs(M.allFrames) do
    if rawget(fr, "dungeon") and rawget(fr, "chipText") and fr:IsShown() then rows[fr.dungeon] = fr; nrows = nrows + 1 end
    if rawget(fr, "home") == true then home = fr end
end
local cards, badges = 0, 0
for _, card in ipairs({ f.homeCardsContent:GetChildren() }) do
    if rawget(card, "dungeonName") and card:IsShown() then
        cards = cards + 1
        if card.ppFit and card.ppFit:IsShown() then badges = badges + 1 end
    end
end
check(nrows == cards and nrows >= 30, "une ligne par carte de l'accueil (" .. nrows .. " lignes, " .. cards .. " cartes)")
check(badges >= 3, "pastilles « À ton niveau » / « Bientôt » sur l'accueil (" .. badges .. ")")
local dm = rows["The Deadmines"]
check(dm and dm.fit == "good" and dm.done == 1 and dm.total >= 5, "Mortemines : à ton niveau, 1 quête faite sur " .. tostring(dm and dm.total))

section("un donjon, ses quêtes, retour à l'accueil")
M.fire(dm, "OnClick", "LeftButton")
M.advance(0.5)
check(f.currentView == "dungeon" and X.GetSelectedDungeon() == "The Deadmines" and dm.selected == true, "clic : les Mortemines s'ouvrent, la ligne est surlignée")
M.fire(f.questsTab, "PreClick")
M.fire(f.questsTab, "OnClick", "LeftButton")
M.advance(0.5)
local oh = f.questObjectiveHeader
check(oh and oh.ppHeader and S(oh).text == S(oh).text:upper() and close(S(oh).textColor[1], T.accent[1]), "titres de sections en capitales bleues : " .. tostring(oh and S(oh).text))
local qrows, bars = 0, 0
for _, row in ipairs({ f.questContent:GetChildren() }) do
    if rawget(row, "questIndex") and row:IsShown() then
        qrows = qrows + 1
        if row.ppBar and S(row.ppBar).shown then bars = bars + 1 end
    end
end
check(qrows >= 5 and bars == 1, "barre bleue sur la quête sélectionnée (" .. qrows .. " quêtes, " .. bars .. " barre)")
local gnome = rows["Gnomeregan"]
M.fire(gnome, "OnClick", "LeftButton")
M.advance(0.5)
check(X.GetSelectedDungeon() == "Gnomeregan" and ForeverDungeonJournalDB.lastMode == "quests", "autre donjon depuis l'onglet Quêtes : on reste sur les quêtes")
local red = 0
for _, row in ipairs({ f.questContent:GetChildren() }) do
    if rawget(row, "questIndex") and row:IsShown() and row.meta then
        local c = S(row.meta).textColor
        if c and close(c[1], T.bad[1]) and close(c[2], T.bad[2]) then red = red + 1 end
    end
end
check(red >= 1, "niveau requis en rouge quand il dépasse ton niveau (" .. red .. ")")
M.fire(home, "OnClick", "LeftButton")
M.advance(0.5)
check(f.currentView == "home" and home.selected, "« Accueil » ramène aux cartes")
check(#M.errors == 0, "navigation sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end

section("couleurs : plus de brun, de bronze ni d'or du journal")
local function warm(c)
    local h, s, v = Skin.HSV(c[1], c[2], c[3])
    return s >= 0.25 and h >= 12 and h <= 65 and v > 0.12 and (c[4] or 1) > 0.05
end
local stats = { frames = 0, bg = 0, bgWarm = 0, edgeWarm = 0, tex = 0, texWarm = 0, parchments = 0 }
local function walk(fr)
    if rawget(fr, "ppOwn") then return end
    stats.frames = stats.frames + 1
    local s = S(fr)
    if s.backdropInfo and s.backdropColor then
        stats.bg = stats.bg + 1
        if warm(s.backdropColor) then stats.bgWarm = stats.bgWarm + 1 end
        if s.backdropBorderColor and warm(s.backdropBorderColor) then stats.edgeWarm = stats.edgeWarm + 1 end
    end
    for _, r in ipairs({ fr:GetRegions() }) do
        local rs = S(r)
        if rs.kind == "Texture" and rs.shown ~= false then
            if rs.texture == "color" and rs.color then
                stats.tex = stats.tex + 1
                if warm(rs.color) then stats.texWarm = stats.texWarm + 1 end
            elseif type(rs.texture) == "string" and rs.texture:find("QuestBG", 1, true) then
                stats.parchments = stats.parchments + 1
            end
        end
    end
    for _, c in ipairs({ fr:GetChildren() }) do walk(c) end
end
walk(f)
check(stats.bg >= 50 and stats.bgWarm == 0 and stats.edgeWarm == 0, "fonds et liserés : " .. stats.bgWarm .. " + " .. stats.edgeWarm .. " restés chauds sur " .. stats.bg)
check(stats.tex >= 300 and stats.texWarm == 0, "aplats : " .. stats.texWarm .. " restés chauds sur " .. stats.tex)
check(stats.parchments == 0, "parchemins visibles : " .. stats.parchments)

section("ses autres fenêtres, réglages de Platyplus")
local windows = 0
for _, step in ipairs({ { "ToggleSettingsPanel", nil, "ForeverDungeonJournalSettings" },
    { "ToggleFavouritesWindow", f, "ForeverDungeonJournalFavourites" } }) do
    local fn = X[step[1]]
    local ok, err = true, nil
    if type(fn) == "function" then ok, err = pcall(fn, step[2]) end
    M.advance(0.3)
    local w = rawget(_G, step[3])
    check(ok and #M.errors == 0, step[1] .. " sans erreur" .. (ok and "" or (" : " .. tostring(err):sub(1, 200))))
    if #M.errors > 0 then M.report() M.errors = {} end
    if w then
        check(w.ppWindow == true, "  " .. step[3] .. " : cadre des fenêtres Platyplus")
        windows = windows + 1
        w:Hide()
    end
end
check(windows >= 1, "fenêtres secondaires habillées (" .. windows .. ")")
ns:Set("dungeonList", false)
M.advance(0.3)
check(not side:IsShown(), "« Liste des donjons » éteint : la colonne disparaît")
ns:Set("dungeonList", true)
M.advance(0.3)
check(side:IsShown() and #M.errors == 0, "rallumé : elle revient")
if #M.errors > 0 then M.report() M.errors = {} end

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
