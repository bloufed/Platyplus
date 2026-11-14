-- Platyplus : onglets Réputation, Compétences, JcJ et Monnaies de la fenêtre du personnage (CharacterWindow.lua)
--  * Réputation : tes factions par groupe (clic sur un groupe : le replier), une barre colorée selon le rang ;
--    clic sur une faction : sa description et ses actions (suivre sur la barre d'expérience, guerre, inactive)
--  * Compétences : métiers, armes, armures, langues, avec leur niveau ; clic : la description
--  * JcJ : ton rang de la saison, ta progression, la fin de saison, tes victoires honorables, la prochaine récompense
--  * Monnaies : seulement si le personnage en a
-- Vérifié dans le code de Forever : Camelot/ReputationFrame.lua (C_Reputation.GetNumFactions, GetFactionDataByIndex,
-- Expand/CollapseFactionHeader, SetWatchedFactionByIndex, ToggleFactionAtWar, SetFactionActive, FACTION_BAR_COLORS,
-- FACTION_STANDING_LABEL), Camelot/SkillsFrame.lua (C_SkillInfo.GetNumSkillLines, GetSkillLineInfo ->
-- name, isHeader, isCollapsed, rank, modifier, maxRank, description ; Expand/CollapseSkillHeader),
-- Camelot/PVPRankFrame.lua (C_MajorFactions.GetMajorFactionProgressionInfo(2800) : renownLevel,
-- renownReputationEarned, renownLevelThreshold, maxLevel ; PVP_RANK_<n>_<faction> ; GetRenownRewardsForLevel).
local ADDON, ns = ...

local CW = ns.CharWindow
if not CW then return end

local floor, max, min = math.floor, math.max, math.min
local function api(name) return rawget(_G, name) end
local call, try = CW.Call, CW.Try

local function number(n)
    n = tonumber(n) or 0
    local f = api("BreakUpLargeNumbers")
    if f then
        local ok, s = pcall(f, n)
        if ok and s then return s end
    end
    return tostring(n)
end

---------------------------------------------------------------------------
-- Liste à volets (groupes repliables, lignes avec barre, détail sous la ligne choisie)
---------------------------------------------------------------------------
local List = {}
List.__index = List

local LIST_W = CW.CONTENT_W - 10

-- petit triangle : pointe à droite (replié) ou en bas (ouvert)
local function triangle(frame)
    local t = { right = {}, down = {} }
    for i, size in ipairs({ 7, 5, 3, 1 }) do
        local d = frame:CreateTexture(nil, "OVERLAY")
        d:SetColorTexture(1, 1, 1, 1)
        d:SetSize(size, 1)
        t.down[i] = d
        local r = frame:CreateTexture(nil, "OVERLAY")
        r:SetColorTexture(1, 1, 1, 1)
        r:SetSize(1, size)
        t.right[i] = r
    end
    function t:Place(anchor, x, y)
        for i = 1, 4 do
            self.down[i]:ClearAllPoints()
            self.down[i]:SetPoint("TOP", anchor, "TOPLEFT", x + 4, y - 4 - i)
            self.right[i]:ClearAllPoints()
            self.right[i]:SetPoint("LEFT", anchor, "TOPLEFT", x + 2 + i, y - 8)
        end
    end
    function t:Set(collapsed, shown, c)
        for i = 1, 4 do
            self.down[i]:SetShown(shown and not collapsed)
            self.right[i]:SetShown(shown and collapsed)
            self.down[i]:SetVertexColor(c[1], c[2], c[3], 1)
            self.right[i]:SetVertexColor(c[1], c[2], c[3], 1)
        end
    end
    return t
end

function CW.NewList(panel)
    local area = ns.Win.ScrollArea(panel, LIST_W, CW.BODY_H)
    area.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    return setmetatable({ area = area, pools = { row = {}, text = {}, button = {} },
                          used = { row = 0, text = 0, button = 0 }, y = 0 }, List)
end

function List:Begin()
    for kind, pool in pairs(self.pools) do
        for _, o in ipairs(pool) do o:Hide() end
        self.used[kind] = 0
    end
    self.y = 0
end

function List:Finish()
    self.area:SetContentHeight(self.y + 10)
end

function List:Acquire(kind, make)
    self.used[kind] = self.used[kind] + 1
    local o = self.pools[kind][self.used[kind]]
    if not o then
        o = make()
        self.pools[kind][self.used[kind]] = o
    end
    o:ClearAllPoints()
    o:Show()
    return o
end

local ROW_H = 34

local function makeRow(list)
    local W, C = ns.W, ns.W.C
    local r = CreateFrame("Button", nil, list.area.child)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = W.Round(r, "BACKGROUND", 0, 7)
    -- progression : la ligne elle-même se remplit (textures de la ligne, sous le texte : rien ne cache les chiffres)
    r.fillAnchor = r:CreateTexture(nil, "BACKGROUND", nil, 1)   -- (sans image : sert seulement de cadre au remplissage)
    r.fill = W.Round(r, "BORDER", 0, 7)
    r.fill:AnchorBox(r.fillAnchor)
    r.accent = r:CreateTexture(nil, "ARTWORK")          -- trait de couleur à gauche (rang de la faction...)
    r.accent:SetWidth(3)
    r.line = r:CreateTexture(nil, "BORDER")             -- filet après le titre d'un groupe
    r.line:SetHeight(1)
    r.line:SetColorTexture(1, 1, 1, 0.08)
    r.arrow = triangle(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.name = W.Text(r, "GameFontHighlight", C.text, "OVERLAY", 14)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    -- pastille tout à droite (rang, bonus)
    r.pillAnchor = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.pillAnchor:SetHeight(20)
    r.pill = W.Round(r, "ARTWORK", 0, 10)
    r.pill:AnchorBox(r.pillAnchor)
    r.pillText = W.Text(r, "GameFontHighlight", C.text, "OVERLAY", 12)
    r.pillText:SetPoint("CENTER", r.pillAnchor, "CENTER", 0, 0)
    r.right = W.Text(r, "GameFontHighlight", C.dim, "OVERLAY", 13)
    r.right:SetJustifyH("RIGHT")
    if r.right.SetWordWrap then r.right:SetWordWrap(false) end
    r:SetScript("OnEnter", function(self)
        self.bg:SetColor(self.o.header and C.white or C.btnHover, self.o.header and 0.04 or 1)
        local tip = api("GameTooltip")
        if tip and self.o.tip then
            tip:SetOwner(self, "ANCHOR_RIGHT")
            if type(self.o.tip) == "function" then try("infobulle", self.o.tip, tip, self) else tip:SetText(self.o.tip, 1, 1, 1, 1, true) end
            tip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        list.PaintRow(self)
        local tip = api("GameTooltip")
        if tip and tip:IsOwned(self) then tip:Hide() end
    end)
    r:SetScript("OnClick", function(self, button)
        if self.o.onClick then
            W.Sound("click")
            try("clic", self.o.onClick, button)
        end
    end)
    return r
end

function List.PaintRow(r)
    local C = ns.W.C
    local o = r.o
    if o.header then
        r.bg:SetColor(C.white, 0)
    elseif o.selected then
        r.bg:SetColor(C.accent2, 0.45)
    else
        r.bg:SetColor(C.card, 0.7)
    end
end

-- o : pillW / rightW (largeurs fixes des colonnes pastille et chiffres), text, header, collapsed, indent, icon, right (chiffres, à droite), rightColor, pill = { texte, couleur }
--     (pastille tout à droite), value (0..1 : la ligne se remplit jusque-là), barColor, accent (trait de gauche),
--     color, tip (texte ou function(tooltip, ligne)), onClick(bouton), selected
-- Ligne : [trait] [flèche] [icône] nom ..................... chiffres  [pastille]   (fond rempli selon la progression)
--         avec rightW :              nom ..................... [pastille]  chiffres
function List:Row(o)
    local W, C = ns.W, ns.W.C
    local r = self:Acquire("row", function() return makeRow(self) end)
    r.o = o
    local x = (o.indent or 0) * 18
    local rowW = LIST_W - x
    local h = o.header and 30 or ROW_H
    self.y = self.y + (self.y > 0 and (o.header and 12 or 4) or 0)
    r:SetPoint("TOPLEFT", self.area.child, "TOPLEFT", x, -self.y)
    r:SetSize(rowW, h)
    self.y = self.y + h

    local textX = 12
    r.arrow:Place(r, 8, -floor(h / 2) + 8)
    r.arrow:Set(o.collapsed and true or false, o.collapsed ~= nil, o.header and C.gold or C.dim)
    if o.collapsed ~= nil then textX = 24 end
    if o.accent and not o.header then
        r.accent:Show()
        r.accent:ClearAllPoints()
        r.accent:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -6)
        r.accent:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 6)
        r.accent:SetColorTexture(o.accent[1], o.accent[2], o.accent[3], 0.9)
    else
        r.accent:Hide()
    end
    if o.icon then
        r.icon:Show()
        r.icon:SetTexture(o.icon)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "LEFT", textX, 0)
        textX = textX + 28
    else
        r.icon:Hide()
    end

    -- à droite : la pastille, puis les chiffres juste avant. Avec une colonne de chiffres fixe (rightW), c'est
    -- l'inverse : les chiffres collés au bord droit (même place sur toutes les lignes), la pastille juste avant
    -- eux dans sa colonne (pillW, réservée même quand la ligne n'en a pas)
    local fixed = o.rightW and not o.header
    local pillRight = fixed and -(12 + o.rightW + 10) or -10
    local rightEdge = -12
    local pw = 0
    if o.pill and not o.header then
        local pc = o.pill[2] or C.dim
        r.pillText:SetText(o.pill[1] or "")
        W.TextColor(r.pillText, pc)
        pw = o.pillW or max(44, (r.pillText:GetStringWidth() or 0) + 20)
        r.pillAnchor:ClearAllPoints()
        r.pillAnchor:SetPoint("RIGHT", r, "RIGHT", pillRight, 0)
        r.pillAnchor:SetWidth(pw)
        r.pill:SetColor(pc, 0.16)
        r.pill:Show()
        r.pillText:Show()
    else
        r.pill:Hide()
        r.pillText:Hide()
        if o.pillW and not o.header then pw = o.pillW end
    end
    if not fixed and pw > 0 then rightEdge = -10 - pw - 12 end
    r.right:ClearAllPoints()
    r.right:SetPoint("RIGHT", r, "RIGHT", rightEdge, 0)
    r.right:SetText(o.right or "")
    W.TextColor(r.right, o.rightColor or C.dim)
    local nameEdge     -- bord droit du nom (décalage négatif depuis la droite de la ligne)
    if fixed then
        r.right:SetWidth(o.rightW)
        r.rightFixed = true
        nameEdge = (pw > 0) and (pillRight - pw - 12) or -(12 + o.rightW + 16)
    else
        if r.rightFixed then
            r.right:SetWidth(0)
            r.rightFixed = nil
        end
        local rightW = (o.right and o.right ~= "") and ((r.right:GetStringWidth() or 0) + 16) or 0
        nameEdge = rightEdge - rightW
    end

    r.name:SetFont(W.Font(), o.header and 15 or 14, "")
    W.TextColor(r.name, o.color or (o.header and C.gold or C.text))
    r.name:SetText(o.text or "")
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r, "LEFT", textX, 0)
    r.name:SetWidth(max(40, rowW - textX + nameEdge))

    -- remplissage de la ligne selon la progression
    if o.value and not o.header then
        local v = max(0, min(1, o.value))
        r.fillAnchor:ClearAllPoints()
        r.fillAnchor:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
        r.fillAnchor:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
        r.fillAnchor:SetWidth(max(14, floor(rowW * v)))
        r.fill:SetColor(o.barColor or C.accent, 0.20)
        r.fill:SetShown(v > 0)
    else
        r.fill:Hide()
    end
    r.value = o.value

    if o.header then
        local w = r.name:GetStringWidth() or 0
        r.line:Show()
        r.line:ClearAllPoints()
        r.line:SetPoint("LEFT", r, "LEFT", textX + w + 12, 0)
        r.line:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    else
        r.line:Hide()
    end
    List.PaintRow(r)
    return r
