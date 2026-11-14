-- Test : icône flottante et barre d'infos (Launcher.lua)
-- python -I dev\lua.py run dev\test_launcher.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local S = M.state

---------------------------------------------------------------------------
-- Monde simulé (API NON VÉRIFIÉES sur Forever : fausses versions ici)
---------------------------------------------------------------------------
local W = {
    fps = 60, home = 40, world = 55, netError = false,
    xp = 1000, xpMax = 10000, level = 20, rested = 2500, maxLevel = false,
    mapID = 1429, x = 0.4523, y = 0.6789,
    dura = { [1] = { 80, 100 }, [5] = { 45, 100 } }, alerts = {},
    bagSlots = { [0] = 16, [1] = 12, [5] = 20 }, bagFree = { [0] = 8, [1] = 6, [5] = 15 }, bagFamily = { [5] = 1 },
    bagsToggled = 0,
    ilvl = 23.46, ilvlAll = 25.5, charToggled = nil,
}
def("GetAverageItemLevel", function() return W.ilvlAll, W.ilvl end)
def("ToggleCharacter", function(tab) W.charToggled = tab end)
def("GetFramerate", function() return W.fps end)
def("GetNetStats", function()
    if W.netError then error("GetNetStats en panne") end
    return 12.5, 3.25, W.home, W.world
end)
def("UnitXP", function() return W.xp end)
def("UnitXPMax", function() return W.xpMax end)
def("UnitLevel", function() return W.level end)
def("GetXPExhaustion", function() return W.rested end)
def("IsPlayerAtEffectiveMaxLevel", function() return W.maxLevel end)
def("C_Map", {
    GetBestMapForUnit = function() return W.mapID end,
    GetPlayerMapPosition = function()
        if not W.x then return nil end
        return { GetXY = function() return W.x, W.y end }
    end,
    GetMapInfo = function(id) return { mapID = id, name = "Forêt d'Elwynn" } end,
})
def("GetInventoryItemDurability", function(slot)
    local d = W.dura[slot]
    if d then return d[1], d[2] end
end)
def("GetInventoryAlertStatus", function(i) return W.alerts[i] or 0 end)
def("C_Container", {
    GetContainerNumSlots = function(b) return W.bagSlots[b] or 0 end,
    GetContainerNumFreeSlots = function(b) return W.bagFree[b] or 0, W.bagFamily[b] or 0 end,
    GetContainerItemInfo = function() return nil end,
})
def("ToggleAllBags", function() W.bagsToggled = W.bagsToggled + 1 end)

