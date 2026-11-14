-- Platyplus : vente automatique chez les marchands
--
-- Un "cycle de vente" se déclenche à l'ouverture d'un marchand (sauf si Maj est tenu) ou à la demande
-- (ns.Junk:SellNow(), bouton "Vendre (Platyplus)" de la fenêtre du marchand). Il comporte deux phases :
--  1) GRIS (+ liste "toujours vendre") : on appelle d'abord C_MerchantFrame.SellAllJunkItems(), la fonction
--     du bouton "vendre les gris" de Blizzard ; si des objets restent une seconde plus tard (appel refusé ou
--     sans effet), on les vend à la main avec C_Container.UseContainerItem, un par un (ticker de 0,1 s).
--     Si un gris est protégé par la liste "neverSell", on n'appelle PAS la fonction de Blizzard (elle
--     vendrait aussi ce gris) : tout part à la main, uniquement ce que evaluate() autorise.
--  2) ÉQUIPEMENT INUTILE (seulement si ns.db.sellGear) : les sacs sont relus, puis vente à la main, du moins
--     cher au plus cher, au plus gearMaxPerVisit pièces par visite.
-- Un seul rapport final : une ligne d'argent dans le flux flottant, et dans le chat la liste de
-- l'équipement vendu. Rien n'est affiché si rien n'a été vendu.
--
-- Une seule fonction, evaluate(bag, slot, info), décide du sort d'un objet : elle sert à l'aperçu
-- (Junk:BuildList) comme à la vente, donc l'aperçu montre exactement ce qui sera vendu.
local ADDON, ns = ...

local Junk = {}
ns.Junk = Junk

---------------------------------------------------------------------------
-- Constantes
---------------------------------------------------------------------------
local function enumValue(group, name, default)
    local g = Enum and Enum[group]
    local v = g and g[name]
    if type(v) == "number" then return v end
    return default
end

local POOR           = enumValue("ItemQuality", "Poor", 0)
local BAG_FIRST      = enumValue("BagIndex", "Backpack", 0)
local BAG_LAST       = enumValue("BagIndex", "ReagentBag", 5)
local MONEY_SLOT     = enumValue("LootSlotType", "Money", 2)
local ITEM_SLOT      = enumValue("LootSlotType", "Item", 1)
local CLASS_WEAPON   = enumValue("ItemClass", "Weapon", 2)
local CLASS_ARMOR    = enumValue("ItemClass", "Armor", 4)
local ARMOR_COSMETIC = enumValue("ItemArmorSubclass", "Cosmetic", 5)
local BIND_ONACQUIRE = enumValue("ItemBind", "OnAcquire", 1)
local BIND_ONEQUIP   = enumValue("ItemBind", "OnEquip", 2)
local BIND_ONUSE     = enumValue("ItemBind", "OnUse", 3)

-- Sous-classes d'armes qui ne sont pas de "vrais" équipements de combat (NON VÉRIFIÉ : valeurs classiques) :
-- 14 = divers (pioches, marteaux...), 20 = canne à pêche. On ne les vend jamais d'office.
local WEAPON_GENERIC, WEAPON_FISHINGPOLE = 14, 20

