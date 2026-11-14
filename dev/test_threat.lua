-- Test : fenêtre de menace (Threat.lua) dans le simulateur strict
-- Mobs factices (plates, boss, cibles de groupe), menace pilotée par le test, valeurs secrètes (menace, nom, vie).
-- Vérifie : énumération + dédoublonnage, filtres (mort/joueur/hors combat), couleurs (comme les plates), tri
-- (danger / vie / arrivée), filtre « que ceux que je n'ai pas », lignes max, en-tête « N mobs · M perdus »,
-- affichage automatique (combat, 3 s de grâce, groupe), menace secrète, aperçu /pp menace test, pas d'OnUpdate hors combat.
-- Usage : python -I dev\lua.py run dev\test_threat.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local impl, S = M.impl, M.state

impl.SetText = function(f, t) S(f).text = t end
impl.GetText = function(f) return S(f).text end
impl.SetValue = function(f, v) S(f).value = v end
impl.SetMinMaxValues = function(f, a, b) S(f).min, S(f).max = a, b end
impl.SetVertexColorFromBoolean = function(tex, value, ifTrue, ifFalse)
    S(tex).fromBool = { value = value, ifTrue = ifTrue, ifFalse = ifFalse }
end
impl.RegisterForDrag = function(f, ...) S(f).drag = select("#", ...) > 0 end
impl.SetVertexColor = function(f, r, g, b) S(f).vertex = { r, g, b } end

---------------------------------------------------------------------------
-- Valeurs secrètes
---------------------------------------------------------------------------
local SecretMT = {}
local function secret(v) return setmetatable({ v = v }, SecretMT) end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__lt", "__le", "__len", "__call", "__concat", "__eq" }) do
    SecretMT[op] = function() error("opération interdite sur une valeur secrète (" .. op .. ")", 2) end
end
SecretMT.__index = function() error("lecture interdite dans une valeur secrète", 2) end
def("issecretvalue", function(x) return getmetatable(x) == SecretMT end)

---------------------------------------------------------------------------
-- Monde simulé
---------------------------------------------------------------------------
local sim = {
    units = {},          -- [jeton] = mob (la même table pour deux jetons = le même mob)
    group = true, raid = false, combat = false, forms = {},
}
local function mob(t)
    t.hp, t.max = t.hp or 100, t.max or 100
    if t.combat == nil then t.combat = true end
    if t.canAttack == nil then t.canAttack = true end
    return t
