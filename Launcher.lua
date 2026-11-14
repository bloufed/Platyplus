-- Platyplus : icône flottante et barre d'infos
--  * icône ronde posée où l'on veut sur l'écran (pas sur la minicarte) :
--    clic gauche = options, clic droit = menu rapide, glisser = déplacer (Maj + glisser si verrouillée)
--  * barre d'infos collée à l'icône : FPS, latence, or, places libres, durabilité, coordonnées, XP
--    (XP : pourcentage par défaut ; clic = XP/h, temps avant le niveau, monstres restants ; Maj + clic = nouvelle session)
--  * info-bulle : statistiques de la session (or gagné, XP par heure sur le temps actif, temps avant le niveau),
--    session gardée dans PlatyplusCharDB.launcherSession et reprise après un /reload
-- Optimisation : tout passe par les événements ; un seul ticker de 1 s, actif seulement quand la barre est
-- visible ET montre une valeur qui change sans événement (FPS, latence, coordonnées) ; OnUpdate seulement
-- pendant un glissement ; aucune table créée pendant les mises à jour ; menu créé au premier clic droit.
--
-- API du jeu (WoW Forever 1.60.1)
--  vérifiées : C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition (vector2:GetXY), GetInventoryAlertStatus (1 à 11),
--              UPDATE_INVENTORY_ALERTS, C_Container.GetContainerNumFreeSlots, BAG_UPDATE_DELAYED, GetMoney, PLAYER_MONEY
--  NON VÉRIFIÉES (toutes protégées : valeur retirée de la barre si absente, événement ignoré si inconnu) :
--              GetFramerate, GetNetStats, UnitXP, UnitXPMax, UnitLevel, GetXPExhaustion, IsPlayerAtEffectiveMaxLevel,
--              GetInventoryItemDurability, C_Map.GetMapInfo, ToggleAllBags, PLAYER_XP_UPDATE, PLAYER_LEVEL_UP,
--              UPDATE_INVENTORY_DURABILITY, PLAYER_EQUIPMENT_CHANGED, GLOBAL_MOUSE_DOWN, DISPLAY_SIZE_CHANGED,
--              UI_SCALE_CHANGED, PLAYER_LOGOUT, icônes de pièces Interface\MoneyFrame\UI-*Icon
--  doc Forever : QUEST_TURNED_IN (questID, xpReward, moneyReward), GetXPExhaustion (nil si pas reposé)
local ADDON, ns = ...

local Launcher = {}
ns.Launcher = Launcher

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local format, tostring, tonumber, type, pcall, ipairs = string.format, tostring, tonumber, type, pcall, ipairs

---------------------------------------------------------------------------
-- Mise en page
---------------------------------------------------------------------------
local BUTTON_SIZE = 30          -- zone cliquable de l'icône (à peine plus haute que la barre de 24 px)
local LOGO_SIZE = 32            -- le logo (tuile bleue) est le bouton : ni disque ni anneau ; la tuile fait ~26 px
local HOVER_GROW = 2            -- agrandissement au survol
local PRESS_SHRINK = 2          -- le logo s'enfonce pendant le clic
local SHADOW_SIZE = 46
local HALO_SIZE = 58

local DOCK_H = 24
local DOCK_GAP = 4              -- espace entre l'icône et la barre
local DOCK_PAD = 10             -- marge intérieure de la barre
local ITEM_GAP = 16             -- espace entre deux valeurs (le séparateur est au milieu)
local DOT_SIZE = 6
local DOT_SPACE = 10            -- pastille + espace avant le texte

local MENU_W = 214
local MENU_PAD = 6
local ROW_H = 22
local HEADER_H = 32

local TICK = 1                  -- secondes entre deux relevés (FPS, latence, coordonnées)
local SLOW_EVERY = 10           -- l'XP/h baisse avec le temps sans événement : relue tous les 10 relevés
-- XP/h = XP de la session / temps de jeu ACTIF (comme Titan Panel, XPBarNone, Experiencer, mais sans les pauses) :
local XP_IDLE = 5 * 60          -- une pause de plus de 5 min sans XP (ville, AFK) ne compte que pour 5 min
local XP_MIN_ACTIVE = 2 * 60    -- pas de taux avant 2 min de jeu actif (un monstre en 20 s donnerait 50k/h)
local SESSION_RESUME = 30 * 60  -- /reload ou reconnexion dans les 30 min : la session continue (PlatyplusCharDB)
local KILL_AVG = 10             -- XP par monstre : moyenne des 10 derniers
local QUEST_AVG = 5             -- XP par quête : moyenne des 5 dernières
local QUEST_MATCH = 1.5         -- QUEST_TURNED_IN et PLAYER_XP_UPDATE à moins de 1,5 s : le même gain
local XP_MODES = { "pct", "rate", "time", "kills" }   -- ce que la barre montre (clic = suivant)
local XP_MODE_SHORT = { pct = "%", rate = "XP/h", time = "temps", kills = "monstres" }
local MAX_ERRORS = 3            -- une valeur qui plante 3 fois est retirée de la barre
local BAG_LOW = 5
local DRAG_THROTTLE = 0.1       -- pendant un glissement, côté de la barre réévalué 10 fois par seconde
local CLICK_AFTER_DRAG = 0.2    -- un relâchement juste après un glissement n'est pas un clic

local BAG_FIRST = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0
local BAG_LAST = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"       -- NON VÉRIFIÉ sur Forever
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

local VALID_POINT = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local WARN = { 1.00, 0.65, 0.20 }
local XP_COLOR = { 0.72, 0.52, 1.00 }
local RESTED_COLOR = { 0.30, 0.60, 1.00 }   -- bleu de la barre d'XP reposée de Blizzard
local SWITCH_OFF = { 0.27, 0.29, 0.35 }
local KNOB_OFF = { 0.78, 0.80, 0.85 }
local BLACK = { 0, 0, 0 }
local WHITE = { 1, 1, 1 }

-- interrupteurs du menu rapide : { réglage, libellé }
local MENU_ENTRIES = {
    { "interact",       "Interaction rapide" },
    { "instantLoot",    "Loot instantané" },
    { "sellJunk",       "Vente auto" },
    { "autoQuest",      "Quêtes auto" },
    { "hud",            "Barre de ressource" },
    { "floatLoot",      "Flux de butin" },
    { "dock",           "Barre d'infos" },
    { "launcherLocked", "Verrouiller l'icône" },
}
local MENU_KEY = {}
for _, entry in ipairs(MENU_ENTRIES) do MENU_KEY[entry[1]] = true end

---------------------------------------------------------------------------
-- État
---------------------------------------------------------------------------
local T, MEDIA                  -- ns.THEME et ns.MEDIA, lus à l'Init
local GOOD, BAD, ACCENT
local HEX = {}                  -- couleurs du thème en |cff...

local button, dock, menu, menuHL, catcher, events, ticker
local menuRows = {}
local items, byName = {}, {}    -- valeurs de la barre, dans l'ordre d'affichage
local DOCK_KEY = {}
local dockActive, dockWidth, dockSide = false, 0, nil
local batching, dirty = false, false
local moving, dragEnd, dragElapsed = false, nil, 0
local hovering, pressed, suspend = false, false, false
local tickCount = 0
local globalMouse = nil         -- GLOBAL_MOUSE_DOWN : nil = pas encore essayé, false = refusé par le client

-- statistiques de la session (depuis la connexion ; continue après un /reload)
local session = {
    started = false, start = 0,     -- start en GetTime(), recalé à la reprise pour exclure le temps hors ligne
    money0 = 0, money = 0, gained = 0, spent = 0,
    xp = 0, xpMax = 0, level = 0, xpGained = 0,
    active = 0, lastGain = 0,       -- temps actif validé (s) et instant du dernier gain (GetTime)
    killXP = 0, questXP = 0,        -- XP de la session par monstres (et découvertes) / par quêtes
    kills = {}, quests = {},        -- derniers gains par monstre / par quête, pour les moyennes
    questPending = 0, questT = -100, lastKillT = -100,
}

Launcher.items = byName
Launcher.session = session