local MAX_GEAR_QUALITY = 4          -- jamais au-dessus d'épique, quoi que dise le réglage
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local TICK = 0.1                    -- délai entre deux ventes à la main
local BULK_WAIT = 1                 -- attente après SellAllJunkItems avant de vérifier ce qui reste
local REPORT_DELAY = 0.5            -- attente avant le rapport (le temps que l'argent arrive)

local LIST_OTHER = { neverSell = "alwaysSell", alwaysSell = "neverSell" }

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------
local function formatMoney(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. " po" end
    if silver > 0 then parts[#parts + 1] = silver .. " pa" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. " pc" end
    return table.concat(parts, " ")
end

local function inList(listName, itemID)
    local list = ns.db and ns.db[listName]
    return (type(list) == "table" and list[itemID]) and true or false
end

local function merchantOpen()
    return (MerchantFrame and MerchantFrame:IsShown()) and true or false
end

-- IsSellAllJunkEnabled absent => on considère que c'est autorisé (comme avant)
local function junkAllowedHere()
    if C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled then
        return C_MerchantFrame.IsSellAllJunkEnabled() and true or false
    end
    return true
end

-- Enveloppes des API d'objets : ne renvoient rien si l'API n'existe pas (=> l'objet n'est pas vendu)
local function itemInfo(link)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(link) end
end

local function instantInfo(link)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(link) end
end

local function itemLevel(link)
    if not (C_Item and C_Item.GetDetailedItemLevelInfo) then return nil end
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if type(level) == "number" and level > 0 then return level end
    return nil
end

local function unitSellPrice(link)
    if not link then return 0 end
    local price = select(11, itemInfo(link))
    return tonumber(price) or 0
end

---------------------------------------------------------------------------
-- Équipement : emplacements et familles (chaînes INVTYPE_* : NON VÉRIFIÉ mais stables depuis toujours)
---------------------------------------------------------------------------
local SLOTS = {
    INVTYPE_HEAD = { 1 },  INVTYPE_NECK = { 2 },   INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },   INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },  INVTYPE_FEET = { 8 },   INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
}

local WEAPON_FAMILY = {
    INVTYPE_2HWEAPON = "2h",
    INVTYPE_WEAPON = "1h", INVTYPE_WEAPONMAINHAND = "1h",
    INVTYPE_SHIELD = "shield",
    INVTYPE_WEAPONOFFHAND = "offhand", INVTYPE_HOLDABLE = "offhand",
}

-- "2h" / "1h" / "shield" / "offhand" / "armor" ; nil si l'emplacement n'est pas géré
local function familyOf(equipLoc)
    if not SLOTS[equipLoc] then return nil end
    return WEAPON_FAMILY[equipLoc] or "armor"
end

-- objets portés, lus une seule fois par analyse des sacs : equippedCache[emplacement] = { link, family, level }
local equippedCache = {}

local function equippedSlot(slotId)
    local entry = equippedCache[slotId]
    if entry then return entry end
    entry = {}
    local link = GetInventoryItemLink("player", slotId)
    if link then
        entry.link = link
        local _, _, _, equipLoc = instantInfo(link)
        entry.family = familyOf(equipLoc)
        entry.level = itemLevel(link)
    end
    equippedCache[slotId] = entry
    return entry
end

---------------------------------------------------------------------------
-- Règles "équipement inutile" (prudentes : au moindre doute, on garde)
---------------------------------------------------------------------------
local function isUselessGear(bag, slot, info)
    local db = ns.db
    local link = info.hyperlink
    local quality = info.quality
    if not link or type(quality) ~= "number" then return false end

    -- a. qualité
    local maxQuality = math.min(tonumber(db.gearMaxQuality) or 2, MAX_GEAR_QUALITY)
    if quality > maxQuality then return false end

    -- a. classe : armes et armures seulement, ni cosmétiques ni outils (canne à pêche...)
    local _, _, _, equipLoc, _, classID, subClassID = instantInfo(link)
    if classID ~= CLASS_WEAPON and classID ~= CLASS_ARMOR then return false end
    if classID == CLASS_ARMOR and subClassID == ARMOR_COSMETIC then return false end
    if classID == CLASS_WEAPON and (subClassID == WEAPON_GENERIC or subClassID == WEAPON_FISHINGPOLE) then
        return false
    end
    local slots = SLOTS[equipLoc]
    if not slots then return false end           -- chemise, tabard, distance, relique, sac...

    -- e. objet absent du cache : on ne vend pas (pas d'attente)
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = itemInfo(link)
    if not name then return false end

    -- b. liaison : jamais d'objet lié au compte (7, 8, 9) ni de liaison inconnue
    local sellable = false
    if bindType == BIND_ONACQUIRE or bindType == BIND_ONEQUIP or bindType == BIND_ONUSE then
        if info.isBound == true then
            sellable = true
        elseif db.gearIncludeBoE and bindType == BIND_ONEQUIP then
            sellable = true
        end
    end
    if not sellable then return false end

    -- a. ensemble d'équipement ; si l'appel échoue on garde (prudence)
    local okSet, inSet = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
    if not okSet or inSet then return false end

    -- c. niveau d'objet comparé à ce qui est porté
    local bagLevel = itemLevel(link)
    if not bagLevel then return false end
    local margin = math.max(1, tonumber(db.gearMargin) or 1)
    local family = familyOf(equipLoc)
    local comparable = 0
    for _, slotId in ipairs(slots) do
        local worn = equippedSlot(slotId)
        if not worn.link then return false end             -- emplacement vide : un gain potentiel
        if worn.family == family then
            if not worn.level then return false end        -- niveau porté inconnu
            if worn.level - bagLevel < margin then return false end
            comparable = comparable + 1
        end                                                -- famille incompatible : emplacement ignoré
    end
    if comparable == 0 then return false end

    -- d. apparence pas encore connue : on garde (API NON VÉRIFIÉE : ignorée si absente ou en erreur)
    if db.keepUnknownTransmog then
        local api = C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogByItemInfo
        if api then
            local ok, has = pcall(api, link)
            if ok and has == false then return false end
        end
    end

    return true
end

---------------------------------------------------------------------------
-- Décision : "junk" / "always" / "gear" / nil  (partagée par l'aperçu et la vente)
---------------------------------------------------------------------------
local function evaluate(bag, slot, info)
    if type(info) ~= "table" or not info.itemID then return nil end
    local db = ns.db
    local itemID = info.itemID
    if inList("neverSell", itemID) then return nil end        -- neverSell l'emporte sur tout
    if info.isLocked or info.hasNoValue then return nil end
    if db.sellJunk and info.quality == POOR then return "junk" end
    if inList("alwaysSell", itemID) then return "always" end
    if db.sellGear and isUselessGear(bag, slot, info) then return "gear" end
    return nil
end

---------------------------------------------------------------------------
-- Analyse des sacs
---------------------------------------------------------------------------
local visitGear = 0     -- pièces d'équipement réellement vendues pendant la visite en cours

local function gearBudget()
    local cap = tonumber(ns.db.gearMaxPerVisit)
    if not cap then cap = 12 end
    return math.max(0, math.floor(cap) - visitGear)
end

-- Renvoie la liste ordonnée (gris, toujours vendre, équipement du moins cher au plus cher),
-- et un booléen : y a-t-il un gris protégé par neverSell (la fonction de Blizzard le vendrait).
local function scan()
    equippedCache = {}
    local junk, always, gear = {}, {}, {}
    local protectedJunk = false

    for bag = BAG_FIRST, BAG_LAST do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                if info.quality == POOR and not info.hasNoValue and inList("neverSell", info.itemID) then
                    protectedJunk = true
                end
                local reason = evaluate(bag, slot, info)
                if reason then
                    local count = info.stackCount or 1
                    local entry = {
                        bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                        icon = info.iconFileID, count = count,
                        price = unitSellPrice(info.hyperlink) * count,
                        reason = reason,
                    }
                    local group = (reason == "junk" and junk) or (reason == "always" and always) or gear
                    group[#group + 1] = entry
                end
            end
        end
    end

    table.sort(gear, function(a, b)
        if a.price ~= b.price then return a.price < b.price end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    for i = #gear, gearBudget() + 1, -1 do gear[i] = nil end

    local list = {}
    for _, group in ipairs({ junk, always, gear }) do
        for _, entry in ipairs(group) do list[#list + 1] = entry end
    end
    equippedCache = {}
    return list, protectedJunk
end

local function only(list, reasonA, reasonB)
    local out = {}
    for _, entry in ipairs(list) do
        if entry.reason == reasonA or entry.reason == reasonB then out[#out + 1] = entry end
    end
    return out
end

local function numJunk(list)
    if C_MerchantFrame and C_MerchantFrame.GetNumJunkItems then
        return C_MerchantFrame.GetNumJunkItems() or 0
    end
    return #only(list, "junk")
end

---------------------------------------------------------------------------
-- Cycle de vente
---------------------------------------------------------------------------
local current      -- cycle en cours (nil = libre) : { moneyBefore, lastMoney, earned, attempted, ... }
local ticker       -- ticker de vente à la main
local moneyCycle   -- cycle dont on suit les gains d'argent (jusqu'à son rapport)

local function stopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- note chaque objet tenté (une seule fois) pour le montrer dans le flux flottant après la vente
local function track(cycle, entry)
    local key = entry.bag .. ":" .. entry.slot
    if cycle.seen[key] then return end
    cycle.seen[key] = true
    cycle.attempted[#cycle.attempted + 1] = entry
end

-- Fenêtre de confirmation Blizzard (objet échangeable / remboursable...). Noms NON VÉRIFIÉS : on cherche
-- des mots-clés dans StaticPopup1..N.which. Toute erreur = pas de détection (jamais bloquant).
local function popupBlocking()
    local ok, found = pcall(function()
        for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
            local popup = _G["StaticPopup" .. i]
            local which = popup and popup:IsShown() and popup.which
            if type(which) == "string"
                and (which:find("MERCHANT", 1, true) or which:find("REFUND", 1, true)
                    or which:find("TRADE_TIMER", 1, true) or which:find("SELL", 1, true)) then
                return true
            end
        end
        return false
    end)
    return ok and found or false
end

-- Rapport unique d'un cycle : argent (flux flottant) + liste de l'équipement réellement vendu (chat)
local function report(cycle)
    if cycle.reported then return end
    cycle.reported = true
    if moneyCycle == cycle then moneyCycle = nil end

    -- un objet est vendu si son emplacement ne contient plus le même lien
    local soldGear, soldEntries = {}, {}
    for _, entry in ipairs(cycle.attempted) do
        local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
        if not info or info.itemID ~= entry.itemID or info.hyperlink ~= entry.link then
            soldEntries[#soldEntries + 1] = entry
            if entry.reason == "gear" then soldGear[#soldGear + 1] = entry.link or tostring(entry.itemID) end
        end
    end
    visitGear = visitGear + #soldGear

    -- chaque objet vendu apparaît dans le flux flottant, comme au ramassage
    if ns.db.floatLoot and ns.db.sellFeed and ns.Float then
        for _, entry in ipairs(soldEntries) do
            ns.Float:Add({
                icon = entry.icon, link = entry.link, name = entry.link or tostring(entry.itemID),
                qty = entry.count, type = ITEM_SLOT, price = entry.price, source = "sold",
            })
        end
    end

    -- différence d'argent ; les gains suivis par PLAYER_MONEY écartent une éventuelle réparation automatique
    local gained = math.max(GetMoney() - cycle.moneyBefore, cycle.earned)
    if gained > 0 then
        local text = ns.Tf("Vendu : %s", formatMoney(gained))
        if ns.db.floatLoot and ns.Float then
            ns.Float:Add({ icon = COIN_ICON, name = text, money = gained, source = "sold", qty = 0, quality = 0, type = MONEY_SLOT })
        else
            ns:Print(text)
        end
    end
    if #soldGear > 0 then
        ns:Print(ns.Tf("Équipement vendu : %s", table.concat(soldGear, " ")))
    end
end

-- Termine proprement le cycle : libère le drapeau "occupé" une fois le rapport fait
local function finish(cycle)
    if current ~= cycle or cycle.finishing then return end
    cycle.finishing = true
    C_Timer.After(REPORT_DELAY, function()
        report(cycle)
        if current == cycle then current = nil end
    end)
end

-- Interrompt le cycle en cours (marchand fermé ou rouvert) ; ce qui a déjà été vendu est quand même rapporté
local function abortCycle()
    local cycle = current
    current = nil
    stopTicker()
    if cycle and not cycle.finishing then
        cycle.finishing = true
        C_Timer.After(REPORT_DELAY, function() report(cycle) end)
    end
end

-- La confirmation de Blizzard attend une décision du joueur : on arrête le cycle et on le prévient
local function stopOnPopup(cycle)
    cycle.blocked = true
    ns:Print("vente interrompue : le jeu demande une confirmation (objet échangeable ou remboursable). Réponds-y ou vends cet objet à la main, puis relance la vente.")
    finish(cycle)
end

-- Vend la liste à la main, un objet toutes les 0,1 s ; onDone() est appelé quand la liste est épuisée.
-- Marchand fermé ou fenêtre de confirmation : on arrête tout le cycle.
local function sellByHand(cycle, list, onDone)
    local index = 0
    ns:Debug("vente à la main :", #list, "objet(s)")
    stopTicker()
    ticker = C_Timer.NewTicker(TICK, function(self)
        if current ~= cycle then
            self:Cancel()
            if ticker == self then ticker = nil end
            return
        end
        index = index + 1
        local entry = list[index]
        if not entry then
            self:Cancel()
            ticker = nil
            onDone()
            return
        end
        if not merchantOpen() then
            self:Cancel()
            ticker = nil
            finish(cycle)
            return
        end

        -- une fenêtre de confirmation encore ouverte : on ne vend rien de plus
        if popupBlocking() then
            self:Cancel()
            ticker = nil
            stopOnPopup(cycle)
            return
        end

        -- les sacs ont pu bouger : on revérifie que c'est bien le même objet et qu'il doit toujours partir
        local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
        equippedCache = {}
        local reason = info and info.itemID == entry.itemID and evaluate(entry.bag, entry.slot, info)
        equippedCache = {}
        if reason then
            track(cycle, entry)
            C_Container.UseContainerItem(entry.bag, entry.slot)
            if popupBlocking() then
                self:Cancel()
                ticker = nil
                stopOnPopup(cycle)
            end
        end
    end)
end

-- Phase 2 : équipement inutile (les sacs sont relus : l'état a changé après les gris)
local function gearPhase(cycle)
    if current ~= cycle then return end
    if not ns.db.sellGear then return finish(cycle) end
    local list = only(scan(), "gear")
    if #list == 0 then return finish(cycle) end
    ns:Debug("équipement à vendre :", #list)
    sellByHand(cycle, list, function() finish(cycle) end)
end

-- Combien de gris la fonction de Blizzard va vendre (0 = on ne l'utilise pas : désactivée, indisponible,
-- ou un gris est protégé par neverSell et serait vendu par erreur)
local function bulkJunkCount(list, protectedJunk)
    if not ns.db.sellJunk or protectedJunk or not junkAllowedHere() then return 0 end
    if not (C_MerchantFrame and C_MerchantFrame.SellAllJunkItems) then return 0 end
    return numJunk(list)
end

-- Phase 1 : gris (+ "toujours vendre"). list / protectedJunk viennent de scan().
local function junkPhase(cycle, list, protectedJunk)
    local junkReason = junkAllowedHere() and "junk" or nil
    local phase = only(list, junkReason, "always")
    local nextPhase = function() gearPhase(cycle) end
    local count = bulkJunkCount(list, protectedJunk)

    if count > 0 then
        ns:Debug("gris à vendre :", count)
        for _, e in ipairs(only(list, "junk")) do track(cycle, e) end
        C_MerchantFrame.SellAllJunkItems()
        C_Timer.After(BULK_WAIT, function()
            if current ~= cycle then return end
            if not merchantOpen() then return finish(cycle) end
            local rest = only((scan()), junkReason, "always")
            if #rest > 0 then
                sellByHand(cycle, rest, nextPhase)
            else
                nextPhase()
            end
        end)
    elseif #phase > 0 then
        sellByHand(cycle, phase, nextPhase)
    else
        nextPhase()
    end
end

-- Lance un cycle complet. Renvoie false (sans rien faire) s'il n'y a rien à vendre.
local function startCycle()
    local list, protectedJunk = scan()
    local junkReason = junkAllowedHere() and "junk" or nil
    if #only(list, junkReason, "always") == 0 and #only(list, "gear") == 0
        and bulkJunkCount(list, protectedJunk) == 0 then
        return false
    end
    local now = GetMoney()
    current = { moneyBefore = now, lastMoney = now, earned = 0, attempted = {}, seen = {} }
    moneyCycle = current
    junkPhase(current, list, protectedJunk)
    return true
end

---------------------------------------------------------------------------
-- Bouton sur la fenêtre du marchand
---------------------------------------------------------------------------
local button

local function showTooltip(self)
    if not GameTooltip then return end
    local list = Junk:BuildList()
    local total, counts = 0, { junk = 0, always = 0, gear = 0 }
    for _, entry in ipairs(list) do
        total = total + (entry.price or 0)
        counts[entry.reason] = (counts[entry.reason] or 0) + 1
    end

    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(ns.T("Platyplus - vente"), 1, 1, 1)
    if #list == 0 then
        GameTooltip:AddLine(ns.T("Rien à vendre."), 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(ns.Tf("%d objet(s) à vendre", #list), 1, 1, 1)
        GameTooltip:AddLine(ns.Tf("Total estimé : %s", formatMoney(total)), 1, 0.82, 0)
        if counts.junk > 0 then GameTooltip:AddLine(ns.Tf("Gris : %d", counts.junk), 0.7, 0.7, 0.7) end
        if counts.always > 0 then GameTooltip:AddLine(ns.Tf("Toujours vendre : %d", counts.always), 0.7, 0.7, 0.7) end
        if counts.gear > 0 then GameTooltip:AddLine(ns.Tf("Équipement inutile : %d", counts.gear), 0.7, 0.7, 0.7) end
    end
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- créé au premier MERCHANT_SHOW ; ne fait rien si MerchantFrame n'existe pas
local function ensureButton()
    if button or not MerchantFrame then return end

    button = CreateFrame("Button", nil, MerchantFrame)
    button:SetSize(96, 18)
    button:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -28, -4)
    if MerchantFrame.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel(MerchantFrame:GetFrameLevel() + 10)
    end

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.45, 0.45, 0.45, 1)
    local bg = button:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(1, 1, 1, 0.15)

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("|T" .. ns.LOGO .. ":14:14:0:0|t " .. ns.T("Vendre"))

    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function()
        hideTooltip()
        Junk:SellNow()
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
end

---------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------

-- Liste ordonnée de ce qui SERAIT vendu maintenant (sans condition de marchand ouvert) :
-- gris, puis "toujours vendre", puis équipement du moins cher au plus cher (coupé à gearMaxPerVisit).
-- Entrées : { bag, slot, itemID, link, icon, count, price (cuivre, pile entière), reason = "junk"|"always"|"gear" }
function Junk:BuildList()
    if not ns.db then return {} end
    return (scan())
end

-- Déclenche tout le cycle à la demande (Maj ignoré : action volontaire)
function Junk:SellNow()
    if not merchantOpen() then
        ns:Print("ouvre d'abord un marchand")
        return
    end
    if current then
        ns:Print("une vente est déjà en cours")
        return
    end
    if not startCycle() then
        ns:Print("rien à vendre")
    end
end

-- De combien de niveaux d'objet cette pièce améliore ce que tu portes (utilisé pour choisir une récompense de quête).
-- nil = pas de la bonne sorte (ce n'est pas une arme ni une armure, ou emplacement non géré) ou niveau inconnu ;
-- 1000 = l'emplacement est vide ; sinon la meilleure différence parmi les emplacements comparables (négatif = moins bon).
function Junk:UpgradeDelta(link)
    if not link then return nil end
    local _, _, _, equipLoc, _, classID = instantInfo(link)
    if classID ~= CLASS_WEAPON and classID ~= CLASS_ARMOR then return nil end
    local slots = SLOTS[equipLoc]
    if not slots then return nil end
    local level = itemLevel(link)
    if not level then return nil end

    equippedCache = {}
    local family = familyOf(equipLoc)
    local best
    for _, slotId in ipairs(slots) do
        local worn = equippedSlot(slotId)
        if not worn.link then
            best = 1000
        elseif worn.family == family and worn.level then
            local delta = level - worn.level
            if not best or delta > best then best = delta end
        end
    end
    equippedCache = {}
    return best
end

-- valide les arguments : renvoie l'itemID (entier > 0) ou nil ; listName = "neverSell" ou "alwaysSell"
local function checkListArgs(listName, itemID)
    if type(listName) ~= "string" or not LIST_OTHER[listName] then return nil end
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 or itemID > 2147483647 or itemID ~= math.floor(itemID) then return nil end
    return itemID
end

-- Ajoute l'objet à la liste (et le retire de l'autre) ; renvoie true si les arguments sont valides
function Junk:AddToList(listName, itemID)
    itemID = checkListArgs(listName, itemID)
    if not itemID then
        ns:Debug("AddToList : arguments invalides")
        return false
    end
    local list = ns.db[listName]
    if type(list) ~= "table" then
        ns:Set(listName, {})
        list = ns.db[listName]
    end
    list[itemID] = true

    -- un objet ne peut être que dans une des deux listes
    local otherName = LIST_OTHER[listName]
    local other = ns.db[otherName]
    local otherChanged = (type(other) == "table" and other[itemID] ~= nil)
    if otherChanged then other[itemID] = nil end

    ns:Notify(listName)
    if otherChanged then ns:Notify(otherName) end
    return true
end

-- Retire l'objet de la liste ; renvoie true si les arguments sont valides
function Junk:RemoveFromList(listName, itemID)
    itemID = checkListArgs(listName, itemID)
    if not itemID then
        ns:Debug("RemoveFromList : arguments invalides")
        return false
    end
    local list = ns.db[listName]
    if type(list) == "table" then list[itemID] = nil end
    ns:Notify(listName)
    return true
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local function onMerchantShow()
    abortCycle()      -- sécurité : un cycle resté ouvert d'une visite précédente
    visitGear = 0
    if IsShiftKeyDown() then
        ns:Debug("Maj tenu : aucune vente automatique")
    else
        startCycle()
    end
    ensureButton()
end

local function onPlayerMoney()
    local cycle = moneyCycle
    if not cycle then return end
    local now = GetMoney()
    if now > cycle.lastMoney then cycle.earned = cycle.earned + (now - cycle.lastMoney) end
    cycle.lastMoney = now
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        onMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        abortCycle()
    elseif event == "PLAYER_MONEY" then
        onPlayerMoney()
    end
end)

function Junk:Init()
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    frame:RegisterEvent("PLAYER_MONEY")
end
