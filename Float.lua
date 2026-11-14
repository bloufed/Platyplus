-- Platyplus : flux de butin flottant, style « bandeau de notification »
-- Chaque ligne est un voile sombre SANS cadre, ombre ni coins arrondis, qui s'efface vers la droite : on lit une
-- notification posée sur le jeu, pas un bouton. Liseré et cadre d'icône à la couleur de la qualité, nom de l'objet,
-- quantité, source en petit texte coloré (Vendu, Fabriqué, Quête...) et prix ou montant à droite avec les pièces.
-- Les lignes ne captent jamais la souris : on clique au travers.
-- Animations : entrée en glissant + fondu, réempilement fluide, « pulse » quand une ligne fusionne, sortie en fondu.
-- Optimisation : un seul OnUpdate (celui du conteneur PlatyplusFeed), actif seulement quand des lignes sont
-- visibles et endormi tant qu'aucune animation n'est en cours ; lignes réutilisées (pool), textures et polices
-- créées une seule fois par ligne ; aucune table ni chaîne créée par image.
local ADDON, ns = ...

local Float = {}
ns.Float = Float

local floor, sin, pi, huge = math.floor, math.sin, math.pi, math.huge
local tremove, tinsert = table.remove, table.insert
local format = string.format

---------------------------------------------------------------------------
-- Dimensions et rythme (en points, avant l'échelle floatScale)
---------------------------------------------------------------------------
local ROW_W, ROW_H, GAP = 300, 36, 5     -- bandeau d'une ligne
local STEP = ROW_H + GAP
local ICON, ICON_X = 28, 21              -- icône 28 px, son centre à 21 px du bord gauche
local TEXT_X, PAD_R = 44, 12             -- début du texte, marge droite
local TITLE_Y, SUB_Y = 7, -8             -- deux lignes de texte quand la source est affichée
local SCRIM_ALPHA = 0.62                 -- opacité du voile sombre derrière le texte
local SCRIM_SOLID = 0.5                  -- part de la ligne où le voile est plein, avant de s'effacer vers la droite
local SCRIM_TINT = 0.14                  -- le voile prend un soupçon de la couleur de qualité
local WASH_W, WASH_ALPHA = 120, 0.22     -- lueur de couleur qui part du liseré et s'efface
Float.ROW_W, Float.ROW_H = ROW_W, ROW_H  -- lus par les scénarios de test

local IN_TIME = 0.22      -- entrée (glissement + fondu)
local FADE = 0.6          -- fondu de fin de vie
local OUT_TIME = 0.2      -- sortie rapide d'une ligne poussée hors de la limite
local PULSE_TIME = 0.35   -- « pulse » quand une ligne fusionne
local SLIDE = 36          -- distance du glissement d'entrée
local MOVE_SPEED = 14     -- vivacité du réempilement (plus grand = plus rapide)

local MONEY_TYPE = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROUND = ns.MEDIA .. "Round"
local STROKE = ns.MEDIA .. "RoundStroke"
local SHADOW = ns.MEDIA .. "Shadow"
local GLOW = ns.MEDIA .. "Glow"
local GRADIENT = ns.MEDIA .. "Gradient"   -- opaque en haut, transparent en bas ; tourné d'un quart de tour ci-dessous

-- Pièces : icônes classiques de Blizzard (non vérifiées sur Forever) ou repli texte « po / pa / pc » en couleur
local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
local GOLD_TXT, SILVER_TXT, COPPER_TXT = " |cffffd100po|r", " |cffc7c7cfpa|r", " |cffeda55fpc|r"
local coinIcons = false   -- décidé à Init

-- Titre d'une ligne d'argent selon sa source (le montant est à droite, la pastille dessous)
local MONEY_TITLE = {
    loot = "Argent ramassé", money = "Argent ramassé", sold = "Ventes", quest = "Récompense",
    repair = "Réparation", mail = "Argent reçu", received = "Argent reçu", trade = "Argent échangé",
}

-- Couleurs de qualité de repli (0 gris ... 7 héritage) si ITEM_QUALITY_COLORS manque une entrée
local QUALITY_FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1.00, 1.00, 1.00 }, [2] = { 0.12, 1.00, 0.00 }, [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1.00, 0.50, 0.00 }, [6] = { 0.90, 0.80, 0.50 }, [7] = { 0.00, 0.80, 1.00 },
}
-- lueur derrière l'icône selon la qualité (rare et mieux)
local GLOW_BY_QUALITY = { [3] = 0.22, [4] = 0.40, [5] = 0.55, [6] = 0.55, [7] = 0.40 }