end

-- texte libre (description, message)
function List:Text(text, indent, size, color)
    if type(text) ~= "string" or text == "" then return end
    local W, C = ns.W, ns.W.C
    local fs = self:Acquire("text", function() return W.Text(self.area.child, "GameFontHighlight", C.dim, "OVERLAY", 13) end)
    local x = (indent or 0) * 18 + 14
    fs:SetFont(W.Font(), size or 13, "")
    W.TextColor(fs, color or C.dim)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(LIST_W - x - 14)
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetText(text)
    self.y = self.y + 8
    fs:SetPoint("TOPLEFT", self.area.child, "TOPLEFT", x, -self.y)
    self.y = self.y + W.Measure(fs, text, LIST_W - x - 14)
    return fs
end

-- rangée de boutons sous une ligne : { { text, onClick }, ... }
function List:Buttons(list, indent)
    local W = ns.W
    local x = (indent or 0) * 18 + 14
    self.y = self.y + 8
    for i, def in ipairs(list) do
        local b = self:Acquire("button", function()
            local btn
            btn = W.Button(self.area.child, {
                text = "", width = 190, height = 26,
                getText = function() return btn and btn.text or "" end,
                onClick = function() if btn.action then try("action", btn.action) end end,
            })
            return btn
        end)
        b.text, b.action = def[1], def[2]
        b:Refresh()
        b:SetPoint("TOPLEFT", self.area.child, "TOPLEFT", x + (i - 1) * 200, -self.y)
    end
    self.y = self.y + 26 + 4
