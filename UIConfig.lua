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
    launcherPoint = true, launcherX = true, launcherY = true,
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
        desc:SetText(ns.T("Une touche pour parler aux PNJ, ramasser le butin et rendre les quêtes ; des alertes de combat, la menace lisible sur les mobs, la vente automatique, des fenêtres plus claires et bien plus. Tous les réglages sont dans la fenêtre de Platyplus (tu peux aussi taper /pp)."))
        local btn = W.Button(panel, {
            text = "Ouvrir les options de Platyplus", width = 270, height = 34, primary = true,
            onClick = function()
                -- on ne ferme PAS la fenêtre d'options de Blizzard depuis l'addon (risque de taint sur ses
                -- raccourcis) : notre fenêtre (strate DIALOG) s'ouvre simplement par-dessus
                UI:Open()
            end,
        })
        btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
        local tour = W.Button(panel, {
            text = "Revoir la visite guidée", width = 220, height = 34,
            onClick = function() UI:ShowWelcome(1) end,
        })
        tour:SetPoint("LEFT", btn, "RIGHT", 10, 0)

        local category = Settings.RegisterCanvasLayoutCategory(panel, "Platyplus")
        Settings.RegisterAddOnCategory(category)
        self.category = category
    end)
    if not ok then ns:Debug("page Settings indisponible :", err) end
end

---------------------------------------------------------------------------
-- Visite guidée « Bienvenue dans Platyplus » (UI:ShowWelcome) : une page de présentation générale, puis une petite
-- page par grande fonction (ce qu'elle fait, avec des exemples ; ses réglages principaux en interrupteurs ; un lien
-- vers son onglet d'options) et une page de fin (ce qu'il faut retenir). Colonne des étapes à gauche (clic = aller à
-- l'étape), Précédent / Suivant en bas. Affichée une fois, à la première connexion avec l'addon (réglage welcomeSeen) ;
-- /pp bienvenue la réaffiche. Construite seulement quand on l'ouvre, chaque page à sa première visite.
---------------------------------------------------------------------------
local WELCOME_NAME = "PlatyplusWelcome"
local WEL_W, WEL_H = 860, 620
local RAIL_W = 216                              -- colonne des étapes
local WEL_PAD = 30                              -- marges de la zone de contenu
local BODY_W = WEL_W - RAIL_W - 2 * WEL_PAD    -- largeur utile d'une page
local BODY_TOP = 34
local FOOT_H = 74                               -- pied : compteur d'étapes et boutons
local STEP_H, STEP_GAP = 34, 2
local CARD_IN = 16                              -- marge intérieure de la carte des réglages rapides
local HEAD_DX = 62                              -- retrait du titre et de l'accroche (à droite de l'icône)

