-- Scénario : ressource sur les portraits et coût des sorts (pastilles), piloté par les ÉVÉNEMENTS,
-- avec émulation des "valeurs secrètes" (sur une valeur secrète : pas de calcul, pas de comparaison ;
-- string.format puis SetText seulement)
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
impl.SetVertexColor = function(f, r, g, b, a) S(f).vertex = { r, g, b, a or 1 } end
impl.SetTextColor = function(f, r, g, b) S(f).color = { r, g, b } end

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
-- string.format accepte les secrets et renvoie un texte secret
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

---------------------------------------------------------------------------
-- Monde simulé
---------------------------------------------------------------------------
local power = { type = 1, token = "RAGE", cur = 45, max = 100, secretCur = false, secretMax = false }
local target = { exists = false, cur = 2500, max = 5000, type = 0, token = "MANA" }

def("UnitExists", function(u) return u == "player" or (u == "target" and target.exists) end)
def("UnitPowerType", function(u)
    if u == "target" then return target.type, target.token, 0, 0, 0 end
    return power.type, power.token, 0, 0, 0
end)
def("UnitPower", function(u)
    local v = (u == "target") and target.cur or power.cur
    if u ~= "target" and power.secretCur then return secret(v) end
    return v
end)
def("UnitPowerMax", function(u)
    local v = (u == "target") and target.max or power.max
    if power.secretMax then return secret(v) end
    return v
end)
def("PowerBarColor", {
    RAGE = { r = 1, g = 0, b = 0 }, MANA = { r = 0, g = 0, b = 1 }, ENERGY = { r = 1, g = 1, b = 0 },
    [0] = { r = 0, g = 0, b = 1 }, [1] = { r = 1, g = 0, b = 0 }, [3] = { r = 1, g = 1, b = 0 },
})

-- cadres d'unité Blizzard
local function unitFrame(name, containerKey, portraitKey)
    local f = CreateFrame("Frame", name, UIParent)
    local container = CreateFrame("Frame", nil, f)
    f[containerKey] = container
    container[portraitKey] = container:CreateTexture(nil, "ARTWORK")
    return f
end
def("PlayerFrame", unitFrame("PlayerFrame", "PlayerFrameContainer", "PlayerPortrait"))
def("TargetFrame", unitFrame("TargetFrame", "TargetFrameContainer", "Portrait"))

-- barres d'action : ActionButton1..5, le 3e coûte du mana, le 4e est une macro, le 5e un objet
local slots = {
    [1] = { "spell", 100 }, [2] = { "spell", 200 }, [3] = { "spell", 300 },
    [4] = { "macro", 100, "spell" }, [5] = { "item", 5000 },
}
local actionInfoCalls = 0
def("GetActionInfo", function(action)
    actionInfoCalls = actionInfoCalls + 1
    local s = slots[action]
    if s then return s[1], s[2], s[3] end
end)
local costs = {
    [100] = { { type = 1, name = "RAGE", cost = 30, minCost = 30 } },
    [200] = { { type = 1, name = "RAGE", cost = 40, minCost = 20 } },
    [300] = { { type = 0, name = "MANA", cost = 4500, minCost = 4500 } },
}
-- le jeu, lui, connaît les vraies valeurs : il dit si un sort est abordable même quand UnitPower est secret
local forced = {}   -- [action] = true : « pas assez de ressource » imposé
local function lackingFor(spellID)
    local list = costs[spellID]
    if not list then return false end
    for _, c in ipairs(list) do
        if c.type == power.type and power.cur < c.minCost then return true end
    end
    return false
end
local usableCalls = 0
local C_ActionBarImpl = {
    IsUsableAction = function(action)
        usableCalls = usableCalls + 1
        local s = slots[action]
        if not s or s[1] == "item" then return true, false end
        local lacking = forced[action] or lackingFor(s[2])
        return not lacking, lacking
    end,
}
def("C_ActionBar", C_ActionBarImpl)
local spellUsableCalls = 0
def("C_Spell", {
    GetSpellPowerCost = function(id) return costs[id] end,
    IsSpellUsable = function(id)
        spellUsableCalls = spellUsableCalls + 1
        local lacking = lackingFor(id)
        return not lacking, lacking
    end,
})
def("ActionButtonUtil", { ActionBarButtonNames = { "ActionButton", "MultiBarBottomLeftButton" } })
local btn = {}
for i = 1, 5 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.action = i
    b.TextOverlayContainer = CreateFrame("Frame", nil, b)
    btn[i] = b
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Resources.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.2)