end

local function listTab(def)
    def.build = function(panel) panel.list = CW.NewList(panel) end
    local fill = def.fill
    def.refresh = function(panel)
        panel.list:Begin()
        fill(panel.list)
        panel.list:Finish()
    end
    CW:RegisterTab(def)
end

---------------------------------------------------------------------------
-- Réputation
---------------------------------------------------------------------------
local selectedFaction            -- factionID dont le détail est ouvert

local function standingLabel(reaction)
    local key = "FACTION_STANDING_LABEL" .. tostring(reaction)
    local text = call("GetText", key, call("UnitSex", "player"))
    if type(text) ~= "string" or text == "" or text == key then text = api(key) end
    return type(text) == "string" and text or ns.Tf("Rang %s", tostring(reaction))
end

local function reactionColor(reaction)
    local colors = api("FACTION_BAR_COLORS")
    local c = type(colors) == "table" and colors[reaction]
    if type(c) == "table" and c.r then return { c.r, c.g, c.b, 1 } end
    return ns.W.C.accent
end

-- rang, avancée (0..1) et texte « 1 250 / 3 000 » ; amitiés comprises
local function standing(d)
    local label = standingLabel(d.reaction)
    local cur = (d.currentStanding or 0) - (d.currentReactionThreshold or 0)
    local span = (d.nextReactionThreshold or 0) - (d.currentReactionThreshold or 0)
    local G = api("C_GossipInfo")
    local fr = G and G.GetFriendshipReputation and call(G.GetFriendshipReputation, d.factionID)
    if type(fr) == "table" and (tonumber(fr.friendshipFactionID) or 0) > 0 then
        label = fr.reaction or label
        if fr.nextThreshold then
            cur = (fr.standing or 0) - (fr.reactionThreshold or 0)
            span = fr.nextThreshold - (fr.reactionThreshold or 0)
        else
            span = 0
        end
    end
    if span <= 0 then return label, 1, nil end
    return label, max(0, min(1, cur / span)), number(cur) .. " / " .. number(span)
