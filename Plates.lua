-- Platyplus : plates des mobs (le principe de Threat Plates, personnalisable)
-- Sur les plates de nom du jeu (barres de vie au-dessus des mobs), Platyplus ajoute :
--  * la couleur de la menace. Tank : vert = le mob te tape (aggro sûre), orange = ça se joue (quelqu'un te rattrape,
--    ou tu vas la prendre), rouge = il tape quelqu'un d'autre, bleu = un autre tank du groupe le tient.
--    DPS/soigneur : l'inverse (vert = il ne te regarde pas, rouge = il te tape).
--    Hors combat (platesIdle) : couleurs du jeu, ou nos couleurs par réaction (hostile / neutre / amical / tapé).
--  * une alerte quand un mob t'échappe (tank) : la plate clignote (+ son en option) ;
--  * l'icône de quête : « ! » pour un mob à tuer, sac pour un objet à récupérer, avec « 3/8 » ;
--  * « Rare » / « Élite » / « Boss » au-dessus du bout droit de la barre ;
--  * le look : cadre du jeu remplacé (fond + bord réglables), arrondi 0-4, texture, opacité, cible mise en avant,
--    plates non ciblées atténuées, toutes les couleurs. Styles prêts à l'emploi : Plates.PRESETS / ApplyPreset.
-- Tank ou pas ? Réglage platesRole : "auto" = posture défensive, forme d'ours (ou aura de tank du jeu), ou rôle « tank »
-- donné par le groupe ; "tank" / "dps" pour forcer.
--
-- Méthode : on n'écrit dans les cadres du jeu que l'alpha et les masques de deux textures (le cadre bgTexture et le
-- remplissage de la barre) — Blizzard_NamePlateUnitFrame.lua ne touche jamais à ces deux propriétés, nos réglages y
-- restent. Tout le reste est à nous : textures créées SUR la barre de vie (teinte juste au-dessus du remplissage, fond et
-- bord en BACKGROUND) et un cadre enfant pour les icônes. Pas de couleur écrite sur leur barre, pas de Hide, pas de hook.
-- Un addon qui cache les plates du jeu (Threat Plates, Plater...) cache donc aussi les nôtres.
-- Vérifié dans le code de Forever (doc générée UnitDocumentation / NamePlateDocumentation / TooltipInfo*,
-- Blizzard_NamePlateUnitFrame.lua L56 : UnitFrame.healthBar = HealthBarsContainer.healthBar ; Blizzard_NamePlates.xml :
-- barre, conteneur et UnitFrame tous useParentLevel) :
-- UnitDetailedThreatSituation("player", unit) -> isTanking, status (0..3, nil = pas sur sa liste de menace), secret
-- quand le jeu restreint la menace ; UnitThreatSituation(membre, mob) ; UnitIsTapDenied, UnitClassification,
-- UnitCanAttack, UnitAffectingCombat, UnitReaction : jamais secrets ; UnitHasEffectivelyTankAura ;
-- NAME_PLATE_UNIT_ADDED/REMOVED, UNIT_THREAT_LIST_UPDATE, UNIT_THREAT_SITUATION_UPDATE ; C_TooltipInfo.GetUnit -> lignes
-- .type (QuestTitle 17, QuestObjective 8 avec .completed, QuestPlayer 18 = objectifs d'un autre membre du groupe) ;
-- Texture:SetVertexColorFromBoolean(bool secret, couleurSiVrai, couleurSiFaux) : colore sans lire la valeur.
-- Menace secrète : on ne peut ni comparer ni tester ; la couleur est alors confiée au jeu par SetVertexColorFromBoolean
-- sur « je tanke ce mob » (vert/rouge, pas d'orange ni de bleu ni d'alerte), seulement pour un mob en combat.
-- NON VÉRIFIÉ en jeu : le rendu (masques arrondis, couches), les lignes de quête des infobulles.
--
-- Optimisation : aucune boucle permanente. Tout part des événements ; les rafraîchissements groupés passent par un seul
-- minuteur court. Le clignotement d'alerte a son OnUpdate le temps du clignotement seulement.
local ADDON, ns = ...

local Plates = {}
ns.Plates = Plates

local NAME = "plates des mobs"           -- nom affiché par le garde-fou s'il coupe le module

-- couleurs : [genre] = réglage + valeur par défaut (les mêmes que DEFAULTS dans Core.lua)
local COLOR_KEYS = {
    safe = "platesColSafe", warn = "platesColWarn", loose = "platesColLoose", other = "platesColOther",
    hostile = "platesColHostile", neutral = "platesColNeutral", friendly = "platesColFriendly", tapped = "platesColTapped",
    back = "platesColBack", border = "platesColBorder", target = "platesColTarget", glow = "platesColGlow",
    quest = "platesColQuest",
    castInterrupt = "platesColCastInterrupt", castShield = "platesColCastShield", castKick = "platesColCastKick",
}
local COLOR_DEFAULTS = {
    safe = { 0.20, 0.82, 0.30 }, warn = { 1.00, 0.62, 0.10 }, loose = { 0.95, 0.18, 0.15 }, other = { 0.25, 0.62, 0.98 },
    hostile = { 0.78, 0.20, 0.16 }, neutral = { 0.95, 0.80, 0.25 }, friendly = { 0.30, 0.78, 0.35 },
    tapped = { 0.55, 0.55, 0.58 }, back = { 0.04, 0.04, 0.05 }, border = { 0, 0, 0 }, target = { 1, 1, 1 },
    glow = { 1, 0.10, 0.05 }, quest = { 1, 0.85, 0.20 },
    castInterrupt = { 1, 0.72, 0.10 }, castShield = { 0.55, 0.55, 0.62 }, castKick = { 0.25, 0.85, 1 },
}
Plates.COLOR_KEYS, Plates.COLOR_DEFAULTS = COLOR_KEYS, COLOR_DEFAULTS

local TEXTURES = {                       -- réglage platesTexture
    smooth = "Interface\\AddOns\\Platyplus\\Media\\Bar",          -- dégradé Platyplus
    flat = "Interface\\Buttons\\WHITE8X8",                         -- couleur unie
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",          -- barre classique du jeu
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",               -- barre des cadres de raid
}
-- texture blanche colorée par SetVertexColor (comme la teinte, qui s'affiche bien en jeu) ; une SetColorTexture blanche
-- n'a pas pris la couleur posée ensuite (fond resté blanc en jeu, 2026-11-14)
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MASK = "Interface\\AddOns\\Platyplus\\Media\\PlateMask"     -- + 1..4 : rayons 3, 5, 7, 11 (make_media.py platemask)
local TANK_FORMS = {                     -- sorts de posture/forme qui font de toi un tank (GetShapeshiftFormInfo)
    [71] = true,                         -- Posture défensive
    [5487] = true, [9634] = true,        -- Forme d'ours, Forme d'ours redoutable
}
local QUEST_KILL = "Interface\\GossipFrame\\AvailableQuestIcon"   -- « ! » jaune
local QUEST_ITEM = "Interface\\GossipFrame\\VendorGossipIcon"      -- sac
local SOUND_ID = 8959                    -- SOUNDKIT.RAID_WARNING
local REFRESH_DELAY = 0.1                -- regroupement des rafraîchissements de toutes les plates (s)
local QUEST_DELAY = 1                    -- regroupement des relectures de quêtes (s)
local CONFLICTS = { "TidyPlates_ThreatPlates", "Plater", "Kui_Nameplates", "NeatPlates" }

local LINE_QUEST_OBJECTIVE, LINE_QUEST_TITLE, LINE_QUEST_PLAYER = 8, 17, 18

local lib
local active = {}                        -- [jeton "nameplateN"] = nos éléments de cette plate
local byBar = setmetatable({}, { __mode = "k" })   -- [barre de vie] = nos éléments (réutilisés ; aussi l'aperçu)
local events
local isTank, tankWhy = false, "-"
local groupTanks = {}                    -- jetons des autres tanks du groupe
local questKinds = {}                    -- [texte d'objectif] = "item" | "monster" | ...
local myName
local refreshPending, questPending = false, false
local lastSound = 0
local colorObjects                       -- ColorMixin des couleurs (pour SetVertexColorFromBoolean)
local targetBar                          -- barre de vie de la plate de ta cible (ou nil)
local onEvent, refreshAll, scanQuests    -- protégées par le garde-fou (créées dans Init)
local guarded                            -- guarded(fn, ...) : appel protégé par le même garde-fou

local function api(name) return rawget(_G, name) end

-- vrai si la valeur est secrète (ou si le test lui-même la refuse) ; API lue avec rawget : absente = jamais secret
local function isSecret(value)
    local test = rawget(_G, "issecretvalue")
    if type(test) ~= "function" then return false end
    local ok, result = pcall(test, value)
    return (not ok) or result == true
end
local function db(key) return ns.db and ns.db[key] end

local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- valeur lisible et vraie (un secret compte pour « non »)
local function yes(value)
    if isSecret(value) then return false end
    return value and true or false
end

local function clamp(v, lo, hi, default)
    v = tonumber(v) or default
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- couleur réglée -> r, g, b (réglage absent ou abîmé : couleur par défaut)
local function col(kind)
    local c = db(COLOR_KEYS[kind])
    if type(c) ~= "table" or type(c[1]) ~= "number" or type(c[2]) ~= "number" or type(c[3]) ~= "number" then
        c = COLOR_DEFAULTS[kind]
    end
    return c[1], c[2], c[3]
end

local function rebuildColorObjects()
    local create = api("CreateColor")
    if type(create) ~= "function" then colorObjects = nil return end
    colorObjects = {}
    for kind in pairs(COLOR_DEFAULTS) do colorObjects[kind] = create(col(kind)) end
end

---------------------------------------------------------------------------
-- Rôle : tank ou pas ?
---------------------------------------------------------------------------
local function detectTank()
    local role = db("platesRole") or "auto"
    if role == "tank" then return true, "réglage « tank »" end
    if role == "dps" then return false, "réglage « DPS / soins »" end
    local ok, aura = call(api("UnitHasEffectivelyTankAura"), "player")
    if ok and yes(aura) then return true, "aura de tank" end
    local count = api("GetNumShapeshiftForms")
    local info = api("GetShapeshiftFormInfo")
    local okN, n = call(count)
    if okN and type(n) == "number" and type(info) == "function" then
        for i = 1, n do
            local okI, _, isActive, _, spellID = pcall(info, i)
            if okI and yes(isActive) and not isSecret(spellID) and TANK_FORMS[spellID] then
                return true, "posture/forme de tank"
            end
        end
    end
    local okR, assigned = call(api("UnitGroupRolesAssigned"), "player")
    if okR and not isSecret(assigned) and assigned == "TANK" then return true, "rôle tank du groupe" end
    return false, "pas en posture de tank"
end

local function updateGroupTanks()
    wipe(groupTanks)
    for _, unit in ipairs(lib.groupUnits()) do
        if not lib.isMe(unit) then
            local okR, assigned = call(api("UnitGroupRolesAssigned"), unit)
            local okA, aura = call(api("UnitHasEffectivelyTankAura"), unit)
            if (okR and not isSecret(assigned) and assigned == "TANK") or (okA and yes(aura)) then
                groupTanks[#groupTanks + 1] = unit
            end
        end
    end
end

---------------------------------------------------------------------------
-- Nos éléments sur une plate
---------------------------------------------------------------------------
local function healthBarOf(unit)
    local C = api("C_NamePlate")
    if not (C and C.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C.GetNamePlateForUnit, unit)
    if not ok or not plate then return nil end
    local uf = plate.UnitFrame
    if not uf then return nil end
    return uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar), uf
end

local function stopFlash(o)
    o.flashing = false
    o.glow:Hide()
    o.root:SetScript("OnUpdate", nil)
end

local function flashOnUpdate(root, elapsed)
    local o = root.pp
    o.flashLeft = o.flashLeft - elapsed
    if o.flashLeft <= 0 then stopFlash(o) return end
    -- trois éclats : l'alpha suit une vague
    local p = (o.flashTime - o.flashLeft) / o.flashTime * 3
    o.glow:SetAlpha(0.25 + 0.75 * math.abs(math.sin(p * math.pi)))
end

local function newMask(owner, target)
    if not owner.CreateMaskTexture then return nil end
    local m = owner:CreateMaskTexture()
    m:SetAllPoints(target)
    return m
end

local function build(bar, uf, preview)
    local o = byBar[bar]
    if o then return o end
    o = { preview = preview }
    local root = CreateFrame("Frame", nil, bar)
    root:SetAllPoints(bar)
    root:SetFrameLevel((bar:GetFrameLevel() or 0) + 1)
    root.pp = o
    o.root, o.bar, o.uf = root, bar, uf

    -- teinte : région de la barre elle-même, juste au-dessus du remplissage (sous-niveau +1) et ancrée à sa texture
    -- (suit la vie sans la lire). Dans la barre et pas dans un cadre à nous plus haut : le nom, le texte de vie,
    -- la bordure de cible (OVERLAY) restent par-dessus.
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local layer, sub = "ARTWORK", 0
    local okL, l, sl = pcall(function() return fill:GetDrawLayer() end)
    if okL and type(l) == "string" and not isSecret(l) and not isSecret(sl) then layer, sub = l, tonumber(sl) or 0 end
    local tint = bar:CreateTexture(nil, layer, nil, math.min(7, sub + 1))
    if fill then tint:SetAllPoints(fill) else tint:SetAllPoints(bar) end
    tint:Hide()
    o.tint = tint   -- (affichée/cachée par setTint)

    -- cadre à nous (remplace bgTexture, rendu transparent) : bord (plus grand) puis fond (taille de la barre), en
    -- BACKGROUND de la barre, sous le remplissage
    local border = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetTexture(WHITE)
    border:Hide()
    o.border = border
    local targetBorder = bar:CreateTexture(nil, "BACKGROUND", nil, -8)     -- bord de la cible : 1 px de plus
    targetBorder:SetTexture(WHITE)
    targetBorder:Hide()
    o.targetBorder = targetBorder
    local back = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
    back:SetAllPoints(bar)
    back:SetTexture(WHITE)
    back:Hide()
    o.back = back

    -- liseré du clignotement « il t'échappe » (cadre sous la barre : seul le bord dépasse)
    local glowFrame = CreateFrame("Frame", nil, bar)
    glowFrame:SetFrameLevel(math.max(0, (bar:GetFrameLevel() or 1) - 1))
    o.glowFrame = glowFrame               -- ancré dans applyLook : 3 px au-delà du bord
    local glow = glowFrame:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(glowFrame)
    glow:SetTexture(WHITE)
    glow:Hide()
    o.glow = glow

    -- coins arrondis : masques étirés (barre : remplissage du jeu + teinte ; fond ; bord ; liseré)
    o.maskBar, o.maskBack, o.maskBorder = newMask(bar, bar), newMask(bar, back), newMask(bar, border)
    o.maskTarget = newMask(bar, targetBorder)
    o.maskGlow = newMask(glowFrame, glowFrame)

    -- quête : icône + progression (côté réglable)
    o.quest = root:CreateTexture(nil, "OVERLAY")
    o.quest:Hide()
    o.questText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.questText:Hide()

    -- « Rare » / « Élite » / « Boss » au-dessus du bout droit de la barre (à droite : icônes de contrôle du jeu)
    local tag = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 2)
    tag:Hide()
    o.tag = tag

    byBar[bar] = o
    return o
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
-- l'aperçu des options montre toujours le style, même plates coupées
local function on(o) return o.preview or db("plates") end

local function alphaOf(o)
    if not on(o) then return 1 end
    local a = clamp(db("platesOpacity"), 20, 100, 100) / 100
    local hasTarget = (o.preview and o.previewHasTarget) or (not o.preview and targetBar ~= nil)
    if hasTarget and not o.isTarget then a = a * clamp(db("platesNonTarget"), 10, 100, 100) / 100 end
    return a
end

local function fillOf(o) return o.bar.GetStatusBarTexture and o.bar:GetStatusBarTexture() end

local function setMask(tex, m, add)
    if not (tex and m) then return end
    local key = add and "AddMaskTexture" or "RemoveMaskTexture"
    if tex[key] then pcall(tex[key], tex, m) end
end

-- teinte affichée : le remplissage du jeu est caché dessous (sinon les deux, transparents, se mélangent)
local function setTint(o, show)
    o.tint:SetShown(show)
    local fill = fillOf(o)
    if fill and fill.SetAlpha then pcall(fill.SetAlpha, fill, show and 0 or alphaOf(o)) end
end

local function colorFromBoolean(tex, value, ifTrue, ifFalse)
    if not (tex.SetVertexColorFromBoolean and colorObjects) then return false end
    return (pcall(tex.SetVertexColorFromBoolean, tex, value, colorObjects[ifTrue], colorObjects[ifFalse]))
end

-- pose la couleur de o.kind sur la teinte (nil = couleurs du jeu ; "bool" = menace secrète, couleur choisie par le jeu)
local function paint(o)
    local kind = o.kind
    if kind == nil then setTint(o, false) return end
    if kind == "bool" then
        if colorFromBoolean(o.tint, o.secretTanking, isTank and "safe" or "loose", isTank and "loose" or "safe") then
            setTint(o, true)
        else
            setTint(o, false)
        end
        return
    end
    local r, g, b = col(kind)
    o.tint:SetVertexColor(r, g, b, 1)
    setTint(o, true)
end

-- Ancrages : refaits SEULEMENT quand le réglage change (SetPoint/ClearAllPoints sont des fonctions protégées : sur une
-- barre protégée en combat, les rejouer à chaque changement de cible pourrait être bloqué)
local function placeQuest(o)
    local size = clamp(db("platesQuestSize"), 10, 32, 18)
    local side = db("platesQuestSide") or "left"
    local q, t, bar = o.quest, o.questText, o.bar
    t:SetTextColor(col("quest"))
    local key = side .. size
    if o.questKey == key then return end
    o.questKey = key
    q:SetSize(size, size)
    q:ClearAllPoints()
    t:ClearAllPoints()
    if side == "right" then
        q:SetPoint("LEFT", bar, "RIGHT", 4, 0)
        t:SetPoint("LEFT", q, "RIGHT", 1, 0)
    elseif side == "top" then
        q:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
        t:SetPoint("LEFT", q, "RIGHT", 1, 0)
    else
        -- à gauche du marqueur de raid (lui-même à gauche de la barre) pour ne pas le couvrir
        local raidMark = o.uf and o.uf.RaidTargetFrame
        if raidMark then q:SetPoint("RIGHT", raidMark, "LEFT", -2, 0) else q:SetPoint("RIGHT", bar, "LEFT", -22, 0) end
        t:SetPoint("RIGHT", q, "LEFT", -1, 0)
    end
end

local applyCastLook                      -- (barres d'incantation, plus bas)

local function applyLook(o)
    local slim = on(o) and db("platesSlim") and true or false
    local a = alphaOf(o)
    local bar = o.bar

    -- cadre du jeu ou le nôtre
    local frame = bar.bgTexture
    if frame and frame.SetAlpha then pcall(frame.SetAlpha, frame, slim and 0 or a) end
    o.back:SetShown(slim)
    o.back:SetVertexColor(col("back"))
    o.back:SetAlpha(a * clamp(db("platesBackAlpha"), 0, 100, 90) / 100)
    local size = clamp(db("platesBorder"), 0, 4, 1)
    if o.borderSize ~= size then
        o.borderSize = size
        local function around(tex, d)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", bar, "TOPLEFT", -d, d)
            tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", d, -d)
        end
        around(o.border, size)
        around(o.targetBorder, size + 1)
        -- liseré d'alerte : 3 px au-delà du bord le plus large, sinon le bord le cache
        o.glowFrame:ClearAllPoints()
        o.glowFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -(size + 4), size + 4)
        o.glowFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", size + 4, -(size + 4))
    end
    local highlight = slim and o.isTarget and db("platesTarget") and true or false
    o.border:SetVertexColor(col("border"))
    o.border:SetAlpha(a)
    o.border:SetShown(slim and not highlight and size > 0)
    o.targetBorder:SetVertexColor(col("target"))
    o.targetBorder:SetShown(highlight)
    -- bord de cible du jeu (blanc, ancré au cadre du jeu devenu invisible) : caché quand c'est le nôtre qui marque
    local selected = bar.selectedBorder
    if selected and selected.SetAlpha then pcall(selected.SetAlpha, selected, (slim and db("platesTarget")) and 0 or 1) end

    -- texture de la teinte et opacité
    local file = TEXTURES[db("platesTexture")] or TEXTURES.smooth
    if o.texFile ~= file then
        o.texFile = file
        o.tint:SetTexture(file)
    end
    o.tint:SetAlpha(a)
    o.glow:SetVertexColor(col("glow"))

    -- coins arrondis (avec notre cadre seulement : celui du jeu a ses propres coins)
    local radius = slim and math.floor(clamp(db("platesRadius"), 0, 4, 3)) or 0
    if radius > 0 and o.maskFile ~= radius and o.maskBar then
        o.maskFile = radius
        for _, m in ipairs({ o.maskBar, o.maskBack, o.maskBorder, o.maskTarget, o.maskGlow }) do
            m:SetTexture(MASK .. radius, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
    end
    local round = radius > 0
    if o.rounded ~= round and o.maskBar then     -- un masque ajouté deux fois : on ne bascule que sur changement
        o.rounded = round
        setMask(fillOf(o), o.maskBar, round)
        setMask(o.tint, o.maskBar, round)
        setMask(bar.deselectedOverlay, o.maskBar, round)   -- voile du jeu sur les plates non ciblées
        setMask(o.back, o.maskBack, round)
        setMask(o.border, o.maskBorder, round)
        setMask(o.targetBorder, o.maskTarget, round)
        setMask(o.glow, o.maskGlow, round)
    end

    placeQuest(o)
    paint(o)
    applyCastLook(o)
end

local function hideAll(o)
    o.kind = nil
    setTint(o, false)
    o.quest:Hide()
    o.questText:Hide()
    o.tag:Hide()
    stopFlash(o)
end

---------------------------------------------------------------------------
-- Menace et couleur hors combat
---------------------------------------------------------------------------
-- un autre tank du groupe tient ce mob (lecture possible seulement hors restriction)
local function heldByOtherTank(unit)
    local fn = api("UnitThreatSituation")
    for _, member in ipairs(groupTanks) do
        local ok, s = call(fn, member, unit)
        if ok and not isSecret(s) and s == 3 then return true end
    end
    return false
end

local function alert(o)
    if not db("platesAlert") then return end
    o.flashTime = clamp(db("platesAlertTime"), 0.5, 4, 1.4)
    o.flashLeft = o.flashTime
    o.flashing = true
    o.glow:SetAlpha(1)
    o.glow:Show()
    o.root:SetScript("OnUpdate", flashOnUpdate)
    if db("platesAlertSound") then
        local now = (api("GetTime") or os.time)()
        if now - lastSound > 1 then
            lastSound = now
            local id = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or SOUND_ID
            call(api("PlaySound"), id, "Master")
        end
    end
end

-- couleur hors combat (platesIdle = "reaction") : hostile / neutre / amical ; les joueurs gardent les couleurs du jeu
local function idleKind(unit, canAttack)
    if db("platesIdle") ~= "reaction" then return nil end
    local okP, player = call(api("UnitIsPlayer"), unit)
    if okP and yes(player) then return nil end
    local okR, reaction = call(api("UnitReaction"), unit, "player")
    if okR and type(reaction) == "number" and not isSecret(reaction) then
        if reaction <= 3 then return "hostile" elseif reaction == 4 then return "neutral" end
        return "friendly"
    end
    return canAttack and "hostile" or nil
end

-- plates éteintes : leurs événements sont débranchés, le rôle (et les autres tanks) se relit à la demande (au plus toutes les
-- 0,5 s) pour la fenêtre de menace
local roleStamp = -1
local function refreshRoleIfOff()
    if db("plates") then return end
    local now = (api("GetTime") or os.time)()
    if now - roleStamp < 0.5 then return end
    roleStamp = now
    isTank, tankWhy = detectTank()
    updateGroupTanks()
end

-- genre de couleur (safe/warn/loose/other) d'une menace lisible (status 0..3) selon ton rôle ; partagé avec Threat.lua
local function kindFromStatus(status, unit)
    if isTank then
        if status == 3 then return "safe" end
        if status == 0 then return (db("platesOfftank") and heldByOtherTank(unit)) and "other" or "loose" end
        return "warn"
    end
    if status >= 2 then return "loose" end            -- il te tape (2 : quelqu'un te rattrape, mais c'est toi)
    if status == 1 then return "warn" end             -- tu vas le prendre
    return "safe"
end

-- Pour la fenêtre de menace : kind, status, tanking (secret possible) d'un mob.
-- kind = safe/warn/loose/other, "bool" (menace secrète : tanking sert à SetVertexColorFromBoolean), nil (pas en combat avec toi) ;
-- 4e retour : % de menace (scaledPercentage, secret possible : seulement string.format puis SetText)
function Plates.ThreatKind(unit)
    refreshRoleIfOff()
    local ok, tanking, status, scaled = call(api("UnitDetailedThreatSituation"), "player", unit)
    if not ok then return nil end
    if isSecret(status) or isSecret(tanking) then return "bool", nil, tanking, scaled end
    if status == nil then return nil end
    return kindFromStatus(status, unit), status, tanking, scaled
end

-- (couleurs de la fenêtre de menace : mêmes réglages que les plates)
function Plates.Color(kind) return col(kind) end
function Plates.ColorObject(kind) return colorObjects and colorObjects[kind] end

-- choisit o.kind pour l'unité, puis peint
local function updateThreat(unit, o)
    local okC, canAttack = call(api("UnitCanAttack"), "player", unit)
    canAttack = okC and yes(canAttack)
    local okT, tapped = call(api("UnitIsTapDenied"), unit)
    if okT and yes(tapped) then
        o.status = nil
        o.kind = db("platesIdle") == "reaction" and "tapped" or nil
        return paint(o)
    end
    if not canAttack then
        o.status = nil
        o.kind = idleKind(unit, false)
        return paint(o)
    end
    local ok, tanking, status = call(api("UnitDetailedThreatSituation"), "player", unit)
    if not ok then o.kind = idleKind(unit, true) return paint(o) end

    if isSecret(status) or isSecret(tanking) then
        -- menace secrète : vert/rouge choisis par le jeu, pour un mob en combat seulement
        o.status = nil
        local okF, fighting = call(api("UnitAffectingCombat"), unit)
        if okF and yes(fighting) then
            o.kind, o.secretTanking = "bool", tanking
        else
            o.kind = idleKind(unit, true)
        end
        return paint(o)
    end

    local before = o.status
    o.status = status
    if status == nil then o.kind = idleKind(unit, true) return paint(o) end   -- pas en combat avec toi
    local kind = kindFromStatus(status, unit)
    o.kind = kind
    paint(o)
    -- alerte : un mob qui te tapait (2 ou 3) tape maintenant quelqu'un d'autre (0 ou 1) ; pas si un autre tank le prend
    if isTank and before and before >= 2 and status <= 1 and kind ~= "other" then alert(o) end
end

---------------------------------------------------------------------------
-- Quête (lignes de l'infobulle du mob) et rareté
---------------------------------------------------------------------------
local function clean(text)
    return (text:gsub("^%s*%-?%s*", ""):gsub("%s+$", ""))
end

-- clé de questKinds : le texte sans la progression (« Loup tué : 3/8 » -> « Loup tué : »), car l'infobulle et le
-- journal ne sont pas toujours à jour en même temps
local function kindKey(text)
    return clean((text:gsub("%d+%s*/%s*%d+", ""):gsub("%d+%s*%%", "")))
end

local noQuests = false                    -- journal lu et sans objectif : pas la peine de lire les infobulles

local function rebuildQuestKinds()
    wipe(questKinds)
    noQuests = false
    local Q = api("C_QuestLog")
    if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo and Q.GetQuestObjectives) then return end
    local ok, n = pcall(Q.GetNumQuestLogEntries)
    if not ok or type(n) ~= "number" then return end
    local count = 0
    for i = 1, n do
        local okI, info = pcall(Q.GetInfo, i)
        if okI and type(info) == "table" and not info.isHeader and info.questID then
            local okO, objectives = pcall(Q.GetQuestObjectives, info.questID)
            if okO and type(objectives) == "table" then
                for _, obj in ipairs(objectives) do
                    if not isSecret(obj.text) and not isSecret(obj.type) and type(obj.text) == "string" then
                        questKinds[kindKey(obj.text)] = obj.type
                        count = count + 1
                    end
                end
            end
        end
    end
    noQuests = (count == 0)
end

-- premier objectif non fini du joueur sur ce mob -> texte d'objectif, "3/8" (ou "40%" ou ""), type ; sinon nil
function Plates.QuestOf(unit)
    local T = api("C_TooltipInfo")
    if not (T and T.GetUnit) then return nil end
    local ok, data = pcall(T.GetUnit, unit)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local mine = false
    for i = 2, #data.lines do
        local line = data.lines[i]
        local text, kind = line.leftText, line.type
        if isSecret(text) or isSecret(kind) or type(text) ~= "string" then
            mine = false                                    -- ligne illisible : on passe à la suivante
        elseif kind == LINE_QUEST_TITLE then
            mine = true
        elseif kind == LINE_QUEST_PLAYER then
            mine = (myName ~= nil and text == myName)      -- objectifs d'un autre membre du groupe : ignorés
        elseif kind == LINE_QUEST_OBJECTIVE then
            local done = line.completed
            if mine and not yes(done) then
                local cur, goal = text:match("(%d+)%s*/%s*(%d+)")
                local pct = text:match("(%d+)%s*%%")
                cur, goal, pct = tonumber(cur), tonumber(goal), tonumber(pct)
                if cur and goal then
                    if cur < goal then return clean(text), cur .. "/" .. goal, questKinds[kindKey(text)] end
                elseif pct then
                    if pct < 100 then return clean(text), pct .. "%", questKinds[kindKey(text)] end
                else
                    return clean(text), "", questKinds[kindKey(text)]
                end
            end
        else
            mine = false
        end
    end
    return nil
end

local function showQuest(o, progress, kind)
    if progress == nil then o.quest:Hide() o.questText:Hide() return end
    o.quest:SetTexture(kind == "item" and QUEST_ITEM or QUEST_KILL)
    o.quest:Show()
    o.questText:SetText(progress)
    o.questText:SetShown(progress ~= "" and db("platesQuestText") ~= false)
end

local function updateQuest(unit, o)
    if noQuests or not db("platesQuest") then return showQuest(o, nil) end
    local objective, progress, kind = Plates.QuestOf(unit)
    showQuest(o, objective and progress or nil, kind)
end

-- « Rare », « Élite », « Rare élite », « Boss » selon les réglages
local function tagText(class)
    local rare, elite = db("platesRare"), db("platesElite")
    if class == "rare" then return rare and "Rare" or nil, 0.80, 0.85, 0.95 end
    if class == "rareelite" then
        if rare and elite then return "Rare élite", 0.80, 0.85, 0.95 end
        if rare then return "Rare", 0.80, 0.85, 0.95 end
        return elite and "Élite" or nil, 1, 0.82, 0.25
    end
    if class == "elite" then return elite and "Élite" or nil, 1, 0.82, 0.25 end
    if class == "worldboss" then return elite and "Boss" or nil, 1, 0.35, 0.30 end
    return nil
end

local function showTag(o, class)
    local text, r, g, b = tagText(class)
    if text then
        o.tag:SetText(ns.T(text))
        o.tag:SetTextColor(r, g, b)
    end
    o.tag:SetShown(text ~= nil)
end

local function updateRare(unit, o)
    local okC, class = call(api("UnitClassification"), unit)
    showTag(o, (okC and not isSecret(class)) and class or nil)
end

---------------------------------------------------------------------------
-- Barres d'incantation des ennemis
---------------------------------------------------------------------------
-- La barre d'incantation du jeu (UnitFrame.castBar = CastBarsContainer.castBar, NamePlateCastingBarTemplate) se montre,
-- se cache et se remplit toute seule. On y ajoute comme sur la barre de vie : une teinte au-dessus du remplissage
-- (interruptible / ton interruption est prête / pas interruptible), notre cadre (fond, bord, arrondi) à la place de son
-- fond (Background), et le temps restant à droite. Le jeu réécrit la texture et la couleur du remplissage à chaque
-- incantation (CastingBarFrame.lua UpdateBarFillTexture), jamais son alpha ; il fait SetAlpha sur la barre entière pour
-- le fondu de fin (nos régions suivent).
-- UnitCastingInfo / UnitChannelInfo : secrets quand le jeu restreint les incantations (SecretWhenUnitSpellCastRestricted) ;
-- notInterruptible secret -> SetVertexColorFromBoolean. Recharge des interruptions : C_Spell.GetSpellCooldown -> isActive,
-- isOnGCD (NeverSecret, SpellSharedDocumentation.lua).
-- NON VÉRIFIÉ en jeu.
local INTERRUPTS = {                     -- tous les rangs (si le jeu retire les anciens du grimoire)
    6552, 6554,                          -- Volée de coups (guerrier, posture berserker)
    72, 1671, 1672,                      -- Coup de bouclier (guerrier, avec un bouclier)
    1766, 1767, 1768, 1769,              -- Coup de pied (voleur)
    2139,                                -- Contresort (mage)
    8042, 8044, 8045, 8046, 10412, 10413, 10414,   -- Horion de terre (chaman)
}
local kickReady = false

-- vrai si une de tes interruptions est connue, utilisable et pas en recharge (le temps de recharge global ne compte pas) ;
-- rend vrai si la réponse a changé
local function updateKick()
    local was = kickReady
    kickReady = false
    local S = api("C_Spell")
    local book = api("C_SpellBook")
    -- IsPlayerSpell n'existe ici qu'avec les anciennes API (Blizzard_DeprecatedSpellBook) : C_SpellBook d'abord
    local known = (type(book) == "table" and book.IsSpellKnown) or api("IsPlayerSpell")
    for _, id in ipairs(INTERRUPTS) do
        local okK, has = call(known, id)
        if okK and yes(has) then
            local okC, info = call(S and S.GetSpellCooldown, id)
            local onCooldown = okC and type(info) == "table" and yes(info.isActive) and not yes(info.isOnGCD)
            local okU, usable = call(S and S.IsSpellUsable, id)
            local canUse = (not okU) or isSecret(usable) or (usable and true or false)
            if not onCooldown and canUse then
                kickReady = true
                break
            end
        end
    end
    return was ~= kickReady
end

local function castBarOf(uf)
    if not uf then return nil end
    return uf.castBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar)
end

local function castTimerOnUpdate(root, elapsed)
    local c = root.cast
    c.acc = (c.acc or 0) + elapsed
    if c.acc < 0.1 then return end
    c.acc = 0
    if not c.endTime then return end
    local left = c.endTime - ((api("GetTime") or os.time)())
    c.timer:SetText(left > 0 and string.format("%.1f", left) or "")
end

local stopCast                           -- (plus bas)

local function buildCast(o, cb)
    if o.cast and o.cast.bar == cb then return o.cast end
    local c = { bar = cb }
    local fill = cb.GetStatusBarTexture and cb:GetStatusBarTexture()
    local layer, sub = "ARTWORK", 0
    local okL, l, sl = pcall(function() return fill:GetDrawLayer() end)
    if okL and type(l) == "string" and not isSecret(l) and not isSecret(sl) then layer, sub = l, tonumber(sl) or 0 end
    c.tint = cb:CreateTexture(nil, layer, nil, math.min(7, sub + 1))
    if fill then c.tint:SetAllPoints(fill) else c.tint:SetAllPoints(cb) end
    c.tint:Hide()
    c.border = cb:CreateTexture(nil, "BACKGROUND", nil, -8)
    c.border:SetTexture(WHITE)
    c.border:Hide()
    c.back = cb:CreateTexture(nil, "BACKGROUND", nil, -7)
    c.back:SetTexture(WHITE)
    c.back:SetAllPoints(cb)
    c.back:Hide()
    c.maskBar, c.maskBack, c.maskBorder = newMask(cb, cb), newMask(cb, c.back), newMask(cb, c.border)
    local root = CreateFrame("Frame", nil, cb)              -- enfant de la barre : son OnUpdate ne tourne que si elle est affichée
    root:SetAllPoints(cb)
    root:SetFrameLevel((cb:GetFrameLevel() or 0) + 1)
    root.cast = c
    root:SetScript("OnHide", function() stopCast(o) end)  -- la barre du jeu a fini son fondu
    c.root = root
    c.timer = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.timer:SetPoint("LEFT", cb, "RIGHT", 3, 0)
    c.timer:Hide()
    o.cast = c
    return c
end

local function setCastTint(c, show)
    c.tint:SetShown(show)
    local fill = c.bar.GetStatusBarTexture and c.bar:GetStatusBarTexture()
    if fill and fill.SetAlpha then pcall(fill.SetAlpha, fill, show and 0 or 1) end
end

applyCastLook = function(o)
    local c = o.cast
    if not c then return end
    local enabled = on(o) and db("platesCast") and true or false
    local styled = enabled and db("platesCastStyle") and db("platesSlim") and true or false
    local a = alphaOf(o)
    local cb = c.bar
    local bg = cb.Background
    if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, styled and 0 or 1) end
    local frame = cb.Border                               -- cadre du style « Classic » (sinon caché par le jeu)
    if frame and frame.SetAlpha then pcall(frame.SetAlpha, frame, styled and 0 or 1) end
    c.back:SetShown(styled)
    c.back:SetVertexColor(col("back"))
    c.back:SetAlpha(a * clamp(db("platesBackAlpha"), 0, 100, 90) / 100)
    local size = clamp(db("platesBorder"), 0, 4, 1)
    if c.borderSize ~= size then                          -- ancrage refait seulement quand le réglage change
        c.borderSize = size
        c.border:ClearAllPoints()
        c.border:SetPoint("TOPLEFT", cb, "TOPLEFT", -size, size)
        c.border:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", size, -size)
    end
    c.border:SetVertexColor(col("border"))
    c.border:SetAlpha(a)
    c.border:SetShown(styled and size > 0)
    local file = TEXTURES[db("platesTexture")] or TEXTURES.smooth
    if c.texFile ~= file then
        c.texFile = file
        c.tint:SetTexture(file)
    end
    c.tint:SetAlpha(a)
    local radius = styled and math.floor(clamp(db("platesRadius"), 0, 4, 3)) or 0
    if radius > 0 and c.maskFile ~= radius and c.maskBar then
        c.maskFile = radius
        for _, m in ipairs({ c.maskBar, c.maskBack, c.maskBorder }) do
            m:SetTexture(MASK .. radius, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
    end
    local round = radius > 0
    if c.rounded ~= round and c.maskBar then
        c.rounded = round
        setMask(cb.GetStatusBarTexture and cb:GetStatusBarTexture(), c.maskBar, round)
        setMask(c.tint, c.maskBar, round)
        setMask(c.back, c.maskBack, round)
        setMask(c.border, c.maskBorder, round)
    end
    if not enabled then stopCast(o) end
end

stopCast = function(o)
    local c = o.cast
    if not c then return end
    c.casting, c.endTime = false, nil
    setCastTint(c, false)
    c.timer:Hide()
    c.root:SetScript("OnUpdate", nil)
end

-- couleur de l'incantation en cours : notInterruptible lisible, secret (couleur confiée au jeu) ou nil (= interruptible)
local function paintCast(o, notInterruptible)
    local c = o.cast
    local interruptKind = (db("platesCastKick") and kickReady) and "castKick" or "castInterrupt"
    if isSecret(notInterruptible) then
        if not colorFromBoolean(c.tint, notInterruptible, "castShield", interruptKind) then
            setCastTint(c, false)
            return
        end
    else
        c.tint:SetVertexColor(col(notInterruptible and "castShield" or interruptKind))
    end
    c.tint:SetAlpha(alphaOf(o))
    setCastTint(c, true)
end

-- lit l'incantation en cours de l'unité et met la barre à jour ; rend vrai si elle est interruptible (lisible)
-- ending : fin normale du sort (STOP) -> on garde la teinte pendant le fondu du jeu, sinon on verrait sa texture « pleine »
local function updateCast(unit, o, ending)
    local c = o.cast
    if not c then return false end
    if not (db("plates") and db("platesCast")) then stopCast(o) return false end
    local ok, name, _, _, _, endMs, _, _, notInterruptible = call(api("UnitCastingInfo"), unit)
    if not ok or (not isSecret(name) and name == nil) then
        ok, name, _, _, _, endMs, _, notInterruptible = call(api("UnitChannelInfo"), unit)
    end
    if not ok or (not isSecret(name) and name == nil) then
        if ending then
            c.casting, c.endTime = false, nil
            c.timer:Hide()
            c.root:SetScript("OnUpdate", nil)
        else
            stopCast(o)
        end
        return false
    end
    c.casting = true
    c.notInterruptible = notInterruptible
    paintCast(o, notInterruptible)
    if db("platesCastTimer") and type(endMs) == "number" and not isSecret(endMs) then
        c.endTime, c.acc = endMs / 1000, 1
        c.timer:SetText("")
        c.timer:Show()
        c.root:SetScript("OnUpdate", castTimerOnUpdate)
    else
        c.endTime = nil
        c.timer:Hide()
        c.root:SetScript("OnUpdate", nil)
    end
    return not isSecret(notInterruptible) and not notInterruptible
end

local CAST_END = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true }
local CAST_BROKEN = { UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true }
local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }

local function castEvent(unit, o, event)
    if not o.cast then return end
    if CAST_END[event] then
        -- (une canalisation qui suit un sort peut arriver avant le STOP du sort : on relit l'état réel)
        updateCast(unit, o, true)
        return
    end
    if CAST_BROKEN[event] then
        stopCast(o)                               -- on laisse voir le rouge « Interrompu » du jeu
        updateCast(unit, o)
        return
    end
    local interruptible = updateCast(unit, o)
    if CAST_START[event] then
        -- le jeu retouche le remplissage au début de l'incantation : on repasse après lui
        C_Timer.After(0, function() if active[unit] == o then guarded(updateCast, unit, o) end end)
        if interruptible and db("platesCastSound") and targetBar ~= nil and o.bar == targetBar then
            local now = (api("GetTime") or os.time)()
            if now - lastSound > 1 then
                lastSound = now
                call(api("PlaySound"), (SOUNDKIT and SOUNDKIT.RAID_WARNING) or SOUND_ID, "Master")
            end
        end
    end
end

local function recolorCasts()
    if not (db("plates") and db("platesCast")) then return end
    for unit, o in pairs(active) do
        if o.cast and o.cast.casting then paintCast(o, o.cast.notInterruptible) end
    end
end

---------------------------------------------------------------------------
-- Cible
---------------------------------------------------------------------------
local function updateTarget()
    targetBar = healthBarOf("target")
    for _, o in pairs(active) do
        o.isTarget = (targetBar ~= nil and o.bar == targetBar)
        applyLook(o)
    end
end

---------------------------------------------------------------------------
-- Cycle de vie des plates
---------------------------------------------------------------------------
local function setup(unit, retried)
    local bar, uf = healthBarOf(unit)
    if not bar then
        active[unit] = nil
        -- notre cadre a pu recevoir NAME_PLATE_UNIT_ADDED avant celui du jeu (UnitFrame pas encore posé) : un essai de plus
        if not retried then
            C_Timer.After(0, function()
                local C = api("C_NamePlate")
                local ok, plate = call(C and C.GetNamePlateForUnit, unit)
                if ok and plate and not active[unit] and db("plates") then guarded(setup, unit, true) end
            end)
        end
        return
    end
    if lib.isMe(unit) then return end            -- ta propre plate (ressources) : pas touchée
    local o = build(bar, uf)
    o.uf = uf or o.uf
    local cb = castBarOf(o.uf)
    if cb then buildCast(o, cb) end
    active[unit] = o
    o.unit, o.status, o.kind = unit, nil, nil
    local oldTarget = targetBar
    targetBar = healthBarOf("target")
    o.isTarget = (targetBar ~= nil and bar == targetBar)
    if targetBar ~= oldTarget then updateTarget() end   -- la plate de ta cible vient d'apparaître : atténuer les autres
    stopFlash(o)
    o.root:Show()
    applyLook(o)
    updateThreat(unit, o)
    updateQuest(unit, o)
    updateRare(unit, o)
    updateCast(unit, o)                          -- une incantation déjà en cours
end

local function release(unit)
    local o = active[unit]
    active[unit] = nil
    if o and o.unit == unit then
        hideAll(o)
        stopCast(o)
        o.status, o.isTarget = nil, false
        -- la plate de ta cible disparaît (mort, trop loin) : les autres ne sont plus atténuées
        if o.bar == targetBar then
            targetBar = nil                       -- (le jeu peut encore la donner pendant NAME_PLATE_UNIT_REMOVED)
            for _, other in pairs(active) do
                other.isTarget = false
                applyLook(other)
            end
        end
    end
end

local function scheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshPending = false
        refreshAll()
    end)
end

local function scheduleQuests()
    if questPending then return end
    questPending = true
    C_Timer.After(QUEST_DELAY, function()
        questPending = false
        scanQuests()
    end)
end

local function updateRole()
    local was = isTank
    isTank, tankWhy = detectTank()
    if was ~= isTank then scheduleRefresh() end
end

local EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_FLAGS", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
    "UNIT_CLASSIFICATION_CHANGED", "PLAYER_TARGET_CHANGED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE",
}

