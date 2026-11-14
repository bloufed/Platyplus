-- Platyplus : widgets de la fenêtre d'options (ns.W)
-- Thème sombre moderne tiré de ns.THEME : cartes et boutons arrondis (Media\Round découpé en 9 morceaux),
-- pastilles et boutons ronds (Media\Circle), ombres douces (Media\Shadow). Aucun template Blizzard.
-- Règles :
--  * chaque widget a :Refresh(clé) qui RELIT ns.db et se redessine ; Refresh n'écrit jamais dans ns.db
--  * un widget n'écrit que par ns:Set (ou par ns.Junk pour les listes d'objets)
--  * pas d'OnUpdate permanent : seulement pendant une courte animation (ou un glissement), puis il est retiré
local ADDON, ns = ...

local W = {}
ns.W = W

local floor, ceil, max, min, abs, sin = math.floor, math.ceil, math.max, math.min, math.abs, math.sin
local T = ns.THEME
local Tr, Tf = ns.T, ns.Tf
-- texte d'une option de menu : déjà coloré (W.Quality traduit lui-même) = laissé tel quel
local function TrOpt(t)
    if type(t) == "string" and t:find("^|c") then return t end
    return Tr(t)
end   -- traduction à l'usage (Locale.lua) ; T = thème dans ce fichier

