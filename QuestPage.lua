-- Platyplus : la page d'une quête dans le journal à côté de la carte (ns.QuestPage ; réglage mapQuestPage)
--
-- Blizzard empile tout dans l'ordre de son modèle (titre, histoire, objectifs, récompenses à part en bas).
-- Ici, dans l'ordre où on s'en sert :
--   1. ce qu'il faut faire : le but de la quête, puis chaque objectif avec sa progression (coche verte quand
--      il est rempli) ; quête terminée : « Objectifs remplis » et à qui la rendre ;
--   2. les récompenses : au choix, puis celles qu'on reçoit dans tous les cas (tuiles colorées selon la rareté,
--      infobulle au survol, Maj-clic pour lier), l'or, l'XP, les sorts ;
--   3. l'histoire, repliée (clic sur son titre pour la déplier ; ce choix est gardé).
-- Rien de Blizzard n'est remplacé : sa page (QuestMapFrame.DetailsFrame) s'ouvre comme d'habitude, avec ses boutons
-- (Retour, Abandonner, Partager, Suivre) ; sa zone de texte et son cadre de récompenses sont seulement cachés et cette
-- page se pose à leur place. Les informations viennent des mêmes fonctions que la page de Blizzard (quête choisie
-- par C_QuestLog.SetSelectedQuest dans QuestMapFrame_ShowQuestDetails, que l'on suit par hooksecurefunc).
-- Vérifié dans le code de Forever (Mainline\QuestMapFrame.lua / .xml, QuestInfo.lua).
local ADDON, ns = ...

local QP = {}
ns.QuestPage = QP

local floor, max = math.floor, math.max

local function api(name) return rawget(_G, name) end

-- appel protégé d'une fonction du jeu qui peut manquer : ses valeurs, ou rien
local function call(fn, ...)
    if type(fn) == "string" then fn = api(fn) end
    if type(fn) ~= "function" then return end
    local res = { pcall(fn, ...) }
    if not res[1] then return end
    return unpack(res, 2, table.maxn(res))
end

local PAD = 10
local TILE_H = 42
local ICON = 32
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"      -- (coche verte du jeu, présente partout)
local BODY = { 0.86, 0.87, 0.91, 1 }
local DONE = { 0.45, 0.85, 0.50, 1 }

local QUALITY_FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1.00, 1.00, 1.00 }, [2] = { 0.12, 1.00, 0.00 }, [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1.00, 0.50, 0.00 },
}
local function qualityColor(q)
    q = tonumber(q) or 1
    local blizzard = api("ITEM_QUALITY_COLORS")
    local c = type(blizzard) == "table" and blizzard[q]
    if type(c) == "table" and c.r then return { c.r, c.g, c.b, 1 } end
    local f = QUALITY_FALLBACK[q] or QUALITY_FALLBACK[1]
    return { f[1], f[2], f[3], 1 }
end
-- le bleu « rare » et le violet « épique » éclaircis pour se lire sur fond sombre
local function readable(c)
    local lum = 0.30 * c[1] + 0.59 * c[2] + 0.11 * c[3]
    if lum >= 0.55 then return c end
    local t = (0.55 - lum) * 1.4
    return { c[1] + (1 - c[1]) * t, c[2] + (1 - c[2]) * t, c[3] + (1 - c[3]) * t, 1 }
end

local function number(n)
    local s = call("BreakUpLargeNumbers", n)
    return s or tostring(n)
end

function QP.Enabled()
    return ns.db ~= nil and ns.db.mapQuestPage ~= false and ns.W ~= nil
end