-- Mots des montants d'argent (« 3 Argent\n20 Cuivre ») ; complété à Init avec GOLD_AMOUNT & co.
local MONEY_WORDS = { ["or"] = 10000, gold = 10000, argent = 100, silver = 100, cuivre = 1, copper = 1 }

local THEME, SOURCES, FONT
local qualityColors = {}   -- [qualité] = { r, g, b }
local labelToKey = {}      -- « Vendu » -> "sold" (ancien champ prefix)

local container, anchor, anchorBox, anchorHint
local active = {}          -- lignes affichées, active[1] = la plus récente
local leaving = {}         -- lignes poussées hors de la limite, en train de disparaître
local pool = {}            -- lignes libres, réutilisées
local idleUntil, idleDuration = 0, nil
local moving, saving = false, false

---------------------------------------------------------------------------
-- Petits outils
---------------------------------------------------------------------------
local function hex(r, g, b)
    return format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function stripCodes(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("[%s:]+$", ""):gsub("^%s+", "")
    return text
end

local function oneLine(text)
    return (tostring(text or ""):gsub("%s*\n%s*", " "))
end

-- 9 morceaux d'une image à coins arrondis : cut = borne des coins (0.25 pour Round), size = taille affichée des coins,
-- outset = débord autour du parent, dropY = décalage vertical (ombre portée)
local function nineSlice(parent, file, layer, sublevel, cut, size, outset, dropY)
    local parts = {}
    local o, d = outset or 0, dropY or 0
    local u = { 0, cut, 1 - cut, 1 }
    for i = 1, 9 do
        local t = parent:CreateTexture(nil, layer, nil, sublevel)
        t:SetTexture(file)
        local col, line = (i - 1) % 3, floor((i - 1) / 3)
        t:SetTexCoord(u[col + 1], u[col + 2], u[line + 1], u[line + 2])
        parts[i] = t
    end
    local tl, tr, bl, br = parts[1], parts[3], parts[7], parts[9]
    tl:SetSize(size, size); tl:SetPoint("TOPLEFT", parent, "TOPLEFT", -o, o + d)
    tr:SetSize(size, size); tr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", o, o + d)
    bl:SetSize(size, size); bl:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -o, -o + d)
    br:SetSize(size, size); br:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", o, -o + d)
    parts[2]:SetPoint("TOPLEFT", tl, "TOPRIGHT");   parts[2]:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    parts[8]:SetPoint("TOPLEFT", bl, "TOPRIGHT");   parts[8]:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    parts[4]:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); parts[4]:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    parts[6]:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); parts[6]:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    parts[5]:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); parts[5]:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    return parts
end

local function tint(parts, r, g, b, a)
    for i = 1, #parts do parts[i]:SetVertexColor(r, g, b, a) end
end

local function newText(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)   -- ombre pleine : le texte reste lisible là où le voile s'efface
    fs:SetWordWrap(false)
    return fs
end

-- texte facultatif (source, quantité) : vidé quand il est absent, pour qu'une ligne réutilisée ne garde rien
local function setOptional(fs, text)
    if text then
        fs:SetText(text)
        fs:Show()
    else
        fs:SetText("")
        fs:Hide()
    end
end

-- Gradient.tga tourné d'un quart de tour : opaque à gauche, transparent à droite.
-- Ordre de SetTexCoord à 8 valeurs : haut-gauche, bas-gauche, haut-droite, bas-droite (x, y de la texture).
local function fadeRight(t)
    t:SetTexture(GRADIENT)
    t:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Couleurs, sources, argent
