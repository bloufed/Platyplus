-- Scénario : petits plus (Tweaks.lua) — erreurs rouges, courrier, niveau d'objet (fiche + sacs), durabilité
-- Usage : python -I dev\lua.py run dev\test_tweaks.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local S = M.state

---------------------------------------------------------------------------
-- Compléments au simulateur (méthodes / fonctions WoW réelles absentes de wowmock.lua)
---------------------------------------------------------------------------
-- hooksecurefunc : vrai post-hook (le simulateur n'en fournit qu'un no-op)
def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = rawget(tbl, name)
    if type(orig) ~= "function" then error("hooksecurefunc : " .. tostring(name) .. " n'est pas une fonction", 2) end
    rawset(tbl, name, function(...)
        local results = { orig(...) }
        hook(...)
        return unpack(results)
    end)
end)
-- SetTextColor est un no-op dans le simulateur : on garde la couleur pour la vérifier
M.impl.SetTextColor = function(f, r, g, b) S(f).color = { r, g, b } end

-- cadres Blizzard qui peuvent manquer dans le jeu (lus avec rawget par Tweaks, mais déclarés ici pour le mode strict)
for _, name in ipairs({ "ContainerFrame2", "ContainerFrame3", "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
    "ContainerFrame7", "CharacterFrame", "PaperDollFrame", "CharacterLevelText", "OpenAllMail" }) do
    M.optional[name] = true
end

---------------------------------------------------------------------------
-- Monde simulé : objets, équipement, sac
---------------------------------------------------------------------------
local items = {
    [1]   = { name = "Chiffon", q = 0, ilvl = 1, equip = "", class = 15, sub = 0, bind = 0, price = 10 },
    [2]   = { name = "Casque use", q = 2, ilvl = 20, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 500 },
    [3]   = { name = "Casque meilleur", q = 3, ilvl = 40, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 900 },
    [4]   = { name = "Potion", q = 1, ilvl = 35, equip = "", class = 0, sub = 0, bind = 0, price = 50 },
    [5]   = { name = "Chemise", q = 1, ilvl = 1, equip = "INVTYPE_BODY", class = 4, sub = 0, bind = 0, price = 5 },
    [6]   = { name = "Epee BoE", q = 4, ilvl = 55, equip = "INVTYPE_WEAPON", class = 2, sub = 7, bind = 2, price = 3000 },
    [100] = { name = "Casque porte", q = 3, ilvl = 30, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 0 },
    [101] = { name = "Plastron porte", q = 4, ilvl = 45, equip = "INVTYPE_CHEST", class = 4, sub = 1, bind = 1, price = 0 },
    [102] = { name = "Chemise portee", q = 1, ilvl = 1, equip = "INVTYPE_BODY", class = 4, sub = 0, bind = 0, price = 0 },
    [103] = { name = "Hache portee", q = 2, ilvl = 33, equip = "INVTYPE_2HWEAPON", class = 2, sub = 1, bind = 1, price = 0 },
}
local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. items[id].name .. "]|h|r" end
local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end

local bag = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 6 }   -- [slot] = itemID (7 = vide)
local BAG_SIZE = 7
local equipped = { [1] = 100, [5] = 101, [4] = 102, [16] = 103 }

def("C_Container", {
    GetContainerNumSlots = function(b) return b == 0 and BAG_SIZE or 0 end,
    GetContainerNumFreeSlots = function() return 1, 0 end,
    GetContainerItemInfo = function(b, slot)
        local id = b == 0 and bag[slot]
        if not id then return nil end
        local it = items[id]
        return { iconFileID = 1000 + id, stackCount = 1, isLocked = false, quality = it.q, hyperlink = linkOf(id),
                 hasNoValue = it.price == 0, itemID = id, isBound = it.bind == 1, itemName = it.name }
    end,
    GetContainerItemEquipmentSetInfo = function() return false, "" end,
})
def("C_Item", {
    GetItemInfo = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        return it.name, linkOf(id), it.q, it.ilvl, 1, "x", "y", 1, it.equip, 1000 + id, it.price, it.class, it.sub, it.bind
    end,
    GetItemInfoInstant = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        return id, "x", "y", it.equip, 1000 + id, it.class, it.sub
    end,
    GetDetailedItemLevelInfo = function(link) local it = items[idOf(link)]; return it and it.ilvl, false, it and it.ilvl end,
})
def("C_TransmogCollection", { PlayerHasTransmogByItemInfo = function() return true end })
def("GetInventoryItemLink", function(unit, slot) local id = equipped[slot]; return id and linkOf(id) end)
def("GetInventoryItemQuality", function(unit, slot) local id = equipped[slot]; return id and items[id].q end)
def("GetAverageItemLevel", function() return 36.6, 35.2, 30 end)