-- Les étapes, dans l'ordre. Textes en français = clés de traduction (traduits à la construction).
--  rail : nom dans la colonne ; title, pitch : en-tête ; points : ce que fait la fonction, avec des exemples ;
--  key : capture de la touche d'interaction ; switches : réglages rapides { clé de ns.db, libellé, info-bulle } ;
--  tabs : onglets d'options où se trouvent tous les réglages (id de Pages.list)
local TOUR = {
    { kind = "intro", rail = "Bienvenue" },
    { kind = "modes", rail = "Ton mode", icon = "Interface\\Icons\\INV_Scroll_03", tabs = { "modes" },
      title = "Choisis ta base",
      pitch = "Un clic règle toutes les fonctions d'un coup. Tu ajustes ensuite ce que tu veux, ici ou avec /pp." },
    { rail = "La touche", icon = "Interface\\Icons\\INV_Misc_Key_03", tabs = { "general" }, key = true,
      title = "Une touche pour presque tout",
      pitch = "Vise quelque chose (ou approche-toi) et appuie sur ta touche : Platyplus fait la bonne action.",
      points = {
          "Parler à un PNJ, ouvrir un coffre, cueillir une plante, dépecer une bête.",
          "Dans un dialogue, la même touche fait défiler le texte, accepte la quête, puis la rend.",
          "À l'endroit indiqué par une quête, elle utilise l'objet de quête. Maj + touche : interagir normalement.",
          "Dans le même onglet, deux touches de plus pour manger et boire le meilleur de tes sacs (une potion en combat).",
      } },
    { rail = "Combat", icon = "Interface\\Icons\\Ability_MeleeDamage", tabs = { "procs", "resources" },
      title = "Des alertes de combat lisibles",
      pitch = "Ce qu'il faut faire s'affiche en grand près de ton personnage, avec la touche à presser.",
      points = {
          "Alerte de proc : quand une technique devient utilisable (Fulgurance, Riposte, un sort qui brille…), son icône apparaît avec sa touche.",
          "Barre de coups blancs : le minuteur de ton attaque automatique, pour placer tes coups au bon moment.",
          "Rappel de buffs : ceux que ton groupe peut te donner et qui te manquent ; pour un guerrier, le Cri de guerre en combat.",
          "Au survol d'un mob : ce qu'il peut te faire subir (étourdissement, ralentissement, peur…) et combien de temps.",
      },
      switches = {
          { "procAlert", "Alerte de proc", "L'icône du sort qui vient de devenir utilisable, sous ton personnage, avec la touche à presser." },
          { "swingBar", "Barre de coups blancs", "Une barre qui se remplit jusqu'à ton prochain coup automatique. Visible en combat seulement." },
          { "buffAllies", "Buffs que mon groupe peut me donner", "Hors combat : l'icône du buff qui te manque et le nom de l'allié qui peut te le donner." },
      } },
    { rail = "Menace", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance", tabs = { "plates", "resources" },
      title = "La menace d'un coup d'œil",
      pitch = "En combat, la barre de vie de chaque mob (sa « plate ») prend la couleur de la situation.",
      points = {
          "Si tu fais des dégâts : vert quand le mob t'ignore, orange quand ça se joue, rouge quand il t'attaque. Si tu tankes, c'est l'inverse : rouge, il t'échappe.",
          "Sur la plate : ta progression de quête (« 3/8 ») et l'étiquette « Rare ».",
          "Barres d'incantation : une couleur à part quand ton interruption est prête.",
          "En groupe, une fenêtre de menace liste chaque mob du combat et qui il attaque.",
      },
      switches = {
          { "plates", "Plates colorées par la menace", "Les barres de vie des mobs changent de couleur selon qui ils attaquent. Ton rôle (tank ou dégâts) est deviné tout seul." },
          { "threatWindow", "Fenêtre de menace", "Par défaut, elle n'apparaît qu'en groupe et en combat." },
      } },
    { rail = "Butin", icon = "Interface\\Icons\\INV_Misc_Bag_08", tabs = { "loot" },
      title = "Le butin sans clics",
      pitch = "Tout est ramassé d'un coup, et tu vois ce que tu gagnes sans ouvrir tes sacs.",
      points = {
          "Ouvre un cadavre ou un coffre : tout le butin part directement dans tes sacs.",
          "Ce que tu gagnes défile à côté de ton personnage : butin, achats, objets fabriqués, récompenses de quête.",
          "Les plantes et les cadavres qui ont encore du butin pour toi scintillent quand tu approches.",
          "En groupe, une fenêtre suit les jets de dés : qui fait Besoin ou Cupidité, et qui gagne.",
      },
      switches = {
          { "instantLoot", "Loot instantané", "Tout le contenu d'un cadavre ou d'un coffre est ramassé dès l'ouverture." },
          { "floatLoot", "Flux de butin à l'écran", "Chaque objet gagné s'affiche quelques secondes à côté de ton personnage, avec sa quantité." },
          { "lootRolls", "Fenêtre des jets de dés", "En groupe, elle s'ouvre quand un objet est mis aux dés et montre le choix et le dé de chaque joueur." },
      } },
    { rail = "Vente & HDV", icon = "Interface\\Icons\\INV_Misc_Coin_02", tabs = { "sell" },
      title = "Vendre et réparer sans y penser",
      pitch = "Parle à un marchand : le tri est déjà fait.",
      points = {
          "Les objets gris et l'équipement moins bon que le tien se vendent tout seuls. Tu peux les racheter chez le marchand.",
          "Une liste « Ne jamais vendre » protège ce que tu veux garder, et un aperçu montre ce qui partira.",
          "Ton équipement est réparé, avec l'argent de la guilde quand c'est possible.",
          "À l'hôtel des ventes : un panneau pour mettre en vente en quelques clics, et le prix de l'HDV dans les infobulles.",
      },
      switches = {
          { "sellJunk", "Vendre les objets gris", "Chez un marchand, tous tes objets gris sont vendus." },
          { "sellGear", "Vendre l'équipement inutile", "Équipement blanc ou vert d'un niveau inférieur à ce que tu portes. Réglable dans l'onglet Vente & HDV." },
          { "autoRepair", "Réparer chez les marchands", "Ton équipement est réparé dès que tu parles à un marchand qui sait réparer." },
      } },
    { rail = "Fenêtres", icon = "Interface\\Icons\\INV_Misc_Bag_07", tabs = { "windows", "chat" },
      title = "Des fenêtres plus claires",
      pitch = "Les fenêtres du jeu redessinées : plus grandes et plus lisibles.",
      points = {
          "Quêtes et dialogues en grand texte ; les récompenses au choix en grandes cartes, la meilleure pour toi mise en avant.",
          "Tous tes sacs dans une seule fenêtre.",
          "Fenêtre du personnage (touche C) : équipement, niveau d'objet, réputation, compétences, monnaies.",
          "Un chat plus lisible : onglets, anti-spam, et l'historique gardé après un /reload.",
      },
      switches = {
          { "questWindow", "Fenêtre de quête et de dialogue", "Remplace la fenêtre de dialogue des PNJ par une fenêtre Platyplus en grand texte." },
          { "bagWindow", "Une seule fenêtre pour tous les sacs", "Remplace les sacs séparés du jeu (touche B)." },
          { "charWindow", "Fenêtre du personnage", "Remplace la fiche du personnage du jeu (touche C)." },
      } },
    { rail = "Icône & infos", logo = true, tabs = { "launcher" },
      title = "L'icône Platyplus",
      pitch = "Ton raccourci vers tout Platyplus, posé où tu veux à l'écran.",
      points = {
          "Clic gauche : les options. Clic droit : un menu pour allumer ou couper les fonctions. Glisse-la pour la déplacer.",
          "À côté, une barre d'infos : FPS, latence, or, place dans les sacs, durabilité, niveau d'objet.",
          "Expérience : le pourcentage du niveau. Clique dessus pour voir l'XP par heure, le temps avant le niveau ou les mobs restants.",
      },
      switches = {
          { "launcher", "Icône Platyplus", "Cachée, tu ouvres toujours les options avec /pp." },
          { "dock", "Barre d'infos à côté de l'icône", "Choisis les infos affichées dans l'onglet Icône & infos." },
      } },
    { kind = "done", rail = "C'est parti" },
}