local layout, refreshDock, updateSide, updateTicker, refreshMenu   -- définies plus bas

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------
local function hex(c)
    return format("|cff%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

local function round(v) return floor(v + 0.5) end

-- 1234567 -> "1 234 567"
local function group(n)
    local s = tostring(floor(n))
    local k
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1 %2") until k == 0
    return s
end

-- 12.34 -> "12,3"
local function decimal(v)
    return (format("%.1f", v):gsub("%.", ","))
end

-- 12345 -> "12,3k"
local function compact(n)
    n = floor(n + 0.5)
    if n < 1000 then return tostring(n) end
    if n < 1000000 then return (decimal(n / 1000):gsub(",0$", "")) .. "k" end
    return (decimal(n / 1000000):gsub(",0$", "")) .. "M"
end

local function duration(sec)
    sec = floor((sec or 0) + 0.5)
    if sec < 60 then return "< 1 min" end
    local m = floor(sec / 60)
    if m < 60 then return m .. " min" end
    local h = floor(m / 60)
    if h > 99 then return "> 99 h" end
    return format("%d h %02d", h, m % 60)
end

-- short = barre d'infos : pas de cuivre dès qu'il y a de l'or, pas d'argent au-delà de 1000 po
local function coins(copper, short)
    copper = floor(abs(tonumber(copper) or 0))
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if g > 0 then
        if short then
            if g >= 1000 or s == 0 then return group(g) .. GOLD_ICON end
            return group(g) .. GOLD_ICON .. " " .. s .. SILVER_ICON
        end
        local text = group(g) .. GOLD_ICON
        if s > 0 then text = text .. " " .. s .. SILVER_ICON end
        if c > 0 then text = text .. " " .. c .. COPPER_ICON end
        return text
    end
    if s > 0 then
        if c > 0 then return s .. SILVER_ICON .. " " .. c .. COPPER_ICON end
        return s .. SILVER_ICON
    end
    return c .. COPPER_ICON
end

local function texture(parent, layer, sub, file, w, h)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(file)
    if w then t:SetSize(w, h or w) end
    return t
end

-- Cadre arrondi en 9 morceaux (coins nets quelle que soit la taille).
-- cut = part du coin dans l'image (Round : 0.25 ; Shadow : 0.375), edge = taille affichée du coin,
-- pad = débord autour du parent, dy = décalage vertical (ombre portée)
local function nineSlice(parent, layer, sub, file, cut, edge, pad, c, a, dy)
    pad, dy = pad or 0, dy or 0
    local box = {}
    local coord = { 0, cut, 1 - cut, 1 }
    for i = 1, 9 do
        local col, row = (i - 1) % 3, floor((i - 1) / 3)
        local t = parent:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(file)
        t:SetTexCoord(coord[col + 1], coord[col + 2], coord[row + 1], coord[row + 2])
        t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
        box[i] = t
    end
    local tl, tp, tr, lf, ct, rt, bl, bt, br = box[1], box[2], box[3], box[4], box[5], box[6], box[7], box[8], box[9]
    tl:SetSize(edge, edge)
    tr:SetSize(edge, edge)
    bl:SetSize(edge, edge)
    br:SetSize(edge, edge)
    tl:SetPoint("TOPLEFT", parent, "TOPLEFT", -pad, pad + dy)
    tr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", pad, pad + dy)
    bl:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -pad, -pad + dy)
    br:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", pad, -pad + dy)
    tp:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    tp:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    bt:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bt:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    lf:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    lf:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    rt:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
    rt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    ct:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
    ct:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    return box
end

-- Échelle de l'icône (et de la barre, qui en est l'enfant) par rapport à UIParent
local function relScale(frame)
    local ui = UIParent:GetEffectiveScale()
    if not ui or ui == 0 then return 1 end
    return (frame:GetEffectiveScale() or ui) / ui
end

-- Pose frame au-dessus ou en dessous de owner (côté le plus dégagé), alignée sur son bord gauche ou droit
local function attach(frame, owner, gap)
    frame:ClearAllPoints()
    local cx, cy = owner:GetCenter()
    if not cx then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    local s = relScale(owner)
    cx, cy = cx * s, cy * s
    local h = (cx > UIParent:GetWidth() / 2) and "RIGHT" or "LEFT"
    if cy > UIParent:GetHeight() / 2 then
        frame:SetPoint("TOP" .. h, owner, "BOTTOM" .. h, 0, -gap)
    else
        frame:SetPoint("BOTTOM" .. h, owner, "TOP" .. h, 0, gap)
    end
end

---------------------------------------------------------------------------
-- Info-bulles
---------------------------------------------------------------------------
local function tipTitle(text)
    GameTooltip:SetText(ns.T(text), T.accent[1], T.accent[2], T.accent[3])
end

local function tipPair(left, right, c)
    c = c or T.text
    GameTooltip:AddDoubleLine(ns.T(left), right, T.dim[1], T.dim[2], T.dim[3], c[1], c[2], c[3])
end

local function tipNote(text)
    GameTooltip:AddLine(ns.T(text), T.dim[1], T.dim[2], T.dim[3], true)
end

local function tipBlank()
    GameTooltip:AddLine(" ")
end

local function showTooltip(owner, fill, arg)
    if moving then return end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    attach(GameTooltip, owner, 6)
    local ok, err = pcall(fill, arg)
    if not ok then ns:Debug("info-bulle :", tostring(err)) end
    GameTooltip:Show()
end

local function hideTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Lectures du jeu (toutes protégées)
---------------------------------------------------------------------------
-- Fonction ou espace de noms du jeu facultatif : nil si ce client ne le connaît pas.
-- Lecture sous pcall (aucune allocation) : marche aussi avec un environnement strict sur les globales.
local G = _G
local function index(t, k) return t[k] end

local function api(name)
    local ok, v = pcall(index, G, name)
    if ok and type(v) == "function" then return v end
    return nil
end

local function apiTable(name)
    local ok, v = pcall(index, G, name)
    if ok and type(v) == "table" then return v end
    return nil
end

local function xpAvailable()
    return api("UnitXP") ~= nil and api("UnitXPMax") ~= nil
end

local function playerXP()
    local xp, xpMax = api("UnitXP"), api("UnitXPMax")
    if not (xp and xpMax) then return nil, nil end
    return tonumber(xp("player")) or 0, tonumber(xpMax("player")) or 0
end

local function playerLevel()
    local fn = api("UnitLevel")
    return fn and tonumber(fn("player")) or 0
end

local function atMaxLevel()
    local fn = api("IsPlayerAtEffectiveMaxLevel")
    if fn then
        local ok, v = pcall(fn)
        if ok and v ~= nil then return v and true or false end
    end
    local _, mx = playerXP()
    return not mx or mx <= 0
end

local function netStats()
    local bandIn, bandOut, home, world = api("GetNetStats")()
    return tonumber(bandIn) or 0, tonumber(bandOut) or 0, tonumber(home) or 0, tonumber(world) or 0
end

local function containerApi()
    local C = apiTable("C_Container")
    if C and type(C.GetContainerNumFreeSlots) == "function" then return C end
    return nil
end

local function mapApi()
    local C = apiTable("C_Map")
    if C and type(C.GetBestMapForUnit) == "function" and type(C.GetPlayerMapPosition) == "function" then return C end
    return nil
end

-- places libres / totales des sacs normaux, puis des sacs spéciaux (composants...)
local function bagCounts()
    local C = containerApi()
    local free, total, sfree, stotal = 0, 0, 0, 0
    for bag = BAG_FIRST, BAG_LAST do
        local f, family = C.GetContainerNumFreeSlots(bag)
        local n = C.GetContainerNumSlots and C.GetContainerNumSlots(bag) or 0
        f, n = tonumber(f) or 0, tonumber(n) or 0
        if not family or family == 0 then
            free, total = free + f, total + n
        else
            sfree, stotal = sfree + f, stotal + n
        end
    end
    if total == 0 and free == 0 and stotal > 0 then return sfree, stotal, 0, 0 end
    return free, total, sfree, stotal
end

-- lowest = durabilité de la pièce la plus usée (0 à 1, nil si inconnue),
-- worst = pire alerte d'équipement (0 bon, 1 va casser, 2 cassé ; nil si l'API manque)
local function durabilityState()
    local lowest
    local itemDurability = api("GetInventoryItemDurability")
    if itemDurability then
        for slot = 1, 19 do
            local cur, mx = itemDurability(slot)
            cur, mx = tonumber(cur), tonumber(mx)
            if cur and mx and mx > 0 then
                local p = cur / mx
                if not lowest or p < lowest then lowest = p end
            end
        end
    end
    local worst
    local alertStatus = api("GetInventoryAlertStatus")
    if alertStatus then
        worst = 0
        for i = 1, 11 do
            local a = tonumber(alertStatus(i)) or 0
            if a > worst then worst = a end
        end
    end
    return lowest, worst
end

local function playerCoords()
    local C = mapApi()
    if not C then return nil, nil, nil end
    local mapID = C.GetBestMapForUnit("player")
    if not mapID then return nil, nil, nil end
    local pos = C.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil, nil, mapID end
    local x, y
    if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or (x == 0 and y == 0) then return nil, nil, mapID end
    return x, y, mapID
end

