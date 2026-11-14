-- Platyplus : barre de mana du healer
-- Une barre posée où tu veux à l'écran (comme la barre de ressource) qui montre la mana du soigneur de ton groupe :
-- son nom (à la couleur de sa classe) et « 4 320 / 6 800 ».
--
-- Qui est « ton healer » ?
--  1. le joueur choisi avec le bouton « Mon healer = ma cible » (réglage healerName), tant qu'il est dans le groupe ;
--  2. sinon le soigneur désigné par le groupe (rôle « soigneur » : file de donjon, ou donné par le chef de groupe).
--
-- Vérifié dans le code de Forever (UnitDocumentation.lua) : UnitGroupRolesAssigned(unit) -> "HEALER" | "TANK" | "DAMAGER" |
-- "NONE" ; UnitPower / UnitPowerMax(unit, mana) ; événements UNIT_POWER_UPDATE, UNIT_MAXPOWER, UNIT_DISPLAYPOWER (ceux
-- que CompactUnitFrame écoute pour la mana d'un allié) ; PLAYER_ROLES_ASSIGNED et GROUP_ROSTER_UPDATE pour les rôles.
-- NON VÉRIFIÉ en jeu : l'affichage pendant les restrictions de combat (valeurs secrètes).
--
-- Alerte « healer à sec » (healerLow, healerLowPercent, healerLowSound) : sous le seuil, la barre et son liseré virent au
-- rouge, un double éclat part une fois, et un son si l'option est cochée (en combat seulement). L'alerte se relâche
-- 5 points au-dessus du seuil (sinon elle clignoterait autour). Vérifié dans le code de Forever : UnitPowerPercent(unit,
-- mana, false) vaut 0..1 (CurveConstants, Blizzard_SharedXMLBase) ; C_CurveUtil.CreateColorCurve + Enum.LuaCurveType.Step ;
-- StatusBar:SetStatusBarColor accepte des couleurs secrètes (SecretArguments = "AllowedWhenTainted") ; SOUNDKIT.RAID_WARNING.
-- Quand la mana est secrète on ne peut pas la comparer : le seuil est alors confié au jeu, par une courbe de couleur
-- (rouge sous le seuil, couleur de la mana au-dessus) évaluée par UnitPowerPercent. Pas d'éclat ni de son dans ce cas :
-- il faudrait un booléen lisible. NON VÉRIFIÉ en jeu : cette teinte par courbe.
--
-- Valeurs secrètes (voir Resources.lua) : UnitPower, UnitPowerMax, UnitName, UnitGroupRolesAssigned peuvent être secrets.
-- La mana et le nom sont passés tels quels à StatusBar:SetValue / SetText, sans calcul ni comparaison ; un rôle ou un nom
-- secret ne se compare pas : on garde alors le healer déjà trouvé.
--
-- Optimisation : aucune boucle OnUpdate. On n'écoute que la mana d'UN seul joueur (RegisterUnitEvent) et les changements
-- de groupe ; la liste du groupe n'est relue qu'à ces occasions. Option coupée : plus aucun événement écouté.
local ADDON, ns = ...

local Healer = {}
ns.HealerMana = Healer

local NAME = "mana du healer"          -- nom affiché par le garde-fou s'il coupe la barre
local BAR_H = 22
local INSET = 3
local PREVIEW_SECONDS = 6
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local MANA_TOKEN = "MANA"
local DIM = "|cff9da3b0"
local SAMPLE_NAME, SAMPLE_CUR, SAMPLE_MAX = "Mon healer", 4200, 6800   -- barre d'exemple : aperçu, déplacement
local LACK = { 1.00, 0.30, 0.30 }       -- rouge « à sec » (le même que « pas assez de ressource » de la barre de ressource)
local LOW_RELEASE = 5                   -- l'alerte se relâche 5 points au-dessus du seuil
local FLASH_TIME = 1.2                  -- durée du double éclat (s)
local FALLBACK_SOUND = 8959             -- SOUNDKIT.RAID_WARNING

local KEYS = {
    "healerBar", "healerName", "healerWidth", "healerScale", "healerX", "healerY", "healerLocked",
    "healerLow", "healerLowPercent",     -- healerLowSound ne change rien à l'affichage : lu au moment de l'alerte
}
local POSITION_KEYS = { healerX = true, healerY = true, healerScale = true }

local lib, isSecret, draw
local root, fill, top, nameText, valueText, mover, events, stroke, flash, driver
local unit                              -- jeton du healer suivi ("party2", "raid17"...) ou nil
local hasMana = true                    -- faux si le healer suivi n'a pas de mana (maximum lisible à 0)
local active, previewing, moving = false, false, false
local previewToken = 0
local sampleCur = SAMPLE_CUR            -- mana de la barre d'exemple (elle tombe sous le seuil pendant l'aperçu)
local low = false                       -- alerte « à sec » en cours
local secretMode = false                -- dernière valeur lue : secrète
local flashTime = 0
local curve, curveThreshold, curveFailed   -- courbe de couleur pour la mana secrète
local onEvent, animate, applyAll        -- fonctions protégées par le garde-fou (créées dans Init)

