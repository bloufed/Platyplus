-- Test du chat amélioré (ChatPlus.lua, ns.ChatPlus) dans le simulateur, en mode strict.
-- Reproduit ce que fait Forever : fenêtres de chat (textures nommées « ChatFrame1Background »...), onglets
-- (parentKey Left/Middle/Right/Active*/Highlight*), zone de saisie (AddHistoryLine, SetAltArrowKeyMode),
-- ChatFrameUtil.AddMessageEventFilter, CVars showTimestamps / chatClassColorOverride, valeurs secrètes.
-- Usage : python -I dev\lua.py run dev\test_chatplus.lua <dossier Platyplus> <dossier dev>
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

-- valeurs secrètes
local SECRET = "message protégé"
def("issecretvalue", function(v) return v == SECRET end)
def("canaccessvalue", function(...)
    for i = 1, select("#", ...) do if select(i, ...) == SECRET then return false end end
    return true
end)

-- joueur, amis, son
def("UnitName", function(unit) if unit == "player" then return "Leo" end return nil end)
def("UnitFullName", function() return "Leo", "Royaume" end)
def("GetRealmName", function() return "Royaume" end)
def("Ambiguate", function(name) return (tostring(name):match("^[^%-]+")) end)
def("UnitInParty", function(name) return name == "Copain" end)
def("UnitInRaid", function() return nil end)
def("C_FriendList", { IsFriend = function(guid) return guid == "Player-ami" end })
def("IsGuildMember", function(guid) return guid == "Player-guilde" end)
local sounds, flashes = 0, 0
def("SOUNDKIT", { TELL_MESSAGE = 3081 })
def("PlaySound", function() sounds = sounds + 1 end)
def("FlashClientIcon", function() flashes = flashes + 1 end)
def("date", function(f) return "12:34" end)
M.optional.TIMESTAMP_FORMAT_HHMM_24HR = true
M.optional.IsCombatLog = true
M.optional.MenuUtil = true

-- CVars connus du client
M.cvars = M.cvars or {}
M.cvars.showTimestamps = "none"
M.cvars.chatClassColorOverride = "1"