---------------------------------------------------------------------------
-- Données de la quête (quête choisie dans le journal)
---------------------------------------------------------------------------
function QP.Read(questID)
    local Q = api("C_QuestLog") or {}
    local d = { id = questID, objectives = {}, choices = {}, rewards = {}, spells = {} }
    d.title = call(Q.GetTitleForQuestID, questID) or "?"
    local index = call(Q.GetLogIndexForQuestID, questID)
    local info = index and call(Q.GetInfo, index)
    if type(info) == "table" then
        d.level = info.level
        d.group = info.suggestedGroup
    end
    d.complete = call(Q.IsComplete, questID) and true or false
    d.story, d.goal = call("GetQuestLogQuestText", index)
    for _, o in ipairs(call(Q.GetQuestObjectives, questID) or {}) do
        if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
            d.objectives[#d.objectives + 1] = { text = o.text, done = o.finished and true or false }
        end
    end
    if d.complete then d.turnIn = index and call("GetQuestLogCompletionText", index) end
    -- récompenses (mêmes fonctions que QuestInfo.lua pour le journal)
    local nChoices = tonumber((call("GetNumQuestLogChoices", questID, true))) or 0
    for i = 1, nChoices do
        local name, icon, count, quality, usable = call("GetQuestLogChoiceInfo", i)
        d.choices[#d.choices + 1] = { kind = "choice", index = i, name = name, icon = icon, count = count,
            quality = quality, usable = usable, link = call("GetQuestLogItemLink", "choice", i, questID) }
    end
    local nRewards = tonumber((call("GetNumQuestLogRewards", questID))) or 0
    for i = 1, nRewards do
        local name, icon, count, quality, usable = call("GetQuestLogRewardInfo", i, questID)
        d.rewards[#d.rewards + 1] = { kind = "reward", index = i, name = name, icon = icon, count = count,
            quality = quality, usable = usable, link = call("GetQuestLogItemLink", "reward", i, questID) }
    end
    local sys = api("C_QuestInfoSystem")
    local ids = sys and call(sys.GetQuestRewardSpells, questID)
    for _, spellID in ipairs(type(ids) == "table" and ids or {}) do
        local s = call(sys.GetQuestRewardSpellInfo, questID, spellID)
        if type(s) == "table" and not s.hideSpellLearnText then
            d.spells[#d.spells + 1] = { kind = "spell", spellID = spellID, name = s.name, icon = s.texture }
        end
    end
    d.money = tonumber((call("GetQuestLogRewardMoney", questID))) or 0
    d.xp = tonumber((call("GetQuestLogRewardXP", questID))) or 0
    return d
end

---------------------------------------------------------------------------
-- Mise en page : une pile verticale dans une zone qui défile
---------------------------------------------------------------------------
local page, child, thumb
local pools = { text = {}, tile = {}, row = {} }
local used = { text = 0, tile = 0, row = 0 }
local cursor, width = 0, 280

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

local function addText(text, size, color, gap, indent)
    if type(text) ~= "string" or text == "" then return nil end
    local W = ns.W
    local fs = acquire("text", function() return child:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end)
    fs:SetFont(W.Font(), size, "")
    W.TextColor(fs, color)
    fs:SetJustifyH("LEFT")
    local w = width - (indent or 0)
    fs:SetWidth(w)
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetSpacing then fs:SetSpacing(size >= 13 and 2 or 1) end
    fs:SetText(text)
    cursor = cursor + (gap or 0)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", indent or 0, -cursor)
    cursor = cursor + W.Measure(fs, text, w)
    return fs
end

local function addHeader(text) return addText(ns.T(text), 11, ns.W.C.accent, cursor > 0 and 16 or 0) end

-- objectif : petite coche (verte, remplie) ou puce, et son texte
local function addObjective(text, done)
    local W, C = ns.W, ns.W.C
    local row = acquire("row", function()
        local r = CreateFrame("Frame", nil, child)
        r:SetSize(14, 14)
        r.dot = W.Round(r, "ARTWORK", 0, 4)
        r.dot:AnchorBox(r, 3, 3, 3, 3)
        r.check = r:CreateTexture(nil, "OVERLAY")
        r.check:SetTexture(CHECK)
        r.check:SetSize(14, 14)
        r.check:SetPoint("CENTER", r, "CENTER", 0, 0)
        return r
    end)
    local fs = addText(text, 13, done and DONE or C.text, 6, 20)
    if not fs then row:Hide() return end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", fs, "TOPLEFT", -19, 0)
    row.dot:SetColor(done and DONE or C.dim, done and 0.9 or 0.6)
    row.dot:SetShown(not done)
    row.check:SetShown(done)
end

local function tileTooltip(t)
    local tip = api("GameTooltip")
    if not tip then return end
    tip:SetOwner(t, "ANCHOR_RIGHT")
    local ok = false
    if t.kind == "spell" and t.spellID and tip.SetSpellByID then
        ok = pcall(tip.SetSpellByID, tip, t.spellID)
    elseif t.kind and t.index and tip.SetQuestLogItem then
        ok = pcall(tip.SetQuestLogItem, tip, t.kind, t.index, QP.questID)
    end
    if not ok then tip:SetText(t.name:GetText() or "") end
    tip:Show()
end

local function makeTile()
    local W, C = ns.W, ns.W.C
    local t = CreateFrame("Button", nil, child)
    t:SetHeight(TILE_H)
    t.bg = W.Round(t, "BACKGROUND", 0, 8)
    t.stroke = W.Stroke(t, "BORDER", 0, 8)
    t.icon = W.Icon(t, ICON, "ARTWORK")
    t.icon:SetPoint("LEFT", t, "LEFT", 5, 0)
    t.ring = W.Stroke(t, "OVERLAY", 0, 4)
    t.ring:AnchorBox(t.icon, -1, -1, -1, -1)
    t.count = W.Text(t, "NumberFontNormal", C.white, "OVERLAY", 11, "OUTLINE")
    t.count:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", -1, 2)
    t.name = W.Text(t, "GameFontHighlight", C.text, "OVERLAY", 13)
    t.name:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
    t.name:SetPoint("RIGHT", t, "RIGHT", -8, 0)
    t.name:SetJustifyH("LEFT")
    if t.name.SetMaxLines then t.name:SetMaxLines(2) end
    local function paint(self)
        self.bg:SetColor(self.hover and C.btnHover or C.card, 0.95)
        self.stroke:SetColor(C.white, self.hover and 0.14 or 0.06)
    end
    t.Paint = paint
    t:SetScript("OnEnter", function(self) self.hover = true paint(self) tileTooltip(self) end)
    t:SetScript("OnLeave", function(self)
        self.hover = false
        paint(self)
        local tip = api("GameTooltip")
        if tip and tip:IsOwned(self) then tip:Hide() end
    end)
    t:SetScript("OnClick", function(self)
        local modified = api("IsModifiedClick")
        if modified and modified() and self.link then call("HandleModifiedItemClick", self.link) end
    end)
    return t
end

local function addTile(e)
    local W, C = ns.W, ns.W.C
    local t = acquire("tile", makeTile)
    cursor = cursor + 6
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -cursor)
    t:SetWidth(width)
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
    t.hover = false
    t:Paint()
    cursor = cursor + TILE_H
    return t
end

-- titre de l'histoire : une ligne cliquable « Histoire de la quête » avec un chevron (replié / déplié)
local storyButton
local function addStoryToggle(open)
    local W, C = ns.W, ns.W.C
    if not storyButton then
        local b = CreateFrame("Button", nil, child)
        b:SetHeight(26)
        b.bg = W.Round(b, "BACKGROUND", 0, 6)
        b.label = W.Text(b, "GameFontHighlight", C.text, "OVERLAY", 12)
        b.label:SetPoint("LEFT", b, "LEFT", 10, 0)
        b.arrow = W.Text(b, "GameFontHighlight", C.dim, "OVERLAY", 13)
        b.arrow:SetPoint("RIGHT", b, "RIGHT", -10, 0)
        b:SetScript("OnEnter", function(self) self.bg:SetColor(C.btnHover, 1) end)
        b:SetScript("OnLeave", function(self) self.bg:SetColor(C.card, 0.9) end)
        b:SetScript("OnClick", function()
            ns.db.questPageStory = not ns.db.questPageStory
            if W.Sound then W.Sound("click") end
            QP:Render(true)
        end)
        storyButton = b
    end
    local b = storyButton
    cursor = cursor + 16
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -cursor)
    b:SetWidth(width)
    b.bg:SetColor(C.card, 0.9)
    b.label:SetText(ns.T("Histoire de la quête"))
    b.arrow:SetText(open and "–" or "+")
    b:Show()
    cursor = cursor + 26
