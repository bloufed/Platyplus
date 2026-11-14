-- Platyplus : étincelles sur tout ce que tu peux ramasser
-- Principe repris de l'addon « Forever Loot Sparkles » (GPL-3.0-or-later, voir Licenses\ForeverLootSparkles.txt),
-- réécrit pour Platyplus : réglages dans ns.db, options dans l'onglet Butin, image Media\Flare.tga.
--
-- 1. Objets de quête (sparkleLoot) : le jeu sait faire briller le butin de quête, mais un préréglage graphique coupe
--    cette étincelle. Platyplus remet le CVar outlineModeShowLootEffectWhenDisabled à 1 à la connexion, et 1 s après
--    chaque changement graphique. Le mode de contour (outline) reste celui du joueur. En combat : après le combat.
--    Couper l'option ne prend effet qu'après un redémarrage du jeu (/reload ne suffit pas) : un message le dit.
--
-- 2. Plantes, objets de quête et cadavres qui ont encore du butin (sparkleHerbs,
--    sparkleQuestObjects, sparkleCorpses) : le jeu n'a pas d'étincelle pour eux. Le ciblage « souple » de Blizzard
--    choisit toujours une cible d'interaction (l'unité "softinteract", la même que celle de ta touche d'interaction,
--    voir Interact.lua) et peut lui donner une plaque de nom. Un petit nuage d'éclats dorés est accroché à cette plaque :
--    terne hors de portée, vif avec une courte rafale quand tu peux ramasser, gris quand c'est impossible (compétence
--    trop basse...). La catégorie vient de l'icône de curseur de l'objet, l'état du test de portée d'interaction.
--    Une seule étincelle à la fois : celle de l'objet que le jeu ciblerait. Pas d'étincelle pendant un combat
--    (le jeu ne laisse pas un addon changer ces réglages en combat).
--
-- Réglages du jeu modifiés pendant que ce point 2 est actif : SoftTargetInteract (3, au démarrage seulement),
-- SoftTargetInteractRange (60 ; le jeu lâche la cible vers 15 m), SoftTargetInteractArc (2 : tout autour de toi),
-- SoftTargetInteractOnlyInRange (0), SoftTargetIconGameObject (1, au démarrage seulement) et
-- SoftTargetNameplateInteract (1 seulement sur un objet qui brille). Les valeurs d'origine sont gardées dans
-- ns.db.sparkleCVars (clé volontairement absente de DEFAULTS : « tout réinitialiser » ne doit pas les perdre)
-- et remises dès que plus aucune des quatre catégories n'est allumée. SoftTargetInteract n'est pas remis tant que
-- l'interaction rapide de Platyplus est allumée : elle en a besoin.
--
-- Tout ce qui touche à d'autres unités peut échouer ou rendre des valeurs « secrètes » : c'est alors « inconnu »,
-- jamais une erreur (pcall + issecretvalue).
local ADDON, ns = ...

local Sparkles = {}
ns.Sparkles = Sparkles

local SOFT = "softinteract"
local TEXTURE = ns.MEDIA .. "Flare"
local FALLBACK_TEXTURE = "Interface\\Cooldown\\star4"
local LOOT_CVAR = "outlineModeShowLootEffectWhenDisabled"

-- réglage de Platyplus pour chaque catégorie d'objet
local CATEGORY_KEYS = {
    herb = "sparkleHerbs",
    quest = "sparkleQuestObjects",
    corpseLoot = "sparkleCorpses",
}

local CATEGORY_LABELS = {
    herb = "plante", quest = "objet de quête", corpseLoot = "cadavre avec du butin",
    other = "autre (PNJ, coffre...)",
}

local RANGE = 60            -- portée de la cible d'interaction demandée (m) ; le jeu la lâche vers 15 m
local ARC = 2               -- 0 = droit devant, 1 = devant, 2 = tout autour
local OFFSET_Y = -45        -- de la plaque de nom vers l'objet (pixels)
local SPREAD = 46           -- rayon où apparaissent les éclats (pixels)
local GLINT_SIZE = 34
local GLINT_COUNT = 7
local GOLD = { 1, 0.88, 0.52 }   -- or pâle, celui de l'étincelle de butin du jeu
local GREY = { 0.62, 0.62, 0.62 }

