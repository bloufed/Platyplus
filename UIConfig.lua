-- Platyplus : fenêtre d'options (ns.UI)
--  * fenêtre sombre arrondie avec ombre portée (990 x 780), barre latérale à onglets rangés par groupes, avec le
--    sommaire de l'onglet ouvert (ses cartes : clic = la page défile jusqu'à elle), contenu en cartes qui défile
--  * page dans les options Blizzard (Échap > Options > AddOns) avec un bouton d'ouverture
-- La fenêtre n'est construite qu'à la première ouverture. Pas de bouton de minicarte : l'icône flottante est ns.Launcher.
-- Aucun OnUpdate permanent : seulement pendant une animation (apparition, défilement doux) ou un glissement.
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local W = ns.W
local C = W.C
local TEX = W.TEX

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local FRAME_NAME = "PlatyplusConfigFrame"

local WIN_W, WIN_H = 990, 780
local CORNER = 10
local SIDE_W = 232
local BRAND_H = 88
local HEAD_H = 80
local PAD_L = 26
local VIEW_W = W.PAGE_W                              -- largeur des pages
local PAD_R = WIN_W - SIDE_W - PAD_L - VIEW_W        -- place de la barre de défilement
local PAD_B = 14
local VIEW_H = WIN_H - HEAD_H - PAD_B
local PAGE_TOP, PAGE_BOTTOM = 8, 22
local BAR_W, BAR_H = 6, VIEW_H - 12
local TAB_H, TAB_GAP = 32, 2
local GROUP_H = 24          -- titre d'un groupe d'onglets (JOUER, OBJETS...)
local SUB_H = 22            -- une entrée du sommaire : les cartes de l'onglet ouvert, sous lui
local WHEEL_STEP = 80
local SIDE_VIEW_H = WIN_H - BRAND_H - 10        -- zone des onglets (sous la marque) : au-delà, elle défile
local SIDE_WHEEL = 48

-- info-bulles des lignes : juste à droite de la fenêtre
W.TIP_DX = W.CARD_PAD + PAD_R + 14

-- Réglages qui ne concernent aucun widget : inutile de relire la page
local IGNORED = {
    uiX = true, uiY = true, uiPoint = true, uiTab = true,
    point = true, relPoint = true, x = true, y = true,
    hudX = true, hudY = true, launcherPoint = true, launcherX = true, launcherY = true,
}

UI.pages = {}
UI.tabs = {}
UI.current = nil

---------------------------------------------------------------------------
-- Défilement : immédiat (SetScroll) ou doux (ScrollTo, OnUpdate le temps du mouvement)
---------------------------------------------------------------------------
function UI:ScrollRange()
    return max(0, (self.child:GetHeight() or 0) - VIEW_H)
end

function UI:UpdateBar(v, range)
    if range <= 0 then
        self.bar:Hide()
        self.fadeTop:Hide()
        self.fadeBottom:Hide()
        return
    end
    self.bar:Show()
    local thumbH = max(32, BAR_H * VIEW_H / (VIEW_H + range))
    local travel = BAR_H - thumbH
    self.thumb:SetHeight(thumbH)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOP", self.bar, "TOP", 0, -(v / range) * travel)
    self.fadeTop:SetShown(v > 1)
    self.fadeBottom:SetShown(v < range - 1)
end

function UI:ApplyScroll(v)
    local range = self:ScrollRange()
    v = max(0, min(range, v or 0))
    self.scrollPos = v
    self.scroll:SetVerticalScroll(v)
    self:UpdateBar(v, range)
    self:UpdateSpy(v, range)
end

function UI:SetScroll(v)
    self.scrollTarget = nil
    self.scroll:SetScript("OnUpdate", nil)
    self:ApplyScroll(v)
end

local function smoothScroll(self, elapsed)
    local target = UI.scrollTarget
    if not target then
        self:SetScript("OnUpdate", nil)
        return
    end
    target = max(0, min(UI:ScrollRange(), target))
    local cur = UI.scrollPos or 0
    local d = target - cur
    if abs(d) < 0.5 then
        UI.scrollTarget = nil
        self:SetScript("OnUpdate", nil)
        UI:ApplyScroll(target)
        return
    end
    UI:ApplyScroll(cur + d * min(1, elapsed * 16))
end

function UI:ScrollTo(v)
    self.scrollTarget = max(0, min(self:ScrollRange(), v or 0))
    self.scroll:SetScript("OnUpdate", smoothScroll)
end

function UI:ScrollBy(delta)
    self:ScrollTo((self.scrollTarget or self.scrollPos or 0) + delta)
end

-- la page affichée a changé de hauteur
function UI:FitContent(h)
    self.child:SetHeight(max(VIEW_H, (h or 0) + PAGE_TOP + PAGE_BOTTOM))
    self:ApplyScroll(self.scrollPos or 0)
end

---------------------------------------------------------------------------
-- Position de la fenêtre : toujours CENTER / CENTER avec des décalages uiX, uiY
---------------------------------------------------------------------------
function UI:ApplyPosition()
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", ns.db.uiX or 0, ns.db.uiY or 0)
end

function UI:StopMoving()
    local f = self.frame
    f:StopMovingOrSizing()
    local fx, fy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if fx and fy and ux and uy then
        local fs, us = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local ratio = (fs and us and us ~= 0) and (fs / us) or 1
        ns:Set("uiX", floor(fx * ratio - ux + 0.5))
        ns:Set("uiY", floor(fy * ratio - uy + 0.5))
    end
    self:ApplyPosition()
