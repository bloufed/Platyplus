-- Test de la fenêtre de chat Platyplus (ChatWindow.lua, ns.ChatWindow) dans le simulateur, en mode strict.
-- Reproduit ce que fait Forever : chaque fenêtre de chat ajoute ses messages par
-- AddMessage(texte, r, g, b, id, accès, type, événement, argumentsBruts) ; zone de saisie enfant de sa fenêtre ;
-- GetPlayerLink, ChatFrameUtil.GetDecoratedSenderName, SetItemRef ; valeurs secrètes.
-- Usage : python -I dev\lua.py run dev\test_chatwindow.lua <dossier Platyplus> <dossier dev>
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
M.impl.SetParent = function(f, parent) S(f).parent = parent end   -- (le simulateur l'ignore)

max = math.max

-- valeurs secrètes
local SECRET = "message protégé"
def("issecretvalue", function(v) return v == SECRET end)
def("canaccessvalue", function(...)
    for i = 1, select("#", ...) do if select(i, ...) == SECRET then return false end end
    return true
end)

def("UnitName", function(unit) if unit == "player" then return "Leo" end end)
def("UnitFullName", function() return "Leo", "Royaume" end)
def("GetRealmName", function() return "Royaume" end)
def("Ambiguate", function(name) return (tostring(name):match("^[^%-]+")) end)
def("date", function(fmt) if fmt == "%Y-%m-%d" then return "2026-11-05" end return "15:27" end)
def("GetPlayerLink", function(name, display, lineID) return "|Hplayer:" .. name .. ":" .. tostring(lineID) .. "|h[" .. display .. "]|h" end)
local refs = {}
def("SetItemRef", function(link, text, button) refs[#refs + 1] = link end)
-- le jeu colore le nom par classe seulement si son option est cochée : ici, non (nom brut)
local classColorInGame = false
def("ChatFrameUtil", {
    GetDecoratedSenderName = function(event, text, sender)
        local short = sender:match("^[^%-]+")
        if classColorInGame then return "|cffc79c6e" .. short .. "|r" end
        return short
    end,
})
def("GetPlayerInfoByGUID", function(guid) if guid == "Player-Bob-Royaume" then return "Druide", "DRUID" end end)
def("RAID_CLASS_COLORS", { DRUID = { r = 1, g = 0.49, b = 0.04 } })
def("C_ChatInfo", { ReplaceIconAndGroupExpressions = function(msg) return msg end })
M.optional.IsCombatLog = true
M.optional.TIMESTAMP_FORMAT_HHMM_24HR = true
M.optional.MenuUtil = true
M.optional.GetBNPlayerLink = true
M.optional.UnitInParty = true
M.optional.UnitInRaid = true
M.optional.C_FriendList = true
M.optional.IsGuildMember = true
M.optional.SOUNDKIT = true
M.optional.PlaySound = true
M.optional.FlashClientIcon = true
M.optional.ChatFontNormal = true
M.optional.IsShiftKeyDown = true

-- fenêtres de chat du jeu
def("NUM_CHAT_WINDOWS", 3)
local function chatFrame(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(400, 180)
    f.history = {}
    f.AddMessage = function(self, msg, r, g, b) table.insert(self.history, { message = msg, r = r, g = g, b = b }) end
    f.GetNumMessages = function(self) return #self.history end
    f.GetMessageInfo = function(self, i) local e = self.history[i]; if e then return e.message, e.r, e.g, e.b end end
    f.TransformMessages = function() end
    def(name .. "Tab", CreateFrame("Button", name .. "Tab", UIParent))
    local eb = CreateFrame("EditBox", name .. "EditBox", f)
    eb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -5, -2)
    eb.AddHistoryLine = function() end
    eb.SetAltArrowKeyMode = function() end
    f.editBox = eb
    def(name, f)
    return f
end
local chat1, chat2, chat3 = chatFrame("ChatFrame1"), chatFrame("ChatFrame2"), chatFrame("ChatFrame3")
def("COMBATLOG", chat2)
def("SELECTED_CHAT_FRAME", chat1)
def("DEFAULT_CHAT_FRAME", chat1)
local CHAT_FRAMES = { "ChatFrame1", "ChatFrame2", "ChatFrame3" }
def("CHAT_FRAMES", CHAT_FRAMES)
def("GeneralDockManager", CreateFrame("Frame", "GeneralDockManager", UIParent))
def("FCF_OpenTemporaryWindow", function() end)
def("FCFTab_UpdateColors", function() end)

-- modèles du jeu (frFR) et couleurs des types, pour reconnaître les lignes déjà là
def("CHAT_GUILD_GET", "|Hchannel:GUILD|h[Guilde]|h %s :\32")
def("CHAT_PARTY_GET", "|Hchannel:PARTY|h[Groupe]|h %s :\32")
def("CHAT_WHISPER_GET", "%s chuchote : ")
def("CHAT_WHISPER_INFORM_GET", "À %s : ")
def("CHAT_SAY_GET", "%s dit : ")
def("CHAT_CHANNEL_GET", "%s : ")
def("CHAT_YELL_GET", "%s crie : ")
def("CHAT_EMOTE_GET", "%s ")
def("ChatTypeInfo", {
    GUILD = { r = 0.25, g = 1, b = 0.25 }, PARTY = { r = 0.67, g = 0.67, b = 1 },
    WHISPER = { r = 1, g = 0.5, b = 1 }, WHISPER_INFORM = { r = 1, g = 0.5, b = 1 },
    SAY = { r = 1, g = 1, b = 1 }, EMOTE = { r = 1, g = 0.5, b = 0.25 },
})

M.enableStrict()
local files = { "Core.lua", "UIWidgets.lua", "Misc.lua", "ChatPlus.lua", "ChatWindow.lua", "GameSettings.lua" }
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
-- fenêtre très haute : tous les messages du test sont dessinés (la vue ne dessine que ce qui se voit ; voir « défilement »)
PlatyplusDB = { chatSkin = false, chatWinPos = { x = 20, y = 20, w = 600, h = 4000 } }
M.fireEvent("ADDON_LOADED", "Platyplus")
local CW = ns.ChatWindow

local function args(msg, author, lineID, extra)
    local a = { msg, author, "", "", "", "", 0, 0, "", 0, lineID, "Player-" .. author, 0, false, false, false, false, n = 17 }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end
-- la ligne telle que le jeu la formate (un message protégé : toute la ligne l'est)
local FORMAT = { CHAT_MSG_GUILD = "|Hchannel:GUILD|h[Guilde]|h %s : ", CHAT_MSG_PARTY = "|Hchannel:PARTY|h[Groupe]|h %s : ",
    CHAT_MSG_WHISPER = "%s chuchote : ", CHAT_MSG_WHISPER_INFORM = "À %s : ", CHAT_MSG_SAY = "%s dit : ",
    CHAT_MSG_CHANNEL = "|Hchannel:channel:1|h[1. Général]|h %s : " }
local function say(frame, event, msg, author, lineID, extra, r, g, b)
    local text = msg
    if msg ~= SECRET then
        local link = "|Hplayer:" .. author .. ":" .. lineID .. "|h[" .. author:match("^[^%-]+") .. "]|h"
        text = (FORMAT[event] or "%s : "):format(link) .. msg
    end
    frame:AddMessage(text, r or 0.25, g or 1, b or 0.25, 1, 0, 0, event, args(msg, author, lineID, extra))
end
-- la vue : une ligne (cadre) par message ; son texte, sa couleur
local function row(k) return CW.rows[#CW.rows - (k or 0)] end
local function lines() local t = {} for i, r in ipairs(CW.rows) do t[i] = tostring(r.body:GetText()) end return t end
local function lastLine(k) return tostring(row(k) and row(k).body:GetText()) end
local function color(r) local cr, cg, cb = r.body:GetTextColor(); return cr, cg, cb end
local function count() return #CW.rows end

section("à la place du chat du jeu")
check(CW.frame and CW.frame:IsShown(), "fenêtre Platyplus affichée")
check(not chat1:IsVisible() and not _G.ChatFrame1Tab:IsVisible() and not GeneralDockManager:IsVisible(), "fenêtres, onglets et dock du jeu rangés")
check(chat1.editBox:GetParent() == CW.frame, "zone de saisie du jeu posée dans la fenêtre")
section("lignes formatées par le jeu, sans événement : lues d'après le texte, chacune dans son onglet")
-- (ce que Forever passe à AddMessage : le texte formaté, la couleur ; l'événement et ses arguments pas toujours)
chat1:AddMessage("Bienvenue dans World of Warcraft", 1, 1, 0)
chat1:AddMessage("|Hchannel:GUILD|h[Guilde]|h |Hplayer:Bob-Royaume:1|h[Bob]|r|h : coucou", 0.25, 1, 0.25)
chat1:AddMessage("[15:20] |Hchannel:PARTY|h[Groupe]|h |Hplayer:Bob-Royaume:2|h[Bob]|h : go", 0.67, 0.67, 1)
chat1:AddMessage("|Hplayer:Ana-Royaume:3|h[Ana]|h chuchote : psst", 1, 0.5, 1)
chat1:AddMessage("À |Hplayer:Ana-Royaume:4|h[Ana]|h : oui", 1, 0.5, 1)
chat1:AddMessage("|Hchannel:channel:1|h[1. Général]|h |Hplayer:Jean-Royaume:5|h[Jean]|h : LFM", 1, 0.75, 0.75)
chat1:AddMessage("|Hplayer:Ana-Royaume:6|h[Ana]|h dit : hello", 1, 1, 1)
chat1:AddMessage("|Hplayer:Ana-Royaume:7|h[Ana]|h salue tout le monde.", 1, 0.5, 0.25)
chat1:AddMessage("|Hplayer:Ana-Royaume:8|h[Ana]|h a rejoint le groupe.", 1, 1, 0)
chat1:AddMessage("À vendre : 3 piles de lin", 1, 1, 0)
-- ligne vraiment vue dans Forever (horodatage du jeu, canal raccourci, nom déjà coloré)
chat1:AddMessage("17:12 |Hchannel:channel:1|h[1]|h |Hplayer:Zlv Execute:2540:CHANNEL:1|h[|cffc69b6dZlv Execute|r]|h : LFM Sister rathtalon", 1, 0.75, 0.75)
local function tabHas(id, word)
    CW:SelectTab(id)
    return table.concat(lines(), "\n"):find(word, 1, true) ~= nil
end
check(tabHas("guild", "coucou") and tabHas("chat", "coucou"), "guilde (lien de canal du jeu) : Guilde et Chat")
check(tabHas("group", "go") and not tabHas("guild", "go"), "groupe, même avec l'heure devant : Groupe")
check(tabHas("whisper", "psst") and tabHas("whisper", "oui"), "chuchotements reçu et envoyé : Chuchot.")
check(tabHas("channel", "LFM"), "canal (|Hchannel:channel:) : Canaux")
check(tabHas("chat", "hello") and tabHas("chat", "salue"), "dire et émote : Chat")
check(not tabHas("chat", "Bienvenue") and not tabHas("chat", "rejoint") and not tabHas("chat", "vendre"),
    "système, même avec un lien de joueur ou « À » devant : pas dans Chat")
check(tabHas("game", "Bienvenue") and tabHas("game", "rejoint") and tabHas("game", "vendre") and not tabHas("game", "coucou"), "Jeu : le reste")
CW:SelectTab("channel")
local zlv = row()
chat1:AddMessage("17:27 |Hchannel:GUILD|h[G]|h |Hplayer:Raage Quit:3082:GUILD:|h[|cfffff468Raage Quit|r]|h : Bienvenue, Alli Kupina !", 0.2, 0.8, 0.2)
check(tabHas("guild", "Alli Kupina") and row().e.label == "Guilde" and row().e.time == "17:27", "canal de guilde raccourci « [G] » : Guilde quand même, heure du jeu")
CW:SelectTab("channel")
zlv = CW.rows[#CW.rows]
check(zlv.e.conv and zlv.e.author == "Zlv Execute" and zlv.e.body == "LFM Sister rathtalon" and zlv.e.label == "Canal 1",
    "ligne de Forever : auteur, texte et canal (raccourci : « Canal 1 ») lus dans le texte")
check(zlv.e.time == "17:12" and zlv.clock.text:GetText() == "17:12", "l'heure du jeu devant la ligne devient l'heure du message")
check(tostring(zlv.body:GetText()):find("|cffc69b6dZlv Execute|r", 1, true), "nom déjà coloré par le jeu : gardé")
CW:SelectTab("whisper")
check(row(1).e.conv and row(1).e.mine == false and row().e.inform and row().e.mine, "chuchotement reçu à gauche, envoyé (« À ») à droite")
CW:SelectTab("group")
local bob = row()
check(bob.e.time == "15:20" and tostring(bob.body:GetText()):find("|cff33ccffBob|r", 1, true), "nom sans couleur : bleu Platyplus ; heure [15:20] du jeu")
CW:SelectTab("chat")
check(#lines() == 9, "Chat : les 9 conversations (2 guilde, groupe, 2 chuchotements, 2 canaux, dire, émote)")

section("messages (mode compact : une ligne par message)")
ns:Set("chatWinTwoLines", false)
local DIM, TEXT, ORANGE = "|cff99a1b3", { 0.93, 0.94, 0.97 }, "|cffff7d0a"
say(chat1, "CHAT_MSG_GUILD", "salut leo, ça va ?", "Bob-Royaume", 101)
check(lastLine():find("|Hplayer:Bob%-Royaume:101|h%[" .. ORANGE .. "Bob|r%]|h"), "nom cliquable, dans la couleur de sa classe (sans l'option du jeu) : " .. lastLine())
check(lastLine():find("^|Haddon:Platyplus:copy:%d+|h" .. DIM .. "15:27|r|h |cff40ff40%[Guilde%]|r "), "heure grise puis [Guilde] dans la couleur du canal")
local tail = DIM .. " : |rsalut |cffffd133leo|r, ça va ?"
check(lastLine():sub(-#tail) == tail, "puis « : » gris et le texte, ton nom surligné")
local cr, cg = color(row())
check(math.abs(cr - TEXT[1]) < 0.01 and math.abs(cg - TEXT[2]) < 0.01, "texte en clair, pas dans la couleur du canal")
local n = count()
say(chat3, "CHAT_MSG_GUILD", "salut leo, ça va ?", "Bob-Royaume", 101)
check(count() == n, "même message reçu par une 2e fenêtre : pas de doublon")
say(chat1, "CHAT_MSG_GUILD", "tu viens ?", "Bob-Royaume", 102)
check(count() == n + 1 and lastLine():find("Bob", 1, true) and lastLine():find("tu viens ?", 1, true), "message suivant du même joueur : son nom quand même")
classColorInGame = true
say(chat1, "CHAT_MSG_GUILD", "allô ?", "Bob-Royaume", 103)
check(lastLine():find("|cffc79c6eBob|r", 1, true) and not lastLine():find(ORANGE, 1, true), "nom déjà coloré par le jeu : gardé tel quel")
classColorInGame = false
say(chat1, "CHAT_MSG_CHANNEL", "LFM Mortemines tank", "Jean-Royaume", 104, { [4] = "1. Général - Elwynn", [9] = "Général" })
check(lastLine():find("[Général]", 1, true) and not lastLine():find("Elwynn", 1, true), "canal : son nom court")
check(lastLine():find("|cff33ccffJean|r", 1, true), "classe inconnue : nom en bleu Platyplus")
say(chat1, "CHAT_MSG_WHISPER_INFORM", "j'arrive", "Bob-Royaume", 105)
check(lastLine():find("[Chuchote]", 1, true) and lastLine():find("à |r|Hplayer:Bob", 1, true), "chuchotement envoyé : « [Chuchote] à Bob »")
say(chat1, "CHAT_MSG_SAY", "bonjour", "Ana-Royaume", 106)
check(lastLine():find("[Dire]", 1, true) and lastLine():find("bonjour", 1, true), "dire : dans l'onglet Chat")
n = count()
chat1:AddMessage("Tu reçois du butin : [Lin]", 0, 0.7, 0)
check(count() == n, "message du jeu : pas dans l'onglet Chat")
chat2:AddMessage("Ton Coup de bouclier inflige 50", 1, 1, 1, 1, 0, 0, "CHAT_MSG_COMBAT_X", nil)
say(chat1, "CHAT_MSG_GUILD", SECRET, "Bob-Royaume", 107)
check(lastLine() == SECRET and row().e.cat == "guild" and row().kind == "secret",
    "message protégé : affiché tel que le jeu l'a écrit, dans l'onglet de son type (guilde, d'après l'événement)")

section("onglets")
CW:SelectTab("game")
local all = table.concat(lines(), "\n")
local loot
for _, r in ipairs(CW.rows) do if r.body:GetText() == "Tu reçois du butin : [Lin]" then loot = r end end
check(loot and select(2, color(loot)) == 0.7 and not loot.bubbleShown, "Jeu : le butin, sur une ligne, tel quel")
check(not all:find("Mortemines", 1, true) and not all:find("salut", 1, true), "Jeu : pas les conversations")
check(not all:find("Coup de bouclier", 1, true), "journal de combat : pas copié")
CW:SelectTab("guild")
all = table.concat(lines(), "\n")
check(all:find("salut", 1, true) and not all:find("Mortemines", 1, true) and not all:find("butin", 1, true), "Guilde : seulement la guilde")
check(all:find(SECRET, 1, true), "Guilde : le message protégé de guilde aussi")
say(chat1, "CHAT_MSG_WHISPER", "psst", "Ana-Royaume", 108)
local whisperTab, gameTab
for _, t in ipairs(CW.tabs) do if t.id == "whisper" then whisperTab = t elseif t.id == "game" then gameTab = t end end
check(tostring(whisperTab.label:GetText()):find("1", 1, true), "chuchotement reçu ailleurs : compteur sur son onglet")
chat1:AddMessage("Tu reçois du butin : [Laine]", 0, 0.7, 0)
check(gameTab.label:GetText() == "Jeu", "butin reçu ailleurs : pas de compteur sur Jeu")
CW:SelectTab("whisper")
check(not tostring(whisperTab.label:GetText()):find("1", 1, true), "compteur remis à zéro en ouvrant l'onglet")
CW:SelectTab("chat")
check(lastLine():find("psst", 1, true), "Chat : les chuchotements aussi")

section("recherche")
CW.frame.search:SetText("mortemines")
M.fire(CW.frame.search, "OnTextChanged")
check(count() == 1 and table.concat(lines(), "\n"):find("Mortemines", 1, true), "seulement les messages qui contiennent le mot")
CW.frame.search:SetText("introuvable")
M.fire(CW.frame.search, "OnTextChanged")
check(lastLine():find("Aucun message", 1, true), "rien trouvé : dit")
M.fire(CW.frame.search, "OnEscapePressed")
check(CW.search == "" and count() > 5, "Échap : tout revient")

section("liens")
local guildHeader
for _, l in ipairs(lines()) do if l:find("salut", 1, true) and l:find("copy:", 1, true) then guildHeader = l break end end
local guildCopy = guildHeader and guildHeader:match("|H(addon:Platyplus:copy:%d+)|h")
check(guildCopy ~= nil, "heure cliquable")
M.fire(CW.rows[1].box, "OnHyperlinkClick", guildCopy, "15:27", "LeftButton")
local copy = _G.PlatyplusCopy
check(copy and copy:IsShown() and tostring(copy.original):find("Bob : salut leo", 1, true), "clic sur l'heure : message prêt à copier")
M.fire(CW.rows[1].box, "OnHyperlinkClick", "player:Bob-Royaume:101", "[Bob]", "RightButton")
check(refs[#refs] == "player:Bob-Royaume:101", "clic sur un nom : géré par le jeu (menu, chuchoter)")

section("texte dans la couleur du canal")
ns:Set("chatWinChannelText", true)
check(color(row()) == 0.25 and select(2, color(row())) == 1, "texte dans la couleur du canal")
ns:Set("chatWinChannelText", false)

section("messages façon messagerie")
ns:Set("chatWinTwoLines", true)
local first
for i, r in ipairs(CW.rows) do if r.e and r.e.body == "salut |cffffd133leo|r, ça va ?" then first = i break end end
check(first ~= nil, "le message est affiché")
local b1 = CW.rows[first]
local t1, tail1 = tostring(b1.body:GetText()), "|cffc3c8d5 : |rsalut |cffffd133leo|r, ça va ?"
check(t1:find("^|Hplayer:Bob%-Royaume:101|h%[" .. ORANGE .. "Bob|r%]|h") and t1:sub(-#tail1) == tail1,
    "« Nom : texte » sur une seule ligne, nom cliquable et coloré : " .. t1)
check(b1.tag:IsShown() and b1.tag:GetText() == "Guilde", "canal en petit à droite (onglet Chat)")
check(b1.clock:IsShown() and b1.clock.text:GetText() == "15:27", "heure à droite")
check(select(1, b1.box:GetPoint(1)) == "BOTTOMLEFT" and b1.box:GetWidth() >= CW.viewW - 10, "message sur toute la largeur, sans bulle")
check(b1.bar and b1.backColor == nil and b1:GetHeight() == b1.box:GetHeight(), "barre du canal à gauche, pas de fond pour un message ordinaire")
local b2, b3 = CW.rows[first + 1], CW.rows[first + 2]
check(b2.e.body == "tu viens ?" and tostring(b2.body:GetText()):find("Bob", 1, true) and not b2.clock:IsShown() and not b2.tag:IsShown(),
    "message suivant du même joueur (moins d'une minute) : resserré, son nom mais ni heure ni canal")
check(b3.e.body == "allô ?" and not b3.clock:IsShown(), "3e message du même joueur dans la minute : sans heure non plus")
-- chaque ligne est posée sur celle d'en dessous : le décalage de son ancrage est l'espace qui les sépare
local gap1 = select(5, b1:GetPoint(1))
check(select(2, b1:GetPoint(1)) == b2 and gap1 <= 3.5, "les messages collés se suivent de près (posée sur la suivante, " .. tostring(gap1) .. " px)")
local b4 = CW.rows[first + 3]
check(tostring(b4.body:GetText()):find("Jean", 1, true) and b4.clock:IsShown() and b4.tag:GetText() == "Général", "autre joueur : son nom, l'heure et le canal")
check(select(2, b3:GetPoint(1)) == b4 and select(5, b3:GetPoint(1)) > gap1, "plus d'espace entre deux joueurs")
local mine
for _, r in ipairs(CW.rows) do if r.e and r.e.inform then mine = r end end
check(mine and select(1, mine.box:GetPoint(1)) == "BOTTOMLEFT" and mine.backColor ~= nil and tostring(mine.body:GetText()):find("à |r|Hplayer:Bob", 1, true),
    "chuchotement envoyé : fond teinté, « à Bob »")
CW:SelectTab("guild")
local g1
for _, r in ipairs(CW.rows) do if r.e and r.e.body == "salut |cffffd133leo|r, ça va ?" then g1 = r end end
check(g1 and not g1.tag:IsShown(), "onglet Guilde : le canal n'est pas répété à chaque message")
CW:SelectTab("chat")
n = count()
M.time = M.time + 100
say(chat1, "CHAT_MSG_WHISPER", "re", "Ana-Royaume", 109)
check(count() == n + 1 and row().e.body == "re" and row().clock:IsShown(), "plus d'une minute après : l'heure à nouveau")
say(chat1, "CHAT_MSG_WHISPER", "re re", "Ana-Royaume", 110)
check(count() == n + 2 and not row().clock:IsShown(), "dans la minute : seulement le message")
check(CW:Following() and CW.rows[#CW.rows].e.body == "re re", "la vue suit en bas")
section("noms longs de Forever (« Prénom Nom »)")
check(CW.ShortName("Glouglou Wavewisdom") == "Glouglou W." and CW.ShortName("Шишига Болотный") == "Шишига Б.",
    "nom long : « Prénom N. » (cyrillique compris) : " .. tostring(CW.ShortName("Шишига Болотный")))
check(CW.ShortName("Mr Deadson") == nil and CW.ShortName("Bob") == nil and CW.ShortName("Bartholomewsson") == nil, "nom court ou d'un seul mot : entier")
-- (sans nouveau message : la suite du test compte sur « re re » en bas)
local gl = tostring(CW.NameOf({ author = "Glouglou Wavewisdom",
    link = "|Hplayer:Glouglou Wavewisdom:111:WHISPER|h[|cff33ccffGlouglou Wavewisdom|r]|h" }))
check(gl == "|Hplayer:Glouglou Wavewisdom:111:WHISPER|h[|cff33ccffGlouglou W.|r]|h", "affiché « Glouglou W. », le lien garde le nom complet : " .. gl)
check(CW.NameOf({ author = "Bob", link = "|Hplayer:Bob:1|hBob|h" }) == "|Hplayer:Bob:1|hBob|h", "nom court : lien inchangé")
-- fenêtre de taille normale : la vue ne dessine que ce qui se voit, le plus récent en bas
CW.frame:SetSize(560, 230)
CW:Layout()
local total = #CW.list
check(#CW.rows < total and CW.rows[#CW.rows].e.body == "re re" and CW.moreAbove, "petite fenêtre : seuls les derniers messages sont dessinés (" .. #CW.rows .. "/" .. total .. "), le plus récent en bas")
M.fire(CW.view, "OnMouseWheel", 1)
check(CW.offset == 1 and CW.rows[#CW.rows].e.body == "re", "molette vers le haut : un message plus haut")
say(chat1, "CHAT_MSG_WHISPER", "là ?", "Ana-Royaume", 112)
check(CW.newBtn:IsShown() and CW.offset == 2 and CW.rows[#CW.rows].e.body == "re" and tostring(CW.newBtn.label:GetText()):find("1 nouveau", 1, true),
    "remonté dans l'historique : la vue ne bouge pas, « 1 nouveau message »")
M.fire(CW.rows[2].box, "OnMouseWheel", -1)
check(CW.offset == 1, "molette sur une bulle : la vue défile aussi")
M.fire(CW.newBtn, "OnClick")
check(not CW.newBtn:IsShown() and CW.offset == 0 and CW.rows[#CW.rows].e.body == "là ?", "clic : retour en bas, le nouveau message en bas")
for _ = 1, 200 do M.fire(CW.view, "OnMouseWheel", 1) end
check(not CW.moreAbove and CW.rows[1].e == CW.list[1] and CW.offset < total, "tout en haut : le plus ancien message en haut, ça s'arrête là")
M.fire(CW.view, "OnMouseWheel", -1)
check(CW.moreAbove, "et ça redescend")
CW:ScrollToBottom()
check(CW.offset == 0 and S(CW.thumb).shown, "barre de position affichée quand il y a plus haut")
CW.frame:SetSize(600, 4000)
CW:Layout()
M.fire(row().clock, "OnClick")
copy = _G.PlatyplusCopy
check(copy:IsShown() and tostring(copy.original):find("Ana : là ?", 1, true), "clic sur l'heure : message prêt à copier")

section("hauteur mal mesurée (retour du joueur : un long message déborde sur les suivants)")
-- au chargement, la police n'est pas toujours prête : la mesure rend une ligne alors que le texte en fait plusieurs
local realHeight = M.impl.GetStringHeight
M.impl.GetStringHeight = function(f) if f == CW.meter.body then return 15 end return realHeight(f) end
local long = string.rep("Recrute ! Rejoins une guilde PvE & PvP où la bonne humeur prime ! ", 6)
say(chat1, "CHAT_MSG_GUILD", long, "Lama-Royaume", 401)
M.impl.GetStringHeight = realHeight
local lr = row()
local shownH = lr.body:GetStringHeight()
check(lr.e.body == long and shownH > 40 and lr.h < shownH, "mesure fausse : ligne trop basse au départ (" .. lr.h .. " < " .. shownH .. ")")
M.advance(0.2)
lr = row()
check(lr.h >= shownH + 6 and lr:GetHeight() == lr.h and lr.box:GetHeight() == lr.h and (CW.stats.heightFixes or 0) >= 1,
    "une image plus tard : la ligne prend la hauteur du texte affiché (" .. lr.h .. ")")
local fixes = CW.stats.heightFixes
M.advance(5)
check(CW.stats.heightFixes == fixes, "puis plus rien à corriger (pas de boucle)")
ns:Set("chatWinTwoLines", false)

section("messages protégés au milieu des autres (retour du joueur : messages qui manquaient, défilement cassé)")
-- dans Forever, un texte qui a affiché une valeur protégée garde une marque « secret » et ses mesures deviennent
-- protégées elles aussi : le simulateur fait pareil (mesurer un tel texte rend une valeur protégée)
local marked = setmetatable({}, { __mode = "k" })
local baseSetText, baseHeight, baseWidth = M.impl.SetText, M.impl.GetStringHeight, M.impl.GetStringWidth
M.impl.SetText = function(f, t) if t == SECRET then marked[f] = true end return baseSetText(f, t) end
M.impl.GetStringHeight = function(f) if marked[f] then return SECRET end return baseHeight(f) end
M.impl.GetStringWidth = function(f) if marked[f] then return SECRET end return baseWidth(f) end
M.impl.ClearText = function(f) marked[f] = nil; S(f).text = "" end
ns:Set("chatWinTwoLines", true)
CW:SelectTab("group")
for k = 1, 6 do say(chat1, "CHAT_MSG_PARTY", SECRET, "Bob-Royaume", 300 + k, nil, 0.67, 0.67, 1) end
local secretRows = 0
for _, r in ipairs(CW.rows) do if r.kind == "secret" then secretRows = secretRows + 1 end end
check(secretRows >= 6 and row().kind == "secret" and row().body:GetText() == SECRET, "messages de groupe protégés : dans Groupe, tels quels")
check(row().bubble and #M.errors == 0, "dans une bulle (conversation, d'après l'événement)")
local sr = row()
check(select(1, sr.body:GetPoint(1)) == "BOTTOMLEFT" and select(1, sr:GetPoint(1)) == "BOTTOMRIGHT" and select(2, sr:GetPoint(2)) == sr.body,
    "ligne protégée : posée sur la précédente, sa hauteur suit son texte (aucune mesure)")
say(chat1, "CHAT_MSG_PARTY", "on y va ?", "Bob-Royaume", 320, nil, 0.67, 0.67, 1)
check(row().e.body == "on y va ?" and row().kind == "bubble" and #M.errors == 0 and (CW.stats.drawErrors or 0) == 0,
    "message lisible après des protégés : affiché, sans erreur de dessin")
CW:SelectTab("chat")
CW:SelectTab("group")
local drawn = {}
for _, r in ipairs(CW.rows) do drawn[#drawn + 1] = r.e end
check(#drawn == #CW.list and drawn[#drawn].body == "on y va ?" and (CW.stats.drawErrors or 0) == 0,
    "on change d'onglet et on revient : tous les messages sont redessinés (" .. #drawn .. "/" .. #CW.list .. ")")
-- même message reçu par deux fenêtres du jeu : une seule fois ; même fenêtre deux fois de suite : deux messages
local n0 = #CW.store
chat1:AddMessage("Vous ramassez 46 Cuivre", 1, 1, 0, 1, 0, 0, "CHAT_MSG_MONEY", nil)
chat3:AddMessage("Vous ramassez 46 Cuivre", 1, 1, 0, 1, 0, 0, "CHAT_MSG_MONEY", nil)
chat1:AddMessage("Vous ramassez 46 Cuivre", 1, 1, 0, 1, 0, 0, "CHAT_MSG_MONEY", nil)
check(#CW.store == n0 + 2, "butin identique deux fois de suite : les deux ; la copie d'une autre fenêtre : écartée")
local n1 = #CW.store
chat1:AddMessage(SECRET, 0.67, 0.67, 1, 1, 0, 0, "CHAT_MSG_PARTY", args(SECRET, SECRET, SECRET))
chat3:AddMessage(SECRET, 0.67, 0.67, 1, 1, 0, 0, "CHAT_MSG_PARTY", args(SECRET, SECRET, SECRET))
check(#CW.store == n1 + 1 and #M.errors == 0, "message protégé reçu par deux fenêtres : une seule fois")
-- sans événement : la couleur de la ligne dit son type
chat1:AddMessage(SECRET, 1, 0.5, 1)
check(CW.store[#CW.store].cat == "whisper", "message protégé sans événement : la couleur dit l'onglet (chuchotement)")
M.impl.SetText, M.impl.GetStringHeight, M.impl.GetStringWidth = baseSetText, baseHeight, baseWidth
M.impl.ClearText = nil
ns:Set("chatWinTwoLines", false)
CW:SelectTab("chat")

section("couper / rallumer")
ns:Set("chatWindow", false)
check(chat1:GetParent() == UIParent and _G.ChatFrame1Tab:GetParent() == UIParent, "coupé : fenêtres du jeu remises")
check(chat1.editBox:GetParent() == chat1 and select(2, chat1.editBox:GetPoint(1)) == chat1, "coupé : zone de saisie remise à sa place")
check(not CW.frame:IsShown(), "coupé : fenêtre Platyplus cachée")
ns:Set("chatWindow", true)
check(CW.frame:IsShown() and not chat1:IsVisible(), "rallumé")

section("fenêtre de chuchotement créée plus tard")
local chat11 = chatFrame("ChatFrame11")
CHAT_FRAMES[#CHAT_FRAMES + 1] = "ChatFrame11"
FCF_OpenTemporaryWindow("WHISPER", "Ana")
check(not chat11:IsVisible(), "rangée elle aussi")
say(chat11, "CHAT_MSG_WHISPER", "toujours là ?", "Ana-Royaume", 111)
check(lastLine():find("[Chuchote]", 1, true) and lastLine():find("toujours là ?", 1, true), "ses messages arrivent dans la fenêtre Platyplus")

section("journal gardé par Platyplus entre deux /reload")
ns:Set("chatWinTwoLines", true)
local saved = PlatyplusDB.chatWinLog and PlatyplusDB.chatWinLog["Leo-Royaume"]
check(type(saved) == "table" and #saved > 10, "journal écrit au fil de l'eau pour ce personnage : " .. tostring(saved and #saved))
local hasSecret = false
for _, rec in ipairs(saved or {}) do for _, v in pairs(rec) do if v == SECRET then hasSecret = true end end end
check(not hasSecret, "aucune valeur protégée dans le journal")
local status = table.concat(CW:Status(), " | ")
check(status:find("journal sauvé pour ce personnage : " .. #saved, 1, true) and status:find("lus dans le texte", 1, true), "/pp chat : état : " .. status)
-- journal d'une version précédente : repris si le journal est vide, puis effacé
local keep = PlatyplusDB.chatWinLog["Leo-Royaume"]
PlatyplusDB.chatWinLog["Leo-Royaume"] = {}
PlatyplusDB.chatWinHistory = { { raw = "|Hchannel:GUILD|h[Guilde]|h |Hplayer:Vieux-Royaume:1|h[Vieux]|h : d'une vieille version", r = 0.25, g = 1, b = 0.25, day = "2026-11-04", cat = "guild", time = "12:00" } }
CW.detached = true   -- (l'instance précédente reste accrochée aux fenêtres du simulateur : on la débranche)
local nsM = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
nsM.ChatWindow:SelectTab("guild")
check(nsM.ChatWindow.rows[1].e.author == "Vieux-Royaume" and nsM.ChatWindow.rows[1].clock.text:GetText() == "04/11 12:00" and PlatyplusDB.chatWinHistory == nil,
    "ancien journal (chatWinHistory) repris dans le nouveau, puis effacé")
PlatyplusDB.chatWinLog["Leo-Royaume"] = keep
-- nouveau chargement (comme après /reload) : fenêtres du jeu vides, le lendemain
def("date", function(fmt) if fmt == "%Y-%m-%d" then return "2026-11-06" end return "09:00" end)
nsM.ChatWindow.detached = true
local ns2 = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
local CW2 = ns2.ChatWindow
CW2:SelectTab("guild")
local found, seen = nil, {}
for _, r in ipairs(CW2.rows) do seen[#seen + 1] = tostring(r.body:GetText()) end
check(table.concat(seen, "\n"):find("salut |cffffd133leo", 1, true), "après rechargement : la guilde d'hier est là")
check(table.concat(seen, "\n"):find("session précédente", 1, true) and CW2.rows[#CW2.rows].e.divider, "un séparateur « session précédente » en bas")
check(not table.concat(seen, "\n"):find("Mortemines", 1, true), "Guilde : toujours seulement la guilde")
local gi
for i, r in ipairs(CW2.rows) do if r.e.body == "salut |cffffd133leo|r, ça va ?" then gi = i end end
local g2 = gi and CW2.rows[gi + 1]
check(g2 and g2.e.body == "tu viens ?" and not g2.clock:IsShown() and g2.e.stamp < 0 and CW2.rows[gi].e.stamp < 0, "Guilde : « tu viens ? » suit « salut » à la même minute d'hier : collé, sans en-tête")
CW2:SelectTab("chat")
for _, r in ipairs(CW2.rows) do if r.e and r.e.body == "salut |cffffd133leo|r, ça va ?" then found = r end end
check(found and found.clock.text:GetText() == "05/11 15:27", "message d'un autre jour : la date devant l'heure : " .. tostring(found and found.clock.text:GetText()))
check(found and tostring(found.body:GetText()):find("|Hplayer:Bob", 1, true), "nom toujours coloré et cliquable")
CW2:SelectTab("game")
seen = {}
for _, r in ipairs(CW2.rows) do seen[#seen + 1] = tostring(r.body:GetText()) end
check(table.concat(seen, "\n"):find("butin", 1, true), "Jeu : le butin d'hier aussi")
CW2:SelectTab("channel")
seen = {}
for _, r in ipairs(CW2.rows) do seen[#seen + 1] = tostring(r.e.author) end
check(table.concat(seen, "\n"):find("Zlv Execute", 1, true), "Canaux : la ligne de Forever relue d'après son texte")
local n2 = #CW2.store
say(chat1, "CHAT_MSG_GUILD", "re-bonjour", "Bob-Royaume", 201)
check(#CW2.store == n2 + 1 and #PlatyplusDB.chatWinLog["Leo-Royaume"] >= #saved, "un nouveau message s'ajoute au journal")
CW = CW2

M.report()
if #failures > 0 or #M.errors > 0 then
    M.realPrint("ÉCHECS : " .. #failures)
    os.exit(1)
end
M.realPrint("tout est bon")