---------------------------------------------------------------------------
-- Qui est le healer ?
---------------------------------------------------------------------------
local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- API facultatives lues sans faire d'erreur si le client ne les a pas
local function api(name) return rawget(_G, name) end

-- membres du groupe et « est-ce moi ? » : partagés avec Buffs.lua (Resources.lib)
local function groupUnits() return lib.groupUnits() end
local function isMe(u) return lib.isMe(u) end

-- renvoie (jeton, incertain) : incertain = vrai si une valeur secrète nous a empêchés de comparer
local function findHealer()
    local wanted = ns.db and ns.db.healerName or ""
    local uncertain, byRole = false, nil
    local roleOf = api("UnitGroupRolesAssigned")
    for _, u in ipairs(groupUnits()) do
        if UnitExists(u) and not isMe(u) then
            if wanted ~= "" then
                local name = UnitName(u)
                if isSecret(name) then
                    uncertain = true
                elseif name == wanted then
                    return u, false
                end
            end
            if not byRole and type(roleOf) == "function" then
                local role = roleOf(u)
                if isSecret(role) then
                    uncertain = true
                elseif role == "HEALER" then
                    byRole = u
                end
            end
        end
    end
    return byRole, uncertain
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local savePosition

local function barWidth()
    return math.floor(clamp(ns.db.healerWidth or 200, 100, 600) + 0.5)
end

