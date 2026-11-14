-- Platyplus : prépare le jeu pour le traducteur (ns.Trad)
--  * le traducteur est un programme à part (Traducteur\Traducteur.pyw) : un add-on n'a ni Internet ni IA,
--    il ne peut pas traduire lui-même
--  * option « tradChatLog » : lien [FR] au bout des messages reçus en langue étrangère ; un clic et le programme
--    affiche la traduction (bande de pixels, voir plus bas) ; clic droit : zone à copier (Ctrl+C), au cas où
--  * elle allume aussi le journal du chat (Logs\WoWChatLog.txt, lu par le programme) au cas où le jeu l'écrirait
--    un jour pendant la partie : Forever ne l'écrit pas (vu en jeu le 06/11/2026)
--  * le nom de tes personnages est noté (tradPersos) pour que le programme ne traduise pas tes propres messages
--  LoggingChat existe dans Forever (vérifié dans le code de Forever : Blizzard_ChatFrameBase\Shared\SlashCommands.lua,
--  commande /chatlog). Qu'un add-on ait le droit de l'appeler : NON VÉRIFIÉ en jeu (d'où les pcall).
local ADDON, ns = ...

local T = {}
ns.Trad = T

local function api(name) return rawget(_G, name) end

local function isLogging()
    local LoggingChat = api("LoggingChat")
    if type(LoggingChat) ~= "function" then return nil end
    local ok, on = pcall(LoggingChat)
    if ok then return on and true or false end
    return nil
end

-- allume (ou éteint, si c'est nous qui l'avions allumé) le journal du chat ; renvoie l'état du journal
function T:Apply()
    local LoggingChat = api("LoggingChat")
    if type(LoggingChat) ~= "function" then return nil end
    if ns.db.tradChatLog then
        if not isLogging() then
            pcall(LoggingChat, true)
            T.startedByUs = isLogging() and true or false
        end
    elseif T.startedByUs then
        pcall(LoggingChat, false)
        T.startedByUs = false
    end
    return isLogging()
end

---------------------------------------------------------------------------
-- Clic pour traduire
-- Vu en jeu le 06/11/2026 : Forever crée Logs\WoWChatLog.txt mais n'y écrit rien pendant la partie (0 octet après
-- 20 minutes de chat, même en éteignant et rallumant le journal). Le programme ne peut donc pas lire le chat tout seul.
-- À la place : un lien [FR] au bout des messages reçus. Un clic ouvre une petite zone avec « Nom › message »
-- sélectionné ; Ctrl+C le copie, le programme voit la copie faite dans le jeu et affiche la traduction.
-- (CopyToClipboard est réservé à Blizzard dans Forever : HasRestrictions. D'où le Ctrl+C.)
-- Vérifié dans le code de Forever (Misc.lua, ns.Chat, même mécanisme pour les liens web) : ChatFrameUtil.
-- AddMessageEventFilter, liens « addon: », clic -> EventRegistry « SetItemRef ». Les messages protégés (secrets)
-- ne passent pas par les filtres : pas de lien sur eux.
---------------------------------------------------------------------------
local LINK_PREFIX = "addon:Platyplus:trad:"
local LINK_LABEL = "|cff6fb8ff[FR]|r"
local SEPARATOR = " › "      -- le programme reconnaît « Nom › message »
local MAX_LINES = 300
local CHAT_EVENTS = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL",
}
-- mots qui n'existent qu'en français (« de », « la », « que », « tu », « mais », « bien », « du »... existent aussi
-- en espagnol, portugais, italien ou allemand : pas dans la liste)
local FRENCH_WORDS = {}
for w in ([[je nous vous est les une pour pas avec moi toi oui merci salut bonjour bonsoir coucou stp svp c'est
    j'ai ça quoi aussi très ici dans et cette tout peux veux fais suis mdr ptdr jsp chui wesh dsl tkt]]):gmatch("%S+") do
    FRENCH_WORDS[w] = true
end

T.lines, T.byLine, T.count = {}, {}, 0

local function isSecret(v)
    local f = api("issecretvalue")
    if type(f) ~= "function" then return false end
    local ok, s = pcall(f, v)
    return ok and s and true or false
end

local function plain(text)
    if ns.Chat and ns.Chat.CleanLine then return ns.Chat.CleanLine(text) or text end
    return text
end

-- vrai si le message a l'air écrit en français (un mot qui n'existe qu'en français suffit)
function T.LooksFrench(msg)
    for word in plain(msg):lower():gmatch("[%a\128-\255']+") do
        if FRENCH_WORDS[word] then return true end
    end
    return false
end

-- un message montré dans plusieurs fenêtres de chat passe plusieurs fois par le filtre : même numéro (lineID)
local function remember(author, msg, lineID)
    if type(lineID) ~= "number" or isSecret(lineID) then lineID = nil end
    if lineID and T.byLine[lineID] then return T.byLine[lineID] end
    T.count = T.count + 1
    local id = T.count
    T.lines[id] = { author = author, text = msg, lineID = lineID }
    local old = T.lines[id - MAX_LINES]
    if old then
        if old.lineID then T.byLine[old.lineID] = nil end
        T.lines[id - MAX_LINES] = nil
    end
    if lineID then T.byLine[lineID] = id end
    return id
end

-- filtre du chat : ajoute [FR] au bout d'un message reçu qui n'a pas l'air en français
-- arguments après msg : auteur(1) ... lineID(10), guid(11) ; il faut tous les renvoyer
local function tradFilter(_, _, msg, ...)
    if not (ns.db and ns.db.tradChatLog) then return false end
    if type(msg) ~= "string" or isSecret(msg) or msg:find(LINK_PREFIX, 1, true) then return false end
    local author, guid = ..., select(11, ...)
    if isSecret(author) or isSecret(guid) then return false end
    local me = api("UnitGUID") and UnitGUID("player")
    if guid and me and not isSecret(me) and guid == me then return false end
    local text = plain(msg)
    if not text:find("%a%a") or T.LooksFrench(text) then return false end
    if type(author) ~= "string" or author == "" then
        author = "?"
    else
        if api("Ambiguate") then author = Ambiguate(author, "none") end
        author = plain(author)   -- nom Battle.net protégé (|K) -> « ? »
    end
    local id = remember(author, text, select(10, ...))
    return false, msg .. " |H" .. LINK_PREFIX .. id .. "|h" .. LINK_LABEL .. "|h", ...
end
T.Filter = tradFilter

-- petite zone de copie, près du clic
local box
local function buildBox()
    local W, TH = ns.W, ns.THEME
    local f = CreateFrame("Frame", "PlatyplusTradCopy", UIParent)
    f:SetSize(480, 62)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    if W and W.Round then
        W.Round(f, "BACKGROUND", -6, 10):SetColor(W.C.bg)
        W.Stroke(f, "BORDER", 0, 10):SetColor(W.C.white, 0.12)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetColorTexture(0.08, 0.09, 0.11, 0.97)
    end
    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    if TH and TH.accent then hint:SetTextColor(TH.accent[1], TH.accent[2], TH.accent[3]) end
    hint:SetText(ns.T("Ctrl+C : traduire   ·   Échap : fermer"))
    local edit = CreateFrame("EditBox", nil, f)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -28)
    edit:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 8)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnEnterPressed", function() f:Hide() end)
    edit:SetScript("OnEditFocusLost", function() f:Hide() end)
    -- lecture seule : toute frappe remet le texte, sélectionné
    edit:SetScript("OnTextChanged", function(self, user)
        if user and f.original then
            self:SetText(f.original)
            self:HighlightText()
        end
    end)
    -- Ctrl+C : le jeu copie, puis on ferme (un peu après, pour ne pas couper la copie)
    edit:SetScript("OnKeyDown", function(_, key)
        if key == "C" and IsControlKeyDown() then
            C_Timer.After(0.15, function() f:Hide() end)
        end
    end)
    f.edit = edit
    if UISpecialFrames then table.insert(UISpecialFrames, "PlatyplusTradCopy") end
    return f
end

function T:ShowCopy(line)
    box = box or buildBox()
    box.original = (line.author or "?") .. SEPARATOR .. (line.text or "")
    box:ClearAllPoints()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if x and y and scale and scale > 0 then
        box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale - 40, y / scale + 14)
    else
        box:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
    end
    box.edit:SetText(box.original)
    box:Show()
    box:Raise()
    box.edit:SetFocus()
    box.edit:SetCursorPosition(0)
    box.edit:HighlightText()
    return box
