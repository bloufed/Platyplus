-- Platyplus : hôtel des ventes (HDV)
-- À l'ouverture de l'HDV, un panneau s'accroche à droite de la fenêtre de Blizzard :
--  1) SCAN DES SACS : tout ce que l'HDV accepte (C_AuctionHouse.IsSellItemValid), SAUF : objets liés, ensemble
--     d'équipement, équipement blanc ou gris (réglable : ahGearMinQuality), outils de métier (pioche, couteau à
--     dépecer, canne à pêche...), objets gris, liste « jamais à l'HDV » (clic droit).
--     Marchandises (minerais, herbes, tissus...) regroupées par objet ; autres objets (équipement...) un par emplacement.
--     CASES À COCHER : seuls les objets cochés sont mis en vente. Les choix sont retenus par objet (ahChecked) :
--     coche ton minerai une fois, il sera coché à chaque visite. Rien n'est coché d'office.
--  2) SCAN DES PRIX, sans clic, en deux temps :
--     a. UNE recherche groupée pour tous les objets sauf l'équipement (C_AuctionHouse.SearchForItemKeys) : le plus bas
--        prix de chacun arrive d'un coup. Un objet absent de la réponse, ou dont une vente est à toi, passe en b.
--     b. une recherche par objet restant (équipement : il faut comparer au même niveau d'objet), envoyées dès que le
--        jeu dit que la file est libre (événement AUCTION_HOUSE_THROTTLED_SYSTEM_READY), 95 par minute au plus
--        (la doc de Blizzard en autorise 100).
--  3) PRIX : le moins cher des AUTRES vendeurs moins N pc (1 pc par défaut) ; aligné si le moins cher est déjà à toi.
--     Personne n'en vend : dernier prix vu (14 jours), sinon prix marchand x N.
--     Une seule règle de sécurité (réglable) : pas de mise en vente si le marchand t'en donne autant ou plus
--     (l'HDV garde 5 % de la vente). Ex. minerai à 18 pc à l'HDV (17 pc pour toi) contre 5 pc au marchand : vendu.
--  4) MISE EN VENTE : 1 clic (ou ta touche, ou la macro /click PlatyplusAHPost) = 1 mise en vente, sans attendre la
--     réponse du serveur entre deux clics. PostItem / PostCommodity sont « HasRestrictions » dans la doc de Blizzard :
--     le jeu exige une action du joueur (clic ou touche) pour chacune. Tout poster d'un coup est impossible pour un
--     addon, et ce serait du bot. Une marchandise part en une fois, quelle que soit la quantité.
-- Vérifié dans le code de Forever (dépôt wow-ui-source, branche forever : AuctionHouseDocumentation.lua,
-- Blizzard_AuctionHouseUI) :
--  * PostCommodity(loc, durée, quantité, prixUnitaire) et PostItem(loc, durée, quantité, enchère, achatImmédiat)
--    renvoient needsConfirmation ; si vrai le jeu envoie AUCTION_HOUSE_POST_WARNING et attend
--    ConfirmPostCommodity / ConfirmPostItem avec les mêmes arguments (eux aussi sur action du joueur)
--  * prix au cuivre près si C_AuctionHouse.SupportsCopperValues() (cas de Forever : on y voit des prix à 19 pc),
--    sinon en multiples de 1 pa ; durée 1 / 2 / 3 = 12 / 24 / 48 h ; Enum.ItemCommodityStatus Unknown 0, Item 1,
--    Commodity 2
--  * SearchForItemKeys(itemKeys, sorts) -> AUCTION_HOUSE_BROWSE_RESULTS_UPDATED, GetBrowseResults() :
--    { itemKey, minPrice, totalQuantity, containsOwnerItem } (fonction documentée, pas utilisée par l'HDV de Blizzard :
--    si elle ne répond pas en 4 s, tout passe par les recherches une par une)
--  * équipement : clé d'objet sans niveau ni suffixe + SendSellSearchQuery ; meilleur prix = même niveau d'objet
--    (sauf qualité Inhabituel) ; buyoutAmount d'un résultat = prix à l'unité
--  * résultats : COMMODITY_SEARCH_RESULTS_UPDATED(itemID), ITEM_SEARCH_RESULTS_UPDATED(itemKey) ;
--    AUCTION_HOUSE_AUCTION_CREATED à chaque vente créée ; AUCTION_HOUSE_SHOW_ERROR / AUCTION_HOUSE_POST_ERROR si refus
-- NON VÉRIFIÉ en jeu : tous les appels sont protégés (pcall) ; un appel refusé marque l'objet « refusé » sans rien bloquer.
local ADDON, ns = ...

local Auction = {}
ns.Auction = Auction

local floor, max, min = math.floor, math.max, math.min

local function enumValue(group, name, fallback)
    local e = Enum and Enum[group]
    local v = e and e[name]
    if v == nil then return fallback end
    return v
end

local SILVER           = tonumber(rawget(_G, "COPPER_PER_SILVER")) or 100
local BAG_FIRST        = enumValue("BagIndex", "Backpack", 0)
local BAG_LAST         = enumValue("BagIndex", "ReagentBag", 5)
local COMMODITY        = enumValue("ItemCommodityStatus", "Commodity", 2)
local ITEM             = enumValue("ItemCommodityStatus", "Item", 1)
local SORT_PRICE       = enumValue("AuctionHouseSortOrder", "Price", 0)
local SORT_NAME        = enumValue("AuctionHouseSortOrder", "Name", 1)
local QUALITY_UNCOMMON = enumValue("ItemQuality", "Uncommon", 2)
local CLASS_WEAPON     = enumValue("ItemClass", "Weapon", 2)
local CLASS_ARMOR      = enumValue("ItemClass", "Armor", 4)
local CLASS_PROFESSION = enumValue("ItemClass", "Profession", 19)          -- outils de métier des clients récents
local WEAPON_GENERIC   = enumValue("ItemWeaponSubclass", "Generic", 14)    -- « Divers » : pioche de mineur...
local WEAPON_FISHING   = enumValue("ItemWeaponSubclass", "Fishingpole", 20)

