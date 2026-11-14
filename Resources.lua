-- Platyplus : ressources
--  1) chiffre exact de la ressource (rage, énergie, mana...) sur le portrait du joueur et, en option, de la cible
--  2) coût en ressource de chaque sort des barres d'action, dans une pastille arrondie à la couleur de la ressource ;
--     la pastille passe au ROUGE (fond sombre, liseré et chiffre rouges) quand le sort n'est pas abordable
--  3) Resources.lib : outils partagés avec ResourceBar.lua (lecture des barres d'action, coûts, sorts abordables,
--     garde-fou, valeurs secrètes, enregistrement prudent des événements)
--
-- Optimisation : tout est piloté par les ÉVÉNEMENTS, sans scrutation. Les portraits suivent UNIT_POWER_FREQUENT
-- (filtré sur le joueur et la cible) ; les barres d'action sont relues quand elles changent (ACTIONBAR_SLOT_CHANGED,
-- posture, sorts appris, macros...) et l'état « abordable » quand le jeu le signale (ACTION_USABLE_CHANGED,
-- SPELL_UPDATE_USABLE, ressource du joueur). Les rafales d'événements sont regroupées en une seule relecture
-- 0,05 s plus tard. Seul reste un filet très lent (toutes les 5 s, seulement si une fonction est active) pour les
-- coûts qui changent sans prévenir (auras, talents).
--
-- Forever : la doc API du client contient le système de "valeurs secrètes" (C_Secrets, issecretvalue) ; on ne sait
-- pas s'il est actif (test en jeu : C_Secrets.HasSecretRestrictions()), donc on gère les deux cas.
-- UnitPower peut alors renvoyer une valeur "secrète" en combat. Sur une valeur secrète, le code d'un addon
-- ne peut ni calculer ni comparer, mais il peut la passer à string.format puis à FontString:SetText (et à
-- StatusBar:SetValue / SetMinMaxValues) : c'est la seule chose qu'on fait avec elle. Les coûts de sorts
-- (C_Spell.GetSpellPowerCost) et IsUsableAction / IsSpellUsable ne sont pas secrets : c'est EUX qui disent si un sort
-- est abordable, jamais une comparaison UnitPower >= coût (sauf en dernier recours, sur un nombre ordinaire).
-- Unité : Blizzard soustrait costInfo.cost tel quel de UnitPower(unit, type) pour sa barre de prédiction,
-- les deux sont donc dans la même unité (30 pour un sort à 30 de rage).
local ADDON, ns = ...

local Resources = {}
ns.Resources = Resources

local lib = {}
Resources.lib = lib

local POWER_MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local FLUSH_DELAY = 0.05       -- regroupe les rafales d'événements des barres d'action
local SAFETY_TICK = 5          -- filet très lent : relit coûts et barres au cas où un événement manque
local MAX_ERRORS = 3           -- erreurs de suite avant de couper une fonction (au lieu de spammer le joueur)
local LACK = { 1.00, 0.30, 0.30 }   -- rouge « pas assez de ressource »

-- noms des boutons des barres d'action par défaut (vérifié dans ActionButtonUtil.lua, 12 boutons par barre)
local DEFAULT_BAR_BASES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local PORTRAIT_POS = {
    TOP    = { "TOP", 0, -4 },
    CENTER = { "CENTER", 0, 0 },
    BOTTOM = { "BOTTOM", 0, 4 },
}
local COST_POS = {
    TOPLEFT    = { "TOPLEFT", 2, -2 },
    BOTTOMLEFT = { "BOTTOMLEFT", 2, 2 },
    TOP        = { "TOP", 0, -2 },
    CENTER     = { "CENTER", 0, 0 },
}

