-- Test des touches « manger » et « boire » (ns.Eat, dans Misc.lua) dans le simulateur, en mode strict.
-- Manger : meilleure nourriture hors combat, meilleure potion de soins en combat ; boire : boisson / potion de mana.
-- Boutons sécurisés de type « macro » : « /use [combat] item:POTION; item:NOURRITURE » (vérifié dans Forever :
-- SECURE_ACTIONS.macro -> C_Macro.RunMacroText) ; le jeu évalue [combat] à l'appui.
-- Usage : python -I dev\lua.py run dev\test_eat.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local function lastPrint() return M.printed[#M.printed] or "" end
local function printedHas(sub)
    for _, line in ipairs(M.printed) do if line:find(sub, 1, true) then return true end end
    return false
end

---------------------------------------------------------------------------
-- Monde simulé (noms et sorts vérifiés dans Forever : C_Item.GetItemSpell -> nom, id ; C_Spell.GetSpellName)
---------------------------------------------------------------------------
Enum.ItemConsumableSubclass = { Generic = 0, Potion = 1, Fooddrink = 5 }

-- id = { nom, classe, sous-classe, sort, id du sort, niveau requis, niveau d'objet, utilisable }
local ITEMS = {
    [4540] = { "Pain dur", 0, 5, "Nourriture", 433, 1, 5, true },
    [4541] = { "Pain de seigle", 0, 5, "Nourriture", 434, 5, 15, true },
    [4599] = { "Jambon fumé", 0, 5, "Nourriture", 435, 15, 25, true },
    [8952] = { "Viande rôtie de raptor", 0, 5, "Nourriture", 1131, 45, 55, false },     -- trop haut pour toi
    [117]  = { "Viande séchée coriace", 0, 0, "Nourriture", 433, 1, 5, true },          -- sous-classe 0 (Forever)
    [159]  = { "Eau fraîche", 0, 5, "Boisson", 430, 1, 5, true },
    [1179] = { "Thé glacé", 0, 5, "Boisson", 431, 15, 25, true },
    [21023] = { "Ragoût de crabe", 0, 5, "Nourriture et boisson", 22734, 15, 25, true },  -- les deux
    [2593] = { "Bière naine", 0, 5, "Ivresse", 5020, 1, 1, true },                       -- alcool : rien
    [118]  = { "Potion de soins mineure", 0, 1, "Potion de soins", 439, 1, 5, true },
    [858]  = { "Potion de soins inférieure", 0, 1, "Potion de soins", 440, 3, 13, true },
    [929]  = { "Potion de soins", 0, 1, "Potion de soins", 441, 12, 22, true },
    [3928] = { "Potion de soins supérieure", 0, 1, "Potion de soins", 4042, 35, 45, false }, -- trop haute
    [2455] = { "Potion de mana mineure", 0, 1, "Rappel de mana", 437, 5, 10, true },
    [3385] = { "Potion de mana inférieure", 0, 1, "Rappel de mana", 438, 14, 24, true },
    [2862] = { "Pierre à aiguiser grossière", 0, 0, "Aiguisage", 2828, 1, 5, true },
    [2589] = { "Étoffe de lin", 7, 5, nil, nil, 1, 5, true },
}
local bags
local function setBags(b) bags = b end
local function countOf(id)
    local n = 0
    for _, slots in pairs(bags) do for _, it in pairs(slots) do if it[1] == id then n = n + it[2] end end end
    return n
end
def("C_Container", {
    GetContainerNumSlots = function(bag) return bags[bag] and 16 or 0 end,
    GetContainerNumFreeSlots = function() return 10, 0 end,
    GetContainerItemInfo = function(bag, slot)
        local it = bags[bag] and bags[bag][slot]
        if not it then return nil end
        return { itemID = it[1], stackCount = it[2], itemName = ITEMS[it[1]][1] }
    end,
})
def("C_Item", {
    GetItemInfoInstant = function(id)
        local d = ITEMS[id]; if not d then return nil end
        return id, "Consommable", "x", "", 1000 + id, d[2], d[3]
    end,
    GetItemInfo = function(id)
        local d = ITEMS[id]; if not d then return nil end
        return d[1], "|cffffffff|Hitem:" .. id .. "|h[" .. d[1] .. "]|h|r", 1, d[7], d[6]
    end,
    GetItemSpell = function(id) local d = ITEMS[id]; if d and d[4] then return d[4], d[5] end end,
    IsUsableItem = function(id) local d = ITEMS[id]; return d and d[8] or false, false end,
    GetItemCount = function(id) return countOf(id) end,
})
local SPELL_NAMES = { [433] = "Nourriture", [430] = "Boisson", [441] = "Potion de soins", [437] = "Rappel de mana" }
def("C_Spell", { GetSpellName = function(id) return SPELL_NAMES[id] end })

M.enableStrict()

---------------------------------------------------------------------------
section("chargement : aucune touche par défaut")
setBags({
    [0] = { [1] = { 4540, 20 }, [2] = { 4541, 5 }, [3] = { 1179, 10 }, [4] = { 2593, 3 }, [5] = { 159, 20 } },
    [1] = { [1] = { 4599, 4 }, [2] = { 8952, 2 }, [3] = { 118, 5 }, [4] = { 929, 2 }, [5] = { 3928, 1 },
            [6] = { 2455, 4 }, [7] = { 3385, 1 }, [8] = { 2589, 40 }, [9] = { 2862, 3 } },
})
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Interact.lua", "Misc.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.1)
local Eat = ns.Eat
local eatBtn, drinkBtn = rawget(_G, "PlatyplusEatButton"), rawget(_G, "PlatyplusDrinkButton")
local S = M.state
check(Eat ~= nil and eatBtn ~= nil and drinkBtn ~= nil, "module ns.Eat, boutons PlatyplusEatButton et PlatyplusDrinkButton")
for _, b in ipairs({ eatBtn, drinkBtn }) do
    check(S(b).template == "SecureActionButtonTemplate" and b:GetAttribute("type") == "macro" and b:GetAttribute("useOnKeyDown") == true,
        "bouton sécurisé de type « macro », agit à l'appui")
end
check(ns.db.eatKey == "" and ns.db.drinkKey == "", "aucune touche par défaut")
check(M.overrides["F"] == "INTERACTMOUSEOVER", "la touche d'interaction F est en place")
local bound = 0
for _, cmd in pairs(M.overrides) do if cmd:find("PlatyplusEat", 1, true) or cmd:find("PlatyplusDrink", 1, true) then bound = bound + 1 end end
check(bound == 0, "sans touche choisie, rien n'est lié")

---------------------------------------------------------------------------
section("choix des objets")
local function bestId(kind) local b = Eat:BestOf(kind); return b and b.id end
check(bestId("food") == 4599, "nourriture : jambon (niv. 15) ; raptor (45) écarté, boissons, bière, potions ignorées")
check(bestId("drink") == 1179, "boisson : thé glacé (niv. 15) avant l'eau fraîche (niv. 1)")
check(bestId("heal") == 929, "potion de soins : « Potion de soins » (niv. 12) ; la supérieure (35) est trop haute")
check(bestId("mana") == 3385, "potion de mana : inférieure (niv. 14) avant la mineure (5)")
check(Eat:Best() and Eat:Best().id == 4599, "Eat:Best() (compatibilité) = la nourriture")
local saved = bags
setBags({ [0] = { [1] = { 117, 6 }, [2] = { 2862, 3 }, [3] = { 21023, 2 } } })
check(bestId("food") == 21023 and bestId("drink") == 21023, "« Nourriture et boisson » compte pour manger ET pour boire")
setBags({ [0] = { [1] = { 117, 6 }, [2] = { 2862, 3 } } })
check(bestId("food") == 117 and bestId("drink") == nil, "nourriture en sous-classe 0 reconnue ; pierre à aiguiser ignorée")
setBags(saved)

---------------------------------------------------------------------------
section("touche pour manger : nourriture hors combat, potion en combat")
M.printed = {}
ns:Set("eatKey", "G")
check(M.overrides["G"] == "CLICK PlatyplusEatButton:LeftButton", "G -> bouton « manger »")
check(eatBtn:GetAttribute("macrotext") == "/use [combat] item:929; item:4599",
    "macro : potion en combat, jambon sinon (" .. tostring(eatBtn:GetAttribute("macrotext")) .. ")")
check(printedHas("touche pour manger : G ; hors combat") and printedHas("Jambon fumé") and printedHas("en combat")
    and printedHas("Potion de soins"), "le chat confirme : " .. lastPrint())
check(M.overrides["F"] == "INTERACTMOUSEOVER", "F garde l'interaction")

section("touche pour boire : boisson hors combat, potion de mana en combat")
M.printed = {}
ns:Set("drinkKey", "H")
check(M.overrides["H"] == "CLICK PlatyplusDrinkButton:LeftButton", "H -> bouton « boire »")
check(drinkBtn:GetAttribute("macrotext") == "/use [combat] item:3385; item:1179",
    "macro : potion de mana en combat, thé sinon (" .. tostring(drinkBtn:GetAttribute("macrotext")) .. ")")
check(printedHas("touche pour boire : H"), "le chat confirme la touche pour boire")
check(M.overrides["G"] == "CLICK PlatyplusEatButton:LeftButton", "la touche pour manger reste")

---------------------------------------------------------------------------
section("les sacs changent")
bags[1][3], bags[1][4] = nil, nil           -- plus de potion de soins
M.fireEvent("BAG_UPDATE_DELAYED")
check(eatBtn:GetAttribute("macrotext") == "/use [nocombat] item:4599", "plus de potion : nourriture seulement, hors combat")
setBags({ [0] = { [1] = { 118, 3 } } })    -- seulement une potion
M.fireEvent("BAG_UPDATE_DELAYED")
check(eatBtn:GetAttribute("macrotext") == "/use [combat] item:118", "plus de nourriture : la potion, en combat seulement")
setBags({ [0] = {} })
M.fireEvent("BAG_UPDATE_DELAYED")
check(eatBtn:GetAttribute("macrotext") == nil and drinkBtn:GetAttribute("macrotext") == nil, "plus rien : aucune macro")
M.printed = {}
M.fire(eatBtn, "PreClick", "LeftButton", true)
check(lastPrint():find("rien à manger", 1, true) ~= nil, "appui hors combat sans nourriture : « rien à manger »")
M.fire(eatBtn, "PreClick", "LeftButton", true)
check(#M.printed == 1, "message pas répété à chaque appui")
M.inCombat = true
M.advance(3)
M.fire(eatBtn, "PreClick", "LeftButton", true)
check(lastPrint():find("aucune potion de soins", 1, true) ~= nil, "appui en combat sans potion : « aucune potion de soins »")
M.fire(drinkBtn, "PreClick", "LeftButton", true)
check(lastPrint():find("aucune potion de mana", 1, true) ~= nil, "boire en combat sans potion : « aucune potion de mana »")

---------------------------------------------------------------------------
section("combat")
setBags({ [0] = { [1] = { 4540, 20 }, [2] = { 118, 2 } } })
M.fireEvent("PLAYER_REGEN_DISABLED")
M.fireEvent("BAG_UPDATE_DELAYED")
local errorsBefore = #M.errors
ns:Set("eatKey", "J")
check(#M.errors == errorsBefore, "en combat : aucun SetAttribute ni liaison tenté (" .. (#M.errors - errorsBefore) .. " erreur)")
check(M.overrides["G"] == "CLICK PlatyplusEatButton:LeftButton" and M.overrides["J"] == nil, "en combat : l'ancienne touche reste")
check(eatBtn:GetAttribute("macrotext") == nil, "en combat : la macro n'est pas modifiée")
M.inCombat = false
M.fireEvent("PLAYER_REGEN_ENABLED")
check(M.overrides["J"] == "CLICK PlatyplusEatButton:LeftButton" and M.overrides["G"] == nil, "après le combat : J remplace G")
check(eatBtn:GetAttribute("macrotext") == "/use [combat] item:118; item:4540", "après le combat : macro à jour")

---------------------------------------------------------------------------
section("conflits de touches")
M.printed = {}
ns:Set("eatKey", "F")
check(M.overrides["F"] == "INTERACTMOUSEOVER" and printedHas("déjà ta touche d'interaction"), "manger sur F : refusé, expliqué")
ns:Set("eatKey", "J"); M.printed = {}
ns:Set("eatKey", "F")
check(printedHas("déjà ta touche d'interaction"), "le redit à chaque nouvel essai")
ns:Set("eatKey", "J"); M.printed = {}
ns:Set("drinkKey", "J")
check(M.overrides["J"] == "CLICK PlatyplusEatButton:LeftButton" and printedHas("déjà ta touche pour manger"),
    "boire sur la touche de manger : refusé, expliqué")
ns:Set("drinkKey", "K")
check(M.overrides["K"] == "CLICK PlatyplusDrinkButton:LeftButton", "boire sur K : accepté")
ns:Set("interact", false)
ns:Set("eatKey", "F")
check(M.overrides["F"] == "CLICK PlatyplusEatButton:LeftButton", "interaction coupée : F peut servir à manger")
ns:Set("interact", true)
check(M.overrides["F"] == "INTERACTMOUSEOVER", "interaction rallumée : F redevient l'interaction")
ns:Set("eatKey", "J")

---------------------------------------------------------------------------
section("commandes et diagnostic")
M.printed = {}
SlashCmdList.PLATYPLUS("drink l")
check(ns.db.drinkKey == "L" and M.overrides["L"] == "CLICK PlatyplusDrinkButton:LeftButton", "/pp drink l -> touche L")
SlashCmdList.PLATYPLUS("boire off")
local any = false
for _, cmd in pairs(M.overrides) do if cmd:find("PlatyplusDrink", 1, true) then any = true end end
check(ns.db.drinkKey == "" and not any and printedHas("touche pour boire retirée"), "/pp boire off retire la touche")
SlashCmdList.PLATYPLUS("eat")
check(lastPrint():find("touche pour manger : J", 1, true) and lastPrint():find("Pain dur", 1, true)
    and lastPrint():find("en combat", 1, true), "/pp eat décrit hors combat et en combat : " .. lastPrint())
setBags({ [0] = { [1] = { 4599, 4 }, [2] = { 1179, 10 }, [3] = { 929, 2 }, [4] = { 3385, 1 }, [5] = { 2593, 3 },
    [6] = { 21023, 2 }, [7] = { 3928, 1 } } })
M.fireEvent("BAG_UPDATE_DELAYED")
M.printed = {}
SlashCmdList.PLATYPLUS("eat debug")
check(printedHas("potion de soins : sort « Potion de soins »"), "noms de sorts reconnus")
check(printedHas("Potion de soins : potion de soins : OK"), "potion de soins : OK")
check(printedHas("Thé glacé : boisson : OK"), "thé : boisson")
check(printedHas("Ragoût de crabe : nourriture + boisson : OK"), "ragoût : nourriture + boisson")
check(printedHas("Potion de soins supérieure : potion de soins, mais pas utilisable"), "potion trop haute : signalée")
check(printedHas("Bière naine : sort « Ivresse » (5020) : ni nourriture"), "bière : rien")
-- ragoût (niv. 15, x2) et jambon (niv. 15, x4) à égalité : on finit d'abord la plus petite réserve
check(printedHas("la touche J (manger) fait : CLICK PlatyplusEatButton:LeftButton ; macro : /use [combat] item:929; item:21023"),
    "ce que fait vraiment la touche, et sa macro (ragoût : même niveau que le jambon, moins de réserve)")

---------------------------------------------------------------------------
section("client sans noms de sorts")
-- 2e chargement (comme un /reload) sur un client où C_Spell.GetSpellName ne répond pas : replis et identifiants
def("C_Spell", { GetSpellName = function() return nil end })
local ns2 = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Interact.lua", "Misc.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
setBags({ [0] = { [1] = { 4599, 4 }, [2] = { 1179, 10 }, [3] = { 929, 2 }, [4] = { 3385, 1 } } })
M.fireEvent("BAG_UPDATE_DELAYED")
check(ns2.Eat:BestOf("food").id == 4599 and ns2.Eat:BestOf("drink").id == 1179, "replis « Nourriture » / « Boisson »")
check(ns2.Eat:BestOf("heal").id == 929 and ns2.Eat:BestOf("mana").id == 3385, "potions reconnues par l'identifiant de leur sort")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
