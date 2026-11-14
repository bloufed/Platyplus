-- Platyplus : outils partagés sur les ressources et les barres d'action (Resources.lib)
--  Utilisés par Procs.lua, Buffs.lua, HealerMana.lua, Plates.lua et Threat.lua : lecture des barres d'action, coûts
--  des sorts, sorts abordables, garde-fou, valeurs secrètes, enregistrement prudent des événements.
--
-- Optimisation : tout est piloté par les ÉVÉNEMENTS, sans scrutation. Les barres d'action sont relues quand elles
-- changent (ACTIONBAR_SLOT_CHANGED, posture, sorts appris, macros...) et l'état « abordable » quand le jeu le signale ;
-- les rafales d'événements sont regroupées en une seule relecture 0,05 s plus tard. Seul reste un filet très lent
-- (toutes les 5 s, seulement si un module a demandé les barres) pour les coûts qui changent sans prévenir.
--
-- Valeurs secrètes (client Forever, issecretvalue) : sur une valeur secrète, le code d'un addon ne peut ni calculer ni
-- comparer, seulement la passer à string.format puis à FontString:SetText. Les coûts de sorts (C_Spell.GetSpellPowerCost)
-- et IsUsableAction / IsSpellUsable ne sont pas secrets : c'est EUX qui disent si un sort est abordable.

local ADDON, ns = ...

local Resources = {}
ns.Resources = Resources

local lib = {}
Resources.lib = lib

local POWER_MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local FLUSH_DELAY = 0.05       -- regroupe les rafales d'événements des barres d'action
local SAFETY_TICK = 5          -- filet très lent : relit coûts et barres au cas où un événement manque
local MAX_ERRORS = 3           -- erreurs de suite avant de couper une fonction (au lieu de spammer le joueur)

-- noms des boutons des barres d'action par défaut (vérifié dans ActionButtonUtil.lua, 12 boutons par barre)
local DEFAULT_BAR_BASES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

-- noms de secours (le client fournit normalement les siens : RAGE = "Rage", ENERGY = "Énergie"...)
local POWER_NAMES = {
    MANA = "Mana", RAGE = "Rage", FOCUS = "Focalisation", ENERGY = "Énergie", RUNIC_POWER = "Puissance runique",
    COMBO_POINTS = "Points de combo", RUNES = "Runes", SOUL_SHARDS = "Fragments d'âme",
    LUNAR_POWER = "Puissance astrale", HOLY_POWER = "Puissance sacrée", MAELSTROM = "Maelström",
    INSANITY = "Folie", CHI = "Chi", ARCANE_CHARGES = "Charges arcaniques", FURY = "Fureur", PAIN = "Douleur",
    ESSENCE = "Essence",
}

---------------------------------------------------------------------------
-- Outils partagés (Resources.lib)
---------------------------------------------------------------------------

