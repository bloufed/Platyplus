-- Platyplus : rappel de buffs
--  1) Cri de guerre (buffShout) : en combat, si tu ne l'as pas, son icône apparaît avec la touche à presser, dans
--     l'alerte de proc (Procs.lua lit Buffs:Reminders()). Hors combat : rien (demande du joueur : « uniquement en combat
--     si je l'ai pas »). Seulement s'il est rangé sur tes barres : sans bouton, pas de touche à montrer.
--  2) Buffs de tes alliés (buffAllies) : hors combat, une rangée d'icônes montre ce que ton groupe peut te donner et
--     que tu n'as pas, avec le nom de l'allié dessous : Robustesse (prêtre), Marque du fauve (druide), Intelligence des
--     arcanes (mage, si tu utilises de la mana), une bénédiction (paladin : puissance, ou sagesse si tu utilises de la
--     mana ; n'importe quelle bénédiction compte). Les buffs de talents (Esprit divin, Rois) ne sont pas proposés : on ne
--     peut pas savoir si l'allié les a. Cachée en combat : on ne buffe pas en plein combat.
--
-- Vérifié dans le code de Forever (doc API générée) :
--  * auras du joueur secrètes en combat (SecretWhenUnitAuraRestricted). GetAuraDataBySpellName et
--    GetPlayerAuraBySpellID ne renvoient alors RIEN (RequiresNonSecretAura) : ça ressemble à « pas le buff ».
--    C_Secrets.ShouldSpellAuraBeSecret(sort) dit si la réponse est fiable (SecretPredicateAPIDocumentation.lua).
--    Sinon on se fie à l'heure de fin du cri lue avant le combat, ou à ton propre lancer : UNIT_SPELLCAST_SUCCEEDED
--    n'est secret que pour les autres unités que le joueur (SecretWhenUnitSpellCastRestricted) ;
--  * hors combat, GetUnitAuras("player", "HELPFUL") liste tes buffs, lisibles.
-- Numéros vérifiés dans la table SpellName du client (wago.tools, build 1.60.1.70245, frFR) :
--   Cri de guerre 6673, 5242, 6192, 11549, 11550, 11551, 25289 ; Mot de pouvoir : Robustesse 1243, Prière de robustesse
--   21562 ; Marque du fauve 1126, Don du fauve 21849 ; Intelligence des arcanes 1459, Illumination des arcanes 23028 ;
--   Bénédictions : puissance 19740 / 25782, sagesse 19742 / 25894, rois 20217 / 25898, salut 1038 / 25895,
--   lumière 19977 / 25890 (sanctuaire absent de Forever).
-- NON VÉRIFIÉ en jeu : tout ce module, en particulier si le Cri de guerre est lisible en combat.
--
-- Optimisation : aucune boucle OnUpdate. Relecture sur événements (tes auras, ton lancer, groupe, combat), regroupés ;
-- un seul réveil programmé à la fin du Cri de guerre pendant un combat.
local ADDON, ns = ...

local Buffs = {}
ns.Buffs = Buffs

local NAME = "rappel de buffs"
local ICON = 30
local GAP = 10
local NAME_H = 12
local MAX_ITEMS = 6
local FLUSH_DELAY = 0.1
local PREVIEW_SECONDS = 6
local SHOUT_DURATION = 120          -- secours si la durée du cri n'a jamais été lue (2 min)
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local SHOUT_IDS = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local SHOUT_SET = {}
for _, id in ipairs(SHOUT_IDS) do SHOUT_SET[id] = true end

local BLESSINGS = { 19740, 25782, 19742, 25894, 20217, 25898, 1038, 25895, 19977, 25890 }
-- class : qui peut le donner ; ids : le buff proposé (et sa version de groupe) ; any : n'importe lequel de ceux-là suffit ;
-- mana : true = seulement si tu utilises de la mana, false = seulement si tu n'en utilises pas, nil = pour tous
local ALLY_BUFFS = {
    { class = "PRIEST",  ids = { 1243, 21562 } },
    { class = "DRUID",   ids = { 1126, 21849 } },
    { class = "MAGE",    ids = { 1459, 23028 }, mana = true },
    { class = "PALADIN", ids = { 19740, 25782 }, any = BLESSINGS, mana = false },
    { class = "PALADIN", ids = { 19742, 25894 }, any = BLESSINGS, mana = true },
}
-- aperçu : deux buffs d'exemple
local SAMPLES = {
    { spellID = 1243, ally = "Ariane", classFile = "PRIEST" },
    { spellID = 1126, ally = "Cléo", classFile = "DRUID" },
}

local KEYS = { "buffShout", "buffAllies", "buffLocked" }
local POSITION_KEYS = { buffX = true, buffY = true }

local lib, isSecret, draw
local root, title, mover, events
local items = {}                     -- cases d'icônes réutilisées
local shown = {}                     -- ce qui est affiché : { spellID, name, ally, classFile }
local names = {}                     -- [spellID] = nom lu dans le jeu (gardé une fois connu)
local inCombat = false
local shoutUntil                     -- heure (GetTime) de fin du cri ; nil = pas de cri ; math.huge = sans fin
local shoutDuration                  -- durée du cri lue sur l'aura
local shoutTimer = 0                 -- jeton du réveil de fin du cri
local queued, previewing, moving = false, false, false
local previewToken = 0
local refreshAll, onEvent, applyAll  -- protégées par le garde-fou (créées dans Init)

---------------------------------------------------------------------------
-- Lecture du jeu
---------------------------------------------------------------------------
local function api(name) return rawget(_G, name) end

local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function spellName(id)
    if names[id] then return names[id] end
    local s = api("C_Spell")
    if type(s) ~= "table" or type(s.GetSpellName) ~= "function" then return nil end
    local ok, name = pcall(s.GetSpellName, id)
    if ok and not isSecret(name) and type(name) == "string" and name ~= "" then
        names[id] = name
        return name
    end
    return nil
end

local function spellTexture(id)
    local s = api("C_Spell")
    if type(s) == "table" and type(s.GetSpellTexture) == "function" then
        local ok, tex = pcall(s.GetSpellTexture, id)
        if ok and not isSecret(tex) and tex ~= nil then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function shoutName() return spellName(SHOUT_IDS[1]) end

local function isShout(id)
    if id == nil or isSecret(id) then return false end
    if SHOUT_SET[id] then return true end
    local name = shoutName()
    return name ~= nil and spellName(id) == name
end

-- tes buffs, par nom ; nil si on ne peut pas savoir (auras cachées par le jeu, une aura secrète, API absente)
local function myBuffNames()
    local ua = api("C_UnitAuras")
    if type(ua) ~= "table" then return nil end
    -- auras cachées en ce moment : une liste vide ne voudrait pas dire « aucun buff » (C_Secrets.ShouldAurasBeSecret)
    local sec = api("C_Secrets")
    if type(sec) == "table" and type(sec.ShouldAurasBeSecret) == "function" then
        local ok, hidden = pcall(sec.ShouldAurasBeSecret)
        if not ok or isSecret(hidden) or hidden == true then return nil end
    end
    local set = {}
    local function add(aura)
        if aura == nil then return true end
        if isSecret(aura) or type(aura) ~= "table" then return false end
        local name = aura.name
        if name == nil or isSecret(name) then return false end
        set[name] = true
        return true
    end
    if type(ua.GetUnitAuras) == "function" then
        local ok, list = pcall(ua.GetUnitAuras, "player", "HELPFUL")
        if not ok or type(list) ~= "table" or isSecret(list) then return nil end
        for _, aura in ipairs(list) do
            if not add(aura) then return nil end
        end
        return set
    end
    if type(ua.GetAuraDataByIndex) == "function" then
        for i = 1, 40 do
            local ok, aura = pcall(ua.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then return nil end
            if aura == nil then break end
            if not add(aura) then return nil end
        end
        return set
    end
    return nil
end

-- la réponse « as-tu le cri ? » est-elle fiable maintenant ?
local function shoutReadable()
    local sec = api("C_Secrets")
    if type(sec) == "table" and type(sec.ShouldSpellAuraBeSecret) == "function" then
        local ok, hidden = pcall(sec.ShouldSpellAuraBeSecret, SHOUT_IDS[1])
        return ok and not isSecret(hidden) and hidden == false
    end
    return not inCombat              -- API absente : en combat, « rien » ne veut rien dire
end

-- relit le cri sur toi quand la réponse est fiable : heure de fin, ou nil s'il n'y est pas.
-- Sinon (combat), on garde ce qu'on savait : l'heure de fin lue avant, ou ton propre lancer.
local function readShout()
    if not shoutReadable() then return end
    local ua = api("C_UnitAuras")
    if type(ua) ~= "table" then return end
    local aura
    local name = shoutName()
    if name and type(ua.GetAuraDataBySpellName) == "function" then
        local ok, a = pcall(ua.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if ok and isSecret(a) then return end
        if ok then aura = a end
    end
    if aura == nil and type(ua.GetPlayerAuraBySpellID) == "function" then
        for _, id in ipairs(SHOUT_IDS) do
            local ok, a = pcall(ua.GetPlayerAuraBySpellID, id)
            if ok and isSecret(a) then return end
            if ok and a ~= nil then aura = a break end
        end
    end
    if aura == nil then
        shoutUntil = nil
        return
    end
    if type(aura) ~= "table" then return end
    local exp, dur = aura.expirationTime, aura.duration
    exp = (not isSecret(exp)) and tonumber(exp) or nil
    dur = (not isSecret(dur)) and tonumber(dur) or nil
    if dur and dur > 0 then shoutDuration = dur end
    shoutUntil = (exp and exp > 0) and exp or math.huge    -- 0 : aura sans fin
end

local function shoutMissing()
    return shoutUntil == nil or GetTime() >= shoutUntil
end

-- utilises-tu de la mana ? (guerrier : non ; un druide en forme d'ours : oui)
local function usesMana()
    local fn = api("UnitPowerMax")
    if type(fn) ~= "function" then return false end
    local ok, max = pcall(fn, "player", MANA)
    if not ok or isSecret(max) then return false end
    return (tonumber(max) or 0) > 0
end

local function unitOk(u, fnName, want)
    local fn = api(fnName)
    if type(fn) ~= "function" then return true end
    local ok, v = pcall(fn, u)
    if not ok or isSecret(v) then return true end
    return (v and true or false) == want
end

-- ce que tes alliés peuvent te donner et que tu n'as pas ; nil si on ne peut pas savoir
local function allyMissing()
    local mine = myBuffNames()
    if not mine then return nil end
    local providers = {}             -- [classe] = premier allié de cette classe, connecté et en vie
    for _, u in ipairs(lib.groupUnits()) do
        if UnitExists(u) and not lib.isMe(u) and unitOk(u, "UnitIsConnected", true) and unitOk(u, "UnitIsDeadOrGhost", false) then
            local _, classFile = UnitClass(u)
            if not isSecret(classFile) and type(classFile) == "string" and not providers[classFile] then
                providers[classFile] = u
            end
        end
    end
    local list = {}
    local mana = usesMana()
    for _, b in ipairs(ALLY_BUFFS) do
        local u = providers[b.class]
        if u and (b.mana == nil or b.mana == mana) then
            local have, known = false, false
            for _, id in ipairs(b.any or b.ids) do
                local n = spellName(id)
                if n then
                    known = true
                    if mine[n] then have = true break end
                end
            end
            if known and not have then
                local ally = UnitName(u)
                local _, classFile = UnitClass(u)
                list[#list + 1] = { spellID = b.ids[1], name = spellName(b.ids[1]), ally = ally, classFile = classFile }
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Rangée « buffs à demander »
---------------------------------------------------------------------------
local function newItem()
    local T = ns.THEME
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(ICON, ICON)
    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetTexture(ns.MEDIA .. "Round")
    f.back:SetVertexColor(0, 0, 0, 0.85)
    f.back:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.back:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.stroke = f:CreateTexture(nil, "OVERLAY")
    f.stroke:SetTexture(ns.MEDIA .. "RoundStroke")
    f.stroke:SetVertexColor(T.gold[1], T.gold[2], T.gold[3], 0.9)
    f.stroke:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.stroke:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.ally = draw.fontString(f, 10, "OUTLINE")
    f.ally:SetPoint("TOP", f, "BOTTOM", 0, -3)
    return f
end

local function paintItems(list)
    local T = ns.THEME
    local n = math.min(#list, MAX_ITEMS)
    local width = n * ICON + math.max(0, n - 1) * GAP
    for i = 1, n do
        local e = list[i]
        local f = items[i] or newItem()
        items[i] = f
        f.icon:SetTexture(spellTexture(e.spellID))
        f.ally:SetText(e.ally)                     -- nom de l'allié : peut être secret, SetText l'accepte
        local color = (not isSecret(e.classFile)) and type(e.classFile) == "string" and RAID_CLASS_COLORS
            and RAID_CLASS_COLORS[e.classFile]
        if color then f.ally:SetTextColor(color.r, color.g, color.b) else f.ally:SetTextColor(T.text[1], T.text[2], T.text[3]) end
        f.entry = e
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", root, "TOPLEFT", (i - 1) * (ICON + GAP), -16)
        f:Show()
    end
    for i = n + 1, #items do
        items[i]:Hide()
        items[i].entry = nil
    end
    root:SetSize(math.max(width, 120), 16 + ICON + 3 + NAME_H)
end

local function refreshPanel()
    local list
    if previewing or moving then
        list = {}
        for i, s in ipairs(SAMPLES) do
            list[i] = { spellID = s.spellID, name = spellName(s.spellID), ally = s.ally, classFile = s.classFile }
        end
    elseif ns.db.buffAllies and not inCombat then
        list = allyMissing() or {}
    else
        list = {}
    end
    wipe(shown)
    for i, e in ipairs(list) do shown[i] = e end
    if #list > 0 then
        paintItems(list)
        root:Show()
    else
        root:Hide()
    end
end

---------------------------------------------------------------------------
-- Cri de guerre : réveil à sa fin pendant un combat (l'aura n'est peut-être plus lisible)
---------------------------------------------------------------------------
local function requestProcs()
    if ns.Procs and ns.Procs.Request then ns.Procs:Request() end
end

local function scheduleShoutEnd()
    shoutTimer = shoutTimer + 1
    if not (inCombat and ns.db.buffShout and shoutUntil and shoutUntil ~= math.huge) then return end
    local left = shoutUntil - GetTime()
    if left <= 0 then return end
    local token = shoutTimer
    C_Timer.After(left + 0.1, function()
        if token ~= shoutTimer then return end
        requestProcs()
    end)
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local function wanted()
    return (ns.db.buffShout or ns.db.buffAllies or previewing or moving) and true or false
end

local function registerEvents()
    events:UnregisterAllEvents()
    if not wanted() then return end
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
        "GROUP_ROSTER_UPDATE" }) do
        lib.registerEvent(events, event)
    end
    lib.registerUnitEvent(events, "UNIT_AURA", "player")
    lib.registerUnitEvent(events, "UNIT_SPELLCAST_SUCCEEDED", "player")
end

local function doRefresh()
    if ns.db.buffShout then
        readShout()
        scheduleShoutEnd()
    end
    refreshPanel()
    requestProcs()
end

function Buffs:Request()
    if queued then return end
    queued = true
    C_Timer.After(FLUSH_DELAY, function()
        queued = false
        if refreshAll then refreshAll() end
    end)
end

local function handleEvent(event, unit, castGUID, spellID)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        refreshPanel()                                -- cachée tout de suite en combat
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_DEAD" then
        shoutUntil = nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= nil and not isSecret(unit) and unit ~= "player" then return end
        if not isShout(spellID) then return end
        shoutUntil = GetTime() + (shoutDuration or SHOUT_DURATION)   -- tu viens de crier : relu ensuite si lisible
    elseif event == "UNIT_AURA" then
        if unit ~= nil and not isSecret(unit) and unit ~= "player" then return end
    end
    Buffs:Request()
end

---------------------------------------------------------------------------
-- Position, déplacement, aperçu
---------------------------------------------------------------------------
local function applyPosition()
    if not root then return end
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", tonumber(ns.db.buffX) or 0, tonumber(ns.db.buffY) or 160)
end

local function savePosition()
    local cx, cy = root:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s, u = root:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (cx and cy and ux and uy and s and u and s > 0) then return end
    ns:Set("buffX", math.floor(cx - ux * u / s + 0.5))
    ns:Set("buffY", math.floor(cy - uy * u / s + 0.5))
end

local function build()
    local T = ns.THEME
    root = CreateFrame("Frame", "PlatyplusBuffs", UIParent)
    root:SetSize(120, 16 + ICON + 3 + NAME_H)
    root:SetFrameStrata("MEDIUM")
    root:SetClampedToScreen(true)
    root:SetMovable(true)
    root:EnableMouse(false)                           -- ne bloque jamais les clics
    if root.SetDontSavePosition then pcall(root.SetDontSavePosition, root, true) end
    root:Hide()
    title = draw.fontString(root, 11, "OUTLINE")
    title:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    title:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    title:SetText(ns.T("Buffs à demander"))

    mover = CreateFrame("Frame", nil, root)
    mover:SetPoint("TOPLEFT", root, "TOPLEFT", -12, 26)
    mover:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 12, -8)
    mover:SetFrameLevel(60)
    local A = T.accent
    draw.nineSlice(mover, "BACKGROUND", 0, ns.MEDIA .. "Round", 0.25, 8, 0):SetColor(A[1], A[2], A[3], 0.20)
    draw.nineSlice(mover, "BORDER", 0, ns.MEDIA .. "RoundStroke", 0.25, 8, 0):SetColor(A[1], A[2], A[3], 0.95)
    local head = draw.fontString(mover, 12, "OUTLINE")
    head:SetPoint("TOP", mover, "TOP", 0, -6)
    head:SetTextColor(A[1], A[2], A[3])
    head:SetText(ns.T("Buffs à demander — glisse-moi"))
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function() root:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        if root.SetUserPlaced then pcall(root.SetUserPlaced, root, false) end
        savePosition()
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Buffs:ToggleMove() end
    end)
    mover:Hide()

    events = CreateFrame("Frame")
    Buffs.frames = { root = root, title = title, mover = mover, events = events }
    Buffs.items = items
end

local function applyRaw()
    moving = ns.db.buffLocked == false
    mover:SetShown(moving)
    applyPosition()
    registerEvents()
    if not ns.db.buffShout then shoutTimer = shoutTimer + 1 end
    doRefresh()
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function Buffs:Apply()
    if not (root and ns.db) then return end
    applyAll()
end

-- l'alerte de proc doit-elle tourner pour nous ?
function Buffs:WantsAlerts()
    return ns.db and ns.db.buffShout and true or false
end

-- pour Procs:Collect : le Cri de guerre manquant en combat, un élément par bouton qui le contient
function Buffs:Reminders()
    local list = {}
    if not (lib and ns.db and ns.db.buffShout and inCombat) then return list end
    if not shoutMissing() then return list end
    local name = shoutName()
    for _, a in ipairs(lib.actions()) do
        if a.spellID and isShout(a.spellID) then
            list[#list + 1] = { spellID = a.spellID, action = a.action, button = a.button,
                name = name and ns.Tf("%s manquant", name) or ns.T("Cri de guerre manquant") }
        end
    end
    return list
end

-- ce que montre la rangée « buffs à demander » (tests, /pp buffs)
function Buffs:Shown()
    return shown
end

function Buffs:InCombat()
    return inCombat
end

-- /pp buffs : état lisible
function Buffs:Status()
    local lines = {}
    local name = shoutName() or ns.T("Cri de guerre")
    local onBars = false
    if lib then
        for _, a in ipairs(lib.actions()) do
            if a.spellID and isShout(a.spellID) then onBars = true break end
        end
    end
    local state
    if not onBars then
        state = ns.T("pas sur tes barres : pas de rappel")
    elseif shoutMissing() then
        state = ns.T("tu ne l'as pas")
    elseif shoutUntil == math.huge then
        state = ns.T("actif")
    else
        state = ns.Tf("actif (encore %d s)", math.max(0, math.floor(shoutUntil - GetTime())))
    end
    lines[#lines + 1] = ns.Tf("%s en combat : %s - %s", name, ns.db.buffShout and "ON" or "OFF", state)
        .. (shoutReadable() and "" or ns.T(" (lecture des buffs cachée par le jeu en ce moment)"))
    local missing = allyMissing()
    local text
    if missing == nil then
        text = ns.T("illisible en ce moment")
    elseif #missing == 0 then
        text = ns.T("rien à demander")
    else
        local parts = {}
        for _, e in ipairs(missing) do
            parts[#parts + 1] = tostring(e.name or ns.Tf("sort %d", e.spellID)) .. " (" .. (isSecret(e.ally) and "?" or tostring(e.ally)) .. ")"
        end
        text = table.concat(parts, ", ")
    end
    lines[#lines + 1] = ns.Tf("Buffs de tes alliés : %s - %s", ns.db.buffAllies and "ON" or "OFF", text)
    return lines
end

function Buffs:ToggleMove()
    if not root then return end
    local unlock = ns.db.buffLocked ~= false
    ns:Set("buffLocked", not unlock)
    if unlock then
        ns:Print("buffs à demander : glisse la rangée où tu veux, puis clic droit dessus (ou Verrouiller) pour la verrouiller")
    else
        ns:Print("buffs à demander : position enregistrée")
    end
end

function Buffs:ResetPosition()
    ns:Reset("buffX")
    ns:Reset("buffY")
end

-- montre la rangée quelques secondes avec deux buffs d'exemple
function Buffs:Preview(seconds)
    if not root then return end
    previewToken = previewToken + 1
    local token = previewToken
    previewing = true
    self:Apply()
    C_Timer.After(tonumber(seconds) or PREVIEW_SECONDS, function()
        if token ~= previewToken then return end
        previewing = false
        Buffs:Apply()
    end)
end

---------------------------------------------------------------------------
-- Demander un buff : clic droit sur un joueur -> « Demander un buff » -> la liste de ce que sa classe peut donner ;
-- un clic lui chuchote la demande (« Salut ! Tu pourrais me mettre Bénédiction des rois stp ? Merci :) »).
-- Vérifié dans le code de Forever :
--  * Menu.ModifyMenu(tag, fn(owner, rootDescription, contextData)) ajoute des lignes aux menus clic droit, sans
--    taint (Blizzard_Menu/11_0_0_MenuImplementationGuide.lua) ; tag = "MENU_UNIT_" .. type de menu
--    (Blizzard_UnitPopupShared/UnitPopupShared.lua, SetTag ; types dans UnitPopupSharedMenus.lua) ;
--  * contextData : .unit (portrait, cadre de groupe) ou .name/.surname/.playerLocation (nom cliqué dans le chat) ;
--  * UnitClass : le nom de fichier de classe (PALADIN...) n'est jamais secret ; C_PlayerInfo.GetClass(playerLocation) ;
--  * C_ChatInfo.SendChatMessage refuse les arguments secrets venant d'un addon (AllowedWhenUntainted) : si le jeu
--    cache le nom (instance), pas de chuchotement possible -> la demande part dans le chat du groupe.
-- NON VÉRIFIÉ en jeu.
---------------------------------------------------------------------------
local ASK_TAGS = { "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "TARGET", "FOCUS", "FRIEND", "GUILD", "CHAT_ROSTER",
    "COMMUNITIES_WOW_MEMBER", "COMMUNITIES_GUILD_MEMBER" }
-- par classe, dans l'ordre du menu : id = sort (nom et icône du menu lus dans le jeu) ; fr/en = le mot court
-- envoyé (« rois stp », « BoK pls ») ; label = texte du menu quand ce n'est pas le nom du sort.
-- Numéros vérifiés dans SpellName (wago.tools).
local ASK_BUFFS = {
    PALADIN = { { id = 20217, fr = "rois", en = "BoK" }, { id = 19740, fr = "puissance", en = "BoM" },
                { id = 19742, fr = "sagesse", en = "BoW" }, { id = 1038, fr = "salut", en = "Salv" },
                { id = 19977, fr = "lumière", en = "BoL" } },
    PRIEST  = { { id = 1243, fr = "buff endu", en = "Fort" }, { id = 14752, fr = "esprit", en = "Spirit" },
                { id = 976, fr = "prot ombre", en = "Shadow prot" } },
    DRUID   = { { id = 1126, fr = "marque", en = "MotW" }, { id = 467, fr = "épines", en = "Thorns" } },
    MAGE    = { { id = 1459, fr = "buff int", en = "Int" }, { id = 604, fr = "atténuation", en = "Dampen" },
                { id = 1008, fr = "amplification", en = "Amplify" },
                { id = 587, label = "De la nourriture", fr = "à manger", en = "food" },
                { id = 5504, label = "De l'eau", fr = "de l'eau", en = "water" } },
    WARLOCK = { { id = 5697, fr = "respi", en = "breath" }, { id = 132, fr = "détec invi", en = "detect invis" },
                { id = 6201, label = "Une pierre de soins", fr = "pierre de soins", en = "HS" },
                { id = 698, label = "M'invoquer", fr = "invoc", en = "summon" } },
    SHAMAN  = { { id = 131, fr = "respi", en = "water breathing" },
                { id = 546, fr = "marche sur l'eau", en = "water walk" } },
}
-- première ligne du sous-menu : demander « un buff » sans préciser lequel
local ASK_ALL = { all = true, label = "Tous ses buffs", fr = "buff", en = "buff" }
local ASK_CLASS = {
    fr = { PALADIN = "Paladin", PRIEST = "Prêtre", DRUID = "Druide", MAGE = "Mage", WARLOCK = "Démoniste",
           SHAMAN = "Chaman" },
    en = { PALADIN = "Paladin", PRIEST = "Priest", DRUID = "Druid", MAGE = "Mage", WARLOCK = "Warlock",
           SHAMAN = "Shaman" },
}
-- phrases : chuchotement, et chat de groupe (classe : demande)
local ASK_TEXT = {
    fr = { whisper = "Salut, %s stp ? Merci :)", group = "%s, %s stp ? Merci :)", anyone = "Hé" },
    en = { whisper = "Hi, could I get %s pls? Thanks :)", group = "%s, could I get %s pls? Thanks :)", anyone = "Hey" },
}

-- langue du message (réglage buffAskLang) et mot court pour une ligne du menu
local function askLang()
    return (ns.db and ns.db.buffAskLang == "en") and "en" or "fr"
end

local function askWhat(entry, lang)
    return entry[lang] or spellName(entry.id) or "buff"
end

local function plain(v)                   -- v si lisible, nil si secret (tester le secret AVANT toute comparaison)
    if isSecret(v) or v == nil then return nil end
    return v
end

local function callPlain(fnName, ...)     -- premier retour d'une API globale, nil si absente, en erreur ou secret
    local f = api(fnName)
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, ...)
    if not ok then return nil end
    return plain(v)
end

-- classe (PALADIN...) du joueur du menu ; nil si ce n'est pas un joueur ou si on ne sait pas
local function askClass(data)
    local unit = data.unit
    if unit then
        if callPlain("UnitIsPlayer", unit) == false then return nil end
        if callPlain("UnitCanCooperate", "player", unit) == false then return nil end
        local f = api("UnitClass")
        if type(f) == "function" then
            local ok, _, file = pcall(f, unit)
            if ok and type(plain(file)) == "string" then return file end
        end
    end
    local P = api("C_PlayerInfo")
    if data.playerLocation and type(P) == "table" and type(P.GetClass) == "function" then
        local ok, _, file = pcall(P.GetClass, data.playerLocation)
        if ok and type(plain(file)) == "string" then return file end
    end
    local byGUID = api("GetPlayerInfoByGUID")
    if data.guid and type(byGUID) == "function" then
        local ok, _, file = pcall(byGUID, data.guid)
        if ok and type(plain(file)) == "string" then return file end
    end
    -- dernier recours (instance : UnitClass peut être secret) : position créée depuis le jeton d'unité
    local PL = api("PlayerLocation")
    if unit and type(P) == "table" and type(P.GetClass) == "function" and type(PL) == "table"
        and type(PL.CreateFromUnit) == "function" then
        local ok, loc = pcall(PL.CreateFromUnit, PL, unit)
        if ok and loc then
            local ok2, _, file = pcall(P.GetClass, loc)
            if ok2 and type(plain(file)) == "string" then return file end
        end
    end
    return nil
end

local function askIsSelf(data)
    if data.unit and callPlain("UnitIsUnit", data.unit, "player") == true then return true end
    local me, name = callPlain("UnitNameUnmodified", "player"), plain(data.name)
    return me ~= nil and name ~= nil and me == name
end

-- nom à qui chuchoter (« Nom » ou « Nom-Royaume ») ; nil s'il est secret
local function askTarget(data)
    local name
    local util = api("UnitPopupSharedUtil")
    if type(util) == "table" and type(util.GetFullPlayerName) == "function" then
        local ok, n = pcall(util.GetFullPlayerName, data)
        if ok then name = plain(n) end
    end
    if name == nil then
        name = plain(data.name)
        local realm = plain(data.surname) or plain(data.server)
        if type(name) == "string" and type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
    end
    name = plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

local function askSender()
    local C = api("C_ChatInfo")
    if type(C) == "table" and type(C.SendChatMessage) == "function" then return C.SendChatMessage end
    local f = api("SendChatMessage")
    if type(f) == "function" then return f end
    return nil
end

-- le joueur du menu est-il dans ton groupe ? et sur quel canal lui parler
local function askGroupChannel(unit)
    if type(unit) ~= "string" then return nil end
    local mine = unit:find("^party") or unit:find("^raid") or callPlain("UnitInParty", unit) == true
        or callPlain("UnitInRaid", unit) ~= nil
    if not mine then return nil end
    local home = (Enum and Enum.PartyCategory and Enum.PartyCategory.Home) or 1
    local instance = (Enum and Enum.PartyCategory and Enum.PartyCategory.Instance) or 2
    if callPlain("IsInGroup", instance) == true and callPlain("IsInGroup", home) ~= true then return "INSTANCE_CHAT" end
    if callPlain("IsInRaid") == true then return "RAID" end
    if callPlain("IsInGroup") == true then return "PARTY" end
    return nil
end

-- envoie la demande ; renvoie le canal utilisé ("WHISPER", "PARTY"...) ou nil
function Buffs:Ask(data, classFile, entry)
    local lang = askLang()
    local text = ASK_TEXT[lang]
    local what = askWhat(entry, lang)
    local C = api("C_ChatInfo")
    if type(C) == "table" and type(C.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(C.InChatMessagingLockdown)
        if ok and plain(locked) == true then
            ns:Print("le jeu bloque le chat en ce moment (combat de boss) : réessaie juste après.")
            return nil
        end
    end
    local send = askSender()
    if not send then ns:Print("impossible d'envoyer un message ici.") return nil end
    local target = askTarget(data)
    if target then
        local ok, err = pcall(send, text.whisper:format(what), "WHISPER", nil, target)
        if ok then return "WHISPER" end
        ns:Debug("Buffs : chuchotement refusé : " .. tostring(err))
    end
    local channel = askGroupChannel(data.unit)
    if channel then
        local who = ASK_CLASS[lang][classFile] or text.anyone
        local ok, err = pcall(send, text.group:format(who, what), channel)
        if ok then return channel end
        ns:Debug("Buffs : message de groupe refusé : " .. tostring(err))
    end
    ns:Print("impossible de lui écrire ici (le jeu cache son nom ou bloque le chat) : demande-lui à la main.")
    return nil
end

-- lignes ajoutées au menu clic droit
local function addAskMenu(_, rootDescription, data)
    if not (ns.db and ns.db.buffAsk) or type(data) ~= "table" or not rootDescription then return end
    local classFile = askClass(data)
    local list = classFile and ASK_BUFFS[classFile]
    if not list or askIsSelf(data) then return end
    local rows = {}
    for _, entry in ipairs(list) do
        local label = entry.label and ns.T(entry.label) or spellName(entry.id)
        if label then rows[#rows + 1] = { entry = entry, label = label } end
    end
    if #rows == 0 then return end
    rootDescription:CreateDivider()
    local sub = rootDescription:CreateButton(ns.T("Demander un buff"))
    sub:CreateButton(ns.T(ASK_ALL.label), function()
        local ok, err = pcall(Buffs.Ask, Buffs, data, classFile, ASK_ALL)
        if not ok then ns:Debug("Buffs : demande de buff : " .. tostring(err)) end
    end)
    if sub.CreateDivider then sub:CreateDivider() end
    for _, row in ipairs(rows) do
        local entry = row.entry
        local tex = spellTexture(entry.id)
        sub:CreateButton("|T" .. tostring(tex) .. ":16:16:0:0:64:64:5:59:5:59|t " .. row.label, function()
            local ok, err = pcall(Buffs.Ask, Buffs, data, classFile, entry)
            if not ok then ns:Debug("Buffs : demande de buff : " .. tostring(err)) end
        end)
    end
end

local askMenuReady = false
local function setupAskMenu()
    if askMenuReady then return end
    local M = api("Menu")
    if type(M) ~= "table" or type(M.ModifyMenu) ~= "function" then
        ns:Debug("Buffs : Menu.ModifyMenu absent, pas de « Demander un buff » au clic droit")
        return
    end
    askMenuReady = true
    local function safeAdd(owner, rootDescription, data)
        local ok, err = pcall(addAskMenu, owner, rootDescription, data)
        if not ok then ns:Debug("Buffs : menu clic droit : " .. tostring(err)) end
    end
    for _, which in ipairs(ASK_TAGS) do
        pcall(M.ModifyMenu, "MENU_UNIT_" .. which, safeAdd)
    end
end

-- pour les tests et /pp buffs : ce que le menu proposerait pour une classe
function Buffs:AskList(classFile)
    local out = {}
    for _, entry in ipairs(ASK_BUFFS[classFile] or {}) do out[#out + 1] = entry.label or spellName(entry.id) end
    return out
end

function Buffs:Init()
    if not isSecret then
        isSecret = function(v)
            local f = rawget(_G, "issecretvalue")
            return type(f) == "function" and f(v) and true or false
        end
    end
    setupAskMenu()
    lib = ns.Resources and ns.Resources.lib
    draw = ns.ResourceBar and ns.ResourceBar.nineSlice and { nineSlice = ns.ResourceBar.nineSlice, fontString = ns.ResourceBar.fontString }
    if not (lib and draw) then
        ns:Debug("Buffs : Resources.lua ou ResourceBar.lua absent, rappel de buffs désactivé")
        return
    end
    isSecret = lib.isSecret
    local lockdown = api("InCombatLockdown")
    inCombat = type(lockdown) == "function" and lockdown() and true or false
    build()
    onEvent = lib.guard(NAME, handleEvent)
    refreshAll = lib.guard(NAME, doRefresh)
    applyAll = lib.guard(NAME, applyRaw)
    events:SetScript("OnEvent", function(_, event, ...) onEvent(event, ...) end)
    lib.subscribe(function(reason)                  -- barres d'action changées : le cri a peut-être bougé
        if reason == "actions" and ns.db.buffShout then requestProcs() end
    end)
    for _, key in ipairs(KEYS) do
        ns:OnChange(key, function()
            lib.resetFailures(NAME)
            Buffs:Apply()
            if key == "buffShout" and ns.Procs and ns.Procs.Apply then ns.Procs:Apply() end
        end)
    end
    for key in pairs(POSITION_KEYS) do ns:OnChange(key, applyPosition) end
    self:Apply()
end