-- position d'un onglet d'options d'après son id (Pages.list)
local function tabIndex(id)
    for i = 1, ns.Pages:Count() do
        local def = ns.Pages:GetInfo(i)
        if def and def.id == id then return i, def end
    end
end

-- texte sur plusieurs lignes, aligné à gauche
local function para(parent, text, color, size, width)
    local fs = W.Text(parent, "GameFontHighlight", color or C.text, "OVERLAY", size or 13)
    fs:SetWidth(width or BODY_W)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(2)
    fs:SetText(text)
    fs.textH = W.Measure(fs, text, width or BODY_W)
    return fs
end

-- hauteur d'une ligne de texte simple (mesurée par le jeu, approchée par le simulateur)
local function lineHeight(fs)
    local ok, h = pcall(fs.GetStringHeight, fs)
    fs.textH = (ok and type(h) == "number" and h > 0) and h or 14
    return fs
end

-- pose `region` sous `prev` (texte mesuré ou cadre), décalé de dx, à `gap` points d'écart. Ancré sur le HAUT de prev
-- plus sa hauteur : un texte qui passe à la ligne n'a pas de hauteur fixe sur laquelle s'ancrer par le bas.
local function below(region, prev, dx, gap)
    local h = prev.textH or prev:GetHeight() or 0
    region:SetPoint("TOPLEFT", prev, "TOPLEFT", dx or 0, -floor(h + (gap or 0) + 0.5))
end

-- petit titre de section en capitales (« RÉGLAGES RAPIDES »)
local function sectionTitle(parent, text)
    local fs = W.Text(parent, "GameFontHighlightSmall", C.dim, "OVERLAY", 11)
    local t = ns.T(text)
    fs:SetText(ns.Win and ns.Win.Upper and ns.Win.Upper(t) or t:upper())
    return lineHeight(fs)
end

-- liste à puces sous `anchor` ; dx = décalage horizontal de la 1re ligne par rapport au bord gauche d'anchor
local function bullets(parent, list, anchor, dx, gap)
    local last
    for i, text in ipairs(list) do
        local fs = para(parent, ns.T(text), C.text, 13, BODY_W - 18)
        if i == 1 then
            below(fs, anchor, dx + 18, gap)
        else
            below(fs, last, 0, 9)
        end
        local dot = W.NewTex(parent, TEX.circle, "ARTWORK")
        dot:SetSize(6, 6)
        dot:SetPoint("TOPLEFT", fs, "TOPLEFT", -15, -5)
        dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
        last = fs
    end
    return last
end