local POLL_INTERVAL = 0.12  -- relecture de la cible et de son état (secondes)
local FADE_IN = 0.35
local BLEND_TIME = 0.30     -- fondu entre deux états
local STATE_DELAY = 0.15    -- un état doit tenir ce temps avant d'apparaître (pas de scintillement au bord de la portée)
local LOCK_DELAY = 0.60     -- idem pour « verrouillé », confirmé plus prudemment

-- Réglages du jeu modifiés ; les valeurs d'origine sont gardées puis remises
local MANAGED_CVARS = {
    "SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractRange",
    "SoftTargetInteractArc", "SoftTargetInteractOnlyInRange", "SoftTargetIconGameObject",
}

-- Fichiers de curseur (Interface\Cursor\*.blp) -> catégorie
local CURSOR_CATEGORY = {
    GatherHerbs = "herb",
    Quest = "quest", QuestRepeatable = "quest", QuestTurnIn = "quest",
    Interact = "other", PickLock = "other", LootAll = "other", Pickup = "other",
}

-- Le client rend un identifiant de fichier, un chemin (Interface\Cursor\Mine) ou un nom d'atlas
-- (Cursor_Crosshair_UnableGatherHerbs_64) : on cherche donc des mots-clés dans le texte.
local CURSOR_KEYWORDS = {
    { "gather", "herb" },
    { "quest", "quest" },
    { "lootall", "other" },
    { "pickup", "other" },
    { "picklock", "other" },
    { "interact", "other" },
}

local sin, cos, sqrt, random, min, max, pi = math.sin, math.cos, math.sqrt, math.random, math.min, math.max, math.pi

local gateOpen              -- la plaque de nom de la cible du jeu est-elle allumée ? nil = à reposer
local pendingCVars = false  -- "apply" ou "restore" une fois le combat fini
local pendingForce = false  -- l'« apply » en attente allume aussi la touche d'interaction
local directWorks = false   -- GetNamePlateForUnit("softinteract") a déjà marché pour un objet
local activeUnits = {}      -- nameplateN -> true
local cursorLookup         -- fileID -> { catégorie, grisé } (construit à la première utilisation)
local questTexts = {}       -- objectifs de quête pas finis, en minuscules et sans compteurs
local questsDirty = true
local probe                 -- texture cachée qui sert à lire l'icône de curseur

local sparkle = {}          -- l'unique cadre d'étincelle et l'état de son animation
local loot = { applying = false, pendingCombat = false, shown = false, token = 0 }

---------------------------------------------------------------------------
-- Petits outils
---------------------------------------------------------------------------
-- Les API du jeu sont lues au moment de l'appel : une API absente de ce client donne « inconnu », pas une erreur.
local function api(name) return rawget(_G, name) end

local function isSecret(value)
    local fn = api("issecretvalue")
    return fn ~= nil and fn(value) and true or false
end

-- Les appels qui touchent d'autres unités peuvent échouer ou rendre une valeur secrète : les deux = « inconnu »
local function safeCall(func, ...)
    if not func then return nil end
    local ok, result = pcall(func, ...)
    if not ok or isSecret(result) then return nil end
    return result
end

local function call(name, ...)
    return safeCall(api(name), ...)
end

local function lerp(a, b, t) return a + (b - a) * t end

local function approach(value, target, step)
    if value < target then return min(value + step, target) end
    return max(value - step, target)
end

local function isActive()
    local db = ns.db
    if not db then return false end
    for _, key in pairs(CATEGORY_KEYS) do
        if db[key] then return true end
    end
    return false
end