end

local function startMoving()
    UI.frame:StartMoving()
end

local function stopMoving()
    UI:StopMoving()
end

---------------------------------------------------------------------------
-- Onglets : icône + libellé ; actif = pastille accent arrondie avec léger halo.
-- Une seule pastille de sélection (qui glisse d'un onglet à l'autre) et une seule pastille de survol
-- pour toute la barre : pas de formes en double par onglet.
-- Les onglets sont rangés par groupes titrés (champ `group` de Pages.list) ; sous l'onglet ouvert, son sommaire :
-- une entrée par carte de la page (clic : la page défile jusqu'à elle ; celle qu'on lit est allumée).
---------------------------------------------------------------------------
local function tabY(index)
    local tab = UI.tabs[index]
    return tab and tab.y or -14
end

---------------------------------------------------------------------------
-- Défilement de la barre latérale (onglets + sommaire) : jamais de débordement de la fenêtre.
-- self.side = contenu (enfant de self.sideScroll, qui coupe ce qui dépasse) ; self.sideH = hauteur du contenu.
-- Pas d'OnUpdate : défilement immédiat, molette sur la zone (la page de droite ne bouge pas).
---------------------------------------------------------------------------
function UI:SideRange()
    return max(0, (self.sideH or 0) - SIDE_VIEW_H)
end

function UI:SideScroll(v)
    local sc = self.sideScroll
    if not sc then return end
    local range = self:SideRange()
    v = max(0, min(range, v or 0))
    self.sidePos = v
    sc:SetVerticalScroll(v)
    local bar, thumb = self.sideBar, self.sideThumb
    if range <= 0 then
        bar:Hide()
        return
    end
    bar:Show()
    local h = max(24, SIDE_VIEW_H * SIDE_VIEW_H / (SIDE_VIEW_H + range))
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", bar, "TOP", 0, -(v / range) * (SIDE_VIEW_H - h))
end

-- fait défiler le minimum pour que [top, bottom] (distances positives depuis le haut du contenu) soit visible ;
-- si c'est trop grand, le haut l'emporte
function UI:SideReveal(top, bottom)
    if not self.sideScroll or self:SideRange() <= 0 then return end
    local v = self.sidePos or 0
    if bottom > v + SIDE_VIEW_H then v = bottom - SIDE_VIEW_H end
    if top < v then v = top end
    self:SideScroll(v)
end

-- cartes de la page `index` qui ont un titre (sans doublon) : le sommaire ; rien s'il n'y en a qu'une
function UI:TocCards(index)
    local page = self.pages[index]
    local list, seen = {}, {}
    if not page or not page.widgets then return list end
    for _, w in ipairs(page.widgets) do
        local title = w.title and w.title.GetText and w.title:GetText()
        if type(title) == "string" and title ~= "" and not seen[title] and w:IsShown() then
            seen[title] = true
            list[#list + 1] = w
        end
    end
    if #list < 2 then return {} end
    return list
end

function UI:PaintSub(s)
    local on = s.active
    W.TextColor(s.text, on and C.white or (s.hover and C.text or C.dim))
    s.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], on and 1 or 0.5)
    s.dot:SetSize(on and 6 or 4, on and 6 or 4)
end

function UI:ScrollToCard(card)
    if card and card.stackY then self:ScrollTo(PAGE_TOP + card.stackY - 6) end
end

function UI:NewSub(n)
    local s = CreateFrame("Button", nil, self.side)
    s:SetSize(SIDE_W - 24, SUB_H)
    s:RegisterForClicks("LeftButtonUp")
    local dot = s:CreateTexture(nil, "ARTWORK")
    dot:SetTexture(TEX.circle)
    dot:SetPoint("CENTER", s, "LEFT", 21, 0)             -- sous le centre des icônes d'onglet
    local text = W.Text(s, "GameFontHighlightSmall", C.dim, "OVERLAY", 12)
    text:SetPoint("LEFT", s, "LEFT", 42, 0)               -- aligné sur le libellé des onglets
    text:SetPoint("RIGHT", s, "RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    s.dot, s.text = dot, text
    s:SetScript("OnEnter", function(b) b.hover = true; UI:PaintSub(b) end)
    s:SetScript("OnLeave", function(b) b.hover = false; UI:PaintSub(b) end)
    s:SetScript("OnClick", function(b) UI:ScrollToCard(b.card) end)
    self.subs[n] = s
    return s
end

-- entrée allumée : la dernière carte dont le haut est passé sous le haut de la vue (la dernière tout en bas)
function UI:UpdateSpy(v, range)
    local subs = self.subs
    if not subs or not subs[1] or not subs[1]:IsShown() then return end
    local best, last
    for _, s in ipairs(subs) do
        if s:IsShown() and s.card then
            last = s
            if not best or (PAGE_TOP + (s.card.stackY or 0)) <= v + 40 then best = s end
        end
    end
    if range and range > 0 and v >= range - 2 then best = last end
    for _, s in ipairs(subs) do
        local on = (s == best)
        if s.active ~= on then
            s.active = on
            self:PaintSub(s)
            if on then self:SideReveal(-select(5, s:GetPoint(1)) - 2, -select(5, s:GetPoint(1)) + SUB_H + 2) end
        end
    end
end

-- place les titres de groupe, les onglets et le sommaire de l'onglet ouvert, de haut en bas
function UI:LayoutSide()
    local side = self.side
    if not side then return end
    local y = 6
    local prevGroup
    local nSub = 0
    local firstSub, lastSub
    for i, tab in ipairs(self.tabs) do
        local def = ns.Pages:GetInfo(i)
        local g = def and def.group
        if g and g ~= prevGroup then
            local label = self.groupLabels[g]
            if label then
                label:ClearAllPoints()
                label:SetPoint("BOTTOMLEFT", side, "TOPLEFT", 24, -(y + GROUP_H - 6))
            end
            y = y + GROUP_H
            prevGroup = g
        end
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -y)
        tab.y = -y
        y = y + TAB_H + TAB_GAP
        if i == self.current then
            for _, card in ipairs(self:TocCards(i)) do
                nSub = nSub + 1
                local s = self.subs[nSub] or self:NewSub(nSub)
                s.card = card
                s.text:SetText(card.title:GetText())
                s.active, s.hover = false, false
                self:PaintSub(s)
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -y)
                s:Show()
                firstSub = firstSub or s
                lastSub = s
                y = y + SUB_H
            end
            if nSub > 0 then y = y + 6 end
            self.sideCurTop, self.sideCurBottom = -tab.y - 4, y
        end
    end
    self.sideH = y + 8
    side:SetHeight(self.sideH)
    self:SideScroll(self.sidePos or 0)
    for k = nSub + 1, #self.subs do
        self.subs[k]:Hide()
        self.subs[k].card = nil
    end
    -- fil vertical qui relie les entrées du sommaire (sous leurs points)
    local rail = self.subRail
    if firstSub then
        rail:ClearAllPoints()
        rail:SetPoint("TOP", firstSub, "TOPLEFT", 21, 2)
        rail:SetPoint("BOTTOM", lastSub, "BOTTOMLEFT", 21, floor(SUB_H / 2))
        rail:Show()
    else
        rail:Hide()
    end
