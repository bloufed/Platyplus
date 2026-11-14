-- Test des sacs Platyplus (BagWindow.lua, Windows.lua) dans le simulateur, en mode strict.
-- Reproduit ce que fait Forever : ContainerFrame1..N enfants de ContainerFrameContainer, ContainerFrameCombinedBags,
-- OpenAllBags / ToggleAllBags / CloseAllBags (Échap), IsAnyBagOpen, cases ContainerFrameItemButtonTemplate dont le
-- numéro de sac vient du cadre parent (GetBagID -> self:GetParent():GetID()).
-- Usage : python -I dev\lua.py run dev\test_bagwindow.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = tbl[name]
    rawset(tbl, name, function(...)
        local results = { orig(...) }
        hook(...)
        return unpack(results)
    end)
end)
M.impl.SetParent = function(f, parent) S(f).parent = parent end
M.impl.IsClampedToScreen = function(f) return S(f).clamped == true end
M.impl.SetClampedToScreen = function(f, v) S(f).clamped = v and true or false end

---------------------------------------------------------------------------
-- Sacs simulés : sac à dos 16 places, un sac de 8, trousseau de 4 (une clé)
---------------------------------------------------------------------------
local sizes = { [0] = 16, [1] = 8, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [-2] = 4 }
local contents = {
    [0] = {
        [1] = { iconFileID = 101, stackCount = 20, quality = 1, itemName = "Étoffe de lin", itemID = 2589, hyperlink = "lin" },
        [2] = { iconFileID = 102, stackCount = 1, quality = 2, itemName = "Bottes du marcheur", itemID = 900, hyperlink = "bottes" },
        [12] = { iconFileID = 103, stackCount = 5, quality = 0, itemName = "Os brisé", itemID = 901, hyperlink = "os" },
    },
    [1] = { [3] = { iconFileID = 104, stackCount = 3, quality = 1, itemName = "Pain de seigle", itemID = 4540, hyperlink = "pain" } },
    [-2] = { [1] = { iconFileID = 105, stackCount = 1, quality = 1, itemName = "Clé de la cellule", itemID = 5000, hyperlink = "cle" } },
}
def("C_Container", {
    GetContainerNumSlots = function(bag) return sizes[bag] or 0 end,
    GetContainerNumFreeSlots = function(bag)
        local n = sizes[bag] or 0
        for _ in pairs(contents[bag] or {}) do n = n - 1 end
        return n, 0
    end,
    GetContainerItemInfo = function(bag, slot) return contents[bag] and contents[bag][slot] end,
    GetContainerItemQuestInfo = function(bag, slot)
        local info = contents[bag] and contents[bag][slot]
        return { isQuestItem = info and info.questItem == true or false, isActive = false }
    end,
})

-- base d'objets (C_Item) : type de chaque objet, comme GetItemInfoInstant du jeu (classID, subClassID)
local ITEMS = {
    [2589] = { class = 7, sub = 5 },                -- Étoffe de lin : artisanat, tissu
    [2318] = { class = 7, sub = 6 },                -- Cuir léger : artisanat, cuir
    [900]  = { class = 4, sub = 2, loc = "INVTYPE_FEET" },   -- Bottes du marcheur : armure
    [901]  = { class = 15, sub = 0 },               -- Os brisé : divers (gris)
    [4540] = { class = 0, sub = 5 },                -- Pain de seigle : consommable, nourriture
    [118]  = { class = 0, sub = 1 },                -- Potion de soins mineure : consommable, potion
    [5000] = { class = 13, sub = 0 },               -- Clé de la cellule
    [902]  = { class = 12, sub = 0 },               -- Collier du chef : objet de quête
    [905]  = { class = 15, sub = 0 },               -- Lettre scellée : divers, mais marquée « quête » par le sac
    [903]  = { class = 2, sub = 7, loc = "INVTYPE_WEAPON" }, -- Épée rouillée : arme, dans « Toujours vendre »
    [904]  = { class = 15, sub = 0 },               -- Dent de loup : grise, dans « Ne jamais vendre »
    [906]  = { class = 1, sub = 0 },                -- Sac en lin : sac
}
local LINKS = { lin = 2589, cuir = 2318, bottes = 900, os = 901, pain = 4540, potion = 118, cle = 5000, collier = 902,
                lettre = 905, epee = 903, dent = 904, sac = 906 }