-- l'info-bulle garde ses lignes pour qu'on puisse les lire
local tipLines, tipOwner = {}, nil
local GT = GameTooltip
rawset(GT, "SetOwner", function(_, owner)
    tipOwner = owner
    for i = #tipLines, 1, -1 do tipLines[i] = nil end
end)
rawset(GT, "SetText", function(_, text) tipLines[#tipLines + 1] = tostring(text) end)
rawset(GT, "AddLine", function(_, text) tipLines[#tipLines + 1] = tostring(text) end)
rawset(GT, "AddDoubleLine", function(_, l, r) tipLines[#tipLines + 1] = tostring(l) .. " = " .. tostring(r) end)
rawset(GT, "IsOwned", function(self, f) return tipOwner == f and S(self).shown end)
local function tipHas(s)
    for _, l in ipairs(tipLines) do if l:find(s, 1, true) then return true end end
    return false
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Launcher.lua" })
local ui = { toggle = 0, open = 0 }
ns.UI = { Toggle = function() ui.toggle = ui.toggle + 1 end, Open = function() ui.open = ui.open + 1 end }
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(0.1)

local L = ns.Launcher
local btn = L and L.button
local dock = L and L.dock
local I = L and L.items or {}
local THEME = ns.THEME
local BAD_HEX = string.format("|cff%02x%02x%02x", THEME.bad[1] * 255 + 0.5, THEME.bad[2] * 255 + 0.5, THEME.bad[3] * 255 + 0.5)
local function text(name) return I[name] and tostring(S(I[name].text).text) or "" end
local function activeTickers()
    local n = 0
    for _, t in ipairs(M.timers) do if t.repeating and not t.cancelled then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
section("icône")
check(L ~= nil and btn ~= nil, "module et bouton créés")
check(btn == rawget(_G, "PlatyplusLauncher"), "cadre nommé PlatyplusLauncher")
check(S(btn).parent == UIParent, "posé sur UIParent (pas sur la minicarte)")
check(S(btn).shown, "icône visible")
check(S(btn).w == 30 and S(btn).h == 30, "taille 30 px")
local p = S(btn).points[1]
check(p and p[1] == "TOPRIGHT" and p[2] == UIParent and p[3] == "TOPRIGHT" and p[4] == -250 and p[5] == -30,
    "position par défaut TOPRIGHT -250 -30")
check(btn.visual and S(btn.visual.logo).texture == ns.LOGO, "logo Platyplus")
check(S(btn.visual.halo).alpha == 0, "halo éteint au repos")

---------------------------------------------------------------------------
section("barre d'infos")
check(dock ~= nil and S(dock).shown and S(dock).parent == btn, "barre visible, enfant de l'icône")
for _, name in ipairs({ "fps", "latency", "gold", "bags", "durability", "xp" }) do
    check(I[name] and I[name].visible, "valeur affichée : " .. name)
end
check(I.coords and not I.coords.visible, "coordonnées masquées par défaut")
check(text("fps"):find("60", 1, true) and I.fps.color == THEME.good, "FPS 60 en vert (" .. text("fps") .. ")")
check(text("latency"):find("55", 1, true) and I.latency.color == THEME.good, "latence 55 ms (" .. text("latency") .. ")")
check(text("gold"):find("100|TInterface\\MoneyFrame\\UI-GoldIcon", 1, true), "or avec icône (" .. text("gold") .. ")")
check(text("bags"):find("14", 1, true) and I.bags.color == THEME.good, "14 places libres hors sac de composants (" .. text("bags") .. ")")
check(text("durability"):find("45 %", 1, true) and I.durability.color ~= THEME.good and I.durability.color ~= THEME.bad,
    "durabilité 45 % en orange (" .. text("durability") .. ")")
check(text("xp"):find("10,0 %", 1, true), "XP : pourcentage du niveau (" .. text("xp") .. ")")
check(not S(I.fps.sep).shown and S(I.latency.sep).shown and S(I.xp.sep).shown, "séparateurs entre les valeurs seulement")
check(S(dock).w > 20, "largeur calculée (" .. tostring(S(dock).w) .. ")")
check(L.dockSide == "RIGHT" and S(dock).points[1][1] == "LEFT" and S(dock).points[1][3] == "RIGHT", "barre à droite de l'icône")
check(L.ticker ~= nil and activeTickers() == 1, "un seul ticker actif")

---------------------------------------------------------------------------
section("ticker (FPS, latence)")
W.fps = 20; M.advance(1.05)
check(text("fps"):find("20", 1, true) and I.fps.color == THEME.bad, "FPS 20 en rouge (" .. text("fps") .. ")")
W.fps = 35; M.advance(1.05)
check(text("fps"):find("35", 1, true) and I.fps.color ~= THEME.bad and I.fps.color ~= THEME.good, "FPS 35 en orange")
W.world = 400; M.advance(1.05)
check(text("latency"):find("400", 1, true) and I.latency.color == THEME.bad, "latence 400 ms en rouge")
W.world = 55; W.fps = 60; M.advance(1.05)
check(activeTickers() == 1, "toujours un seul ticker")

do
    -- optimisation : un relevé sans changement ne crée ni table ni texte (XP/h relue 200 fois comprise).
    -- JIT coupé pendant la mesure : la compilation des traces de LuaJIT fausserait le compte.
    local jit = rawget(_G, "jit")
    if jit then jit.off(); jit.flush() end
    local function allocated(fn)
        collectgarbage("collect"); collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 2000 do fn() end
        local grown = collectgarbage("count") - before
        collectgarbage("restart")
        return grown
    end
    local t = L.ticker
    local grown = allocated(function() t.fn(t) end)
    local oneTable = allocated(function() local _ = {} end)
    if jit then jit.on() end
    check(grown < 1 and oneTable > 50, string.format("2000 relevés : %.2f Ko alloués (une table par relevé : %.0f Ko)", grown, oneTable))
end

---------------------------------------------------------------------------
section("coordonnées")
ns:Set("dockCoords", true)
check(I.coords.visible and text("coords"):find("45,2 · 67,9", 1, true), "coordonnées 45,2 · 67,9 (" .. text("coords") .. ")")
W.x = 0.5; M.advance(1.05)
check(text("coords"):find("50,0 · 67,9", 1, true), "mises à jour par le ticker (" .. text("coords") .. ")")
W.x = nil; M.advance(1.05)
check(text("coords"):find("-", 1, true) and not text("coords"):find("50,0", 1, true), "indisponibles : tiret")
W.x = 0.4523; M.advance(1.05)

---------------------------------------------------------------------------
section("sacs")
W.bagFree[0], W.bagFree[1] = 2, 1
M.fireEvent("BAG_UPDATE_DELAYED")
check(text("bags"):find("3", 1, true) and text("bags"):find(BAD_HEX, 1, true) and I.bags.color == THEME.bad,
    "3 places : rouge (" .. text("bags") .. ")")
M.fire(I.bags.frame, "OnClick", "LeftButton")
check(W.bagsToggled == 1, "clic sur les sacs : ouverture")
M.fire(I.bags.frame, "OnClick", "RightButton")
check(L:IsMenuShown(), "clic droit sur la barre : menu")
L:HideMenu()

---------------------------------------------------------------------------
section("durabilité")
W.dura[5] = { 10, 100 }
M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(text("durability"):find("10 %", 1, true) and text("durability"):find(BAD_HEX, 1, true), "10 % en rouge (" .. text("durability") .. ")")
W.dura[5] = { 0, 100 }
M.fireEvent("UPDATE_INVENTORY_DURABILITY")
check(text("durability"):find("cassé", 1, true), "pièce cassée (" .. text("durability") .. ")")
-- sans GetInventoryItemDurability : état d'alerte
local realDura = GetInventoryItemDurability
M.optional.GetInventoryItemDurability = true
rawset(_G, "GetInventoryItemDurability", nil)
W.alerts[3] = 1; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(text("durability"):find("faible", 1, true), "repli sur GetInventoryAlertStatus : faible (" .. text("durability") .. ")")
W.alerts[3] = 2; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(text("durability"):find("cassé", 1, true), "repli : cassé")
W.alerts[3] = nil; M.fireEvent("UPDATE_INVENTORY_ALERTS")
check(text("durability"):find("OK", 1, true), "repli : OK")
M.fire(I.durability.frame, "OnEnter")
check(tipHas("Durabilité") and tipHas("État = bon"), "info-bulle durabilité")
def("GetInventoryItemDurability", realDura)
W.dura[5] = { 90, 100 }
M.fireEvent("PLAYER_EQUIPMENT_CHANGED")
check(text("durability"):find("80 %", 1, true), "pourcentage de retour (" .. text("durability") .. ")")

---------------------------------------------------------------------------
section("niveau d'objet")
check(I.ilvl and I.ilvl.visible and text("ilvl"):find("23,4", 1, true), "niveau d'objet porté affiché : 23,4 (" .. text("ilvl") .. ")")
W.ilvl = 27
M.fireEvent("PLAYER_EQUIPMENT_CHANGED")
check(text("ilvl"):find("27,0", 1, true), "nouvel équipement : 27,0 (" .. text("ilvl") .. ")")
W.ilvl = 27.5
M.fireEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
check(text("ilvl"):find("27,5", 1, true), "PLAYER_AVG_ITEM_LEVEL_UPDATE relu (" .. text("ilvl") .. ")")
M.fire(I.ilvl.frame, "OnEnter")
check(tipHas("Équipement porté = 27,5") and tipHas("Meilleur possible (avec tes sacs) = 25,5"), "info-bulle du niveau d'objet")
M.fire(I.ilvl.frame, "OnLeave")
M.fire(I.ilvl.frame, "OnClick", "LeftButton")
check(W.charToggled == "PaperDollFrame", "clic : fiche du personnage")
ns:Set("dockIlvl", false)
check(not I.ilvl.visible, "valeur masquable (dockIlvl)")
ns:Set("dockIlvl", true)

---------------------------------------------------------------------------
section("or et session")
local money0 = M.money
M.money = M.money + 123456; M.fireEvent("PLAYER_MONEY")
check(L.session.gained == 123456, "or gagné compté")
check(text("gold"):find("112|T", 1, true) and text("gold"):find("34|TInterface\\MoneyFrame\\UI-SilverIcon", 1, true),
    "or et argent dans la barre (" .. text("gold") .. ")")
M.money = M.money - 20000; M.fireEvent("PLAYER_MONEY")
check(L.session.spent == 20000 and L.session.money0 == money0, "or dépensé compté")
M.fire(I.gold.frame, "OnEnter")
check(tipHas("Or gagné = +12") and tipHas("Or dépensé = -2") and tipHas("Bilan = +10"), "info-bulle de l'or")
M.fire(I.gold.frame, "OnLeave")

---------------------------------------------------------------------------
section("XP")
check(text("xp"):find("XP", 1, true) and text("xp"):find("10,0 %", 1, true) and not text("xp"):find("/h", 1, true),
    "par défaut : le pourcentage seul (" .. text("xp") .. ")")
check(I.xp.color and I.xp.color[1] < 0.5 and I.xp.color[3] == 1, "pastille bleue quand on est reposé")
M.advance(61)
W.xp = 3000; M.fireEvent("PLAYER_XP_UPDATE")
check(L.session.xpGained == 2000 and L.session.killXP == 2000, "2000 XP gagnés sur un monstre (" .. L.session.xpGained .. ")")
check(text("xp"):find("30,0 %", 1, true), "pourcentage à jour (" .. text("xp") .. ")")
-- quête rendue (annoncée avant le gain d'XP) qui fait monter de niveau
M.fireEvent("QUEST_TURNED_IN", 101, 7500, 0)
W.level, W.xp, W.xpMax = 21, 500, 12000
M.fireEvent("PLAYER_LEVEL_UP", 21)
M.fireEvent("PLAYER_XP_UPDATE")
check(L.session.xpGained == 9500, "montée de niveau comptée une seule fois (" .. L.session.xpGained .. ")")
check(L.session.questXP == 7500 and L.session.killXP == 2000, "XP de la quête séparée de celle des monstres ("
    .. L.session.questXP .. " / " .. L.session.killXP .. ")")
-- gain vu avant l'annonce de la quête : reclassé
W.xp = 2000; M.fireEvent("PLAYER_XP_UPDATE")
M.fireEvent("QUEST_TURNED_IN", 102, 1500, 0)
check(L.session.questXP == 9000 and L.session.killXP == 2000 and #L.session.kills == 1,
    "quête annoncée après le gain : reclassée (" .. L.session.questXP .. " / " .. L.session.killXP .. ")")
-- une pause de 25 min (ville) ne compte que pour 5 min de jeu actif
local a0 = L.session.active
M.advance(25 * 60)
W.xp = 4000; M.fireEvent("PLAYER_XP_UPDATE")
check(L.session.xpGained == 13000, "le total de session continue (" .. L.session.xpGained .. ")")
check(math.abs(L.session.active - a0 - 300) < 0.01, "25 min sans XP comptées 5 min de jeu actif ("
    .. string.format("%.1f", L.session.active - a0) .. " s)")
local rate = L.xpPerHour()
check(rate and math.abs(rate - 13000 / L.session.active * 3600) < 1, "XP/h = XP de la session / temps actif ("
    .. tostring(rate and math.floor(rate)) .. ")")

section("XP : modes au clic")
check(ns.db.dockXpMode == "pct", "mode par défaut : pourcentage")
M.fire(I.xp.frame, "OnClick", "LeftButton")
check(ns.db.dockXpMode == "rate" and text("xp"):find("XP/h", 1, true) and text("xp"):find("k", 1, true),
    "clic : XP par heure (" .. text("xp") .. ")")
M.fire(I.xp.frame, "OnClick", "LeftButton")
check(ns.db.dockXpMode == "time" and text("xp"):find("Niv. dans", 1, true), "clic : temps avant le niveau (" .. text("xp") .. ")")
local wTime = I.xp.width
M.fire(I.xp.frame, "OnClick", "LeftButton")
-- 8000 XP restantes / 2000 XP par monstre
check(ns.db.dockXpMode == "kills" and text("xp"):find("Mobs", 1, true) and text("xp"):find("~4", 1, true),
    "clic : monstres restants (" .. text("xp") .. ")")
M.fire(I.xp.frame, "OnClick", "LeftButton")
check(ns.db.dockXpMode == "pct" and text("xp"):find("33,3 %", 1, true), "clic : retour au pourcentage (" .. text("xp") .. ")")
check(I.xp.width < wTime, "la largeur suit le texte plus court (" .. I.xp.width .. " < " .. wTime .. ")")
M.fire(I.xp.frame, "OnEnter")
check(tipHas("Niveau 21") and tipHas("Bonus de repos = +2 500") and tipHas("Prochain niveau dans")
    and tipHas("Monstres restants = ~4") and tipHas("Quêtes restantes = ~2") and tipHas("Temps de jeu actif"),
    "info-bulle XP : tout le détail")
check(tipHas("Maj + clic"), "info-bulle XP : rappel des clics")
M.fire(I.xp.frame, "OnLeave")
W.rested = nil; M.fireEvent("PLAYER_XP_UPDATE")
check(I.xp.color[1] > 0.5, "pastille violette sans repos")
W.rested = 2500; M.fireEvent("PLAYER_XP_UPDATE")

section("XP : session gardée au /reload")
W.clock = 1000000
def("time", function() return W.clock end)
M.fireEvent("PLAYER_LOGOUT")
local saved = rawget(_G, "PlatyplusCharDB") and rawget(_G, "PlatyplusCharDB").launcherSession
check(saved and saved.xpGained == 13000 and saved.savedAt == 1000000, "session écrite dans PlatyplusCharDB")
W.clock = W.clock + 60
L.session.started = false
M.fireEvent("PLAYER_ENTERING_WORLD", false, true)
check(L.session.resumed and L.session.xpGained == 13000 and L.session.questXP == 9000 and #L.session.kills == 2,
    "reprise après /reload (" .. L.session.xpGained .. ")")
M.fireEvent("PLAYER_LOGOUT")
W.clock = W.clock + 31 * 60
L.session.started = false
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
check(not L.session.resumed and L.session.xpGained == 0, "plus de 30 min après : nouvelle session")
M.advance(30)
W.xp = 5000; M.fireEvent("PLAYER_XP_UPDATE")
check(L.session.xpGained == 1000, "nouvelle session : 1000 XP")
M.shift = true
M.fire(I.xp.frame, "OnClick", "LeftButton")
M.shift = false
check(L.session.xpGained == 0 and ns.db.dockXpMode == "pct", "Maj + clic : session remise à zéro, mode inchangé")
W.xp = 6000; M.advance(150); M.fireEvent("PLAYER_XP_UPDATE")

---------------------------------------------------------------------------
section("info-bulle et survol de l'icône")
M.fire(btn, "OnEnter")
check(tipOwner == btn and tipHas("Platy") and tipHas("v" .. ns.version), "titre et version")
check(tipHas("Or gagné") and tipHas("Bilan") and tipHas("XP par heure") and tipHas("Prochain niveau dans"), "statistiques de session")
check(tipHas("Clic gauche") and tipHas("Clic droit") and tipHas("Glisser"), "rappels des clics")
check(S(btn.visual.halo).alpha > 0 and S(btn.visual.logo).w == 34, "halo et agrandissement au survol")
M.fire(btn, "OnLeave")
check(S(btn.visual.halo).alpha == 0 and S(btn.visual.logo).w == 32 and not S(GT).shown, "retour au repos, info-bulle fermée")
M.fire(btn, "OnMouseDown", "LeftButton")
check(S(btn.visual.logo).w == 30, "logo enfoncé pendant le clic")
M.fire(btn, "OnMouseUp", "LeftButton")
check(S(btn.visual.logo).w == 32, "logo relâché")

W.maxLevel = true; M.fireEvent("PLAYER_LEVEL_UP", 60)
check(not I.xp.visible, "XP masquée au niveau maximum")
M.fire(btn, "OnEnter")
check(not tipHas("XP par heure"), "pas d'XP/h dans l'info-bulle au niveau maximum")
M.fire(btn, "OnLeave")
W.maxLevel = false; M.fireEvent("PLAYER_XP_UPDATE")
check(I.xp.visible, "XP de retour")

section("info-bulles des valeurs")
for _, name in ipairs({ "fps", "latency", "gold", "bags", "durability", "coords", "xp" }) do
    M.fire(I[name].frame, "OnEnter")
    check(tipOwner == I[name].frame and #tipLines >= 2, "info-bulle " .. name .. " (" .. tostring(tipLines[1]) .. ")")
    M.fire(I[name].frame, "OnLeave")
end
M.fire(I.latency.frame, "OnEnter")
check(tipHas("Domicile = 40 ms") and tipHas("Monde = 55 ms") and tipHas("Bande passante = 12,5 / 3,3 Ko/s"), "détail de la latence")
M.fire(I.coords.frame, "OnEnter")
check(tipHas("Carte = Forêt d'Elwynn"), "nom de la carte")
M.fire(I.bags.frame, "OnEnter")
check(tipHas("Places libres = 3 / 28") and tipHas("Sac de composants = 15 / 20") and tipHas("Clic : ouvrir les sacs"), "détail des sacs")
M.fire(I.bags.frame, "OnLeave")

---------------------------------------------------------------------------
section("clics et menu rapide")
M.fire(btn, "OnClick", "LeftButton")
check(ui.toggle == 1, "clic gauche : ns.UI:Toggle()")
M.fire(btn, "OnClick", "RightButton")
local menu = rawget(_G, "PlatyplusLauncherMenu")
check(menu ~= nil and L.menu == menu and L:IsMenuShown(), "clic droit : menu ouvert")
check(S(menu).strata == "DIALOG", "menu au premier plan")
local special = false
for _, name in ipairs(UISpecialFrames) do if name == "PlatyplusLauncherMenu" then special = true end end
check(special, "Échap ferme le menu (UISpecialFrames)")
check(S(menu).events.GLOBAL_MOUSE_DOWN == true, "écoute les clics ailleurs pendant qu'il est ouvert")

local rows, nrows = {}, 0
for _, f in ipairs(S(menu).frames) do
    if f.key then rows[f.key] = f; nrows = nrows + 1 end
end
check(nrows == 8, "8 interrupteurs (" .. nrows .. ")")
for _, key in ipairs({ "interact", "instantLoot", "sellJunk", "autoQuest", "hud", "floatLoot", "dock", "launcherLocked" }) do
    check(rows[key] and rows[key].on == (ns.db[key] and true or false), "interrupteur " .. key .. " à jour")
end
for _, key in ipairs({ "interact", "instantLoot", "sellJunk", "autoQuest", "hud", "floatLoot" }) do
    local before = ns.db[key]
    M.fire(rows[key], "OnClick", "LeftButton")
    check(ns.db[key] == not before and rows[key].on == not before, "clic : " .. key .. " -> " .. tostring(ns.db[key]))
    M.fire(rows[key], "OnClick", "LeftButton")
    check(ns.db[key] == before, "reclic : " .. key .. " revenu")
end
M.fire(rows.dock, "OnClick", "LeftButton")
check(ns.db.dock == false and not S(dock).shown and L.ticker == nil and activeTickers() == 0,
    "menu : barre d'infos coupée, ticker arrêté")
check(L:IsMenuShown(), "le menu reste ouvert après un interrupteur")
M.fire(rows.dock, "OnClick", "LeftButton")
check(ns.db.dock == true and S(dock).shown and L.ticker ~= nil and activeTickers() == 1, "barre d'infos rallumée, ticker relancé")
M.fire(rows.launcherLocked, "OnClick", "LeftButton")
check(ns.db.launcherLocked == true and rows.launcherLocked.on, "icône verrouillée depuis le menu")
ns:Set("autoQuest", true)
check(rows.autoQuest.on == true, "réglage changé ailleurs : interrupteur suit")
ns:Set("autoQuest", false)
M.fire(rows.hud, "OnEnter"); M.fire(rows.hud, "OnLeave")

M.fireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
check(not L:IsMenuShown() and not S(menu).events.GLOBAL_MOUSE_DOWN, "clic ailleurs : menu fermé, écoute coupée")
M.fire(btn, "OnClick", "RightButton")
check(L:IsMenuShown(), "rouvert")
M.fire(btn, "OnClick", "RightButton")
check(not L:IsMenuShown(), "clic droit de nouveau : fermé")
M.fire(btn, "OnClick", "RightButton")
M.fire(L.optionsRow, "OnClick", "LeftButton")
check(ui.open == 1 and not L:IsMenuShown(), "« Ouvrir les options » : ns.UI:Open() et menu fermé")
M.fire(btn, "OnClick", "RightButton")
M.fire(btn, "OnClick", "LeftButton")
check(ui.toggle == 2 and not L:IsMenuShown(), "clic gauche menu ouvert : menu fermé + options")
M.fire(btn, "OnClick", "RightButton")
M.fire(btn, "OnEnter")
check(tipOwner ~= btn, "pas d'info-bulle par-dessus le menu")
M.fire(btn, "OnLeave")
L:HideMenu()

---------------------------------------------------------------------------
section("glisser")
-- verrouillée (depuis le menu) : sans Maj rien ne bouge
M.fire(btn, "OnDragStart")
check(S(btn).scripts.OnUpdate == nil, "verrouillée : pas de glissement sans Maj")
M.fire(btn, "OnDragStop")
check(ns.db.launcherPoint == "TOPRIGHT" and ns.db.launcherX == -250, "verrouillée : position inchangée")
-- Maj + glisser vers le coin haut-droit
M.shift = true
M.fire(btn, "OnDragStart")
M.shift = false
check(S(btn).scripts.OnUpdate ~= nil, "Maj + glisser : OnUpdate seulement pendant le glissement")
rawset(btn, "GetLeft", function() return 1300 end)
rawset(btn, "GetRight", function() return 1340 end)
rawset(btn, "GetTop", function() return 740 end)
rawset(btn, "GetBottom", function() return 700 end)
M.advance(0.3)
check(L.dockSide == "LEFT" and S(dock).points[1][1] == "RIGHT", "près du bord droit : barre passée à gauche pendant le glissement")
M.fire(btn, "OnDragStop")
check(S(btn).scripts.OnUpdate == nil, "OnUpdate retiré à la fin du glissement")
check(ns.db.launcherPoint == "TOPRIGHT" and ns.db.launcherX == -26 and ns.db.launcherY == -28,
    "position sauvegardée : " .. tostring(ns.db.launcherPoint) .. " " .. tostring(ns.db.launcherX) .. " " .. tostring(ns.db.launcherY))
p = S(btn).points[1]
check(p[1] == "TOPRIGHT" and p[4] == -26 and p[5] == -28, "icône replacée sur la position sauvegardée")
local before = ui.toggle
M.fire(btn, "OnClick", "LeftButton")
check(ui.toggle == before, "le relâchement du glissement n'ouvre pas les options")
M.advance(0.3)
M.fire(btn, "OnClick", "LeftButton")
check(ui.toggle == before + 1, "clic normal ensuite")

ns:Set("launcherLocked", false)
for _, k in ipairs({ "GetLeft", "GetRight", "GetTop", "GetBottom" }) do rawset(btn, k, nil) end
M.fire(I.gold.frame, "OnDragStart")
check(S(btn).scripts.OnUpdate ~= nil, "glisser depuis la barre déplace l'icône")
M.fire(I.gold.frame, "OnDragStop")
check(ns.db.launcherPoint == "BOTTOMLEFT" and ns.db.launcherX == 100 and ns.db.launcherY == 100,
    "ancrage au coin le plus proche : " .. tostring(ns.db.launcherPoint) .. " " .. tostring(ns.db.launcherX) .. " " .. tostring(ns.db.launcherY))
check(L.dockSide == "RIGHT", "barre revenue à droite")
M.fire(btn, "OnDragStart")
ns:Set("launcher", false)
check(S(btn).scripts.OnUpdate == nil, "icône masquée pendant un glissement : glissement arrêté")
ns:Set("launcher", true)

---------------------------------------------------------------------------
section("échelle, visibilité, réinitialisation")
ns:Set("launcherScale", 1.5)
p = S(btn).points[1]
check(S(btn).scale == 1.5 and math.abs(p[4] - 100 / 1.5) < 0.01, "échelle 1,5 ; coin d'ancrage conservé")
ns:Set("launcherScale", 5)
check(S(btn).scale == 2, "échelle bornée à 2")
ns:Set("launcherScale", 1)

ns:Set("launcher", false)
check(not S(btn).shown and L.ticker == nil and activeTickers() == 0, "icône masquée : ticker arrêté")
M.fire(btn, "OnClick", "RightButton")
check(not L:IsMenuShown(), "pas de menu quand l'icône est masquée")
ns:Set("launcher", true)
check(S(btn).shown and S(dock).shown and L.ticker ~= nil, "icône réaffichée : barre et ticker de retour")

ns:Set("dock", false)
check(not S(dock).shown and L.ticker == nil, "dock coupé : barre masquée, ticker arrêté")
ns:Set("dock", true)
for _, k in ipairs({ "dockFps", "dockLatency", "dockBags", "dockDurability", "dockIlvl", "dockCoords", "dockXp" }) do ns:Set(k, false) end
check(S(dock).shown and I.gold.visible and L.ticker == nil and activeTickers() == 0, "or seul : barre visible SANS ticker")
check(not S(I.gold.sep).shown, "pas de séparateur devant la seule valeur")
ns:Set("dockGold", false)
check(not S(dock).shown and L.ticker == nil, "aucune valeur : barre masquée")
ns:Set("dockCoords", true)
check(S(dock).shown and L.ticker ~= nil, "coordonnées seules : ticker relancé")
for _, k in ipairs({ "dockFps", "dockLatency", "dockGold", "dockBags", "dockDurability", "dockIlvl", "dockXp" }) do ns:Set(k, true) end

L:ResetPosition()
p = S(btn).points[1]
check(ns.db.launcherPoint == "TOPRIGHT" and ns.db.launcherX == -250 and ns.db.launcherY == -30
    and p[1] == "TOPRIGHT" and p[4] == -250 and p[5] == -30, "ResetPosition : position par défaut")

M.fireEvent("DISPLAY_SIZE_CHANGED"); M.fireEvent("UI_SCALE_CHANGED")
M.fireEvent("PLAYER_ENTERING_WORLD", false, true)
check(S(btn).shown and S(dock).shown, "changement d'écran / chargement : toujours en place")

---------------------------------------------------------------------------
section("API absentes ou en panne")
local realFps = GetFramerate
M.optional.GetFramerate = true
rawset(_G, "GetFramerate", nil)
L:Refresh()
check(not I.fps.visible and I.latency.visible, "sans GetFramerate : FPS retiré, le reste reste")
def("GetFramerate", realFps)
L:Refresh()
check(I.fps.visible, "GetFramerate de retour")

local realXP = UnitXP
M.optional.UnitXP = true
rawset(_G, "UnitXP", nil)
L:Refresh()
check(not I.xp.visible, "sans UnitXP : XP retirée")
M.fire(btn, "OnEnter")
check(tipHas("Or gagné") and not tipHas("XP par heure"), "info-bulle sans XP")
M.fire(btn, "OnLeave")
def("UnitXP", realXP)

W.netError = true
M.advance(3.5)
local cut = false
for _, line in ipairs(M.printed) do if line:find("retiré après des erreurs répétées", 1, true) then cut = true end end
check(cut and I.latency.broken and not I.latency.visible, "latence en panne : retirée après 3 erreurs, sans erreur Lua")
check(I.fps.visible and L.ticker ~= nil, "les autres valeurs continuent")
W.netError = false

---------------------------------------------------------------------------
section("réglages")
ns:ResetAll(false)
p = S(btn).points[1]
check(S(btn).shown and p[1] == "TOPRIGHT" and p[4] == -250, "ResetAll : icône par défaut")
ns:Set("debug", true); ns:Set("debug", false)

---------------------------------------------------------------------------
section("repli sans GLOBAL_MOUSE_DOWN (second chargement)")
do
    local realRegister = M.impl.RegisterEvent
    M.impl.RegisterEvent = function(f, e)
        if e == "GLOBAL_MOUSE_DOWN" then error("Attempt to register unknown event \"GLOBAL_MOUSE_DOWN\"") end
        return realRegister(f, e)
    end
    local ns2 = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Launcher.lua" })
    ns2.UI = { Toggle = function() end }
    M.fireEvent("ADDON_LOADED", "Platyplus")
    local L2 = ns2.Launcher
    check(L2 and L2.button and S(L2.button).shown, "second module chargé")
    local mark = #M.allFrames
    L2:ShowMenu()
    local catcher
    for i = #M.allFrames, mark + 1, -1 do
        local f = M.allFrames[i]
        local s = S(f)
        if s.kind == "Button" and s.parent == UIParent and s.strata == "DIALOG" and s.shown then catcher = f break end
    end
    check(L2:IsMenuShown() and catcher ~= nil, "menu ouvert avec un cadre plein écran de secours")
    if catcher then M.fire(catcher, "OnClick", "LeftButton") end
    check(not L2:IsMenuShown() and catcher and not S(catcher).shown, "clic ailleurs : menu et cadre de secours fermés")
    M.impl.RegisterEvent = realRegister
end

---------------------------------------------------------------------------
section("test automatique de tous les contrôles")
do
    local frames = {}
    for i, f in ipairs(M.allFrames) do frames[i] = f end
    for _, f in ipairs(frames) do
        local sc = S(f).scripts
        if sc.OnEnter then M.fire(f, "OnEnter") end
        if sc.OnLeave then M.fire(f, "OnLeave") end
        if sc.OnMouseDown then M.fire(f, "OnMouseDown", "LeftButton") end
        if sc.OnMouseUp then M.fire(f, "OnMouseUp", "RightButton") end
        if sc.OnDragStart then M.fire(f, "OnDragStart"); M.fire(f, "OnDragStop") end
    end
    M.advance(0.5)
    for _, f in ipairs(frames) do
        local sc = S(f).scripts
        if sc.OnClick then M.fire(f, "OnClick", "RightButton"); M.fire(f, "OnClick", "LeftButton") end
        if sc.OnShow then M.fire(f, "OnShow") end
    end
    M.advance(2)
    check(true, "contrôles actionnés")
end

---------------------------------------------------------------------------
section("globales")
local allowed = { PlatyplusDB = true, SLASH_PLATYPLUS1 = true, SLASH_PLATYPLUS2 = true, SLASH_PLATYPLUS3 = true }
local bad = {}
for _, name in ipairs(M.newGlobals) do if not allowed[name] then bad[#bad + 1] = name end end
check(#bad == 0, "aucune globale créée par Launcher.lua (" .. table.concat(bad, ", ") .. ")")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