end

local function paintTab(b)
    W.TextColor(b.text, b.active and C.white or (b.hover and C.text or C.dim))
    local muted = not (b.active or b.hover)
    if b.icon.SetDesaturation then
        b.icon:SetDesaturation(muted and 0.65 or 0)
    else
        b.icon:SetDesaturated(muted)
    end
    b.icon:SetAlpha(muted and 0.8 or 1)
end

-- icône d'onglet ; si le fichier manque (SetTexture renvoie false), pastille avec l'initiale
local function setTabIcon(b, def)
    local ok = b.icon:SetTexture(def.icon)
    if ok ~= false then return end
    b.icon:SetTexture(TEX.circle)
    b.icon:SetTexCoord(0, 1, 0, 1)
    b.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.35)
    local letter = W.Text(b, "GameFontHighlight", C.white, "OVERLAY", 12)
    letter:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
    letter:SetText((ns.T(def.title)):match("^[%z\1-\127\194-\244][\128-\191]*") or "?")
end

local function tabEnter(self)
    self.hover = true
    paintTab(self)
    if not self.active then
        UI.tabHover:AnchorBox(self, 0, 0, 0, 0)
        UI.tabHover:Show()
    end
end

local function tabLeave(self)
    self.hover = false
    paintTab(self)
    UI.tabHover:Hide()
end

local function tabClick(self)
    if UI.current ~= self.index then W.Sound("tab") end
    UI:SelectTab(self.index)
end

-- pastille de sélection : glisse vers l'onglet choisi (OnUpdate le temps du glissement)
local function selectorStep(sel, p)
    local y = sel.fromY + (sel.toY - sel.fromY) * W.Ease(p)
    sel:ClearAllPoints()
    sel:SetPoint("TOPLEFT", sel:GetParent(), "TOPLEFT", 12, y)
end

function UI:MoveSelector(index, animate)
    local sel = self.selector
    local y = tabY(index)
    sel:Show()
    if animate and sel.curY and sel.curY ~= y then
        sel.fromY, sel.toY, sel.curY = sel.curY, y, y
        W.Animate(sel, 0.18, selectorStep)
    else
        sel.fromY, sel.toY, sel.curY = y, y, y
        selectorStep(sel, 1)
    end
end

local function buildTabShapes(self, side)
    local sel = CreateFrame("Frame", nil, side)
    sel:SetSize(SIDE_W - 24, TAB_H)
    sel:SetFrameLevel(side:GetFrameLevel() or 1)   -- sous les onglets
    local halo = W.NewTex(sel, TEX.glow, "BACKGROUND", -2)
    halo:SetPoint("TOPLEFT", sel, "TOPLEFT", -14, 14)
    halo:SetPoint("BOTTOMRIGHT", sel, "BOTTOMRIGHT", 14, -14)
    halo:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.16)
    local pill = W.Round(sel, "BACKGROUND", 0, 8)
    pill:SetColor(C.accent, 0.16)
    local ring = W.Stroke(sel, "BORDER", 0, 8)
    ring:SetColor(C.accent, 0.32)
    sel:Hide()
    self.selector = sel

    local hover = W.Round(side, "BACKGROUND", 0, 8)
    hover:SetColor(C.white, 0.05)
    hover:Hide()
    self.tabHover = hover
end

local function createTab(parent, index, def)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIDE_W - 24, TAB_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, tabY(index))
    b:RegisterForClicks("LeftButtonUp")
    b.index = index

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", b, "LEFT", 11, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon
    setTabIcon(b, def)

    local text = W.Text(b, "GameFontHighlight", C.dim)
    text:SetPoint("LEFT", icon, "RIGHT", 11, 0)
    text:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(ns.T(def.title))
    b.text = text

    b.active, b.hover = false, false
    b:SetScript("OnEnter", tabEnter)
    b:SetScript("OnLeave", tabLeave)
    b:SetScript("OnClick", tabClick)
    paintTab(b)
    return b
