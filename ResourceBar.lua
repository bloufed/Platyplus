-- Platyplus : barre de ressource (HUD)
-- Une grande barre lisible au centre bas de l'écran :
--  * fond sombre arrondi, remplissage à la couleur de la ressource (rage, énergie, mana...) avec un halo au bout,
--    le nom de la ressource à gauche et le chiffre « 45 / 100 » au centre ;
--  * un repère (trait fin + mini-icône au-dessus) à la position du coût de chacun de tes sorts des barres d'action :
--    tu vois d'un coup d'oeil quand la barre « passe » un sort ;
--  * dessous, les icônes de ces sorts triées par coût : allumées quand tu peux les lancer, grisées sinon,
--    avec le coût en rouge quand c'est la ressource qui manque.
--
-- Optimisation : tout passe par les événements (UNIT_POWER_FREQUENT du joueur seulement, entrée / sortie de combat ;
-- barres d'action et sorts abordables via Resources.lib qui regroupe les rafales). Aucune scrutation : la seule
-- boucle OnUpdate anime le remplissage et le fondu, puis s'arrête d'elle-même.
--
-- Valeurs secrètes (voir Resources.lua) : si UnitPower / UnitPowerMax sont secrets, on les passe tels quels à
-- StatusBar:SetMinMaxValues / SetValue et à string.format -> SetText, sans animation ni calcul ; le halo suit le
-- bout du remplissage par simple ancrage (aucun calcul). Les repères ont besoin d'un maximum lisible : ils se
-- cachent si le maximum est secret. « Abordable » vient toujours de C_ActionBar.IsUsableAction /
-- C_Spell.IsSpellUsable, jamais d'une comparaison avec UnitPower.
local ADDON, ns = ...

local Bar = {}
ns.ResourceBar = Bar

local NAME = "barre de ressource"   -- nom affiché par le garde-fou s'il coupe la barre
local BAR_H = 22                     -- hauteur de la barre
local INSET = 3                      -- marge entre le fond arrondi et le remplissage
local MARK_ICON = 16                 -- mini-icônes au-dessus des repères
local ICON, ICON_GAP = 28, 6         -- icônes des sorts sous la barre
local MAX_ICONS = 12
local PREVIEW_SECONDS = 6
local FILL_SPEED = 14                -- vitesse de l'animation de remplissage (plus grand = plus vif)
local FADE_IN, FADE_OUT = 0.25, 0.45 -- durées des fondus (s)
local DIM = "|cff9da3b0"             -- « / 100 » en gris clair : le chiffre courant ressort
local LACK = { 1.00, 0.30, 0.30 }    -- rouge « pas assez de ressource »
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ressources « au repos » à zéro (rage, puissance runique...) ; les autres le sont au maximum (mana, énergie...)
local REST_AT_ZERO = {
    RAGE = true, RUNIC_POWER = true, LUNAR_POWER = true, INSANITY = true, FURY = true, PAIN = true, MAELSTROM = true,
}

local KEYS = {
    "hud", "hudCombatOnly", "hudWidth", "hudScale", "hudX", "hudY", "hudLocked", "hudMarkers", "hudSpells", "hudSpellCount",
}
local POSITION_KEYS = { hudX = true, hudY = true, hudScale = true }

local lib, isSecret                  -- Resources.lib (outils partagés), branché dans Init
local root, fill, top, spark, nameText, valueText, row, mover, driver, events
local markers, icons, spells = {}, {}, {}
local power = { type = nil, token = nil, max = nil, has = false, secret = false, atRest = true }
local shown, target, snap, jump = 0, nil, 0.5, true   -- valeur affichée (animation), visée, seuil, saut direct
local alpha, alphaTarget = 0, 0
local inCombat, previewing, moving, active = false, false, false, false
local previewToken = 0
local spellSig, lastText
local onEvent, onLib, animate, applyAll   -- fonctions protégées par le garde-fou (créées dans Init)

Bar.power = power
Bar.icons = icons
Bar.markers = markers
function Bar:GetSpells() return spells end

---------------------------------------------------------------------------
-- Outils de dessin
---------------------------------------------------------------------------
local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function barWidth()
    return math.floor(clamp(ns.db.hudWidth or 240, 80, 1200) + 0.5)
end

-- rectangle arrondi en 9 morceaux ; cut = part de l'image occupée par un coin (Round 0.25, Shadow 0.375)
local function nineSlice(parent, layer, sublevel, file, cut, corner, outset)
    local o = outset or 0
    local c1, c2 = cut, 1 - cut
    local parts = {}
    local function piece(left, right, top_, bottom)
        local tex = parent:CreateTexture(nil, layer, nil, sublevel)
        tex:SetTexture(file)
        tex:SetTexCoord(left, right, top_, bottom)
        parts[#parts + 1] = tex
        return tex
    end
    local tl = piece(0, c1, 0, c1)
    tl:SetSize(corner, corner)
    tl:SetPoint("TOPLEFT", parent, "TOPLEFT", -o, o)
    local tr = piece(c2, 1, 0, c1)
    tr:SetSize(corner, corner)
    tr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", o, o)
    local bl = piece(0, c1, c2, 1)
    bl:SetSize(corner, corner)
    bl:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -o, -o)
    local br = piece(c2, 1, c2, 1)
    br:SetSize(corner, corner)
    br:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", o, -o)
    local t = piece(c1, c2, 0, c1)
    t:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT", 0, 0)
    local b = piece(c1, c2, c2, 1)
    b:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    local l = piece(0, c1, c1, c2)
    l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT", 0, 0)
    local r = piece(c2, 1, c1, c2)
    r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
    local c = piece(c1, c2, c1, c2)
    c:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0)
    c:SetPoint("BOTTOMRIGHT", br, "TOPLEFT", 0, 0)
    return {
        SetColor = function(_, red, green, blue, a)
            for _, tex in ipairs(parts) do tex:SetVertexColor(red, green, blue, a or 1) end
        end,
    }
