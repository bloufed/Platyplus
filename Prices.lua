-- Platyplus : prix de l'hôtel des ventes (ns.Prices)
--  * BASE DE PRIX par objet : le moins cher à l'unité, par royaume et faction
--    ns.db.ahMarket["Royaume-Faction"] = { p = { [itemID] = prix }, t = { [itemID] = date }, scan = date, replicate = date }
--  * SOURCES :
--     - scan complet de l'HDV : C_AuctionHouse.ReplicateItems() envoie TOUTES les ventes d'un coup (le serveur le
--       permet une fois toutes les 15 min). Lu par paquets de 1500 lignes par image pour ne pas figer le jeu.
--       Automatique à l'ouverture de l'HDV si le dernier date de plus d'une heure (réglable), ou /pp hdv complet.
--     - chaque prix trouvé par l'assistant de mise en vente (Auction.lua), plus récent
--  * PRIX D'ACHAT CHEZ LES MARCHANDS (fils, fioles, sel...) relevés à chaque visite : ns.db.vendorBuy[itemID]
--    (le coût d'une recette prend le moins cher des deux)
--  * LIGNE « HDV » dans les infobulles d'objets (sacs, équipement porté, liens, HDV...) : prix à l'unité, et pour
--    la pile entière quand l'objet est dans tes sacs
-- Vérifié dans le code de Forever (wow-ui-source, branche forever) :
--  * AuctionHouseDocumentation : ReplicateItems() (sans action du joueur), GetNumReplicateItems(),
--    GetReplicateItemInfo(index) avec un index qui part de 0 (type « number », pas « luaIndex ») ; 17e retour = itemID,
--    3e = quantité, 10e = prix d'achat immédiat du lot ; événement REPLICATE_ITEM_LIST_UPDATE
--  * TooltipDataHandler.lua : TooltipDataProcessor.AddTooltipPostCall(type, fonction(tooltip, data)) ;
--    Enum.TooltipDataType.Item = 0 ; data.id = itemID
--  * MerchantFrame.lua : GetMerchantNumItems(), GetMerchantItemLink(i), C_MerchantFrame.GetItemInfo(i) -> { price
--    (pour stackCount objets), stackCount, hasExtendedCost }
-- NON VÉRIFIÉ en jeu : tous les appels sont protégés ; si le scan complet ne répond pas en 60 s, il est abandonné.
local ADDON, ns = ...

local Prices = {}
ns.Prices = Prices

local floor, max, min = math.floor, math.max, math.min

local REPLICATE_COOLDOWN = 15 * 60   -- le serveur n'accepte qu'un scan complet toutes les 15 min
local AUTO_SCAN_EVERY    = 60 * 60   -- scan automatique si le dernier date de plus d'une heure
local SCAN_TIMEOUT       = 60        -- s sans réponse au scan complet : abandon
local CHUNK              = 1500      -- lignes lues par image
local DAY                = 24 * 3600

local function db(key)
    return ns.db and ns.db[key]
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    ns:Debug("prix : appel refusé :", tostring(a))
    return nil
end

local function now()
    local f = rawget(_G, "time")
    return type(f) == "function" and f() or 0
end

local function AH()
    return rawget(_G, "C_AuctionHouse")
end

local function money(copper)
    if ns.W and ns.W.FormatMoney then return ns.W.FormatMoney(copper) end
    return tostring(copper) .. " pc"
end
Prices.Money = money

local function itemIDFromLink(link)
    return link and tonumber(tostring(link):match("item:(%d+)"))
end

-- « il y a 3 h », « il y a 2 j »
function Prices.AgeText(seconds)
    seconds = max(0, floor(seconds or 0))
    if seconds < 3600 then return ns.Tf("il y a %d min", max(1, floor(seconds / 60))) end
    if seconds < DAY then return ns.Tf("il y a %d h", floor(seconds / 3600)) end
    return ns.Tf("il y a %d j", floor(seconds / DAY))
end

---------------------------------------------------------------------------
-- Base de prix
---------------------------------------------------------------------------
local function realmKey()
    local realm = call(rawget(_G, "GetRealmName")) or "?"
    local faction = call(rawget(_G, "UnitFactionGroup"), "player") or ""
    return tostring(realm) .. "-" .. tostring(faction)
end

local function market()
    if not ns.db then return { p = {}, t = {}, scan = 0 } end
    local all = ns.db.ahMarket
    if type(all) ~= "table" then
        all = {}
        ns.db.ahMarket = all
    end
    local key = realmKey()
    local m = all[key]
    if type(m) ~= "table" then
        m = {}
        all[key] = m
    end
    if type(m.p) ~= "table" then m.p = {} end
    if type(m.t) ~= "table" then m.t = {} end
    m.scan = tonumber(m.scan) or 0
    m.replicate = tonumber(m.replicate) or 0
    return m
end

local listeners = {}

-- fn() appelée quand des prix changent (fin d'un scan complet, prix trouvé par l'assistant)
function Prices:OnUpdate(fn)
    listeners[#listeners + 1] = fn
end

local notifyPending = false
local function notify()
    -- regroupe les changements d'une même image
    if notifyPending then return end
    notifyPending = true
    C_Timer.After(0, function()
        notifyPending = false
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end)
end

-- Note le prix le plus bas vu à l'HDV pour un objet (prix à l'unité)
function Prices:Record(itemID, unitPrice, when)
    itemID, unitPrice = tonumber(itemID), tonumber(unitPrice)
    if not itemID or not unitPrice or unitPrice <= 0 then return end
    local m = market()
    m.p[itemID] = floor(unitPrice)
    m.t[itemID] = when or now()
    notify()
end

-- Prix à l'unité et âge (s) ; maxAge facultatif : nil si plus ancien
function Prices:Get(itemID, maxAge)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local m = market()
    local p = tonumber(m.p[itemID])
    if not p or p <= 0 then return nil end
    local age = now() - (tonumber(m.t[itemID]) or 0)
    if maxAge and age > maxAge then return nil end
    return p, age
end

-- Prix d'achat chez un marchand (à l'unité), s'il a été relevé
function Prices:VendorBuy(itemID)
    local t = db("vendorBuy")
    local p = type(t) == "table" and tonumber(t[tonumber(itemID) or 0])
    if p and p > 0 then return p end