end

-- en-tête de la zone de contenu : icône, titre et description de l'onglet
function UI:SetHeader(index)
    local def = ns.Pages:GetInfo(index)
    if not def then return end
    local ok = self.headIcon:SetTexture(def.icon)
    if ok == false then
        self.headIcon:SetTexture(ns.LOGO)
        self.headIcon:SetTexCoord(0, 1, 0, 1)
    else
        self.headIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    self.headTitle:SetText(ns.T(def.title))
    self.headDesc:SetText(ns.T(def.desc or ""))
end

-- apparition de page : fondu + petite glissade (OnUpdate retiré à la fin)
local function pageFade(page, p)
    local e = W.Ease(p)
    page:SetAlpha(e)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", UI.child, "TOPLEFT", 0, -PAGE_TOP - (1 - e) * 10)
end

-- noSave : ne pas mémoriser l'onglet ; noAnim : sans fondu ; force : relire même si l'onglet est déjà affiché
function UI:SelectTab(index, noSave, noAnim, force)
    local count = ns.Pages:Count()
    index = max(1, min(count, floor(tonumber(index) or 1)))

    W.CancelCapture()
    W.CloseMenu()

    if not force and index == self.current and self.pages[index] and self.pages[index]:IsShown() then
        self:ScrollTo(0)
        return
    end

    W.FinishAnimations()
    for i, tab in ipairs(self.tabs) do
        tab.active = (i == index)
        paintTab(tab)
    end
    self.tabHover:Hide()
    for i, p in pairs(self.pages) do
        if i ~= index then p:Hide() end
    end

    local page = self.pages[index]
    if not page then
        page = ns.Pages:Create(index, self.child)
        page.onHeight = function(h)
            if UI.current == index then UI:FitContent(h) end
        end
        self.pages[index] = page
    end
    self.current = index
    self:LayoutSide()                       -- (le sommaire de cet onglet s'ouvre sous lui, les suivants descendent)
    if self.sideCurTop then self:SideReveal(self.sideCurTop, self.sideCurBottom) end   -- l'onglet actif reste visible
    self:MoveSelector(index, not noAnim)
    self:SetHeader(index)

    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -PAGE_TOP)
    page:Show()
    self:FitContent(page.contentHeight or page:GetHeight())
    self:SetScroll(0)

    page:Refresh()
    page:PageShown()

    if noAnim then
        page:SetAlpha(1)
    else
        W.Animate(page, 0.2, pageFade)
    end

    if not noSave and ns.db.uiTab ~= index then ns:Set("uiTab", index) end
end

---------------------------------------------------------------------------
-- Construction de la fenêtre
---------------------------------------------------------------------------
local function buildBrand(f)
    local brand = CreateFrame("Frame", nil, f)
    brand:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    brand:SetSize(SIDE_W, BRAND_H)
    brand:EnableMouse(true)
    brand:RegisterForDrag("LeftButton")
    brand:SetScript("OnDragStart", startMoving)
    brand:SetScript("OnDragStop", stopMoving)

    local logo = brand:CreateTexture(nil, "ARTWORK")
    logo:SetSize(40, 40)
    logo:SetPoint("TOPLEFT", brand, "TOPLEFT", 18, -24)
    logo:SetTexture(ns.LOGO)
    local glow = W.NewTex(brand, TEX.glow, "BACKGROUND", 1)
    glow:SetSize(88, 88)
    glow:SetPoint("CENTER", logo, "CENTER", 0, 0)
    glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.20)

    local title = W.Text(brand, "GameFontHighlight", nil, "OVERLAY", 19)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 11, -2)
    title:SetText(W.Color("accent", "Platy") .. W.Color("gold", "plus"))

    local ver = W.Text(brand, "GameFontHighlightSmall", C.dim, "OVERLAY", 10)
    ver:SetPoint("LEFT", title, "RIGHT", 11, 0)
    ver:SetText("v" .. tostring(ns.version or "?"))
    local verPill = W.Round(brand, "ARTWORK", 0, 6)
    verPill:AnchorBox(ver, -6, -3, -6, -3)
    verPill:SetColor(C.white, 0.07)

    local sub = W.Text(brand, "GameFontHighlightSmall", C.dim)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    sub:SetText(ns.T("Le confort tout-en-un"))

    local line = brand:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", brand, "BOTTOMLEFT", 18, 0)
    line:SetPoint("BOTTOMRIGHT", brand, "BOTTOMRIGHT", -18, 0)
    line:SetHeight(1)
    line:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    return brand
end

