-- Test du chat plus confortable (Misc.lua, ns.Chat) dans le simulateur, en mode strict.
-- Reproduit ce que fait Forever : ChatFrameUtil.AddMessageEventFilter (filtres), EventRegistry « SetItemRef » (clic sur un
-- lien « addon: »), fenêtres de chat avec historique, GetNumMessages / GetMessageInfo (1 = le plus ancien) et
-- TransformMessages(test, transformation) ; issecretvalue pour les messages protégés.
-- Usage : python -I dev\lua.py run dev\test_chat.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = rawget(tbl, name)
    rawset(tbl, name, function(...)
        local results = { orig(...) }
        hook(...)
        return unpack(results)
    end)
end)
M.impl.SetText = function(f, t) S(f).text = t end
M.impl.GetText = function(f) return S(f).text end

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
local function runFilters(event, msg, ...)
    for _, fn in ipairs(filters[event] or {}) do
        local results = { fn(nil, event, msg, ...) }
        if results[1] then return nil end
        if results[2] ~= nil then return unpack(results, 2) end
    end
    return msg, ...
end
local function click(link) local c = callbacks.SetItemRef; if c then c.fn(c.owner, link, "[x]", "LeftButton", nil) end end

-- fenêtres de chat avec historique
def("NUM_CHAT_WINDOWS", 2)
local function chatFrame(name)
    local f = CreateFrame("Frame", name, UIParent)
    f.history = {}
    f.AddMessage = function(self, msg, r, g, b) table.insert(self.history, { message = msg, r = r, g = g, b = b }) end
    f.GetNumMessages = function(self) return #self.history end
    f.GetMessageInfo = function(self, i) local e = self.history[i]; if e then return e.message, e.r, e.g, e.b end end
    f.TransformMessages = function(self, pred, transform)
        for _, e in ipairs(self.history) do
            if pred(e.message, e.r, e.g, e.b) then
                e.message = (transform(e.message, e.r, e.g, e.b))
                e.transforms = (e.transforms or 0) + 1
            end
        end
    end
    return f
end
local chat1, chat2 = chatFrame("ChatFrame1"), chatFrame("ChatFrame2")
def("DEFAULT_CHAT_FRAME", chat1)
def("SELECTED_CHAT_FRAME", chat1)

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Misc.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.advance(0.1)
local Chat = ns.Chat

section("installation")
check(Chat ~= nil and ns.db.chatLinks and ns.db.chatShortChannels and ns.db.chatCopyButton, "trois options actives par défaut")
local n = 0
for _, list in pairs(filters) do n = n + #list end
check(n == 17 and filters.CHAT_MSG_GUILD and filters.CHAT_MSG_CHANNEL, "filtre posé sur 17 types de messages (" .. n .. ")")
check(callbacks.SetItemRef ~= nil, "clic sur nos liens : rappel « SetItemRef » d'EventRegistry")

section("liens web")
local msg, author, extra = runFilters("CHAT_MSG_GUILD", "va voir https://forever.example.com/guide?x=1.", "Bob", "lang")
check(msg == "va voir |Haddon:Platyplus:url:https://forever.example.com/guide?x=1|h|cff33ccff[https://forever.example.com/guide?x=1]|r|h.",
    "https://... devient un lien, le point final reste dehors : " .. tostring(msg))
check(author == "Bob" and extra == "lang", "les autres arguments du message sont transmis")
msg = runFilters("CHAT_MSG_SAY", "regarde www.wowhead.com pour ça")
check(msg and msg:find("|Haddon:Platyplus:url:www.wowhead.com|h", 1, true), "www... devient un lien")
local plain = "rien à voir ici, version 1.60.1"
check(runFilters("CHAT_MSG_SAY", plain) == plain, "texte sans adresse : intact (1.60.1 n'est pas un lien)")
local item = "achète |cffffffff|Hitem:1234|h[Épée]|h|r sur https://x.com"
check(runFilters("CHAT_MSG_SAY", item) == item, "message avec lien d'objet : laissé tel quel")
check(runFilters("CHAT_MSG_SAY", SECRET) == SECRET, "message protégé : jamais touché")
click("addon:Platyplus:url:https://forever.example.com/guide")
local copy = rawget(_G, "PlatyplusCopy")
check(copy and S(copy).shown and S(copy.edit).text == "https://forever.example.com/guide", "clic : fenêtre avec le lien, prêt à copier")
check(tostring(S(copy.title).text) == "Lien web", "titre « Lien web »")
local other = 0
copy:Hide()
click("addon:AutreAddon:truc")
check(not S(copy).shown, "les liens des autres addons ne sont pas pris")
local exists = false
for _, name in ipairs(UISpecialFrames) do if name == "PlatyplusCopy" then exists = true end end
check(exists, "Échap ferme la fenêtre de copie (UISpecialFrames)")

