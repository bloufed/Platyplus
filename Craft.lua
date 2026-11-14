-- Platyplus : coût des recettes face à l'HDV (ns.Craft)
-- À droite de la fenêtre de métier, pour la recette affichée :
--  * l'objet fabriqué : son prix à l'HDV et ce qu'il te reste une fois vendu (l'HDV garde 5 %)
--  * chaque composant obligatoire : quantité x prix le plus bas entre l'HDV et le marchand (prix d'achat relevé)
--  * le résultat : bénéfice ou perte en fabriquant pour revendre
-- Les prix viennent de ns.Prices (scan complet de l'HDV, assistant de mise en vente, visites chez les marchands).
-- Vérifié dans le code de Forever (wow-ui-source, branche forever : Blizzard_Professions en version « Camelot »,
-- Blizzard_ProfessionsTemplates, TradeSkillUITypesDocumentation, ProfessionConstantsDocumentation) :
--  * ProfessionsFrame.CraftingPage.SchematicForm:Init(recipeInfo) à chaque recette affichée ; :GetRecipeInfo()
--  * C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft) -> { outputItemID, quantityMin, quantityMax,
--    reagentSlotSchematics = { { reagents = { { itemID } }, reagentType, quantityRequired } } }
--  * Enum.CraftingReagentType.Basic = 1 : composants obligatoires (optionnels et finitions ignorés)
--  * C_TradeSkillUI.GetRecipeOutputItemData(recipeID) -> { itemID, hyperlink } quand outputItemID manque
--  * Blizzard_Professions est chargé à la demande : on s'y accroche à son ADDON_LOADED
-- NON VÉRIFIÉ en jeu : tout est protégé ; sans ProfessionsFrame, ce module ne fait rien.
local ADDON, ns = ...

local Craft = {}
ns.Craft = Craft

local floor, max = math.floor, math.max
local AH_CUT = 0.05
local CARD_W, PAD, LINE_H = 270, 14, 18
local BASIC = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1

local function db(key)
    return ns.db and ns.db[key]
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

local function money(copper)
    return ns.Prices and ns.Prices.Money(copper) or tostring(copper)
end

local function itemName(id)
    local name = C_Item and call(C_Item.GetItemNameByID, id)
    if name and name ~= "" then return name end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return ns.Tf("Objet #%s", tostring(id))
end

local function itemQuality(id)
    local q = C_Item and call(C_Item.GetItemQualityByID, id)
    return type(q) == "number" and q or 1
end

local function qtyText(q)
    if q == floor(q) then return tostring(q) end
    return (string.format("%.1f", q):gsub("%.", ","))
end

