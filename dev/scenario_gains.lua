-- Scénario : objets fabriqués / achetés / reçus dans le flux, choix de récompense de quête, réglages du jeu en un clic
local ADDON_DIR, SCRATCH = ARGS[1], ARGS[2]
local M = dofile(SCRATCH .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

---------------------------------------------------------------------------
-- Monde simulé : objets, sacs, équipement
---------------------------------------------------------------------------
local items = {
    [2]   = { name = "Casque use", q = 2, ilvl = 20, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 500 },
    [3]   = { name = "Casque meilleur", q = 2, ilvl = 40, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 900 },
    [30]  = { name = "Gemme chere", q = 3, ilvl = 1, equip = "", class = 3, sub = 0, bind = 0, price = 8000 },
    [21]  = { name = "Barre de fer", q = 1, ilvl = 1, equip = "", class = 7, sub = 0, bind = 0, price = 100 },
    [22]  = { name = "Potion", q = 1, ilvl = 1, equip = "", class = 0, sub = 0, bind = 0, price = 50 },
    [23]  = { name = "Lettre", q = 1, ilvl = 1, equip = "", class = 15, sub = 0, bind = 0, price = 0 },
    [24]  = { name = "Plume", q = 1, ilvl = 1, equip = "", class = 7, sub = 0, bind = 0, price = 5 },
    [25]  = { name = "Cuir", q = 1, ilvl = 1, equip = "", class = 7, sub = 0, bind = 0, price = 5 },
    [100] = { name = "Casque equipe", q = 3, ilvl = 30, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 0 },
}
local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. items[id].name .. "]|h|r" end
local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end

local bag = {}   -- [slot] = { id, count }
local function addToBag(id, n)
    for slot = 1, 20 do
        if bag[slot] and bag[slot].id == id then bag[slot].count = bag[slot].count + n return end
    end
    for slot = 1, 20 do
        if not bag[slot] then bag[slot] = { id = id, count = n } return end
    end
end

def("C_Container", {
    GetContainerNumSlots = function(b) return b == 0 and 20 or 0 end,
    GetContainerItemInfo = function(b, slot)
        local e = b == 0 and bag[slot]
        if not e then return nil end
        local it = items[e.id]
        return { iconFileID = 1000 + e.id, stackCount = e.count, isLocked = false, quality = it.q, hyperlink = linkOf(e.id),
                 hasNoValue = it.price == 0, itemID = e.id, isBound = it.bind == 1, itemName = it.name }
    end,
    GetContainerItemEquipmentSetInfo = function() return false, "" end,
    GetContainerNumFreeSlots = function() return 10, 0 end,
})
def("C_Item", {
    GetItemInfo = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        return it.name, linkOf(id), it.q, it.ilvl, 1, "x", "y", 1, it.equip, 1000 + id, it.price, it.class, it.sub, it.bind, 0, nil, false, ""
    end,
    GetItemInfoInstant = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        return id, "x", "y", it.equip, 1000 + id, it.class, it.sub
    end,
    GetDetailedItemLevelInfo = function(link) local it = items[idOf(link)]; return it and it.ilvl, false, it and it.ilvl end,
    GetItemNameByID = function(id) return items[id] and items[id].name end,
})
def("GetInventoryItemLink", function(unit, slot) if slot == 1 then return linkOf(100) end end)
def("C_MerchantFrame", { IsSellAllJunkEnabled = function() return true end, GetNumJunkItems = function() return 0 end })
def("C_TransmogCollection", { PlayerHasTransmogByItemInfo = function() return true end })

-- loot
local lootSlots = { { id = 24, qty = 1 } }
def("GetNumLootItems", function() return #lootSlots end)
def("GetLootSlotType", function(i) return lootSlots[i] and 1 or 0 end)
def("GetLootSlotInfo", function(i) local s = lootSlots[i]; return 1000 + s.id, items[s.id].name, s.qty, nil, items[s.id].q, false end)
def("GetLootSlotLink", function(i) return linkOf(lootSlots[i].id) end)
def("LootSlot", function(i)
    M.fireEvent("LOOT_SLOT_CLEARED", i)
    addToBag(lootSlots[i].id, lootSlots[i].qty)
end)
def("StaticPopup_Hide", function() end)

-- fenêtres Blizzard
local function frame(name) local f = CreateFrame("Frame", name, UIParent); f:Hide(); return f end
local professions, merchant, bank = frame("ProfessionsFrame"), frame("MerchantFrame"), frame("BankFrame")

-- quêtes : trois choix (casque meilleur que celui porté, casque moins bon, gemme chère)
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
for i = 1, #choiceIds do
    local b = CreateFrame("Button", nil, UIParent)
    b.type = "choice"
    b:SetID(i)
    choiceButtons[i] = b
end
def("QuestInfoRewardsFrame", { RewardButtons = choiceButtons })
def("QuestInfoItem_OnClick", function(self) questInfo.itemChoice = self:GetID() end)
local completedWith
local questFrame = frame("QuestFrame"); questFrame:Hide()
local rewardPanel = frame("QuestFrameRewardPanel"); rewardPanel:Hide()
local completeButton = CreateFrame("Button", "QuestFrameCompleteQuestButton", UIParent)
completeButton:SetScript("OnClick", function() completedWith = questInfo.itemChoice end)

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local files = { "Core.lua", "Loot.lua", "Float.lua", "Interact.lua", "Dialog.lua", "Junk.lua", "Gains.lua", "Quests.lua", "GameSettings.lua" }
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(3)   -- fin de la période de calme, premier relevé des sacs
ns.db.duration = 600

-- textes affichés dans le flux : nom, badge, pastille de source et prix de chaque carte visible du conteneur PlatyplusFeed
local function rows()
    local list = {}
    for _, f in ipairs(M.allFrames) do
        local s = M.state(f)
        if s.kind == "FontString" and s.text ~= "" and s.parent then
            local p = M.state(s.parent)
            if p.parent == PlatyplusFeed and p.shown then list[#list + 1] = tostring(s.text) end
        end
    end
    return list
end
local function has(substring)
    for _, t in ipairs(rows()) do if t:find(substring, 1, true) then return true end end
    return false
end
local function clearFeed()
    ns.db.duration = 0.05; M.advance(1); ns.db.duration = 600
end

section("objets fabriqués, achetés, reçus")
professions:Show()
addToBag(21, 2); M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(has("Fabriqué") and has("Barre de fer") and has("x2"), "fabrication : « Fabriqué [Barre de fer] x2 »")
professions:Hide(); clearFeed()

M.fireEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT", {})
addToBag(21, 1); M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(has("Fabriqué"), "fabrication reconnue par l'événement même fenêtre fermée")
clearFeed(); M.advance(9)

merchant:Show()
addToBag(22, 1); M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(has("Acheté") and has("Potion"), "achat chez un marchand : « Acheté [Potion] »")
merchant:Hide(); clearFeed()

bank:Show()
addToBag(23, 1); M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(not has("Lettre"), "retrait de banque : rien affiché")
bank:Hide(); clearFeed()

M.fireEvent("PLAYER_EQUIPMENT_CHANGED", 1)
addToBag(25, 1); M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(not has("Cuir"), "changement d'équipement : rien affiché")
clearFeed(); M.advance(2)

addToBag(23, 1); M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(has("Reçu") and has("Lettre"), "objet reçu sans fenêtre : « Reçu [Lettre] »")
clearFeed()

section("pas de doublon avec le loot")
M.fireEvent("LOOT_READY", true)
M.advance(0.2)
check(has("Plume") and not has("Reçu"), "loot ramassé affiché une seule fois")
M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(not has("Reçu"), "le suivi des sacs ne le remontre pas")
M.fireEvent("LOOT_CLOSED"); clearFeed()

section("récompense de quête")
M.fireEvent("QUEST_TURNED_IN", 123, 500, 250)
-- 250 pc = 2 pa 50 pc : en texte « po/pa/pc » ou avec les icônes de pièces selon le client
check(has("Quête") and has("50") and (has("pc") or has("CopperIcon")), "argent de la quête affiché")
addToBag(25, 1); M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(has("Quête") and has("Cuir"), "objet reçu juste après la remise : « Quête [Cuir] »")
clearFeed(); M.advance(6)

ns:Set("gainFeed", false)
addToBag(24, 3); M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.6)
check(not has("Reçu"), "option coupée : rien affiché")
ns:Set("gainFeed", true)

section("conseil de récompense (jamais choisi à ta place)")
questInfo.itemChoice = 0
local best, upgrade = ns.Quests:BestChoice()
check(best and best.index == 2 and upgrade == 10, "conseil : la pièce qui améliore l'équipement (choix " .. tostring(best and best.index) .. ")")
check(questInfo.itemChoice == 0, "le conseil ne choisit rien dans le jeu")
check(ns.Quests:NeedsChoice() == true, "plusieurs objets et rien de cliqué : la quête attend un choix")

section("la touche attend que le joueur choisisse")
questInfo.itemChoice = 0
questFrame:Show(); rewardPanel:Show()
M.fireEvent("QUEST_COMPLETE"); M.advance(0.2)
local printed = #M.printed
PlatyplusAdvance:GetScript("OnClick")(PlatyplusAdvance, "LeftButton", true)
check(completedWith == nil and questInfo.itemChoice == 0, "F sans choix : rien n'est choisi ni rendu")
check(#M.printed == printed + 1, "… et un message dit de choisir d'abord")
ns.Quests:Select(3)
PlatyplusAdvance:GetScript("OnClick")(PlatyplusAdvance, "LeftButton", true)
check(completedWith == 3, "récompense choisie puis F : quête rendue avec ce choix (" .. tostring(completedWith) .. ")")
questFrame:Hide(); rewardPanel:Hide()

section("réglages du jeu en un clic")
M.cvars.countdownForCooldowns = "0"; M.cvars.statusTextDisplay = "NONE"; M.cvars.statusText = "0"
M.cvars.showTargetOfTarget = "0"; M.cvars.softTargetEnemy = "1"
local applied = ns.GameSettings:ApplyRecommended()
check(applied == 4, "4 réglages appliqués, le 5e est inconnu du client (" .. applied .. ")")
check(M.cvars.softTargetEnemy == "3" and M.cvars.countdownForCooldowns == "1" and M.cvars.statusTextDisplay == "NUMERIC"
    and M.cvars.statusText == "1" and M.cvars.showTargetOfTarget == "1", "valeurs recommandées en place")
check(ns.db.cvarBackup.softTargetEnemy == "1" and ns.db.cvarBackup.statusTextDisplay == "NONE", "valeurs d'origine sauvegardées")
local list = ns.GameSettings.list
check(ns.GameSettings:IsOn(list[2]) and not ns.GameSettings:Available(list[4]), "état lu en direct, réglage inconnu grisé")
ns.GameSettings:Set(list[2], false)
check(M.cvars.countdownForCooldowns == "0" and ns.db.cvarBackup.countdownForCooldowns == nil, "un réglage coupé revient à sa valeur d'origine")
ns.GameSettings:RestoreAll()
check(M.cvars.softTargetEnemy == "1" and M.cvars.statusTextDisplay == "NONE" and M.cvars.showTargetOfTarget == "0", "tout remis comme avant")
check(next(ns.db.cvarBackup) == nil, "sauvegarde vidée")
SlashCmdList.PLATYPLUS("preset"); SlashCmdList.PLATYPLUS("preset restore")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