section("noms de canaux courts")
chat1:AddMessage("|Hchannel:channel:1|h[1. Général - Forêt d'Elwynn]|h [Bob]: salut", 1, 0.8, 0.6)
chat1:AddMessage("|Hchannel:GUILD|h[Guilde]|h [Ana]: yo", 0.2, 1, 0.2)
chat1:AddMessage("|Hchannel:PARTY|h[Groupe]|h [Léo]: go", 0.6, 0.6, 1)
chat1:AddMessage("Pas de canal ici")
chat1:AddMessage(SECRET)
check(chat1.history[1].message == "|Hchannel:channel:1|h[1]|h [Bob]: salut", "[1. Général - Forêt d'Elwynn] -> [1]")
check(chat1.history[2].message == "|Hchannel:GUILD|h[G]|h [Ana]: yo", "[Guilde] -> [G]")
check(chat1.history[3].message == "|Hchannel:PARTY|h[Gr]|h [Léo]: go", "[Groupe] -> [Gr]")
check(chat1.history[4].message == "Pas de canal ici" and chat1.history[5].message == SECRET, "autres lignes et ligne protégée intactes")
check(chat1.history[1].transforms == 1 and chat1.history[2].transforms == 1, "chaque ligne n'est réécrite qu'une fois")
chat2:AddMessage("|Hchannel:channel:2|h[2. Commerce - Hurlevent]|h [Max]: vends")
check(chat2.history[1].message == "|Hchannel:channel:2|h[2]|h [Max]: vends", "aussi dans les autres fenêtres de chat")

section("copier le chat")
SlashCmdList.PLATYPLUS("copier")
local text = tostring(S(copy.edit).text)
check(S(copy).shown and tostring(S(copy.title).text) == "Copier le chat", "/pp copier ouvre la fenêtre")
check(text:find("[1] [Bob]: salut", 1, true) and text:find("[G] [Ana]: yo", 1, true), "lignes en texte simple (codes retirés) : " .. text:sub(1, 60))
check(not text:find(SECRET, 1, true) and not text:find("|H", 1, true), "ligne protégée sautée, aucun code de lien")
local lines = select(2, text:gsub("\n", "\n")) + 1
check(lines == 4, "4 lignes copiables sur 5 (" .. lines .. ")")
check(Chat.CleanLine("|cffff0000rouge|r |TInterface\\Icons\\X:12|t |Hitem:1|h[Épée]|h |Kq1|k") == "rouge  [Épée] ?", "nettoyage des codes")
copy:Hide()

section("bouton de copie")
local btn
for _, c in ipairs(S(chat1).frames) do if S(c).kind == "Button" then btn = c end end
check(btn and S(btn).shown and S(btn).points[1][1] == "TOPRIGHT", "petit bouton en haut à droite de la fenêtre de chat")
M.fire(btn, "OnClick", "LeftButton")
check(S(copy).shown, "un clic ouvre la copie")
copy:Hide()

section("options coupées")
ns:Set("chatLinks", false)
local n2 = 0
for _, list in pairs(filters) do n2 = n2 + #list end
check(n2 == 0, "liens coupés : filtres retirés")
ns:Set("chatShortChannels", false)
chat1:AddMessage("|Hchannel:channel:1|h[1. Général - Forêt d'Elwynn]|h [Bob]: re")
check(chat1.history[6].message:find("[1. Général", 1, true) ~= nil, "canaux courts coupés : nouvelles lignes intactes")
ns:Set("chatCopyButton", false)
check(not S(btn).shown, "bouton de copie caché")
ns:Set("chatLinks", true)
local n3 = 0
for _, list in pairs(filters) do n3 = n3 + #list end
check(n3 == 17, "liens remis : filtres reposés une seule fois (" .. n3 .. ")")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