---------------------------------------------------------------------------
local function buildColors()
    local blizzard = rawget(_G, "ITEM_QUALITY_COLORS")
    for q = 0, 7 do
        local c = type(blizzard) == "table" and blizzard[q]
        if type(c) == "table" and tonumber(c.r) then
            qualityColors[q] = { c.r, c.g, c.b }
        else
            qualityColors[q] = QUALITY_FALLBACK[q]
        end
    end
    for key, s in pairs(SOURCES) do
        if s.label then labelToKey[s.label] = key end
    end
    -- mots localisés du jeu : GOLD_AMOUNT = "%d Or" -> « or »
    for name, value in pairs({ GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }) do
        local fmt = rawget(_G, name)
        if type(fmt) == "string" then
            local word = fmt:gsub("%%d", ""):gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
            if word ~= "" and not word:find("[%d%s]") then MONEY_WORDS[word] = value end
        end
    end
end

-- Les icônes de pièces existent-elles sur ce client ? Sinon on écrit « po / pa / pc ».
local function detectCoinIcons()
    local byPath = rawget(_G, "GetFileIDFromPath")
    if type(byPath) == "function" then
        local ok, id = pcall(byPath, "Interface\\MoneyFrame\\UI-GoldIcon")
        if ok then return id ~= nil and id ~= 0 end
    end
    -- le code d'argent de Blizzard (MoneyFrame) se sert de ces icônes : sa présence suffit
    return type(rawget(_G, "GetCoinTextureString")) == "function"
end

local function bigNumber(n)
    local f = rawget(_G, "BreakUpLargeNumbers")
    if n >= 1000 and type(f) == "function" then
        local ok, s = pcall(f, n)
        if ok and s then return s end
    end
    return tostring(n)
end

local function moneyText(copper)
    copper = floor((tonumber(copper) or 0) + 0.5)
    if copper < 0 then copper = -copper end
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local T = ns.T
    local gi, si, ci = T(GOLD_TXT), T(SILVER_TXT), T(COPPER_TXT)
    if coinIcons then gi, si, ci = GOLD_ICON, SILVER_ICON, COPPER_ICON end
    local out = ""
    if g > 0 then out = bigNumber(g) .. gi end
    if s > 0 then out = (out ~= "" and out .. " " or "") .. s .. si end
    if c > 0 or out == "" then out = (out ~= "" and out .. " " or "") .. c .. ci end
    return out
end
Float.MoneyText = moneyText

-- « 3 Argent\n20 Cuivre » -> 320 ; nil si le texte n'est pas compris (il sera affiché tel quel)
local function parseMoney(text)
    if type(text) ~= "string" then return nil end
    local total, found = 0, false
    for num, word in text:gmatch("(%d+)%s*([^%d%s]+)") do
        local unit = MONEY_WORDS[(word:lower():gsub("%p+$", ""))]
        if not unit then return nil end
        total = total + tonumber(num) * unit
        found = true
    end
    if not found then return nil end
    local rest = text:gsub("(%d+)%s*([^%d%s]+)", ""):gsub("[%s%p]", "")
    if rest ~= "" then return nil end
    return total
end

local function qualityRGB(q)
    local c = qualityColors[q] or qualityColors[1] or QUALITY_FALLBACK[1]
    return c[1], c[2], c[3]
end

-- couleur d'un objet : sa qualité, sinon la couleur de son lien ; renvoie r, g, b, qualité (ou nil)
local function itemRGB(info)
    local q = tonumber(info.quality)
    if q and qualityColors[q] then
        local r, g, b = qualityRGB(q)
        return r, g, b, q
    end
    local link = info.link
    if type(link) == "string" then
        local iq = tonumber(link:match("|cnIQ(%d+):") or "")
        if iq and qualityColors[iq] then
            local r, g, b = qualityRGB(iq)
            return r, g, b, iq
        end
        local hr, hg, hb = link:match("|c%x%x(%x%x)(%x%x)(%x%x)")
        if hr then
            local r, g, b = tonumber(hr, 16) / 255, tonumber(hg, 16) / 255, tonumber(hb, 16) / 255
            for k = 0, 7 do
                local c = qualityColors[k]
                if c and math.abs(c[1] - r) + math.abs(c[2] - g) + math.abs(c[3] - b) < 0.05 then q = k break end
            end
            return r, g, b, q
        end
    end
    local r, g, b = qualityRGB(1)
    return r, g, b, nil
end

