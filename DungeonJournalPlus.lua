-- Platyplus : ce que Platyplus ajoute au journal des donjons (DungeonJournal, dossier DungeonJournal/).
--
-- * Liste des donjons (réglage dungeonList) : une colonne collée à gauche du journal, toujours là, avec tous les
--   donjons dans l'ordre des niveaux. Un clic ouvre un donjon, depuis n'importe quelle page : plus besoin de revenir à
--   l'accueil et de faire défiler les grandes cartes pour passer d'un donjon à l'autre. Chaque ligne montre la
--   tranche de niveau en couleur (vert : à ton niveau, or : bientôt, rouge : trop dur, gris : dépassé) et les
--   quêtes faites (comptées comme sur les cartes du journal : ta faction, ta classe, tes métiers ; ✓ quand tout
--   est fait). « Accueil » ramène aux cartes. Les donjons masqués avec « Masquer donjons » n'y sont pas non plus.
-- * Accueil (réglage dungeonFit) : sur chaque carte, la tranche de niveau prend la même couleur, une pastille
--   « À ton niveau » ou « Bientôt » s'ajoute, et la première fois qu'on ouvre l'accueil il défile jusqu'aux
--   donjons de ton niveau.
-- Journal intégré : il prévient par les points d'accroche de DungeonJournalGlue.lua (PpViewChanged, PpAfterHome) ;
-- ses pages s'ouvrent par les siennes (PpSelectDungeon, PpShowHome), ajoutées par dev/make_dungeonjournal.py.
-- Addon DungeonJournal d'Exehn installé à part (pas de journal intégré actif) : la même colonne et le même accueil
-- sont posés SUR sa fenêtre, de l'extérieur (« surcharge », en bas du fichier) : aucun de ses fichiers n'est
-- embarqué, aucune de ses fonctions n'est remplacée, Platyplus passe derrière lui par hooksecurefunc / HookScript.
local ADDON, ns = ...

local Plus = {}
ns.DungeonPlus = Plus

