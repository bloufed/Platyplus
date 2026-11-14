-- Test de la barre de coups blancs (ResourceBar.lua, ns.SwingBar) dans le simulateur, en mode strict.
-- Simule le minuteur natif de Forever (SwingTimerDocumentation.lua) : PLAYER_SWING(durée, type 0/1/2),
-- C_SwingTimer.IsTargetWithinSwingRange(type) -> vrai / faux / nil ; UnitAttackSpeed ; C_Spell.IsCurrentSpell (attente).
-- Usage : python -I dev\lua.py run dev\test_swing.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local function near(a, b, e) return type(a) == "number" and math.abs(a - b) < (e or 0.02) end

local W = { main = 2.6, off = nil, range = true, queued = nil }
def("UnitAttackSpeed", function() return W.main, W.off end)
def("C_SwingTimer", { IsTargetWithinSwingRange = function() return W.range end })
local NAMES = { [78] = "Frappe héroïque", [845] = "Enchaînement" }
def("C_Spell", {
    GetSpellName = function(id) return NAMES[id] end,
    IsCurrentSpell = function(name) return W.queued == name end,
})

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "ResourceBar.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.advance(0.2)
local Swing = ns.SwingBar
local root, bars = Swing:Frames()
local function value(b) return S(b).value end
local function updating() return root and S(root).scripts.OnUpdate ~= nil end
local function label() local l; for _, r in ipairs(S(root).regions) do if S(r).kind == "FontString" and S(r).fontSize == 10 then l = r end end; return l end
local function timeText() local t; for _, r in ipairs(S(root).regions) do if S(r).kind == "FontString" and S(r).fontSize == 11 then t = r end end; return t end

section("au repos")
check(ns.db.swingBar == true and root ~= nil and rawget(_G, "PlatyplusSwingBar") == root, "barre créée, active par défaut")
check(not S(root).shown and not updating(), "hors combat : cachée, aucun calcul")
check(S(root).points[1][1] == "CENTER" and S(root).points[1][5] == -275 and S(root).w == 240, "sous le personnage, 240 px")

section("combat et coups")
M.inCombat = true
M.fireEvent("PLAYER_REGEN_DISABLED")
check(S(root).shown and S(root).alpha == 1, "entrée en combat : visible")
check(tostring(S(label()).text) == "Coup blanc", "étiquette « Coup blanc »")
M.fireEvent("PLAYER_SWING", 2.6, 0)
check(updating() and value(bars[0]) == 0, "un coup part : la barre repart de zéro")
check(S(bars[0].flash).alpha > 0, "éclair au moment du coup")
M.advance(1.3)
check(near(value(bars[0]), 0.5), "à mi-chemin : moitié remplie (" .. tostring(value(bars[0])) .. ")")
check(tostring(S(timeText()).text) == "1,3", "temps restant « 1,3 » (" .. tostring(S(timeText()).text) .. ")")
check(S(bars[0].flash).alpha == 0, "l'éclair s'est éteint")
M.advance(1.5)
check(value(bars[0]) == 1 and not updating(), "coup prêt : barre pleine, plus aucun calcul")
check(not S(bars[1]).shown, "une seule arme : pas de barre de main gauche")

section("deux armes")
W.off = 1.8
M.fireEvent("UNIT_ATTACK_SPEED", "player")
M.fireEvent("PLAYER_SWING", 2.6, 0)
M.fireEvent("PLAYER_SWING", 1.8, 1)
check(S(bars[1]).shown, "main gauche : fine barre visible")
M.advance(0.9)
check(near(value(bars[1]), 0.5) and near(value(bars[0]), 0.9 / 2.6), "chaque main suit sa propre vitesse")
ns:Set("swingOffHand", false)
M.fireEvent("PLAYER_SWING", 1.8, 1)
check(not S(bars[1]).shown, "option main gauche coupée : barre cachée")
ns:Set("swingOffHand", true)

section("Frappe héroïque en attente")
M.fireEvent("PLAYER_SWING", 2.6, 0)
W.queued = "Frappe héroïque"
M.advance(0.2)
check(tostring(S(label()).text) == "Frappe héroïque", "étiquette « Frappe héroïque »")
local gold = ns.THEME.gold
check(near(S(label()).textColor[1], gold[1]) and near(S(label()).textColor[2], gold[2]), "en doré")
W.queued = nil
M.advance(0.2)
check(tostring(S(label()).text) == "Coup blanc", "retour au blanc quand elle part")

section("portée")
M.fireEvent("PLAYER_SWING", 2.6, 0)
W.range = false
M.advance(0.2)
check(near(S(root).alpha, 0.45), "cible hors de portée : barre pâlie")
W.range = nil
M.advance(0.2)
check(S(root).alpha == 1, "portée inconnue (pas de cible) : pas pâlie")
W.range = true

section("fin du combat : pouf, elle disparaît")
M.fireEvent("PLAYER_SWING", 2.6, 0)
M.advance(1)
M.inCombat = false
M.fireEvent("PLAYER_REGEN_ENABLED")
check(not S(root).shown and not updating(), "fin du combat, même en plein coup : cachée tout de suite, plus aucun calcul")
M.fireEvent("PLAYER_SWING", 2.6, 0)
check(not S(root).shown and not updating(), "un coup hors combat ne la fait pas réapparaître")
M.advance(0.5)
M.inCombat = true
M.fireEvent("PLAYER_REGEN_DISABLED")
check(S(root).shown and updating() and near(value(bars[0]), 0, 0.01), "entrée en combat juste après : le coup déjà parti est suivi")
M.advance(1.3)
check(near(value(bars[0]), 1.8 / 2.6), "il continue là où il en était (" .. tostring(value(bars[0])) .. ")")
M.inCombat = false
M.fireEvent("PLAYER_REGEN_ENABLED")
check(not S(root).shown, "et disparaît à la fin du combat")

section("aperçu, déplacement, option")
Swing:Preview(6)
check(S(root).shown and updating(), "aperçu hors combat : visible, coups simulés")
M.advance(2.7)
check(tostring(S(label()).text) == "Frappe héroïque", "aperçu : 2e coup avec Frappe héroïque en attente")
M.advance(4)
check(not S(root).shown, "aperçu fini : cachée")
ns:Set("swingLocked", false)
check(S(root).shown and S(root).mouse == true, "déverrouillée : visible et déplaçable")
ns:Set("swingLocked", true)
M.advance(1)
check(not S(root).shown and S(root).mouse == false, "verrouillée : cachée hors combat")
ns:Set("swingWidth", 320)
check(S(root).w == 320, "largeur réglable")
ns:Set("swingBar", false)
M.inCombat = true
M.fireEvent("PLAYER_REGEN_DISABLED")
M.fireEvent("PLAYER_SWING", 2.6, 0)
check(not S(root).shown and not updating(), "option coupée : rien en combat")
ns:Set("swingBar", true)
M.inCombat = false

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