-- clé de source et libellé de la pastille ; l'ancien champ prefix n'est lu que sans source
local function resolveSource(info)
    local key = info.source
    if type(key) == "string" and key ~= "" then
        local s = SOURCES[key]
        return key, s and s.label
    end
    if type(info.prefix) == "string" then
        local plain = stripCodes(info.prefix)
        if plain ~= "" then
            local known = labelToKey[plain]
            if known then return known, SOURCES[known].label end
            return "?" .. plain, plain
        end
    end
    return "loot", nil
end

local function sourceRGB(key, isMoney)
    local s = SOURCES[key]
    if isMoney and (key == "loot" or not s) then s = SOURCES.money end
    local c = (s and s.color) or THEME.dim
    return c[1], c[2], c[3]
end

-- nom affiché : le lien (sans crochets) ou le nom coloré par la qualité
local function itemLabel(info, r, g, b)
    local link = info.link
    if type(link) == "string" and link:find("|H", 1, true) then
        return (link:gsub("|h%[(.-)%]|h", "|h%1|h"))
    end
    local name = oneLine(info.name or link or "?")
    if name:find("|c", 1, true) then return name end
    return hex(r, g, b) .. name .. "|r"
end

---------------------------------------------------------------------------
-- Lignes
---------------------------------------------------------------------------
local function setPulse(row, p)
    local s = ICON + 6 * p
    row.icon:SetSize(s, s)
    row.border:SetSize(s + 2, s + 2)
    local base = row.glowBase or 0
    row.glow:SetAlpha(base + (0.9 - base) * p)
end

local function newRow()
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(ROW_W, ROW_H)
    row:EnableMouse(false)   -- jamais cliquable : la souris passe au travers
    row:Hide()

    -- voile sombre sans bord : plein sur la moitié gauche, puis il s'efface jusqu'à rien à droite
    local solid = row:CreateTexture(nil, "BACKGROUND", nil, -6)
    solid:SetColorTexture(1, 1, 1, 1)
    solid:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    solid:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    solid:SetWidth(floor(ROW_W * SCRIM_SOLID))
    local fade = row:CreateTexture(nil, "BACKGROUND", nil, -6)
    fadeRight(fade)
    fade:SetPoint("TOPLEFT", solid, "TOPRIGHT", 0, 0)
    fade:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.scrim = { solid, fade }

    -- liseré de qualité sur le bord gauche, prolongé par une lueur de la même couleur qui s'efface
    local accent = row:CreateTexture(nil, "BACKGROUND", nil, -4)
    accent:SetColorTexture(1, 1, 1, 1)
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.accent = accent
    local wash = row:CreateTexture(nil, "BACKGROUND", nil, -5)
    fadeRight(wash)
    wash:SetWidth(WASH_W)
    wash:SetPoint("TOPLEFT", accent, "TOPRIGHT", 0, 0)
    wash:SetPoint("BOTTOMLEFT", accent, "BOTTOMRIGHT", 0, 0)
    row.wash = wash

    local glow = row:CreateTexture(nil, "ARTWORK", nil, -2)
    glow:SetTexture(GLOW)
    glow:SetBlendMode("ADD")
    glow:SetSize(48, 48)
    glow:SetPoint("CENTER", row, "LEFT", ICON_X, 0)
    row.glow = glow

    local border = row:CreateTexture(nil, "ARTWORK", nil, 1)
    border:SetColorTexture(1, 1, 1, 1)   -- carré uni teinté à la qualité : fin liseré autour de l'icône
    border:SetPoint("CENTER", row, "LEFT", ICON_X, 0)
    row.border = border

    local icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- rogne le cadre gravé des icônes Blizzard
    icon:SetPoint("CENTER", row, "LEFT", ICON_X, 0)
    row.icon = icon

    row.title = newText(row, 13)
    row.title:SetJustifyH("LEFT")

    row.value = newText(row, 12)
    row.value:SetJustifyH("RIGHT")
    row.value:SetPoint("RIGHT", row, "RIGHT", -PAD_R, 0)

    -- source en petit texte coloré sous le nom (pas de pastille : rien qui ressemble à un bouton)
    row.tag = newText(row, 10)
    row.tag:SetJustifyH("LEFT")
    row.tag:SetPoint("LEFT", row, "LEFT", TEXT_X, SUB_Y)

    -- quantité juste après le nom, en texte simple
    row.countText = newText(row, 12)
    row.countText:SetPoint("LEFT", row.title, "RIGHT", 5, 0)
    row.countText:SetTextColor(0.82, 0.82, 0.86)

    row.glowBase = 0
    setPulse(row, 0)
    return row