local R = ns.Resources
local function playerText() return tostring(S(R.portraits.player.text).text) end
local function targetText() return tostring(S(R.portraits.target.text).text) end
local function pill(i) return R.pills[btn[i]] end
local function labelText(i)
    local p = pill(i)
    if not p or not S(p).shown then return nil end
    return tostring(S(p.text).text)
end
local function isRed(i)
    local c = S(pill(i).text).color
    return c and c[1] > 0.9 and c[2] < 0.5 and c[3] < 0.5
end
local function isWhite(i)
    local c = S(pill(i).text).color
    return c and c[1] == 1 and c[2] == 1 and c[3] == 1
end
local function powerEvent(unit, token) M.fireEvent("UNIT_POWER_FREQUENT", unit or "player", token or "RAGE") end
local function pollers()
    local n = 0
    for _, f in ipairs(M.allFrames) do
        if S(f).scripts.OnUpdate and M.impl.IsVisible(f) then n = n + 1 end
    end
    return n
end

section("portrait du joueur : piloté par les événements")
check(playerText() == "45", "rage 45 affichée (" .. playerText() .. ")")
check(S(R.portraits.player.host).shown, "texte visible")
local units = nil
for _, f in ipairs(M.allFrames) do
    local s = S(f)
    if s.units and s.units.UNIT_POWER_FREQUENT and s.units.UNIT_POWER_FREQUENT[1] == "player"
        and s.units.UNIT_POWER_FREQUENT[2] == nil and s.scripts.OnEvent and s.events.UNIT_MAXPOWER
        and not s.events.ACTIONBAR_SLOT_CHANGED then
        units = s.units
    end
end
check(units ~= nil, "UNIT_POWER_FREQUENT enregistré pour le joueur seul (RegisterUnitEvent)")
check(pollers() == 0, "aucune boucle OnUpdate active (pas de scrutation)")
power.cur = 60; M.advance(1)
check(playerText() == "45", "sans événement, rien ne bouge (" .. playerText() .. ")")
powerEvent()
check(playerText() == "60", "UNIT_POWER_FREQUENT : mise à jour immédiate (" .. playerText() .. ")")
power.cur = 70; powerEvent("player", "COMBO_POINTS")
check(playerText() == "60", "événement d'une autre ressource ignoré (" .. playerText() .. ")")
powerEvent("party1", "RAGE")
check(playerText() == "60", "événement d'une autre unité ignoré")
powerEvent()
check(playerText() == "70", "puis bonne ressource (" .. playerText() .. ")")
power.cur = 45; powerEvent()
ns:Set("powerFormat", "curmax")
check(playerText() == "45 / 100", "format valeur / maximum (" .. playerText() .. ")")
power.cur, power.max = 12345, 25000; M.fireEvent("UNIT_MAXPOWER", "player", "RAGE")
check(playerText() == "12,345 / 25,000", "séparateurs de milliers (" .. playerText() .. ")")
power.cur, power.max = 45, 100; M.fireEvent("UNIT_MAXPOWER", "player", "RAGE")
local c = S(R.portraits.player.text).color
check(c and c[1] == 1 and c[2] < 0.5, "chiffre à la couleur de la rage, éclaircie")
check(S(R.portraits.player.shade).texture ~= nil, "voile sombre derrière le chiffre")

section("portrait du joueur : valeurs secrètes (en combat)")
power.secretCur = true; powerEvent()
check(playerText() == "45 / 100", "valeur secrète affichée sans calcul (" .. playerText() .. ")")
check(isSecretObj(S(R.portraits.player.text).text), "le texte affiché est bien la chaîne secrète")
power.secretMax = true; M.fireEvent("UNIT_MAXPOWER", "player", "RAGE")
check(playerText() == "45 / 100", "valeur et maximum secrets (" .. playerText() .. ")")
ns:Set("powerFormat", "cur")
check(playerText() == "45", "format simple en secret (" .. playerText() .. ")")
power.secretCur, power.secretMax = false, false; powerEvent()
check(playerText() == "45", "retour aux valeurs ordinaires")

