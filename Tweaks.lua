-- Platyplus : petits plus (QoL)
--  1. hideErrors     : masque les messages d'erreur rouges (UI_ERROR_MESSAGE) ; les messages d'info restent
--  2. autoOpenMail   : à l'ouverture de la boîte aux lettres, clique le bouton Blizzard « Tout ouvrir »
--                      (Maj tenu à l'ouverture = rien ; un seul essai par ouverture)
--  3. charIlvl       : niveau d'objet sur chaque emplacement de la fiche du personnage + moyenne portée
--  4. bagIlvl        : niveau d'objet des armes / armures dans les sacs + pièce d'or sur ce que Platyplus vendrait
--  5. durabilityWarn : une alerte (flux + chat) quand l'équipement passe à « presque cassé » ou « cassé »
--  6. hideXpBar      : masque les barres d'expérience et de réputation du bas de l'écran
--
-- Optimisation : uniquement des événements et des hooks, aucun OnUpdate ni ticker. Un hook n'est posé
-- qu'au premier besoin (option active) et vérifie l'option à chaque appel ; les textes sont créés une
-- seule fois par bouton puis réutilisés. Les rafales sont regroupées (C_Timer.After) et la liste de
-- vente n'est calculée qu'une fois par rafraîchissement des sacs, quel que soit le nombre de boutons.
-- Les cadres et fonctions Blizzard sont lus avec rawget : absents = fonction sans effet (nouvel essai à
-- chaque ADDON_LOADED tant que c'est utile), jamais d'erreur Lua.
local ADDON, ns = ...

local Tweaks = {}
ns.Tweaks = Tweaks

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------

-- globale du jeu qui peut manquer (cadre Blizzard, fonction absente de ce client) : nil sans erreur
local function api(name)
    return rawget(_G, name)
end

-- appelle la fonction globale si elle existe (sinon ne renvoie rien)
local function call(name, ...)
    local fn = rawget(_G, name)
    if type(fn) == "function" then return fn(...) end
end

local function enumValue(group, name, default)
    local enum = api("Enum")
    local g = enum and enum[group]
    local v = g and g[name]
    if type(v) == "number" then return v end
    return default
end

local function hex(c, fallback)
    c = c or fallback
    return string.format("%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

---------------------------------------------------------------------------
-- Constantes
---------------------------------------------------------------------------
local CLASS_WEAPON = enumValue("ItemClass", "Weapon", 2)
local CLASS_ARMOR  = enumValue("ItemClass", "Armor", 4)

local ERROR_EVENT   = "UI_ERROR_MESSAGE"
local MAIL_WAIT     = 0.3    -- après MAIL_INBOX_UPDATE, avant de cliquer « Tout ouvrir »
local MAIL_FALLBACK = 1.5    -- si MAIL_INBOX_UPDATE n'arrive pas, on essaie quand même une fois
local LOGIN_GRACE   = 5      -- durabilité : après l'entrée en jeu, on mémorise l'état sans alerter
local MAX_ERRORS    = 5      -- une fonction qui plante autant de fois est coupée pour la session
local ALERT_SLOTS   = 11     -- GetInventoryAlertStatus(1..11)
local GOLD_ICON     = "Interface\\MoneyFrame\\UI-GoldIcon"
local REPAIR_ICON   = "Interface\\Icons\\Trade_BlackSmithing"

local THEME = ns.THEME or {}
local DIM  = hex(THEME.dim,  { 0.60, 0.63, 0.70 })
local GOLD = hex(THEME.gold, { 1.00, 0.82, 0.20 })

-- emplacements de la fiche qui reçoivent un niveau d'objet (chemise, tabard et munitions : rien d'utile)
local CHAR_SLOT_NAMES = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
    "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}
local CHAR_SLOT = {}
for _, name in ipairs(CHAR_SLOT_NAMES) do CHAR_SLOT[name] = true end

-- emplacements comptés dans la moyenne maison (si GetAverageItemLevel manque) : tout sauf chemise (4) et tabard (19)
local AVG_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local BAG_FRAME_NAMES = {
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
    "ContainerFrame5", "ContainerFrame6", "ContainerFrame7", "ContainerFrameCombinedBags",
}

-- armes / armures sans niveau utile
local NO_LEVEL_LOC = { [""] = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
    INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true }

-- réglages qui changent ce que Platyplus vendrait (=> pièces des sacs à revoir)
local JUNK_KEYS = { "sellJunk", "sellGear", "gearMaxQuality", "gearMargin", "gearIncludeBoE",
    "keepUnknownTransmog", "gearMaxPerVisit", "neverSell", "alwaysSell" }

local LABELS = {
    hideErrors = "masquer les erreurs", autoOpenMail = "ouverture du courrier",
    charIlvl = "niveau d'objet (fiche)", bagIlvl = "niveau d'objet (sacs)",
    durabilityWarn = "alerte de durabilité",
    hideXpBar = "barre d'expérience masquée",
}

---------------------------------------------------------------------------
-- Garde-fou : une fonction qui plante ne casse jamais le code de Blizzard qu'elle accompagne
---------------------------------------------------------------------------
local errorCount, broken = {}, {}

local function guarded(name, fn)
    return function(...)
        if broken[name] then return end
        local ok, err = pcall(fn, ...)
        if ok then return end
        errorCount[name] = (errorCount[name] or 0) + 1
        ns:Debug(name .. " : " .. tostring(err))
        if errorCount[name] >= MAX_ERRORS then
            broken[name] = true
            ns:Print(ns.Tf("« %s » coupé pour cette session après des erreurs répétées", ns.T(LABELS[name] or name)))
        end
    end
end

-- regroupe les rafales : fn n'est appelée qu'une fois par clé et par délai
local scheduled = {}
local function schedule(key, delay, fn)
    if scheduled[key] then return end
    scheduled[key] = true
    C_Timer.After(delay, function()
        scheduled[key] = nil
        fn()
    end)
end

---------------------------------------------------------------------------
-- Événements (un seul cadre ; un événement n'est enregistré que s'il sert)
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
local registered = {}

local function setEvent(event, want)
    want = want and true or false
    if (registered[event] or false) == want then return end
    if want then
        if pcall(frame.RegisterEvent, frame, event) then
            registered[event] = true
        else
            ns:Debug("événement inconnu de ce client :", event)
        end
    else
        pcall(frame.UnregisterEvent, frame, event)
        registered[event] = false
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if fn then fn(...) end
end)

---------------------------------------------------------------------------
-- Niveaux d'objet
---------------------------------------------------------------------------

-- niveau d'objet d'un lien ; nil si inconnu (données pas encore chargées) ou sans intérêt (<= 1)
local function itemLevel(link)
    local C = api("C_Item")
    if not (link and C) then return nil end
    local level
    if C.GetDetailedItemLevelInfo then level = C.GetDetailedItemLevelInfo(link) end
    if (type(level) ~= "number" or level <= 0) and C.GetItemInfo then
        level = select(4, C.GetItemInfo(link))
    end
    if type(level) ~= "number" or level <= 1 then return nil end
    return math.floor(level + 0.5)
end

-- armes et armures seulement ; mémorisé par lien (cache vidé s'il grossit trop)
local levelCache, levelCacheSize = {}, 0
local LEVEL_CACHE_MAX = 600

local function gearLevel(link)
    local cached = levelCache[link]
    if cached ~= nil then return cached or nil end
    local C = api("C_Item")
    if not (C and C.GetItemInfoInstant) then return nil end
    local _, _, _, equipLoc, _, classID = C.GetItemInfoInstant(link)
    local level = false
    if (classID == CLASS_WEAPON or classID == CLASS_ARMOR) and not NO_LEVEL_LOC[equipLoc or ""] then
        level = itemLevel(link)
        if not level then return nil end      -- pas encore connu : on réessaiera au prochain passage
    end
    if levelCacheSize >= LEVEL_CACHE_MAX then
        levelCache, levelCacheSize = {}, 0
    end
    levelCache[link] = level
    levelCacheSize = levelCacheSize + 1
    return level or nil
end

local function qualityColor(quality)
    local colors = api("ITEM_QUALITY_COLORS")
    local c = type(quality) == "number" and colors and colors[quality]
    if c and c.r then return c.r, c.g, c.b end
    return 1, 1, 1
end

---------------------------------------------------------------------------
-- Textes posés sur les boutons (créés une fois, réutilisés)
---------------------------------------------------------------------------
local overlays = {}   -- [bouton] = { frame, level (FontString), coin (Texture, créée au besoin), bag }
local numberFont

local function fontPath()
    if numberFont then return numberFont end
    local font = api("NumberFontNormal")
    local path = font and font.GetFont and font:GetFont()
    numberFont = path or api("STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF"
    return numberFont
end

-- cadre fils du bouton, au-dessus de son icône et de son temps de recharge
local function overlayFor(button, isBag)
    local o = overlays[button]
    if o then return o end
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints(button)
    if button.GetFrameLevel then holder:SetFrameLevel(button:GetFrameLevel() + 3) end

    local level = holder:CreateFontString(nil, "OVERLAY")
    level:SetFont(fontPath(), isBag and 11 or 12, "OUTLINE")
    if isBag then
        level:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 2, 2)
        level:SetJustifyH("LEFT")
    else
        level:SetPoint("BOTTOM", holder, "BOTTOM", 0, 2)
        level:SetJustifyH("CENTER")
    end
    level:Hide()

    o = { frame = holder, level = level, bag = isBag and true or false }
    overlays[button] = o
    return o
end

local function setLevel(o, level, quality)
    if not level then
        o.level:Hide()
        return
    end
    o.level:SetText(tostring(level))
    o.level:SetTextColor(qualityColor(quality))
    o.level:Show()
end

local function setCoin(o, shown)
    if shown then
        if not o.coin then
            local coin = o.frame:CreateTexture(nil, "OVERLAY")
            coin:SetTexture(GOLD_ICON)
            coin:SetSize(12, 12)
            coin:SetPoint("TOPLEFT", o.frame, "TOPLEFT", 2, -2)
            o.coin = coin
        end
        o.coin:Show()
    elseif o.coin then
        o.coin:Hide()
    end
end

---------------------------------------------------------------------------
-- 1. Messages d'erreur rouges
---------------------------------------------------------------------------
local errorsMuted = false   -- true si c'est nous qui avons retiré l'événement du cadre
local errorsFound = false   -- UIErrorsFrame trouvé au moins une fois

local function applyErrors()
    local f = api("UIErrorsFrame")
    if not (f and f.RegisterEvent and f.UnregisterEvent) then return false end
    errorsFound = true
    if ns.db.hideErrors then
        local listening = true
        if f.IsEventRegistered then
            local ok, isRegistered = pcall(f.IsEventRegistered, f, ERROR_EVENT)
            if ok then listening = isRegistered and true or false end
        end
        if listening and pcall(f.UnregisterEvent, f, ERROR_EVENT) then
            errorsMuted = true
        end
    elseif errorsMuted then
        pcall(f.RegisterEvent, f, ERROR_EVENT)
        errorsMuted = false
    end
    return true
end

---------------------------------------------------------------------------
-- 2. Courrier : « Tout ouvrir » à l'ouverture
---------------------------------------------------------------------------
local mail = { hooked = false, generation = 0, pending = false, scheduled = nil }

local function openAllButton()
    local button = api("OpenAllMail")
    if not button then
        local inbox = api("InboxFrame")
        button = inbox and inbox.OpenAllMail
    end
    if not button then
        local mailFrame = api("MailFrame")
        button = mailFrame and mailFrame.OpenAllMail
    end
    return button
end

-- annule l'essai en cours (les minuteries déjà lancées deviennent caduques)
local function stopMail()
    mail.pending = false
    mail.generation = mail.generation + 1
    setEvent("MAIL_INBOX_UPDATE", false)
end

local function tryOpenAll(generation)
    if generation ~= mail.generation or not mail.pending then return end
    stopMail()                                   -- un seul essai par ouverture de la boîte
    if not ns.db.autoOpenMail then return end
    local mailFrame = api("MailFrame")
    if not (mailFrame and mailFrame:IsShown()) then return end
    local button = openAllButton()
    if not (button and button.Click) then
        ns:Debug("courrier : bouton « Tout ouvrir » introuvable")
        return
    end
    if button.IsVisible and not button:IsVisible() then return end   -- onglet « Envoyer », manette...
    if button.IsEnabled and not button:IsEnabled() then return end   -- ouverture déjà en cours
    local count = call("GetInboxNumItems")
    if count ~= nil and (tonumber(count) or 0) <= 0 then return end  -- boîte vide
    ns:Debug("courrier : Tout ouvrir")
    button:Click()
end
local tryOpenAllSafe = guarded("autoOpenMail", tryOpenAll)

local function onMailShow()
    stopMail()
    if not ns.db.autoOpenMail then return end
    if IsShiftKeyDown() then
        ns:Debug("Maj tenu : courrier non ouvert automatiquement")
        return
    end
    mail.pending = true
    local generation = mail.generation
    setEvent("MAIL_INBOX_UPDATE", true)
    C_Timer.After(MAIL_FALLBACK, function() tryOpenAllSafe(generation) end)
end

handlers.MAIL_INBOX_UPDATE = guarded("autoOpenMail", function()
    if not mail.pending or mail.scheduled == mail.generation then return end
    local generation = mail.generation
    mail.scheduled = generation
    C_Timer.After(MAIL_WAIT, function() tryOpenAllSafe(generation) end)
end)

local function installMail()
    if mail.hooked then return true end
    local mailFrame = api("MailFrame")
    if not (mailFrame and mailFrame.HookScript) then return false end
    mailFrame:HookScript("OnShow", guarded("autoOpenMail", onMailShow))
    mailFrame:HookScript("OnHide", guarded("autoOpenMail", stopMail))
    mail.hooked = true
    return true
end

local function applyMail()
    if ns.db.autoOpenMail then
        installMail()
    else
        stopMail()
    end
end

---------------------------------------------------------------------------
-- 3. Fiche du personnage : niveau d'objet par emplacement + moyenne
---------------------------------------------------------------------------
local char = { hooked = false }
local avg       -- { frame, text } : moyenne affichée sur la fiche

local function inventoryQuality(slot, link)
    local quality = call("GetInventoryItemQuality", "player", slot)
    if type(quality) ~= "number" then
        local C = api("C_Item")
        if C and C.GetItemInfo then quality = select(3, C.GetItemInfo(link)) end
    end
    return quality
end

-- met à jour (ou cache) le texte d'un emplacement de la fiche ; ignore tout autre bouton
local function updateCharSlot(button)
    local name = button and button.GetName and button:GetName()
    if not (name and CHAR_SLOT[name]) then return false end
    local o = overlays[button]
    local level, link
    if ns.db.charIlvl then
        local slot = button:GetID()
        link = slot and call("GetInventoryItemLink", "player", slot)
        level = link and itemLevel(link)
        if level and not o then o = overlayFor(button, false) end
        if level then
            setLevel(o, level, inventoryQuality(slot, link))
            return true
        end
    end
    if o then setLevel(o, nil) end
    return true
end

-- moyenne de l'équipement porté : GetAverageItemLevel (2e valeur = porté), sinon calcul maison
local function averageItemLevel()
    local fn = api("GetAverageItemLevel")
    if type(fn) == "function" then
        local ok, overall, equipped = pcall(fn)
        local value = ok and (tonumber(equipped) or tonumber(overall))
        if value and value > 0 then return value end
    end
    local sum, count = 0, 0
    for _, slot in ipairs(AVG_SLOTS) do
        local link = call("GetInventoryItemLink", "player", slot)
        local level = link and itemLevel(link)
        if level then
            sum, count = sum + level, count + 1
        end
    end
    if count == 0 then return nil end
    return sum / count
end

local function ensureAverage()
    if avg then return avg end
    local parent = api("PaperDollFrame") or api("CharacterFrame")
    if not (parent and parent.CreateFontString) then return nil end
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(220, 16)
    if parent.GetFrameLevel then holder:SetFrameLevel(parent:GetFrameLevel() + 10) end
    local anchor = api("CharacterLevelText")
    if anchor and anchor.GetObjectType then
        holder:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    else
        holder:SetPoint("TOP", parent, "TOP", 0, -56)
    end
    local text = holder:CreateFontString(nil, "OVERLAY")
    text:SetFont(api("STANDARD_TEXT_FONT") or fontPath(), 12, "OUTLINE")
    text:SetPoint("CENTER", holder, "CENTER", 0, 0)
    avg = { frame = holder, text = text }
    return avg
end

local function refreshAverage()
    if not ns.db.charIlvl then
        if avg then avg.frame:Hide() end
        return
    end
    local value = averageItemLevel()
    local a = (value or avg) and ensureAverage()
    if not a then return end
    if not value then
        a.frame:Hide()
        return
    end
    a.text:SetText(ns.Tf("|cff%sNiveau d'objet moyen|r  |cff%s%d|r", DIM, GOLD, math.floor(value + 0.0001)))
    a.frame:Show()
end
local refreshAverageSafe = guarded("charIlvl", refreshAverage)

local function refreshChar()
    for _, name in ipairs(CHAR_SLOT_NAMES) do
        local button = api(name)
        if button then updateCharSlot(button) end
    end
    refreshAverage()
end
local refreshCharSafe = guarded("charIlvl", refreshChar)

-- après PaperDollItemSlotButton_Update(self) de Blizzard
local onSlotUpdate = guarded("charIlvl", function(button)
    if not ns.db.charIlvl then return end
    if updateCharSlot(button) then
        schedule("average", 0, refreshAverageSafe)   -- toutes les cases d'un coup => une seule moyenne
    end
end)

local function installChar()
    if char.hooked then return true end
    if type(api("PaperDollItemSlotButton_Update")) ~= "function" then return false end
    if pcall(hooksecurefunc, "PaperDollItemSlotButton_Update", onSlotUpdate) then
        char.hooked = true
    end
    return char.hooked
end

local function applyChar()
    if ns.db.charIlvl then installChar() end
    schedule("char", 0, refreshCharSafe)          -- affiche, ou cache tout si l'option est coupée
end

---------------------------------------------------------------------------
-- 4. Sacs : niveau d'objet + pièce sur ce que Platyplus vendrait
---------------------------------------------------------------------------
local bags = { frames = {}, hooked = {}, seen = {}, unhooked = 0, missing = true, updateAllHooked = false }
local sellCache     -- [bag * 1000 + slot] = true ; partagé par tous les sacs mis à jour dans la même image

local function clearSellCache() sellCache = nil end

-- un seul appel à ns.Junk:BuildList() par rafraîchissement, quel que soit le nombre de sacs / boutons
local function sellSet()
    if sellCache then return sellCache end
    local set = {}
    local junk = ns.Junk
    if junk and junk.BuildList then
        local ok, list = pcall(junk.BuildList, junk)
        if ok and type(list) == "table" then
            for _, entry in ipairs(list) do
                if entry.bag and entry.slot then set[entry.bag * 1000 + entry.slot] = true end
            end
        elseif not ok then
            ns:Debug("liste de vente indisponible :", tostring(list))
        end
    end
    sellCache = set
    C_Timer.After(0, clearSellCache)
    return set
end

local function bagOf(button)
    if type(button.GetBagID) == "function" then return button:GetBagID() end
    local parent = button.GetParent and button:GetParent()
    return parent and parent.GetID and parent:GetID()
end

-- la pièce de Blizzard (gris chez un marchand) est au même endroit : on ne double pas
local function blizzardCoinShown(button)
    local junkIcon = button.JunkIcon
    return junkIcon and junkIcon.IsShown and junkIcon:IsShown() and true or false
end

local function decorateButton(button, set)
    local bag, slot = bagOf(button), button:GetID()
    local container = api("C_Container")
    local info = bag and slot and container and container.GetContainerItemInfo
        and container.GetContainerItemInfo(bag, slot)
    local link = type(info) == "table" and info.hyperlink or nil
    local level = link and gearLevel(link) or nil
    local sell = (link and set[bag * 1000 + slot] and not blizzardCoinShown(button)) and true or false
    local o = overlays[button]
    if not o then
        if not level and not sell then return end   -- rien à montrer : aucun texte créé
        o = overlayFor(button, true)
    end
    setLevel(o, level, info and info.quality)
    setCoin(o, sell)
end

-- pour la fenêtre de sacs Platyplus (BagWindow.lua), dont les cases ne sont pas celles du jeu
function Tweaks:DecorateBagButton(button)
    if not ns.db.bagIlvl then return end
    decorateButton(button, sellSet())
end

local function decorateFrame(bagFrame)
    if not ns.db.bagIlvl then return end
    local set = sellSet()
    for _, button in bagFrame:EnumerateValidItems() do
        decorateButton(button, set)
    end
end

-- après bagFrame:UpdateItems() de Blizzard
local onUpdateItems = guarded("bagIlvl", decorateFrame)

local function refreshBags(onlyUnhooked)
    if not ns.db.bagIlvl then return end
    for _, bagFrame in ipairs(bags.frames) do
        if (not onlyUnhooked or not bags.hooked[bagFrame]) and bagFrame:IsShown() then
            decorateFrame(bagFrame)
        end
    end
end
local refreshBagsSafe = guarded("bagIlvl", function() refreshBags(false) end)
local refreshUnhookedSafe = guarded("bagIlvl", function() refreshBags(true) end)

-- filet : un sac sans UpdateItems accrochable est revu après ContainerFrame_UpdateAll
-- (et après BAG_UPDATE_DELAYED, enregistré seulement dans ce cas)
local onUpdateAll = guarded("bagIlvl", function()
    if ns.db.bagIlvl and bags.unhooked > 0 then
        schedule("bagsUnhooked", 0, refreshUnhookedSafe)
    end
end)
handlers.BAG_UPDATE_DELAYED = onUpdateAll

local function hideBagOverlays()
    for _, o in pairs(overlays) do
        if o.bag then
            o.level:Hide()
            if o.coin then o.coin:Hide() end
        end
    end
end

-- accroche chaque cadre de sac existant (une fois) ; bags.missing = un nom n'existe pas encore
local function installBags()
    local missing = false
    for _, name in ipairs(BAG_FRAME_NAMES) do
        if not bags.seen[name] then
            local bagFrame = api(name)
            if not bagFrame then
                missing = true
            else
                bags.seen[name] = true
                if type(bagFrame.EnumerateValidItems) == "function" then
                    bags.frames[#bags.frames + 1] = bagFrame
                    if type(bagFrame.UpdateItems) == "function"
                        and pcall(hooksecurefunc, bagFrame, "UpdateItems", onUpdateItems) then
                        bags.hooked[bagFrame] = true
                    else
                        bags.unhooked = bags.unhooked + 1
                    end
                else
                    ns:Debug(name .. " : pas de EnumerateValidItems, ignoré")
                end
            end
        end
    end
    if not bags.updateAllHooked and type(api("ContainerFrame_UpdateAll")) == "function" then
        bags.updateAllHooked = pcall(hooksecurefunc, "ContainerFrame_UpdateAll", onUpdateAll) and true or false
    end
    bags.missing = missing
end

local function applyBags()
    if ns.db.bagIlvl then
        installBags()
        schedule("bags", 0.05, refreshBagsSafe)
    else
        hideBagOverlays()
    end
end

local onJunkRulesChanged = guarded("bagIlvl", function()
    if ns.db.bagIlvl then schedule("bags", 0.1, refreshBagsSafe) end
end)

---------------------------------------------------------------------------
-- 5. Durabilité
---------------------------------------------------------------------------
-- state : nil = pas encore mémorisé ; sinon pire état (0 bon, 1 presque cassé, 2 cassé)
-- ready : la période de grâce qui suit l'entrée en jeu est passée (avant, on n'alerte jamais)
local dura = { state = nil, ready = false, graceStarted = false }

local function worstAlert()
    local fn = api("GetInventoryAlertStatus")
    if type(fn) ~= "function" then return nil end
    local worst = 0
    for index = 1, ALERT_SLOTS do
        local ok, status = pcall(fn, index)
        status = ok and tonumber(status) or 0
        if status > worst then worst = status end
    end
    return worst
end

-- pourcentage de la pièce la plus abîmée (nil si l'API manque ou rien n'a de durabilité)
local function lowestDurability()
    local fn = api("GetInventoryItemDurability")
    if type(fn) ~= "function" then return nil end
    local lowest
    for slot = 1, 18 do
        local ok, current, maximum = pcall(fn, slot)
        current, maximum = ok and tonumber(current), ok and tonumber(maximum)
        if current and maximum and maximum > 0 then
            local ratio = current / maximum
            if not lowest or ratio < lowest then lowest = ratio end
        end
    end
    return lowest and math.floor(lowest * 100 + 0.5)
end

local function alertDurability(worst)
    local isBroken = worst >= 2
    local text = isBroken and ns.T("Équipement cassé : répare-le vite") or ns.T("Équipement presque cassé : pense à réparer")
    if ns.Float and ns.Float.Add then
        local ok, err = pcall(ns.Float.Add, ns.Float, { icon = REPAIR_ICON, name = text, source = "info" })
        if not ok then ns:Debug("flux indisponible :", tostring(err)) end
    end
    local percent = lowestDurability()
    local detail = percent and ns.Tf(" (pièce la plus abîmée : %d %%)", percent) or ""
    ns:Print("|cff" .. (isBroken and "ff4040" or "ff8000") .. text .. detail .. "|r")
end

-- une alerte par aggravation (0 -> 1, 0 -> 2, 1 -> 2) ; une amélioration (réparation) se mémorise en silence
local function checkDurability()
    if not (ns.db.durabilityWarn and dura.ready) then return end
    local worst = worstAlert()
    if not worst then return end
    local previous = dura.state
    dura.state = worst
    if previous ~= nil and worst > previous then alertDurability(worst) end
end

local endGrace = guarded("durabilityWarn", function()
    dura.ready = true
    if ns.db.durabilityWarn then dura.state = worstAlert() end   -- état de départ, sans alerte
end)

local function startGrace()
    if dura.graceStarted then return end
    dura.graceStarted = true
    C_Timer.After(LOGIN_GRACE, endGrace)
end

local function applyDurability()
    if ns.db.durabilityWarn and dura.ready then
        dura.state = worstAlert()          -- réactivée : l'état actuel sert de départ, sans alerte
    else
        dura.state = nil
    end
end

handlers.UPDATE_INVENTORY_ALERTS = guarded("durabilityWarn", checkDurability)

---------------------------------------------------------------------------
-- 6. Barres d'expérience et de réputation masquées (hideXpBar)
-- Vérifié dans le code de Forever (Blizzard_StatusTrackingBar/Mainline/StatusTrackingBar.xml) : StatusTrackingBarManager
-- (non protégé) porte MainStatusTrackingBarContainer et SecondaryStatusTrackingBarContainer, où le jeu range la barre
-- d'XP et celle de réputation. Le parent caché cache tout ; s'il est remontré (mode Édition...), on le recache.
-- Option coupée : il est remontré, Blizzard reprend la main sur ce qu'il affiche.
---------------------------------------------------------------------------
local xpBar = { hooked = false, hidden = false }

local function applyXpBar()
    local manager = api("StatusTrackingBarManager")
    if not (manager and manager.Hide) then return end
    if not xpBar.hooked then
        xpBar.hooked = true
        manager:HookScript("OnShow", function(self)
            if ns.db.hideXpBar then self:Hide() end
        end)
    end
    if ns.db.hideXpBar then
        manager:Hide()
        xpBar.hidden = true
    elseif xpBar.hidden then
        xpBar.hidden = false
        manager:Show()
    end
end

function Tweaks:XpBarHidden()
    local manager = api("StatusTrackingBarManager")
    return manager ~= nil and xpBar.hidden and not manager:IsShown()
end

---------------------------------------------------------------------------
-- Synchronisation des événements et installation différée
---------------------------------------------------------------------------
local function needsInstall()
    local db = ns.db
    if db.hideErrors and not errorsFound then return true end
    if db.autoOpenMail and not mail.hooked then return true end
    if db.charIlvl and not char.hooked then return true end
    if db.bagIlvl and bags.missing then return true end
    return false
end

local function syncEvents()
    local db = ns.db
    setEvent("UPDATE_INVENTORY_ALERTS", db.durabilityWarn)
    setEvent("PLAYER_EQUIPMENT_CHANGED", db.charIlvl or db.bagIlvl)
    setEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE", db.charIlvl)
    setEvent("BAG_UPDATE_DELAYED", db.bagIlvl and bags.unhooked > 0)
    setEvent("PLAYER_ENTERING_WORLD", db.hideErrors or not dura.graceStarted)
    setEvent("MAIL_INBOX_UPDATE", mail.pending)
    setEvent("ADDON_LOADED", needsInstall())
end

-- un addon Blizzard chargé à la demande a pu créer ce qui manquait
handlers.ADDON_LOADED = function()
    local db = ns.db
    if db.hideErrors and not errorsFound then guarded("hideErrors", applyErrors)() end
    if db.autoOpenMail and not mail.hooked then guarded("autoOpenMail", installMail)() end
    if db.charIlvl and not char.hooked then
        guarded("charIlvl", installChar)()
        if char.hooked then schedule("char", 0, refreshCharSafe) end
    end
    if db.bagIlvl and bags.missing then
        guarded("bagIlvl", installBags)()
        schedule("bags", 0.05, refreshBagsSafe)
    end
    syncEvents()
end

handlers.PLAYER_ENTERING_WORLD = function()
    if ns.db.hideErrors then guarded("hideErrors", applyErrors)() end   -- au cas où l'événement aurait été remis
    startGrace()
    syncEvents()
end

local function averageVisible()
    return avg and avg.frame:IsVisible()
end

handlers.PLAYER_EQUIPMENT_CHANGED = function()
    local db = ns.db
    if db.bagIlvl then schedule("bags", 0.1, refreshBagsSafe) end           -- une pièce portée change ce qui est vendable
    if db.charIlvl and averageVisible() then schedule("average", 0.1, refreshAverageSafe) end
end

handlers.PLAYER_AVG_ITEM_LEVEL_UPDATE = function()
    if ns.db.charIlvl and averageVisible() then schedule("average", 0.1, refreshAverageSafe) end
end

---------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------
local initialized = false

local function applyAll()
    guarded("hideErrors", applyErrors)()
    guarded("autoOpenMail", applyMail)()
    guarded("charIlvl", applyChar)()
    guarded("bagIlvl", applyBags)()
    guarded("durabilityWarn", applyDurability)()
    guarded("hideXpBar", applyXpBar)()
    syncEvents()
end

function Tweaks:Init()
    if initialized then return end
    initialized = true

    local function onChange(key, apply)
        local safe = guarded(key, apply)
        ns:OnChange(key, function()
            safe()
            syncEvents()
        end)
    end
    onChange("hideErrors", applyErrors)
    onChange("autoOpenMail", applyMail)
    onChange("charIlvl", applyChar)
    onChange("bagIlvl", applyBags)
    onChange("durabilityWarn", applyDurability)
    onChange("hideXpBar", applyXpBar)
    for _, key in ipairs(JUNK_KEYS) do ns:OnChange(key, onJunkRulesChanged) end

    applyAll()
    if call("IsLoggedIn") then startGrace() end   -- chargé après l'entrée en jeu
    syncEvents()
end

-- réapplique tout (après un changement fait hors de ns:Set, par exemple)
function Tweaks:Refresh()
    if not initialized then return end
    applyAll()
end

-- niveau d'objet moyen de l'équipement porté (nil si inconnu)
function Tweaks:AverageItemLevel()
    return averageItemLevel()
end

-- pire état de durabilité (0 / 1 / 2, nil si l'API manque) et pourcentage de la pièce la plus abîmée
function Tweaks:Durability()
    return worstAlert(), lowestDurability()
end

-- textes posés sur un bouton : { frame, level, coin, bag } ou nil (tests, débogage)
function Tweaks:GetOverlay(button)
    return overlays[button]
end

-- FontString de la moyenne sur la fiche (nil tant qu'elle n'a pas été affichée)
function Tweaks:GetAverageLabel()
    return avg and avg.text
end

-- état des accroches (débogage)
function Tweaks:Status()
    local hooks = 0
    for _ in pairs(bags.hooked) do hooks = hooks + 1 end
    return {
        errorsMuted = errorsMuted, errorsFound = errorsFound,
        mailHooked = mail.hooked, mailPending = mail.pending,
        charHooked = char.hooked,
        bagFrames = #bags.frames, bagHooks = hooks, bagFallback = bags.updateAllHooked,
        durability = dura.state, durabilityReady = dura.ready,
        broken = broken,
    }
end