local SIDE_W = 240          -- largeur de la colonne
local ROW_H = 24
local PAD = 12
local LIST_TOP = 92         -- haut de la liste (sous l'en-tête et « Accueil »)
Plus.SIDE_W = SIDE_W
local floor, min, max = math.floor, math.min, math.max

local D                     -- le journal : ns.Dungeon (intégré) ou l'espace de noms de l'addon séparé (surcharge)
local external = false      -- D est l'addon d'Exehn installé à part
local EXT_NS, EXT_FRAME, EXT_DB = "ForeverDungeonJournal_NS", "ForeverDungeonJournalFrame", "ForeverDungeonJournalDB"
local side, rows, homeRow, scroll, content, thumb = nil, {}, nil, nil, nil, nil
local pending = false
local scrolledHome = false

---------------------------------------------------------------------------
-- Niveaux et quêtes
---------------------------------------------------------------------------
local function playerLevel()
    local ok, lvl = pcall(UnitLevel, "player")
    if not ok or type(lvl) ~= "number" then return nil end
    local secret = rawget(_G, "issecretvalue")
    if secret and secret(lvl) then return nil end
    return lvl
end

-- « 17-26 » -> 17, 26 ; « 15 » -> 15, 20 ; « 55+ » -> 55, 60
function Plus.Levels(level)
    local s = tostring(level or "")
    local a, b = s:match("(%d+)%D+(%d+)")
    if a then return tonumber(a), tonumber(b) end
    a = s:match("(%d+)")
    if a then a = tonumber(a) return a, a + 5 end
    return nil
end

-- good : à ton niveau ; soon : 1 à 3 niveaux trop tôt ; hard : plus tôt encore ; past : dépassé
function Plus.Fit(lvl, lo, hi)
    if not (lvl and lo and hi) then return nil end
    if lvl > hi then return "past" end
    if lvl >= lo then return "good" end
    if lvl >= lo - 3 then return "soon" end
    return "hard"
end

local FIT_TEXT = { good = "À ton niveau", soon = "Bientôt", hard = "Trop dur pour l'instant", past = "Dépassé" }
Plus.FIT_TEXT = FIT_TEXT

local function fitColor(fit)
    local T = ns.THEME
    if fit == "good" then return T.good end
    if fit == "soon" then return T.gold end
    if fit == "hard" then return T.bad end
    return T.dim
end
Plus.FitColor = fitColor

local function faction()
    local ok, f = pcall(UnitFactionGroup, "player")
    if ok and f == "Horde" then return "Horde" end
    return "Alliance"
end

-- quêtes du donjon pour toi, comptées comme sur les cartes de l'accueil du journal
function Plus.Progress(dungeon)
    local done, total = 0, 0
    if type(dungeon) ~= "table" or not D then return 0, 0 end
    local fac = faction()
    local matches = D.PpQuestMatchesFaction or D.QuestMatchesFaction   -- (la 2e : exposée par l'addon depuis la 2.0)
    for _, q in ipairs(dungeon.quests or {}) do
        local ok, mine = true, true
        if matches then ok, mine = pcall(matches, q, fac) end
        if ok and mine and not q.hideFromMainList and not q.repeatable then
            total = total + 1
            if q.id and D.IsQuestFinished then
                local ok2, fin = pcall(D.IsQuestFinished, q.id)
                if ok2 and fin then done = done + 1 end
            end
        end
    end
    return done, total
end

local function dungeonName(name)
    if D and D.LocalizeDungeonName then
        local ok, n = pcall(D.LocalizeDungeonName, name)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return name
end

local function utf8len(s)
    local n = 0
    for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n
end

-- nom court pour la liste : une aile de donjon garde ce qui la distingue (« Monastère écarlate : Cathédrale » ->
-- « Monastère : Cathédrale ») ; le nom entier est dans l'infobulle
function Plus.ShortName(full)
    if utf8len(full) <= 22 then return full end
    local prefix, wing = full:match("^(.-)%s*:%s*(.+)$")
    if prefix and wing then
        local first = prefix:match("^(%S+)") or prefix
        return first .. " : " .. wing
    end
    return full
end

local function call(name, ...)
    local fn = D and D[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and v or nil
end

-- les donjons de l'accueil du journal, dans le même ordre et avec les mêmes masqués
local function shownDungeons()
    local out = {}
    if not (D and type(D.ORDER) == "table" and type(D.DB) == "table") then return out end
    local hidden = call("HiddenDungeons") or {}
    for _, name in ipairs(D.ORDER) do
        local dungeon = D.DB[name]
        if dungeon then
            local locked = call("IsDungeonLocked", name)
            if call("HomeFilterHides", name) then
                -- (filtre « Forever » du journal : seulement les nouveaux donjons)
            elseif locked or not (hidden[name] or call("IsDungeonAutoHidden", name)) then
                out[#out + 1] = name
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Colonne de gauche
---------------------------------------------------------------------------
local function journal() return rawget(_G, external and EXT_FRAME or "PlatyplusDungeonFrame") end

-- Ouvrir l'accueil ou un donjon. Journal intégré : ses pages (PpShowHome, PpSelectDungeon). Addon séparé : ce
-- qu'il expose lui-même — son bouton « Donjons » (retour à l'accueil) et FDJ.OpenBossPage / OpenQuestPage, en
-- gardant l'onglet où l'on est (ForeverDungeonJournalDB.lastMode).
local function showHome()
    if not external then return call("PpShowHome") end
    local f = journal()
    local back = f and f.backButton
    if not (back and f.currentView ~= "home") then return end
    if type(back.Click) == "function" then pcall(back.Click, back) end
    if f.currentView ~= "home" then
        -- (clic sans effet, bouton caché ou désactivé : son script directement)
        local click = back.GetScript and back:GetScript("OnClick")
        if type(click) == "function" then pcall(click, back, "LeftButton") end
    end
end

local function selectDungeon(name)
    if not external then return call("PpSelectDungeon", name) end
    local d = D.DB[name]
    if not d then return end
    if call("IsDungeonLocked", name) then
        call("RPGLockedNotice", name)   -- (mode RPG : le journal dit pourquoi, comme sur ses cartes)
        return
    end
    if d.previewOnly and not (type(D.DUNGEON_MAPS) == "table" and D.DUNGEON_MAPS[name]) then return end
    local db = rawget(_G, EXT_DB)
    if type(db) == "table" and db.lastMode == "quests" and type(D.OpenQuestPage) == "function" then
        call("OpenQuestPage", name)
    else
        call("OpenBossPage", name)
    end
end

local function paintRow(row)
    local C = ns.W.C
    local selected, hover = row.selected, row.hover
    row.sel:SetShown(selected)
    row.bar:SetShown(selected)
    row.hl:SetShown(hover and not selected)
    local c = row.dimmed and C.dim or C.text
    if selected then c = C.white end
    row.name:SetTextColor(c[1], c[2], c[3])
end

local function rowEnter(row)
    row.hover = true
    paintRow(row)
    if not row.dungeon then return end
    local d = D.DB[row.dungeon]
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(dungeonName(row.dungeon), 1, 1, 1)
    if d and d.level then
        local c = fitColor(row.fit)
        GameTooltip:AddLine(ns.Tf("Niveaux %s", tostring(d.level)) .. (row.fit and ("  ·  " .. ns.T(FIT_TEXT[row.fit])) or ""),
            c[1], c[2], c[3])
    end
    if row.total and row.total > 0 then
        local line = row.done == row.total and ns.Tf("Toutes tes quêtes sont faites (%d)", row.total)
            or ns.Tf("Quêtes faites : %d sur %d", row.done, row.total)
        GameTooltip:AddLine(line, 0.85, 0.85, 0.85)
    elseif d and not d.previewOnly then
        GameTooltip:AddLine(ns.T("Pas de quête pour toi dans ce donjon"), 0.6, 0.6, 0.6)
    end
    if row.locked then
        GameTooltip:AddLine(ns.T("Verrouillé (mode RPG) : bats le boss final du donjon précédent."), 1, 0.5, 0.4, true)
    elseif d and d.previewOnly then
        GameTooltip:AddLine(ns.T("Bientôt : boss, butin et quêtes pas encore connus."), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function rowLeave(row)
    row.hover = false
    paintRow(row)
    GameTooltip:Hide()
end

local function rowClick(row)
    if row.home then
        showHome()
    elseif row.dungeon then
        selectDungeon(row.dungeon)
    end
    Plus.ViewChanged()
end

local function newRow(parent, width)
    local W, C = ns.W, ns.W.C
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row.hl = W.Round(row, "BACKGROUND", 1, 6)
    row.hl:SetColor(C.white, 0.06)
    row.sel = W.Round(row, "BACKGROUND", 2, 6)
    row.sel:SetColor(C.accent, 0.20)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    row.bar:SetSize(2, ROW_H - 10)
    row.bar:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name = W.Text(row, "GameFontHighlightSmall", C.text, "OVERLAY", 12)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", rowLeave)
    row:SetScript("OnClick", rowClick)
    return row
end

local function dungeonRow(parent)
    local W, C = ns.W, ns.W.C
    local row = newRow(parent, SIDE_W - 2 * PAD - 8)
    row.chip = W.Pill(row, "ARTWORK", 1, 16)
    row.chipText = W.Text(row, "GameFontHighlightSmall", C.text, "OVERLAY", 10)
    row.chipText:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.chipText:SetWidth(40)
    row.chipText:SetJustifyH("CENTER")
    row.chip:Span(row, 6, -(row:GetWidth() - 50), 0)
    row.progress = W.Text(row, "GameFontHighlightSmall", C.dim, "OVERLAY", 10)
    row.progress:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.progress:SetJustifyH("RIGHT")
    row.tick = row:CreateTexture(nil, "OVERLAY")
    row.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    row.tick:SetSize(13, 13)
    row.tick:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.lock = row:CreateTexture(nil, "OVERLAY")
    row.lock:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
    row.lock:SetSize(12, 12)
    row.lock:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.name:SetPoint("LEFT", row, "LEFT", 54, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    return row
end

local function fillRow(row, name, lvl)
    local d = D.DB[name]
    row.dungeon = name
    row.name:SetText(Plus.ShortName(dungeonName(name)))
    local lo, hi = Plus.Levels(d and d.level)
    row.fit = Plus.Fit(lvl, lo, hi)
    local c = fitColor(row.fit)
    row.chipText:SetText(lo and (lo == hi and tostring(lo) or (tostring(d.level):gsub("%s", ""))) or "?")
    row.chipText:SetTextColor(c[1], c[2], c[3])
    row.chip:SetColor(c, row.fit == "good" and 0.22 or 0.12)
    row.locked = call("IsDungeonLocked", name) and true or false
    row.done, row.total = Plus.Progress(d)
    local allDone = row.total > 0 and row.done == row.total
    row.tick:SetShown(allDone and not row.locked)
    row.lock:SetShown(row.locked)
    row.progress:SetShown(not allDone and not row.locked and row.total > 0)
    row.progress:SetText(row.total > 0 and (row.done .. "/" .. row.total) or "")
    row.dimmed = row.locked or (d and d.previewOnly) or row.fit == "past"
end

-- hauteur visible de la liste (celle de la colonne moins l'en-tête, si le jeu ne l'a pas encore calculée)
local function viewHeight()
    local h = scroll:GetHeight()
    if not h or h <= 0 then
        local f = journal()
        h = ((f and f:GetHeight()) or 590) - LIST_TOP - 16
    end
    return h
end

-- défilement de la liste (molette), avec un fin repère à droite
local function setScroll(v)
    local h = viewHeight()
    local range = max(0, content:GetHeight() - h)
    v = max(0, min(range, v or 0))
    scroll:SetVerticalScroll(v)
    if range <= 0 or h <= 0 then thumb:Hide() return end
    local th = max(24, h * h / (h + range))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 6, -((h - th) * v / range))
    thumb:Show()
end

-- la ligne voulue dans la partie visible (sans bouger si elle y est déjà)
local function reveal(index, toTop)
    local top = (index - 1) * ROW_H
    local cur, h = scroll:GetVerticalScroll() or 0, viewHeight()
    if toTop then setScroll(top - ROW_H) return end
    if top < cur then setScroll(top)
    elseif top + ROW_H > cur + h then setScroll(top + ROW_H - h) end
end

local function extendChrome(f)
    -- style Platyplus : le cadre de la fenêtre englobe la colonne (une seule fenêtre)
    if f.ppBg then f.ppBg:AnchorBox(f, -SIDE_W, 0, 0, 0) end
    if f.ppStroke then f.ppStroke:AnchorBox(f, -SIDE_W, 0, 0, 0) end
    if f.ppShadow then f.ppShadow:AnchorBox(f, -14 - SIDE_W, -17, -14, -11) end
end

local function build(f)
    local W, C = ns.W, ns.W.C
    side = CreateFrame("Frame", "PlatyplusDungeonList", f)
    side.ppOwn = true   -- (à Platyplus : le style posé sur l'addon séparé n'y touche pas)
    side:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDE_W)
    side:EnableMouse(true)
    -- la fenêtre se déplace aussi par la colonne
    side:RegisterForDrag("LeftButton")
    side:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end)
    side:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    if f.ppBg then
        extendChrome(f)
    else
        -- journal sans le style Platyplus : la colonne a son propre fond
        W.Shadow(side, 12, 18, -3):SetColor(C.black, 0.5)
        W.Round(side, "BACKGROUND", -7, 10):SetColor(C.bg, 0.97)
        W.Stroke(side, "BORDER", -7, 10):SetColor(C.white, 0.09)
    end
    local sep = side:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.06)
    sep:SetWidth(1)
    sep:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, -12)
    sep:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 12)

    -- en-tête : titre et ton niveau
    local title = W.Text(side, "GameFontNormal", C.text, "OVERLAY", 14)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", PAD + 6, -19)
    title:SetText(ns.T("Donjons"))
    local lvlChip = CreateFrame("Frame", nil, side)
    lvlChip:SetSize(64, 18)
    lvlChip:SetPoint("TOPRIGHT", side, "TOPRIGHT", -PAD - 4, -18)
    lvlChip:EnableMouse(true)
    W.Pill(lvlChip, "ARTWORK", 0, 18):SetColor(C.accent, 0.16)
    side.level = W.Text(lvlChip, "GameFontHighlightSmall", C.accent, "OVERLAY", 11)
    side.level:SetPoint("CENTER", lvlChip, "CENTER", 0, 0)
    W.SetTip(lvlChip, "Ton niveau", "Les tranches de niveau sont colorées selon ton niveau :\n"
        .. W.Color("good", "vert") .. " à ton niveau, " .. W.Color("gold", "or") .. " bientôt (1 à 3 niveaux), "
        .. W.Color("bad", "rouge") .. " trop dur pour l'instant, " .. W.Color("dim", "gris") .. " dépassé.\n"
        .. "À droite : tes quêtes faites dans le donjon (✓ : toutes).")
    local line = side:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -44)
    line:SetPoint("TOPRIGHT", side, "TOPRIGHT", -PAD, -44)

    homeRow = newRow(side, SIDE_W - 2 * PAD)
    homeRow.home = true
    homeRow:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -54)
    homeRow.icon = homeRow:CreateTexture(nil, "OVERLAY")
    homeRow.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    homeRow.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    homeRow.icon:SetSize(16, 16)
    homeRow.icon:SetPoint("LEFT", homeRow, "LEFT", 10, 0)
    homeRow.name:SetPoint("LEFT", homeRow.icon, "RIGHT", 8, 0)
    homeRow.name:SetText(ns.T("Accueil : tous les donjons"))
    homeRow.name:SetPoint("RIGHT", homeRow, "RIGHT", -6, 0)

    local line2 = side:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.06)
    line2:SetHeight(1)
    line2:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -LIST_TOP + 8)
    line2:SetPoint("TOPRIGHT", side, "TOPRIGHT", -PAD, -LIST_TOP + 8)

    scroll = CreateFrame("ScrollFrame", nil, side)
    scroll:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -PAD - 8, 16)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        setScroll((self:GetVerticalScroll() or 0) - delta * ROW_H * 3)
    end)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(SIDE_W - 2 * PAD - 8, 10)
    scroll:SetScrollChild(content)
    thumb = side:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.20)
    thumb:SetWidth(3)
    thumb:Hide()

    -- la fenêtre reste entière à l'écran, colonne comprise ; placée au centre par défaut, elle se décale
    -- d'une demi-colonne pour que l'ensemble reste centré
    if f.SetClampRectInsets then f:SetClampRectInsets(-SIDE_W, 0, 0, 0) end
    local point, rel, relPoint, x, y = f:GetPoint(1)
    if point == "CENTER" and (rel == nil or rel == UIParent) and x == 0 then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, relPoint or "CENTER", SIDE_W / 2, y or 0)
    end
    -- (addon séparé : une erreur ici ne remonte pas au joueur)
    side:HookScript("OnShow", external and Plus.Quiet and Plus.Quiet(function() Plus.Refresh() end)
        or function() Plus.Refresh() end)
