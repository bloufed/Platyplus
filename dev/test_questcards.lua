-- Test des cartes de récompense de quête (QuestCards.lua) dans le simulateur
-- Usage : python -I dev\lua.py run dev\test_questcards.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

---------------------------------------------------------------------------
-- Monde simulé : un casque porté (niv. 30) et trois récompenses au choix
---------------------------------------------------------------------------
local items = {
    [2]   = { name = "Casque use", q = 2, ilvl = 20, equip = "INVTYPE_HEAD", class = 4, sub = 1, price = 500 },
    [3]   = { name = "Casque meilleur", q = 3, ilvl = 40, equip = "INVTYPE_HEAD", class = 4, sub = 1, price = 900,
              stats = { ITEM_MOD_STRENGTH_SHORT = 9, ITEM_MOD_STAMINA_SHORT = 7, RESISTANCE0_NAME = 120, ITEM_MOD_AGILITY_SHORT = 2 } },
    [30]  = { name = "Gemme chere", q = 4, ilvl = 1, equip = "", class = 3, sub = 0, price = 8000 },
    [100] = { name = "Casque equipe", q = 3, ilvl = 30, equip = "INVTYPE_HEAD", class = 4, sub = 1, price = 0 },
}
local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. items[id].name .. "]|h|r" end
local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end

def("C_Item", {
    GetItemInfo = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        local itemType = it.class == 4 and "Armure" or "Gemme"
        local sub = it.class == 4 and "Plaques" or "Simple"
        return it.name, linkOf(id), it.q, it.ilvl, 1, itemType, sub, 1, it.equip, 1000 + id, it.price, it.class, it.sub, 1
    end,
    GetItemInfoInstant = function(link)
        local id = idOf(link) or tonumber(link); local it = items[id]
        if not it then return nil end
        return id, "x", "y", it.equip, 1000 + id, it.class, it.sub
    end,
    GetDetailedItemLevelInfo = function(link) local it = items[idOf(link)]; return it and it.ilvl end,
    GetItemNameByID = function(id) return items[id] and items[id].name end,
    GetItemStats = function(link) local it = items[idOf(link)]; return it and it.stats or {} end,
    RequestLoadItemDataByID = function() end,
})
def("ITEM_MOD_STRENGTH_SHORT", "Force"); def("ITEM_MOD_STAMINA_SHORT", "Endurance"); def("ITEM_MOD_AGILITY_SHORT", "Agilité")
def("RESISTANCE0_NAME", "Armure"); def("INVTYPE_HEAD", "Tête")
def("GetInventoryItemLink", function(unit, slot) if slot == 1 then return linkOf(100) end end)
def("C_MerchantFrame", { IsSellAllJunkEnabled = function() return true end, GetNumJunkItems = function() return 0 end })
def("GetTitleText", function() return "La marée noire" end)