end

---------------------------------------------------------------------------
-- Clic sur [FR] : le message part au programme par une bande de pixels
-- Un add-on ne peut ni écrire un fichier, ni copier, ni parler à un autre programme. Il peut dessiner : pendant
-- 0,6 s, une fine bande de carrés de couleur (3 pixels de côté, 3 rangées de 256 au plus) en haut à gauche de
-- l'écran code « Nom › message ». Le programme regarde ce coin de l'écran (capture, rien n'est envoyé au jeu),
-- lit la bande et traduit. Le même format est lu par Traducteur\trad\bande.py :
--  * carrés 1-3 : balise magenta, vert, magenta ; 4-7 : gris d'étalonnage (niveaux 0, 85, 170, 255) ;
--  * puis chaque octet en 2 carrés (4 bits chacun) : rouge = 2 bits forts, vert = 2 bits faibles (niveaux ci-dessus),
--    bleu = numéro du carré modulo 4 (contrôle d'alignement) ;
--  * octets : numéro du message, longueur (2 octets), le texte en UTF-8 (250 octets au plus), somme modulo 256.
-- Vérifié dans le code de Forever : ConvertPixelsToUI (PixelUtilSecure.lua) = pixels * 768 / (hauteur physique
-- de l'écran * échelle du cadre) ; GetPhysicalScreenSize, SetIgnoreParentAlpha / SetIgnoreParentScale existent.
---------------------------------------------------------------------------
local STRIP_CELL, STRIP_ROW, STRIP_TIME, STRIP_MAX = 3, 256, 0.6, 250
local LEVELS = { 0, 85 / 255, 170 / 255, 1 }
local strip, stripTex, stripId = nil, {}, 0

-- coupe à n octets sans casser une lettre accentuée (UTF-8)
local function utf8Cut(s, n)
    if #s <= n then return s end
    local cut = n
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end   -- l'octet suivant commence une lettre : on coupe là
        cut = cut - 1
    end
    return s:sub(1, cut)
end

-- liste des carrés {r, g, b} pour ce texte (exposée pour les tests)
function T.StripCells(payload, id)
    local bytes = { id, math.floor(#payload / 256), #payload % 256 }
    for i = 1, #payload do bytes[#bytes + 1] = payload:byte(i) end
    local sum = 0
    for _, b in ipairs(bytes) do sum = sum + b end
    bytes[#bytes + 1] = sum % 256
    local cells = { { 1, 0, 1 }, { 0, 1, 0 }, { 1, 0, 1 } }
    for k = 1, 4 do cells[#cells + 1] = { LEVELS[k], LEVELS[k], LEVELS[k] } end
    local k = 0
    for _, b in ipairs(bytes) do
        for _, n in ipairs({ math.floor(b / 16), b % 16 }) do
            cells[#cells + 1] = { LEVELS[math.floor(n / 4) + 1], LEVELS[n % 4 + 1], LEVELS[k % 4 + 1] }
            k = k + 1
        end
    end
    return cells
end

function T:SendStrip(line, duration)
    local payload = utf8Cut((line.author or "?") .. SEPARATOR .. (line.text or ""), STRIP_MAX)
    stripId = stripId % 255 + 1
    local cells = T.StripCells(payload, stripId)
    if not strip then
        strip = CreateFrame("Frame", "PlatyplusTradStrip", UIParent)
        strip:SetFrameStrata("TOOLTIP")
        strip:SetFrameLevel(5000)
        if strip.SetIgnoreParentAlpha then strip:SetIgnoreParentAlpha(true) end
        strip:EnableMouse(false)
    end
    local _, physH = GetPhysicalScreenSize()
    local scale = strip:GetEffectiveScale()
    if not (physH and physH > 0 and scale and scale > 0) then return false end
    local u = STRIP_CELL * 768 / (physH * scale)     -- un carré = 3 vrais pixels
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    strip:SetSize(math.min(#cells, STRIP_ROW) * u, math.ceil(#cells / STRIP_ROW) * u)
    for i, c in ipairs(cells) do
        local t = stripTex[i]
        if not t then
            t = strip:CreateTexture(nil, "OVERLAY")
            stripTex[i] = t
        end
        local idx = i - 1
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", strip, "TOPLEFT", (idx % STRIP_ROW) * u, -math.floor(idx / STRIP_ROW) * u)
        t:SetSize(u, u)
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:Show()
    end
    for i = #cells + 1, #stripTex do stripTex[i]:Hide() end
    strip:Show()
    local mine = stripId
    C_Timer.After(duration or STRIP_TIME, function()
        if stripId == mine then strip:Hide() end
    end)
    return true
end

-- clic gauche sur [FR] : traduction directe ; clic droit : la petite zone à copier (Ctrl+C), au cas où
local function onSetItemRef(_, link, _, button)
    if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return end
    local line = T.lines[tonumber(link:sub(#LINK_PREFIX + 1)) or 0]
    if not line then
        ns:Print("traducteur : message trop ancien pour être traduit.")
    elseif button == "RightButton" then
        T:ShowCopy(line)
    else
        T:SendStrip(line)
    end
end

local filtersOn, clickHooked = false, false
function T:ApplyLinks()
    local util = api("ChatFrameUtil")
    local want = ns.db.tradChatLog and true or false
    if util and util.AddMessageEventFilter and want ~= filtersOn then
        for _, event in ipairs(CHAT_EVENTS) do
            if want then
                pcall(util.AddMessageEventFilter, event, tradFilter)
            elseif util.RemoveMessageEventFilter then
                pcall(util.RemoveMessageEventFilter, event, tradFilter)
            end
        end
        filtersOn = want
    end
    local registry = api("EventRegistry")
    if want and not clickHooked and registry and registry.RegisterCallback then
        clickHooked = pcall(registry.RegisterCallback, registry, "SetItemRef", onSetItemRef, T) and true or false
    end
end

function T:NotePlayer()
    local UnitName, issecretvalue = api("UnitName"), api("issecretvalue")
    local name = UnitName and UnitName("player")
    if issecretvalue and issecretvalue(name) then return end
    if type(name) ~= "string" or name == "" then return end
    ns.db.tradPersos = ns.db.tradPersos or {}
    ns.db.tradPersos[name] = true
end

function T:Status()
    local on = isLogging()
    local etat
    if on == nil then
        etat = ns.T("|cffff4040le jeu ne dit pas si le journal est allumé|r")
    elseif on then
        etat = ns.T("|cff00ff00journal du chat allumé|r (Logs\\WoWChatLog.txt)")
    else
        etat = ns.T("|cffff4040journal du chat éteint|r")
    end
    return etat
end

-- /pp trad [on|off]
function T:Command(arg)
    arg = (arg or ""):lower()
    if arg == "test" then
        -- bande d'essai affichée 8 s : le traducteur doit afficher « c'est un test de Platyplus »
        local ok = T:SendStrip({ author = "Platyplus", text = "this is a Platyplus test" }, 8)
        ns:Print(ok and "bande d'essai affichée 8 s en haut à gauche : le traducteur doit afficher sa traduction."
            or "bande d'essai impossible (taille de l'écran inconnue).")
        return
    end
    local want
    if arg == "on" or arg == "1" then want = true
    elseif arg == "off" or arg == "0" then want = false
    elseif arg == "etat" or arg == "état" then want = nil
    else want = not ns.db.tradChatLog end
    if want ~= nil then ns:Set("tradChatLog", want) end
    if ns.db.tradChatLog then
        ns:Print("traducteur : |cff00ff00ON|r -", self:Status())
        ns:Print(ns.Tf("lance « Traducteur Platyplus » (raccourci sur le bureau) : il s'affiche par-dessus le jeu. Clic sur %s au bout d'un message : traduction. |cffffff00Ctrl+Entrée|r : écrire dans une autre langue.", LINK_LABEL))
    else
        ns:Print("traducteur : |cffff4040OFF|r -", self:Status())
    end
end

function T:Init()
    ns:OnChange("tradChatLog", function() T:Apply() end)
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event)
        T:NotePlayer()
        T:Apply()
        if event == "PLAYER_LOGIN" then f:UnregisterEvent("PLAYER_LOGIN") end
    end)
    ns:OnChange("tradChatLog", function() T:ApplyLinks() end)
    T:ApplyLinks()
end
