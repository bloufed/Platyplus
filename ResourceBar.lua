-- Platyplus : aides de dessin partagées + barre de coups blancs
--  * ns.ResourceBar : outils de dessin (rectangle arrondi en 9 morceaux, texte) utilisés par Buffs.lua et HealerMana.lua ;
--  * ns.SwingBar : barre de coups blancs (minuteur d'attaque automatique), plus bas dans ce fichier.
local ADDON, ns = ...

local Bar = {}
ns.ResourceBar = Bar

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