-- durabilité
local alert = {}
for i = 1, 11 do alert[i] = 0 end
local durability = { [1] = { 80, 100 }, [5] = { 30, 120 } }
def("GetInventoryAlertStatus", function(i) return alert[i] end)
def("GetInventoryItemDurability", function(slot) local d = durability[slot]; if d then return d[1], d[2] end end)

---------------------------------------------------------------------------
-- Cadres Blizzard simulés
---------------------------------------------------------------------------
-- erreurs rouges
local errors = CreateFrame("MessageFrame", "UIErrorsFrame", UIParent)
errors:RegisterEvent("UI_ERROR_MESSAGE"); errors:RegisterEvent("UI_INFO_MESSAGE"); errors:RegisterEvent("SYSMSG")

-- boîte aux lettres
local mailFrame = CreateFrame("Frame", "MailFrame", UIParent); mailFrame:Hide()
local inbox = CreateFrame("Frame", "InboxFrame", mailFrame)
local openAll = CreateFrame("Button", "OpenAllMail", inbox)
inbox.OpenAllMail = openAll
local mailClicks, inboxCount = 0, 3
openAll:SetScript("OnClick", function(self) mailClicks = mailClicks + 1; self:Disable() end)  -- StartOpening : se désactive
def("GetInboxNumItems", function() return inboxCount, inboxCount end)
local function openMailbox()
    openAll:Enable()          -- StopOpening de la fois précédente
    mailFrame:Show()
end
local function closeMailbox() mailFrame:Hide() end

-- fiche du personnage
local charFrame = CreateFrame("Frame", "CharacterFrame", UIParent)
local paperDoll = CreateFrame("Frame", "PaperDollFrame", charFrame)
def("CharacterLevelText", charFrame:CreateFontString("CharacterLevelText"))
local SLOT_IDS = {
    CharacterHeadSlot = 1, CharacterNeckSlot = 2, CharacterShoulderSlot = 3, CharacterShirtSlot = 4,
    CharacterChestSlot = 5, CharacterWaistSlot = 6, CharacterLegsSlot = 7, CharacterFeetSlot = 8,
    CharacterWristSlot = 9, CharacterHandsSlot = 10, CharacterFinger0Slot = 11, CharacterFinger1Slot = 12,
    CharacterTrinket0Slot = 13, CharacterTrinket1Slot = 14, CharacterBackSlot = 15, CharacterMainHandSlot = 16,
    CharacterSecondaryHandSlot = 17, CharacterRangedSlot = 18, CharacterTabardSlot = 19, CharacterAmmoSlot = 0,
}
local slotButtons = {}
for name, id in pairs(SLOT_IDS) do
    local b = CreateFrame("Button", name, paperDoll)
    b:SetID(id)
    slotButtons[name] = b
end
local bagBarButton = CreateFrame("Button", "CharacterBag0Slot", UIParent); bagBarButton:SetID(31)
local blizzSlotUpdates = 0
def("PaperDollItemSlotButton_Update", function(self) blizzSlotUpdates = blizzSlotUpdates + 1 end)
local function showPaperDoll()   -- comme PaperDollItemSlotButton_OnShow sur chaque case
    for _, b in pairs(slotButtons) do _G.PaperDollItemSlotButton_Update(b) end
    _G.PaperDollItemSlotButton_Update(bagBarButton)
end

-- sacs : cadres avec Items, EnumerateValidItems, UpdateItems
local function enumerate(self)
    local function iterator(container, index)
        index = index + 1
        if index <= container.size then
            local item = container.Items[index]
            if item then return index, item end
        end
    end
    return iterator, self, 0
