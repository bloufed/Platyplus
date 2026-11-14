-- Test : hôtel des ventes (Auction.lua) dans le simulateur
--  * calcul des prix (fonction pure) : au cuivre près, « jamais moins que le marchand » (l'HDV garde 5 %)
--  * scan des sacs : liés, ensemble d'équipement, équipement blanc, outils de métier, marchandises regroupées
--  * cases à cocher : rien n'est mis en vente sans être coché, choix retenus d'une visite à l'autre, « Tout cocher »
--  * recherche des prix : une recherche groupée (SearchForItemKeys), puis une par objet restant, sans attente inutile
--  * mise en vente : un clic = une vente, clics enchaînés sans attendre le serveur, confirmation demandée par le jeu,
--    touche liée seulement HDV ouvert
-- Usage : python -I dev\lua.py run dev\test_auction.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

---------------------------------------------------------------------------
-- Faux jeu : sacs, objets, HDV
---------------------------------------------------------------------------
local ORE, SWORD, BOUND, HERB, CLOTH, HELM, SETITEM, POTION = 2770, 100, 300, 765, 2589, 200, 400, 118
local WHITE, PICK, POLE, PROTOOL = 101, 2901, 6367, 500
local ITEMS = {
    [ORE]     = { name = "Minerai de cuivre", quality = 1, vendor = 5, commodity = true },
    [SWORD]   = { name = "Epee verte", quality = 2, vendor = 5000, ilvl = 30, class = 2 },
    [BOUND]   = { name = "Anneau lie", quality = 3, vendor = 900, class = 4 },
    [HERB]    = { name = "Pacifique", quality = 1, vendor = 0, commodity = true },
    [CLOTH]   = { name = "Etoffe de lin", quality = 1, vendor = 13, commodity = true },
    [HELM]    = { name = "Heaume rare", quality = 3, vendor = 20000, ilvl = 50, class = 4 },
    [SETITEM] = { name = "Bottes du set", quality = 3, vendor = 800, ilvl = 40, class = 4 },
    [POTION]  = { name = "Potion mineure", quality = 1, vendor = 1, commodity = true },
    [WHITE]   = { name = "Epee blanche", quality = 1, vendor = 300, ilvl = 10, class = 2, sub = 7 },
    [PICK]    = { name = "Pioche de mineur", quality = 1, vendor = 16, class = 2, sub = 14 },
    [POLE]    = { name = "Canne a peche verte", quality = 2, vendor = 900, class = 2, sub = 20 },
    [PROTOOL] = { name = "Outil de metier", quality = 2, vendor = 900, class = 19 },
}
local function link(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. ITEMS[id].name .. "]|h|r" end

local bag = {   -- sac 0
    { id = ORE, count = 20 }, { id = ORE, count = 15 }, { id = SWORD, count = 1 }, { id = BOUND, count = 1, bound = true },
    { id = HERB, count = 5 }, { id = CLOTH, count = 10 }, { id = HELM, count = 1 }, { id = SETITEM, count = 1, set = true },
    { id = POTION, count = 4 }, { id = WHITE, count = 1 }, { id = PICK, count = 1 }, { id = POLE, count = 1 },
    { id = PROTOOL, count = 1 },
}
local function slotInfo(b, s)
    if b ~= 0 then return nil end
    local x = bag[s]
    if not x then return nil end
    local it = ITEMS[x.id]
    return { itemID = x.id, hyperlink = link(x.id), iconFileID = 1000 + x.id, stackCount = x.count, quality = it.quality,
        isBound = x.bound or false, itemName = it.name, isLocked = false }
end

def("C_Container", {
    GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
    GetContainerItemInfo = slotInfo,
    GetContainerItemEquipmentSetInfo = function(b, s) local x = b == 0 and bag[s]; return x and x.set or false, "" end,
})
def("C_Item", {
    GetItemInfo = function(l)
        local id = tonumber(tostring(l):match("item:(%d+)"))
        local it = ITEMS[id]
        if not it then return nil end
        return it.name, l, it.quality, 1, 1, "", "", 20, "", 1, it.vendor, it.class or 7, 0
    end,
    GetItemInfoInstant = function(id)
        id = tonumber(tostring(id):match("(%d+)"))
        local it = ITEMS[id]
        if it then return id, "", "", "", 1000 + id, it.class or 7, it.sub or 0 end
    end,
    GetCurrentItemLevel = function(loc) local x = bag[loc.slot]; return x and ITEMS[x.id].ilvl or 1 end,
    GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id].name end,
    RequestLoadItemDataByID = function() end,
})
def("ItemLocation", {
    CreateFromBagAndSlot = function(_, b, s) return { bag = b, slot = s } end,
})
def("time", function() return 1700000000 end)
local popupsHidden = {}
def("StaticPopup_Hide", function(which) popupsHidden[#popupsHidden + 1] = which end)

-- état de l'HDV simulé
local queries, browses, posts, confirms = {}, {}, {}, {}
local commodityResults = {
    [ORE]    = { { unitPrice = 25, quantity = 40, containsOwnerItem = false },
                 { unitPrice = 19, quantity = 12, containsOwnerItem = false } },   -- pas trié : on prend quand même le min
    [CLOTH]  = { { unitPrice = 5, quantity = 200, containsOwnerItem = false } },
    [HERB]   = {},
    [POTION] = { { unitPrice = 30, quantity = 4, containsOwnerItem = true }, { unitPrice = 34, quantity = 9 } },
}
local itemResults = {
    [SWORD] = { { buyoutAmount = 15000, itemKey = { itemID = SWORD, itemLevel = 28 } },
                { buyoutAmount = 14000, itemKey = { itemID = SWORD, itemLevel = 33 } } },
    [HELM]  = { { buyoutAmount = 50000, itemKey = { itemID = HELM, itemLevel = 45 } },
                { buyoutAmount = 120000, itemKey = { itemID = HELM, itemLevel = 50 }, containsOwnerItem = true },
                { buyoutAmount = 130000, itemKey = { itemID = HELM, itemLevel = 50 } } },
}
local needConfirm = { [SWORD] = true } -- le jeu demande une confirmation pour l'épée
local lastResults, browseResults = {}, {}
local busyUntil = 0                    -- file de messages de l'HDV occupée jusqu'à cette heure

local function sendQuery(key, sorts, separate, isSell)
    queries[#queries + 1] = { id = key.itemID, t = M.time, ilvl = key.itemLevel, sell = isSell, separate = separate,
        sorts = sorts and #sorts or 0, busy = M.time < busyUntil }
    busyUntil = M.time + 0.15
    lastResults[key.itemID] = true
    M.addTimer(0.15, function()
        if ITEMS[key.itemID].commodity then
            M.fireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID)
        else
            M.fireEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = key.itemID, itemLevel = 0 })
        end
        M.fireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    end)
end

def("C_AuctionHouse", {
    SupportsCopperValues = function() return true end,
    IsSellItemValid = function(loc) local x = bag[loc.slot]; return x ~= nil and not x.bound end,
    GetItemCommodityStatus = function(loc) local x = bag[loc.slot]; return ITEMS[x.id].commodity and 2 or 1 end,
    GetItemKeyFromItem = function(loc)
        local x = bag[loc.slot]
        return { itemID = x.id, itemLevel = ITEMS[x.id].ilvl or 0, itemSuffix = 0, battlePetSpeciesID = 0 }
    end,
    GetItemKeyInfo = function(key) local it = ITEMS[key.itemID]; return { isEquipment = it.class == 2 or it.class == 4 } end,
    IsThrottledMessageSystemReady = function() return M.time >= busyUntil end,
    SendSearchQuery = function(key, sorts, separate) sendQuery(key, sorts, separate, false) end,
    SendSellSearchQuery = function(key, sorts, separate) sendQuery(key, sorts, separate, true) end,
    SearchForItemKeys = function(keys, sorts)
        local ids = {}
        for _, k in ipairs(keys) do ids[#ids + 1] = k.itemID end
        browses[#browses + 1] = { ids = ids, t = M.time, sorts = #sorts }
        busyUntil = M.time + 0.15
        -- réponse : le plus bas prix de chaque objet vendu (l'herbe n'est vendue par personne : absente)
        browseResults = {}
        for _, id in ipairs(ids) do
            local rows = commodityResults[id]
            if rows and #rows > 0 then
                local minPrice, mine = nil, false
                for _, r in ipairs(rows) do
                    if not minPrice or r.unitPrice < minPrice then minPrice = r.unitPrice end
                    if r.containsOwnerItem then mine = true end
                end
                browseResults[#browseResults + 1] = { itemKey = { itemID = id, itemLevel = 0, itemSuffix = 0,
                    battlePetSpeciesID = 0 }, minPrice = minPrice, totalQuantity = 1, containsOwnerItem = mine }
            end
        end
        M.addTimer(0.15, function()
            M.fireEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
            M.fireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        end)
    end,
    GetBrowseResults = function() return browseResults end,
    HasSearchResults = function(key) return lastResults[key.itemID] == true end,
    GetNumCommoditySearchResults = function(id) return #(commodityResults[id] or {}) end,
    GetCommoditySearchResultInfo = function(id, i) return commodityResults[id][i] end,
    GetNumItemSearchResults = function(key) return #(itemResults[key.itemID] or {}) end,
    GetItemSearchResultInfo = function(key, i) return itemResults[key.itemID][i] end,
    GetAvailablePostCount = function(loc)
        local id, n = bag[loc.slot].id, 0
        for _, x in pairs(bag) do if x.id == id then n = n + x.count end end
        return n
    end,
    PostCommodity = function(loc, duration, qty, unit)
        local id = bag[loc.slot].id
        posts[#posts + 1] = { kind = "commodity", id = id, duration = duration, qty = qty, price = unit, t = M.time }
        -- le serveur prend les objets mais n'envoie pas « vente créée » (on teste la minuterie de secours)
        for s, x in pairs(bag) do if x.id == id then bag[s] = nil end end
        return false
    end,
    PostItem = function(loc, duration, qty, bid, buyout)
        local id = bag[loc.slot].id
        posts[#posts + 1] = { kind = "item", id = id, duration = duration, qty = qty, bid = bid, price = buyout, t = M.time }
        return needConfirm[id] == true
    end,
    ConfirmPostItem = function(loc, duration, qty, bid, buyout)
        confirms[#confirms + 1] = { id = bag[loc.slot].id, qty = qty, bid = bid, price = buyout }
    end,
    ConfirmPostCommodity = function() end,
})

-- fenêtre de l'HDV de Blizzard (chargée à la demande dans le vrai jeu)
local ahFrame = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
ahFrame:SetSize(800, 540)

-- réglages d'une version précédente (plancher et qualité minimale retirés) ; l'épée verte déjà cochée
def("PlatyplusDB", { ahFloor = 1.2, ahMinQuality = 1, ahChecked = { [SWORD] = true } })

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Auction.lua", "UIWidgets.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.advance(0.1)
local A = ns.Auction

---------------------------------------------------------------------------
section("calcul des prix")
check(ns.db.ahFloor == nil and ns.db.ahMinQuality == nil and ns.db.ahVendorCheck == true and ns.db.ahGearMinQuality == 2,
    "anciens réglages effacés ; « jamais moins que le marchand » et équipement à partir du vert")
local function cp(o)
    o.undercut = o.undercut or 1
    o.noCompMult = o.noCompMult or 3
    if o.vendorCheck == nil then o.vendorCheck = true end
    o.step = o.step or 1
    return A.ComputePrice(o)
end
local p, how = cp({ lowest = 19, vendor = 5 })
check(p == 18 and how == "undercut", "minerai : 19 pc à l'HDV, 5 pc au marchand -> 18 pc (" .. tostring(p) .. ", " .. tostring(how) .. ")")
p, how = cp({ lowest = 19, mine = true, vendor = 5 })
check(p == 19 and how == "mine", "aligné sur sa propre vente")
p, how = cp({ lowest = 6, vendor = 5 })
check(p == nil and how == "low", "5 pc à l'HDV (4 pc pour toi) contre 5 pc au marchand : pour le marchand")
p, how = cp({ lowest = 6, vendor = 5, vendorCheck = false })
check(p == 5, "« jamais moins que le marchand » coupé : mis en vente quand même (" .. tostring(p) .. ")")
p, how = cp({ lowest = 1, vendor = 0 })
check(p == nil and how == "low", "impossible de passer sous 1 pc")
p, how = cp({ lowest = 2300, vendor = 5, step = 100 })
check(p == 2200, "HDV sans cuivre : au moins 1 pa de moins (" .. tostring(p) .. ")")
p, how = cp({ lowest = 2350, vendor = 5, undercut = 1, step = 100 })
check(p == 2300, "HDV sans cuivre : arrondi à la pa (" .. tostring(p) .. ")")
p, how = cp({ vendor = 5000 })
check(p == 15000 and how == "vendor", "personne n'en vend : prix marchand x 3 (" .. tostring(p) .. ")")
p, how = cp({ vendor = 5000, lastSeen = 42345 })
check(p == 42345 and how == "last", "personne n'en vend : dernier prix vu (" .. tostring(p) .. ")")
p, how = cp({ vendor = 5000, lastSeen = 1000 })
check(p == 15000 and how == "vendor", "dernier prix vu sous le marchand : prix marchand x 3 (" .. tostring(p) .. ")")
p, how = cp({ vendor = 0 })
check(p == nil and how == "noref", "ni concurrence ni prix marchand : pas proposé")
check(A.NetPrice(18) == 17, "18 pc à l'HDV = 17 pc pour toi")

---------------------------------------------------------------------------
section("touche liée seulement pendant que l'HDV est ouvert")
ns:Set("ahKey", "BUTTON4")
check(M.overrides["BUTTON4"] == nil, "HDV fermé : rien de lié")

section("ouverture de l'HDV : scan des sacs")
local openedAt = M.time
M.fireEvent("AUCTION_HOUSE_SHOW")
M.advance(0.05)
local panel = rawget(_G, "PlatyplusAHPanel")
check(panel ~= nil and panel:IsShown(), "panneau affiché à côté de l'HDV")
check(M.overrides["BUTTON4"] == "CLICK PlatyplusAHPost:LeftButton", "touche liée au bouton (" .. tostring(M.overrides["BUTTON4"]) .. ")")
local entries = A:Entries()
local byId = {}
for _, e in ipairs(entries) do byId[e.id] = e end
check(#entries == 6, "6 objets proposés (" .. #entries .. ")")
check(byId[ORE] and byId[ORE].count == 35, "minerai regroupé : 35 (" .. tostring(byId[ORE] and byId[ORE].count) .. ")")
check(byId[BOUND] == nil, "objet lié ignoré")
check(byId[SETITEM] == nil, "objet d'un ensemble d'équipement ignoré")
check(byId[WHITE] == nil, "équipement blanc pas proposé")
check(byId[PICK] == nil, "pioche de mineur pas proposée")
check(byId[POLE] == nil, "canne à pêche (même verte) pas proposée")
check(byId[PROTOOL] == nil, "outil de métier pas proposé")
check(A.HiddenReason(PICK, 1) == "tool" and A.HiddenReason(WHITE, 1) == "gear" and A.HiddenReason(HELM, 3) == nil,
    "raisons : outil, équipement blanc ; heaume rare proposé")
check(entries[1].id == SWORD and entries[2].id == HELM, "objets déjà cochés en premier, puis le plus rare")
check(byId[SWORD].checked and not byId[ORE].checked and not byId[HELM].checked, "seule l'épée cochée (choix retenu)")

section("recherche des prix")
local doneAt
for _ = 1, 100 do
    M.advance(0.05)
    local waiting = false
    for _, e in ipairs(entries) do if e.status == "wait" or e.status == "query" then waiting = true end end
    if not waiting then doneAt = M.time break end
end
check(doneAt and doneAt - openedAt < 1.6, string.format("tous les prix connus en %.2f s", (doneAt or 99) - openedAt))
check(#browses == 1, "une seule recherche groupée (" .. #browses .. ")")
local inBrowse = {}
for _, id in ipairs(browses[1] and browses[1].ids or {}) do inBrowse[id] = true end
check(inBrowse[ORE] and inBrowse[CLOTH] and inBrowse[HERB] and inBrowse[POTION] and not inBrowse[SWORD] and not inBrowse[HELM],
    "recherche groupée : marchandises seulement, pas l'équipement")
local detail = {}
for _, q in ipairs(queries) do detail[q.id] = (detail[q.id] or 0) + 1 end
check(queries[1] and queries[1].id == SWORD, "l'objet coché cherché en premier")
check(not detail[ORE] and not detail[CLOTH], "minerai et étoffe réglés par la recherche groupée")
check(detail[HERB] == 1, "herbe absente de la réponse groupée : recherche détaillée")
check(detail[POTION] == 1, "potion dont une vente est à toi : recherche détaillée")
check(detail[SWORD] == 1 and detail[HELM] == 1, "une recherche par pièce d'équipement")
local busy = false
for _, q in ipairs(queries) do
    if q.busy then busy = true end
    if q.sell then check(q.ilvl == 0, "équipement cherché sans niveau d'objet (" .. q.id .. ")") end
    check(q.separate == true and q.sorts == 2, "recherche avec ses propres ventes séparées et triée par prix (" .. q.id .. ")")
end
check(not busy, "aucune recherche envoyée pendant que la file de l'HDV est occupée")
check(byId[ORE].status == "ready" and byId[ORE].price == 18, "minerai : 19 pc - 1 pc = 18 pc (" .. tostring(byId[ORE].price) .. ")")
check(byId[CLOTH].status == "low", "étoffe à 5 pc, 13 pc au marchand : pour le marchand (" .. tostring(byId[CLOTH].status) .. ")")
check(byId[HERB].status == "noref", "herbe que personne ne vend et sans prix marchand : pas proposée (" .. tostring(byId[HERB].status) .. ")")
check(byId[POTION].status == "ready" and byId[POTION].price == 30 and byId[POTION].mine,
    "potion : aligné sur sa propre vente à 30 pc (" .. tostring(byId[POTION].price) .. ")")
check(byId[SWORD].status == "ready" and byId[SWORD].price == 13999,
    "épée verte : niveau ignoré, 140 pa - 1 pc (" .. tostring(byId[SWORD].price) .. ")")
check(byId[HELM].status == "ready" and byId[HELM].price == 120000 and byId[HELM].mine,
    "heaume : même niveau d'objet, aligné sur sa vente (" .. tostring(byId[HELM].price) .. ")")
check(type(ns.db.ahPrices["c:" .. ORE]) == "table" and ns.db.ahPrices["c:" .. ORE].p == 19, "prix vu mémorisé")
local printedSummary = false
for _, line in ipairs(M.printed) do if line:find("prêt", 1, true) then printedSummary = true end end
check(printedSummary, "résumé du scan dans le chat")

section("réglage changé : prix recalculés sans nouvelle recherche")
local before = #queries + #browses
ns:Set("ahUndercut", 3)
check(byId[ORE].price == 16 and #queries + #browses == before, "minerai à 16 pc avec 3 pc de moins (" .. tostring(byId[ORE].price) .. ")")
ns:Set("ahUndercut", 1)
ns:Set("ahVendorCheck", false)
check(byId[CLOTH].status == "ready" and byId[CLOTH].price == 4, "« jamais moins que le marchand » coupé : étoffe à 4 pc")
ns:Set("ahVendorCheck", true)
check(byId[CLOTH].status == "low", "remis : étoffe pour le marchand")

section("cases à cocher")
local button = rawget(_G, "PlatyplusAHPost")
check(button ~= nil, "bouton nommé PlatyplusAHPost (macro /click)")
A:ToggleAll()
check(byId[ORE].checked and byId[HELM].checked and byId[POTION].checked and not byId[CLOTH].checked and not byId[HERB].checked,
    "« Tout cocher » : tous les objets qui ont un prix (pas ceux pour le marchand ni sans prix)")
check(A:AllReadyChecked(), "tout est coché : le bouton propose « Tout décocher »")
A:ToggleAll()
check(not byId[ORE].checked and not byId[SWORD].checked and next(ns.db.ahChecked) == nil,
    "« Tout décocher » : plus rien de coché ni de retenu")
button:Click()
check(#posts == 0, "rien de coché : aucune mise en vente")
check(M.printed[#M.printed] and M.printed[#M.printed]:find("coche", 1, true) ~= nil, "message « coche d'abord »")
local helmRow
for _, f in ipairs(M.allFrames) do
    if M.state(f).kind == "Button" and f.entry == byId[HELM] then helmRow = f end
end
check(helmRow ~= nil, "ligne du heaume trouvée")
if helmRow then helmRow:Click("LeftButton") end
check(byId[HELM].checked and ns.db.ahChecked[HELM] == true, "clic sur la ligne : heaume coché et retenu")
for _, id in ipairs({ SWORD, ORE, POTION }) do A:ToggleCheck(byId[id]) end
check(ns.db.ahChecked[ORE] and ns.db.ahChecked[SWORD] and ns.db.ahChecked[POTION], "épée, minerai et potions cochés")

section("mise en vente : un clic = une vente, sans attendre le serveur")
button:Click()
check(#posts == 1 and posts[1].id == SWORD and posts[1].price == 13999 and posts[1].kind == "item"
    and posts[1].duration == 2 and posts[1].qty == 1 and posts[1].bid == nil,
    "clic 1 : épée via PostItem(loc, 24 h, 1, sans enchère, 139 pa 99 pc)")
check(byId[SWORD].status == "confirm", "le jeu demande une confirmation pour l'épée")
M.fireEvent("AUCTION_HOUSE_POST_WARNING")
M.advance(0.05)
check(popupsHidden[1] == "AUCTION_HOUSE_POST_WARNING", "fenêtre de confirmation de Blizzard fermée")
button:Click()
check(#confirms == 1 and confirms[1].id == SWORD and confirms[1].price == 13999 and #posts == 1,
    "clic 2 : confirmation envoyée avec les mêmes arguments")
button:Click()
check(#posts == 2 and posts[2].id == HELM and posts[2].price == 120000, "clic 3 tout de suite : heaume, sans attendre le serveur")
button:Click()
check(#posts == 3 and posts[3].kind == "commodity" and posts[3].id == ORE and posts[3].qty == 35 and posts[3].price == 18,
    "clic 4 : les 35 minerais d'un coup via PostCommodity(loc, 24 h, 35, 18 pc)")
button:Click()
check(#posts == 4 and posts[4].id == POTION and posts[4].qty == 4 and posts[4].price == 30, "clic 5 : potions")
M.fireEvent("AUCTION_HOUSE_AUCTION_CREATED", 1)
check(byId[SWORD].status == "done" and byId[HELM].status == "posting", "1re « vente créée » : l'épée (le plus ancien envoi)")
M.fireEvent("AUCTION_HOUSE_AUCTION_CREATED", 2)
check(byId[HELM].status == "done", "2e : le heaume")
M.advance(6)
check(byId[ORE].status == "done" and byId[POTION].status == "done",
    "pas de « vente créée » mais les objets ont quitté les sacs : en vente")

local printedBefore = #M.printed
button:Click()
check(#posts == 4, "plus rien de prêt : aucun appel")
check(#M.printed > printedBefore, "message « rien de prêt »")

section("lignes : exclure")
local rows = 0
for _, f in ipairs(M.allFrames) do
    local s = M.state(f)
    if s.kind == "Button" and s.parent and M.state(s.parent) and M.state(s.parent).parent == panel and s.shown then
        rows = rows + 1
    end
end
check(rows == 6, "6 lignes affichées (" .. rows .. ")")
A:Exclude(byId[HERB])
check(ns.db.ahNever[HERB] == true and #A:Entries() == 5, "clic droit : herbe exclue pour toujours")
ns:ResetAll(true)
check(ns.db.ahNever[HERB] == true and ns.db.ahPrices["c:" .. ORE] ~= nil and ns.db.ahChecked[ORE] == true,
    "réinitialisation : listes, cases cochées et prix vus gardés")

section("recherche groupée sans réponse : repli sur les recherches une par une")
M.fireEvent("AUCTION_HOUSE_CLOSED")
bag[1], bag[2], bag[6] = { id = ORE, count = 7 }, nil, { id = CLOTH, count = 3 }
local realBrowse = C_AuctionHouse.SearchForItemKeys
C_AuctionHouse.SearchForItemKeys = function(keys, sorts) browses[#browses + 1] = { ids = {}, t = M.time } end
queries = {}
M.fireEvent("AUCTION_HOUSE_SHOW")
M.advance(6)
entries = A:Entries()
byId = {}
for _, e in ipairs(entries) do byId[e.id] = e end
check(byId[ORE] and byId[ORE].status == "ready" and byId[ORE].price == 18, "minerai quand même trouvé (" .. tostring(byId[ORE] and byId[ORE].status) .. ")")
check(byId[ORE] and byId[ORE].checked, "visite suivante : le minerai est toujours coché")
check(#queries >= 2, "recherches détaillées après 4 s sans réponse (" .. #queries .. ")")
C_AuctionHouse.SearchForItemKeys = realBrowse

section("fermeture")
ns:Set("ahKey", "BUTTON4")
M.fireEvent("AUCTION_HOUSE_CLOSED")
check(not panel:IsShown(), "panneau caché")
check(M.overrides["BUTTON4"] == nil, "touche rendue")
check(#A:Entries() == 0, "liste vidée")

section("commande /pp hdv")
SlashCmdList["PLATYPLUS"]("hdv")
SlashCmdList["PLATYPLUS"]("hdv exclus")
SlashCmdList["PLATYPLUS"]("hdv touche off")
check(ns.db.ahKey == "", "/pp hdv touche off")

M.report()
M.realPrint(#failures == 0 and "TOUT EST BON" or (#failures .. " échec(s)"))