---------------------------------------------------------------------------
-- Dimensions communes (UIConfig s'aligne dessus)
---------------------------------------------------------------------------
W.PAGE_W = 700                       -- largeur d'une page (et des cartes)
W.CARD_PAD = 18                      -- marge intérieure des cartes
W.ROW_W = W.PAGE_W - 2 * W.CARD_PAD  -- largeur d'une ligne de réglage dans une carte
W.INDENT = 22                        -- décalage d'un niveau de sous-option
W.ROW_H = 40                         -- hauteur d'une ligne simple
W.TIP_DX = 60                        -- écart entre le bord droit d'une ligne et son info-bulle (réglé par UIConfig)

---------------------------------------------------------------------------
-- Couleurs (dérivées de ns.THEME)
---------------------------------------------------------------------------
local function col(c, a)
    return { c[1], c[2], c[3], a or c[4] or 1 }
end

local function mix(c1, c2, t, a)
    return { c1[1] + (c2[1] - c1[1]) * t, c1[2] + (c2[2] - c1[2]) * t, c1[3] + (c2[3] - c1[3]) * t, a or 1 }
end

local WHITE, BLACK = { 1, 1, 1, 1 }, { 0, 0, 0, 1 }

local C = {
    bg      = col(T.bg),
    panel   = col(T.panel),
    card    = col(T.card),
    line    = col(T.line),
    accent  = col(T.accent),
    accent2 = col(T.accent2),
    gold    = col(T.gold),
    good    = col(T.good),
    bad     = col(T.bad),
    text    = col(T.text),
    dim     = col(T.dim),
    white   = WHITE,
    black   = BLACK,
}
C.warn        = C.gold
C.accentHover = mix(C.accent, WHITE, 0.25)
C.accentDown  = mix(C.accent, BLACK, 0.18)
C.accentOff   = mix(C.accent, C.card, 0.68)
C.ink         = { 0.03, 0.06, 0.09, 1 }          -- texte posé sur un fond accent
C.field       = mix(C.card, BLACK, 0.38)         -- champs, pastilles de valeur
C.fieldHover  = mix(C.card, WHITE, 0.05)
C.fieldListen = mix(C.field, C.accent, 0.08)
C.btn         = mix(C.card, WHITE, 0.08)
C.btnHover    = mix(C.card, WHITE, 0.15)
C.btnDown     = mix(C.card, WHITE, 0.03)
C.btnOff      = mix(C.card, BLACK, 0.10)
C.track       = mix(C.card, WHITE, 0.15)
C.trackHover  = mix(C.card, WHITE, 0.22)
C.trackOff    = mix(C.card, WHITE, 0.06)
C.off         = mix(C.dim, C.card, 0.45)         -- texte d'une option grisée
C.knob        = { 0.97, 0.98, 1.00, 1 }
C.knobOff     = { 0.55, 0.57, 0.63, 1 }
C.danger      = mix(C.bad, C.card, 0.78)         -- bouton « danger » au repos
C.dangerHover = mix(C.bad, BLACK, 0.12)
C.dangerDown  = mix(C.bad, BLACK, 0.30)
C.hover       = { 1, 1, 1, 0.04 }                -- survol d'une ligne
C.stroke      = { 1, 1, 1, 0.07 }
C.menu        = mix(C.card, WHITE, 0.03, 0.99)
C.capFace     = mix(C.card, WHITE, 0.13)
C.capBase     = mix(C.card, BLACK, 0.55)
W.C = C

local function hex(c)
    return string.format("%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end
W.Hex = hex
W.HEX = { accent = hex(C.accent), gold = hex(C.gold), dim = hex(C.dim), text = hex(C.text), good = hex(C.good), bad = hex(C.bad) }

-- « |cff33ccfftexte|r » dans une couleur du thème
function W.Color(name, text)
    return "|cff" .. (W.HEX[name] or "ffffff") .. tostring(text) .. "|r"
end

local function lerp(a, b, p)
    return a + (b - a) * p
end

local function textColor(fs, c, a)
    fs:SetTextColor(c[1], c[2], c[3], a or c[4] or 1)
end
W.TextColor = textColor

local function font()
    local path = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    return ns.Font and ns.Font(path) or path   -- cyrillique si la langue est ruRU (Locale.lua)
end
W.Font = font

-- FontString : modèle de police du jeu, couleur, taille facultative (police standard)
function W.Text(parent, template, color, layer, size, flags)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlight")
    if size then fs:SetFont(font(), size, flags or "") end
    if color then textColor(fs, color) end
    return fs
end

-- Hauteur d'un texte dimensionné en largeur ; estimation si l'API ne répond pas
local function measure(fs, text, width)
    local h = fs:GetStringHeight()
    if not h or h < 1 then
        local lines = 0
        for part in ((text or "") .. "\n"):gmatch("(.-)\n") do
            lines = lines + max(1, ceil(#part * 6.5 / max(width, 1)))
        end
        h = lines * 13
    end
    return h
end
W.Measure = measure

-- Qualités d'objet (couleurs fixes du jeu depuis toujours)
W.QUALITY = {
    [0] = { name = "Médiocre",   hex = "9d9d9d" },
    [1] = { name = "Commun",     hex = "ffffff" },
    [2] = { name = "Inhabituel", hex = "1eff00" },
    [3] = { name = "Rare",       hex = "0070dd" },
    [4] = { name = "Épique",     hex = "a335ee" },
    [5] = { name = "Légendaire", hex = "ff8000" },
}

function W.Quality(q, text)
    local info = W.QUALITY[q]
    if not info then return text end
    return "|cff" .. info.hex .. Tr(text) .. "|r"
end

---------------------------------------------------------------------------
-- Sons d'interface (ceux des options Blizzard ; absents = silence)
---------------------------------------------------------------------------
local SOUNDS = {
    on    = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
    off   = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", 857 },
    tab   = { "IG_CHARACTER_INFO_TAB", 841 },
    open  = { "IG_MAINMENU_OPEN", 850 },
    close = { "IG_MAINMENU_CLOSE", 851 },
    click = { "U_CHAT_SCROLL_BUTTON", 1115 },
}

function W.Sound(name)
    local s = SOUNDS[name]
    local play = rawget(_G, "PlaySound")
    if not s or not play then return end
    local kit = rawget(_G, "SOUNDKIT")
    local id = (type(kit) == "table" and kit[s[1]]) or s[2]
    pcall(play, id)
end

---------------------------------------------------------------------------
-- Petites animations : OnUpdate posé le temps de l'animation, puis retiré
---------------------------------------------------------------------------
local running = {}   -- [frame] = true : animations en cours (pour les terminer d'un coup)

local function animEnd(self)
    self:SetScript("OnUpdate", nil)
    self.animating = false
    running[self] = nil
    self.animStep(self, 1)
    local done = self.animDone
    self.animDone = nil
    if done then done(self) end
end

local function animUpdate(self, elapsed)
    local t = (self.animT or 0) + elapsed
    self.animT = t
    local p = t / self.animDur
    if p >= 1 then
        animEnd(self)
    else
        self.animStep(self, p)
    end
end

-- step(frame, p) avec p de 0 à 1 ; done(frame) à la fin
function W.Animate(frame, duration, step, done)
    frame.animT, frame.animDur, frame.animStep, frame.animDone = 0, max(duration, 0.01), step, done
    frame.animating = true
    running[frame] = true
    frame:SetScript("OnUpdate", animUpdate)
    step(frame, 0)
end

-- finish = true : saute à l'état final ; sinon l'animation s'arrête où elle en est
function W.StopAnimation(frame, finish)
    if not frame.animating then return end
    if finish then
        animEnd(frame)
    else
        frame:SetScript("OnUpdate", nil)
        frame.animating = false
        running[frame] = nil
    end
end

-- Termine toutes les animations en cours (changement d'onglet, fermeture de la fenêtre) :
-- une page cachée en pleine animation ne garde pas d'OnUpdate en attente
function W.FinishAnimations()
    for frame in pairs(running) do animEnd(frame) end
end

-- départ rapide, arrivée douce
function W.Ease(p)
    local q = 1 - p
    return 1 - q * q * q
end

---------------------------------------------------------------------------
-- Dessin : textures de Media, formes en 9 morceaux, pastilles
---------------------------------------------------------------------------
local MEDIA = ns.MEDIA
local TEX = {
    round  = MEDIA .. "Round",
    stroke = MEDIA .. "RoundStroke",
    shadow = MEDIA .. "Shadow",
    circle = MEDIA .. "Circle",
    glow   = MEDIA .. "Glow",
    grad   = MEDIA .. "Gradient",
    bar    = MEDIA .. "Bar",
}
W.TEX = TEX

-- Texture lissée : on coupe l'alignement sur la grille de pixels (sinon les formes en 9 morceaux bavent)
-- SetSnapToPixelGrid / SetTexelSnappingBias : clients récents seulement, testés avant appel
local function newTex(frame, file, layer, sub)
    local t = frame:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    if file then t:SetTexture(file) end
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    return t
end
W.NewTex = newTex

-- Une « forme » = liste de textures colorées ensemble
local Shape = {}
Shape.__index = Shape

function Shape:SetColor(c, a)
    local r, g, b, al = c[1], c[2], c[3], a or c[4] or 1
    for i = 1, #self do self[i]:SetVertexColor(r, g, b, al) end
end

function Shape:SetRGBA(r, g, b, a)
    for i = 1, #self do self[i]:SetVertexColor(r, g, b, a or 1) end
end

function Shape:SetShown(v)
    v = v and true or false
    for i = 1, #self do self[i]:SetShown(v) end
end

function Shape:Show() self:SetShown(true) end
function Shape:Hide() self:SetShown(false) end

-- Forme en 9 morceaux posée sur `region` ; l, t, r, b = retraits (négatif = débord)
function Shape:AnchorBox(region, l, t, r, b)
    l, t, r, b = l or 0, t or 0, r or 0, b or 0
    self.tl:ClearAllPoints()
    self.tl:SetPoint("TOPLEFT", region, "TOPLEFT", l, -t)
    self.tr:ClearAllPoints()
    self.tr:SetPoint("TOPRIGHT", region, "TOPRIGHT", -r, -t)
    self.bl:ClearAllPoints()
    self.bl:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", l, b)
    self.br:ClearAllPoints()
    self.br:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", -r, b)
end

-- Pastille horizontale : de x1 (depuis le bord gauche de region) à x2 (depuis le bord droit), centrée en y
function Shape:Span(region, x1, x2, y)
    self.a:ClearAllPoints()
    self.b:ClearAllPoints()
    if self.vertical then
        self.a:SetPoint("TOP", region, "TOP", y or 0, x1 or 0)
        self.b:SetPoint("BOTTOM", region, "BOTTOM", y or 0, x2 or 0)
    else
        self.a:SetPoint("LEFT", region, "LEFT", x1 or 0, y or 0)
        self.b:SetPoint("RIGHT", region, "RIGHT", x2 or 0, y or 0)
    end
end

-- cut : borne de découpe dans la texture (0.25 pour Round, 0.375 pour Shadow)
-- flat = "R" : bord droit droit (pour la barre latérale), "L" : bord gauche droit
local function nineSlice(frame, file, layer, sub, corner, cut, flat)
    local s = setmetatable({}, Shape)
    local a, b = cut, 1 - cut
    local lx1, lx2, rx1, rx2 = 0, a, b, 1
    if flat == "L" then lx1, lx2 = a, b end
    if flat == "R" then rx1, rx2 = a, b end
    local function piece(l, r, t, bt)
        local tex = newTex(frame, file, layer, sub)
        tex:SetTexCoord(l, r, t, bt)
        s[#s + 1] = tex
        return tex
    end
    local tl, tr = piece(lx1, lx2, 0, a), piece(rx1, rx2, 0, a)
    local bl, br = piece(lx1, lx2, b, 1), piece(rx1, rx2, b, 1)
    tl:SetSize(corner, corner)
    tr:SetSize(corner, corner)
    bl:SetSize(corner, corner)
    br:SetSize(corner, corner)
    local top, bottom = piece(a, b, 0, a), piece(a, b, b, 1)
    local left, right = piece(lx1, lx2, a, b), piece(rx1, rx2, a, b)
    local mid = piece(a, b, a, b)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT", 0, 0)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
    mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0)
    mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT", 0, 0)
    s.tl, s.tr, s.bl, s.br = tl, tr, bl, br
    s:AnchorBox(frame)
    return s
end

-- Rectangle arrondi plein (corner <= moitié de la plus petite dimension)
function W.Round(frame, layer, sub, corner, flat)
    return nineSlice(frame, TEX.round, layer or "BACKGROUND", sub, corner or 8, 0.25, flat)
end

-- Contour arrondi
function W.Stroke(frame, layer, sub, corner, flat)
    return nineSlice(frame, TEX.stroke, layer or "BORDER", sub, corner or 8, 0.25, flat)
end

-- Ombre portée : déborde de `out` autour de frame, décalée de `dy` vers le bas
function W.Shadow(frame, out, corner, dy)
    out, dy = out or 16, dy or 0
    local s = nineSlice(frame, TEX.shadow, "BACKGROUND", -8, corner or 20, 0.375)
    s:AnchorBox(frame, -out, -(out - dy), -out, -(out + dy))
    return s
end

-- Pastille (bout arrondis) : deux demi-disques + une bande ; size = hauteur (ou largeur si vertical)
local function pill(frame, layer, sub, size, vertical)
    local s = setmetatable({}, Shape)
    local a = newTex(frame, TEX.circle, layer, sub)
    local b = newTex(frame, TEX.circle, layer, sub)
    local m = newTex(frame, TEX.round, layer, sub)
    m:SetTexCoord(0.45, 0.55, 0.45, 0.55)   -- centre plein de Round : blanc uni
    if vertical then
        a:SetTexCoord(0, 1, 0, 0.5)
        b:SetTexCoord(0, 1, 0.5, 1)
        a:SetSize(size, size / 2)
        b:SetSize(size, size / 2)
        m:SetWidth(size * 0.96)
        m:SetPoint("TOP", a, "BOTTOM", 0, 0)
        m:SetPoint("BOTTOM", b, "TOP", 0, 0)
    else
        a:SetTexCoord(0, 0.5, 0, 1)
        b:SetTexCoord(0.5, 1, 0, 1)
        a:SetSize(size / 2, size)
        b:SetSize(size / 2, size)
        m:SetHeight(size * 0.96)            -- le disque de Circle occupe 96 % de l'image
        m:SetPoint("LEFT", a, "RIGHT", 0, 0)
        m:SetPoint("RIGHT", b, "LEFT", 0, 0)
    end
    s[1], s[2], s[3] = a, b, m
    s.a, s.b, s.m, s.size, s.vertical = a, b, m, size, vertical
    s:Span(frame, 0, 0, 0)
    return s
end
W.Pill = pill

-- Petit triangle « menu » (pointe en bas), dessiné en 4 traits : net à toutes les échelles
local CHEVRON = { 7, 5, 3, 1 }
local function chevron(frame, layer)
    local s = setmetatable({}, Shape)
    for i = 1, #CHEVRON do
        local t = frame:CreateTexture(nil, layer or "OVERLAY")
        t:SetTexture(TEX.round)
        t:SetTexCoord(0.45, 0.55, 0.45, 0.55)
        t:SetSize(CHEVRON[i], 1)
        if i > 1 then t:SetPoint("TOP", s[i - 1], "BOTTOM", 0, 0) end
        s[i] = t
    end
    s.top = s[1]
    return s
end

---------------------------------------------------------------------------
-- Lecture / écriture d'un réglage
---------------------------------------------------------------------------
local function evalEnabled(opts)
    if opts and opts.enabled then
        return opts.enabled() and true or false
    end
    return true
end

local function getValue(opts)
    if opts.get then return opts.get() end
    return ns.db[opts.key]
end

local function setValue(opts, value)
    if opts.set then
        opts.set(value)
    else
        ns:Set(opts.key, value)
    end
end

local function defaultValue(opts)
    if opts.key and ns.DEFAULTS then return ns.DEFAULTS[opts.key] end
    return nil
end

---------------------------------------------------------------------------
-- Info-bulles
---------------------------------------------------------------------------
local TIP_TEXT = { 0.82, 0.84, 0.90 }
local TIP_SOFT = { 0.55, 0.58, 0.66 }

local function showTip(self)
    local tip = self.platyplusTip
    if not tip or not (tip.title or tip.text) then return end
    local owner = tip.owner or self
    local placed = false
    if tip.side then
        -- à droite de la fenêtre, à la hauteur de la ligne, s'il y a la place
        local right, screen = owner:GetRight(), UIParent:GetRight()
        if right and screen and right + W.TIP_DX + 280 <= screen then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", W.TIP_DX, 0)
            placed = true
        end
    end
    if not placed then
        GameTooltip:SetOwner(self, tip.side and "ANCHOR_CURSOR" or "ANCHOR_TOP")
    end
    GameTooltip:SetText(tip.title or tip.text or "", 1, 1, 1, 1, true)
    if tip.title and tip.text then
        GameTooltip:AddLine(tip.text, TIP_TEXT[1], TIP_TEXT[2], TIP_TEXT[3], true)
    end
    if owner.isEnabled == false and owner.requires then
        GameTooltip:AddLine(owner.requires, C.gold[1], C.gold[2], C.gold[3], true)
    end
    if tip.default then
        local d = tip.default()
        if d then GameTooltip:AddLine(Tf("Par défaut : %s", Tr(d)), TIP_SOFT[1], TIP_SOFT[2], TIP_SOFT[3], true) end
    end
    if tip.hint then
        GameTooltip:AddLine(tip.hint, C.accent[1], C.accent[2], C.accent[3], true)
    end
    GameTooltip:Show()
end

local function hideTip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- Attache une info-bulle (title = ligne blanche, text = explication)
-- extra (facultatif) : side = à droite de la fenêtre, default = fonction -> texte, hint = ligne bleue
function W.SetTip(frame, title, text, owner, extra)
    local tip = frame.platyplusTip or {}
    -- traduit ici (à la construction) : le texte est le même à chaque survol
    tip.title, tip.text, tip.owner = Tr(title), Tr(text), owner
    if extra then
        tip.side, tip.default, tip.hint = extra.side, extra.default, Tr(extra.hint)
    end
    frame.platyplusTip = tip
    frame:EnableMouse(true)
    if not frame.platyplusTipHooked then
        frame.platyplusTipHooked = true
        frame:HookScript("OnEnter", showTip)
        frame:HookScript("OnLeave", hideTip)
    end
end

---------------------------------------------------------------------------
-- Argent : icônes de pièces (repli texte po / pa / pc)
---------------------------------------------------------------------------
-- Textures classiques de Blizzard, NON VÉRIFIÉES sur Forever : passer W.COIN_ICONS à false pour le texte seul
W.COIN_ICONS = true
local COIN_GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local COIN_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COIN_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

local function groupDigits(n)
    local f = rawget(_G, "BreakUpLargeNumbers")
    if f then
        local ok, s = pcall(f, n)
        if ok and s then return s end
    end
    return tostring(n)
end

function W.FormatMoney(copper)
    copper = floor(tonumber(copper) or 0)
    local g = floor(copper / 10000)
    local s = floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if W.COIN_ICONS then
        if g > 0 then out = groupDigits(g) .. COIN_GOLD end
        if s > 0 then out = out .. (out ~= "" and " " or "") .. s .. COIN_SILVER end
        if c > 0 or out == "" then out = out .. (out ~= "" and " " or "") .. c .. COIN_COPPER end
        return "|cffffffff" .. out .. "|r"
    end
    if g > 0 then out = "|cffffd100" .. groupDigits(g) .. " po|r" end
    if s > 0 then out = out .. (out ~= "" and " " or "") .. "|cffc7c7cf" .. s .. " pa|r" end
    if c > 0 or out == "" then out = out .. (out ~= "" and " " or "") .. "|cffeda55f" .. c .. " pc|r" end
    return out
end

---------------------------------------------------------------------------
-- Objets (noms chargés à la demande)
---------------------------------------------------------------------------
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local requested = {}   -- [itemID] = true : demande de chargement déjà envoyée

local function requestItem(id)
    if requested[id] then return end
    requested[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end

local function itemName(id)
    local name
    if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(id) end
    if name and name ~= "" then return name, true end
    requestItem(id)
    return ns.Tf("Objet #%d", id), false
end

local function itemIcon(id)
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
        return icon
    end
end

-- C_Item.GetItemQualityByID : non vérifié, protégé
local function itemQuality(id)
    if C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, id)
        if ok and type(q) == "number" then return q end
    end
end

-- Icône carrée recadrée (bords Blizzard retirés)
local function iconTex(frame, size, layer)
    local t = frame:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return t
end
W.Icon = iconTex

---------------------------------------------------------------------------
-- Base commune des lignes de réglage
---------------------------------------------------------------------------
local ROW_H = W.ROW_H

local function innerW(parent)
    return (parent and parent.innerW) or W.ROW_W
end
W.InnerWidth = innerW

local function initRow(row, parent, opts)
    row:SetSize(innerW(parent), ROW_H)
    row.opts = opts
    row.requires = Tr(opts.requires)
    row.isEnabled = true
    row.indent = (opts.indent or 0) * W.INDENT
    if row.indent > 0 then
        -- rail des sous-options : trait vertical continu + petite branche vers le libellé
        local rail = row:CreateTexture(nil, "BACKGROUND")
        rail:SetPoint("TOPLEFT", row, "TOPLEFT", row.indent - 13, 0)
        rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", row.indent - 13, 0)
        rail:SetWidth(1)
        rail:SetColorTexture(1, 1, 1, 0.10)
        local tick = row:CreateTexture(nil, "BACKGROUND")
        tick:SetSize(7, 1)
        tick:SetColorTexture(1, 1, 1, 0.10)
        row.tick = tick
    end
end

-- Libellé (et petite description grise facultative) ; rightW = largeur réservée au contrôle à droite
local function rowLabels(row, opts, rightW)
    local width = row:GetWidth() - row.indent - rightW - 18
    local label = W.Text(row, "GameFontHighlight", C.text)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetWidth(width)
    label:SetText(Tr(opts.label or ""))
    row.label = label
    local h = ROW_H
    if opts.desc then
        local d = W.Text(row, "GameFontHighlightSmall", C.dim)
        d:SetJustifyH("LEFT")
        d:SetJustifyV("TOP")
        d:SetWidth(width)
        local descText = Tr(opts.desc)
        d:SetText(descText)
        label:SetPoint("TOPLEFT", row, "TOPLEFT", row.indent, -11)
        d:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        row.desc = d
        h = max(ROW_H, floor(11 + 13 + 3 + measure(d, descText, width) + 11 + 0.5))
        if row.tick then row.tick:SetPoint("TOPLEFT", row, "TOPLEFT", row.indent - 13, -17) end
    else
        label:SetPoint("LEFT", row, "LEFT", row.indent, 0)
        if row.tick then row.tick:SetPoint("LEFT", row, "LEFT", row.indent - 13, 0) end
    end
    row:SetHeight(h)
    return label
end

local function paintLabels(row)
    local on = row.isEnabled
    textColor(row.label, on and C.text or C.off)
    if row.desc then textColor(row.desc, on and C.dim or C.off) end
end

-- Surbrillance douce de la ligne survolée (une seule forme partagée par carte)
local function rowEnter(row)
    local host = row:GetParent()
    if host and host.ShowHover and row.isEnabled ~= false then host:ShowHover(row) end
end

local function rowLeave(row)
    local host = row:GetParent()
    if host and host.HideHover then host:HideHover(row) end
end

---------------------------------------------------------------------------
-- Interrupteur moderne
-- opts : key (ou get/set), label, desc, tip, enabled = fonction, requires = texte, indent = 0..2
---------------------------------------------------------------------------
local SW_W, SW_H, KNOB = 38, 22, 16
local SW_TRAVEL = SW_W - SW_H

local function paintSwitch(row)
    local p, on = row.pos, row.isEnabled
    local a, b
    if on then
        a = row.hover and C.trackHover or C.track
        b = row.hover and C.accentHover or C.accent
    else
        a, b = C.trackOff, C.accentOff
    end
    row.track:SetRGBA(lerp(a[1], b[1], p), lerp(a[2], b[2], p), lerp(a[3], b[3], p), 1)
    row.knob:ClearAllPoints()
    row.knob:SetPoint("CENTER", row.sw, "LEFT", SW_H / 2 + SW_TRAVEL * p, 0)
    local k = on and C.knob or C.knobOff
    row.knob:SetVertexColor(k[1], k[2], k[3], 1)
    paintLabels(row)
end

local function switchStep(row, p)
    row.pos = lerp(row.animFrom, row.animTo, W.Ease(p))
    paintSwitch(row)
end

local function onOffText(v)
    return Tr(v and "activé" or "désactivé")
end

function W.Switch(parent, opts)
    local row = CreateFrame("Button", nil, parent)
    initRow(row, parent, opts)
    row:RegisterForClicks("LeftButtonUp")
    rowLabels(row, opts, SW_W)

    local sw = CreateFrame("Frame", nil, row)   -- support du dessin (sans souris : le clic va à la ligne)
    sw:SetSize(SW_W, SW_H)
    sw:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.sw = sw
    row.track = pill(sw, "ARTWORK", 0, SW_H)
    local shadow = newTex(sw, TEX.circle, "ARTWORK", 1)
    shadow:SetSize(KNOB + 3, KNOB + 3)
    shadow:SetVertexColor(0, 0, 0, 0.35)
    local knob = newTex(sw, TEX.circle, "ARTWORK", 2)
    knob:SetSize(KNOB, KNOB)
    shadow:SetPoint("CENTER", knob, "CENTER", 0, -1)
    row.knob = knob
    row.pos, row.value, row.hover = 0, false, false

    function row:Refresh()
        if not ns.db then return end
        self.isEnabled = evalEnabled(opts)
        local v = getValue(opts) and true or false
        if v ~= self.value or not self.painted then
            self.value = v
            local target = v and 1 or 0
            if self.painted and self:IsVisible() then
                self.animFrom, self.animTo = self.pos, target
                W.Animate(self, 0.16, switchStep)
                return
            end
            W.StopAnimation(self)
            self.pos = target
        end
        self.painted = true
        if not self.animating then paintSwitch(self) end
    end

    row:SetScript("OnEnter", function(self)
        self.hover = true
        rowEnter(self)
        if not self.animating then paintSwitch(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover = false
        rowLeave(self)
        if not self.animating then paintSwitch(self) end
    end)
    row:SetScript("OnClick", function(self)
        if not self.isEnabled then return end
        local v = not getValue(opts)
        setValue(opts, v)
        W.Sound(v and "on" or "off")
        self:Refresh()
    end)

    W.SetTip(row, opts.label, opts.tip, nil, {
        side = true,
        default = function()
            local d = defaultValue(opts)
            if d == nil then return nil end
            return onOffText(d)
        end,
    })
    row:Refresh()
    return row
end

---------------------------------------------------------------------------
-- Curseur : piste arrondie, poignée ronde, valeur dans une pastille
-- opts : key (ou get/set), label, desc, min, max, step, format (chaîne ou fonction), tip, enabled, indent
-- Clic droit sur la ligne : valeur par défaut
---------------------------------------------------------------------------
local SL_W, SL_H, THUMB, TRACK_H = 196, 20, 16, 6
local BADGE_W, BADGE_H = 60, 24

-- format "%.1f" -> virgule française
local function formatValue(opts, v)
    local f = opts.format
    if type(f) == "function" then return f(v) end
    local s = string.format(Tr(f or "%d"), v)
    return (s:gsub("(%d)%.(%d)", "%1,%2"))
end
W.FormatValue = formatValue

function W.Slider(parent, opts)
    local row = CreateFrame("Frame", nil, parent)
    initRow(row, parent, opts)
    row:EnableMouse(true)
    rowLabels(row, opts, SL_W + BADGE_W + 14)
    row.painting = false

    local step = opts.step or 1

    local badge = CreateFrame("Frame", nil, row)
    badge:SetSize(BADGE_W, BADGE_H)
    badge:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local badgeBg = W.Round(badge, "BACKGROUND", 0, 7)
    badgeBg:SetColor(C.field)
    local valueText = W.Text(badge, "GameFontHighlight", C.accent)
    valueText:SetPoint("CENTER", badge, "CENTER", 0, 0)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(SL_W, SL_H)
    slider:SetPoint("RIGHT", badge, "LEFT", -14, 0)
    slider:SetMinMaxValues(opts.min, opts.max)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetHitRectInsets(-4, -4, -6, -6)
    slider:EnableMouse(true)

    local track = pill(slider, "BACKGROUND", 0, TRACK_H)
    track:SetColor(C.field)
    local fillCap = newTex(slider, TEX.circle, "ARTWORK", 0)
    fillCap:SetTexCoord(0, 0.5, 0, 1)
    fillCap:SetSize(TRACK_H / 2, TRACK_H)
    fillCap:SetPoint("LEFT", slider, "LEFT", 0, 0)
    local fill = newTex(slider, TEX.round, "ARTWORK", 0)
    fill:SetTexCoord(0.45, 0.55, 0.45, 0.55)
    fill:SetHeight(TRACK_H * 0.96)
    fill:SetPoint("LEFT", fillCap, "RIGHT", 0, 0)

    slider:SetThumbTexture(TEX.circle)
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(THUMB, THUMB)
        thumb:SetDrawLayer("OVERLAY", 3)
        if thumb.SetSnapToPixelGrid then thumb:SetSnapToPixelGrid(false) end
        if thumb.SetTexelSnappingBias then thumb:SetTexelSnappingBias(0) end
        local shadow = newTex(slider, TEX.circle, "OVERLAY", 1)
        shadow:SetSize(THUMB + 3, THUMB + 3)
        shadow:SetPoint("CENTER", thumb, "CENTER", 0, -1)
        shadow:SetVertexColor(0, 0, 0, 0.4)
        local halo = newTex(slider, TEX.glow, "OVERLAY", 0)
        halo:SetSize(36, 36)
        halo:SetPoint("CENTER", thumb, "CENTER", 0, 0)
        halo:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.45)
        halo:Hide()
        row.halo = halo
    end

    local function snap(v)
        v = floor((v - opts.min) / step + 0.5) * step + opts.min
        v = max(opts.min, min(opts.max, v))
        return tonumber(string.format("%.4f", v))
    end

    local function paint(v)
        valueText:SetText(formatValue(opts, v))
        local frac = 0
        if opts.max > opts.min then frac = (v - opts.min) / (opts.max - opts.min) end
        -- la bande va jusqu'au centre de la poignée
        fill:SetWidth(max(0.5, THUMB / 2 + frac * (SL_W - THUMB) - TRACK_H / 2))
        local on = row.isEnabled
        local fc = on and C.accent or C.accentOff
        fill:SetVertexColor(fc[1], fc[2], fc[3], 1)
        fillCap:SetVertexColor(fc[1], fc[2], fc[3], 1)
        local tc = on and C.track or C.trackOff
        track:SetRGBA(tc[1], tc[2], tc[3], 1)
        if thumb then
            local k = on and C.knob or C.knobOff
            thumb:SetVertexColor(k[1], k[2], k[3], 1)
        end
        textColor(valueText, on and C.accent or C.off)
        paintLabels(row)
        slider:EnableMouse(on)
    end

    function row:Refresh()
        if not ns.db then return end
        self.isEnabled = evalEnabled(opts)
        local v = tonumber(getValue(opts))
        if not v then v = opts.min end
        v = max(opts.min, min(opts.max, v))
        self.painting = true
        slider:SetValue(v)
        self.painting = false
        self.current = v
        paint(v)
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if row.painting or not row.isEnabled then return end
        local v = snap(value)
        paint(v)
        if v ~= row.current then
            row.current = v
            setValue(opts, v)
        end
    end)

    local function enter()
        rowEnter(row)
        if row.halo and row.isEnabled then row.halo:Show() end
    end
    local function leave()
        rowLeave(row)
        if row.halo then row.halo:Hide() end
    end
    row:SetScript("OnEnter", enter)
    row:SetScript("OnLeave", leave)
    slider:SetScript("OnEnter", enter)
    slider:SetScript("OnLeave", leave)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or not self.isEnabled then return end
        if opts.key and defaultValue(opts) ~= nil then
            ns:Reset(opts.key)
            W.Sound("click")
            self:Refresh()
        end
    end)

    local extra = {
        side = true,
        default = function()
            local d = defaultValue(opts)
            if type(d) ~= "number" then return nil end
            return formatValue(opts, d)
        end,
        hint = opts.key and "Clic droit sur le libellé : valeur par défaut." or nil,
    }
    W.SetTip(row, opts.label, opts.tip, nil, extra)
    W.SetTip(slider, opts.label, opts.tip, row, extra)
    row:Refresh()
    return row
end

---------------------------------------------------------------------------
-- Ligne « couleur » : 6 pastilles de palette + pastille de la couleur actuelle (clic = sélecteur du jeu)
-- opts : key (ou get/set), label, desc, tip, enabled, requires, indent, palette = { {r,g,b}, ... }
-- La valeur est une table { r, g, b } (0..1), toujours remplacée par une NOUVELLE table. Clic droit : défaut.
---------------------------------------------------------------------------
local PALETTE = {
    { 0.20, 0.82, 0.30 }, { 1, 0.62, 0.10 }, { 0.95, 0.18, 0.15 },
    { 0.25, 0.62, 0.98 }, { 0.65, 0.40, 0.95 }, { 0.55, 0.55, 0.60 },
}
local DOT, DOT_GAP, BIG = 16, 4, 24

local function rgbOf(v)
    if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" then
        return v[1], v[2], v[3]
    end
    return 0.5, 0.5, 0.5
end

local function colorText(v)
    local r, g, b = rgbOf(v)
    return string.format("%d, %d, %d", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

function W.ColorRow(parent, opts)
    local palette = opts.palette or PALETTE
    local n = #palette
    local dotsW = n * DOT + (n - 1) * DOT_GAP
    local rightW = dotsW + 10 + BIG
    local row = CreateFrame("Frame", nil, parent)
    initRow(row, parent, opts)
    row:EnableMouse(true)
    rowLabels(row, opts, rightW)
    row.hover = false

    -- grande pastille : couleur actuelle, contour un peu plus grand
    local big = CreateFrame("Button", nil, row)
    big:SetSize(BIG, BIG)
    big:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    big:RegisterForClicks("LeftButtonUp")
    local ring = newTex(big, TEX.circle, "ARTWORK", 1)
    ring:SetPoint("CENTER", big, "CENTER", 0, 0)
    ring:SetSize(BIG + 2, BIG + 2)
    local fill = newTex(big, TEX.circle, "ARTWORK", 2)
    fill:SetPoint("CENTER", big, "CENTER", 0, 0)
    fill:SetSize(BIG - 2, BIG - 2)
    row.big, row.bigFill, row.bigRing = big, fill, ring

    local function apply(r, g, b)
        setValue(opts, { r, g, b })   -- toujours une nouvelle table
        row:Refresh()
    end

    row.dots = {}
    for i = 1, n do
        local d = CreateFrame("Button", nil, row)
        d:SetSize(DOT, DOT)
        d:SetPoint("RIGHT", big, "LEFT", -10 - (n - i) * (DOT + DOT_GAP), 0)
        d:RegisterForClicks("LeftButtonUp")
        local t = newTex(d, TEX.circle, "ARTWORK", 1)
        t:SetAllPoints(d)
        d.tex, d.rgb = t, palette[i]
        d:SetScript("OnClick", function()
            if not row.isEnabled then return end
            local c = palette[i]
            apply(c[1], c[2], c[3])
            W.Sound("click")
        end)
        d:SetScript("OnEnter", function() rowEnter(row) end)
        d:SetScript("OnLeave", function() rowLeave(row) end)
        row.dots[i] = d
    end

    function row:Refresh()
        if not ns.db then return end
        self.isEnabled = evalEnabled(opts)
        local r, g, b = rgbOf(getValue(opts))
        local a = self.isEnabled and 1 or 0.35
        self.bigFill:SetVertexColor(r, g, b, a)
        local l = C.line
        self.bigRing:SetVertexColor(l[1], l[2], l[3], self.isEnabled and 1 or 0.5)
        for _, d in ipairs(self.dots) do
            d.tex:SetVertexColor(d.rgb[1], d.rgb[2], d.rgb[3], a)
        end
        paintLabels(self)
    end

    big:SetScript("OnClick", function()
        if not row.isEnabled then return end
        local picker = rawget(_G, "ColorPickerFrame")
        if not picker or not picker.SetupColorPickerAndShow then return end
        local r, g, b = rgbOf(getValue(opts))
        local old = { r, g, b }
        pcall(picker.SetupColorPickerAndShow, picker, {
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function()
                local ok, nr, ng, nb = pcall(picker.GetColorRGB, picker)
                if ok and type(nr) == "number" and type(ng) == "number" and type(nb) == "number" then
                    apply(nr, ng, nb)
                end
            end,
            cancelFunc = function(previous)
                local p = (type(previous) == "table" and type(previous.r) == "number") and previous or nil
                if p then apply(p.r, p.g, p.b) else apply(old[1], old[2], old[3]) end
            end,
        })
        W.Sound("click")
    end)
    big:SetScript("OnEnter", function() rowEnter(row) end)
    big:SetScript("OnLeave", function() rowLeave(row) end)

    row:SetScript("OnEnter", function() row.hover = true rowEnter(row) end)
    row:SetScript("OnLeave", function() row.hover = false rowLeave(row) end)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or not self.isEnabled then return end
        local d = defaultValue(opts)
        if type(d) == "table" then
            local r, g, b = rgbOf(d)
            apply(r, g, b)
            W.Sound("click")
        end
    end)

    W.SetTip(row, opts.label, opts.tip, nil, {
        side = true,
        default = function()
            local d = defaultValue(opts)
            if type(d) ~= "table" then return nil end
            return colorText(d)
        end,
        hint = "Clic sur la grande pastille : choisir une couleur. Clic droit : défaut.",
    })
    row:Refresh()
    return row
end

---------------------------------------------------------------------------
-- Menu déroulant partagé : une seule liste flottante, fermée par un clic ailleurs
---------------------------------------------------------------------------
local MENU_ITEM_H, MENU_PAD = 26, 5
local menu

local function closeMenu()
    if not menu or not menu:IsShown() then return end
    menu:Hide()
    menu.catcher:Hide()
    local owner = menu.owner
    menu.owner, menu.anchor, menu.onPick = nil, nil, nil
    if owner and owner.OnMenuClosed then owner:OnMenuClosed() end
end
W.CloseMenu = closeMenu

local function menuItemEnter(self)
    local m = self:GetParent()
    m.hl:AnchorBox(self, 0, 0, 0, 0)
    m.hl:Show()
    if not self.current then textColor(self.text, WHITE) end
end

local function menuItemLeave(self)
    local m = self:GetParent()
    m.hl:Hide()
    if not self.current then textColor(self.text, C.text) end
end

local function menuItemClick(self)
    local m = self:GetParent()
    local pick, value = m.onPick, self.value
    closeMenu()
    W.Sound("click")
    if pick then pick(value) end
end

local function newMenuItem(m, i)
    local b = CreateFrame("Button", nil, m)
    b:SetHeight(MENU_ITEM_H)
    b:RegisterForClicks("LeftButtonUp")
    local text = W.Text(b, "GameFontHighlight", C.text)
    text:SetPoint("LEFT", b, "LEFT", 10, 0)
    text:SetPoint("RIGHT", b, "RIGHT", -24, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    local check = newTex(b, TEX.circle, "ARTWORK")
    check:SetSize(7, 7)
    check:SetPoint("RIGHT", b, "RIGHT", -10, 0)
    check:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    b.text, b.check = text, check
    b:SetScript("OnEnter", menuItemEnter)
    b:SetScript("OnLeave", menuItemLeave)
    b:SetScript("OnClick", menuItemClick)
    m.items[i] = b
    return b
end

local function menuFade(m, p)
    m:SetAlpha(W.Ease(p))
end

local function ensureMenu()
    if menu then return menu end
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(120)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:Hide()
    local shadow = W.Shadow(m, 14, 18, 3)
    shadow:SetColor(BLACK, 0.85)
    local bg = W.Round(m, "BACKGROUND", 0, 8)
    bg:SetColor(C.menu)
    local stroke = W.Stroke(m, "BORDER", 0, 8)
    stroke:SetColor(WHITE, 0.10)
    m.hl = W.Round(m, "ARTWORK", 0, 6)
    m.hl:SetColor(C.accent, 0.16)
    m.hl:Hide()
    m.items = {}

    -- grand bouton invisible derrière la liste : un clic ailleurs la ferme
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(100)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("AnyDown")
    catcher:SetScript("OnClick", closeMenu)
    catcher:Hide()
    m.catcher = catcher

    menu = m
    return m
end

-- options = { { value =, text = }, ... } ; onPick(value) ; owner:OnMenuClosed() appelé à la fermeture
function W.OpenMenu(anchor, options, current, onPick, owner)
    local m = ensureMenu()
    if m:IsShown() and m.anchor == anchor then
        closeMenu()
        return
    end
    closeMenu()
    m.anchor, m.owner, m.onPick = anchor, owner, onPick

    local n = #options
    m:SetSize(max(anchor:GetWidth() or 0, 160), n * MENU_ITEM_H + 2 * MENU_PAD)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    for i, option in ipairs(options) do
        local b = m.items[i] or newMenuItem(m, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", m, "TOPLEFT", MENU_PAD, -MENU_PAD - (i - 1) * MENU_ITEM_H)
        b:SetPoint("TOPRIGHT", m, "TOPRIGHT", -MENU_PAD, -MENU_PAD - (i - 1) * MENU_ITEM_H)
        b.value = option.value
        b.current = (option.value == current)
        b.text:SetText(TrOpt(option.text))
        textColor(b.text, b.current and C.accent or C.text)
        b.check:SetShown(b.current)
        b:Show()
    end
    for i = n + 1, #m.items do m.items[i]:Hide() end
    m.hl:Hide()
    m.catcher:Show()
    m:Show()
    W.Animate(m, 0.12, menuFade)
end

---------------------------------------------------------------------------
-- Menu déroulant (ligne : libellé + champ arrondi qui ouvre la liste ; toute la ligne est cliquable)
-- opts : key, label, desc, tip, options = { {value=, text=}, ... } (ou fonction), enabled, indent, width
---------------------------------------------------------------------------
local DD_W, DD_H = 220, 28

function W.Dropdown(parent, opts)
    local row = CreateFrame("Button", nil, parent)
    initRow(row, parent, opts)
    row:RegisterForClicks("LeftButtonUp")
    local boxW = opts.width or DD_W
    rowLabels(row, opts, boxW)
    row.hover, row.open = false, false

    local box = CreateFrame("Frame", nil, row)
    box:SetSize(boxW, DD_H)
    box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local bg = W.Round(box, "BACKGROUND", 0, 7)
    local stroke = W.Stroke(box, "BORDER", 0, 7)
    local text = W.Text(box, "GameFontHighlight", C.text)
    text:SetPoint("LEFT", box, "LEFT", 11, 0)
    text:SetPoint("RIGHT", box, "RIGHT", -28, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    local chev = chevron(box)
    chev.top:SetPoint("TOP", box, "RIGHT", -14, 2)

    local function getOptions()
        if type(opts.options) == "function" then return opts.options() end
        return opts.options or {}
    end

    local function optionText(value)
        for _, o in ipairs(getOptions()) do
            if o.value == value then return TrOpt(o.text) end
        end
        return tostring(value)
    end

    local function paint()
        text:SetText(optionText(getValue(opts)))
        if row.isEnabled then
            bg:SetColor(row.hover and C.fieldHover or C.field)
            if row.open then
                stroke:SetColor(C.accent, 0.9)
            else
                stroke:SetColor(row.hover and WHITE or C.stroke, row.hover and 0.16 or nil)
            end
            textColor(text, C.text)
            chev:SetColor(row.open and C.accent or C.dim)
        else
            bg:SetColor(C.btnOff)
            stroke:SetColor(C.stroke)
            textColor(text, C.off)
            chev:SetColor(C.off)
        end
        paintLabels(row)
    end

    function row:Refresh()
        if not ns.db then return end
        self.isEnabled = evalEnabled(opts)
        paint()
    end

    function row:OnMenuClosed()
        self.open = false
        paint()
    end

    row:SetScript("OnEnter", function(self) self.hover = true rowEnter(self) paint() end)
    row:SetScript("OnLeave", function(self) self.hover = false rowLeave(self) paint() end)
    row:SetScript("OnClick", function(self)
        if not self.isEnabled then return end
        W.OpenMenu(box, getOptions(), getValue(opts), function(value)
            setValue(opts, value)
            row:Refresh()
        end, self)
        self.open = (menu and menu:IsShown() and menu.owner == self) and true or false
        paint()
    end)

    W.SetTip(row, opts.label, opts.tip, nil, {
        side = true,
        default = function()
            local d = defaultValue(opts)
            if d == nil then return nil end
            return optionText(d)
        end,
    })
    row:Refresh()
    return row
end

---------------------------------------------------------------------------
-- Bouton arrondi
-- opts : text, onClick(bouton), tip, tipTitle, width (sinon automatique), height,
--        primary (accent), danger (rouge), enabled, requires, getText,
--        confirm = texte affiché au 1er clic (le 2e clic dans les 3 s déclenche onClick)
---------------------------------------------------------------------------
local CONFIRM_DELAY = 3

local function paintButton(b)
    local opts = b.opts
    local bgc, txt, strokeA = C.btn, C.text, 0.07
    if not b.isEnabled then
        bgc, txt, strokeA = C.btnOff, C.off, 0.03
    elseif b.armed then
        bgc, txt, strokeA = b.down and C.dangerDown or C.dangerHover, WHITE, 0
    elseif opts.primary then
        bgc = b.down and C.accentDown or (b.hover and C.accentHover or C.accent)
        txt, strokeA = C.ink, 0
    elseif opts.danger then
        bgc = b.down and C.dangerDown or (b.hover and C.dangerHover or C.danger)
        txt, strokeA = b.hover and WHITE or C.bad, 0
    else
        bgc = b.down and C.btnDown or (b.hover and C.btnHover or C.btn)
    end
    b.bg:SetColor(bgc)
    b.stroke:SetColor(WHITE, strokeA)
    textColor(b.label, txt)
    b.label:SetText(b.armed and Tr(opts.confirm or b.baseText) or b.baseText)
    b.label:ClearAllPoints()
    b.label:SetPoint("CENTER", b, "CENTER", 0, (b.down and b.isEnabled) and -1 or 0)
end

function W.Button(parent, opts)
    local b = CreateFrame("Button", nil, parent)
    local h = opts.height or 30
    b:RegisterForClicks("LeftButtonUp")
    b.opts = opts
    b.requires = Tr(opts.requires)
    b.isEnabled = true
    b.hover, b.down, b.armed = false, false, false
    b.token = 0
    b.baseText = Tr(opts.text or "")

    local corner = min(7, h / 2)
    b.bg = W.Round(b, "BACKGROUND", 0, corner)
    b.stroke = W.Stroke(b, "BORDER", 0, corner)
    b.label = W.Text(b, "GameFontHighlight", C.text)

    -- largeur : toujours au moins celle du texte mesuré (le texte traduit est plus long que le français)
    b.label:SetText(b.baseText)
    local textW = b.label:GetStringWidth() or 0
    if opts.confirm then
        b.label:SetText(Tr(opts.confirm))
        textW = max(textW, b.label:GetStringWidth() or 0)
    end
    local width = max(opts.width or 0, ceil(textW + 34), opts.minWidth or 96)
    b:SetSize(width, h)

    local function disarm()
        b.armed = false
        b.token = b.token + 1
    end

    function b:SetLabel(text)
        self.baseText = Tr(text or "")
        paintButton(self)
    end

    function b:Refresh()
        if ns.db or not opts.enabled then
            self.isEnabled = evalEnabled(opts)
        end
        if opts.getText and ns.db then self.baseText = Tr(opts.getText()) end
        paintButton(self)
    end

    b:SetScript("OnEnter", function(self) self.hover = true paintButton(self) end)
    b:SetScript("OnLeave", function(self) self.hover = false self.down = false paintButton(self) end)
    b:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and self.isEnabled then self.down = true paintButton(self) end
    end)
    b:SetScript("OnMouseUp", function(self)
        if self.down then self.down = false paintButton(self) end
    end)
    b:SetScript("OnHide", function(self)
        self.hover, self.down = false, false
        disarm()
        paintButton(self)
    end)
    b:SetScript("OnClick", function(self)
        if not self.isEnabled then return end
        if opts.confirm then
            if not self.armed then
                self.armed = true
                self.token = self.token + 1
                local token = self.token
                paintButton(self)
                W.Sound("click")
                if C_Timer and C_Timer.After then
                    C_Timer.After(CONFIRM_DELAY, function()
                        if self.token == token and self.armed then
                            disarm()
                            paintButton(self)
                        end
                    end)
                end
                return
            end
            disarm()
            paintButton(self)
        end
        W.Sound("click")
        if opts.onClick then opts.onClick(self) end
    end)

    if opts.tip then W.SetTip(b, opts.tipTitle or opts.text, opts.tip) end
    b:Refresh()
    return b
end

-- Rangée de boutons (passe à la ligne si besoin) ; list = { opts de W.Button, ... }
function W.ButtonRow(parent, list)
    local width = innerW(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    f.noDivider = true
    f.topGap = 12
    f.buttons = {}
    local x, y, lineH = 0, 0, 0
    for i, o in ipairs(list) do
        local b = W.Button(f, o)
        local bw = b:GetWidth() or 0
        if x > 0 and x + bw > width then
            x, y, lineH = 0, y + lineH + 8, 0
        end
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        x = x + bw + 8
        lineH = max(lineH, b:GetHeight() or 0)
        f.buttons[i] = b
    end
    f:SetHeight(y + lineH + 6)
    function f:Refresh()
        for _, b in ipairs(self.buttons) do b:Refresh() end
    end
    return f
end

---------------------------------------------------------------------------
-- Texte d'aide (gris, plusieurs lignes, hauteur calculée)
---------------------------------------------------------------------------
function W.Help(parent, text, opts)
    opts = opts or {}
    local width = innerW(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    f.noDivider = true
    f.topGap = opts.gap or 6
    local indent = (opts.indent or 0) * W.INDENT
    local fs = W.Text(f, "GameFontHighlightSmall", opts.color or C.dim)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", indent, 0)
    fs:SetWidth(width - indent)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    f.fs = fs

    function f:SetHelp(newText)
        newText = Tr(newText)
        fs:SetText(newText or "")
        self:SetHeight(measure(fs, newText, width - indent) + 6)
        if self.onResize then self.onResize() end
    end
    function f:Refresh() end

    f:SetHelp(text)
    return f
end

---------------------------------------------------------------------------
-- Encadré d'information (kind = "info" bleu, "warn" or)
---------------------------------------------------------------------------
function W.Note(parent, text, kind)
    local width = innerW(parent)
    local warn = (kind == "warn")
    local c = warn and C.gold or C.accent
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    f.noDivider = true
    f.topGap = 10
    local bg = W.Round(f, "BACKGROUND", 0, 8)
    bg:SetColor(c, 0.07)
    local stroke = W.Stroke(f, "BORDER", 0, 8)
    stroke:SetColor(c, 0.22)
    local dot = newTex(f, TEX.circle, "ARTWORK")
    dot:SetSize(18, 18)
    dot:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    dot:SetVertexColor(c[1], c[2], c[3], 0.95)
    local mark = W.Text(f, "GameFontHighlightSmall", C.ink, "OVERLAY", 12)
    mark:SetPoint("CENTER", dot, "CENTER", 0, 0)
    mark:SetText(warn and "!" or "i")
    local fs = W.Text(f, "GameFontHighlightSmall", C.text)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -12)
    fs:SetWidth(width - 54)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")

    function f:SetNote(newText)
        newText = Tr(newText)
        fs:SetText(newText or "")
        self:SetHeight(max(38, measure(fs, newText, width - 54) + 24))
        if self.onResize then self.onResize() end
    end
    function f:Refresh() end

    f:SetNote(text)
    return f
end

---------------------------------------------------------------------------
-- Ligne d'information : libellé à gauche, valeur à droite (opts.text() renvoie la valeur, couleurs permises)
---------------------------------------------------------------------------
function W.Info(parent, opts)
    local row = CreateFrame("Frame", nil, parent)
    initRow(row, parent, opts)
    row:EnableMouse(true)
    local width = row:GetWidth()
    local labelW = opts.labelWidth or 190
    local label = W.Text(row, "GameFontHighlight", C.text)
    label:SetPoint("LEFT", row, "LEFT", row.indent, 0)
    label:SetWidth(labelW)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(Tr(opts.label or ""))
    row.label = label
    local value = W.Text(row, "GameFontHighlight", C.text)
    value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    value:SetWidth(width - row.indent - labelW - 12)
    value:SetJustifyH("RIGHT")
    value:SetWordWrap(false)
    row.value = value

    function row:Refresh()
        if not ns.db then return end
        value:SetText(Tr(opts.text and opts.text() or ""))
    end

    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", rowLeave)
    if opts.tip then W.SetTip(row, opts.tipTitle or opts.label, opts.tip, nil, { side = true }) end
    row:Refresh()
    return row
end

---------------------------------------------------------------------------
-- Capteur de touche dessiné comme des touches de clavier
-- opts : key (défaut "key"), label, tip
---------------------------------------------------------------------------
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}

-- « ALT-CTRL-SHIFT-TOUCHE », l'ordre de WoW
local function composeBinding(key)
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix .. key
end

-- « SHIFT-F » -> { "Maj", "F" } (textes du jeu quand ils existent) ; out est réutilisé
local MOD_GLOBALS = { ALT = "ALT_KEY_TEXT", CTRL = "CTRL_KEY_TEXT", SHIFT = "SHIFT_KEY_TEXT" }
local MOD_FALLBACK = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Maj" }

local function keyParts(binding, out)
    for i = #out, 1, -1 do out[i] = nil end
    if not binding or binding == "" then return out end
    local rest = binding
    while true do
        local m, r = rest:match("^(%u+)%-(.+)$")
        if m and MOD_GLOBALS[m] then
            out[#out + 1] = rawget(_G, MOD_GLOBALS[m]) or MOD_FALLBACK[m]
            rest = r
        else
            break
        end
    end
    out[#out + 1] = _G["KEY_" .. rest] or rest
    return out
end

local prettyBuffer = {}
local function prettyKey(binding)
    if not binding or binding == "" then return "(aucune)" end
    return table.concat(keyParts(binding, prettyBuffer), " + ")
end
W.PrettyKey = prettyKey

-- nom lisible de l'action que le jeu lie à cette touche (sans tenir compte des liaisons de Platyplus)
local function gameActionFor(binding)
    if not binding or binding == "" then return nil end
    local ok, action = pcall(GetBindingAction, binding)
    if ok and type(action) == "string" and action ~= "" then
        return _G["BINDING_NAME_" .. action] or action
    end
    return nil
end

local activeCapture

-- Arrête l'écoute en cours, s'il y en a une (fermeture de la fenêtre, changement d'onglet)
function W.CancelCapture()
    if activeCapture then activeCapture:Stop() end
end

local CAP_H = 34
local MAX_CAPS = 4

local function newKeycap(zone)
    local cap = CreateFrame("Frame", nil, zone)
    cap:SetHeight(CAP_H + 3)
    local base = W.Round(cap, "BACKGROUND", 0, 7)
    base:AnchorBox(cap, 0, 3, 0, 0)
    base:SetColor(C.capBase)
    local face = W.Round(cap, "BORDER", 0, 7)
    face:AnchorBox(cap, 0, 0, 0, 3)
    face:SetColor(C.capFace)
    local edge = W.Stroke(cap, "BORDER", 1, 7)
    edge:AnchorBox(cap, 0, 0, 0, 3)
    edge:SetColor(WHITE, 0.08)
    local shine = newTex(cap, TEX.grad, "ARTWORK", 0)
    shine:SetPoint("TOPLEFT", cap, "TOPLEFT", 5, -2)
    shine:SetPoint("TOPRIGHT", cap, "TOPRIGHT", -5, -2)
    shine:SetHeight(14)
    shine:SetVertexColor(1, 1, 1, 0.06)
    local text = W.Text(cap, "GameFontHighlight", C.text, "OVERLAY", 15)
    text:SetPoint("CENTER", cap, "CENTER", 0, 1.5)
    cap.text = text
    return cap
end

function W.KeyCapture(parent, opts)
    opts = opts or {}
    local keyName = opts.key or "key"
    local default = ns.DEFAULTS and ns.DEFAULTS[keyName] or "F"
    local width = innerW(parent)
    local ZONE_H, SIDE = 84, 168

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, ZONE_H + 8)
    f.opts = opts
    f.noDivider = true
    f.topGap = 4

    local zone = CreateFrame("Frame", nil, f)
    zone:SetSize(width - SIDE - 14, ZONE_H)
    zone:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    zone:EnableMouse(true)
    local zoneBg = W.Round(zone, "BACKGROUND", 0, 9)
    local zoneStroke = W.Stroke(zone, "BORDER", 0, 9)
    local glow = newTex(zone, TEX.glow, "BACKGROUND", 1)
    glow:SetPoint("TOPLEFT", zone, "TOPLEFT", 20, -6)
    glow:SetPoint("BOTTOMRIGHT", zone, "BOTTOMRIGHT", -20, 14)
    glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.10)

    local caps, pluses = {}, {}
    local listenText = W.Text(zone, "GameFontHighlight", C.accent, "OVERLAY", 15)
    listenText:SetPoint("CENTER", zone, "CENTER", 0, 8)
    listenText:SetText(Tr("Appuie sur une touche…"))
    listenText:Hide()
    local hint = W.Text(zone, "GameFontHighlightSmall", C.dim)
    hint:SetPoint("BOTTOM", zone, "BOTTOM", 0, 9)

    local side = CreateFrame("Frame", nil, f)
    side:SetSize(SIDE, ZONE_H)
    side:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

    local warnDot = newTex(f, TEX.circle, "ARTWORK")
    warnDot:SetSize(16, 16)
    warnDot:SetPoint("TOPLEFT", zone, "BOTTOMLEFT", 2, -11)
    warnDot:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    local warnMark = W.Text(f, "GameFontHighlightSmall", C.ink, "OVERLAY", 11)
    warnMark:SetPoint("CENTER", warnDot, "CENTER", 0, 0)
    warnMark:SetText("!")
    local conflict = W.Text(f, "GameFontHighlightSmall", C.gold)
    conflict:SetPoint("TOPLEFT", zone, "BOTTOMLEFT", 26, -12)
    conflict:SetWidth(width - 28)
    conflict:SetJustifyH("LEFT")
    conflict:SetJustifyV("TOP")

    local listening = false
    local pulseT = 0
    zone.hover = false
    local parts = {}

    local function layoutCaps(binding)
        keyParts(binding, parts)
        if #parts == 0 then parts[1] = "aucune" end
        local n = min(#parts, MAX_CAPS)
        local total = 0
        for i = 1, n do
            local cap = caps[i]
            if not cap then
                cap = newKeycap(zone)
                caps[i] = cap
            end
            cap.text:SetText(parts[i])
            local w = max(CAP_H + 8, ceil((cap.text:GetStringWidth() or 0) + 26))
            cap:SetWidth(w)
            cap.w = w
            total = total + w
        end
        total = total + (n - 1) * 22
        local x = floor(((zone:GetWidth() or 0) - total) / 2)
        for i = 1, n do
            local cap = caps[i]
            cap:ClearAllPoints()
            cap:SetPoint("LEFT", zone, "LEFT", x, 8)
            cap:Show()
            x = x + cap.w
            if i < n then
                local p = pluses[i]
                if not p then
                    p = W.Text(zone, "GameFontHighlight", C.dim, "OVERLAY", 14)
                    p:SetText("+")
                    pluses[i] = p
                end
                p:ClearAllPoints()
                p:SetPoint("CENTER", zone, "LEFT", x + 11, 9)
                p:Show()
                x = x + 22
            end
        end
        for i = n + 1, #caps do caps[i]:Hide() end
        for i = max(n, 1), #pluses do pluses[i]:Hide() end
    end

    local function setCapsShown(shown)
        if not shown then
            for _, cap in ipairs(caps) do cap:Hide() end
            for _, p in ipairs(pluses) do p:Hide() end
        end
    end

    local changeButton, resetButton

    local function paint()
        local binding = ns.db and ns.db[keyName]
        if listening then
            setCapsShown(false)
            listenText:Show()
            hint:SetText(Tr("Échap ou clic gauche = annuler · boutons de souris acceptés"))
            textColor(hint, C.dim)
            zoneBg:SetColor(C.fieldListen)
            glow:Show()
        else
            listenText:Hide()
            layoutCaps(binding)
            hint:SetText(Tr("Clique ici pour changer de touche"))
            textColor(hint, zone.hover and C.text or C.dim)
            zoneBg:SetColor(zone.hover and C.fieldHover or C.field)
            zoneStroke:SetColor(zone.hover and WHITE or C.stroke, zone.hover and 0.16 or nil)
            glow:Hide()
        end
        local other = not listening and gameActionFor(binding)
        local h = ZONE_H + 8
        if other then
            conflict:SetText(Tf("Le jeu lie aussi cette touche à : |cffffffff%s|r. Platyplus a la priorité : cette action ne marchera plus avec cette touche tant que Platyplus l'utilise.", other))
            warnDot:Show()
            warnMark:Show()
            h = ZONE_H + 12 + measure(conflict, conflict:GetText(), width - 28) + 8
        else
            conflict:SetText("")
            warnDot:Hide()
            warnMark:Hide()
        end
        if abs((f:GetHeight() or 0) - h) > 0.5 then
            f:SetHeight(h)
            if f.onResize then f.onResize() end
        end
        if changeButton then
            changeButton:SetLabel(listening and "Annuler" or "Changer la touche")
        end
    end

    -- contour qui respire pendant l'écoute (OnUpdate seulement pendant l'écoute)
    local function pulse(self, elapsed)
        pulseT = pulseT + elapsed
        zoneStroke:SetColor(C.accent, 0.55 + 0.35 * sin(pulseT * 5))
    end

    -- Le clavier n'est écouté QUE pendant l'écoute : dans WoW, poser un script OnKeyDown active le clavier du cadre,
    -- qui avale alors toutes les touches (Échap ne fermait plus la fenêtre, et l'autre capteur de la page volait la
    -- touche). Comme le KeybindListener de Blizzard (Blizzard_Keybindings.lua de Forever), le script est posé au
    -- début de l'écoute et retiré à la fin.
    local onKeyDown, commit

    local function stop()
        if not listening then return end
        listening = false
        zone:SetScript("OnUpdate", nil)
        zone:SetScript("OnKeyDown", nil)
        zone:EnableKeyboard(false)
        pcall(zone.SetPropagateKeyboardInput, zone, true)
        if activeCapture == zone then activeCapture = nil end
        paint()
    end
    zone.Stop = stop

    local function start()
        if activeCapture and activeCapture ~= zone then activeCapture:Stop() end
        listening = true
        activeCapture = zone
        zone:SetScript("OnKeyDown", onKeyDown)
        zone:EnableKeyboard(true)
        -- SetPropagateKeyboardInput peut être refusé en combat sur les clients récents : protégé
        pcall(zone.SetPropagateKeyboardInput, zone, false)
        pulseT = 0
        zone:SetScript("OnUpdate", pulse)
        pulse(zone, 0)
        paint()
    end

    commit = function(binding)
        stop()
        ns:Set(keyName, binding)
        W.Sound("on")
        f:Refresh()
        -- Interact applique la liaison juste après : on relit « touche liée à » un instant plus tard
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, function()
                if f:IsVisible() and ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            end)
        end
    end

    onKeyDown = function(self, key)
        if not listening then return end
        if key == "ESCAPE" then
            stop()
            return
        end
        if MODIFIER_KEYS[key] then return end
        commit(composeBinding(key))
    end
    zone:EnableKeyboard(false)          -- au repos : aucune touche interceptée
    zone.IsListening = function() return listening end

    zone:SetScript("OnMouseDown", function(self, button)
        if not listening then
            if button == "LeftButton" then
                W.Sound("click")
                start()
            end
            return
        end
        if button == "LeftButton" then
            stop()           -- 2e clic gauche : annule
            return
        end
        if button == "RightButton" then return end
        local name
        if button == "MiddleButton" then
            name = "BUTTON3"
        else
            local n = tostring(button):match("^Button(%d+)$")
            if n then name = "BUTTON" .. n end
        end
        if name then commit(composeBinding(name)) end
    end)

    zone:SetScript("OnEnter", function(self) self.hover = true if not listening then paint() end end)
    zone:SetScript("OnLeave", function(self) self.hover = false if not listening then paint() end end)
    zone:SetScript("OnHide", stop)

    changeButton = W.Button(side, {
        text = "Changer la touche", width = SIDE, height = 32, primary = true,
        tip = "Écoute la prochaine touche appuyée (avec Maj, Ctrl ou Alt si tu veux). "
            .. "Pour un bouton de souris, clique avec ce bouton dans le cadre de gauche.",
        onClick = function()
            if listening then stop() else start() end
        end,
    })
    changeButton:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -6)

    resetButton = W.Button(side, {
        text = "Remettre " .. prettyKey(default),
        width = SIDE, height = 32,
        tip = "Rétablit la touche par défaut de Platyplus (" .. prettyKey(default) .. ").",
        enabled = function() return ns.db[keyName] ~= default end,
        onClick = function()
            stop()
            ns:Reset(keyName)
            f:Refresh()
        end,
    })
    resetButton:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 6)
    f.reset = resetButton

    function f:Refresh()
        if not ns.db then return end
        paint()
        resetButton:Refresh()
    end

    W.SetTip(zone, opts.label or "Touche d'interaction",
        opts.tip or "Clique ici puis appuie sur la touche voulue (avec Maj, Ctrl ou Alt si tu veux). Pour un bouton de souris (molette, boutons latéraux), clique dans ce cadre avec ce bouton. Échap annule.")

    f:Refresh()
    return f
end

---------------------------------------------------------------------------
-- Éditeur de liste d'objets (neverSell / alwaysSell)
-- opts : list = "neverSell" | "alwaysSell", label, tip
---------------------------------------------------------------------------
local LIST_ROW_H, LIST_ROW_GAP = 30, 3
local DROP_H, INPUT_H = 54, 30
local LIST_TOP = DROP_H + 10 + INPUT_H + 8 + 16 + 8
local LIST_MAX_ROWS = 200

local function sortedIds(list)
    local ids = {}
    if type(list) == "table" then
        for id, on in pairs(list) do
            local n = tonumber(id)
            if on and n then ids[#ids + 1] = n end
        end
    end
    table.sort(ids)
    return ids
end

local function addToList(listName, id)
    if ns.Junk and ns.Junk.AddToList then
        ns.Junk:AddToList(listName, id)
    else
        local t = ns.db[listName]
        if type(t) ~= "table" then t = {} end
        t[id] = true
        ns:Set(listName, t)
    end
end

local function removeFromList(listName, id)
    if ns.Junk and ns.Junk.RemoveFromList then
        ns.Junk:RemoveFromList(listName, id)
    else
        local t = ns.db[listName]
        if type(t) ~= "table" then t = {} end
        t[id] = nil
        ns:Set(listName, t)
    end
end

local function hideOwnTip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- Petit bouton rond « × »
local function closeGlyphButton(parent, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:RegisterForClicks("LeftButtonUp")
    local bg = newTex(b, TEX.circle, "BACKGROUND")
    bg:SetAllPoints(b)
    local x = W.Text(b, "GameFontHighlight", C.dim, "OVERLAY", floor(size * 0.62 + 0.5))
    x:SetPoint("CENTER", b, "CENTER", 0.5, 1)
    x:SetText("×")
    local function paint(hover)
        if hover then
            bg:SetVertexColor(C.bad[1], C.bad[2], C.bad[3], 0.9)
            textColor(x, WHITE)
        else
            bg:SetVertexColor(1, 1, 1, 0.05)
            textColor(x, C.dim)
        end
    end
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnClick", onClick)
    paint(false)
    b.glyph, b.bgTex = x, bg
    return b
end
W.CloseGlyphButton = closeGlyphButton

-- Spécificités d'une liste d'objets / de sorts : le reste du widget est commun
local ITEM_KIND = {
    one = "%d objet", many = "%d objets",
    drop = "Glisse ici un objet de tes sacs", dropSub = "ou tape son ID / colle son lien juste en dessous",
    placeholder = "ID d'objet ou lien, puis Entrée", empty = "Aucun objet dans cette liste pour l'instant.",
    addTip = "Ajoute à la liste l'objet dont tu as tapé l'ID ou collé le lien.", removeTip = "Retire cet objet de la liste.",
    cursor = function()
        local kind, id = GetCursorInfo()
        if kind == "item" then return id end
    end,
    holds = function() return GetCursorInfo() == "item" end,
    parse = function(raw)
        local text = tostring(raw or "")
        local id = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
        if not id or id <= 0 or id ~= floor(id) then
            return nil, Tr("Entre un ID d'objet (ex. 6948) ou colle un lien d'objet.")
        end
        if C_Item and C_Item.GetItemInfoInstant and not C_Item.GetItemInfoInstant(id) then
            return nil, Tf("L'ID %d ne correspond à aucun objet du jeu.", id)
        end
        return id
    end,
    already = "Cet objet est déjà dans la liste.",
    add = function(listName, id) addToList(listName, id) end,
    remove = function(listName, id) removeFromList(listName, id) end,
    describe = function(id)
        local name, known = itemName(id)
        local q = known and itemQuality(id) or nil
        return itemIcon(id) or QUESTION, q and W.Quality(q, name) or name, name
    end,
    tip = function(self)
        local id = self.itemID
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id)
        if not ok then GameTooltip:SetText((itemName(id)), 1, 1, 1) end
        GameTooltip:Show()
    end,
    loadEvent = "GET_ITEM_INFO_RECEIVED",
}

local function buildList(parent, opts, K)
    local listName = opts.list
    local width = innerW(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, LIST_TOP + 30)
    f.opts = opts
    f.rows = {}
    f.noDivider = true
    f.topGap = 2

    -- zone de dépôt
    local drop = CreateFrame("Frame", nil, f)
    drop:SetSize(width, DROP_H)
    drop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drop:EnableMouse(true)
    local dropBg = W.Round(drop, "BACKGROUND", 0, 9)
    local dropStroke = W.Stroke(drop, "BORDER", 0, 9)
    local plus = newTex(drop, TEX.circle, "ARTWORK")
    plus:SetSize(26, 26)
    plus:SetPoint("LEFT", drop, "LEFT", 14, 0)
    local plusText = W.Text(drop, "GameFontHighlight", C.ink, "OVERLAY", 17)
    plusText:SetPoint("CENTER", plus, "CENTER", 0.5, 1)
    plusText:SetText("+")
    local dropText = W.Text(drop, "GameFontHighlight", C.text)
    dropText:SetPoint("TOPLEFT", plus, "TOPRIGHT", 12, 1)
    dropText:SetText(Tr(K.drop))
    local dropSub = W.Text(drop, "GameFontHighlightSmall", C.dim)
    dropSub:SetPoint("TOPLEFT", dropText, "BOTTOMLEFT", 0, -3)
    dropSub:SetText(Tr(K.dropSub))

    -- state : "idle", "hover" (souris dessus, rien en main), "ready" (un objet est tenu)
    local function paintDrop(state)
        if state == "ready" then
            dropBg:SetColor(C.accent, 0.10)
            dropStroke:SetColor(C.accent, 0.85)
            plus:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
            textColor(dropText, C.accent)
        else
            dropBg:SetColor(state == "hover" and C.fieldHover or C.field)
            dropStroke:SetColor(WHITE, state == "hover" and 0.16 or 0.07)
            plus:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], state == "hover" and 1 or 0.7)
            textColor(dropText, C.text)
        end
    end
    paintDrop("idle")

    local status = W.Text(f, "GameFontHighlightSmall", C.dim)
    status:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(DROP_H + 10 + INPUT_H + 8))
    status:SetWidth(width - 120)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    local count = W.Text(f, "GameFontHighlightSmall", C.dim)
    count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -(DROP_H + 10 + INPUT_H + 8))
    count:SetJustifyH("RIGHT")

    local function setStatus(text, color)
        status:SetText(text or "")
        textColor(status, color or C.dim)
    end

    -- ajout d'un ID (nombre, nom ou lien selon la liste)
    local function addItem(raw)
        local id, err = K.parse(raw)
        if not id then
            setStatus(err, C.bad)
            return false
        end
        local current = ns.db[listName]
        if type(current) == "table" and current[id] then
            setStatus(Tr(K.already), C.gold)
            return false
        end
        K.add(listName, id)
        f:Render()
        setStatus(Tf("Ajouté : %s", (select(3, K.describe(id)))), C.good)
        W.Sound("on")
        return true
    end

    local function receiveCursor()
        local id = K.cursor()
        if id then
            -- Un sort pris sur une barre en a été retiré (PickupAction) : on le garde en main
            -- pour que le joueur le repose, au lieu de le jeter avec ClearCursor.
            if not K.keepCursor then ClearCursor() end
            if addItem(id) and K.keepCursor and K.holds() then
                setStatus(Tr("Ajouté. Repose le sort sur ta barre s'il en venait."), C.gold)
            end
        elseif K.keepCursor and K.holds() then
            setStatus(Tr("Numéro du sort introuvable : tape son nom ou son numéro à la place."), C.bad)
        end
        paintDrop("idle")
    end
    drop:SetScript("OnReceiveDrag", receiveCursor)
    drop:SetScript("OnMouseUp", receiveCursor)
    drop:SetScript("OnEnter", function()
        paintDrop(K.holds() and "ready" or "hover")
    end)
    drop:SetScript("OnLeave", function() paintDrop("idle") end)

    -- champ texte arrondi
    local box = CreateFrame("EditBox", nil, f)
    box:SetSize(width - 110, INPUT_H)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(DROP_H + 10))
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    box:SetTextInsets(12, 12, 0, 0)
    box:SetMaxLetters(400)
    local boxBg = W.Round(box, "BACKGROUND", 0, 7)
    boxBg:SetColor(C.field)
    local boxStroke = W.Stroke(box, "BORDER", 0, 7)
    boxStroke:SetColor(C.stroke)
    local placeholder = W.Text(box, "GameFontHighlightSmall", C.off)
    placeholder:SetPoint("LEFT", box, "LEFT", 12, 0)
    placeholder:SetText(Tr(K.placeholder))

    local function updatePlaceholder()
        placeholder:SetShown((box:GetText() or "") == "" and not box:HasFocus())
    end
    box:SetScript("OnEditFocusGained", function()
        boxStroke:SetColor(C.accent, 0.85)
        updatePlaceholder()
    end)
    box:SetScript("OnEditFocusLost", function()
        boxStroke:SetColor(C.stroke)
        updatePlaceholder()
    end)
    box:SetScript("OnTextChanged", updatePlaceholder)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    local function submit()
        if addItem(box:GetText()) then box:SetText("") end
    end
    box:SetScript("OnEnterPressed", submit)

    local addButton = W.Button(f, { text = "Ajouter", width = 100, height = INPUT_H, onClick = submit,
        tip = K.addTip })
    addButton:SetPoint("LEFT", box, "RIGHT", 10, 0)

    local empty = W.Text(f, "GameFontHighlightSmall", C.off)
    empty:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(LIST_TOP + 6))
    empty:SetText(Tr(K.empty))

    local moreText = W.Text(f, "GameFontHighlightSmall", C.dim)
    moreText:Hide()

    local function newRow(i)
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(width, LIST_ROW_H)
        r:EnableMouse(true)
        local rbg = W.Round(r, "BACKGROUND", 0, 7)
        rbg:SetColor(WHITE, 0.035)
        r.bg = rbg
        r.icon = iconTex(r, 22)
        r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.name = W.Text(r, "GameFontHighlight", C.text)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.name:SetWidth(width - 160)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.id = W.Text(r, "GameFontHighlightSmall", C.dim)
        r.id:SetPoint("RIGHT", r, "RIGHT", -38, 0)
        r.id:SetJustifyH("RIGHT")
        r.remove = closeGlyphButton(r, 22, function()
            K.remove(listName, r.itemID)
            W.Sound("off")
            f:Render()
        end)
        r.remove:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        W.SetTip(r.remove, "Retirer", K.removeTip)
        r:SetScript("OnEnter", function(self)
            self.bg:SetColor(WHITE, 0.07)
            K.tip(self)
        end)
        r:SetScript("OnLeave", function(self)
            self.bg:SetColor(WHITE, 0.035)
            hideOwnTip(self)
        end)
        f.rows[i] = r
        return r
    end

    function f:Render()
        local ids = sortedIds(ns.db and ns.db[listName])
        count:SetText(#ids == 0 and "" or Tf(#ids > 1 and K.many or K.one, #ids))
        local shown = min(#ids, LIST_MAX_ROWS)
        for i = 1, shown do
            local r = self.rows[i] or newRow(i)
            local id = ids[i]
            r.itemID = id
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(LIST_TOP + (i - 1) * (LIST_ROW_H + LIST_ROW_GAP)))
            local icon, text = K.describe(id)
            r.icon:SetTexture(icon)
            r.name:SetText(text)
            r.id:SetText("#" .. id)
            r:Show()
        end
        for i = shown + 1, #self.rows do self.rows[i]:Hide() end
        empty:SetShown(#ids == 0)

        local h = LIST_TOP + 26
        if shown > 0 then h = LIST_TOP + shown * (LIST_ROW_H + LIST_ROW_GAP) + 4 end
        if #ids > shown then
            moreText:ClearAllPoints()
            moreText:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -h)
            moreText:SetText(Tf("… et %d autres", #ids - shown))
            moreText:Show()
            h = h + 20
        else
            moreText:Hide()
        end
        if abs((self:GetHeight() or 0) - h) > 0.5 then
            self:SetHeight(h)
            if self.onResize then self.onResize() end
        end
    end

    -- noms d'objets : le jeu les charge à la demande (événement écouté seulement quand la liste est visible)
    local events = CreateFrame("Frame")
    local eventsOn = false
    local pending = false
    events:SetScript("OnEvent", function(_, event, itemID)
        local list = ns.db and ns.db[listName]
        if event ~= K.loadEvent or type(list) ~= "table" or not list[itemID] then return end
        if pending then return end
        if C_Timer and C_Timer.After then
            pending = true
            C_Timer.After(0.1, function()
                pending = false
                if f:IsVisible() then f:Render() end
            end)
        else
            f:Render()
        end
    end)
    local function setEvents(on)
        if on == eventsOn then return end
        eventsOn = on
        if on then
            if K.loadEvent then pcall(events.RegisterEvent, events, K.loadEvent) end
        else
            if K.loadEvent then pcall(events.UnregisterEvent, events, K.loadEvent) end
        end
    end
    f:SetScript("OnHide", function() setEvents(false) end)
    f:SetScript("OnShow", function() setEvents(true) end)

    function f:Refresh(key)
        if key and key ~= listName then return end
        if not ns.db then return end
        setEvents(self:IsVisible())
        self:Render()
    end

    W.SetTip(drop, opts.label, opts.tip)
    f:Refresh()
    return f
end

function W.ItemList(parent, opts)
    return buildList(parent, opts, ITEM_KIND)
end

---------------------------------------------------------------------------
-- Éditeur de liste de sorts (procExtra / procIgnore) : même widget, avec des sorts
-- opts : list = "procExtra" | "procIgnore", label, tip
-- Vérifié dans le code de Forever : GetCursorInfo() -> "spell", emplacement, type de livre, spellID
-- (Blizzard_ClickBindingUI.lua : cursorType == "spell" -> le 4e retour est le numéro) ; C_Spell.GetSpellInfo accepte un
-- numéro, un nom ou un lien et renvoie { name, iconID, spellID } ou rien (doc API générée).
---------------------------------------------------------------------------
local function plainValue(v)
    local sec = rawget(_G, "issecretvalue")
    if v == nil or (type(sec) == "function" and sec(v)) then return nil end
    return v
end

-- numéro, nom, icône d'un sort (nil si le jeu ne le connaît pas) ; tout en pcall
local function spellData(identifier)
    local api = rawget(_G, "C_Spell")
    if type(api) ~= "table" or type(api.GetSpellInfo) ~= "function" then return nil end
    local ok, info = pcall(api.GetSpellInfo, identifier)
    if not ok or type(info) ~= "table" then return nil end
    local id, name, icon = plainValue(info.spellID), plainValue(info.name), plainValue(info.iconID)
    if type(id) ~= "number" then id = tonumber(identifier) end
    if type(name) ~= "string" or not id then return nil end
    return id, name, icon
end

local function copyList(listName)
    local t = {}
    for k, v in pairs(type(ns.db[listName]) == "table" and ns.db[listName] or {}) do t[k] = v end
    return t
end

local SPELL_KIND = {
    one = "%d sort", many = "%d sorts",
    drop = "Glisse ici un sort de ton grimoire",
    keepCursor = true,
    dropSub = "ou tape son nom ou son numéro juste en dessous",
    placeholder = "Nom ou numéro du sort, puis Entrée", empty = "Aucun sort dans cette liste pour l'instant.",
    addTip = "Ajoute à la liste le sort dont tu as tapé le nom ou le numéro.", removeTip = "Retire ce sort de la liste.",
    cursor = function()
        local kind, a, _, spellID = GetCursorInfo()
        if kind == "spell" then return tonumber(spellID) end
    end,
    holds = function() return GetCursorInfo() == "spell" end,
    parse = function(raw)
        local text = strtrim(tostring(raw or ""))
        local id = tonumber(text:match("spell:(%d+)")) or tonumber(text:match("^(%d+)$"))
        if id then
            if rawget(_G, "C_Spell") and not spellData(id) then
                return nil, Tf("Le numéro %d ne correspond à aucun sort du jeu.", id)
            end
            return id
        end
        if text == "" then return nil, Tr("Tape le nom d'un sort (ex. Exécution) ou son numéro.") end
        local rid = spellData(text)
        if not rid then
            return nil, Tf("Aucun sort nommé « %s » dans ton grimoire. Glisse-le plutôt ici, ou tape son numéro.", text)
        end
        return rid
    end,
    already = "Ce sort est déjà dans la liste.",
    add = function(listName, id)
        local t = copyList(listName)
        t[id] = true
        ns:Set(listName, t)
    end,
    remove = function(listName, id)
        local t = copyList(listName)
        t[id] = nil
        ns:Set(listName, t)
    end,
    describe = function(id)
        local _, name, icon = spellData(id)
        name = name or Tf("Sort #%d", id)
        return icon or QUESTION, name, name
    end,
    tip = function(self)
        local id = self.itemID
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, id)
        if not ok then GameTooltip:SetText(Tf("Sort #%d", id), 1, 1, 1) end
        GameTooltip:Show()
    end,
}

function W.SpellList(parent, opts)
    return buildList(parent, opts, SPELL_KIND)
end

---------------------------------------------------------------------------
-- Aperçu de la vente : liste de ce que ns.Junk:BuildList() vendrait
-- opts : keys = { [clé de réglage] = true } qui déclenchent une mise à jour (avec délai)
---------------------------------------------------------------------------
local PREVIEW_ROW_H, PREVIEW_TOP = 28, 58
local PREVIEW_MAX_ROWS = 40
local REASONS = {
    junk   = { text = "Gris",            color = { 0.70, 0.70, 0.72, 1 } },
    gear   = { text = "Équipement",      color = { 1.00, 0.62, 0.25, 1 } },
    always = { text = "Toujours vendre", color = C.accent },
}

function W.Preview(parent, opts)
    opts = opts or {}
    local width = innerW(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 60)
    f.opts = opts
    f.rows = {}
    f.entries = nil
    f.scheduled = false
    f.noDivider = true
    f.topGap = 12

    -- bandeau de total
    local band = CreateFrame("Frame", nil, f)
    band:SetSize(width, 46)
    band:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    local bandBg = W.Round(band, "BACKGROUND", 0, 9)
    bandBg:SetColor(C.field)
    local coin = newTex(band, TEX.circle, "ARTWORK")
    coin:SetSize(26, 26)
    coin:SetPoint("LEFT", band, "LEFT", 12, 0)
    coin:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.18)
    local coinIcon = iconTex(band, 18, "OVERLAY")
    coinIcon:SetPoint("CENTER", coin, "CENTER", 0, 0)
    coinIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    local summary = W.Text(band, "GameFontHighlight", C.text)
    summary:SetPoint("LEFT", coin, "RIGHT", 12, 0)
    summary:SetWidth(width - 230)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    local total = W.Text(band, "GameFontHighlight", C.text, "OVERLAY", 14)
    total:SetPoint("RIGHT", band, "RIGHT", -14, 0)
    total:SetJustifyH("RIGHT")

    local moreText = W.Text(f, "GameFontHighlightSmall", C.dim)
    moreText:Hide()

    local function newRow(i)
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(width, PREVIEW_ROW_H)
        r:EnableMouse(true)
        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(r)
        stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
        r.icon = iconTex(r, 20)
        r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.name = W.Text(r, "GameFontHighlight", C.text)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.name:SetWidth(width - 300)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        -- étiquette de raison (pastille colorée)
        local tag = CreateFrame("Frame", nil, r)
        tag:SetSize(80, 18)
        tag:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        tag.bg = pill(tag, "BACKGROUND", 0, 18)
        tag.text = W.Text(tag, "GameFontHighlightSmall", C.dim)
        tag.text:SetPoint("CENTER", tag, "CENTER", 0, 0)
        r.tag = tag
        r.price = W.Text(r, "GameFontHighlightSmall", C.text)
        r.price:SetPoint("RIGHT", tag, "LEFT", -12, 0)
        r.price:SetJustifyH("RIGHT")
        r:SetScript("OnEnter", function(self)
            if not self.link then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) then
                GameTooltip:SetText(self.link, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", hideOwnTip)
        f.rows[i] = r
        return r
    end

    function f:Render()
        local entries = self.entries
        local shown = 0
        local h = 46

        if not entries then
            summary:SetText(Tr(self.err or "Clique sur « Actualiser l'aperçu » pour voir ce qui serait vendu."))
            textColor(summary, self.err and C.bad or C.dim)
            total:SetText("")
        elseif #entries == 0 then
            summary:SetText(Tr("Rien à vendre pour le moment avec ces réglages."))
            textColor(summary, C.dim)
            total:SetText("")
        else
            local sum, pieces = 0, 0
            for _, e in ipairs(entries) do
                sum = sum + (tonumber(e.price) or 0)
                pieces = pieces + (tonumber(e.count) or 1)
            end
            summary:SetText(Tf(pieces > 1 and "%d objets à vendre" or "%d objet à vendre", pieces))
            textColor(summary, C.text)
            total:SetText(W.FormatMoney(sum))
            shown = min(#entries, PREVIEW_MAX_ROWS)
            for i = 1, shown do
                local e = entries[i]
                local r = self.rows[i] or newRow(i)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(PREVIEW_TOP + (i - 1) * PREVIEW_ROW_H))
                r.link = e.link
                local icon = e.icon or (e.itemID and itemIcon(e.itemID))
                r.icon:SetTexture(icon or QUESTION)
                local name = e.link or (e.itemID and (itemName(e.itemID))) or "?"
                local cnt = tonumber(e.count) or 1
                r.name:SetText(cnt > 1 and (name .. " |cffffffff×" .. cnt .. "|r") or name)
                r.price:SetText(W.FormatMoney(e.price))
                local reason = REASONS[e.reason]
                local rc = reason and reason.color or C.dim
                r.tag.text:SetText(reason and Tr(reason.text) or tostring(e.reason or "?"))
                textColor(r.tag.text, rc)
                r.tag.bg:SetColor(rc, 0.14)
                r.tag:SetWidth(max(44, ceil((r.tag.text:GetStringWidth() or 0) + 20)))
                r:Show()
            end
            h = PREVIEW_TOP + shown * PREVIEW_ROW_H + 4
        end
        for i = shown + 1, #self.rows do self.rows[i]:Hide() end

        if entries and #entries > shown then
            moreText:ClearAllPoints()
            moreText:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -h)
            moreText:SetText(Tf("… et %d autres", #entries - shown))
            moreText:Show()
            h = h + 20
        else
            moreText:Hide()
        end

        if abs((self:GetHeight() or 0) - h) > 0.5 then
            self:SetHeight(h)
            if self.onResize then self.onResize() end
        end
    end

    -- recalcule la liste (ne modifie aucun réglage)
    function f:Update()
        if not (ns.Junk and ns.Junk.BuildList) then
            self.entries = nil
            self.err = "Le module de vente n'est pas disponible."
        else
            local ok, res = pcall(ns.Junk.BuildList, ns.Junk)
            if ok then
                self.entries = type(res) == "table" and res or {}
                self.err = nil
            else
                self.entries = nil
                self.err = "Erreur pendant le calcul de l'aperçu (voir l'erreur Lua)."
                geterrorhandler()(res)
            end
        end
        self:Render()
    end

    function f:ScheduleUpdate()
        if self.scheduled then return end
        if C_Timer and C_Timer.After then
            self.scheduled = true
            C_Timer.After(0.4, function()
                self.scheduled = false
                if self:IsVisible() then self:Update() end
            end)
        else
            self:Update()
        end
    end

    -- Un réglage de vente a changé : on recalcule (une seule fois si ça enchaîne)
    function f:Refresh(key)
        if not key or not (opts.keys and opts.keys[key]) then return end
        if self:IsVisible() then self:ScheduleUpdate() end
    end

    -- appelé à l'ouverture de l'onglet
    function f:OnPageShow()
        self:Update()
    end

    f:Render()
    return f
end

---------------------------------------------------------------------------
-- Liste de commandes : entries = { { "/pp config", "ouvre la fenêtre" }, ... }
---------------------------------------------------------------------------
function W.CommandList(parent, entries)
    local width = innerW(parent)
    local f = CreateFrame("Frame", nil, parent)
    local rowH = 24
    f:SetSize(width, #entries * rowH + 2)
    f.noDivider = true
    f.topGap = 2
    for i, e in ipairs(entries) do
        local y = -(i - 1) * rowH
        if i % 2 == 1 then
            local stripe = f:CreateTexture(nil, "BACKGROUND")
            stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
            stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
            stripe:SetHeight(rowH)
            stripe:SetColorTexture(1, 1, 1, 0.025)
        end
        local cmd = W.Text(f, "GameFontHighlight", C.accent)
        cmd:SetPoint("LEFT", f, "TOPLEFT", 10, y - rowH / 2)
        cmd:SetWidth(200)
        cmd:SetJustifyH("LEFT")
        cmd:SetWordWrap(false)
        cmd:SetText(e[1])
        local desc = W.Text(f, "GameFontHighlightSmall", C.dim)
        desc:SetPoint("LEFT", cmd, "RIGHT", 10, 0)
        desc:SetWidth(width - 230)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(false)
        desc:SetText(Tr(e[2]))
    end
    function f:Refresh() end
    return f
end

---------------------------------------------------------------------------
-- Piles : une page est une pile de cartes, une carte est une pile de lignes
---------------------------------------------------------------------------
local building = 0     -- > 0 : construction d'une page en cours, on ne range qu'à la fin

function W.BeginBuild()
    building = building + 1
end

-- fin de construction : on range chaque carte puis la page, une seule fois
function W.EndBuild(page)
    building = max(0, building - 1)
    if building > 0 or not page then return end
    page.frozen = true
    for _, w in ipairs(page.widgets) do
        if w.Relayout then w:Relayout() end
    end
    page.frozen = false
    page:Relayout()
end

local Stack = {}

function Stack:Relayout()
    if building > 0 or self.frozen then return end
    local px = self.padX or 0
    local y = self.padTop or 0
    local nDiv = 0
    local prev
    for _, w in ipairs(self.widgets) do
        if w:IsShown() then
            if prev then
                local gap = w.gap or 0
                if self.useDividers and not w.noDivider and not prev.noDivider then
                    nDiv = nDiv + 1
                    local d = self.dividers[nDiv]
                    if not d then
                        d = self:CreateTexture(nil, "BORDER", nil, 1)
                        d:SetHeight(1)
                        d:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
                        self.dividers[nDiv] = d
                    end
                    d:ClearAllPoints()
                    d:SetPoint("TOPLEFT", self, "TOPLEFT", px + (w.indent or 0), -(y + floor(gap / 2)))
                    d:SetPoint("TOPRIGHT", self, "TOPRIGHT", -px, -(y + floor(gap / 2)))
                    d:Show()
                end
                y = y + gap
            end
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", self, "TOPLEFT", px, -y)
            w.stackY = y               -- (haut de l'élément dans sa pile : le sommaire des options y défile)
            y = y + (w:GetHeight() or 0)
            prev = w
        end
    end
    if self.dividers then
        for i = nDiv + 1, #self.dividers do self.dividers[i]:Hide() end
    end
    y = y + (self.padBottom or 0)
    self.contentHeight = y
    self:SetHeight(max(y, 1))
    if self.onHeight then self.onHeight(y) end
    if self.onResize then self.onResize() end
end

function Stack:Add(widget, gap)
    if gap then
        widget.gap = gap
    elseif widget.noDivider or self.rowGap == nil then
        widget.gap = widget.topGap or self.rowGap or 4
    else
        widget.gap = self.rowGap
    end
    local stack = self
    widget.onResize = function() stack:Relayout() end
    self.widgets[#self.widgets + 1] = widget
    self:Relayout()
    return widget
end

-- key : clé de réglage qui vient de changer (nil = tout relire)
function Stack:Refresh(key)
    for _, w in ipairs(self.widgets) do
        if w.Refresh then w:Refresh(key) end
    end
end

-- l'onglet vient d'être affiché
function Stack:PageShown()
    for _, w in ipairs(self.widgets) do
        if w.PageShown then
            w:PageShown()
        elseif w.OnPageShow then
            w:OnPageShow()
        end
    end
end

local SHORTCUTS = {
    Help = "Help", Note = "Note", Info = "Info", Switch = "Switch", Slider = "Slider",
    Dropdown = "Dropdown", Buttons = "ButtonRow", Key = "KeyCapture", ItemList = "ItemList", SpellList = "SpellList",
    Preview = "Preview", Commands = "CommandList", Card = "Card", Color = "ColorRow",
}
for method, ctor in pairs(SHORTCUTS) do
    Stack[method] = function(self, ...)
        return self:Add(W[ctor](self, ...))
    end
end

local function makeStack(frame, padX, padTop, padBottom, inner, rowGap, useDividers)
    for k, fn in pairs(Stack) do frame[k] = fn end
    frame.widgets = {}
    frame.padX, frame.padTop, frame.padBottom = padX, padTop, padBottom
    frame.innerW = inner
    frame.rowGap = rowGap
    frame.useDividers = useDividers
    if useDividers then frame.dividers = {} end
    return frame
end

---------------------------------------------------------------------------
-- Carte : fond arrondi, titre, petite description grise, puis les réglages
---------------------------------------------------------------------------
local CARD_RADIUS = 10

function W.Card(parent, title, desc)
    local width = innerW(parent)
    local pad = W.CARD_PAD
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, 60)
    card.noDivider = true
    card.topGap = 14

    local bg = W.Round(card, "BACKGROUND", 0, CARD_RADIUS)
    bg:SetColor(C.card)
    local stroke = W.Stroke(card, "BACKGROUND", 2, CARD_RADIUS)
    stroke:SetColor(C.line)
    -- léger reflet en haut de la carte
    local shine = newTex(card, TEX.grad, "BACKGROUND", 1)
    shine:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -1)
    shine:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -1)
    shine:SetHeight(28)
    shine:SetVertexColor(1, 1, 1, 0.025)

    local head = 16
    if title then
        local t = W.Text(card, "GameFontHighlight", C.text, "OVERLAY", 14)
        t:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -16)
        t:SetText(Tr(title))
        card.title = t
        head = head + 16
    end
    if desc then
        local d = W.Text(card, "GameFontHighlightSmall", C.dim)
        d:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -(head + 4))
        d:SetWidth(width - 2 * pad)
        d:SetJustifyH("LEFT")
        d:SetJustifyV("TOP")
        desc = Tr(desc)
        d:SetText(desc)
        card.desc = d
        head = head + 4 + measure(d, desc, width - 2 * pad)
    end
    head = floor(head + 8 + 0.5)

    makeStack(card, pad, head, 8, width - 2 * pad, 0, true)

    -- surbrillance de la ligne survolée : une seule forme par carte, déplacée sur la ligne
    local hl = W.Round(card, "BORDER", 0, 7)
    hl:SetColor(C.hover)
    hl:Hide()
    function card:ShowHover(row)
        hl:AnchorBox(row, (row.indent or 0) - 10, 0, -10, 0)
        hl:Show()
        self.hoverRow = row
    end
    function card:HideHover(row)
        if self.hoverRow == row then
            hl:Hide()
            self.hoverRow = nil
        end
    end
    card:SetScript("OnHide", function(self)
        hl:Hide()
        self.hoverRow = nil
    end)
    return card
end

---------------------------------------------------------------------------
-- Page : pile de cartes (largeur W.PAGE_W)
---------------------------------------------------------------------------
function W.Page(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(W.PAGE_W, 1)
    makeStack(p, 0, 0, 0, W.PAGE_W, nil, false)
    return p
end
