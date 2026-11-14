-- Platyplus : fenêtre de quête (ns.QuestWindow), à la place des fenêtres de dialogue des PNJ
--  * une fenêtre Platyplus pour tout ce qu'un PNJ te dit : discussion (options, quêtes proposées et en cours),
--    quête proposée, objets à rapporter, récompenses ; texte en grand, déplaçable par son bandeau, taille réglable
--  * récompenses en tuiles colorées selon la rareté (infobulle au survol, Maj-clic pour lier) ; « Conseillé »
--    sur l'objet que Platyplus te suggère (Quests:BestChoice) ; clic : choisir, double-clic : choisir et rendre
--  * Platyplus ne choisit jamais une récompense à ta place
--  * la touche de chaque choix est écrite devant lui : la touche d'interaction (F) sur ce que la touche ferait
--    (même règle que Dialog.lua : quête à rendre > quête à accepter > 1re option), 1, 2, 3... sur les autres lignes
--    et sur les récompenses au choix ; le bouton principal (Accepter, Continuer, Rendre) porte aussi la touche
--
-- Comment : les fenêtres du jeu (QuestFrame, GossipFrame) s'ouvrent comme d'habitude mais restent hors de l'écran
-- (ns.Win.Conceal) ; cette fenêtre lit les mêmes informations et ses boutons cliquent les vrais boutons du jeu.
-- La touche de Platyplus, les grandes cartes de récompense, l'acceptation automatique et les confirmations du jeu
-- (quête qui coûte de l'or...) marchent donc comme avant. Échap ferme le dialogue comme d'habitude.
-- Vérifié dans le code de Forever : QuestFrame.lua (panneaux Greeting / Detail / Progress / Reward, boutons
-- QuestFrameAcceptButton, QuestFrameDeclineButton, QuestFrameCompleteButton, QuestFrameGoodbyeButton,
-- QuestFrameCompleteQuestButton, QuestFrameGreetingGoodbyeButton), GossipFrameShared.lua (C_GossipInfo :
-- GetText, GetOptions triées par orderIndex, SelectOptionByIndex, Get/SelectAvailableQuests, Get/SelectActiveQuests),
-- QuestInfo.lua (GetQuestItemInfo("choice" / "reward" / "required", i), GetRewardMoney, GetRewardXP).
local ADDON, ns = ...

local QW = { mode = nil, choice = nil }
ns.QuestWindow = QW

local floor, max, min = math.floor, math.max, math.min

local function api(name) return rawget(_G, name) end
local function db(key) return ns.db and ns.db[key] end

local function try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns:Debug("fenêtre de quête (" .. where .. ") :", err) end
    return ok, err
end

-- appel protégé d'une fonction du jeu qui peut manquer : renvoie ses valeurs, ou rien
local function call(name, ...)
    local fn = type(name) == "function" and name or api(name)
    if type(fn) ~= "function" then return end
    local res = { n = 0 }
    local function pack(...) res.n = select("#", ...); for i = 1, res.n do res[i] = (select(i, ...)) end end
    pack(pcall(fn, ...))
    if not res[1] then return end
    return unpack(res, 2, res.n)
end

local function shown(name)
    local f = api(name)
    return f ~= nil and f:IsShown()
end

local WIDTH = 500
local PAD = 18
local CONTENT_W = WIDTH - 2 * PAD            -- la fine barre de défilement se dessine dans la marge (hors zone)
local BODY_MAX = 470                        -- au-delà, le texte défile
local FOOT_H = 60
local COLS = 2
local TILE_GAP = 10
local TILE_W = floor((CONTENT_W - TILE_GAP * (COLS - 1)) / COLS)
local TILE_H = 52
local ICON = 38
local ROW_ICON = 20
local KEY_W, KEY_H = 24, 20                 -- pastille de touche devant une ligne
local BOOK = "Interface\\QuestFrame\\UI-QuestLog-BookIcon"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local BODY = { 0.86, 0.87, 0.91, 1 }

local QUALITY_FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1.00, 1.00, 1.00 }, [2] = { 0.12, 1.00, 0.00 }, [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1.00, 0.50, 0.00 }, [6] = { 0.90, 0.80, 0.50 }, [7] = { 0.00, 0.80, 1.00 },
}

local function qualityColor(q)
    q = tonumber(q) or 1
    local blizzard = api("ITEM_QUALITY_COLORS")
    local c = type(blizzard) == "table" and blizzard[q]
    if type(c) == "table" and c.r then return { c.r, c.g, c.b, 1 } end
    local f = QUALITY_FALLBACK[q] or QUALITY_FALLBACK[1]
    return { f[1], f[2], f[3], 1 }
end

-- texte lisible sur fond sombre : le bleu « rare » et le violet « épique » sont trop foncés tels quels
local function readable(c)
    local lum = 0.30 * c[1] + 0.59 * c[2] + 0.11 * c[3]
    if lum >= 0.55 then return c end
    local t = (0.55 - lum) * 1.4
    return { c[1] + (1 - c[1]) * t, c[2] + (1 - c[2]) * t, c[3] + (1 - c[3]) * t, 1 }
end

local function number(n)
    local f = api("BreakUpLargeNumbers")
    if f then
        local ok, s = pcall(f, n)
        if ok and s then return s end
    end
    return tostring(n)
