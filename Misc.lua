-- Platyplus : confort
--  * réparation automatique chez les marchands (argent de guilde si possible)
--  * alerte "sacs presque pleins"
--  * invitations de groupe (amis / guilde), invitations de guilde, duels, invocations, résurrections
--  * masquer les têtes parlantes
--  * zoom maximum de la caméra
--  * tri des sacs
-- Chaque fonction a son interrupteur dans ns.db ; un événement n'est enregistré que si son option est active.
local ADDON, ns = ...

local Misc = {}
ns.Misc = Misc

local BAG_FIRST = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0
local BAG_LAST = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
local MONEY_SLOT = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local ZOOM_CVAR = "cameraDistanceMaxZoomFactor"
local DEFAULT_ZOOM = 1.9      -- valeur par défaut du jeu, remise quand on coupe l'option

-- { événement, réglage qui l'active } : l'événement n'est enregistré que si ns.db[réglage] est vrai
local EVENT_OPTIONS = {
    { "MERCHANT_SHOW",          "autoRepair" },
    { "BAG_UPDATE_DELAYED",     "bagWarn" },
    { "PARTY_INVITE_REQUEST",   "acceptInvites" },
    { "GUILD_INVITE_REQUEST",   "declineGuildInvites" },
    { "DUEL_REQUESTED",         "declineDuels" },       -- NON VÉRIFIÉ
    { "CONFIRM_SUMMON",         "acceptSummon" },       -- NON VÉRIFIÉ
    { "RESURRECT_REQUEST",      "acceptRes" },          -- NON VÉRIFIÉ
    { "TALKINGHEAD_REQUESTED",  "hideTalkingHead" },    -- NON VÉRIFIÉ
}
local EVENT_KEY = {}
for _, pair in ipairs(EVENT_OPTIONS) do EVENT_KEY[pair[1]] = pair[2] end

local frame = CreateFrame("Frame")   -- l'unique cadre d'événements du module
local handlers = {}           -- handlers[événement] = fonction(...)
local registered = {}         -- [événement] = true tant qu'il est enregistré
local unknown = {}            -- [événement] = true si le client l'a refusé (déjà signalé)
local initialized = false

local armed = nil             -- sacs : nil = état initial pas encore mémorisé, true = prêt à alerter, false = déjà alerté
local cameraChanged = false   -- true si on a modifié le zoom pendant cette session

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

-- Appelle fn(...) sous pcall si c'est bien une fonction.
-- Retourne false (fonction absente ou erreur), sinon true + les deux premiers résultats.
local function try(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        ns:Debug("appel refusé :", tostring(a))
        return false
    end
    return true, a, b
end

-- exécute fn à la prochaine image (une seule fois, pas de ticker)
local function nextFrame(fn)
    if C_Timer and C_Timer.After then C_Timer.After(0, fn) end
end

-- Ferme des popups sans appeler leur OnCancel. Refait une fois à l'image suivante : si notre
-- gestionnaire passe avant celui de Blizzard, la popup n'existait pas encore au premier appel.
local function hidePopups(...)
    local names = { ... }
    local function hide()
        for _, name in ipairs(names) do try(StaticPopup_Hide, name) end
    end
    hide()
    nextFrame(hide)
end

local function formatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. " po" end
    if silver > 0 then parts[#parts + 1] = silver .. " pa" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. " pc" end
    return table.concat(parts, " ")
end

local function nameOf(name)
    if name == nil or name == "" then return "?" end
    return tostring(name)
end

---------------------------------------------------------------------------
-- 1. Réparation automatique
---------------------------------------------------------------------------

-- La guilde peut-elle payer ? (retrait autorisé : -1 = illimité ; et fonds de la banque suffisants)
local function guildCanPay(cost)
    if type(CanGuildBankRepair) ~= "function" or not CanGuildBankRepair() then return false end
    if type(GetGuildBankWithdrawMoney) ~= "function" or type(GetGuildBankMoney) ~= "function" then return false end
    local allowed = GetGuildBankWithdrawMoney() or 0
    local bank = GetGuildBankMoney() or 0
    if allowed ~= -1 and allowed < cost then return false end
    return bank >= cost
end

local function announceRepair(cost, guild)
    local text = "Réparé : " .. formatMoney(cost) .. (guild and " (guilde)" or "")
    if ns.Float and ns.Float.Add then
        ns.Float:Add({ icon = COIN_ICON, name = text, money = cost, source = "repair", qty = 0, quality = 0, type = MONEY_SLOT })
    end
    ns:Print(text)
end

-- manual = true : on dit pourquoi rien n'est réparé ; automatique : on se tait quand il n'y a rien à faire
local function doRepair(manual)
    if type(CanMerchantRepair) ~= "function" or type(GetRepairAllCost) ~= "function"
        or type(RepairAllItems) ~= "function" then
        if manual then ns:Print("réparation indisponible dans cette version du jeu") end
        return false
    end
    if not CanMerchantRepair() then
        if manual then ns:Print("ce marchand ne répare pas") end
        return false
    end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then
        if manual then ns:Print("rien à réparer") end
        return false
    end

    if ns.db.repairGuild and guildCanPay(cost) then
        RepairAllItems(true)
        announceRepair(cost, true)
        return true
    end
    if GetMoney() >= cost then
        RepairAllItems()
        announceRepair(cost, false)
        return true
    end
    ns:Print("pas assez d'or pour réparer (il faut " .. formatMoney(cost) .. ")")
    return false
end

handlers.MERCHANT_SHOW = function()
    if IsShiftKeyDown() then return end    -- Maj à l'ouverture : on ne répare pas
    doRepair(false)
end

-- Répare maintenant (marchand ouvert), quel que soit l'interrupteur et même avec Maj.
function Misc:RepairNow()
    if not (MerchantFrame and MerchantFrame:IsShown()) then
        ns:Print("ouvre d'abord un marchand")
        return false
    end
    return doRepair(true)
end

---------------------------------------------------------------------------
-- 2. Sacs presque pleins
---------------------------------------------------------------------------

-- Emplacements libres des sacs 0 à 5. Seuls les sacs "normaux" (famille 0 ou nil) comptent,
-- sauf s'il n'y en a aucun. Retourne nil si l'API est absente.
local function countFreeSlots()
    local C = C_Container
    if not (C and C.GetContainerNumFreeSlots) then return nil end
    local normalFree, specialFree, normalBags = 0, 0, 0
    for bag = BAG_FIRST, BAG_LAST do
        local free, family = C.GetContainerNumFreeSlots(bag)
        free = free or 0
        if not family or family == 0 then
            normalFree = normalFree + free
            local slots = C.GetContainerNumSlots and C.GetContainerNumSlots(bag) or 0
            if (slots or 0) > 0 then normalBags = normalBags + 1 end
        else
            specialFree = specialFree + free
        end
    end
    if normalBags == 0 then return normalFree + specialFree end
    return normalFree
end

local function bagLimit()
    return math.max(0, math.floor(tonumber(ns.db.bagWarnSlots) or 5))
end

local function alertBags(free)
    local text
    if free <= 0 then
        text = "Sacs pleins !"
    elseif free == 1 then
        text = "Sacs presque pleins : 1 emplacement libre"
    else
        text = "Sacs presque pleins : " .. free .. " emplacements libres"
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1, 0.5, 0)
    end
    ns:Print("|cffff8000" .. text .. "|r")
end

-- Une alerte quand on passe à <= seuil ; ré-armée au-dessus de seuil + 2.
-- Le premier passage (connexion, ou réglage modifié) mémorise l'état sans rien dire.
local function checkBags()
    local free = countFreeSlots()
    if not free then return end
    local limit = bagLimit()
    if armed == nil then
        armed = free > limit
    elseif armed then
        if free <= limit then
            armed = false
            alertBags(free)
        end
    elseif free > limit + 2 then
        armed = true
    end
end

local function resetBagState()
    armed = nil
    if ns.db.bagWarn then checkBags() end
end

handlers.BAG_UPDATE_DELAYED = checkBags

---------------------------------------------------------------------------
-- 3 à 8. Invitations, duels, invocations, résurrections, têtes parlantes
---------------------------------------------------------------------------

-- ami (personnage ou Battle.net) ou membre de la guilde
local function isTrusted(guid)
    if not guid then return false end
    if C_FriendList then
        local ok, isFriend = try(C_FriendList.IsFriend, guid)
        if ok and isFriend then return true end
    end
    if C_BattleNet then
        local ok, info = try(C_BattleNet.GetAccountInfoByGUID, guid)
        if ok and type(info) == "table" and (info.isFriend or info.isBattleTagFriend) then return true end
    end
    local ok, inGuild = try(IsPlayerInGuildFromGUID, guid)
    return (ok and inGuild) and true or false
end

-- PARTY_INVITE_REQUEST : name, isTank, isHealer, isDamage, isNativeRealm, allowMultipleRoles, inviterGUID, ...
handlers.PARTY_INVITE_REQUEST = function(name, _, _, _, _, _, guid)
    if not isTrusted(guid) then
        ns:Debug("invitation de groupe ignorée :", nameOf(name))
        return
    end
    if not try(AcceptGroup) then                       -- NON VÉRIFIÉ
        ns:Debug("AcceptGroup indisponible")
        return
    end
    hidePopups("PARTY_INVITE")
    ns:Print("Invitation de " .. nameOf(name) .. " acceptée")
end

-- GUILD_INVITE_REQUEST : inviter, guildName, ...
handlers.GUILD_INVITE_REQUEST = function(inviter, guildName)
    if not try(DeclineGuild) then                      -- NON VÉRIFIÉ
        ns:Debug("DeclineGuild indisponible")
        return
    end
    hidePopups("GUILD_INVITE")
    local text = "Invitation de guilde de " .. nameOf(inviter)
    if guildName and guildName ~= "" then text = text .. " (" .. tostring(guildName) .. ")" end
    ns:Print(text .. " refusée")
end

-- DUEL_REQUESTED : challenger
handlers.DUEL_REQUESTED = function(challenger)
    if not try(CancelDuel) then                        -- NON VÉRIFIÉ
        ns:Debug("CancelDuel indisponible")
        return
    end
    hidePopups("DUEL_REQUESTED")
    ns:Print("Duel de " .. nameOf(challenger) .. " refusé")
end

-- CONFIRM_SUMMON : seulement hors combat
handlers.CONFIRM_SUMMON = function()
    if InCombatLockdown() then
        ns:Debug("invocation non acceptée : en combat")
        return
    end
    local info = C_SummonInfo
    if not (info and info.ConfirmSummon) then
        ns:Debug("C_SummonInfo.ConfirmSummon indisponible")
        return
    end
    -- le nom se lit AVANT de confirmer
    local _, summoner = try(info.GetSummonConfirmSummoner)
    if not try(info.ConfirmSummon) then return end
    hidePopups("CONFIRM_SUMMON")
    ns:Print("Invocation de " .. nameOf(summoner) .. " acceptée")
end

-- RESURRECT_REQUEST : offerer ; seulement hors combat
handlers.RESURRECT_REQUEST = function(offerer)
    if InCombatLockdown() then
        ns:Debug("résurrection non acceptée : en combat")
        return
    end
    if not try(AcceptResurrect) then                   -- NON VÉRIFIÉ
        ns:Debug("AcceptResurrect indisponible")
        return
    end
    -- Blizzard affiche l'une des trois popups selon la maladie de résurrection / le délai
    hidePopups("RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER")
    ns:Print("Résurrection de " .. nameOf(offerer) .. " acceptée")
end

local function closeTalkingHead()
    local head = TalkingHeadFrame
    if head and type(head.CloseImmediately) == "function" then
        try(head.CloseImmediately, head)
        return true
    end
    return false
end

-- Le cadre est chargé à la demande : on réessaie une fois à l'image suivante au cas où
-- il aurait été créé / affiché après nous.
handlers.TALKINGHEAD_REQUESTED = function()
    closeTalkingHead()
    nextFrame(closeTalkingHead)
end

---------------------------------------------------------------------------
-- 9. Zoom de la caméra
---------------------------------------------------------------------------

-- N'écrit le CVar que si cameraZoom est actif ; à la désactivation, remet 1.9 seulement
-- si on l'avait modifié pendant cette session.
function Misc:ApplyCamera()
    if ns.db.cameraZoom then
        local factor = tonumber(ns.db.cameraZoomFactor)
        if not factor or factor <= 0 then
            ns:Debug("facteur de zoom invalide :", tostring(ns.db.cameraZoomFactor))
            return false
        end
        local ok, result = pcall(SetCVar, ZOOM_CVAR, factor)
        if ok and result ~= false then
            cameraChanged = true
            ns:Debug("zoom caméra ->", factor)
            return true
        end
        ns:Debug("zoom caméra refusé par le jeu")
        return false
    elseif cameraChanged then
        local ok, result = pcall(SetCVar, ZOOM_CVAR, DEFAULT_ZOOM)
        if ok and result ~= false then
            cameraChanged = false
            ns:Debug("zoom caméra remis à", DEFAULT_ZOOM)
            return true
        end
    end
    return false
end

-- Connexion : applique le zoom voulu et mémorise l'état des sacs (sans alerte).
handlers.PLAYER_LOGIN = function()
    pcall(frame.UnregisterEvent, frame, "PLAYER_LOGIN")
    Misc:ApplyCamera()
    if ns.db.bagWarn then checkBags() end
end

---------------------------------------------------------------------------
-- 10. Tri des sacs
---------------------------------------------------------------------------

function Misc:SortBags()
    if InCombatLockdown() then
        ns:Print("impossible de trier les sacs en combat")
        return false
    end
    local ok = false
    if C_Container and type(C_Container.SortBags) == "function" then   -- NON VÉRIFIÉ
        ok = pcall(C_Container.SortBags)
    end
    if not ok and type(SortBags) == "function" then                    -- NON VÉRIFIÉ
        ok = pcall(SortBags)
    end
    if ok then
        ns:Print("tri des sacs lancé")
    else
        ns:Print("tri des sacs indisponible dans cette version du jeu")
    end
    return ok
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
frame:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if not fn then return end
    local key = EVENT_KEY[event]
    if key and not ns.db[key] then return end   -- l'option a été coupée entre-temps
    fn(...)
end)

-- (dés)enregistre l'événement selon l'état de son option ; loud = on prévient si le client ne le connaît pas
local function syncEvent(event, loud)
    local want = ns.db[EVENT_KEY[event]] and true or false
    if want == (registered[event] or false) then return end
    if want then
        if pcall(frame.RegisterEvent, frame, event) then
            registered[event] = true
        elseif not unknown[event] then
            unknown[event] = true
            local text = "événement " .. event .. " inconnu de ce client : l'option « "
                .. EVENT_KEY[event] .. " » reste sans effet"
            if loud then ns:Print(text) else ns:Debug(text) end
        end
    else
        pcall(frame.UnregisterEvent, frame, event)
        registered[event] = false
    end
end

function Misc:Init()
    if initialized then return end
    initialized = true

    for _, pair in ipairs(EVENT_OPTIONS) do
        local event = pair[1]
        syncEvent(event, false)
        ns:OnChange(pair[2], function() syncEvent(event, true) end)
    end

    ns:OnChange("bagWarn", resetBagState)
    ns:OnChange("bagWarnSlots", resetBagState)
    ns:OnChange("cameraZoom", function() Misc:ApplyCamera() end)
    ns:OnChange("cameraZoomFactor", function() Misc:ApplyCamera() end)

    frame:RegisterEvent("PLAYER_LOGIN")
    if IsLoggedIn and IsLoggedIn() then handlers.PLAYER_LOGIN() end
end

---------------------------------------------------------------------------
-- Touches « manger » et « boire » (ns.Eat)
-- Rangées ici plutôt que dans un nouveau fichier : le jeu ne voit un fichier ajouté à un addon qu'après un
-- redémarrage complet, alors qu'un /reload suffit pour un fichier existant.
-- * Touche pour manger (eatKey) : hors combat la meilleure nourriture, EN COMBAT la meilleure potion de soins.
--   Touche pour boire (drinkKey) : hors combat la meilleure boisson, en combat la meilleure potion de mana.
-- * Chaque touche est liée (override binding, propriétaire à part : indépendant de Interact) à un bouton sécurisé
--   de type « macro » : « /use [combat] item:POTION; item:NOURRITURE ». Les attributs d'un bouton sécurisé ne
--   changent pas en combat, mais la condition [combat] est évaluée par le jeu au moment de l'appui : la macro,
--   préparée hors combat, choisit seule. Vérifié dans Forever (SecureTemplates.lua : SECURE_ACTIONS.macro ->
--   C_Macro.RunMacroText). « item:ID » : jamais « sac emplacement » (un sac réorganisé n'utilise jamais autre chose).
-- * Reconnaissance par le sort d'utilisation de l'objet (C_Item.GetItemSpell -> nom, id), jamais par la sous-classe
--   (constaté en jeu sur Forever : la nourriture n'est pas toujours en « Nourriture et boissons ») :
--     nourriture = nom qui commence par celui du sort 433 « Nourriture » (« Nourriture et boisson » compte) ;
--     boisson    = nom qui contient celui du sort 430 « Boisson » (« Nourriture et boisson » compte aussi) ;
--     potion de soins / de mana = sort de la liste des potions connues, ou même nom que le sort 441 / 437.
--   Les noms sont lus dans le jeu (donc dans sa langue), avec un repli anglais / français.
-- * La plus haute = niveau requis le plus haut, puis niveau d'objet, parmi ce que tu peux utiliser
--   (C_Item.IsUsableItem) ; à égalité, celle dont il te reste le moins (libère une place dans les sacs).
-- * Le choix est refait hors combat, aux changements de sacs et de niveau, puis après le combat.
-- * Optimisation : les événements de sacs ne sont écoutés que si une touche est choisie.
---------------------------------------------------------------------------
do
    local Eat = {}
    ns.Eat = Eat

    local CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
    local BAG_EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP" }

    local function idSet(list)
        local t = {}
        for _, id in ipairs(list) do t[id] = true end
        return t
    end

    -- sortes d'objets : sort de référence (nom lu dans le jeu), repli, règle de nom, sorts connus
    local KINDS = {
        food  = { spell = 433, fallback = { "Food", "Nourriture" }, rule = "prefix", label = "nourriture" },
        drink = { spell = 430, fallback = { "Drink", "Boisson" }, rule = "contains", label = "boisson" },
        heal  = { spell = 441, fallback = { "Healing Potion", "Potion de soins" }, rule = "prefix", label = "potion de soins",
                  ids = idSet({ 439, 440, 441, 2024, 4042, 17534, 28495, 43185, 53144 }) },
        mana  = { spell = 437, fallback = { "Restore Mana", "Rappel de mana", "Restauration de mana" }, rule = "prefix",
                  label = "potion de mana", ids = idSet({ 437, 438, 2023, 11903, 17530, 17531, 28499, 43186, 53146 }) },
    }
    local KIND_ORDER = { "food", "drink", "heal", "mana" }

    -- les deux touches : sorte d'objet hors combat / en combat
    local ROLES = {
        { id = "eat", key = "eatKey", button = "PlatyplusEatButton", rest = "food", combat = "heal",
          verb = "manger", restMissing = "rien à manger dans tes sacs", combatMissing = "aucune potion de soins dans tes sacs" },
        { id = "drink", key = "drinkKey", button = "PlatyplusDrinkButton", rest = "drink", combat = "mana",
          verb = "boire", restMissing = "rien à boire dans tes sacs", combatMissing = "aucune potion de mana dans tes sacs" },
    }
    local ROLE = {}
    for _, r in ipairs(ROLES) do ROLE[r.id] = r end

    local owner = CreateFrame("Frame")    -- propriétaire des liaisons de ces deux touches
    local events = CreateFrame("Frame")
    local best = {}           -- best[sorte] = { id, name, link, icon, count, minLevel, ilvl } ou nil
    local dirty = true        -- les sacs ont peut-être changé depuis le dernier choix
    local pending = false     -- quelque chose attend la fin du combat
    local listening = false   -- événements de sacs enregistrés
    local warned = {}         -- [rôle] = conflit déjà expliqué
    local lastMissing = {}    -- [rôle] = heure du dernier message « rien à ... »

    local function keyOf(role)
        local key = ns.db and ns.db[role.key]
        if type(key) == "string" and key ~= "" then return key end
    end

    local function anyKey()
        for _, r in ipairs(ROLES) do if keyOf(r) then return true end end
        return false
    end

    -- noms reconnus pour une sorte (lus une fois)
    local function namesOf(kind)
        if kind.names then return kind.names end
        local list = {}
        local spell = rawget(_G, "C_Spell")
        if type(spell) == "table" and spell.GetSpellName then
            local ok, name = pcall(spell.GetSpellName, kind.spell)
            if ok and type(name) == "string" and name ~= "" then list[1] = name end
        end
        for _, name in ipairs(kind.fallback) do list[#list + 1] = name end
        kind.names = list
        return list
    end

    local function matches(kind, spellName, spellID)
        if kind.ids and spellID and kind.ids[spellID] then return true end
        if type(spellName) ~= "string" then return false end
        local lower = spellName:lower()
        for _, name in ipairs(namesOf(kind)) do
            if kind.rule == "contains" then
                if lower:find(name:lower(), 1, true) then return true end
            elseif spellName:sub(1, #name) == name then
                return true
            end
        end
        return false
    end

    local function better(a, b)
        if not b then return true end
        if a.minLevel ~= b.minLevel then return a.minLevel > b.minLevel end
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        return a.count < b.count
    end

    -- fiche d'un consommable utilisable : sorte(s) reconnue(s) ; renvoie fiche, { sorte = true } (ou nil)
    local function classify(id, items)
        local ok, _, _, _, _, icon, classID = pcall(items.GetItemInfoInstant, id)
        if not ok or classID ~= CONSUMABLE then return nil end
        local okSpell, spellName, spellID = pcall(items.GetItemSpell, id)
        if not okSpell then return nil end
        local kinds
        for _, k in ipairs(KIND_ORDER) do
            if matches(KINDS[k], spellName, spellID) then
                kinds = kinds or {}
                kinds[k] = true
            end
        end
        if not kinds then return nil end
        local okUse, usable = pcall(items.IsUsableItem, id)
        if not okUse or not usable then return nil end
        local okInfo, name, link, _, ilvl, minLevel = pcall(items.GetItemInfo, id)
        if not okInfo then name, link, ilvl, minLevel = nil, nil, nil, nil end
        local okCount, count = pcall(items.GetItemCount, id)
        return {
            id = id, name = name, link = link, icon = icon,
            ilvl = tonumber(ilvl) or 0, minLevel = tonumber(minLevel) or 0,
            count = (okCount and tonumber(count)) or 0,
        }, kinds
    end

    -- parcourt les sacs (une fois par objet différent) et retient le meilleur de chaque sorte
    local function scan()
        dirty = not listening    -- sans événements de sacs, on rescanne à chaque demande
        for k in pairs(KINDS) do best[k] = nil end
        local items, bags = rawget(_G, "C_Item"), rawget(_G, "C_Container")
        if type(items) ~= "table" or type(bags) ~= "table" then return end
        local seen = {}
        for bag = BAG_FIRST, BAG_LAST do
            local okSlots, slots = pcall(bags.GetContainerNumSlots, bag)
            for slot = 1, (okSlots and tonumber(slots)) or 0 do
                local okItem, info = pcall(bags.GetContainerItemInfo, bag, slot)
                local id = okItem and type(info) == "table" and info.itemID
                if id and not seen[id] then
                    seen[id] = true
                    local c, kinds = classify(id, items)
                    if c then
                        for k in pairs(kinds) do
                            if better(c, best[k]) then best[k] = c end
                        end
                    end
                end
            end
        end
    end

    -- macro d'une touche : en combat la potion, sinon la nourriture / boisson (évalué par le jeu à l'appui)
    local function macroFor(role)
        local rest, combat = best[role.rest], best[role.combat]
        if rest and combat then return "/use [combat] item:" .. combat.id .. "; item:" .. rest.id end
        if rest then return "/use [nocombat] item:" .. rest.id end
        if combat then return "/use [combat] item:" .. combat.id end
        return nil
    end

    local function applyMacros()
        for _, role in ipairs(ROLES) do
            local b = role.frame
            if b then
                local want = macroFor(role)
                if b:GetAttribute("macrotext") ~= want then b:SetAttribute("macrotext", want) end
            end
        end
    end

    local function refresh()
        if InCombatLockdown() then
            dirty, pending = true, true
            return
        end
        scan()
        applyMacros()
    end

    local function createButtons()
        if InCombatLockdown() then return end
        for _, role in ipairs(ROLES) do
            if not role.frame then
                local b = CreateFrame("Button", role.button, UIParent, "SecureActionButtonTemplate")
                b:SetAttribute("type", "macro")
                b:SetAttribute("useOnKeyDown", true)   -- agit à l'appui de la touche, comme la touche d'interaction
                b:RegisterForClicks("AnyDown")
                -- juste avant d'agir : choix frais si les sacs ont bougé (hors combat), message s'il n'y a rien
                b:SetScript("PreClick", function()
                    local fight = InCombatLockdown()
                    if dirty and not fight then refresh() end
                    local kind = fight and role.combat or role.rest
                    if not best[kind] then
                        local now = GetTime()
                        if now - (lastMissing[role.id] or -10) > 2 then
                            lastMissing[role.id] = now
                            ns:Print(fight and role.combatMissing or role.restMissing)
                        end
                    end
                end)
                role.frame = b
            end
        end
    end

    local function syncEvents()
        local want = anyKey()
        if want == listening then return end
        listening = want
        for _, event in ipairs(BAG_EVENTS) do
            if want then pcall(events.RegisterEvent, events, event) else pcall(events.UnregisterEvent, events, event) end
        end
        dirty = true
    end

    -- motif de refus d'une touche (nil si elle peut être liée)
    local function conflict(role)
        local key = keyOf(role)
        if not key then return nil end
        if key == ns.db.key and ns.db.interact then
            return "la touche pour " .. role.verb .. " est déjà ta touche d'interaction (" .. key .. ") : choisis-en une autre"
        end
        if role.id == "drink" and key == keyOf(ROLE.eat) then
            return "la touche pour boire est déjà ta touche pour manger (" .. key .. ") : choisis-en une autre"
        end
        return nil
    end

    function Eat:ApplyBinding()
        if InCombatLockdown() then
            pending = true
            return
        end
        ClearOverrideBindings(owner)
        for _, role in ipairs(ROLES) do
            local key = keyOf(role)
            if key and role.frame then
                local why = conflict(role)
                if why then
                    if not warned[role.id] then
                        warned[role.id] = true
                        ns:Print(why)
                    end
                else
                    warned[role.id] = false
                    SetOverrideBindingClick(owner, true, key, role.button)
                end
            end
        end
    end

    -- meilleur objet d'une sorte (rescanne si besoin, hors combat)
    function Eat:BestOf(kind)
        if dirty and not InCombatLockdown() then refresh() end
        return best[kind]
    end

    -- compatibilité : la meilleure nourriture
    function Eat:Best()
        return self:BestOf("food")
    end

    local function itemText(b)
        return (b.link or b.name or ("objet " .. b.id)) .. " (il t'en reste " .. b.count .. ")"
    end

    local function shortText(b)
        return (b.link or b.name or ("objet " .. b.id)) .. " |cffbbbbbbx" .. b.count .. "|r"
    end

    -- texte des options : « hors combat : X · en combat : Y »
    function Eat:ChoiceText(roleId)
        local role = ROLE[roleId or "eat"]
        local rest, combat = self:BestOf(role.rest), self:BestOf(role.combat)
        local none = "|cff999999aucune|r"
        return (rest and shortText(rest) or none) .. "  |cff888888·  en combat :|r  " .. (combat and shortText(combat) or none)
    end

    function Eat:Describe(roleId)
        local role = ROLE[roleId or "eat"]
        local key = keyOf(role)
        local keyText = key or ("aucune (/pp " .. (role.id == "eat" and "eat" or "drink") .. " TOUCHE pour en choisir une)")
        local rest, combat = self:BestOf(role.rest), self:BestOf(role.combat)
        return "touche pour " .. role.verb .. " : " .. keyText
            .. " ; hors combat : " .. (rest and itemText(rest) or KINDS[role.rest].label .. " : aucune")
            .. " ; en combat : " .. (combat and itemText(combat) or KINDS[role.combat].label .. " : aucune")
    end

    -- après un changement de touche : on dit ce qui marche, ou pourquoi ça ne marchera pas
    local function announce(role)
        local key = keyOf(role)
        if not key then
            ns:Print("touche pour " .. role.verb .. " retirée")
            return
        end
        if conflict(role) then return end        -- ApplyBinding vient de l'expliquer
        if InCombatLockdown() then
            ns:Print("touche pour " .. role.verb .. " : " .. key .. " (active dès la fin du combat)")
            return
        end
        local rest, combat = Eat:BestOf(role.rest), Eat:BestOf(role.combat)
        local text = "touche pour " .. role.verb .. " : " .. key .. " ; "
            .. (rest and ("hors combat " .. itemText(rest)) or (role.restMissing .. " pour l'instant"))
            .. " ; " .. (combat and ("en combat " .. itemText(combat)) or ("en combat : " .. role.combatMissing))
        ns:Print(text)
        if not rest and not combat then ns:Print("(/pp eat debug montre ce que Platyplus voit dans tes sacs)") end
    end

    -- diagnostic : chaque consommable des sacs, son sort, et ce qu'il est pour Platyplus
    function Eat:Explain()
        local lines = {}
        for _, k in ipairs(KIND_ORDER) do
            lines[#lines + 1] = KINDS[k].label .. " : sort « " .. table.concat(namesOf(KINDS[k]), " », « ") .. " »"
        end
        local items, bags = rawget(_G, "C_Item"), rawget(_G, "C_Container")
        if type(items) ~= "table" or type(bags) ~= "table" then
            lines[#lines + 1] = "API des objets ou des sacs absente de ce client"
            return lines
        end
        local seen, any = {}, false
        for bag = BAG_FIRST, BAG_LAST do
            local okSlots, slots = pcall(bags.GetContainerNumSlots, bag)
            for slot = 1, (okSlots and tonumber(slots)) or 0 do
                local okItem, info = pcall(bags.GetContainerItemInfo, bag, slot)
                local id = okItem and type(info) == "table" and info.itemID
                if id and not seen[id] then
                    seen[id] = true
                    local ok, _, _, _, _, _, classID, subclassID = pcall(items.GetItemInfoInstant, id)
                    if ok and classID == CONSUMABLE then
                        any = true
                        local okName, name = pcall(items.GetItemInfo, id)
                        local okSpell, spellName, spellID = pcall(items.GetItemSpell, id)
                        local okUse, usable = pcall(items.IsUsableItem, id)
                        local found = {}
                        for _, k in ipairs(KIND_ORDER) do
                            if okSpell and matches(KINDS[k], spellName, spellID) then found[#found + 1] = KINDS[k].label end
                        end
                        local why
                        if #found == 0 then
                            why = "sort « " .. tostring(okSpell and spellName or "aucun") .. " » (" .. tostring(okSpell and spellID or "?")
                                .. ") : ni nourriture, ni boisson, ni potion (sous-classe " .. tostring(subclassID) .. ")"
                        elseif not (okUse and usable) then
                            why = table.concat(found, " + ") .. ", mais pas utilisable pour toi en ce moment"
                        else
                            why = table.concat(found, " + ") .. " : OK"
                        end
                        local label = (okName and name) or info.itemName or ("objet " .. id)
                        lines[#lines + 1] = "  " .. tostring(label) .. " : " .. why
                    end
                end
            end
        end
        if not any then lines[#lines + 1] = "  aucun consommable dans tes sacs" end
        for _, role in ipairs(ROLES) do
            local key = keyOf(role)
            if key then
                local action = GetBindingAction(key, true)
                lines[#lines + 1] = "la touche " .. key .. " (" .. role.verb .. ") fait : "
                    .. ((action and action ~= "") and action or "rien")
                    .. " ; macro : " .. tostring(macroFor(role) or "aucune")
            end
        end
        return lines
    end

    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if not pending then return end
            pending = false
            createButtons()
            Eat:ApplyBinding()
            if dirty then refresh() end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            createButtons()
            Eat:ApplyBinding()
        end
        dirty = true
        if anyKey() then refresh() end
    end)

    function Eat:Init()
        if InCombatLockdown() then pending = true else createButtons() end
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        syncEvents()
        for _, role in ipairs(ROLES) do
            ns:OnChange(role.key, function()
                warned[role.id] = false          -- un nouveau choix mérite toujours une explication
                syncEvents()
                Eat:ApplyBinding()
                if anyKey() then refresh() end
                announce(role)
            end)
        end
        ns:OnChange("key", function() Eat:ApplyBinding() end)
        ns:OnChange("interact", function() Eat:ApplyBinding() end)
        if IsLoggedIn and IsLoggedIn() then
            Eat:ApplyBinding()
            if anyKey() then refresh() end
        end
    end
end

---------------------------------------------------------------------------
-- Chat plus confortable (ns.Chat) : liens web cliquables, copie du chat, canaux raccourcis
-- Vérifié dans le code de Forever (Blizzard_ChatFrameBase, Blizzard_SharedXML/ScrollingMessageFrame.lua, LinkUtil,
-- ItemRefHandlersShared.lua) :
-- * filtres : ChatFrameUtil.AddMessageEventFilter(événement, f) ; f(cadre, événement, msg, ...) renvoie true pour cacher,
--   ou false, nouveauMsg, ... (TOUS les arguments suivants, sinon ils sont perdus). Blizzard n'appelle pas les filtres
--   quand le message est secret (restrictions d'instance) : rien n'est touché dans ce cas ;
-- * liens : le type « addon » est réservé aux addons ; un clic déclenche EventRegistry « SetItemRef » (link, text...) ;
-- * historique : cadre:GetNumMessages(), cadre:GetMessageInfo(i) (1 = le plus ancien) ; cadre:TransformMessages(test,
--   transformation) réécrit des lignes, prévu « pour les addons » (barrière sécurisée). Les canaux « [1. Général - Zone] »
--   sont écrits en dur (aucun texte global) : on raccourcit la ligne juste après son ajout (hooksecurefunc sur AddMessage).
-- Jamais : remplacer une méthode, une chaîne globale (CHAT_*_GET) ou une fenêtre popup de Blizzard (fenêtres partagées).
---------------------------------------------------------------------------
do
    local Chat = {}
    ns.Chat = Chat

    local LINK_PREFIX = "addon:Platyplus:url:"
    local URL_EVENTS = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE",
    }
    -- étiquettes courtes des canaux nommés (type du lien |Hchannel:TYPE|h, indépendant de la langue)
    local SHORT = {
        GUILD = "G", OFFICER = "O", PARTY = "Gr", PARTY_LEADER = "Gr", RAID = "R", RAID_LEADER = "R",
        RAID_WARNING = "AR", INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "I",
    }
    local COLOR_LINK = "|cff33ccff"

    local filtersOn, clickHooked = false, false
    local hooked = setmetatable({}, { __mode = "k" })   -- cadres de chat déjà accrochés
    local copyFrame, copyButtons = nil, {}

    local function api(name) return rawget(_G, name) end

    local function isSecret(v)
        local f = api("issecretvalue")
        if type(f) == "function" then
            local ok, s = pcall(f, v)
            return ok and s and true or false
        end
        return false
    end

    ---------------------------------------------------------------------------
    -- Liens web
    local URL_PATTERNS = {
        "https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+",
        "www%.[%w%-]+%.[%w%-%.]+[%w%-%._~:/%?#@!%$&'%*%+,;=%%]*",
    }

    -- « bla https://x.y/z bla » -> lien cliquable ; nil si rien à faire (messages avec liens d'objets laissés tels quels)
    local function linkify(msg)
        if type(msg) ~= "string" or isSecret(msg) then return nil end
        if msg:find("|H", 1, true) or msg:find("|K", 1, true) then return nil end
        local changed = false
        for _, pattern in ipairs(URL_PATTERNS) do
            msg = msg:gsub(pattern, function(url)
                if url:find(LINK_PREFIX, 1, true) then return nil end
                local clean = url:gsub("[%.,;:!%?%)]+$", "")   -- ponctuation finale : pas dans le lien
                local tail = url:sub(#clean + 1)
                changed = true
                return "|H" .. LINK_PREFIX .. clean .. "|h" .. COLOR_LINK .. "[" .. clean .. "]|r|h" .. tail
            end)
            if changed then break end      -- une seule forme par message : pas de lien dans un lien
        end
        return changed and msg or nil
    end
    Chat.Linkify = linkify

    local function urlFilter(_, _, msg, ...)
        if not (ns.db and ns.db.chatLinks) then return false end
        local new = linkify(msg)
        if new then return false, new, ... end
        return false
    end

    ---------------------------------------------------------------------------
    -- Fenêtre de copie (la nôtre : les fenêtres popup de Blizzard sont partagées)
    local function cleanLine(text)
        if type(text) ~= "string" or isSecret(text) then return nil end
        text = text:gsub("|K.-|k", "?")                 -- noms Battle.net protégés
        text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
        text = text:gsub("|H.-|h(.-)|h", "%1")
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return text
    end
    Chat.CleanLine = cleanLine

    local function buildCopy()
        local W = ns.W
        local T = ns.THEME
        local f = CreateFrame("Frame", "PlatyplusCopy", UIParent)
        f:SetSize(600, 380)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:Hide()
        if W and W.Round then
            W.Round(f, "BACKGROUND", -6, 10):SetColor(W.C.bg)
            W.Stroke(f, "BORDER", 0, 10):SetColor(W.C.white, 0.09)
        else
            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(f)
            bg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.97)
        end
        local title = f:CreateFontString(nil, "OVERLAY")
        title:SetFont(ns.Font(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), 15, "")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
        title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        local hint = f:CreateFontString(nil, "OVERLAY")
        hint:SetFont(ns.Font(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), 11, "")
        hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -19)
        hint:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
        hint:SetText(ns.T("Ctrl+C pour copier · Échap pour fermer"))

        local box = CreateFrame("Frame", nil, f)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -44)
        box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(box)
        boxBg:SetColorTexture(0, 0, 0, 0.35)

        local scroll = CreateFrame("ScrollFrame", nil, box)
        scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(600 - 28 - 16)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        -- lecture seule : toute frappe remet le texte d'origine, sélectionné
        edit:SetScript("OnTextChanged", function(self, user)
            if user and f.original then
                self:SetText(f.original)
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(edit)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange() or 0
            local v = (self:GetVerticalScroll() or 0) - delta * 40
            if v < 0 then v = 0 elseif v > range then v = range end
            self:SetVerticalScroll(v)
        end)
        f.title, f.edit, f.scroll = title, edit, scroll
        if UISpecialFrames then table.insert(UISpecialFrames, "PlatyplusCopy") end
        return f
    end

    -- ouvre la fenêtre avec ce texte, tout sélectionné
    function Chat:ShowCopy(titleText, text)
        copyFrame = copyFrame or buildCopy()
        copyFrame.title:SetText(ns.T(titleText or "Copier"))
        copyFrame.original = text or ""
        copyFrame.edit:SetText(copyFrame.original)
        copyFrame:Show()
        copyFrame:Raise()
        copyFrame.edit:SetFocus()
        copyFrame.edit:HighlightText()
        copyFrame.scroll:SetVerticalScroll(copyFrame.scroll:GetVerticalScrollRange() or 0)   -- les plus récents
        return copyFrame
    end

    -- texte d'une fenêtre de chat (lignes secrètes sautées)
    function Chat:ChatText(frame)
        frame = frame or api("SELECTED_CHAT_FRAME") or api("DEFAULT_CHAT_FRAME") or api("ChatFrame1")
        if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return "", 0 end
        local lines, skipped = {}, 0
        local okN, n = pcall(frame.GetNumMessages, frame)
        for i = 1, (okN and tonumber(n)) or 0 do
            local ok, msg = pcall(frame.GetMessageInfo, frame, i)
            local line = ok and cleanLine(msg)
            if line then lines[#lines + 1] = line else skipped = skipped + 1 end
        end
        return table.concat(lines, "\n"), skipped
    end

    function Chat:CopyChat(frame)
        local text, skipped = self:ChatText(frame)
        local f = self:ShowCopy("Copier le chat", text)
        if skipped > 0 then ns:Debug("copie du chat :", skipped, "ligne(s) protégée(s) sautée(s)") end
        return f
    end

    -- clic sur un de nos liens web
    local function onSetItemRef(_, link)
        if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return end
        Chat:ShowCopy("Lien web", link:sub(#LINK_PREFIX + 1))
    end

    ---------------------------------------------------------------------------
    -- Canaux raccourcis
    local function shortenText(msg)
        msg = msg:gsub("(|Hchannel:channel:%d+|h)%[(%d+)%. [^%]]*%]|h", "%1[%2]|h")
        msg = msg:gsub("(|Hchannel:(%u[%u_]*)|h)%[([^%]]+)%]|h", function(head, kind, label)
            local short = SHORT[kind]
            if short and short ~= label then return head .. "[" .. short .. "]|h" end
            return nil
        end)
        return msg
    end
    Chat.Shorten = shortenText

    local function needsShort(message)
        if type(message) ~= "string" or isSecret(message) or not message:find("|Hchannel:", 1, true) then return false end
        return shortenText(message) ~= message
    end

    local function shortenEntry(message, ...)
        return shortenText(message), ...
    end

    local function afterAddMessage(frame)
        if not (ns.db and ns.db.chatShortChannels) or type(frame.TransformMessages) ~= "function" then return end
        pcall(frame.TransformMessages, frame, needsShort, shortenEntry)
    end

    ---------------------------------------------------------------------------
    -- Petit bouton « copier » sur les fenêtres de chat (logo Platyplus, discret)
    local function copyButtonFor(frame)
        if copyButtons[frame] then return copyButtons[frame] end
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(18, 18)
        b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        b:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(b)
        icon:SetTexture(ns.LOGO)
        b:SetAlpha(0.35)
        b:SetScript("OnEnter", function(self)
            self:SetAlpha(1)
            local tip = api("GameTooltip")
            if tip then
                tip:SetOwner(self, "ANCHOR_LEFT")
                tip:SetText(ns.T("Copier le chat"))
                tip:AddLine(ns.T("Ouvre les dernières lignes de cette fenêtre dans une zone de texte (Ctrl+C)."), 1, 1, 1, true)
                tip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            self:SetAlpha(0.35)
            local tip = api("GameTooltip")
            if tip then tip:Hide() end
        end)
        b:SetScript("OnClick", function() Chat:CopyChat(frame) end)
        copyButtons[frame] = b
        return b
    end

    local function chatFrames()
        local list = {}
        for i = 1, tonumber(api("NUM_CHAT_WINDOWS")) or 10 do
            local f = api("ChatFrame" .. i)
            if f then list[#list + 1] = f end
        end
        return list
    end

    ---------------------------------------------------------------------------
    function Chat:Apply()
        -- liens : filtres posés une fois (retirés si l'option est coupée)
        local util = api("ChatFrameUtil")
        local want = ns.db.chatLinks and true or false
        if util and util.AddMessageEventFilter and want ~= filtersOn then
            for _, event in ipairs(URL_EVENTS) do
                if want then
                    pcall(util.AddMessageEventFilter, event, urlFilter)
                elseif util.RemoveMessageEventFilter then
                    pcall(util.RemoveMessageEventFilter, event, urlFilter)
                end
            end
            filtersOn = want
        end
        local registry = api("EventRegistry")
        if want and not clickHooked and registry and registry.RegisterCallback then
            clickHooked = pcall(registry.RegisterCallback, registry, "SetItemRef", onSetItemRef, Chat) and true or false
        end
        -- canaux raccourcis et bouton de copie, sur chaque fenêtre de chat
        for _, frame in ipairs(chatFrames()) do
            if ns.db.chatShortChannels and not hooked[frame] and type(frame.AddMessage) == "function" then
                if pcall(hooksecurefunc, frame, "AddMessage", afterAddMessage) then hooked[frame] = true end
            end
            if ns.db.chatShortChannels then afterAddMessage(frame) end
            if ns.db.chatCopyButton then
                copyButtonFor(frame):Show()
            elseif copyButtons[frame] then
                copyButtons[frame]:Hide()
            end
        end
    end

    function Chat:Init()
        for _, key in ipairs({ "chatLinks", "chatShortChannels", "chatCopyButton" }) do
            ns:OnChange(key, function() Chat:Apply() end)
        end
        Chat:Apply()
    end
end