local function createUI()
    local T = ns.THEME
    root = CreateFrame("Frame", "PlatyplusHealerMana", UIParent)
    root:SetSize(200, BAR_H)
    root:SetFrameStrata("MEDIUM")
    root:SetClampedToScreen(true)
    root:SetMovable(true)
    root:EnableMouse(false)          -- la barre ne bloque jamais les clics
    if root.SetDontSavePosition then pcall(root.SetDontSavePosition, root, true) end
    root:Hide()

    -- même fond que la barre de ressource : ombre douce, fond arrondi, liseré léger
    draw.nineSlice(root, "BACKGROUND", -8, ns.MEDIA .. "Shadow", 0.375, 16, 12):SetColor(0, 0, 0, 0.85)
    draw.nineSlice(root, "BACKGROUND", 0, ns.MEDIA .. "Round", 0.25, 7, 0):SetColor(T.card[1], T.card[2], T.card[3], 0.94)
    stroke = draw.nineSlice(root, "BORDER", 0, ns.MEDIA .. "RoundStroke", 0.25, 7, 0)   -- rouge pendant l'alerte
    stroke:SetColor(1, 1, 1, 0.10)

    fill = CreateFrame("StatusBar", nil, root)
    fill:SetPoint("TOPLEFT", root, "TOPLEFT", INSET, -INSET)
    fill:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -INSET, INSET)
    fill:SetStatusBarTexture(ns.MEDIA .. "Bar")
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    fill:SetStatusBarColor(lib.powerColor(MANA, MANA_TOKEN, 0.1))
    local track = fill:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(fill)
    track:SetColorTexture(0, 0, 0, 0.35)

    top = CreateFrame("Frame", nil, root)
    top:SetAllPoints(fill)
    top:SetFrameLevel((fill:GetFrameLevel() or 1) + 3)

    -- éclat rouge de l'alerte (par-dessus le remplissage, sous les textes)
    flash = top:CreateTexture(nil, "ARTWORK", nil, -1)
    flash:SetAllPoints(top)
    flash:SetColorTexture(LACK[1], LACK[2], LACK[3], 1)
    flash:SetAlpha(0)

    -- le chiffre à droite, le nom à gauche (coupé proprement s'il est trop long)
    valueText = draw.fontString(top, 13, "OUTLINE")
    valueText:SetPoint("RIGHT", top, "RIGHT", -5, 0)
    valueText:SetJustifyH("RIGHT")
    nameText = draw.fontString(top, 12, "OUTLINE")
    nameText:SetPoint("LEFT", top, "LEFT", 5, 0)
    nameText:SetPoint("RIGHT", valueText, "LEFT", -6, 0)
    nameText:SetJustifyH("LEFT")

    -- cadre de déplacement
    mover = CreateFrame("Frame", nil, root)
    mover:SetPoint("TOPLEFT", root, "TOPLEFT", -12, 30)
    mover:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 12, -30)
    mover:SetFrameLevel((top:GetFrameLevel() or 1) + 30)
    local A = T.accent
    draw.nineSlice(mover, "BACKGROUND", 0, ns.MEDIA .. "Round", 0.25, 8, 0):SetColor(A[1], A[2], A[3], 0.20)
    draw.nineSlice(mover, "BORDER", 0, ns.MEDIA .. "RoundStroke", 0.25, 8, 0):SetColor(A[1], A[2], A[3], 0.95)
    local title = draw.fontString(mover, 12, "OUTLINE")
    title:SetPoint("TOP", mover, "TOP", 0, -8)
    title:SetTextColor(A[1], A[2], A[3])
    title:SetText(ns.T("Mana du healer — glisse-moi"))
    local hint = draw.fontString(mover, 10, "")
    hint:SetPoint("BOTTOM", mover, "BOTTOM", 0, 8)
    hint:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    hint:SetText(ns.T("clic droit : verrouiller"))
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function() root:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        if root.SetUserPlaced then pcall(root.SetUserPlaced, root, false) end
        savePosition()
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Healer:ToggleMove() end
    end)
    mover:Hide()

    -- animation de l'éclat : visible seulement pendant l'éclat, puis elle s'arrête d'elle-même
    driver = CreateFrame("Frame")
    driver:Hide()
    events = CreateFrame("Frame")

    Healer.frames = {
        root = root, fill = fill, top = top, name = nameText, value = valueText, mover = mover, events = events,
        flash = flash, driver = driver, stroke = stroke,
    }
end

---------------------------------------------------------------------------
-- Affichage : nom, valeur, visibilité
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Alerte « healer à sec »
---------------------------------------------------------------------------
local function lowThreshold()
    return clamp(ns.db.healerLowPercent or 20, 1, 90)
end

-- couleur du remplissage et du liseré selon l'état (ne s'appelle que quand l'état change)
local function paintLow()
    if low then
        fill:SetStatusBarColor(LACK[1], LACK[2], LACK[3])
        stroke:SetColor(LACK[1], LACK[2], LACK[3], 0.85)
    else
        fill:SetStatusBarColor(lib.powerColor(MANA, MANA_TOKEN, 0.1))
        stroke:SetColor(1, 1, 1, 0.10)
    end
end

local function resetLow()
    low = false
    paintLow()
end

local function playAlertSound()
    local play = rawget(_G, "PlaySound")
    if type(play) ~= "function" then return end
    local kit = rawget(_G, "SOUNDKIT")
    pcall(play, (type(kit) == "table" and kit.RAID_WARNING) or FALLBACK_SOUND)
end

-- double éclat rouge, et le son si l'option est cochée (en combat seulement : un healer qui boit hors combat est « à sec »
-- exprès ; force = pendant l'aperçu, pour entendre le son)
local function raiseAlert(force)
    flashTime = 0
    driver:Show()
    if ns.db.healerLowSound then
        local inCombat = rawget(_G, "InCombatLockdown")
        if force or (type(inCombat) == "function" and inCombat()) then playAlertSound() end
    end
end

-- mana lisible : l'alerte s'allume sous le seuil et se relâche LOW_RELEASE points au-dessus
local function evaluateLow(cur, max, force)
    local was = low
    if ns.db.healerLow and max > 0 then
        local pct = cur / max * 100
        local threshold = lowThreshold()
        if low then
            if pct >= math.min(threshold + LOW_RELEASE, 100) then low = false end
        elseif pct < threshold then
            low = true
        end
    else
        low = false
    end
    if low ~= was then
        paintLow()
        if low then raiseAlert(force) end
    end
