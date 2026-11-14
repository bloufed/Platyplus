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
--
-- Addon DungeonJournal d'Exehn installé à part (pas de journal intégré actif) : le même style est posé sur SA
-- fenêtre, de l'extérieur (« surcharge », en bas du fichier), avec les mêmes fonctions C / Backdrop / Highlight /
-- Widget, appelées derrière lui par hooksecurefunc au lieu des points d'accroche.
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
-- (pieces : l'addon séparé, pris en main après coup — seuls les trois morceaux du modèle sont cachés, pas les
-- images que le journal a pu poser ensuite sur son bouton)
local function panelButton(b, pieces)
    if not b or b.ppSkinned then return end
    b.ppSkinned = true
    local W, C = ns.W, ns.W.C
    if pieces then
        for _, key in ipairs(pieces) do
            local t = b[key]
            if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
        end
    else
        hideTextures(b)
    end
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
    -- (addon séparé : rien n'est remplacé sur ses cadres ; les hooks de la surcharge rendent son fond transparent
    -- d'après f.ppWindow)
    if not Skin.external then
        local setColor, setBorder = f.SetBackdropColor, f.SetBackdropBorderColor
        if type(setColor) == "function" then
            f.SetBackdropColor = function(self, r, g, b) return setColor(self, r, g, b, 0) end
        end
        if type(setBorder) == "function" then
            f.SetBackdropBorderColor = function(self, r, g, b) return setBorder(self, r, g, b, 0) end
        end
    end
    Skin.windows = (Skin.windows or 0) + 1
end

-- fenêtres du journal qui ne sont pas posées directement sur l'écran mais flottent comme des fenêtres
local WINDOW_NAMES = { PlatyplusDungeonLootFilter = true, ForeverDungeonJournalLootFilter = true }

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

-- liseré fin d'un pixel, fond uni (modifie la table donnée)
local function flatten(out)
    local edge = out.edgeFile ~= nil
    if edge then
        out.edgeFile = WHITE
        out.edgeSize = 1
    end
    if out.bgFile then out.bgFile = WHITE end
    out.tile, out.tileSize = false, nil
    local i = edge and 1 or 0
    out.insets = { left = i, right = i, top = i, bottom = i }
    return out
end

-- un cadre posé sur l'écran (ou qui flotte comme une fenêtre) et qui a un fond : une fenêtre
local function isWindow(f, bd)
    local parent = f.GetParent and f:GetParent()
    local name = f.GetName and f:GetName()
    return bd.bgFile ~= nil and (parent == UIParent or (name ~= nil and WINDOW_NAMES[name] == true))
end

function Skin.Backdrop(f, bd)
    local out = {}
    for k, v in pairs(bd) do out[k] = v end
    flatten(out)
    if isWindow(f, out) then Skin.Window(f) end
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

local sectionHeaderExternal   -- (surcharge : les mêmes titres, par hooks ; défini plus bas)

local function sectionHeader(fs)
    if not fs or fs.ppHeader then return end
    fs.ppHeader = true
    local A = T.accent
    if Skin.external then return sectionHeaderExternal(fs, A) end
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
        local D = Skin.external or ns.Dungeon
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
    if Skin.external then
        -- (addon séparé : il note la quête sélectionnée dans ses réglages)
        local db = rawget(_G, "ForeverDungeonJournalDB")
        selected = type(db) == "table" and db.lastQuest or nil
    end
    local A = T.accent
    for _, row in ipairs({ list:GetChildren() }) do
        if row.questIndex and row.meta and row:IsShown() then
            if not row.ppBar then
                row.ppBar = row:CreateTexture(nil, "OVERLAY")
                row.ppBar:SetColorTexture(A[1], A[2], A[3], 1)
                row.ppBar:SetWidth(3)
                row.ppBar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -6)
                row.ppBar:SetHeight(36)
                if Skin.external and Skin.Ext then Skin.Ext.QuestRow(row) end
            end
            row.ppBar:SetShown(row.questIndex == selected)
            colorLevel(row.meta, row.check and row.check:IsShown())
            if row.haveIt then row.haveIt:SetTextColor(A[1], A[2], A[3]) end
        end
    end
end