-- en-tête d'une page : icône, titre, accroche
local function pageHeader(page, step)
    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetSize(46, 46)
    icon:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    if step.logo then
        icon:SetTexture(ns.LOGO)
    else
        icon:SetTexture(step.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local title = W.Text(page, "GameFontHighlight", C.text, "OVERLAY", 21)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", HEAD_DX - 46, -1)
    title:SetWidth(BODY_W - HEAD_DX - 30)   -- (le bouton de fermeture est au-dessus, à droite)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(ns.T(step.title))
    lineHeight(title)
    local pitch = para(page, ns.T(step.pitch or ""), C.dim, 13, BODY_W - HEAD_DX)
    below(pitch, title, 0, 7)
    -- l'accroche descend au moins jusqu'au bas de l'icône : ce qui suit s'ancre sur elle
    pitch.textH = max(pitch.textH, 46 - 1 - title.textH - 7)
    page.icon, page.title, page.pitch = icon, title, pitch
    return pitch
end

-- liens vers les onglets d'options de la fonction (« Tous les réglages : Procs · Combat »)
local function tabLinks(f, page, step, anchor, dx)
    local intro = W.Text(page, "GameFontHighlightSmall", C.dim, "OVERLAY", 12)
    intro:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx, -16)
    intro:SetText(ns.T(#(step.tabs or {}) > 1 and "Tous les réglages dans les onglets" or "Tous les réglages dans l'onglet"))
    lineHeight(intro)
    local prev = intro
    for _, id in ipairs(step.tabs or {}) do
        local index, def = tabIndex(id)
        if index then
            local b = CreateFrame("Button", nil, page)
            b:SetHeight(20)
            local fs = W.Text(b, "GameFontHighlight", C.accent, "OVERLAY", 12)
            fs:SetPoint("LEFT", b, "LEFT", 0, 0)
            fs:SetText(ns.T(def.title) .. "  ›")
            b:SetWidth(floor((fs:GetStringWidth() or 120) + 4))
            b:SetPoint("LEFT", prev, "RIGHT", (prev == intro) and 10 or 18, 0)
            b:SetScript("OnEnter", function() W.TextColor(fs, C.accentHover) end)
            b:SetScript("OnLeave", function() W.TextColor(fs, C.accent) end)
            b:SetScript("OnClick", function()
                W.Sound("click")
                f.resume = f.step                 -- /pp bienvenue reprendra ici
                f:Hide()
                UI:Open()
                UI:SelectTab(index)
            end)
            prev = b
        end
    end
    return intro
end

-- réglages rapides : interrupteurs (ou capture de la touche) dans une carte
local function quickCard(page, step, anchor, dx)
    local label = sectionTitle(page, step.key and "Ta touche" or "Réglages rapides")
    below(label, anchor, dx, 22)
    local card = CreateFrame("Frame", nil, page)
    card:SetWidth(BODY_W)
    below(card, label, 0, 8)
    card.innerW = BODY_W - 2 * CARD_IN
    W.Round(card, "BACKGROUND", 1, 9):SetColor(C.card)
    page.widgets = {}
    local h = 0
    if step.key then
        local cap = W.KeyCapture(card, { key = "key", label = "Touche d'interaction" })
        cap:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_IN, -CARD_IN)
        local function fit() card:SetHeight(floor((cap:GetHeight() or 92) + 2 * CARD_IN - 8 + 0.5)) end
        cap.onResize = fit
        fit()
        page.widgets[1] = cap
        return card
    end
    for i, sw in ipairs(step.switches or {}) do
        local row = W.Switch(card, { key = sw[1], label = sw[2], tip = sw[3] })
        row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_IN, -(6 + h))
        h = h + row:GetHeight()
        if i < #step.switches then
            local line = card:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_IN, -(6 + h))
            line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_IN, -(6 + h))
            line:SetColorTexture(1, 1, 1, 0.05)
        end
        page.widgets[#page.widgets + 1] = row
    end
    card:SetHeight(h + 12)
    return card
end

-- page d'une fonction : en-tête, ce qu'elle fait, réglages rapides, liens vers ses onglets
local function buildFeaturePage(f, page, step)
    local pitch = pageHeader(page, step)
    local last = bullets(page, step.points or {}, pitch, -HEAD_DX, 22)
    local card = quickCard(page, step, last, -18)
    tabLinks(f, page, step, card, 0)
end

-- choix d'un mode prêt à l'emploi (UIPages : Pages.ModePicker) ; les pages suivantes montrent ses interrupteurs
local function buildModesPage(f, page, step)
    local pitch = pageHeader(page, step)
    local picker = ns.Pages.ModePicker(page, BODY_W, { base = C.card, hover = C.btn })
    below(picker, pitch, -HEAD_DX, 24)
    page.widgets = { picker }
    local note = para(page, ns.T("Pas sûr ? Garde Recommandé : c'est le réglage de départ. Les pages suivantes "
        .. "montrent les principaux interrupteurs de chaque fonction, réglés selon ton mode."), C.dim, 12)
    below(note, picker, 0, 14)
    note:SetHeight(note.textH)        -- (les liens s'ancrent sous elle)
    tabLinks(f, page, step, note, 0)
end

-- Choix de la langue, tout en haut de la présentation : une pastille par langue, chacune écrite dans sa langue.
-- Platyplus démarre en anglais ; si le jeu est dans une autre langue proposée, une ligne (dans cette langue) invite à
-- cliquer dessus. Le changement s'applique tout de suite à la visite (reconstruite) quand le dictionnaire est encore
-- chargé (première visite), sinon au /reload. Renvoie un cadre dont la hauteur couvre le bloc (ancrage du reste).
local CYR_FONT = "Fonts\\FRIZQT___CYR.TTF"
local CHIP_H, CHIP_GAP = 28, 6

local function reloadButton(page)
    return W.Button(page, {
        text = "Recharger l'interface", width = 200, height = 28,
        confirm = "Clique encore pour recharger",
        onClick = function()
            local reload = rawget(_G, "ReloadUI")
            if InCombatLockdown and InCombatLockdown() then
                ns:Print("impossible en combat : réessaie après le combat")
            elseif reload then
                reload()
            end
        end,
    })
end

local function languageBlock(f, page, anchor)
    local L = ns.Locale
    local chosen = L.Resolve(ns.db and ns.db.language)
    local client = L.Client()
    local block = CreateFrame("Frame", nil, page)
    block:SetWidth(BODY_W)
    below(block, anchor, 0, 20)

    local label = W.Text(block, "GameFontHighlightSmall", C.dim, "OVERLAY", 11)
    label:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    local word = ns.T("Langue")
    word = ns.Win and ns.Win.Upper and ns.Win.Upper(word) or word:upper()
    label:SetText(ns.lang == "enUS" and "LANGUAGE" or (word .. "  ·  LANGUAGE"))
    lineHeight(label)

    local top = floor(label.textH + 8 + 0.5)
    local x, row = 0, 0
    for _, l in ipairs(ns.LANGUAGES) do
        local b = CreateFrame("Button", nil, block)
        b:SetHeight(CHIP_H)
        local active = (l.code == chosen)
        b.bg = W.Round(b, "BACKGROUND", 1, 8)
        local fs = W.Text(b, "GameFontHighlight", active and C.ink or C.text, "OVERLAY", 13)
        if l.code == "ruRU" then pcall(fs.SetFont, fs, CYR_FONT, 13, "") end   -- cyrillique sur tous les clients
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(l.name)
        local ok, sw = pcall(fs.GetStringWidth, fs)
        local w = floor(((ok and type(sw) == "number" and sw > 0) and sw or 7 * #l.name) + 28 + 0.5)
        if x > 0 and x + w > BODY_W then x, row = 0, row + 1 end
        b:SetWidth(w)
        b:SetPoint("TOPLEFT", block, "TOPLEFT", x, -(top + row * (CHIP_H + CHIP_GAP)))
        x = x + w + CHIP_GAP
        local function paint(hover)
            if active then
                b.bg:SetColor(C.accent)
            else
                b.bg:SetColor(hover and C.btnHover or C.btn)
            end
        end
        paint(false)
        b:SetScript("OnEnter", function() paint(true) end)
        b:SetScript("OnLeave", function() paint(false) end)
        b:SetScript("OnClick", function()
            if active then return end
            UI:SetTourLanguage(l.code)
        end)
        b.code = l.code
        block.chips = block.chips or {}
        block.chips[#block.chips + 1] = b
    end
    local h = top + (row + 1) * CHIP_H + row * CHIP_GAP

    -- ligne sous les pastilles : après un changement, ce qu'il reste à faire ; sinon, l'invitation dans la langue
    -- du jeu (si Platyplus la propose et qu'elle n'est pas déjà choisie)
    local text, color, withReload
    if UI.langSwitched == "live" then
        -- (phrase d'un seul tenant : l'extraction des traductions lit les T("…") littéraux de ce fichier)
        text = ns.T("Langue changée. Les textes déjà affichés ailleurs (barre d'infos, options du jeu) suivront au prochain /reload.")
        color, withReload = C.dim, true
    elseif UI.langSwitched == "reload" then
        text, color, withReload = ns.T("Recharge l'interface pour passer Platyplus dans cette langue."), C.gold, true
    else
        if client and client ~= chosen then
            local name = L.Name(client)
            local fmt = L.In(client, "Clique sur « %s » pour avoir Platyplus dans la langue de ton jeu.")
            text = fmt and string.format(fmt, name)
                or ns.Tf("Clique sur « %s » pour avoir Platyplus dans la langue de ton jeu.", name)
            color = C.gold
        end
    end
    if text then
        local note = para(block, text, color, 12, withReload and (BODY_W - 214) or BODY_W)
        if client == "ruRU" then pcall(note.SetFont, note, CYR_FONT, 12, "") end
        note:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(h + 10))
        local noteH = note.textH
        if withReload then
            local btn = reloadButton(block)
            btn:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -(h + 6))
            noteH = max(noteH, 28)
        end
        h = h + 10 + noteH
    end
    block:SetHeight(floor(h + 0.5))
    page.langBlock = block
    return block
end

-- présentation générale
local function buildIntroPage(f, page)
    local logo = page:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    logo:SetTexture(ns.LOGO)
    local glow = W.NewTex(page, TEX.glow, "BACKGROUND", 2)
    glow:SetSize(140, 140)
    glow:SetPoint("CENTER", logo, "CENTER", 0, 0)
    glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.22)
    local title = W.Text(page, "GameFontHighlight", nil, "OVERLAY", 25)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 18, -6)
    title:SetText(ns.Tf("Bienvenue dans %s", W.Color("accent", "Platy") .. W.Color("gold", "plus")))
    lineHeight(title)
    local sub = W.Text(page, "GameFontHighlight", C.dim, "OVERLAY", 12)
    below(sub, title, 0, 8)
    sub:SetText(ns.Tf("Le confort tout-en-un pour WoW Forever · v%s", tostring(ns.version or "?")))

    local lang = languageBlock(f, page, logo)
    local intro = para(page, ns.T("Platyplus rassemble en un seul addon les petits plus qui rendent le jeu plus fluide : "
        .. "une touche qui fait presque tout, des alertes de combat lisibles, le butin et la vente sans clics, "
        .. "et des fenêtres plus claires."), C.text, 14)
    below(intro, lang, 0, 22)

    local HOW = {
        { "Prêt à jouer", "Les fonctions utiles sont déjà allumées : tu peux fermer cette fenêtre et jouer tout de suite." },
        { "Un mode pour commencer", "Recommandé, Complet, Immersif ou Minimal : un clic règle tout d'un coup, et tu changes ensuite ce que tu veux." },
        { "Tout se règle avec /pp", "Tape /pp ou clique sur l'icône Platyplus : chaque fonction a son interrupteur, et chaque réglage s'explique quand tu le survoles. Pour revoir cette visite : /pp bienvenue." },
    }
    local prev = intro
    for i, how in ipairs(HOW) do
        local dot = W.NewTex(page, TEX.circle, "ARTWORK")
        dot:SetSize(28, 28)
        below(dot, prev, (i == 1) and 0 or -44, (i == 1) and 26 or 18)
        dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.18)
        local n = W.Text(page, "GameFontHighlight", C.accent, "OVERLAY", 14)
        n:SetPoint("CENTER", dot, "CENTER", 0, 0)
        n:SetText(tostring(i))
        local t = W.Text(page, "GameFontHighlight", C.text, "OVERLAY", 14)
        t:SetPoint("TOPLEFT", dot, "TOPRIGHT", 16, -1)
        t:SetWidth(BODY_W - 44)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        t:SetText(ns.T(how[1]))
        lineHeight(t)
        local d = para(page, ns.T(how[2]), C.dim, 12, BODY_W - 44)
        below(d, t, 0, 5)
        prev = d
    end
