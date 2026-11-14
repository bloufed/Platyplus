-- Test de la traduction (Locale.lua, Locales\*.lua, ns.T / ns.Tf / ns:SetupLocale, commande /pp langue).
-- Échoue sur des marqueurs incohérents (%d, %s, codes couleur, retours) entre une clé et sa traduction ;
-- ne se plaint PAS d'une couverture incomplète (voir `python -I dev\i18n.py verifier` pour la couverture).
-- Usage : python -I dev\lua.py run dev\test_i18n.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()
M.optional.GetLocale = true

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

local SECRET = "texte secret"
def("issecretvalue", function(v) return v == SECRET end)
local clientLocale = "frFR"
def("GetLocale", function() return clientLocale end)
def("PlatyplusDB", { language = "frFR", welcomeSeen = true })

local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua" })

---------------------------------------------------------------------------
section("cohérence des dictionnaires (marqueurs)")
local FMT = "%%[%-%+#0]*%d*%.?%d*[sdfxXcgi%%]"
local function list(s, pattern)
    local t = {}
    for m in s:gmatch(pattern) do t[#t + 1] = m end
    return t
end
local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
local function sortedList(s)
    local t = {}
    for m in s:gmatch("|c%x%x%x%x%x%x%x%x") do t[#t + 1] = m end
    for m in s:gmatch("|r") do t[#t + 1] = m end
    for m in s:gmatch("|T.-|t") do t[#t + 1] = m end
    for m in s:gmatch("|n") do t[#t + 1] = m end
    for _ in s:gmatch("\n") do t[#t + 1] = "\\n" end
    table.sort(t)
    return t
end
local total, bad = 0, 0
local codes = {}
for code in pairs(ns.Strings) do codes[#codes + 1] = code end
table.sort(codes)
check(#codes >= 6, "les 6 dictionnaires sont enregistrés (enUS deDE esES itIT ptBR ruRU)")
for _, code in ipairs(codes) do
    local n = 0
    for k, v in pairs(ns.Strings[code]) do
        total, n = total + 1, n + 1
        local ok = type(k) == "string" and type(v) == "string" and v:match("%S") ~= nil
            and same(list(k, FMT), list(v, FMT)) and same(sortedList(k), sortedList(v))
        if not ok then
            bad = bad + 1
            M.realPrint("  ECHEC marqueurs " .. code .. " : " .. tostring(k):sub(1, 80))
            failures[#failures + 1] = "marqueurs " .. code
        end
    end
    M.realPrint(string.format("       %s : %d traduction(s)", code, n))
end
check(bad == 0, "aucune traduction n'altère les marqueurs (" .. total .. " vérifiées)")

---------------------------------------------------------------------------
section("T en français = la clé")
M.fireEvent("ADDON_LOADED", "Platyplus")
check(ns.lang == "frFR" and ns.langReady, "language = frFR : ns.lang frFR")
ns.AddStrings("enUS", { ["Clé test"] = "Test key", ["%d objets vendus"] = "%d items sold", ["Texte secret"] = "ne doit pas servir" })
check(ns.T("Clé test") == "Clé test", "frFR : T renvoie la clé même s'il existe une traduction anglaise")
check(ns.Tf("%d objets vendus", 3) == "3 objets vendus", "frFR : Tf formate la clé")

---------------------------------------------------------------------------
section("T en anglais")
ns.db.language = "enUS"
ns:SetupLocale()
check(ns.lang == "enUS", "language = enUS : ns.lang enUS")
check(ns.T("Clé test") == "Test key", "enUS : traduction trouvée")
check(ns.T("Clé inconnue") == "Clé inconnue", "enUS : sans traduction, la clé (français) est renvoyée")
check(ns.Tf("%d objets vendus", 3) == "3 items sold", "enUS : Tf traduit puis formate")

---------------------------------------------------------------------------
section("repli : langue -> anglais -> français")
ns.AddStrings("deDE", { ["Clé autre"] = "Anderer Schlüssel", ["Clé test"] = "Testschlüssel" })
ns.AddStrings("esES", { ["Clé esp"] = "Clave" })
ns.db.language = "deDE"
ns:SetupLocale()
check(ns.lang == "deDE", "language = deDE : ns.lang deDE")
check(ns.T("Clé autre") == "Anderer Schlüssel", "deDE : traduction allemande")
check(ns.T("Clé test") == "Testschlüssel", "deDE : l'allemand l'emporte sur l'anglais")
check(ns.T("%d objets vendus") == "%d items sold", "deDE : absent en allemand -> anglais")
check(ns.T("Clé inconnue") == "Clé inconnue", "deDE : absent partout -> français")
check(ns.Strings.esES == nil, "SetupLocale libère les dictionnaires inutiles (esES)")
check(ns.Strings.enUS ~= nil, "SetupLocale garde l'anglais (repli)")

---------------------------------------------------------------------------
section("valeurs non texte, secrètes, nil")
check(ns.T(nil) == nil, "T(nil) = nil")
check(ns.T(42) == 42, "T(nombre) = nombre")
local tbl = {}
check(ns.T(tbl) == tbl, "T(table) = table")
check(ns.T(true) == true, "T(booléen) = booléen")
ns.AddStrings("deDE", { [SECRET] = "traduit" })
check(ns.T(SECRET) == SECRET, "T(valeur secrète) = la valeur, jamais traduite")
check(ns.T("") == "", "T(chaîne vide) = chaîne vide")
check(select("#", ns.Tf("rien")) == 1 and ns.Tf("rien") == "rien", "Tf sans argument")

---------------------------------------------------------------------------
section("choix de la langue (auto, client, réglage)")
ns.db.language = "auto"
clientLocale = "frFR"; ns:SetupLocale()
check(ns.lang == "frFR", "auto + client frFR -> frFR")
clientLocale = "esMX"; ns:SetupLocale()
check(ns.lang == "esES", "auto + client esMX -> esES")
clientLocale = "ptPT"; ns:SetupLocale()
check(ns.lang == "ptBR", "auto + client ptPT -> ptBR")
clientLocale = "koKR"; ns:SetupLocale()
check(ns.lang == "enUS", "auto + client koKR (non géré) -> enUS")
ns.db.language = "ruRU"; ns:SetupLocale()
check(ns.lang == "ruRU", "réglage ruRU prioritaire sur le client")
ns.db.language = "klingon"; clientLocale = "deDE"; ns:SetupLocale()
check(ns.lang == "deDE", "réglage inconnu -> langue du client")
ns.db.language = nil; ns:SetupLocale()
check(ns.lang == "deDE", "réglage absent -> langue du client")
check(ns.Locale.Name("enUS") == "English" and ns.Locale.Name("xx") == "xx", "Locale.Name")

---------------------------------------------------------------------------
section("commande /pp langue")
ns.db.language = "auto"; clientLocale = "frFR"; ns:SetupLocale()
local slash = SlashCmdList and SlashCmdList.PLATYPLUS
check(slash ~= nil, "commande /pp enregistrée")
if slash then
    M.printed = {}
    slash("langue")
    check(#M.printed >= 1, "/pp langue affiche la langue active")
    slash("langue enUS")
    check(ns.db.language == "enUS", "/pp langue enUS change le réglage")
    slash("lang deDE")
    check(ns.db.language == "deDE", "/pp lang deDE (alias)")
    slash("language AUTO")
    check(ns.db.language == "auto", "/pp language auto")
    slash("langue xx")
    check(ns.db.language == "auto", "langue inconnue : réglage inchangé")
    slash("langue français")
    check(ns.db.language == "frFR", "/pp langue par nom natif")
end

section("police cyrillique (ruRU sur client non russe)")
do
    local FR = "Fonts\\FRIZQT__.TTF"
    local CYR = "Fonts\\FRIZQT___CYR.TTF"
    ns.db.language = "ruRU"; clientLocale = "frFR"; ns:SetupLocale()
    check(ns.Font(FR) == CYR, "ruRU + client frFR -> FRIZQT___CYR")
    clientLocale = "ruRU"; ns:SetupLocale()
    check(ns.Font(FR) == FR, "client ruRU -> police standard inchangée")
    ns.db.language = "enUS"; clientLocale = "frFR"; ns:SetupLocale()
    check(ns.Font(FR) == FR, "autre langue -> police standard")
end

section("suivi des textes manquants (/pp langue manque)")
do
    ns.db.language = "enUS"; clientLocale = "frFR"; ns:SetupLocale()
    ns.i18nTrace = nil
    M.printed = {}
    SlashCmdList.PLATYPLUS("langue manque")
    check(ns.i18nTrace == true, "1er appel active le suivi")
    ns.T("Phrase française sans traduction du test")
    SlashCmdList.PLATYPLUS("langue manque")
    check(ns.i18nMissing["Phrase française sans traduction du test"] ~= nil, "le texte manquant est listé")
    local r = ns.Tf("%s", SECRET)   -- résultat de Tf secret : pas de clé de table
    check(true, "Tf avec résultat secret ne plante pas")
    ns.i18nTrace = nil
end

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