---------------------------------------------------------------------------
-- Surcharge : le même style sur l'addon DungeonJournal d'Exehn installé à part (ForeverDungeonJournal)
---------------------------------------------------------------------------
-- Aucun de ses fichiers n'est embarqué et aucune de ses fonctions n'est remplacée : Platyplus passe DERRIÈRE lui.
--   * avant qu'il construise sa fenêtre (ADDON_LOADED) : ses thèmes par donjon (FDJ.THEMES, des données) sont
--     réécrits comme ceux du journal intégré ;
--   * chaque cadre, texte et aplat du journal est « pris en main » une fois : un hooksecurefunc sur SES méthodes
--     (SetBackdrop, SetBackdropColor, SetBackdropBorderColor, SetTextColor, SetColorTexture, SetHighlightTexture)
--     convertit chaque couleur que le journal y pose. La conversion rappelle la méthode d'origine, prise avant le
--     hook : pas de boucle ;
--   * la prise en main se fait À LA CRÉATION, comme pour le journal intégré : un hooksecurefunc sur CreateFrame
--     (qui ne regarde que les cadres nommés ForeverDungeonJournal* posés sur l'écran et les enfants des cadres
--     déjà connus) et sur CreateTexture / CreateFontString de chaque cadre connu. Le journal pose donc ses
--     couleurs APRÈS nos hooks, y compris pendant la construction de sa fenêtre (PLAYER_LOGIN) ;
--   * filet de sécurité : ce qui aurait échappé (cadre déplacé d'un parent à l'autre...) est repris par un passage
--     léger sur sa fenêtre principale — le nombre d'enfants et de régions de chaque cadre connu est relu dix fois
--     par seconde tant qu'elle est affichée (OnUpdate d'un cadre enfant : rien quand elle est fermée), et seuls
--     les cadres qui ont changé sont relus. Un aplat repris ainsi garde sa couleur jusqu'à ce que le journal la
--     repose (le jeu ne sait pas relire la couleur d'un aplat).
-- Si l'addon change (un champ ou une fonction manque), la partie concernée ne se fait pas, sans message : le
-- journal garde son look à cet endroit.
local Ext = {}
Skin.Ext = Ext
Ext.count = 0

-- ses fenêtres posées sur l'écran : reconnues à leur création par leur nom (EXT_PREFIX) ; cette liste sert de
-- filet de sécurité pour celles qui existeraient déjà (la principale : ForeverDungeonJournalFrame)
local EXT_PREFIX = "^ForeverDungeonJournal"
local EXT_WINDOWS = { "ForeverDungeonJournalFavourites", "ForeverDungeonJournalSettings", "ForeverDungeonJournalLFGMenu",
    "ForeverDungeonJournalCopyBox", "ForeverDungeonJournalRPGConfirm", "ForeverDungeonJournalModeChooser",
    "ForeverDungeonJournalFavouriteContextMenu", "ForeverDungeonJournalRunLog", "ForeverDungeonJournalRunLogMenu",
    "ForeverDungeonJournalTrackerMenu", "ForeverDungeonJournalSleepingBagMenu" }
-- ses parchemins (champs de sa fenêtre) ; les autres sont reconnus à leur image (QuestBG)
local EXT_PARCHMENTS = { "homeParchment", "contentParchment", "headerParchment", "leftParchment", "rightParchment",
    "questLeftParchment", "questRightParchment", "questParchment" }
-- les surbrillances de Blizzard qu'il pose sur ses boutons (SetHighlightTexture)
local EXT_HIGHLIGHTS = { "ui-questtitlehighlight", "buttonhilight-square", "ui-common-mousehilight",
    "ui-plusbutton-hilight", "sizegrabber-highlight" }
local PANEL_PIECES = { "Left", "Middle", "Right" }
local EXT_TEMPLATES = { "UIPanelButtonTemplate", "UIPanelCloseButton", "UIPanelScrollFrameTemplate" }
local SWEEP_EVERY = 0.1

local seen = setmetatable({}, { __mode = "k" })    -- cadres et régions déjà pris en main
local sizes = setmetatable({}, { __mode = "k" })   -- cadre -> enfants et régions comptés au dernier passage
local flat = setmetatable({}, { __mode = "k" })    -- tables de fond du journal déjà aplaties (sur place)
local copies = setmetatable({}, { __mode = "k" })  -- table de fond du jeu -> sa copie aplatie
local knownRegions = setmetatable({}, { __mode = "k" })   -- cadre -> régions comptées à la dernière prise en main
local knownChildren = setmetatable({}, { __mode = "k" })  -- cadre -> enfants comptés
local roots = {}                                   -- fenêtre -> liste de ses cadres
local rootOf = setmetatable({}, { __mode = "k" })  -- cadre -> liste de sa fenêtre
local shared = {}                                  -- [fonction][méthode d'origine] = hook partagé
local direct = false                               -- nos propres créations et couleurs : laissées telles quelles

-- des nombres ordinaires (ni nil ni valeur secrète)
local function plain(...)
    local secret = rawget(_G, "issecretvalue")
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if (secret and secret(v)) or type(v) ~= "number" then return false end
    end
    return true
end

-- Après chaque obj:method(...) du journal, fn(raw, obj, ...) ; raw est la méthode d'avant le hook (l'appeler ne
-- repasse pas par le hook). Un seul hook par (fonction, méthode d'origine), partagé par tous les objets.
local function after(obj, method, fn)
    local hook = rawget(_G, "hooksecurefunc")
    if type(obj) ~= "table" or type(hook) ~= "function" then return false end
    local raw = obj[method]
    if type(raw) ~= "function" then return false end
    local byRaw = shared[fn]
    if not byRaw then
        byRaw = {}
        shared[fn] = byRaw
    end
    local run = byRaw[raw]
    if not run then
        local busy = false
        run = function(self, ...)
            if busy then return end
            busy = true
            local ok, err = pcall(fn, raw, self, ...)
            busy = false
            if not ok then ns:Debug("journal des donjons (style) : " .. tostring(err)) end
        end
        byRaw[raw] = run
    end
    return (pcall(hook, obj, method, run))
end

-- une couleur de Platyplus posée sur un objet du journal : telle quelle, sans conversion
function Skin.Direct(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return end
    local was = direct
    direct = true
    local ok, err = pcall(fn, obj, ...)
    direct = was
    if not ok then error(err, 0) end
end

-- ce que Platyplus crée lui-même sur la fenêtre du journal (colonne, pastilles) : pas pris en main
function Skin.Own(fn, ...)
    if not Skin.external then return fn(...) end
    local was = direct
    direct = true
    local ok, a = pcall(fn, ...)
    direct = was
    if not ok then error(a, 0) end
    return a
end

-- les habillages de Platyplus (cadre de fenêtre, pastille de bouton...) : mêmes fonctions que pour le journal
-- intégré, sans que leurs propres textures soient prises pour celles du journal
local function own(fn, ...)
    local was = direct
    direct = true
    local ok, err = pcall(fn, ...)
    direct = was
    if not ok then ns:Debug("journal des donjons (style) : " .. tostring(err)) end
end

local function recolor(raw, self, kind, r, g, b, a)
    local R, G, B, A = Skin.C(kind, r, g, b, a)
    if R ~= r or G ~= g or B ~= b or A ~= a then raw(self, R, G, B, A) end
end

local function hookBg(raw, self, r, g, b, a)
    if direct then return end
    if self.ppWindow then return raw(self, r, g, b, 0) end   -- fenêtre : son fond laisse la place au cadre Platyplus
    recolor(raw, self, "bg", r, g, b, a)
end

local function hookEdge(raw, self, r, g, b, a)
    if direct then return end
    if self.ppWindow then return raw(self, r, g, b, 0) end
    recolor(raw, self, "edge", r, g, b, a)
end

local function hookText(raw, self, r, g, b, a)
    if direct then return end
    recolor(raw, self, "text", r, g, b, a)
end

local function hookTex(raw, self, r, g, b, a)
    if direct then return end
    recolor(raw, self, "tex", r, g, b, a)
end

local function hookHighlight(_, self)
    own(Skin.Highlight, self)
end

-- objectif rempli : le brun du parchemin, écrit dans le texte, devient le vert « fait »
local function hookInk(raw, self, text)
    if type(text) ~= "string" or not text:find("|cff6e5c40", 1, true) then return end
    local done = Skin.Ink("done")
    if done then raw(self, (text:gsub("|cff6e5c40", done))) end
end

-- le fond vient d'être aplati : Blizzard le redessine (et remet ses couleurs à blanc, par nos hooks)
local function reapply(self, raw, info)
    if type(self.ApplyBackdrop) == "function" then
        self:ApplyBackdrop()
    elseif raw then
        raw(self, nil)
        raw(self, info)
    end
end

local function repaint(self)
    local r, g, b, a = self:GetBackdropColor()
    if plain(r, g, b) then self:SetBackdropColor(r, g, b, a) end
    r, g, b, a = self:GetBackdropBorderColor()
    if plain(r, g, b) then self:SetBackdropBorderColor(r, g, b, a) end
end

-- une table de fond du jeu (constante de Blizzard, fond d'un modèle) : ses champs sont « sûrs ». Platyplus n'y
-- écrit jamais (elle sert aussi aux infobulles et aux fenêtres du jeu)
local function gameOwned(info)
    local secure = rawget(_G, "issecurevariable")
    if type(secure) ~= "function" then return false end
    for _, key in ipairs({ "bgFile", "edgeFile" }) do
        if info[key] ~= nil then
            local ok, yes = pcall(secure, info, key)
            if ok and yes then return true end
        end
    end
    return false
end

-- Le journal a posé un fond. Sa table est aplatie SUR PLACE (une donnée du journal, comme ses thèmes ; le cadre
-- garde la même table, donc un second SetBackdrop identique reste sans effet comme chez Blizzard). Une table qui
-- appartient au jeu n'est pas touchée : le cadre reçoit une copie aplatie. raw : SetBackdrop d'avant le hook.
local function restyle(self, raw, info, always)
    if gameOwned(info) then
        local copy = copies[info]
        if not copy then
            copy = {}
            for k, v in pairs(info) do copy[k] = v end
            flatten(copy)
            flat[copy] = true
            copies[info] = copy
        end
        if isWindow(self, copy) and not self.ppWindow then own(Skin.Window, self) end
        if raw then raw(self, copy) end
        return
    end
    local fresh = not flat[info]
    if fresh then
        flat[info] = true
        flatten(info)
    end
    local window = isWindow(self, info) and not self.ppWindow
    if window then own(Skin.Window, self) end
    if fresh or always then reapply(self, raw, info)
    elseif window then repaint(self) end
end

local function hookBackdrop(raw, self, info)
    if type(info) ~= "table" then return end
    restyle(self, raw, info)
end

-- chemin d'image en minuscules, ou nil (aplat, image du jeu sans chemin)
local function texturePath(t)
    local path = t.GetTextureFilePath and t:GetTextureFilePath()
    if type(path) ~= "string" then path = t.GetTexture and t:GetTexture() end
    if type(path) ~= "string" then return nil end
    return (path:lower():gsub("/", "\\"))
end

-- la couleur d'un texte est-elle celle de sa police ? (le journal ne l'a pas choisie : on la laisse)
local function fontColor(fs, r, g, b)
    local font = fs.GetFontObject and fs:GetFontObject()
    if type(font) ~= "table" or type(font.GetTextColor) ~= "function" then return false end
    local fr, fg, fb = font:GetTextColor()
    return plain(fr, fg, fb) and math.abs(fr - r) < 0.004 and math.abs(fg - g) < 0.004 and math.abs(fb - b) < 0.004
end

local function isCloseButton(b)
    local t = b.GetNormalTexture and b:GetNormalTexture()
    if type(t) ~= "table" then return false end
    local atlas = t.GetAtlas and t:GetAtlas()
    if type(atlas) == "string" and atlas:lower():find("redbutton-exit", 1, true) then return true end
    local path = texturePath(t)
    return path ~= nil and path:find("ui-panel-minimizebutton", 1, true) ~= nil
end

local function adoptRegion(r)
    local kind = r.GetObjectType and r:GetObjectType()
    if kind == "FontString" then
        if not after(r, "SetTextColor", hookText) then return end
        local cr, cg, cb, ca = r:GetTextColor()
        if plain(cr, cg, cb) and not fontColor(r, cr, cg, cb) then r:SetTextColor(cr, cg, cb, ca) end
    elseif kind == "Texture" then
        local path = texturePath(r)
        if path and path:find("questframe\\questbg", 1, true) then
            r:Hide()   -- parchemin (le journal ne le remontre jamais : il ne change que sa teinte)
            return
        end
        if not after(r, "SetColorTexture", hookTex) then return end
    else
        return
    end
    Ext.count = Ext.count + 1
end

local function count(f)
    local children = f.GetNumChildren and f:GetNumChildren() or select("#", f:GetChildren())
    local regions = f.GetNumRegions and f:GetNumRegions() or select("#", f:GetRegions())
    return children, regions
end

-- Le journal vient de créer une texture ou un texte sur un cadre connu : en principe sa dernière région. Si le
-- compte ne tombe pas juste (autre ordre que celui de création, régions de Platyplus pas encore vues), toutes
-- celles qui ne sont pas encore vues sont prises.
local function hookNewRegion(_, self)
    if direct then return end
    local _, n = count(self)
    if n == 0 then return end
    local r = select(n, self:GetRegions())
    local expected = (knownRegions[self] or 0) + 1 == n and type(r) == "table" and not seen[r]
    if expected then
        seen[r] = true
        adoptRegion(r)
    else
        for _, x in ipairs({ self:GetRegions() }) do
            if not seen[x] then
                seen[x] = true
                pcall(adoptRegion, x)
            end
        end
    end
    knownRegions[self] = n
end

-- template : le modèle donné à CreateFrame, quand le cadre est pris en main à sa création
local function adoptFrame(f, template)
    Ext.count = Ext.count + 1
    -- fond : aplati, couleurs du moment converties, puis suivi
    if type(f.SetBackdrop) == "function" and type(f.SetBackdropColor) == "function" then
        local info = f.backdropInfo
        local br, bg, bb, ba, er, eg, eb, ea
        if type(info) == "table" then
            br, bg, bb, ba = f:GetBackdropColor()
            er, eg, eb, ea = f:GetBackdropBorderColor()
        end
        local rawSet = f.SetBackdrop
        after(f, "SetBackdrop", hookBackdrop)
        after(f, "SetBackdropColor", hookBg)
        after(f, "SetBackdropBorderColor", hookEdge)
        if type(info) == "table" then
            -- (redessiné dans tous les cas : sa table a pu être aplatie pour un autre cadre depuis son dernier dessin)
            restyle(f, rawSet, info, true)
            if plain(br, bg, bb) then f:SetBackdropColor(br, bg, bb, ba) end
            if plain(er, eg, eb) then f:SetBackdropBorderColor(er, eg, eb, ea) end
        end
    end
    -- boutons et barres de défilement de Blizzard, surbrillances
    local kind = f.GetObjectType and f:GetObjectType()
    local widget
    if type(template) == "string" then
        for _, name in ipairs(EXT_TEMPLATES) do
            if template:find(name, 1, true) then widget = name break end
        end
    end
    if widget then
        own(Skin.Widget, widget, f)
    elseif template ~= nil then
        -- (créé sur un autre modèle : laissé tel quel, comme dans le journal intégré)
    elseif kind == "ScrollFrame" then
        own(scrollBar, f)
    elseif (kind == "Button" or kind == "CheckButton") and not f.ppSkinned then
        -- (cadre repris après coup, modèle inconnu : reconnu à ses morceaux)
        if kind == "Button" and type(f.Left) == "table" and type(f.Middle) == "table" and type(f.Right) == "table" then
            own(panelButton, f, PANEL_PIECES)
        elseif kind == "Button" and isCloseButton(f) then
            own(closeButton, f)
        else
            local hl = f.GetHighlightTexture and f:GetHighlightTexture()
            local path = type(hl) == "table" and texturePath(hl)
            if path then
                for _, name in ipairs(EXT_HIGHLIGHTS) do
                    if path:find(name, 1, true) then
                        own(Skin.Highlight, f)
                        break
                    end
                end
            end
        end
    end
    if kind == "Button" or kind == "CheckButton" then after(f, "SetHighlightTexture", hookHighlight) end
    if kind == "EditBox" then after(f, "SetTextColor", hookText) end
    -- ce que le journal y créera : pris en main aussitôt
    after(f, "CreateTexture", hookNewRegion)
    after(f, "CreateFontString", hookNewRegion)
end

-- un cadre du journal qu'on peut habiller : pas les nôtres, ni un cadre protégé ou interdit, ni une infobulle
-- (ses lignes sont écrites par le jeu, avec les couleurs du jeu)
local function usable(f)
    if type(f) ~= "table" then return false end
    if f.IsForbidden and f:IsForbidden() then return false end
    if f.ppOwn then return false end
    if f.IsProtected and f:IsProtected() then return false end
    if f.GetObjectType and f:GetObjectType() == "GameTooltip" then return false end
    return true
end

-- nombre d'enfants et de régions en un seul nombre ; nil si le jeu refuse de le dire (erreur, valeur secrète)
local function signature(f)
    local ok, children, regions = pcall(count, f)
    if not ok or not plain(children, regions) then return nil end
    knownChildren[f], knownRegions[f] = children, regions
    return children * 100000 + regions
end

local take

-- régions et enfants directs d'un cadre : les nouveaux sont pris en main
local function scan(f, list)
    local n = 0
    for _, r in ipairs({ f:GetRegions() }) do
        if not seen[r] then
            seen[r] = true
            n = n + 1
            pcall(adoptRegion, r)
        end
    end
    for _, child in ipairs({ f:GetChildren() }) do
        if not seen[child] then n = n + take(child, list) end
    end
    return n
end

-- un cadre nouveau, avec ce qu'il contient déjà (les morceaux de son modèle) ; il rejoint la liste de sa fenêtre
take = function(f, list, template)
    seen[f] = true
    if not usable(f) then return 0 end
    rootOf[f] = list
    list[#list + 1] = f
    pcall(adoptFrame, f, template)
    local ok, n = pcall(scan, f, list)
    sizes[f] = signature(f)
    return 1 + (ok and n or 0)
end

-- passage sur une fenêtre : seuls les cadres dont le nombre d'enfants ou de régions a changé sont relus
function Ext.Sweep(root)
    local list = roots[root]
    if not list then return 0 end
    local found, i = 0, 1
    while i <= #list do
        local f = list[i]
        local now = signature(f)
        if now and sizes[f] ~= now then
            local ok, n = pcall(scan, f, list)
            if ok then found = found + n end
            sizes[f] = signature(f)
        end
        i = i + 1
    end
    return found
end

-- liste des quêtes et page d'une quête : repassées une fois, à l'image suivante (le journal finit son dessin)
local questsPending = false
local function questsSoon()
    if questsPending then return end
    questsPending = true
    local function run()
        questsPending = false
        local f = Ext.main
        if not (f and f.IsShown and f:IsShown()) then return end
        pcall(Skin.AfterQuests, "list", f)
        pcall(Skin.AfterQuests, "detail", f)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end
Ext.QuestsSoon = questsSoon

-- une ligne de la liste des quêtes vient d'être habillée : son prochain dessin repassera par ici
function Ext.QuestRow(row)
    after(row.meta, "SetText", questsSoon)
end

-- parchemins restés sans champ (page du chemin vers l'entrée) : reconnus à leur image
local function hideParchments(f)
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then
            local path = texturePath(r)
            if path and path:find("questframe\\questbg", 1, true) then r:Hide() end
        end
    end
    for _, child in ipairs({ f:GetChildren() }) do
        if usable(child) then hideParchments(child) end
    end
end

function Ext.Tick(root)
    local n = Ext.Sweep(root)
    if root == Ext.main then
        Ext.Windows()
        if n > 0 then questsSoon() end
    end
end

-- une fenêtre du journal : habillée en entier, avec ce qu'elle contient déjà
function Ext.Adopt(win, template)
    if roots[win] or seen[win] or not usable(win) then return false end
    local list = {}
    roots[win] = list
    -- fenêtre sur un modèle de Blizzard (les Favoris) : cadre métal et portrait effacés
    if win.NineSlice or win.TitleContainer or win.PortraitContainer or win.Inset then own(Skin.BlizzardWindow, win) end
    local close = win.closeButton
    if type(close) == "table" and not close.ppSkinned then own(closeButton, close) end
    take(win, list, template)
    return true
end

-- filet de sécurité : passage léger sur la fenêtre principale tant qu'elle est affichée
local function watch(win)
    if win.ppWatch then return end
    local wait = 0
    own(function()
        local ticker = CreateFrame("Frame", nil, win)
        ticker.ppOwn = true
        seen[ticker] = true
        win.ppWatch = ticker
        ticker:SetScript("OnUpdate", function(_, elapsed)
            wait = wait + (elapsed or 0)
            if wait < SWEEP_EVERY then return end
            wait = 0
            local ok, err = pcall(Ext.Tick, win)
            if not ok then ns:Debug("journal des donjons (style) : " .. tostring(err)) end
        end)
    end)
end

-- le journal vient de créer un cadre : une de ses fenêtres (nommée, posée sur l'écran), ou l'enfant d'un cadre
-- connu (nommé : on le retrouve par son nom ; sinon c'est le dernier enfant de son parent)
local function created(kind, name, parent, template)
    local list = rootOf[parent]
    if list then
        local n = count(parent)
        local f = type(name) == "string" and rawget(_G, name) or nil
        if type(f) ~= "table" and n > 0 then f = select(n, parent:GetChildren()) end
        if type(f) == "table" and not seen[f] and (knownChildren[parent] or 0) + 1 == n then
            take(f, list, template)
        else
            -- (pas le compte attendu : autre ordre que celui de création, ou cadres de Platyplus pas encore vus)
            for _, child in ipairs({ parent:GetChildren() }) do
                if not seen[child] then take(child, list, child == f and template or nil) end
            end
        end
        knownChildren[parent] = n
    elseif parent == UIParent and type(name) == "string" and name:find(EXT_PREFIX) and kind ~= "GameTooltip" then
        local f = rawget(_G, name)
        if type(f) == "table" then Ext.Adopt(f, template) end
    end
end

-- Ce hook tourne après CHAQUE CreateFrame du jeu : c'est la partie la plus large de la surcharge. Il sort tout de
-- suite, sans pcall ni table, pour tout cadre qui n'est ni une fenêtre du journal (posée sur l'écran, nom
-- ForeverDungeonJournal*) ni l'enfant d'un cadre déjà connu. Ext.stats compte ce qu'il voit et ce qu'il coûte
-- (/pp donjons etat) ; éteindre « Style Platyplus » puis /reload le retire entièrement.
local stats = { calls = 0, taken = 0, ms = 0 }
Ext.stats = stats
local EXT_NAME = "ForeverDungeonJournal"
local function hookCreateFrame(kind, name, parent, template)
    stats.calls = stats.calls + 1
    if direct or parent == nil then return end
    if parent == UIParent then
        if type(name) ~= "string" or name:sub(1, #EXT_NAME) ~= EXT_NAME then return end
    elseif rootOf[parent] == nil then
        return
    end
    local clock = rawget(_G, "debugprofilestop")
    local t0 = type(clock) == "function" and clock() or nil
    local ok, err = pcall(created, kind, name, parent, template)
    stats.taken = stats.taken + 1
    if t0 then stats.ms = stats.ms + (clock() - t0) end
    if not ok then ns:Debug("journal des donjons (style) : " .. tostring(err)) end
end

-- ses autres fenêtres, dès qu'elles existent
function Ext.Windows()
    for _, name in ipairs(EXT_WINDOWS) do
        local win = rawget(_G, name)
        if win and not roots[win] then Ext.Adopt(win) end
    end
end

sectionHeaderExternal = function(fs, A)
    seen[fs] = true
    if GameFontNormalSmall then fs:SetFontObject(GameFontNormalSmall) end
    local parent = fs:GetParent()
    local line = parent:CreateTexture(nil, "ARTWORK")
    seen[line] = true
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    fs.ppLine = line
    after(fs, "SetTextColor", function(raw, self) raw(self, A[1], A[2], A[3], 1) end)
    after(fs, "SetText", function(raw, self, text)
        if type(text) ~= "string" then return end
        local up = upper(stripCodes(text))
        if up ~= text then raw(self, up) end
    end)
    after(fs, "Show", function() line:Show() end)
    after(fs, "Hide", function() line:Hide() end)
    after(fs, "SetShown", function(_, _, v) line:SetShown(v and true or false) end)
    fs:SetTextColor(A[1], A[2], A[3], 1)
    fs:SetText(fs:GetText())
    line:SetShown(fs:IsShown())
end

-- sa fenêtre principale vient d'être construite
function Ext.Main(f)
    if Ext.main or type(f) ~= "table" then return end
    Ext.main = f
    for _, key in ipairs(EXT_PARCHMENTS) do
        local t = f[key]
        if type(t) == "table" and t.Hide then
            seen[t] = true
            t:Hide()
        end
    end
    pcall(hideParchments, f)
    own(Skin.AfterBuild, f)
    -- textes de la page d'une quête : objectifs remplis en vert ; chaque dessin d'une quête repasse le style
    for key, v in pairs(f) do
        if type(key) == "string" and key:find("[Qq]uest") and type(v) == "table" and not v.ppHeader
            and type(v.GetObjectType) == "function" and v:GetObjectType() == "FontString" then
            after(v, "SetText", hookInk)
        end
    end
    after(f.selectedQuestMeta, "SetText", questsSoon)
    local P = ns.DungeonPlus
    if P and P.HookScript then P.HookScript(f.questLeftPanel, "OnShow", questsSoon) end
    Ext.Adopt(f)
    watch(f)
    Ext.Sweep(f)
    Ext.Windows()
end

-- ADDON_LOADED : l'addon séparé est déjà chargé (OptionalDeps), sa fenêtre pas encore construite
function Ext.Init()
    local P = ns.DungeonPlus
    if not (P and P.Standalone and P.StandaloneNS and P.WhenBuilt and P.Standalone()) then return end
    local X = P.StandaloneNS()
    if not X or type(rawget(_G, "hooksecurefunc")) ~= "function" then return end
    Skin.external = X
    local ok, n = pcall(Skin.Themes, X)
    Skin.themes = ok and n or 0
    Skin.active = true
    -- tout ce que le journal crée à partir de maintenant est pris en main à sa création
    pcall(hooksecurefunc, "CreateFrame", hookCreateFrame)
    P.WhenBuilt(Ext.Main)
    -- ses fenêtres ouvertes à la demande : réglages, Favoris (sur un modèle de Blizzard, comme pour le journal
    -- intégré : cadre métal effacé, cadre Platyplus)
    P.Hook(X, "ToggleSettingsPanel", Ext.Windows)
    P.Hook(X, "ToggleFavouritesWindow", function()
        Ext.Windows()
        local win = rawget(_G, "ForeverDungeonJournalFavourites")
        if win and not win.ppWindow then own(Skin.BlizzardWindow, win) end
    end)
end

---------------------------------------------------------------------------
-- Démarrage (ADDON_LOADED, depuis Core.lua) : avant que le journal construise ses fenêtres (PLAYER_LOGIN)
---------------------------------------------------------------------------
function Skin:Init()
    local D = ns.Dungeon
    if not D or D.PpStandby then
        -- pas de journal intégré actif : l'addon d'Exehn installé à part, s'il est chargé (surcharge)
        if Skin.On() then Skin.Ext.Init() end
        return
    end
    if not Skin.On() then return end
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
    if Skin.external then
        return ns.Tf("style Platyplus : allumé sur l'addon séparé (%d thèmes de donjon, %d fenêtres habillées, %d éléments suivis)",
            Skin.themes or 0, Skin.windows or 0, Skin.Ext.count or 0)
    end
    return ns.Tf("style Platyplus : allumé (%d thèmes de donjon, %d fenêtres habillées)",
        Skin.themes or 0, Skin.windows or 0)
end

-- surcharge : ce que coûte le suivi des cadres du journal (hook de CreateFrame), pour /pp donjons etat
function Skin:StatusCost()
    if not (Skin.active and Skin.external) then return nil end
    local s = Skin.Ext.stats
    return ns.Tf("suivi des cadres du journal : %d pris en main sur %d créés par le jeu, %d ms en tout (éteindre « Style Platyplus » puis /reload le retire)",
        s.taken, s.calls, math.floor(s.ms + 0.5))
end