---------------------------------------------------------------------------
-- Calcul (testé hors du jeu)
---------------------------------------------------------------------------
-- Renvoie nil si la recette est inconnue, sinon :
-- { outputID, qty, unit, value, net, age, reagents = { { id, qty, unit, source, total } }, cost, missing, profit }
function Craft.Evaluate(recipeID)
    local ui = rawget(_G, "C_TradeSkillUI")
    if not (ui and ui.GetRecipeSchematic and recipeID) then return nil end
    local schematic = call(ui.GetRecipeSchematic, recipeID, false)
    if type(schematic) ~= "table" then return nil end
    local P = ns.Prices
    local r = { reagents = {}, cost = 0, missing = 0 }

    -- objet fabriqué (quantité moyenne si la recette en donne « de 2 à 3 »)
    r.outputID = schematic.outputItemID
    if not r.outputID and ui.GetRecipeOutputItemData then
        local out = call(ui.GetRecipeOutputItemData, recipeID)
        r.outputID = type(out) == "table" and out.itemID or nil
    end
    local qMin, qMax = tonumber(schematic.quantityMin) or 1, tonumber(schematic.quantityMax) or 1
    r.qty = max(1, (qMin + max(qMin, qMax)) / 2)
    if r.outputID and P then
        r.unit, r.age = P:Get(r.outputID)
        if r.unit then
            r.value = floor(r.unit * r.qty)
            r.net = floor(r.value * (1 - AH_CUT))
        end
    end

    -- composants obligatoires : le moins cher des choix possibles, HDV ou marchand
    for _, slot in ipairs(type(schematic.reagentSlotSchematics) == "table" and schematic.reagentSlotSchematics or {}) do
        if slot.reagentType == BASIC and (tonumber(slot.quantityRequired) or 0) > 0 then
            local best
            for _, choice in ipairs(type(slot.reagents) == "table" and slot.reagents or {}) do
                local id = choice.itemID
                if id then
                    local unit, source
                    if P then unit, source = P:Cost(id) end
                    if not best or (unit and (not best.unit or unit < best.unit)) then
                        best = { id = id, unit = unit, source = source }
                    end
                end
            end
            if best then
                best.qty = slot.quantityRequired
                if best.unit then
                    best.total = floor(best.unit * best.qty + 0.5)
                    r.cost = r.cost + best.total
                else
                    r.missing = r.missing + 1
                end
                r.reagents[#r.reagents + 1] = best
            end
        end
    end
    if r.net and r.missing == 0 then r.profit = r.net - r.cost end
    return r
end

---------------------------------------------------------------------------
-- Carte à côté de la fenêtre de métier
---------------------------------------------------------------------------
local card, lines, title, footer
local currentRecipe
local hooked = false

local function newLine(i)
    local W, C = ns.W, ns.W.C
    local l = {}
    l.left = W.Text(card, "GameFontHighlightSmall", C.text, nil, 11)
    l.left:SetJustifyH("LEFT")
    l.left:SetWordWrap(false)
    l.right = W.Text(card, "GameFontHighlightSmall", C.text, nil, 11)
    l.right:SetJustifyH("RIGHT")
    lines[i] = l
    return l
end

local function createCard()
    local W, C = ns.W, ns.W.C
    card = CreateFrame("Frame", "PlatyplusCraftPrices", UIParent)
    card:SetSize(CARD_W, 120)
    card:SetClampedToScreen(true)
    card:EnableMouse(true)
    card:Hide()
    W.Shadow(card, 12, 16, 3)
    W.Round(card, "BACKGROUND", 0, 10):SetColor(C.bg)
    W.Stroke(card, "BORDER", 0, 10):SetColor(C.white, 0.07)
    local logo = card:CreateTexture(nil, "ARTWORK")
    logo:SetSize(20, 20)
    logo:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -PAD + 2)
    logo:SetTexture(ns.LOGO)
    title = W.Text(card, "GameFontHighlight", C.text, nil, 13)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText(ns.T("Prix à l'HDV"))
    footer = W.Text(card, "GameFontHighlightSmall", C.dim, nil, 10)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(true)
    lines = {}
end

-- rows = { { gauche, droite, couleurGauche, couleurDroite, espaceAvant } }
local function render(rows, foot)
    local C = ns.W.C
    local y = -PAD - 26
    for i, row in ipairs(rows) do
        local l = lines[i] or newLine(i)
        y = y - (row[5] or 0)
        l.left:ClearAllPoints()
        l.left:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, y)
        l.left:SetPoint("RIGHT", card, "RIGHT", -PAD - 96, 0)
        l.right:ClearAllPoints()
        l.right:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y)
        l.left:SetText(row[1] or "")
        l.right:SetText(row[2] or "")
        local lc, rc = row[3] or C.text, row[4] or C.text
        l.left:SetTextColor(lc[1], lc[2], lc[3], 1)
        l.right:SetTextColor(rc[1], rc[2], rc[3], 1)
        l.left:Show()
        l.right:Show()
        y = y - LINE_H
    end
    for i = #rows + 1, #lines do
        lines[i].left:Hide()
        lines[i].right:Hide()
    end
    footer:ClearAllPoints()
    footer:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, y - 6)
    footer:SetPoint("RIGHT", card, "RIGHT", -PAD, 0)
    footer:SetText(foot or "")
    local footH = (foot and foot ~= "") and max(12, footer:GetStringHeight() or 24) or 0
    card:SetHeight(-y + 6 + footH + PAD)
end

