-- Platyplus : fenêtre de menace (ns.Threat) : tous les mobs en combat avec le groupe, d'un coup d'oeil.
-- Une ligne par mob : marqueur de raid, nom, vie, qui le tient (toi / le nom de sa cible), ta menace en %, et une
-- couleur d'état (la logique de Plates.lua est réutilisée : Plates.ThreatKind, mêmes couleurs que les plates) :
--   safe = tu l'as (tank) / il ne te tape pas (DPS) · warn = tu es en train de le perdre / tu vas le prendre ·
--   loose = tu ne l'as plus (tank) / il te tape (DPS) · other = un autre tank le tient · none = pas de cible.
-- Énumération : plates (nameplate1..40), boss1-5, cible/focus/survol, cibles des membres du groupe ; dédoublonné par
-- GUID (keyOf) quand il est lisible ; sinon (UnitIsUnit secret entre jetons non comparables) un jeton autre qu'une plate
-- n'est gardé que s'il n'a pas de plate (C_NamePlate.GetNamePlateForUnit) et que UnitIsUnit ne le dit pas déjà pris.
-- Un mob d'inconnus (pas sur ta liste de menace, cible hors groupe) est écarté.
-- Vérifié dans le code de Forever (doc générée) : UnitDetailedThreatSituation / UnitThreatSituation / UnitHealth /
-- GetRaidTargetIndex rendent des valeurs SECRÈTES quand le jeu restreint la menace/la vie (instances) ; UnitName aussi
-- (identité) ; UnitIsUnit aussi (comparaison). Ici : vie = StatusBar:SetMinMaxValues/SetValue seulement, nom, %, cible =
-- SetText seulement, couleur = SetVertexColorFromBoolean ; aucun calcul sur un secret. Marqueur de raid secret : pas
-- d'icône (on ne peut pas savoir s'il y en a un). NON VÉRIFIÉ en jeu.
-- VÉRIFIÉ EN JEU le 2026-11-15 : ni cibler ni marquer depuis cette fenêtre. (1) Un bouton sécurisé type1 = "target" avec
-- unit = "nameplateN" ne fait rien (le même bouton avec unit = "player" cible bien le joueur) : le jeu refuse les jetons
-- de plate dans les boutons sécurisés. (2) SetRaidTarget appelé par l'addon est une action protégée (fenêtre « Platyplus
-- a été bloqué », pcall ne la rattrape pas). Ne pas réessayer. Ce qui reste possible : survol = infobulle + plate
-- entourée (Plates.Highlight).
-- Pas d'OnUpdate permanent : événements regroupés (0,2 s) + un petit ticker (0,5 s) seulement fenêtre affichée en combat.
local ADDON, ns = ...

local Threat = {}
ns.Threat = Threat

local NAME = "fenêtre de menace"      -- nom affiché par le garde-fou s'il coupe le module
local WIDTH, ROW_H, GAP = 380, 30, 3
local MAX_ROWS = 12
local BAR_TEX = "Interface\\AddOns\\Platyplus\\Media\\Bar"
local MARKERS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- danger d'abord (tank : ceux que tu n'as pas ; DPS : ceux qui te tapent : les genres de Plates sont déjà dans ce sens)
local RANK = { loose = 1, bool = 2, warn = 3, none = 4, other = 5, safe = 6 }
local NONE_COLOR = { 0.55, 0.55, 0.58 }

local frame, rows, emptyText, ticker
local inCombat, pending, hiding = false, false, false
local grace, graceToken = false, 0     -- ~3 s de grâce après le combat ; le jeton annule une grâce devenue caduque
local testMode = false
local dismissed = false                -- croix cliquée en combat : cachée jusqu'au prochain combat (réglage intact)
local lastKind = {}                    -- [clé du mob] = dernier genre (alerte « perdu »)
local seqOf = {}                       -- [clé du mob] = ordre d'arrivée
local nextSeq = 0
local previous = {}                    -- liste précédente { key=, unit= }
local guarded, guardedCall, applyLock
local hovered                          -- ligne survolée (infobulle + plate éclairée)

local function api(name) return rawget(_G, name) end
local function db(key) return ns.db and ns.db[key] end

local function isSecret(value)
    local test = rawget(_G, "issecretvalue")
    if type(test) ~= "function" then return false end
    local ok, result = pcall(test, value)
    return (not ok) or result == true
end

local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- vrai si lisible et vrai (un secret compte pour « non »)
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

local function plural(n, one, many) return n == 1 and one or many end

local function isTank()
    local P = ns.Plates
    if P and P.IsTank then return (P:IsTank()) and true or false end
    return false
end

---------------------------------------------------------------------------
-- Couleurs (celles des plates)
---------------------------------------------------------------------------
local function colorOf(kind)
    local P = ns.Plates
    if kind == "none" or not (P and P.Color) then return NONE_COLOR[1], NONE_COLOR[2], NONE_COLOR[3] end
    return P.Color(kind)
end

-- objet couleur d'un état : celui (mis en cache) de Plates, sinon créé à la volée
local function colorObject(kind)
    local P = ns.Plates
    local obj = P and P.ColorObject and P.ColorObject(kind)
    if obj ~= nil then return obj end
    local create = api("CreateColor")
    if type(create) ~= "function" then return nil end
    return create(colorOf(kind))