end

local function fillReputation(list)
    local W, C = ns.W, ns.W.C
    local R = api("C_Reputation")
    if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then
        list:Text(ns.T("Réputations indisponibles sur ce client."))
        return
    end
    local n = tonumber((call(R.GetNumFactions))) or 0
    local depth = 0
    for i = 1, n do
        local d = call(R.GetFactionDataByIndex, i)
        if type(d) == "table" and d.name then
            local index = i
            if d.isHeader and not d.isHeaderWithRep then
                depth = d.isChild and 1 or 0
                list:Row({ header = true, text = d.name, collapsed = d.isCollapsed and true or false, indent = depth,
                    onClick = function()
                        if d.isCollapsed then R.ExpandFactionHeader(index) else R.CollapseFactionHeader(index) end
                        CW.RefreshSoon("ReputationFrame")
                    end })
            else
                local label, value, progress = standing(d)
                local indent = d.isHeaderWithRep and (d.isChild and 1 or 0) or (depth + 1)
                local open = selectedFaction == d.factionID
                local rc = reactionColor(d.reaction)
                local right = progress or ""
                if d.isWatched then right = W.Color("accent", ns.T("suivie")) .. (right ~= "" and ("   " .. right) or "") end
                list:Row({
                    text = d.name, indent = indent, value = value, barColor = rc, accent = rc,
                    right = right, pill = { label, rc }, pillW = 84, rightW = 170, color = d.atWarWith and C.bad or C.text,
                    collapsed = d.isHeaderWithRep and (d.isCollapsed and true or false) or nil,
                    selected = open,
                    tip = d.atWarWith and ns.T("En guerre : tu peux attaquer ses membres.") or nil,
                    onClick = function()
                        if d.isHeaderWithRep then
                            if d.isCollapsed then R.ExpandFactionHeader(index) else R.CollapseFactionHeader(index) end
                        else
                            selectedFaction = (selectedFaction ~= d.factionID) and d.factionID or nil
                        end
                        CW.RefreshSoon("ReputationFrame")
                    end,
                })
                if open then
                    list:Text(d.description, indent)
                    local buttons = {
                        { d.isWatched and ns.T("Ne plus suivre") or ns.T("Suivre sur la barre"), function()
                            R.SetWatchedFactionByIndex(d.isWatched and 0 or index)
                            CW.RefreshSoon("ReputationFrame")
                        end },
                    }
                    if d.canToggleAtWar and R.ToggleFactionAtWar then
                        buttons[#buttons + 1] = { d.atWarWith and ns.T("Faire la paix") or ns.T("Déclarer la guerre"), function()
                            R.ToggleFactionAtWar(index)
                            CW.RefreshSoon("ReputationFrame")
                        end }
                    end
                    if d.canSetInactive and R.SetFactionActive then
                        local active = not R.IsFactionActive or R.IsFactionActive(index)
                        buttons[#buttons + 1] = { active and ns.T("Ranger (inactive)") or ns.T("Remettre active"), function()
                            R.SetFactionActive(index, not active)
                            CW.RefreshSoon("ReputationFrame")
                        end }
                    end
                    list:Buttons(buttons, indent)
                end
            end
        end
    end
    if n == 0 then list:Text(ns.T("Aucune réputation pour l'instant.")) end