end

-- Coût le plus bas pour se procurer un objet : HDV ou marchand ; renvoie prix, "HDV" | "marchand"
function Prices:Cost(itemID)
    local ah = self:Get(itemID)
    local vendor = self:VendorBuy(itemID)
    if vendor and (not ah or vendor <= ah) then return vendor, "marchand" end
    if ah then return ah, "HDV" end
end

function Prices:Count()
    local n = 0
    for _ in pairs(market().p) do n = n + 1 end
    return n
end

function Prices:LastFullScan()
    local m = market()
    return m.scan > 0 and m.scan or nil
end

---------------------------------------------------------------------------
-- Scan complet de l'HDV
---------------------------------------------------------------------------
local scan = { state = "idle", done = 0, total = 0, gen = 0 }
local ahOpen = false

function Prices:ScanState()
    return scan.state, scan.done, scan.total
end

-- Secondes avant de pouvoir relancer un scan complet (0 = possible)
function Prices:FullScanWait()
    local m = market()
    return max(0, REPLICATE_COOLDOWN - (now() - m.replicate))
end

function Prices:ShouldAutoScan()
    if not db("ahFullScan") or scan.state ~= "idle" then return false end
    local m = market()
    return now() - m.scan >= AUTO_SCAN_EVERY and self:FullScanWait() == 0
end

local function finishRead(best)
    local m = market()
    local t = now()
    local n = 0
    for id, p in pairs(best) do
        m.p[id] = p
        m.t[id] = t
        n = n + 1
    end
    m.scan = t
    scan.state = "idle"
    ns:Print(ns.Tf("HDV : scan complet terminé, %d objet(s) avec un prix.", n))
    notify()
end

local function readChunk(gen, best, index)
    if gen ~= scan.gen or scan.state ~= "reading" then return end
    local api = AH()
    local last = min(scan.total - 1, index + CHUNK - 1)
    for i = index, last do
        local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = pcall(api.GetReplicateItemInfo, i)
        count, buyout = tonumber(count), tonumber(buyout)
        if ok and itemID and buyout and buyout > 0 and count and count > 0 then
            local unit = floor(buyout / count)
            if unit > 0 and (not best[itemID] or unit < best[itemID]) then best[itemID] = unit end
        end
    end
    scan.done = last + 1
    notify()
    if scan.done >= scan.total then
        finishRead(best)
    else
        C_Timer.After(0, function() readChunk(gen, best, last + 1) end)
    end
end

local function startRead()
    if scan.state ~= "waiting" then return end
    local api = AH()
    scan.total = call(api and api.GetNumReplicateItems) or 0
    scan.done = 0
    scan.state = "reading"
    if scan.total <= 0 then
        scan.state = "idle"
        ns:Print(ns.T("HDV : le scan complet n'a rien renvoyé."))
        notify()
        return
    end
    readChunk(scan.gen, {}, 0)
end