end

-- textes qui changent quand la ligne fusionne : quantité, prix, montant ; le nom est tronqué s'il manque de place
local function refresh(row)
    local v = ""
    if row.isMoney then
        if row.amount then v = (row.negative and "-" or "") .. moneyText(row.amount) end
    elseif row.price and row.price > 0 then
        v = moneyText(row.price)
    end
    row.value:SetText(v)
    local used = 0
    if v ~= "" then used = row.value:GetStringWidth() + 10 end

    if not row.isMoney and row.count > 1 then
        setOptional(row.countText, "x" .. row.count)
        used = used + row.countText:GetStringWidth() + 5
    else
        setOptional(row.countText, nil)
    end

    local title = row.title
    title:SetWidth(0)          -- largeur libre pour mesurer le texte
    title:SetText(row.label)
    local avail = ROW_W - TEXT_X - PAD_R - used
    if avail < 60 then avail = 60 end   -- montant énorme : le nom garde au moins quelques lettres
    if title:GetStringWidth() > avail then title:SetWidth(avail) end
end

-- remplit une ligne neuve ou réutilisée
local function fill(row, info, source, pillLabel, isMoney, guild)
    local r, g, b, q
    if isMoney then
        r, g, b = sourceRGB(source, true)
        row.glowBase = 0.22
        if row.amount then
            row.label = ns.T(MONEY_TITLE[source] or "Argent") .. (guild and ns.T(" (guilde)") or "")
        else
            row.label = "|cffffd100" .. oneLine(info.name or "?") .. "|r"
        end
    else
        r, g, b, q = itemRGB(info)
        row.glowBase = (q and GLOW_BY_QUALITY[q]) or 0
        row.label = itemLabel(info, r, g, b)
    end

    tint(row.scrim, r * SCRIM_TINT, g * SCRIM_TINT, b * SCRIM_TINT, SCRIM_ALPHA)
    row.wash:SetVertexColor(r, g, b, WASH_ALPHA)
    row.accent:SetVertexColor(r, g, b, 1)
    row.border:SetVertexColor(r, g, b, 1)
    row.glow:SetVertexColor(r, g, b, 1)
    row.icon:SetTexture(info.icon or (isMoney and COIN_ICON or UNKNOWN_ICON))

    local text = THEME.text
    row.title:SetTextColor(text[1], text[2], text[3])
    if row.negative then
        row.value:SetTextColor(THEME.bad[1], THEME.bad[2], THEME.bad[3])
    else
        row.value:SetTextColor(text[1], text[2], text[3])
    end

    if pillLabel then
        local sr, sg, sb = sourceRGB(source, false)
        setOptional(row.tag, ns.T(pillLabel))
        row.tag:SetTextColor(sr + (1 - sr) * 0.25, sg + (1 - sg) * 0.25, sb + (1 - sb) * 0.25)
    else
        setOptional(row.tag, nil)
    end
    row.title:ClearAllPoints()
    row.title:SetPoint("LEFT", row, "LEFT", TEXT_X, pillLabel and TITLE_Y or 0)

    refresh(row)
end

local function place(row)
    row:ClearAllPoints()
    row:SetPoint("CENTER", container, "CENTER", row.x, row.y)
end

