-- Platyplus : objets obtenus autrement qu'en les ramassant (artisanat, achat, courrier, quête, échange, butin de groupe)
-- On compare le contenu des sacs avant et après chaque changement : un objet dont le total augmente est un gain.
-- Le butin déjà montré par Platyplus (module Loot) est "attendu" et déduit, pour ne jamais apparaître deux fois.
-- La source (Fabriqué, Acheté, Courrier, Quête...) se devine à la fenêtre ouverte ; sinon "Reçu".
local ADDON, ns = ...

local Gains = {}
ns.Gains = Gains

local BAG_FIRST = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0
local BAG_LAST = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
local ITEM_SLOT = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1

local SETTLE = 2            -- secondes après l'entrée dans le monde pendant lesquelles on ne montre rien (chargement des sacs)
local DEBOUNCE = 0.25       -- les changements de sacs arrivent en rafale : on attend qu'ils se calment
local EXPECT_SECONDS = 8    -- durée de vie d'un gain "attendu" (déjà montré par un autre module)
local EQUIP_QUIET = 1.2     -- changer d'équipement déplace des objets entre porté et sacs : on ignore
local QUEST_WINDOW = 5      -- une remise de quête explique les gains qui suivent

-- libellé de source -> clé de ns.SOURCES (le flux affiche la pastille correspondante)
local SOURCE_KEY = {
    ["Reçu"] = "received", ["Quête"] = "quest", ["Fabriqué"] = "crafted",
    ["Acheté"] = "bought", ["Courrier"] = "mail", ["Échangé"] = "trade",
}

-- fenêtres Blizzard dont la présence explique un gain (noms à vérifier sur Forever : absents = ignorés)
local CRAFT_FRAMES = { "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }
local MAIL_FRAMES = { "MailFrame", "InboxFrame" }
local STORAGE_FRAMES = { "BankFrame", "GuildBankFrame", "AccountBankPanel", "BankPanel" }

local counts                  -- [itemID] = { count, link, icon, quality } au dernier relevé ; nil = pas encore relevé
local expected = {}           -- [itemID] = { count, expires }
local lastEquip, lastTurnIn, lastCraft, enteredAt = -100, -100, -100, 0
local CRAFT_WINDOW = 8      -- TRADE_SKILL_ITEM_CRAFTED_RESULT (code de Forever) : l'objet arrive dans les secondes qui suivent
local scheduled = false

local function itemIDOf(link)
    if not link then return nil end
    return tonumber(tostring(link):match("item:(%d+)"))
end

-- Un autre module vient de montrer cet objet : on ne le remontrera pas quand il arrivera dans les sacs.
function Gains:Expect(link, count)
    local id = itemIDOf(link)
    if not id then return end
    local now = GetTime()
    local e = expected[id]
    if not e or e.expires < now then
        e = { count = 0 }
        expected[id] = e
    end
    e.count = e.count + (tonumber(count) or 1)
    e.expires = now + EXPECT_SECONDS
end

-- Une quête vient d'être rendue : les objets qui suivent sont ses récompenses.
function Gains:NoteTurnIn()
    lastTurnIn = GetTime()
end

local function scan()
    local result = {}
    for bag = BAG_FIRST, BAG_LAST do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local r = result[info.itemID]
                if not r then
                    r = { count = 0, link = info.hyperlink, icon = info.iconFileID, quality = info.quality }
                    result[info.itemID] = r
                end
                r.count = r.count + (info.stackCount or 1)
            end
        end
    end
    return result
end

local function anyShown(names)
    for _, name in ipairs(names) do
        local frame = _G[name]
        if frame and frame.IsShown and frame:IsShown() then return true end
    end
    return false
end

-- nil = ne rien montrer (déplacement banque / équipement), sinon le mot placé devant l'objet
local function sourceLabel(now)
    if now - lastEquip < EQUIP_QUIET then return nil end
    if anyShown(STORAGE_FRAMES) then return nil end
    if now - lastTurnIn < QUEST_WINDOW then return "Quête" end
    if now - lastCraft < CRAFT_WINDOW or anyShown(CRAFT_FRAMES) then return "Fabriqué" end
    if MerchantFrame and MerchantFrame:IsShown() then return "Acheté" end
    if anyShown(MAIL_FRAMES) then return "Courrier" end
    if TradeFrame and TradeFrame:IsShown() then return "Échangé" end
    return "Reçu"
end

local function check()
    scheduled = false
    if not ns.db or not ns.db.gainFeed then
        counts = nil
        return
    end
    local now = GetTime()
    local fresh = scan()
    local old = counts
    counts = fresh
    if not old then return end                           -- premier relevé : silencieux
    if now - enteredAt < SETTLE then return end

    for id, e in pairs(expected) do
        if e.expires < now then expected[id] = nil end
    end
    local label = sourceLabel(now)

    for id, new in pairs(fresh) do
        local gain = new.count - (old[id] and old[id].count or 0)
        if gain > 0 then
            local e = expected[id]
            if e then
                local used = math.min(gain, e.count)
                gain = gain - used
                e.count = e.count - used
                if e.count <= 0 then expected[id] = nil end
            end
            if gain > 0 and label and ns.Float then
                ns.Float:Add({
                    icon = new.icon, link = new.link, name = new.link or tostring(id),
                    qty = gain, quality = new.quality, type = ITEM_SLOT, source = SOURCE_KEY[label],
                })
            end
        end
    end
end

local function schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(DEBOUNCE, check)
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        lastEquip = GetTime()
        schedule()
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        lastCraft = GetTime()
        schedule()
    elseif event == "PLAYER_ENTERING_WORLD" then
        enteredAt = GetTime()
        counts = nil
        schedule()
    else
        schedule()
    end
end)

function Gains:Init()
    -- événements pas tous vérifiés sur Forever : un événement refusé par le client est simplement ignoré
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BAG_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
        "TRADE_SKILL_ITEM_CRAFTED_RESULT" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    ns:OnChange("gainFeed", function()
        counts = nil
        schedule()
    end)
    schedule()
end