end

listTab({ id = "ReputationFrame", label = "Réputation", order = 2, fill = fillReputation,
          events = { "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" } })

---------------------------------------------------------------------------
-- Compétences
---------------------------------------------------------------------------
local selectedSkill

local function fillSkills(list)
    local W, C = ns.W, ns.W.C
    local S = api("C_SkillInfo")
    if not (S and S.GetNumSkillLines and S.GetSkillLineInfo) then
        list:Text(ns.T("Compétences indisponibles sur ce client."))
        return
    end
    local n = tonumber((call(S.GetNumSkillLines))) or 0
    for i = 1, n do
        local info = call(S.GetSkillLineInfo, i)
        if type(info) == "table" and info.name then
            local index = i
            if info.isHeader then
                list:Row({ header = true, text = info.name, collapsed = info.isCollapsed and true or false,
                    onClick = function()
                        if info.isCollapsed then S.ExpandSkillHeader(index) else S.CollapseSkillHeader(index) end
                        CW.RefreshSoon("SkillsFrame")
                    end })
            else
                local rank, maxRank, mod = tonumber(info.rank) or 0, tonumber(info.maxRank) or 0, tonumber(info.modifier) or 0
                local right, value, pill
                if maxRank > 1 then
                    right = rank .. " / " .. maxRank
                    value = rank / maxRank
                    if mod ~= 0 then
                        pill = { (mod > 0 and "+" or "") .. mod, mod > 0 and C.good or C.bad }
                    elseif rank >= maxRank then
                        pill = { ns.T("palier atteint"), C.gold }
                    end
                else
                    pill = { ns.T("connue"), C.dim }
                end
                local key = info.skillID or info.name
                local open = selectedSkill == key
                list:Row({
                    text = info.name, indent = 1, right = right, rightColor = C.text, pill = pill, pillW = 104, rightW = 70, value = value,
                    barColor = rank >= maxRank and C.good or C.accent, selected = open,
                    onClick = function()
                        selectedSkill = (selectedSkill ~= key) and key or nil
                        CW.RefreshSoon("SkillsFrame")
                    end,
                })
                if open then
                    local desc = info.description
                    list:Text((type(desc) == "string" and desc ~= "") and desc or ns.T("Pas de description."), 1)
                end
            end
        end
    end
    if n == 0 then list:Text(ns.T("Aucune compétence.")) end