local function handle(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        setup(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        release(unit)
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_FLAGS" then
        local o = unit and active[unit]
        if o then updateThreat(unit, o) end           -- target/focus/boss1... : leur plate a son propre événement
    elseif event == "PLAYER_TARGET_CHANGED" then
        updateTarget()
    elseif event:sub(1, 15) == "UNIT_SPELLCAST_" then
        local o = unit and active[unit]
        if o then castEvent(unit, o, event) end
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        if updateKick() then recolorCasts() end
    elseif event == "UNIT_CLASSIFICATION_CHANGED" then
        local o = unit and active[unit]
        if o then updateRare(unit, o) end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        scheduleRefresh()
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
        scheduleQuests()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        updateGroupTanks()
        updateRole()
        scheduleRefresh()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        updateRole()
        if updateKick() then recolorCasts() end          -- Volée de coups : seulement en posture berserker
    elseif event == "PLAYER_ENTERING_WORLD" then
        updateGroupTanks()
        updateRole()
        updateKick()
        scheduleQuests()
    end
end

-- toutes les plates déjà affichées (option allumée en cours de jeu, /reload)
local function adoptVisible()
    local C = api("C_NamePlate")
    if not (C and C.GetNamePlates) then return end
    local ok, list = pcall(C.GetNamePlates)
    if not ok or type(list) ~= "table" then return end
    for _, plate in ipairs(list) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if type(unit) == "string" and not isSecret(unit) and not active[unit] then setup(unit) end
    end
end

local function conflict()
    local loaded = (api("C_AddOns") and C_AddOns.IsAddOnLoaded) or api("IsAddOnLoaded")
    for _, name in ipairs(CONFLICTS) do
        local ok, loadedOn = call(loaded, name)
        if ok and yes(loadedOn) then return name end
    end
end

local previews = {}                       -- widgets d'aperçu des options (repeints à chaque réglage)

-- Questie dessine aussi ses icônes d'objectif sur les plates (option nameplateEnabled de son profil, Questie/Modules/
-- Options/NativeOptions/NativeOptionsNameplate.lua) : en double avec les nôtres. Réglage platesHideQuestie : on coupe la
-- sienne ; on ne la rallume que si c'est nous qui l'avions coupée (platesQuestieOff).
local function syncQuestie(tries)
    tries = tries or 0
    local Q = api("Questie")
    local profile = type(Q) == "table" and type(Q.db) == "table" and Q.db.profile
    if type(profile) ~= "table" then
        if api("Questie") ~= nil and tries < 6 then C_Timer.After(5, function() syncQuestie(tries + 1) end) end
        return
    end
    local hide = db("plates") and db("platesQuest") and db("platesHideQuestie")
    if hide and profile.nameplateEnabled ~= false then
        profile.nameplateEnabled = false
        ns.db.platesQuestieOff = true
        local loader = api("QuestieLoader")
        local ok, mod = call(type(loader) == "table" and loader.ImportModule, loader, "QuestieNameplate")
        if ok and type(mod) == "table" and mod.HideCurrentFrames then pcall(mod.HideCurrentFrames, mod) end
    elseif not hide and db("platesQuestieOff") then
        profile.nameplateEnabled = true
        ns.db.platesQuestieOff = false
    end
end

local function restyleAll()
    rebuildColorObjects()
    for _, o in pairs(byBar) do applyLook(o) end
    for _, p in ipairs(previews) do p:Refresh() end
end

function Plates:Apply()
    if not events then return end
    if db("plates") then
        for _, ev in ipairs(EVENTS) do lib.registerEvent(events, ev) end
        updateGroupTanks()
        updateRole()
        rebuildQuestKinds()
        adoptVisible()
        refreshAll()
    else
        events:UnregisterAllEvents()
        for unit in pairs(active) do release(unit) end
        targetBar = nil
    end
    for _, o in pairs(byBar) do applyLook(o) end         -- plates éteintes : le cadre du jeu revient
end

---------------------------------------------------------------------------
-- Styles prêts à l'emploi : chaque style remet toutes les couleurs par défaut puis applique ses valeurs
---------------------------------------------------------------------------
Plates.PRESETS = {
    { id = "platyplus", text = "Platyplus", values = {
        platesSlim = true, platesRadius = 3, platesBorder = 1, platesBackAlpha = 90, platesOpacity = 85,
        platesTexture = "smooth", platesIdle = "reaction", platesTarget = true, platesNonTarget = 100 } },
    { id = "threat", text = "Threat Plates", values = {
        platesSlim = true, platesRadius = 0, platesBorder = 1, platesBackAlpha = 100, platesOpacity = 100,
        platesTexture = "blizzard", platesIdle = "reaction", platesTarget = true, platesNonTarget = 100,
        platesColSafe = { 0, 1, 0 }, platesColWarn = { 1, 1, 0 }, platesColLoose = { 1, 0, 0 },
        platesColOther = { 0.06, 0.67, 0.78 } } },
    { id = "minimal", text = "Minimaliste", values = {
        platesSlim = true, platesRadius = 4, platesBorder = 0, platesBackAlpha = 60, platesOpacity = 75,
        platesTexture = "flat", platesIdle = "reaction", platesTarget = true, platesNonTarget = 60 } },
    { id = "game", text = "Comme le jeu", values = {
        platesSlim = false, platesRadius = 0, platesBorder = 1, platesBackAlpha = 90, platesOpacity = 100,
        platesTexture = "blizzard", platesIdle = "game", platesTarget = false, platesNonTarget = 100 } },
}

function Plates.ApplyPreset(id)
    for _, preset in ipairs(Plates.PRESETS) do
        if preset.id == id then
            for _, key in pairs(COLOR_KEYS) do ns:Reset(key) end
            for key, value in pairs(preset.values) do ns:Set(key, ns.Copy(value)) end
            return true
        end
    end
    return false
end

-- Tous les réglages de look et de couleurs (pas l'interrupteur ni le rôle) : bouton « tout remettre par défaut »
Plates.LOOK_KEYS = {
    "platesSlim", "platesRadius", "platesBorder", "platesBackAlpha", "platesOpacity", "platesTexture", "platesIdle",
    "platesTarget", "platesNonTarget", "platesQuestSize", "platesQuestSide", "platesQuestText", "platesAlertTime",
    "platesCastStyle", "platesCastKick", "platesCastTimer",
}
for _, key in pairs(COLOR_KEYS) do Plates.LOOK_KEYS[#Plates.LOOK_KEYS + 1] = key end

function Plates.ResetLook()
    for _, key in ipairs(Plates.LOOK_KEYS) do ns:Reset(key) end
end

---------------------------------------------------------------------------
-- Aperçu dans les options : 4 plates d'exemple peintes avec les vrais réglages (même code que les vraies plates)
---------------------------------------------------------------------------
local SAMPLES = {
    { name = "Loup des bois", kind = "safe", value = 0.85, caption = "Il te tape" },
    { name = "Ours grizzly", kind = "warn", value = 0.55, caption = "Ça se joue · ta cible", target = true,
      cast = "Rugissement", castKind = "interrupt", castValue = 0.6, castLeft = "0.8" },
    { name = "Murloc côtier", kind = "loose", value = 0.35, caption = "Il tape un allié",
      cast = "Soins (pas interruptible)", castKind = "shield", castValue = 0.3, castLeft = "2.1" },
    { name = "Kobold mineur", kind = "hostile", value = 1, caption = "Hors combat · quête · rare", quest = "3/8",
      class = "rare" },
}

-- columns : 2 (dans une carte) ou 1 (panneau d'aperçu collé à la fenêtre d'options)
function Plates.NewPreview(parent, width, columns)
    width, columns = width or 550, columns or 2
    local box = CreateFrame("Frame", nil, parent)
    local cellW, cellH = math.floor(width / columns), 84
    local rows = math.ceil(#SAMPLES / columns)
    box:SetSize(width, cellH * rows + 8)
    box.noDivider = true
    box.samples = {}
    for i, s in ipairs(SAMPLES) do
        local col0, row0 = (i - 1) % columns, math.floor((i - 1) / columns)
        local bar = CreateFrame("StatusBar", nil, box)
        bar:SetStatusBarTexture(TEXTURES.blizzard)
        bar:SetStatusBarColor(0.85, 0.12, 0.10)          -- ce que montrerait le jeu sans nos couleurs
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(s.value)
        -- décalée à droite : à gauche, la place de l'icône de quête et de « 3/8 »
        bar:SetPoint("TOP", box, "TOPLEFT", col0 * cellW + cellW / 2 + 20, -(row0 * cellH + 20))
        -- cadre du jeu imité (rendu transparent par « Remplacer le cadre du jeu »)
        local frame = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
        frame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
        frame:SetColorTexture(0, 0, 0, 0.75)
        bar.bgTexture = frame
        local name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("BOTTOM", bar, "TOP", 0, 3)
        name:SetText(s.name)
        local caption = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        caption:SetTextColor(0.72, 0.75, 0.80)
        caption:SetText(ns.T(s.caption))
        local o = build(bar, nil, true)
        if s.cast then
            -- barre d'incantation imitée : remplissage, fond du jeu, nom du sort dedans
            local cb = CreateFrame("StatusBar", nil, box)
            cb:SetStatusBarTexture(TEXTURES.blizzard)
            cb:SetStatusBarColor(1, 0.7, 0)
            cb:SetMinMaxValues(0, 1)
            cb:SetValue(s.castValue)
            cb:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -3)
            cb:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -3)
            local bgc = cb:CreateTexture(nil, "BACKGROUND", nil, -6)
            bgc:SetAllPoints(cb)
            bgc:SetColorTexture(0, 0, 0, 0.5)
            cb.Background = bgc
            local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", cb, "LEFT", 3, 0)
            text:SetText(ns.T(s.cast))
            buildCast(o, cb)
            o.castPreview = cb
            caption:SetPoint("TOP", cb, "BOTTOM", 0, -5)
        else
            caption:SetPoint("TOP", bar, "BOTTOM", 0, -5)
        end
        o.isTarget = s.target and true or false
        o.previewHasTarget = true
        o.kind = s.kind
        box.samples[i] = { o = o, s = s, bar = bar }
    end

    function box:Refresh()
        local style = Plates.GetGameSetting("nameplateStyle") or 1
        local size = Plates.GetGameSetting("nameplateSize") or 2
        local scale = ({ 0.8, 1, 1.25, 1.4, 1.6 })[size] or 1
        local h = math.floor(((style == 1) and 13 or 20) * math.min(scale, 1.4) + 0.5)
        local w = math.min(cellW - 100, math.floor(210 * math.min(scale, 1.25)))
        for _, e in ipairs(self.samples) do
            e.bar:SetSize(w, h)
            local o, s = e.o, e.s
            o.kind = s.kind
            -- hors combat en couleurs du jeu : pas de teinte
            if s.kind == "hostile" and db("platesIdle") ~= "reaction" then o.kind = nil end
            applyLook(o)
            showQuest(o, s.quest and (db("platesQuest") and s.quest or nil), "monster")
            showTag(o, s.class)
            if o.cast then
                o.cast.bar:SetHeight(math.max(8, math.floor(h * 0.75 + 0.5)))
                o.cast.bar:SetShown(db("platesCast") and true or false)
                if db("platesCast") then
                    local kind = s.castKind == "shield" and "castShield"
                        or (db("platesCastKick") and "castKick" or "castInterrupt")
                    o.cast.tint:SetVertexColor(col(kind))
                    o.cast.tint:SetAlpha(alphaOf(o))
                    setCastTint(o.cast, true)
                    o.cast.timer:SetText(s.castLeft)
                    o.cast.timer:SetShown(db("platesCastTimer") and true or false)
                end
            end
        end
    end
    box:Refresh()
    previews[#previews + 1] = box
    return box
end

---------------------------------------------------------------------------
-- Taille et épaisseur des plates : réglages du jeu (CVars nameplateSize 1..5, nameplateStyle 0 épaisse / 1 fine / 2 bloc ;
-- Blizzard_NamePlateConstants Camelot : barre fine 13 px, épaisse 20 px, × 0,75..1,6 selon la taille). Hors combat.
---------------------------------------------------------------------------
local function inCombat()
    local ok, v = call(api("InCombatLockdown"))
    return ok and yes(v)
end

function Plates.GetGameSetting(name)
    local ok, v = call(api("GetCVar"), name)
    return ok and not isSecret(v) and tonumber(v) or nil
end

function Plates.SetGameSetting(name, value)
    if inCombat() then
        ns:Print("taille des plates : à changer hors combat.")
        return false
    end
    local ok = call(api("SetCVar"), name, tostring(value))
    for _, p in ipairs(previews) do pcall(p.Refresh, p) end
    return ok
end

function Plates:IsTank()
    refreshRoleIfOff()
    return isTank, ns.T(tankWhy)
end

-- /pp plates : état et ce que voit chaque plate affichée
function Plates:Command()
    local other = conflict()
    ns:Print(ns.Tf("plates des mobs : %s - rôle : %s (%s)", db("plates") and ns.T("allumées") or ns.T("éteintes"),
        isTank and ns.T("tank") or ns.T("DPS/soins"), ns.T(tankWhy)))
    if other then ns:Print(ns.Tf("%s est chargé : il cache les plates du jeu, donc aussi celles de Platyplus.", other)) end
    local n = 0
    for unit, o in pairs(active) do
        n = n + 1
        local ok, _, status = call(api("UnitDetailedThreatSituation"), "player", unit)
        local threat = not ok and ns.T("erreur") or isSecret(status) and ns.T("secrète") or tostring(status)
        local objective, progress = Plates.QuestOf(unit)
        ns:Print("  " .. unit, ns.T("menace :"), threat, ns.T("- couleur :"), tostring(o.kind or ns.T("jeu")),
            objective and ns.Tf("- quête : %s %s", objective, progress) or "",
            o.tag:IsShown() and ("- " .. (o.tag:GetText() or "")) or "", o.isTarget and ns.T("- cible") or "")
    end
    if n == 0 then ns:Print(ns.T("  aucune plate de mob affichée (touche V pour les montrer)")) end
    -- détail du rendu de la plate de ta cible (opacités réellement posées)
    local o = targetBar and byBar[targetBar]
    if o then
        local function alpha(region)
            if not (region and region.GetAlpha) then return "-" end
            local okA, v = pcall(region.GetAlpha, region)
            if not okA then return ns.T("erreur") end
            if isSecret(v) then return ns.T("secret") end
            return string.format("%.2f%s", v, region:IsShown() and "" or ns.T(" (caché)"))
        end
        ns:Print(ns.T("  cible : opacité réglée"), tostring(db("platesOpacity")) .. "%", ns.T("- teinte"), alpha(o.tint),
            ns.T("- fond"), alpha(o.back), ns.T("- bord"), alpha(o.border), ns.T("- remplissage du jeu"),
            alpha(fillOf(o)), ns.T("- cadre du jeu"), alpha(o.bar.bgTexture))
    end
    ns:Print(ns.T("  ton interruption :"), kickReady and ns.T("prête") or ns.T("pas prête (ou tu n'en as pas)"))
    local Q = api("Questie")
    local profile = type(Q) == "table" and type(Q.db) == "table" and Q.db.profile
    if type(profile) == "table" then
        ns:Print(ns.T("  icônes de Questie sur les plates :"), profile.nameplateEnabled == false and ns.T("coupées") or ns.T("affichées"))
    end
end

function Plates:Init()
    lib = ns.Resources and ns.Resources.lib
    if not lib then return end
    local ok, name = call(api("UnitName"), "player")
    if ok and not isSecret(name) then myName = name end
    rebuildColorObjects()

    onEvent = lib.guard(NAME, handle)
    refreshAll = lib.guard(NAME, function()
        for unit, o in pairs(active) do updateThreat(unit, o) end
    end)
    guarded = lib.guard(NAME, function(fn, ...) fn(...) end)
    scanQuests = lib.guard(NAME, function()
        rebuildQuestKinds()
        for unit, o in pairs(active) do updateQuest(unit, o) end
    end)

    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(...) onEvent(...) end)
    ns:OnChange("plates", function()
        lib.resetFailures(NAME)
        Plates:Apply()
        syncQuestie(6)
        for _, p in ipairs(previews) do pcall(p.Refresh, p) end
    end)
    ns:OnChange("platesRole", function() updateRole() refreshAll() end)
    -- tous les autres réglages plates* : look, couleurs, quêtes, rareté
    -- regroupés sur une image : le sélecteur de couleur écrit à chaque image, un style prêt écrit ~25 réglages
    local restylePending, questsTouched = false, false
    ns:OnChange("*", function(key)
        if type(key) ~= "string" or key:sub(1, 6) ~= "plates" then return end
        if key == "plates" or key == "platesRole" or key == "platesBigDone" then return end
        if key:sub(1, 11) == "platesQuest" or key == "platesHideQuestie" then questsTouched = true end
        if restylePending then return end
        restylePending = true
        C_Timer.After(0, function()
            restylePending = false
            local quests = questsTouched
            questsTouched = false
            guarded(function()
                if quests then syncQuestie(6) end
                restyleAll()
                if db("plates") then
                    refreshAll()
                    if quests then scanQuests() end
                    for unit, o in pairs(active) do updateRare(unit, o) end
                end
            end)
        end)
    end)
    self:Apply()
    syncQuestie()

    -- une fois : barres plus épaisses et plus grandes (le réglage du jeu par défaut sur Forever = fine, normale)
    if db("plates") and not db("platesBigDone") then
        C_Timer.After(3, function()
            if inCombat() or db("platesBigDone") then return end
            ns.db.platesBigDone = true
            local style, size = Plates.GetGameSetting("nameplateStyle"), Plates.GetGameSetting("nameplateSize")
            local changed = false
            if style == 1 then changed = Plates.SetGameSetting("nameplateStyle", 0) or changed end
            if size and size < 3 then changed = Plates.SetGameSetting("nameplateSize", 3) or changed end
            if changed then
                ns:Print("plates des mobs : barres passées en « épaisse » et « grande ». À régler dans /pp, onglet Plates.")
            end
        end)
    end

    local other = db("plates") and conflict()
    if other then
        C_Timer.After(5, function()
            ns:Print(ns.Tf("%s est chargé : il remplace les plates du jeu, celles de Platyplus (couleurs de menace, quêtes) ne se voient pas. Désactive-le dans la liste des addons, ou coupe « Plates des mobs » (/pp plates off).", other))
        end)
    end
end