end

-- page de fin : commandes à retenir, bon à savoir
local function buildDonePage(f, page)
    local pitch = pageHeader(page, {
        logo = true,
        title = "Tout est prêt !",
        pitch = "Platyplus est réglé pour bien démarrer. Voici l'essentiel à retenir.",
    })
    local label = sectionTitle(page, "À retenir")
    below(label, pitch, -HEAD_DX, 26)
    local CMDS = {
        { "/pp", "ouvre les options (comme un clic sur l'icône Platyplus)" },
        { "/pp help", "liste toutes les commandes dans le chat" },
        { "/pp mode", "montre ton mode ; /pp mode complet (ou immersif…) en change" },
        { "/pp bienvenue", "relance cette visite" },
    }
    local prev, CODE_W = label, 132
    for i, cmd in ipairs(CMDS) do
        local pillF = CreateFrame("Frame", nil, page)
        pillF:SetSize(CODE_W, 26)
        below(pillF, prev, 0, (i == 1) and 10 or 8)
        W.Round(pillF, "BACKGROUND", 1, 7):SetColor(C.field)
        local code = W.Text(pillF, "GameFontHighlight", C.accent, "OVERLAY", 13)
        code:SetPoint("LEFT", pillF, "LEFT", 10, 0)
        code:SetText(cmd[1])
        local d = W.Text(page, "GameFontHighlight", C.text, "OVERLAY", 13)
        d:SetPoint("LEFT", pillF, "RIGHT", 14, 0)
        d:SetWidth(BODY_W - CODE_W - 14)
        d:SetJustifyH("LEFT")
        d:SetWordWrap(false)
        d:SetText(ns.T(cmd[2]))
        prev = pillF
    end
    local tips = sectionTitle(page, "Bon à savoir")
    below(tips, prev, 0, 26)
    bullets(page, {
        "Dans les options, survole un réglage pour lire son explication. Clic droit sur un curseur : il revient à sa valeur par défaut.",
        "D'autres onglets t'attendent : Confort (invitations, duels, invocations), Réglages du jeu (réglages conseillés en un clic) et Avancé (langue de Platyplus, remise à zéro).",
        "Un souci, une idée ? Écris-nous sur github.com/bloufed/Platyplus.",
    }, tips, 0, 10)
