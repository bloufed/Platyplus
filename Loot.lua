-- Platyplus : loot instantané
-- LOOT_READY (arg: autoloot) -> on ramasse chaque case tout de suite avec LootSlot().
-- LOOT_SLOT_CLEARED confirme qu'une case a bien été ramassée -> on l'envoie au flux flottant.
local ADDON, ns = ...

local Loot = {}
ns.Loot = Loot

local SlotType = Enum and Enum.LootSlotType or { None = 0, Item = 1, Money = 2, Currency = 3 }

local looting, startedAt = false, 0
local snapshot = {}   -- [slot] = infos lues AVANT le ramassage

-- autoLootDefault = 1 évite que la fenêtre de loot s'affiche et clignote. La valeur d'origine est gardée une fois
-- (ns.db.cvarBackup, comme les réglages du jeu) et remise quand on coupe le loot instantané.
function Loot:EnsureAutoLoot()
    local ok, current = pcall(GetCVar, "autoLootDefault")
    if not ok or current == nil then return end
    if type(ns.db.cvarBackup) ~= "table" then ns.db.cvarBackup = {} end
    local backup = ns.db.cvarBackup
    if ns.db.instantLoot then
        if current ~= "1" then
            if backup.autoLootDefault == nil then backup.autoLootDefault = current end
            pcall(SetCVar, "autoLootDefault", "1")
            ns:Debug("autoLootDefault -> 1")
        end
    elseif backup.autoLootDefault ~= nil then
        pcall(SetCVar, "autoLootDefault", backup.autoLootDefault)
        ns:Debug("autoLootDefault ->", backup.autoLootDefault, "(valeur d'origine)")
        backup.autoLootDefault = nil
    end
end

local function onLootReady(autoloot)
    if not ns.db.instantLoot then return end
    -- autoloot == false quand le modificateur de loot manuel est tenu (Maj par défaut) :
    -- dans ce cas on laisse la fenêtre de loot normale.
    if not autoloot then return end
    -- LOOT_READY peut arriver deux fois pour la même ouverture
    if looting and (GetTime() - startedAt) < 2 then return end

    local count = GetNumLootItems()
    if not count or count == 0 then return end

    looting, startedAt = true, GetTime()
    wipe(snapshot)

    -- de la dernière case à la première : les index ne bougent pas pendant qu'on ramasse
    for slot = count, 1, -1 do
        local slotType = GetLootSlotType(slot)
        if slotType and slotType ~= SlotType.None then
            local icon, name, qty, _, quality, locked = GetLootSlotInfo(slot)
            if not locked then
                snapshot[slot] = {
                    icon = icon, name = name, qty = qty, quality = quality,
                    link = GetLootSlotLink(slot), type = slotType, source = "loot",
                }
                LootSlot(slot)
            end
        end
    end
    ns:Debug("LOOT_READY :", count, "case(s)")
end

local function onSlotCleared(slot)
    local info = snapshot[slot]
    if not info then return end
    snapshot[slot] = nil
    ns.Float:Add(info)
    -- l'objet arrive dans les sacs juste après : on le signale au suivi des gains pour ne pas le montrer deux fois
    if ns.Gains and info.link then ns.Gains:Expect(info.link, info.qty) end
end

local function onLootClosed()
    looting = false
    wipe(snapshot)
end

-- Objet "lié quand ramassé" : Blizzard demande une confirmation, on la valide à ta place
local function onBindConfirm(slot)
    if not ns.db.confirmBind then return end
    if type(ConfirmLootSlot) ~= "function" then return end   -- fonction classique, non vérifiée dans le code Blizzard
    pcall(ConfirmLootSlot, slot)
    -- la fenêtre de confirmation est affichée par Blizzard juste après cet événement : on la ferme à l'image suivante
    C_Timer.After(0, function() StaticPopup_Hide("LOOT_BIND") end)
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "LOOT_READY" then
        onLootReady(...)
    elseif event == "LOOT_SLOT_CLEARED" then
        onSlotCleared(...)
    elseif event == "LOOT_CLOSED" then
        onLootClosed()
    elseif event == "LOOT_BIND_CONFIRM" then
        onBindConfirm(...)
    elseif event == "PLAYER_LOGIN" then
        Loot:EnsureAutoLoot()
    end
end)

function Loot:Init()
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("LOOT_READY")
    frame:RegisterEvent("LOOT_SLOT_CLEARED")
    frame:RegisterEvent("LOOT_CLOSED")
    frame:RegisterEvent("LOOT_BIND_CONFIRM")
    ns:OnChange("instantLoot", function() Loot:EnsureAutoLoot() end)
end