end
local blizzBagUpdates = 0
local function makeBagFrame(name, combined)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetID(0)
    f.Items, f.size = {}, BAG_SIZE
    for slot = 1, BAG_SIZE do
        local b = CreateFrame("ItemButton", nil, f)
        b:SetID(slot)
        if combined then b.bagID = 0 end
        b.GetBagID = function(self) return self.bagID or self:GetParent():GetID() end
        b.JunkIcon = b:CreateTexture(); b.JunkIcon:Hide()
        f.Items[slot] = b
    end
    f.EnumerateValidItems = enumerate
    f.UpdateItems = function(self) blizzBagUpdates = blizzBagUpdates + 1 end
    return f
end
local bag1 = makeBagFrame("ContainerFrame1")
local combined = makeBagFrame("ContainerFrameCombinedBags", true); combined:Hide()
def("ContainerFrame_UpdateAll", function()
    for _, f in ipairs({ bag1, combined, rawget(_G, "ContainerFrame2") }) do
        if f and f:IsShown() then f:UpdateItems() end
    end
end)

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Float.lua", "Junk.lua", "Tweaks.lua" })
check(ns.Tweaks ~= nil, "module ns.Tweaks présent")

-- on compte les appels à BuildList et les lignes du flux
local buildCalls = 0
local origBuild = ns.Junk.BuildList
ns.Junk.BuildList = function(self) buildCalls = buildCalls + 1; return origBuild(self) end
local floats = {}
local origAdd = ns.Float.Add
ns.Float.Add = function(self, info) floats[#floats + 1] = info; return origAdd(self, info) end

M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.loggedIn = true
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(0.2)
check(ns.db ~= nil, "ns.db créé")
ns.db.duration = 600
local status = ns.Tweaks:Status()
check(status.charHooked, "hook PaperDollItemSlotButton_Update posé (charIlvl actif par défaut)")
check(status.bagHooks == 2 and status.bagFrames == 2,
    "ContainerFrame1 et ContainerFrameCombinedBags accrochés (" .. status.bagFrames .. "/" .. status.bagHooks .. ")")
check(status.bagFallback, "ContainerFrame_UpdateAll accroché (filet)")
check(not status.mailHooked, "courrier pas accroché tant que l'option est coupée")

---------------------------------------------------------------------------
section("1. erreurs rouges")
check(errors:IsEventRegistered("UI_ERROR_MESSAGE"), "option coupée par défaut : erreurs affichées")
ns:Set("hideErrors", true)
check(not errors:IsEventRegistered("UI_ERROR_MESSAGE"), "option active : UI_ERROR_MESSAGE retiré")
check(errors:IsEventRegistered("UI_INFO_MESSAGE") and errors:IsEventRegistered("SYSMSG"), "messages d'info conservés")
errors:RegisterEvent("UI_ERROR_MESSAGE")          -- quelque chose le remet...
M.fireEvent("PLAYER_ENTERING_WORLD", false, true)  -- ... rechargement d'écran : on le retire de nouveau
check(not errors:IsEventRegistered("UI_ERROR_MESSAGE"), "retiré de nouveau après un écran de chargement")
ns:Set("hideErrors", false)
check(errors:IsEventRegistered("UI_ERROR_MESSAGE"), "option coupée : UI_ERROR_MESSAGE remis")
ns:Set("hideErrors", false)
check(errors:IsEventRegistered("UI_ERROR_MESSAGE"), "recouper ne change rien")

---------------------------------------------------------------------------
section("2. courrier")
openMailbox(); M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(2); closeMailbox()
check(mailClicks == 0, "option coupée : rien n'est ouvert")
ns:Set("autoOpenMail", true)
check(ns.Tweaks:Status().mailHooked, "MailFrame accroché à l'activation")

openMailbox()
M.advance(0.1)
check(mailClicks == 0, "pas de clic immédiat")
M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(0.1); M.fireEvent("MAIL_INBOX_UPDATE")
M.advance(0.5)
check(mailClicks == 1, "« Tout ouvrir » cliqué après MAIL_INBOX_UPDATE (" .. mailClicks .. ")")
openAll:Enable()   -- l'ouverture se termine, le bouton redevient actif
for _ = 1, 3 do M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(0.4) end
M.advance(3)
check(mailClicks == 1, "pas de relance en boucle (" .. mailClicks .. ")")
closeMailbox()

openMailbox(); M.advance(2)
check(mailClicks == 2, "sans MAIL_INBOX_UPDATE : un essai de secours (" .. mailClicks .. ")")
closeMailbox()

M.shift = true; openMailbox(); M.shift = false
M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(3)
check(mailClicks == 2, "Maj tenu à l'ouverture : rien")
closeMailbox()

openMailbox(); M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(0.1); closeMailbox(); M.advance(3)
check(mailClicks == 2, "boîte refermée avant le clic : rien")

inboxCount = 0
openMailbox(); M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(2)
check(mailClicks == 2, "boîte vide : pas de clic")
closeMailbox(); inboxCount = 3

openMailbox(); openAll:Disable(); M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(2)
check(mailClicks == 2, "bouton désactivé (ouverture déjà en cours) : pas de clic")
closeMailbox()

openMailbox(); ns:Set("autoOpenMail", false); M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(2)
check(mailClicks == 2, "option coupée pendant l'attente : pas de clic")
closeMailbox()
ns:Set("autoOpenMail", true)
openMailbox(); M.fireEvent("MAIL_INBOX_UPDATE"); M.advance(1)
check(mailClicks == 3, "réactivée : de nouveau un clic (" .. mailClicks .. ")")
closeMailbox()

---------------------------------------------------------------------------
section("3. fiche du personnage")
local function slotText(name)
    local o = ns.Tweaks:GetOverlay(slotButtons[name])
    if not o or not S(o.level).shown then return nil end
    return S(o.level).text
end
showPaperDoll(); M.advance(0.1)
check(blizzSlotUpdates >= 21, "le code de Blizzard est toujours appelé (" .. blizzSlotUpdates .. ")")
check(slotText("CharacterHeadSlot") == "30", "tête : 30 (" .. tostring(slotText("CharacterHeadSlot")) .. ")")
check(slotText("CharacterChestSlot") == "45", "torse : 45")
check(slotText("CharacterMainHandSlot") == "33", "main droite : 33")
check(slotText("CharacterShirtSlot") == nil and ns.Tweaks:GetOverlay(slotButtons.CharacterShirtSlot) == nil, "chemise : rien")
check(slotText("CharacterNeckSlot") == nil, "emplacement vide : rien")
check(ns.Tweaks:GetOverlay(bagBarButton) == nil, "bouton de sac de la barre : ignoré")
do
    local o = ns.Tweaks:GetOverlay(slotButtons.CharacterHeadSlot)
    local c, q = S(o.level).color, ITEM_QUALITY_COLORS[3]
    check(c and c[1] == q.r and c[2] == q.g and c[3] == q.b, "couleur de la qualité (rare)")
    local o2 = ns.Tweaks:GetOverlay(slotButtons.CharacterChestSlot)
    local c2, q2 = S(o2.level).color, ITEM_QUALITY_COLORS[4]
    check(c2 and c2[1] == q2.r and c2[3] == q2.b, "couleur de la qualité (épique)")
end
local avgLabel = ns.Tweaks:GetAverageLabel()
local function avgShown() return avgLabel and S(S(avgLabel).parent).shown end
check(avgLabel ~= nil and tostring(S(avgLabel).text):find("35", 1, true) ~= nil,
    "moyenne portée affichée (" .. tostring(avgLabel and S(avgLabel).text) .. ")")

equipped[1] = 3
M.fireEvent("PLAYER_EQUIPMENT_CHANGED", 1, false)
_G.PaperDollItemSlotButton_Update(slotButtons.CharacterHeadSlot); M.advance(0.2)
check(slotText("CharacterHeadSlot") == "40", "nouvelle pièce : 40 (" .. tostring(slotText("CharacterHeadSlot")) .. ")")

ns:Set("charIlvl", false); M.advance(0.1)
check(slotText("CharacterHeadSlot") == nil and slotText("CharacterChestSlot") == nil, "option coupée : textes cachés")
check(not avgShown(), "option coupée : moyenne cachée")
showPaperDoll(); M.advance(0.1)
check(slotText("CharacterHeadSlot") == nil, "option coupée : la mise à jour de Blizzard ne les remet pas")
ns:Set("charIlvl", true); M.advance(0.1)
check(slotText("CharacterHeadSlot") == "40" and slotText("CharacterChestSlot") == "45", "réactivée : textes revenus sans attendre Blizzard")
check(avgShown(), "réactivée : moyenne revenue")

def("GetAverageItemLevel", nil)
ns:Set("charIlvl", true); M.advance(0.1)
-- moyenne maison : tête 40, torse 45, hache 33 (chemise exclue) => 39,3
check(tostring(S(avgLabel).text):find("39", 1, true) ~= nil, "moyenne calculée sans GetAverageItemLevel (" .. tostring(S(avgLabel).text) .. ")")
check(ns.Tweaks:AverageItemLevel() and math.floor(ns.Tweaks:AverageItemLevel()) == 39, "Tweaks:AverageItemLevel()")
equipped[1] = 100

---------------------------------------------------------------------------
section("4. sacs")
local function bagOverlay(frame, slot) return ns.Tweaks:GetOverlay(frame.Items[slot]) end
local function bagLevel(frame, slot)
    local o = bagOverlay(frame, slot)
    if not o or not S(o.level).shown then return nil end
    return S(o.level).text
end
local function bagCoin(frame, slot)
    local o = bagOverlay(frame, slot)
    return (o and o.coin and S(o.coin).shown) and true or false
end

M.advance(0.2)
buildCalls = 0
bag1:UpdateItems()
check(blizzBagUpdates >= 1, "le UpdateItems de Blizzard est toujours appelé")
check(buildCalls == 1, "un seul BuildList pour tout le sac (" .. buildCalls .. ")")
check(bagLevel(bag1, 2) == "20" and bagLevel(bag1, 3) == "40" and bagLevel(bag1, 6) == "55",
    "niveaux : 20, 40, 55 (" .. tostring(bagLevel(bag1, 2)) .. ", " .. tostring(bagLevel(bag1, 3)) .. ", " .. tostring(bagLevel(bag1, 6)) .. ")")
check(bagLevel(bag1, 1) == nil, "gris non équipable : pas de niveau")
check(bagOverlay(bag1, 4) == nil, "potion : aucun texte créé")
check(bagOverlay(bag1, 5) == nil, "chemise : aucun texte créé")
check(bagOverlay(bag1, 7) == nil, "case vide : aucun texte créé")
check(bagCoin(bag1, 1), "pièce sur le gris")
check(bagCoin(bag1, 2), "pièce sur le casque inutile")
check(not bagCoin(bag1, 3) and not bagCoin(bag1, 6), "pas de pièce sur ce qui est gardé")
do
    local c, q = S(bagOverlay(bag1, 6).level).color, ITEM_QUALITY_COLORS[4]
    check(c and c[1] == q.r and c[3] == q.b, "niveau coloré par la qualité")
end

M.advance(0.1)
buildCalls = 0
combined:Show()
bag1:UpdateItems(); combined:UpdateItems()
check(buildCalls == 1, "deux sacs mis à jour dans la même image : un seul BuildList (" .. buildCalls .. ")")
check(bagLevel(combined, 2) == "20" and bagCoin(combined, 2), "sacs combinés décorés aussi")
M.advance(0.1)
bag1:UpdateItems()
check(buildCalls == 2, "image suivante : liste recalculée (" .. buildCalls .. ")")
combined:Hide()

local before = #M.allFrames
M.advance(0.1); bag1:UpdateItems(); M.advance(0.1); bag1:UpdateItems()
check(#M.allFrames == before, "textes réutilisés : aucun cadre créé aux mises à jour suivantes")

-- règles de vente modifiées => pièces revues (une seule fois, regroupé)
M.advance(0.1)
buildCalls = 0
ns.Junk:AddToList("neverSell", 2)
ns:Set("gearMargin", 1); ns:Set("gearMargin", 1)
M.advance(0.3)
check(buildCalls == 1, "changement de règles : un seul rafraîchissement (" .. buildCalls .. ")")
check(not bagCoin(bag1, 2) and bagLevel(bag1, 2) == "20", "« jamais vendre » : pièce retirée, niveau gardé")
ns.Junk:RemoveFromList("neverSell", 2); M.advance(0.3)
check(bagCoin(bag1, 2), "retiré de la liste : pièce revenue")

-- la pièce de Blizzard (gris chez le marchand) est au même endroit
bag1.Items[1].JunkIcon:Show(); M.advance(0.1); bag1:UpdateItems()
check(not bagCoin(bag1, 1), "pièce de Blizzard visible : la nôtre se cache")
bag1.Items[1].JunkIcon:Hide(); M.advance(0.1); bag1:UpdateItems()
check(bagCoin(bag1, 1), "pièce de Blizzard cachée : la nôtre revient")

-- objet déplacé : la case vidée perd son texte
bag[3] = nil; M.advance(0.1); bag1:UpdateItems()
check(bagLevel(bag1, 3) == nil, "case vidée : niveau caché")
bag[3] = 3; M.advance(0.1); bag1:UpdateItems()

-- changement d'équipement : sacs revus
M.advance(0.1)
buildCalls = 0
equipped[1] = 3   -- casque 40 porté : le casque 30 n'existe pas dans le sac, le 20 reste inutile
M.fireEvent("PLAYER_EQUIPMENT_CHANGED", 1, false); M.fireEvent("PLAYER_EQUIPMENT_CHANGED", 1, true)
M.advance(0.3)
check(buildCalls == 1, "PLAYER_EQUIPMENT_CHANGED en rafale : un seul rafraîchissement (" .. buildCalls .. ")")
equipped[1] = 100

-- désactivation / réactivation
ns:Set("bagIlvl", false)
check(bagLevel(bag1, 2) == nil and not bagCoin(bag1, 1), "option coupée : tout caché")
buildCalls = 0
M.advance(0.1); bag1:UpdateItems(); M.advance(0.1)
check(buildCalls == 0 and bagLevel(bag1, 2) == nil, "option coupée : aucun calcul, rien d'affiché")
ns:Set("bagIlvl", true); M.advance(0.2)
check(bagLevel(bag1, 2) == "20" and bagCoin(bag1, 1), "réactivée : tout revient sans attendre Blizzard")

-- cadre de sac créé plus tard (addon chargé à la demande)
local bag2 = makeBagFrame("ContainerFrame2")
bag2:SetID(0)
M.fireEvent("ADDON_LOADED", "Blizzard_Test")
M.advance(0.2)
check(ns.Tweaks:Status().bagHooks == 3, "ContainerFrame2 accroché après ADDON_LOADED (" .. ns.Tweaks:Status().bagHooks .. ")")
bag2:UpdateItems()
check(bagLevel(bag2, 6) == "55", "nouveau sac décoré")
_G.ContainerFrame_UpdateAll(); M.advance(0.1)
check(bagLevel(bag1, 2) == "20", "ContainerFrame_UpdateAll : rien de cassé")

-- filet : un sac sans UpdateItems (méthode absente) est revu après ContainerFrame_UpdateAll / BAG_UPDATE_DELAYED
local bag3 = makeBagFrame("ContainerFrame3")
bag3.UpdateItems = nil
M.fireEvent("ADDON_LOADED", "Blizzard_Test2"); M.advance(0.2)
check(ns.Tweaks:Status().bagFrames == 4 and ns.Tweaks:Status().bagHooks == 3, "sac sans UpdateItems : suivi sans hook")
bag[6] = 3; M.fireEvent("BAG_UPDATE_DELAYED"); M.advance(0.1)
check(bagLevel(bag3, 6) == "40", "BAG_UPDATE_DELAYED : sac sans hook mis à jour (" .. tostring(bagLevel(bag3, 6)) .. ")")
bag[6] = 6; _G.ContainerFrame_UpdateAll(); M.advance(0.1)
check(bagLevel(bag3, 6) == "55", "ContainerFrame_UpdateAll : sac sans hook mis à jour (" .. tostring(bagLevel(bag3, 6)) .. ")")
bag3:Hide()

---------------------------------------------------------------------------
section("5. durabilité")
local function infoRows()
    local n = 0
    for _, info in ipairs(floats) do if info.source == "info" then n = n + 1 end end
    return n
end
local function chatCount(word)
    local n = 0
    for _, line in ipairs(M.printed) do if line:find(word, 1, true) then n = n + 1 end end
    return n
end
-- la connexion a eu lieu au tout début ; la période de grâce est passée (le test a avancé de plusieurs secondes)
-- on refait un scénario de connexion complet avec un nouveau chargement plus bas ; ici : session en cours
check(ns.Tweaks:Status().durabilityReady, "période de grâce terminée")
alert[3] = 1; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(infoRows() == 1, "0 -> presque cassé : une ligne dans le flux (" .. infoRows() .. ")")
check(floats[#floats].name == "Équipement presque cassé : pense à réparer" and floats[#floats].icon ~= nil,
    "texte et icône de la ligne")
check(chatCount("presque cassé") == 1, "un message dans le chat")
check(chatCount("25 %") == 1, "pourcentage de la pièce la plus abîmée (30/120 = 25 %)")
M.fireEvent("UPDATE_INVENTORY_ALERTS"); M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(infoRows() == 1, "même état : pas de nouvelle alerte")
alert[5] = 2; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(infoRows() == 2 and chatCount("Équipement cassé") == 1, "presque cassé -> cassé : nouvelle alerte")
alert[3], alert[5] = 0, 0; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(infoRows() == 2, "réparé : rien")
alert[7] = 1; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(infoRows() == 3, "de nouveau abîmé : nouvelle alerte")
ns:Set("durabilityWarn", false)
alert[7] = 2; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(infoRows() == 3, "option coupée : aucune alerte")
ns:Set("durabilityWarn", true)
M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(infoRows() == 3, "réactivée : l'état actuel sert de départ, sans alerte")
alert[7] = 0; M.fireEvent("UPDATE_INVENTORY_ALERTS"); alert[7] = 1; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(infoRows() == 4, "puis alerte au changement suivant")
local worst, pct = ns.Tweaks:Durability()
check(worst == 1 and pct == 25, "Tweaks:Durability() (" .. tostring(worst) .. ", " .. tostring(pct) .. ")")
alert[7] = 0

---------------------------------------------------------------------------
section("réinitialisation et garde-fous")
ns:ResetAll(false); M.advance(0.5)
check(errors:IsEventRegistered("UI_ERROR_MESSAGE"), "après ResetAll : erreurs affichées (défaut)")
-- une API qui plante ne casse pas le code de Blizzard et coupe la fonction après plusieurs erreurs
local savedInfo = C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function() error("boom") end
local blizzBefore = blizzBagUpdates
for _ = 1, 6 do M.advance(0.1); bag1:UpdateItems() end
check(blizzBagUpdates == blizzBefore + 6, "le code de Blizzard continue malgré nos erreurs")
check(chatCount("coupé pour cette session") == 1, "fonction coupée une fois, un seul message")
C_Container.GetContainerItemInfo = savedInfo

do
    -- aucune boucle permanente dans le fichier
    local fh = io.open(ADDON_DIR .. "\\Tweaks.lua", "rb")
    local src = fh:read("*a"); fh:close()
    check(not src:find('SetScript%("OnUpdate"') and not src:find("NewTicker", 1, true), "ni OnUpdate ni ticker dans Tweaks.lua")
end
local stray = {}
for _, name in ipairs(M.newGlobals) do
    if not (name == "PlatyplusDB" or name:find("^SLASH_PLATYPLUS")) then stray[#stray + 1] = name end
end
check(#stray == 0, "aucune globale créée (" .. table.concat(stray, ", ") .. ")")

---------------------------------------------------------------------------
section("connexion : rien si l'état n'a pas changé")
do
    -- nouveau chargement complet, équipement déjà abîmé avant la connexion
    for i = 1, 11 do alert[i] = 0 end
    alert[2] = 1
    M.loggedIn = false
    local ns2 = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Float.lua", "Junk.lua", "Tweaks.lua" })
    local adds = 0
    local add2 = ns2.Float.Add
    ns2.Float.Add = function(self, info) if info.source == "info" then adds = adds + 1 end return add2(self, info) end
    M.fireEvent("ADDON_LOADED", "Platyplus")
    M.fireEvent("UPDATE_INVENTORY_ALERTS")         -- l'inventaire arrive pendant le chargement
    M.fireEvent("PLAYER_LOGIN"); M.loggedIn = true
    M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
    M.advance(1); M.fireEvent("UPDATE_INVENTORY_ALERTS")
    M.advance(6); M.fireEvent("UPDATE_INVENTORY_ALERTS")
    check(adds == 0, "équipement déjà abîmé à la connexion : aucune alerte (" .. adds .. ")")
    alert[2] = 2; M.fireEvent("UPDATE_INVENTORY_ALERTS")
    check(adds >= 1, "puis alerte quand l'état s'aggrave")
end

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