local function itemOf(x) return ITEMS[x] and x or LINKS[x] end
def("C_Item", {
    GetItemInfoInstant = function(x)
        local id = itemOf(x)
        local it = id and ITEMS[id]
        if not it then return nil end
        return id, "type", "sous-type", it.loc or "", 0, it.class, it.sub
    end,
    -- nom et prix de vente ; pas de type de liaison : l'équipement n'est jamais vendu d'office ici
    GetItemInfo = function(x)
        local id = itemOf(x)
        if not id then return nil end
        return "objet " .. id, x, 1, 10, 1, "type", "sous-type", 20, ITEMS[id].loc or "", 0, 25
    end,
    GetItemNameByID = function(id) return ITEMS[id] and ("objet " .. id) or nil end,
    GetDetailedItemLevelInfo = function() return 10 end,
})
def("KEYRING_CONTAINER", -2)
def("GetKeyRingSize", function() return sizes[-2] end)
def("C_ActionBar", { ShouldShowKeyring = function() return true end })

-- fonctions des cases (Blizzard_ItemButton) : on note ce que la fenêtre leur demande
def("ClearItemButtonOverlay", function() end)
def("SetItemButtonQuality", function(b, q) b.quality = q end)
def("SetItemButtonCount", function(b, n) b.count = n end)
def("SetItemButtonDesaturated", function(b, v) b.desat = v and true or false end)

-- gabarit ContainerFrameItemButtonTemplate : méthodes du mixin du jeu, simplifiées
local createFrame = CreateFrame
def("CreateFrame", function(kind, name, parent, template)
    local f = createFrame(kind, name, parent, template)
    if template == "ContainerFrameItemButtonTemplate" then
        f.SetHasItem = function(self, has) self.hasItem = has and true or nil end
        f.SetItemButtonTexture = function(self, tex) self.tex = tex end
        f.SyncAppearanceWithHasItem = function() end
        f.UpdateExtended = function() end
        f.UpdateQuestItem = function() end
        f.UpdateNewItem = function() end
        f.UpdateJunkItem = function(self, q) self.junk = q == 0 end
        f.UpdateItemContextMatching = function() end
        f.UpdateCooldown = function(self) self.cooldowns = (self.cooldowns or 0) + 1 end
        f.SetReadable = function() end
        f.CheckUpdateTooltip = function() end
        f.SetMatchesSearch = function(self, v) self.matches = v end
        f.GetBagID = function(self) return self:GetParent():GetID() end   -- comme le gabarit, sans SetBagID
    end
    return f
end)

-- sacs du jeu
local container = CreateFrame("Frame", "ContainerFrameContainer", UIParent)
def("ContainerFrameContainer", container)
local backpack = CreateFrame("Frame", "ContainerFrame1", container)
backpack:Hide()
def("ContainerFrame1", backpack)
local combined = CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
combined:Hide()
def("ContainerFrameCombinedBags", combined)
local closeCalls = 0
def("IsAnyBagOpen", function() return backpack:IsShown() end)
def("OpenAllBags", function() backpack:Show() end)
def("CloseAllBags", function() closeCalls = closeCalls + 1; local was = backpack:IsShown(); backpack:Hide(); return was end)
def("ToggleAllBags", function() if backpack:IsShown() then backpack:Hide() else backpack:Show() end end)
def("ToggleBackpack", function() ToggleAllBags() end)
M.money = 123456