local function coordText(x, y)
    local ix, iy = round(x * 1000), round(y * 1000)
    return format("%d,%d · %d,%d", floor(ix / 10), ix % 10, floor(iy / 10), iy % 10)
end

---------------------------------------------------------------------------
-- Session : or et XP depuis la connexion (reprise après un /reload ou une reconnexion rapide)
---------------------------------------------------------------------------
-- Ce que font Titan Panel [XP], XPBarNone ou Experiencer : XP/h = XP de la session / temps de la session,
-- temps avant le niveau = XP restante / XP/h, monstres restants = XP restante / XP d'un monstre.
-- Ici en mieux : le temps compté est le temps ACTIF (une pause sans XP compte au plus XP_IDLE : ville, AFK,
-- repas ne font plus s'écrouler le taux), la session survit au /reload, et l'XP des quêtes (QUEST_TURNED_IN)
-- est séparée de celle des monstres pour que « monstres restants » ne soit pas faussé par un rendu de quête.
local function wallClock()
    local fn = api("time")
    if not fn then return nil end
    local ok, v = pcall(fn)
    return ok and tonumber(v) or nil
end

local function charDB(create)
    local db = rawget(G, "PlatyplusCharDB")
    if type(db) ~= "table" then
        if not create then return nil end
        db = {}
        rawset(G, "PlatyplusCharDB", db)
    end
    return db
end

local function secret(v)
    local fn = api("issecretvalue")
    return fn ~= nil and fn(v) == true
end

-- copie d'une liste de nombres positifs (sauvegarde relue), limitée aux size derniers
local function numbers(list, size)
    local out = {}
    if type(list) == "table" then
        for i = 1, #list do
            local v = tonumber(list[i])
            if v and v > 0 then out[#out + 1] = v end
        end
    end
    while #out > size do table.remove(out, 1) end
    return out
end

local function addRecent(list, value, size)
    list[#list + 1] = value
    if #list > size then table.remove(list, 1) end
end

local function average(list)
    local n, sum = #list, 0
    if n == 0 then return nil end
    for i = 1, n do sum = sum + list[i] end
    return sum / n
end

local function elapsed()
    return GetTime() - session.start
end

-- temps de jeu actif : chaque intervalle entre deux gains d'XP compte au plus XP_IDLE
local function activeTime()
    return session.active + min(max(0, GetTime() - session.lastGain), XP_IDLE)
end

local SAVED_NUMBERS = { "elapsed", "active", "money0", "gained", "spent", "xpGained", "killXP", "questXP" }

-- session sauvegardée au /reload ou à la déconnexion, reprise si elle date de moins de SESSION_RESUME
local function savedSession()
    local db = charDB(false)
    local saved = db and db.launcherSession
    if type(saved) ~= "table" then return nil end
    local now, at = wallClock(), tonumber(saved.savedAt)
    if not now or not at or now < at or now - at > SESSION_RESUME then return nil end
    for _, k in ipairs(SAVED_NUMBERS) do
        if not tonumber(saved[k]) then return nil end
    end
    return saved
end

local function saveSession()
    if not session.started then return end
    local db = charDB(true)
    local now = wallClock()
    if not now then
        db.launcherSession = nil
        return
    end
    db.launcherSession = {
        savedAt = now, elapsed = elapsed(), active = activeTime(),
        money0 = session.money0, gained = session.gained, spent = session.spent,
        xpGained = session.xpGained, killXP = session.killXP, questXP = session.questXP,
        kills = session.kills, quests = session.quests,
    }
end

-- fresh = nouvelle session même si une sauvegarde récente existe (Maj + clic sur l'XP)
local function startSession(fresh)
    if session.started then return end
    session.started = true
    local now = GetTime()
    local money = tonumber(GetMoney()) or 0
    local cur, mx = playerXP()
    session.money = money
    session.xp, session.xpMax, session.level = cur or 0, mx or 0, playerLevel()
    session.lastGain, session.questPending, session.questT, session.lastKillT = now, 0, -100, -100
    local saved = not fresh and savedSession()
    session.resumed = saved and true or false
    if saved then
        session.start, session.active = now - tonumber(saved.elapsed), tonumber(saved.active)
        session.money0, session.gained, session.spent = tonumber(saved.money0), tonumber(saved.gained), tonumber(saved.spent)
        session.xpGained, session.killXP, session.questXP =
            tonumber(saved.xpGained), tonumber(saved.killXP), tonumber(saved.questXP)
        session.kills, session.quests = numbers(saved.kills, KILL_AVG), numbers(saved.quests, QUEST_AVG)
    else
        session.start, session.active = now, 0
        session.money0, session.gained, session.spent = money, 0, 0
        session.xpGained, session.killXP, session.questXP = 0, 0, 0
        session.kills, session.quests = {}, {}
    end
end

local function trackMoney()
    if not session.started then return end
    local money = tonumber(GetMoney()) or 0
    local delta = money - session.money
    if delta > 0 then
        session.gained = session.gained + delta
    elseif delta < 0 then
        session.spent = session.spent - delta
    end
    session.money = money
end

-- Montée de niveau : l'XP repart de zéro (baisse) ou le niveau et le palier changent ensemble.
-- Un état intermédiaire (niveau neuf, XP pas encore remise à jour) est ignoré sans rien retenir :
-- le relevé suivant voit encore l'ancien niveau et compte la montée une seule fois.
local function trackXP()
    if not session.started then return end
    local cur, mx = playerXP()
    if not cur then return end
    local level = playerLevel()
    if session.xpMax <= 0 then      -- XP pas encore connue à la connexion : simple point de départ
        session.xp, session.xpMax, session.level = cur, mx, level
        return
    end
    if level > session.level and cur == session.xp then return end
    local gain
    if cur < session.xp or (level > session.level and mx ~= session.xpMax) then
        gain = max(0, session.xpMax - session.xp) + cur
        session.level = level
    else
        gain = cur - session.xp
    end
    session.xp, session.xpMax = cur, mx
    if gain <= 0 then return end
    local now = GetTime()
    session.xpGained = session.xpGained + gain
    session.active = session.active + min(max(0, now - session.lastGain), XP_IDLE)
    session.lastGain = now
    -- quête rendue juste avant (QUEST_TURNED_IN arrivé en premier) : cette part est de l'XP de quête
    local quest = 0
    if session.questPending > 0 and now - session.questT <= QUEST_MATCH then
        quest = min(gain, session.questPending)
        if gain - quest < quest * 0.1 then quest = gain end     -- arrondis : pas de « monstre » de 3 XP
        session.questXP = session.questXP + quest
        addRecent(session.quests, quest, QUEST_AVG)
    end
    session.questPending = 0
    local rest = gain - quest
    if rest > 0 then                -- monstre (ou découverte d'une zone)
        session.killXP = session.killXP + rest
        addRecent(session.kills, rest, KILL_AVG)
        session.lastKillT = now
    end
end

-- QUEST_TURNED_IN (questID, xpReward, moneyReward). Ordre des deux événements inconnu : si le gain vient
-- d'être compté comme un monstre, on le reclasse ; sinon l'XP annoncée attend le PLAYER_XP_UPDATE suivant.
local function trackQuest(xpReward)
    if not session.started or secret(xpReward) then return end
    xpReward = tonumber(xpReward) or 0
    if xpReward <= 0 then return end
    local now = GetTime()
    local kills = session.kills
    local n = #kills
    -- même montant à 10 % près : c'est ce gain-là (un vrai monstre tué juste avant reste un monstre)
    if n > 0 and now - session.lastKillT <= QUEST_MATCH
        and kills[n] >= xpReward * 0.9 and kills[n] <= xpReward * 1.1 then
        local moved = table.remove(kills, n)
        session.killXP = max(0, session.killXP - moved)
        session.questXP = session.questXP + moved
        addRecent(session.quests, moved, QUEST_AVG)
        session.lastKillT = -100
    else
        session.questPending = session.questPending + xpReward
        session.questT = now
    end
end

-- montant par heure depuis le début de la session (nil pendant la première minute)
local function perHour(amount)
    if not session.started then return nil end
    local t = elapsed()
    if t < 60 or amount <= 0 then return nil end
    return amount / t * 3600
end

-- XP/h de la session sur le temps actif (nil avant XP_MIN_ACTIVE ou sans aucun gain)
local function xpPerHour()
    if not session.started or session.xpGained <= 0 then return nil end
    local t = activeTime()
    if t < XP_MIN_ACTIVE then return nil end
    return session.xpGained / t * 3600
end

local function xpLeft()
    local cur, mx = playerXP()
    if not cur or mx <= 0 then return nil end
    return max(0, mx - cur)
end

local function timeToLevel(rate)
    local left = xpLeft()
    if not left or not rate or rate <= 0 then return nil end
    return left / rate * 3600
end

-- monstres (ou quêtes) avant le niveau, d'après l'XP moyenne des derniers ; renvoie aussi cette moyenne
local function countToLevel(list)
    local left, avg = xpLeft(), average(list)
    if not left or not avg or avg <= 0 then return nil end
    return max(1, ceil(left / avg)), avg
end

local function restedXP()
    local fn = api("GetXPExhaustion")
    if not fn then return 0 end
    local ok, v = pcall(fn)
    return ok and tonumber(v) or 0
end

Launcher.xpPerHour = xpPerHour      -- pour les tests

local function xpMode()
    local m = ns.db.dockXpMode
    for _, v in ipairs(XP_MODES) do
        if v == m then return m end
    end
    return "pct"
end

local function tipSessionMoney()
    local net = (tonumber(GetMoney()) or 0) - session.money0
    tipPair("Or gagné", "+" .. coins(session.gained), GOOD)
    if session.spent > 0 then tipPair("Or dépensé", "-" .. coins(session.spent), BAD) end
    tipPair("Bilan", (net < 0 and "-" or "+") .. coins(net), net < 0 and BAD or GOOD)
    local rate = perHour(session.gained)
    if rate then tipPair("Or gagné par heure", coins(rate)) end
end

---------------------------------------------------------------------------
-- Valeurs de la barre d'infos
---------------------------------------------------------------------------
-- Nouveau texte (et couleur de pastille) d'une valeur. La largeur ne fait que grandir entre deux
-- réinitialisations : la barre ne tremble pas quand les FPS passent de 59 à 60.
local function setValue(item, text, color)
    if color and item.dotTex and color ~= item.color then
        item.color = color
        item.dotTex:SetVertexColor(color[1], color[2], color[3], 1)
    end
    if text == item.last then return end
    item.last = text
    item.text:SetText(text)
    local w = ceil(item.text:GetStringWidth() or 0) + (item.dotTex and DOT_SPACE or 0)
    if w > item.width then
        item.width = w
        if batching then dirty = true else layout() end
    end
end

local function labeled(item, value, valueHex)
    return HEX.dim .. ns.T(item.label) .. "|r " .. (valueHex or HEX.text) .. value .. "|r"
end

local function fpsColor(v)
    if v >= 50 then return GOOD elseif v >= 25 then return WARN end
    return BAD
end

local function latencyColor(v)
    if v <= 100 then return GOOD elseif v <= 250 then return WARN end
    return BAD
end

local function define(item)
    item.width, item.visible = 0, false
    items[#items + 1] = item
    byName[item.name] = item
    DOCK_KEY[item.key] = true
end

define({
    name = "fps", key = "dockFps", label = "FPS", title = "FPS", useDot = true, ticker = true,
    available = function() return api("GetFramerate") ~= nil end,
    update = function(item)
        local v = floor((tonumber(api("GetFramerate")()) or 0) + 0.5)
        if v == item.num then return end
        item.num = v
        setValue(item, labeled(item, tostring(v)), fpsColor(v))
    end,
    tip = function(item)
        tipTitle("Images par seconde")
        tipPair("Actuellement", tostring(item.num or 0) .. " FPS", item.color)
        tipNote("Fluidité de l'affichage. Vert : 50 et plus, orange : 25 à 49, rouge : moins de 25.")
    end,
})

define({
    name = "latency", key = "dockLatency", label = "MS", title = "Latence", useDot = true, ticker = true,
    available = function() return api("GetNetStats") ~= nil end,
    update = function(item)
        local _, _, home, world = netStats()
        local v = floor(max(home, world) + 0.5)
        if v == item.num then return end
        item.num = v
        setValue(item, labeled(item, tostring(v)), latencyColor(v))
    end,
    tip = function()
        local bandIn, bandOut, home, world = netStats()
        tipTitle("Latence")
        tipPair("Domicile", floor(home + 0.5) .. " ms", latencyColor(home))
        tipPair("Monde", floor(world + 0.5) .. " ms", latencyColor(world))
        tipPair("Bande passante", ns.Tf("%s / %s Ko/s", decimal(bandIn), decimal(bandOut)))
        tipNote("Domicile : discussion, hôtel des ventes. Monde : combat et autres joueurs. Vert jusqu'à 100 ms, orange jusqu'à 250 ms, rouge au-delà.")
    end,
})

define({
    name = "gold", key = "dockGold", title = "Or",
    available = function() return type(GetMoney) == "function" end,
    update = function(item)
        local money = tonumber(GetMoney()) or 0
        if money == item.num then return end
        item.num = money
        setValue(item, HEX.text .. coins(money, true) .. "|r")
    end,
    tip = function()
        tipTitle("Or")
        tipPair("Sur ce personnage", coins(GetMoney()))
        if session.started then
            tipBlank()
            tipSessionMoney()
        end
    end,
})

define({
    name = "bags", key = "dockBags", label = "Sacs", title = "Sacs", useDot = true,
    available = function() return containerApi() ~= nil end,
    update = function(item)
        local free = bagCounts()
        if free == item.num then return end
        item.num = free
        local low = free <= BAG_LOW
        setValue(item, labeled(item, tostring(free), low and HEX.bad or nil), low and BAD or (free <= 10 and WARN) or GOOD)
    end,
    tip = function()
        local free, total, sfree, stotal = bagCounts()
        tipTitle("Sacs")
        tipPair("Places libres", free .. " / " .. total, free <= BAG_LOW and BAD or nil)
        if stotal > 0 then tipPair("Sac de composants", sfree .. " / " .. stotal) end
        tipNote(ns.Tf("En rouge à %d places libres ou moins.", BAG_LOW))
        if api("ToggleAllBags") then tipNote("Clic : ouvrir les sacs") end
    end,
    click = function()
        local toggle = api("ToggleAllBags")
        if toggle then pcall(toggle) end
    end,
})

define({
    name = "durability", key = "dockDurability", label = "Dura", title = "Durabilité", useDot = true,
    available = function()
        return api("GetInventoryItemDurability") ~= nil or api("GetInventoryAlertStatus") ~= nil
    end,
    update = function(item)
        local lowest, worst = durabilityState()
        if lowest then
            local color = (lowest <= 0.2 or worst == 2) and BAD or (lowest <= 0.5 or worst == 1) and WARN or GOOD
            local value = lowest <= 0 and ns.T("cassé") or (floor(lowest * 100 + 0.5) .. " %")
            setValue(item, labeled(item, value, color == BAD and HEX.bad or nil), color)
        elseif worst then
            if worst >= 2 then
                setValue(item, labeled(item, ns.T("cassé"), HEX.bad), BAD)
            elseif worst == 1 then
                setValue(item, labeled(item, ns.T("faible"), HEX.warn), WARN)
            else
                setValue(item, labeled(item, ns.T("OK")), GOOD)
            end
        else
            setValue(item, labeled(item, "-", HEX.dim), T.dim)
        end
    end,
    tip = function(item)
        local lowest, worst = durabilityState()
        tipTitle("Durabilité")
        if lowest then tipPair("Pièce la plus usée", floor(lowest * 100 + 0.5) .. " %", item.color) end
        if worst and worst >= 2 then
            tipPair("État", ns.T("pièce cassée"), BAD)
        elseif worst == 1 then
            tipPair("État", ns.T("pièce bientôt cassée"), WARN)
        elseif worst then
            tipPair("État", ns.T("bon"), GOOD)
        end
        tipNote("Répare chez un marchand (Platyplus peut réparer tout seul : voir les options).")
    end,
})

-- niveau d'objet moyen de l'équipement porté (calcul de Tweaks : GetAverageItemLevel, sinon moyenne maison)
local function itemLevels()
    local fn = api("GetAverageItemLevel")
    local overall, equipped
    if type(fn) == "function" then
        local ok, a, b = pcall(fn)
        if ok then overall, equipped = tonumber(a), tonumber(b) end
    end
    if not equipped or equipped <= 0 then
        local tweaks = ns.Tweaks
        if tweaks and tweaks.AverageItemLevel then
            local ok, v = pcall(tweaks.AverageItemLevel, tweaks)
            if ok then equipped = tonumber(v) end
        end
    end
    if equipped and equipped <= 0 then equipped = nil end
    if overall and overall <= 0 then overall = nil end
    return equipped, overall
end

local function oneDecimal(v)
    return (format("%.1f", floor(v * 10 + 0.0001) / 10):gsub("%.", ","))
end

define({
    name = "ilvl", key = "dockIlvl", label = "iLvl", title = "Niveau d'objet", useDot = true, slow = true,
    available = function()
        return api("GetAverageItemLevel") ~= nil or (ns.Tweaks and ns.Tweaks.AverageItemLevel) ~= nil
    end,
    update = function(item)
        local v = itemLevels()
        local key = v and floor(v * 10 + 0.0001) or -1
        if key == item.num then return end
        item.num = key
        if v then
            setValue(item, labeled(item, oneDecimal(v), HEX.gold), T.gold)
        else
            setValue(item, labeled(item, "-", HEX.dim), T.dim)
        end
    end,
    tip = function()
        local equipped, overall = itemLevels()
        tipTitle("Niveau d'objet")
        tipPair("Équipement porté", equipped and oneDecimal(equipped) or "-", T.gold)
        if overall and equipped and floor(overall * 10) ~= floor(equipped * 10) then
            tipPair("Meilleur possible (avec tes sacs)", oneDecimal(overall))
        end
        tipNote("Moyenne du niveau d'objet de ce que tu portes. Plus il est haut, plus ton équipement est puissant.")
        if api("ToggleCharacter") then tipNote("Clic : ouvrir la fiche du personnage") end
    end,
    click = function()
        local toggle = api("ToggleCharacter")
        if toggle then pcall(toggle, "PaperDollFrame") end
    end,
})

define({
    name = "coords", key = "dockCoords", label = "XY", title = "Coordonnées", useDot = true, ticker = true,
    available = function()
        return mapApi() ~= nil
    end,
    update = function(item)
        local x, y = playerCoords()
        local key = x and (round(x * 1000) * 10000 + round(y * 1000)) or -1
        if key == item.num then return end
        item.num = key
        if x then
            setValue(item, labeled(item, coordText(x, y)), ACCENT)
        else
            setValue(item, labeled(item, "-", HEX.dim), T.dim)
        end
    end,
    tip = function()
        local x, y, mapID = playerCoords()
        tipTitle("Coordonnées")
        local C = mapApi()
        if mapID and C and type(C.GetMapInfo) == "function" then
            local ok, info = pcall(C.GetMapInfo, mapID)
            if ok and type(info) == "table" and info.name then tipPair("Carte", tostring(info.name)) end
        end
        tipPair("Position", x and coordText(x, y) or ns.T("indisponible"))
        tipNote("Position de ton personnage sur la carte de la zone (de 0 à 100). Indisponible dans certaines instances.")
    end,
})

-- texte de la barre selon le mode choisi (clic sur l'XP = mode suivant)
local function xpBarText()
    local mode = xpMode()
    local label, value
    if mode == "rate" then
        local rate = xpPerHour()
        label, value = ns.T("XP/h"), rate and compact(rate)
    elseif mode == "time" then
        local rate = xpPerHour()
        local left = rate and timeToLevel(rate)
        label, value = ns.T("Niv. dans"), left and duration(left)
    elseif mode == "kills" then
        local n = countToLevel(session.kills)
        label, value = ns.T("Mobs"), n and ("~" .. group(n))
    else
        local cur, mx = playerXP()
        label, value = ns.T("XP"), (mx and mx > 0) and (oneDecimal(cur / mx * 100) .. " %")
    end
    return HEX.dim .. label .. "|r " .. (value and (HEX.text .. value) or (HEX.dim .. "-")) .. "|r"
end

-- « % · XP/h · temps · monstres », le mode affiché en clair
local function xpModesLine()
    local mode, parts = xpMode(), {}
    for i, m in ipairs(XP_MODES) do parts[i] = (m == mode and HEX.text or HEX.dim) .. ns.T(XP_MODE_SHORT[m]) .. "|r" end
    return table.concat(parts, HEX.dim .. " · |r")
end

define({
    name = "xp", key = "dockXp", label = "XP", title = "Expérience", useDot = true, slow = true,
    available = xpAvailable,
    hidden = atMaxLevel,
    update = function(item)
        setValue(item, xpBarText(), restedXP() > 0 and RESTED_COLOR or XP_COLOR)
    end,
    tip = function()
        local cur, mx = playerXP()
        local rested = restedXP()
        tipTitle("Expérience")
        if mx and mx > 0 then
            tipPair(ns.Tf("Niveau %d", tonumber(playerLevel()) or 0), group(cur) .. " / " .. group(mx) .. " (" .. oneDecimal(cur / mx * 100) .. " %)")
            tipPair("Reste", group(mx - cur) .. " XP")
            if rested > 0 then
                tipPair("Bonus de repos", ns.Tf("+%s (%d %% du niveau)", group(rested), floor(rested / mx * 100)),
                    RESTED_COLOR)
            end
        end
        local rate = session.started and xpPerHour()
        if session.started then
            tipBlank()
            tipPair("Gagnée cette session", group(session.xpGained) .. " XP")
            tipPair("Temps de jeu actif", duration(activeTime()))
            tipPair("Par heure", rate and group(rate) or "-", XP_COLOR)
            local left = rate and timeToLevel(rate)
            tipPair("Prochain niveau dans", left and duration(left) or "-")
            local kills, perKill = countToLevel(session.kills)
            if kills then tipPair("Monstres restants", ns.Tf("~%s (%s XP chacun)", group(kills), group(perKill))) end
            local quests, perQuest = countToLevel(session.quests)
            if quests then tipPair("Quêtes restantes", ns.Tf("~%s (%s XP chacune)", group(quests), group(perQuest))) end
            if session.questXP > 0 then
                tipPair("Monstres / quêtes", floor(session.killXP / session.xpGained * 100 + 0.5) .. " % / "
                    .. floor(session.questXP / session.xpGained * 100 + 0.5) .. " %")
            end
        end
        tipBlank()
        if session.started and not rate then tipNote("L'XP par heure apparaît après 2 minutes de jeu.") end
        tipNote("Calcul sur le temps de jeu actif : une pause de plus de 5 min sans XP (ville, AFK) ne compte que pour 5 min. La session continue après un /reload.")
        tipNote(ns.Tf("%sClic|r : %s", HEX.gold, xpModesLine()))
        tipNote(ns.Tf("%sMaj + clic|r : nouvelle session", HEX.gold))
    end,
    click = function(item)
        if IsShiftKeyDown() then
            Launcher:ResetSession()
            ns:Print("nouvelle session : XP et or de la session remis à zéro")
        else
            local mode, nextMode = xpMode(), XP_MODES[1]
            for i, m in ipairs(XP_MODES) do
                if m == mode then nextMode = XP_MODES[i % #XP_MODES + 1] end
            end
            ns:Set("dockXpMode", nextMode)
        end
        if item.frame and GameTooltip:IsOwned(item.frame) then showTooltip(item.frame, item.tip, item) end
    end,
})

-- La valeur doit-elle apparaître dans la barre ?
local function wanted(item)
    local db = ns.db
    if not (db.launcher and db.dock and db[item.key]) then return false end
    if item.broken or not item.available() then return false end
    if item.hidden and item.hidden() then return false end
    return true
end

-- Met une valeur à jour sous protection : une API qui plante 3 fois retire la valeur de la barre.
local function safeUpdate(item)
    local ok, err = pcall(item.update, item)
    if ok then return end
    item.errors = (item.errors or 0) + 1
    ns:Debug("barre d'infos (" .. item.name .. ") :", tostring(err))
    if item.errors >= MAX_ERRORS and not item.broken then
        item.broken = true
        ns:Print(ns.Tf("barre d'infos : « %s » retiré après des erreurs répétées", ns.T(item.title)))
        C_Timer.After(0, function() refreshDock() end)
    end
end

local function refreshItem(item)
    if item and item.visible and dockActive then safeUpdate(item) end
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local registered, unknownEvent = {}, {}

local function setEvent(event, want)
    want = want and true or false
    if unknownEvent[event] or (registered[event] or false) == want then return end
    if want then
        if pcall(events.RegisterEvent, events, event) then
            registered[event] = true
        else
            unknownEvent[event] = true
            ns:Debug("événement inconnu de ce client :", event)
        end
    else
        pcall(events.UnregisterEvent, events, event)
        registered[event] = false
    end
end

-- les événements de la barre ne sont écoutés que si la valeur correspondante est affichée
local function syncEvents()
    local bags = dockActive and byName.bags.visible
    local dura = dockActive and byName.durability.visible
    local ilvl = dockActive and byName.ilvl.visible
    setEvent("BAG_UPDATE_DELAYED", bags)
    setEvent("UPDATE_INVENTORY_ALERTS", dura)
    setEvent("UPDATE_INVENTORY_DURABILITY", dura)
    setEvent("PLAYER_EQUIPMENT_CHANGED", dura or ilvl)
    setEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE", ilvl)
end

---------------------------------------------------------------------------
-- Ticker unique (FPS, latence, coordonnées ; XP/h une fois sur 10)
---------------------------------------------------------------------------
local function tick()
    if not dockActive then return end
    tickCount = tickCount + 1
    local slow = tickCount % SLOW_EVERY == 0
    for _, item in ipairs(items) do
        if item.visible and (item.ticker or (slow and item.slow)) then safeUpdate(item) end
    end
end

updateTicker = function()
    local want = false
    if dockActive and dock and dock:IsVisible() then
        for _, item in ipairs(items) do
            if item.visible and item.ticker then
                want = true
                break
            end
        end
        -- XP/h et temps avant le niveau bougent sans événement (pauses) : relus toutes les 10 s
        local mode = xpMode()
        if byName.xp.visible and (mode == "rate" or mode == "time") then want = true end
    end
    if want and not ticker then
        ticker = C_Timer.NewTicker(TICK, tick)
        Launcher.ticker = ticker
    elseif not want and ticker then
        ticker:Cancel()
        ticker = nil
        Launcher.ticker = nil
    end
end

---------------------------------------------------------------------------
-- Position de l'icône
---------------------------------------------------------------------------
local function launcherScale()
    local s = tonumber(ns.db.launcherScale) or 1
    if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
    return s
end

local function applyScale()
    button:SetScale(launcherScale())
end

-- Les décalages sont sauvegardés en unités d'UIParent : changer l'échelle ne déplace pas le coin d'ancrage.
local function place()
    local point = ns.db.launcherPoint
    if not VALID_POINT[point] then point = "TOPRIGHT" end
    local s = launcherScale()
    button:ClearAllPoints()
    button:SetPoint(point, UIParent, point, (tonumber(ns.db.launcherX) or 0) / s, (tonumber(ns.db.launcherY) or 0) / s)
end

-- Après un glissement : ancrage sur le coin / bord d'écran le plus proche (tiers de l'écran),
-- pour que l'icône reste au même endroit si la résolution change.
local function savePosition()
    local l, r, t, b = button:GetLeft(), button:GetRight(), button:GetTop(), button:GetBottom()
    if not (l and r and t and b) then return end
    local s = relScale(button)
    l, r, t, b = l * s, r * s, t * s, b * s
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = (l + r) / 2, (t + b) / 2
    local h, x, v, y
    if cx < W / 3 then
        h, x = "LEFT", l
    elseif cx > W * 2 / 3 then
        h, x = "RIGHT", r - W
    else
        h, x = "", cx - W / 2
    end
    if cy > H * 2 / 3 then
        v, y = "TOP", t - H
    elseif cy < H / 3 then
        v, y = "BOTTOM", b
    else
        v, y = "", cy - H / 2
    end
    local point = v .. h
    if point == "" then point = "CENTER" end
    suspend = true
    ns:Set("launcherPoint", point)
    ns:Set("launcherX", round(x))
    ns:Set("launcherY", round(y))
    suspend = false
    place()
    updateSide()
end

-- La barre se colle à droite de l'icône, ou à gauche s'il n'y a pas la place.
updateSide = function()
    if not dock or not dockActive then return end
    local side = "RIGHT"
    local l, r = button:GetLeft(), button:GetRight()
    if l and r then
        local s = relScale(button)
        local need = (dockWidth + DOCK_GAP) * s
        local roomRight = UIParent:GetWidth() - r * s
        local roomLeft = l * s
        if roomRight < need and roomLeft > roomRight then side = "LEFT" end
    end
    if side == dockSide then return end
    dockSide = side
    Launcher.dockSide = side
    dock:ClearAllPoints()
    if side == "RIGHT" then
        dock:SetPoint("LEFT", button, "RIGHT", DOCK_GAP, 0)
    else
        dock:SetPoint("RIGHT", button, "LEFT", -DOCK_GAP, 0)
    end
end

---------------------------------------------------------------------------
-- Glisser
---------------------------------------------------------------------------
local function onDragUpdate(_, dt)
    dragElapsed = dragElapsed + (dt or 0)
    if dragElapsed < DRAG_THROTTLE then return end
    dragElapsed = 0
    updateSide()
end

local function startDrag()
    if moving or not button:IsShown() then return end
    if ns.db.launcherLocked and not IsShiftKeyDown() then return end
    moving = true
    Launcher:HideMenu()
    hideTooltip(button)
    if GameTooltip:IsShown() then GameTooltip:Hide() end
    button:StartMoving()
    dragElapsed = 0
    button:SetScript("OnUpdate", onDragUpdate)
end

local function stopDrag()
    dragEnd = GetTime()     -- même refusé (icône verrouillée), un glissement ne doit pas finir en clic
    if not moving then return end
    moving = false
    button:SetScript("OnUpdate", nil)
    button:StopMovingOrSizing()
    if button.SetUserPlaced then button:SetUserPlaced(false) end   -- c'est Platyplus qui sauvegarde la position
    savePosition()
end

---------------------------------------------------------------------------
-- Icône
---------------------------------------------------------------------------
local function setLook()
    local v = button.visual
    local grow = hovering and HOVER_GROW or 0
    local logo = LOGO_SIZE + grow - (pressed and PRESS_SHRINK or 0)
    v.logo:SetSize(logo, logo)
    v.halo:SetAlpha(hovering and 0.6 or 0)
end

local function openOptions()
    local UI = ns.UI
    if UI and UI.Open then
        UI:Open()
    elseif UI and UI.Toggle then
        UI:Toggle()
    else
        ns:Print("interface indisponible")
    end
end

local function fillLauncherTip()
    GameTooltip:AddDoubleLine("|cff33ccffPlaty|r|cffffd133plus|r", "v" .. tostring(ns.version),
        1, 1, 1, T.dim[1], T.dim[2], T.dim[3])
    if session.started then
        tipBlank()
        tipPair("Session", duration(elapsed()))
        tipSessionMoney()
        if xpAvailable() and not atMaxLevel() then
            local rate = xpPerHour()
            tipPair("XP par heure", rate and compact(rate) or "-", XP_COLOR)
            local left = rate and timeToLevel(rate)
            tipPair("Prochain niveau dans", left and duration(left) or "-")
        end
    end
    tipBlank()
    tipNote(ns.Tf("%sClic gauche|r : options", HEX.gold))
    tipNote(ns.Tf("%sClic droit|r : menu rapide", HEX.gold))
    if ns.db.launcherLocked then
        tipNote(ns.Tf("%sMaj + glisser|r : déplacer (icône verrouillée)", HEX.gold))
    else
        tipNote(ns.Tf("%sGlisser|r : déplacer", HEX.gold))
    end
end

local function createButton()
    local b = CreateFrame("Button", "PlatyplusLauncher", UIParent)
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(20)
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    if b.SetDontSavePosition then b:SetDontSavePosition(true) end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    button = b
    Launcher.button = b

    local v = {}
    v.shadow = texture(b, "BACKGROUND", -8, MEDIA .. "Glow", SHADOW_SIZE)
    v.shadow:SetPoint("CENTER", b, "CENTER", 0, -2)
    v.shadow:SetVertexColor(0, 0, 0, 0.8)
    v.halo = texture(b, "BACKGROUND", -6, MEDIA .. "Glow", HALO_SIZE)
    v.halo:SetPoint("CENTER", b, "CENTER", 0, 0)
    v.halo:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    v.halo:SetBlendMode("ADD")
    v.logo = texture(b, "ARTWORK", 0, ns.LOGO, LOGO_SIZE)
    v.logo:SetPoint("CENTER", b, "CENTER", 1, 1)   -- dans l'image, la tuile est décalée en bas à gauche (place du +)
    b.visual = v
    setLook()

    b:SetScript("OnEnter", function(self)
        hovering = true
        setLook()
        if not (menu and menu:IsShown()) then showTooltip(self, fillLauncherTip) end
    end)
    b:SetScript("OnLeave", function(self)
        hovering, pressed = false, false
        setLook()
        hideTooltip(self)
    end)
    b:SetScript("OnMouseDown", function()
        pressed = true
        setLook()
    end)
    b:SetScript("OnMouseUp", function()
        pressed = false
        setLook()
    end)
    b:SetScript("OnClick", function(self, mouse)
        if dragEnd and GetTime() - dragEnd < CLICK_AFTER_DRAG then return end
        hideTooltip(self)
        if mouse == "RightButton" then
            Launcher:ToggleMenu()
            return
        end
        Launcher:HideMenu()
        if ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        else
            ns:Print("interface indisponible")
        end
    end)
    b:SetScript("OnDragStart", startDrag)
    b:SetScript("OnDragStop", stopDrag)
    b:SetScript("OnHide", function()
        stopDrag()
        Launcher:HideMenu()
    end)
end

---------------------------------------------------------------------------
-- Barre d'infos
---------------------------------------------------------------------------
local function itemEnter(self) showTooltip(self, self.item.tip, self.item) end
local function itemLeave(self) hideTooltip(self) end
local function itemClick(self, mouse)
    if dragEnd and GetTime() - dragEnd < CLICK_AFTER_DRAG then return end
    if mouse == "RightButton" then
        Launcher:ToggleMenu()
    elseif self.item.click then
        self.item.click(self.item)
    end
end

local function createItem(item)
    local f = CreateFrame("Button", nil, dock)
    f:SetSize(1, DOCK_H)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    f.item = item
    item.frame = f
    if item.useDot then
        local d = texture(f, "ARTWORK", 0, MEDIA .. "Circle", DOT_SIZE)
        d:SetPoint("LEFT", f, "LEFT", 0, 0)
        d:SetVertexColor(T.dim[1], T.dim[2], T.dim[3], 1)
        item.dotTex = d
    end
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(GameFontHighlightSmall)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetPoint("LEFT", f, "LEFT", item.dotTex and DOT_SPACE or 0, 0)
    item.text = text
    local sep = dock:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.12)
    sep:SetSize(1, 12)
    sep:SetPoint("CENTER", f, "LEFT", -ITEM_GAP / 2, 0)
    sep:Hide()
    item.sep = sep
    f:SetScript("OnEnter", itemEnter)
    f:SetScript("OnLeave", itemLeave)
    f:SetScript("OnClick", itemClick)
    f:SetScript("OnDragStart", startDrag)
    f:SetScript("OnDragStop", stopDrag)
end

local function createDock()
    local d = CreateFrame("Frame", "PlatyplusLauncherDock", button)
    d:SetSize(DOCK_PAD * 2, DOCK_H)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    dock = d
    Launcher.dock = d
    nineSlice(d, "BACKGROUND", -8, MEDIA .. "Shadow", 0.375, 16, 13, BLACK, 0.8, -2)
    nineSlice(d, "BACKGROUND", -7, MEDIA .. "Round", 0.25, 8, 0, T.bg, 0.86)
    nineSlice(d, "BORDER", 0, MEDIA .. "RoundStroke", 0.25, 8, 0, WHITE, 0.10)
    d:SetScript("OnDragStart", startDrag)
    d:SetScript("OnDragStop", stopDrag)
    d:SetScript("OnMouseUp", function(_, mouse)
        if mouse == "RightButton" then Launcher:ToggleMenu() end
    end)
    -- OnShow / OnHide arrivent aussi quand un parent change (icône masquée, Alt+Z) : le ticker suit
    d:SetScript("OnShow", function() updateTicker() end)
    d:SetScript("OnHide", function() updateTicker() end)
    for _, item in ipairs(items) do createItem(item) end
end

layout = function()
    dirty = false
    local x, count = DOCK_PAD, 0
    for _, item in ipairs(items) do
        if item.visible then
            local f = item.frame
            f:SetWidth(max(item.width, 1))
            f:ClearAllPoints()
            f:SetPoint("LEFT", dock, "LEFT", x, 0)
            if count > 0 then item.sep:Show() else item.sep:Hide() end
            x = x + item.width + ITEM_GAP
            count = count + 1
        end
    end
    local width = count > 0 and (x - ITEM_GAP + DOCK_PAD) or DOCK_PAD * 2
    if width ~= dockWidth then
        dockWidth = width
        dock:SetWidth(width)
    end
    updateSide()
end

-- Relit les réglages : valeurs affichées, largeurs (remises à zéro), événements et ticker.
refreshDock = function()
    if not dock then return end
    local count = 0
    batching, dirty = true, false
    for _, item in ipairs(items) do
        local vis = wanted(item)
        item.visible = vis
        item.width, item.last, item.num = 0, nil, nil
        if vis then
            count = count + 1
            item.frame:Show()
            safeUpdate(item)
        else
            item.frame:Hide()
            item.sep:Hide()
        end
    end
    batching = false
    dockActive = count > 0
    if dockActive then
        layout()
        dock:Show()
    else
        dock:Hide()
    end
    syncEvents()
    updateTicker()
end

---------------------------------------------------------------------------
-- Menu rapide (créé au premier clic droit)
---------------------------------------------------------------------------
local function rowEnter(self)
    menuHL:ClearAllPoints()
    menuHL:SetAllPoints(self)
    menuHL:Show()
end

local function rowLeave()
    menuHL:Hide()
end

local function setSwitch(row, on)
    local c = on and T.accent or SWITCH_OFF
    row.swL:SetVertexColor(c[1], c[2], c[3], 1)
    row.swM:SetVertexColor(c[1], c[2], c[3], 1)
    row.swR:SetVertexColor(c[1], c[2], c[3], 1)
    local k = on and WHITE or KNOB_OFF
    row.knob:SetVertexColor(k[1], k[2], k[3], 1)
    row.knob:ClearAllPoints()
    row.knob:SetPoint("CENTER", on and row.swR or row.swL, "CENTER", 0, 0)
    local t = on and T.text or T.dim
    row.label:SetTextColor(t[1], t[2], t[3])
    row.on = on
end

local function createRow(parent, y, text)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(MENU_W - MENU_PAD * 2, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", MENU_PAD, -y)
    row:SetFrameLevel(parent:GetFrameLevel() + 2)
    row:RegisterForClicks("LeftButtonUp")
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(GameFontHighlightSmall)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetText(text)
    row.label = label
    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", rowLeave)
    return row
end

-- interrupteur en pilule : deux disques + un rectangle, et une pastille blanche qui glisse
local function addSwitch(row)
    local right = texture(row, "ARTWORK", 0, MEDIA .. "Circle", 14)
    right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    local left = texture(row, "ARTWORK", 0, MEDIA .. "Circle", 14)
    left:SetPoint("RIGHT", right, "RIGHT", -12, 0)
    local mid = texture(row, "ARTWORK", 0, MEDIA .. "Round")
    mid:SetTexCoord(0.25, 0.75, 0.25, 0.75)
    mid:SetHeight(13)                       -- le disque de Circle occupe 96 % de l'image
    mid:SetPoint("LEFT", left, "CENTER", 0, 0)
    mid:SetPoint("RIGHT", right, "CENTER", 0, 0)
    row.swL, row.swM, row.swR = left, mid, right
    row.knob = texture(row, "ARTWORK", 2, MEDIA .. "Circle", 10)
end

local function toggleRow(self)
    ns:Set(self.key, not ns.db[self.key])
end

local function showCatcher()
    if not catcher then
        -- repli si GLOBAL_MOUSE_DOWN n'existe pas : un cadre plein écran sous le menu ferme le menu au clic
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("DIALOG")
        catcher:SetFrameLevel(max(0, menu:GetFrameLevel() - 1))
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", function() Launcher:HideMenu() end)
    end
    catcher:Show()
end

local function createMenu()
    local m = CreateFrame("Frame", "PlatyplusLauncherMenu", UIParent)
    m:Hide()
    m:SetFrameStrata("DIALOG")
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:SetWidth(MENU_W)
    menu = m
    Launcher.menu = m
    table.insert(UISpecialFrames, "PlatyplusLauncherMenu")   -- Échap ferme le menu

    nineSlice(m, "BACKGROUND", -8, MEDIA .. "Shadow", 0.375, 18, 15, BLACK, 1, -2)
    nineSlice(m, "BACKGROUND", -7, MEDIA .. "Round", 0.25, 8, 0, T.panel)
    nineSlice(m, "BORDER", 0, MEDIA .. "RoundStroke", 0.25, 8, 0, T.accent, 0.35)

    -- en-tête : logo, nom, version
    local logo = texture(m, "ARTWORK", 0, ns.LOGO, 20)
    logo:SetPoint("TOPLEFT", m, "TOPLEFT", 10, -7)
    local title = m:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(GameFontNormal)
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText("|cff33ccffPlaty|r|cffffd133plus|r")
    local version = m:CreateFontString(nil, "OVERLAY")
    version:SetFontObject(GameFontDisableSmall)
    version:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    version:SetPoint("RIGHT", m, "TOPRIGHT", -12, -17)
    version:SetText("v" .. tostring(ns.version))
    local line = m:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(T.line[1], T.line[2], T.line[3], T.line[4])
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", m, "TOPLEFT", 8, -HEADER_H)
    line:SetPoint("TOPRIGHT", m, "TOPRIGHT", -8, -HEADER_H)

    -- une seule surbrillance, déplacée sur la ligne survolée
    local hl = CreateFrame("Frame", nil, m)
    hl:SetFrameLevel(m:GetFrameLevel() + 1)
    hl:Hide()
    nineSlice(hl, "BACKGROUND", 0, MEDIA .. "Round", 0.25, 6, 0, WHITE, 0.07)
    menuHL = hl

    local y = HEADER_H + 4
    for _, entry in ipairs(MENU_ENTRIES) do
        local row = createRow(m, y, ns.T(entry[2]))
        row.key = entry[1]
        addSwitch(row)
        row:SetScript("OnClick", toggleRow)
        menuRows[#menuRows + 1] = row
        y = y + ROW_H
    end

    local sep = m:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(T.line[1], T.line[2], T.line[3], T.line[4])
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", m, "TOPLEFT", 8, -(y + 3))
    sep:SetPoint("TOPRIGHT", m, "TOPRIGHT", -8, -(y + 3))
    y = y + 7

    local options = createRow(m, y, ns.T("Ouvrir les options"))
    options.action = "options"
    options.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    local arrow = options:CreateFontString(nil, "OVERLAY")
    arrow:SetFontObject(GameFontHighlightSmall)
    arrow:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    arrow:SetPoint("RIGHT", options, "RIGHT", -10, 0)
    arrow:SetText("»")
    options:SetScript("OnClick", function()
        Launcher:HideMenu()
        openOptions()
    end)
    Launcher.optionsRow = options
    y = y + ROW_H

    -- journal des donjons (DungeonJournalPlus.lua) : seulement s'il y en a un (intégré ou addon séparé)
    if ns.DungeonPlus and ns.DungeonPlus.Available and ns.DungeonPlus.Available() then
        local journal = createRow(m, y, ns.T("Journal des donjons"))
        journal.action = "dungeons"
        local jArrow = journal:CreateFontString(nil, "OVERLAY")
        jArrow:SetFontObject(GameFontHighlightSmall)
        jArrow:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
        jArrow:SetPoint("RIGHT", journal, "RIGHT", -10, 0)
        jArrow:SetText("»")
        journal:SetScript("OnClick", function()
            Launcher:HideMenu()
            if ns.DungeonPlus and ns.DungeonPlus.Toggle then ns.DungeonPlus.Toggle() end
        end)
        Launcher.journalRow = journal
        y = y + ROW_H
    end

    m:SetHeight(y + MENU_PAD)

    m:SetScript("OnShow", function(self)
        refreshMenu()
        if globalMouse ~= false then
            globalMouse = pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") and true or false
        end
        if not globalMouse then showCatcher() end
    end)
    m:SetScript("OnHide", function(self)
        if globalMouse then pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end
        menuHL:Hide()
        if catcher then catcher:Hide() end
    end)
    -- clic ailleurs : on ferme (clic sur l'icône ou la barre : leur propre clic s'en charge)
    m:SetScript("OnEvent", function(self, event)
        if event ~= "GLOBAL_MOUSE_DOWN" then return end
        if self:IsMouseOver() or button:IsMouseOver() then return end
        if dock:IsVisible() and dock:IsMouseOver() then return end
        self:Hide()
    end)
end

refreshMenu = function()
    if not (menu and menu:IsShown()) then return end
    for _, row in ipairs(menuRows) do setSwitch(row, ns.db[row.key] and true or false) end
end

---------------------------------------------------------------------------
-- Réglages
---------------------------------------------------------------------------
local function applyVisibility()
    if ns.db.launcher then
        button:Show()
    else
        button:Hide()
        Launcher:HideMenu()
    end
end

local function onSetting(key)
    if key == "launcherPoint" or key == "launcherX" or key == "launcherY" then
        if not suspend then
            place()
            updateSide()
        end
    elseif key == "launcherScale" then
        applyScale()
        place()
        updateSide()
    elseif key == "launcher" then
        applyVisibility()
        refreshDock()
    elseif key == "dock" or DOCK_KEY[key] then
        refreshDock()
    elseif key == "dockXpMode" then
        local item = byName.xp
        item.width, item.last = 0, nil      -- la largeur suit le nouveau texte (plus court ou plus long)
        refreshItem(item)
        if item.visible and dockActive then layout() end
        updateTicker()
    end
    if MENU_KEY[key] then refreshMenu() end
end

local WATCHED = {
    "launcher", "launcherPoint", "launcherX", "launcherY", "launcherScale", "launcherLocked",
    "dock", "dockFps", "dockLatency", "dockGold", "dockBags", "dockDurability", "dockIlvl", "dockCoords", "dockXp",
    "dockXpMode",
}

local handlers = {}

function handlers.PLAYER_LOGIN()
    setEvent("PLAYER_LOGIN", false)
    startSession()
    Launcher:Refresh()
end

function handlers.PLAYER_ENTERING_WORLD()
    startSession()          -- sans effet si la session a déjà commencé
    place()
    refreshDock()
end

function handlers.PLAYER_MONEY()
    trackMoney()
    refreshItem(byName.gold)
end

function handlers.PLAYER_XP_UPDATE()
    trackXP()
    local item = byName.xp
    if wanted(item) ~= item.visible then refreshDock() else refreshItem(item) end   -- niveau max atteint
end
handlers.PLAYER_LEVEL_UP = handlers.PLAYER_XP_UPDATE

function handlers.QUEST_TURNED_IN(_, xpReward)
    trackQuest(xpReward)
end

-- aussi au /reload : la session est reprise au chargement suivant (si moins de 30 min plus tard)
function handlers.PLAYER_LOGOUT()
    saveSession()
end

function handlers.BAG_UPDATE_DELAYED()
    refreshItem(byName.bags)
end

function handlers.UPDATE_INVENTORY_ALERTS()
    refreshItem(byName.durability)
end
handlers.UPDATE_INVENTORY_DURABILITY = handlers.UPDATE_INVENTORY_ALERTS

function handlers.PLAYER_AVG_ITEM_LEVEL_UPDATE()
    refreshItem(byName.ilvl)
end

function handlers.PLAYER_EQUIPMENT_CHANGED()
    refreshItem(byName.durability)
    refreshItem(byName.ilvl)
end

function handlers.DISPLAY_SIZE_CHANGED()
    place()
    updateSide()
end
handlers.UI_SCALE_CHANGED = handlers.DISPLAY_SIZE_CHANGED

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function Launcher:Init()
    if self.initialized then return end
    self.initialized = true

    T, MEDIA = ns.THEME, ns.MEDIA
    GOOD, BAD, ACCENT = T.good, T.bad, T.accent
    HEX.text, HEX.dim, HEX.bad, HEX.warn, HEX.gold = hex(T.text), hex(T.dim), hex(T.bad), hex(WARN), hex(T.gold)

    createButton()
    createDock()

    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, ...)
        local fn = handlers[event]
        if fn then fn(...) end
    end)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
        "QUEST_TURNED_IN", "PLAYER_LOGOUT", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
        setEvent(event, true)
    end

    local seen = {}
    for _, key in ipairs(WATCHED) do
        seen[key] = true
        ns:OnChange(key, onSetting)
    end
    for _, entry in ipairs(MENU_ENTRIES) do
        if not seen[entry[1]] then ns:OnChange(entry[1], onSetting) end
    end

    local loggedIn = api("IsLoggedIn")
    if loggedIn and loggedIn() then
        startSession()
    else
        setEvent("PLAYER_LOGIN", true)
    end
    self:Refresh()
end

-- Réapplique tout : échelle, position, visibilité, barre d'infos, menu.
function Launcher:Refresh()
    if not button then return end
    applyScale()
    place()
    applyVisibility()
    refreshDock()
    refreshMenu()
end

-- Nouvelle session : XP, temps actif et or de la session repartent de zéro (Maj + clic sur l'XP).
function Launcher:ResetSession()
    session.started = false
    local db = charDB(false)
    if db then db.launcherSession = nil end
    startSession(true)
    refreshItem(byName.xp)
    refreshItem(byName.gold)
end

function Launcher:ResetPosition()
    suspend = true
    ns:Reset("launcherPoint")
    ns:Reset("launcherX")
    ns:Reset("launcherY")
    suspend = false
    if button then
        place()
        updateSide()
    end
end

function Launcher:ShowMenu()
    if not button or not button:IsShown() then return end
    if not menu then createMenu() end
    hideTooltip(button)
    attach(menu, button, 6)
    menu:Show()             -- OnShow relit les interrupteurs
end

function Launcher:HideMenu()
    if menu then menu:Hide() end
end

function Launcher:ToggleMenu()
    if menu and menu:IsShown() then self:HideMenu() else self:ShowMenu() end
end

function Launcher:IsMenuShown()
    return menu ~= nil and menu:IsShown()
end