end

local function updateThumb()
    if not (page and thumb) then return end
    local range = page:GetVerticalScrollRange() or 0
    local h = page:GetHeight() or 0
    if range <= 0 or h <= 0 then thumb:Hide() return end
    local total = h + range
    local th = max(24, h * h / total)
    local pos = (page:GetVerticalScroll() or 0) / range
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -pos * (h - th))
    thumb:Show()
end

local function setScroll(v)
    local range = page:GetVerticalScrollRange() or 0
    page:SetVerticalScroll(math.max(0, math.min(range, v)))
    updateThumb()
end

---------------------------------------------------------------------------
-- La page
---------------------------------------------------------------------------
function QP:Render(keepScroll)
    if not (page and self.questID) then return end
    local W, C = ns.W, ns.W.C
    width = floor((page:GetWidth() or 0) - 6)   -- (la languette de défilement occupe les 6 derniers pixels)
    if width < 120 then width = 270 end
    child:SetWidth(width)
    local scroll = keepScroll and page:GetVerticalScroll() or 0
    releaseAll()
    if storyButton then storyButton:Hide() end
    local d = QP.Read(self.questID)
    self.data = d

    -- titre, niveau
    addText(d.title, 16, C.gold, 0)
    local sub = {}
    if tonumber(d.level) and d.level > 0 then sub[#sub + 1] = ns.Tf("Niveau %d", d.level) end
    if tonumber(d.group) and d.group > 1 then sub[#sub + 1] = ns.Tf("Groupe (%d)", d.group) end
    if #sub > 0 then addText(table.concat(sub, " · "), 11, C.dim, 8) end

    -- 1. ce qu'il faut faire
    addHeader("À FAIRE")
    if d.complete then
        addText(ns.Tf("|T%s:14|t Objectifs remplis", CHECK), 13, DONE, 6)
        if type(d.turnIn) == "string" and d.turnIn ~= "" then addText(d.turnIn, 13, BODY, 4) end
    else
        if type(d.goal) == "string" and d.goal ~= "" then addText(d.goal, 13, BODY, 6) end
        for _, o in ipairs(d.objectives) do addObjective(o.text, o.done) end
    end

    -- 2. récompenses
    local hasRewards = #d.choices + #d.rewards + #d.spells > 0 or d.money > 0 or d.xp > 0
    if hasRewards then
        addHeader("RÉCOMPENSES")
        if #d.choices > 0 then
            addText((#d.choices > 1 and ns.T("Au choix, un de ces objets :") or ns.T("Tu recevras :")), 12, C.dim, 4)
            for _, e in ipairs(d.choices) do addTile(e) end
        end
        if #d.rewards + #d.spells > 0 then
            addText((#d.choices > 0 and ns.T("Et aussi :") or ns.T("Tu recevras :")), 12, C.dim, 8)
            for _, e in ipairs(d.rewards) do addTile(e) end
            for _, e in ipairs(d.spells) do addTile(e) end
        end
        local extras = {}
        if d.money > 0 and W.FormatMoney then extras[#extras + 1] = W.FormatMoney(d.money) end
        if d.xp > 0 then extras[#extras + 1] = W.Color("accent", number(d.xp) .. " XP") end
        if #extras > 0 then addText(table.concat(extras, "     "), 13, C.text, 8) end
    end

    -- 3. l'histoire, repliée
    if type(d.story) == "string" and d.story ~= "" then
        local open = ns.db.questPageStory and true or false
        addStoryToggle(open)
        if open then addText(d.story, 13, BODY, 8) end
    end

    cursor = cursor + 8
    child:SetHeight(max(1, cursor))
    if page.UpdateScrollChildRect then page:UpdateScrollChildRect() end
    setScroll(scroll)
end

-- les cadres de Blizzard que la page remplace : cachés tant qu'elle est là (Blizzard les remontre : on suit)
local hidden = {}
local function keepHidden(frame)
    if not frame or hidden[frame] then
        if frame and QP.active then frame:Hide() end
        return
    end
    hidden[frame] = true
    if hooksecurefunc then
        hooksecurefunc(frame, "Show", function(self) if QP.active then self:Hide() end end)
        hooksecurefunc(frame, "SetShown", function(self, v) if v and QP.active then self:Hide() end end)
    end
    if QP.active then frame:Hide() end
end

local function blizzardArt(df, alpha)
    if df.Bg then df.Bg:SetAlpha(alpha) end
    if df.SealMaterialBG then df.SealMaterialBG:SetAlpha(alpha) end
    if df.BackFrame then
        for _, r in ipairs({ df.BackFrame:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(alpha) end
        end
    end
end

-- pied de page : Abandonner / Partager / Suivre (boutons de Blizzard, non protégés) répartis dans la largeur du
-- contenu, PAD de chaque côté, PAD au-dessus du bas. Hors combat seulement ; rien de Blizzard n'est remplacé.
local FOOT_GAP, FOOT_H = 6, 21
local footerSaved     -- [bouton] = { w, h, points } : leur place d'origine, remise quand la page rend la main au jeu
local function layoutFooter(df)
    if not df or (InCombatLockdown and InCombatLockdown()) then return end
    pcall(function()
        local a, s, t = df.AbandonButton, df.ShareButton, df.TrackButton
        if not (a and s and t) then return end
        if not footerSaved then
            local saved = {}
            for _, b in ipairs({ a, s, t }) do
                local points = {}
                for i = 1, (b:GetNumPoints() or 0) do points[i] = { b:GetPoint(i) } end
                saved[b] = { w = b:GetWidth(), h = b:GetHeight(), points = points }
            end
            footerSaved = saved
        end
        local total = df:GetWidth() or 0
        if total < 120 then total = 300 end
        local bw = floor((total - 2 * PAD - 2 * FOOT_GAP) / 3)
        for _, b in ipairs({ a, s, t }) do
            b:ClearAllPoints()
            b:SetSize(bw, FOOT_H)
        end
        a:SetPoint("BOTTOMLEFT", df, "BOTTOMLEFT", PAD, PAD)
        s:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT", FOOT_GAP, 0)
        t:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", FOOT_GAP, 0)
    end)
end

-- remet les trois boutons là où le jeu les avait mis (page de Blizzard de nouveau visible)
local function restoreFooter()
    if not footerSaved or (InCombatLockdown and InCombatLockdown()) then return end
    pcall(function()
        for b, o in pairs(footerSaved) do
            b:ClearAllPoints()
            for _, p in ipairs(o.points) do b:SetPoint(unpack(p)) end
            if o.w and o.h and o.w > 0 then b:SetSize(o.w, o.h) end
        end
    end)
end

local function build(df)
    local W, C = ns.W, ns.W.C
    -- fond sombre de toute la page (textures de la page de Blizzard elle-même : sous ses boutons)
    QP.bg = W.Round(df, "BACKGROUND", -8, 8)
    QP.bg:AnchorBox(df, -3, -3, -3, -3)
    QP.bg:SetColor(C.panel, 0.98)
    page = CreateFrame("ScrollFrame", nil, df)
    page:SetPoint("TOPLEFT", df, "TOPLEFT", PAD, -45)   -- (sous le bandeau « Retour »)
    page:SetPoint("BOTTOMRIGHT", df, "BOTTOMRIGHT", -(PAD - 6), PAD + FOOT_H + 8)   -- (au-dessus d'Abandonner, Partager, Suivre)
    child = CreateFrame("Frame", nil, page)
    child:SetSize(270, 1)
    page:SetScrollChild(child)
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta) setScroll((page:GetVerticalScroll() or 0) - delta * 40) end)
    page:SetScript("OnSizeChanged", function() if QP.active then QP:Render(true) end end)
    thumb = CreateFrame("Frame", nil, page)
    thumb:SetWidth(3)
    W.Round(thumb, "OVERLAY", 0, 1):SetColor(C.white, 0.22)
    thumb:Hide()
    QP.page, QP.child = page, child
end

function QP:Active() return self.active and true or false end

function QP:Show(questID)
    local log = api("QuestMapFrame")
    local df = log and log.DetailsFrame
    if not df or not questID then return end
    if not QP.Enabled() then
        if self.active then self:Hide() end
        return
    end
    if not page then build(df) end
    self.questID = questID
    self.active = true
    keepHidden(df.ScrollFrame)
    keepHidden(df.RewardsFrameContainer)
    blizzardArt(df, 0)
    QP.bg:Show()
    page:Show()
    layoutFooter(df)
    self:Render(false)
end

function QP:Hide()
    self.active = false
    self.questID = nil
    if page then page:Hide() end
    if QP.bg then QP.bg:Hide() end
    local log = api("QuestMapFrame")
    local df = log and log.DetailsFrame
    if df then
        blizzardArt(df, 1)
        restoreFooter()
        if df.ScrollFrame then df.ScrollFrame:Show() end
        if df.RewardsFrameContainer then df.RewardsFrameContainer:Show() end
    end
end

-- les objectifs avancent, un objet arrive du serveur : la page ouverte se met à jour (en une fois)
local pending = false
local function refreshSoon()
    if not QP.active or pending then return end
    pending = true
    local after = C_Timer and C_Timer.After
    if after then
        after(0.2, function() pending = false if QP.active then QP:Render(true) end end)
    else
        pending = false
        QP:Render(true)
    end
end
QP.RefreshSoon = refreshSoon

function QP:Init()
    if self.hooked then return end
    self.hooked = true
    if hooksecurefunc and type(api("QuestMapFrame_ShowQuestDetails")) == "function" then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID) QP:Show(questID) end)
    end
    local log = api("QuestMapFrame")
    local df = log and log.DetailsFrame
    if df then df:HookScript("OnHide", function() QP:Hide() end) end
    local events = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED", "QUEST_ITEM_UPDATE" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", refreshSoon)
    if ns.OnChange then
        ns:OnChange("mapQuestPage", function()
            local log = api("QuestMapFrame")
            local d = log and log.DetailsFrame
            if d and d:IsShown() and d.questID then QP:Show(d.questID) elseif QP.active then QP:Hide() end
        end)
    end
end

function QP:Status()
    return ("page de quête Platyplus : %s%s"):format(QP.Enabled() and "allumée" or "éteinte",
        self.active and (" (quête " .. tostring(self.questID) .. " affichée)") or "")
end
