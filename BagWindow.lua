-- Platyplus : sacs (ns.BagWindow), une seule fenêtre Platyplus pour tous tes sacs
--  * tous les sacs à la suite dans une grille, cases plus grandes, nombre de colonnes et taille réglables
--  * recherche par nom (les autres objets s'éteignent), bouton Trier, argent et places libres en bas
--  * rangement par type (réglage bagWinGroup) : Quête, Consommables, Artisanat, Équipement, Divers, Poubelle, Libre,
--    chaque section sous son titre. Seul l'affichage change : les objets restent à leur place dans les sacs.
--  * déplaçable par son bandeau ; elle s'ouvre et se ferme avec les sacs du jeu (touche B, bouton du sac à dos,
--    marchand, banque, courrier, Échap)
--
-- Comment : les cases sont celles du jeu (gabarit ContainerFrameItemButtonTemplate) : clic droit pour utiliser,
-- glisser, Maj-clic pour lier, vente chez le marchand, partage des piles, temps de recharge, objets de quête, nouveaux
-- objets... tout marche comme dans les sacs du jeu. Le numéro du sac est donné par un cadre porteur (SetID), comme
-- le prévoit le gabarit (GetBagID -> self:GetParent():GetID()), sans rien écrire dans les cases.
-- Les sacs du jeu s'ouvrent et se ferment comme d'habitude mais sont rangés dans un cadre caché (SetParent) :
-- on suit leurs ouvertures (hooksecurefunc sur OpenAllBags, ToggleAllBags, CloseAllBags...) sans rien remplacer.
-- Vérifié dans le code de Forever : Mainline/ContainerFrame.lua (ContainerFrameMixin:UpdateItems, méthodes des cases,
-- IsAnyBagOpen, CloseAllBags appelé par Échap), ContainerFrame.xml (ContainerFrame1..N enfants de
-- ContainerFrameContainer ; ContainerFrameCombinedBags), Camelot/BankFrame.lua (la banque a ses propres cases :
-- elle n'utilise pas ces cadres de sacs).
local ADDON, ns = ...

local BW = { buttons = {}, search = "" }
ns.BagWindow = BW

local floor, max, min = math.floor, math.max, math.min

local function api(name) return rawget(_G, name) end
local function db(key) return ns.db and ns.db[key] end

local function try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns:Debug("sacs (" .. where .. ") :", err) end
    return ok, err
end

local SLOT = 40           -- taille d'une case (le gabarit du jeu fait 37)
local NATIVE = 37
local GAP = 4
local PAD = 14
local FOOT_H = 36
local SECTION_GAP = 12
local LABEL_H = 18
local MIN_W = 360

local BACKPACK = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0
local REAGENT = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
local KEYRING = rawget(_G, "KEYRING_CONTAINER") or (Enum and Enum.BagIndex and Enum.BagIndex.Keyring) or -2

local function numBagSlots()
    local c = rawget(_G, "Constants")
    local n = c and c.InventoryConstants and c.InventoryConstants.NumBagSlots
    return tonumber(n) or rawget(_G, "NUM_BAG_SLOTS") or 4
end

local function containerSlots(bag)
    if bag == KEYRING then
        local size = api("GetKeyRingSize")
        if size then
            local ok, n = pcall(size)
            if ok and tonumber(n) then return tonumber(n) end
        end
    end
    local C = api("C_Container")
    if not (C and C.GetContainerNumSlots) then return 0 end
    local ok, n = pcall(C.GetContainerNumSlots, bag)
    return ok and tonumber(n) or 0
end

local function itemInfo(bag, slot)
    local C = api("C_Container")
    if not (C and C.GetContainerItemInfo) then return nil end
    local ok, info = pcall(C.GetContainerItemInfo, bag, slot)
    return ok and type(info) == "table" and info or nil
end

local function itemName(info)
    if not info then return nil end
    if type(info.itemName) == "string" and info.itemName ~= "" then return info.itemName end
    local C = api("C_Item")
    if info.itemID and C and C.GetItemNameByID then
        local ok, name = pcall(C.GetItemNameByID, info.itemID)
        if ok and type(name) == "string" then return name end
    end
    return nil
end

-- toutes les cases de ces sacs, à la suite : { { sac, case }, ... }
local function bagSlots(bags)
    local list = {}
    for _, bag in ipairs(bags) do
        for slot = 1, containerSlots(bag) do list[#list + 1] = { bag, slot } end
    end
    return list
end

---------------------------------------------------------------------------
-- Rangement par type (réglage bagWinGroup) : seul l'affichage change, les objets restent où ils sont dans les sacs
---------------------------------------------------------------------------
-- Sections, dans l'ordre d'affichage (titres écrits en capitales : string.upper ne met pas les accents en capitale)
local GROUPS = {
    { key = "quest",      label = "QUÊTE" },
    { key = "consumable", label = "CONSOMMABLES" },
    { key = "trade",      label = "ARTISANAT" },
    { key = "gear",       label = "ÉQUIPEMENT" },
    { key = "misc",       label = "DIVERS" },
    { key = "junk",       label = "POUBELLE" },
    { key = "empty",      label = "LIBRE" },
}
BW.GROUPS = GROUPS

-- classID de C_Item.GetItemInfoInstant (Enum.ItemClass) -> section ; le reste va dans Divers (sacs, carquois, clés,
-- montures, mascottes...). Vérifié dans le code de Forever : ItemConstantsDocumentation.lua (0 consommable, 1 sac,
-- 2 arme, 3 gemme, 4 armure, 5 composant, 6 projectile, 7 artisanat, 8 amélioration d'objet, 9 recette, 11 carquois,
-- 12 objet de quête, 13 clé, 15 divers, 19 profession).
local CLASS_GROUP = {
    [0] = "consumable", [6] = "consumable", [8] = "consumable",   -- flèches et balles, kits d'armure : consommés
    [2] = "gear", [4] = "gear",
    [3] = "trade", [5] = "trade", [7] = "trade", [9] = "trade", [19] = "trade",
    [12] = "quest",
}
local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

-- C_Item.GetItemInfoInstant : lit la base du jeu sans attendre le serveur. Vérifié dans le code de Forever
-- (ItemDocumentation.lua : itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID ; peut ne rien rendre).
local function itemClass(info)
    local C = api("C_Item")
    if not (C and C.GetItemInfoInstant) then return nil end
    local ok, _, _, _, _, _, classID, subClassID = pcall(C.GetItemInfoInstant, info.itemID or info.hyperlink)
    if not ok then return nil end
    return tonumber(classID), tonumber(subClassID)
end

-- objet de quête vu par le sac (aussi un objet « Divers » qui démarre une quête). Vérifié dans le code de Forever :
-- ContainerDocumentation.lua (ItemQuestInfo : isQuestItem, questID, isActive), comme ContainerFrameMixin:UpdateItems.
local function questInfo(bag, slot)
    local C = api("C_Container")
    if not (C and C.GetContainerItemQuestInfo) then return nil end
    local ok, q = pcall(C.GetContainerItemQuestInfo, bag, slot)
    return ok and type(q) == "table" and q or nil
end

-- ce que la vente automatique va vendre chez le marchand (Junk.lua, la liste de son aperçu) : ["sac:case"] = itemID
local function soldList()
    local sold = {}
    local J = ns.Junk
    if not (J and J.BuildList) then return sold end
    local ok, list = pcall(J.BuildList, J)
    if ok and type(list) == "table" then
        for _, e in ipairs(list) do
            if e.bag and e.slot then sold[e.bag .. ":" .. e.slot] = e.itemID end
        end
    end
    return sold
end

local function protected(itemID)
    local list = db("neverSell")
    return itemID ~= nil and type(list) == "table" and list[itemID] and true or false
end

-- clé de tri d'un nom : minuscules sans accents, pour que « Étoffe » se range avec les « e »
local FOLD = { ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
               ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ö"] = "o", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
               ["À"] = "a", ["Â"] = "a", ["Ç"] = "c", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Î"] = "i", ["Ô"] = "o" }
local function sortName(name)
    if type(name) ~= "string" then return "" end
    return (name:lower():gsub("\195[\128-\191]", FOLD))
end

local lastID, lastGroup = {}, {}   -- ["sac:case"] : un objet tenu en main (verrouillé) garde sa section

-- Section d'un objet. Dans l'ordre : ce que la vente automatique va vendre -> Poubelle ; objet de quête -> Quête ;
-- gris (sauf s'il est dans « Ne jamais vendre ») -> Poubelle ; sinon selon son type. Case vide -> Libre.
function BW:ItemGroup(bag, slot, info, sold)
    if not info then return "empty" end
    local key = bag .. ":" .. slot
    local classID, subClassID = itemClass(info)
    if info.isLocked and lastID[key] == info.itemID and lastGroup[key] then
        return lastGroup[key], classID, subClassID
    end
    local group
    if sold and info.itemID and sold[key] == info.itemID then
        group = "junk"
    else
        local q = questInfo(bag, slot)
        if classID == 12 or (q and (q.isQuestItem or q.questID)) then
            group = "quest"
        elseif info.quality == POOR and not protected(info.itemID) then
            group = "junk"
        else
            group = CLASS_GROUP[classID] or "misc"
        end
    end
    lastID[key], lastGroup[key] = info.itemID, group
    return group, classID, subClassID
end

-- dans une section : par sorte (potions ensemble, étoffes ensemble...), puis par nom ; les piles d'un même objet
-- se suivent. Les cases vides restent dans l'ordre des sacs.
local function before(a, b)
    if a.class ~= b.class then return a.class < b.class end
    if a.sub ~= b.sub then return a.sub < b.sub end
    if a.name ~= b.name then return a.name < b.name end
    if a.id ~= b.id then return a.id < b.id end
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[2] < b[2]
end

function BW:Groups(bags)
    local sold = soldList()
    local by = {}
    for _, g in ipairs(GROUPS) do by[g.key] = {} end
    for _, bag in ipairs(bags) do
        for slot = 1, containerSlots(bag) do
            local info = itemInfo(bag, slot)
            local group, classID, subClassID = self:ItemGroup(bag, slot, info, sold)
            local list = by[group] or by.misc
            list[#list + 1] = {
                bag, slot, class = classID or 99, sub = subClassID or 99,
                name = sortName(itemName(info)), id = info and info.itemID or 0,
            }
        end
    end
    local sections = {}
    for _, g in ipairs(GROUPS) do
        local list = by[g.key]
        if #list > 0 then
            if g.key ~= "empty" then table.sort(list, before) end
            sections[#sections + 1] = { label = g.label, group = g.key, slots = list }
        end
    end
    return sections
end

-- Sections de la fenêtre : { label, slots = { { sac, case }, ... } }
function BW:Sections()
    local main = {}
    for bag = BACKPACK, BACKPACK + numBagSlots() do
        if containerSlots(bag) > 0 then main[#main + 1] = bag end
    end
    local list
    if db("bagWinGroup") then
        list = self:Groups(main)
    else
        list = { { label = nil, slots = bagSlots(main) } }
    end
    if REAGENT > BACKPACK + numBagSlots() and containerSlots(REAGENT) > 0 then
        list[#list + 1] = { label = "COMPOSANTS", slots = bagSlots({ REAGENT }) }
    end
    -- trousseau de clés : seulement s'il contient au moins une clé
    local bar = api("C_ActionBar")
    local keyring = bar and bar.ShouldShowKeyring and select(2, pcall(bar.ShouldShowKeyring))
    if keyring == true then
        local n = containerSlots(KEYRING)
        for slot = 1, n do
            if itemInfo(KEYRING, slot) then
                list[#list + 1] = { label = "TROUSSEAU", slots = bagSlots({ KEYRING }) }
                break
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Cases
---------------------------------------------------------------------------
local frame, grid, searchBox, moneyText, freeText
local holders = {}        -- [sac] = cadre porteur (SetID(sac))
local labels = {}         -- étiquettes de section
BW.labels = labels
local layoutKey           -- disposition actuelle (sacs, tailles, colonnes) : on ne refait la grille que si elle change

local function holder(bag)
    local h = holders[bag]
    if not h then
        h = CreateFrame("Frame", nil, grid)
        h:SetID(bag)
        h:SetAllPoints(grid)
        holders[bag] = h
    end
    return h
end

local function buttonName(bag, slot)
    return "PlatyplusBag" .. (bag < 0 and ("K" .. -bag) or tostring(bag)) .. "Slot" .. slot
end

local function newButton(bag, slot)
    local parent = holder(bag)
    local ok, b = pcall(CreateFrame, "ItemButton", buttonName(bag, slot), parent, "ContainerFrameItemButtonTemplate")
    if not ok or not b then
        b = CreateFrame("Button", buttonName(bag, slot), parent, "ContainerFrameItemButtonTemplate")
    end
    b:SetID(slot)
    return b
end

local function getButton(bag, slot)
    BW.buttons[bag] = BW.buttons[bag] or {}
    local b = BW.buttons[bag][slot]
    if not b then
        b = newButton(bag, slot)
        BW.buttons[bag][slot] = b
    end
    return b
end

-- appel d'une méthode de la case si elle existe (le gabarit change d'une version du jeu à l'autre)
local function m(b, name, ...)
    local fn = b[name]
    if type(fn) == "function" then
        local ok, err = pcall(fn, b, ...)
        if not ok then ns:Debug("sacs (" .. name .. ") :", err) end
    end
end

local function g(name, ...)
    local fn = api(name)
    if type(fn) == "function" then pcall(fn, ...) end
end

local function matches(info)
    if BW.search == "" then return true end
    local name = itemName(info)
    return name ~= nil and name:lower():find(BW.search, 1, true) ~= nil
end

-- même suite d'appels que ContainerFrameMixin:UpdateItems du jeu, case par case
function BW:UpdateButton(b)
    local bag, slot = b:GetParent():GetID(), b:GetID()
    local info = itemInfo(bag, slot)
    local texture = info and info.iconFileID
    local quality = info and info.quality
    g("ClearItemButtonOverlay", b)
    m(b, "SetHasItem", texture)
    m(b, "SetItemButtonTexture", texture)
    m(b, "SyncAppearanceWithHasItem")
    g("SetItemButtonQuality", b, quality, info and info.hyperlink, false, info and info.isBound)
    g("SetItemButtonCount", b, info and info.stackCount)
    g("SetItemButtonDesaturated", b, info and info.isLocked)
    m(b, "UpdateExtended")
    local C = api("C_Container")
    if C and C.GetContainerItemQuestInfo then
        local ok, q = pcall(C.GetContainerItemQuestInfo, bag, slot)
        if ok and type(q) == "table" then m(b, "UpdateQuestItem", q.isQuestItem, q.questID, q.isActive) end
    end
    m(b, "UpdateNewItem", quality)
    m(b, "UpdateJunkItem", quality, info and info.hasNoValue)
    m(b, "UpdateItemContextMatching")
    m(b, "UpdateCooldown", texture)
    m(b, "SetReadable", info and info.isReadable)
    local tip = api("GameTooltip")
    m(b, "CheckUpdateTooltip", tip and tip:GetOwner())
    local found = matches(info)
    if b.SetMatchesSearch then m(b, "SetMatchesSearch", found) else b:SetAlpha(found and 1 or 0.25) end
    -- niveau d'objet et pièce « à vendre » (Tweaks.lua), comme sur les sacs du jeu
    local tweaks = ns.Tweaks
    if tweaks and tweaks.DecorateBagButton then
        local ok, err = pcall(tweaks.DecorateBagButton, tweaks, b)
        if not ok then ns:Debug("sacs (niveau d'objet) :", err) end
    end
end

function BW:UpdateAll()
    if not (frame and frame:IsShown()) then return end
    for bag, list in pairs(self.buttons) do
        for _, b in pairs(list) do
            if b:IsShown() then self:UpdateButton(b) end
        end
    end
    self:UpdateFooter()
end

function BW:UpdateSlot(bag, slot)
    local list = self.buttons[bag]
    local b = list and list[slot]
    if b and b:IsShown() then self:UpdateButton(b) end
end

function BW:UpdateCooldowns()
    for _, list in pairs(self.buttons) do
        for _, b in pairs(list) do
            if b:IsShown() then
                local info = itemInfo(b:GetParent():GetID(), b:GetID())
                m(b, "UpdateCooldown", info and info.iconFileID)
            end
        end
    end
end

function BW:UpdateFooter()
    if not frame then return end
    local money = api("GetMoney")
    moneyText:SetText(ns.W.FormatMoney(money and money() or 0))
    local free, total = 0, 0
    local C = api("C_Container")
    for bag = BACKPACK, BACKPACK + numBagSlots() do
        local n = containerSlots(bag)
        total = total + n
        if n > 0 and C and C.GetContainerNumFreeSlots then
            local ok, f = pcall(C.GetContainerNumFreeSlots, bag)
            if ok then free = free + (tonumber(f) or 0) end
        end
    end
    local color = free == 0 and "bad" or (free <= 3 and "gold" or "text")
    freeText:SetText(ns.W.Color(color, free) .. ns.W.Color("dim", ns.Tf(" / %d places libres", total)))
end

---------------------------------------------------------------------------
-- Grille
---------------------------------------------------------------------------
local function columns()
    return max(4, min(24, floor(tonumber(db("bagWinColumns")) or 10)))
end

-- disposition : colonnes, puis chaque section et ses cases dans l'ordre (rangé par type, elle change avec le contenu)
local function signature(sections)
    local parts = { columns() }
    for _, s in ipairs(sections) do
        parts[#parts + 1] = "|" .. (s.label or "")
        for _, p in ipairs(s.slots) do parts[#parts + 1] = p[1] .. ":" .. p[2] end
    end
    return table.concat(parts, ",")
end

local function label(i)
    local l = labels[i]
    if not l then
        l = ns.W.Text(grid, "GameFontNormal", ns.W.C.dim, "OVERLAY", 12)
        labels[i] = l
    end
    l:Show()
    return l
end

function BW:Layout(force)
    if not frame then return end
    local sections = self:Sections()
    local key = signature(sections)
    if key == layoutKey and not force then return end
    layoutKey = key
    for _, list in pairs(self.buttons) do
        for _, b in pairs(list) do b:Hide() end
    end
    for _, l in ipairs(labels) do l:Hide() end

    -- Les sections sont posées en étagères, de gauche à droite : une petite section se met à côté de la précédente
    -- s'il reste la place (une colonne vide entre les deux), sinon elle commence une nouvelle étagère.
    -- Exemple à 10 cases par ligne : Quête (3 objets) et Consommables (6) tiennent sur la même ligne (3 + 1 + 6).
    local cols = columns()
    local step = SLOT + GAP
    local bs = SLOT / NATIVE
    local y, x, shelfH, shelfLabel = 0, 0, 0, nil   -- haut de l'étagère, prochaine colonne libre, sa hauteur
    local nLabel = 0
    for _, s in ipairs(sections) do
        local n = #s.slots
        if n > 0 then
            local l, w = nil, min(n, cols)
            if s.label then
                nLabel = nLabel + 1
                l = label(nLabel)
                l:SetText(ns.T(s.label))
                local lw = tonumber(l:GetStringWidth()) or 0
                w = max(w, min(cols, math.ceil((lw + GAP) / step)))   -- le titre tient au-dessus de sa section
            end
            local labeled = l ~= nil
            local startX = x > 0 and x + 1 or 0
            if x > 0 and (startX + w > cols or labeled ~= shelfLabel) then
                y = y + shelfH + SECTION_GAP
                x, startX, shelfH = 0, 0, 0
            end
            shelfLabel = labeled
            local top = y + (labeled and LABEL_H or 0)
            if l then
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", grid, "TOPLEFT", startX * step, -y)
            end
            local perRow = min(n, cols)
            for i, p in ipairs(s.slots) do
                local b = getButton(p[1], p[2])
                local col, row = startX + (i - 1) % perRow, floor((i - 1) / perRow)
                b:SetScale(bs)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", grid, "TOPLEFT", (col * step) / bs, -(top + row * step) / bs)
                b:Show()
            end
            local rows = math.ceil(n / perRow)
            shelfH = max(shelfH, (top - y) + rows * step - GAP)
            x = startX + w
        end
    end
    y = y + shelfH
    local gridW = cols * step - GAP
    local w = max(MIN_W, gridW + 2 * PAD)
    grid:SetSize(gridW, max(y, SLOT))
    frame:SetSize(w, ns.Win.HEAD_H + 12 + max(y, SLOT) + FOOT_H + 8)
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local function setSearch(text)
    BW.search = (text or ""):lower()
    BW:UpdateAll()
end

local function closeBags()
    local close = api("CloseAllBags")
    if close then try("fermeture", close) end
    if frame and frame:IsShown() then
        frame:Hide()
        ns.Win.PlayKit("IG_BACKPACK_CLOSE")
    end
end
BW.Close = closeBags

local function build()
    local W, C, Win = ns.W, ns.W.C, ns.Win
    frame = Win.Create("PlatyplusBagWindow", {
        title = "Sacs", width = MIN_W, height = 300, posKey = "bagWinPos", scaleKey = "bagWinScale",
        corner = "BOTTOMRIGHT", default = { "BOTTOMRIGHT", "BOTTOMRIGHT", -60, 120 },
        onClose = closeBags,
    })
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", frame.head, "LEFT", PAD + 2, 0)

    -- Trier
    local sort = Win.FlatButton(frame.head, "Trier", function()
        if ns.Misc and ns.Misc.SortBags then ns.Misc:SortBags() end
    end)
    sort:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
    frame.sort = sort

    -- recherche
    local box = CreateFrame("EditBox", nil, frame.head)
    box:SetAutoFocus(false)
    box:SetSize(150, 26)
    box:SetPoint("RIGHT", sort, "LEFT", -8, 0)
    box:SetFont(W.Font(), 13, "")
    box:SetTextInsets(10, 10, 0, 0)
    if box.SetMaxLetters then box:SetMaxLetters(40) end
    local bg = W.Round(box, "BACKGROUND", 0, 7)
    bg:SetColor(C.field, 1)
    local stroke = W.Stroke(box, "BORDER", 0, 7)
    stroke:SetColor(C.white, 0.06)
    local placeholder = W.Text(box, "GameFontDisable", C.dim, "OVERLAY", 13)
    placeholder:SetPoint("LEFT", box, "LEFT", 10, 0)
    placeholder:SetText(ns.T("Chercher…"))
    box:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        placeholder:SetShown(t == "")
        setSearch(t)
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function() stroke:SetColor(C.accent, 0.9) end)
    box:SetScript("OnEditFocusLost", function() stroke:SetColor(C.white, 0.06) end)
    searchBox = box

    grid = CreateFrame("Frame", nil, frame)
    grid:SetPoint("TOP", frame, "TOP", 0, -(Win.HEAD_H + 12))
    grid:SetSize(100, 100)

    moneyText = W.Text(frame, "GameFontHighlight", C.text, "OVERLAY", 14)
    moneyText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 2, 14)
    freeText = W.Text(frame, "GameFontHighlight", C.text, "OVERLAY", 13)
    freeText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 2, 14)

    frame:SetScript("OnShow", function()
        BW:Layout(true)
        BW:UpdateAll()
    end)
    frame:SetScript("OnHide", function()
        if searchBox:GetText() ~= "" then searchBox:SetText("") end
        searchBox:ClearFocus()
    end)
    BW.frame, BW.grid, BW.searchBox, BW.moneyText, BW.freeText = frame, grid, searchBox, moneyText, freeText
    return frame
end

---------------------------------------------------------------------------
-- Sacs du jeu rangés, ouverture suivie
---------------------------------------------------------------------------
local hidden, stash = nil, {}
BW.broken = false

local function enabled()
    return db("bagWindow") and not BW.broken
end

local function blizzardFrames()
    local list = {}
    local container = api("ContainerFrameContainer")
    if container then
        list[#list + 1] = container
    else
        for i = 1, 13 do
            local f = api("ContainerFrame" .. i)
            if f then list[#list + 1] = f end
        end
    end
    local combined = api("ContainerFrameCombinedBags")
    if combined then list[#list + 1] = combined end
    return list
end

function BW:HideBlizzard()
    if not hidden then
        hidden = CreateFrame("Frame")
        hidden:Hide()
    end
    for _, f in ipairs(blizzardFrames()) do
        if not stash[f] then
            stash[f] = f:GetParent()
            f:SetParent(hidden)
        end
    end
end

function BW:RestoreBlizzard()
    for f, parent in pairs(stash) do
        f:SetParent(parent)
        stash[f] = nil
    end
end

local function anyBagOpen()
    local any = api("IsAnyBagOpen")
    if any then
        local ok, open = pcall(any)
        if ok then return open and true or false end
    end
    return false
end

function BW:Sync()
    if not enabled() then
        if frame then frame:Hide() end
        return
    end
    if anyBagOpen() then
        if not frame then
            local ok = try("construction", build)
            if not ok then
                self.broken = true
                self:Apply()
                ns:Print("la fenêtre des sacs n'a pas pu s'ouvrir : sacs du jeu gardés")
                return
            end
        end
        -- les sacs du jeu sont rangés : leur son d'ouverture ne joue plus, on le joue ici
        if not frame:IsShown() then
            ns.Win.Open(frame)
            ns.Win.PlayKit("IG_BACKPACK_OPEN")
        end
    elseif frame and frame:IsShown() then
        frame:Hide()
        ns.Win.PlayKit("IG_BACKPACK_CLOSE")
    end
end

local pending = false
local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        BW:Sync()
    end)
end
BW.Schedule = schedule

function BW:Apply()
    if enabled() then
        self:HideBlizzard()
        schedule()
    else
        self:RestoreBlizzard()
        if frame then frame:Hide() end
    end
end

function BW:ApplyLook()
    if not frame then return end
    ns.Win.Place(frame)
    self:Layout(true)
    if frame:IsShown() then self:UpdateAll() end
end

function BW:ResetPosition()
    ns.db.bagWinPos = {}
    if frame then ns.Win.Reset(frame) end
end

-- mises à jour regroupées à l'image suivante (les rafales de BAG_UPDATE arrivent par paquets)
local dirty = false
local function refreshSoon()
    if dirty then return end
    dirty = true
    C_Timer.After(0, function()
        dirty = false
        if frame and frame:IsShown() then
            BW:Layout()
            BW:UpdateAll()
        end
    end)
end

local events = CreateFrame("Frame")
local EVENTS = { "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY",
                 "QUEST_ACCEPTED", "UNIT_QUEST_LOG_CHANGED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_NEW_ITEMS_UPDATED",
                 "INVENTORY_SEARCH_UPDATE", "GET_ITEM_INFO_RECEIVED" }
events:SetScript("OnEvent", function(_, event, a, b)
    if not (frame and frame:IsShown()) then return end
    if event == "ITEM_LOCK_CHANGED" then
        if a and b then BW:UpdateSlot(a, b) else refreshSoon() end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        BW:UpdateCooldowns()
    elseif event == "PLAYER_MONEY" then
        BW:UpdateFooter()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- rangé par type : la vente automatique a besoin des infos de l'objet pour dire s'il part à la poubelle
        if BW.search ~= "" or db("bagWinGroup") then refreshSoon() end
    else
        refreshSoon()
    end
end)

function BW:Init()
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    if api("hooksecurefunc") then
        for _, name in ipairs({ "OpenAllBags", "CloseAllBags", "ToggleAllBags", "ToggleBackpack", "OpenBackpack",
                                "CloseBackpack", "ToggleBag", "OpenBag", "CloseBag" }) do
            if type(api(name)) == "function" then hooksecurefunc(name, schedule) end
        end
    end
    -- filet : un sac fermé par un chemin qu'on ne suit pas
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.5, function()
            if frame and frame:IsShown() and enabled() and not anyBagOpen() then frame:Hide() end
        end)
    end
    ns:OnChange("bagWindow", function() BW:Apply() end)
    ns:OnChange("bagWinScale", function() BW:ApplyLook() end)
    ns:OnChange("bagWinColumns", function() BW:ApplyLook() end)
    ns:OnChange("bagWinGroup", function() BW:ApplyLook() end)
    -- ce que la vente automatique va vendre change : la section Poubelle aussi
    for _, key in ipairs({ "sellJunk", "sellGear", "neverSell", "alwaysSell", "gearMaxQuality", "gearIncludeBoE",
                           "gearMargin", "gearMaxPerVisit", "keepUnknownTransmog" }) do
        ns:OnChange(key, function() if db("bagWinGroup") then refreshSoon() end end)
    end
    try("application", function() BW:Apply() end)
end

function BW:Status()
    local lines = {}
    lines[1] = "sacs : " .. (db("bagWindow") and (self.broken and "en panne (sacs du jeu gardés)" or "fenêtre Platyplus") or "sacs du jeu")
    local n = 0
    for _, list in pairs(self.buttons) do for _ in pairs(list) do n = n + 1 end end
    lines[2] = "cases créées : " .. n
    lines[3] = "rangement : " .. (db("bagWinGroup") and "par type" or "sacs à la suite")
    return lines
end