end

---------------------------------------------------------------------------
-- Quel dialogue est ouvert ?
---------------------------------------------------------------------------
function QW:CurrentMode()
    if shown("QuestFrame") then
        if shown("QuestFrameDetailPanel") then return "detail" end
        if shown("QuestFrameProgressPanel") then return "progress" end
        if shown("QuestFrameRewardPanel") then return "reward" end
        if shown("QuestFrameGreetingPanel") then return "greeting" end
        return nil
    end
    if shown("GossipFrame") then return "gossip" end
    return nil
end

---------------------------------------------------------------------------
-- Actions : on clique les vrais boutons du jeu
---------------------------------------------------------------------------
local function clickBlizzard(name)
    local b = api(name)
    if b and b:IsShown() and b:IsEnabled() then
        b:Click()
        return true
    end
    return false
end

local function blizzardEnabled(name)
    local b = api(name)
    return b ~= nil and b:IsShown() and b:IsEnabled() and true or false
end

local function blizzardText(name, fallback)
    local b = api(name)
    local t = b and b.GetText and b:GetText()
    if type(t) == "string" and t ~= "" then return t end
    return fallback
end

local function closeDialog()
    local hide = api("HideUIPanel")
    if shown("QuestFrame") then
        if hide then hide(QuestFrame) else call("CloseQuest") end
    elseif shown("GossipFrame") then
        if hide then hide(GossipFrame) else call(C_GossipInfo and C_GossipInfo.CloseGossip) end
    end
end
QW.Close = closeDialog

function QW:NeedsChoice()
    return self.mode == "reward" and (call("GetNumQuestChoices") or 0) > 1 and ns.Quests and ns.Quests:Chosen() == 0
end

function QW:Choose(index)
    if self.mode ~= "reward" or not (ns.Quests and index) then return end
    self.choice = index
    self.selecting = true
    ns.Quests:Select(index)
    self.selecting = false
    self:Repaint()
end

function QW:Complete()
    if self.mode == "reward" then
        if self:NeedsChoice() then return false end
        return clickBlizzard("QuestFrameCompleteQuestButton")
    end
    return false
end

---------------------------------------------------------------------------
-- Éléments réutilisés (textes, lignes de liste, tuiles d'objet)
---------------------------------------------------------------------------
local frame, scroll, child, thumb, portrait, primary, secondary
local pools = { text = {}, row = {}, tile = {} }
local used = { text = 0, row = 0, tile = 0 }
QW.pools, QW.used = pools, used          -- (lus par les tests)
local cursor = 0          -- hauteur déjà remplie dans la zone de texte

local function acquire(kind, make)
    used[kind] = used[kind] + 1
    local obj = pools[kind][used[kind]]
    if not obj then
        obj = make()
        pools[kind][used[kind]] = obj
    end
    obj:Show()
    return obj
end

local function releaseAll()
    for kind, list in pairs(pools) do
        for i = 1, #list do list[i]:Hide() end
        used[kind] = 0
    end
    cursor = 0
end

local function addText(text, size, color, gap)
    if type(text) ~= "string" or text == "" then return nil end
    local W = ns.W
    local fs = acquire("text", function() return child:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end)
    fs:SetFont(W.Font(), size, "")
    W.TextColor(fs, color)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(CONTENT_W)
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetSpacing then fs:SetSpacing(size >= 15 and 3 or 1) end
    fs:SetText(text)
    cursor = cursor + (gap or 0)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -cursor)
    cursor = cursor + W.Measure(fs, text, CONTENT_W)
    return fs
end

local function addTitle(text) return addText(text, 20, ns.W.C.gold, cursor > 0 and 14 or 0) end
local function addBody(text) return addText(text, 15, BODY, cursor > 0 and 10 or 0) end
-- (titres écrits en majuscules : la fonction upper de Lua ne connaît pas les lettres accentuées)
local function addHeader(text) return addText(ns.T(text), 12, ns.W.C.accent, cursor > 0 and 20 or 0) end
local function addSub(text) return addText(ns.T(text), 13, ns.W.C.dim, cursor > 0 and 8 or 0) end

-- Pastille de touche : « F » (dorée : ce que fait la touche d'interaction) ou « 1 », « 2 »... (grise)
local function makeKeyBadge(parent)
    local W, C = ns.W, ns.W.C
    local k = CreateFrame("Frame", nil, parent)
    k:SetSize(KEY_W, KEY_H)
    k.bg = W.Round(k, "BACKGROUND", 0, 5)
    k.text = W.Text(k, "GameFontHighlight", C.ink, "OVERLAY", 12, "")
    k.text:SetPoint("CENTER", k, "CENTER", 0, 0)
    k:Hide()
    return k
end

-- key : "F" (ou la touche choisie) = touche principale ; "1".."9" = numéro ; nil = pas de touche
local function paintKeyBadge(k, key, main)
    local W, C = ns.W, ns.W.C
    if not key then k:Hide() return end
    k.text:SetText(key)
    if main then
        k.bg:SetColor(C.gold, 1)
        W.TextColor(k.text, C.ink)
    else
        k.bg:SetColor(C.btnHover, 1)
        W.TextColor(k.text, C.text)
    end
    k:SetWidth(max(KEY_W, (k.text:GetStringWidth() or 0) + 10))
    k:Show()
end

-- ligne cliquable d'une liste (option de discussion, quête)
local function makeRow()
    local W, C = ns.W, ns.W.C
    local r = CreateFrame("Button", nil, child)
    r:SetWidth(CONTENT_W)
    r.bg = W.Round(r, "BACKGROUND", 0, 8)
    r.key = makeKeyBadge(r)
    r.key:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_ICON, ROW_ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", 10, 0)
    r.label = W.Text(r, "GameFontHighlight", C.text, "OVERLAY", 15)
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.slot = KEY_W
    r.label:SetWidth(CONTENT_W - ROW_ICON - 34)
    r.label:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self)
        self.bg:SetColor(C.btnHover, 1)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.bg:SetColor(C.card, 0.75)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    r:SetScript("OnClick", function(self)
        W.Sound("click")
        if self.action then try("choix", self.action) end
    end)
    return r