section("position, taille, cible")
for _, pos in ipairs({ "TOP", "CENTER", "BOTTOM" }) do ns:Set("powerPos", pos) end
ns:Set("powerSize", 20)
target.exists = true
ns:Set("powerTarget", true)
check(targetText() == "2,500", "ressource de la cible (" .. targetText() .. ")")
target.cur = 1000; powerEvent("target", "MANA")
check(targetText() == "1,000", "la cible suit ses propres événements (" .. targetText() .. ")")
target.exists = false; M.fireEvent("PLAYER_TARGET_CHANGED")
check(not S(R.portraits.target.host).shown, "texte de la cible caché sans cible")
target.exists = true; M.fireEvent("PLAYER_TARGET_CHANGED")
check(S(R.portraits.target.host).shown, "nouvelle cible : texte de retour")
ns:Set("powerTarget", false)
check(not S(R.portraits.target.host).shown, "option coupée : texte de la cible caché")

section("coût des sorts : pastilles")
check(labelText(1) == "30", "sort à 30 de rage (" .. tostring(labelText(1)) .. ")")
check(labelText(2) == "20+", "coût minimal 20 avec part optionnelle (" .. tostring(labelText(2)) .. ")")
check(labelText(3) == nil, "coût en mana masqué par défaut")
check(labelText(4) == "30", "macro lançant un sort (" .. tostring(labelText(4)) .. ")")
check(labelText(5) == nil, "objet : pas de coût")
local p1 = S(pill(1))
check(p1.h == 16 and p1.w >= p1.h, "pastille au moins ronde (" .. p1.w .. "x" .. p1.h .. ")")
local body = S(pill(1).body[2]).vertex
check(body and body[1] > 0.4 and body[2] < 0.1 and body[3] < 0.1, "fond de la pastille à la couleur de la rage")
check(S(pill(1).body[1]).texture and S(pill(1).body[1]).texture:find("Circle", 1, true), "bouts ronds (Media\\Circle)")
check(isWhite(1) and isWhite(2), "chiffre blanc quand le sort est abordable")
check(S(pill(1)).parent == btn[1].TextOverlayContainer, "pastille posée au-dessus du cooldown (TextOverlayContainer)")
ns:Set("spellCostMana", true)
check(labelText(3) == "4500", "coût en mana affiché sur demande (" .. tostring(labelText(3)) .. ")")
local body3 = S(pill(3).body[2]).vertex
check(body3 and body3[3] > 0.4 and body3[1] < 0.1, "pastille de mana bleue")
ns:Set("spellCostMana", false)
check(labelText(3) == nil, "coût en mana de nouveau masqué")
for _, pos in ipairs({ "TOPLEFT", "BOTTOMLEFT", "TOP", "CENTER" }) do ns:Set("spellCostPos", pos) end
ns:Set("spellCostSize", 16)
check(labelText(1) == "30", "coût conservé après changement de position et de taille")
check(S(pill(1)).h == 21, "pastille agrandie avec le texte (" .. S(pill(1)).h .. ")")
ns:Set("spellCostSize", 11)

section("pastille ROUGE quand le sort n'est pas abordable")
power.cur = 25; powerEvent()
check(isWhite(1), "pas encore relu : rafale regroupée (0,05 s)")
M.advance(0.1)
check(isRed(1), "30 de rage avec 25 : pastille rouge")
check(isWhite(2), "coût minimal 20 avec 25 : pastille normale")
check(isRed(4), "la macro suit le même sort")
local edge = S(pill(1).edge[1]).vertex
check(edge and edge[1] > 0.9 and edge[2] < 0.5, "liseré rouge")
power.cur = 10; powerEvent(); M.advance(0.1)
check(isRed(1) and isRed(2), "10 de rage : les deux sorts en rouge")
power.cur = 45; powerEvent(); M.advance(0.1)
check(isWhite(1) and isWhite(2), "45 de rage : tout redevient normal")
forced[2] = true; M.fireEvent("ACTION_USABLE_CHANGED", {}); M.advance(0.1)
check(isRed(2) and isWhite(1), "ACTION_USABLE_CHANGED relu (champs non lus, on réinterroge)")
forced[2] = nil; M.fireEvent("SPELL_UPDATE_USABLE"); M.advance(0.1)
check(isWhite(2), "SPELL_UPDATE_USABLE relu")
local before = usableCalls
for _ = 1, 10 do powerEvent(); M.fireEvent("ACTIONBAR_UPDATE_USABLE") end
M.advance(0.1)
check(usableCalls - before <= 4, "rafale de 20 événements = une seule relecture (" .. (usableCalls - before) .. " appels)")