end

function Plus.Refresh()
    if not (D and side and side:IsShown()) then return end
    local f = journal()
    if not f then return end
    local lvl = playerLevel()
    side.level:SetText(lvl and ns.Tf("Niveau %d", lvl) or "")
    local names = shownDungeons()
    local selected, view = nil, f.currentView
    if D.GetSelectedDungeon then selected = D.GetSelectedDungeon() end
    local selIndex, firstGood
    for i, name in ipairs(names) do
        local row = rows[i]
        if not row then
            row = dungeonRow(content)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
            rows[i] = row
        end
        fillRow(row, name, lvl)
        row.selected = (view == "dungeon" and name == selected)
        if row.selected then selIndex = i end
        if not firstGood and row.fit == "good" then firstGood = i end
        paintRow(row)
        row:Show()
    end
    for i = #names + 1, #rows do rows[i]:Hide() end
    content:SetHeight(max(10, #names * ROW_H))
    homeRow.selected = (view ~= "dungeon")
    paintRow(homeRow)
    -- première ouverture : les donjons de ton niveau en haut ; ensuite le donjon ouvert reste visible
    if not side.placed then
        side.placed = true
        if selIndex and view == "dungeon" then reveal(selIndex, true)
        elseif firstGood then reveal(firstGood, true)
        else setScroll(0) end
    elseif selIndex then
        reveal(selIndex)
    else
        setScroll(scroll:GetVerticalScroll())
    end
end

-- le journal a changé de page : une seule mise à jour, à l'image suivante (il finit d'abord la sienne)
function Plus.ViewChanged()
    if pending then return end
    pending = true
    local function run()
        pending = false
        local f = journal()
        if not f then return end
        if ns.db.dungeonList ~= false and not side then
            -- (addon séparé : la colonne est à Platyplus, son style ne la prend pas pour un morceau du journal)
            local skin = ns.DungeonSkin
            if skin and skin.Own then skin.Own(build, f) else build(f) end
        end
        if side then
            side:SetShown(ns.db.dungeonList ~= false)
            Plus.Refresh()
        end
    end
    if external and Plus.Quiet then run = Plus.Quiet(run) end   -- (surcharge : jamais de message d'erreur)
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

---------------------------------------------------------------------------
-- Accueil : niveau conseillé sur les cartes
---------------------------------------------------------------------------
local function newBadge(card)
    local W, C = ns.W, ns.W.C
    local b = CreateFrame("Frame", nil, card)   -- (un cran au-dessus de la carte et de son image)
    b.ppOwn = true
    b:SetSize(90, 18)
    b.pill = W.Pill(b, "ARTWORK", 0, 18)
    b.text = W.Text(b, "GameFontHighlightSmall", C.text, "OVERLAY", 10)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    card.ppFit = b
    return b
end

local function cardBadge(card)
    if card.ppFit then return card.ppFit end
    local skin = ns.DungeonSkin
    if skin and skin.Own then return skin.Own(newBadge, card) end
    return newBadge(card)
end

function Plus.AfterHome(cards, shown)
    if not (D and type(cards) == "table") then return end
    local on = ns.db.dungeonFit ~= false
    local lvl = playerLevel()
    local firstGood
    for i, card in ipairs(cards) do
        local name = card.dungeonName
        local d = name and D.DB[name]
        if card:IsShown() and d then
            local lo, hi = Plus.Levels(d.level)
            local fit = on and Plus.Fit(lvl, lo, hi) or nil
            local badge = (fit == "good" or fit == "soon") and cardBadge(card) or card.ppFit
            if fit and card.meta then
                -- (notre couleur, posée telle quelle : sur l'addon séparé, le style ne la reconvertit pas)
                local c = fitColor(fit)
                local skin = ns.DungeonSkin
                if skin and skin.Direct then skin.Direct(card.meta, "SetTextColor", c[1], c[2], c[3])
                else card.meta:SetTextColor(c[1], c[2], c[3]) end
            elseif card.meta and D.PpC then
                card.meta:SetTextColor(D.PpC("text", 1.00, 0.95, 0.82))
            elseif card.meta and external then
                card.meta:SetTextColor(1.00, 0.95, 0.82)   -- la couleur du journal (le style, s'il est là, la convertit)
            end
            if badge then
                local show = (fit == "good" or fit == "soon") and not d.previewOnly
                    and not call("IsDungeonLocked", name)
                if show then
                    local c = fitColor(fit)
                    badge.text:SetText(ns.T(fit == "good" and "À ton niveau" or "Bientôt"))
                    badge.text:SetTextColor(c[1], c[2], c[3])
                    badge:SetWidth((badge.text:GetStringWidth() or 60) + 18)
                    badge.pill:SetColor(ns.W.C.black, 0.72)
                    badge:ClearAllPoints()
                    if card.meta then
                        badge:SetPoint("LEFT", card.meta, "LEFT", (card.meta:GetStringWidth() or 40) + 10, 0)
                    else
                        badge:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 70, 8)
                    end
                end
                badge:SetShown(show)
            end
            if fit == "good" and not firstGood then firstGood = i end
        end
    end
    -- première fois qu'on voit l'accueil : il défile jusqu'aux donjons de ton niveau (2 cartes par rangée)
    local f = journal()
    if on and firstGood and not scrolledHome and f and f:IsVisible() and f.currentView == "home" and f.homeScroll then
        scrolledHome = true
        local target = floor((firstGood - 1) / 2) * 138
        local function go()
            local range = f.homeScroll:GetVerticalScrollRange() or 0
            f.homeScroll:SetVerticalScroll(max(0, min(range, target)))
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, go) else go() end
    end
end

---------------------------------------------------------------------------
-- Ouvrir le journal depuis Platyplus (menu de l'icône, /pp donjons, onglet Donjons)
---------------------------------------------------------------------------
-- Trois états, sans dépendre de ns.Dungeon : journal intégré (dossier DungeonJournal/, absent de la version
-- publique), addon DungeonJournal d'Exehn installé à part (Platyplus le surcharge : Plus.Overlay()), ou aucun.
function Plus.Bundled()
    return ns.Dungeon ~= nil
end

-- le journal intégré est là ET actif (il se met en veille quand l'addon séparé tourne)
function Plus.BundledActive()
    local d = ns.Dungeon
    return d ~= nil and not d.PpStandby and type(rawget(_G, "PlatyplusDungeon_Toggle")) == "function"
end

-- l'addon séparé est chargé (globale d'ouverture, ou IsAddOnLoaded gardé par pcall)
function Plus.Standalone()
    if type(rawget(_G, "ForeverDungeonJournal_Toggle")) == "function" then return true end
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if type(loaded) ~= "function" then return false end
    local ok, v = pcall(loaded, "ForeverDungeonJournal")
    return ok and v and true or false
end

-- l'addon séparé est chargé ET Platyplus s'y est branché : la liste, « À ton niveau » et le style s'y appliquent
function Plus.Overlay()
    return external
end

-- les réglages dungeonList / dungeonFit / dungeonSkin ont un effet (journal intégré actif, ou surcharge)
function Plus.Tunable()
    return external or Plus.BundledActive()
end

-- un journal est ouvrable, d'une façon ou d'une autre
function Plus.Available()
    return Plus.BundledActive() or type(rawget(_G, "ForeverDungeonJournal_Toggle")) == "function"
end

function Plus.Toggle()
    local d = ns.Dungeon
    if not (d and not d.PpStandby) then
        -- pas de journal intégré actif : l'addon séparé, s'il est là
        local standalone = rawget(_G, "ForeverDungeonJournal_Toggle")
        if type(standalone) == "function" then
            standalone()
            if Plus.BuiltCheck then Plus.BuiltCheck() end   -- (fenêtre construite seulement maintenant ? on s'y branche)
            return
        end
    end
    local toggle = rawget(_G, "PlatyplusDungeon_Toggle")
    if type(toggle) == "function" then return toggle() end
    if ns.Dungeon then
        ns:Print("journal des donjons indisponible (le dossier DungeonJournal n'a pas pu se charger).")
    else
        ns:Print("le journal des donjons n'est pas inclus dans cette version : installe l'addon DungeonJournal d'Exehn (CurseForge), Platyplus l'ouvrira d'ici.")
    end
end

-- le journal sur un donjon précis (nom interne, ex. « The Deadmines »)
function Plus.Open(name)
    local f = journal()
    if not (f and D and D.DB and D.DB[name]) then return Plus.Toggle() end
    if not f:IsShown() then f:Show() end
    selectDungeon(name)
end

-- les réglages du journal lui-même (sa fenêtre d'options, comme /dj options)
function Plus.OpenOptions()
    local fn = D and (external or not D.PpStandby) and D.ToggleSettingsPanel
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn)
    if not ok then geterrorhandler()(err) end
    return ok
end

function Plus:Status()
    local lines = {}
    if external then
        -- surcharge : l'addon d'Exehn, avec les ajouts de Platyplus
        local version = Plus.StandaloneVersion()
        lines[1] = ns.Tf("journal des donjons : l'addon DungeonJournal d'Exehn (version %s), installé à part ; Platyplus y ajoute sa liste, « À ton niveau » et son style (/dj ou /pp donjons)", version)
        if not Plus.Verified(version) then
            lines[#lines + 1] = ns.Tf("version %s de l'addon : pas encore vérifiée avec Platyplus (vérifiées : %s)",
                version, table.concat(Plus.VERIFIED, ", "))
        end
        if not Plus.attached then
            lines[#lines + 1] = ns.T("fenêtre du journal pas encore trouvée : les ajouts de Platyplus attendent, le journal garde son look")
        else
            local missing = Plus.Health()
            if #missing > 0 then lines[#lines + 1] = Plus.HealthText(missing) end
        end
        if ns.DungeonSkin and ns.DungeonSkin.Status then lines[#lines + 1] = ns.DungeonSkin:Status() end
        local cost = ns.DungeonSkin and ns.DungeonSkin.StatusCost and ns.DungeonSkin:StatusCost()
        if cost then lines[#lines + 1] = cost end
        lines[#lines + 1] = ns.Tf("liste des donjons à gauche : %s ; « À ton niveau » sur l'accueil : %s",
            ns.T(ns.db.dungeonList ~= false and "allumée" or "éteinte"), ns.T(ns.db.dungeonFit ~= false and "allumé" or "éteint"))
        if ns.Dungeon and ns.Dungeon.PpStandby then
            lines[#lines + 1] = ns.T("le journal intégré à Platyplus est en veille tant que l'addon séparé est activé ; il garde une copie de ses réglages, favoris et progression.")
        end
        return lines
    end
    if not D then
        if Plus.Standalone() then
            return { ns.T("journal des donjons : celui de l'addon DungeonJournal d'Exehn, installé à part (/dj ou /pp donjons). Le journal intégré n'est pas inclus dans cette version de Platyplus.") }
        end
        return { ns.T("journal des donjons : non inclus dans cette version ; installe l'addon DungeonJournal d'Exehn (CurseForge), Platyplus l'ouvrira ensuite avec /pp donjons.") }
    end
    if D.PpStandby then
        return { ns.T("l'addon DungeonJournal séparé est actif : c'est lui qui tourne (/dj). Platyplus garde une copie de ses réglages, favoris et progression ; désactive-le dans la liste des addons pour passer à celui de Platyplus.") }
    end
    local n = (type(D.ORDER) == "table") and #D.ORDER or 0
    lines[1] = ns.Tf("journal des donjons : %d donjons, touche dans Raccourcis > Journal des donjons, /dj ou /pp donjons", n)
    if ns.DungeonSkin and ns.DungeonSkin.Status then lines[#lines + 1] = ns.DungeonSkin:Status() end
    lines[#lines + 1] = ns.Tf("liste des donjons à gauche : %s ; « À ton niveau » sur l'accueil : %s",
        ns.T(ns.db.dungeonList ~= false and "allumée" or "éteinte"), ns.T(ns.db.dungeonFit ~= false and "allumé" or "éteint"))
    return lines
end

---------------------------------------------------------------------------
-- Surcharge : l'addon DungeonJournal d'Exehn installé à part (ForeverDungeonJournal)
---------------------------------------------------------------------------
-- Ce qu'il expose : son espace de noms (_G.ForeverDungeonJournal_NS : données DB / ORDER, fonctions FDJ.*), sa
-- fenêtre (_G.ForeverDungeonJournalFrame, construite à PLAYER_LOGIN ; champs currentView, homePanel, contentPanel,
-- homeCardsContent, homeScroll, backButton, dungeonTitle) et ses réglages (ForeverDungeonJournalDB.lastMode).
-- Vérifié sur ses versions 1.6.6, 2.0.1 et 2.0.6. Tout est gardé : un champ ou une fonction qui manque dans une version
-- future, et la partie concernée ne se fait pas, sans message.

-- son espace de noms, s'il a bien ses données
function Plus.StandaloneNS()
    local X = rawget(_G, EXT_NS)
    if type(X) == "table" and type(X.DB) == "table" and type(X.ORDER) == "table" then return X end
    return nil
end

-- sa version (« ? » si le jeu ne la donne pas)
function Plus.StandaloneVersion()
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata
    if type(meta) == "function" then
        local ok, v = pcall(meta, "ForeverDungeonJournal", "Version")
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    return "?"
end

-- Ce dont la surcharge se sert chez lui : des noms internes de son addon, pas une interface prévue pour ça. Une
-- mise à jour peut en retirer ; la partie concernée ne se fait alors plus, sans erreur. Pour que ce ne soit pas
-- silencieux : Plus.Health() dit ce qui manque (/pp donjons etat, onglet Donjons, une ligne dans le chat à la
-- première ouverture du journal), et dev/test_surcharge_reel.lua le vérifie sur l'addon installé.
-- Versions de l'addon sur lesquelles la surcharge a été vérifiée (à compléter après chaque test_surcharge_reel).
Plus.VERIFIED = { "1.6.6", "2.0.1", "2.0.6" }
local CONTRACT_NS = { "HiddenDungeons", "IsDungeonLocked", "IsQuestFinished", "LocalizeDungeonName", "GetSelectedDungeon",
    "RefreshHomeCards", "UpdateRPGHeader", "OpenBossPage", "OpenQuestPage", "ToggleSettingsPanel" }
local CONTRACT_FRAME = { "homePanel", "contentPanel", "homeCardsContent", "homeScroll", "backButton", "closeButton",
    "dungeonTitle", "questContent", "selectedQuestMeta", "questObjectiveHeader" }

function Plus.Verified(version)
    for _, v in ipairs(Plus.VERIFIED) do
        if v == version then return true end
    end
    return false
end

-- noms que Platyplus ne trouve plus chez l'addon (vide : tout est là, ou pas de surcharge)
function Plus.Health()
    local missing = {}
    if not external then return missing end
    local f = journal()
    if type(f) ~= "table" then
        missing[1] = EXT_FRAME
        return missing
    end
    if type(D.THEMES) ~= "table" then missing[#missing + 1] = "FDJ.THEMES" end
    for _, name in ipairs(CONTRACT_NS) do
        if type(D[name]) ~= "function" then missing[#missing + 1] = "FDJ." .. name end
    end
    for _, key in ipairs(CONTRACT_FRAME) do
        if f[key] == nil then missing[#missing + 1] = key end
    end
    return missing
end

function Plus.HealthText(missing)
    return ns.Tf("surcharge incomplète : l'addon DungeonJournal a changé et Platyplus n'y trouve plus %s ; une partie de ses ajouts ne s'affiche pas",
        table.concat(missing, ", "))
end

-- une seule ligne dans le chat, à la première ouverture du journal de la session, si quelque chose manque
local noticed = false
local function notice()
    if noticed or not external then return end
    if Plus.attached and #Plus.Health() == 0 then return end
    noticed = true
    ns:Print(ns.T("le journal des donjons a changé : une partie des ajouts de Platyplus ne s'y affiche plus (détail : /pp donjons etat)."))
end

-- une erreur dans NOTRE code derrière le sien ne remonte pas au joueur (/pp debug pour la voir)
local function quiet(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns:Debug("journal des donjons (surcharge) : " .. tostring(err)) end
    end
end
Plus.Quiet = quiet

-- hooksecurefunc gardé sur une fonction de l'addon (tbl[name]) : faux si elle n'existe pas (ou plus)
function Plus.Hook(tbl, name, fn)
    local hook = rawget(_G, "hooksecurefunc")
    if type(hook) ~= "function" or type(tbl) ~= "table" or type(tbl[name]) ~= "function" then return false end
    return (pcall(hook, tbl, name, quiet(fn)))
end

function Plus.HookScript(frame, script, fn)
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
    return (pcall(frame.HookScript, frame, script, quiet(fn)))
end

-- fn(fenêtre) dès que la fenêtre de l'addon existe : il la construit à PLAYER_LOGIN (avant ou après nous, selon
-- l'ordre des cadres), on regarde donc à la connexion, à l'image suivante, puis à chaque ouverture
local builtWaiting, builtWatch = {}, nil
local function builtCheck()
    if #builtWaiting == 0 then return true end
    local f = rawget(_G, EXT_FRAME)
    if type(f) ~= "table" then return false end
    local list = builtWaiting
    builtWaiting = {}
    for _, fn in ipairs(list) do quiet(fn)(f) end
    return true
end
Plus.BuiltCheck = builtCheck

function Plus.WhenBuilt(fn)
    builtWaiting[#builtWaiting + 1] = fn
    if builtCheck() or builtWatch then return end
    builtWatch = CreateFrame("Frame")
    local function later(delay)
        if C_Timer and C_Timer.After then C_Timer.After(delay, builtCheck) end
    end
    for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do pcall(builtWatch.RegisterEvent, builtWatch, e) end
    builtWatch:SetScript("OnEvent", function(self)
        if builtCheck() then self:UnregisterAllEvents() return end
        later(0)
        later(2)
    end)
    -- (ouvert sans que sa fenêtre ait été trouvée : elle a changé de nom, on le dit une fois)
    Plus.Hook(_G, "ForeverDungeonJournal_Toggle", function()
        builtCheck()
        if not Plus.attached then notice() end
    end)
end

-- l'accueil vient d'être redessiné (FDJ.UpdateRPGHeader est son dernier geste) : ses cartes sont les enfants de
-- homeCardsContent, dans l'ordre de l'accueil
local function externalAfterHome()
    local f = journal()
    local content = f and f.homeCardsContent
    if not (content and content.GetChildren) or f.currentView ~= "home" then return end
    local cards = {}
    for _, card in ipairs({ content:GetChildren() }) do
        if type(card) == "table" and card.dungeonName then cards[#cards + 1] = card end
    end
    Plus.AfterHome(cards)
end

local function attachExternal(f)
    if Plus.attached then return end
    Plus.attached = true
    local changed = function() Plus.ViewChanged() end
    -- changement de page : sa fenêtre et ses deux pages se montrent ; changement de donjon : le titre du donjon
    -- est réécrit, et (2.0) les flèches « donjon précédent / suivant » sont mises à jour
    Plus.HookScript(f, "OnShow", changed)
    Plus.HookScript(f, "OnShow", notice)
    Plus.HookScript(f.homePanel, "OnShow", changed)
    Plus.HookScript(f.contentPanel, "OnShow", changed)
    Plus.Hook(f.dungeonTitle, "SetText", changed)
    Plus.Hook(D, "UpdateDungeonArrows", changed)
    Plus.Hook(D, "UpdateRPGHeader", externalAfterHome)
    if f.IsShown and f:IsShown() then
        Plus.ViewChanged()
        externalAfterHome()
    end
end

function Plus:Init()
    local own = ns.Dungeon
    if own and not own.PpStandby then
        -- journal intégré : il prévient par les points d'accroche de DungeonJournalGlue.lua
        D = own
        if type(D.DB) ~= "table" then return end
        D.PpPlus = { ViewChanged = Plus.ViewChanged, AfterHome = Plus.AfterHome }
    else
        -- pas de journal intégré actif : l'addon d'Exehn installé à part, s'il est chargé
        D = own
        local X = Plus.Standalone() and Plus.StandaloneNS() or nil
        if not X then return end
        D, external = X, true
        Plus.WhenBuilt(attachExternal)
    end
    ns:OnChange("dungeonList", function() Plus.ViewChanged() end)
    ns:OnChange("dungeonFit", function()
        scrolledHome = true
        if D.RefreshHomeCards then pcall(D.RefreshHomeCards) end
    end)
    -- quêtes rendues, niveau gagné : les lignes se remettent à jour si la liste est affichée. QUEST_LOG_UPDATE arrive
    -- par rafales : une seule mise à jour au plus toutes les 0,5 s (rien quand le journal est fermé : il refait
    -- tout à l'ouverture)
    local ev, waiting = CreateFrame("Frame"), false
    for _, e in ipairs({ "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function()
        if waiting or not (side and side:IsVisible()) then return end
        waiting = true
        C_Timer.After(0.5, function()
            waiting = false
            if side and side:IsVisible() then Plus.ViewChanged() end
        end)
    end)
end