end

-- icon : fichier, ou function(texture) qui la peint ; dim : texte grisé (quête trop basse, option indisponible)
-- key / main : pastille de touche (voir paintKeyBadge)
local function addRow(text, icon, action, dim, tip, key, main)
    local W, C = ns.W, ns.W.C
    local r = acquire("row", makeRow)
    r.action, r.tip = action, tip
    r.bg:SetColor(C.card, 0.75)
    paintKeyBadge(r.key, key, main)
    r.icon:ClearAllPoints()
    -- sans touche (option grisée) : la place de la pastille reste réservée, pour aligner le texte
    local keyW = key and r.key:GetWidth() or KEY_W
    r.icon:SetPoint("LEFT", r, "LEFT", 8 + keyW + 8, 0)
    r:SetAlpha(dim and not key and 0.55 or 1)
    local labelW = CONTENT_W - ROW_ICON - 34 - (keyW + 6)
    r.label:SetWidth(labelW)
    r.icon:SetTexture(nil)
    r.icon:SetVertexColor(1, 1, 1, 1)
    if type(icon) == "function" then
        if not try("icône", icon, r.icon) then r.icon:SetTexture(QUESTION) end
    else
        r.icon:SetTexture(icon or QUESTION)
    end
    r.label:SetText(text or "?")
    W.TextColor(r.label, dim and key and C.dim or C.text)
    local h = max(34, W.Measure(r.label, text or "", labelW) + 14)
    r:SetHeight(h)
    cursor = cursor + (cursor > 0 and 6 or 0)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -cursor)
    cursor = cursor + h
    return r
end

-- Touches des choix d'un dialogue : la touche d'interaction sur celui que Dialog.lua prendrait, 1, 2, 3...
-- sur les autres (dans l'ordre d'affichage). entries[i] = { kind, action } ; renvoie keys[i] = touche ou nil
-- et l'indice du choix principal, et donne les actions numérotées à Dialog.
local function assignKeys(entries)
    local D = ns.Dialog
    local keys, numbered = {}, {}
    local label = D and D:KeyLabel() or nil
    local mainIndex = label and D:DefaultChoice(entries) or nil
    local n, limit = 0, (D and D.NUM_KEYS) or 9
    for i, e in ipairs(entries) do
        if i == mainIndex then
            keys[i] = label
        elseif label and e.action and e.kind ~= "locked" and n < limit then
            n = n + 1
            keys[i] = tostring(n)
            numbered[n] = e.action
        end
    end
    if D then D:SetChoices(numbered) end
    return keys, mainIndex
end

-- entries[i] = { header, text, icon, action, dim, tip, kind } : lignes d'un dialogue, avec leurs touches
local function addRows(entries)
    local keys, mainIndex = assignKeys(entries)
    for i, e in ipairs(entries) do
        if e.header then addHeader(e.header) end
        addRow(e.text, e.icon, e.action, e.dim, e.tip, keys[i], i == mainIndex)
    end
end

---------------------------------------------------------------------------
-- Tuiles de récompense
---------------------------------------------------------------------------
local function tileTooltip(t)
    local tip = api("GameTooltip")
    if not tip then return end
    tip:SetOwner(t, "ANCHOR_RIGHT")
    local ok = false
    if t.kind == "spell" and t.spellID and tip.SetSpellByID then
        ok = pcall(tip.SetSpellByID, tip, t.spellID)
    elseif t.kind and t.index and tip.SetQuestItem then
        ok = pcall(tip.SetQuestItem, tip, t.kind, t.index)
    end
    if not ok then tip:SetText(t.name:GetText() or "") end
    if t.kind == "choice" and QW.mode == "reward" then
        tip:AddLine(ns.T("Clic : choisir · double-clic : choisir et rendre la quête"), 0.2, 0.8, 1, true)
    end
    tip:Show()
end