local function buildHeader(self, f)
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_W, 0)
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    head:SetHeight(HEAD_H)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", startMoving)
    head:SetScript("OnDragStop", stopMoving)

    local tile = CreateFrame("Frame", nil, head)
    tile:SetSize(42, 42)
    tile:SetPoint("TOPLEFT", head, "TOPLEFT", PAD_L, -20)
    local tileBg = W.Round(tile, "BACKGROUND", 0, 10)
    tileBg:SetColor(C.accent, 0.12)
    local tileStroke = W.Stroke(tile, "BORDER", 0, 10)
    tileStroke:SetColor(C.accent, 0.25)
    local icon = tile:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("CENTER", tile, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.headIcon = icon

    local title = W.Text(head, "GameFontHighlight", C.white, "OVERLAY", 18)
    title:SetPoint("TOPLEFT", tile, "TOPRIGHT", 14, -3)
    title:SetPoint("RIGHT", head, "RIGHT", -70, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    self.headTitle = title
    local desc = W.Text(head, "GameFontHighlightSmall", C.dim)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetWidth(WIN_W - SIDE_W - PAD_L - 42 - 14 - 80)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    self.headDesc = desc

    -- bouton fermer rond
    local close = CreateFrame("Button", nil, head)
    close:SetSize(30, 30)
    close:SetPoint("TOPRIGHT", head, "TOPRIGHT", -18, -24)
    close:RegisterForClicks("LeftButtonUp")
    local cbg = W.NewTex(close, TEX.circle, "BACKGROUND")
    cbg:SetAllPoints(close)
    local cx = W.Text(close, "GameFontHighlight", C.dim, "OVERLAY", 18)
    cx:SetPoint("CENTER", close, "CENTER", 0.5, 1)
    cx:SetText("×")
    local function paintClose(hover)
        if hover then
            cbg:SetVertexColor(C.bad[1], C.bad[2], C.bad[3], 0.92)
            W.TextColor(cx, C.white)
        else
            cbg:SetVertexColor(1, 1, 1, 0.05)
            W.TextColor(cx, C.dim)
        end
    end
    close:SetScript("OnEnter", function() paintClose(true) end)
    close:SetScript("OnLeave", function() paintClose(false) end)
    close:SetScript("OnClick", function() UI:Close() end)
    paintClose(false)
    W.SetTip(close, "Fermer", "Ferme la fenêtre (Échap marche aussi).")

    local line = head:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", PAD_L, 0)
    line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -16, 0)
    line:SetHeight(1)
    line:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    return head
end

local function buildScrollBar(self, f)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -(HEAD_H + 6))
    bar:EnableMouse(true)
    bar:EnableMouseWheel(true)
    local track = W.Pill(bar, "BACKGROUND", 0, BAR_W, true)
    track:SetColor(C.white, 0.035)

    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetSize(BAR_W, 40)
    thumb:SetPoint("TOP", bar, "TOP", 0, 0)
    thumb:EnableMouse(true)
    local tp = W.Pill(thumb, "ARTWORK", 0, BAR_W, true)
    tp:SetColor(C.white, 0.20)
    self.bar, self.thumb = bar, thumb

    local drag
    local function dragUpdate(s)
        if not drag then return end
        local _, y = GetCursorPosition()
        y = y / s:GetEffectiveScale()
        local range = UI:ScrollRange()
        local travel = BAR_H - (s:GetHeight() or 0)
        if range > 0 and travel > 0 then
            UI:SetScroll(drag.start + (drag.y - y) * range / travel)
        end
    end
    local function stopDrag()
        thumb:SetScript("OnUpdate", nil)
        drag = nil
        tp:SetColor(C.white, 0.20)
    end
    thumb:SetScript("OnMouseDown", function(s, button)
        if button ~= "LeftButton" then return end
        local _, cy = GetCursorPosition()
        drag = { y = cy / s:GetEffectiveScale(), start = UI.scrollPos or 0 }
        tp:SetColor(C.accent, 0.9)
        s:SetScript("OnUpdate", dragUpdate)
    end)
    thumb:SetScript("OnMouseUp", stopDrag)
    thumb:SetScript("OnHide", stopDrag)
    thumb:SetScript("OnEnter", function() if not drag then tp:SetColor(C.white, 0.34) end end)
    thumb:SetScript("OnLeave", function() if not drag then tp:SetColor(C.white, 0.20) end end)

    bar:SetScript("OnMouseDown", function(s, button)
        if button ~= "LeftButton" then return end
        local _, cy = GetCursorPosition()
        local top = s:GetTop()
        if not top then return end
        local y = top - cy / s:GetEffectiveScale()
        local thumbH = thumb:GetHeight() or 0
        local travel = BAR_H - thumbH
        if travel > 0 then
            UI:ScrollTo((y - thumbH / 2) / travel * UI:ScrollRange())
        end
    end)
    bar:SetScript("OnMouseWheel", function(_, delta)
        W.CloseMenu()
        UI:ScrollBy(-delta * WHEEL_STEP)
    end)
end

local function windowFade(f, p)
    f:SetAlpha(W.Ease(p))
end