-- "1" et "1.000000" sont égaux
local function sameValue(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na == nb end
    return tostring(a) == tostring(b)
end

---------------------------------------------------------------------------
-- Réglages du jeu
---------------------------------------------------------------------------
local function cvarGet(name)
    local ok, value = pcall(GetCVar, name)
    if ok then return value end
    return nil
end

-- N'écrit que les CVars connus du client, et seulement quand la valeur change : CVAR_UPDATE est synchrone, chaque
-- écriture fait tourner les gestionnaires de Blizzard « teintés » par l'addon (erreurs de teinte vues ailleurs).
local function cvarSet(name, value)
    local current = cvarGet(name)
    if current == nil or sameValue(current, value) then return end
    pcall(SetCVar, name, tostring(value))
end

local function savedCVars()
    if type(ns.db.sparkleCVars) ~= "table" then ns.db.sparkleCVars = {} end
    return ns.db.sparkleCVars
end

---------------------------------------------------------------------------
-- 1. Étincelle de butin du jeu (objets de quête)
---------------------------------------------------------------------------
local LOOT_WATCHED = { graphicsquality = true, raidgraphicsquality = true, [LOOT_CVAR:lower()] = true }

local function lootApply()
    if not ns.db.sparkleLoot then return end
    if InCombatLockdown() then
        loot.pendingCombat = true
        return
    end
    loot.applying = true
    cvarSet(LOOT_CVAR, 1)
    loot.applying = false
end

-- Plusieurs changements d'affilée (un préréglage en fait plusieurs) : une seule remise, après la dernière
local function lootSchedule(delay)
    loot.token = loot.token + 1
    local mine = loot.token
    C_Timer.After(delay, function()
        if mine == loot.token then lootApply() end
    end)
end

local function lootChanged(_, value)
    if value then
        loot.shown = true
        lootApply()
    else
        loot.pendingCombat = false
        loot.token = loot.token + 1   -- annule une remise programmée
        loot.applying = true
        cvarSet(LOOT_CVAR, 0)
        loot.applying = false
        -- Couper ne prend effet qu'après un redémarrage complet du jeu (/reload ne suffit pas)
        if loot.shown then
            ns:Print("redémarre le jeu pour retirer les étincelles de butin : /reload ne suffit pas.")
        end
    end
end

---------------------------------------------------------------------------
-- 2. Étincelles à l'approche : réglages du jeu
---------------------------------------------------------------------------
local evaluate   -- définie plus bas

-- La plaque de nom que le jeu pose sur la cible d'interaction : l'étincelle s'y accroche. Elle n'est allumée que pour
-- un objet qui a une étincelle, pour que les PNJ, boîtes aux lettres... marchent avec la touche sans plaque.
local function setGate(open)
    if open == gateOpen or InCombatLockdown() then return end
    gateOpen = open
    cvarSet("SoftTargetNameplateInteract", open and 1 or 0)
end

-- SoftTargetInteract (« Activer la touche d'interaction ») et SoftTargetIconGameObject (les icônes d'interaction des
-- objets du monde) sont aussi des réglages du joueur : allumés quand les étincelles démarrent et à chaque fois qu'une
-- option est allumée (force) ; à la connexion, un joueur qui les a coupés depuis les garde coupés.
local function applyCVars(force)
    if InCombatLockdown() then
        pendingCVars = "apply"
        pendingForce = pendingForce or force == true
        return
    end
    local saved = savedCVars()
    if saved.SoftTargetInteract == nil or saved.SoftTargetIconGameObject == nil then force = true end
    for _, name in ipairs(MANAGED_CVARS) do
        if saved[name] == nil then saved[name] = cvarGet(name) or false end
    end
    if force then
        cvarSet("SoftTargetInteract", 3)        -- cible d'interaction toujours active
        cvarSet("SoftTargetIconGameObject", 1)  -- les objets du monde ont une plaque de nom
    end
    cvarSet("SoftTargetInteractRange", RANGE)
    cvarSet("SoftTargetInteractArc", ARC)
    cvarSet("SoftTargetInteractOnlyInRange", 0) -- trouve aussi les objets hors de portée d'interaction
    gateOpen = nil
    evaluate()
end

local function restoreCVars()
    if InCombatLockdown() then
        pendingCVars = "restore"
        return
    end
    local saved = ns.db.sparkleCVars
    if type(saved) ~= "table" or next(saved) == nil then return end
    for name, value in pairs(saved) do
        -- l'interaction rapide de Platyplus a besoin de SoftTargetInteract à 3 (voir Interact.lua)
        local keep = name == "SoftTargetInteract" and ns.db.interact
        if value ~= false and not keep then cvarSet(name, value) end
    end
    ns.db.sparkleCVars = nil
    gateOpen = nil
end

---------------------------------------------------------------------------
-- Reconnaissance de l'objet
---------------------------------------------------------------------------
local function buildCursorLookup()
    cursorLookup = {}
    local getID = api("GetFileIDFromPath")
    if not getID then return end
    for name, category in pairs(CURSOR_CATEGORY) do
        for _, prefix in ipairs({ "", "Unable" }) do
            local path = "Interface\\Cursor\\" .. prefix .. name
            local id = safeCall(getID, path) or safeCall(getID, path .. ".blp")
            if id then cursorLookup[id] = { category, prefix ~= "" } end
        end
    end
end

local function normalizeText(text)
    text = text:lower():gsub("\194\160", " ")   -- espace insécable
    text = text:gsub("\226\128\153", "'")        -- apostrophe typographique
    text = text:gsub("%d+%s*/%s*%d+", "")        -- compteur « 0/1 »
    text = text:gsub("^[%s:%-]+", ""):gsub("[%s:%-]+$", "")
    return text
end

local function rebuildQuestTexts()
    questsDirty = false
    wipe(questTexts)
    local log = api("C_QuestLog")
    if not (log and log.GetQuestObjectives) then return end
    local modern = log.GetNumQuestLogEntries and log.GetQuestIDForLogIndex
    local count = modern and safeCall(log.GetNumQuestLogEntries) or safeCall(api("GetNumQuestLogEntries")) or 0
    for index = 1, count do
        local questID
        if modern then
            questID = safeCall(log.GetQuestIDForLogIndex, index)
        elseif api("GetQuestLogTitle") then
            local ok, _, _, _, isHeader, _, _, _, id = pcall(api("GetQuestLogTitle"), index)
            if ok and not isHeader then questID = id end
        end
        local objectives = type(questID) == "number" and safeCall(log.GetQuestObjectives, questID)
        if type(objectives) == "table" then
            for _, objective in ipairs(objectives) do
                local text = objective.text
                if not objective.finished and type(text) == "string" and not isSecret(text) then
                    text = normalizeText(text)
                    if #text >= 4 then questTexts[#questTexts + 1] = text end
                end
            end
        end
    end
end

-- Le nom de l'objet fait-il partie d'un objectif pas fini (« Scie trempée : 0/1 »), ou l'objectif fait-il partie du
-- nom (« Provisions » dans « Caisse de provisions ») ?
local function matchesObjective(name)
    if type(name) ~= "string" or #name < 4 then return false end
    if questsDirty then rebuildQuestTexts() end
    name = normalizeText(name)
    for _, text in ipairs(questTexts) do
        if text:find(name, 1, true) or (#text >= 5 and name:find(text, 1, true)) then return true end
    end
    return false
end

local function isQuestRelated(unit, name)
    local log = api("C_QuestLog")
    if log and log.UnitIsRelatedToActiveQuest and safeCall(log.UnitIsRelatedToActiveQuest, unit) == true then
        return true
    end
    local enum, tooltips = api("Enum"), api("C_TooltipInfo")
    local lineType = enum and enum.TooltipDataLineType and enum.TooltipDataLineType.QuestObjective
    if lineType and tooltips and tooltips.GetUnit then
        local data = safeCall(tooltips.GetUnit, unit)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.type == lineType then return true end
            end
        end
    end
    return matchesObjective(name)
end

-- Catégorie et « grisé » (variante Unable : on ne peut pas interagir maintenant) d'un nom de curseur
local function readCursorName(name)
    if type(name) ~= "string" then return nil end
    name = name:lower()
    local blocked = name:find("unable", 1, true) ~= nil
    for _, entry in ipairs(CURSOR_KEYWORDS) do
        if name:find(entry[1], 1, true) then return entry[2], blocked end
    end
    return nil, blocked
end

-- Rend la catégorie de l'objet et si son curseur est grisé
local function classify(unit, name)
    local category, blocked
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
    end
    if safeCall(api("SetUnitCursorTexture"), probe, unit, nil, true) then
        if not cursorLookup then buildCursorLookup() end
        local texture = probe:GetTexture()
        local atlas = probe.GetAtlas and probe:GetAtlas()
        if isSecret(texture) then texture = nil end
        if isSecret(atlas) then atlas = nil end
        local known = type(texture) == "number" and cursorLookup[texture]
        if known then
            category, blocked = known[1], known[2]
        else
            category, blocked = readCursorName(texture)
            if not category then
                local fromAtlas, atlasBlocked = readCursorName(atlas)
                category, blocked = fromAtlas, blocked or atlasBlocked
            end
        end
    end
    if category ~= "herb" and isQuestRelated(unit, name) then
        category = "quest"
    end
    return category, blocked or false
end

-- Le cadavre a-t-il encore du butin que ce personnage peut prendre ? pcall et pas safeCall : il faut les deux valeurs.
local function hasLootLeft(unit)
    local guid, canLootUnit = call("UnitGUID", unit), api("CanLootUnit")
    if not (guid and canLootUnit) then return false end
    local ok, hasLoot, canLoot = pcall(canLootUnit, guid)
    if not ok or isSecret(hasLoot) or isSecret(canLoot) then return false end
    return hasLoot == true and canLoot ~= false
end

-- UnitIsCorpse est faux pour un monstre mort (vérifié dans le client), UnitIsDead non
local function isCorpseWithLoot(unit)
    return call("UnitIsDead", unit) == true and hasLootLeft(unit)
end

-- Catégorie (et « grisé ») de la cible : un objet du monde, ou un cadavre qui a encore du butin
local function classifyTarget(unit)
    if call("UnitIsGameObject", unit) == true then
        return classify(unit, call("UnitName", unit))
    end
    if ns.db.sparkleCorpses and isCorpseWithLoot(unit) then return "corpseLoot", false end
    return nil, false
end

-- "ready" : on peut interagir ; "far" : trop loin ; "locked" : à portée mais le jeu refuse (compétence trop basse,
-- objet verrouillé...)
local function readState(unit, blocked)
    local inRange = api("UnitIsInInteractRange") and call("UnitIsInInteractRange", unit)
    if inRange == false then return "far" end
    if blocked then return inRange == true and "locked" or "far" end
    return "ready"
end

---------------------------------------------------------------------------
-- Cible
---------------------------------------------------------------------------
local function getNamePlate(unit)
    local plates = api("C_NamePlate")
    return plates and safeCall(plates.GetNamePlateForUnit, unit)
end

-- true, false, ou nil quand le client ne dit rien (valeurs secrètes). Un objet du monde « n'existe » pas pour
-- UnitExists.
local function softTargetExists()
    local isUnit, isObject = call("UnitExists", SOFT), call("UnitIsGameObject", SOFT)
    if isUnit == true or isObject == true then return true end
    if isUnit == false and isObject == false then return false end
    return nil
end

-- Rend l'unité à interroger, sa plaque de nom (nil si le jeu ne l'affiche pas, ou pas encore) et, sans cible lisible,
-- si c'est faute de savoir. Tant que "softinteract" n'a pas donné la plaque d'un objet du monde sur ce client, on
-- cherche aussi parmi les plaques visibles.
local function resolveTarget()
    local exists = softTargetExists()
    if exists == false then return nil end
    local plate = getNamePlate(SOFT)
    if plate then
        if not directWorks and call("UnitIsGameObject", SOFT) == true then directWorks = true end
        return SOFT, plate
    end
    if not directWorks then
        for unit in pairs(activeUnits) do
            if call("UnitIsGameObject", unit) == true or call("UnitIsUnit", unit, SOFT) == true then
                plate = getNamePlate(unit)
                if plate then return unit, plate end
            end
        end
    end
    if exists then return SOFT, nil end
    return nil, nil, true
end

---------------------------------------------------------------------------
-- Étincelle (dessin)
---------------------------------------------------------------------------
-- Pose un éclat ailleurs, dans un disque aplati, après une courte pause sombre
local function respawn(glint, now)
    local angle, reach = random() * 2 * pi, sqrt(random())
    glint.x, glint.y = cos(angle) * reach * SPREAD, sin(angle) * reach * SPREAD * 0.75
    glint.life = 0.6 + 0.8 * random()
    glint.scale = 0.5 + 0.7 * random()
    glint.angle = random() * 2 * pi
    glint.turn = (random() - 0.5) * 2
    glint.age = now and 0 or -0.6 * random()
end

local function animate(self, elapsed)
    if elapsed > 0.1 then elapsed = 0.1 end   -- pas de saut après un gel d'image
    sparkle.appear = approach(sparkle.appear, 1, elapsed / FADE_IN)
    sparkle.ready = approach(sparkle.ready, sparkle.state == "ready" and 1 or 0, elapsed / BLEND_TIME)
    sparkle.locked = approach(sparkle.locked, sparkle.state == "locked" and 1 or 0, elapsed / BLEND_TIME)

    local ready, locked = sparkle.ready, sparkle.locked
    -- plus terne et plus calme hors de portée, gris et lent sur un objet verrouillé
    local alpha = sparkle.appear * lerp(0.55, 1, ready) * (1 - 0.55 * locked)
    local speed = lerp(0.8, 1.2, ready) * (1 - 0.5 * locked)
    local r = lerp(GOLD[1], GREY[1], locked)
    local g = lerp(GOLD[2], GREY[2], locked)
    local b = lerp(GOLD[3], GREY[3], locked)

    for _, glint in ipairs(sparkle.glints) do
        glint.age = glint.age + elapsed * speed
        if glint.age >= glint.life then respawn(glint) end
        local shine = glint.age > 0 and sin(pi * glint.age / glint.life) or 0
        local texture = glint.texture
        texture:SetPoint("CENTER", self, "CENTER", glint.x, glint.y + 10 * max(glint.age, 0))
        local size = max(GLINT_SIZE * glint.scale * (0.35 + 0.65 * shine), 0.01)
        texture:SetSize(size, size)
        texture:SetRotation(glint.angle + glint.turn * max(glint.age, 0))
        texture:SetVertexColor(r, g, b, min(alpha * shine, 1))
    end
end

local function createSparkle()
    local frame = CreateFrame("Frame")
    frame:SetSize(1, 1)
    frame:Hide()
    sparkle.glints = {}
    for i = 1, GLINT_COUNT do
        local texture = frame:CreateTexture(nil, "OVERLAY")
        if texture:SetTexture(TEXTURE) == false then texture:SetTexture(FALLBACK_TEXTURE) end
        texture:SetBlendMode("ADD")
        texture:SetVertexColor(1, 1, 1, 0)
        if texture.SetSnapToPixelGrid then
            texture:SetSnapToPixelGrid(false)
            texture:SetTexelSnappingBias(0)
        end
        sparkle.glints[i] = { texture = texture }
    end
    frame:SetScript("OnUpdate", animate)
    sparkle.frame = frame
    return frame
end

local function release()
    if not sparkle.anchor then return end
    sparkle.frame:Hide()
    sparkle.frame:ClearAllPoints()
    sparkle.frame:SetParent(nil)
    sparkle.anchor, sparkle.retarget = nil, nil
end

local function attach(plate, state)
    local frame = sparkle.frame or createSparkle()
    frame:SetParent(plate)
    -- sous le contenu de la plaque : son texte reste lisible
    local ok, level = pcall(plate.GetFrameLevel, plate)
    if ok and level and not isSecret(level) then frame:SetFrameLevel(max(level - 1, 0)) end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", plate, "CENTER", 0, OFFSET_Y)
    frame:SetIgnoreParentAlpha(true)

    sparkle.anchor = plate
    sparkle.state, sparkle.pending = state, nil
    sparkle.ready = state == "ready" and 1 or 0
    sparkle.locked = state == "locked" and 1 or 0
    sparkle.appear = 0
    for _, glint in ipairs(sparkle.glints) do respawn(glint) end
    frame:Show()
end

-- Un nouvel état n'apparaît qu'une fois stable
local function proposeState(state)
    if state == sparkle.state then
        sparkle.pending = nil
        return
    end
    local now = GetTime()
    if sparkle.pending ~= state then
        sparkle.pending, sparkle.pendingSince = state, now
    elseif now - sparkle.pendingSince >= (state == "locked" and LOCK_DELAY or STATE_DELAY) then
        sparkle.pending = nil
        sparkle.state = state
        if state == "ready" then
            -- tous les éclats repartent d'un coup : la rafale « à portée »
            for _, glint in ipairs(sparkle.glints) do respawn(glint, true) end
        end
    end
end

-- Trouve la cible d'interaction, puis met d'accord la plaque de nom du jeu (allumée seulement pour un objet qui brille)
-- et l'étincelle
function evaluate()
    if not isActive() then
        release()
        return
    end
    -- en combat le jeu ne laisse pas changer la plaque : pas d'étincelle, elles reviennent après le combat
    if InCombatLockdown() then
        release()
        return
    end
    local unit, plate, unknown = resolveTarget()
    if not unit then
        setGate(unknown == true)   -- dans le doute, le jeu montre sa cible
        release()
        return
    end

    local category, blocked = classifyTarget(unit)
    local option = category and CATEGORY_KEYS[category]
    local wanted = option ~= nil and ns.db[option] == true
    setGate(wanted)
    if not wanted or not plate then
        -- sans plaque, elle vient d'être demandée : l'étincelle suit à son arrivée
        release()
        return
    end

    local state = readState(unit, blocked)
    if sparkle.anchor ~= plate or sparkle.retarget then
        release()
        attach(plate, state)
    else
        proposeState(state)
    end
end

---------------------------------------------------------------------------
-- Événements et options
---------------------------------------------------------------------------
local function refresh(force)
    if isActive() then
        applyCVars(force)
    else
        release()
        restoreCVars()
    end
end

local poller = CreateFrame("Frame")
poller:Hide()
local sinceCheck = 0
poller:SetScript("OnUpdate", function(_, elapsed)
    sinceCheck = sinceCheck + elapsed
    if sinceCheck >= POLL_INTERVAL then
        sinceCheck = 0
        evaluate()
    end
end)

local function updatePoller()
    poller:SetShown(isActive())
end

local handlers = {}

function handlers.PLAYER_LOGIN()
    lootApply()
    lootSchedule(5)   -- les réglages liés au compte peuvent arriver après la connexion et écraser le CVar
    if isActive() then
        applyCVars()
    else
        restoreCVars()   -- au cas où une coupure est restée en attente (combat, fermeture du jeu)
    end
    updatePoller()
end
-- Les réglages liés au compte peuvent arriver après PLAYER_LOGIN et écraser les nôtres
handlers.VARIABLES_LOADED = function()
    lootApply()
    if isActive() then applyCVars() end
end
handlers.PLAYER_ENTERING_WORLD = handlers.VARIABLES_LOADED

-- Les CVars ne changent pas en combat : on ferme la plaque juste avant. Laissée ouverte, chaque cadavre à piller
-- garderait une plaque à 0 % de vie jusqu'à la fin du combat ; le prix : pas d'étincelle en combat.
function handlers.PLAYER_REGEN_DISABLED()
    if isActive() then setGate(false) end
end

function handlers.PLAYER_REGEN_ENABLED()
    if loot.pendingCombat then
        loot.pendingCombat = false
        lootApply()
    end
    if pendingCVars == "apply" then
        applyCVars(pendingForce)
    elseif pendingCVars == "restore" then
        restoreCVars()
    end
    pendingCVars, pendingForce = false, false
    evaluate()
end

function handlers.CVAR_UPDATE(name)
    if not loot.applying and ns.db.sparkleLoot and type(name) == "string" and LOOT_WATCHED[name:lower()] then
        lootSchedule(1)
    end
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
    activeUnits[unit] = true
    evaluate()
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
    activeUnits[unit] = nil
    local plate = getNamePlate(unit)
    if plate and plate == sparkle.anchor then release() end
end

function handlers.PLAYER_SOFT_INTERACT_CHANGED(oldTarget, newTarget)
    -- une plaque recyclée d'une cible à la suivante ne montre pas le changement toute seule
    if not isSecret(oldTarget) and not isSecret(newTarget) and oldTarget and newTarget and oldTarget ~= newTarget then
        sparkle.retarget = sparkle.anchor ~= nil
    end
    evaluate()
end

function handlers.QUEST_LOG_UPDATE()
    questsDirty = true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if ns.db and handlers[event] then handlers[event](...) end
end)

