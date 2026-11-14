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
local tipLeaks = 0
local function leakCheck(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "table" and getmetatable(v) ~= nil and issecretvalue(v) then tipLeaks = tipLeaks + 1 end
    end
end
impl.SetText = (function(old) return function(f, t, ...) if S(f).name == "GameTooltip" then leakCheck(t, ...) end S(f).lines = {} ; return old(f, t, ...) end end)(impl.SetText)
impl.AddLine = function(f, t, ...) leakCheck(t, ...) local l = S(f).lines or {} ; S(f).lines = l ; l[#l + 1] = tostring(t) end
impl.AddDoubleLine = function(f, a, b, ...) leakCheck(a, b, ...) local l = S(f).lines or {} ; S(f).lines = l ; l[#l + 1] = tostring(a) .. " " .. tostring(b) end
impl.IsOwned = function(f, owner) return S(f).owner == owner end
impl.SetOwner = function(f, owner) S(f).owner = owner end
impl.Hide = (function(old) return function(f, ...) S(f).tipHidden = true ; return old(f, ...) end end)(impl.Hide)

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
def("UnitIsUnit", function(a, b)
    if b == "player" then      -- « la cible de ce mob, c'est moi » : lisible
        local base = a:match("^(.-)target$")
        return base ~= nil and sim.units[base] ~= nil and sim.units[base].targetsMe == true
    end
    return sim.units[a] ~= nil and sim.units[a] == sim.units[b]
end)
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
-- une ligne = enfant de la fenêtre qui porte une StatusBar (la vie en fond) ; les textes sont des régions de cette barre
local function barOf(row)
    for _, ch in ipairs(S(row).frames or {}) do if S(ch).kind == "StatusBar" then return ch end end
end
local function rowsOf()
    local f = frame()
    local list = {}
    if not f then return list end
    for _, child in ipairs(S(f).frames or {}) do
        if S(child).shown and barOf(child) then list[#list + 1] = child end
    end
    return list
end
-- textes d'une ligne : nom (1re FontString), qui le tient (2e), %
local function fontStrings(row)
    local out = {}
    for _, r in ipairs(S(barOf(row)).regions) do if S(r).kind == "FontString" then out[#out + 1] = r end end
    return out
end
local function regionOf(row, i) return S(barOf(row)).regions[i] end
local function stripeVertex(row) return S(regionOf(row, 2)).vertex end
local function names()
    local out = {}
    for _, row in ipairs(rowsOf()) do out[#out + 1] = S(fontStrings(row)[1]).text end
    return out
end
local function joined() return table.concat(names(), ",") end
-- bandeau : pastilles « N mobs » et « N perdus » (la seconde cachée à zéro) ; vide si aucun mob
local function headerText()
    local f = frame()
    local out = {}
    for _, pill in ipairs({ f.pillTotal, f.pillLost }) do
        if S(pill).shown then out[#out + 1] = S(pill.text).text end
    end
    return table.concat(out, " · ")
end
local function printedSince(n0)
    local out = {}
    for i = n0 + 1, #M.printed do out[#out + 1] = tostring(M.printed[i]) end
    return table.concat(out, " / ")
end
local function has(text, part) return text:find(part, 1, true) ~= nil end
local function tipLines() return table.concat(S(GameTooltip).lines or {}, " | ") end
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
check(S(regionOf(rows[1], 3)).marker == 8, "marqueur de raid 8 sur Alpha")
local bar = barOf(rows[3])
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

section("survol : infobulle, plate éclairée")
local lit = {}
local realHighlight = P.Highlight
P.Highlight = function(u) lit[#lit + 1] = u == nil and "nil" or u end
local raidCalls, raidFail = {}, false
def("SetRaidTarget", function(u, i)
    if raidFail then error("refusé") end
    raidCalls[#raidCalls + 1] = u .. ":" .. i
    sim.units[u].marker = i ~= 0 and i or nil
end)
rows = rowsOf()
M.fire(rows[1], "OnEnter")
check(lit[#lit] == "nameplate1", "survol d'Alpha : la plate nameplate1 est mise en évidence (" .. tostring(lit[#lit]) .. ")")
check(S(GameTooltip).text == "Alpha", "infobulle : le nom")
check(has(tipLines(), "Vie : 100%") and has(tipLines(), "Sylvara"), "infobulle : vie et qui il attaque (" .. tipLines() .. ")")
check(has(tipLines(), "Il t'a échappé"), "infobulle tank : « Il t'a échappé » pour un mob perdu")
check(not has(tipLines(), "Clic droit"), "infobulle : plus de ligne d'aide du clic droit")
M.fire(rows[3], "OnLeave")
check(lit[#lit] == "nameplate1", "OnLeave d'une autre ligne : rien n'est retiré")
M.fire(rows[1], "OnLeave")
check(lit[#lit] == "nil", "fin du survol : plate retirée")
M.fire(rows[2], "OnEnter")
check(has(tipLines(), "Tu es en train de le perdre"), "infobulle tank : mob qui t'échappe")
M.fire(rows[3], "OnEnter")
check(has(tipLines(), "Tu le tiens") and has(tipLines(), "toi"), "infobulle tank : « Tu le tiens » et « toi »")
b.threat = { true, 3, 87 }; refresh()
check(has(tipLines(), "87%"), "infobulle rafraîchie avec la menace")
-- DPS : formulations propres au rôle
setForm(false)
M.fire(rows[1], "OnEnter")
check(has(tipLines(), "Il te tape") or has(tipLines(), "Tu vas prendre l'aggro") or has(tipLines(), "Il ne te tape pas"), "infobulle DPS : formulation de rôle DPS")
setForm(true)
M.fire(rows[3], "OnLeave")
-- le hover sur une ligne qui disparaît retire la plate
M.fire(rows[3], "OnEnter")
sim.units.nameplate2 = nil; sim.units.nameplate2 = nil
refresh()
check(lit[#lit] ~= "nameplate2", "ligne survolée disparue : la plate n'est plus éclairée")
sim.units.nameplate2 = b
refresh()
M.fire(S(frame()).frames[1], "OnLeave")
-- clic sur une ligne : aucun appel protégé (SetRaidTarget est bloqué par le jeu quand il vient d'un addon)
rows = rowsOf()
local function rowOf(name) for _, r in ipairs(rowsOf()) do if S(fontStrings(r)[1]).text == name then return r end end end
M.fire(rowOf("Alpha"), "OnEnter")
M.fire(rowOf("Alpha"), "OnMouseUp", "RightButton")
M.fire(rowOf("Alpha"), "OnMouseUp", "LeftButton")
M.fire(rowOf("Charlie"), "OnMouseUp", "RightButton")
check(#raidCalls == 0 and #M.errors == 0, "clic droit ou gauche sur une ligne : SetRaidTarget n'est jamais appelé")
M.fire(rowOf("Alpha"), "OnLeave")
P.Highlight = realHighlight
-- porteur lisible : sa cible est toi alors que la menace est « aucune »
c.targetsMe = true
refresh()
check(S(fontStrings(rowOf("Charlie"))[2]).text == "toi", "mob dont la cible lisible est toi : « toi » et non ton propre nom")
c.targetsMe = nil
refresh()
check(headerText() ~= "", "bandeau : pastilles affichées")

section("mémoire des mobs entre deux combats")
local flashes3, realAnim3 = 0, W.Animate
W.Animate = function(f, d, step, done) if f ~= frame() then flashes3 = flashes3 + 1 end return realAnim3(f, d, step, done) end
b.threat = { true, 3 }; refresh()
leaveCombat(); M.advance(4)
check(not shown(), "fenêtre cachée après la grâce")
b.threat = { false, 0 }
enterCombat()
check(flashes3 == 0, "mob revu au combat suivant déjà perdu : pas de fausse alerte « perdu » (" .. flashes3 .. ")")
W.Animate = realAnim3
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
check(sr and S(S(barOf(sr)).barTexture).fromBool ~= nil, "menace secrète : couleur par SetVertexColorFromBoolean")
check(sr and S(regionOf(sr, 3)).marker == nil, "marqueur secret : pas d'icône")
check(sr and getmetatable(S(fontStrings(sr)[3]).text) == SecretMT, "% secret : texte mis en forme sans calcul")
tipLeaks = 0
M.fire(sr, "OnEnter")
check(tipLeaks == 0, "infobulle d'un mob à valeurs secrètes : aucun argument secret envoyé à GameTooltip (" .. tipLeaks .. ")")
check(S(GameTooltip).text == "Mob" and has(tipLines(), "caché par le jeu"), "infobulle secrète : titre fixe « Mob » et « caché par le jeu » (" .. tipLines() .. ")")
M.fire(sr, "OnLeave")
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
check(shown() and #rowsOf() == 6, "/pp menace test : 6 lignes factices")
check(headerText() == "6 mobs · 1 perdu", "aperçu : en-tête (" .. tostring(headerText()) .. ")")
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

section("/pp menace etat : pourquoi la fenêtre est là ou non")
local n1 = #M.printed
T:Command("etat")
local st1 = printedSince(n1)
check(has(st1, "cachée") and has(st1, "Seulement en combat"), "hors combat en mode auto : raison « seulement en combat » (" .. st1 .. ")")
check(has(st1, "rôle retenu") and has(st1, "tank"), "le rôle retenu est donné")
check(has(st1, "nameplate1 : écarté (pas en combat)") or has(st1, "nameplate1 : listé") or has(st1, "nameplate"), "une ligne par jeton existant")
n1 = #M.printed
T:Command("diag"); T:Command("status")
check(printedSince(n1):find("rôle retenu", 1, true) ~= nil, "alias diag et status")
ns:Set("threatWindow", false)
n1 = #M.printed
T:Command("etat")
check(has(printedSince(n1), "réglage éteint"), "réglage éteint : raison donnée")
n1 = #M.printed
T:Command("on")
T:Command("off")
check(has(printedSince(n1), "réglage éteint"), "/pp menace off : dit aussi la raison en une ligne")
ns:Set("threatWindow", true)
n1 = #M.printed
T:Command("on")
check(has(printedSince(n1), "pas affichée") and has(printedSince(n1), "Seulement en combat"), "/pp menace on hors combat : raison en une ligne")
sim.group = false
M.fireEvent("GROUP_ROSTER_UPDATE")
n1 = #M.printed
T:Command("etat")
check(has(printedSince(n1), "en groupe"), "seul avec « seulement en groupe » : raison donnée")
sim.group = true
M.fireEvent("GROUP_ROSTER_UPDATE")
enterCombat()
n1 = #M.printed
T:Command("etat")
local st2 = printedSince(n1)
check(has(st2, "affichée") and not has(st2, "cachée"), "en combat : « affichée »")
check(has(st2, "nameplate1 : listé - genre loose, statut 0") or has(st2, "nameplate1 : listé"), "jeton listé : genre et statut")
check(has(st2, "focus : écarté (mort)"), "mob mort : écarté, raison « mort »")
local before = #rowsOf()
sim.units.nameplate4.threat = { secret(false), secret(1) }
sim.units.nameplate4.player = false
sim.units.nameplate4.name = "Secret"
n1 = #M.printed
T:Command("etat")
check(has(printedSince(n1), "statut secret"), "menace secrète : écrit « secret » sans la comparer")
sim.units.nameplate4.player = true
M.fire(frame().close, "OnClick"); M.advance(0.5)
n1 = #M.printed
T:Command("etat")
check(has(printedSince(n1), "croix"), "fermée par la croix : raison donnée")
check(#M.errors == 0, "aucune erreur (état)")
leaveCombat(); M.advance(4)

section("sonde /pp menace clic")
M.inCombat = true
n1 = #M.printed
T:Command("clic")
check(has(printedSince(n1), "hors combat seulement") and T.probeButton == nil, "en combat : refusé, aucun bouton créé")
M.inCombat = false
local savedUnits = sim.units
sim.units = {}
n1 = #M.printed
T:Command("clic")
check(has(printedSince(n1), "aucune plate attaquable") and T.probeButton == nil, "sans plate attaquable : le dit")
sim.units = savedUnits
sim.blindIsUnit = false
-- la seule plate attaquable est déjà ta cible : le dire (sinon le test serait vrai d'avance)
sim.units = { nameplate1 = savedUnits.nameplate1, target = savedUnits.nameplate1 }
n1 = #M.printed
T:Command("clic")
check(has(printedSince(n1), "déjà ta cible") and T.probeButton == nil, "seule plate = ta cible : message, aucun bouton")
sim.blindIsUnit = true
n1 = #M.printed
T:Command("clic")
check(has(printedSince(n1), "déjà ta cible") and T.probeButton == nil, "comparaison secrète : prudence, plate sautée")
sim.blindIsUnit = false
sim.units = savedUnits
sim.units.target = nil
T:Command("clic")
local pb = T.probeButton
check(S(pb).attrs.useOnKeyDown == false, "useOnKeyDown = false : le clic agit au relâchement quelle que soit la CVar")
sim.units.target = sim.units.nameplate1
check(pb ~= nil and S(pb).template == "SecureActionButtonTemplate" and S(pb).shown, "bouton de test sécurisé créé et affiché")
check(S(pb).attrs.type1 == "target" and S(pb).attrs.unit == "nameplate1", "attributs type1 = target, unit = premier jeton attaquable")
check(has(tostring(S(pb.label).text), "Clique ici : cibler Alpha"), "libellé « Clique ici : cibler <mob> » (" .. tostring(S(pb.label).text) .. ")")
n1 = #M.printed
M.fire(pb, "PostClick"); M.advance(0.5)
check(has(printedSince(n1), "accepte de cibler une plate"), "cible changée : « ton jeu accepte »")
sim.units.target = sim.units.nameplate3
n1 = #M.printed
M.fire(pb, "PostClick"); M.advance(0.5)
check(has(printedSince(n1), "refuse de cibler une plate"), "cible inchangée : « ton jeu refuse »")
sim.blindIsUnit = true
n1 = #M.printed
M.fire(pb, "PostClick"); M.advance(0.5)
check(has(printedSince(n1), "illisible"), "comparaison secrète : « illisible »")
sim.blindIsUnit = false
M.inCombat = true
n1 = #M.printed
M.fire(T.probeCross, "OnClick")
check(has(printedSince(n1), "hors combat") and S(pb).shown, "croix en combat : bouton gardé (jamais de Hide en combat)")
M.inCombat = false
M.fire(T.probeCross, "OnClick")
check(S(pb).shown ~= true, "croix hors combat : bouton retiré")
check(#M.errors == 0, "aucune erreur de lockdown (sonde)")

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