end

-- icône aux coins arrondis si le client sait masquer une texture (sinon icône carrée, rognée)
local function addMask(owner, tex)
    if not (owner.CreateMaskTexture and tex.AddMaskTexture) then return end
    pcall(function()
        local mask = owner:CreateMaskTexture()
        mask:SetTexture(ns.MEDIA .. "Round", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end)
end

local function fontString(parent, size, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, flags or "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
    fs:SetWordWrap(false)
    return fs
end

-- partagés avec HealerMana.lua (même fond arrondi, même texte)
Bar.nineSlice = nineSlice
Bar.fontString = fontString

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local savePosition

local function createUI()
    local T = ns.THEME
    root = CreateFrame("Frame", "PlatyplusResourceBar", UIParent)
    root:SetSize(240, BAR_H)
    root:SetFrameStrata("MEDIUM")
    root:SetClampedToScreen(true)
    root:SetMovable(true)
    root:EnableMouse(false)          -- la barre ne bloque jamais les clics
    if root.SetDontSavePosition then pcall(root.SetDontSavePosition, root, true) end
    root:SetAlpha(0)
    root:Hide()

    -- ombre douce, fond arrondi, liseré très léger
    nineSlice(root, "BACKGROUND", -8, ns.MEDIA .. "Shadow", 0.375, 16, 12):SetColor(0, 0, 0, 0.85)
    nineSlice(root, "BACKGROUND", 0, ns.MEDIA .. "Round", 0.25, 7, 0):SetColor(T.card[1], T.card[2], T.card[3], 0.94)
    nineSlice(root, "BORDER", 0, ns.MEDIA .. "RoundStroke", 0.25, 7, 0):SetColor(1, 1, 1, 0.10)

    -- remplissage
    fill = CreateFrame("StatusBar", nil, root)
    fill:SetPoint("TOPLEFT", root, "TOPLEFT", INSET, -INSET)
    fill:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -INSET, INSET)
    fill:SetStatusBarTexture(ns.MEDIA .. "Bar")
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    local track = fill:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(fill)
    track:SetColorTexture(0, 0, 0, 0.35)

    -- calque du dessus : repères, halo, textes
    top = CreateFrame("Frame", nil, root)
    top:SetAllPoints(fill)
    top:SetFrameLevel((fill:GetFrameLevel() or 1) + 3)

    -- halo au bout du remplissage : ancré sur la texture de la barre, il la suit sans aucun calcul
    local barTexture = fill.GetStatusBarTexture and fill:GetStatusBarTexture()
    if barTexture then
        spark = top:CreateTexture(nil, "ARTWORK", nil, -1)
        spark:SetTexture(ns.MEDIA .. "Glow")
        spark:SetBlendMode("ADD")
        spark:SetSize(18, BAR_H + 10)
        spark:SetPoint("CENTER", barTexture, "RIGHT", 0, 0)
        spark:Hide()
    end

    valueText = fontString(top, 15, "OUTLINE")
    valueText:SetPoint("CENTER", top, "CENTER", 0, 0)
    nameText = fontString(top, 11, "OUTLINE")
    nameText:SetPoint("LEFT", top, "LEFT", 5, 0)
    nameText:SetPoint("RIGHT", valueText, "LEFT", -6, 0)   -- coupé proprement s'il est trop long
    nameText:SetJustifyH("LEFT")

    -- rangée d'icônes sous la barre
    row = CreateFrame("Frame", nil, root)
    row:SetSize(1, ICON)
    row:SetPoint("TOP", root, "BOTTOM", 0, -8)

    -- cadre de déplacement
    mover = CreateFrame("Frame", nil, root)
    mover:SetPoint("TOPLEFT", root, "TOPLEFT", -12, 46)
    mover:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 12, -(ICON + 26))
    mover:SetFrameLevel((top:GetFrameLevel() or 1) + 30)
    local A = T.accent
    nineSlice(mover, "BACKGROUND", 0, ns.MEDIA .. "Round", 0.25, 8, 0):SetColor(A[1], A[2], A[3], 0.20)
    nineSlice(mover, "BORDER", 0, ns.MEDIA .. "RoundStroke", 0.25, 8, 0):SetColor(A[1], A[2], A[3], 0.95)
    local title = fontString(mover, 12, "OUTLINE")
    title:SetPoint("TOP", mover, "TOP", 0, -6)
    title:SetTextColor(A[1], A[2], A[3])
    title:SetText(ns.T("Barre de ressource — glisse-moi"))
    local hint = fontString(mover, 10, "")
    hint:SetPoint("BOTTOM", mover, "BOTTOM", 0, 6)
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
        if button == "RightButton" then Bar:ToggleMove() end
    end)
    mover:Hide()

    -- animation (remplissage, fondu) : visible seulement pendant un changement
    driver = CreateFrame("Frame")
    driver:Hide()
    events = CreateFrame("Frame")

    Bar.frames = {
        root = root, fill = fill, top = top, spark = spark, name = nameText, value = valueText,
        row = row, mover = mover, driver = driver, events = events,
    }