local function release(row)
    row:Hide()
    row.key, row.pulseAt = nil, nil
    pool[#pool + 1] = row
end

local function growDir()
    return (ns.db.feedGrow == "DOWN") and -1 or 1
end

local function maxRows()
    local n = floor(tonumber(ns.db.rows) or 6)
    if n < 1 then n = 1 end
    return n
end

-- position cible de chaque ligne : la plus récente sur l'ancre, les autres poussées vers le haut (ou le bas)
local function layoutTargets()
    local dir = growDir()
    for i = 1, #active do active[i].ty = dir * (i - 1) * STEP end
end

-- au-delà de la limite, les plus anciennes sortent en fondu rapide en glissant d'un cran
local function trim(now)
    local limit, dir = maxRows(), growDir()
    while #active > limit do
        local row = tremove(active)
        row.ty = dir * #active * STEP
        row.leaveAt, row.leaveAlpha = now, row.alpha or 1
        row.key = nil
        leaving[#leaving + 1] = row
    end
end

local function wake()
    if not container or (#active == 0 and #leaving == 0) then return end
    idleUntil = 0
    if not container:IsShown() then container:Show() end
end

local function clearAll()
    for i = #active, 1, -1 do release(active[i]); active[i] = nil end
    for i = #leaving, 1, -1 do release(leaving[i]); leaving[i] = nil end
    if container then container:Hide() end
end

-- côté d'arrivée : celui du bord d'écran le plus proche de l'ancre
local function slideSide()
    local w = UIParent:GetWidth() or 0
    local cx = anchor and anchor:GetCenter()
    if not cx then   -- ancre jamais affichée : on se fie à la position enregistrée
        local point, x = tostring(ns.db.point or "CENTER"), tonumber(ns.db.x) or 0
        if point:find("LEFT", 1, true) then cx = x
        elseif point:find("RIGHT", 1, true) then cx = w + x
        else cx = w / 2 + x end
    end
    return (cx < w / 2) and -1 or 1
end

local function push(info)
    if not container or type(info) ~= "table" then return end
    local now = GetTime()
    local source, pillLabel = resolveSource(info)
    local isMoney = (info.type == MONEY_TYPE) or (info.money ~= nil)
    local qty = floor(tonumber(info.qty) or 1)
    if qty < 1 then qty = 1 end
    local price = tonumber(info.price)
    if price and price <= 0 then price = nil end

    local key, amount, guild = nil, nil, false
    if isMoney then
        amount = tonumber(info.money) or parseMoney(info.name)
        guild = source == "repair" and type(info.name) == "string" and info.name:find("guilde", 1, true) ~= nil
        if amount then key = "$" .. source .. (guild and "+g" or "") end
    else
        key = source .. "\001" .. tostring(info.link or info.name or "?")
    end

    -- même objet (ou même argent) déjà affiché : on cumule, le délai repart et la ligne « pulse »
    if key then
        for i = 1, #active do
            local row = active[i]
            if row.key == key then
                if isMoney then
                    row.amount = row.amount + amount
                else
                    row.count = row.count + qty
                    if price then row.price = (row.price or 0) + price end
                end
                row.t0, row.pulseAt = now, now
                refresh(row)
                wake()
                return
            end
        end
    end

    local row = tremove(pool) or newRow()
    row.key, row.isMoney, row.negative = key, isMoney, isMoney and source == "repair"
    row.count = isMoney and 1 or qty
    row.price = (not isMoney) and price or nil
    row.amount = amount
    fill(row, info, source, pillLabel, isMoney, guild)

    tinsert(active, 1, row)
    trim(now)
    layoutTargets()
    row.born, row.t0, row.pulseAt = now, now, nil
    row.slide = SLIDE * slideSide()
    row.x, row.y = row.slide, row.ty
    row.alpha = 0
    row:SetAlpha(0)
    setPulse(row, 0)
    place(row)
    row:Show()
    wake()
end

---------------------------------------------------------------------------
-- Animation : un seul OnUpdate, celui du conteneur
---------------------------------------------------------------------------
-- avance une ligne d'une image ; renvoie true tant qu'elle bouge encore
local function stepRow(row, alpha, x, now, e)
    local busy = false
    local y, ty = row.y, row.ty
    if y ~= ty then
        local d = ty - y
        if d < 0.5 and d > -0.5 then y = ty else y = y + d * e; busy = true end
    end
    if x ~= row.x or y ~= row.y then
        row.x, row.y = x, y
        place(row)
    end
    if alpha ~= row.alpha then
        row.alpha = alpha
        row:SetAlpha(alpha)
    end
    local p = row.pulseAt
    if p then
        local k = (now - p) / PULSE_TIME
        if k >= 1 then
            row.pulseAt = nil
            setPulse(row, 0)
        else
            setPulse(row, sin(k * pi))
            busy = true
        end
    end
    return busy
end

local function onUpdate(self, elapsed)
    local now = GetTime()
    local duration = tonumber(ns.db.duration) or 4
    -- rien ne bouge : on dort jusqu'au prochain fondu (sauf si la durée a changé)
    if now < idleUntil and duration == idleDuration then return end

    local e = elapsed * MOVE_SPEED
    if e > 1 then e = 1 end
    local busy, relayout, nextWake = false, false, huge

    for i = #active, 1, -1 do
        local row = active[i]
        local left = row.t0 + duration - now
        if left <= 0 then
            tremove(active, i)
            release(row)
            relayout = true
        else
            local alpha, x = 1, 0
            local k = (now - row.born) / IN_TIME
            if k < 1 then
                if k < 0 then k = 0 end
                local inv = 1 - k
                k = 1 - inv * inv * inv          -- ralentit en arrivant
                alpha, x = k, row.slide * (1 - k)
                busy = true
            end
            if left < FADE then
                alpha = alpha * left / FADE
                busy = true
            elseif left - FADE < nextWake then
                nextWake = left - FADE
            end
            if stepRow(row, alpha, x, now, e) then busy = true end
        end
    end

    for i = #leaving, 1, -1 do
        local row = leaving[i]
        local k = (now - row.leaveAt) / OUT_TIME
        if k >= 1 then
            tremove(leaving, i)
            release(row)
        else
            stepRow(row, row.leaveAlpha * (1 - k), row.x, now, e)
            busy = true
        end
    end

    if relayout then
        layoutTargets()
        busy = true
    end
    if #active == 0 and #leaving == 0 then
        self:Hide()   -- plus rien à montrer : l'OnUpdate s'arrête
        return
    end
    if busy then
        idleUntil = 0
    else
        idleUntil, idleDuration = now + nextWake, duration
    end
end

---------------------------------------------------------------------------
-- Ancre déplaçable
---------------------------------------------------------------------------
local function updateHint()
    if not anchorHint then return end
    anchorHint:SetText((ns.db.feedGrow == "DOWN") and ns.T("Clic droit pour valider - les lignes descendent")
        or ns.T("Clic droit pour valider - les lignes montent"))
end

local function savePosition()
    local point, _, relPoint, x, y = anchor:GetPoint(1)
    if not point then return end
    saving = true   -- une seule mise en place à la fin, pas une par clé
    ns:Set("point", point)
    ns:Set("relPoint", relPoint or point)
    ns:Set("x", floor((tonumber(x) or 0) + 0.5))
    ns:Set("y", floor((tonumber(y) or 0) + 0.5))
    saving = false
    Float:ApplyPosition()
end

local function buildAnchor()
    anchor = CreateFrame("Frame", "PlatyplusAnchor", UIParent)
    anchor:SetSize(ROW_W, ROW_H)
    anchor:SetFrameStrata("DIALOG")
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    if anchor.SetDontSavePosition then anchor:SetDontSavePosition(true) end   -- la position vit dans PlatyplusDB
    anchor:EnableMouse(false)
    anchor:RegisterForDrag("LeftButton")
    anchor:Hide()

    -- le dessin suit l'échelle du flux : il montre exactement où apparaît la ligne la plus récente
    local box = CreateFrame("Frame", nil, anchor)
    box:SetSize(ROW_W, ROW_H)
    box:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    anchorBox = box

    local accent, card = THEME.accent, THEME.card
    tint(nineSlice(box, SHADOW, "BACKGROUND", -8, 0.375, 16, 13, -2), 1, 1, 1, 0.8)
    tint(nineSlice(box, ROUND, "BACKGROUND", -6, 0.25, 8), card[1] + (accent[1] - card[1]) * 0.15,
        card[2] + (accent[2] - card[2]) * 0.15, card[3] + (accent[3] - card[3]) * 0.15, 0.92)
    tint(nineSlice(box, STROKE, "BORDER", 0, 0.25, 8), accent[1], accent[2], accent[3], 0.95)

    local logo = box:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.LOGO)
    logo:SetSize(26, 26)
    logo:SetPoint("CENTER", box, "LEFT", ICON_X, 0)

    local title = newText(box, 12)
    title:SetPoint("LEFT", box, "LEFT", TEXT_X, TITLE_Y)
    title:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    title:SetText(ns.T("Flux Platyplus - glisse-moi"))

    anchorHint = newText(box, 10)
    anchorHint:SetPoint("LEFT", box, "LEFT", TEXT_X, SUB_Y)
    anchorHint:SetTextColor(THEME.dim[1], THEME.dim[2], THEME.dim[3])
    updateHint()

    anchor:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        savePosition()
    end)
    anchor:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and moving then Float:ToggleMove() end
    end)
