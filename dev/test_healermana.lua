-- Test : barre de mana du healer (HealerMana.lua) dans le simulateur strict
-- healer repéré par son rôle, choisi en le ciblant, groupe et raid, valeurs secrètes, déplacement, aperçu, réglages,
-- absence de scrutation, garde-fou
-- Usage : python -I dev\lua.py run dev\test_healermana.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

---------------------------------------------------------------------------
-- Méthodes réelles de WoW absentes du simulateur : ajoutées ici, pour ce test seulement
---------------------------------------------------------------------------
local impl, S = M.impl, M.state
impl.RegisterUnitEvent = function(f, event, ...)
    local s = S(f)
    s.events[event] = true
    s.units = s.units or {}
    s.units[event] = { ... }
end
impl.GetStatusBarTexture = function(f)
    local s = S(f)
    if not s.barTexture then s.barTexture = impl.CreateTexture(f) end
    return s.barTexture
end
impl.SetStatusBarTexture = function(f, file) S(f).barFile = file end
impl.SetStatusBarColor = function(f, r, g, b) S(f).barColor = { r, g, b } end
impl.SetVertexColor = function(f, r, g, b, a) S(f).vertex = { r, g, b, a or 1 } end
impl.SetTextColor = function(f, r, g, b) S(f).color = { r, g, b } end
impl.SetDesaturated = function(f, v) S(f).desat = v and true or false end
impl.GetCenter = function(f)
    local c = S(f).center
    if c then return c[1], c[2] end
    return 683, 384
end

---------------------------------------------------------------------------
-- Émulation des valeurs secrètes
---------------------------------------------------------------------------
local SecretMT = {}
local function secret(v) return setmetatable({ v = v }, SecretMT) end
local function isSecretObj(x) return getmetatable(x) == SecretMT end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__lt", "__le", "__len", "__call", "__concat", "__eq" }) do
    SecretMT[op] = function() error("opération interdite sur une valeur secrète (" .. op .. ")", 2) end
end
SecretMT.__tostring = function(s) return tostring(s.v) end
local realFormat = string.format
string.format = function(fmt, ...)
    local n = select("#", ...)
    local args, anySecret = { ... }, false
    for i = 1, n do
        if isSecretObj(args[i]) then args[i] = args[i].v; anySecret = true end
    end
    local text = realFormat(fmt, unpack(args, 1, n))
    if anySecret then return secret(text) end
    return text
end
def("issecretvalue", function(x) return isSecretObj(x) end)
local realSetValue = impl.SetValue
impl.SetValue = function(f, v)
    local s = S(f)
    if isSecretObj(v) or isSecretObj(s.max) or isSecretObj(s.min) then s.value = v return end
    return realSetValue(f, v)
end

---------------------------------------------------------------------------
-- Monde simulé : moi (guerrier), un groupe, une cible
---------------------------------------------------------------------------
local world = {
    raid = false,
    units = {},            -- ["party1"] = { name, class, classFile, role, mana, max }
    target = nil,          -- nom de la cible (ou nil)
    secretRole = false, secretName = false, secretClass = false, secretMana = false, secretMax = false,
}
local ME = "Moi"
local function unitName(u)
    if u == "player" then return ME end
    if u == "target" then return world.target end
    return world.units[u] and world.units[u].name