local choiceIds = { 2, 3, 30 }
def("GetNumQuestChoices", function() return #choiceIds end)
def("GetQuestItemInfo", function(kind, i)
    local it = items[choiceIds[i]]
    return it.name, 1000 + choiceIds[i], 1, it.q, true, choiceIds[i]
end)
def("GetQuestItemLink", function(kind, i) return linkOf(choiceIds[i]) end)
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

local function frame(name) local f = CreateFrame("Frame", name, UIParent); f:Hide(); return f end
local questFrame, rewardPanel = frame("QuestFrame"), frame("QuestFrameRewardPanel")
local completedWith
local completeButton = CreateFrame("Button", "QuestFrameCompleteQuestButton", UIParent)
completeButton:SetScript("OnClick", function() completedWith = questInfo.itemChoice end)

---------------------------------------------------------------------------
-- Chargement de tout l'addon, comme le jeu
---------------------------------------------------------------------------
local files = {}
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    local f = line:match("^([%w_%.]+%.lua)%s*$")
    if f then files[#files + 1] = f end
end
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(3)

local S = M.state
local Cards = ns.QuestCards

local function panel() return rawget(_G, "PlatyplusQuestCards") end
local function shown() local p = panel(); return p ~= nil and S(p).shown end
local function visibleCards()
    local list = {}
    local p = panel()
    if not p then return list end
    for _, c in ipairs(S(p.grid).frames) do
        if S(c).shown and c.data then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.data.index < b.data.index end)
    return list
end
local function text(fs) return tostring(S(fs).text or "") end

local function openReward()
    completedWith = nil
    questInfo.itemChoice = 0                     -- QuestInfo_Display remet le choix à zéro
    questFrame:Show(); rewardPanel:Show()
    M.fireEvent("QUEST_COMPLETE")
    M.advance(0.2)
end
local function closeReward()
    questFrame:Hide(); rewardPanel:Hide()
    M.fireEvent("QUEST_FINISHED")
    M.advance(0.2)
end

---------------------------------------------------------------------------
section("API et réglage")
check(Cards and Cards.Update and Cards.Demo and Cards.Take and Cards.Choose, "ns.QuestCards : Update, Demo, Take, Choose")
check(ns.db.questCards == true, "activé par défaut")
check(panel() == nil, "rien de construit avant la première quête")

section("ouverture d'une récompense au choix")
openReward()
check(shown(), "les cartes s'affichent")
local list = visibleCards()
check(#list == 3, "3 cartes (" .. #list .. ")")
local p = panel()
check(S(p).strata == "DIALOG", "au-dessus de la fenêtre de quête (strate DIALOG)")
check(text(p.kicker):find("La marée noire", 1, true) ~= nil, "titre de la quête affiché (" .. text(p.kicker) .. ")")
local special = false
for _, name in ipairs(UISpecialFrames) do if name == "PlatyplusQuestCards" then special = true end end
check(special, "Échap ferme les cartes (UISpecialFrames)")

section("contenu des cartes")
local c1, c2, c3 = list[1], list[2], list[3]
check(text(c1.qualityText) == "Inhabituel" and text(c2.qualityText) == "Rare" and text(c3.qualityText) == "Épique",
    "rareté écrite sur chaque carte")
check(text(c2.name) == "Casque meilleur", "nom de l'objet")
check(text(c2.sub):find("Tête", 1, true) and text(c2.sub):find("niv. 40", 1, true), "emplacement et niveau (" .. text(c2.sub) .. ")")
check(text(c2.stats[1]) == "120 Armure" and text(c2.stats[2]) == "+9 Force" and text(c2.stats[3]) == "+7 Endurance",
    "3 caractéristiques, les plus grosses d'abord (" .. text(c2.stats[1]) .. " / " .. text(c2.stats[2]) .. ")")
check(S(c2.chip).shown and text(c2.chip.text) == "+10 niv. vs ton équipement", "pastille d'amélioration (" .. text(c2.chip.text) .. ")")
check(S(c1.chip).shown and text(c1.chip.text) == "10 niv. de moins", "pastille « moins bon » (" .. text(c1.chip.text) .. ")")
check(not S(c3.chip).shown, "pas de pastille pour un objet qui ne s'équipe pas")
check(text(c3.price):find("Vente", 1, true) ~= nil, "prix de vente affiché")
local qc = c3.qc
check(qc and math.abs(qc[1] - 0.64) < 0.01 and math.abs(qc[3] - 0.93) < 0.01, "couleur de la carte = qualité épique")

section("recommandée = simple conseil, rien de choisi d'avance")
check(S(c2.badge).shown and not S(c1.badge).shown and not S(c3.badge).shown, "« Recommandée » sur l'amélioration seulement")
check(questInfo.itemChoice == 0, "aucune récompense choisie à l'ouverture (" .. questInfo.itemChoice .. ")")
check(not S(c1.check).shown and not S(c2.check).shown and not S(c3.check).shown, "aucune coche")
check(p.take.isEnabled == false and text(p.take.label) == "Choisis une carte", "« Prendre » attend un choix")
p.take:Click()
check(completedWith == nil, "sans choix, rien n'est rendu")
local printed = #M.printed
PlatyplusAdvance:GetScript("OnClick")(PlatyplusAdvance, "LeftButton", true)
check(completedWith == nil and questInfo.itemChoice == 0, "la touche de Platyplus ne choisit pas à ta place")
check(#M.printed == printed + 1, "… elle dit de choisir d'abord")

section("clic sur une carte")
c2:Click()
check(questInfo.itemChoice == 2 and S(c2.check).shown, "clic sur la recommandée : choisie, coche affichée")
check(text(p.take.label):find("Casque meilleur", 1, true) ~= nil, "bouton « Prendre : Casque meilleur »")
c3:Click()
check(questInfo.itemChoice == 3, "clic = choix dans la fenêtre Blizzard (" .. questInfo.itemChoice .. ")")
check(S(c3.check).shown and not S(c2.check).shown, "la coche suit")
check(text(p.take.label):find("Gemme chere", 1, true) ~= nil, "le bouton suit (" .. text(p.take.label) .. ")")

section("le jeu efface le choix en rafraîchissant la fenêtre")
questInfo.itemChoice = 0
M.fireEvent("QUEST_ITEM_UPDATE"); M.advance(0.3)
check(questInfo.itemChoice == 3, "choix du joueur reposé, pas remplacé par la recommandée (" .. questInfo.itemChoice .. ")")

section("prendre la récompense")
p.take:Click()
check(completedWith == 3, "« Prendre » clique Terminer avec la carte choisie (" .. tostring(completedWith) .. ")")
closeReward()
check(not shown(), "quête rendue : cartes cachées")

openReward()
M.fire(visibleCards()[1], "OnDoubleClick")
check(completedWith == 1, "double-clic : choisit et rend la quête (" .. tostring(completedWith) .. ")")
closeReward()

openReward()
visibleCards()[3]:Click()
PlatyplusAdvance:GetScript("OnClick")(PlatyplusAdvance, "LeftButton", true)
check(completedWith == 3, "la touche de Platyplus rend la quête avec la carte choisie (" .. tostring(completedWith) .. ")")
closeReward()

section("aucune amélioration : la plus chère est conseillée")
choiceIds = { 2, 30 }
openReward()
local two = visibleCards()
check(S(two[2].badge).shown and not S(two[1].badge).shown, "« Recommandée » sur la plus chère")
check(text(two[2].chip.text) == "Se vend le plus cher" and questInfo.itemChoice == 0, "pastille « Se vend le plus cher », rien de choisi")
closeReward()
choiceIds = { 2, 3, 30 }

section("quand les cartes ne s'affichent pas")
M.shift = true; openReward(); M.shift = false
check(not shown(), "Maj tenu à l'ouverture : fenêtre classique")
closeReward()

openReward()
M.fire(panel().classic, "OnClick")
check(not shown(), "« Fenêtre classique » cache les cartes")
M.fireEvent("QUEST_ITEM_UPDATE"); M.advance(0.3)
check(not shown(), "… et elles ne reviennent pas pour cette quête")
closeReward()

ns:Set("questCards", false)
openReward()
check(not shown(), "option coupée : rien")
closeReward()
ns:Set("questCards", true)

choiceIds = { 3 }
openReward()
check(not shown(), "une seule récompense : pas de cartes")
closeReward()
choiceIds = { 2, 3, 30 }

ns:Set("autoQuest", true)
openReward()
check(shown() and completedWith == nil and questInfo.itemChoice == 0, "quêtes automatiques : cartes affichées, la quête attend ton choix")
visibleCards()[1]:Click()
panel().take:Click()
check(completedWith == 1, "… puis rendue avec la carte choisie")
closeReward()
ns:Set("autoQuest", false)

section("beaucoup de choix : deux rangées équilibrées")
choiceIds = { 2, 3, 30, 2, 3, 30, 2 }
openReward()
local many = visibleCards()
check(#many == 7, "7 cartes")
check(many[4].y == 0 and many[5].y > 0, "4 sur la première rangée, 3 sur la seconde")
check(S(panel()).w > 0 and S(panel()).w < 1366, "panneau plus étroit que l'écran (" .. S(panel()).w .. ")")
closeReward()
choiceIds = { 2, 3, 30 }

section("aperçu /pp cartes")
questInfo.itemChoice = 0
SlashCmdList.PLATYPLUS("cartes")
M.advance(0.3)
local demo = visibleCards()
check(shown() and #demo == 4, "4 cartes d'exemple")
check(questInfo.itemChoice == 0, "aperçu : rien n'est envoyé au jeu (" .. questInfo.itemChoice .. ")")
check(S(demo[2].badge).shown and text(demo[3].chip.text) == "Inutilisable", "recommandée et objet inutilisable")
demo[4]:Click()
check(S(demo[4].check).shown and questInfo.itemChoice == 0, "clic dans l'aperçu : coche seulement (" .. questInfo.itemChoice .. ")")
local printed = #M.printed
panel().take:Click()
check(not shown() and #M.printed == printed + 1, "« Prendre » ferme l'aperçu avec un message")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