end

local function createIcon(i)
    local T = ns.THEME
    local f = CreateFrame("Frame", nil, row)
    f:SetSize(ICON, ICON)
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)       -- halo accent quand le sort est prêt
    f.glow:SetTexture(ns.MEDIA .. "Glow")
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.5)
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -12, 12)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 12, -12)
    f.back = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.back:SetTexture(ns.MEDIA .. "Round")
    f.back:SetVertexColor(0, 0, 0, 0.85)
    f.back:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.back:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addMask(f, f.icon)
    f.stroke = f:CreateTexture(nil, "OVERLAY")
    f.stroke:SetTexture(ns.MEDIA .. "RoundStroke")
    f.stroke:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.stroke:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.cost = fontString(f, 11, "OUTLINE")
    f.cost:SetPoint("TOP", f, "BOTTOM", 0, -3)
    icons[i] = f
    return f
end

local function createMarker(i)
    local h = BAR_H - 2 * INSET
    local m = {}
    m.shade = top:CreateTexture(nil, "ARTWORK", nil, 1)       -- ombre : trait visible même sur l'énergie jaune
    m.shade:SetColorTexture(0, 0, 0, 0.45)
    m.shade:SetSize(4, h)
    m.line = top:CreateTexture(nil, "ARTWORK", nil, 2)
    m.line:SetColorTexture(1, 1, 1, 1)
    m.line:SetSize(2, h)
    m.line:SetPoint("CENTER", m.shade, "CENTER", 0, 0)
    m.back = top:CreateTexture(nil, "ARTWORK", nil, 3)
    m.back:SetTexture(ns.MEDIA .. "Round")
    m.back:SetVertexColor(0, 0, 0, 0.85)
    m.back:SetSize(MARK_ICON + 2, MARK_ICON + 2)
    m.icon = top:CreateTexture(nil, "ARTWORK", nil, 4)
    m.icon:SetSize(MARK_ICON - 2, MARK_ICON - 2)
    m.icon:SetPoint("CENTER", m.back, "CENTER", 0, 0)
    m.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addMask(top, m.icon)
    markers[i] = m
    return m
end

---------------------------------------------------------------------------
-- État « abordable » des sorts (icônes et repères)
---------------------------------------------------------------------------
local function paintIcon(f, state)
    if f.state == state then return end
    f.state = state
    local T = ns.THEME
    local lit = state == "lit"
    f.icon:SetDesaturated(not lit)
    f.icon:SetAlpha(lit and 1 or (state == "lack" and 0.75 or 0.5))
    f.glow:SetShown(lit)
    if lit then
        f.stroke:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.95)
        f.cost:SetTextColor(T.text[1], T.text[2], T.text[3])
    elseif state == "lack" then
        f.stroke:SetVertexColor(LACK[1], LACK[2], LACK[3], 0.85)
        f.cost:SetTextColor(LACK[1], LACK[2], LACK[3])
    else      -- pas utilisable pour une autre raison (posture, cible...) : grisé, coût neutre
        f.stroke:SetVertexColor(0.30, 0.32, 0.38, 0.9)
        f.cost:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    end
end

local function paintMarker(m, affordable)
    if m.lit == affordable then return end
    m.lit = affordable
    m.line:SetAlpha(affordable and 0.95 or 0.4)
    m.icon:SetDesaturated(not affordable)
    m.icon:SetAlpha(affordable and 1 or 0.55)
end

-- relit l'état des sorts affichés (icônes, repères) et ne repeint que ce qui change
local function refreshLit()
    for _, s in ipairs(spells) do
        if s.needed then
            local usable, lacking = lib.usable(s.action, s.spellID, s.cost, power.type)
            if lacking then
                s.state = "lack"
            elseif usable == false then
                s.state = "off"
            else
                s.state = "lit"
            end
        end
    end
    for _, f in ipairs(icons) do
        if f.spell and f:IsShown() then paintIcon(f, f.spell.state) end
    end
    for _, m in ipairs(markers) do
        if m.used and m.spell then paintMarker(m, m.spell.state ~= "lack") end
    end
end

---------------------------------------------------------------------------
-- Sorts des barres d'action qui coûtent la ressource affichée
---------------------------------------------------------------------------
local function spellIcon(spellID, action)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(spellID) end
    if not icon and action and GetActionTexture then icon = GetActionTexture(action) end
    return icon or QUESTION
end

local function collectSpells()
    local list, seen = {}, {}
    for _, slot in ipairs(lib.actions()) do
        if not seen[slot.spellID] then
            seen[slot.spellID] = true
            local amount = lib.costOf(slot.spellID, power.type)
            if amount then
                list[#list + 1] = { spellID = slot.spellID, action = slot.action, cost = amount, order = slot.order }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.order < b.order
    end)
    return list
end