end

local function applyScale()
    local s = tonumber(ns.db.floatScale) or 1
    if s < 0.3 then s = 0.3 elseif s > 3 then s = 3 end
    container:SetScale(s)
    anchorBox:SetScale(s)
    anchor:SetSize(ROW_W * s, ROW_H * s)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
-- info : icon, link, name, qty, quality, price, money, source, type (2 = argent), prefix (ancien)
function Float:Add(info)
    if not ns.db or not ns.db.floatLoot then return end
    push(info)
end

function Float:ApplyPosition()
    if not anchor then return end
    local db = ns.db
    local point = db.point or "CENTER"
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, db.relPoint or point, tonumber(db.x) or 0, tonumber(db.y) or 0)
end

function Float:ToggleMove()
    if not anchor then return end
    moving = not moving
    if moving then
        updateHint()
        anchor:EnableMouse(true)
        anchor:Show()
        ns:Print("glisse le cadre bleu où tu veux, puis clic droit dessus (ou /pp move) pour valider")
    else
        anchor:StopMovingOrSizing()
        anchor:EnableMouse(false)
        anchor:Hide()
        ns:Print("position du flux enregistrée")
    end
end

function Float:IsMoving()
    return moving
end

-- Démonstration : une ligne de chaque source, arrivées en cascade, puis une fusion (le tissu passe à x4)
local LINEN = "Interface\\Icons\\INV_Fabric_Linen_02"
local DEMO = {
    { icon = "Interface\\Icons\\Trade_BlackSmithing", name = "Réparé : 1 po 12 pa 40 pc", money = 11240,
      source = "repair", type = MONEY_TYPE },
    { icon = COIN_ICON, name = "Quête : 2 po 35 pa", money = 23500, source = "quest", type = MONEY_TYPE },
    { icon = "Interface\\Icons\\INV_Potion_51", name = "Potion de soins", qty = 5, quality = 1, source = "bought" },
    { icon = "Interface\\Icons\\INV_Boots_05", name = "Bottes de l'éclaireur", qty = 1, quality = 2, source = "quest" },
    { icon = LINEN, name = "Rouleau de tissu de lin", qty = 2, quality = 1, source = "crafted" },
    { icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", name = "Crâne fêlé", qty = 3, quality = 0,
      price = 255, source = "sold" },
    { icon = "Interface\\Icons\\INV_Sword_04", name = "Lame du crépuscule", qty = 1, quality = 4, source = "loot" },
}
local DEMO_MERGE = { icon = LINEN, name = "Rouleau de tissu de lin", qty = 2, quality = 1, source = "crafted" }