-- filtres de messages
local filters = {}
def("ChatFrameUtil", {
    AddMessageEventFilter = function(event, fn) filters[event] = filters[event] or {}; table.insert(filters[event], fn) end,
    RemoveMessageEventFilter = function(event, fn)
        for i, f in ipairs(filters[event] or {}) do if f == fn then table.remove(filters[event], i) break end end
    end,
})
-- un message passe par les filtres, comme dans Blizzard (arguments 1 à 12 de l'événement)
local lineCounter = 0
local function send(event, msg, author, opts)
    opts = opts or {}
    lineCounter = lineCounter + 1
    local lineID = opts.lineID or lineCounter
    local args = { msg, author, "", "", "", opts.flags or "", 0, 0, "", 0, lineID, opts.guid or "Player-x" }
    for _, fn in ipairs(filters[event] or {}) do
        local results = { fn(nil, event, unpack(args, 1, 12)) }
        if results[1] then return nil end
        if results[2] ~= nil then for i = 2, 13 do args[i - 1] = results[i] end end
    end
    return args[1]
end

-- fenêtres de chat
def("NUM_CHAT_WINDOWS", 2)
local function texture(parent, name)
    local t = parent:CreateTexture(name)
    t:SetTexture("Interface\\ChatFrame\\" .. (name or "tex"))
    if name then def(name, t) end   -- comme dans le jeu : une texture nommée est une globale
    return t
end
local function chatFrame(name)
    local f = CreateFrame("Frame", name, UIParent)
    f.history = {}
    f.AddMessage = function(self, msg, r, g, b) table.insert(self.history, { message = msg, r = r, g = g, b = b }) end
    f.GetNumMessages = function(self) return #self.history end
    f.GetMessageInfo = function(self, i) local e = self.history[i]; if e then return e.message, e.r, e.g, e.b end end
    f.TransformMessages = function() end
    f.Background = texture(f, name .. "Background")
    for _, key in ipairs({ "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture", "LeftTexture",
        "RightTexture", "BottomTexture", "TopTexture", "ButtonFrameBackground", "ButtonFrameTopTexture" }) do
        texture(f, name .. key)
    end
    local tab = CreateFrame("Button", name .. "Tab", UIParent)
    for _, key in ipairs({ "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
        "HighlightLeft", "HighlightMiddle", "HighlightRight" }) do
        tab[key] = texture(tab, nil)
    end
    local eb = CreateFrame("EditBox", name .. "EditBox", f)
    for _, key in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do texture(eb, name .. "EditBox" .. key) end
    eb.history = {}
    eb.AddHistoryLine = function(self, text) table.insert(self.history, text) end
    eb.SetAltArrowKeyMode = function(self, v) self.altArrow = v end
    f.editBox = eb
    return f
end
local chat1, chat2 = chatFrame("ChatFrame1"), chatFrame("ChatFrame2")
def("COMBATLOG", chat2)
def("SELECTED_CHAT_FRAME", chat1)
def("DEFAULT_CHAT_FRAME", chat1)
def("CHAT_FRAMES", { "ChatFrame1", "ChatFrame2" })
def("FCFTab_UpdateColors", function() end)
def("FCF_OpenTemporaryWindow", function() end)

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Misc.lua", "ChatPlus.lua", "GameSettings.lua" })
-- une session précédente a gardé des lignes et ce qui a été tapé
PlatyplusDB = {
    chatLog = { ["Leo-Royaume"] = { ChatFrame1 = { { "ancienne ligne", 1, 1, 1 }, { "|cff33ccffautre|r", 0.5, 0.5, 0.5 } } } },
    chatSent = { ["Leo-Royaume"] = { "/pp", "salut" } },
}
M.fireEvent("ADDON_LOADED", "Platyplus")
local CP = ns.ChatPlus

section("mémoire : retour de la session précédente")
check(#chat1.history == 3 and chat1.history[1].message == "ancienne ligne", "lignes remises dans la fenêtre (" .. #chat1.history .. ")")
check(chat1.history[1].r == 0.8, "un peu plus pâles")
check(tostring(chat1.history[3].message):find("fin de la session précédente", 1, true) ~= nil, "suivies d'un séparateur")
check(#ns.db.chatLog["Leo-Royaume"].ChatFrame1 == 2, "remises sans être enregistrées une deuxième fois")
check(chat1.editBox.history[1] == "/pp" and chat1.editBox.history[2] == "salut", "ce que tu avais tapé revient dans la zone de saisie")
check(chat1.editBox.altArrow == false, "flèches haut / bas sans Alt")

section("mémoire : enregistrement")
chat1:AddMessage("bonjour à tous", 1, 1, 0)
local log = ns.db.chatLog["Leo-Royaume"].ChatFrame1
check(log[#log][1] == "bonjour à tous" and log[#log][4] == 0, "nouvelle ligne gardée avec sa couleur")
chat1:AddMessage("|Hchannel:channel:1|h[1. Général - Elwynn]|h bla", 1, 1, 1)
check(log[#log][1] == "|Hchannel:channel:1|h[1]|h bla", "gardée raccourcie comme à l'écran")
chat1:AddMessage(SECRET, 1, 1, 1)
check(log[#log][1] ~= SECRET, "message secret jamais gardé")
chat2:AddMessage("Tu frappes le sanglier", 1, 1, 1)
check(ns.db.chatLog["Leo-Royaume"].ChatFrame2 == nil, "journal de combat jamais gardé")
for i = 1, 120 do chat1:AddMessage("ligne " .. i, 1, 1, 1) end
check(#log == 100 and log[100][1] == "ligne 120", "100 lignes au plus par fenêtre")
chat1.editBox:AddHistoryLine("/pp chat")
chat1.editBox:AddHistoryLine("/pp chat")
local sent = ns.db.chatSent["Leo-Royaume"]
check(sent[#sent] == "/pp chat" and sent[#sent - 1] == "salut", "ce que tu tapes est gardé (sans doublon à la suite)")
ns:Set("chatSentHistory", false)
check(chat1.editBox.altArrow == true, "option coupée : Alt + flèches comme avant")
ns:Set("chatSentHistory", true)
local lines, sentCount = CP.Memory:Count()
check(lines == 100 and sentCount == 3, "compte affiché dans les options")
CP.Memory:Clear()
check(ns.db.chatLog["Leo-Royaume"] == nil, "« Effacer l'historique »")

section("look")
local bg = _G.ChatFrame1Background
check(bg:GetTexture() == "Interface\\Buttons\\WHITE8X8", "fond uni")
check(_G.ChatFrame1TopLeftTexture:GetTexture() == nil and _G.ChatFrame1ButtonFrameTopTexture:GetTexture() == nil, "bords arrondis retirés")
local tab = _G.ChatFrame1Tab
check(tab.Left:GetTexture() == nil and tab.ActiveMiddle:GetTexture() == nil, "onglet : art de Blizzard retiré")
check(tab.PlatyplusSkin and S(tab.PlatyplusSkin.line).shown, "onglet actif souligné")
check(not S(_G.ChatFrame2Tab.PlatyplusSkin.line).shown, "les autres non")
FCFTab_UpdateColors(_G.ChatFrame2Tab, true)
check(S(_G.ChatFrame2Tab.PlatyplusSkin.line).shown, "suit l'onglet choisi (FCFTab_UpdateColors)")
check(_G.ChatFrame1EditBoxLeft:GetTexture() == nil and chat1.editBox.PlatyplusSkin.bg ~= nil, "zone de saisie redessinée")
ns:Set("chatSkin", false)
check(bg:GetTexture() == "Interface\\ChatFrame\\ChatFrame1Background", "coupé : fond d'origine")
check(_G.ChatFrame1TopLeftTexture:GetTexture() == "Interface\\ChatFrame\\ChatFrame1TopLeftTexture", "coupé : bords d'origine")
check(not S(tab.PlatyplusSkin.line).shown and not S(chat1.editBox.PlatyplusSkin.bg).shown, "coupé : nos ajouts cachés")
ns:Set("chatSkin", true)
check(bg:GetTexture() == "Interface\\Buttons\\WHITE8X8", "rallumé")

section("lisibilité : réglages du jeu")
check(M.cvars.showTimestamps == "%H:%M ", "heure allumée au premier chargement (" .. tostring(M.cvars.showTimestamps) .. ")")
check(ns.db.cvarBackup.showTimestamps == "none", "valeur d'origine gardée")
check(M.cvars.chatClassColorOverride == "0", "couleurs de classe partout")
ns:Set("chatTimestamps", false)
check(M.cvars.showTimestamps == "none", "coupé : valeur d'origine remise")
ns:Set("chatTimestamps", true)

section("lisibilité : ton nom")
local out = send("CHAT_MSG_GUILD", "salut leo, ça va ?", "Bob-Royaume")
check(out == "salut |cffffd133leo|r, ça va ?", "nom surligné : " .. tostring(out))
check(sounds == 1 and flashes == 1, "son et icône qui clignote")
send("CHAT_MSG_GUILD", "leo leo", "Bob-Royaume")
check(sounds == 1, "pas de son en rafale (3 s)")
out = send("CHAT_MSG_SAY", "Leonard est là", "Bob-Royaume")
check(out == "Leonard est là", "pas au milieu d'un autre mot")
out = send("CHAT_MSG_SAY", "voilà |Hplayer:Leo|h[Leo]|h et Leo", "Bob-Royaume")
check(out == "voilà |Hplayer:Leo|h[Leo]|h et |cffffd133Leo|r", "liens laissés intacts : " .. tostring(out))
out = send("CHAT_MSG_SAY", "je suis Leo", "Leo-Royaume")
check(out == "je suis Leo", "pas dans tes propres messages")

section("anti-spam")
check(send("CHAT_MSG_CHANNEL", "WTS GOLD cheap www.g0ld-shop.com 24/7", "Spammeur") == nil, "vente d'or avec site : masquée")
check(send("CHAT_MSG_CHANNEL", "Gold 10€ les 1000, livraison rapide", "Spammeur2") == nil, "vente d'or en euros : masquée")
check(send("CHAT_MSG_CHANNEL", "il me manque du gold pour ma monture", "Paul") ~= nil, "parler d'or : affiché")
check(send("CHAT_MSG_CHANNEL", "un joueur cherche de l'aide, gold à gagner", "Paul") ~= nil, "« eur » dans « joueur » : affiché")
check(send("CHAT_MSG_CHANNEL", "Golden Pearl à vendre", "Paul") ~= nil, "« Golden » n'est pas « gold »")
check(send("CHAT_MSG_CHANNEL", "LFM Mortemines tank", "Jean") ~= nil, "premier message : affiché")
check(send("CHAT_MSG_CHANNEL", "LFM  Mortemines tank !", "Jean") == nil, "le même 1 min plus tard : masqué")
M.time = M.time + 130
check(send("CHAT_MSG_CHANNEL", "LFM Mortemines tank", "Jean") ~= nil, "le même 2 min plus tard : affiché")
check(send("CHAT_MSG_CHANNEL", "WTS GOLD www.shop.com", "Ami", { guid = "Player-ami" }) ~= nil, "jamais un ami")
check(send("CHAT_MSG_CHANNEL", "WTS GOLD www.shop.com", "Membre", { guid = "Player-guilde" }) ~= nil, "jamais la guilde")
check(send("CHAT_MSG_CHANNEL", "WTS GOLD www.shop.com", "Copain") ~= nil, "jamais le groupe")
check(send("CHAT_MSG_CHANNEL", "WTS GOLD www.shop.com", "MJ", { flags = "GM" }) ~= nil, "jamais un MJ")
SlashCmdList.PLATYPLUS("spam ajouter Boost")
check(ns.db.chatFilterWords[1] == "boost", "/pp spam ajouter")
check(send("CHAT_MSG_CHANNEL", "Vends BOOST donjons", "Vendeur") == nil, "mot choisi : masqué")
SlashCmdList.PLATYPLUS("spam retirer boost")
check(#ns.db.chatFilterWords == 0, "/pp spam retirer")
local before = CP.Spam.hidden
send("CHAT_MSG_CHANNEL", "WTS GOLD www.x.com", "S3", { lineID = 9999 })
check(send("CHAT_MSG_CHANNEL", "WTS GOLD www.x.com", "S3", { lineID = 9999 }) == nil and CP.Spam.hidden == before + 1,
    "même ligne vue par deux fenêtres : même décision, comptée une fois")
check(CP.Spam:RecentText():find("vente d'or", 1, true) ~= nil, "liste des messages masqués, avec la raison")
ns:Set("chatSpam", false)
check(send("CHAT_MSG_CHANNEL", "WTS GOLD www.y.com", "S4") ~= nil, "option coupée : rien n'est masqué")
ns:Set("chatSpam", true)

section("état")
local status = CP:Status()
check(#status == 3, "/pp chat : 3 lignes")
for _, l in ipairs(status) do M.realPrint("     " .. l) end

M.report()
if #failures > 0 or #M.errors > 0 then
    M.realPrint("ÉCHECS : " .. #failures)
    os.exit(1)
end
M.realPrint("tout est bon")
