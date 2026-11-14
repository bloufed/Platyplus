-- Platyplus : cadre commun des fenêtres Platyplus (ns.Win) : fenêtre de quête, sacs
--  * fond sombre arrondi, liseré clair, ombre ; bandeau avec titre et croix ; on tire le bandeau pour déplacer
--  * position gardée dans ns.db[posKey] = { x, y } : coin `corner` du cadre, en points de l'écran (UIParent),
--    donc indépendante de la taille choisie ; taille (échelle) lue dans ns.db[scaleKey]
--  * Win.Conceal(cadre) : une fenêtre de Blizzard reste ouverte (ses boutons, ses événements et les autres modules
--    qui la lisent marchent comme avant) mais hors de l'écran et transparente ; Win.Reveal la remet en place
-- Vérifié dans le code de Forever (UIParentPanelManager.lua) : les fenêtres de type « panneau » (QuestFrame,
-- GossipFrame) sont placées par FramePositionDelegate avec frame:ClearAllPoints() puis frame:SetPoint(...) ;
-- un hooksecurefunc sur SetPoint les renvoie hors de l'écran à chaque placement, sans rien remplacer.
local ADDON, ns = ...

local Win = {}
ns.Win = Win

local floor, max, min = math.floor, math.max, math.min

local function api(name) return rawget(_G, name) end

Win.HEAD_H = 44
Win.PAD = 18

---------------------------------------------------------------------------
-- Position et taille
---------------------------------------------------------------------------
local function scaleOf(f)
    local s = tonumber(f.opts.scaleKey and ns.db and ns.db[f.opts.scaleKey]) or 1
    return max(0.6, min(2, s))
end

function Win.Place(f)
    local o = f.opts
    local s = scaleOf(f)
    f:SetScale(s)
    f:ClearAllPoints()
    local pos = o.posKey and ns.db and ns.db[o.posKey]
    if type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
        f:SetPoint(o.corner, UIParent, "BOTTOMLEFT", pos.x / s, pos.y / s)
        return
    end
    local d = o.default
    f:SetPoint(d[1], UIParent, d[2], d[3] / s, d[4] / s)
end

-- coin `corner` du cadre en points de UIParent
local function cornerXY(f, corner)
    local s = f:GetScale() or 1
    local x = corner:find("RIGHT") and f:GetRight() or f:GetLeft()
    local y = corner:find("TOP") and f:GetTop() or f:GetBottom()
    if not (x and y) then return nil end
    return floor(x * s + 0.5), floor(y * s + 0.5)
end

function Win.Save(f)
    local o = f.opts
    if not (o.posKey and ns.db) then return end
    local x, y = cornerXY(f, o.corner)
    if x then ns.db[o.posKey] = { x = x, y = y } end
end

function Win.Reset(f)
    if f.opts.posKey and ns.db then ns.db[f.opts.posKey] = {} end
    Win.Place(f)
end

---------------------------------------------------------------------------
-- Petits éléments
---------------------------------------------------------------------------
-- croix dessinée (deux traits tournés) : pas de police ni d'image du jeu à deviner
function Win.CloseButton(parent, onClick)
    local W, C = ns.W, ns.W.C
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.bg = W.Round(b, "BACKGROUND", 0, 7)
    b.bg:SetColor(C.white, 0)
    local lines = {}
    for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSize(14, 2)
        t:SetPoint("CENTER")
        if t.SetRotation then t:SetRotation(angle) end
        lines[i] = t
    end
    local function paint(hover)
        local c = hover and C.text or C.dim
        for _, t in ipairs(lines) do t:SetVertexColor(c[1], c[2], c[3], 1) end
        b.bg:SetColor(hover and C.bad or C.white, hover and 0.22 or 0)
    end
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnClick", function() onClick() end)   -- (le son est celui de la fenêtre du jeu qui se ferme)
    paint(false)
    return b
end

-- bouton texte plat (onglet, petite action) : fond au survol, trait d'accent quand il est actif
function Win.FlatButton(parent, text, onClick, height)
    local W, C = ns.W, ns.W.C
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height or 24)
    b.bg = W.Round(b, "BACKGROUND", 0, 6)
    b.bg:SetColor(C.white, 0)
    b.label = W.Text(b, "GameFontHighlight", C.text, "OVERLAY", 13)
    b.label:SetPoint("CENTER")
    function b:SetLabel(t)
        self.label:SetText(ns.T(t))
        self:SetWidth((self.label:GetStringWidth() or 0) + 20)
    end
    b:SetLabel(text)
    b:SetScript("OnEnter", function(self) self.bg:SetColor(C.white, 0.07) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColor(C.white, 0) end)
    b:SetScript("OnClick", function(self, button)
        W.Sound("click")
        onClick(self, button)
    end)
    return b