end

-- mana secrète : on ne peut rien comparer. Le jeu évalue lui-même une courbe de couleur (rouge sous le seuil, couleur de la
-- mana au-dessus) sur le pourcentage, et on pose la couleur obtenue telle quelle sur la barre.
local function buildCurve(threshold)
    local util, enum, mk = rawget(_G, "C_CurveUtil"), rawget(_G, "Enum"), rawget(_G, "CreateColor")
    if not (type(util) == "table" and util.CreateColorCurve and type(mk) == "function"
        and type(enum) == "table" and enum.LuaCurveType) then return nil end
    local ok, result = pcall(function()
        local c = util.CreateColorCurve()
        c:SetType(enum.LuaCurveType.Step)
        c:AddPoint(0, mk(LACK[1], LACK[2], LACK[3], 1))
        local r, g, b = lib.powerColor(MANA, MANA_TOKEN, 0.1)
        c:AddPoint(threshold / 100, mk(r, g, b, 1))
        return c
    end)
    return ok and result or nil
end

local function tintSecret()
    local percent = rawget(_G, "UnitPowerPercent")
    local wanted = ns.db.healerLow and type(percent) == "function" and not curveFailed
    if wanted then
        local threshold = lowThreshold()
        if not curve or curveThreshold ~= threshold then
            curve, curveThreshold = buildCurve(threshold), threshold
            if not curve then curveFailed = true end
        end
        if curve then
            -- tout dans le pcall : le résultat est peut-être secret, on ne le teste pas
            local ok = pcall(function()
                local color = percent(unit, MANA, false, curve)
                fill:SetStatusBarColor(color:GetRGBA())
            end)
            if ok then return end
            curveFailed = true
        end
    end
    fill:SetStatusBarColor(lib.powerColor(MANA, MANA_TOKEN, 0.1))
end

local function paintSample()
    local T = ns.THEME
    nameText:SetText(ns.T(SAMPLE_NAME))
    nameText:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    fill:SetMinMaxValues(0, SAMPLE_MAX)
    fill:SetValue(sampleCur)
    valueText:SetText(lib.plainNumber(sampleCur) .. " " .. DIM .. "/ " .. lib.plainNumber(SAMPLE_MAX) .. "|r")
    if secretMode then
        secretMode = false
        paintLow()
    end
    evaluateLow(sampleCur, SAMPLE_MAX, true)
end

local function paintName()
    local T = ns.THEME
    local name = UnitName(unit)
    nameText:SetText(name)                      -- peut être secret : SetText l'accepte
    local _, classFile = UnitClass(unit)
    local color = (not isSecret(classFile)) and type(classFile) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then
        nameText:SetTextColor(color.r, color.g, color.b)
    else
        nameText:SetTextColor(T.text[1], T.text[2], T.text[3])
    end
end

local function paintValue()
    local cur = UnitPower(unit, MANA)
    local max = UnitPowerMax(unit, MANA)
    if isSecret(cur) or isSecret(max) then
        -- valeur secrète : affichage direct, ni calcul ni comparaison ; le seuil d'alerte est confié au jeu (courbe)
        hasMana = true
        fill:SetMinMaxValues(0, max)
        fill:SetValue(cur)
        valueText:SetText(string.format("%d " .. DIM .. "/ %d|r", cur, max))
        if not secretMode then
            secretMode = true
            low = false                           -- pas d'éclat ni de son sans valeur lisible
            stroke:SetColor(1, 1, 1, 0.10)
        end
        tintSecret()
    else
        max = tonumber(max) or 0
        cur = tonumber(cur) or 0
        hasMana = max > 0
        fill:SetMinMaxValues(0, math.max(max, 1))
        fill:SetValue(cur)
        valueText:SetText(lib.plainNumber(cur) .. " " .. DIM .. "/ " .. lib.plainNumber(max) .. "|r")
        if secretMode then
            secretMode = false
            paintLow()                            -- retire la teinte de la courbe
        end
        evaluateLow(cur, max, false)
    end
end

local function wantShown()
    if moving or previewing then return true end
    return ns.db.healerBar and unit ~= nil and hasMana and true or false
end