function UI:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    self.frame = f
    self:ApplyPosition()

    -- ombre, fond arrondi, barre latérale (coins droits à droite), fin contour
    local shadow = W.Shadow(f, 18, 22, 4)
    shadow:SetColor(C.black, 0.9)
    local bg = W.Round(f, "BACKGROUND", -6, CORNER)
    bg:SetColor(C.bg)
    local side = W.Round(f, "BACKGROUND", -5, CORNER, "R")
    side:AnchorBox(f, 0, 0, WIN_W - SIDE_W, 0)
    side:SetColor(C.panel)
    local sideLine = f:CreateTexture(nil, "BACKGROUND", nil, -4)
    sideLine:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_W, 0)
    sideLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", SIDE_W, 0)
    sideLine:SetWidth(1)
    sideLine:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    local border = W.Stroke(f, "BORDER", 0, CORNER)
    border:SetColor(C.white, 0.09)

    -- barre latérale : marque, onglets, pied
    -- les onglets vivent dans un cadre de défilement sous la marque (coupe ce qui dépasse, molette, barre fine)
    local sideScroll = CreateFrame("ScrollFrame", nil, f)
    sideScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -BRAND_H)
    sideScroll:SetSize(SIDE_W, SIDE_VIEW_H)
    if sideScroll.SetClipsChildren then sideScroll:SetClipsChildren(true) end
    local sideFrame = CreateFrame("Frame", nil, sideScroll)
    sideFrame:SetSize(SIDE_W, SIDE_VIEW_H)
    sideScroll:SetScrollChild(sideFrame)
    sideScroll:EnableMouseWheel(true)
    sideScroll:SetScript("OnMouseWheel", function(_, delta)
        W.CloseMenu()
        UI:SideScroll((UI.sidePos or 0) - delta * SIDE_WHEEL)
    end)
    self.sideScroll = sideScroll
    local sideBar = CreateFrame("Frame", nil, f)
    sideBar:SetPoint("TOPLEFT", sideScroll, "TOPLEFT", SIDE_W - 6, 0)
    sideBar:SetSize(3, SIDE_VIEW_H)
    sideBar:SetFrameLevel((sideScroll:GetFrameLevel() or 1) + 20)
    local sideThumb = sideBar:CreateTexture(nil, "OVERLAY")
    sideThumb:SetWidth(3)
    sideThumb:SetColorTexture(1, 1, 1, 0.3)
    sideBar:Hide()
    self.sideBar, self.sideThumb = sideBar, sideThumb
    buildBrand(f)
    buildTabShapes(self, sideFrame)
    self.side = sideFrame
    self.subs = {}
    self.groupLabels = {}
    local rail = sideFrame:CreateTexture(nil, "BACKGROUND")
    rail:SetWidth(1)
    rail:SetColorTexture(1, 1, 1, 0.12)
    rail:Hide()
    self.subRail = rail
    for i = 1, ns.Pages:Count() do
        local def = ns.Pages:GetInfo(i)
        self.tabs[i] = createTab(sideFrame, i, def)
        local g = def and def.group
        if g and not self.groupLabels[g] then
            local label = W.Text(sideFrame, "GameFontHighlightSmall", C.off, "OVERLAY", 10)
            label:SetWidth(SIDE_W - 40)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText(ns.Win and ns.Win.Upper and ns.Win.Upper(ns.T(g)) or ns.T(g):upper())
            self.groupLabels[g] = label
        end
    end
    self:LayoutSide()

    buildHeader(self, f)

    -- zone de contenu avec défilement
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_W + PAD_L, -HEAD_H)
    scroll:SetSize(VIEW_W, VIEW_H)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(VIEW_W, VIEW_H)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        W.CloseMenu()
        UI:ScrollBy(-delta * WHEEL_STEP)
    end)
    self.scroll, self.child = scroll, child

    -- fondus haut / bas au-dessus du contenu (signalent qu'il reste à défiler)
    local over = CreateFrame("Frame", nil, f)
    over:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    over:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    over:SetFrameLevel((f:GetFrameLevel() or 1) + 40)
    local fadeTop = W.NewTex(over, TEX.grad, "OVERLAY")
    fadeTop:SetPoint("TOPLEFT", over, "TOPLEFT", 0, 0)
    fadeTop:SetPoint("TOPRIGHT", over, "TOPRIGHT", 0, 0)
    fadeTop:SetHeight(18)
    fadeTop:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
    local fadeBottom = W.NewTex(over, TEX.grad, "OVERLAY")
    fadeBottom:SetTexCoord(0, 1, 1, 0)
    fadeBottom:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", 0, 0)
    fadeBottom:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", 0, 0)
    fadeBottom:SetHeight(26)
    fadeBottom:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
    self.fadeTop, self.fadeBottom = fadeTop, fadeBottom

    buildScrollBar(self, f)

    f:SetScript("OnHide", function()
        W.CancelCapture()
        W.CloseMenu()
        GameTooltip:Hide()
        UI:SetScroll(UI.scrollPos or 0)
        W.FinishAnimations()
        if UI.events then UI.events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        W.Sound("close")
    end)

    -- Échap ferme la fenêtre : liste UISpecialFrames, fermée par CloseAllWindows (via securecall, sans risque).
    -- NE PAS utiliser RegisterGameMenuEscHandler depuis un addon : la liste de Blizzard en devient « contaminée »
    -- (taint), et à chaque Échap Blizzard appelle ensuite des fonctions réservées (SpellStopCasting...) depuis ce
    -- chemin contaminé -> « Platyplus a été bloqué à cause d'une action qui n'est utilisable que par l'IU de
    -- Blizzard » (constaté en jeu le 2026-11-05).
    if UISpecialFrames then
        table.insert(UISpecialFrames, FRAME_NAME)
    end

    return f
end

---------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------
function UI:Open()
    if not ns.db then return end
    local f = self:Build()
    local wasShown = f:IsShown()
    self:ApplyPosition()
    f:Show()
    f:Raise()
    if self.events then self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    self:SelectTab(ns.db.uiTab, true, true, not wasShown)
    if not wasShown then
        W.Sound("open")
        W.Animate(f, 0.16, windowFade)
    end
end

function UI:Close()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

-- Relit les réglages dans les widgets de la page affichée (key = réglage qui vient de changer)
function UI:Refresh(key)
    local f = self.frame
    if not f or not f:IsShown() then return end
    if key and IGNORED[key] then return end
    if self.refreshing then return end
    local page = self.pages[self.current]
    if not page then return end
    self.refreshing = true
    local ok, err = pcall(page.Refresh, page, key)
    self.refreshing = false
    if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Page dans les options Blizzard (non testable hors du jeu : tout est protégé)
---------------------------------------------------------------------------
function UI:RegisterSettingsPanel()
    if self.category then return end
    local ok, err = pcall(function()
        local panel = CreateFrame("Frame")
        panel.name = "Platyplus"

        local logo = panel:CreateTexture(nil, "ARTWORK")
        logo:SetSize(56, 56)
        logo:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
        logo:SetTexture(ns.LOGO)
        local title = W.Text(panel, "GameFontHighlight", nil, "OVERLAY", 22)
        title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 14, -6)
        title:SetText(W.Color("accent", "Platy") .. W.Color("gold", "plus"))
        local sub = W.Text(panel, "GameFontHighlight", C.dim)
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        sub:SetText(ns.Tf("Le confort tout-en-un · v%s", tostring(ns.version or "?")))
        local desc = W.Text(panel, "GameFontHighlight", C.text)
        desc:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -18)
        desc:SetWidth(560)
        desc:SetJustifyH("LEFT")
        desc:SetText(ns.T("Une touche pour interagir, looter, parler et rendre les quêtes ; vente automatique, barre de ressource lisible, flux de butin et bien plus. Tous les réglages sont dans la fenêtre de Platyplus (tu peux aussi taper /pp)."))
        local btn = W.Button(panel, {
            text = "Ouvrir les options de Platyplus", width = 270, height = 34, primary = true,
            onClick = function()
                -- on ne ferme PAS la fenêtre d'options de Blizzard depuis l'addon (risque de taint sur ses
                -- raccourcis) : notre fenêtre (strate DIALOG) s'ouvre simplement par-dessus
                UI:Open()
            end,
        })
        btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)

        local category = Settings.RegisterCanvasLayoutCategory(panel, "Platyplus")
        Settings.RegisterAddOnCategory(category)
        self.category = category
    end)
    if not ok then ns:Debug("page Settings indisponible :", err) end
