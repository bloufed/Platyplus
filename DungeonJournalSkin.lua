-- Platyplus : le journal des donjons aux couleurs de Platyplus (réglage dungeonSkin, onglet Donjons ; effet au /reload).
--
-- Rien n'est déplacé ni retiré : seul le dessin change, le journal garde sa mise en page et tout ce qu'il sait faire.
-- Le script d'import (dev/make_dungeonjournal.py) fait passer chaque couleur et chaque fond du journal par
-- DungeonJournalGlue.lua, qui les confie ici (D.PpSkin) :
--   * C(kind, r, g, b, a) : les bruns, bronzes et ors du journal deviennent les gris bleutés de Platyplus, à la même
--     clarté relative ; un or vif (survol, sélection) devient le bleu Platyplus ; le texte doré devient clair, l'encre
--     sombre des pages de quête aussi (le parchemin disparaît). Les couleurs qui ont un sens (qualité des objets,
--     vert « fait », rouge, cyan du mode « masquer ») restent les leurs ;
--   * les thèmes par donjon (UI/ThemeData.lua) sont réécrits avec les rôles de Platyplus : fond, panneau, carte,
--     liseré, sélection bleutée, texte, texte atténué ;
--   * Backdrop : liserés fins d'un pixel au lieu des bords de Blizzard, ni pierre ni parchemin ; une fenêtre posée
--     sur l'écran (le journal, ses favoris, son filtre de butin, ses réglages...) reçoit le cadre des fenêtres
--     Platyplus : fond sombre arrondi, liseré clair, ombre ;
--   * Highlight : la lueur dorée au survol devient le voile clair de Platyplus ;
--   * Widget : boutons de Blizzard en pastilles, croix dessinée, barres de défilement fines.
-- Les décisions sont prises à la construction de chaque cadre : changer le réglage demande un /reload.
local ADDON, ns = ...

local Skin = {}
ns.DungeonSkin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"
local min, max, floor = math.min, math.max, math.floor

-- le style est-il voulu ? (réglages chargés, widgets de Platyplus présents)
function Skin.On()
    return ns.db ~= nil and ns.db.dungeonSkin ~= false and ns.W ~= nil and ns.W.Round ~= nil
end

---------------------------------------------------------------------------
-- Couleurs
---------------------------------------------------------------------------
local T = ns.THEME

-- teinte (0-360), saturation, valeur
local function hsv(r, g, b)
    local hi, lo = max(r, g, b), min(r, g, b)
    local d = hi - lo
    local h = 0
    if d > 0 then
        if hi == r then h = 60 * (((g - b) / d) % 6)
        elseif hi == g then h = 60 * ((b - r) / d + 2)
        else h = 60 * ((r - g) / d + 4) end
    end
    return h, (hi > 0) and d / hi or 0, hi
end
Skin.HSV = hsv

local function lum(r, g, b) return 0.30 * r + 0.59 * g + 0.11 * b end