---------------------------------------------------------------------------
-- Chargement de tout l'addon, comme le jeu
---------------------------------------------------------------------------
M.enableStrict()
local files = {}
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    local f = line:match("^([%w_%.]+%.lua)%s*$")
    if f then files[#files + 1] = f end
end
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(1)

local BW = ns.BagWindow
local function win() return rawget(_G, "PlatyplusBagWindow") end
local function winShown() local f = win(); return f ~= nil and S(f).shown end
local function shownButtons()
    local list = {}
    for bag, slots in pairs(BW.buttons) do
        for slot, b in pairs(slots) do if S(b).shown then list[#list + 1] = b end end
    end
    return list
end
local function button(bag, slot) return BW.buttons[bag] and BW.buttons[bag][slot] end

section("réglages et sacs du jeu rangés")
check(BW and BW.Sync and BW.Apply and BW.Layout and BW.UpdateAll, "ns.BagWindow : Sync, Apply, Layout, UpdateAll")
check(ns.db.bagWindow == true and ns.db.bagWinColumns == 10, "actifs par défaut, 10 cases par ligne")
check(S(container).parent ~= UIParent and S(combined).parent ~= UIParent, "sacs du jeu rangés dans un cadre caché")
check(win() == nil, "rien de construit avant la première ouverture")
check(ns.db.bagWinGroup == true, "rangement par type actif par défaut")
ns:Set("bagWinGroup", false)     -- d'abord les sacs à la suite, case par case

section("ouverture avec la touche des sacs")
ToggleAllBags()
M.advance(0.1)
check(winShown(), "fenêtre des sacs ouverte")
check(not backpack:IsVisible(), "le sac du jeu est ouvert mais invisible")
local list = shownButtons()
check(#list == 28, "28 cases : 16 + 8 + trousseau de 4 (" .. #list .. ")")
local b1 = button(0, 1)
check(b1 and b1:GetName() == "PlatyplusBag0Slot1" and b1:GetBagID() == 0 and b1:GetID() == 1,
    "case nommée, sac donné par le cadre porteur, emplacement par SetID")
check(button(-2, 1) and button(-2, 1):GetBagID() == -2 and button(-2, 1):GetName() == "PlatyplusBagK2Slot1", "trousseau : sac -2")
check(button(1, 3):GetBagID() == 1, "deuxième sac : sac 1")
check(b1.tex == 101 and b1.count == 20 and b1.quality == 1, "objet affiché : icône, nombre, qualité")
check(button(0, 3).tex == nil and button(0, 3).hasItem == nil, "case vide")
check(button(0, 12).junk == true, "objet gris marqué")
-- disposition : 10 par ligne, case 11 = 2e ligne, 1re colonne
local p11 = S(button(0, 11)).points[1]
local bs = 40 / 37
check(p11 and math.abs(p11[4]) < 0.01 and math.abs(p11[5] + 44 / bs) < 0.01, "case 11 en début de 2e ligne")
local p17 = S(button(1, 1)).points[1]
check(p17 and math.abs(p17[4] - 6 * 44 / bs) < 0.01, "le sac 1 suit le sac à dos dans la grille (case 17 en colonne 7)")
check(S(button(0, 1)).scale and math.abs(S(button(0, 1)).scale - bs) < 0.001, "cases agrandies (40 px)")
check(tostring(S(BW.freeText).text):find("20", 1, true) and tostring(S(BW.freeText).text):find("24 places libres", 1, true),
    "places libres : 20 / 24 (" .. tostring(S(BW.freeText).text) .. ")")
check(tostring(S(BW.moneyText).text):find("12", 1, true) ~= nil, "argent affiché")

section("recherche")
BW.searchBox:SetText("lin")
check(b1.matches == true and button(0, 2).matches == false and button(1, 3).matches == false, "« lin » : seule l'étoffe reste allumée")
BW.searchBox:SetText("")
check(button(0, 2).matches == true, "recherche vidée : tout est rallumé")

section("mises à jour")
contents[0][1].isLocked = true
M.fireEvent("ITEM_LOCK_CHANGED", 0, 1)
check(b1.desat == true, "objet verrouillé (en main) grisé")
contents[0][1].isLocked = nil
sizes[1] = 12
M.fireEvent("BAG_UPDATE_DELAYED")
M.advance(0.1)
check(#shownButtons() == 32, "sac changé (12 places) : grille refaite (" .. #shownButtons() .. ")")
local before = b1.cooldowns or 0
M.fireEvent("BAG_UPDATE_COOLDOWN")
check((b1.cooldowns or 0) > before, "temps de recharge mis à jour")

section("fermeture")
CloseAllBags()                   -- Échap passe par CloseAllBags
M.advance(0.1)
check(not winShown(), "Échap (CloseAllBags) ferme la fenêtre")
OpenAllBags()                    -- marchand, banque, courrier
M.advance(0.1)
check(winShown(), "OpenAllBags (marchand...) l'ouvre")
local closes = closeCalls
win().close:Click()
M.advance(0.1)
check(not winShown() and not backpack:IsShown() and closeCalls == closes + 1, "la croix ferme aussi les sacs du jeu")
ToggleAllBags()
M.advance(0.1)
backpack:Hide()                  -- fermé par un chemin qu'on ne suit pas
M.advance(0.6)
check(not winShown(), "filet : un sac fermé autrement ferme la fenêtre")

section("colonnes, taille, position")
ToggleAllBags()
M.advance(0.1)
ns:Set("bagWinColumns", 8)
local p9 = S(button(0, 9)).points[1]
check(p9 and math.abs(p9[4]) < 0.01, "8 cases par ligne : la case 9 commence une ligne")
ns:Set("bagWinScale", 1.25)
check(S(win()).scale == 1.25, "taille appliquée")
check(S(win()).points[1][1] == "BOTTOMRIGHT", "ancrée par le coin bas droit (grandit vers le haut)")
BW:ResetPosition()
check(next(ns.db.bagWinPos) == nil, "position remise à zéro")

section("option coupée : sacs du jeu")
ns:Set("bagWindow", false)
M.advance(0.1)
check(not winShown(), "fenêtre Platyplus cachée")
check(S(container).parent == UIParent and S(combined).parent == UIParent, "sacs du jeu remis à leur place")
check(backpack:IsVisible(), "le sac ouvert redevient visible")
ns:Set("bagWindow", true)
M.advance(0.1)
check(S(container).parent ~= UIParent and winShown(), "option remise : sacs du jeu rangés, fenêtre Platyplus ouverte")

---------------------------------------------------------------------------
-- Rangement par type
---------------------------------------------------------------------------
section("rangement par type")
ns:Set("bagWinColumns", 10)
-- sacs : sac à dos 16 places, sac 1 de 12 places (agrandi plus haut), trousseau de 4
contents[0][4] = { iconFileID = 110, stackCount = 2, quality = 1, itemName = "Potion de soins mineure", itemID = 118, hyperlink = "potion" }
contents[0][5] = { iconFileID = 111, stackCount = 1, quality = 1, itemName = "Collier du chef", itemID = 902, hyperlink = "collier" }
contents[0][6] = { iconFileID = 112, stackCount = 4, quality = 1, itemName = "Cuir léger", itemID = 2318, hyperlink = "cuir" }
contents[0][7] = { iconFileID = 113, stackCount = 1, quality = 1, itemName = "Épée rouillée", itemID = 903, hyperlink = "epee" }
contents[0][8] = { iconFileID = 114, stackCount = 2, quality = 0, itemName = "Dent de loup", itemID = 904, hyperlink = "dent" }
contents[0][9] = { iconFileID = 101, stackCount = 7, quality = 1, itemName = "Étoffe de lin", itemID = 2589, hyperlink = "lin" }
contents[0][10] = { iconFileID = 115, stackCount = 1, quality = 1, itemName = "Lettre scellée", itemID = 905, hyperlink = "lettre",
                    questItem = true }
contents[1][5] = { iconFileID = 116, stackCount = 1, quality = 1, itemName = "Sac en lin", itemID = 906, hyperlink = "sac" }
ns.Junk:AddToList("alwaysSell", 903)       -- l'épée sera vendue au marchand
ns.Junk:AddToList("neverSell", 904)        -- la dent grise est gardée
ns:Set("bagWinGroup", true)
M.fireEvent("BAG_UPDATE_DELAYED")
M.advance(0.1)

local function slotsOf(group)
    for _, s in ipairs(BW:Sections()) do
        if s.group == group then
            local out = {}
            for _, p in ipairs(s.slots) do out[#out + 1] = p[1] .. ":" .. p[2] end
            return table.concat(out, " ")
        end
    end
    return ""
end
local order = {}
for _, s in ipairs(BW:Sections()) do order[#order + 1] = s.label or "-" end
check(table.concat(order, ",") == "QUÊTE,CONSOMMABLES,ARTISANAT,ÉQUIPEMENT,DIVERS,POUBELLE,LIBRE,TROUSSEAU",
    "sections dans l'ordre, les vides absentes (" .. table.concat(order, ",") .. ")")
check(slotsOf("quest") == "0:5 0:10", "Quête : le collier (type quête) et la lettre (marquée quête par le sac) (" .. slotsOf("quest") .. ")")
check(slotsOf("consumable") == "0:4 1:3", "Consommables : la potion puis le pain, d'un autre sac (" .. slotsOf("consumable") .. ")")
check(slotsOf("trade") == "0:1 0:9 0:6", "Artisanat : les deux piles d'étoffe côte à côte, puis le cuir (" .. slotsOf("trade") .. ")")
check(slotsOf("gear") == "0:2", "Équipement : les bottes")
check(slotsOf("misc") == "1:5 0:8", "Divers : le sac, puis la dent grise protégée par « Ne jamais vendre » (" .. slotsOf("misc") .. ")")
check(slotsOf("junk") == "0:7 0:12", "Poubelle : l'épée de « Toujours vendre » et l'os gris (" .. slotsOf("junk") .. ")")
local freeSlots = select(2, slotsOf("empty"):gsub("%d+:%d+", ""))
check(freeSlots == 16, "Libre : les places vides des deux sacs, 28 places moins 12 objets (" .. freeSlots .. ")")
check(#shownButtons() == 32, "toujours une case par place (" .. #shownButtons() .. ")")

-- titres affichés
local shownLabels = {}
for _, l in ipairs(BW.labels) do if S(l).shown then shownLabels[#shownLabels + 1] = S(l).text end end
check(#shownLabels == 8 and shownLabels[1] == "QUÊTE" and shownLabels[6] == "POUBELLE", "un titre par section (" .. #shownLabels .. ")")

-- disposition : les petites sections se suivent sur la même ligne (une colonne vide entre deux)
local function pos(bag, slot)
    local p = S(button(bag, slot)).points[1]
    return p[4] * bs / 44, -p[5] * bs
end
local qx, qy = pos(0, 5)
local cx, cy = pos(0, 4)
local tx, ty = pos(0, 1)
check(math.abs(qx) < 0.01 and math.abs(qy - 18) < 0.01, "Quête en haut à gauche, sous son titre")
check(math.abs(cx - 3) < 0.01 and math.abs(cy - qy) < 0.01, "Consommables à côté (colonne 4), sur la même ligne")
check(math.abs(tx - 6) < 0.01 and math.abs(ty - qy) < 0.01, "Artisanat aussi (colonne 7)")
local gx, gy = pos(0, 2)
check(math.abs(gx) < 0.01 and gy > qy + 40, "Équipement ne tient plus : nouvelle ligne")
local lx = S(BW.labels[2]).points[1][4]
check(math.abs(lx - 3 * 44) < 0.01, "le titre Consommables est au-dessus de sa section")

-- un objet tenu en main garde sa place (l'épée verrouillée n'est plus « à vendre » pour la vente automatique)
contents[0][7].isLocked = true
M.fireEvent("BAG_UPDATE_DELAYED")
M.advance(0.1)
check(slotsOf("junk") == "0:7 0:12", "objet en main : il reste dans sa section (" .. slotsOf("junk") .. ")")
contents[0][7].isLocked = nil

-- « Ne jamais vendre » sur l'os : il quitte la poubelle aussitôt
ns.Junk:AddToList("neverSell", 901)
M.advance(0.1)
check(slotsOf("junk") == "0:7" and slotsOf("misc") == "1:5 0:8 0:12",
    "os protégé : il passe dans Divers, après la dent (ordre des noms) (" .. slotsOf("misc") .. ")")
ns.Junk:RemoveFromList("neverSell", 901)
M.advance(0.1)
check(slotsOf("junk") == "0:7 0:12", "protection retirée : il revient à la poubelle")

-- un objet ramassé : la grille est refaite, il rejoint les siens
contents[1][7] = { iconFileID = 101, stackCount = 3, quality = 1, itemName = "Étoffe de lin", itemID = 2589, hyperlink = "lin" }
M.fireEvent("BAG_UPDATE_DELAYED")
M.advance(0.1)
check(slotsOf("trade") == "0:1 0:9 1:7 0:6", "nouvelle étoffe : avec les autres étoffes (" .. slotsOf("trade") .. ")")
check(button(1, 7).tex == 101, "et affichée")

BW.searchBox:SetText("lin")
check(button(1, 7).matches == true and button(0, 4).matches == false, "recherche : marche aussi rangé par type")
BW.searchBox:SetText("")

section("rangement par type coupé")
ns:Set("bagWinGroup", false)
check(#BW:Sections() == 2 and BW:Sections()[1].label == nil, "sacs à la suite : une seule section, puis le trousseau")
local ax, ay = pos(0, 1)
local bx, by = pos(0, 2)
check(math.abs(ax) < 0.01 and math.abs(ay) < 0.01 and math.abs(bx - 1) < 0.01 and math.abs(by) < 0.01,
    "les cases reviennent dans l'ordre des sacs")
local labelsNow = 0
for _, l in ipairs(BW.labels) do if S(l).shown then labelsNow = labelsNow + 1 end end
check(labelsNow == 1, "plus que le titre du trousseau")
check(BW:Status()[3] == "rangement : sacs à la suite", "état affiché")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