end

listTab({ id = "SkillsFrame", label = "Compétences", order = 3, fill = fillSkills,
          events = { "SKILL_LINES_CHANGED", "CHARACTER_POINTS_CHANGED" } })

---------------------------------------------------------------------------
-- JcJ : rang de la saison
---------------------------------------------------------------------------
local PVP_FACTION = 2800

local function rankTitle(rank)
    if not rank or rank <= 0 then return api("PVP_RANK_0_NAME") or ns.T("Sans rang") end
    local ranks = Enum and Enum.PvPRanks
    if type(ranks) == "table" and ranks.Rank_1 then
        local faction01 = call("UnitFactionGroup", "player") == "Alliance" and 1 or 0
        local key = "PVP_RANK_" .. tostring(ranks.Rank_1 + rank - 1) .. "_" .. faction01
        local text = call("GetText", key, call("UnitSex", "player"))
        if type(text) ~= "string" or text == key then text = api(key) end
        if type(text) == "string" and text ~= "" then return text end
    end
    return ns.Tf("Rang %d", rank)
end

local function duration(seconds)
    seconds = floor(tonumber(seconds) or 0)
    local d, h, m = floor(seconds / 86400), floor(seconds % 86400 / 3600), floor(seconds % 3600 / 60)
    if d > 0 then return ns.Tf("%d j %d h", d, h) end
    if h > 0 then return ns.Tf("%d h %d min", h, m) end
    return ns.Tf("%d min", m)
end

