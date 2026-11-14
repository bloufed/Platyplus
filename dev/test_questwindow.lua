-- Test de la fenêtre de quête Platyplus (QuestWindow.lua, Windows.lua) dans le simulateur, en mode strict.
-- Reproduit ce que fait Forever : GossipFrame et QuestFrame (panneaux Greeting / Detail / Progress / Reward) ouverts
-- par le jeu, placés par le gestionnaire de panneaux avec SetPoint, boutons Accepter / Continuer / Terminer,
-- QuestInfoItem_OnClick pour le choix de récompense, QUEST_ITEM_UPDATE qui efface ce choix.
-- Usage : python -I dev\lua.py run dev\test_questwindow.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

-- hooksecurefunc réel (le simulateur n'en fait rien) : fonctions globales et méthodes de cadres
def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = tbl[name]
    rawset(tbl, name, function(...)
        local results = { orig(...) }
        hook(...)
        return unpack(results)
    end)
end)
M.impl.SetText = function(f, t) S(f).text = t end
M.impl.GetText = function(f) return S(f).text end
M.impl.IsClampedToScreen = function(f) return S(f).clamped == true end
M.impl.SetClampedToScreen = function(f, v) S(f).clamped = v and true or false end

---------------------------------------------------------------------------
-- Monde simulé
---------------------------------------------------------------------------
local items = {
    [2]   = { name = "Casque usé", q = 2, ilvl = 20, equip = "INVTYPE_HEAD", class = 4, sub = 1, price = 500 },
    [3]   = { name = "Casque meilleur", q = 3, ilvl = 40, equip = "INVTYPE_HEAD", class = 4, sub = 1, price = 900 },
    [30]  = { name = "Gemme chère", q = 4, ilvl = 1, equip = "", class = 3, sub = 0, price = 8000 },
    [40]  = { name = "Potion de soins", q = 1, ilvl = 1, equip = "", class = 0, sub = 0, price = 25 },
    [50]  = { name = "Peau de loup", q = 1, ilvl = 1, equip = "", class = 12, sub = 0, price = 0 },
    [100] = { name = "Casque équipé", q = 3, ilvl = 30, equip = "INVTYPE_HEAD", class = 4, sub = 1, price = 0 },
}
local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. items[id].name .. "]|h|r" end
local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end
def("C_Item", {
    GetItemInfo = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        return it.name, linkOf(id), it.q, it.ilvl, 1, "Armure", "Plaques", 1, it.equip, 1000 + id, it.price, it.class, it.sub, 1
    end,
    GetItemInfoInstant = function(link)
        local id = idOf(link) or tonumber(link); local it = items[id]
        if not it then return nil end
        return id, "x", "y", it.equip, 1000 + id, it.class, it.sub
    end,
    GetDetailedItemLevelInfo = function(link) local it = items[idOf(link)]; return it and it.ilvl end,
    GetItemNameByID = function(id) return items[id] and items[id].name end,
    GetItemStats = function() return {} end,
    RequestLoadItemDataByID = function() end,
})
def("INVTYPE_HEAD", "Tête")
def("GetInventoryItemLink", function(unit, slot) if slot == 1 then return linkOf(100) end end)
def("C_MerchantFrame", { IsSellAllJunkEnabled = function() return true end, GetNumJunkItems = function() return 0 end })
def("UnitName", function(unit)
    if unit == "player" then return "Leo" end
    if unit == "npc" or unit == "questnpc" then return "Garde Thomas" end
end)
def("UnitExists", function(unit) return unit == "npc" or unit == "questnpc" or unit == "player" end)
local portraits = 0
def("SetPortraitTexture", function(tex, unit) portraits = portraits + 1; tex:SetTexture("portrait:" .. unit) end)
def("IsModifiedClick", function() return M.shift == true end)
local linked
def("HandleModifiedItemClick", function(link) linked = link; return true end)