section("valeurs secrètes : rouge quand même, sans comparer")
power.secretCur = true; power.cur = 25; powerEvent(); M.advance(0.1)
check(isRed(1) and isWhite(2), "en secret, IsUsableAction dit qui est abordable")
power.cur = 45; powerEvent(); M.advance(0.1)
check(isWhite(1), "en secret, retour à la normale")
def("C_ActionBar", {})
power.cur = 25; powerEvent(); M.advance(0.1)
check(isRed(1) and spellUsableCalls > 0, "sans C_ActionBar.IsUsableAction : repli sur C_Spell.IsSpellUsable")
def("C_Spell", { GetSpellPowerCost = function(id) return costs[id] end })
power.cur = 25; powerEvent(); M.advance(0.1)
check(isWhite(1), "sans aucune API et valeur secrète : on ne sait pas, donc pas de rouge (et aucune comparaison)")
power.secretCur = false; power.cur = 25; powerEvent(); M.advance(0.1)
check(isRed(1), "sans API, valeur ordinaire : comparaison de dernier recours")
power.cur = 45; powerEvent()
def("C_ActionBar", C_ActionBarImpl)
def("C_Spell", { GetSpellPowerCost = function(id) return costs[id] end, IsSpellUsable = function() return true, false end })
M.advance(0.1)

section("barres d'action : relues sur événement, rafales regroupées")
slots[1] = { "spell", 400 }
check(labelText(1) == "30", "pas d'événement : rien ne change encore")
before = actionInfoCalls
for i = 1, 12 do M.fireEvent("ACTIONBAR_SLOT_CHANGED", i) end
M.fireEvent("UPDATE_SHAPESHIFT_FORM")
M.advance(0.1)
check(labelText(1) == nil, "coût retiré quand le bouton change de sort")
check(actionInfoCalls - before <= 10, "13 événements = une seule relecture des barres (" .. (actionInfoCalls - before) .. " appels)")
slots[1] = { "spell", 100 }; M.fireEvent("ACTIONBAR_SLOT_CHANGED", 1); M.advance(0.1)
check(labelText(1) == "30", "coût de retour")
costs[100] = { { type = 1, name = "RAGE", cost = 25, minCost = 25 } }
M.advance(5.2)
check(labelText(1) == "25", "filet très lent (5 s) : coût changé sans événement relu (" .. tostring(labelText(1)) .. ")")
costs[100] = { { type = 1, name = "RAGE", cost = 30, minCost = 30 } }
R:Refresh()
check(labelText(1) == "30", "Refresh relit tout de suite")
check(pollers() == 0, "toujours aucune boucle OnUpdate active")

section("désactivation")
ns:Set("powerPlayer", false)
check(not S(R.portraits.player.host).shown, "portrait caché quand l'option est coupée")
power.cur = 50; powerEvent()
check(not S(R.portraits.player.host).shown, "et il le reste malgré les événements")
ns:Set("spellCost", false)
check(labelText(1) == nil and labelText(2) == nil, "coûts cachés quand l'option est coupée")
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 1); M.advance(0.1)
check(labelText(1) == nil, "et ils le restent malgré les événements")
ns:Set("powerPlayer", true); ns:Set("spellCost", true)
check(labelText(1) == "30", "coûts de retour quand on réactive")
check(playerText() == "50", "portrait de retour avec la bonne valeur (" .. playerText() .. ")")

section("garde-fou : la fonction se coupe seule après des erreurs répétées")
def("GetActionInfo", function() error("boom") end)
for i = 1, 4 do M.fireEvent("ACTIONBAR_SLOT_CHANGED", i); M.advance(0.1) end
local cut = 0
for _, line in ipairs(M.printed) do if line:find("coupé après des erreurs", 1, true) then cut = cut + 1 end end
check(cut == 1, "message affiché une fois, sans erreur Lua pour le joueur (" .. cut .. ")")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