-- Outils de métier jamais proposés (identifiants des objets classiques, NON VÉRIFIÉS sur Forever ; les familles
-- d'objets ci-dessus et la règle « équipement blanc ou gris » attrapent aussi ceux qui manqueraient ici)
local TOOLS = {
    [2901] = true,  -- Pioche de mineur
    [7005] = true,  -- Couteau à dépecer
    [5956] = true,  -- Marteau de forgeron
    [6219] = true,  -- Clé plate à arc
    [10498] = true, -- Micro-ajusteur gyromatique
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true,   -- bâtonnets runiques
    [6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true,     -- cannes à pêche
    [19022] = true, [19970] = true,
    [4471] = true,  -- Silex et amadou
    [20815] = true, -- Outils de joaillier
    [40772] = true, -- Couteau de l'armée gnome
}

local POST_BUTTON   = "PlatyplusAHPost"   -- nom global : touche et macro /click PlatyplusAHPost
local PER_MINUTE    = 95                  -- recherches par minute au maximum (Blizzard : 100)
local QUERY_TIMEOUT = 6                   -- s sans réponse du serveur : on passe à l'objet suivant
local BROWSE_TIMEOUT = 4                  -- s sans réponse à la recherche groupée : recherches une par une
local AH_CUT        = 0.05                -- part de la vente gardée par l'HDV
local POST_TIMEOUT  = 5                   -- s sans « vente créée » : on regarde si l'objet a quitté les sacs
local PRICE_MAX_AGE = 14 * 24 * 3600      -- un prix vu reste une référence 14 jours
local PRICE_MAX     = 800                 -- prix mémorisés au maximum (les plus anciens sont oubliés)
local SORTS = {
    { sortOrder = SORT_PRICE, reverseSort = false },
    { sortOrder = SORT_NAME, reverseSort = false },
}

Auction.SILVER = SILVER
Auction.POST_BUTTON = POST_BUTTON

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------
local function db(key)
    return ns.db and ns.db[key]
end

-- appel protégé : renvoie les résultats de fn, ou rien si fn manque ou plante
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    ns:Debug("HDV : appel refusé :", tostring(a))
    return nil
end

-- appel protégé : renvoie true si fn existe et n'a pas planté (pour les fonctions qui ne renvoient rien)
local function try(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, ...)
    if not ok then ns:Debug("HDV : appel refusé :", tostring(err)) end
    return ok
end

local function AH()
    return rawget(_G, "C_AuctionHouse")
end

local function now()
    local f = rawget(_G, "time")
    return type(f) == "function" and f() or 0
end

local function money(copper)
    if ns.W and ns.W.FormatMoney then return ns.W.FormatMoney(copper) end
    return tostring(floor((copper or 0) / 10000)) .. " po"
end

local function colorText(name, text)
    if ns.W and ns.W.Color then return ns.W.Color(name, text) end
    return tostring(text)
end

-- multiple de step (1 pc, ou 1 pa si l'HDV refuse le cuivre), arrondi vers le bas (ou vers le haut)
local function roundTo(copper, step, up)
    step = step or 1
    if up then return math.ceil(copper / step) * step end
    return floor(copper / step) * step
end

local function copyKey(k, itemID)
    k = k or {}
    return {
        itemID = k.itemID or itemID,
        itemLevel = k.itemLevel or 0,
        itemSuffix = k.itemSuffix or 0,
        battlePetSpeciesID = k.battlePetSpeciesID or 0,
    }
end

local function keyString(k)
    return tostring(k.itemID) .. ":" .. tostring(k.itemLevel or 0) .. ":" .. tostring(k.itemSuffix or 0)
        .. ":" .. tostring(k.battlePetSpeciesID or 0)
end

---------------------------------------------------------------------------
-- Prix (fonction pure : testée hors du jeu)
---------------------------------------------------------------------------
-- Ce que tu touches vraiment pour une unité vendue à ce prix (l'HDV garde 5 %)
function Auction.NetPrice(price)
    return floor((price or 0) * (1 - AH_CUT))
end

-- o = { lowest, mine, vendor, lastSeen, undercut (pc), noCompMult, vendorCheck, step (1 pc ou 1 pa) }
-- renvoie prix, comment ; prix = nil quand on ne met pas en vente :
--   comment = "undercut" (moins cher - N pc), "mine" (aligné sur ta vente), "last" (dernier prix vu),
--   "vendor" (prix marchand x N), "low" (le marchand paie autant ou plus), "noref" (aucune référence)
function Auction.ComputePrice(o)
    local step = max(1, tonumber(o.step) or 1)
    local vendor = max(0, tonumber(o.vendor) or 0)
    local function vendorBetter(p)
        return o.vendorCheck and vendor > 0 and Auction.NetPrice(p) <= vendor
    end
    local lowest = tonumber(o.lowest)
    if lowest and lowest > 0 then
        local price, how
        if o.mine then
            price, how = roundTo(lowest, step), "mine"
        else
            price = roundTo(lowest - max(0, floor(tonumber(o.undercut) or 0)), step)
            if price >= lowest then price = roundTo(lowest, step) - step end   -- au moins un cran sous l'autre vendeur
            how = "undercut"
        end
        if price < step or vendorBetter(price) then return nil, "low" end
        return price, how
    end
    -- personne n'en vend : dernier prix vu, sinon prix marchand x N
    local noComp = roundTo(vendor * (tonumber(o.noCompMult) or 1), step, true)
    local lastSeen = tonumber(o.lastSeen)
    if lastSeen and lastSeen >= step and not vendorBetter(roundTo(lastSeen, step)) then
        return roundTo(lastSeen, step), "last"
    end
    if vendor > 0 and noComp >= step and not vendorBetter(noComp) then
        return noComp, "vendor"
    end
    if vendor > 0 then return nil, "low" end
    return nil, "noref"
end

local HOW_TEXT = {
    undercut = "un peu moins cher que les autres vendeurs",
    mine     = "aligné sur ta propre vente (déjà la moins chère)",
    last     = "personne n'en vend : dernier prix vu à l'HDV",
    vendor   = "personne n'en vend : prix du marchand x %s",
}

-- derniers prix vus, par objet (et par niveau pour l'équipement)
local function priceBook()
    local book = db("ahPrices")
    if type(book) ~= "table" then
        book = {}
        if ns.db then ns.db.ahPrices = book end
    end
    return book
end

local function lastSeen(priceKey)
    local seen = priceBook()[priceKey]
    if type(seen) == "table" and tonumber(seen.p) and (now() - (tonumber(seen.t) or 0)) <= PRICE_MAX_AGE then
        return tonumber(seen.p)
    end
end

local function remember(priceKey, price)
    local book = priceBook()
    book[priceKey] = { p = price, t = now() }
    local n, oldestKey, oldestT = 0, nil, math.huge
    for k, v in pairs(book) do
        n = n + 1
        local t = type(v) == "table" and tonumber(v.t) or 0
        if t < oldestT then oldestKey, oldestT = k, t end
    end
    if n > PRICE_MAX and oldestKey then book[oldestKey] = nil end
end

---------------------------------------------------------------------------
-- État de la visite
---------------------------------------------------------------------------
local entries = {}      -- objets affichés (voir newEntry)
local isOpen = false    -- HDV ouvert
local scanning = false  -- recherche des prix en cours
local current           -- objet dont on attend les prix
local generation = 0    -- change à chaque scan : les minuteries d'un scan précédent ne font plus rien
local sentTimes = {}    -- heures des dernières recherches (pour rester sous 95 par minute)
local browsing = false  -- recherche groupée envoyée, on attend sa réponse
local step = 1          -- plus petit écart de prix accepté par l'HDV : 1 pc (ou 1 pa sans cuivre)
local posting = {}      -- objets envoyés, dans l'ordre : chaque « vente créée » valide le plus ancien
local pending           -- confirmation demandée par le jeu : { e, commodity, args }
local retriedUnknown = false

local events = CreateFrame("Frame")   -- reçoit les événements et possède la touche de l'HDV
local panel                           -- créé à la première ouverture de l'HDV
local refresh                         -- redessine le panneau (défini plus bas)

local STATUS = {
    wait     = { "en attente", "dim" },
    query    = { "recherche...", "accent" },
    ready    = { "prêt", "good" },
    low      = { "marchand mieux", "bad" },
    noref    = { "aucun prix connu", "gold" },
    noanswer = { "pas de réponse", "gold" },
    posting  = { "envoi...", "accent" },
    confirm  = { "à confirmer", "gold" },
    done     = { "en vente", "good" },
    error    = { "refusé", "bad" },
    gone     = { "plus dans les sacs", "dim" },
}

function Auction:StatusText(e)
    if not e.checked and e.status == "ready" then
        return colorText("dim", ns.T("non coché"))
    end
    local s = STATUS[e.status] or { tostring(e.status), "dim" }
    return colorText(s[2], ns.T(s[1]))
end

-- objets cochés : retenus d'une visite à l'autre, par objet
local function checkedList()
    local t = db("ahChecked")
    if type(t) ~= "table" then
        t = {}
        if ns.db then ns.db.ahChecked = t end
    end
    return t
end

---------------------------------------------------------------------------
-- Scan des sacs
---------------------------------------------------------------------------
local function itemLocation(bag, slot)
    local IL = rawget(_G, "ItemLocation")
    if not (IL and IL.CreateFromBagAndSlot) then return nil end
    return call(IL.CreateFromBagAndSlot, IL, bag, slot)
end

local function sellable(loc)
    local api = AH()
    if not (loc and api) then return false end
    return call(api.IsSellItemValid, loc, false) and true or false
end

local function inEquipmentSet(bag, slot)
    if not (C_Container and C_Container.GetContainerItemEquipmentSetInfo) then return false end
    return call(C_Container.GetContainerItemEquipmentSetInfo, bag, slot) and true or false
end

local function vendorPrice(link)
    if not (link and C_Item and C_Item.GetItemInfo) then return 0 end
    local ok, price = pcall(function() return (select(11, C_Item.GetItemInfo(link))) end)
    return ok and tonumber(price) or 0
end

-- famille et sous-famille de l'objet (6e et 7e retours de GetItemInfoInstant)
local function itemClass(itemID)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, classID, subclassID = pcall(function()
        local _, _, _, _, _, c, s = C_Item.GetItemInfoInstant(itemID)
        return c, s
    end)
    if ok then return classID, subclassID end
end

local function isEquipment(key, itemID)
    local api = AH()
    if key and api and api.GetItemKeyInfo then
        local info = call(api.GetItemKeyInfo, key)
        if type(info) == "table" and info.isEquipment ~= nil then return info.isEquipment and true or false end
    end
    local classID = itemClass(itemID)
    return classID == CLASS_WEAPON or classID == CLASS_ARMOR
end

-- Pourquoi un objet n'est jamais proposé (nil = proposé) :
--   "tool" = outil de métier (pioche, couteau à dépecer, canne à pêche...), "gear" = équipement sous la qualité
--   choisie (blanc et gris par défaut), "junk" = objet gris (il part chez le marchand)
function Auction.HiddenReason(itemID, quality)
    quality = quality or 1
    if TOOLS[itemID] then return "tool" end
    local classID, subclassID = itemClass(itemID)
    if classID == CLASS_PROFESSION then return "tool" end
    if classID == CLASS_WEAPON and (subclassID == WEAPON_GENERIC or subclassID == WEAPON_FISHING) then return "tool" end
    if (classID == CLASS_WEAPON or classID == CLASS_ARMOR) and quality < (tonumber(db("ahGearMinQuality")) or 2) then
        return "gear"
    end
    if quality < 1 then return "junk" end
    return nil
end

local function newEntry(info, bag, slot, loc, commodity)
    local api = AH()
    local key = api and call(api.GetItemKeyFromItem, loc)
    local e = {
        id = info.itemID,
        link = info.hyperlink,
        icon = info.iconFileID,
        quality = info.quality or 1,
        name = info.itemName or (info.hyperlink and info.hyperlink:match("%[(.-)%]")) or ns.Tf("Objet #%s", tostring(info.itemID)),
        bag = bag,
        slot = slot,
        count = info.stackCount or 1,
        commodity = commodity,
        vendor = vendorPrice(info.hyperlink),
        status = "wait",
    }
    local full = copyKey(key, info.itemID)
    e.searchKey = copyKey(full)
    if commodity then
        e.group = "c:" .. info.itemID
        e.priceKey = e.group
        e.uid = e.group
    else
        e.equipment = isEquipment(key, info.itemID)
        e.ilvl = (C_Item and call(C_Item.GetCurrentItemLevel, loc)) or full.itemLevel or 0
        -- équipement : on compare aux objets semblables, sans niveau ni suffixe (comme la fenêtre de Blizzard)
        if e.equipment then
            e.searchKey.itemLevel = 0
            e.searchKey.itemSuffix = 0
        end
        e.ignoreLevel = (not e.equipment) or e.quality == QUALITY_UNCOMMON or full.battlePetSpeciesID > 0
        e.group = "i:" .. keyString(e.searchKey)
        e.priceKey = "i:" .. keyString(full) .. (e.equipment and (":" .. tostring(e.ilvl)) or "")
        e.uid = e.group .. "@" .. bag .. ":" .. slot
    end
    e.checked = checkedList()[info.itemID] and true or false
    return e
end

-- Renvoie la liste des objets à proposer, et true si des objets n'étaient pas encore chargés par le jeu
function Auction:ScanBags()
    local list, byItem, unknown = {}, {}, false
    local api = AH()
    if not (api and C_Container) then return list, false end
    local never = type(db("ahNever")) == "table" and db("ahNever") or {}
    for bag = BAG_FIRST, BAG_LAST do
        local slots = call(C_Container.GetContainerNumSlots, bag) or 0
        for slot = 1, slots do
            local info = call(C_Container.GetContainerItemInfo, bag, slot)
            if info and info.itemID and not info.isBound and not never[info.itemID]
                and not Auction.HiddenReason(info.itemID, info.quality) then
                local loc = itemLocation(bag, slot)
                if sellable(loc) and not inEquipmentSet(bag, slot) then
                    local status = call(api.GetItemCommodityStatus, loc)
                    if status == COMMODITY then
                        local e = byItem[info.itemID]
                        if e then
                            e.count = e.count + (info.stackCount or 1)
                        else
                            e = newEntry(info, bag, slot, loc, true)
                            byItem[info.itemID] = e
                            list[#list + 1] = e
                        end
                    elseif status == ITEM then
                        list[#list + 1] = newEntry(info, bag, slot, loc, false)
                    else
                        unknown = true   -- données de l'objet pas encore arrivées
                    end
                end
            end
        end
    end
    -- cochés d'abord (triés une fois par scan : les lignes ne sautent pas quand tu coches)
    table.sort(list, function(a, b)
        if a.checked ~= b.checked then return a.checked end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.name ~= b.name then return a.name < b.name end
        return (a.ilvl or 0) > (b.ilvl or 0)
    end)
    return list, unknown
end

function Auction:Entries()
    return entries
end

---------------------------------------------------------------------------
-- Scan des prix
---------------------------------------------------------------------------
local function priceOptions(e)
    return {
        lowest = e.lowest,
        mine = e.mine,
        vendor = e.vendor,
        -- dernier prix vu : celui de l'assistant, sinon celui du scan complet (pas pour l'équipement : il ignore le niveau)
        lastSeen = lastSeen(e.priceKey)
            or (not e.equipment and ns.Prices and ns.Prices:Get(e.id, 14 * 24 * 3600)) or nil,
        undercut = db("ahUndercut"),
        noCompMult = db("ahNoCompetition"),
        vendorCheck = db("ahVendorCheck") ~= false,
        step = step,
    }
end

-- (re)calcule le prix d'un objet dont on connaît l'état de l'HDV
local function price(e)
    local p, how = Auction.ComputePrice(priceOptions(e))
    e.how = how
    if p then
        e.price, e.status = p, "ready"
    else
        e.price, e.status = nil, how
    end
end

local function applyResult(e, lowest, mine)
    e.lowest, e.mine, e.searched = lowest, mine and true or false, true
    if lowest then
        remember(e.priceKey, lowest)
        if ns.Prices then ns.Prices:Record(e.id, lowest) end   -- infobulles et coût des recettes
    end
    price(e)
end

-- marchandise : le moins cher (les lignes sont groupées par prix)
local function lowestCommodity(e)
    local api = AH()
    local n = call(api.GetNumCommoditySearchResults, e.id) or 0
    local best, mine
    for i = 1, n do
        local r = call(api.GetCommoditySearchResultInfo, e.id, i)
        local unit = r and tonumber(r.unitPrice)
        if unit and unit > 0 and (not best or unit < best or (unit == best and r.containsOwnerItem)) then
            best, mine = unit, r.containsOwnerItem
        end
    end
    return best, mine
end

-- objet : le moins cher au même niveau d'objet (sauf qualité Inhabituel, comme la fenêtre de Blizzard)
local function lowestItem(e)
    local api = AH()
    local n = call(api.GetNumItemSearchResults, e.searchKey) or 0
    local best, mine
    for i = 1, n do
        local r = call(api.GetItemSearchResultInfo, e.searchKey, i)
        local buyout = r and tonumber(r.buyoutAmount)
        if buyout and buyout > 0 and (e.ignoreLevel or not r.itemKey or r.itemKey.itemLevel == e.ilvl) then
            if not best or buyout < best or (buyout == best and r.containsOwnerItem) then
                best, mine = buyout, r.containsOwnerItem
            end
        end
    end
    return best, mine
end

local function setGroupStatus(group, from, to)
    for _, x in ipairs(entries) do
        if x.group == group and x.status == from then x.status = to end
    end
end

local function readResults(e)
    for _, x in ipairs(entries) do
        if x.group == e.group and x.status == "query" then
            if x.commodity then
                applyResult(x, lowestCommodity(x))
            else
                applyResult(x, lowestItem(x))
            end
        end
    end
end

local nextQuery

local function finishScan()
    scanning = false
    local ready, total, unchecked = 0, 0, 0
    for _, e in ipairs(entries) do
        if e.status == "ready" and e.checked then
            ready = ready + 1
            total = total + e.price * e.count
        elseif e.status == "ready" then
            unchecked = unchecked + 1
        end
    end
    local text = ns.T("HDV : prix trouvés.") .. " "
    if ready > 0 then
        text = text .. ns.Tf("%d objet(s) coché(s) prêt(s) pour environ %s : un clic sur « Mettre en vente » (ou ta touche) par objet.",
            ready, money(total))
    else
        text = text .. ns.T("Coche les objets à vendre (clic sur la ligne) : tes choix sont retenus pour la prochaine fois.")
    end
    if ready > 0 and unchecked > 0 then
        text = text .. " " .. ns.Tf("%d autre(s) à cocher si tu veux.", unchecked)
    end
    ns:Print(text)
    -- puis le scan complet de l'HDV (prix de tout : infobulles, recettes), au plus une fois par heure
    if ns.Prices and ns.Prices:ShouldAutoScan() then ns.Prices:FullScan(true) end
end

local function onQueryTimeout(e, gen)
    if gen ~= generation or current ~= e then return end
    current = nil
    -- résultats arrivés sans l'événement attendu ?
    if call(AH().HasSearchResults, e.searchKey) then
        readResults(e)
    end
    setGroupStatus(e.group, "query", "noanswer")
    refresh()
    nextQuery()
end

-- Peut-on envoyer une recherche maintenant ? Sinon, dans combien de secondes réessayer
local function queryDelay()
    local t = GetTime()
    while sentTimes[1] and t - sentTimes[1] >= 60 do table.remove(sentTimes, 1) end
    if #sentTimes >= PER_MINUTE then return sentTimes[1] + 60 - t + 0.05 end
    if call(AH().IsThrottledMessageSystemReady) == false then return 0.5 end   -- l'événement READY arrive souvent avant
    return 0
end

local function retryLater(delay)
    local gen = generation
    C_Timer.After(delay, function() if gen == generation then nextQuery() end end)
end

-- a. recherche groupée : tous les objets en attente, sauf l'équipement
local function browseDone()
    if not browsing then return end
    browsing = false
    local byKey, byItem = {}, {}
    for _, r in ipairs(call(AH().GetBrowseResults) or {}) do
        if type(r) == "table" and type(r.itemKey) == "table" then
            byKey[keyString(r.itemKey)] = r
            byItem[r.itemKey.itemID] = byItem[r.itemKey.itemID] or r
        end
    end
    for _, e in ipairs(entries) do
        if e.status == "query" and e.inBrowse then
            e.inBrowse = nil
            local r = byKey[keyString(e.searchKey)] or byItem[e.id]
            local minPrice = r and tonumber(r.minPrice)
            if minPrice and minPrice > 0 and not r.containsOwnerItem then
                applyResult(e, minPrice, false)
            else
                -- absent de la réponse, ou une vente est à toi : recherche détaillée pour cet objet
                e.status = "wait"
                e.needDetail = true
            end
        end
    end
    refresh()
    nextQuery()
end

local function startBrowse()
    local api = AH()
    if not (api and api.SearchForItemKeys and api.GetBrowseResults) then return false end
    local keys, seen = {}, {}
    for _, e in ipairs(entries) do
        if e.status == "wait" and not e.equipment and not e.needDetail and not seen[e.group] then
            seen[e.group] = true
            keys[#keys + 1] = copyKey(e.searchKey)
        end
    end
    if #keys < 2 then return false end   -- un seul objet : la recherche détaillée est aussi rapide
    if not try(api.SearchForItemKeys, keys, SORTS) then return false end
    sentTimes[#sentTimes + 1] = GetTime()
    browsing = true
    for _, e in ipairs(entries) do
        if seen[e.group] and e.status == "wait" then
            e.status, e.inBrowse = "query", true
        end
    end
    local gen = generation
    C_Timer.After(BROWSE_TIMEOUT, function() if gen == generation then browseDone() end end)
    refresh()
    return true
end

nextQuery = function()
    if not (isOpen and scanning) or current or browsing then return end
    -- les objets cochés d'abord : ce sont ceux que tu vas mettre en vente
    local e
    for _, x in ipairs(entries) do
        if x.status == "wait" and (x.checked or not e) then
            e = x
            if x.checked then break end
        end
    end
    if not e then
        finishScan()
        refresh()
        return
    end
    local delay = queryDelay()
    if delay > 0 then return retryLater(delay) end
    if not e.equipment and not e.needDetail and startBrowse() then return end

    -- b. recherche détaillée d'un objet
    local api = AH()
    setGroupStatus(e.group, "wait", "query")
    current = e
    sentTimes[#sentTimes + 1] = GetTime()
    local sent
    if e.equipment then
        sent = try(api.SendSellSearchQuery, e.searchKey, SORTS, true)
    else
        sent = try(api.SendSearchQuery, e.searchKey, SORTS, true)
    end
    if not sent then
        current = nil
        setGroupStatus(e.group, "query", "noanswer")
        refresh()
        return retryLater(0.2)
    end
    local gen = generation
    C_Timer.After(QUERY_TIMEOUT, function() onQueryTimeout(e, gen) end)
    refresh()
end

local function onCommodityResults(itemID)
    local e = current
    if not (e and e.commodity and e.id == itemID) then return end
    current = nil
    readResults(e)
    refresh()
    nextQuery()
end

local function onItemResults(itemKey)
    local e = current
    if not (e and not e.commodity) then return end
    if type(itemKey) == "table" and itemKey.itemID and itemKey.itemID ~= e.id then return end
    current = nil
    readResults(e)
    refresh()
    nextQuery()
end

-- Relit les sacs ; withPrices = relance aussi la recherche des prix
function Auction:Rescan(withPrices)
    if not isOpen then
        ns:Print(ns.T("ouvre d'abord l'hôtel des ventes"))
        return
    end
    generation = generation + 1
    current, scanning, browsing = nil, false, false
    local api = AH()
    step = (api and call(api.SupportsCopperValues)) and 1 or SILVER
    local list, unknown = self:ScanBags()
    entries = list
    if unknown and not retriedUnknown then
        -- certains objets n'étaient pas encore chargés par le jeu : un second passage un peu plus tard
        retriedUnknown = true
        local gen = generation
        C_Timer.After(1.5, function()
            if gen == generation and isOpen then Auction:Rescan(withPrices) end
        end)
    end
    if withPrices and #entries > 0 then
        scanning = true
        nextQuery()
    end
    refresh()
end

-- Prix recalculés sans nouvelle recherche (après un changement de réglage)
function Auction:Reprice()
    for _, e in ipairs(entries) do
        if e.searched and (e.status == "ready" or e.status == "low" or e.status == "noref") then price(e) end
    end
    refresh()
end

---------------------------------------------------------------------------
-- Mise en vente (un appel = une action du joueur)
---------------------------------------------------------------------------
local function slotMatches(e, bag, slot)
    local info = call(C_Container.GetContainerItemInfo, bag, slot)
    if not info or info.itemID ~= e.id or info.isLocked then return false end
    if not e.commodity and info.hyperlink ~= e.link then return false end
    return true
end

-- Emplacement actuel de l'objet (il a pu bouger depuis le scan) et quantité à mettre en vente
local function locate(e)
    if not slotMatches(e, e.bag, e.slot) then
        local found = false
        for bag = BAG_FIRST, BAG_LAST do
            local slots = call(C_Container.GetContainerNumSlots, bag) or 0
            for slot = 1, slots do
                if slotMatches(e, bag, slot) then
                    e.bag, e.slot, found = bag, slot, true
                    break
                end
            end
            if found then break end
        end
        if not found then return nil end
    end
    local loc = itemLocation(e.bag, e.slot)
    if not sellable(loc) then return nil end
    local qty
    if e.commodity then
        local available = call(AH().GetAvailablePostCount, loc)
        qty = (tonumber(available) and available > 0) and available or e.count
    else
        local info = call(C_Container.GetContainerItemInfo, e.bag, e.slot)
        qty = info and info.stackCount or 1
    end
    return loc, qty
end

local function hideBlizzardWarning()
    -- la fenêtre de Blizzard confirmerait SA propre vente (vide ici) : on la ferme, le clic suivant confirme la nôtre
    C_Timer.After(0, function()
        if type(StaticPopup_Hide) == "function" then pcall(StaticPopup_Hide, "AUCTION_HOUSE_POST_WARNING") end
    end)
end

local function unqueue(e)
    for i = #posting, 1, -1 do
        if posting[i] == e then table.remove(posting, i) end
    end
end

-- le plus ancien objet encore « envoi... » (les réponses du serveur arrivent dans l'ordre des envois)
local function oldestPosting()
    while posting[1] and posting[1].status ~= "posting" do table.remove(posting, 1) end
    return table.remove(posting, 1)
end

local function checkPosted(e, token)
    if e.status ~= "posting" or e.postToken ~= token then return end
    unqueue(e)
    -- pas de « vente créée » reçu : l'objet a-t-il quitté son emplacement ?
    if slotMatches(e, e.bag, e.slot) then
        e.status = "error"
        e.note = "pas de réponse du serveur"
    else
        e.status = "done"
    end
    refresh()
end

local function startInflight(e)
    posting[#posting + 1] = e
    e.status = "posting"
    e.postToken = (e.postToken or 0) + 1
    local token = e.postToken
    C_Timer.After(POST_TIMEOUT, function() checkPosted(e, token) end)
end

local function fail(e, why)
    e.status = "error"
    e.note = why
    if why then
        ns:Print(ns.Tf("HDV : %s refusé (%s)", tostring(e.link or e.name), type(why) == "string" and ns.T(why) or tostring(why)))
    else
        ns:Print(ns.Tf("HDV : %s refusé", tostring(e.link or e.name)))
    end
end

local function post(e, loc, qty)
    local api = AH()
    local duration = tonumber(db("ahDuration")) or 2
    local fn, args
    if e.commodity then
        fn, args = api.PostCommodity, { loc, duration, qty, e.price, n = 4 }
    else
        fn, args = api.PostItem, { loc, duration, qty, nil, e.price, n = 5 }
    end
    if type(fn) ~= "function" then
        fail(e, "fonction absente du jeu")
        return
    end
    local ok, needsConfirmation = pcall(fn, unpack(args, 1, args.n))
    if not ok then
        fail(e, needsConfirmation)
        return
    end
    e.postedQty = qty
    if needsConfirmation then
        pending = { e = e, commodity = e.commodity, args = args }
        e.status = "confirm"
        ns:Print(ns.Tf("HDV : le jeu demande une confirmation pour %s. Clique encore (ou ta touche) pour confirmer.",
            tostring(e.link or e.name)))
    else
        startInflight(e)
    end
end

local function confirmPending()
    local p = pending
    pending = nil
    local api = AH()
    local fn = p.commodity and api.ConfirmPostCommodity or api.ConfirmPostItem
    local ok, err = false, "fonction absente du jeu"
    if type(fn) == "function" then ok, err = pcall(fn, unpack(p.args, 1, p.args.n)) end
    if ok then startInflight(p.e) else fail(p.e, err) end
end

function Auction:NextReady()
    for _, e in ipairs(entries) do
        if e.status == "ready" and e.checked then return e end
    end
end

-- Appelée par le clic sur le bouton (ou la touche) : une seule mise en vente par appel
function Auction:PostNext()
    if not isOpen then
        ns:Print(ns.T("ouvre d'abord l'hôtel des ventes"))
        return
    end
    if pending then
        confirmPending()
        refresh()
        return
    end
    local uncheckedReady = false
    for _, e in ipairs(entries) do
        if e.status == "ready" and e.checked then
            local loc, qty = locate(e)
            if loc then
                post(e, loc, qty)
                refresh()
                return
            end
            e.status = "gone"
        elseif e.status == "ready" then
            uncheckedReady = true
        end
    end
    refresh()
    if uncheckedReady then
        ns:Print(ns.T("HDV : coche d'abord les objets à mettre en vente (clic sur la ligne)"))
    else
        ns:Print(scanning and ns.T("HDV : recherche des prix en cours, patiente un instant") or ns.T("HDV : rien de prêt à mettre en vente"))
    end
end

-- Coche / décoche un objet : retenu pour les prochaines visites (toutes les lignes du même objet suivent)
function Auction:SetChecked(e, on)
    on = on and true or false
    checkedList()[e.id] = on or nil
    for _, x in ipairs(entries) do
        if x.id == e.id then
            x.checked = on
            if not on and pending and pending.e == x then
                pending = nil
                price(x)
            end
        end
    end
end

function Auction:ToggleCheck(e)
    self:SetChecked(e, not e.checked)
    refresh()
end

-- « Tout cocher » : tous les objets qui ont un prix ; s'ils le sont déjà, tout décocher
function Auction:AllReadyChecked()
    local any = false
    for _, e in ipairs(entries) do
        if e.status == "ready" then
            if not e.checked then return false end
            any = true
        end
    end
    return any
end

function Auction:ToggleAll()
    local on = not self:AllReadyChecked()
    for _, e in ipairs(entries) do
        if e.status == "ready" or not on then self:SetChecked(e, on) end
    end
    refresh()
end

-- Clic droit : ne plus jamais proposer cet objet
function Auction:Exclude(e)
    local never = db("ahNever")
    if type(never) ~= "table" then never = {} end
    never[e.id] = true
    checkedList()[e.id] = nil
    ns:Set("ahNever", never)
    for i = #entries, 1, -1 do
        local x = entries[i]
        if x.id == e.id and x.status ~= "posting" and x.status ~= "done" then
            if pending and pending.e == x then pending = nil end
            table.remove(entries, i)
        end
    end
    ns:Print(ns.Tf("HDV : %s ne sera plus proposé (/pp hdv exclus pour la liste)", tostring(e.link or e.name)))
    refresh()
end

---------------------------------------------------------------------------
-- Touche « mettre en vente le suivant » (seulement pendant que l'HDV est ouvert)
---------------------------------------------------------------------------
local function applyBinding()
    if InCombatLockdown() then return end
    ClearOverrideBindings(events)
    local key = db("ahKey")
    if isOpen and db("ahAssist") and type(key) == "string" and key ~= "" then
        SetOverrideBindingClick(events, true, key, POST_BUTTON)
    end
end

---------------------------------------------------------------------------
-- Panneau
---------------------------------------------------------------------------
local PANEL_W, ROW_H, HEADER_H, FOOTER_H = 350, 38, 66, 112
local rows, offset = {}, 0
local list, title, subtitle, emptyText, summary, postButton, scanButton, allButton, fullButton, keyHint, scrollText

local function anchorPanel()
    local ahFrame = rawget(_G, "AuctionHouseFrame")
    panel:ClearAllPoints()
    local height = 520
    if ahFrame and ahFrame.GetHeight then
        panel:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", 8, 0)
        height = max(380, floor((ahFrame:GetHeight() or 520) + 0.5))
        if ahFrame.GetFrameStrata then panel:SetFrameStrata(ahFrame:GetFrameStrata() or "HIGH") end
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
        panel:SetFrameStrata("HIGH")
    end
    panel:SetHeight(height)
end

local function qualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function showRowTip(row)
    local e = row.entry
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    if e.link then pcall(GameTooltip.SetHyperlink, GameTooltip, e.link) else GameTooltip:SetText(e.name) end
    GameTooltip:AddLine(" ")
    local unit = e.count > 1 and (" " .. ns.T("l'unité")) or ""
    if e.searched then
        if e.lowest then
            GameTooltip:AddDoubleLine(e.mine and ns.T("Moins cher à l'HDV (à toi)") or ns.T("Moins cher à l'HDV"), money(e.lowest) .. unit,
                0.8, 0.8, 0.8, 1, 1, 1)
        else
            GameTooltip:AddLine(ns.T("Personne n'en vend en ce moment."), 0.8, 0.8, 0.8)
        end
    end
    if e.price then
        GameTooltip:AddDoubleLine(ns.T("Ton prix"), money(e.price) .. unit, 0.4, 0.9, 0.5, 1, 1, 1)
        GameTooltip:AddDoubleLine(ns.T("Pour toi (l'HDV garde 5 %)"), money(Auction.NetPrice(e.price)) .. unit,
            0.8, 0.8, 0.8, 1, 1, 1)
        if e.count > 1 then
            GameTooltip:AddDoubleLine(ns.Tf("Total pour %d", e.count), money(e.price * e.count), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        local how = HOW_TEXT[e.how]
        if how then
            GameTooltip:AddLine((ns.T(how):gsub("%%s", (tostring(db("ahNoCompetition") or ""):gsub("%.", ",")))), 0.6, 0.63, 0.7, true)
        end
    end
    if e.vendor and e.vendor > 0 then
        GameTooltip:AddDoubleLine(ns.T("Le marchand t'en donne"), money(e.vendor) .. unit, 0.6, 0.63, 0.7, 0.8, 0.8, 0.8)
    end
    if e.status == "low" then
        GameTooltip:AddLine(ns.T("Même un peu moins cher que les autres, l'HDV te rapporterait autant ou moins que le marchand (il garde 5 %) : vends-le plutôt au marchand."), 1, 0.4, 0.4, true)
    elseif e.status == "noref" then
        GameTooltip:AddLine(ns.T("Personne n'en vend et l'objet n'a pas de prix marchand : mets-le en vente à la main."),
            1, 0.82, 0.2, true)
    elseif e.status == "error" and e.note then
        GameTooltip:AddLine(ns.Tf("Refusé : %s", type(e.note) == "string" and ns.T(e.note) or tostring(e.note)), 1, 0.4, 0.4, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(e.checked and ns.T("Clic : décocher (il ne sera plus mis en vente)")
        or ns.T("Clic : cocher pour le mettre en vente (retenu pour les prochaines fois)"), 0.2, 0.8, 1, true)
    GameTooltip:AddLine(ns.T("Clic droit : ne plus jamais le proposer"), 0.2, 0.8, 1)
    GameTooltip:Show()
end

local CHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"   -- coche classique de Blizzard (NON VÉRIFIÉ sur Forever)

local function paintRowBg(row)
    local C = ns.W.C
    if row.hover then row.bg:SetColor(C.btnHover) else row.bg:SetColor(C.card) end
    local on = row.entry and row.entry.checked
    -- case pleine (couleur Platyplus) + coche quand l'objet est coché ; la couleur suffit si la coche manque
    if on then
        row.boxBg:SetColor(row.hover and C.accentHover or C.accent)
        row.boxStroke:SetColor(C.white, 0)
    else
        row.boxBg:SetColor(row.hover and C.fieldHover or C.field)
        row.boxStroke:SetColor(C.white, row.hover and 0.45 or 0.25)
    end
    row.check:SetShown(on and true or false)
end

local function createRow(i)
    local W, C = ns.W, ns.W.C
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H - 4)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = W.Round(row, "BACKGROUND", 0, 6)
    -- case à cocher (dessinée : aucun modèle Blizzard)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.boxBg = W.Round(box, "ARTWORK", 0, 4)
    row.boxStroke = W.Stroke(box, "OVERLAY", 0, 4)
    row.check = box:CreateTexture(nil, "OVERLAY", nil, 2)
    row.check:SetSize(20, 20)
    row.check:SetPoint("CENTER", box, "CENTER", 1, 0)
    row.check:SetTexture(CHECK_TEX)
    if row.check.SetDesaturated then row.check:SetDesaturated(true) end
    row.check:SetVertexColor(C.ink[1], C.ink[2], C.ink[3], 1)
    row.icon = W.Icon(row, ROW_H - 12)
    row.icon:SetPoint("LEFT", box, "RIGHT", 8, 0)
    row.name = W.Text(row, "GameFontHighlight", C.text, nil, 12)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -104, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = W.Text(row, "GameFontHighlightSmall", C.dim, nil, 10)
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -104, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.price = W.Text(row, "GameFontHighlight", C.text, nil, 12)
    row.price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.price:SetJustifyH("RIGHT")
    row.state = W.Text(row, "GameFontHighlightSmall", C.dim, nil, 10)
    row.state:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 5)
    row.state:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self) self.hover = true paintRowBg(self) showRowTip(self) end)
    row:SetScript("OnLeave", function(self)
        self.hover = false
        paintRowBg(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self, button)
        if not self.entry then return end
        if button == "RightButton" then Auction:Exclude(self.entry) else Auction:ToggleCheck(self.entry) end
        if self.hover and self.entry then showRowTip(self) end
    end)
    paintRowBg(row)
    return row
end

local function visibleRows()
    local h = list:GetHeight()
    if not h or h < ROW_H then h = (panel:GetHeight() or 520) - HEADER_H - FOOTER_H end
    return max(1, floor(h / ROW_H))
end

local function paintPostButton(b)
    local C = ns.W.C
    local bg, txt = C.btnOff, C.off
    if b.state == "confirm" then
        bg = b.hover and C.dangerHover or C.gold
        txt = C.ink
    elseif b.state == "ready" then
        bg = b.down and C.accentDown or (b.hover and C.accentHover or C.accent)
        txt = C.ink
    end
    b.bg:SetColor(bg)
    ns.W.TextColor(b.label, txt)
end

local function createPanel()
    local W, C = ns.W, ns.W.C
    panel = CreateFrame("Frame", "PlatyplusAHPanel", UIParent)
    panel:SetSize(PANEL_W, 520)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    W.Shadow(panel, 14, 18, 4)
    W.Round(panel, "BACKGROUND", 0, 10):SetColor(C.bg)
    W.Stroke(panel, "BORDER", 0, 10):SetColor(C.white, 0.07)

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
    logo:SetTexture(ns.LOGO)
    title = W.Text(panel, "GameFontHighlightLarge", C.text, nil, 15)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
    title:SetText(ns.T("Hôtel des ventes"))
    subtitle = W.Text(panel, "GameFontHighlightSmall", C.dim, nil, 11)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(false)

    -- scan complet de l'HDV (tous les prix : infobulles et coût des recettes)
    fullButton = W.Button(panel, {
        text = "Scan complet", height = 22, width = 104,
        tip = "Relève le prix de TOUT ce qui est en vente à l'HDV, d'un coup : il sert aux infobulles de tes objets et au "
            .. "coût des recettes dans la fenêtre de métier. Le serveur ne l'autorise qu'une fois toutes les 15 min. "
            .. "Il se lance seul à l'ouverture de l'HDV si le dernier date de plus d'une heure.",
        onClick = function() if ns.Prices then ns.Prices:FullScan() end end,
    })
    fullButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -14)
    title:SetPoint("RIGHT", fullButton, "LEFT", -6, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -HEADER_H)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, FOOTER_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        refresh()
    end)
    emptyText = W.Text(list, "GameFontHighlight", C.dim, nil, 12)
    emptyText:SetPoint("TOPLEFT", list, "TOPLEFT", 12, -20)
    emptyText:SetPoint("RIGHT", list, "RIGHT", -12, 0)
    emptyText:SetJustifyH("CENTER")
    scrollText = W.Text(panel, "GameFontHighlightSmall", C.dim, nil, 10)
    scrollText:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -2, 4)

    summary = W.Text(panel, "GameFontHighlightSmall", C.text, nil, 11)
    summary:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, FOOTER_H - 22)
    summary:SetPoint("RIGHT", panel, "RIGHT", -110, 0)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    local hint = CreateFrame("Frame", nil, panel)
    hint:SetSize(100, 16)
    hint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, FOOTER_H - 24)
    keyHint = W.Text(hint, "GameFontHighlightSmall", C.dim, nil, 10)
    keyHint:SetAllPoints(hint)
    keyHint:SetJustifyH("RIGHT")
    W.SetTip(hint, ns.T("Une mise en vente par clic"),
        ns.Tf("Blizzard exige un clic ou une touche pour chaque mise en vente : aucun addon ne peut tout poster seul. Choisis une touche dans /pp > Vente > Hôtel des ventes, ou crée une macro « /click %s ».", POST_BUTTON))

    -- bouton nommé : la touche et la macro /click PlatyplusAHPost cliquent dessus (clic = action du joueur)
    local b = CreateFrame("Button", POST_BUTTON, panel)
    b:SetHeight(36)
    b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 44)
    b:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 44)
    b:RegisterForClicks("AnyUp")
    b.bg = W.Round(b, "BACKGROUND", 0, 8)
    b.label = W.Text(b, "GameFontHighlight", C.ink, nil, 13)
    b.label:SetPoint("LEFT", b, "LEFT", 12, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -12, 0)
    b.label:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) self.hover = true paintPostButton(self) end)
    b:SetScript("OnLeave", function(self) self.hover, self.down = false, false paintPostButton(self) end)
    b:SetScript("OnMouseDown", function(self) self.down = true paintPostButton(self) end)
    b:SetScript("OnMouseUp", function(self) self.down = false paintPostButton(self) end)
    b:SetScript("OnClick", function() Auction:PostNext() end)
    postButton = b

    local half = floor((PANEL_W - 24 - 8) / 2)
    scanButton = W.Button(panel, {
        text = "Rechercher à nouveau", height = 26, width = half,
        tip = "Relit tes sacs et redemande les prix à l'hôtel des ventes.",
        onClick = function() Auction:Rescan(true) end,
    })
    scanButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
    allButton = W.Button(panel, {
        text = "Tout cocher", height = 26, width = half,
        tip = "Coche tous les objets qui ont un prix (ou les décoche tous s'ils le sont déjà). "
            .. "Tes choix sont retenus pour les prochaines visites.",
        onClick = function() Auction:ToggleAll() end,
    })
    allButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
end

refresh = function()
    if not (panel and panel:IsShown()) then return end
    local n = visibleRows()
    for i = #rows + 1, n do rows[i] = createRow(i) end
    offset = max(0, min(offset, #entries - n))

    local counts = { ready = 0, done = 0, low = 0, total = 0, unchecked = 0 }
    for _, e in ipairs(entries) do
        if e.status == "ready" and e.checked then
            counts.ready = counts.ready + 1
            counts.total = counts.total + e.price * e.count
        elseif e.status == "ready" then
            counts.unchecked = counts.unchecked + 1
        elseif e.status == "done" then
            counts.done = counts.done + 1
        elseif e.status == "low" then
            counts.low = counts.low + 1
        end
    end

    for i, row in ipairs(rows) do
        local e = (i <= n) and entries[offset + i] or nil
        row.entry = e
        if e then
            row:Show()
            row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(e.name)
            row.name:SetTextColor(qualityColor(e.quality))
            local sub = "x" .. e.count
            if not e.commodity and e.equipment and (e.ilvl or 0) > 0 then sub = sub .. ns.Tf(" · niv. %d", e.ilvl) end
            if e.price and e.count > 1 then sub = sub .. " · " .. money(e.price * e.count) end
            row.sub:SetText(sub)
            row.price:SetText(e.price and money(e.price) or "|cff888888-|r")
            row.state:SetText(Auction:StatusText(e))
            local faded = e.status == "done" or e.status == "gone"
            row:SetAlpha(faded and 0.5 or (e.checked and 1 or 0.8))
            paintRowBg(row)
        else
            row:Hide()
        end
    end

    if #entries == 0 then
        emptyText:SetText(isOpen and ns.T("Rien à proposer : aucun objet de tes sacs ne peut aller à l'HDV (objets liés, équipement blanc ou gris, outils de métier, ou objets exclus).") or "")
        emptyText:Show()
    else
        emptyText:Hide()
    end
    scrollText:SetText(#entries > n and ((offset + 1) .. "-" .. min(#entries, offset + n) .. " / " .. #entries) or "")

    local searching = 0
    for _, e in ipairs(entries) do
        if e.status == "wait" or e.status == "query" then searching = searching + 1 end
    end
    local fullState, fullDone, fullTotal = "idle", 0, 0
    if ns.Prices then fullState, fullDone, fullTotal = ns.Prices:ScanState() end
    if scanning then
        subtitle:SetText(ns.Tf("recherche des prix... encore %d", searching))
    elseif fullState == "waiting" then
        subtitle:SetText(ns.T("scan complet de l'HDV : en attente du serveur..."))
    elseif fullState == "reading" then
        subtitle:SetText(ns.Tf("scan complet de l'HDV : %d %%", floor(fullDone * 100 / max(1, fullTotal))))
    else
        subtitle:SetText(ns.Tf("%d objet(s) dans tes sacs · %d mis en vente", #entries, counts.done))
    end
    summary:SetText(colorText("good", ns.Tf("%d coché(s) prêt(s)", counts.ready))
        .. (counts.ready > 0 and (" · " .. money(counts.total)) or ""))

    local nextE = Auction:NextReady()
    if pending then
        postButton.state = "confirm"
        postButton.label:SetText(ns.Tf("Confirmer : %s", tostring(pending.e.name)))
    elseif nextE then
        postButton.state = "ready"
        postButton.label:SetText(nextE.count > 1 and ns.Tf("Mettre en vente : %s x%d", tostring(nextE.name), nextE.count)
            or ns.Tf("Mettre en vente : %s", tostring(nextE.name)))
    else
        postButton.state = "none"
        postButton.label:SetText(scanning and ns.T("Recherche des prix...")
            or (counts.unchecked > 0 and ns.T("Coche les objets à vendre") or ns.T("Rien à mettre en vente")))
    end
    paintPostButton(postButton)
    allButton:SetLabel(Auction:AllReadyChecked() and ns.T("Tout décocher") or ns.T("Tout cocher"))

    local key = db("ahKey")
    keyHint:SetText((type(key) == "string" and key ~= "") and ns.Tf("Touche : %s", colorText("accent", key)) or ns.T("1 clic = 1 vente"))
end

function Auction:Refresh()
    refresh()
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local function onShow()
    isOpen = true
    retriedUnknown = false
    offset = 0
    if not db("ahAssist") then return end
    -- le panneau de Blizzard est chargé à la demande : on attend l'image suivante pour s'y accrocher
    C_Timer.After(0, function()
        if not isOpen or not db("ahAssist") then return end
        if not (ns.W and ns.W.C) then return end
        if not panel then createPanel() end
        anchorPanel()
        panel:Show()
        applyBinding()
        Auction:Rescan(db("ahAutoScan") and true or false)
    end)
end

local function onClosed()
    isOpen = false
    generation = generation + 1
    scanning, current, browsing, pending = false, nil, false, nil
    wipe(posting)
    wipe(entries)
    if panel then panel:Hide() end
    applyBinding()
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        onShow()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        onClosed()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        onCommodityResults(...)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        onItemResults(...)
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        browseDone()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        nextQuery()
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        local e = oldestPosting()
        if e then
            e.status = "done"
            refresh()
        end
    elseif event == "AUCTION_HOUSE_POST_WARNING" then
        if pending then hideBlizzardWarning() end
    elseif event == "AUCTION_HOUSE_POST_ERROR" or event == "AUCTION_HOUSE_SHOW_ERROR" then
        local e = oldestPosting()
        if e then
            fail(e, "erreur de l'hôtel des ventes")
            refresh()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        applyBinding()
    end
end)

---------------------------------------------------------------------------
-- Commande /pp hdv
---------------------------------------------------------------------------
function Auction:Command(arg)
    local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "scan" or cmd == "rescan" then
        self:Rescan(true)
    elseif cmd == "on" or cmd == "off" then
        ns:Set("ahAssist", cmd == "on")
        ns:Print(ns.T("assistant d'hôtel des ventes :"), cmd == "on" and "|cff00ff00ON|r" or "|cffff4040OFF|r")
    elseif cmd == "touche" or cmd == "key" then
        rest = strtrim(rest or "")
        if rest == "" then
            ns:Print(ns.T("usage : /pp hdv touche F   (ou MOUSEWHEELDOWN, SHIFT-F... ; off pour aucune)"))
            return
        end
        ns:Set("ahKey", rest:lower() == "off" and "" or rest:upper())
        ns:Print(ns.T("touche de mise en vente :"), db("ahKey") ~= "" and db("ahKey") or ns.T("aucune"))
    elseif cmd == "complet" or cmd == "full" then
        if ns.Prices then ns.Prices:FullScan() end
    elseif cmd == "exclus" or cmd == "never" then
        if rest:lower() == "vider" or rest:lower() == "clear" then
            ns:Set("ahNever", {})
            ns:Print(ns.T("liste « jamais à l'HDV » vidée"))
            return
        end
        local ids = {}
        for id, on in pairs(type(db("ahNever")) == "table" and db("ahNever") or {}) do
            if on then ids[#ids + 1] = tonumber(id) or id end
        end
        if #ids == 0 then ns:Print(ns.T("aucun objet exclu de l'HDV")) return end
        ns:Print(ns.Tf("%d objet(s) jamais proposé(s) à l'HDV (/pp hdv exclus vider pour tout reprendre) :", #ids))
        for _, id in ipairs(ids) do
            local name = C_Item and C_Item.GetItemNameByID and call(C_Item.GetItemNameByID, id)
            print("  " .. tostring(name or ns.Tf("objet #%s", tostring(id))))
        end
    else
        local key = db("ahKey")
        ns:Print(ns.T("hôtel des ventes : un panneau s'ouvre à côté de l'HDV et cherche les prix de tes objets. Coche ceux à vendre (retenu pour la prochaine fois), puis un clic ou une touche par objet (règle de Blizzard)."))
        print(ns.T("  /pp hdv scan            relit les sacs et redemande les prix (HDV ouvert)"))
        print(ns.T("  /pp hdv complet         scan complet : le prix de tout l'HDV (infobulles, recettes ; 1 fois / 15 min)"))
        print(ns.Tf("  /pp hdv touche <TOUCHE> touche de mise en vente pendant que l'HDV est ouvert (actuelle : %s)",
            (type(key) == "string" and key ~= "") and key or ns.T("aucune")))
        print(ns.T("  /pp hdv exclus [vider]  objets jamais proposés (clic droit sur une ligne pour en ajouter)"))
        print(ns.T("  /pp hdv on|off          active / coupe l'assistant"))
        print(ns.Tf("  macro : /click %s   (= le bouton « Mettre en vente »)", POST_BUTTON))
    end
end

function Auction:Init()
    for _, event in ipairs({
        "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
        "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_WARNING",
        "AUCTION_HOUSE_POST_ERROR", "AUCTION_HOUSE_SHOW_ERROR", "PLAYER_REGEN_ENABLED",
        "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_FAILURE",
    }) do
        pcall(events.RegisterEvent, events, event)   -- un événement inconnu du client est ignoré
    end
    ns:OnChange("ahKey", applyBinding)
    ns:OnChange("ahAssist", function(_, on)
        if not isOpen then return end
        if on then onShow() else
            generation = generation + 1
            scanning, current, browsing, pending = false, nil, false, nil
            if panel then panel:Hide() end
            applyBinding()
        end
    end)
    for _, key in ipairs({ "ahUndercut", "ahVendorCheck", "ahNoCompetition" }) do
        ns:OnChange(key, function() Auction:Reprice() end)
    end
    ns:OnChange("ahGearMinQuality", function() if isOpen and db("ahAssist") then Auction:Rescan(true) end end)
    ns:OnChange("ahChecked", function()
        for _, e in ipairs(entries) do e.checked = checkedList()[e.id] and true or false end
        refresh()
    end)
    ns:OnChange("ahNever", function() refresh() end)
    if ns.Prices and ns.Prices.OnUpdate then ns.Prices:OnUpdate(function() refresh() end) end
end