local function buildPvP(panel)
    local W, C, Win = ns.W, ns.W.C, ns.Win
    local card = CreateFrame("Frame", nil, panel)
    card:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    card:SetSize(CW.CONTENT_W - 10, 150)
    W.Round(card, "BACKGROUND", 0, 12):SetColor(C.card, 0.8)
    W.Stroke(card, "BORDER", 0, 12):SetColor(C.white, 0.05)
    panel.badge = card:CreateTexture(nil, "ARTWORK")
    panel.badge:SetSize(96, 96)
    panel.badge:SetPoint("LEFT", card, "LEFT", 22, 0)
    panel.rank = W.Text(card, "GameFontHighlightLarge", C.gold, "OVERLAY", 22)
    panel.rank:SetPoint("TOPLEFT", card, "TOPLEFT", 140, -26)
    panel.rankNum = W.Text(card, "GameFontHighlight", C.dim, "OVERLAY", 14)
    panel.rankNum:SetPoint("LEFT", panel.rank, "RIGHT", 12, -1)
    panel.bar = Win.Bar(card, 14)
    panel.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 140, -70)
    panel.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -26, -70)
    panel.progress = W.Text(card, "GameFontHighlight", C.text, "OVERLAY", 13)
    panel.progress:SetPoint("TOPLEFT", panel.bar, "BOTTOMLEFT", 0, -8)
    panel.season = W.Text(card, "GameFontHighlight", C.dim, "OVERLAY", 13)
    panel.season:SetPoint("TOPRIGHT", panel.bar, "BOTTOMRIGHT", 0, -8)
    -- trois tuiles : victoires du jour, victoires au total, rang maximum de la saison
    panel.tiles = {}
    local tileW = floor((CW.CONTENT_W - 10 - 2 * 12) / 3)
    for i, label in ipairs({ "Victoires honorables aujourd'hui", "Victoires honorables au total", "Rang maximum de la saison" }) do
        label = ns.T(label)
        local t = CreateFrame("Frame", nil, panel)
        t:SetSize(tileW, 76)
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * (tileW + 12), -162)
        W.Round(t, "BACKGROUND", 0, 10):SetColor(C.card, 0.7)
        t.value = W.Text(t, "GameFontHighlightLarge", i == 3 and C.gold or C.text, "OVERLAY", 26)
        t.value:SetPoint("TOPLEFT", t, "TOPLEFT", 16, -12)
        t.label = W.Text(t, "GameFontHighlight", C.dim, "OVERLAY", 12)
        t.label:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 16, 12)
        t.label:SetText(label)
        panel.tiles[i] = t
    end
    panel.list = CW.NewList(panel)
    panel.list.area.scroll:ClearAllPoints()
    panel.list.area.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -250)
    panel.list.area.scroll:SetHeight(CW.BODY_H - 250)
end