-- discussion
local gossip = {
    text = "Salut, voyageur. Les loups rôdent près de la ferme.",
    available = { { title = "Les loups de la ferme", questID = 101, isTrivial = false } },
    active = { { title = "Le colis perdu", questID = 102, isComplete = true } },
    options = {
        { name = "Je voudrais acheter quelque chose.", icon = 132060, orderIndex = 2, status = 0 },
        { name = "Où est l'auberge ?", icon = 132053, orderIndex = 1, status = 0 },
    },
}
local selected = {}
def("C_GossipInfo", {
    GetText = function() return gossip.text end,
    GetAvailableQuests = function() return gossip.available end,
    GetActiveQuests = function() return gossip.active end,
    GetOptions = function()
        local copy = {}
        for i, o in ipairs(gossip.options) do copy[i] = o end
        return copy
    end,
    SelectAvailableQuest = function(id) selected[#selected + 1] = "available:" .. id end,
    SelectActiveQuest = function(id) selected[#selected + 1] = "active:" .. id end,
    SelectOptionByIndex = function(i) selected[#selected + 1] = "option:" .. i end,
    CloseGossip = function() end,
})

-- quête affichée
local quest = {
    id = 101, title = "Les loups de la ferme", text = "Les loups dévorent nos poules. Rapporte-moi 5 peaux de loup.",
    objectives = "Rapporter 5 Peaux de loup au garde Thomas.", progress = "As-tu les peaux ?",
    reward = "Merci, la ferme est sauvée !", choices = { 2, 3, 30 }, rewards = { 40 }, money = 1250, xp = 850,
    required = { { 50, 5 } }, completable = false,
}
def("GetQuestID", function() return quest.id end)
def("GetTitleText", function() return quest.title end)
def("GetQuestText", function() return quest.text end)
def("GetObjectiveText", function() return quest.objectives end)
def("GetProgressText", function() return quest.progress end)
def("GetRewardText", function() return quest.reward end)
def("GetNumQuestChoices", function() return #quest.choices end)
def("GetNumQuestRewards", function() return #quest.rewards end)
def("GetNumQuestItems", function() return #quest.required end)
def("GetRewardMoney", function() return quest.money end)
def("GetRewardXP", function() return quest.xp end)
def("GetQuestMoneyToGet", function() return 0 end)
def("IsQuestCompletable", function() return quest.completable end)
def("GetQuestItemInfo", function(kind, i)
    local id, count
    if kind == "choice" then id = quest.choices[i] elseif kind == "reward" then id = quest.rewards[i]
    else id, count = quest.required[i][1], quest.required[i][2] end
    local it = items[id]
    return it.name, 1000 + id, count or 1, it.q, true, id
end)
def("GetQuestItemLink", function(kind, i)
    local id = kind == "choice" and quest.choices[i] or (kind == "reward" and quest.rewards[i] or quest.required[i][1])
    return linkOf(id)
end)
local questInfo = { itemChoice = 0 }
def("QuestInfoFrame", questInfo)
local choiceButtons = {}
for i = 1, 4 do
    local b = CreateFrame("Button", nil, UIParent)
    b.type = "choice"
    b:SetID(i)
    choiceButtons[i] = b
end
def("QuestInfoRewardsFrame", { RewardButtons = choiceButtons })
def("QuestInfoItem_OnClick", function(self) questInfo.itemChoice = self:GetID() end)

-- fenêtres du jeu
local function frame(name, parent) local f = CreateFrame("Frame", name, parent or UIParent); f:Hide(); def(name, f); return f end
local questFrame = frame("QuestFrame")
local panels = {}
for _, n in ipairs({ "Greeting", "Detail", "Progress", "Reward" }) do panels[n] = frame("QuestFrame" .. n .. "Panel", questFrame) end
local gossipFrame = frame("GossipFrame")
local clicks = {}
local function button(name, text)
    local b = CreateFrame("Button", name, questFrame)
    b:SetText(text)
    b:SetScript("OnClick", function() clicks[#clicks + 1] = name .. ":" .. tostring(questInfo.itemChoice) end)
    def(name, b)
    return b
end
local accept = button("QuestFrameAcceptButton", "Accepter")
button("QuestFrameDeclineButton", "Refuser")
local continue = button("QuestFrameCompleteButton", "Continuer")
button("QuestFrameGoodbyeButton", "Au revoir")
button("QuestFrameCompleteQuestButton", "Terminer la quête")
button("QuestFrameGreetingGoodbyeButton", "Au revoir")

-- comme le gestionnaire de panneaux du jeu : ShowUIPanel place la fenêtre à gauche
def("ShowUIPanel", function(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Show()
end)

local function openPanel(name, event)
    for n, p in pairs(panels) do if n ~= name then p:Hide() end end
    ShowUIPanel(questFrame)
    panels[name]:Show()
    if event then M.fireEvent(event) end
    M.advance(0.1)
end
local function closeQuest()
    questFrame:Hide()
    for _, p in pairs(panels) do p:Hide() end
    M.fireEvent("QUEST_FINISHED")
    M.advance(0.3)
end

---------------------------------------------------------------------------
-- Chargement de tout l'addon, comme le jeu
---------------------------------------------------------------------------
M.enableStrict()
local files = {}
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    local f = line:match("^([%w_%.]+%.lua)%s*$")
    if f then files[#files + 1] = f end
end
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
PlatyplusDB = { questCards = false }
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(1)

local QW = ns.QuestWindow
local function win() return rawget(_G, "PlatyplusQuestWindow") end
local function winShown() local f = win(); return f ~= nil and S(f).shown end
local function texts()
    local out = {}
    for i = 1, QW.used.text do out[#out + 1] = tostring(S(QW.pools.text[i]).text) end
    return table.concat(out, "\n")
end
local function rows() local t = {} for i = 1, QW.used.row do t[i] = QW.pools.row[i] end return t end
local function tiles() local t = {} for i = 1, QW.used.tile do t[i] = QW.pools.tile[i] end return t end
local function label(b) return tostring(S(b.label).text) end
local function offscreen(f) local p = S(f).points[1]; return p ~= nil and p[4] == -6000 and S(f).alpha == 0 end

section("réglages et fenêtres du jeu cachées")
check(QW and QW.Sync and QW.Apply and QW.Choose and QW.Complete, "ns.QuestWindow : Sync, Apply, Choose, Complete")
check(ns.db.questWindow == true and ns.db.questWinScale == 1.1, "active par défaut, taille 110 %")
check(offscreen(questFrame) and offscreen(gossipFrame), "QuestFrame et GossipFrame hors de l'écran, transparentes")
check(win() == nil, "rien de construit avant le premier dialogue")

section("discussion avec un PNJ")
ShowUIPanel(gossipFrame)
M.fireEvent("GOSSIP_SHOW")
M.advance(0.3)
check(winShown(), "fenêtre de quête affichée")
check(offscreen(gossipFrame), "GossipFrame replacée hors de l'écran après ShowUIPanel (crochet sur SetPoint)")
check(S(win().title).text == "Garde Thomas", "nom du PNJ dans le bandeau (" .. tostring(S(win().title).text) .. ")")
check(portraits > 0, "portrait du PNJ")
check(texts():find("Les loups rôdent", 1, true) ~= nil, "texte du PNJ")
local r = rows()
check(#r == 4, "4 lignes : 1 quête proposée, 1 en cours, 2 options (" .. #r .. ")")
check(label(r[1]) == "Les loups de la ferme", "quête proposée en premier")
check(label(r[2]):find("terminée", 1, true) ~= nil, "quête en cours marquée terminée")
check(label(r[3]) == "Où est l'auberge ?" and label(r[4]) == "Je voudrais acheter quelque chose.",
    "options dans l'ordre du jeu (orderIndex)")
local function key(row) return S(row.key).shown and S(row.key.text).text or nil end
check(key(r[2]) == "F", "F sur la quête terminée (ce que fait la touche) (" .. tostring(key(r[2])) .. ")")
check(key(r[1]) == "1" and key(r[3]) == "2" and key(r[4]) == "3", "1, 2, 3 sur les autres lignes dans l'ordre")
check(M.overrides["1"] == "CLICK PlatyplusChoice1:LeftButton" and M.overrides["3"] == "CLICK PlatyplusChoice3:LeftButton",
    "touches 1 à 9 liées pendant le dialogue")
check(M.overrides["F"] == "CLICK PlatyplusAdvance:LeftButton", "F fait avancer le dialogue")
PlatyplusChoice2:Click()
check(selected[#selected] == "option:1", "touche 2 : SelectOptionByIndex(1) (Où est l'auberge ?)")
ns:Set("gossipOptions", false)
gossip.active = {}
M.fireEvent("GOSSIP_SHOW")
M.advance(0.2)
r = rows()
check(key(r[1]) == "F" and key(r[2]) == "1", "sans quête terminée : F sur la quête proposée")
gossip.available = {}
M.fireEvent("GOSSIP_SHOW")
M.advance(0.2)
r = rows()
check(key(r[1]) == "1" and key(r[2]) == "2", "options seules, F ne choisit pas d'option : seulement 1 et 2")
ns:Set("gossipOptions", true)
M.fireEvent("GOSSIP_SHOW")
M.advance(0.2)
r = rows()
check(key(r[1]) == "F" and key(r[2]) == "1", "F choisit la 1re option : F puis 1")
gossip.available = { { title = "Les loups de la ferme", questID = 101, isTrivial = false } }
gossip.active = { { title = "Le colis perdu", questID = 102, isComplete = true } }
M.fireEvent("GOSSIP_SHOW")
M.advance(0.2)
r = rows()
while #selected > 0 do table.remove(selected) end
r[1]:Click()
r[4]:Click()
check(selected[1] == "available:101" and selected[2] == "option:2", "clics : SelectAvailableQuest(101), SelectOptionByIndex(2)")
check(QW.secondary and S(QW.secondary).shown and label(QW.secondary) == "Au revoir", "bouton Au revoir")
check(not S(QW.primary).shown, "pas de bouton principal en discussion")

section("de la discussion à la quête : la fenêtre reste ouverte")
gossipFrame:Hide()
M.fireEvent("GOSSIP_CLOSED")
openPanel("Detail", "QUEST_DETAIL")
check(winShown() and QW.mode == "detail", "même fenêtre, quête proposée (" .. tostring(QW.mode) .. ")")
check(offscreen(questFrame), "QuestFrame hors de l'écran")
local t = texts()
check(t:find("Les loups de la ferme", 1, true) and t:find("dévorent nos poules", 1, true), "titre et texte de la quête")
check(t:find("OBJECTIFS", 1, true) and t:find("Rapporter 5 Peaux", 1, true), "objectifs")
check(t:find("RÉCOMPENSES", 1, true) ~= nil, "section récompenses")
local tl = tiles()
check(#tl == 4, "4 tuiles : 3 au choix + 1 donnée (" .. #tl .. ")")
check(S(tl[1].name).text == "Casque usé" and S(tl[4].name).text == "Potion de soins", "noms des objets")
check(t:find("850 XP", 1, true) ~= nil, "expérience affichée")
check(label(QW.primary) == "F  ·  Accepter" and QW.primary.isEnabled, "bouton Accepter (texte du jeu) avec la touche F")
check(next(ns.Dialog.choices) == nil, "quête proposée : rien de numéroté")
check(label(QW.secondary) == "Refuser", "bouton Refuser")
tl[2]:Click()
check(questInfo.itemChoice == 0, "quête proposée : un clic sur une tuile ne choisit rien")
M.shift = true
tl[3]:Click()
M.shift = false
check(linked == linkOf(30), "Maj-clic : lien de l'objet")
QW.primary:Click()
check(clicks[#clicks] == "QuestFrameAcceptButton:0", "Accepter clique le vrai bouton du jeu")

section("objets à rapporter")
openPanel("Progress", "QUEST_PROGRESS")
continue:Disable()
QW:Render()
check(QW.mode == "progress", "dialogue : objets à rapporter")
t = texts()
check(t:find("À RAPPORTER", 1, true) and #tiles() == 1 and S(tiles()[1].count).text == "5", "Peau de loup x5")
check(t:find("Il te manque", 1, true) ~= nil, "pas encore terminable : prévenu")
check(not QW.primary.isEnabled, "Continuer grisé tant que le jeu le grise")
continue:Enable()
quest.completable = true
QW:Render()
check(QW.primary.isEnabled and label(QW.primary) == "F  ·  Continuer", "Continuer actif, avec la touche F")
QW.primary:Click()
check(clicks[#clicks] == "QuestFrameCompleteButton:0", "Continuer clique le vrai bouton")

section("récompense au choix")
questInfo.itemChoice = 0
openPanel("Reward", "QUEST_COMPLETE")
check(QW.mode == "reward", "dialogue : récompense")
tl = tiles()
check(not QW.primary.isEnabled and label(QW.primary) == "Choisis une récompense", "rendre impossible sans choix (pas de F)")
check(S(tl[1].key).shown and S(tl[1].key.text).text == "1" and S(tl[3].key.text).text == "3" and not S(tl[4].key).shown,
    "récompenses au choix numérotées 1 à 3, pas la récompense donnée")
PlatyplusChoice3:Click()
check(questInfo.itemChoice == 3, "touche 3 : choix 3 posé dans le jeu")
check(QW.primary.isEnabled and label(QW.primary) == "F  ·  Rendre la quête", "F apparaît sur Rendre la quête une fois choisi")
questInfo.itemChoice = 0
ns.Quests:Select(0)
QW:Repaint()
local recommended
for i, tile in ipairs(tl) do if S(tile.tag).shown then recommended = i end end
check(recommended == 2, "« Conseillé » sur le casque qui améliore l'équipement (" .. tostring(recommended) .. ")")
check(questInfo.itemChoice == 0, "rien n'est choisi d'avance")
tl[1]:Click()
check(questInfo.itemChoice == 1, "clic : choix 1 posé dans le jeu")
check(QW.primary.isEnabled and label(QW.primary) == "F  ·  Rendre la quête", "Rendre la quête actif")
questInfo.itemChoice = 0
M.fireEvent("QUEST_ITEM_UPDATE")
M.advance(0.1)
check(questInfo.itemChoice == 1, "choix reposé après QUEST_ITEM_UPDATE (le jeu l'efface)")
QW.primary:Click()
check(clicks[#clicks] == "QuestFrameCompleteQuestButton:1", "rend la quête avec le choix 1")
M.fire(tl[3], "OnDoubleClick")
check(clicks[#clicks] == "QuestFrameCompleteQuestButton:3", "double-clic : choisit et rend en une fois")

section("choix fait ailleurs (grandes cartes, touche)")
ns.Quests:Select(2)
check(QW.choice == 2 and QW.primary.isEnabled, "la fenêtre suit un choix fait par un autre module")

section("fermeture")
win().close:Click()
M.advance(0.3)
check(not S(questFrame).shown, "la croix ferme le dialogue du jeu")
check(not winShown(), "fenêtre cachée")
check(next(ns.Dialog.choices) == nil, "fermé : plus rien de numéroté")
closeQuest()
check(M.overrides["1"] == nil and M.overrides["F"] == "INTERACTMOUSEOVER", "dialogue fini : touches 1 à 9 rendues, F interagit")

section("déplacement et taille")
ns:Set("questWinScale", 1.3)
check(S(win()).scale == 1.3, "taille appliquée (" .. tostring(S(win()).scale) .. ")")
ns.db.questWinPos = { x = 300, y = 700 }
QW:ApplyScale()
local p = S(win()).points[1]
check(p and p[1] == "TOPLEFT" and math.abs(p[4] - 300 / 1.3) < 0.01, "position gardée en points de l'écran")
QW:ResetPosition()
check(next(ns.db.questWinPos) == nil, "position remise à zéro")

section("option coupée : fenêtres du jeu")
openPanel("Detail", "QUEST_DETAIL")
check(winShown(), "fenêtre ouverte")
ns:Set("questWindow", false)
M.advance(0.1)
check(not winShown(), "fenêtre Platyplus cachée")
check(S(questFrame).alpha == 1 and S(questFrame).points[1][4] == 16, "QuestFrame revient à gauche de l'écran")
ShowUIPanel(questFrame)
check(S(questFrame).points[1][4] == 16, "le jeu la place à nouveau normalement")
closeQuest()
ns:Set("questWindow", true)
check(offscreen(questFrame), "option remise : de nouveau hors de l'écran")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