end
def("IsInRaid", function() return world.raid end)
def("GetNumSubgroupMembers", function()
    local n = 0
    for u in pairs(world.units) do if u:find("^party") then n = n + 1 end end
    return n
end)
def("GetNumGroupMembers", function()
    local n = 0
    for u in pairs(world.units) do if u:find("^raid") then n = n + 1 end end
    return n
end)
def("UnitExists", function(u) return unitName(u) ~= nil end)
def("UnitIsUnit", function(a, b)
    local x, y = unitName(a), unitName(b)
    return x ~= nil and x == y
end)
def("UnitName", function(u)
    local n = unitName(u)
    if n and world.secretName and u ~= "player" then return secret(n) end
    return n
end)
def("UnitClass", function(u)
    local e = world.units[u]
    if not e then return "Guerrier", "WARRIOR", 1 end
    if world.secretClass then return secret(e.class), secret(e.classFile), 5 end
    return e.class, e.classFile, 5
end)
def("UnitGroupRolesAssigned", function(u)
    local e = world.units[u]
    local role = e and e.role or "NONE"
    if world.secretRole then return secret(role) end
    return role
end)
local manaCalls = 0
def("UnitPower", function(u, powerType)
    manaCalls = manaCalls + 1
    local e = world.units[u]
    if not e then return 0 end
    if world.secretMana then return secret(e.mana) end
    return e.mana
end)
def("UnitPowerMax", function(u, powerType)
    local e = world.units[u]
    if not e then return 0 end
    if world.secretMax then return secret(e.max) end
    return e.max
end)
def("RAID_CLASS_COLORS", {
    PRIEST = { r = 1, g = 1, b = 1 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    ROGUE = { r = 1, g = 0.96, b = 0.41 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
})

-- ce qu'exige la barre de ressource (chargée avec Resources.lua) pour s'initialiser
def("UnitPowerType", function() return 1, "RAGE", 0, 0, 0 end)
def("PowerBarColor", {
    RAGE = { r = 1, g = 0, b = 0 }, MANA = { r = 0, g = 0, b = 1 }, [0] = { r = 0, g = 0, b = 1 }, [1] = { r = 1, g = 0, b = 0 },
})
def("GetActionInfo", function() end)
def("C_ActionBar", { IsUsableAction = function() return true, false end })
def("C_Spell", { GetSpellPowerCost = function() return {} end, GetSpellTexture = function() return 1 end, IsSpellUsable = function() return true end })
def("ActionButtonUtil", { ActionBarButtonNames = { "ActionButton" } })
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.action = i
    b.TextOverlayContainer = CreateFrame("Frame", nil, b)
end

local function party(list)
    world.units = {}
    for i, e in ipairs(list) do world.units["party" .. i] = e end
end
local function member(name, role, classFile, class, mana, max)
    return { name = name, role = role, classFile = classFile, class = class, mana = mana or 3000, max = max or 6000 }
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Resources.lua", "ResourceBar.lua", "HealerMana.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.5)

local H = ns.HealerMana
local F = H.frames or {}
local T = ns.THEME
local function strip(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function valueText() return strip(S(F.value).text) end
local function nameOf() return tostring(S(F.name).text) end
local function printedCount(text)
    local n = 0
    for _, line in ipairs(M.printed) do if line:find(text, 1, true) then n = n + 1 end end
    return n
end
local function pollers()
    local n = 0
    for _, f in ipairs(M.allFrames) do
        if S(f).scripts.OnUpdate and impl.IsVisible(f) then n = n + 1 end
    end
    return n
end
local function unitEvent(event, unit, token) M.fireEvent(event, unit, token) end
local function roster() M.fireEvent("GROUP_ROSTER_UPDATE") end
-- unité dont la mana est écoutée ; le simulateur garde la liste des unités après UnregisterAllEvents : on regarde l'événement
local function watching()
    if not S(F.events).events.UNIT_POWER_UPDATE then return nil end
    return S(F.events).units and S(F.events).units.UNIT_POWER_UPDATE
end

---------------------------------------------------------------------------
section("affichage de base")
check(F.root ~= nil and rawget(_G, "PlatyplusHealerMana") == F.root, "cadre PlatyplusHealerMana créé")
check(ns.db.healerBar == false, "coupée par défaut")
check(not S(F.root).shown, "cachée")
check(next(S(F.events).events) == nil, "option coupée : aucun événement écouté")
check(ns.db.healerName == "" and ns.db.healerWidth == 200 and ns.db.healerScale == 1 and ns.db.healerLocked == true,
    "réglages par défaut : aucun healer choisi, 200, 100 %, verrouillée")
check(ns.db.healerX == -260 and ns.db.healerY == -120, "position par défaut (-260, -120)")
check(ns.db.healerLow == true and ns.db.healerLowPercent == 20 and ns.db.healerLowSound == false,
    "alerte « à sec » : allumée, seuil 20 %, sans son")

ns:Set("healerBar", true)
check(not S(F.root).shown, "allumée mais sans groupe : cachée")
check(S(F.events).events.GROUP_ROSTER_UPDATE and S(F.events).events.PLAYER_ROLES_ASSIGNED, "écoute les changements de groupe et de rôle")
check(watching() == nil, "aucune mana écoutée tant qu'il n'y a pas de healer")
local p = S(F.root).points[1]
check(p and p[1] == "CENTER" and p[2] == UIParent and p[3] == "CENTER" and p[4] == -260 and p[5] == -120, "position depuis le centre de l'écran")
check(S(F.root).w == 200 and S(F.root).h == 22 and S(F.root).scale == 1, "200 x 22, échelle 1")
check(tostring(S(F.fill).barFile):find("Media\\Bar", 1, true) ~= nil, "texture Media\\Bar")
local bc = S(F.fill).barColor
check(bc and bc[3] > bc[1] and bc[3] > 0.9, "remplissage bleu (couleur de la mana)")

---------------------------------------------------------------------------
section("healer désigné par le groupe")
party({
    member("Tomas", "TANK", "WARRIOR", "Guerrier"),
    member("Ariane", "HEALER", "PRIEST", "Prêtre", 4200, 6800),
    member("Ben", "DAMAGER", "ROGUE", "Voleur"),
})
roster()
check(S(F.root).shown, "un healer dans le groupe : barre visible")
check(nameOf() == "Ariane", "nom du healer (" .. nameOf() .. ")")
local nc = S(F.name).color
check(nc and nc[1] == 1 and nc[2] == 1 and nc[3] == 1, "nom à la couleur de sa classe (prêtre : blanc)")
check(valueText() == "4,200 / 6,800", "chiffre « 4,200 / 6,800 » (" .. valueText() .. ")")
check(tostring(S(F.value).text):find("|c", 1, true) ~= nil, "« / 6,800 » atténué")
check(S(F.fill).min == 0 and S(F.fill).max == 6800 and S(F.fill).value == 4200, "remplissage 4200 sur 6800")
check(watching() and watching()[1] == "party2", "la mana écoutée est celle de party2 seulement")
check(S(F.events).units.UNIT_MAXPOWER[1] == "party2" and S(F.events).units.UNIT_DISPLAYPOWER[1] == "party2", "maximum et type de ressource aussi")
check(H:Summary():find("Ariane", 1, true) ~= nil and H:Summary():find("Prêtre", 1, true) ~= nil, "Summary : nom et classe (" .. tostring(H:Summary()) .. ")")

section("événements de mana")
world.units.party2.mana = 1000
M.advance(1)
check(valueText() == "4,200 / 6,800", "sans événement, rien ne bouge (pas de scrutation)")
unitEvent("UNIT_POWER_UPDATE", "party2", "MANA")
check(valueText() == "1,000 / 6,800" and S(F.fill).value == 1000, "UNIT_POWER_UPDATE : chiffre et remplissage à jour")
world.units.party2.mana = 2500
unitEvent("UNIT_POWER_UPDATE", "party3", "MANA")
check(valueText() == "1,000 / 6,800", "événement d'un autre joueur ignoré (repli sans RegisterUnitEvent)")
unitEvent("UNIT_POWER_UPDATE", "party2", "RAGE")
check(valueText() == "1,000 / 6,800", "événement d'une autre ressource ignoré")
unitEvent("UNIT_POWER_UPDATE", "party2", "MANA")
check(valueText() == "2,500 / 6,800", "puis la mana suivante")
world.units.party2.max = 7000
unitEvent("UNIT_MAXPOWER", "party2")
check(valueText() == "2,500 / 7,000" and S(F.fill).max == 7000, "UNIT_MAXPOWER : nouveau maximum")
M.advance(2)       -- l'éclat de l'alerte (mana passée à 14 %) est fini
check(pollers() == 0, "aucune boucle OnUpdate")

section("le groupe change")
party({
    member("Ariane", "HEALER", "PRIEST", "Prêtre", 4200, 6800),
    member("Ben", "DAMAGER", "ROGUE", "Voleur"),
})
roster()
check(nameOf() == "Ariane" and watching()[1] == "party1", "Tomas part : Ariane devient party1, la mana écoutée suit")
party({ member("Ben", "DAMAGER", "ROGUE", "Voleur") })
roster()
check(not S(F.root).shown, "le healer part : barre cachée")
check(watching() == nil, "plus aucune mana écoutée")
check(H:Summary() == nil, "Summary : aucun healer")
party({ member("Ben", "DAMAGER", "ROGUE", "Voleur"), member("Cléo", "HEALER", "DRUID", "Druide", 100, 5000) })
M.fireEvent("PLAYER_ROLES_ASSIGNED")
check(S(F.root).shown and nameOf() == "Cléo" and valueText() == "100 / 5,000", "rôle donné par le chef : la barre apparaît")
local dc = S(F.name).color
check(dc and dc[1] == 1 and math.abs(dc[2] - 0.49) < 1e-6, "couleur du druide")
party({ member("Cléo", "HEALER", "DRUID", "Druide", 100, 5000), member("Ariane", "HEALER", "PRIEST", "Prêtre") })
roster()
check(nameOf() == "Cléo", "deux soigneurs : le premier de la liste")

---------------------------------------------------------------------------
section("choisir son healer avec la cible")
M.printed = {}
world.target = nil
check(H:PickTarget() == false and printedCount("cible d'abord") == 1, "sans cible : message, rien ne change")
world.target = "Inconnu"
check(H:PickTarget() == false and printedCount("n'est pas dans ton groupe") == 1 and ns.db.healerName == "", "cible hors groupe : refusée")
world.target = ME
check(H:PickTarget() == false and ns.db.healerName == "", "se cibler soi-même : refusé")
world.target = "Ariane"
check(H:PickTarget() == true and ns.db.healerName == "Ariane", "cible dans le groupe : choisie")
check(nameOf() == "Ariane" and watching()[1] == "party2", "la barre suit Ariane (party2) malgré un autre soigneur plus haut")
check(printedCount("tu suis maintenant Ariane") == 1, "message de confirmation")
party({ member("Ariane", "DAMAGER", "PRIEST", "Prêtre", 900, 6800), member("Cléo", "HEALER", "DRUID", "Druide") })
roster()
check(nameOf() == "Ariane" and watching()[1] == "party1", "choisie à la main : suivie même sans le rôle de soigneur")
party({ member("Cléo", "HEALER", "DRUID", "Druide", 100, 5000) })
roster()
check(nameOf() == "Cléo", "le joueur choisi quitte le groupe : retour au soigneur désigné")
party({ member("Cléo", "HEALER", "DRUID", "Druide", 100, 5000), member("Ariane", "DAMAGER", "PRIEST", "Prêtre") })
roster()
check(nameOf() == "Ariane", "il revient : de nouveau suivi")
H:ClearPick()
check(ns.db.healerName == "" and nameOf() == "Cléo", "« Laisser le jeu choisir » : retour au rôle")

---------------------------------------------------------------------------
section("raid")
world.units = {}
world.raid = true
for i, e in ipairs({
    member(ME, "DAMAGER", "WARRIOR", "Guerrier"),
    member("Tomas", "TANK", "WARRIOR", "Guerrier"),
    member("Ariane", "HEALER", "PRIEST", "Prêtre", 5000, 9000),
}) do world.units["raid" .. i] = e end
roster()
check(nameOf() == "Ariane" and watching()[1] == "raid3", "raid : healer trouvé parmi raid1..raidN, jeton raid3")
world.units.raid1.role = "HEALER"      -- moi, soigneur : jamais mon propre mana
roster()
check(nameOf() == "Ariane", "je ne me suis pas moi-même (je suis raid1)")
world.raid = false

---------------------------------------------------------------------------
section("valeurs secrètes")
party({ member("Ariane", "HEALER", "PRIEST", "Prêtre", 4200, 6800) })
roster()
M.errors = {}
world.secretMana = true
unitEvent("UNIT_POWER_UPDATE", "party1", "MANA")
check(valueText() == "4200 / 6800", "mana secrète affichée sans calcul (" .. valueText() .. ")")
check(isSecretObj(S(F.value).text) and isSecretObj(S(F.fill).value), "texte et remplissage reçoivent la valeur secrète")
check(S(F.root).shown, "barre toujours visible")
world.secretMax = true
unitEvent("UNIT_MAXPOWER", "party1")
check(isSecretObj(S(F.fill).max) and S(F.root).shown, "maximum secret passé tel quel à la barre")
world.secretMana, world.secretMax = false, false
unitEvent("UNIT_MAXPOWER", "party1")
check(valueText() == "4,200 / 6,800" and S(F.fill).value == 4200, "retour aux valeurs ordinaires")
world.secretRole = true
roster()
check(S(F.root).shown and nameOf() == "Ariane" and watching()[1] == "party1", "rôle secret : on garde le healer déjà trouvé")
world.secretRole = false
world.secretName, world.secretClass = true, true
roster()
check(isSecretObj(S(F.name).text), "nom secret passé tel quel à SetText")
local sc = S(F.name).color
check(sc and sc[1] == T.text[1], "classe secrète : nom en blanc neutre")
check(H:Summary() ~= nil and H:Summary():find("masqué", 1, true) ~= nil, "Summary : « nom masqué » sans erreur")
world.secretName, world.secretClass = false, false
roster()
check(#M.errors == 0, "aucune opération interdite sur une valeur secrète (" .. tostring(M.errors[1]) .. ")")

section("sans mana")
world.units.party1.max = 0
unitEvent("UNIT_MAXPOWER", "party1")
check(not S(F.root).shown, "maximum lisible à 0 : cachée")
world.units.party1.max = 6800
unitEvent("UNIT_MAXPOWER", "party1")
check(S(F.root).shown, "mana de retour : visible")

---------------------------------------------------------------------------
section("alerte « healer à sec »")
local sounds = {}
def("PlaySound", function(id) sounds[#sounds + 1] = id end)
local function barRed()
    local c = S(F.fill).barColor
    return c ~= nil and c[1] == 1 and math.abs(c[2] - 0.3) < 1e-6 and math.abs(c[3] - 0.3) < 1e-6
end
local function barBlue()
    local c = S(F.fill).barColor
    return c ~= nil and c[3] > c[1] and c[3] > 0.9
end
local function healerMana(cur)
    world.units.party1.mana = cur
    unitEvent("UNIT_POWER_UPDATE", "party1", "MANA")
end
party({ member("Ariane", "HEALER", "PRIEST", "Prêtre", 4200, 6800) })
ns:Set("healerLowSound", true)
M.inCombat = false
roster()
M.advance(2)
check(not H:IsLow() and barBlue(), "4 200 / 6 800 (62 %) : pas à sec, barre bleue")
healerMana(1360)
check(not H:IsLow(), "pile 20 % : pas encore à sec (« sous » le seuil)")
healerMana(1359)
check(H:IsLow() and barRed(), "sous 20 % : à sec, barre rouge")
check(S(F.driver).shown, "éclat lancé")
M.advance(0.1)
check(S(F.flash).alpha > 0.2, "éclat visible (" .. tostring(S(F.flash).alpha) .. ")")
M.advance(2)
check(not S(F.driver).shown and S(F.flash).alpha == 0 and pollers() == 0, "éclat fini : plus de boucle, rouge éteint")
check(barRed() and H:IsLow(), "la barre reste rouge tant que le healer est à sec")
check(#sounds == 0, "hors combat : pas de son, même coché")
healerMana(1496)
check(H:IsLow() and #sounds == 0, "22 % : toujours à sec (l'alerte se retire à 25 %)")
healerMana(1700)
check(not H:IsLow() and barBlue(), "25 % : alerte retirée, barre bleue")
M.advance(2)
healerMana(1400)
check(not H:IsLow() and not S(F.driver).shown, "20,6 % : pas de nouvelle alerte (le seuil est 20)")
M.inCombat = true
healerMana(1000)
check(H:IsLow() and #sounds == 1 and sounds[1] == 8959, "en combat : un son (SOUNDKIT.RAID_WARNING = 8959)")
healerMana(900)
check(#sounds == 1, "pas de son répété tant que l'alerte dure")
M.advance(2)
roster()
check(#sounds == 1 and not S(F.driver).shown and H:IsLow(), "changement de groupe : pas de nouvel éclat ni son")
ns:Set("healerLowSound", false)
healerMana(3000); healerMana(500)
check(H:IsLow() and #sounds == 1 and S(F.driver).shown, "sans l'option son : éclat mais pas de son")
M.advance(2)
M.inCombat = false

section("seuil et interrupteur")
healerMana(2500)                                    -- 36,8 %
check(not H:IsLow(), "36,8 % : pas à sec avec le seuil à 20 %")
ns:Set("healerLowPercent", 40)
check(H:IsLow() and barRed(), "seuil changé à 40 % : à sec tout de suite")
ns:Set("healerLowPercent", 20)
check(not H:IsLow() and barBlue(), "seuil remis à 20 % : alerte retirée")
M.advance(2)
healerMana(500)
check(H:IsLow(), "7 % : à sec")
ns:Set("healerLow", false)
check(not H:IsLow() and barBlue(), "alerte coupée : la barre redevient bleue")
healerMana(300)
M.advance(2)
check(not H:IsLow() and not S(F.driver).shown, "alerte coupée : mana à 4 %, rien")
ns:Set("healerLow", true)
check(H:IsLow() and barRed(), "alerte rallumée : à sec tout de suite")
M.advance(2)
party({ member("Ben", "DAMAGER", "ROGUE", "Voleur"), member("Cléo", "HEALER", "DRUID", "Druide", 100, 5000) })
roster()
check(H:IsLow() and S(F.driver).shown and nameOf() == "Cléo" and watching()[1] == "party2",
    "un autre healer (autre jeton) déjà à sec : l'alerte repart pour lui")
M.advance(2)
party({ member("Ariane", "HEALER", "PRIEST", "Prêtre", 4200, 6800) })
roster()
check(not H:IsLow() and barBlue(), "healer remplacé par un autre bien rempli : alerte retirée")
party({})
roster()
check(not H:IsLow() and not S(F.root).shown, "plus de healer : pas d'alerte, barre cachée")

section("alerte avec mana secrète (courbe de couleur)")
local curves, percentCalls = 0, 0
local function mkColor(r, g, b, a) return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(self) return self.r, self.g, self.b, self.a end } end
def("CreateColor", mkColor)
local enum = rawget(_G, "Enum") or {}
enum.LuaCurveType = { Linear = 0, Step = 1 }
def("Enum", enum)
local lastCurve
def("C_CurveUtil", { CreateColorCurve = function()
    curves = curves + 1
    local c = { points = {} }
    function c:SetType(t) self.type = t end
    function c:AddPoint(x, color) self.points[#self.points + 1] = { x = x, color = color } end
    lastCurve = c
    return c
end })
def("UnitPowerPercent", function(u, powerType, unmodified, curve)
    percentCalls = percentCalls + 1
    local e = world.units[u]
    local pct = e.mana / e.max
    local pick
    for _, pt in ipairs(curve.points) do if pt.x <= pct then pick = pt.color end end
    return pick
end)
party({ member("Ariane", "HEALER", "PRIEST", "Prêtre", 4200, 6800) })
M.inCombat = true
ns:Set("healerLowSound", true)
roster()
M.advance(2)
M.errors = {}
local soundsBefore = #sounds
world.secretMana, world.secretMax = true, true
healerMana(600)                                     -- 8,8 %
check(isSecretObj(S(F.fill).value) and valueText() == "600 / 6800", "mana secrète passée telle quelle (" .. valueText() .. ")")
check(barRed(), "8,8 % (secrète) : la courbe rend la barre rouge")
check(not H:IsLow() and not S(F.driver).shown and #sounds == soundsBefore, "mais ni éclat ni son : rien de lisible à comparer")
check(curves == 1 and lastCurve.type == 1 and #lastCurve.points == 2, "courbe en escalier créée une fois, deux points")
check(lastCurve.points[1].x == 0 and math.abs(lastCurve.points[2].x - 0.2) < 1e-9, "rouge dès 0, couleur de la mana à partir de 0,2")
healerMana(3400)                                    -- 50 %
check(barBlue() and curves == 1, "50 % (secrète) : bleu, même courbe réutilisée")
ns:Set("healerLowPercent", 40)
check(curves == 2 and math.abs(lastCurve.points[2].x - 0.4) < 1e-9, "seuil à 40 % : courbe refaite avec 0,4")
healerMana(2380)                                    -- 35 %
check(barRed(), "35 % (secrète) avec le seuil à 40 % : rouge")
world.secretMana, world.secretMax = false, false
M.inCombat = false
healerMana(2380)
check(H:IsLow() and barRed() and S(F.driver).shown, "retour à une valeur lisible : alerte normale (éclat)")
M.advance(2)
ns:Set("healerLowPercent", 20)
check(not H:IsLow() and barBlue(), "seuil à 20 % : 35 % n'est plus à sec, bleu")
world.secretMana, world.secretMax = true, true
def("UnitPowerPercent", function() percentCalls = percentCalls + 1; error("boom") end)
local callsBefore = percentCalls
for _ = 1, 3 do healerMana(600) end
check(barBlue() and percentCalls - callsBefore == 1, "courbe refusée par le jeu : couleur normale, pas de nouvel essai (" .. (percentCalls - callsBefore) .. ")")
world.secretMana, world.secretMax = false, false
healerMana(4200)
check(#M.errors == 0, "aucune erreur Lua (" .. tostring(M.errors[1]) .. ")")

section("aperçu de l'alerte")
party({})
roster()
ns:Set("healerLowSound", true)
M.inCombat = false
local soundsBeforePreview = #sounds
H:Preview()
check(S(F.root).shown and valueText() == "4,200 / 6,800" and not H:IsLow() and barBlue(), "aperçu : mana d'exemple bien remplie d'abord")
M.advance(2.2)
check(H:IsLow() and barRed() and valueText() == "816 / 6,800", "puis sous le seuil (12 %) : rouge (" .. valueText() .. ")")
check(S(F.driver).shown, "avec l'éclat")
check(#sounds == soundsBeforePreview + 1, "et le son, même hors combat, pour l'entendre")
M.advance(5)
check(not S(F.root).shown and not H:IsLow() and barBlue(), "fin : barre cachée, alerte retirée")
H:Preview()
check(valueText() == "4,200 / 6,800" and not H:IsLow(), "aperçu relancé : repart de la mana pleine")
M.advance(7)
party({ member("Ariane", "HEALER", "PRIEST", "Prêtre", 4200, 6800) })
roster()
H:Preview()
check(nameOf() == "Mon healer", "aperçu avec un vrai healer : la barre d'exemple prend la place")
healerMana(100)
check(valueText() == "4,200 / 6,800", "pendant l'aperçu : les événements du vrai healer ne l'écrasent pas")
M.advance(7)
check(nameOf() == "Ariane" and valueText() == "100 / 6,800" and H:IsLow(), "après l'aperçu : le vrai healer est de retour (à sec)")
M.advance(2)
ns:Set("healerLowSound", false)
healerMana(4200)
party({})
roster()

---------------------------------------------------------------------------
section("déplacement")
party({})
roster()
check(not S(F.root).shown, "sans healer : cachée")
H:ToggleMove()
check(ns.db.healerLocked == false and S(F.mover).shown, "déverrouillée : cadre « glisse-moi » visible")
check(S(F.root).shown and nameOf() == "Mon healer" and valueText() == "4,200 / 6,800", "barre d'exemple visible pour la placer")
check(printedCount("glisse la barre") == 1, "message d'aide affiché")
S(F.root).center = { 783, 284 }
M.fire(F.mover, "OnDragStart")
M.fire(F.mover, "OnDragStop")
check(ns.db.healerX == 100 and ns.db.healerY == -100, "position enregistrée depuis le centre (" .. tostring(ns.db.healerX) .. ", " .. tostring(ns.db.healerY) .. ")")
p = S(F.root).points[1]
check(p[1] == "CENTER" and p[4] == 100 and p[5] == -100, "barre réancrée au centre + décalage")
S(F.root).center = nil
M.fire(F.mover, "OnMouseUp", "RightButton")
check(ns.db.healerLocked == true and not S(F.mover).shown, "clic droit : verrouillée")
check(not S(F.root).shown, "sans healer : de nouveau cachée")
H:ResetPosition()
p = S(F.root).points[1]
check(ns.db.healerX == -260 and ns.db.healerY == -120 and p[4] == -260 and p[5] == -120, "ResetPosition : position par défaut")

section("aperçu")
H:Preview()
check(S(F.root).shown and nameOf() == "Mon healer", "Preview : barre d'exemple visible sans healer")
M.advance(3)
check(S(F.root).shown, "toujours là après 3 s")
M.advance(4)
check(not S(F.root).shown, "disparaît après l'aperçu")
ns:Set("healerBar", false)
check(next(S(F.events).events) == nil, "barre coupée : plus aucun événement écouté")
H:Preview(2)
check(S(F.root).shown and S(F.events).events.GROUP_ROSTER_UPDATE, "Preview même coupée : visible et à jour")
M.advance(3)
check(not S(F.root).shown and next(S(F.events).events) == nil, "fin de l'aperçu : cachée et silencieuse")
party({ member("Ariane", "HEALER", "PRIEST", "Prêtre", 4200, 6800) })
roster()
check(not S(F.root).shown, "coupée : un healer dans le groupe ne montre rien")
ns:Set("healerBar", true)
check(S(F.root).shown and nameOf() == "Ariane", "réactivée : visible")

---------------------------------------------------------------------------
section("réglages")
ns:Set("healerWidth", 300)
check(S(F.root).w == 300, "largeur 300")
ns:Set("healerWidth", 200)
ns:Set("healerScale", 1.5)
check(S(F.root).scale == 1.5, "échelle 150 %")
ns:Set("healerScale", 1)
ns:Set("healerX", 40); ns:Set("healerY", -200)
p = S(F.root).points[1]
check(p[4] == 40 and p[5] == -200, "healerX / healerY réglés à la main")
H:ResetPosition()
ns:Set("healerName", "Ariane")
check(nameOf() == "Ariane", "healerName écrit à la main : pris en compte tout de suite")
ns:Set("healerName", "")

section("commande /pp healer")
M.printed = {}
SlashCmdList.PLATYPLUS("healer off")
check(ns.db.healerBar == false and not S(F.root).shown, "/pp healer off")
SlashCmdList.PLATYPLUS("healer on")
check(ns.db.healerBar == true and S(F.root).shown, "/pp healer on")
world.target = "Ariane"
SlashCmdList.PLATYPLUS("healer cible")
check(ns.db.healerName == "Ariane", "/pp healer cible")
SlashCmdList.PLATYPLUS("healer auto")
check(ns.db.healerName == "", "/pp healer auto")
M.printed = {}
SlashCmdList.PLATYPLUS("healer")
check(printedCount("healer suivi") == 1 and printedCount("Ariane") == 1, "/pp healer : dit qui est suivi")

---------------------------------------------------------------------------
section("sans scrutation")
M.advance(6)
check(pollers() == 0, "au repos, aucune boucle OnUpdate")
local before = manaCalls
M.advance(30)
check(manaCalls == before, "UnitPower jamais appelé sans événement (" .. (manaCalls - before) .. " appel(s))")

---------------------------------------------------------------------------
section("garde-fou")
def("UnitPower", function() error("boom") end)
for _ = 1, 4 do unitEvent("UNIT_POWER_UPDATE", "party1", "MANA"); M.advance(0.1) end
check(printedCount("« mana du healer » coupé") == 1, "coupée après 3 erreurs, message une seule fois, aucune erreur Lua")

---------------------------------------------------------------------------
section("bilan")
local badGlobals = {}
for _, name in ipairs(M.newGlobals) do
    if not (name:find("^Platyplus") or name:find("^SLASH_PLATYPLUS")) then badGlobals[#badGlobals + 1] = name end
end
check(#badGlobals == 0, "aucune globale hors « Platyplus… » (" .. table.concat(badGlobals, ",") .. ")")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