end

-- colonne des étapes : rond numéroté + nom ; l'étape affichée est soulignée par une barre bleue
local function paintStep(b)
    local f = b.owner
    local cur = (b.index == f.step)
    local seen = f.seen[b.index]
    b.bg:SetShown(cur or b.hover)
    b.bg:SetColor(cur and C.card or C.hover)
    b.bar:SetShown(cur)
    if cur then
        b.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
        W.TextColor(b.num, C.ink)
    elseif seen then
        b.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.28)
        W.TextColor(b.num, C.text)
    else
        b.dot:SetVertexColor(1, 1, 1, 0.08)
        W.TextColor(b.num, C.dim)
    end
    W.TextColor(b.label, (cur or b.hover) and C.text or (seen and C.text or C.dim), (cur or b.hover or seen) and 1 or 0.85)
end

local function buildRail(f)
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    rail:SetWidth(RAIL_W)
    W.Round(rail, "BACKGROUND", -5, CORNER, "R"):SetColor(C.panel)
    local edge = rail:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)
    edge:SetWidth(1)
    edge:SetColorTexture(1, 1, 1, 0.06)

    local logo = rail:CreateTexture(nil, "ARTWORK")
    logo:SetSize(34, 34)
    logo:SetPoint("TOPLEFT", rail, "TOPLEFT", 20, -24)
    logo:SetTexture(ns.LOGO)
    local name = W.Text(rail, "GameFontHighlight", nil, "OVERLAY", 16)
    name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
    name:SetText(W.Color("accent", "Platy") .. W.Color("gold", "plus"))
    local sub = W.Text(rail, "GameFontHighlightSmall", C.dim, "OVERLAY", 11)
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    sub:SetText(ns.T("Visite guidée"))

    f.steps = {}
    for i, step in ipairs(TOUR) do
        local b = CreateFrame("Button", nil, rail)
        b:SetSize(RAIL_W - 24, STEP_H)
        b:SetPoint("TOPLEFT", rail, "TOPLEFT", 12, -(84 + (i - 1) * (STEP_H + STEP_GAP)))
        b.owner, b.index = f, i
        b.bg = W.Round(b, "BACKGROUND", 1, 7)
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetSize(3, STEP_H - 14)
        b.bar:SetPoint("LEFT", b, "LEFT", 0, 0)
        b.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        b.dot = W.NewTex(b, TEX.circle, "ARTWORK")
        b.dot:SetSize(22, 22)
        b.dot:SetPoint("LEFT", b, "LEFT", 12, 0)
        b.num = W.Text(b, "GameFontHighlightSmall", C.dim, "OVERLAY", 11)
        b.num:SetPoint("CENTER", b.dot, "CENTER", 0, 0)
        b.num:SetText(tostring(i))
        b.label = W.Text(b, "GameFontHighlight", C.dim, "OVERLAY", 13)
        b.label:SetPoint("LEFT", b.dot, "RIGHT", 11, 0)
        b.label:SetWidth(RAIL_W - 24 - 12 - 22 - 11 - 8)
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
        b.label:SetText(ns.T(step.rail))
        b:SetScript("OnEnter", function(self) self.hover = true paintStep(self) end)
        b:SetScript("OnLeave", function(self) self.hover = false paintStep(self) end)
        b:SetScript("OnClick", function(self)
            if self.index ~= f.step then
                W.Sound("tab")
                f:ShowStep(self.index)
            end
        end)
        f.steps[i] = b
    end