end

---------------------------------------------------------------------------
-- La fenêtre
---------------------------------------------------------------------------
-- opts : title, width, height, posKey, scaleKey, corner ("TOPLEFT"...), default = { point, pointUIParent, x, y },
--        onClose (croix), strata
function Win.Create(name, opts)
    local W, C = ns.W, ns.W.C
    local f = CreateFrame("Frame", name, UIParent)
    f.opts = opts
    f:Hide()
    f:SetSize(opts.width or 400, opts.height or 300)
    f:SetFrameStrata(opts.strata or "MEDIUM")
    if f.SetToplevel then f:SetToplevel(true) end
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)          -- les clics ne traversent pas la fenêtre

    W.Shadow(f, 18, 22, -4):SetColor(C.black, 0.55)
    f.bg = W.Round(f, "BACKGROUND", -6, 12)
    f.bg:SetColor(C.bg, 0.97)
    W.Stroke(f, "BORDER", 0, 12):SetColor(C.white, 0.08)

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(Win.HEAD_H)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() f:StartMoving() end)
    head:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        Win.Save(f)
        Win.Place(f)             -- réancré sur le coin choisi (StartMoving pose ses propres points)
    end)
    f.head = head

    local line = head:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", 12, 0)
    line:SetPoint("BOTTOMRIGHT", -12, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.07)

    f.title = W.Text(head, "GameFontHighlightLarge", C.text, "OVERLAY", 17)
    f.title:SetPoint("LEFT", head, "LEFT", Win.PAD, 0)
    f.title:SetPoint("RIGHT", head, "RIGHT", -44, 0)
    f.title:SetJustifyH("LEFT")
    if f.title.SetWordWrap then f.title:SetWordWrap(false) end
    f.title:SetText(ns.T(opts.title or ""))

    f.close = Win.CloseButton(head, function() if opts.onClose then opts.onClose() else f:Hide() end end)
    f.close:SetPoint("RIGHT", head, "RIGHT", -10, 0)

    Win.Place(f)
    return f
end

-- Apparition douce (fondu) ; rien si la fenêtre est déjà affichée. Pas de son : celui du jeu suffit
function Win.Open(f)
    if f:IsShown() then return end
    local W = ns.W
    f:SetAlpha(0)
    f:Show()
    W.Animate(f, 0.14, function(self, p) self:SetAlpha(W.Ease(p)) end)
end

-- son du jeu par son nom dans SOUNDKIT (absent : silence)
function Win.PlayKit(name)
    local kit, play = api("SOUNDKIT"), api("PlaySound")
    local id = type(kit) == "table" and kit[name]
    if id and play then pcall(play, id) end
end

---------------------------------------------------------------------------
-- Fenêtres de Blizzard gardées ouvertes hors de l'écran
---------------------------------------------------------------------------
local concealed = {}         -- [cadre] = { clamped = bool } tant qu'il est caché
local hooked = setmetatable({}, { __mode = "k" })   -- (rien n'est écrit dans les cadres de Blizzard)
local moving = false

local function offscreen(frame)
    if moving or not concealed[frame] then return end
    moving = true
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -6000, 0)
        frame:SetAlpha(0)
    end)
    moving = false
end

function Win.Conceal(frame)
    if not frame or concealed[frame] then return end
    local clamped = frame.IsClampedToScreen and frame:IsClampedToScreen()
    concealed[frame] = { clamped = clamped }
    if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end
    if not hooked[frame] and api("hooksecurefunc") then
        hooked[frame] = true
        hooksecurefunc(frame, "SetPoint", offscreen)
    end
    offscreen(frame)
end