-- un repère par coût distinct ; mini-icônes sur deux étages quand elles se chevauchent
local function layoutMarkers()
    local n = 0
    local max = power.max
    if ns.db.hudMarkers and max and max > 0 and #spells > 0 then
        local width = barWidth() - 2 * INSET
        local seen = {}
        local last1, last2 = -1e9, -1e9
        for _, s in ipairs(spells) do
            if not seen[s.cost] and s.cost <= max then
                seen[s.cost] = true
                n = n + 1
                local m = markers[n] or createMarker(n)
                local x = math.floor(width * s.cost / max + 0.5)
                m.spell, m.used, m.lit, m.x = s, true, nil, x
                s.needed = true
                m.shade:ClearAllPoints()
                m.shade:SetPoint("CENTER", top, "LEFT", x, 0)
                m.shade:Show()
                m.line:Show()
                local lane
                if x - last1 > MARK_ICON then
                    lane, last1 = 0, x
                elseif x - last2 > MARK_ICON then
                    lane, last2 = 1, x
                end
                if lane then
                    m.lane = lane
                    m.back:ClearAllPoints()
                    m.back:SetPoint("BOTTOM", top, "TOPLEFT", x, INSET + 2 + lane * (MARK_ICON + 3))
                    m.icon:SetTexture(s.icon)
                    m.back:Show()
                    m.icon:Show()
                else
                    m.lane = nil
                    m.back:Hide()
                    m.icon:Hide()
                end
            end
        end
    end
    for i = n + 1, #markers do
        local m = markers[i]
        m.used, m.spell, m.lane = false, nil, nil
        m.shade:Hide()
        m.line:Hide()
        m.back:Hide()
        m.icon:Hide()
    end
    refreshLit()
end

local function layoutIcons()
    local count = 0
    if ns.db.hudSpells then count = math.floor(clamp(ns.db.hudSpellCount or 6, 0, MAX_ICONS)) end
    local n = math.min(count, #spells)
    for i = 1, n do
        local f = icons[i] or createIcon(i)
        local s = spells[i]
        f.spell, f.state = s, nil
        s.needed = true
        f.icon:SetTexture(s.icon)
        f.cost:SetText(lib.shortNumber(s.cost))
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (ICON + ICON_GAP), 0)
        f:Show()
    end
    for i = n + 1, #icons do
        icons[i]:Hide()
        icons[i].spell = nil
    end
    row:SetWidth(math.max(1, n * ICON + math.max(0, n - 1) * ICON_GAP))
    row:SetShown(n > 0)
end