end

local function welcomePageFade(page, p)
    page:SetAlpha(p)
end

local function buildWelcome()
    local f = CreateFrame("Frame", WELCOME_NAME, UIParent)
    f:SetSize(WEL_W, WEL_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()
    f.step, f.seen, f.pages = 1, {}, {}

    local shadow = W.Shadow(f, 18, 22, 4)
    shadow:SetColor(C.black, 0.9)
    W.Round(f, "BACKGROUND", -6, CORNER):SetColor(C.bg)
    W.Stroke(f, "BORDER", 0, CORNER):SetColor(C.white, 0.09)

    buildRail(f)

    local close = W.CloseGlyphButton(f, 22, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    f.close = close

    -- zone des pages
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", RAIL_W + WEL_PAD, -BODY_TOP)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -WEL_PAD, FOOT_H)
    f.body = body

    -- pied : filet, compteur, boutons (un jeu de boutons par situation : début, milieu, fin)
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RAIL_W + WEL_PAD, FOOT_H - 2)
    rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -WEL_PAD, FOOT_H - 2)
    rule:SetColorTexture(1, 1, 1, 0.06)
    local counter = W.Text(f, "GameFontHighlightSmall", C.dim, "OVERLAY", 12)
    counter:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RAIL_W + WEL_PAD, 30)
    f.counter = counter

    local function nav(opts)
        local b = W.Button(f, opts)
        b:Hide()
        return b
    end
    f.next = nav({ text = "Suivant", width = 150, height = 34, primary = true,
        onClick = function() f:ShowStep(f.step + 1) end })
    f.start = nav({ text = "Commencer la visite", width = 200, height = 34, primary = true,
        onClick = function() f:ShowStep(2) end })
    f.open = nav({ text = "Ouvrir les options", width = 190, height = 34, primary = true,
        onClick = function()
            f:Hide()
            UI:Open()
        end })
    f.back = nav({ text = "Précédent", width = 130, height = 34,
        onClick = function() f:ShowStep(f.step - 1) end })
    f.go = nav({ text = "Passer la visite", width = 160, height = 34,
        onClick = function() f:Hide() end })
    f.finish = nav({ text = "Terminer", width = 130, height = 34,
        onClick = function() f:Hide() end })
    for _, b in ipairs({ f.next, f.start, f.open }) do
        b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -WEL_PAD, 20)
    end
    f.back:SetPoint("RIGHT", f.next, "LEFT", -10, 0)
    f.go:SetPoint("RIGHT", f.start, "LEFT", -10, 0)
    f.finish:SetPoint("RIGHT", f.open, "LEFT", -10, 0)

    -- affiche l'étape i (page construite à sa première visite)
    function f:ShowStep(i)
        i = max(1, min(#TOUR, floor(tonumber(i) or 1)))
        W.CancelCapture()
        local step = TOUR[i]
        local page = self.pages[i]
        if not page then
            page = CreateFrame("Frame", nil, body)
            page:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
            page:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
            -- protégé (comme Pages:Create) : une erreur dans une page ne bloque ni la visite ni la navigation
            local build = (step.kind == "intro" and buildIntroPage) or (step.kind == "done" and buildDonePage)
                or (step.kind == "modes" and buildModesPage) or buildFeaturePage
            local ok, err = pcall(build, self, page, step)
            if not ok then geterrorhandler()(err) end
            self.pages[i] = page
        end
        for j, p in pairs(self.pages) do
            if j ~= i then p:Hide() end
        end
        self.step = i
        self.seen[i] = true
        page:Show()
        for _, w in ipairs(page.widgets or {}) do
            if w.Refresh then w:Refresh() end
        end
        if self:IsVisible() then
            page:SetAlpha(0)
            W.Animate(page, 0.18, welcomePageFade)
        else
            page:SetAlpha(1)
        end
        for _, b in ipairs(self.steps) do paintStep(b) end
        local first, last = (i == 1), (i == #TOUR)
        self.start:SetShown(first)
        self.go:SetShown(first)
        self.next:SetShown(not first and not last)
        self.back:SetShown(not first and not last)
        self.open:SetShown(last)
        self.finish:SetShown(last)
        counter:SetText(ns.Tf("Étape %d sur %d", i, #TOUR))
    end

    f:SetScript("OnShow", function() W.Sound("open") end)
    f:SetScript("OnHide", function(self)
        W.CancelCapture()
        GameTooltip:Hide()
        -- visite fermée (pas reconstruite pour une autre langue) : les dictionnaires inutiles sont libérés
        if not self.switching and ns.Locale and ns.Locale.Release then ns.Locale.Release() end
    end)

    -- Échap la ferme : UISpecialFrames seulement (voir la fenêtre d'options : pas de RegisterGameMenuEscHandler)
    if UISpecialFrames then
        local listed = false
        for _, name in ipairs(UISpecialFrames) do if name == WELCOME_NAME then listed = true end end
        if not listed then table.insert(UISpecialFrames, WELCOME_NAME) end
    end
    return f
end

-- langue choisie dans la visite : appliquée tout de suite (visite reconstruite dans la nouvelle langue) si son
-- dictionnaire est encore chargé, sinon gardée pour le prochain /reload (la page d'accueil le dit, avec un bouton)
function UI:SetTourLanguage(code)
    if not ns.db or (InCombatLockdown and InCombatLockdown()) then return end
    W.Sound("click")
    ns:Set("language", code)
    local old = self.welcome
    if ns.Locale.Switch(code) then
        self.langSwitched = "live"
        if old then
            old.switching = true
            old:Hide()
            old.switching = nil
        end
        self.welcome = nil
        self:ShowWelcome(1)
    else
        self.langSwitched = "reload"
        if old and old.pages[1] then
            old.pages[1]:Hide()
            old.pages[1] = nil
            old:ShowStep(1)
        end
    end
end

-- step : étape à afficher (par défaut : celle où un lien vers les options l'avait fermée, sinon le début)
function UI:ShowWelcome(step)
    if not ns.db then return end
    if not self.welcome then self.welcome = buildWelcome() end
    local f = self.welcome
    f:ShowStep(step or f.resume or 1)
    f.resume = nil
    f:Show()
    f:Raise()
    if not ns.db.welcomeSeen then ns:Set("welcomeSeen", true) end
end

-- première connexion avec Platyplus : la visite s'ouvre une seule fois, un instant après l'arrivée en jeu
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