end
def("UnitExists", function(u)
    if sim.units[u] ~= nil or u == "player" then return true end
    local base = u:match("^(.-)target$")
    return base ~= nil and sim.units[base] ~= nil and sim.units[base].holder ~= nil
end)
def("UnitCanAttack", function(_, u) return sim.units[u] ~= nil and sim.units[u].canAttack end)
def("UnitIsPlayer", function(u) return sim.units[u] ~= nil and sim.units[u].player == true end)
def("UnitIsDead", function(u) return sim.units[u] ~= nil and sim.units[u].dead == true end)
def("UnitAffectingCombat", function(u)
    if u == "player" then return sim.combat end
    return sim.units[u] ~= nil and sim.units[u].combat
end)
def("UnitIsUnit", function(a, b) return sim.units[a] ~= nil and sim.units[a] == sim.units[b] end)
def("UnitGUID", function(u) return sim.units[u] and sim.units[u].guid or nil end)
def("UnitName", function(u)
    if sim.units[u] then return sim.units[u].name end
    local base = u:match("^(.-)target$")
    if base and sim.units[base] then return sim.units[base].holder end
    return nil
end)
def("UnitHealth", function(u) return sim.units[u].hp end)
def("UnitHealthMax", function(u) return sim.units[u].max end)
def("GetRaidTargetIndex", function(u) return sim.units[u] and sim.units[u].marker or nil end)
def("SetRaidTargetIconTexture", function(tex, i) S(tex).marker = i end)
def("IsInGroup", function() return sim.group end)
def("IsInRaid", function() return sim.raid end)
def("GetNumSubgroupMembers", function() return 0 end)
def("GetNumGroupMembers", function() return 1 end)
def("UnitGroupRolesAssigned", function() return "NONE" end)
def("UnitHasEffectivelyTankAura", function() return false end)
def("GetNumShapeshiftForms", function() return #sim.forms end)
def("GetShapeshiftFormInfo", function(i) local f = sim.forms[i] return 1, f.active, true, f.spellID end)
def("UnitDetailedThreatSituation", function(_, u)
    local m = sim.units[u]
    if not m then return nil end
    if m.threat == nil then return nil end
    return m.threat[1], m.threat[2], m.threat[3] or 0, 0, 0
end)
def("UnitThreatSituation", function() return nil end)
def("CreateColor", function(r, g, b, a) return { r = r, g = g, b = b, a = a } end)

-- la mise en forme de nombres secrets (string.format) rend un texte secret
local realFormat = string.format
string.format = function(fmt, ...)
    local n = select("#", ...)
    local args, anySecret = { ... }, false
    for i = 1, n do
        if getmetatable(args[i]) == SecretMT then args[i] = args[i].v; anySecret = true end
    end
    local text = realFormat(fmt, unpack(args, 1, n))
    if anySecret then return secret(text) end
    return text
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Resources.lua", "UIWidgets.lua", "Windows.lua", "Plates.lua", "Threat.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(1)
local T, P = ns.Threat, ns.Plates

local function frame()
    for _, f in ipairs(M.allFrames) do if S(f).name == "PlatyplusThreat" then return f end end
end
local function shown() local f = frame() return f ~= nil and S(f).shown == true end
local function rowsOf()
    local f = frame()
    local list = {}
    if not f then return list end
    for _, child in ipairs(S(f).frames or {}) do
        local s = S(child)
        if s.shown and s.regions and #s.regions >= 6 then list[#list + 1] = child end
    end
    return list
end
-- textes d'une ligne : nom (1re FontString), qui le tient (2e), %
local function fontStrings(row)
    local out = {}
    for _, r in ipairs(S(row).regions) do if S(r).kind == "FontString" then out[#out + 1] = r end end
    return out
end
local function stripeVertex(row) return S(S(row).regions[2]).vertex end
local function names()
    local out = {}
    for _, row in ipairs(rowsOf()) do out[#out + 1] = S(fontStrings(row)[1]).text end
    return out
end
local function joined() return table.concat(names(), ",") end
local function headerText()
    local f = frame()
    for _, r in ipairs(S(S(f).frames[1]).regions) do
        if S(r).kind == "FontString" and r ~= f.title then
            local t = S(r).text
            if type(t) == "string" and (t:find("mob") or t:find("Aucun")) then return t end
        end
    end
end
local function near(c, ref) return c and math.abs(c[1] - ref[1]) < 0.01 and math.abs(c[2] - ref[2]) < 0.01 and math.abs(c[3] - ref[3]) < 0.01 end
local COLORS = P.COLOR_DEFAULTS
local function enterCombat() sim.combat = true; M.fireEvent("PLAYER_REGEN_DISABLED"); M.advance(0.3) end
local function leaveCombat() sim.combat = false; M.fireEvent("PLAYER_REGEN_ENABLED") end
local function setForm(on)
    sim.forms = on and { { active = true, spellID = 71 } } or {}
    M.fireEvent("UPDATE_SHAPESHIFT_FORM")
    M.advance(0.3)
end
local function refresh() M.fireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1"); M.advance(0.3) end

---------------------------------------------------------------------------
section("réglages et démarrage")
check(ns.db.threatWindow == true and ns.db.threatAuto == true and ns.db.threatSort == "danger", "réglages par défaut présents")
check(not shown(), "hors combat, en mode auto : fenêtre cachée")
check(#M.errors == 0, "aucune erreur au chargement")

---------------------------------------------------------------------------
section("énumération et dédoublonnage")
setForm(true)    -- tank
local a = mob({ name = "Alpha", guid = "G1", threat = { false, 0 }, holder = "Sylvara", marker = 8 })
local b = mob({ name = "Bravo", guid = "G2", threat = { true, 3 }, hp = 40, holder = "Heros" })
local c = mob({ name = "Charlie", guid = "G3", threat = { false, 1 }, hp = 90, holder = "Heros" })
sim.units.nameplate1, sim.units.nameplate2, sim.units.nameplate3 = a, b, c
sim.units.target = a                         -- même mob que nameplate1 : une seule ligne
sim.units.party1target = c                   -- idem
sim.units.focus = mob({ name = "Mort", guid = "G4", dead = true, threat = { false, 0 } })
sim.units.nameplate4 = mob({ name = "Joueur", guid = "G5", player = true, threat = { false, 0 } })
sim.units.nameplate5 = mob({ name = "Calme", guid = "G6", combat = false, threat = { false, 0 } })
enterCombat()
check(shown(), "combat : la fenêtre apparaît")
check(#rowsOf() == 3, "3 lignes (doublons, mort, joueur et mob hors combat écartés), vu " .. #rowsOf())
check(joined() == "Alpha,Charlie,Bravo", "tri danger : perdu, fragile, tenu (" .. joined() .. ")")
check(headerText() == "3 mobs · 1 perdu", "en-tête : « 3 mobs · 1 perdu » (" .. tostring(headerText()) .. ")")

section("couleurs, qui le tient, %")
local rows = rowsOf()
check(near(stripeVertex(rows[1]), COLORS.loose), "Alpha : rouge (tu ne l'as plus)")
check(near(stripeVertex(rows[2]), COLORS.warn), "Charlie : orange (tu le perds)")
check(near(stripeVertex(rows[3]), COLORS.safe), "Bravo : vert (tu l'as)")
check(S(fontStrings(rows[3])[2]).text == "toi", "Bravo : « toi » dans la colonne du porteur")
check(S(fontStrings(rows[1])[2]).text == "Sylvara", "Alpha : tenu par Sylvara")
b.threat = { true, 3, 87 }
refresh()
check(S(fontStrings(rowsOf()[3])[3]).text == "87%", "ta menace en % sur la ligne de Bravo")
check(S(S(rows[1]).regions[3]).marker == 8, "marqueur de raid 8 sur Alpha")
local bar = nil
for _, ch in ipairs(S(rows[3]).frames or {}) do if S(ch).kind == "StatusBar" then bar = ch end end
check(bar and S(bar).value == 40 and S(bar).max == 100, "barre de vie de Bravo : 40 / 100")

section("tri par vie, par arrivée, filtre, lignes max")
ns:Set("threatSort", "health"); M.advance(0.3)
check(joined() == "Bravo,Charlie,Alpha", "tri vie : la plus basse d'abord (" .. joined() .. ")")
ns:Set("threatSort", "arrival"); M.advance(0.3)
check(#rowsOf() == 3, "tri arrivée : 3 lignes")
ns:Set("threatSort", "danger"); M.advance(0.3)
ns:Set("threatOnlyLost", true); M.advance(0.3)
check(joined() == "Alpha,Charlie", "« que ceux que je n'ai pas » : Bravo caché (" .. joined() .. ")")
check(headerText() == "3 mobs · 1 perdu", "l'en-tête compte tous les mobs, même cachés")
ns:Set("threatOnlyLost", false)
ns:Set("threatRows", 3); M.advance(0.3)
for i = 6, 9 do sim.units["nameplate" .. i] = mob({ name = "Extra" .. i, guid = "X" .. i, threat = { true, 3 }, holder = "Heros" }) end
refresh()
check(#rowsOf() == 3, "lignes max 3 respectées")
check(headerText() == "7 mobs · 1 perdu", "en-tête : 7 mobs au total (" .. tostring(headerText()) .. ")")
ns:Set("threatRows", 8)
for i = 6, 9 do sim.units["nameplate" .. i] = nil end
refresh()

section("DPS : les couleurs suivent le rôle")
setForm(false)
M.advance(0.3)
rows = rowsOf()
check(near(stripeVertex(rows[1]), COLORS.loose) or near(stripeVertex(rows[1]), COLORS.warn), "DPS : tri danger, premier = celui qui te tape ou va te taper")
check(headerText() == "3 mobs · 1 sur toi", "DPS : compteur « N sur toi » (ceux qui te frappent) (" .. tostring(headerText()) .. ")")
setForm(true)

section("alerte « perdu »")
local flashes = 0
local W = ns.W
local realAnimate = W.Animate
W.Animate = function(f, d, step, done) flashes = flashes + 1 return realAnimate(f, d, step, done) end
b.threat = { false, 0 }
refresh()
check(flashes == 1, "Bravo passe de tenu à perdu : un éclat (" .. flashes .. ")")
refresh()
check(flashes == 1, "pas de nouvel éclat tant qu'il reste perdu")
ns:Set("threatFlash", false)
b.threat = { true, 3 }; refresh()
b.threat = { false, 0 }; refresh()
check(flashes == 1, "éclat coupé : rien")
ns:Set("threatFlash", true)
W.Animate = realAnimate
b.threat = { true, 3 }; refresh()

section("valeurs secrètes")
local s1 = mob({ name = secret("Secret"), guid = secret("GS"), threat = { secret(true), secret(2), secret(55) },
    holder = secret("Autre"), hp = secret(70), max = secret(100), marker = secret(3) })
sim.units.nameplate7 = s1
refresh()
check(#M.errors == 0, "mob à valeurs secrètes : aucune erreur")
check(#rowsOf() == 4, "le mob secret a sa ligne")
local sr
for _, row in ipairs(rowsOf()) do
    if getmetatable(S(fontStrings(row)[1]).text) == SecretMT then sr = row end
end
check(sr ~= nil, "nom secret passé tel quel à SetText")
check(sr and S(S(sr).regions[2]).fromBool ~= nil, "menace secrète : couleur par SetVertexColorFromBoolean")
check(sr and S(S(sr).regions[3]).marker == nil, "marqueur secret : pas d'icône")
check(sr and getmetatable(S(fontStrings(sr)[3]).text) == SecretMT, "% secret : texte mis en forme sans calcul")
ns:Set("threatSort", "health"); M.advance(0.3)
check(#M.errors == 0, "tri par vie avec une vie secrète : aucune erreur")
ns:Set("threatSort", "danger")
sim.units.nameplate7 = nil
refresh()

section("doublons sans GUID lisible, mobs d'inconnus")
local realIsUnit = rawget(_G, "UnitIsUnit")
def("UnitIsUnit", function(x, y)
    if sim.blindIsUnit then return secret(false) end      -- jetons non comparables : réponse secrète
    return realIsUnit(x, y)
end)
def("C_NamePlate", { GetNamePlateForUnit = function(u)
    local m = sim.units[u]
    if m and m.plated then return {} end
    return nil
end })
def("UnitInParty", function(u)
    local base = u:match("^(.-)target$")
    return (base and sim.units[base] and sim.units[base].inParty) and true or false
end)
def("UnitInRaid", function() return nil end)
sim.blindIsUnit = true
local boss = mob({ name = "Gardien", guid = secret("GB"), threat = { true, 3 }, plated = true, holder = "Heros" })
local rare = mob({ name = "Sans plate", guid = secret("GR"), threat = { true, 3 }, holder = "Heros" })
local savedFocus = sim.units.focus
sim.units.nameplate8, sim.units.boss1, sim.units.target = boss, boss, boss
sim.units.boss2, sim.units.focus = rare, rare
refresh()
check(#M.errors == 0, "GUID et UnitIsUnit secrets : aucune erreur")
check(#rowsOf() == 5, "même mob par plate + boss1 + cible, et boss2 + focus sans plate : 5 lignes, pas plus (vu " .. #rowsOf() .. ")")
local flashes2, realAnim2 = 0, W.Animate
W.Animate = function(f, d, step, done) flashes2 = flashes2 + 1 return realAnim2(f, d, step, done) end
boss.threat = { false, 0 }; refresh()
check(flashes2 == 0, "clé de repli « t: » : pas d'alerte « perdu »")
W.Animate = realAnim2
sim.units.nameplate8, sim.units.boss1, sim.units.boss2 = nil, nil, nil
sim.units.target, sim.units.focus = a, savedFocus
sim.blindIsUnit = false
refresh()
check(#rowsOf() == 3, "retour à 3 lignes")

local stranger = mob({ name = "Inconnu", guid = "GZ", holder = "Passant" })          -- pas de menace (threat nil)
sim.units.nameplate9 = stranger
refresh()
check(#rowsOf() == 3, "mob d'inconnus (ni menace ni cible du groupe) : écarté")
stranger.inParty = true
refresh()
check(#rowsOf() == 4, "même mob ciblant un membre du groupe : listé")
stranger.inParty = false
sim.units.boss3 = mob({ name = "Boss muet", guid = "GB3", holder = "Passant" })
refresh()
check(#rowsOf() == 4, "jeton boss sans menace : gardé (le mob d'inconnus reste écarté)")
sim.units.nameplate9, sim.units.boss3 = nil, nil
refresh()

section("une ligne en erreur et garde-fou")
local realKind = P.ThreatKind
P.ThreatKind = function(u)
    if u == "nameplate2" then error("boum") end
    return realKind(u)
end
refresh()
check(#M.errors == 0, "erreur de ligne : rien ne remonte")
P.ThreatKind = realKind
refresh()
check(#rowsOf() == 3, "après l'erreur : les trois lignes reviennent")
P.ThreatKind = function() error("boum") end
for _ = 1, 4 do refresh() end
check(not shown(), "garde-fou déclenché : la fenêtre est cachée (pas coincée)")
P.ThreatKind = realKind
ns:Set("threatWindow", false); ns:Set("threatWindow", true); M.advance(0.5)
refresh()
check(shown() and #rowsOf() == 3, "réactivation : la fenêtre revient")

section("croix cliquée en combat")
local cross = frame().close
M.fire(cross, "OnClick")
M.advance(0.5)
check(not shown() and ns.db.threatWindow == true, "croix en combat : cachée, réglage intact")
leaveCombat(); enterCombat()
check(shown(), "prochain combat : la fenêtre revient")

section("fin de combat et groupe")
leaveCombat()
M.advance(1)
check(shown(), "1 s après la fin du combat : encore là")
M.advance(2.5)
M.advance(0.5)
check(not shown(), "3 s après : cachée (fondu terminé)")
enterCombat()
check(shown(), "nouveau combat : revient")
leaveCombat()
enterCombat()
M.advance(5)
check(shown(), "combat repris pendant la grâce : reste")
sim.group = false
M.fireEvent("GROUP_ROSTER_UPDATE"); M.advance(0.5)
check(not shown(), "seul, avec « seulement en groupe » : cachée")
ns:Set("threatGroupOnly", false); M.advance(0.5)
check(shown(), "option coupée : visible seul")
ns:Set("threatGroupOnly", true); sim.group = true
M.fireEvent("GROUP_ROSTER_UPDATE"); M.advance(0.5)
check(shown(), "retour en groupe : visible")

section("toujours visible, interrupteur")
leaveCombat(); M.advance(4)
ns:Set("threatAuto", false); M.advance(0.5)
check(shown(), "pas d'auto : visible hors combat")
ns:Set("threatWindow", false); M.advance(0.5)
check(not shown(), "fenêtre coupée : cachée")
ns:Set("threatWindow", true); ns:Set("threatAuto", true); M.advance(4)
check(not shown(), "remise en mode auto, hors combat : cachée")

section("aperçu et commande")
check(ns.db.threatLocked == true, "position verrouillée")
T:Command("test")
check(S(frame().head).drag == true, "aperçu : bandeau déplaçable même verrouillée")
check(shown() and #rowsOf() == 5, "/pp menace test : 5 lignes factices")
check(headerText() == "5 mobs · 1 perdu", "aperçu : en-tête (" .. tostring(headerText()) .. ")")
T:Command("test")
M.advance(1)
check(not shown(), "second /pp menace test : aperçu retiré")
check(S(frame().head).drag == false, "aperçu retiré : verrou rétabli")
T:Command("off")
check(ns.db.threatWindow == false, "/pp menace off")
T:Command("")
check(ns.db.threatWindow == true, "/pp menace bascule")
check(ns.db.threatLocked == true and S(frame().head).drag == false, "verrouillée : bandeau non déplaçable")
ns:Set("threatLocked", false)
check(S(frame().head).drag == true, "déverrouillée : bandeau déplaçable")
ns:Set("threatLocked", true)

section("pas d'OnUpdate permanent")
leaveCombat(); M.advance(5)
local active = 0
for _, fr in ipairs(M.allFrames) do
    if S(fr).scripts and S(fr).scripts.OnUpdate and S(fr).shown ~= false and S(fr).name ~= "PlatyplusThreat" then
        local p = S(fr).parent
        if p and S(p).name == "PlatyplusThreat" then active = active + 1 end
    end
end
check(active == 0, "hors combat : aucun OnUpdate sur les cadres de la fenêtre")
check(ns.db.threatWindow and T.events ~= nil, "module initialisé")

section("bilan"); M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