local function makeTile()
    local W, C = ns.W, ns.W.C
    local t = CreateFrame("Button", nil, child)
    t:SetSize(TILE_W, TILE_H)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t.bg = W.Round(t, "BACKGROUND", 0, 9)
    t.stroke = W.Stroke(t, "BORDER", 0, 9)
    t.icon = W.Icon(t, ICON, "ARTWORK")
    t.icon:SetPoint("LEFT", t, "LEFT", 7, 0)
    t.ring = W.Stroke(t, "OVERLAY", 0, 4)
    t.ring:AnchorBox(t.icon, -1, -1, -1, -1)
    t.count = W.Text(t, "NumberFontNormal", C.white, "OVERLAY", 12, "OUTLINE")
    t.count:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", -1, 2)
    t.name = W.Text(t, "GameFontHighlight", C.text, "OVERLAY", 13)
    t.name:SetPoint("LEFT", t.icon, "RIGHT", 9, 0)
    t.name:SetWidth(TILE_W - ICON - 26)
    t.nameW = TILE_W - ICON - 26
    t.name:SetJustifyH("LEFT")
    if t.name.SetMaxLines then t.name:SetMaxLines(2) end
    t.tag = W.Text(t, "GameFontNormalSmall", C.gold, "OVERLAY", 10)
    t.tag:SetPoint("TOPRIGHT", t, "TOPRIGHT", -8, -4)
    t.tag:SetText(ns.T("CONSEILLÉ"))
    -- pastille de touche sur le coin de l'icône (dans la tuile : la zone de défilement rogne ce qui dépasse)
    t.key = makeKeyBadge(t)
    t.key:SetSize(20, 18)
    t.key:SetPoint("TOPLEFT", t.icon, "TOPLEFT", -3, 3)
    t:SetScript("OnEnter", function(self)
        self.hover = true
        QW.PaintTile(self)
        tileTooltip(self)
    end)
    t:SetScript("OnLeave", function(self)
        self.hover = false
        QW.PaintTile(self)
        local tip = api("GameTooltip")
        if tip and tip:IsOwned(self) then tip:Hide() end
    end)
    t:SetScript("OnClick", function(self)
        local modified = api("IsModifiedClick")
        if modified and modified() and self.link then
            local handle = api("HandleModifiedItemClick")
            if handle then try("lien", handle, self.link) end
            return
        end
        if self.kind == "choice" and QW.mode == "reward" then
            W.Sound("click")
            QW:Choose(self.index)
        end
    end)
    t:SetScript("OnDoubleClick", function(self)
        if self.kind == "choice" and QW.mode == "reward" then
            QW:Choose(self.index)
            QW:Complete()
        end
    end)
    return t
end

function QW.PaintTile(t)
    local C = ns.W.C
    local selected = t.kind == "choice" and QW.mode == "reward" and ns.Quests and ns.Quests:Chosen() == t.index
    if selected then
        t.bg:SetColor(C.accent2, 0.55)
        t.stroke:SetColor(C.accent, 1)
    else
        t.bg:SetColor(t.hover and C.btnHover or C.card, 0.95)
        t.stroke:SetColor(C.white, t.hover and 0.14 or 0.06)
    end
end

local tileCol = 0         -- colonne de la prochaine tuile (0 = nouvelle rangée)
local rowTop = 0

local function endTiles()
    if tileCol > 0 then
        cursor = rowTop + TILE_H
        tileCol = 0
    end
end

-- e = { kind, index, name, icon, count, quality, link, spellID, usable, recommended }
local function addTile(e)
    local W, C = ns.W, ns.W.C
    local t = acquire("tile", makeTile)
    if tileCol == 0 then
        rowTop = cursor + (cursor > 0 and 8 or 0)
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", child, "TOPLEFT", tileCol * (TILE_W + TILE_GAP), -rowTop)
    t.kind, t.index, t.link, t.spellID = e.kind, e.index, e.link, e.spellID
    t.icon:SetTexture(e.icon or QUESTION)
    if t.icon.SetDesaturated then t.icon:SetDesaturated(e.usable == false) end
    if e.usable == false then t.icon:SetVertexColor(1, 0.35, 0.35, 1) else t.icon:SetVertexColor(1, 1, 1, 1) end
    local qc = e.quality and qualityColor(e.quality) or C.text
    t.ring:SetColor(qc, (e.quality and e.quality >= 2) and 0.9 or 0.25)
    t.name:SetText(e.name or ns.T("Chargement…"))
    W.TextColor(t.name, readable(qc))
    local count = tonumber(e.count) or 1
    t.count:SetText(count > 1 and tostring(count) or "")
    t.tag:SetShown(e.recommended and true or false)
    -- bandeau « CONSEILLÉ » : le nom s'arrête avant lui
    t.name:SetWidth(e.recommended and (t.nameW - ((t.tag:GetStringWidth() or 54) + 8)) or t.nameW)
    paintKeyBadge(t.key, e.key, false)
    t.hover = false
    QW.PaintTile(t)
    tileCol = tileCol + 1
    if tileCol >= COLS then
        cursor = rowTop + TILE_H
        tileCol = 0
    else
        cursor = max(cursor, rowTop + TILE_H)
    end
    return t
end

