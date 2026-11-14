-- Test : barre de ressource (ResourceBar.lua) dans le simulateur strict
-- barre, chiffre en clair et en secret, repères, icônes allumées / grisées, combat seulement, déplacement,
-- aperçu, réglages, changement de ressource, absence de scrutation, garde-fou
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
-- Méthodes réelles de WoW absentes du simulateur (ou muettes) : ajoutées ici, pour ce test seulement
---------------------------------------------------------------------------
local impl, S = M.impl, M.state
impl.RegisterUnitEvent = function(f, event, ...)   -- Frame:RegisterUnitEvent(event, unit1[, unit2])
    local s = S(f)
    s.events[event] = true
    s.units = s.units or {}
    s.units[event] = { ... }
end
impl.GetStatusBarTexture = function(f)             -- StatusBar:GetStatusBarTexture()
    local s = S(f)
    if not s.barTexture then s.barTexture = impl.CreateTexture(f) end
    return s.barTexture
end
impl.SetStatusBarTexture = function(f, file) S(f).barFile = file end
impl.SetStatusBarColor = function(f, r, g, b) S(f).barColor = { r, g, b } end
impl.SetVertexColor = function(f, r, g, b, a) S(f).vertex = { r, g, b, a or 1 } end
impl.SetTextColor = function(f, r, g, b) S(f).color = { r, g, b } end
impl.SetDesaturated = function(f, v) S(f).desat = v and true or false end
impl.GetCenter = function(f)                       -- centre propre à chaque cadre (déplacement)
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
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__lt", "__le", "__len", "__call" }) do
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
-- StatusBar:SetValue / SetMinMaxValues acceptent les valeurs secrètes dans le jeu : le simulateur les range telles quelles
local realSetValue = impl.SetValue
impl.SetValue = function(f, v)
    local s = S(f)
    if isSecretObj(v) or isSecretObj(s.max) or isSecretObj(s.min) then s.value = v return end
    return realSetValue(f, v)
end

---------------------------------------------------------------------------
-- Monde simulé : un guerrier
---------------------------------------------------------------------------
local power = { type = 1, token = "RAGE", cur = 45, max = 100, secretCur = false, secretMax = false }
def("UnitExists", function(u) return u == "player" end)
def("UnitPowerType", function() return power.type, power.token, 0, 0, 0 end)
def("UnitPower", function(u)
    if power.secretCur then return secret(power.cur) end
    return power.cur
end)
def("UnitPowerMax", function(u)
    if power.secretMax then return secret(power.max) end
    return power.max
end)
def("PowerBarColor", {
    RAGE = { r = 1, g = 0, b = 0 }, MANA = { r = 0, g = 0, b = 1 }, ENERGY = { r = 1, g = 1, b = 0 },
    [0] = { r = 0, g = 0, b = 1 }, [1] = { r = 1, g = 0, b = 0 }, [3] = { r = 1, g = 1, b = 0 },
})

local slots = {
    [1] = { "spell", 100 },             -- Frappe héroïque, 15 rage
    [2] = { "spell", 200 },             -- Pourfendre, 10 rage
    [3] = { "spell", 300 },             -- Frappe mortelle, 30 rage
    [4] = { "spell", 400 },             -- Exécution, 15 rage (même coût que la Frappe héroïque)
    [5] = { "spell", 500 },             -- Tourbillon, 25 rage
    [6] = { "spell", 600 },             -- sort de mana
    [7] = { "spell", 700 },             -- Charge : aucun coût
    [8] = { "macro", 300, "spell" },    -- macro qui lance la Frappe mortelle (doublon)
    [9] = { "item", 5000 },
    [10] = { "spell", 800 },            -- sort d'énergie (forme de félin)
}
def("GetActionInfo", function(action)
    local s = slots[action]
    if s then return s[1], s[2], s[3] end
end)
local costs = {
    [100] = { { type = 1, name = "RAGE", cost = 15, minCost = 15 } },
    [200] = { { type = 1, name = "RAGE", cost = 10, minCost = 10 } },
    [300] = { { type = 1, name = "RAGE", cost = 30, minCost = 30 } },
    [400] = { { type = 1, name = "RAGE", cost = 15, minCost = 15 } },
    [500] = { { type = 1, name = "RAGE", cost = 25, minCost = 25 } },
    [600] = { { type = 0, name = "MANA", cost = 50, minCost = 50 } },
    [700] = {},
    [800] = { { type = 3, name = "ENERGY", cost = 40, minCost = 40 } },
}
local blocked = {}   -- [action] = true : sort inutilisable pour une autre raison (posture, cible...)
local function spellOfSlot(action)
    local s = slots[action]
    if s and (s[1] == "spell" or (s[1] == "macro" and s[3] == "spell")) then return s[2] end