-- les teintes du journal : bruns, bronzes, ors (le décor) ; pour le texte, seulement les ors et les crèmes
-- (l'orange des objets légendaires, 30°, reste le sien)
local function warm(h, s) return s >= 0.08 and h >= 12 and h <= 65 end
local function golden(h, s) return s >= 0.08 and h >= 36 and h <= 62 end

-- gris bleuté de Platyplus à la clarté v (bg 0.07, panel 0.11, card 0.14 sur le vert)
local function cool(v) return v * 0.88, v, v * 1.28 end

-- clarté d'un fond du journal -> clarté d'un fond Platyplus (tout reste sombre, l'ordre est gardé)
local function darkLevel(r, g, b)
    return 0.055 + 0.13 * min(1, lum(r, g, b) / 0.32)
end

local function blend(r, g, b, c, t)
    return r + (c[1] - r) * t, g + (c[2] - g) * t, b + (c[3] - b) * t
end

local MAP = {}

-- fond (SetBackdropColor)
function MAP.bg(r, g, b, a, h, s, v)
    if s < 0.08 and (v <= 0.03 or v >= 0.97) then return r, g, b, a end   -- voiles noirs ou blancs
    if s >= 0.08 and not warm(h, s) then return r, g, b, a end            -- couleur qui a un sens (vert, cyan...)
    local R, G, B = cool(darkLevel(r, g, b))
    if s >= 0.45 and v >= 0.30 then R, G, B = blend(R, G, B, T.accent, 0.28) end   -- survol, sélection
    return R, G, B, a
end

-- liseré (SetBackdropBorderColor)
function MAP.edge(r, g, b, a, h, s, v)
    if s < 0.08 and v >= 0.97 then return r, g, b, a end                  -- déjà un liseré clair
    if s >= 0.25 and not warm(h, s) then return r, g, b, a end
    if warm(h, s) and s >= 0.45 and v >= 0.8 then return T.accent[1], T.accent[2], T.accent[3], a end
    return 1, 1, 1, (a or 1) * (0.07 + 0.08 * min(1, v / 0.6))
end

-- aplat (SetColorTexture) : bandeaux, filets, lueurs
function MAP.tex(r, g, b, a, h, s, v)
    if s < 0.08 or not warm(h, s) then return r, g, b, a end
    if v < 0.35 then
        local R, G, B = cool(darkLevel(r, g, b))
        return R, G, B, a
    end
    if (a or 1) >= 0.35 then return 1, 1, 1, 0.10 end                    -- filets
    return T.accent[1], T.accent[2], T.accent[3], a                       -- lueurs, voiles de survol
end

-- texte (SetTextColor)
function MAP.text(r, g, b, a, h, s, v)
    if v < 0.42 then
        if s >= 0.15 and not warm(h, s) then                              -- encre colorée : même teinte, éclaircie
            local k = 0.85 / max(v, 0.05)
            return min(1, r * k), min(1, g * k), min(1, b * k), a
        end
        local c = v < 0.2 and T.text or T.dim                             -- encre du parchemin
        return c[1], c[2], c[3], a
    end
    if s >= 0.15 and not golden(h, s) then return r, g, b, a end
    if (s >= 0.4 and v >= 0.75) or v >= 0.85 then return T.text[1], T.text[2], T.text[3], a end
    return T.dim[1], T.dim[2], T.dim[3], a
end

-- couleurs écrites dans les textes du journal (« |cff... ») : objectif rempli en vert, texte secondaire atténué
local function hexColor(c)
    return string.format("|cff%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end
local INK = { done = "good", muted = "dim" }
function Skin.Ink(role)
    local c = INK[role] and T[INK[role]]
    return c and hexColor(c) or nil
end

function Skin.C(kind, r, g, b, a)
    local fn = MAP[kind]
    if not fn or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return r, g, b, a end
    local h, s, v = hsv(r, g, b)
    return fn(r, g, b, a, h, s, v)
end

-- thèmes par donjon : les rôles de Platyplus (les tables sont modifiées sur place, le journal les garde en main)
function Skin.Themes(D)
    local themes = D and D.THEMES
    if type(themes) ~= "table" then return 0 end
    local C = T
    local sel = { blend(C.card[1], C.card[2], C.card[3], C.accent, 0.25) }
    local roles = {
        frame = { C.bg[1], C.bg[2], C.bg[3], 0.99 },
        content = { C.panel[1], C.panel[2], C.panel[3], 0.94 },
        border = { 1, 1, 1, 0.08 },
        header = { C.card[1], C.card[2], C.card[3], 0.96 },
        left = { C.panel[1], C.panel[2], C.panel[3], 0.94 },
        right = { C.panel[1], C.panel[2], C.panel[3], 0.94 },
        row = { C.card[1], C.card[2], C.card[3], 0.92 },
        rowSelected = { sel[1], sel[2], sel[3], 0.96 },
        lootRow = { C.card[1], C.card[2], C.card[3], 0.94 },
        title = { C.text[1], C.text[2], C.text[3] },
        text = { C.text[1], C.text[2], C.text[3] },
        muted = { C.dim[1], C.dim[2], C.dim[3] },
    }
    local done, n = {}, 0
    for _, theme in pairs(themes) do
        if type(theme) == "table" and not done[theme] then
            done[theme] = true
            for key, c in pairs(roles) do
                if type(theme[key]) == "table" then
                    local t = theme[key]
                    for i = 1, 4 do t[i] = c[i] end
                end
            end
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Boutons de Blizzard : croix dessinée, bouton texte en pastille (repris de l'ancien habillage de la carte)
---------------------------------------------------------------------------
-- cache les textures d'un cadre (pas ses textes) ; SetAlpha tient même si Blizzard les remontre
local function hideTextures(frame)
    if not (frame and frame.GetRegions) then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
end

local function hideButtonArt(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = b[get] and b[get](b)
        if t then t:SetAlpha(0) end
    end
end

-- deux traits tournés pour la croix : pas de police ni d'image du jeu à deviner
local function crossStrokes(parent)
    local out = {}
    for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSize(13, 2)
        t:SetPoint("CENTER", parent, "CENTER", 0, 0)
        if t.SetRotation then t:SetRotation(angle) end
        out[i] = t
    end
    return out
end

-- croix de fenêtre : glyphe clair, fond rouge léger au survol
local function closeButton(b)
    if not b or b.ppSkinned then return end
    b.ppSkinned = true
    local W, C = ns.W, ns.W.C
    hideButtonArt(b)
    b.ppBg = W.Round(b, "BACKGROUND", 0, 6)
    b.ppBg:AnchorBox(b, 2, 2, 2, 2)
    local glyph = crossStrokes(b)
    local function paint(hover)
        local c = hover and C.text or C.dim
        for _, t in ipairs(glyph) do t:SetVertexColor(c[1], c[2], c[3], 1) end
        b.ppBg:SetColor(hover and C.bad or C.white, hover and 0.22 or 0)
    end
    b:HookScript("OnEnter", function() paint(true) end)
    b:HookScript("OnLeave", function() paint(false) end)
    paint(false)
end

-- bouton texte de Blizzard (UIPanelButtonTemplate) : sa peau à trois morceaux remplacée par une pastille arrondie
local function panelButton(b)
    if not b or b.ppSkinned then return end
    b.ppSkinned = true
    local W, C = ns.W, ns.W.C
    hideTextures(b)
    hideButtonArt(b)
    b.ppBg = W.Round(b, "BACKGROUND", 1, 6)
    b.ppBg:SetColor(C.btn)
    b.ppHover = W.Round(b, "HIGHLIGHT", 0, 6)
    b.ppHover:SetColor(C.white, 0.07)
    local fs = b.GetFontString and b:GetFontString()
    if fs then fs:SetTextColor(C.text[1], C.text[2], C.text[3]) end
end

---------------------------------------------------------------------------
-- Fonds et fenêtres
---------------------------------------------------------------------------
-- cadre des fenêtres Platyplus sous une fenêtre du journal ; son propre fond devient transparent
function Skin.Window(f)
    if f.ppWindow then return end
    f.ppWindow = true
    local W, C = ns.W, ns.W.C
    f.ppShadow = W.Shadow(f, 14, 20, -3)
    f.ppShadow:SetColor(C.black, 0.55)
    f.ppBg = W.Round(f, "BACKGROUND", -7, 10)
    f.ppBg:SetColor(C.bg, 0.97)
    f.ppStroke = W.Stroke(f, "BORDER", -7, 10)
    f.ppStroke:SetColor(C.white, 0.09)
    local setColor, setBorder = f.SetBackdropColor, f.SetBackdropBorderColor
    if type(setColor) == "function" then
        f.SetBackdropColor = function(self, r, g, b) return setColor(self, r, g, b, 0) end
    end
    if type(setBorder) == "function" then
        f.SetBackdropBorderColor = function(self, r, g, b) return setBorder(self, r, g, b, 0) end
    end
    Skin.windows = (Skin.windows or 0) + 1
end

-- fenêtres du journal qui ne sont pas posées directement sur l'écran mais flottent comme des fenêtres
local WINDOW_NAMES = { PlatyplusDungeonLootFilter = true }

-- fenêtre construite sur un modèle de Blizzard (ButtonFrameTemplate, PortraitFrameTemplate,
-- BasicFrameTemplateWithInset : les Favoris) : son cadre métal, son portrait et ses fonds deviennent invisibles
-- (SetAlpha : ils restent transparents même si Blizzard les remontre), et elle reçoit le cadre Platyplus
local TEMPLATE_PIECES = { "NineSlice", "Bg", "Background", "TitleBg", "TopTileStreaks", "PortraitContainer", "portrait",
    "Portrait", "PortraitFrame", "TopLeftCorner", "TopRightCorner", "TopBorder", "BottomLeftCorner",
    "BottomRightCorner", "BottomBorder", "LeftBorder", "RightBorder", "InsetBg" }
function Skin.BlizzardWindow(win)
    if not win or win.ppWindow then return end
    for _, key in ipairs(TEMPLATE_PIECES) do
        local piece = win[key]
        if type(piece) == "table" and piece.SetAlpha then piece:SetAlpha(0) end
    end
    local inset = win.Inset
    if type(inset) == "table" then
        for _, key in ipairs({ "NineSlice", "Bg" }) do
            local piece = inset[key]
            if type(piece) == "table" and piece.SetAlpha then piece:SetAlpha(0) end
        end
    end
    Skin.Window(win)
    local close = win.CloseButton or (win.TitleContainer and win.TitleContainer.CloseButton)
    if close then closeButton(close) end
    local title = win.TitleText or (win.TitleContainer and win.TitleContainer.TitleText)
    if title and title.SetTextColor then title:SetTextColor(T.text[1], T.text[2], T.text[3]) end
end

function Skin.Backdrop(f, bd)
    local out = {}
    for k, v in pairs(bd) do out[k] = v end
    local edge = out.edgeFile ~= nil
    if edge then
        out.edgeFile = WHITE
        out.edgeSize = 1
    end
    if out.bgFile then out.bgFile = WHITE end
    out.tile, out.tileSize = false, nil
    local i = edge and 1 or 0
    out.insets = { left = i, right = i, top = i, bottom = i }
    local parent = f.GetParent and f:GetParent()
    local name = f.GetName and f:GetName()
    if out.bgFile and (parent == UIParent or (name and WINDOW_NAMES[name])) then Skin.Window(f) end
    return out
end

function Skin.Highlight(b)
    local t = b.GetHighlightTexture and b:GetHighlightTexture()
    if not t then return end
    t:SetColorTexture(1, 1, 1, 0.06)
    if t.SetBlendMode then t:SetBlendMode("BLEND") end
end

---------------------------------------------------------------------------
-- Boutons et barres de défilement de Blizzard
---------------------------------------------------------------------------
local function scrollBar(scroll)
    local name = scroll.GetName and scroll:GetName()
    local bar = scroll.ScrollBar or (name and rawget(_G, name .. "ScrollBar"))
    if not bar or bar.ppSkinned then return end
    bar.ppSkinned = true
    local barName = bar.GetName and bar:GetName()
    local thumb = bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture())
    for _, r in ipairs({ bar:GetRegions() }) do
        if r ~= thumb and r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local btn = bar[key] or (barName and rawget(_G, barName .. key))
        if btn then btn:SetAlpha(0) end
    end
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(1, 1, 1, 0.04)
    track:SetWidth(4)
    track:SetPoint("TOP", bar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    if thumb then
        thumb:SetTexture(WHITE)
        thumb:SetVertexColor(1, 1, 1, 0.24)
        thumb:SetWidth(4)
    end
end
Skin.ScrollBar = scrollBar

function Skin.Widget(template, f)
    if template == "UIPanelButtonTemplate" then
        panelButton(f)
    elseif template == "UIPanelCloseButton" then
        closeButton(f)
    elseif template == "UIPanelScrollFrameTemplate" then
        scrollBar(f)
    end
end

---------------------------------------------------------------------------
-- Onglet Quêtes : titres de sections, niveau requis, quête sélectionnée
---------------------------------------------------------------------------
-- Titres de sections de la page d'une quête (Objectif, Commence auprès de, À rendre à, Notes, Récompenses...) :
-- petites capitales bleues suivies d'un filet, comme les sections des fenêtres Platyplus, au lieu du même blanc
-- que le texte. La page se met en place d'après la hauteur réelle des textes : rien ne se chevauche.
local HEADERS = { "questObjectiveHeader", "questRequiredItemsHeader", "questProvidedItemHeader", "questStartsHeader",
    "questTurninHeader", "questNotesHeader", "questDescHeader", "questRewardHeader" }

local function stripCodes(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function upper(text)
    local win = ns.Win
    if win and win.Upper then return win.Upper(text) end
    return text:upper()
end

local function sectionHeader(fs)
    if not fs or fs.ppHeader then return end
    fs.ppHeader = true
    local A = T.accent
    local setText, setColor, show, hide, setShown = fs.SetText, fs.SetTextColor, fs.Show, fs.Hide, fs.SetShown
    if GameFontNormalSmall then fs:SetFontObject(GameFontNormalSmall) end
    fs.SetTextColor = function(self) return setColor(self, A[1], A[2], A[3], 1) end
    fs.SetText = function(self, text)
        if type(text) == "string" then text = upper(stripCodes(text)) end
        return setText(self, text)
    end
    fs:SetTextColor()
    fs:SetText(fs:GetText())
    -- filet à droite du titre, jusqu'au bord de la page ; suit le titre (montré, caché)
    local parent = fs:GetParent()
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    fs.ppLine = line
    fs.Show = function(self) show(self) line:Show() end
    fs.Hide = function(self) hide(self) line:Hide() end
    fs.SetShown = function(self, v) setShown(self, v) line:SetShown(v and true or false) end
    line:SetShown(fs:IsShown())
end

function Skin.AfterBuild(f)
    if not f or f.ppQuestStyled then return end
    f.ppQuestStyled = true
    for _, key in ipairs(HEADERS) do sectionHeader(f[key]) end
end

-- « À partir du niveau 14 » : rouge si ton niveau ne suffit pas encore (le texte vient du journal)
local levelPattern
local function requiredLevel(text)
    if not levelPattern then
        local D = ns.Dungeon
        local fmt = D and D.L and D.L("AVAILABLE_FROM_LEVEL")
        if type(fmt) ~= "string" or not fmt:find("%s", 1, true) then return nil end
        levelPattern = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"):gsub("%%%%s", "(%%d+)")
    end
    local n = stripCodes(text):match(levelPattern)
    return tonumber(n)
end
Skin.RequiredLevel = requiredLevel

local function playerLevel()
    local ok, lvl = pcall(UnitLevel, "player")
    local secret = rawget(_G, "issecretvalue")
    if not ok or type(lvl) ~= "number" or (secret and secret(lvl)) then return nil end
    return lvl
end

local function colorLevel(fs, done)
    if not (fs and fs.GetText) then return end
    local need, lvl = requiredLevel(fs:GetText()), playerLevel()
    local c = (need and lvl and lvl < need and not done) and T.bad or T.dim
    fs:SetTextColor(c[1], c[2], c[3])
    return need
end

function Skin.AfterQuests(kind, f)
    if not f then return end
    local D = ns.Dungeon
    if kind == "detail" then
        colorLevel(f.selectedQuestMeta)
        -- le filet de « Commence auprès de » laisse la place à l'icône « commence dans le donjon »
        local h, icon = f.questStartsHeader, f.questStartDungeonIcon
        if h and h.ppLine then
            h.ppLine:ClearAllPoints()
            if icon and icon:IsShown() then h.ppLine:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            else h.ppLine:SetPoint("LEFT", h, "RIGHT", 8, 0) end
            h.ppLine:SetPoint("RIGHT", h:GetParent(), "RIGHT", -6, 0)
        end
        return
    end
    -- liste : barre bleue sur la quête sélectionnée, niveau requis en rouge s'il manque, « en cours » en bleu
    local list = f.questContent
    if not list then return end
    local selected = D and D.PpSelectedQuest and D.PpSelectedQuest()
    local A = T.accent
    for _, row in ipairs({ list:GetChildren() }) do
        if row.questIndex and row.meta and row:IsShown() then
            if not row.ppBar then
                row.ppBar = row:CreateTexture(nil, "OVERLAY")
                row.ppBar:SetColorTexture(A[1], A[2], A[3], 1)
                row.ppBar:SetWidth(3)
                row.ppBar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -6)
                row.ppBar:SetHeight(36)
            end
            row.ppBar:SetShown(row.questIndex == selected)
            colorLevel(row.meta, row.check and row.check:IsShown())
            if row.haveIt then row.haveIt:SetTextColor(A[1], A[2], A[3]) end
        end
    end
end

---------------------------------------------------------------------------
-- Démarrage (ADDON_LOADED, depuis Core.lua) : avant que le journal construise ses fenêtres (PLAYER_LOGIN)
---------------------------------------------------------------------------
function Skin:Init()
    local D = ns.Dungeon
    if not D or D.PpStandby or not Skin.On() then return end
    D.PpSkin = { C = Skin.C, Backdrop = Skin.Backdrop, Highlight = Skin.Highlight, Widget = Skin.Widget,
        AfterBuild = Skin.AfterBuild, AfterQuests = Skin.AfterQuests, Ink = Skin.Ink }
    Skin.themes = Skin.Themes(D)
    -- les Favoris : une fenêtre sur modèle de Blizzard, construite à la première ouverture
    if type(D.ToggleFavouritesWindow) == "function" then
        local toggle = D.ToggleFavouritesWindow
        D.ToggleFavouritesWindow = function(...)
            local r = { toggle(...) }
            local win = rawget(_G, "PlatyplusDungeonFavourites")
            if win and not win.ppWindow then
                local ok, err = pcall(Skin.BlizzardWindow, win)
                if not ok then geterrorhandler()(err) end
            end
            return unpack(r)
        end
    end
    Skin.active = true
end

-- pour /pp donjons
function Skin:Status()
    if not Skin.active then
        return ns.Tf("style Platyplus : %s", ns.T((ns.db and ns.db.dungeonSkin == false) and "éteint" or "inactif"))
    end
    return ns.Tf("style Platyplus : allumé (%d thèmes de donjon, %d fenêtres habillées)",
        Skin.themes or 0, Skin.windows or 0)
end