-- vrai si la valeur est secrète (ou si le test lui-même refuse la valeur : c'est alors qu'elle l'est)
function lib.isSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, result = pcall(issecretvalue, value)
    return (not ok) or result == true
end
local isSecret = lib.isSecret

-- nombre ordinaire -> texte avec séparateurs de milliers ; ne jamais l'appeler avec une valeur secrète
function lib.plainNumber(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if type(BreakUpLargeNumbers) == "function" then
        local ok, text = pcall(BreakUpLargeNumbers, value)
        if ok and text then return text end
    end
    return tostring(value)
end

-- 1234 -> "1234" ; 12345 -> "12k" ; pour les coûts affichés sur de petits boutons
function lib.shortNumber(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
    if value >= 10000 then return string.format("%dk", math.floor(value / 1000)) end
    return tostring(value)
end

-- couleur de la ressource (PowerBarColor), éclaircie de lighten (0 = telle quelle, 1 = blanc)
function lib.powerColor(powerType, token, lighten)
    local colors = PowerBarColor
    local c = colors and ((token and colors[token]) or colors[powerType])
    local r, g, b = 1, 1, 1
    if c and c.r then r, g, b = c.r, c.g, c.b end
    local k = lighten or 0
    return r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
end

-- nom lisible de la ressource : texte du client (variable globale du même nom que le jeton), sinon le nôtre
function lib.powerName(token)
    if type(token) ~= "string" then return ns.T("Ressource") end
    local localized = rawget(_G, token)   -- recherche dynamique : peut valoir nil sans être une erreur
    if type(localized) == "string" and localized ~= "" then return localized end
    if POWER_NAMES[token] then return ns.T(POWER_NAMES[token]) end
    local text = (token:lower():gsub("_", " "))
    return (text:gsub("^%l", string.upper))
end

-- Enveloppe une fonction : après MAX_ERRORS erreurs de suite DE CETTE fonction, on coupe tout l'affichage
-- « name » (toutes les fonctions enveloppées sous ce nom) et on prévient une fois.
-- La fonction renvoyée rend true si l'appel s'est bien passé, false sinon (erreur ou affichage coupé).
local disabled, generation = {}, {}   -- [nom] = coupé ; [nom] = numéro de remise à zéro
function lib.guard(name, fn)
    generation[name] = generation[name] or 0
    local count, seen = 0, generation[name]
    return function(...)
        if disabled[name] then return false end
        if seen ~= generation[name] then
            seen, count = generation[name], 0     -- réactivé depuis : on repart de zéro
        end
        local ok, err = pcall(fn, ...)
        if ok then
            count = 0
            return true
        end
        count = count + 1
        ns:Debug(name, ":", tostring(err))
        if count >= MAX_ERRORS then
            disabled[name] = true
            ns:Print(ns.Tf("affichage « %s » coupé après des erreurs (réactive l'option pour réessayer). Détail : %s",
                ns.T(name), tostring(err)))
        end
        return false
    end
end

-- vrai si le garde-fou a coupé cet affichage (pour que le module cache sa fenêtre)
function lib.isDisabled(name) return disabled[name] == true end

-- sans argument : tout réactiver ; sinon seulement les noms donnés
function lib.resetFailures(...)
    local n = select("#", ...)
    if n == 0 then
        for name in pairs(generation) do generation[name] = generation[name] + 1 end
        wipe(disabled)
        return
    end
    for i = 1, n do
        local name = select(i, ...)
        disabled[name] = nil
        generation[name] = (generation[name] or 0) + 1
    end
end

-- jetons des autres membres du groupe (en raid, le joueur y figure : l'écarter avec lib.isMe).
-- API facultatives lues avec rawget : pas d'erreur si le client ne les a pas (HealerMana.lua, Buffs.lua)
function lib.groupUnits()
    local list = {}
    local inRaid, numGroup, numSub = rawget(_G, "IsInRaid"), rawget(_G, "GetNumGroupMembers"), rawget(_G, "GetNumSubgroupMembers")
    if type(inRaid) == "function" and inRaid() then
        local n = type(numGroup) == "function" and numGroup() or 0
        for i = 1, math.min(n, 40) do list[#list + 1] = "raid" .. i end
    else
        local n = type(numSub) == "function" and numSub() or 0     -- API absente : pas de groupe lisible
        for i = 1, math.min(n, 4) do list[#list + 1] = "party" .. i end
    end
    return list
end

-- vrai si l'unité est le joueur lui-même (réponse secrète : « non »)
function lib.isMe(unit)
    local isUnit = rawget(_G, "UnitIsUnit")
    local same = type(isUnit) == "function" and isUnit(unit, "player")
    return not lib.isSecret(same) and same and true or false
end

-- un événement inconnu de ce client lève une erreur : on l'ignore simplement
function lib.registerEvent(frame, event)
    return (pcall(frame.RegisterEvent, frame, event))
end

-- RegisterUnitEvent (le jeu ne nous réveille que pour ces unités) ; repli : RegisterEvent + filtre dans le gestionnaire
function lib.registerUnitEvent(frame, event, unit1, unit2)
    if frame.RegisterUnitEvent then
        local ok
        if unit2 then
            ok = pcall(frame.RegisterUnitEvent, frame, event, unit1, unit2)
        else
            ok = pcall(frame.RegisterUnitEvent, frame, event, unit1)
        end
        if ok then return true end
    end
    return lib.registerEvent(frame, event)
end

---------------------------------------------------------------------------
-- Barres d'action : sorts présents, coûts, sorts abordables (caches invalidés par événement)
---------------------------------------------------------------------------
local buttons = {}          -- boutons trouvés (relus tant que la liste est vide, et à chaque écran de chargement)
local actionsCache = nil    -- liste { button, action, spellID, order } des boutons qui contiennent un sort
local armed = false         -- la centrale d'événements des barres est-elle à l'écoute ? (voir lib.setWanted)
local costCache = {}        -- [spellID] = liste { type, token, amount, full } ou false (aucun coût)

local function collectButtons()
    local list = {}
    local bases = (ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames) or DEFAULT_BAR_BASES
    local perBar = NUM_ACTIONBAR_BUTTONS or 12
    for _, base in ipairs(bases) do
        for i = 1, perBar do
            local button = _G[base .. i]
            if button then list[#list + 1] = button end
        end
    end
    return list
end

-- sort contenu dans un bouton : sort direct, ou macro qui lance un sort (type "spell" : vérifié ; macro : déduit du code Blizzard)
local function spellOf(button)
    local action = button.action
    if not action then return nil end
    local kind, id, subType = GetActionInfo(action)
    if id and (kind == "spell" or (kind == "macro" and subType == "spell")) then return id end
    return nil
end

function lib.rescanButtons()
    buttons = collectButtons()
    actionsCache = nil
end

function lib.invalidate()
    actionsCache = nil
    wipe(costCache)
end

-- boutons qui contiennent un sort, dans l'ordre des barres (barre principale d'abord)
function lib.actions()
    if actionsCache then return actionsCache end
    if #buttons == 0 then buttons = collectButtons() end
    local list = {}
    for i, button in ipairs(buttons) do
        local spellID = spellOf(button)
        if spellID then
            list[#list + 1] = { button = button, action = button.action, spellID = spellID, order = i }
        end
    end
    -- sans la centrale (aucun module ne l'a demandée), rien ne viderait le cache : on relit à chaque appel
    if armed then actionsCache = list end
    return list
end

-- coûts d'un sort : amount = coût minimal requis, full = coût complet (plus grand si une part est optionnelle)
function lib.costs(spellID)
    local list = costCache[spellID]
    if list == nil then
        list = false
        local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(spellID)
        if type(costs) == "table" then
            for _, info in ipairs(costs) do
                local amount, full = info.minCost, info.cost
                if not isSecret(amount) and not isSecret(full) then
                    if not amount or amount <= 0 then amount = full end
                    if amount and amount > 0 then
                        list = list or {}
                        list[#list + 1] = { type = info.type, token = info.name, amount = amount,
                            full = (full and full > amount) and full or amount }
                    end
                end
            end
        end
        costCache[spellID] = list
    end
    return list or nil
end

-- coût d'un sort dans une ressource donnée (nil s'il n'en coûte pas)
function lib.costOf(spellID, powerType)
    local list = lib.costs(spellID)
    if not list then return nil end
    for _, c in ipairs(list) do
        if c.type == powerType then return c.amount, c.full end
    end
    return nil
end

-- isUsable, isLacking (booléens) ; nil, nil si le jeu ne sait pas répondre
-- Ordre : C_ActionBar.IsUsableAction (le bouton exact), C_Spell.IsSpellUsable, puis en dernier recours une
-- comparaison avec UnitPower, seulement si la valeur n'est pas secrète.
function lib.usable(action, spellID, cost, powerType)
    if action and C_ActionBar and C_ActionBar.IsUsableAction then
        local usable, lacking = C_ActionBar.IsUsableAction(action)
        return usable and true or false, lacking and true or false
    end
    if spellID and C_Spell and C_Spell.IsSpellUsable then
        local usable, lacking = C_Spell.IsSpellUsable(spellID)
        return usable and true or false, lacking and true or false
    end
    if cost and powerType then
        local cur = UnitPower("player", powerType)
        if not isSecret(cur) and tonumber(cur) then
            local lack = cur < cost
            return not lack, lack
        end
    end
    return nil, nil
end

---------------------------------------------------------------------------
-- Centrale d'événements des barres d'action, partagée par les deux modules
--  * "actions" : contenu des barres ou coûts peut-être changés (caches vidés avant l'appel)
--  * "usable"  : un sort a peut-être changé d'état abordable / utilisable
---------------------------------------------------------------------------
local hub = CreateFrame("Frame")
local subscribers = {}
local wanted = {}           -- [module] = true : quelqu'un a besoin de ces informations
local ticker
local queued, pendingActions = false, false

local ACTION_EVENTS = {
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_FORMS", "SPELLS_CHANGED", "UPDATE_MACROS", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
    "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
    "ACTIONBAR_HIDEGRID", "PLAYER_ENTERING_WORLD",
}
local USABLE_EVENTS = { "ACTION_USABLE_CHANGED", "ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED" }
local ACTION_SET = { UNIT_DISPLAYPOWER = true }
for _, e in ipairs(ACTION_EVENTS) do ACTION_SET[e] = true end
local UNIT_SET = { UNIT_DISPLAYPOWER = true, UNIT_MAXPOWER = true, UNIT_POWER_FREQUENT = true, UNIT_POWER_UPDATE = true }

local function flush()
    queued = false
    local reason = pendingActions and "actions" or "usable"
    if pendingActions then lib.invalidate() end
    pendingActions = false
    for _, fn in ipairs(subscribers) do fn(reason) end   -- chaque abonné est protégé par son garde-fou
end

-- demande une relecture groupée ; actions = true si le contenu des barres a pu changer
function lib.request(actions)
    if actions then pendingActions = true end
    if queued then return end
    queued = true
    C_Timer.After(FLUSH_DELAY, flush)
end

hub:SetScript("OnEvent", function(_, event, unit)
    if UNIT_SET[event] and unit ~= "player" then return end
    if event == "PLAYER_ENTERING_WORLD" then lib.rescanButtons() end
    lib.request(ACTION_SET[event] == true)
end)

function lib.subscribe(fn)
    subscribers[#subscribers + 1] = fn
end

-- un module annonce s'il a besoin des barres d'action ; la centrale ne s'abonne aux événements que si besoin
function lib.setWanted(owner, on)
    wanted[owner] = on and true or nil
    local any = next(wanted) ~= nil
    if any == armed then return end
    armed = any
    if any then
        lib.invalidate()
        for _, e in ipairs(ACTION_EVENTS) do lib.registerEvent(hub, e) end
        for _, e in ipairs(USABLE_EVENTS) do lib.registerEvent(hub, e) end
        lib.registerUnitEvent(hub, "UNIT_DISPLAYPOWER", "player")
        lib.registerUnitEvent(hub, "UNIT_MAXPOWER", "player")
        if not lib.registerUnitEvent(hub, "UNIT_POWER_FREQUENT", "player") then
            lib.registerUnitEvent(hub, "UNIT_POWER_UPDATE", "player")
        end
        if C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(SAFETY_TICK, function() lib.request(true) end)
        end
        lib.request(true)
    else
        hub:UnregisterAllEvents()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end
end