local function updateVisibility()
    if wantShown() then
        root:Show()
    else
        root:Hide()
    end
end

-- barre d'exemple : toujours pendant l'aperçu (il montre aussi l'alerte), et pendant le déplacement s'il n'y a pas de healer
local function showSample()
    return previewing or (moving and not unit)
end

-- relit tout ce qui s'affiche : la barre d'exemple si besoin, sinon le healer réel s'il y en a un
local function repaint()
    if showSample() then
        hasMana = true
        paintSample()
    elseif unit then
        paintName()
        paintValue()
    else
        hasMana = true
        if low or secretMode then
            secretMode = false
            resetLow()
        end
    end
    updateVisibility()
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local function registerEvents()
    events:UnregisterAllEvents()
    if not active then return end
    lib.registerEvent(events, "GROUP_ROSTER_UPDATE")
    lib.registerEvent(events, "PLAYER_ROLES_ASSIGNED")
    lib.registerEvent(events, "PLAYER_ENTERING_WORLD")
    if unit then       -- la mana d'un seul joueur : le jeu ne nous réveille que pour lui
        lib.registerUnitEvent(events, "UNIT_POWER_UPDATE", unit)
        lib.registerUnitEvent(events, "UNIT_MAXPOWER", unit)
        lib.registerUnitEvent(events, "UNIT_DISPLAYPOWER", unit)
    end
end

-- relit la liste du groupe : qui est le healer ?
local function refreshUnit()
    local found, uncertain = findHealer()
    if not found and uncertain and unit and UnitExists(unit) then
        found = unit               -- valeur secrète : on ne peut pas comparer, on garde le healer déjà trouvé
    end
    if found ~= unit then
        unit = found
        if not showSample() then resetLow() end    -- un autre healer : l'alerte repart de zéro
        registerEvents()
    end
    repaint()
end

local function handleEvent(event, who, token)
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        if not unit or showSample() then return end
        if who ~= nil and not isSecret(who) and who ~= unit then return end          -- repli sans RegisterUnitEvent
        if token ~= nil and not isSecret(token) and token ~= MANA_TOKEN and event == "UNIT_POWER_UPDATE" then return end
        paintValue()
        updateVisibility()
    else
        refreshUnit()              -- changement de groupe, de rôle ou entrée dans le monde
    end
end

---------------------------------------------------------------------------
-- Position et réglages
---------------------------------------------------------------------------
local function applyPosition()
    root:SetScale(clamp(ns.db.healerScale or 1, 0.3, 3))
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", tonumber(ns.db.healerX) or -260, tonumber(ns.db.healerY) or -120)
end

-- décalage du centre de la barre par rapport au centre de l'écran, dans l'échelle de la barre
function savePosition()
    local cx, cy = root:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s, u = root:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (cx and cy and ux and uy and s and u and s > 0) then return end
    ns:Set("healerX", math.floor(cx - ux * u / s + 0.5))
    ns:Set("healerY", math.floor(cy - uy * u / s + 0.5))
end

local function applyRaw()
    root:SetSize(barWidth(), BAR_H)
    applyPosition()
    moving = ns.db.healerLocked == false
    mover:SetShown(moving)
    active = (ns.db.healerBar or previewing or moving) and true or false
    registerEvents()
    if active then refreshUnit() else unit = nil; repaint() end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- réapplique tous les réglages
function Healer:Apply()
    if not (root and ns.db) then return end
    applyAll()
end

-- déverrouille / verrouille : déverrouillée, la barre reste visible avec un cadre « glisse-moi »
function Healer:ToggleMove()
    if not root then return end
    local unlock = ns.db.healerLocked ~= false
    ns:Set("healerLocked", not unlock)
    if unlock then
        ns:Print("mana du healer : glisse la barre où tu veux, puis clic droit dessus (ou Verrouiller) pour la verrouiller")
    else
        ns:Print("mana du healer : position enregistrée")
    end
end

function Healer:ResetPosition()
    ns:Reset("healerX")
    ns:Reset("healerY")
end

-- montre la barre quelques secondes, même désactivée ou sans healer, avec des valeurs d'exemple : la mana d'exemple
-- tombe sous le seuil au bout d'un moment, pour montrer l'alerte (éclat, et son si l'option est cochée)
function Healer:Preview(seconds)
    if not root then return end
    seconds = tonumber(seconds) or PREVIEW_SECONDS
    previewToken = previewToken + 1
    local token = previewToken
    sampleCur = SAMPLE_CUR
    if low or secretMode then
        secretMode = false
        resetLow()                 -- pour que l'alerte reparte à chaque aperçu
    end
    previewing = true
    self:Apply()
    C_Timer.After(math.min(2, seconds * 0.35), function()
        if token ~= previewToken or not previewing then return end
        sampleCur = math.floor(SAMPLE_MAX * math.max(lowThreshold() - 8, 2) / 100)
        repaint()
    end)
    C_Timer.After(seconds, function()
        if token ~= previewToken then return end
        previewing = false
        sampleCur = SAMPLE_CUR
        Healer:Apply()
    end)
end

-- « Mon healer = ma cible » : suit ce joueur, tant qu'il est dans le groupe
function Healer:PickTarget()
    if not UnitExists("target") then
        ns:Print("mana du healer : cible d'abord ton healer, puis reclique")
        return false
    end
    local member
    for _, u in ipairs(groupUnits()) do
        if UnitExists(u) and not isMe(u) then
            local isUnit = api("UnitIsUnit")
            local same = type(isUnit) == "function" and isUnit(u, "target")
            if not isSecret(same) and same then member = u break end
        end
    end
    if not member then
        ns:Print("mana du healer : ta cible n'est pas dans ton groupe")
        return false
    end
    local name = UnitName(member)
    if isSecret(name) or type(name) ~= "string" or name == "" then
        ns:Print("mana du healer : son nom est illisible en ce moment (restriction de combat), réessaie hors combat")
        return false
    end
    ns:Set("healerName", name)
    ns:Print(ns.Tf("mana du healer : tu suis maintenant %s%s", name, ns.db.healerBar and ""
        or ns.T(" (la barre est coupée : active « Afficher la mana de mon healer »)")))
    return true
end

-- « Laisser le jeu choisir » : le soigneur désigné par le groupe
function Healer:ClearPick()
    ns:Set("healerName", "")
    ns:Print("mana du healer : le healer est celui que désigne le groupe")
end

-- l'alerte « à sec » est-elle allumée ? (diagnostic et tests)
function Healer:IsLow()
    return low
end

-- texte pour la fenêtre d'options et /pp healer : qui est suivi en ce moment (lu à la demande)
function Healer:Summary()
    if not (ns.db and lib) then return nil end
    local u = findHealer()
    if not u then return nil end
    local name, className = UnitName(u), UnitClass(u)
    if isSecret(name) then return ns.T("suivi (nom masqué en combat)") end
    local text = tostring(name)
    if not isSecret(className) and type(className) == "string" then text = text .. " |cff999999(" .. className .. ")|r" end
    return text
end

-- double éclat : le rouge s'allume, s'éteint, se rallume, puis disparaît
local function animateRaw(self, elapsed)
    flashTime = flashTime + elapsed
    local k = flashTime / FLASH_TIME
    if k >= 1 then
        flash:SetAlpha(0)
        self:Hide()
        return
    end
    flash:SetAlpha(0.6 * (1 - k) * (0.5 + 0.5 * math.cos(k * math.pi * 4)))
end

function Healer:Init()
    lib = ns.Resources and ns.Resources.lib
    draw = ns.ResourceBar and ns.ResourceBar.nineSlice and { nineSlice = ns.ResourceBar.nineSlice, fontString = ns.ResourceBar.fontString }
    if not (lib and draw) then
        ns:Debug("HealerMana : Resources.lua ou ResourceBar.lua absent, barre de mana du healer désactivée")
        return
    end
    isSecret = lib.isSecret
    createUI()

    onEvent = lib.guard(NAME, handleEvent)
    applyAll = lib.guard(NAME, applyRaw)
    animate = lib.guard(NAME, animateRaw)
    events:SetScript("OnEvent", function(_, event, ...) onEvent(event, ...) end)
    driver:SetScript("OnUpdate", function(self, elapsed)
        if not animate(self, elapsed) then self:Hide() end
    end)

    for _, key in ipairs(KEYS) do
        ns:OnChange(key, function()
            lib.resetFailures(NAME)
            if POSITION_KEYS[key] then
                applyPosition()
            else
                Healer:Apply()
            end
        end)
    end
    self:Apply()
end
