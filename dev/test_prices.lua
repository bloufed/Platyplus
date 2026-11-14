-- Test : prix de l'HDV partout (Prices.lua, Craft.lua) dans le simulateur
--  * base de prix : enregistrement, âge, coût le moins cher entre HDV et marchand
--  * scan complet de l'HDV (ReplicateItems) lu par paquets, prix le plus bas à l'unité, attente de 15 min du serveur
--  * prix d'achat relevés chez les marchands
--  * ligne « HDV » dans les infobulles (unité, et pile entière depuis un sac)
--  * coût d'une recette face à l'HDV et carte à côté de la fenêtre de métier
-- Usage : python -I dev\lua.py run dev\test_prices.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

---------------------------------------------------------------------------
-- Faux jeu
---------------------------------------------------------------------------
local ORE, BAR, THREAD, BRACER, HERB, POTION, GEM_A, GEM_B, RING, OPTIONAL = 2770, 2840, 2320, 2853, 765, 118, 801, 802, 900, 950
local NAMES = { [ORE] = "Minerai de cuivre", [BAR] = "Barre de cuivre", [THREAD] = "Fil grossier", [BRACER] = "Bracelets en cuivre",
    [HERB] = "Pacifique", [POTION] = "Potion mineure", [GEM_A] = "Gemme A", [GEM_B] = "Gemme B", [RING] = "Anneau", [OPTIONAL] = "Optionnel" }
local clock = 1700000000
def("time", function() return clock end)
def("GetRealmName", function() return "Forever" end)
def("UnitFactionGroup", function() return "Alliance" end)
def("C_Item", {
    GetItemNameByID = function(id) return NAMES[id] end,
    GetItemQualityByID = function() return 1 end,
    RequestLoadItemDataByID = function() end,
    GetItemInfoInstant = function(id) return id, "", "", "", 1000, 7, 0 end,
})
def("C_Container", {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemInfo = function(bag, slot) if bag == 0 and slot == 3 then return { itemID = ORE, stackCount = 20 } end end,
})
-- vrai hooksecurefunc (le simulateur n'en fait rien par défaut)
def("hooksecurefunc", function(t, name, fn)
    local orig = t[name]
    t[name] = function(...) local a, b, c = orig(...); fn(...); return a, b, c end
end)

-- HDV : scan complet simulé (4 000 lignes : plusieurs paquets)
local replicate, replicateCalls = {}, 0
local function addAuction(itemID, count, buyout) replicate[#replicate + 1] = { itemID = itemID, count = count, buyout = buyout } end
addAuction(ORE, 20, 400)      -- 20 pc l'unité
addAuction(ORE, 10, 190)      -- 19 pc : le moins cher
addAuction(ORE, 5, 0)         -- enchère seule : ignorée
addAuction(BAR, 1, 160)
addAuction(BAR, 4, 600)       -- 150 l'unité
addAuction(THREAD, 1, 50)     -- plus cher que le marchand (10)
addAuction(BRACER, 1, 2000)
addAuction(GEM_A, 1, 50)
addAuction(GEM_B, 1, 40)
for i = 1, 3991 do addAuction(5000 + (i % 50), 1, 1000 + i) end
def("C_AuctionHouse", {
    ReplicateItems = function()
        replicateCalls = replicateCalls + 1
        M.addTimer(0.3, function() M.fireEvent("REPLICATE_ITEM_LIST_UPDATE") end)
    end,
    GetNumReplicateItems = function() return #replicate end,
    GetReplicateItemInfo = function(i)
        local r = replicate[i + 1]   -- index à partir de 0, comme le jeu
        if not r then return nil end
        return "nom", 1, r.count, 1, true, 1, "", 0, 0, r.buyout, 0, nil, nil, "vendeur", nil, 0, r.itemID, true
    end,
})

-- marchand : fil grossier 10 pc l'unité (vendu par 5 à 50 pc), un objet payé en monnaie spéciale ignoré
local merchant = {
    { link = "|Hitem:" .. THREAD .. "::|h", info = { price = 50, stackCount = 5, hasExtendedCost = false } },
    { link = "|Hitem:" .. POTION .. "::|h", info = { price = 0, stackCount = 1, hasExtendedCost = true } },
}
def("GetMerchantNumItems", function() return #merchant end)
def("GetMerchantItemLink", function(i) return merchant[i] and merchant[i].link end)
def("C_MerchantFrame", { GetItemInfo = function(i) return merchant[i].info end })

-- infobulles : on capture la fonction inscrite et les lignes ajoutées
local tooltipFn, tooltipType
def("TooltipDataProcessor", { AddTooltipPostCall = function(t, fn) tooltipType, tooltipFn = t, fn end })
Enum.TooltipDataType = { Item = 0 }
Enum.CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2 }
local tipLines = {}
GameTooltip.AddDoubleLine = function(_, l, r) tipLines[#tipLines + 1] = { l, r } end

-- métiers : recettes simulées
local schematics = {
    [10] = { outputItemID = BRACER, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
        { reagentType = 1, quantityRequired = 2, reagents = { { itemID = BAR } } },
        { reagentType = 1, quantityRequired = 1, reagents = { { itemID = THREAD } } },
        { reagentType = 0, quantityRequired = 1, reagents = { { itemID = OPTIONAL } } },   -- optionnel : ignoré
    } },
    [11] = { outputItemID = RING, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
        { reagentType = 1, quantityRequired = 1, reagents = { { itemID = GEM_A }, { itemID = GEM_B } } },
    } },
    [12] = { outputItemID = nil, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
        { reagentType = 1, quantityRequired = 3, reagents = { { itemID = HERB } } },
    } },
    [13] = { outputItemID = BAR, quantityMin = 2, quantityMax = 3, reagentSlotSchematics = {
        { reagentType = 1, quantityRequired = 1, reagents = { { itemID = ORE } } },
    } },
}
def("C_TradeSkillUI", {
    GetRecipeSchematic = function(id) return schematics[id] end,
    GetRecipeOutputItemData = function() return {} end,
})

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Auction.lua", "Prices.lua", "Craft.lua", "UIWidgets.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.advance(0.1)
local P, Craft = ns.Prices, ns.Craft