end
local function lackingFor(spellID)
    for _, c in ipairs(costs[spellID] or {}) do
        if c.type == power.type and power.cur < c.minCost then return true end
    end
    return false
end
-- le jeu connaît les vraies valeurs : il répond même quand UnitPower est secret
def("C_ActionBar", {
    IsUsableAction = function(action)
        local id = spellOfSlot(action)
        if not id then return true, false end
        local lacking = lackingFor(id)
        return (not lacking) and not blocked[action], lacking
    end,
})
def("C_Spell", {
    GetSpellPowerCost = function(id) return costs[id] end,
    GetSpellTexture = function(id) return 10000 + id end,
    IsSpellUsable = function(id) local l = lackingFor(id); return not l, l end,
})
def("ActionButtonUtil", { ActionBarButtonNames = { "ActionButton" } })
for i = 1, 10 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.action = i
    b.TextOverlayContainer = CreateFrame("Frame", nil, b)
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Resources.lua", "ResourceBar.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.5)

local RB = ns.ResourceBar
local F = RB.frames or {}
local T = ns.THEME
local function strip(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function valueText() return strip(S(F.value).text) end
local function shownIcons()
    local list = {}
    for _, f in ipairs(RB.icons) do if S(f).shown then list[#list + 1] = f end end
    return list
end
local function usedMarkers()
    local list = {}
    for _, m in ipairs(RB.markers) do if m.used and S(m.line).shown then list[#list + 1] = m end end
    return list
end
local function markerX(m) return S(m.shade).points[1][4] end
local function pollers()
    local n = 0
    for _, f in ipairs(M.allFrames) do
        if S(f).scripts.OnUpdate and impl.IsVisible(f) then n = n + 1 end
    end
    return n
end
local function powerEvent(token) M.fireEvent("UNIT_POWER_FREQUENT", "player", token or power.token) end
local function same(c, ref) return c and math.abs(c[1] - ref[1]) < 1e-6 and math.abs(c[2] - ref[2]) < 1e-6 and math.abs(c[3] - ref[3]) < 1e-6 end
local LACK = { 1.00, 0.30, 0.30 }
local function printedCount(text)
    local n = 0
    for _, line in ipairs(M.printed) do if line:find(text, 1, true) then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
section("affichage de base")
check(F.root ~= nil and rawget(_G, "PlatyplusResourceBar") == F.root, "cadre PlatyplusResourceBar créé")
check(ns.db.hud == false and not S(F.root).shown, "coupée par défaut (le coût sur les sorts suffit au joueur)")
ns:Set("hud", true)          -- un joueur qui la veut l'allume dans les options
M.advance(0.5)
check(S(F.root).shown and S(F.root).alpha == 1, "allumée : visible hors combat, fondu terminé")
local p = S(F.root).points[1]
check(p and p[1] == "CENTER" and p[2] == UIParent and p[3] == "CENTER" and p[4] == 0 and p[5] == -170,
    "position depuis le centre de l'écran (0, -170)")
check(S(F.root).w == 240 and S(F.root).h == 22 and S(F.root).scale == 1, "largeur 240, échelle 1")
check(valueText() == "45 / 100", "chiffre « 45 / 100 » au centre (" .. valueText() .. ")")
check(tostring(S(F.value).text):find("|c", 1, true) ~= nil, "« / 100 » atténué (code couleur)")
check(S(F.name).text == "Rage", "nom de la ressource à gauche (" .. tostring(S(F.name).text) .. ")")
local nc = S(F.name).color
-- le nom est écrit en blanc à contour : la version teintée (rouge éclairci) était illisible sur le remplissage rouge
check(nc and nc[1] == T.text[1] and nc[2] == T.text[2] and nc[3] == T.text[3], "nom en blanc, lisible sur le remplissage")
check(S(F.fill).min == 0 and S(F.fill).max == 100 and S(F.fill).value == 45, "remplissage 45 sur 100 (sans animation au premier affichage)")
check(tostring(S(F.fill).barFile):find("Media\\Bar", 1, true) ~= nil, "texture Media\\Bar")
local bc = S(F.fill).barColor
check(bc and bc[1] == 1 and bc[2] < 0.2, "remplissage rouge (PowerBarColor.RAGE)")
check(F.spark and S(F.spark).shown and S(F.spark).points[1][2] == S(F.fill).barTexture, "halo au bout, ancré sur la texture de la barre")
check(S(F.events).units and S(F.events).units.UNIT_POWER_FREQUENT and S(F.events).units.UNIT_POWER_FREQUENT[1] == "player",
    "UNIT_POWER_FREQUENT enregistré pour le joueur seul (RegisterUnitEvent)")
check(pollers() == 0, "aucune boucle OnUpdate active au repos")

---------------------------------------------------------------------------
section("événements de ressource et animation")
power.cur = 80; M.advance(1)
check(valueText() == "45 / 100", "sans événement, rien ne bouge (pas de scrutation)")
powerEvent()
check(valueText() == "80 / 100", "UNIT_POWER_FREQUENT : chiffre à jour tout de suite (" .. valueText() .. ")")
check(S(F.driver).shown, "animation de remplissage lancée")
M.advance(0.05)
local v = S(F.fill).value
check(v > 45 and v < 80, "remplissage en cours (" .. tostring(v) .. ")")
M.advance(0.5)
check(S(F.fill).value == 80 and not S(F.driver).shown, "remplissage arrivé, animation arrêtée")
power.cur = 90
M.fireEvent("UNIT_POWER_FREQUENT", "target", "RAGE")
check(valueText() == "80 / 100", "événement d'une autre unité ignoré")
powerEvent("COMBO_POINTS")
check(valueText() == "80 / 100", "événement d'une autre ressource ignoré")
power.cur = 100; powerEvent(); M.advance(0.5)
check(not S(F.spark).shown, "pas de halo quand la barre est pleine")
power.cur = 0; powerEvent(); M.advance(0.5)
check(not S(F.spark).shown, "pas de halo quand elle est vide")
power.cur = 45; powerEvent(); M.advance(0.5)
check(S(F.spark).shown and S(F.fill).value == 45, "halo de retour à 45")
power.max = 120; M.fireEvent("UNIT_MAXPOWER", "player", "RAGE")
check(valueText() == "45 / 120" and S(F.fill).max == 120, "UNIT_MAXPOWER : nouveau maximum (" .. valueText() .. ")")
power.max = 100; M.fireEvent("UNIT_MAXPOWER", "player", "RAGE"); M.advance(0.3)

---------------------------------------------------------------------------
section("repères des coûts")
local ms = usedMarkers()
check(#ms == 4, "4 repères : 10, 15, 25, 30 (deux sorts à 15 = un seul repère) (" .. #ms .. ")")
local xs = {}
for i, m in ipairs(ms) do xs[i] = markerX(m) end
check(xs[1] == 23 and xs[2] == 35 and xs[3] == 59 and xs[4] == 70, "position = coût / max x largeur utile (" .. table.concat(xs, ",") .. ")")
check(S(ms[1].shade).points[1][2] == F.top, "repères posés sur le calque du dessus")
check(ms[2].spell.spellID == 100 and S(ms[2].icon).texture == 10100, "à coût égal, l'icône du premier sort des barres (Frappe héroïque)")
check(ms[1].lane == 0 and ms[2].lane == 1 and ms[3].lane == 0 and ms[4].lane == 1, "mini-icônes trop proches : sur deux étages")
check(S(ms[2].back).points[1][5] > S(ms[1].back).points[1][5], "le 2e étage est plus haut")
local allLit = true
for _, m in ipairs(ms) do if S(m.line).alpha < 0.9 or S(m.icon).desat then allLit = false end end
check(allLit, "45 de rage : tous les repères allumés")

---------------------------------------------------------------------------
section("icônes des sorts")
local ic = shownIcons()
local tex, txt = {}, {}
for i, f in ipairs(ic) do tex[i] = S(f.icon).texture - 10000; txt[i] = tostring(S(f.cost).text) end
check(#ic == 5, "5 sorts de rage (doublon de macro, mana, Charge et énergie exclus) (" .. #ic .. ")")
check(table.concat(tex, ",") == "200,100,400,500,300", "triés par coût (" .. table.concat(tex, ",") .. ")")
check(table.concat(txt, ",") == "10,15,15,25,30", "coût sous chaque icône (" .. table.concat(txt, ",") .. ")")
check(S(ic[2]).points[1][4] == 34 and S(F.row).w == 5 * 28 + 4 * 6, "alignées sous la barre")
local lit = true
for _, f in ipairs(ic) do
    if S(f.icon).desat or not S(f.glow).shown or not same(S(f.cost).color, T.text) then lit = false end
end
check(lit, "45 de rage : toutes allumées, halo accent")
power.cur = 20; powerEvent()
M.advance(0.1)
check(S(ic[4].icon).desat and S(ic[5].icon).desat, "25 et 30 avec 20 de rage : grisées")
check(same(S(ic[4].cost).color, LACK) and same(S(ic[5].cost).color, LACK), "et leur coût en rouge")
check(not S(ic[4].glow).shown, "sans halo")
check(not S(ic[1].icon).desat and not S(ic[3].icon).desat, "10 et 15 restent allumées")
ms = usedMarkers()
check(S(ms[3].line).alpha < 0.5 and S(ms[3].icon).desat and S(ms[2].line).alpha > 0.9, "repères 25 et 30 éteints, 15 allumé")
blocked[4] = true; M.fireEvent("ACTION_USABLE_CHANGED", {}); M.advance(0.1)
check(S(ic[3].icon).desat and same(S(ic[3].cost).color, T.dim), "Exécution inutilisable (cible) : grisée, coût neutre (pas rouge)")
check(not S(ms[2].icon).desat, "son repère reste allumé : la rage suffit")
blocked[4] = nil; power.cur = 45; powerEvent(); M.advance(0.1)
check(not S(ic[3].icon).desat and not S(ic[5].icon).desat, "tout se rallume à 45")

---------------------------------------------------------------------------
section("valeurs secrètes")
power.secretCur = true; power.cur = 35; powerEvent()
check(valueText() == "35 / 100", "chiffre secret affiché sans calcul (" .. valueText() .. ")")
check(isSecretObj(S(F.value).text) and isSecretObj(S(F.fill).value), "texte et remplissage reçoivent la valeur secrète")
check(not S(F.driver).shown, "pas d'animation sur une valeur secrète")
check(S(F.spark).shown, "halo toujours là (ancrage, aucun calcul)")
check(#usedMarkers() == 4, "maximum lisible : repères conservés")
M.advance(0.1)
check(not S(shownIcons()[5].icon).desat, "30 avec 35 (secret) : allumée grâce à IsUsableAction")
power.cur = 20; powerEvent(); M.advance(0.1)
check(S(shownIcons()[5].icon).desat and same(S(shownIcons()[5].cost).color, LACK), "20 (secret) : grisée et rouge, sans comparer")
power.secretMax = true; M.fireEvent("UNIT_MAXPOWER", "player", "RAGE")
check(#usedMarkers() == 0, "maximum secret : repères cachés")
check(isSecretObj(S(F.fill).max) and valueText() == "20 / 100", "maximum secret passé tel quel à la barre")
power.secretCur, power.secretMax, power.cur = false, false, 50
M.fireEvent("UNIT_MAXPOWER", "player", "RAGE")
check(valueText() == "50 / 100" and S(F.fill).value == 50 and #usedMarkers() == 4, "retour aux valeurs ordinaires : direct, repères revenus")
check(#M.errors == 0, "aucune opération interdite sur une valeur secrète")
M.advance(0.3)

---------------------------------------------------------------------------
section("combat seulement")
ns:Set("hudCombatOnly", true)
check(S(F.root).shown, "rage 50 hors combat : pas au repos, barre visible")
power.cur = 0; powerEvent(); M.advance(0.1)
check(S(F.root).shown and S(F.root).alpha < 1, "rage 0 : fondu de sortie en cours")
M.advance(1)
check(not S(F.root).shown and pollers() == 0, "puis cachée, plus aucune boucle")
M.inCombat = true; M.fireEvent("PLAYER_REGEN_DISABLED")
check(S(F.root).shown and S(F.root).alpha == 0, "entrée en combat : apparaît (alpha 0 au départ)")
M.advance(0.1)
local a = S(F.root).alpha
check(a > 0 and a < 1, "fondu doux d'apparition (" .. tostring(a) .. ")")
M.advance(0.5)
check(S(F.root).alpha == 1, "fondu terminé")
power.cur = 30; powerEvent()
M.inCombat = false; M.fireEvent("PLAYER_REGEN_ENABLED"); M.advance(1)
check(S(F.root).shown, "fin du combat avec 30 de rage : reste visible tant que la rage n'est pas retombée")
power.cur = 0; powerEvent(); M.advance(1)
check(not S(F.root).shown, "rage retombée à 0 : cachée")

---------------------------------------------------------------------------
section("déplacement")
RB:ToggleMove()
check(ns.db.hudLocked == false and S(F.mover).shown, "déverrouillée : cadre « glisse-moi » visible")
M.advance(0.5)
check(S(F.root).shown and S(F.root).alpha == 1, "barre visible pendant le déplacement, même hors combat")
check(printedCount("glisse-la") == 1, "message d'aide affiché")
S(F.root).center = { 783, 284 }
M.fire(F.mover, "OnDragStart")
M.fire(F.mover, "OnDragStop")
check(ns.db.hudX == 100 and ns.db.hudY == -100, "position enregistrée depuis le centre (" .. tostring(ns.db.hudX) .. ", " .. tostring(ns.db.hudY) .. ")")
p = S(F.root).points[1]
check(p[1] == "CENTER" and p[4] == 100 and p[5] == -100, "barre réancrée au centre + décalage")
S(F.root).center = nil
M.fire(F.mover, "OnMouseUp", "RightButton")
check(ns.db.hudLocked == true and not S(F.mover).shown, "clic droit : verrouillée")
M.advance(1)
check(not S(F.root).shown, "hors combat et au repos : de nouveau cachée")
RB:ResetPosition()
p = S(F.root).points[1]
check(ns.db.hudX == 0 and ns.db.hudY == -170 and p[4] == 0 and p[5] == -170, "ResetPosition : position par défaut")
ns:Set("hudScale", 1.5)
check(S(F.root).scale == 1.5, "échelle appliquée")
ns:Set("hudScale", 1)
ns:Set("hudX", 40); ns:Set("hudY", -200)
p = S(F.root).points[1]
check(p[4] == 40 and p[5] == -200, "hudX / hudY réglés à la main")
RB:ResetPosition()

---------------------------------------------------------------------------
section("aperçu")
RB:Preview()
check(S(F.root).shown, "Preview : visible hors combat")
M.advance(3)
check(S(F.root).shown and S(F.root).alpha == 1, "toujours là après 3 s")
M.advance(4)
check(not S(F.root).shown, "disparaît après l'aperçu")
ns:Set("hud", false)
check(not S(F.events).events.UNIT_POWER_FREQUENT, "barre coupée : plus aucun événement de ressource écouté")
RB:Preview(2)
check(S(F.root).shown and S(F.events).events.UNIT_POWER_FREQUENT, "Preview même désactivée : visible et à jour")
M.advance(3)
check(not S(F.root).shown and not S(F.events).events.UNIT_POWER_FREQUENT, "fin de l'aperçu : cachée et silencieuse")
ns:Set("hud", true)
ns:Set("hudCombatOnly", false)
M.advance(0.5)
check(S(F.root).shown and S(F.root).alpha == 1, "réactivée, toujours visible")
power.cur = 45; powerEvent(); M.advance(0.5)

---------------------------------------------------------------------------
section("réglages")
ns:Set("hudWidth", 300)
check(S(F.root).w == 300 and markerX(usedMarkers()[1]) == 29, "largeur 300 : repères recalculés (" .. markerX(usedMarkers()[1]) .. ")")
ns:Set("hudWidth", 240)
ns:Set("hudSpellCount", 2)
check(#shownIcons() == 2, "hudSpellCount 2 : deux icônes (" .. #shownIcons() .. ")")
ns:Set("hudSpellCount", 0)
check(#shownIcons() == 0 and not S(F.row).shown, "hudSpellCount 0 : rangée cachée")
ns:Set("hudSpellCount", 6)
ns:Set("hudSpells", false)
check(#shownIcons() == 0 and not S(F.row).shown and #usedMarkers() == 4, "hudSpells coupé : icônes cachées, repères gardés")
ns:Set("hudMarkers", false)
check(#usedMarkers() == 0, "hudMarkers coupé : repères cachés")
ns:Set("hudSpells", true); ns:Set("hudMarkers", true)
check(#shownIcons() == 5 and #usedMarkers() == 4, "tout revient")
ns:Set("hudLocked", false)
check(S(F.mover).shown, "hudLocked = false : cadre de déplacement")
ns:Set("hudLocked", true)
check(not S(F.mover).shown, "hudLocked = true : verrouillée")

---------------------------------------------------------------------------
section("barres d'action modifiées")
slots[2] = nil
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 2)
check(#shownIcons() == 5, "rafale regroupée : pas encore relu")
M.advance(0.1)
check(#shownIcons() == 4 and S(shownIcons()[1].icon).texture == 10100, "Pourfendre retiré de la barre : icône partie")
check(#usedMarkers() == 3, "et son repère aussi")
slots[2] = { "spell", 200 }
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 2); M.advance(0.1)
check(#shownIcons() == 5, "remis : de retour")

---------------------------------------------------------------------------
section("changement de ressource (forme de félin)")
power.type, power.token, power.cur, power.max = 3, "ENERGY", 60, 100
M.fireEvent("UNIT_DISPLAYPOWER", "player")
check(S(F.name).text == "Énergie" and valueText() == "60 / 100", "nom et chiffre de l'énergie (" .. tostring(S(F.name).text) .. ", " .. valueText() .. ")")
bc = S(F.fill).barColor
check(bc and bc[1] > 0.9 and bc[2] > 0.9 and bc[3] < 0.2, "remplissage jaune")
check(#shownIcons() == 1 and S(shownIcons()[1].icon).texture == 10800, "seul le sort d'énergie est listé")
ms = usedMarkers()
check(#ms == 1 and markerX(ms[1]) == 94, "repère à 40 / 100 (" .. tostring(ms[1] and markerX(ms[1])) .. ")")
power.cur = 70; powerEvent("RAGE")
check(valueText() == "60 / 100", "un événement de rage est ignoré en félin")
ns:Set("hudCombatOnly", true)
power.cur = 100; powerEvent(); M.advance(1)
check(not S(F.root).shown, "énergie pleine hors combat : au repos, cachée")
power.cur = 60; powerEvent(); M.advance(0.5)
check(S(F.root).shown, "énergie dépensée : visible")
ns:Set("hudCombatOnly", false)
power.type, power.token, power.cur, power.max = 1, "RAGE", 45, 100
M.fireEvent("UNIT_DISPLAYPOWER", "player"); M.advance(0.5)
check(S(F.name).text == "Rage" and #shownIcons() == 5 and #usedMarkers() == 4, "retour à la rage")

---------------------------------------------------------------------------
section("sans scrutation")
M.advance(6)
check(pollers() == 0, "au repos, aucune boucle OnUpdate (la seule tourne pendant une animation)")
power.cur = 70; powerEvent()
check(pollers() == 1, "une animation : une boucle")
M.advance(0.5)
check(pollers() == 0, "animation finie : plus de boucle")

---------------------------------------------------------------------------
section("garde-fou")
def("UnitPower", function() error("boom") end)
for _ = 1, 4 do powerEvent(); M.advance(0.1) end
check(printedCount("« barre de ressource » coupé") == 1, "coupée après 3 erreurs, message une seule fois, aucune erreur Lua")

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