-- left, top : où la reposer si elle est ouverte (l'emplacement des panneaux de gauche du jeu)
function Win.Reveal(frame)
    local saved = frame and concealed[frame]
    if not saved then return end
    concealed[frame] = nil
    frame:SetAlpha(1)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(saved.clamped and true or false) end
    if frame:IsShown() then
        moving = true
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        moving = false
    end
end

function Win.IsConcealed(frame)
    return concealed[frame] ~= nil
end

---------------------------------------------------------------------------
-- Zone qui défile (molette) avec une fine barre de position
---------------------------------------------------------------------------
-- area.child : cadre où poser le contenu (largeur fixe) ; area:SetContentHeight(h) après chaque remplissage
function Win.ScrollArea(parent, width, height)
    local area = {}
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetSize(width, height)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(width)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    local thumb = parent:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    thumb:SetColorTexture(1, 1, 1, 0.3)
    thumb:Hide()

    -- fondu en bas : bandes de plus en plus opaques, sur un cadre au-dessus du contenu, sans souris.
    -- Visible seulement tant qu'on n'est pas au bas du contenu.
    local fade = CreateFrame("Frame", nil, parent)
    fade:SetPoint("BOTTOMLEFT", scroll, "BOTTOMLEFT", 0, 0)
    fade:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    fade:SetHeight(16)
    fade:SetFrameLevel(scroll:GetFrameLevel() + 20)   -- au-dessus des barres (Win.Bar) posées dans le contenu
    if fade.EnableMouse then fade:EnableMouse(false) end
    local bg = ns.W and ns.W.C and ns.W.C.bg or { 0.07, 0.08, 0.1 }
    local BANDS = 8
    for i = 1, BANDS do
        local t = fade:CreateTexture(nil, "OVERLAY")
        t:SetPoint("BOTTOMLEFT", fade, "BOTTOMLEFT", 0, (i - 1) * 2)
        t:SetPoint("BOTTOMRIGHT", fade, "BOTTOMRIGHT", 0, (i - 1) * 2)
        t:SetHeight(2)
        t:SetColorTexture(bg[1], bg[2], bg[3], 0.9 * (BANDS - i + 1) / BANDS)
    end
    fade:Hide()

    function area:Update()
        local viewH = scroll:GetHeight() or 0
        local contentH = child:GetHeight() or 0
        if contentH <= viewH + 1 or viewH <= 0 then
            thumb:Hide()
            fade:Hide()
            return
        end
        thumb:Show()
        fade:SetShown((scroll:GetVerticalScroll() or 0) < contentH - viewH - 1)
        local h = max(24, viewH * viewH / contentH)
        local pos = (scroll:GetVerticalScroll() or 0) / (contentH - viewH)
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 7, -(viewH - h) * pos)
    end

    function area:Scroll(v)
        local range = max(0, (child:GetHeight() or 0) - (scroll:GetHeight() or 0))
        scroll:SetVerticalScroll(max(0, min(range, v or 0)))
        self:Update()
    end

    function area:SetContentHeight(h)
        child:SetHeight(max(1, h))
        self:Scroll(scroll:GetVerticalScroll() or 0)
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        area:Scroll((self:GetVerticalScroll() or 0) - delta * 48)
    end)
    area.scroll, area.child, area.thumb, area.fade = scroll, child, thumb, fade
    return area
end

-- Barre de progression arrondie : bar:SetValue(0..1), bar:SetColor(c)
function Win.Bar(parent, height)
    local W, C = ns.W, ns.W.C
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 8)
    local corner = min(4, (height or 8) / 2)
    f.bg = W.Round(f, "BACKGROUND", 0, corner)
    f.bg:SetColor(C.field, 1)
    f.fill = CreateFrame("Frame", nil, f)
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    f.fill.shape = W.Round(f.fill, "ARTWORK", 0, corner)
    -- le texte sur un cadre au-dessus du remplissage (un cadre enfant se dessine par-dessus les textes de son parent)
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints(f)
    top:SetFrameLevel(f.fill:GetFrameLevel() + 1)
    f.text = W.Text(top, "GameFontHighlightSmall", C.text, "OVERLAY", 11, "OUTLINE")
    f.text:SetPoint("CENTER")
    function f:SetValue(p)
        self.value = max(0, min(1, tonumber(p) or 0))
        local w = (self:GetWidth() or 0) * self.value
        self.fill:SetWidth(max(2 * corner, w))
        self.fill:SetShown(self.value > 0)
    end
    function f:SetColor(c, a) self.fill.shape:SetColor(c, a or 1) end
    f:SetScript("OnSizeChanged", function(self) self:SetValue(self.value or 0) end)
    f:SetColor(C.accent)
    return f
end

-- Majuscules qui gardent les accents français (string.upper ne touche pas aux lettres accentuées en UTF-8 :
-- é = C3 A9 devient É = C3 89, de même pour à â ç è ê ë î ï ô ù û ü)
function Win.Upper(text)
    text = tostring(text or ""):upper()
    text = text:gsub("\195([\160-\190])", function(c) return "\195" .. string.char(c:byte() - 32) end)
    -- cyrillique (russe) : а-п = D0 B0-BF, р-я = D1 80-8F, ё = D1 91
    text = text:gsub("\208([\176-\191])", function(c) return "\208" .. string.char(c:byte() - 32) end)
    text = text:gsub("\209([\128-\143])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    text = text:gsub("\209\145", "\208\129")
    return text
end