---------------------------------------------------------------------------
-- Contenu de chaque dialogue
---------------------------------------------------------------------------
-- numbered : récompenses au choix numérotées (touches 1, 2, 3... : voir Dialog.lua)
local function questItems(kind, n, recommended, numbered)
    local D = ns.Dialog
    local keyed = numbered and D and D:KeyLabel() and true or false
    local actions = {}
    for i = 1, n do
        local name, texture, count, quality, isUsable = call("GetQuestItemInfo", kind, i)
        local key = keyed and i <= D.NUM_KEYS and tostring(i) or nil
        if key then actions[i] = function() QW:Choose(i) end end
        addTile({
            kind = kind, index = i, name = name, icon = texture, count = count, quality = quality, usable = isUsable,
            link = call("GetQuestItemLink", kind, i), recommended = recommended == i, key = key,
        })
    end
    if keyed then D:SetChoices(actions) end
    endTiles()
end

local function rewardSpells()
    local list = {}
    local Q = api("C_QuestInfoSystem")
    local questID = call("GetQuestID")
    if not (Q and Q.GetQuestRewardSpells and questID) then return list end
    local ids = call(Q.GetQuestRewardSpells, questID)
    if type(ids) ~= "table" then return list end
    for _, spellID in ipairs(ids) do
        local info = Q.GetQuestRewardSpellInfo and call(Q.GetQuestRewardSpellInfo, questID, spellID)
        if type(info) == "table" and not info.hideSpellLearnText then
            list[#list + 1] = { kind = "spell", spellID = spellID, name = info.name, icon = info.texture }
        end
    end
    return list
end

-- récompenses de la quête affichée ; reward = fenêtre de récompense (choix possible)
local function addRewards(reward)
    local choices = tonumber((call("GetNumQuestChoices"))) or 0
    local items = tonumber((call("GetNumQuestRewards"))) or 0
    local money = tonumber((call("GetRewardMoney"))) or 0
    local xp = tonumber((call("GetRewardXP"))) or 0
    local spells = rewardSpells()
    local title = call("GetRewardTitle")
    if choices + items + money + xp + #spells == 0 and not title then return end

    addHeader("RÉCOMPENSES")
    if choices > 0 then
        local rec
        if choices > 1 and ns.Quests and ns.Quests.BestChoice then
            local ok, best = pcall(ns.Quests.BestChoice, ns.Quests)
            rec = ok and type(best) == "table" and best.index or nil
        end
        local numbered = reward and choices > 1 and ns.Dialog and ns.Dialog:KeyLabel() and true or false
        if choices > 1 then
            addSub(reward and (numbered and "Choisis un objet (clic ou touche 1, 2, 3...), puis rends la quête :"
                                        or "Choisis un objet (clic), puis rends la quête :")
                          or "Tu pourras choisir un de ces objets :")
        else
            addSub("Tu recevras :")
        end
        questItems("choice", choices, rec, numbered)
    end
    if items > 0 or #spells > 0 then
        addSub(choices > 0 and "Tu recevras aussi :" or "Tu recevras :")
        questItems("reward", items)
        for _, s in ipairs(spells) do addTile(s) end
        endTiles()
    end
    local extras = {}
    if money > 0 then extras[#extras + 1] = ns.W.FormatMoney(money) end
    if xp > 0 then extras[#extras + 1] = ns.W.Color("accent", number(xp) .. " XP") end
    if type(title) == "string" and title ~= "" then extras[#extras + 1] = ns.Tf("Titre : %s", ns.W.Color("gold", title)) end
    if #extras > 0 then addText(table.concat(extras, "     "), 15, ns.W.C.text, 12) end
end

local function questIcon(available, info)
    -- l'icône du jeu (quête normale, journalière, répétable, terminée...) ; repli : point d'exclamation / d'interrogation
    return function(tex)
        local util = api("QuestUtil")
        local ok = false
        if type(util) == "table" and info and info.questID then
            if available and util.ApplyQuestIconOfferToTextureForQuestID then
                ok = pcall(util.ApplyQuestIconOfferToTextureForQuestID, tex, info.questID, info.isLegendary,
                    info.frequency, info.repeatable or info.isRepeatable, info.isImportant, info.isMeta, info.questInfoID)
            elseif not available and util.ApplyQuestIconActiveToTextureForQuestID then
                ok = pcall(util.ApplyQuestIconActiveToTextureForQuestID, tex, info.questID, info.isComplete,
                    info.isLegendary, info.frequency, info.repeatable or info.isRepeatable, info.isImportant, info.isMeta,
                    info.questInfoID)
            end
        end
        if not ok then
            if available then
                tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            elseif info and info.isComplete then
                tex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
            else
                tex:SetTexture("Interface\\GossipFrame\\IncompleteQuestIcon")
            end
        end
        if info and info.isTrivial then tex:SetVertexColor(0.6, 0.6, 0.6, 1) end
    end
end

local CONTENT = {}

function CONTENT.gossip()
    local G = api("C_GossipInfo")
    if type(G) ~= "table" then return end
    addBody(call(G.GetText))
    local available = call(G.GetAvailableQuests) or {}
    local active = call(G.GetActiveQuests) or {}
    local entries = {}
    for i, q in ipairs(available) do
        local id = q.questID
        entries[#entries + 1] = { header = i == 1 and "QUÊTES PROPOSÉES" or nil, text = q.title,
            icon = questIcon(true, q), action = function() G.SelectAvailableQuest(id) end, dim = q.isTrivial,
            kind = q.isIgnored and "active" or "available" }
    end
    for i, q in ipairs(active) do
        local id = q.questID
        local label = q.title
        if q.isComplete then label = (label or "?") .. "  " .. ns.W.Color("good", ns.T("· terminée")) end
        entries[#entries + 1] = { header = i == 1 and "QUÊTES EN COURS" or nil, text = label,
            icon = questIcon(false, q), action = function() G.SelectActiveQuest(id) end,
            dim = q.isTrivial and not q.isComplete, kind = q.isComplete and "complete" or "active" }
    end
    local options = call(G.GetOptions) or {}
    table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
    local AVAILABLE = (Enum and Enum.GossipOptionStatus and Enum.GossipOptionStatus.Available) or 0
    for i, o in ipairs(options) do
        local order = o.orderIndex
        local locked = o.status ~= nil and o.status ~= AVAILABLE
        entries[#entries + 1] = { header = (i == 1 and #available + #active > 0) and "DISCUSSION" or nil,
            text = o.name, icon = o.overrideIconID or o.icon, action = function() G.SelectOptionByIndex(order) end,
            dim = locked, tip = locked and o.failureDescription or nil, kind = locked and "locked" or "option" }
    end
    addRows(entries)
end

function CONTENT.greeting()
    addBody(call("GetGreetingText"))
    local numActive = tonumber((call("GetNumActiveQuests"))) or 0
    local numAvailable = tonumber((call("GetNumAvailableQuests"))) or 0
    local entries = {}
    for i = 1, numActive do
        local title, isComplete = call("GetActiveTitle", i)
        local info = { questID = call("GetActiveQuestID", i), isComplete = isComplete,
                       isTrivial = call("IsActiveQuestTrivial", i) }
        local label = title
        if isComplete then label = (label or "?") .. "  " .. ns.W.Color("good", ns.T("· terminée")) end
        entries[#entries + 1] = { header = i == 1 and "QUÊTES EN COURS" or nil, text = label,
            icon = questIcon(false, info), action = function() SelectActiveQuest(i) end,
            dim = info.isTrivial and not isComplete, kind = isComplete and "complete" or "active" }
    end
    for i = 1, numAvailable do
        local isTrivial, frequency, isRepeatable, isLegendary, questID, isImportant, isMeta, questInfoID =
            call("GetAvailableQuestInfo", i)
        local info = { questID = questID, isTrivial = isTrivial, frequency = frequency, isRepeatable = isRepeatable,
                       isLegendary = isLegendary, isImportant = isImportant, isMeta = isMeta, questInfoID = questInfoID }
        entries[#entries + 1] = { header = i == 1 and "QUÊTES PROPOSÉES" or nil, text = call("GetAvailableTitle", i),
            icon = questIcon(true, info), action = function() SelectAvailableQuest(i) end, dim = isTrivial,
            kind = "available" }
    end
    addRows(entries)
end

function CONTENT.detail()
    addTitle(call("GetTitleText"))
    addBody(call("GetQuestText"))
    local objectives = call("GetObjectiveText")
    if type(objectives) == "string" and objectives ~= "" then
        addHeader("OBJECTIFS")
        addBody(objectives)
    end
    addRewards(false)
end

function CONTENT.progress()
    addTitle(call("GetTitleText"))
    addBody(call("GetProgressText"))
    local n = tonumber((call("GetNumQuestItems"))) or 0
    local money = tonumber((call("GetQuestMoneyToGet"))) or 0
    if n > 0 or money > 0 then
        addHeader("À RAPPORTER")
        questItems("required", n)
        if money > 0 then addText(ns.Tf("Coût : %s", ns.W.FormatMoney(money)), 15, ns.W.C.text, 10) end
    end
    if not call("IsQuestCompletable") then
        addText(ns.T("Il te manque encore des objets ou des objectifs."), 13, ns.W.C.gold, 14)
    end
end

function CONTENT.reward()
    addTitle(call("GetTitleText"))
    addBody(call("GetRewardText"))
    addRewards(true)
end

---------------------------------------------------------------------------
-- Boutons du bas, selon le dialogue
---------------------------------------------------------------------------
local FOOTER = {
    gossip = {
        secondary = { "Au revoir", closeDialog },
    },
    greeting = {
        secondary = { "Au revoir", function() if not clickBlizzard("QuestFrameGreetingGoodbyeButton") then closeDialog() end end },
    },
    detail = {
        primary = { function() return blizzardText("QuestFrameAcceptButton", "Accepter") end,
                    function() clickBlizzard("QuestFrameAcceptButton") end,
                    function() return blizzardEnabled("QuestFrameAcceptButton") end },
        secondary = { function() return blizzardText("QuestFrameDeclineButton", "Refuser") end,
                      function() if not clickBlizzard("QuestFrameDeclineButton") then closeDialog() end end,
                      nil, function() return shown("QuestFrameDeclineButton") end },
    },
    progress = {
        primary = { "Continuer", function() clickBlizzard("QuestFrameCompleteButton") end,
                    function() return blizzardEnabled("QuestFrameCompleteButton") end },
        secondary = { "Au revoir", function() if not clickBlizzard("QuestFrameGoodbyeButton") then closeDialog() end end },
    },
    reward = {
        primary = { function() return QW:NeedsChoice() and "Choisis une récompense" or "Rendre la quête" end,
                    function() QW:Complete() end,
                    function() return not QW:NeedsChoice() and blizzardEnabled("QuestFrameCompleteQuestButton") end },
        secondary = { "Plus tard", closeDialog },
    },
}

local function value(v)
    if type(v) == "function" then return v() end
    return v
end

-- le bouton principal porte la touche d'interaction quand elle ferait la même chose (Dialog.lua)
local function keyedText(def, enabled)
    local text = value(def[1]) or ""
    local D = ns.Dialog
    local key = enabled and D and D:KeyLabel() or nil
    if key then return key .. "  ·  " .. text end
    return text
end

local function setupButton(b, def)
    if not def or (def[4] and not def[4]()) then
        b:Hide()
        b.def = nil
        return
    end
    b.def = def
    b:Show()
    b:Refresh()
end

function QW:PaintFooter()
    if not frame then return end
    local spec = FOOTER[self.mode or ""] or {}
    setupButton(primary, spec.primary)
    setupButton(secondary, spec.secondary)
    secondary:ClearAllPoints()
    if primary:IsShown() then
        secondary:SetPoint("RIGHT", primary, "LEFT", -10, 0)
    else
        secondary:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 14)
    end
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------
local function updateThumb()
    local viewH = scroll:GetHeight() or 0
    local contentH = child:GetHeight() or 0
    if contentH <= viewH + 1 or viewH <= 0 then
        thumb:Hide()
        return
    end
    thumb:Show()
    local h = max(24, viewH * viewH / contentH)
    local range = contentH - viewH
    local pos = (scroll:GetVerticalScroll() or 0) / range
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -(viewH - h) * pos)
end

local function setScroll(v)
    local range = max(0, (child:GetHeight() or 0) - (scroll:GetHeight() or 0))
    scroll:SetVerticalScroll(max(0, min(range, v)))
    updateThumb()
end

local function portraitUnit()
    if QW.mode == "gossip" then return "npc" end
    return "questnpc"
end

function QW:Render(keepScroll)
    if not frame then return end
    local previous = keepScroll and scroll:GetVerticalScroll() or 0
    releaseAll()
    tileCol = 0
    if ns.Dialog then ns.Dialog:SetChoices(nil) end
    local fill = CONTENT[self.mode or ""]
    if fill then try("contenu " .. tostring(self.mode), fill) end
    endTiles()
    local contentH = max(cursor, 10)
    child:SetHeight(contentH)
    local bodyH = min(contentH, BODY_MAX)
    scroll:SetHeight(bodyH)
    frame:SetHeight(ns.Win.HEAD_H + 16 + bodyH + FOOT_H)

    -- bandeau : nom du PNJ et son portrait
    local unit = portraitUnit()
    local name = call("UnitName", unit)
    if not name and unit == "questnpc" then name = call("UnitName", "npc") end
    frame.title:SetText(name or ns.T("Quête"))
    local exists = call("UnitExists", unit)
    if exists and api("SetPortraitTexture") then
        try("portrait", SetPortraitTexture, portrait, unit)
    else
        portrait:SetTexture(BOOK)
    end

    self:PaintFooter()
    setScroll(previous)
end

-- Après un choix de récompense : seulement la sélection et les boutons
function QW:Repaint()
    if not (frame and frame:IsShown()) then return end
    for i = 1, used.tile do QW.PaintTile(pools.tile[i]) end
    self:PaintFooter()
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local function build()
    local W, C, Win = ns.W, ns.W.C, ns.Win
    frame = Win.Create("PlatyplusQuestWindow", {
        width = WIDTH, height = 300, posKey = "questWinPos", scaleKey = "questWinScale",
        corner = "TOPLEFT", default = { "TOPLEFT", "TOPLEFT", 30, -110 },
        onClose = function()
            closeDialog()
            frame:Hide()
        end,
    })

    portrait = frame.head:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(30, 30)
    portrait:SetPoint("LEFT", frame.head, "LEFT", PAD - 2, 0)
    if portrait.AddMaskTexture and frame.head.CreateMaskTexture then
        local mask = frame.head:CreateMaskTexture()
        mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(portrait)
        portrait:AddMaskTexture(mask)
    end
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", portrait, "RIGHT", 10, 0)
    frame.title:SetPoint("RIGHT", frame.head, "RIGHT", -44, 0)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(Win.HEAD_H + 14))
    scroll:SetWidth(CONTENT_W)
    scroll:SetHeight(200)
    child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(CONTENT_W)
    child:SetHeight(10)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        setScroll((self:GetVerticalScroll() or 0) - delta * 48)
    end)

    thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.22)
    thumb:Hide()

    local function footerButton(isPrimary)
        local b
        b = W.Button(frame, {
            text = "", width = isPrimary and 200 or 130, height = 34, primary = isPrimary,
            enabled = function() return not (b and b.def and b.def[3]) or (b.def[3]() and true or false) end,
            getText = function()
                if not (b and b.def) then return "" end
                if isPrimary then return keyedText(b.def, b.isEnabled) end
                return value(b.def[1]) or ""
            end,
            onClick = function() if b.def and b.def[2] then try("bouton", b.def[2]) end end,
        })
        return b
    end
    primary = footerButton(true)
    primary:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 14)
    secondary = footerButton(false)

    frame:SetScript("OnHide", function()
        local tip = api("GameTooltip")
        if tip and tip:GetOwner() and tip:IsOwned(frame) then tip:Hide() end
        if ns.Dialog and not QW.covered then ns.Dialog:SetChoices(nil) end
    end)
    QW.frame, QW.primary, QW.secondary, QW.child = frame, primary, secondary, child
    return frame