-- Lignes affichées pour une recette (séparé de l'affichage pour être testé)
function Craft.Describe(r)
    local C = ns.W and ns.W.C or {}
    local rows, foot = {}, nil
    local dim = C.dim
    if r.outputID then
        local q = itemQuality(r.outputID)
        local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        local color = qc and qc.r and { qc.r, qc.g, qc.b } or C.text
        rows[#rows + 1] = { itemName(r.outputID) .. (r.qty ~= 1 and (" x" .. qtyText(r.qty)) or ""),
            r.value and money(r.value) or ns.T("jamais vu"), color, r.value and C.text or C.gold }
        if r.net then
            rows[#rows + 1] = { ns.T("Pour toi (l'HDV garde 5 %)"), money(r.net), dim, C.text }
        end
    else
        rows[#rows + 1] = { ns.T("Rien à vendre (pas d'objet fabriqué)"), "", dim, dim }
    end
    if #r.reagents > 0 then
        rows[#rows + 1] = { ns.T("Composants"), "", C.accent, C.text, 6 }
        for _, g in ipairs(r.reagents) do
            local right = g.total and money(g.total) or "?"
            if g.source == "marchand" then right = ns.Tf("|cff999999marchand|r %s", right) end
            rows[#rows + 1] = { qtyText(g.qty) .. " x " .. itemName(g.id), right, C.text, g.total and C.text or C.gold }
        end
        rows[#rows + 1] = { ns.T("Total des composants"), money(r.cost) .. (r.missing > 0 and " + ?" or ""), dim, C.text }
    end
    if r.profit then
        local gain = r.profit >= 0
        rows[#rows + 1] = { gain and ns.T("Bénéfice") or ns.T("Perte"), (gain and "+" or "-") .. money(math.abs(r.profit)),
            gain and C.good or C.bad, gain and C.good or C.bad, 6 }
    end
    if r.outputID and not r.unit then
        foot = ns.T("Objet jamais vu à l'HDV : ouvre l'HDV pour un scan complet des prix.")
    elseif r.missing > 0 then
        foot = ns.Tf("%d composant(s) sans prix : jamais vu(s) à l'HDV ni chez un marchand visité.", r.missing)
    elseif r.age and r.age > 3600 then
        foot = ns.Tf("Prix de l'objet relevé %s.", ns.Prices.AgeText(r.age))
    end
    return rows, foot
end

function Craft:Hide()
    if card then card:Hide() end
end

function Craft:Show(recipeInfo)
    currentRecipe = recipeInfo
    if not db("craftPrices") or type(recipeInfo) ~= "table" or not recipeInfo.recipeID or recipeInfo.isRecraft then
        return self:Hide()
    end
    if not (ns.W and ns.W.C) then return end
    local r = Craft.Evaluate(recipeInfo.recipeID)
    if not r then return self:Hide() end
    if not card then createCard() end
    local frame = rawget(_G, "ProfessionsFrame")
    card:ClearAllPoints()
    if frame then
        card:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
        if frame.GetFrameStrata then card:SetFrameStrata(frame:GetFrameStrata() or "HIGH") end
    else
        card:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    end
    render(Craft.Describe(r))
    card:Show()
end

function Craft:Refresh()
    if card and card:IsShown() then self:Show(currentRecipe) end
end

-- S'accroche à la fenêtre de métier de Blizzard (une seule fois, dès qu'elle existe)
function Craft:Hook()
    if hooked then return true end
    local frame = rawget(_G, "ProfessionsFrame")
    local form = frame and frame.CraftingPage and frame.CraftingPage.SchematicForm
    if not (form and form.Init) then return false end
    hooked = true
    hooksecurefunc(form, "Init", function(_, recipeInfo) Craft:Show(recipeInfo) end)
    form:HookScript("OnShow", function(f) Craft:Show(call(f.GetRecipeInfo, f)) end)
    form:HookScript("OnHide", function() Craft:Hide() end)
    if frame.HookScript then frame:HookScript("OnHide", function() Craft:Hide() end) end
    return true
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_Professions" and Craft:Hook() then events:UnregisterEvent("ADDON_LOADED") end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        Craft:Refresh()   -- un nom d'objet vient d'arriver
    end
end)

function Craft:Init()
    if not self:Hook() then events:RegisterEvent("ADDON_LOADED") end
    pcall(events.RegisterEvent, events, "GET_ITEM_INFO_RECEIVED")
    ns:OnChange("craftPrices", function(_, on)
        local frame = rawget(_G, "ProfessionsFrame")
        if on and frame and frame:IsShown() then Craft:Show(currentRecipe) else Craft:Hide() end
    end)
    if ns.Prices and ns.Prices.OnUpdate then ns.Prices:OnUpdate(function() Craft:Refresh() end) end
end