local KEYS = {
    "powerPlayer", "powerTarget", "powerFormat", "powerPos", "powerSize",
    "spellCost", "spellCostMana", "spellCostPos", "spellCostSize",
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
-- 0. Outils partagés (Resources.lib, aussi utilisés par ResourceBar.lua)
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
    actionsCache = list
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
local armed = false
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

---------------------------------------------------------------------------
-- 1. Ressource sur les portraits
---------------------------------------------------------------------------
-- Chemins vérifiés dans PlayerFrame.xml / TargetFrame.xml (dépôts live et Forever) :
-- le portrait est une Texture (PlayerFrameContainer.PlayerPortrait, TargetFrameContainer.Portrait).
local PORTRAITS = {
    player = {
        key = "powerPlayer",
        frame = function() return PlayerFrame end,
        portrait = function()
            local f = PlayerFrame
            return f and f.PlayerFrameContainer and f.PlayerFrameContainer.PlayerPortrait
        end,
    },
    target = {
        key = "powerTarget",
        frame = function() return TargetFrame end,
        portrait = function()
            local f = TargetFrame
            return f and f.TargetFrameContainer and f.TargetFrameContainer.Portrait
        end,
    },
}
Resources.portraits = PORTRAITS

local function ensurePortraitText(def)
    if def.text then return true end
    local parent, portrait = def.frame(), def.portrait()
    if not (parent and portrait) then return false end

    -- cadre posé au-dessus du portrait, à la même taille
    local host = CreateFrame("Frame", nil, parent)
    host:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
    host:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
    def.host = host
    def.text = host:CreateFontString(nil, "OVERLAY")
    def.text:SetWordWrap(false)
    def.text:SetShadowColor(0, 0, 0, 1)
    def.text:SetShadowOffset(1, -1)
    -- voile sombre et doux derrière le chiffre : lisible sur n'importe quel portrait
    def.shade = host:CreateTexture(nil, "ARTWORK")
    def.shade:SetTexture(ns.MEDIA .. "Glow")
    def.shade:SetVertexColor(0, 0, 0, 0.75)
    def.shade:SetPoint("CENTER", def.text, "CENTER", 0, 0)
    return true
end

local function stylePortraitText(def)
    local pos = PORTRAIT_POS[ns.db.powerPos] or PORTRAIT_POS.BOTTOM
    local size = tonumber(ns.db.powerSize) or 14
    def.text:ClearAllPoints()
    def.text:SetPoint(pos[1], def.host, pos[1], pos[2], pos[3])
    def.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    def.shade:SetSize(size * (ns.db.powerFormat == "curmax" and 6.5 or 3.6), size * 2.2)
    def.lastText, def.color = nil, nil   -- texte et couleur seront réécrits
end

local function updatePortrait(unit, def)
    if not def.text then return end
    if not UnitExists(unit) then
        def.host:Hide()
        return
    end
    local powerType, token = UnitPowerType(unit)
    if not powerType then
        def.host:Hide()
        return
    end
    def.token = token

    local max = UnitPowerMax(unit, powerType)
    -- une cible sans barre de ressource a un maximum de 0 (comparaison permise seulement si non secret)
    if not isSecret(max) and (not max or max <= 0) then
        def.host:Hide()
        return
    end
    local cur = UnitPower(unit, powerType)
    local both = ns.db.powerFormat == "curmax"

    if isSecret(cur) or isSecret(max) then
        -- valeur secrète : on ne fait QUE la formater et l'afficher
        def.lastText = nil
        if both then
            def.text:SetText(string.format("%d / %d", cur, max))
        else
            def.text:SetText(string.format("%d", cur))
        end
    else
        local text = both and (lib.plainNumber(cur) .. " / " .. lib.plainNumber(max)) or lib.plainNumber(cur)
        if text ~= def.lastText then
            def.lastText = text
            def.text:SetText(text)
        end
    end

    local colorKey = token or powerType
    if def.color ~= colorKey then
        def.color = colorKey
        def.text:SetTextColor(lib.powerColor(powerType, token, 0.35))
    end
    def.host:Show()
end

local updatePortraits = lib.guard("portrait", function()
    for unit, def in pairs(PORTRAITS) do
        if ns.db[def.key] and def.text then updatePortrait(unit, def) end
    end
end)

local onPortraitEvent = lib.guard("portrait", function(event, unit, powerToken)
    if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
    local def = PORTRAITS[unit]                       -- filtre d'unité (utile si RegisterUnitEvent manque)
    if not (def and def.text and ns.db[def.key]) then return end
    if (event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE")
        and powerToken and def.token and powerToken ~= def.token then
        return                                        -- une autre ressource (points de combo...) a bougé
    end
    updatePortrait(unit, def)
end)

local portraitEvents = CreateFrame("Frame")
portraitEvents:SetScript("OnEvent", function(_, event, ...) onPortraitEvent(event, ...) end)

local function applyPortraitEvents()
    portraitEvents:UnregisterAllEvents()
    local u1, u2
    if ns.db.powerPlayer and PORTRAITS.player.text then u1 = "player" end
    if ns.db.powerTarget and PORTRAITS.target.text then
        if u1 then u2 = "target" else u1 = "target" end
    end
    if not u1 then return end
    if not lib.registerUnitEvent(portraitEvents, "UNIT_POWER_FREQUENT", u1, u2) then
        lib.registerUnitEvent(portraitEvents, "UNIT_POWER_UPDATE", u1, u2)
    end
    lib.registerUnitEvent(portraitEvents, "UNIT_MAXPOWER", u1, u2)
    lib.registerUnitEvent(portraitEvents, "UNIT_DISPLAYPOWER", u1, u2)
    if u1 == "target" or u2 == "target" then lib.registerEvent(portraitEvents, "PLAYER_TARGET_CHANGED") end
end

---------------------------------------------------------------------------
-- 2. Coût des sorts sur les barres d'action : une pastille par bouton
---------------------------------------------------------------------------
local pills = {}        -- [bouton] = pastille (Frame : liseré + fond en capsule, texte)
local labels = {}       -- [bouton] = texte de la pastille (FontString)
local shownState = {}   -- [bouton] = { key, entry, action, spellID, lacking } des pastilles affichées
local entries = {}      -- [spellID] = fiche { text, key, r, g, b, amount, type } ou false (pas de coût à afficher)
Resources.labels = labels
Resources.pills = pills

-- capsule = 3 morceaux de Media\Circle : demi-disque gauche, milieu étiré, demi-disque droit (bouts bien ronds)
local function capsule(frame, layer, sublevel, outset)
    local file = ns.MEDIA .. "Circle"
    local o = outset or 0
    local l = frame:CreateTexture(nil, layer, nil, sublevel)
    local m = frame:CreateTexture(nil, layer, nil, sublevel)
    local r = frame:CreateTexture(nil, layer, nil, sublevel)
    l:SetTexture(file)
    l:SetTexCoord(0, 0.5, 0, 1)
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
    l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o)
    r:SetTexture(file)
    r:SetTexCoord(0.5, 1, 0, 1)
    r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o)
    r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
    m:SetTexture(file)
    m:SetTexCoord(0.45, 0.55, 0, 1)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", 0, 0)
    return { l, m, r, outset = o }