end

local function fromBoolean(tex, value, kindTrue, kindFalse)
    if not tex.SetVertexColorFromBoolean then return false end
    local ifTrue, ifFalse = colorObject(kindTrue), colorObject(kindFalse)
    if ifTrue == nil or ifFalse == nil then return false end
    return (pcall(tex.SetVertexColorFromBoolean, tex, value, ifTrue, ifFalse))
end

-- peint une texture blanche (ARTWORK) de la couleur de l'état
local function paintTexture(tex, e)
    if e.kind == "bool" then
        local tank = isTank()
        if not fromBoolean(tex, e.tanking, tank and "safe" or "loose", tank and "loose" or "safe") then
            tex:SetVertexColor(NONE_COLOR[1], NONE_COLOR[2], NONE_COLOR[3], 1)
        end
    else
        local r, g, b = colorOf(e.kind)
        tex:SetVertexColor(r, g, b, 1)
    end
end

---------------------------------------------------------------------------
-- Énumération des mobs
---------------------------------------------------------------------------
local function candidates()
    -- les plates d'abord : ce sont les jetons « de référence » pour le dédoublonnage
    local list = {}
    for i = 1, 40 do list[#list + 1] = "nameplate" .. i end
    for i = 1, 5 do list[#list + 1] = "boss" .. i end
    list[#list + 1] = "target"
    list[#list + 1] = "focus"
    list[#list + 1] = "mouseover"
    local raid = api("IsInRaid")
    local isRaid = type(raid) == "function" and yes(select(2, call(raid)))
    if isRaid then
        for i = 1, 40 do list[#list + 1] = "raid" .. i .. "target" end
    else
        for i = 1, 4 do list[#list + 1] = "party" .. i .. "target" end
    end
    list[#list + 1] = "pettarget"
    return list
end

-- true / false, ou nil quand le jeu ne répond pas (secret, refusé entre jetons non comparables)
local function sameUnit(a, b)
    local ok, r = call(api("UnitIsUnit"), a, b)
    if not ok or isSecret(r) then return nil end
    return r and true or false
end

local function isPlateToken(unit) return unit:find("^nameplate%d") ~= nil end

-- le mob de ce jeton a-t-il une plate ? (nil = on ne sait pas)
local function hasPlate(unit)
    local np = api("C_NamePlate")
    if type(np) ~= "table" or type(np.GetNamePlateForUnit) ~= "function" then return nil end
    local ok, plate = pcall(np.GetNamePlateForUnit, unit)
    if not ok or isSecret(plate) then return nil end
    return plate ~= nil
end

-- hostile, vivant, qui n'est pas un joueur, en combat (un secret sur « en combat » : on garde, le doute profite au mob)
-- 2e retour : raison du rejet (texte français traduit), nil pour un jeton qui n'existe pas (rien à signaler)
local function eligible(unit)
    local ok, exists = call(api("UnitExists"), unit)
    if not (ok and yes(exists)) then return false, nil end
    local okA, attack = call(api("UnitCanAttack"), "player", unit)
    if not (okA and yes(attack)) then return false, ns.T("pas attaquable") end
    local okP, player = call(api("UnitIsPlayer"), unit)
    if okP and yes(player) then return false, ns.T("joueur") end
    local okD, dead = call(api("UnitIsDead"), unit)
    if okD and yes(dead) then return false, ns.T("mort") end
    local okF, fighting = call(api("UnitAffectingCombat"), unit)
    if not okF then return false, ns.T("état de combat illisible") end
    if isSecret(fighting) then return true end
    if fighting then return true end
    return false, ns.T("pas en combat")
end

local function keyOf(unit)
    local ok, guid = call(api("UnitGUID"), unit)
    if ok and not isSecret(guid) and guid ~= nil then return "g:" .. tostring(guid) end
    return "t:" .. unit
end

-- vie en 0..1 (nil si secrète : tri par vie impossible pour ce mob)
local function healthFraction(unit)
    local okH, hp = call(api("UnitHealth"), unit)
    local okM, max = call(api("UnitHealthMax"), unit)
    if not (okH and okM) or isSecret(hp) or isSecret(max) then return nil end
    hp, max = tonumber(hp), tonumber(max)
    if not (hp and max and max > 0) then return nil end
    return hp / max
end

local function describe(unit)
    local e = { unit = unit }
    local P = ns.Plates
    if P and P.ThreatKind then
        local kind, status, tanking, scaled = P.ThreatKind(unit)
        e.kind, e.status, e.tanking, e.scaled = kind or "none", status, tanking, scaled
    else
        -- sans Plates : seulement ce qui est calculable (qui est la cible du mob)
        local ok, mine = call(api("UnitIsUnit"), unit .. "target", "player")
        if ok and not isSecret(mine) then e.kind = mine and "safe" or "none" else e.kind = "none" end
    end
    e.health = healthFraction(unit)
    return e
end

-- mob d'inconnus : pas sur ta liste de menace (genre « none ») et pas ciblé par un membre du groupe. Gardés : les jetons
-- boss, les cibles des membres/du familier ; un secret = on ne sait pas, le doute profite au mob.
local function stranger(unit, e)
    if e.kind ~= "none" then return false end
    if unit:find("^boss%d") or unit:find("^party%d") or unit:find("^raid%d") or unit == "pettarget" then return false end
    local target = unit .. "target"
    for _, name in ipairs({ "UnitInParty", "UnitInRaid" }) do
        local ok, r = call(api(name), target)
        if ok then
            if isSecret(r) then return false end
            if r then return false end
        end
    end
    return true
end

-- énumère, filtre et dédoublonne (sans toucher à la mémoire des mobs). report (facultatif) reçoit une entrée par jeton
-- existant : { unit =, why = raison du rejet ou nil, e = description si gardé } (pour /pp menace etat)
local function scan(report)
    local kept, seen = {}, {}
    for _, unit in ipairs(candidates()) do
        local isOk, why = eligible(unit)
        if report and not isOk and why then report[#report + 1] = { unit = unit, why = why } end
        if isOk then
            local key = keyOf(unit)
            local dup = false
            if key:sub(1, 2) == "g:" then
                dup = seen[key] == true
            elseif not isPlateToken(unit) then
                -- GUID illisible : on ne sait pas comparer deux jetons. Une plate existe -> le mob est déjà listé par nameplateN ;
                -- sinon on le compare aux autres jetons sans plate, et UnitIsUnit muet = on l'ignore (doute = doublon).
                if hasPlate(unit) then
                    dup = true
                else
                    for _, other in ipairs(kept) do
                        if other.key:sub(1, 2) ~= "g:" and not isPlateToken(other.unit) and sameUnit(unit, other.unit) ~= false then
                            dup = true
                            break
                        end
                    end
                end
            end
            if dup then
                if report then report[#report + 1] = { unit = unit, why = ns.T("doublon (déjà listé)") } end
            else
                local e = describe(unit)
                e.key = key
                if stranger(unit, e) then
                    if report then report[#report + 1] = { unit = unit, why = ns.T("inconnu (pas sur ta liste de menace)"), e = e } end
                else
                    seen[key] = true
                    kept[#kept + 1] = e
                    if report then report[#report + 1] = { unit = unit, e = e } end
                end
            end
        end
    end
    return kept
end

-- liste triée, filtrée et tronquée ; compte aussi total / perdus
local function collect()
    local kept = scan()
    -- ordre d'arrivée + alerte « perdu »
    local tank = isTank()
    local now = {}
    for _, e in ipairs(kept) do
        if not seqOf[e.key] then nextSeq = nextSeq + 1 seqOf[e.key] = nextSeq end
        e.seq = seqOf[e.key]
        local was = lastKind[e.key]
        -- pas d'alerte sur une clé de repli « t: » (jeton, pas un mob : il change de mob sans prévenir)
        e.justLost = tank and e.kind == "loose" and e.key:sub(1, 2) == "g:" and (was == "safe" or was == "warn")
        now[e.key] = e.kind
    end
    for key in pairs(seqOf) do if not now[key] then seqOf[key] = nil end end
    lastKind = now
    return kept
end

local function arrange(kept)
    local total, lost = #kept, 0
    for _, e in ipairs(kept) do if e.kind == "loose" then lost = lost + 1 end end
    local list = kept
    if db("threatOnlyLost") and isTank() then
        list = {}
        for _, e in ipairs(kept) do if e.kind ~= "safe" then list[#list + 1] = e end end
    end
    local mode = db("threatSort")
    table.sort(list, function(a, b)
        if mode == "health" then
            local ha, hb = a.health or 2, b.health or 2
            if ha ~= hb then return ha < hb end
        elseif mode ~= "arrival" then
            local ra, rb = RANK[a.kind] or 4, RANK[b.kind] or 4
            if ra ~= rb then return ra < rb end
        end
        return a.seq < b.seq
    end)
    local max = clamp(db("threatRows"), 3, MAX_ROWS, 8)
    while #list > max do list[#list] = nil end
    return list, total, lost
end

---------------------------------------------------------------------------
-- Survol, infobulle, marqueur
---------------------------------------------------------------------------
local HOLDER_COLOR = { 0.72, 0.74, 0.78, 1 }

-- ce que montre la colonne « qui le tient » : (valeur, à toi ?). valeur = texte, texte secret, ou "-"
local function holderValue(e)
    if e.test then return (e.holderMine and ns.T(e.holder or "") or e.holder or ""), e.holderMine == true end
    if not isSecret(e.tanking) and e.tanking == true then return ns.T("toi"), true end
    local target = e.unit .. "target"
    local okE, exists = call(api("UnitExists"), target)
    if okE and not isSecret(exists) and not exists then return "-", false end
    if sameUnit(target, "player") == true then return ns.T("toi"), true end     -- cible lisible : c'est toi
    local ok, who = call(api("UnitName"), target)       -- possiblement secret : SetText / infobulle seulement
    if ok and (isSecret(who) or who ~= nil) then return who, false end
    return "-", false
end

-- l'état en clair selon ton rôle : texte, genre (couleur)
local function stateText(e)
    local kind = e.kind
    if kind == "bool" then return ns.T("Menace cachée par le jeu"), nil end
    if isTank() then
        if kind == "safe" then return ns.T("Tu le tiens"), kind end
        if kind == "warn" then return ns.T("Tu es en train de le perdre"), kind end
        if kind == "loose" then return ns.T("Il t'a échappé"), kind end
        if kind == "other" then return ns.T("Tenu par un autre tank"), kind end
        return ns.T("Il n'est pas sur ta liste de menace"), nil
    end
    if kind == "loose" then return ns.T("Il te tape"), kind end
    if kind == "warn" then return ns.T("Tu vas prendre l'aggro"), kind end
    return ns.T("Il ne te tape pas"), kind == "safe" and kind or nil
end

-- l'infobulle du jeu est PARTAGÉE : aucune valeur secrète n'y part (elle y laisserait un aspect secret) ;
-- une valeur cachée est remplacée par un texte fixe
local function tipLine(left, right, lr, lg, lb)
    if isSecret(right) or type(right) ~= "string" then right = ns.T("caché par le jeu") end
    pcall(GameTooltip.AddDoubleLine, GameTooltip, left, right, lr, lg, lb, 1, 1, 1)
end

local function showTip(row)
    local e = row.e
    if not e or not frame then return end
    local right, screen = frame:GetRight(), UIParent:GetRight()
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if right and screen and right + 300 > screen then
        GameTooltip:SetPoint("TOPRIGHT", frame, "TOPLEFT", -6, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
    end
    local name = e.name
    if not e.test then
        local ok, n = call(api("UnitName"), e.unit)
        name = ok and n or nil
    end
    if isSecret(name) or type(name) ~= "string" then name = ns.T("Mob") end
    GameTooltip:SetText(name, 1, 1, 1)
    local frac = e.test and (e.hp or 0) / 100 or healthFraction(e.unit)
    if frac then GameTooltip:AddLine(ns.Tf("Vie : %d%%", frac * 100 + 0.5), 0.7, 0.72, 0.76) end
    local who, mine = holderValue(e)
    tipLine(ns.T("Attaque :"), who, 0.7, 0.72, 0.76)
    local text, kind = stateText(e)
    local r, g, b = 0.8, 0.8, 0.84
    if kind then r, g, b = colorOf(kind) end
    GameTooltip:AddLine(text, r, g, b, true)
    local v = e.scaled
    if isSecret(v) then
        tipLine(ns.T("Menace :"), nil, 0.7, 0.72, 0.76)      -- « caché par le jeu »
    elseif e.test and e.pct and e.pct ~= "" then
        tipLine(ns.T("Menace :"), e.pct, 0.7, 0.72, 0.76)
    elseif type(v) == "number" then
        tipLine(ns.T("Menace :"), string.format("%d%%", v + 0.5), 0.7, 0.72, 0.76)
    end
    GameTooltip:Show()
end

local function lightPlate(row)
    local P = ns.Plates
    if not (P and P.Highlight) then return end
    local e = row and row.e
    pcall(P.Highlight, (e and not e.test) and e.unit or nil)
end

local function clearHover()
    local old = hovered
    hovered = nil
    if old then old.hoverTex:SetAlpha(0) end
    lightPlate(nil)
    if GameTooltip and GameTooltip.IsOwned and old and GameTooltip:IsOwned(old) then GameTooltip:Hide() end
end

local function enterRow(row)
    hovered = row
    row.hoverTex:SetAlpha(0.1)
    lightPlate(row)
    showTip(row)
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local function newRow(i)
    local W, C = ns.W, ns.W.C
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 2 * 12, ROW_H)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(ns.Win.HEAD_H + 8 + (i - 1) * (ROW_H + GAP)))
    row:EnableMouse(true)

    -- la vie du mob est le fond de la ligne : une StatusBar sur toute la largeur (piste sombre dessous, remplissage de la
    -- couleur d'état à faible opacité) ; tous les textes sont des régions de cette barre (au-dessus de son remplissage)
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetAllPoints(row)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetStatusBarColor(1, 1, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    row.bar = bar

    row.track = bar:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(bar)
    row.track:SetColorTexture(0, 0, 0, 0.45)

    row.stripe = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    row.stripe:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    row.stripe:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    row.stripe:SetWidth(4)
    row.stripe:SetColorTexture(1, 1, 1, 1)

    row.icon = bar:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", bar, "LEFT", 10, 0)
    row.icon:SetTexture(MARKERS)
    row.icon:Hide()

    row.name = W.Text(bar, "GameFontHighlight", C.text, "OVERLAY", 12)
    row.holder = W.Text(bar, "GameFontHighlight", HOLDER_COLOR, "OVERLAY", 11)
    row.pct = W.Text(bar, "GameFontHighlight", C.text, "OVERLAY", 12, "OUTLINE")
    -- colonnes de droite de largeur fixe : % (40) puis qui le tient (88) ; le nom prend le reste, sans les recouvrir
    row.pct:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    row.pct:SetWidth(40)
    row.pct:SetJustifyH("RIGHT")
    row.holder:SetPoint("RIGHT", row.pct, "LEFT", -6, 0)
    row.holder:SetWidth(88)
    row.holder:SetJustifyH("LEFT")
    if row.holder.SetWordWrap then row.holder:SetWordWrap(false) end
    row.name:SetPoint("LEFT", bar, "LEFT", 32, 0)
    row.name:SetPoint("RIGHT", row.holder, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    -- survol : la ligne s'éclaircit
    row.hoverTex = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    row.hoverTex:SetAllPoints(bar)
    row.hoverTex:SetColorTexture(1, 1, 1, 1)
    row.hoverTex:SetAlpha(0)

    row:SetScript("OnEnter", function(self) enterRow(self) end)
    row:SetScript("OnLeave", function(self) if hovered == self then clearHover() end end)

    -- éclat de l'alerte « perdu » : cadre à part (W.Animate prend son OnUpdate)
    row.flash = CreateFrame("Frame", nil, row)
    row.flash:SetAllPoints(row)
    row.flashTex = row.flash:CreateTexture(nil, "OVERLAY")
    row.flashTex:SetAllPoints(row.flash)
    row.flashTex:SetColorTexture(1, 0.15, 0.1, 1)
    row.flashTex:SetAlpha(0)
    row:Hide()
    return row
end

local function flashRow(row)
    if not db("threatFlash") then return end
    local W = ns.W
    W.Animate(row.flash, 1.2, function(_, p)
        row.flashTex:SetAlpha(0.55 * (1 - p))
    end, function() row.flashTex:SetAlpha(0) end)
end

local function setHolder(row, e)
    local C = ns.W.C
    local fs = row.holder
    local value, mine = holderValue(e)
    if not pcall(fs.SetText, fs, value) then fs:SetText("?") end
    ns.W.TextColor(fs, mine and C.good or HOLDER_COLOR)
end

local function setPercent(row, e)
    local fs = row.pct
    local C = ns.W.C
    if e.test then fs:SetText(e.pct or "") return end
    local v = e.scaled
    if isSecret(v) then
        local ok, text = pcall(string.format, "%d%%", v)
        if ok then fs:SetText(text) else fs:SetText("") end
    elseif v == nil then
        fs:SetText("")
    elseif type(v) == "number" then
        fs:SetText(string.format("%d%%", v + 0.5))
    else
        fs:SetText("")
    end
end

local function setMarker(row, e)
    local icon = row.icon
    local index = e.marker
    if not e.test then
        local ok, idx = call(api("GetRaidTargetIndex"), e.unit)
        if not ok or isSecret(idx) then index = nil else index = idx end   -- secret : pas d'icône (on ne sait pas s'il y en a un)
    end
    local set = api("SetRaidTargetIconTexture")
    if type(index) == "number" and index >= 1 and index <= 8 and type(set) == "function" then
        icon:SetTexture(MARKERS)
        set(icon, index)
        icon:Show()
    else
        icon:Hide()
    end
end

local function fillRow(row, e)
    local C = ns.W.C
    row.e = e
    -- bande pleine, remplissage de vie à faible opacité (même couleur d'état ; menace secrète : FromBoolean)
    paintTexture(row.stripe, e)
    local fill = row.bar:GetStatusBarTexture()
    if fill then
        paintTexture(fill, e)
        fill:SetAlpha(0.32)
    end
    setMarker(row, e)
    if e.test then
        row.name:SetText(e.name)
        row.bar:SetMinMaxValues(0, 100)
        row.bar:SetValue(e.hp)
    else
        local ok, name = call(api("UnitName"), e.unit)
        if ok and (isSecret(name) or name ~= nil) then
            if not pcall(row.name.SetText, row.name, name) then row.name:SetText("?") end
        else
            row.name:SetText("?")
        end
        local okM, max = call(api("UnitHealthMax"), e.unit)
        local okH, hp = call(api("UnitHealth"), e.unit)
        local done = false
        if okM and okH then      -- rien n'est comparé : secrets permis ici, StatusBar seulement
            done = pcall(row.bar.SetMinMaxValues, row.bar, 0, max) and pcall(row.bar.SetValue, row.bar, hp)
        end
        if not done then
            row.bar:SetMinMaxValues(0, 1)
            row.bar:SetValue(0)
        end
    end
    ns.W.TextColor(row.name, e.kind == "none" and C.dim or C.text)
    -- le % prend la couleur d'état (menace secrète : couleur du jeu impossible sur un texte, reste blanc)
    if e.kind and e.kind ~= "bool" and e.kind ~= "none" then
        local r, g, b = colorOf(e.kind)
        row.pct:SetTextColor(r, g, b)
    else
        ns.W.TextColor(row.pct, e.kind == "none" and C.dim or C.text)
    end
    setHolder(row, e)
    setPercent(row, e)
    if e.justLost then flashRow(row) end
end

-- pastilles du bandeau : « N mobs » (gris) et « N perdus » / « N sur toi » (couleur « loose »)
local function newPill(parent)
    local W, C = ns.W, ns.W.C
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(18)
    pill.shape = W.Round(pill, "BACKGROUND", 0, 8)
    pill.text = W.Text(pill, "GameFontHighlightSmall", C.dim, "OVERLAY", 11)
    pill.text:SetPoint("CENTER", pill, "CENTER", 0, 0)
    pill:Hide()
    return pill
end

local function setPill(pill, text, kind)
    local C = ns.W.C
    if not text then pill:Hide() return end
    pill.text:SetText(text)
    local chars = select(2, text:gsub("[^\128-\191]", ""))
    pill:SetWidth(chars * 6.3 + 18)
    if kind then
        local r, g, b = colorOf(kind)
        pill.shape:SetColor({ r, g, b }, 0.22)
        pill.text:SetTextColor(r, g, b)
    else
        pill.shape:SetColor(C.white, 0.08)
        ns.W.TextColor(pill.text, C.dim)
    end
    pill:Show()
end

local function summary(total, lost)
    if total == 0 then return nil, nil end
    local count = total == 1 and ns.Tf("%d mob", total) or ns.Tf("%d mobs", total)
    local lostText
    if lost > 0 then
        if isTank() then
            lostText = lost == 1 and ns.Tf("%d perdu", lost) or ns.Tf("%d perdus", lost)
        else
            lostText = ns.Tf("%d sur toi", lost)     -- DPS/soins : ceux qui te frappent
        end
    end
    return count, lostText
end

local function resize(n)
    local Win = ns.Win
    local body = n > 0 and (n * (ROW_H + GAP) - GAP) or 22
    frame:SetHeight(Win.HEAD_H + 8 + body + 14)
end

-- affiche la liste dans la fenêtre
local function render(list, total, lost)
    for i = 1, MAX_ROWS do
        local row = rows[i]
        local e = list[i]
        if e then
            -- une ligne qui échoue ne coupe pas les autres
            local ok, err = pcall(fillRow, row, e)
            if ok then
                row:Show()
            else
                row:Hide()
                if hovered == row then clearHover() end
                ns:Debug(NAME, ":", tostring(err))
            end
        else
            row:Hide()
            row.e = nil
            if hovered == row then clearHover() end
        end
    end
    local count, lostText = summary(total, lost)
    setPill(frame.pillTotal, count, nil)
    setPill(frame.pillLost, lostText, "loose")
    frame.pillLost:ClearAllPoints()
    frame.pillLost:SetPoint("LEFT", frame.pillTotal, "RIGHT", 6, 0)
    emptyText:SetShown(#list == 0)
    emptyText:SetText(total == 0 and ns.T("Aucun mob en combat") or ns.T("Tous tes mobs sont tenus."))
    resize(#list)
    -- la ligne survolée a changé de mob (tri, arrivée, départ) : infobulle et plate éclairée suivent
    if hovered and hovered.e then
        lightPlate(hovered)
        showTip(hovered)
    end
end

local TEST_LIST = {
    { name = "Gardien du portail", marker = 8, kind = "loose", hp = 62, holder = "Sylvara", pct = "0%" },
    { name = "Acolyte fanatique", marker = 7, kind = "warn", hp = 91, holder = "toi", holderMine = true, pct = "78%" },
    { name = "Brute en armure", marker = 1, kind = "safe", hp = 45, holder = "toi", holderMine = true, pct = "100%" },
    { name = "Rôdeur des ombres", kind = "other", hp = 100, holder = "Thorgrim", pct = "34%" },
    { name = "Seigneur de guerre Kar'thalas le Briseur d'os", kind = "warn", hp = 73, holder = "Sylvara", pct = "64%" },
    { name = "Chiot de meute", kind = "none", hp = 18, holder = "-", pct = "" },
}

local function testRows()
    local list, lost = {}, 0
    for i, t in ipairs(TEST_LIST) do
        local e = { test = true, seq = i }
        for k, v in pairs(t) do e[k] = v end
        e.tanking = e.kind == "safe"
        list[#list + 1] = e
        if e.kind == "loose" then lost = lost + 1 end
    end
    return list, #list, lost
end

---------------------------------------------------------------------------
-- Rafraîchissement
---------------------------------------------------------------------------
local function build()
    if frame then return frame end
    local W, C, Win = ns.W, ns.W.C, ns.Win
    frame = Win.Create("PlatyplusThreat", {
        title = "Menace", width = WIDTH, height = 120,
        posKey = "threatPos", scaleKey = "threatScale", corner = "TOPLEFT",
        default = { "TOPLEFT", "TOPLEFT", 40, -260 },
        onClose = function()
            local wasTest = testMode
            testMode = false
            if applyLock then applyLock() end
            if not wasTest then
                if db("threatAuto") then
                    dismissed = true          -- cachée jusqu'au prochain combat, le réglage ne bouge pas
                else
                    ns:Set("threatWindow", false)
                    return
                end
            end
            if Threat.Evaluate then Threat.Evaluate() end     -- (la croix ne cache pas elle-même : fondu via evaluate)
        end,
    })
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", frame.head, "LEFT", ns.Win.PAD, 0)
    frame.title:SetWidth(70)
    -- pastilles du résumé, à droite du titre
    frame.pillTotal = newPill(frame.head)
    frame.pillTotal:SetPoint("LEFT", frame.head, "LEFT", ns.Win.PAD + 78, 0)
    frame.pillLost = newPill(frame.head)
    frame.pillLost:SetPoint("LEFT", frame.pillTotal, "RIGHT", 6, 0)
    frame:SetScript("OnHide", function() clearHover() end)
    rows = {}
    for i = 1, MAX_ROWS do rows[i] = newRow(i) end
    emptyText = W.Text(frame, nil, C.dim, "OVERLAY", 12)
    emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -(Win.HEAD_H + 10))
    emptyText:SetJustifyH("LEFT")
    ticker = CreateFrame("Frame", nil, frame)
    frame.ticker = ticker
    if applyLock then applyLock() end
    return frame
end

-- le garde-fou (Resources.lib.guard) a-t-il coupé le module ?
local function isDisabled()
    local lib = ns.Resources and ns.Resources.lib
    return lib and lib.isDisabled and lib.isDisabled(NAME) and true or false
end

-- cache tout de suite, sans fondu, et arrête le ticker (fenêtre coincée à l'écran sinon)
local function hideNow()
    if not frame then return end
    clearHover()
    lastKind, seqOf = {}, {}
    if ticker then ticker:SetScript("OnUpdate", nil) end
    hiding = false
    frame:Hide()
    frame:SetAlpha(1)
end

local function update()
    if not (frame and frame:IsShown()) then return end
    if testMode then return render(testRows()) end
    render(arrange(collect()))
end

local function schedule()
    if pending then return end
    pending = true
    local timer = api("C_Timer")
    if timer and timer.After then
        timer.After(0.2, function()
            pending = false
            guarded()
        end)
    else
        pending = false
        guarded()
    end
end

-- ticker (vie des mobs...) : seulement fenêtre affichée et en combat
local function syncTicker()
    if not ticker then return end
    if frame:IsShown() and inCombat and not testMode then
        local acc = 0
        ticker:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc >= 0.5 then
                acc = 0
                guarded()
            end
        end)
    else
        ticker:SetScript("OnUpdate", nil)
    end
end

local function groupOk()
    if not db("threatGroupOnly") then return true end
    local fn = api("IsInGroup")
    return type(fn) == "function" and yes(select(2, call(fn)))
end

local function showWindow()
    build()
    if hiding then
        ns.W.StopAnimation(frame, false)
        frame:SetAlpha(1)
        hiding = false
    end
    if not frame:IsShown() then ns.Win.Open(frame) end
end

local function hideWindow(fade)
    if not (frame and frame:IsShown()) or hiding then return end
    if not fade then
        frame:Hide()
        return
    end
    hiding = true
    local W = ns.W
    W.Animate(frame, 0.3, function(self, p) self:SetAlpha(1 - W.Ease(p)) end, function(self)
        hiding = false
        self:Hide()
        self:SetAlpha(1)
        lastKind, seqOf = {}, {}
        syncTicker()
    end)
end

-- décide si la fenêtre doit être là, puis la met à jour
local function evaluate()
    if isDisabled() then
        if frame and frame:IsShown() then hideNow() end
        return
    end
    local want = testMode
    if not want and not dismissed and db("threatWindow") and groupOk() then
        want = (not db("threatAuto")) or inCombat or grace
    end
    if want then
        showWindow()
        update()
    elseif frame and frame:IsShown() then
        hideWindow(true)
    end
    if frame then syncTicker() end
end

Threat.Evaluate = evaluate

local function handle(event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat, grace, dismissed = true, false, false
        graceToken = graceToken + 1
        lastKind, seqOf = {}, {}     -- mémoire du combat précédent : pas de fausse alerte « perdu » sur un mob revu
        evaluate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if db("threatAuto") then
            -- reste ~3 s après la fin du combat, puis fondu
            grace = true
            graceToken = graceToken + 1
            local token = graceToken
            local function finish()
                if token ~= graceToken or inCombat then return end
                grace = false
                evaluate()
            end
            local timer = api("C_Timer")
            if timer and timer.After then timer.After(3, function() guardedCall(finish) end) else finish() end
        end
        evaluate()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        local ok, v = call(api("UnitAffectingCombat"), "player")
        inCombat = ok and yes(v)
        evaluate()
    elseif frame and frame:IsShown() and not testMode then
        if event == "NAME_PLATE_UNIT_REMOVED" and hovered then lightPlate(nil) end   -- (relancée par le rafraîchissement)
        schedule()            -- menace, plates, cibles, marqueurs : regroupés
    end
end

local EVENTS = {
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_TARGET", "PLAYER_TARGET_CHANGED", "RAID_TARGET_UPDATE",
    "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
}

---------------------------------------------------------------------------
-- Commande et réglages
---------------------------------------------------------------------------
function Threat:IsShown() return frame and frame:IsShown() and true or false end

-- aperçu avec des mobs factices (pour régler la position) ; rappelé : on l'arrête
function Threat:Test()
    if testMode then
        testMode = false
        applyLock()
        evaluate()
        return false
    end
    testMode = true
    showWindow()
    applyLock()
    update()
    syncTicker()
    return true
end

-- pourquoi la fenêtre n'est pas affichée (français : ns:Print le traduit), nil si les règles disent « affichée »
local function hiddenReason()
    if isDisabled() then return "coupée par le garde-fou après des erreurs (/pp menace on la relance)" end
    if testMode then return nil end
    if not db("threatWindow") then return "réglage éteint (/pp menace on)" end
    if dismissed then return "fermée par la croix jusqu'au prochain combat" end
    if not groupOk() then return "« Seulement en groupe » est coché et tu n'es pas en groupe" end
    if db("threatAuto") and not (inCombat or grace) then return "« Seulement en combat » est coché et tu n'es pas en combat" end
    return nil
end
Threat.HiddenReason = hiddenReason

-- /pp menace etat : pourquoi la fenêtre est là ou non, le rôle retenu, puis une ligne par jeton existant
function Threat:Status()
    local why = hiddenReason()
    if testMode then
        ns:Print("fenêtre de menace : aperçu factice affiché.")
    elseif why then
        ns:Print("fenêtre de menace : cachée -", why)
    else
        ns:Print("fenêtre de menace : affichée.")
    end
    local P = ns.Plates
    local tank, reason = false, ""
    if P and P.IsTank then tank, reason = P:IsTank() end
    ns:Print("rôle retenu :", tank and ns.T("tank") or ns.T("DPS/soins"), "-", tostring(reason or ""))     -- (reason : déjà traduit par IsTank)
    local report = {}
    local ok, err = pcall(scan, report)
    if not ok then ns:Print("lecture des mobs en erreur :", tostring(err)) return end
    if #report == 0 then ns:Print("aucun jeton de mob existant (rien en combat autour de toi).") return end
    for i, r in ipairs(report) do
        if i > 30 then ns:Print("  ...") break end
        local e = r.e
        local detail = ""
        if e then
            local status = isSecret(e.status) and "secret" or tostring(e.status)
            if e.kind == "bool" then status = "secret" end
            detail = ns.Tf("genre %s, statut %s", tostring(e.kind), status)
        end
        if r.why then
            ns:Print("  " .. r.unit .. " : " .. ns.Tf("écarté (%s)", r.why) .. (detail ~= "" and (" - " .. detail) or ""))
        else
            ns:Print("  " .. r.unit .. " : " .. ns.T("listé") .. " - " .. detail)
        end
    end
end

local function sayWhy()
    local why = hiddenReason()
    if why then ns:Print("fenêtre de menace : pas affichée -", why) end
end

function Threat:Command(arg)
    arg = strtrim(arg or ""):lower()
    if arg == "test" then
        if self:Test() then
            ns:Print("fenêtre de menace : mobs factices affichés (/pp menace test pour les retirer ; tire le bandeau pour la déplacer).")
        else
            ns:Print("fenêtre de menace : aperçu retiré.")
        end
        return
    end
    if arg == "etat" or arg == "état" or arg == "diag" or arg == "status" then
        self:Status()
        return
    end
    if arg == "on" or arg == "off" then
        ns:Set("threatWindow", arg == "on")
    elseif arg == "" or arg == "toggle" then
        ns:Set("threatWindow", not db("threatWindow"))
    elseif arg == "reset" then
        ns:Reset("threatPos")
        if frame then ns.Win.Place(frame) end
        ns:Print("fenêtre de menace remise à sa place.")
        return
    end
    ns:Print("fenêtre de menace :", db("threatWindow") and "allumée" or "éteinte",
        db("threatAuto") and "(seulement en combat)" or "(toujours visible)", "- rôle :", isTank() and "tank" or "DPS/soins")
    sayWhy()
end

-- (re)pose le verrou : tirer le bandeau ne déplace que si la fenêtre est déverrouillée
applyLock = function()
    if not frame then return end
    local head = frame.head
    -- l'aperçu (/pp menace test) sert à régler la position : toujours déplaçable
    if db("threatLocked") and not testMode then
        head:RegisterForDrag()
    else
        head:RegisterForDrag("LeftButton")
    end
end

function Threat:Init()
    local lib = ns.Resources and ns.Resources.lib
    guarded = function() update() end
    guardedCall = function(fn) fn() end
    if lib and lib.guard then
        -- après chaque appel : si le garde-fou a coupé le module, on cache la fenêtre (sinon elle reste figée à l'écran)
        local function watch(fn)
            return function(...)
                local r = fn(...)
                if isDisabled() and frame and frame:IsShown() then hideNow() end
                return r
            end
        end
        guarded = watch(lib.guard(NAME, guarded))
        guardedCall = watch(lib.guard(NAME, guardedCall))
    end
    local ev = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, event) end
    local onEvent = function(_, event) handle(event) end
    if lib and lib.guard then
        local inner = lib.guard(NAME, onEvent)
        onEvent = function(...)
            local r = inner(...)
            if isDisabled() and frame and frame:IsShown() then hideNow() end
            return r
        end
    end
    ev:SetScript("OnEvent", function(...) onEvent(...) end)
    Threat.events = ev
    local ok, v = call(api("UnitAffectingCombat"), "player")
    inCombat = ok and yes(v)
    ns:OnChange("threatWindow", function()
        if lib and lib.resetFailures then lib.resetFailures(NAME) end
        evaluate()
    end)
    for _, key in ipairs({ "threatAuto", "threatGroupOnly", "threatSort", "threatOnlyLost", "threatRows", "threatFlash" }) do
        ns:OnChange(key, function() evaluate() end)
    end
    ns:OnChange("threatLocked", function() applyLock() end)
    ns:OnChange("threatScale", function() if frame then ns.Win.Place(frame) end end)
    evaluate()
end
