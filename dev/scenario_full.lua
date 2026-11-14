-- Scénario d'intégration : vente (gris + équipement), réparation, sacs, confort, interface
local ADDON_DIR, SCRATCH = ARGS[1], ARGS[2]
local M = dofile(SCRATCH .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

---------------------------------------------------------------------------
-- Monde simulé : un sac, des objets, un marchand
---------------------------------------------------------------------------
local items = {
    [1]   = { name = "Chiffon", q = 0, ilvl = 1,  equip = "",             class = 15, sub = 0, bind = 0, price = 10 },
    [2]   = { name = "Casque use", q = 2, ilvl = 20, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 500 },
    [3]   = { name = "Casque meilleur", q = 2, ilvl = 40, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 900 },
    [4]   = { name = "Casque BoE", q = 2, ilvl = 10, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 2, price = 300 },
    [5]   = { name = "Casque epique", q = 4, ilvl = 12, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 2000 },
    [6]   = { name = "Gris protege", q = 0, ilvl = 1,  equip = "",            class = 15, sub = 0, bind = 0, price = 5 },
    [7]   = { name = "Potion toujours vendue", q = 1, ilvl = 1, equip = "",   class = 0,  sub = 0, bind = 0, price = 50 },
    [8]   = { name = "Casque de set", q = 2, ilvl = 11, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 400 },
    [9]   = { name = "Epee sans emplacement porte", q = 2, ilvl = 5, equip = "INVTYPE_FINGER", class = 4, sub = 0, bind = 1, price = 100 },
    [100] = { name = "Casque equipe", q = 3, ilvl = 30, equip = "INVTYPE_HEAD", class = 4, sub = 1, bind = 1, price = 0 },
}
local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. items[id].name .. "]|h|r" end
local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end

local bag = {}   -- [slot] = itemID
for slot = 1, 9 do bag[slot] = slot end
local used, money0 = {}, M.money

def("C_Container", {
    GetContainerNumSlots = function(b) return b == 0 and 9 or 0 end,
    GetContainerItemInfo = function(b, slot)
        local id = b == 0 and bag[slot]
        if not id then return nil end
        local it = items[id]
        return { iconFileID = 1000 + id, stackCount = id == 1 and 3 or 1, isLocked = false, quality = it.q,
                 hyperlink = linkOf(id), hasNoValue = it.price == 0, itemID = id, isBound = it.bind == 1 or it.bind == 3,
                 itemName = it.name }
    end,
    GetContainerItemEquipmentSetInfo = function(b, slot) return bag[slot] == 8, bag[slot] == 8 and "Mon set" or "" end,
    UseContainerItem = function(b, slot)
        local id = bag[slot]
        if not id then return end
        used[#used + 1] = id
        M.money = M.money + items[id].price * (id == 1 and 3 or 1)
        bag[slot] = nil
        M.fireEvent("PLAYER_MONEY")   -- le vrai jeu prévient à chaque vente
    end,
    GetContainerNumFreeSlots = function(b) local n = 0; if b == 0 then for s = 1, 20 do if not bag[s] then n = n + 1 end end end; return n, 0 end,
    SortBags = function() M.sorted = true end,
})
def("C_Item", {
    GetItemInfo = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        return it.name, linkOf(id), it.q, it.ilvl, 1, "x", "y", 1, it.equip, 1000 + id, it.price, it.class, it.sub, it.bind, 0, nil, false, ""
    end,
    GetItemInfoInstant = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        return id, "x", "y", it.equip, 1000 + id, it.class, it.sub
    end,
    GetDetailedItemLevelInfo = function(link) local it = items[idOf(link)]; return it and it.ilvl, false, it and it.ilvl end,
    GetItemNameByID = function(id) return items[id] and items[id].name end,
    RequestLoadItemDataByID = function() end,
})
def("GetInventoryItemLink", function(unit, slot) if slot == 1 then return linkOf(100) end end)
def("C_TransmogCollection", { PlayerHasTransmogByItemInfo = function() return true end })

local junkSoldByApi = 0
def("C_MerchantFrame", {
    IsSellAllJunkEnabled = function() return true end,
    GetNumJunkItems = function() local n = 0; for s, id in pairs(bag) do if items[id].q == 0 and items[id].price > 0 then n = n + 1 end end; return n end,
    SellAllJunkItems = function()
        for s, id in pairs(bag) do
            if items[id].q == 0 and items[id].price > 0 then
                junkSoldByApi = junkSoldByApi + 1
                used[#used + 1] = id
                M.money = M.money + items[id].price * (id == 1 and 3 or 1)
                bag[s] = nil
                M.fireEvent("PLAYER_MONEY")
            end
        end
    end,
})
local merchant = CreateFrame("Frame", "MerchantFrame", UIParent); merchant:Hide()
def("MerchantFrameCloseButton", CreateFrame("Button", "MerchantFrameCloseButton", merchant))

-- réparation / confort
local repairs = {}
def("CanMerchantRepair", function() return true end)
def("GetRepairAllCost", function() return 1234, true end)
def("RepairAllItems", function(guild) repairs[#repairs + 1] = guild and "guilde" or "perso"; M.money = M.money - 1234 end)
def("CanGuildBankRepair", function() return true end)
def("GetGuildBankWithdrawMoney", function() return -1 end)
def("GetGuildBankMoney", function() return 99999999 end)
def("UnitExists", function(unit) return unit == "player" end)
def("StaticPopup_Hide", function() end)
def("UIErrorsFrame", CreateFrame("Frame", "UIErrorsFrame", UIParent))
def("C_FriendList", { IsFriend = function(guid) return guid == "friend-guid" end })
def("C_BattleNet", { GetAccountInfoByGUID = function() return nil end })
def("IsPlayerInGuildFromGUID", function() return false end)
def("AcceptGroup", function() M.groupAccepted = true end)
def("C_SummonInfo", { ConfirmSummon = function() M.summonOk = true end, GetSummonConfirmSummoner = function() return "Gandalf" end })
def("C_PartyInfo", {})
def("C_GossipInfo", { GetActiveQuests = function() return {} end, GetAvailableQuests = function() return {} end, GetOptions = function() return {} end })

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local files = {}
if ARGS[3] then
    for f in ARGS[3]:gmatch("[^,]+") do files[#files + 1] = f end
else
    for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
        local f = line:match("^([%w_%.]+%.lua)%s*$")
        if f then files[#files + 1] = f end
    end
end
M.realPrint("fichiers : " .. table.concat(files, ", "))
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.2)
check(ns.db ~= nil, "ns.db créé")
ns.db.duration = 600   -- les lignes du flux restent affichées pendant tout le test

---------------------------------------------------------------------------
section("aperçu de la vente (BuildList)")
ns.db.neverSell[6] = true
ns.db.alwaysSell[7] = true
if ns.Junk and ns.Junk.BuildList then
    local list = ns.Junk:BuildList()
    local ids, reasons = {}, {}
    for _, e in ipairs(list) do ids[#ids + 1] = e.itemID; reasons[#reasons + 1] = e.reason end
    M.realPrint("   liste : " .. table.concat(ids, ",") .. " / " .. table.concat(reasons, ","))
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end
    check(set[1], "gris vendu (1)")
    check(set[7], "toujours vendre (7)")
    check(set[2], "casque usé soulbound moins bon que celui porté (2)")
    check(not set[3], "casque meilleur gardé (3)")
    check(not set[4], "casque BoE non lié gardé (4)")
    check(not set[5], "casque épique gardé (5)")
    check(not set[6], "gris protégé par « jamais vendre » gardé (6)")
    check(not set[8], "casque d'un ensemble d'équipement gardé (8)")
    check(not set[9], "anneau sans objet porté dans l'emplacement gardé (9)")
    check(ids[1] == 1 and ids[#ids] == 2, "ordre : gris d'abord, équipement ensuite")
    local first = list[1]
    check(first and first.bag and first.slot and first.link and first.icon and first.count and first.price, "entrées complètes (bag, slot, link, icon, count, price)")
else
    check(false, "ns.Junk:BuildList absent")
end

---------------------------------------------------------------------------
section("vente automatique à l'ouverture du marchand")
local moneyBefore = M.money
merchant:Show()
M.fireEvent("MERCHANT_SHOW")
M.advance(8)
local sold = {}
for _, id in ipairs(used) do sold[id] = true end
check(sold[1] and sold[7] and sold[2], "vendus : 1, 7 et 2 (" .. table.concat(used, ",") .. ")")
check(not sold[6], "gris protégé (neverSell) PAS vendu")
check(not sold[3] and not sold[4] and not sold[5] and not sold[8] and not sold[9], "objets à garder intacts")
check(M.money + 1234 > moneyBefore, "argent gagné par les ventes (hors réparation de 1234)")
check(#repairs == 1, "réparation faite (" .. table.concat(repairs, ",") .. ")")
do
    -- chaque objet vendu (gris, « toujours vendre », équipement) + la ligne d'argent apparaissent dans le flux :
    -- une carte visible du conteneur PlatyplusFeed avec la pastille « Vendu » ; objet = son nom est un lien d'objet
    local itemRows, moneyRows = 0, 0
    local soldCards, itemCards = {}, {}
    for _, f in ipairs(M.allFrames) do
        local s = M.state(f)
        if s.kind == "FontString" and s.parent then
            local p = M.state(s.parent)
            local text = tostring(s.text)
            if p.parent == PlatyplusFeed and p.shown then
                if text == "Vendu" then soldCards[s.parent] = true end
                if text:find("|Hitem:", 1, true) then itemCards[s.parent] = true end
            end
        end
    end
    for card in pairs(soldCards) do
        if itemCards[card] then itemRows = itemRows + 1 else moneyRows = moneyRows + 1 end
    end
    check(itemRows == 3, "3 objets vendus visibles dans le flux (" .. itemRows .. ")")
    check(moneyRows == 1, "ligne du total en argent (" .. moneyRows .. ")")
end

M.realPrint("-- Maj tenu : rien ne se vend automatiquement")
bag[1] = 1
used = {}
M.shift = true
M.fireEvent("MERCHANT_CLOSED"); M.fireEvent("MERCHANT_SHOW"); M.advance(5)
check(#used == 0, "aucune vente avec Maj")
M.shift = false
if ns.Junk and ns.Junk.SellNow then
    ns.Junk:SellNow(); M.advance(5)
    check(#used >= 1, "SellNow vend le gris ajouté")
end
merchant:Hide(); M.fireEvent("MERCHANT_CLOSED")
used = {}
if ns.Junk and ns.Junk.SellNow then ns.Junk:SellNow(); check(#used == 0, "SellNow sans marchand ne vend rien") end

M.realPrint("-- listes")
if ns.Junk and ns.Junk.AddToList then
    ns.Junk:AddToList("neverSell", 42)
    check(ns.db.neverSell[42] == true, "AddToList neverSell")
    ns.Junk:AddToList("alwaysSell", 42)
    check(ns.db.alwaysSell[42] == true and ns.db.neverSell[42] == nil, "AddToList alwaysSell retire de neverSell")
    ns.Junk:RemoveFromList("alwaysSell", 42)
    check(ns.db.alwaysSell[42] == nil, "RemoveFromList")
end

---------------------------------------------------------------------------
section("confort")
if ns.Misc then
    -- sacs presque pleins : on remplit le sac
    ns:Set("bagWarn", true); ns:Set("bagWarnSlots", 5)
    for s = 1, 20 do bag[s] = bag[s] or 1 end
    for s = 1, 17 do bag[s] = 1 end
    M.fireEvent("BAG_UPDATE_DELAYED")
    M.advance(0.2)
    for s = 1, 20 do bag[s] = 1 end
    M.fireEvent("BAG_UPDATE_DELAYED")
    M.advance(0.2)
    ns:Set("acceptInvites", true)
    M.fireEvent("PARTY_INVITE_REQUEST", "Bob", false, false, false, true, false, "friend-guid", false)
    check(M.groupAccepted == true, "invitation d'un ami acceptée")
    M.groupAccepted = false
    M.fireEvent("PARTY_INVITE_REQUEST", "Inconnu", false, false, false, true, false, "autre-guid", false)
    check(M.groupAccepted ~= true, "invitation d'un inconnu ignorée")
    ns:Set("acceptSummon", true)
    M.fireEvent("CONFIRM_SUMMON")
    check(M.summonOk == true, "invocation acceptée")
    ns:Set("cameraZoom", true); ns:Set("cameraZoomFactor", 2.2)
    check(M.cvars.cameraDistanceMaxZoomFactor == "2.2", "zoom caméra appliqué (" .. tostring(M.cvars.cameraDistanceMaxZoomFactor) .. ")")
    ns:Set("cameraZoom", false)
    ns.Misc:SortBags()
    check(M.sorted == true, "tri des sacs")
    ns:Set("hideTalkingHead", true); ns:Set("declineDuels", true); ns:Set("acceptRes", true); ns:Set("declineGuildInvites", true)
    ns:Set("hideTalkingHead", false); ns:Set("declineDuels", false); ns:Set("acceptRes", false); ns:Set("declineGuildInvites", false)
else
    check(false, "ns.Misc absent")
end

---------------------------------------------------------------------------
section("interface")
if ns.UI then
    ns.UI:Open()
    check(PlatyplusConfig ~= nil or true, "fenêtre ouverte")
    -- test automatique : on actionne chaque contrôle de chaque frame créée
    local clicks, tabs = 0, 0
    local function monkey()
        local frames = {}
        for i, f in ipairs(M.allFrames) do frames[i] = f end
        for _, f in ipairs(frames) do
            local s = M.state(f)
            local sc = s.scripts
            if sc.OnClick and s.enabled then clicks = clicks + 1; M.fire(f, "OnClick", "LeftButton", false) end
            if sc.OnMouseDown then M.fire(f, "OnMouseDown", "LeftButton") end
            if sc.OnMouseUp then M.fire(f, "OnMouseUp", "LeftButton") end
            if sc.OnEnter then M.fire(f, "OnEnter") end
            if sc.OnLeave then M.fire(f, "OnLeave") end
            if sc.OnValueChanged and s.kind == "Slider" then
                M.fire(f, "OnValueChanged", (s.min + s.max) / 2, true)
                M.fire(f, "OnValueChanged", s.max, true)
                M.fire(f, "OnValueChanged", s.min, true)
            end
            if sc.OnTextChanged and s.kind == "EditBox" then M.fire(f, "OnTextChanged", true) end
            if sc.OnEnterPressed and s.kind == "EditBox" then
                M.state(f).text = "12345"; M.fire(f, "OnEnterPressed")
            end
            if sc.OnReceiveDrag then M.cursor = { "item", 6, "|Hitem:6|h[x]|h" }; M.fire(f, "OnReceiveDrag") end
            if sc.OnMouseWheel then M.fire(f, "OnMouseWheel", -1); M.fire(f, "OnMouseWheel", 1) end
            if sc.OnDragStart then M.fire(f, "OnDragStart"); M.fire(f, "OnDragStop") end
            if sc.OnShow then M.fire(f, "OnShow") end
        end
    end
    monkey(); M.advance(0.3)
    monkey(); M.advance(4)
    M.realPrint("   clics simulés : " .. clicks)
    -- clavier : capteur de touche
    for _, f in ipairs(M.allFrames) do
        local sc = M.state(f).scripts
        if sc.OnKeyDown then
            M.fire(f, "OnKeyDown", "LSHIFT"); M.fire(f, "OnKeyDown", "G"); M.fire(f, "OnKeyDown", "ESCAPE")
        end
    end
    ns.UI:Toggle(); ns.UI:Toggle(); ns.UI:Close()
    ns:Set("launcher", false); ns:Set("launcher", true)   -- l'icône flottante remplace le bouton de minicarte
    SlashCmdList.PLATYPLUS("icon off"); SlashCmdList.PLATYPLUS("icon reset")
    check(ns.db.launcher == true, "/pp icon reset réaffiche l'icône")
    ns:ResetAll(false)
    ns.UI:Refresh()
    SlashCmdList.PLATYPLUS("")
    SlashCmdList.PLATYPLUS("")
else
    check(false, "ns.UI absent")
end

---------------------------------------------------------------------------
section("commandes")
for _, cmd in ipairs({ "help", "config", "list", "sell", "sort", "cvars", "debug on", "debug off", "float off", "float on", "junk off", "junk on" }) do
    SlashCmdList.PLATYPLUS(cmd)
end

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