---------------------------------------------------------------------------
-- Diagnostic (/pp etincelles)
---------------------------------------------------------------------------
local function onoff(v)
    return v and "|cff00ff00ON|r" or "|cffff4040OFF|r"
end

function Sparkles:Status()
    local db = ns.db
    local lines = {}
    lines[#lines + 1] = ns.Tf("étincelle de butin du jeu (objets de quête) : %s (%s = %s)",
        onoff(db.sparkleLoot), LOOT_CVAR, tostring(cvarGet(LOOT_CVAR)))
    lines[#lines + 1] = ns.Tf("à l'approche : plantes %s, objets de quête %s, cadavres avec du butin %s",
        onoff(db.sparkleHerbs), onoff(db.sparkleQuestObjects), onoff(db.sparkleCorpses))
    lines[#lines + 1] = ns.Tf("réglages du jeu : touche d'interaction %s, portée %s, arc %s, seulement à portée %s, plaques d'objets %s, plaque de la cible %s",
        tostring(cvarGet("SoftTargetInteract")), tostring(cvarGet("SoftTargetInteractRange")),
        tostring(cvarGet("SoftTargetInteractArc")), tostring(cvarGet("SoftTargetInteractOnlyInRange")),
        tostring(cvarGet("SoftTargetIconGameObject")), tostring(cvarGet("SoftTargetNameplateInteract")))
    if not isActive() then
        lines[#lines + 1] = ns.T("aucune étincelle à l'approche n'est allumée : rien n'est lu")
        return lines
    end
    if InCombatLockdown() then
        lines[#lines + 1] = ns.T("en combat : pas d'étincelle avant la fin du combat")
        return lines
    end
    local unit, plate, unknown = resolveTarget()
    if not unit then
        lines[#lines + 1] = unknown and ns.T("cible d'interaction : illisible (valeurs secrètes ?)")
            or ns.T("cible d'interaction : aucune (rien à portée du jeu)")
        return lines
    end
    local category, blocked = classifyTarget(unit)
    lines[#lines + 1] = ns.Tf("cible d'interaction : %s, catégorie : %s, %s, %s, étincelle : %s",
        tostring(call("UnitName", unit) or "?"), ns.T(CATEGORY_LABELS[category or "other"] or tostring(category)),
        blocked and ns.T("curseur grisé") or ns.T("curseur normal"),
        plate and ns.T("plaque de nom présente") or ns.T("pas de plaque de nom"),
        sparkle.anchor and (sparkle.state or "?") or ns.T("non"))
    return lines
end

-- Pour les tests : où est accrochée l'étincelle et dans quel état
function Sparkles:Current()
    return sparkle.anchor, sparkle.state, sparkle.frame
end

function Sparkles:Evaluate()
    evaluate()
end

---------------------------------------------------------------------------
function Sparkles:Init()
    for _, event in ipairs({
        "PLAYER_LOGIN", "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "CVAR_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_SOFT_INTERACT_CHANGED",
        "QUEST_LOG_UPDATE",
    }) do
        pcall(events.RegisterEvent, events, event)   -- un événement inconnu de ce client est ignoré
    end

    loot.shown = ns.db.sparkleLoot == true
    ns:OnChange("sparkleLoot", lootChanged)
    for _, key in pairs(CATEGORY_KEYS) do
        ns:OnChange(key, function(_, value)
            refresh(value == true)
            updatePoller()
        end)
    end
    if IsLoggedIn and IsLoggedIn() then handlers.PLAYER_LOGIN() end
end