local function refreshPvP(panel)
    local W, C = ns.W, ns.W.C
    local MF = api("C_MajorFactions")
    local info = MF and MF.GetMajorFactionProgressionInfo and call(MF.GetMajorFactionProgressionInfo, PVP_FACTION)
    local list = panel.list
    list:Begin()
    if type(info) ~= "table" then
        panel.rank:SetText(ns.T("Rang JcJ indisponible"))
        panel.rankNum:SetText("")
        panel.bar:SetValue(0)
        panel.progress:SetText("")
        panel.season:SetText("")
        list:Finish()
        return
    end
    local rank = tonumber(info.renownLevel) or 0
    local points, threshold = tonumber(info.renownReputationEarned) or 0, tonumber(info.renownLevelThreshold) or 0
    panel.rank:SetText(rankTitle(rank))
    panel.rankNum:SetText(rank > 0 and ns.Tf("rang %d", rank) or "")
    local atlas = rank > 0 and ("UI-Character-Info-Honor-Icon-" .. rank)
        or (call("UnitFactionGroup", "player") == "Horde" and "UI-Character-Info-Honor-Icon-Horde" or "UI-Character-Info-Honor-Icon-Alliance")
    -- (l'image n'est posée que si le jeu la connaît ; sinon l'icône JcJ classique)
    local T = api("C_Texture")
    local known = T and T.GetAtlasInfo and call(T.GetAtlasInfo, atlas)
    if known and panel.badge.SetAtlas then
        panel.badge:SetAtlas(atlas)
    else
        panel.badge:SetTexture("Interface\\Icons\\Achievement_PVP_A_01")
    end
    panel.bar:SetColor(C.gold)
    panel.bar:SetValue(threshold > 0 and points / threshold or 1)
    panel.progress:SetText(threshold > 0 and ns.Tf("%s / %s points de rang", number(points), number(threshold)) or ns.T("Rang maximum"))
    local season = tonumber((call("GetCurrentArenaSeason"))) or 0
    local SI = api("C_SeasonInfo")
    local left = SI and SI.GetTimeUntilCurrentPVPSeasonEnd and tonumber((call(SI.GetTimeUntilCurrentPVPSeasonEnd))) or 0
    local parts = {}
    if season > 0 then parts[#parts + 1] = ns.Tf("Saison %d", season) end
    if left > 0 then parts[#parts + 1] = ns.Tf("fin dans %s", duration(left)) end
    panel.season:SetText(table.concat(parts, " · "))

    local hk = call("GetPVPLifetimeStats")
    local today = call("GetPVPSessionStats")
    panel.tiles[1].value:SetText(today and number(today) or "—")
    panel.tiles[2].value:SetText(hk and number(hk) or "—")
    panel.tiles[3].value:SetText(tonumber(info.maxLevel) and tostring(info.maxLevel) or "—")
    local maxLevel = tonumber(info.maxLevel) or rank
    for r = rank + 1, maxLevel do
        local rewards = MF.GetRenownRewardsForLevel and call(MF.GetRenownRewardsForLevel, PVP_FACTION, r)
        if type(rewards) == "table" and #rewards > 0 then
            list:Row({ header = true, text = ns.Tf("Prochaine récompense : rang %d", r) })
            for _, reward in ipairs(rewards) do
                if reward.description or reward.name then
                    list:Row({ text = reward.name or reward.description, icon = reward.icon,
                               tip = reward.description })
                end
            end
            local vendor = call("UnitFactionGroup", "player") == "Horde" and api("PVP_RANK_REWARDS_VENDOR_HORDE")
                or api("PVP_RANK_REWARDS_VENDOR_ALLIANCE")
            if type(vendor) == "string" then list:Text(vendor) end
            break
        end
    end
    list:Finish()
end

CW:RegisterTab({
    id = "PVPRankFrame", label = "JcJ", order = 4, build = buildPvP, refresh = refreshPvP,
    available = function() return api("PVPRankFrame") ~= nil or api("C_MajorFactions") ~= nil end,
    events = { "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "PLAYER_PVP_KILLS_CHANGED" },
})

---------------------------------------------------------------------------
-- Monnaies (seulement si le personnage en a)
---------------------------------------------------------------------------
local function currencyCount()
    local CI = api("C_CurrencyInfo")
    return CI and CI.GetCurrencyListSize and tonumber((call(CI.GetCurrencyListSize))) or 0
end

local function fillCurrency(list)
    local CI = api("C_CurrencyInfo")
    local n = currencyCount()
    for i = 1, n do
        local info = call(CI.GetCurrencyListInfo, i)
        if type(info) == "table" and info.name then
            local index = i
            if info.isHeader then
                local expanded = info.isHeaderExpanded and true or false
                list:Row({ header = true, text = info.name, collapsed = not expanded,
                    onClick = function()
                        CI.ExpandCurrencyList(index, not expanded)
                        CW.RefreshSoon("TokenFrame")
                    end })
            else
                local qty, maxQty = tonumber(info.quantity) or 0, tonumber(info.maxQuantity) or 0
                list:Row({ text = info.name, icon = info.iconFileID, indent = 1,
                    right = number(qty) .. (maxQty > 0 and (" / " .. number(maxQty)) or ""), rightColor = ns.W.C.text,
                    tip = function(tip) if tip.SetCurrencyToken then tip:SetCurrencyToken(index) else tip:SetText(info.name) end end })
            end
        end
    end
end

listTab({ id = "TokenFrame", label = "Monnaies", order = 5, fill = fillCurrency,
          available = function() return currencyCount() > 0 end,
          events = { "CURRENCY_DISPLAY_UPDATE" } })