end

---------------------------------------------------------------------------
-- Présentation « Qu'est-ce que Platyplus ? » : affichée une fois, à la première connexion avec l'addon
-- (réglage welcomeSeen) ; /pp bienvenue la réaffiche. Construite seulement quand on l'ouvre.
---------------------------------------------------------------------------
local WELCOME_NAME = "PlatyplusWelcome"
local WEL_W, WEL_H = 660, 500
local WEL_PAD = 28
local TILE_W = floor((WEL_W - 2 * WEL_PAD - 14) / 2)
local TILE_H = 76

local FEATURES = {
    { icon = "Interface\\Icons\\INV_Misc_Key_03", title = "Une touche pour tout",
      text = "F parle aux PNJ, ramasse le butin, récolte, accepte et rend les quêtes." },
    { icon = "Interface\\Icons\\INV_Misc_Bag_10", title = "Butin instantané, flux à l'écran",
      text = "Tout se ramasse d'un coup ; butin, ventes, fabrication et quêtes défilent à l'écran." },
    { icon = "Interface\\Icons\\INV_Misc_Coin_01", title = "Vente et réparation",
      text = "Les objets gris et l'équipement inutile se vendent seuls ; le marchand répare aussi." },
    { icon = "Interface\\Icons\\Ability_Warrior_BattleShout", title = "Coût en rage sur tes sorts",
      text = "Chaque sort affiche son coût, en rouge tant qu'il te manque de la rage." },
    { icon = "Interface\\Icons\\INV_Misc_Food_15", title = "Touches pour manger et boire",
      text = "Le meilleur repas ou la meilleure boisson ; une potion en combat. Général > Manger et boire." },
    { icon = false, title = "Icône et barre d'infos",
      text = "FPS, or, sacs, durabilité, niveau d'objet, XP/h : posés où tu veux, hors minicarte." },
}

