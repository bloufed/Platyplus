-- Test du module Traducteur (Traducteur.lua, ns.Trad) dans le simulateur.
-- Reproduit ce que fait Forever : ChatFrameUtil.AddMessageEventFilter (filtres), EventRegistry « SetItemRef » (clic sur un
-- lien « addon: »), issecretvalue pour les messages protégés.
-- Usage : python -I dev\lua.py run dev\test_trad.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local function printedHas(sub)
    for _, line in ipairs(M.printed) do if line:find(sub, 1, true) then return true end end
    return false
end

M.impl.SetText = function(f, t) S(f).text = t end
M.impl.GetText = function(f) return S(f).text end

-- le journal du chat du jeu
local logging, calls = false, 0
def("LoggingChat", function(on)
    if on ~= nil then logging = on and true or false; calls = calls + 1 end
    return logging
end)
def("UnitName", function(unit) if unit == "player" then return "Ry Ne" end end)
def("UnitGUID", function(unit) if unit == "player" then return "Player-1-MOI" end end)
def("Ambiguate", function(name) return (name:gsub("%-.*$", "")) end)

-- messages protégés (restrictions d'instance) : chaînes « secrètes »
local SECRET = "message protégé"
def("issecretvalue", function(v) return v == SECRET end)

-- filtres de messages et rappels de clic
local filters = {}
def("ChatFrameUtil", {
    AddMessageEventFilter = function(event, fn) filters[event] = filters[event] or {}; table.insert(filters[event], fn) end,
    RemoveMessageEventFilter = function(event, fn)
        for i, f in ipairs(filters[event] or {}) do if f == fn then table.remove(filters[event], i) break end end
    end,
})
local callbacks = {}
def("EventRegistry", {
    RegisterCallback = function(self, event, fn, owner) callbacks[event] = { fn = fn, owner = owner } end,
})
local function nFilters()
    local n = 0
    for _, list in pairs(filters) do n = n + #list end
    return n
end
-- comme Blizzard : arguments du message = auteur(1) ... lineID(10), guid(11)
local function receive(event, msg, author, lineID, guid)
    local args = { author or "Bob-Royaume", "", "", "", "", 0, 0, "", 0, lineID or 0, guid or "Player-1-BOB" }
    for _, fn in ipairs(filters[event] or {}) do
        local results = { fn(nil, event, msg, unpack(args, 1, 11)) }
        if results[1] then return nil end
        if results[2] ~= nil then
            msg = results[2]
            for i = 1, 11 do args[i] = results[i + 2] end
        end
    end
    return msg, args
end
local function linkOf(msg) return msg and msg:match("|H(addon:Platyplus:trad:%d+)|h") end
local function click(link, button)
    local c = callbacks.SetItemRef
    if c then c.fn(c.owner, link, "[FR]", button or "LeftButton", nil) end
end

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Misc.lua", "Traducteur.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
local T = ns.Trad
local urlFilters = nFilters()   -- ceux de ns.Chat (liens web)

section("option coupée par défaut")
check(T ~= nil, "module ns.Trad chargé")
check(ns.db.tradChatLog == false, "tradChatLog = false par défaut")
check(logging == false and calls == 0, "le journal n'est pas touché")
check(ns.db.tradPersos["Ry Ne"] == true, "le nom du personnage est noté dans tradPersos")
check(nFilters() == urlFilters, "pas de filtre du traducteur tant que l'option est coupée")
check(linkOf((receive("CHAT_MSG_WHISPER", "ARE YOU"))) == nil, "pas de lien [FR]")

section("/pp trad")
SlashCmdList["PLATYPLUS"]("trad")
check(ns.db.tradChatLog == true, "/pp trad allume l'option")
check(logging == true, "le journal du chat est allumé")
check(printedHas("[FR]") and printedHas("Ctrl+Entrée"), "explique le clic sur [FR] et Ctrl+Entrée")
check(nFilters() == urlFilters + 14, "filtre posé sur 14 types de messages reçus (" .. (nFilters() - urlFilters) .. ")")
check(filters.CHAT_MSG_WHISPER and filters.CHAT_MSG_CHANNEL and #filters.CHAT_MSG_WHISPER_INFORM == 1,
    "chuchotements et canaux compris, pas mes chuchotements envoyés")
check(callbacks.SetItemRef ~= nil, "clic sur [FR] : rappel « SetItemRef » d'EventRegistry")
M.fireEvent("PLAYER_ENTERING_WORLD")
check(calls == 1, "pas de nouvel appel quand le journal est déjà allumé")

section("lien [FR] sur les messages étrangers")
local msg, args = receive("CHAT_MSG_WHISPER", "ARE YOU", "Ima Dwaté-Forever", 101)
check(linkOf(msg) ~= nil and msg:find("^ARE YOU |H") and msg:find("[FR]", 1, true), "« ARE YOU » : lien [FR] au bout : " .. tostring(msg))
check(args[1] == "Ima Dwaté-Forever" and args[10] == 101 and args[11] == "Player-1-BOB", "les autres arguments sont transmis")
local msg2 = receive("CHAT_MSG_WHISPER", "ARE YOU", "Ima Dwaté-Forever", 101)
check(linkOf(msg2) == linkOf(msg), "même message dans une 2e fenêtre de chat : même lien")
check(linkOf((receive("CHAT_MSG_CHANNEL", "alguien para ulda?", "Pepe", 102))) ~= nil, "espagnol : lien")
check(linkOf((receive("CHAT_MSG_SAY", "kannst du mir helfen", "Hans", 103))) ~= nil, "allemand (« du ») : lien")
for _, fr in ipairs({ "salut tu fais quoi", "je cherche un groupe pour WC", "c'est bon merci", "dsl j'étais afk" }) do
    local m = receive("CHAT_MSG_GUILD", fr, "Paul", 104)
    check(m == fr, "français, pas de lien : « " .. fr .. " »")
end
check(receive("CHAT_MSG_CHANNEL", "+", "Till", 105) == "+", "« + » (pas de mots) : pas de lien")
check(receive("CHAT_MSG_SAY", "hello", "Ry Ne", 106, "Player-1-MOI") == "hello", "mon propre message : pas de lien")
check(receive("CHAT_MSG_WHISPER", SECRET, "Bob", 107) == SECRET, "message protégé : jamais touché")
local withUrl = receive("CHAT_MSG_SAY", "check https://wowhead.com now", "Bob", 108)
check(withUrl and withUrl:find("|Haddon:Platyplus:url:", 1, true) and linkOf(withUrl), "lien web et [FR] ensemble")

section("clic gauche sur [FR] : bande de pixels pour le programme")
local PHYS_H, SCALE = 1440, 0.64
def("GetPhysicalScreenSize", function() return 3440, PHYS_H end)
M.impl.GetEffectiveScale = function() return SCALE end
local function stripTextures(frame)
    local list = {}
    for _, t in ipairs(M.allFrames) do
        local s = S(t)
        if s.kind == "Texture" and s.parent == frame and s.shown then list[#list + 1] = t end
    end
    return list
end
click(linkOf(msg))
local strip = rawget(_G, "PlatyplusTradStrip")
check(strip and S(strip).shown and S(strip).strata == "TOOLTIP", "la bande s'affiche, au-dessus de tout")
check(strip and S(strip).points[1] and S(strip).points[1][1] == "TOPLEFT" and S(strip).points[1][4] == 0
    and S(strip).points[1][5] == 0, "en haut à gauche de l'écran")
check(not rawget(_G, "PlatyplusTradCopy"), "pas de zone à copier (traduction directe)")
-- rendu : unités de l'interface -> vrais pixels, comme le jeu (ConvertPixelsToUI à l'envers)
local K = SCALE * PHYS_H / 768
local W, H = 768, 9
local px = {}
for i = 1, W * H do px[i] = { 40, 30, 20 } end   -- fond : le haut de l'écran du jeu
local sizesOk, n = true, 0
for _, t in ipairs(stripTextures(strip)) do
    local s = S(t)
    local x0 = math.floor(s.points[1][4] * K + 0.5)
    local y0 = math.floor(-s.points[1][5] * K + 0.5)
    local size = math.floor(s.w * K + 0.5)
    if size ~= 3 or x0 % 3 ~= 0 or y0 % 3 ~= 0 then sizesOk = false end
    local c = s.color
    for y = y0, y0 + size - 1 do
        for x = x0, x0 + size - 1 do
            if x < W and y < H then
                px[y * W + x + 1] = { math.floor(c[3] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[1] * 255 + 0.5) }
            end
        end
    end
    n = n + 1
end
check(sizesOk, "chaque carré fait exactement 3 vrais pixels, aligné sur la grille")
check(n == 7 + 2 * (4 + #("Ima Dwaté › ARE YOU")), "un carré par demi-octet, plus l'en-tête (" .. n .. ")")
local out = {}
for i = 1, W * H do local p = px[i]; out[i] = string.char(p[1], p[2], p[3], 255) end
local file = io.open((os.getenv("TEMP") or ".") .. "/platyplus_bande.bgra", "wb")
if file then file:write(table.concat(out)); file:close() end
M.advance(0.7)
check(not S(strip).shown, "la bande disparaît après 0,6 s")
click(linkOf(msg))
click(linkOf((receive("CHAT_MSG_CHANNEL", "alguien para ulda?", "Pepe", 102))))
M.advance(0.4)
check(S(strip).shown, "deux clics rapides : la 2e bande n'est pas coupée par le minuteur de la 1re")
M.advance(0.4)
check(not S(strip).shown, "puis elle disparaît aussi")
local long = string.rep("é", 200)
local cells = T.StripCells(long, 1)
check(#cells == 7 + 2 * (4 + 400), "StripCells : un octet = 2 carrés")
click(linkOf((receive("CHAT_MSG_SAY", "hola " .. long, "Pepe", 109))))
check(#stripTextures(strip) <= 7 + 2 * (4 + 250), "message trop long : coupé à 250 octets (3 rangées au plus)")
M.advance(1)

section("/pp trad test : bande d'essai de 8 s")
M.printed = {}
SlashCmdList["PLATYPLUS"]("trad test")
check(S(strip).shown and printedHas("bande d'essai"), "la bande d'essai s'affiche, avec une explication")
M.advance(5)
check(S(strip).shown, "elle reste plus longtemps qu'un clic (5 s)")
M.advance(3.5)
check(not S(strip).shown, "puis disparaît (8 s)")
check(ns.db.tradChatLog == true, "/pp trad test ne change pas l'option")

section("clic droit sur [FR] : zone à copier")
M.ctrl = false
click(linkOf(msg), "RightButton")
local box = rawget(_G, "PlatyplusTradCopy")
check(box and S(box).shown, "la petite zone s'ouvre")
check(box and S(box.edit).text == "Ima Dwaté › ARE YOU", "« Nom › message » prêt à copier : " .. tostring(box and S(box.edit).text))
check(box and S(box.edit).focus, "le clavier est dans la zone (Ctrl+C copie tout de suite)")
S(box.edit).scripts.OnTextChanged(box.edit, true)
check(S(box.edit).text == "Ima Dwaté › ARE YOU", "lecture seule : une frappe remet le texte")
M.ctrl = true
S(box.edit).scripts.OnKeyDown(box.edit, "C")
check(S(box).shown, "Ctrl+C : la zone reste le temps de la copie")
M.advance(0.3)
check(not S(box).shown, "puis se ferme toute seule")
M.ctrl = false
click("addon:Platyplus:trad:9999")
check(printedHas("trop ancien"), "lien inconnu (après un /reload) : message clair")
click("addon:Platyplus:url:https://x.com")
check(not S(box).shown, "les liens web ne l'ouvrent pas")

section("/pp trad off")
SlashCmdList["PLATYPLUS"]("trad off")
check(ns.db.tradChatLog == false and logging == false, "/pp trad off éteint le journal qu'on avait allumé")
check(nFilters() == urlFilters, "filtres du traducteur retirés")

section("journal allumé par le joueur lui-même")
logging = true
SlashCmdList["PLATYPLUS"]("trad on")
SlashCmdList["PLATYPLUS"]("trad off")
check(logging == true, "on n'éteint pas un journal qu'on n'a pas allumé (/chatlog du joueur)")

section("nom protégé")
def("UnitName", function() return SECRET end)
ns.db.tradPersos = {}
T:NotePlayer()
check(next(ns.db.tradPersos) == nil, "un nom protégé n'est pas noté (ni comparé)")

M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
