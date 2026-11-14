-- Platyplus : grandes cartes pour choisir la récompense d'une quête
--  * quand une quête rendue propose plusieurs objets au choix, ils s'affichent en grandes cartes au milieu de l'écran,
--    teintées à la qualité de l'objet ; la carte « Recommandée » n'est qu'un conseil (Quests:BestChoice) :
--    rien n'est choisi tant que tu n'as pas cliqué une carte
--  * clic : choisit la carte ; double-clic, « Prendre » ou la touche de Platyplus : rend la quête avec cette récompense
--  * la fenêtre de quête de Blizzard reste ouverte et reste la référence : on clique ses vrais boutons (choix de
--    l'objet, bouton Terminer), donc ses confirmations (quête qui coûte de l'or...) restent actives
--  * Maj tenu à l'ouverture, « Fenêtre classique » ou Échap : pas de cartes pour cette quête
-- Vérifié dans le code de Forever (QuestInfo.lua) : QuestInfo_ShowRewards remet QuestInfoFrame.itemChoice à 0
-- à chaque QUEST_ITEM_UPDATE ; on repose donc le choix après chaque mise à jour.
local ADDON, ns = ...

local Cards = {}
ns.QuestCards = Cards

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local CARD_W, CARD_H = 172, 268
local GAP = 14             -- entre deux cartes
local ROW_GAP = 26         -- entre deux rangées (la pastille « Recommandée » déborde au-dessus de la carte)
local PAD = 24             -- marge intérieure du panneau
local HEAD_H = 90          -- titre
local CENTER_Y = 64        -- au-dessus du centre : la barre de ressource sous le personnage reste visible
local FOOT_H = 60          -- aide et boutons
local ICON = 56
local MAX_STATS = 3
local PER_ROW = 5
local LIFT = 4             -- la carte survolée monte de quelques pixels

local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"     -- coche classique de Blizzard (NON VÉRIFIÉ sur Forever)
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local GLOW_BY_QUALITY = { [2] = 0.16, [3] = 0.28, [4] = 0.42, [5] = 0.55, [6] = 0.50, [7] = 0.42 }
local QUALITY_FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1.00, 1.00, 1.00 }, [2] = { 0.12, 1.00, 0.00 }, [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1.00, 0.50, 0.00 }, [6] = { 0.90, 0.80, 0.50 }, [7] = { 0.00, 0.80, 1.00 },
}
local WHITE = { 1, 1, 1, 1 }
local INK = { 0.16, 0.12, 0.02, 1 }        -- texte sur la pastille dorée
local STAT_TEXT = { 0.80, 0.82, 0.86, 1 }

local W, C                                 -- widgets et couleurs de l'interface, lus à la construction

local function mix(a, b, t, alpha)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, alpha or 1 }
end

local function qualityColor(q)
    q = tonumber(q) or 1
    local blizzard = rawget(_G, "ITEM_QUALITY_COLORS")
    local c = type(blizzard) == "table" and blizzard[q]
    if type(c) == "table" and c.r then return { c.r, c.g, c.b, 1 } end
    local f = QUALITY_FALLBACK[q] or QUALITY_FALLBACK[1]
    return { f[1], f[2], f[3], 1 }
end

-- couleur de texte lisible sur fond sombre : le bleu « rare » et le violet « épique » sont trop foncés tels quels
local function readable(c)
    local lum = 0.30 * c[1] + 0.59 * c[2] + 0.11 * c[3]
    if lum >= 0.55 then return c end
    return mix(c, WHITE, (0.55 - lum) * 1.4)
end

local function qualityName(q)
    local info = W and W.QUALITY and W.QUALITY[tonumber(q) or -1]
    return info and info.name or ""
end

---------------------------------------------------------------------------
-- Données d'une carte : ce que dit le jeu de chaque récompense au choix
---------------------------------------------------------------------------
local function itemInfo(link)
    if link and C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(link) end