-- relit les sorts ; ne refait la mise en page que si la liste a changé (signature)
local function rebuildSpells(force)
    local list = {}
    if (ns.db.hudMarkers or ns.db.hudSpells) and power.type ~= nil then list = collectSpells() end
    local parts = { tostring(power.type) }
    for _, s in ipairs(list) do parts[#parts + 1] = s.spellID .. ":" .. s.cost .. ":" .. tostring(s.action) end
    local sig = table.concat(parts, ",")
    if not force and sig == spellSig then
        refreshLit()
        return
    end
    spellSig = sig
    spells = list
    for _, s in ipairs(spells) do s.icon = spellIcon(s.spellID, s.action) end
    layoutIcons()
    layoutMarkers()      -- se termine par refreshLit
end

---------------------------------------------------------------------------
-- Valeur, couleurs, visibilité
---------------------------------------------------------------------------
local function paintSpark()
    if not spark then return end
    if power.secret then
        spark:Show()     -- position inconnue de nous, mais l'ancrage la suit
        return
    end
    local max = power.max
    spark:SetShown(max ~= nil and shown > 0 and shown < max)
end

local function paintPower()
    if power.type == nil then return end
    fill:SetStatusBarColor(lib.powerColor(power.type, power.token, 0.1))
    if spark then spark:SetVertexColor(lib.powerColor(power.type, power.token, 0.6)) end
    nameText:SetText(lib.powerName(power.token))
    -- blanc à contour : lisible sur le remplissage (souvent de la même couleur que la ressource) comme sur le fond
    local text = ns.THEME.text
    nameText:SetTextColor(text[1], text[2], text[3], 0.9)
end

local function updateValue()
    if power.type == nil then return end
    local cur = UnitPower("player", power.type)
    local max = UnitPowerMax("player", power.type)
    local secretCur, secretMax = isSecret(cur), isSecret(max)

    if secretMax then
        power.has = true
        fill:SetMinMaxValues(0, max)
        if power.max ~= nil then
            power.max = nil
            layoutMarkers()            -- pas de maximum lisible : pas de repères
        end
    else
        max = tonumber(max) or 0
        power.has = max > 0
        if power.max ~= max then
            power.max = max
            snap = math.max(0.5, max * 0.002)
            fill:SetMinMaxValues(0, math.max(max, 1))
            layoutMarkers()
        end
    end

    if secretCur or secretMax then
        -- valeur secrète : affichage direct, ni calcul ni animation
        power.secret, power.atRest = true, false
        target, jump, lastText = nil, true, nil
        if alpha == alphaTarget then driver:Hide() end   -- une animation en cours s'arrête net
        fill:SetValue(cur)
        valueText:SetText(string.format("%d " .. DIM .. "/ %d|r", cur, max))
    else
        cur = tonumber(cur) or 0
        local text = ""
        if power.has then text = lib.plainNumber(cur) .. " " .. DIM .. "/ " .. lib.plainNumber(max) .. "|r" end
        if text ~= lastText then
            lastText = text
            valueText:SetText(text)
        end
        if REST_AT_ZERO[power.token] then power.atRest = cur <= 0 else power.atRest = cur >= max end
        power.secret = false
        if jump or not root:IsVisible() then
            -- premier affichage, barre cachée ou retour d'une valeur secrète : pas d'animation
            jump = false
            shown, target = cur, cur
            fill:SetValue(cur)
        elseif cur ~= target then
            target = cur
            driver:Show()
        end
    end
    paintSpark()
end

local function refreshAll(force)
    local ptype, token = UnitPowerType("player")
    if ptype ~= power.type or token ~= power.token then
        power.type, power.token = ptype, token
        power.max, lastText, target, jump = nil, nil, nil, true
        spells = {}
        force = true
    end
    if power.type == nil then
        power.has = false
        return
    end
    paintPower()
    updateValue()
    rebuildSpells(force)
end

local function wantShown()
    if moving or previewing then return true end
    if not ns.db.hud or not power.has then return false end
    if not ns.db.hudCombatOnly then return true end
    return inCombat or not power.atRest
end

-- fondu doux à l'apparition comme à la disparition
local function updateVisibility()
    if wantShown() then
        if not root:IsShown() then
            alpha = 0
            root:SetAlpha(0)
            root:Show()
        end
        alphaTarget = 1
    elseif root:IsShown() then
        alphaTarget = 0
    else
        return
    end
    if alpha ~= alphaTarget then driver:Show() end
end

local function animateRaw(self, elapsed)
    local busy = false
    if target ~= nil and shown ~= target then
        shown = shown + (target - shown) * math.min(1, elapsed * FILL_SPEED)
        if math.abs(target - shown) <= snap then shown = target end
        fill:SetValue(shown)
        paintSpark()
        busy = shown ~= target
    end
    if alpha ~= alphaTarget then
        if alphaTarget > alpha then
            alpha = math.min(alphaTarget, alpha + elapsed / FADE_IN)
        else
            alpha = math.max(alphaTarget, alpha - elapsed / FADE_OUT)
        end
        root:SetAlpha(alpha)
        if alpha <= 0 then root:Hide() end
        busy = busy or alpha ~= alphaTarget
    end
    if not busy then self:Hide() end   -- plus rien à animer : la boucle s'arrête
end

---------------------------------------------------------------------------
-- Événements, position, réglages
---------------------------------------------------------------------------
local function handleEvent(event, unit, token)
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        if unit ~= "player" or (token and power.token and token ~= power.token) then return end
        updateValue()
    elseif event == "UNIT_MAXPOWER" then
        if unit ~= "player" then return end
        updateValue()
    elseif event == "UNIT_DISPLAYPOWER" then
        if unit ~= "player" then return end
        refreshAll(false)
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        inCombat = InCombatLockdown() and true or false
        refreshAll(true)
    end
    updateVisibility()
end

local function setActive(on)
    if on == active then return end
    active = on
    events:UnregisterAllEvents()
    if not on then return end
    if not lib.registerUnitEvent(events, "UNIT_POWER_FREQUENT", "player") then
        lib.registerUnitEvent(events, "UNIT_POWER_UPDATE", "player")
    end
    lib.registerUnitEvent(events, "UNIT_MAXPOWER", "player")
    lib.registerUnitEvent(events, "UNIT_DISPLAYPOWER", "player")
    lib.registerEvent(events, "PLAYER_REGEN_DISABLED")
    lib.registerEvent(events, "PLAYER_REGEN_ENABLED")
    lib.registerEvent(events, "PLAYER_ENTERING_WORLD")
    inCombat = InCombatLockdown() and true or false
end

local function applyPosition()
    root:SetScale(clamp(ns.db.hudScale or 1, 0.3, 3))
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", tonumber(ns.db.hudX) or 0, tonumber(ns.db.hudY) or -170)
end

-- décalage du centre de la barre par rapport au centre de l'écran, dans l'échelle de la barre
function savePosition()
    local cx, cy = root:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s, u = root:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (cx and cy and ux and uy and s and u and s > 0) then return end
    ns:Set("hudX", math.floor(cx - ux * u / s + 0.5))
    ns:Set("hudY", math.floor(cy - uy * u / s + 0.5))
end

local function applyRaw()
    root:SetSize(barWidth(), BAR_H)
    applyPosition()
    moving = ns.db.hudLocked == false
    mover:SetShown(moving)
    local want = (ns.db.hud or previewing or moving) and true or false
    setActive(want)
    lib.setWanted("bar", want and (ns.db.hudMarkers or ns.db.hudSpells) and true or false)
    if want then refreshAll(true) end
    updateVisibility()
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- réapplique tous les réglages
function Bar:Apply()
    if not (root and ns.db) then return end
    applyAll()
end

-- déverrouille / verrouille : déverrouillée, la barre reste visible avec un cadre « glisse-moi »
function Bar:ToggleMove()
    if not root then return end
    local unlock = ns.db.hudLocked ~= false
    ns:Set("hudLocked", not unlock)
    if unlock then
        ns:Print("barre de ressource : glisse-la où tu veux, puis clic droit dessus (ou Déplacer) pour la verrouiller")
    else
        ns:Print("barre de ressource : position enregistrée")
    end
end

function Bar:ResetPosition()
    ns:Reset("hudX")
    ns:Reset("hudY")
end

-- montre la barre quelques secondes, même hors combat ou si elle est désactivée
function Bar:Preview(seconds)
    if not root then return end
    previewToken = previewToken + 1
    local token = previewToken
    previewing = true
    self:Apply()
    C_Timer.After(tonumber(seconds) or PREVIEW_SECONDS, function()
        if token ~= previewToken then return end
        previewing = false
        Bar:Apply()
    end)
end

function Bar:Init()
    lib = ns.Resources and ns.Resources.lib
    if not lib then
        ns:Debug("ResourceBar : Resources.lua absent, barre de ressource désactivée")
        return
    end
    isSecret = lib.isSecret
    createUI()

    onEvent = lib.guard(NAME, handleEvent)
    animate = lib.guard(NAME, animateRaw)
    applyAll = lib.guard(NAME, applyRaw)
    onLib = lib.guard(NAME, function(reason)
        if not active then return end
        if reason == "actions" then rebuildSpells(false) else refreshLit() end
    end)

    events:SetScript("OnEvent", function(_, event, ...) onEvent(event, ...) end)
    driver:SetScript("OnUpdate", function(self, elapsed)
        if not animate(self, elapsed) then self:Hide() end
    end)
    lib.subscribe(function(reason) onLib(reason) end)

    for _, key in ipairs(KEYS) do
        ns:OnChange(key, function()
            lib.resetFailures(NAME)
            if POSITION_KEYS[key] then
                applyPosition()
            else
                Bar:Apply()
            end
        end)
    end
    self:Apply()
end

---------------------------------------------------------------------------
-- Barre de coups blancs (ns.SwingBar) : minuteur d'attaque automatique
-- Vérifié dans le code de Forever : le journal de combat est réservé (COMBAT_LOG_EVENT_UNFILTERED « HasRestrictions »,
-- lecture déplacée dans l'environnement sécurisé), MAIS le jeu fournit un minuteur natif (Blizzard_SwingTimer,
-- SwingTimerDocumentation.lua) :
-- * PLAYER_SWING (durée du coup, type : 0 main droite, 1 main gauche, 2 distance) à chaque coup blanc ;
-- * C_SwingTimer.IsTargetWithinSwingRange(type) -> vrai / faux / nil (nil ne veut PAS dire hors de portée) ;
-- * UnitAttackSpeed("player") -> vitesse main droite, main gauche (nil ou 0 sans arme), distance.
-- On ne touche pas à C_SwingTimer.EnableRangeCheck (la barre de Blizzard s'en sert) : on interroge la portée.
-- En plus : C_Spell.IsCurrentSpell(sort) = « en attente d'être lancé » -> barre dorée quand Frappe héroïque ou
-- Enchaînement attend le prochain coup.
-- Optimisation : OnUpdate seulement pendant un coup en cours ; contrôles de portée et d'attente 10 fois par seconde.
---------------------------------------------------------------------------
do
    local Swing = {}
    ns.SwingBar = Swing

    local MAIN, OFF = 0, 1
    local BAR_H, OFF_H, GAP = 12, 5, 4
    local CHECK_EVERY = 0.1
    local FLASH_TIME = 0.25
    -- sorts « au prochain coup » (Frappe héroïque, Enchaînement, Attaque du raptor, Mutiler) : noms lus dans le jeu
    local NEXT_SWING_SPELLS = { 78, 845, 2973, 6807 }

    local root, bars, label, timeText
    local state = { [MAIN] = {}, [OFF] = {} }   -- [type] = { start, duration }
    local queuedNames
    local inCombat, previewUntil = false, 0
    local previewQueued = nil                      -- aperçu : sort « en attente » simulé
    local checkTimer, queued, outOfRange = 0, false, false
    local events = CreateFrame("Frame")

    local function api(name) return rawget(_G, name) end

    local function decimal1(v)
        return (string.format("%.1f", v):gsub("%.", ","))
    end

    local function speeds()
        local fn = api("UnitAttackSpeed")
        if type(fn) ~= "function" then return nil end
        local ok, main, off = pcall(fn, "player")
        if not ok then return nil end
        return tonumber(main), tonumber(off)
    end

    local function hasOffHand()
        local _, off = speeds()
        return off ~= nil and off > 0
    end

    local function nextSwingNames()
        if queuedNames then return queuedNames end
        local list = {}
        local spell = api("C_Spell")
        for _, id in ipairs(NEXT_SWING_SPELLS) do
            if type(spell) == "table" and spell.GetSpellName then
                local ok, name = pcall(spell.GetSpellName, id)
                if ok and type(name) == "string" and name ~= "" then list[#list + 1] = name end
            end
        end
        queuedNames = list
        return list
    end

    -- Frappe héroïque (ou équivalent) en attente du prochain coup ?
    local function nextSwingQueued()
        local spell = api("C_Spell")
        if type(spell) ~= "table" or type(spell.IsCurrentSpell) ~= "function" then return false end
        for _, name in ipairs(nextSwingNames()) do
            local ok, current = pcall(spell.IsCurrentSpell, name)
            if ok and current == true then return true, name end
        end
        return false
    end

    local function targetOutOfRange()
        local swing = api("C_SwingTimer")
        if type(swing) ~= "table" or type(swing.IsTargetWithinSwingRange) ~= "function" then return false end
        local ok, inRange = pcall(swing.IsTargetWithinSwingRange, MAIN)
        return ok and inRange == false
    end

    ---------------------------------------------------------------------------
    -- Dessin
    local function newBar(parent, height)
        local T = ns.THEME
        local b = CreateFrame("StatusBar", nil, parent)
        b:SetHeight(height)
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
        b:SetStatusBarTexture(ns.MEDIA .. "Bar")
        b:SetStatusBarColor(0.92, 0.94, 1.0, 1)        -- « coup blanc »
        local track = b:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
        track:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
        track:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.8)
        local edge = b:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT", track, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(1, 1, 1, 0.08)
        local spark = b:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(ns.MEDIA .. "Glow")
        spark:SetBlendMode("ADD")
        spark:SetSize(height * 2.2, height * 2.6)
        spark:SetPoint("CENTER", b:GetStatusBarTexture(), "RIGHT", 0, 0)
        spark:SetVertexColor(1, 1, 1, 0.9)
        local flash = b:CreateTexture(nil, "OVERLAY")
        flash:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
        flash:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, 0)
        flash:SetColorTexture(1, 1, 1, 1)
        flash:SetAlpha(0)
        b.track, b.edge, b.spark, b.flash = track, edge, spark, flash
        return b
    end

    local function build()
        if root then return root end
        local T = ns.THEME
        root = CreateFrame("Frame", "PlatyplusSwingBar", UIParent)
        root:SetFrameStrata("MEDIUM")
        root:SetClampedToScreen(true)
        root:SetMovable(true)
        root:EnableMouse(false)
        root:RegisterForDrag("LeftButton")
        root:SetScript("OnDragStart", function(self) self:StartMoving() end)
        root:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local cx, cy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if cx and ux then
                ns:Set("swingX", math.floor(cx - ux + 0.5))
                ns:Set("swingY", math.floor(cy - uy + 0.5))
            end
        end)
        bars = { [MAIN] = newBar(root, BAR_H), [OFF] = newBar(root, OFF_H) }
        bars[MAIN]:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -14)
        bars[MAIN]:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -14)
        bars[OFF]:SetPoint("TOPLEFT", bars[MAIN], "BOTTOMLEFT", 0, -GAP)
        bars[OFF]:SetPoint("TOPRIGHT", bars[MAIN], "BOTTOMRIGHT", 0, -GAP)
        bars[OFF]:SetStatusBarColor(0.75, 0.78, 0.86, 1)
        label = root:CreateFontString(nil, "OVERLAY")
        label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "")
        label:SetShadowOffset(1, -1)
        label:SetShadowColor(0, 0, 0, 1)
        label:SetPoint("BOTTOMLEFT", bars[MAIN], "TOPLEFT", 1, 3)
        label:SetJustifyH("LEFT")
        label:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
        timeText = root:CreateFontString(nil, "OVERLAY")
        timeText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
        timeText:SetShadowOffset(1, -1)
        timeText:SetShadowColor(0, 0, 0, 1)
        timeText:SetPoint("BOTTOMRIGHT", bars[MAIN], "TOPRIGHT", -1, 3)
        timeText:SetJustifyH("RIGHT")
        timeText:SetTextColor(T.text[1], T.text[2], T.text[3])
        root:Hide()
        return root
    end

    local function applyLayout()
        if not root then return end
        local w = tonumber(ns.db.swingWidth) or 240
        root:SetSize(w, 14 + BAR_H + GAP + OFF_H)
        root:ClearAllPoints()
        root:SetPoint("CENTER", UIParent, "CENTER", tonumber(ns.db.swingX) or 0, tonumber(ns.db.swingY) or -275)
        local unlocked = not ns.db.swingLocked
        root:EnableMouse(unlocked)
    end

    local function paintQueued()
        local T = ns.THEME
        local b = bars[MAIN]
        if queued then
            b:SetStatusBarColor(T.gold[1], T.gold[2], T.gold[3], 1)
            b.spark:SetVertexColor(T.gold[1], T.gold[2], T.gold[3], 1)
            label:SetText(queued)
            label:SetTextColor(T.gold[1], T.gold[2], T.gold[3])
        else
            b:SetStatusBarColor(0.92, 0.94, 1.0, 1)
            b.spark:SetVertexColor(1, 1, 1, 0.9)
            label:SetText(ns.T("Coup blanc"))
            local dim = T.dim
            label:SetTextColor(dim[1], dim[2], dim[3])
        end
    end

    local onUpdate

    local function running()
        return state[MAIN].start ~= nil or state[OFF].start ~= nil
    end

    -- visible seulement en combat (ou pendant un aperçu, ou déverrouillée pour la placer)
    local function wantShown()
        if not ns.db.swingBar then return false end
        if not ns.db.swingLocked then return true end      -- déverrouillée : visible pour la placer
        return inCombat or GetTime() < previewUntil
    end

    -- montre ou cache tout de suite (retour du joueur : « dès que le combat se termine, pouf, il disparaît »)
    local function refreshVisibility()
        if not root then return end
        if wantShown() then
            root:SetAlpha(outOfRange and 0.45 or 1)
            root:Show()
            bars[OFF]:SetShown(ns.db.swingOffHand and (hasOffHand() or state[OFF].start ~= nil) or false)
            if running() then
                root:SetScript("OnUpdate", onUpdate)
            else
                bars[MAIN]:SetValue(0); bars[OFF]:SetValue(0)
                timeText:SetText("")
            end
        else
            root:Hide()
            root:SetScript("OnUpdate", nil)
        end
    end

    onUpdate = function(self, elapsed)
        local now = GetTime()
        local busy = false
        for kind = MAIN, OFF do
            local s, b = state[kind], bars[kind]
            if s.start then
                local p = (now - s.start) / s.duration
                if p >= 1 then
                    s.start = nil
                    b:SetValue(1)
                    if kind == MAIN then timeText:SetText("") end
                else
                    b:SetValue(p)
                    if kind == MAIN then timeText:SetText(decimal1(s.duration - (now - s.start))) end
                    busy = true
                end
            end
            if b.flashAt then
                local k = (now - b.flashAt) / FLASH_TIME
                if k >= 1 then
                    b.flashAt = nil
                    b.flash:SetAlpha(0)
                else
                    b.flash:SetAlpha(0.55 * (1 - k))
                    busy = true
                end
            end
        end
        checkTimer = checkTimer - elapsed
        if checkTimer <= 0 then
            checkTimer = CHECK_EVERY
            local isQueued, name = nextSwingQueued()
            if not isQueued and previewQueued and GetTime() < previewUntil then isQueued, name = true, previewQueued end
            local newQueued = isQueued and name or false
            if newQueued ~= queued then
                queued = newQueued
                paintQueued()
            end
            local oor = targetOutOfRange()
            if oor ~= outOfRange then
                outOfRange = oor
                root:SetAlpha(oor and 0.45 or 1)
            end
        end
        if not wantShown() then
            refreshVisibility()                            -- fin du combat ou de l'aperçu : cachée tout de suite
        elseif not busy and not running() then
            self:SetScript("OnUpdate", nil)                -- plus rien ne bouge : on s'arrête
        end
    end

    -- un coup blanc vient de partir (ou un aperçu)
    local function startSwing(duration, kind)
        duration = tonumber(duration)
        if not duration or duration <= 0 or (kind ~= MAIN and kind ~= OFF) then return end
        build()
        if kind == OFF and not ns.db.swingOffHand then return end
        state[kind].start, state[kind].duration = GetTime(), duration
        bars[kind].flashAt = GetTime()
        bars[kind].flash:SetAlpha(0.55)                   -- éclair tout de suite, il s'éteint ensuite
        bars[kind]:SetValue(0)
        checkTimer = 0
        -- hors combat : on note le coup (le 1er coup peut précéder l'entrée en combat) sans montrer la barre
        refreshVisibility()
    end

    events:SetScript("OnEvent", function(_, event, a, b)
        if event == "PLAYER_SWING" then
            startSwing(a, b)
        elseif event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            build()
            refreshVisibility()
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            refreshVisibility()
        elseif event == "UNIT_ATTACK_SPEED" or event == "PLAYER_EQUIPMENT_CHANGED" then
            refreshVisibility()
        end
    end)

    function Swing:Apply()
        local on = ns.db.swingBar and true or false
        for _, event in ipairs({ "PLAYER_SWING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED" }) do
            if on then pcall(events.RegisterEvent, events, event) else pcall(events.UnregisterEvent, events, event) end
        end
        if on and events.RegisterUnitEvent then
            pcall(events.RegisterUnitEvent, events, "UNIT_ATTACK_SPEED", "player")
        elseif not on then
            pcall(events.UnregisterEvent, events, "UNIT_ATTACK_SPEED")
        end
        if not on then
            state[MAIN].start, state[OFF].start = nil, nil
            if root then
                root:SetScript("OnUpdate", nil)
                root:Hide()
            end
            return
        end
        if not ns.db.swingOffHand then state[OFF].start = nil end
        build()
        applyLayout()
        paintQueued()
        refreshVisibility()
    end

    -- aperçu : quelques coups simulés (vitesse de l'arme), la 2e fois avec Frappe héroïque en attente
    function Swing:Preview(seconds)
        if not ns.db.swingBar then return end
        build()
        applyLayout()
        previewUntil = GetTime() + (tonumber(seconds) or 6)
        local main, off = speeds()
        main = (main and main > 0) and main or 2.6
        startSwing(main, MAIN)
        if off and off > 0 then startSwing(off, OFF) end
        C_Timer.After(main, function()
            if GetTime() < previewUntil then
                previewQueued = nextSwingNames()[1] or "Frappe héroïque"
                queued = previewQueued
                paintQueued()
                startSwing(main, MAIN)
            end
        end)
        C_Timer.After(previewUntil - GetTime() + 0.05, function()
            previewQueued = nil
            queued = false
            paintQueued()
            refreshVisibility()
        end)
    end

    function Swing:ResetPosition()
        ns:Reset("swingX")
        ns:Reset("swingY")
    end

    function Swing:Frames()
        return root, bars
    end

    function Swing:Init()
        inCombat = (InCombatLockdown and InCombatLockdown()) or false
        for _, key in ipairs({ "swingBar", "swingOffHand" }) do
            ns:OnChange(key, function() Swing:Apply() end)
        end
        for _, key in ipairs({ "swingWidth", "swingX", "swingY", "swingLocked" }) do
            ns:OnChange(key, function()
                applyLayout()
                refreshVisibility()
            end)
        end
        Swing:Apply()
    end
end