local function buildWelcome()
    local f = CreateFrame("Frame", WELCOME_NAME, UIParent)
    f:SetSize(WEL_W, WEL_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()

    local shadow = W.Shadow(f, 18, 22, 4)
    shadow:SetColor(C.black, 0.9)
    W.Round(f, "BACKGROUND", -6, CORNER):SetColor(C.bg)
    W.Stroke(f, "BORDER", 0, CORNER):SetColor(C.white, 0.09)
    local band = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    band:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    band:SetHeight(104)
    band:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    local accentLine = f:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)

    -- en-tête : logo, titre, sous-titre
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(60, 60)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", WEL_PAD, -22)
    logo:SetTexture(ns.LOGO)
    local glow = W.NewTex(f, TEX.glow, "BACKGROUND", -4)
    glow:SetSize(130, 130)
    glow:SetPoint("CENTER", logo, "CENTER", 0, 0)
    glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.22)
    local title = W.Text(f, "GameFontHighlight", nil, "OVERLAY", 24)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 16, -6)
    title:SetText(ns.Tf("Bienvenue dans %s", W.Color("accent", "Platy") .. W.Color("gold", "plus")))
    local sub = W.Text(f, "GameFontHighlight", C.dim, "OVERLAY", 12)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetText(ns.Tf("Le confort tout-en-un pour WoW Forever · v%s", tostring(ns.version or "?")))

    local intro = W.Text(f, "GameFontHighlight", C.text, "OVERLAY", 13)
    intro:SetPoint("TOPLEFT", f, "TOPLEFT", WEL_PAD, -122)
    intro:SetWidth(WEL_W - 2 * WEL_PAD)
    intro:SetJustifyH("LEFT")
    intro:SetText(ns.T("Platyplus rassemble les petits plus qui rendent le jeu fluide. Tout est déjà réglé pour bien démarrer ; chaque fonction se coupe ou se règle dans les options."))

    -- six tuiles
    for i, feat in ipairs(FEATURES) do
        local col, row = (i - 1) % 2, floor((i - 1) / 2)
        local tile = CreateFrame("Frame", nil, f)
        tile:SetSize(TILE_W, TILE_H)
        tile:SetPoint("TOPLEFT", f, "TOPLEFT", WEL_PAD + col * (TILE_W + 14), -(172 + row * (TILE_H + 10)))
        W.Round(tile, "BACKGROUND", 1, 8):SetColor(C.card)
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetSize(38, 38)
        icon:SetPoint("TOPLEFT", tile, "TOPLEFT", 14, -14)
        if feat.icon then
            icon:SetTexture(feat.icon)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            icon:SetTexture(ns.LOGO)
        end
        local t = W.Text(tile, "GameFontHighlight", C.text, "OVERLAY", 13)
        t:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 1)
        t:SetWidth(TILE_W - 14 - 38 - 12 - 12)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        t:SetText(ns.T(feat.title))
        local d = W.Text(tile, "GameFontHighlightSmall", C.dim, "OVERLAY", 11)
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -5)
        d:SetWidth(TILE_W - 14 - 38 - 12 - 12)
        d:SetJustifyH("LEFT")
        d:SetJustifyV("TOP")
        d:SetText(ns.T(feat.text))
    end

    -- pied : boutons et rappel des commandes
    local open = W.Button(f, {
        text = "Ouvrir les options", width = 190, height = 34, primary = true,
        onClick = function()
            f:Hide()
            UI:Open()
        end,
    })
    open:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -WEL_PAD, 24)
    local go = W.Button(f, {
        text = "C'est parti", width = 140, height = 34,
        onClick = function() f:Hide() end,
    })
    go:SetPoint("RIGHT", open, "LEFT", -10, 0)
    local hint = W.Text(f, "GameFontHighlightSmall", C.off, "OVERLAY", 11)
    hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", WEL_PAD, 26)
    hint:SetWidth(WEL_W - 2 * WEL_PAD - 190 - 10 - 140 - 16)
    hint:SetJustifyH("LEFT")
    hint:SetText(ns.T("/pp : ouvrir les options\n/pp bienvenue : revoir cette page"))
    f.open, f.go = open, go

    f:SetScript("OnShow", function() W.Sound("open") end)
    f:SetScript("OnHide", function() GameTooltip:Hide() end)

    -- Échap la ferme : UISpecialFrames seulement (voir la fenêtre d'options : pas de RegisterGameMenuEscHandler)
    if UISpecialFrames then table.insert(UISpecialFrames, WELCOME_NAME) end
    return f
end

function UI:ShowWelcome()
    if not ns.db then return end
    if not self.welcome then self.welcome = buildWelcome() end
    self.welcome:Show()
    self.welcome:Raise()
    if not ns.db.welcomeSeen then ns:Set("welcomeSeen", true) end
end

-- première connexion avec Platyplus : la présentation s'ouvre une seule fois, un instant après l'arrivée en jeu
local function maybeWelcome()
    if not ns.db or ns.db.welcomeSeen then return end
    if InCombatLockdown() then
        UI.events:RegisterEvent("PLAYER_REGEN_ENABLED")   -- après le combat
        UI.welcomePending = true
        return
    end
    UI.welcomePending = false
    UI:ShowWelcome()
end

---------------------------------------------------------------------------
-- Chargement (appelé par Core une fois ns.db prêt)
---------------------------------------------------------------------------
local function refreshNow()
    UI:Refresh()
end

-- « Action actuelle » est relue un instant plus tard : Interact applique la liaison après le changement
local function refreshSoon()
    if UI.frame and UI.frame:IsShown() and C_Timer and C_Timer.After then
        C_Timer.After(0.3, refreshNow)
    end
end

function UI:Init()
    if self.initialized then return end
    self.initialized = true

    self:RegisterSettingsPanel()

    -- un réglage a changé (ici ou ailleurs : /pp, autre module) : la page affichée se relit
    ns:OnChange("*", function(key) UI:Refresh(key) end)
    for _, key in ipairs({ "key", "interact", "dialog" }) do ns:OnChange(key, refreshSoon) end

    -- fin de combat : les liaisons sont reposées ; écouté seulement quand la fenêtre est ouverte
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and UI.welcomePending then
            maybeWelcome()
            if not (UI.frame and UI.frame:IsShown()) then UI.events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        end
        refreshSoon()
    end)

    -- présentation à la première connexion : un instant après l'entrée en jeu (ou tout de suite après un /reload)
    if not ns.db.welcomeSeen then
        local starter = CreateFrame("Frame")
        local function later()
            starter:UnregisterAllEvents()
            if C_Timer and C_Timer.After then C_Timer.After(2, maybeWelcome) else maybeWelcome() end
        end
        if IsLoggedIn and IsLoggedIn() then
            later()
        else
            starter:RegisterEvent("PLAYER_ENTERING_WORLD")
            starter:SetScript("OnEvent", later)
        end
    end
end