end

---------------------------------------------------------------------------
-- Ouverture / fermeture : on suit les fenêtres du jeu
---------------------------------------------------------------------------
local pending, hideToken = false, 0
QW.broken = false

local function enabled()
    return db("questWindow") and not QW.broken
end

-- Cartes de récompense affichées par-dessus : on cache seulement NOTRE cadre, sans fermer l'interaction PNJ
function QW:SetCovered(on)
    on = on and true or false
    if self.covered == on then return end
    self.covered = on
    if on then
        if frame and frame:IsShown() then frame:Hide() end
    elseif enabled() and self:CurrentMode() then
        self:Sync()
    elseif ns.Dialog and ns.Dialog.SetChoices then
        ns.Dialog:SetChoices(nil)     -- échange fini pendant les cartes : notre OnHide n'a pas pu vider les choix
    end
end

function QW:Sync()
    if not enabled() then
        if frame then frame:Hide() end
        return
    end
    local mode = self:CurrentMode()
    if not mode then
        -- d'un dialogue à l'autre (discussion -> quête), le jeu ferme puis rouvre : on attend un peu avant de cacher
        hideToken = hideToken + 1
        local token = hideToken
        C_Timer.After(0.12, function()
            if token == hideToken and not QW:CurrentMode() and frame then
                frame:Hide()
                QW.mode = nil
            end
        end)
        return
    end
    hideToken = hideToken + 1
    if not frame then
        local ok = try("construction", build)
        if not ok then
            self.broken = true
            self:Apply()
            ns:Print("la fenêtre de quête n'a pas pu s'ouvrir : fenêtre du jeu gardée")
            return
        end
    end
    local questID = mode ~= "gossip" and mode ~= "greeting" and call("GetQuestID") or nil
    local changed = mode ~= self.mode or questID ~= self.questID
    self.mode, self.questID = mode, questID
    if mode == "reward" and self.choice and ns.Quests and ns.Quests:Chosen() ~= self.choice then
        -- le jeu efface le choix quand il rafraîchit la fenêtre : on le repose
        self.selecting = true
        ns.Quests:Select(self.choice)
        self.selecting = false
    end
    self:Render(not changed)
    if not self.covered then ns.Win.Open(frame) end