function Float:Test()
    if not container then return end
    -- l'aperçu s'affiche même flux coupé : c'est une demande explicite
    for i = 1, #DEMO do
        local info = DEMO[i]
        C_Timer.After((i - 1) * 0.12, function() push(info) end)
    end
    C_Timer.After(#DEMO * 0.12 + 0.5, function() push(DEMO_MERGE) end)
end

function Float:Init()
    THEME, SOURCES = ns.THEME, ns.SOURCES or {}
    FONT = ns.Font(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")   -- cyrillique si ruRU
    buildColors()
    coinIcons = detectCoinIcons()

    container = CreateFrame("Frame", "PlatyplusFeed", UIParent)
    container:SetSize(ROW_W, ROW_H)
    container:SetFrameStrata("HIGH")
    container:EnableMouse(false)
    container:Hide()
    container:SetScript("OnUpdate", onUpdate)

    buildAnchor()
    container:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    self:ApplyPosition()
    applyScale()

    -- changements venus des options (ou de /pp)
    for _, key in ipairs({ "point", "relPoint", "x", "y" }) do
        ns:OnChange(key, function()
            if not saving then Float:ApplyPosition() end
        end)
    end
    ns:OnChange("floatScale", applyScale)
    ns:OnChange("feedGrow", function()
        updateHint()
        layoutTargets()
        wake()
    end)
    ns:OnChange("rows", function()
        trim(GetTime())
        layoutTargets()
        wake()
    end)
    ns:OnChange("duration", wake)
    ns:OnChange("floatLoot", function(_, on)
        if not on then clearAll() end
    end)
end