---------------------------------------------------------------------------
section("base de prix")
check(P:Get(ORE) == nil, "aucun prix au départ")
P:Record(ORE, 25)
local p, age = P:Get(ORE)
check(p == 25 and age == 0, "prix enregistré (" .. tostring(p) .. ")")
clock = clock + 3 * 24 * 3600
check(select(2, P:Get(ORE)) == 3 * 24 * 3600, "âge du prix")
check(P:Get(ORE, 24 * 3600) == nil, "trop ancien quand on demande un âge maximum")
check(P.AgeText(7200) == "il y a 2 h" and P.AgeText(3 * 86400) == "il y a 3 j" and P.AgeText(30) == "il y a 1 min", "âge lisible")
check(type(ns.db.ahMarket["Forever-Alliance"]) == "table", "prix rangés par royaume et faction")

section("scan complet de l'HDV")
local okScan = P:FullScan()
check(okScan == false and replicateCalls == 0, "HDV fermé : pas de scan complet")
M.fireEvent("AUCTION_HOUSE_SHOW")
check(P:ShouldAutoScan(), "jamais scanné : scan automatique proposé")
check(P:FullScan() == true and replicateCalls == 1, "scan complet lancé")
check(P:ScanState() == "waiting", "en attente du serveur")
M.advance(0.8)
local state, done, total = P:ScanState()
check(state == "reading" and done == 1500 and total == 4000, "lecture par paquets en cours (" .. tostring(done) .. " / " .. tostring(total) .. ")")
M.advance(1)
check(P:ScanState() == "idle", "lecture terminée")
check(P:Get(ORE) == 19, "minerai : le moins cher à l'unité, 19 pc (" .. tostring(P:Get(ORE)) .. ")")
check(P:Get(BAR) == 150, "barre : 150 pc l'unité (lot de 4 à 600)")
check(P:Get(5001) and P:Get(5001) < 1100, "objets des derniers paquets aussi lus")
check(P:LastFullScan() == clock, "date du dernier scan complet")
check(not P:ShouldAutoScan(), "scan récent : pas de scan automatique")
check(P:FullScan() == false and replicateCalls == 1, "moins de 15 min : refusé (règle du serveur)")
local said = M.printed[#M.printed] or ""
check(said:find("15 min", 1, true) ~= nil, "message : réessaie plus tard")
clock = clock + 16 * 60
check(P:FullScanWait() == 0, "16 min plus tard : de nouveau possible")
clock = clock + 60 * 60
check(P:ShouldAutoScan(), "plus d'une heure : scan automatique proposé")
ns:Set("ahFullScan", false)
check(not P:ShouldAutoScan(), "scan automatique coupé dans les options")
ns:Set("ahFullScan", true)
M.fireEvent("AUCTION_HOUSE_CLOSED")

section("prix d'achat chez les marchands")
M.fireEvent("MERCHANT_SHOW")
check(P:VendorBuy(THREAD) == 10, "fil grossier : 10 pc l'unité (5 pour 50 pc)")
check(P:VendorBuy(POTION) == nil, "objet payé en monnaie spéciale ignoré")
local cost, source = P:Cost(THREAD)
check(cost == 10 and source == "marchand", "fil : le marchand est moins cher que l'HDV (50 pc)")
cost, source = P:Cost(BAR)
check(cost == 150 and source == "HDV", "barre : seulement à l'HDV")

section("infobulles")
check(tooltipType == 0 and type(tooltipFn) == "function", "inscrit pour les infobulles d'objets")
tooltipFn(GameTooltip, { id = ORE })
check(#tipLines == 1 and tipLines[1][1] == "HDV" and tipLines[1][2]:find("19", 1, true) ~= nil,
    "ligne « HDV » avec le prix à l'unité (" .. tostring(tipLines[1] and tipLines[1][2]) .. ")")
tipLines = {}
local bagButton = { GetBagID = function() return 0 end, GetID = function() return 3 end }
GameTooltip.GetOwner = function() return bagButton end
tooltipFn(GameTooltip, { id = ORE })
check(tipLines[1] and tipLines[1][2]:find("x20", 1, true) ~= nil
    and tipLines[1][2]:find("3|TInterface\\MoneyFrame\\UI-SilverIcon", 1, true) ~= nil,
    "depuis un sac : prix de la pile de 20 = 3 pa 80 pc")
GameTooltip.GetOwner = function() return nil end
tipLines = {}
tooltipFn(GameTooltip, { id = 123456 })
check(#tipLines == 0, "objet jamais vu : rien d'ajouté")
P:Record(HERB, 300, clock - 3 * 86400)
tooltipFn(GameTooltip, { id = HERB })
check(tipLines[1] and tipLines[1][1]:find("il y a 3 j", 1, true) ~= nil, "prix ancien : son âge est indiqué")
tipLines = {}
ns:Set("ahTooltip", false)
tooltipFn(GameTooltip, { id = ORE })
check(#tipLines == 0, "coupé dans les options : rien d'ajouté")
ns:Set("ahTooltip", true)
local otherTooltip = CreateFrame("GameTooltip", "ShoppingTooltip1", UIParent)
tooltipFn(otherTooltip, { id = ORE })
check(#tipLines == 0, "pas sur les infobulles de comparaison")

section("coût des recettes")
local r = Craft.Evaluate(10)
check(r and r.value == 2000 and r.net == 1900, "bracelets : 2 000 à l'HDV, 1 900 pour toi")
check(r and r.cost == 310 and #r.reagents == 2, "composants : 2 barres à 150 + 1 fil à 10 (marchand) = 310, optionnel ignoré")
check(r and r.reagents[2].source == "marchand", "fil compté au prix du marchand")
check(r and r.profit == 1590, "bénéfice : 1 900 - 310 = 1 590 (" .. tostring(r and r.profit) .. ")")
r = Craft.Evaluate(11)
check(r and r.reagents[1].id == GEM_B and r.cost == 40, "plusieurs choix pour un composant : le moins cher (gemme B)")
check(r and r.value == nil and r.profit == nil, "anneau jamais vu à l'HDV : pas de bénéfice calculé")
local rows, foot = Craft.Describe(r)
check(foot and foot:find("jamais vu", 1, true) ~= nil, "message : objet jamais vu, faire un scan complet")
r = Craft.Evaluate(12)
check(r and r.outputID == nil and r.cost == 900, "recette sans objet (enchantement) : seulement le coût (3 x 300)")
rows = Craft.Describe(r)
check(rows[1][1]:find("Rien à vendre", 1, true) ~= nil, "affiché : rien à vendre")
r = Craft.Evaluate(13)
check(r and r.qty == 2.5 and r.value == 375, "recette qui donne 2 à 3 objets : 2,5 en moyenne (375)")
check(r and r.net == 356 and r.profit == 337, "bénéfice : 356 pour toi - 19 de minerai = 337 (" .. tostring(r and r.profit) .. ")")
schematics[14] = { outputItemID = BRACER, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
    { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 424242 } } } } }
r = Craft.Evaluate(14)
check(r and r.missing == 1 and r.profit == nil, "composant sans aucun prix : pas de bénéfice inventé")
rows, foot = Craft.Describe(r)
check(foot and foot:find("sans prix", 1, true) ~= nil, "message : composant sans prix")

section("carte à côté de la fenêtre de métier")
local prof = CreateFrame("Frame", "ProfessionsFrame", UIParent)
prof.CraftingPage = CreateFrame("Frame", nil, prof)
local form = CreateFrame("Frame", nil, prof.CraftingPage)
prof.CraftingPage.SchematicForm = form
function form:Init(recipeInfo) self.currentRecipeInfo = recipeInfo end
function form:GetRecipeInfo() return self.currentRecipeInfo end
M.fireEvent("ADDON_LOADED", "Blizzard_Professions")
form:Init({ recipeID = 10 })
local card = rawget(_G, "PlatyplusCraftPrices")
check(card ~= nil and card:IsShown(), "carte affichée pour la recette choisie")
local texts = {}
for _, f in ipairs(M.allFrames) do
    local s = M.state(f)
    if s.parent == card and s.text then texts[#texts + 1] = s.text end
end
local all = table.concat(texts, " | ")
check(all:find("Bénéfice", 1, true) ~= nil and all:find("Barre de cuivre", 1, true) ~= nil,
    "on y lit le bénéfice et les composants")
form:Init({ recipeID = 10, isRecraft = true })
check(not card:IsShown(), "recette de refonte : carte cachée")
form:Init({ recipeID = 10 })
ns:Set("craftPrices", false)
check(not card:IsShown(), "coupé dans les options : carte cachée")
ns:Set("craftPrices", true)
form:Init({ recipeID = 10 })
form:Hide()
check(not card:IsShown(), "fenêtre de recette fermée : carte cachée")

section("l'assistant de mise en vente nourrit la base de prix")
check(type(ns.Prices.Record) == "function" and ns.Auction ~= nil, "modules chargés")

M.report()
M.realPrint(#failures == 0 and "TOUT EST BON" or (#failures .. " échec(s)"))