end

local function capsuleHeight(c, h)
    local w = h / 2 + c.outset
    c[1]:SetWidth(w)
    c[3]:SetWidth(w)
end

local function capsuleColor(c, r, g, b, a)
    for i = 1, 3 do c[i]:SetVertexColor(r, g, b, a) end
end

local function stylePill(pill, button)
    local pos = COST_POS[ns.db.spellCostPos] or COST_POS.TOPLEFT
    local size = tonumber(ns.db.spellCostSize) or 11
    pill:ClearAllPoints()
    pill:SetPoint(pos[1], button, pos[1], pos[2], pos[3])
    pill.text:SetFont(STANDARD_TEXT_FONT, size, "")   -- pas de contour : chiffre net sur fond uni, ombre portée
    pill.height = math.floor(size + 5 + 0.5)
end

-- largeur selon le texte (jamais secret ici : c'est un coût), au moins un rond
local function sizePill(pill)
    local h = pill.height
    local w = math.max(h, math.ceil((pill.text:GetStringWidth() or 0) + h * 0.6))
    pill:SetSize(w, h)
    capsuleHeight(pill.edge, h)
    capsuleHeight(pill.body, h)
end

-- abordable : fond à la couleur de la ressource, chiffre blanc ; pas abordable : fond sombre, liseré et chiffre rouges
local function paintPill(pill, entry, lacking)
    if lacking then
        capsuleColor(pill.edge, LACK[1], LACK[2], LACK[3], 0.95)
        capsuleColor(pill.body, 0.07, 0.07, 0.08, 0.95)
        pill.text:SetTextColor(LACK[1], LACK[2], LACK[3])
    else
        capsuleColor(pill.edge, 0, 0, 0, 0.8)
        capsuleColor(pill.body, entry.r * 0.55, entry.g * 0.55, entry.b * 0.55, 0.95)
        pill.text:SetTextColor(1, 1, 1)
    end
end

local function pillOf(button)
    local pill = pills[button]
    if pill then return pill end
    -- le conteneur de texte de Blizzard est au-dessus de l'animation de recharge ; à défaut, le bouton lui-même
    local parent = button.TextOverlayContainer or button
    pill = CreateFrame("Frame", nil, parent)       -- ne capte pas la souris : les clics passent au bouton
    pill:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
    pill.edge = capsule(pill, "BACKGROUND", 0, 1)
    pill.body = capsule(pill, "BORDER", 0, 0)
    pill.text = pill:CreateFontString(nil, "OVERLAY")
    pill.text:SetPoint("CENTER", pill, "CENTER", 0, 0)
    pill.text:SetWordWrap(false)
    pill.text:SetShadowColor(0, 0, 0, 0.9)
    pill.text:SetShadowOffset(1, -1)
    stylePill(pill, button)
    pills[button] = pill
    labels[button] = pill.text
    return pill
end

-- fiche de coût d'un sort : coût minimal requis, suivi de "+" s'il existe un coût optionnel en plus ;
-- la ressource principale du joueur d'abord, puis une autre (le mana seulement si l'option le demande)
local function labelEntry(spellID)
    local entry = entries[spellID]
    if entry ~= nil then return entry or nil end
    entry = false
    local list = lib.costs(spellID)
    if list then
        local primary = UnitPowerType("player")
        local best
        for _, c in ipairs(list) do
            if c.type ~= POWER_MANA or ns.db.spellCostMana then
                if c.type == primary then
                    best = c
                    break
                end
                best = best or c
            end
        end
        if best then
            local text = lib.shortNumber(best.amount)
            if best.full > best.amount then text = text .. "+" end
            local r, g, b = lib.powerColor(best.type, best.token)
            entry = { text = text, key = text .. "|" .. tostring(best.type), r = r, g = g, b = b,
                amount = best.amount, type = best.type }
        end
    end
    entries[spellID] = entry
    return entry or nil
