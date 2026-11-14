local ADDON, ns = ...

-- Traductions de Platyplus.
-- Le FRANÇAIS est la langue source : le texte français du code sert de clé.
--   ns.T("Vendre les objets gris")          -> texte dans la langue choisie (ou la clé si pas de traduction)
--   ns.Tf("%d objets vendus", n)            -> string.format(T(fmt), ...)
-- Les dictionnaires sont dans Locales\<code>.lua : ns.AddStrings("enUS", { ["clé française"] = "English", ... }).
-- Chaîne de repli : langue choisie -> anglais -> français (la clé).
--
-- RÈGLES
--  * Ne jamais appeler T() au niveau d'un fichier (à son chargement) : PlatyplusDB et donc la langue
--    ne sont connues qu'à ADDON_LOADED. Garder le français dans les tables statiques et traduire à
--    l'usage : T(entry.name).
--  * La clé est la phrase ENTIÈRE avec ses %s/%d/codes couleur |cff..|r : pas de morceaux collés.
--  * T() ne touche jamais une valeur non texte ni secrète (retournée telle quelle).

local M = {}
ns.Locale = M

-- Langues proposées (français = source). Les clients koKR/zhCN/zhTW/esMX... tombent sur la plus proche.
ns.LANGUAGES = {
    { code = "frFR", name = "Français" },
    { code = "enUS", name = "English" },
    { code = "deDE", name = "Deutsch" },
    { code = "esES", name = "Español" },
    { code = "itIT", name = "Italiano" },
    { code = "ptBR", name = "Português" },
    { code = "ruRU", name = "Русский" },
}

-- Langue du client -> langue Platyplus (le reste = anglais)
local CLIENT_MAP = { esMX = "esES", ptPT = "ptBR" }

local strings = {}          -- strings[code] = { [clé française] = traduction }
ns.Strings = strings
ns.lang = "frFR"            -- langue active (fixée par ns:SetupLocale à ADDON_LOADED)
ns.langReady = false        -- faux tant que SetupLocale n'a pas tourné (T renvoie alors la clé)

local issecretvalue = rawget(_G, "issecretvalue")

-- Les fichiers Locales\xx.lua s'enregistrent ici
function ns.AddStrings(code, tbl)
    local dest = strings[code]
    if not dest then
        strings[code] = tbl
    else
        for k, v in pairs(tbl) do dest[k] = v end
    end
end

local function known(code)
    for _, l in ipairs(ns.LANGUAGES) do
        if l.code == code then return true end
    end
    return false
end

-- Langue demandée -> code effectif ("auto" = langue du client)
function M.Resolve(choice)
    if choice and choice ~= "auto" and known(choice) then return choice end
    local getLocale = rawget(_G, "GetLocale")
    local client = (getLocale and getLocale()) or "enUS"
    client = CLIENT_MAP[client] or client
    if known(client) then return client end
    return "enUS"
end

-- Appelé une fois, au chargement des réglages : fixe la langue et libère les autres dictionnaires
function ns:SetupLocale()
    local choice = self.db and self.db.language
    ns.lang = M.Resolve(choice)
    ns.langReady = true
    for code in pairs(strings) do
        if code ~= ns.lang and code ~= "enUS" then strings[code] = nil end
    end
end

-- Chaînes sans traduction rencontrées (rempli seulement si ns.i18nTrace, pour les tests / `/pp langue manque`)
ns.i18nMissing = {}
local formatted = {}         -- résultats de Tf vus pendant la trace (ne sont pas des clés)

-- Une clé « utile » contient au moins un mot (hors %d, codes couleur et textures)
local function hasWord(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("%%[%-%+#0]*%d*%.?%d*[sdfxXcgi%%]", "")
    return s:find("%a") ~= nil
end

local active, fallback      -- dictionnaires de la langue et de l'anglais (résolus à la 1re demande)
local function dicts()
    active = strings[ns.lang]
    fallback = strings.enUS
end

-- T : traduit une phrase française
local function T(s)
    if type(s) ~= "string" then return s end
    if issecretvalue and issecretvalue(s) then return s end
    if not ns.langReady or ns.lang == "frFR" then return s end
    if not active or active ~= strings[ns.lang] then dicts() end
    local r = active and active[s]
    if r == nil and ns.lang ~= "enUS" then r = fallback and fallback[s] end
    if r == nil then
        if ns.i18nTrace and not formatted[s] and hasWord(s) then ns.i18nMissing[s] = ns.i18nOrigin or true end
        return s
    end
    return r
end
ns.T = T

-- Tf : T puis string.format
function ns.Tf(fmt, ...)
    local r = string.format(T(fmt), ...)
    if ns.i18nTrace and not (issecretvalue and issecretvalue(r)) then formatted[r] = true end
    return r
end

-- Police compatible avec la langue active. Le client non russe n'a pas de cyrillique dans
-- FRIZQT__.TTF : on prend FRIZQT___CYR.TTF (Vérifié dans le code de Forever :
-- _ref/wow-ui-source/Interface/AddOns/Blizzard_Fonts_Shared/Mainline/Fonts.xml, font="Fonts\\FRIZQT___CYR.TTF").
-- À appeler À L'USAGE (la langue n'est connue qu'à ADDON_LOADED).
function ns.Font(path)
    if ns.lang == "ruRU" then
        local getLocale = rawget(_G, "GetLocale")
        if not (getLocale and getLocale() == "ruRU") then return "Fonts\\FRIZQT___CYR.TTF" end
    end
    return path
end

-- Nom lisible de la langue active (pour les options)
function M.Name(code)
    for _, l in ipairs(ns.LANGUAGES) do
        if l.code == code then return l.name end
    end
    return code
end