-- Lance un scan complet (HDV ouvert) ; auto = silencieux si ce n'est pas possible maintenant
function Prices:FullScan(auto)
    local api = AH()
    if not ahOpen or not (api and api.ReplicateItems and api.GetReplicateItemInfo) then
        if not auto then ns:Print(ns.T("ouvre d'abord l'hôtel des ventes pour un scan complet")) end
        return false
    end
    if scan.state ~= "idle" then return false end
    local wait = self:FullScanWait()
    if wait > 0 then
        if not auto then
            ns:Print(ns.Tf("HDV : le serveur n'autorise un scan complet que toutes les 15 min, réessaie dans %d min.",
                math.ceil(wait / 60)))
        end
        return false
    end
    if not pcall(api.ReplicateItems) then
        if not auto then ns:Print(ns.T("HDV : scan complet refusé par le jeu")) end
        return false
    end
    market().replicate = now()
    scan.gen = scan.gen + 1
    scan.state, scan.done, scan.total = "waiting", 0, 0
    ns:Print(ns.T("HDV : scan complet lancé (tous les prix de l'HDV, quelques secondes)..."))
    local gen = scan.gen
    C_Timer.After(SCAN_TIMEOUT, function()
        if gen == scan.gen and scan.state == "waiting" then
            scan.state = "idle"
            ns:Print(ns.T("HDV : pas de réponse au scan complet, réessaie plus tard."))
            notify()
        end
    end)
    notify()
    return true
end

---------------------------------------------------------------------------
-- Prix d'achat chez les marchands
---------------------------------------------------------------------------
function Prices:ReadMerchant()
    local count = call(rawget(_G, "GetMerchantNumItems")) or 0
    local t = db("vendorBuy")
    if type(t) ~= "table" then
        t = {}
        if ns.db then ns.db.vendorBuy = t end
    end
    local found = 0
    for i = 1, count do
        local id = itemIDFromLink(call(rawget(_G, "GetMerchantItemLink"), i))
        local price, stack, extended
        local merchant = rawget(_G, "C_MerchantFrame")
        if merchant and merchant.GetItemInfo then
            local info = call(merchant.GetItemInfo, i)
            if type(info) == "table" then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
        elseif rawget(_G, "GetMerchantItemInfo") then
            local ok, _, _, p, q, _, _, _, ext = pcall(GetMerchantItemInfo, i)
            if ok then price, stack, extended = p, q, ext end
        end
        price, stack = tonumber(price), max(1, tonumber(stack) or 1)
        if id and price and price > 0 and not extended then
            t[id] = price / stack
            found = found + 1
        end
    end
    if found > 0 then notify() end
    return found
end

---------------------------------------------------------------------------
-- Infobulles
---------------------------------------------------------------------------
-- quantité de la pile quand l'infobulle vient d'un emplacement de sac
local function stackCount(tooltip, itemID)
    local ok, owner = pcall(tooltip.GetOwner, tooltip)
    if not ok or type(owner) ~= "table" or not (owner.GetBagID and owner.GetID) then return nil end
    local okBag, bag = pcall(owner.GetBagID, owner)
    local okSlot, slot = pcall(owner.GetID, owner)
    if not (okBag and okSlot and bag and slot and C_Container) then return nil end
    local info = call(C_Container.GetContainerItemInfo, bag, slot)
    if info and info.itemID == itemID then return info.stackCount end
end

function Prices:TooltipLine(itemID, count)
    local p, age = self:Get(itemID)
    if not p then return nil end
    local right = money(p)
    if count and count > 1 then right = right .. ns.Tf("  |cff999999x%d :|r %s", count, money(p * count)) end
    local left = ns.T("HDV")
    if age and age > DAY then left = left .. ns.Tf(" |cff999999(%s)|r", Prices.AgeText(age)) end
    return left, right
end

local function onItemTooltip(tooltip, data)
    if not db("ahTooltip") then return end
    if tooltip ~= rawget(_G, "GameTooltip") and tooltip ~= rawget(_G, "ItemRefTooltip") then return end
    local id = type(data) == "table" and data.id
    local secret = rawget(_G, "issecretvalue")
    if type(id) ~= "number" or (secret and secret(id)) then return end
    local left, right = Prices:TooltipLine(id, stackCount(tooltip, id))
    if left then
        tooltip:AddDoubleLine(left, right, 0.2, 0.8, 1, 1, 1, 1)
    end
end

local function hookTooltips()
    local processor = rawget(_G, "TooltipDataProcessor")
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if processor and processor.AddTooltipPostCall and itemType then
        processor.AddTooltipPostCall(itemType, function(tooltip, data)
            local ok, err = pcall(onItemTooltip, tooltip, data)
            if not ok then ns:Debug("prix : infobulle :", tostring(err)) end
        end)
        return true
    end
    -- anciens clients : OnTooltipSetItem
    if GameTooltip and GameTooltip.HookScript then
        local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tooltip)
            local _, link = tooltip:GetItem()
            pcall(onItemTooltip, tooltip, { id = itemIDFromLink(link) })
        end)
        return ok
    end
    return false
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        if scan.state == "waiting" then
            scan.state = "idle"   -- la lecture déjà commencée continue : les données restent lisibles
            notify()
        end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if scan.state == "waiting" then
            -- l'événement peut arriver plusieurs fois de suite : on lit un peu après le premier
            local gen = scan.gen
            C_Timer.After(0.5, function() if gen == scan.gen then startRead() end end)
        end
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        Prices:ReadMerchant()
    end
end)

function Prices:Init()
    for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
        "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    self.tooltipHooked = hookTooltips()
end