end

local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        QW:Sync()
    end)
end
QW.Schedule = schedule

-- Fenêtres du jeu cachées ou remises selon l'option
function QW:Apply()
    local on = enabled()
    for _, name in ipairs({ "QuestFrame", "GossipFrame" }) do
        local f = api(name)
        if f then
            if on then ns.Win.Conceal(f) else ns.Win.Reveal(f) end
        end
    end
    if on then schedule() elseif frame then frame:Hide() end
end

function QW:ApplyScale()
    if frame then ns.Win.Place(frame) end
end

function QW:ResetPosition()
    ns.db.questWinPos = {}
    if frame then ns.Win.Reset(frame) end
end

local events = CreateFrame("Frame")
local EVENTS = { "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
                 "QUEST_FINISHED", "QUEST_ITEM_UPDATE", "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED" }
events:SetScript("OnEvent", function(_, event)
    if event == "QUEST_COMPLETE" or event == "QUEST_FINISHED" or event == "QUEST_DETAIL" then QW.choice = nil end
    if (event == "QUEST_LOG_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" or event == "QUEST_ITEM_UPDATE")
        and not (frame and frame:IsShown()) then
        return
    end
    schedule()
end)

function QW:Init()
    for _, e in ipairs(EVENTS) do events:RegisterEvent(e) end
    for _, name in ipairs({ "QuestFrame", "GossipFrame", "QuestFrameGreetingPanel", "QuestFrameDetailPanel",
                            "QuestFrameProgressPanel", "QuestFrameRewardPanel" }) do
        local f = api(name)
        if f and f.HookScript then
            f:HookScript("OnShow", schedule)
            f:HookScript("OnHide", schedule)
        end
    end
    -- un choix fait ailleurs (grandes cartes, touche) : la sélection suit
    if api("hooksecurefunc") and type(api("QuestInfoItem_OnClick")) == "function" then
        hooksecurefunc("QuestInfoItem_OnClick", function()
            if QW.selecting then return end
            local current = ns.Quests and ns.Quests:Chosen() or 0
            if current > 0 then QW.choice = current end
            QW:Repaint()
        end)
    end
    ns:OnChange("questWindow", function() QW:Apply() end)
    ns:OnChange("questWinScale", function() QW:ApplyScale() end)
    try("application", function() QW:Apply() end)
end

function QW:Status()
    local lines = {}
    lines[1] = "fenêtre de quête : " .. (db("questWindow") and (self.broken and "en panne (fenêtre du jeu gardée)" or "active") or "coupée")
    lines[2] = "dialogue ouvert : " .. tostring(self:CurrentMode() or "aucun")
    return lines
end