end

-- rouge ou non : relu seulement pour les pastilles affichées, repeint seulement si l'état change
local function refreshPillStates()
    for button, s in pairs(shownState) do
        local _, lacking = lib.usable(s.action, s.spellID, s.entry.amount, s.entry.type)
        lacking = lacking == true
        if lacking ~= s.lacking then
            s.lacking = lacking
            paintPill(pills[button], s.entry, lacking)
        end
    end
end

local function showPill(slot, entry)
    local button = slot.button
    local pill = pillOf(button)
    local s = shownState[button]
    if not s then
        s = {}
        shownState[button] = s
    end
    if s.key ~= entry.key then
        s.key, s.lacking = entry.key, nil     -- lacking = nil : la couleur sera repeinte
        pill.text:SetText(entry.text)
        sizePill(pill)
    end
    s.entry, s.action, s.spellID = entry, slot.action, slot.spellID
    pill:Show()
end

local function updateCostsRaw()
    local seen = {}
    for _, slot in ipairs(lib.actions()) do
        local entry = labelEntry(slot.spellID)
        if entry then
            seen[slot.button] = true
            showPill(slot, entry)
        end
    end
    for button in pairs(shownState) do
        if not seen[button] then
            pills[button]:Hide()
            shownState[button] = nil
        end
    end
    refreshPillStates()
end

local updateCosts = lib.guard("coût des sorts", updateCostsRaw)

local onLib = lib.guard("coût des sorts", function(reason)
    if not (ns.db and ns.db.spellCost) then return end
    if reason == "actions" then
        wipe(entries)
        updateCostsRaw()
    else
        refreshPillStates()
    end
end)

---------------------------------------------------------------------------
-- Mise en route
---------------------------------------------------------------------------

-- crée, met en forme, montre ou cache selon les options
function Resources:Apply()
    if not ns.db then return end

    for _, def in pairs(PORTRAITS) do
        if ns.db[def.key] then
            if ensurePortraitText(def) then stylePortraitText(def) end
        elseif def.host then
            def.host:Hide()
        end
    end
    applyPortraitEvents()
    updatePortraits()

    if ns.db.spellCost then
        for button, pill in pairs(pills) do stylePill(pill, button) end
        wipe(entries)
        for _, s in pairs(shownState) do s.key = nil end   -- texte, taille et couleur seront réécrits
        lib.setWanted("costs", true)
        updateCosts()
    else
        for _, pill in pairs(pills) do pill:Hide() end
        wipe(shownState)
        lib.setWanted("costs", false)
    end
end

-- relit tout tout de suite (utile pour les tests et après un changement d'option)
function Resources:Refresh()
    updatePortraits()
    if ns.db.spellCost then
        lib.invalidate()
        wipe(entries)
        updateCosts()
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then lib.rescanButtons() end
    Resources:Apply()   -- les cadres Blizzard peuvent apparaître après nous : on retente
end)

function Resources:Init()
    for _, key in ipairs(KEYS) do
        ns:OnChange(key, function()
            lib.resetFailures("portrait", "coût des sorts")
            Resources:Apply()
        end)
    end
    lib.subscribe(onLib)
    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:Apply()
end
