-- Test de Resources.lib (outils partagés : garde-fou, valeurs secrètes, nombres, événements) dans le simulateur.
-- Usage : python -I dev\lua.py run dev\test_resourceslib.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
M.optional.issecretvalue = true
M.enableStrict()
local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Resources.lua", "ResourceBar.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus"); M.fireEvent("PLAYER_LOGIN"); M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(1)

local lib = ns.Resources and ns.Resources.lib
section("outils")
check(lib ~= nil, "Resources.lib présent")
check(lib.isSecret(5) == false, "un nombre ordinaire n'est pas secret")
check(lib.shortNumber(1234) == "1234" and lib.shortNumber(12345) == "12k", "shortNumber : 1234 / 12k")
check(type(lib.plainNumber(1234567)) == "string", "plainNumber renvoie un texte")
check(lib.powerName("RAGE") ~= nil, "powerName(RAGE)")
check(type(ns.ResourceBar.nineSlice) == "function" and type(ns.ResourceBar.fontString) == "function",
    "ResourceBar.nineSlice / fontString toujours exposés")

section("garde-fou")
local calls = 0
local f = lib.guard("test lib", function() calls = calls + 1; error("boum") end)
for _ = 1, 6 do f() end
check(calls == 3 and lib.isDisabled("test lib"), "coupé après 3 erreurs de suite (" .. calls .. ")")
lib.resetFailures("test lib")
check(not lib.isDisabled("test lib"), "réactivé par resetFailures")

section("barres d'action")
local got = 0
lib.subscribe(function() got = got + 1 end)
lib.setWanted("test", true)
M.advance(1)
check(got >= 1, "abonné prévenu à l'armement (" .. got .. ")")
lib.setWanted("test", false)
check(type(lib.actions()) == "table", "actions() renvoie une liste")

section("bilan"); M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