end

local function itemLevel(link)
    if not (link and C_Item and C_Item.GetDetailedItemLevelInfo) then return nil end
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if type(level) == "number" and level > 0 then return level end
end

-- « Une main · Épées à une main · niv. 27 » (vide si l'objet n'est pas encore en cache)
local function subtitle(link)
    local name, _, _, _, _, itemType, itemSubType, _, equipLoc = itemInfo(link)
    if not name then return "" end
    local parts = {}
    local slot = type(equipLoc) == "string" and equipLoc ~= "" and rawget(_G, equipLoc)
    if type(slot) == "string" and slot ~= "" then
        parts[#parts + 1] = slot
        if type(itemSubType) == "string" and itemSubType ~= "" and itemSubType ~= slot then parts[#parts + 1] = itemSubType end
        local level = itemLevel(link)
        if level then parts[#parts + 1] = ns.Tf("niv. %d", floor(level)) end
    elseif type(itemType) == "string" and itemType ~= "" then
        parts[#parts + 1] = itemType
    end
    return table.concat(parts, " · ")
end

-- Caractéristiques de l'objet (« +9 Force »), les plus grosses d'abord ; API protégée (absente = rien)
local function itemStats(link)
    local fn = (C_Item and C_Item.GetItemStats) or rawget(_G, "GetItemStats")
    if not (link and type(fn) == "function") then return {} end
    local ok, stats = pcall(fn, link)
    if not ok or type(stats) ~= "table" then return {} end
    local list = {}
    for key, value in pairs(stats) do
        local label = type(key) == "string" and rawget(_G, key)
        if type(label) == "string" and label ~= "" and type(value) == "number" and value ~= 0 then
            list[#list + 1] = { key = key, label = label, value = value }
        end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.label < b.label
    end)
    local out = {}
    for i = 1, min(MAX_STATS, #list) do
        local s = list[i]
        local whole = s.value == floor(s.value)
        if not whole then
            out[i] = string.format("%.1f %s", s.value, s.label)
        elseif s.key:find("^ITEM_MOD_") then
            out[i] = string.format("%+d %s", s.value, s.label)
        else
            out[i] = string.format("%d %s", s.value, s.label)   -- armure, résistances : pas de « + »
        end
    end
    return out
end

-- Pastille de verdict sous les caractéristiques : { texte, couleur } ou nil
local function verdict(e, recommended, reason)
    if recommended and reason == "price" then return { ns.T("Se vend le plus cher"), C.gold } end
    if e.usable == false then return { ns.T("Inutilisable"), C.bad } end
    local d = e.delta
    if d and d >= 1000 then return { ns.T("Emplacement vide"), C.good } end
    if d and d >= 1 then return { ns.Tf("+%d niv. vs ton équipement", floor(d + 0.5)), C.good } end
    if d and d <= -1 then return { ns.Tf("%d niv. de moins", floor(-d + 0.5)), C.dim } end
    if d then return { ns.T("Comme ton équipement"), C.dim } end
    return nil
end

-- Récompenses de la quête affichée, et la recommandée (index, raison « upgrade » ou « price ») ;
-- pas de recommandation si rien n'améliore l'équipement et que tout vaut 0 à la vente
function Cards:Collect()
    local Q = ns.Quests
    local list = {}
    for _, c in ipairs(Q:ReadChoices()) do
        local e = {
            index = c.index, name = c.name, icon = c.icon, count = c.count or 1, quality = c.quality,
            usable = c.usable, link = c.link,
        }
        if not e.name or e.name == "" then
            -- monnaie au choix ou objet pas encore chargé : on reprend ce qu'affiche le bouton de Blizzard
            local b = Q.ChoiceButton and Q:ChoiceButton(c.index)
            if b and b.Name and b.Name.GetText then e.name = b.Name:GetText() end
            if b and b.Icon and b.Icon.GetTexture and not e.icon then e.icon = b.Icon:GetTexture() end
        end
        e.price = Q.SellPrice(c.link, c.count)
        if c.link and ns.Junk and ns.Junk.UpgradeDelta then
            local ok, d = pcall(ns.Junk.UpgradeDelta, ns.Junk, c.link)
            if ok then e.delta = d end
        end
        e.subtitle = subtitle(c.link)
        e.stats = itemStats(c.link)
        list[#list + 1] = e
    end
    local best, upgrade, price = Q:BestChoice()
    if best and ((upgrade or 0) >= 1 or (price or 0) > 0) then
        return list, best.index, (upgrade or 0) >= 1 and "upgrade" or "price"
    end
    return list, nil, nil
end

---------------------------------------------------------------------------
-- État
---------------------------------------------------------------------------
local panel
local cards = {}           -- cartes construites (réutilisées d'une quête à l'autre)
local state = {
    list = {}, rec = nil, reason = nil,
    demo = false,          -- aperçu (/pp cartes) : rien n'est envoyé au jeu
    demoChoice = nil,
    skip = false,          -- l'utilisateur a demandé la fenêtre classique pour cette quête
    choice = nil,          -- récompense cliquée par le joueur (Blizzard efface le choix à chaque mise à jour)
    selecting = false,
}

local function chosen()
    if state.demo then return state.demoChoice or 0 end
    return ns.Quests:Chosen()
end

local function entryOf(index)
    for _, e in ipairs(state.list) do if e.index == index then return e end end
end

local function selectInGame(index)
    state.selecting = true
    ns.Quests:Select(index)
    state.selecting = false
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------
local function anchorCard(card, lift)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", panel.grid, "TOPLEFT", card.x or 0, -(card.y or 0) + (lift or 0))
end

local function paintCard(card)
    local e = card.data
    if not e then return end
    local qc = card.qc
    local selected = chosen() == e.index
    local rec = state.rec == e.index
    card.bg:SetColor(mix(C.card, qc, (card.hover and 0.18 or 0.09) + (selected and 0.04 or 0), 1))
    if rec then
        card.stroke:SetColor(C.gold, 1)
    else
        card.stroke:SetColor(qc, ((tonumber(e.quality) or 1) <= 1 and 0.35 or 0.75) + (card.hover and 0.25 or 0))
    end
    card.ring:SetShown(selected)
    card.check:SetShown(selected)
    card.badge:SetShown(rec)
end

local function fillCard(card, e)
    card.data = e
    local q = tonumber(e.quality) or 1
    local qc = qualityColor(q)
    local tc = readable(qc)
    card.qc = qc

    W.TextColor(card.qualityText, tc)
    card.qualityText:SetText(qualityName(q))

    card.icon:SetTexture(e.icon or QUESTION)
    if e.usable == false then card.icon:SetVertexColor(0.9, 0.25, 0.25, 1) else card.icon:SetVertexColor(1, 1, 1, 1) end
    card.border:SetVertexColor(qc[1], qc[2], qc[3], 1)
    local glow = GLOW_BY_QUALITY[q] or 0
    card.glow:SetVertexColor(qc[1], qc[2], qc[3], 1)
    card.glow:SetAlpha(glow)
    card.glow:SetShown(glow > 0)
    card.count:SetText((e.count or 1) > 1 and ("x" .. e.count) or "")

    W.TextColor(card.name, tc)
    card.name:SetText(e.name or "?")
    card.sub:SetText(e.subtitle or "")
    for i = 1, MAX_STATS do
        card.stats[i]:SetText((e.stats and e.stats[i]) or "")
    end

    local v = verdict(e, state.rec == e.index, state.reason)
    if v then
        card.chip.text:SetText(v[1])
        W.TextColor(card.chip.text, v[2])
        card.chip.bg:SetColor(mix(C.card, v[2], 0.16, 1))
        card.chip:SetWidth(min(CARD_W - 16, ceil((card.chip.text:GetStringWidth() or 0) + 18)))
        card.chip:Show()
    else
        card.chip:Hide()
    end

    if (e.price or 0) > 0 then
        card.price:SetText(ns.Tf("Vente  %s", W.FormatMoney(e.price)))
    else
        card.price:SetText(ns.T("Ne se vend pas"))
    end
    paintCard(card)
end

local function showTooltip(card)
    local e = card.data
    if not e then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    local shown = false
    if not state.demo and GameTooltip.SetQuestItem then
        shown = pcall(GameTooltip.SetQuestItem, GameTooltip, "choice", e.index)
        local compare = rawget(_G, "GameTooltip_ShowCompareItem")
        if shown and IsShiftKeyDown() and type(compare) == "function" then pcall(compare, GameTooltip) end
    end
    if not shown then
        GameTooltip:SetText(e.name or "?", 1, 1, 1, 1, true)
        if e.subtitle and e.subtitle ~= "" then GameTooltip:AddLine(e.subtitle, C.dim[1], C.dim[2], C.dim[3], true) end
    end
    GameTooltip:Show()
end

local function liftTo(card, target)
    local from = card.lift or 0
    W.Animate(card, 0.12, function(f, p)
        f.lift = from + (target - from) * W.Ease(p)
        anchorCard(f, f.lift)
    end)
end

local function newCard()
    local card = CreateFrame("Button", nil, panel.grid)
    card:SetSize(CARD_W, CARD_H)
    card:RegisterForClicks("LeftButtonUp")
    card.lift = 0

    card.bg = W.Round(card, "BACKGROUND", 0, 10)
    card.stroke = W.Stroke(card, "BORDER", 0, 10)
    card.ring = W.Stroke(card, "BORDER", 1, 16)             -- anneau bleu de la carte choisie, un peu à l'extérieur
    card.ring:AnchorBox(card, -4, -4, -4, -4)
    card.ring:SetColor(C.accent, 1)

    card.qualityText = W.Text(card, nil, C.dim, "OVERLAY", 11)
    card.qualityText:SetPoint("TOP", card, "TOP", 0, -14)

    local iconY = -(34 + ICON / 2)
    card.glow = W.NewTex(card, W.TEX.glow, "ARTWORK", -2)
    card.glow:SetBlendMode("ADD")
    card.glow:SetSize(ICON * 2.3, ICON * 2.3)
    card.glow:SetPoint("CENTER", card, "TOP", 0, iconY)
    card.border = card:CreateTexture(nil, "ARTWORK", nil, 1)
    card.border:SetColorTexture(1, 1, 1, 1)                 -- carré uni teinté à la qualité : liseré autour de l'icône
    card.border:SetSize(ICON + 4, ICON + 4)
    card.border:SetPoint("CENTER", card, "TOP", 0, iconY)
    card.icon = W.Icon(card, ICON, "ARTWORK")
    card.icon:SetDrawLayer("ARTWORK", 2)
    card.icon:SetPoint("CENTER", card, "TOP", 0, iconY)
    card.count = W.Text(card, nil, C.text, "OVERLAY", 13, "OUTLINE")
    card.count:SetPoint("BOTTOMRIGHT", card.icon, "BOTTOMRIGHT", -2, 2)

    card.name = W.Text(card, nil, C.text, "OVERLAY", 13)
    card.name:SetSize(CARD_W - 20, 34)                      -- deux lignes au plus, centrées : les cartes restent alignées
    card.name:SetJustifyH("CENTER")
    card.name:SetJustifyV("MIDDLE")
    card.name:SetWordWrap(true)
    if card.name.SetMaxLines then card.name:SetMaxLines(2) end
    card.name:SetPoint("TOP", card.icon, "BOTTOM", 0, -12)

    card.sub = W.Text(card, nil, C.dim, "OVERLAY", 11)
    card.sub:SetWidth(CARD_W - 16)
    card.sub:SetWordWrap(false)
    card.sub:SetJustifyH("CENTER")
    card.sub:SetPoint("TOP", card.name, "BOTTOM", 0, -4)

    card.stats = {}
    local prev = card.sub
    for i = 1, MAX_STATS do
        local s = W.Text(card, nil, STAT_TEXT, "OVERLAY", 12)
        s:SetWidth(CARD_W - 16)
        s:SetWordWrap(false)
        s:SetJustifyH("CENTER")
        s:SetPoint("TOP", prev, "BOTTOM", 0, i == 1 and -10 or -3)
        card.stats[i] = s
        prev = s
    end

    local chip = CreateFrame("Frame", nil, card)
    chip:SetSize(100, 20)
    chip:SetPoint("BOTTOM", card, "BOTTOM", 0, 38)
    chip.bg = W.Round(chip, "BACKGROUND", 1, 6)
    chip.text = W.Text(chip, nil, C.text, "OVERLAY", 11)
    chip.text:SetPoint("CENTER", chip, "CENTER", 0, 0)
    chip:EnableMouse(false)
    card.chip = chip

    card.price = W.Text(card, nil, C.dim, "OVERLAY", 11)
    card.price:SetPoint("BOTTOM", card, "BOTTOM", 0, 15)

    -- pastille « Recommandée » à cheval sur le haut de la carte
    local badge = CreateFrame("Frame", nil, card)
    badge:SetFrameLevel(card:GetFrameLevel() + 3)
    badge:SetPoint("CENTER", card, "TOP", 0, 0)
    badge:EnableMouse(false)
    badge.text = W.Text(badge, nil, INK, "OVERLAY", 11)
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge.text:SetText(ns.T("Recommandée"))
    badge:SetSize(ceil((badge.text:GetStringWidth() or 70) + 26), 20)
    badge.pill = W.Pill(badge, "BACKGROUND", 0, 20)
    badge.pill:SetColor(C.gold, 1)
    card.badge = badge

    -- coche de la carte choisie
    local check = CreateFrame("Frame", nil, card)
    check:SetSize(22, 22)
    check:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    check:SetFrameLevel(card:GetFrameLevel() + 2)
    check:EnableMouse(false)
    local dot = W.NewTex(check, W.TEX.circle, "BACKGROUND")
    dot:SetAllPoints(check)
    dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    local mark = check:CreateTexture(nil, "ARTWORK")
    mark:SetTexture(CHECK)
    mark:SetDesaturated(true)
    mark:SetVertexColor(C.ink[1], C.ink[2], C.ink[3], 1)
    mark:SetSize(18, 18)
    mark:SetPoint("CENTER", check, "CENTER", 0, 0)
    card.check = check

    card:SetScript("OnEnter", function(self)
        self.hover = true
        paintCard(self)
        liftTo(self, LIFT)
        showTooltip(self)
    end)
    card:SetScript("OnLeave", function(self)
        self.hover = false
        paintCard(self)
        liftTo(self, 0)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    card:SetScript("OnClick", function(self)
        if self.data then Cards:Choose(self.data.index) end
    end)
    card:SetScript("OnDoubleClick", function(self)
        if self.data then
            Cards:Choose(self.data.index)
            Cards:Take()
        end
    end)
    card:SetScript("OnHide", function(self)
        self.hover = false
        W.StopAnimation(self)
        self.lift = 0
    end)
    return card
end

-- coupe un texte UTF-8 à n caractères (« ... » s'il est plus long)
local function shorten(text, n)
    local out, count = {}, 0
    for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > n then return (table.concat(out):gsub("%s+$", "")) .. "..." end
        out[count] = ch
    end
    return table.concat(out)
end

local function hintText()
    local db = ns.db
    local take = W.Color("text", ns.T("Double-clic"))
    if db.interact and db.dialog and type(db.key) == "string" and db.key ~= "" then
        take = ns.Tf("%s ou %s", take, W.Color("text", W.PrettyKey(db.key)))
    end
    return ns.Tf("%s : choisir   ·   %s : prendre", W.Color("text", ns.T("Clic")), take)
end

local function refreshFooter()
    local e = entryOf(chosen())
    panel.take:SetLabel(e and ns.Tf("Prendre : %s", shorten(e.name or "?", 20)) or ns.T("Choisis une carte"))
    panel.take:Refresh()
    panel.hint:SetText(hintText())
end

local function build()
    if panel then return panel end
    W, C = ns.W, ns.W.C
    panel = CreateFrame("Frame", "PlatyplusQuestCards", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()

    panel.shadow = W.Shadow(panel, 28, 28, 6)
    panel.bg = W.Round(panel, "BACKGROUND", 0, 14)
    panel.bg:SetColor(C.bg)
    panel.stroke = W.Stroke(panel, "BORDER", 0, 14)
    panel.stroke:SetColor(WHITE, 0.07)

    panel.kicker = W.Text(panel, nil, C.gold, "OVERLAY", 12)
    panel.kicker:SetPoint("TOP", panel, "TOP", 0, -22)
    panel.title = W.Text(panel, nil, C.text, "OVERLAY", 20)
    panel.title:SetPoint("TOP", panel.kicker, "BOTTOM", 0, -10)
    panel.title:SetText(ns.T("Choisis ta récompense"))

    panel.close = W.CloseGlyphButton(panel, 22, function() Cards:Dismiss() end)
    panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -12)
    W.SetTip(panel.close, "Fenêtre classique", "Cache les cartes pour cette quête ; la fenêtre de Blizzard reste ouverte.")

    panel.grid = CreateFrame("Frame", nil, panel)

    panel.line = panel:CreateTexture(nil, "ARTWORK")
    panel.line:SetColorTexture(1, 1, 1, 0.06)
    panel.line:SetHeight(1)
    panel.line:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, FOOT_H)
    panel.line:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, FOOT_H)

    panel.take = W.Button(panel, {
        primary = true, text = "Choisis une carte", width = 190, height = 32,
        enabled = function() return chosen() > 0 end,
        onClick = function() Cards:Take() end,
    })
    panel.take:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 14)
    panel.classic = W.Button(panel, {
        text = "Fenêtre classique", height = 32,
        onClick = function() Cards:Dismiss() end,
    })
    panel.classic:SetPoint("RIGHT", panel.take, "LEFT", -8, 0)

    panel.hint = W.Text(panel, nil, C.dim, "OVERLAY", 11)
    panel.hint:SetJustifyH("LEFT")
    panel.hint:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, 30)
    panel.hint:SetPoint("RIGHT", panel.classic, "LEFT", -12, 0)
    panel.hint:SetWordWrap(true)

    panel:SetScript("OnShow", function()
        if ns.QuestWindow and ns.QuestWindow.SetCovered then ns.QuestWindow:SetCovered(true) end
    end)
    panel:SetScript("OnHide", function()
        if ns.QuestWindow and ns.QuestWindow.SetCovered then ns.QuestWindow:SetCovered(false) end
        if GameTooltip:IsOwned(panel) then GameTooltip:Hide() end
        Cards:Listen(false)
    end)
    local special = rawget(_G, "UISpecialFrames")
    if type(special) == "table" then table.insert(special, "PlatyplusQuestCards") end   -- Échap ferme
    return panel
end

-- Place n cartes : 5 par rangée au plus, rangées équilibrées et centrées
local function layout(n)
    local perRow = n <= PER_ROW and n or ceil(n / ceil(n / PER_ROW))
    local rows = ceil(n / perRow)
    local gridW = perRow * CARD_W + (perRow - 1) * GAP
    local gridH = rows * CARD_H + (rows - 1) * ROW_GAP
    local width = max(gridW + 2 * PAD, 700)
    panel:SetSize(width, HEAD_H + 6 + gridH + 22 + FOOT_H)
    panel.grid:SetSize(gridW, gridH)
    panel.grid:ClearAllPoints()
    panel.grid:SetPoint("TOP", panel, "TOP", 0, -(HEAD_H + 6))
    for i = 1, n do
        local row, col = floor((i - 1) / perRow), (i - 1) % perRow
        local inRow = min(perRow, n - row * perRow)
        local offset = (gridW - (inRow * CARD_W + (inRow - 1) * GAP)) / 2
        local card = cards[i]
        card.x = floor(offset + col * (CARD_W + GAP))
        card.y = row * (CARD_H + ROW_GAP)
        card.lift = 0
        anchorCard(card, 0)
    end
end

local function questTitle()
    if state.demo then return "La marée noire" end
    local fn = rawget(_G, "GetTitleText")
    if type(fn) == "function" then
        local ok, t = pcall(fn)
        if ok and type(t) == "string" and t ~= "" then return t end
    end
    return nil
end

function Cards:Render()
    build()
    local list = state.list
    local n = #list
    for i = 1, n do
        cards[i] = cards[i] or newCard()
        fillCard(cards[i], list[i])
        cards[i]:Show()
    end
    for i = n + 1, #cards do cards[i]:Hide() end
    layout(n)
    local title = questTitle()
    panel.kicker:SetText(title and ns.Tf("Quête terminée  ·  %s", title) or ns.T("Quête terminée"))
    refreshFooter()

    if not panel:IsShown() then
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, CENTER_Y)
        panel:Show()
        -- apparition : fondu et petite montée
        W.Animate(panel, 0.18, function(f, p)
            local e = W.Ease(p)
            f:SetAlpha(e)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 0, CENTER_Y - 12 + 12 * e)
        end)
        W.Sound("open")
    end
end

-- Redessine la sélection (après un clic dans la fenêtre Blizzard, par exemple)
function Cards:Repaint()
    if not (panel and panel:IsShown()) then return end
    for i = 1, #state.list do if cards[i] then paintCard(cards[i]) end end
    refreshFooter()
end

---------------------------------------------------------------------------
-- Quand les montrer
---------------------------------------------------------------------------
function Cards:ShouldShow()
    local db = ns.db
    if not (db and db.questCards) or state.skip then return false end
    if not (QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown()) then return false end
    if (GetNumQuestChoices() or 0) < 2 then return false end
    return true
end

function Cards:Update()
    if state.demo and panel and panel:IsShown() then return end
    if not self:ShouldShow() then
        if panel and panel:IsShown() and not state.demo then panel:Hide() end
        return
    end
    state.demo = false
    state.list, state.rec, state.reason = self:Collect()
    -- rien n'est choisi d'avance : la carte « Recommandée » n'est qu'un conseil
    if state.choice and ns.Quests:Chosen() ~= state.choice and entryOf(state.choice) then
        selectInGame(state.choice)      -- Blizzard a effacé le choix en rafraîchissant la fenêtre : on le repose
    end
    self:Render()
    self:Listen(true)
end

function Cards:Choose(index)
    if not entryOf(index) then return end
    if state.demo then
        state.demoChoice = index
    else
        state.choice = index
        selectInGame(index)
    end
    W.Sound("click")
    self:Repaint()
end

-- Rend la quête avec la récompense choisie (bouton Terminer de Blizzard : ses confirmations restent actives)
function Cards:Take()
    if chosen() == 0 then return false end
    if state.demo then
        local e = entryOf(chosen())
        self:Hide()
        ns:Print(ns.Tf("aperçu des cartes : tu aurais pris %s", tostring(e and e.name or "?")))
        return true
    end
    local button = QuestFrameCompleteQuestButton
    if button and button:IsShown() and button:IsEnabled() then
        button:Click()
        return true
    end
    return false
end

-- « Fenêtre classique » : plus de cartes pour cette quête, la fenêtre de Blizzard reste ouverte
function Cards:Dismiss()
    if not state.demo then state.skip = true end
    self:Hide()
end

function Cards:Hide()
    if panel then panel:Hide() end
    state.demo, state.demoChoice = false, nil
end

function Cards:IsShown()
    return panel ~= nil and panel:IsShown()
end

-- /pp cartes : aperçu avec des objets d'exemple, sans quête
local DEMO = {
    { index = 1, name = "Bottes du marcheur des marais", icon = "Interface\\Icons\\INV_Boots_05", quality = 2,
      subtitle = "Pieds · Cuir · niv. 24", stats = { "+6 Agilité", "+5 Endurance" }, price = 4800, delta = -3 },
    { index = 2, name = "Lame de la marée noire", icon = "Interface\\Icons\\INV_Sword_04", quality = 3,
      subtitle = "Une main · Épée · niv. 27", stats = { "+9 Force", "+7 Endurance" }, price = 11200, delta = 9 },
    { index = 3, name = "Bâton de l'aube grise", icon = "Interface\\Icons\\INV_Staff_08", quality = 3, usable = false,
      subtitle = "Deux mains · Bâton · niv. 27", stats = { "+11 Intelligence", "+6 Esprit" }, price = 14000 },
    { index = 4, name = "Anneau du tisse-orage", icon = "Interface\\Icons\\INV_Jewelry_Ring_03", quality = 4,
      subtitle = "Doigt · niv. 26", stats = { "+5 Force", "+4 Agilité" }, price = 20500, delta = 0 },
}

function Cards:Demo()
    build()
    state.demo = true
    state.list, state.rec, state.reason, state.demoChoice = DEMO, 2, "upgrade", nil
    panel:Hide()
    self:Render()
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
local pending = false

local function scheduleUpdate(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 0, function()
        pending = false
        Cards:Update()
    end)
end

-- Mises à jour des objets (cache, équipement) écoutées seulement pendant que les cartes sont affichées
local LIVE = { "QUEST_ITEM_UPDATE", "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED" }
function Cards:Listen(on)
    for _, event in ipairs(LIVE) do
        if on then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
end

events:SetScript("OnEvent", function(_, event)
    if event == "QUEST_COMPLETE" then
        -- nouvelle fenêtre de récompense : on repart de zéro ; Maj tenu = fenêtre classique
        state.skip = IsShiftKeyDown() and true or false
        state.choice = nil
        if state.demo then Cards:Hide() end
        scheduleUpdate(0)           -- l'image suivante : la fenêtre de Blizzard est remplie
    elseif event == "QUEST_FINISHED" then
        if not state.demo then Cards:Hide() end
        state.choice, state.skip = nil, false
    else
        scheduleUpdate(0.1)         -- regroupe les rafales (GET_ITEM_INFO_RECEIVED arrive par paquets)
    end
end)

function Cards:Init()
    events:RegisterEvent("QUEST_COMPLETE")
    events:RegisterEvent("QUEST_FINISHED")
    -- un clic du joueur directement dans la fenêtre de Blizzard : les cartes suivent
    if type(rawget(_G, "hooksecurefunc")) == "function" and type(rawget(_G, "QuestInfoItem_OnClick")) == "function" then
        hooksecurefunc("QuestInfoItem_OnClick", function()
            if state.selecting or state.demo then return end
            local current = ns.Quests:Chosen()
            if current > 0 then state.choice = current end
            Cards:Repaint()
        end)
    end
    ns:OnChange("questCards", function(_, on)
        if on then Cards:Update() elseif not state.demo then Cards:Hide() end
    end)
    for _, key in ipairs({ "key", "interact", "dialog" }) do
        ns:OnChange(key, function() Cards:Repaint() end)
    end
end
