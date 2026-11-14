-- Platyplus : fenêtre de chat (ns.ChatWindow), à la place des fenêtres de chat de Blizzard
--  * une fenêtre Platyplus (déplaçable par son bandeau, redimensionnable par son coin) : onglets Chat / Guilde /
--    Groupe / Chuchot. / Canaux / Jeu avec le nombre de messages non lus, recherche, bouton « nouveaux messages »
--  * Chat : ce que les joueurs disent (dire, crier, guilde, groupe, chuchotements, canaux) ; Jeu : le reste
--    (butin, expérience, système, messages des addons) pour ne pas noyer les conversations
--  * façon messagerie : une bulle par message (fond arrondi), nom (couleur de classe, cliquable comme d'habitude)
--    et canal en petit au-dessus, heure à droite, le texte en clair en dessous ; mes messages à droite, en bleu ;
--    les messages qui se suivent du même joueur sur le même canal (moins d'une minute) se collent sans en-tête ;
--    option « compact » (chatWinTwoLines coupé) : une ligne par message « 15:27 [Guilde] Bob : salut »
--  * les lignes du jeu (butin, système) : simple texte, dans leur couleur
--  * clic sur l'heure d'une bulle (ou clic droit dessus) : copier le message (Ctrl+C)
--  * l'historique revient après un /reload (journal Platyplus, messages protégés exclus, jour ajouté à l'heure)
--  * la zone de saisie reste celle du jeu (les commandes /cast, /target... tapées marchent comme avant), posée en bas
--
-- Comment : chaque fenêtre de chat de Blizzard reçoit les messages comme d'habitude (ses réglages de canaux restent
-- valables) puis les ajoute avec cadre:AddMessage(texte formaté, r, g, b, id, accès, type, événement, arguments) ;
-- un hooksecurefunc sur AddMessage les recopie ici. La ligne est lue d'après son texte formaté (CHAT_<TYPE>_GET,
-- lien du joueur) ; quand Forever passe aussi l'événement et ses arguments, ils sont préférés (GUID, icônes).
-- Les 300 dernières lignes lisibles sont écrites au fur et à mesure dans PlatyplusDB.chatWinLog[Nom-Royaume] et
-- relues au chargement (Forever ne remet pas l'historique des fenêtres de chat après un /reload). /pp chat : état.
-- Les fenêtres de Blizzard sont rangées dans un cadre caché (SetParent : rien de Blizzard n'est remplacé) et remises
-- à leur place si l'option est coupée.
--
-- Réécrite le 2026-11-07 (retour du joueur : « il affiche pas tout le temps les messages, des fois on peut pas
-- scroll... il faut le revoir intégralement, la DA est cool ») ; l'apparence est gardée, la mécanique change :
--  * messages protégés (valeurs secrètes : en donjon, en rencontre...) : dans Forever, SetText(valeur secrète) pose
--    sur le texte une marque « secret » qui RESTE (SimpleFontStringAPI : SecretArgumentsAddAspect ; seuls ClearText
--    et SetToDefaults l'enlèvent) et ses mesures (GetStringHeight/Width) deviennent secrètes. L'ancienne vue
--    réutilisait ses lignes : après un message protégé, mesurer une ligne réutilisée plantait, le message ne
--    s'affichait pas et le rendu s'arrêtait là (tous les suivants manquaient, hauteur fausse, défilement cassé).
--    Maintenant les messages protégés ont leurs propres lignes, jamais mesurées : leur hauteur est laissée au jeu
--    (chaque ligne est ancrée sur la précédente, pas placée par un calcul). Et ils vont dans l'onglet de leur type
--    (l'événement passé par Forever n'est pas secret ; sinon la couleur de la ligne), plus « partout ».
--  * défilement : plus de ScrollFrame (plage recalculée une image plus tard, hauteur du contenu à tenir juste) :
--    la vue part du bas et défile par message, comme la fenêtre de chat du jeu. Une zone qui coupe ce qui dépasse,
--    les messages empilés du plus récent (en bas) vers les plus anciens ; seuls ceux qui se voient sont dessinés.
--  * doublons : un message n'est écarté que s'il revient d'une AUTRE fenêtre du jeu (avant : même texte dans la même
--    seconde = écarté, donc « Vous ramassez 46 Cuivre » deux fois de suite n'en montrait qu'un).
-- Vérifié dans le code de Forever : ChatFrameOverrides.lua (MessageEventHandler -> AddMessage(..., event, eventArgs) avec
-- eventArgs = SafePack(arguments de l'événement)), ChatFrame.lua (ChatFrameMixin:AddMessage), FloatingChatFrame.xml
-- (zone de saisie : enfant de sa fenêtre), LinkUtil.lua (GetPlayerLink), ChatFrameUtil.GetDecoratedSenderName (nom
-- coloré par classe seulement si l'option du jeu est cochée : sinon on le colore nous-mêmes avec GetPlayerInfoByGUID +
-- RAID_CLASS_COLORS), doc API générée (aspects secrets des FontString, ClearText).
-- NON VÉRIFIÉ en jeu : qu'un cadre puisse s'ancrer sur son propre texte (ligne protégée : cadre posé sur son texte,
-- texte posé sur la ligne d'en dessous) ; en cas de refus, la ligne protégée prend une hauteur fixe (3 lignes au plus).
local ADDON, ns = ...

local CW = { store = {}, seen = {}, seenCount = 0, unread = {}, tab = "chat", search = "" }
ns.ChatWindow = CW

local floor, max, min = math.floor, math.max, math.min

local function api(name) return rawget(_G, name) end
local function db(key) return ns.db and ns.db[key] end

local function readable(v)
    if ns.ChatPlus and ns.ChatPlus.Readable then return ns.ChatPlus.Readable(v) end
    local secret = api("issecretvalue")
    return not (secret and secret(v))
end

local function try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        ns:Debug("fenêtre de chat (" .. where .. ") :", err)
        if not CW.warned then
            CW.warned = true
            ns:Print("fenêtre de chat : une erreur à l'affichage (" .. where .. ") ; /pp debug on pour le détail")
        end
    end
    return ok, err
end

local function hex(c)
    return string.format("%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end
local function paint(c, text) return "|cff" .. hex(c) .. text .. "|r" end

local MAX_STORE = 1000     -- messages gardés en mémoire (session)
local MAX_SHOW = 500       -- messages affichés par onglet
local GROUP_WINDOW = 60    -- secondes : messages qui se suivent sans répéter l'en-tête (mode aéré)
local GAME = "game"        -- onglet Jeu : tout ce qui n'est pas une conversation
local COPY_PREFIX = "addon:Platyplus:copy:"
local URL_PREFIX = "addon:Platyplus:url:"

---------------------------------------------------------------------------
-- Types de messages
---------------------------------------------------------------------------
CW.TABS = {
    { id = "chat", label = "Chat" },
    { id = "guild", label = "Guilde" },
    { id = "group", label = "Groupe" },
    { id = "whisper", label = "Chuchot." },
    { id = "channel", label = "Canaux" },
    { id = GAME, label = "Jeu" },
}

-- type (après CHAT_MSG_) -> { onglet, libellé, conversation (nom + message) }
-- (onglet "chat" : dans l'onglet Chat seulement ; les conversations des autres onglets y sont aussi)
local KIND = {
    SAY = { "chat", "Dire", true }, YELL = { "chat", "Crier", true }, EMOTE = { "chat", "Émote", true },
    GUILD = { "guild", "Guilde", true }, OFFICER = { "guild", "Officiers", true },
    GUILD_ACHIEVEMENT = { "guild" }, GUILD_ITEM_LOOTED = { "guild" },
    PARTY = { "group", "Groupe", true }, PARTY_LEADER = { "group", "Chef de groupe", true },
    RAID = { "group", "Raid", true }, RAID_LEADER = { "group", "Chef de raid", true },
    RAID_WARNING = { "group", "Alerte raid", true },
    INSTANCE_CHAT = { "group", "Instance", true }, INSTANCE_CHAT_LEADER = { "group", "Chef d'instance", true },
    WHISPER = { "whisper", "Chuchote", true }, WHISPER_INFORM = { "whisper", "Chuchote", true },
    BN_WHISPER = { "whisper", "Battle.net", true }, BN_WHISPER_INFORM = { "whisper", "Battle.net", true },
    CHANNEL = { "channel", nil, true },
    CHANNEL_JOIN = { "channel" }, CHANNEL_LEAVE = { "channel" }, CHANNEL_NOTICE = { "channel" },
}
CW.KIND = KIND

-- couleur de classe d'un joueur (GUID de l'auteur), comme ChatFrameUtil.GetDecoratedSenderName le fait quand
-- l'option du jeu est cochée ; nil si on ne sait pas
local function classColor(guid)
    if type(guid) ~= "string" or guid == "" or not readable(guid) then return nil end
    local info = api("GetPlayerInfoByGUID")
    if not info then return nil end
    local ok, _, class = pcall(info, guid)
    if not ok or type(class) ~= "string" or not readable(class) then return nil end
    local colors = api("RAID_CLASS_COLORS")
    local c = colors and colors[class]
    if c and c.r then return { c.r, c.g, c.b } end
    local cc = api("C_ClassColor")
    if cc and cc.GetClassColor then
        local okC, col = pcall(cc.GetClassColor, class)
        if okC and col and col.r then return { col.r, col.g, col.b } end
    end
    return nil
end

local function channelName(args)
    local base = args[9]
    if type(base) == "string" and base ~= "" and readable(base) then
        -- le jeu peut donner « Général - Île de Zéphyrs » : seul le nom du canal reste, sans la zone
        base = base:gsub("%s+%-.*$", "")
        if base ~= "" then return base end
    end
    local full = args[4]
    if type(full) == "string" and readable(full) then
        full = full:gsub("^%d+%.%s*", ""):gsub("%s+%-.*$", "")
        if full ~= "" then return full end
    end
    return ns.T("Canal")
end

local function sameAsMe(author)
    local me = api("UnitName") and UnitName("player")
    if type(author) ~= "string" or not me then return false end
    return (author:match("^[^%-]+") or author) == me
end

-- nom coloré et cliquable, comme le fait le jeu ; si le jeu ne l'a pas coloré (option « couleur de classe »
-- décochée), couleur de classe quand même, sinon bleu Platyplus : le nom doit ressortir du texte
local function playerLink(event, args, author)
    local display
    local util = api("ChatFrameUtil")
    if util and util.GetDecoratedSenderName then
        local ok, name = pcall(util.GetDecoratedSenderName, event, unpack(args, 1, 15))
        if ok and type(name) == "string" and readable(name) then display = name end
    end
    if not display then
        display = api("Ambiguate") and Ambiguate(author, "none") or author
    end
    local bn = event:find("^CHAT_MSG_BN_") ~= nil
    if not display:find("|c", 1, true) then
        display = paint((not bn and classColor(args[12])) or ns.THEME.accent, display)
    end
    local lineID = args[11]
    if bn then
        local bnLink = api("GetBNPlayerLink")
        if bnLink then
            local ok, link = pcall(bnLink, author, display, args[13], lineID)
            if ok and type(link) == "string" then return link end
        end
        return display
    end
    local link = api("GetPlayerLink")
    if link then
        local ok, l = pcall(link, author, display, lineID)
        if ok and type(l) == "string" then return l end
    end
    return "|Hplayer:" .. author .. "|h" .. display .. "|h"
end

-- texte du message, avec ce que le chat de Blizzard ou Platyplus y ajoute (icônes {rt1}, liens web, ton nom)
local function messageBody(event, args, author)
    local msg = args[1]
    local info = api("C_ChatInfo")
    if info and info.ReplaceIconAndGroupExpressions then
        local ok, m = pcall(info.ReplaceIconAndGroupExpressions, msg, args[17], false)
        if ok and type(m) == "string" then msg = m end
    end
    if db("chatLinks") and ns.Chat and ns.Chat.Linkify then
        local ok, m = pcall(ns.Chat.Linkify, msg)
        if ok and type(m) == "string" then msg = m end
    end
    if db("chatMentions") and ns.ChatPlus and ns.ChatPlus.HighlightName and not sameAsMe(author) then
        local me = api("UnitName") and UnitName("player")
        local ok, m = pcall(ns.ChatPlus.HighlightName, msg, me)
        if ok and type(m) == "string" then msg = m end
    end
    return msg
end

local function plain(text)
    if type(text) ~= "string" or not readable(text) then return nil end
    local clean = ns.Chat and ns.Chat.CleanLine and ns.Chat.CleanLine(text) or text
    return clean and clean:lower() or nil
end

---------------------------------------------------------------------------
-- Réception : chaque ligne qu'une fenêtre de chat du jeu affiche (hook sur AddMessage) est lue ici
---------------------------------------------------------------------------
local nextID = 0
local stats = { withEvent = 0, textOnly = 0, secret = 0, dropped = 0, duplicates = 0, drawErrors = 0 }   -- (pour /pp chat)
CW.stats = stats

local function clockNow()
    local d = api("date")
    return d and d("%H:%M") or ""
end
local function today()
    local d = api("date")
    return d and d("%Y-%m-%d") or ""
end

-- « Nom-Royaume » de ce personnage (clé du journal sauvé)
local function charKey()
    local name, realm
    local full = api("UnitFullName")
    if full then name, realm = full("player") end
    name = name or (api("UnitName") and UnitName("player")) or "?"
    if not realm or realm == "" then realm = (api("GetRealmName") and GetRealmName()) or "?" end
    return name .. "-" .. realm
end

-- heure que le jeu met devant la ligne (option horodatage : « 17:12 », « [17:12:30] », « 5:12 PM ») : retirée
-- du texte, gardée comme heure du message
local function splitStamp(text)
    local stamp, rest = text:match("^%[?(%d%d?:%d%d:?%d?%d?%s?[AP]?M?)%]?%s+(.*)$")
    if not stamp then return nil, text end
    return stamp, rest
end

-- « [Guilde] %s : » -> motif Lua « ^%[Guilde%] (lien du joueur) : (texte) »
local PLAYER_LINK = "(|H[BN]?[Nn]?player:[^|]-|h.-|h)"
local function toPattern(fmt)
    local p = (fmt:gsub("%%%d*%$?s", "\1"))
    p = (p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
    p = (p:gsub("\1", PLAYER_LINK))
    return "^" .. p .. "(.*)$"
end

local function sameColor(info, r, g, b)
    if type(info) ~= "table" or not (info.r and info.g and info.b) then return true end   -- (couleur inconnue : on ne tranche pas)
    if not (readable(r) and readable(g) and readable(b)) then return true end
    return math.abs(info.r - (tonumber(r) or 1)) < 0.03 and math.abs(info.g - (tonumber(g) or 1)) < 0.03
        and math.abs(info.b - (tonumber(b) or 1)) < 0.03
end

-- types reconnus dans une ligne formatée, par ordre d'essai (« À %s : » avant « %s » de l'émote)
local LINE_TYPES = { "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT",
    "INSTANCE_CHAT_LEADER", "WHISPER_INFORM", "BN_WHISPER_INFORM", "WHISPER", "BN_WHISPER", "SAY", "YELL", "EMOTE" }
-- code du lien |Hchannel:CODE|h -> type
local CHANNEL_CODE = { GUILD = "GUILD", OFFICER = "OFFICER", PARTY = "PARTY", RAID = "RAID", RAID_WARNING = "RAID_WARNING",
    INSTANCE_CHAT = "INSTANCE_CHAT", BATTLEGROUND = "INSTANCE_CHAT" }

local patternCache = {}
local function patternOf(key)
    local p = patternCache[key]
    if p == nil then
        local fmt = api("CHAT_" .. key .. "_GET")
        if type(fmt) == "string" and fmt ~= "" then
            -- le lien de canal devant (« |Hchannel:GUILD|h[Guilde]|h ») est lu à part : retiré du modèle
            fmt = fmt:gsub("^|Hchannel:[%w_:]+|h%[.-%]|h%s*", "")
            p = toPattern(fmt)
        elseif key == "CHANNEL" then
            p = "^" .. PLAYER_LINK .. "%s*:%s*(.*)$"   -- (modèle du jeu absent : « lien : texte »)
        else
            p = false
        end
        patternCache[key] = p
    end
    return p or nil
end

-- nom du canal tel que le jeu l'écrit (« 1. Général - Mulgore », « [1] » raccourci) -> « Général », « Canal 1 »
-- libellés fixes des types de messages (traduits à l'affichage ; les noms de canaux viennent du jeu : tels quels)
local function shownLabel(l)
    if type(l) ~= "string" then return l end
    for _, k in pairs(KIND) do
        if k[2] == l then return ns.T(l) end
    end
    return l
end

local function cleanChannel(label)
    local n, name = label:match("^(%d+)%.%s*(.-)$")
    if not n then n = label:match("^(%d+)$") end
    name = (name or (n and "") or label):gsub("%s+%-.*$", "")
    if name == "" and n then
        local get = api("GetChannelName")
        local ok, _, full = pcall(get or error, tonumber(n))
        if ok and type(full) == "string" and readable(full) then name = full:gsub("%s+%-.*$", "") end
    end
    if name == "" then return n and ns.Tf("Canal %d", tonumber(n) or 0) or ns.T("Canal") end
    return name
end

-- Lit une ligne telle que le jeu l'a formatée : [|Hchannel:..|h[Canal]|h ] CHAT_<TYPE>_GET avec le lien du joueur, puis
-- le texte. Renvoie { type, label, link, author, lineID, body } pour une conversation, nil sinon (ligne du jeu).
-- (Vérifié dans ChatFrameOverrides.lua de Forever ; la couleur du type départage « %s dit : » d'une ligne système.)
function CW.Parse(text, r, g, b)
    if type(text) ~= "string" or not readable(text) then return nil end
    local chanType, label
    local code, bracket, rest = text:match("^|Hchannel:([%w_:]+)|h%[(.-)%]|h%s*(.*)$")
    if code then
        text = rest
        local n = code:match("^channel:(%d+)$") or code:match("^CHANNEL:(%d+)$")
        if n then
            chanType, label = "CHANNEL", cleanChannel(bracket)
        else
            chanType = CHANNEL_CODE[code]
            if not chanType then return nil end
        end
    end
    local types = api("ChatTypeInfo")
    local candidates = chanType and (chanType == "CHANNEL" and { "CHANNEL" } or { chanType, chanType .. "_LEADER" }) or LINE_TYPES
    for _, key in ipairs(candidates) do
        local p = patternOf(key)
        if p then
            local link, body = text:match(p)
            if link and (chanType or sameColor(types and types[key], r, g, b)) then
                local author = link:match("^|H[BN]?[Nn]?player:([^:|]+)")
                local lineID = tonumber(link:match("^|H[BN]?[Nn]?player:[^:|]+:(%d+)"))
                local kind = KIND[key]
                return { type = key, label = (chanType == "CHANNEL" and label) or (kind and kind[2]) or label, link = link,
                    author = author, lineID = lineID,
                    body = body, bn = key:find("^BN_") ~= nil, inform = key:find("_INFORM$") ~= nil }
            end
        end
    end
    return nil
end

-- nom du lien coloré ? sinon couleur de classe (GUID) ou bleu Platyplus : le nom doit ressortir
local function colorLink(link, guid, bn)
    if link:find("|c", 1, true) then return link end
    local c = (not bn and classColor(guid)) or ns.THEME.accent
    return (link:gsub("|h(.-)|h$", function(disp)
        local inner = disp:match("^%[(.-)%]$")
        return "|h" .. (inner and ("[" .. paint(c, inner) .. "]") or paint(c, disp)) .. "|h"
    end))
end

-- onglet d'un message protégé (texte secret, illisible) : d'après l'événement passé par Forever (son nom n'est jamais
-- secret), sinon d'après la couleur de la ligne (celle de son type, ChatTypeInfo). Second résultat : une conversation.
local function secretCategory(event, r, g, b)
    local chatType = type(event) == "string" and readable(event) and event:match("^CHAT_MSG_(.+)$")
    if chatType then
        local kind = KIND[chatType]
        if kind then return kind[1], kind[3] == true end
        return GAME, false
    end
    local types = api("ChatTypeInfo")
    if type(types) == "table" then
        local found
        for key, kind in pairs(KIND) do
            local info = kind[3] and types[key]
            if type(info) == "table" and info.r and math.abs(info.r - r) < 0.02 and math.abs(info.g - g) < 0.02
                and math.abs(info.b - b) < 0.02 then
                if found and found ~= kind[1] then return "all", false end   -- (couleur partagée : on ne tranche pas)
                found = kind[1]
            end
        end
        if found then return found, true end
    end
    return "all", false
end
CW.SecretCategory = secretCategory

-- fabrique l'entrée d'un message ; nil s'il n'y a rien à afficher
--  text : ligne formatée par le jeu ; event/args : donnés par Forever avec AddMessage quand il les passe (facultatif)
function CW.Entry(text, r, g, b, event, args)
    if text == nil then return nil end
    nextID = nextID + 1
    local e = { id = nextID, stamp = (api("GetTime") and GetTime()) or 0, day = today() }
    if not (readable(r) and readable(g) and readable(b)) then r, g, b = 1, 1, 1 end
    e.r, e.g, e.b = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
    -- message protégé par le jeu (valeurs secrètes, en instance) : ni lu ni gardé, affiché tel quel dans l'onglet de son type
    if type(text) ~= "string" or not readable(text) then
        e.secret, e.text, e.time = true, text, clockNow()
        e.cat, e.secretConv = secretCategory(event, e.r, e.g, e.b)
        e.event = (type(event) == "string" and readable(event)) and event or nil
        return e
    end
    local stamp, line = splitStamp(text)
    e.time = stamp and stamp:match("^%d%d?:%d%d") or clockNow()
    e.raw = text
    local chatType = type(event) == "string" and event:match("^CHAT_MSG_(.+)$")
    local kind = chatType and KIND[chatType]
    if kind and kind[3] and type(args) == "table" and type(args[1]) == "string" and type(args[2]) == "string"
        and readable(args[1]) and readable(args[2]) and args[2] ~= "" then
        -- Forever a passé l'événement et ses arguments : le plus sûr (GUID pour la couleur de classe, icônes {rt1})
        local author = args[2]
        e.conv, e.author, e.source = true, author, "event"
        e.link = playerLink(event, args, author)
        e.body = messageBody(event, args, author)
        e.label = chatType == "CHANNEL" and channelName(args) or kind[2]
        e.inform = chatType == "WHISPER_INFORM" or chatType == "BN_WHISPER_INFORM"
        e.cat = kind[1]
    else
        local p = CW.Parse(line, e.r, e.g, e.b)
        if p then
            local pk = KIND[p.type]
            e.conv, e.author, e.source = true, p.author or "?", "text"
            e.link = colorLink(p.link, nil, p.bn)
            e.body = p.body
            if db("chatLinks") and ns.Chat and ns.Chat.Linkify then
                local ok, m = pcall(ns.Chat.Linkify, e.body)
                if ok and type(m) == "string" then e.body = m end
            end
            if db("chatMentions") and ns.ChatPlus and ns.ChatPlus.HighlightName and not sameAsMe(e.author) then
                local ok, m = pcall(ns.ChatPlus.HighlightName, e.body, api("UnitName") and UnitName("player"))
                if ok and type(m) == "string" then e.body = m end
            end
            e.label = p.label
            e.inform = p.inform
            e.lineID = p.lineID
            e.cat = pk and pk[1] or "chat"
        else
            e.text = line
            e.cat = (kind and kind[1]) or GAME
            e.plain = plain(line)
            return e
        end
    end
    e.mine = e.inform or sameAsMe(e.author)
    e.groupKey = e.cat .. "\1" .. e.author .. "\1" .. (e.label or "")
    e.plain = plain((api("Ambiguate") and Ambiguate(e.author, "none") or e.author) .. " " .. e.body)
    return e
end

-- un message déjà reçu par une AUTRE fenêtre du jeu ? (même ligne : même identifiant ; sinon même texte, ou même type
-- de message protégé, au même instant). La même fenêtre qui redit la même chose dans la même seconde, c'est un vrai
-- second message (butin de deux corps, joueur qui répète) : gardé.
local function duplicate(e, args, frame)
    local key, unique
    local lineID = type(args) == "table" and args[11]
    if type(lineID) == "number" and readable(lineID) and lineID > 0 then
        key, unique = "L" .. lineID, true
    elseif e.lineID then
        key, unique = "L" .. e.lineID, true
    elseif e.raw then
        key = e.raw .. "@" .. tostring(e.stamp)
    elseif e.secret then
        key = "S" .. tostring(e.event) .. "@" .. tostring(e.stamp) .. "@" .. tostring(e.r) .. tostring(e.g) .. tostring(e.b)
    end
    if not key then return false end
    local who = CW.seen[key]
    if who ~= nil and (unique or who ~= (frame or true)) then return true end
    if who == nil then
        CW.seen[key] = frame or true
        CW.seenCount = CW.seenCount + 1
        if CW.seenCount > 2000 then wipe(CW.seen); CW.seenCount = 0 end
    end
    return false
end
CW.Duplicate = duplicate

---------------------------------------------------------------------------
-- Mémoire : les messages de la session (store) ; les lisibles sont aussi écrits tout de suite dans le journal
-- sauvé de ce personnage (PlatyplusDB.chatWinLog[Nom-Royaume]), relu au prochain chargement : Forever ne remet
-- pas l'historique des fenêtres de chat après un /reload, et rien n'attend la déconnexion
---------------------------------------------------------------------------
local SAVE_MAX = 300

local function savedLog()
    if not ns.db then return nil end
    if type(ns.db.chatWinLog) ~= "table" then ns.db.chatWinLog = {} end
    local key = charKey()
    if type(ns.db.chatWinLog[key]) ~= "table" then ns.db.chatWinLog[key] = {} end
    return ns.db.chatWinLog[key]
end

local function push(e)
    local store = CW.store
    store[#store + 1] = e
    if #store > MAX_STORE then table.remove(store, 1) end
    if e.secret or e.restored or not e.raw then return end
    local log = savedLog()
    if not log then return end
    log[#log + 1] = { e.raw, e.r, e.g, e.b, e.day, e.cat, e.time }
    while #log > SAVE_MAX do table.remove(log, 1) end
end

-- « instant » d'une ligne relue, pour grouper les messages qui se suivent à la même minute : bien avant GetTime()
-- (qui part de 0 au lancement du jeu), donc jamais groupée avec un message d'aujourd'hui
local function pastStamp(day, time)
    local y, m, d = day:match("^(%d+)%-(%d+)%-(%d+)$")
    local h, mi = time:match("(%d%d?):(%d%d)$")
    if not (y and h) then return -1e12 end
    return -1e12 + (((tonumber(y) * 372 + tonumber(m) * 31 + tonumber(d)) * 1440 + tonumber(h) * 60 + tonumber(mi)) * 60)
end

-- journal d'une version précédente (PlatyplusDB.chatWinHistory, sauvé à la déconnexion) : versé dans le journal
-- de ce personnage s'il est vide, puis effacé
local function migrateOld(log)
    local old = ns.db and ns.db.chatWinHistory
    if type(old) ~= "table" then return end
    if #log == 0 then
        for _, rec in ipairs(old) do
            local text = type(rec) == "table" and (rec.raw or rec.text)
            if type(text) == "string" then
                log[#log + 1] = { text, tonumber(rec.r) or 1, tonumber(rec.g) or 1, tonumber(rec.b) or 1, rec.day, rec.cat, rec.time }
            end
        end
        while #log > SAVE_MAX do table.remove(log, 1) end
    end
    ns.db.chatWinHistory = nil
end

-- relit le journal sauvé (au chargement) : chaque ligne refaite à partir du texte formaté, dans son onglet
function CW:Restore()
    local log = savedLog()
    if not log then return 0 end
    migrateOld(log)
    self.savedAtLoad = #log
    if #log == 0 then return 0 end
    local now, n = today(), 0
    for _, rec in ipairs(log) do
        if type(rec) == "table" and type(rec[1]) == "string" then
            local e = self.Entry(rec[1], rec[2], rec[3], rec[4])
            if e and not e.secret then
                e.restored = true
                e.day = rec[5] or now
                if type(rec[6]) == "string" then e.cat = rec[6] end
                if type(rec[7]) == "string" and rec[7] ~= "" then e.time = rec[7] end
                e.stamp = pastStamp(e.day, e.time)
                if e.day ~= now and e.day:match("^%d%d%d%d%-%d%d%-%d%d$") then
                    e.time = e.day:sub(9, 10) .. "/" .. e.day:sub(6, 7) .. " " .. e.time
                end
                push(e)
                n = n + 1
            end
        end
    end
    if n > 0 then
        nextID = nextID + 1
        push({ id = nextID, stamp = 0, restored = true, cat = "all", time = "", day = now, centered = true,
            text = paint(ns.THEME.dim, ns.T("— session précédente —")), r = 1, g = 1, b = 1, divider = true })
    end
    self.restoredCount = n
    return n
end

function CW:ClearSaved()
    if ns.db and type(ns.db.chatWinLog) == "table" then ns.db.chatWinLog[charKey()] = nil end
end

local function afterAddMessage(frame, text, r, g, b, _, _, _, event, args)
    if CW.detached then return end
    local memory = ns.ChatPlus and ns.ChatPlus.Memory
    if memory and memory.restoring then return end
    local isLog = api("IsCombatLog")
    if (isLog and isLog(frame)) or (frame ~= nil and frame == api("COMBATLOG")) then return end
    local ok, e = pcall(CW.Entry, text, r, g, b, event, args)
    if not ok then
        stats.dropped = stats.dropped + 1
        CW.lastError = tostring(e)
        ns:Debug("fenêtre de chat :", e)
        return
    end
    if not e then return end
    if duplicate(e, args, frame) then
        stats.duplicates = (stats.duplicates or 0) + 1
        return
    end
    if e.secret then stats.secret = stats.secret + 1
    elseif e.source == "event" then stats.withEvent = stats.withEvent + 1
    else stats.textOnly = stats.textOnly + 1 end
    push(e)
    CW:OnEntry(e)
end
CW.AfterAddMessage = afterAddMessage

---------------------------------------------------------------------------
-- Affichage : la liste de l'onglet (messages qui correspondent), dessinée du bas vers le haut
---------------------------------------------------------------------------
function CW:Matches(e)
    if e.cat == "all" then return self.search == "" end
    if self.tab == "chat" then
        if e.cat == GAME then return false end
    elseif e.cat ~= self.tab then
        return false
    end
    if self.search ~= "" then
        return e.plain ~= nil and e.plain:find(self.search, 1, true) ~= nil
    end
    return true
end

-- morceaux d'un message : heure grise cliquable (copier), [canal] dans la couleur du canal, nom
-- (« à Bob » pour un chuchotement envoyé)
local function clockOf(e) return "|H" .. COPY_PREFIX .. e.id .. "|h" .. paint(ns.THEME.dim, e.time) .. "|h" end
local function labelOf(e, brackets)
    if not e.label then return nil end
    return paint({ e.r, e.g, e.b }, brackets and ("[" .. shownLabel(e.label) .. "]") or shownLabel(e.label))
end
-- Nom affiché : sur Forever c'est « Prénom Nom », souvent long. Au-delà de 12 lettres : « Prénom N. ». Seul le texte
-- visible du lien change : ses données gardent le nom complet (clic = chuchoter la bonne personne, survol = nom entier).
local SHORT_FROM = 13
local function utf8len(s) return select(2, s:gsub("[^\128-\191]", "")) end
local function shortName(full)
    if utf8len(full) < SHORT_FROM then return nil end
    local first, rest = full:match("^(%S+)%s+(.-)%s*$")
    if not first or rest == "" then return nil end
    local initial = (rest:match("(%S+)$") or rest):match("^[%z\1-\127\194-\244][\128-\191]*")
    if not initial then return nil end
    return first .. " " .. initial .. "."
end
CW.ShortName = shortName

local function nameOf(e)
    local link, author = e.link, e.author
    if type(link) ~= "string" or type(author) ~= "string" then return link end
    local full = (api("Ambiguate") and Ambiguate(author, "none")) or author
    local short = type(full) == "string" and shortName(full)
    if not short then return link end
    local head, shown = link:match("^(.-|h)(.-)|h$")        -- |Hplayer:...|h  texte visible  |h
    if not shown then return link end
    local s, f = shown:find(full, 1, true)
    if not s then return link end
    return head .. shown:sub(1, s - 1) .. short .. shown:sub(f + 1) .. "|h"
end
CW.NameOf = nameOf

local function whoOf(e)
    local name = nameOf(e)
    return e.inform and (paint(ns.THEME.dim, "à ") .. name) or name
end

-- couleur du texte d'un message : clair, ou celle du canal si l'option est cochée
local function bodyColor(e)
    if db("chatWinChannelText") then return e.r, e.g, e.b end
    local T = ns.THEME.text
    return T[1], T[2], T[3]
end

-- canal sous-entendu par l'onglet : pas répété dans chaque bulle
local IMPLIED = { guild = "Guilde", group = "Groupe", whisper = "Chuchote" }

-- Mode messagerie : un message = « Nom : texte » sur toute la largeur (retour à la ligne sous le nom), une fine barre
-- de la couleur du canal à gauche, canal et heure en petit à droite ; pas de bulle. Fond teinté pour tes messages
-- et les chuchotements reçus, léger fond au survol.
local TEXT_X = 10                -- début du texte (après la barre du canal)
local PAD_R, PAD_Y = 6, 3        -- marge à droite, marge en haut et en bas d'un message
local BAR_W = 2                  -- barre de la couleur du canal
local GAP, GAP_GROUP = 3, 1      -- espace entre deux messages (autre joueur / même joueur à la suite)
local GAP_PLAIN = 3              -- espace autour d'une ligne du jeu
local MAX_ROWS = 80              -- lignes dessinées au plus (celles qui dépassent en haut sont coupées)
local BOTTOM_PAD = 6             -- marge sous le dernier message (la vue a déjà 10 px sous elle)
local RIGHT_INSET = 6            -- retrait à droite : les messages ne touchent pas la barre de défilement

-- teinte d'en-tête de bulle (heure, séparateur) : entre le gris du thème et le texte, plus lisible
local HEAD_TINT
local function headTint()      -- calculée une fois (entre THEME.dim et THEME.text)
    if not HEAD_TINT then
        local T = ns.THEME
        local d, t = T.dim, T.text
        HEAD_TINT = { (d[1] + t[1]) / 2, (d[2] + t[2]) / 2, (d[3] + t[3]) / 2 }
    end
    return HEAD_TINT
end
local SECRET_LINES = 3           -- repli d'une ligne protégée si le jeu refuse l'ancrage sur son texte

local onHyperlink   -- (défini plus bas, avec la fenêtre)

local function fontPath()
    local fontObj = api("ChatFontNormal")
    local path = (fontObj and fontObj.GetFont and fontObj:GetFont()) or api("STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF"
    return ns.Font and ns.Font(path) or path   -- cyrillique si ruRU (Locale.lua)
end

local function copyEntry(e)
    if not (e and ns.Chat and ns.Chat.ShowCopy) or e.secret or e.divider then return end
    local line = e.conv and ((api("Ambiguate") and Ambiguate(e.author, "none") or e.author) .. " : " .. e.body) or e.text
    ns.Chat:ShowCopy(ns.T("Copier le message"), (ns.Chat.CleanLine and ns.Chat.CleanLine(line)) or line)
end

-- nombre lisible, sinon la valeur de repli (une mesure ne doit jamais faire planter la vue)
local function num(v, fallback)
    if v == nil or not readable(v) then return fallback end
    return tonumber(v) or fallback
end

local function unboundedWidth(fs)
    local w = fs.GetUnboundedStringWidth and num(fs:GetUnboundedStringWidth(), 0) or 0
    if w <= 0 then w = num(fs:GetStringWidth(), 0) end
    return w
end

local function textHeight(fs, text, width)
    local h
    if ns.W and ns.W.Measure then
        local ok, v = pcall(ns.W.Measure, fs, text, width)
        h = ok and num(v, nil) or nil
    end
    if not h or h < 1 then h = num(fs:GetStringHeight(), 0) end
    if h < 1 then h = (CW.fontSize or 13) * 1.25 end
    return h
end

-- un texte qui a pu afficher une valeur protégée garde sa marque : on l'enlève avant de le réutiliser
local function freshText(fs)
    if fs.ClearText then pcall(fs.ClearText, fs) end
end

-- Les mesures se font sur deux textes à part, jamais affichés ni ancrés à une ligne : une ligne posée au-dessus d'une
-- ligne protégée hérite d'un ancrage « secret » et ses mesures deviendraient protégées (doc API : GetStringHeight /
-- GetStringWidth « SecretWhenAnchoringSecret »). Ces deux-là ne reçoivent que du texte lisible.
local function meter()
    local m = CW.meter
    if m then return m end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", 0, 400)          -- hors de l'écran
    f:SetAlpha(0)
    local body = f:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    body:SetNonSpaceWrap(true)
    body:SetIndentedWordWrap(false)
    local small = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    small:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    small:SetWordWrap(false)
    m = { body = body, small = small }
    CW.meter = m
    return m
end

local function meterText(which, text, width)
    local fs = meter()[which]
    local size = CW.fontSize or 13
    if which == "small" then size = max(9, size - 2) end
    local path = CW.fontPath or fontPath()
    if fs.fontKey ~= path .. size then
        fs:SetFont(path, size, "")
        fs.fontKey = path .. size
    end
    fs:SetWidth(width or 0)                                          -- 0 : à la taille du texte
    fs:SetText(text or "")
    return fs
end

-- largeur du texte sur une ligne
local function naturalWidth(which, text)
    return unboundedWidth(meterText(which, text, 0))
end

-- hauteur du texte coupé à cette largeur
local function wrappedHeight(which, text, width)
    return textHeight(meterText(which, text, width), text, width)
end

-- forme d'un message à l'écran : bulle mesurée, ligne simple mesurée, ou ligne protégée (jamais mesurée)
local function kindOf(e)
    if e.secret then return "secret" end
    if e.conv and db("chatWinTwoLines") then return "bubble" end
    return "line"
end

-- le message i se colle-t-il au précédent (même joueur, même canal, moins d'une minute) ? (bulles seulement)
local function grouped(list, i)
    local e, prev = list[i], list[i - 1]
    if not (prev and e.conv and prev.conv and not e.secret and not prev.secret) then return false end
    if not db("chatWinTwoLines") or e.groupKey ~= prev.groupKey then return false end
    local d = (e.stamp or 0) - (prev.stamp or 0)
    return d >= 0 and d < GROUP_WINDOW
end
CW.Grouped = grouped

local function isBubbleLike(e)
    if not db("chatWinTwoLines") then return false end
    return (e.conv and not e.secret) or (e.secret and e.secretConv) or false
end

-- espace entre le message i (au-dessus) et le message i + 1 (en dessous)
local function gapBetween(list, i)
    local upper, lower = list[i], list[i + 1]
    if not (upper and lower) then return 0 end
    if grouped(list, i + 1) then return GAP_GROUP end
    if isBubbleLike(upper) or isBubbleLike(lower) then return GAP end
    return GAP_PLAIN
end

-- une ligne de la vue : row = emplacement sur toute la largeur (empilé sur celui d'en dessous) ; row.box = la bulle
-- ou la ligne elle-même (textes, liens cliquables, molette)
local function newRow(kind, parent)
    local W, T = ns.W, ns.THEME
    local row = CreateFrame("Frame", nil, parent)
    row.kind = kind
    local box = CreateFrame("Frame", nil, row)
    box:SetHyperlinksEnabled(true)
    box:SetScript("OnHyperlinkClick", function(_, link, text, button) onHyperlink(link, text, button) end)
    -- survol d'un nom : le nom complet (il peut être raccourci à l'écran)
    box:SetScript("OnHyperlinkEnter", function(self, link)
        local tip = api("GameTooltip")
        if not (tip and type(link) == "string" and readable(link)) then return end
        local name = link:match("^player:([^:]+)")
        if not name then return end
        tip:SetOwner(self, "ANCHOR_CURSOR")
        tip:SetText(name, 1, 1, 1)
        tip:Show()
    end)
    box:SetScript("OnHyperlinkLeave", function(self)
        local tip = api("GameTooltip")
        if tip and tip:IsOwned(self) then tip:Hide() end
    end)
    box:EnableMouse(true)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta) CW:Wheel(delta) end)
    box:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and row.e and row.e.conv then copyEntry(row.e) end
    end)
    row.box = box
    if kind ~= "line" then
        -- fond (tes messages, chuchotements reçus, survol) et barre de la couleur du canal
        if W and W.Round then
            row.bubble = W.Round(box, "BACKGROUND", 0, 4)
        else
            local tex = box:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints()
            row.bubble = { SetColor = function(_, c, a) tex:SetColorTexture(c[1], c[2], c[3], a) end,
                SetShown = function(_, v) tex:SetShown(v) end }
        end
        local bar = box:CreateTexture(nil, "ARTWORK")
        bar:SetWidth(BAR_W)
        bar:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -1)
        bar:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 1)
        row.bar = bar
        box:SetScript("OnEnter", function() CW:PaintBack(row, true) end)
        box:SetScript("OnLeave", function() CW:PaintBack(row, false) end)
    end
    if kind == "bubble" then
        local clock = CreateFrame("Button", nil, box)
        clock:SetPoint("TOPRIGHT", box, "TOPRIGHT", -PAD_R, -(PAD_Y + 2))   -- (+2 : sur la ligne du texte, plus grand)
        local clockText = clock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        clockText:SetPoint("RIGHT")
        local tint = headTint()
        clockText:SetTextColor(tint[1], tint[2], tint[3])
        clock.text = clockText
        clock:SetScript("OnClick", function() copyEntry(row.e) end)
        clock:SetScript("OnEnter", function(self)
            local tip = api("GameTooltip")
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText(ns.T("Clic : copier ce message"))
                tip:Show()
            end
        end)
        clock:SetScript("OnLeave", function()
            local tip = api("GameTooltip")
            if tip then tip:Hide() end
        end)
        clock:EnableMouseWheel(true)
        clock:SetScript("OnMouseWheel", function(_, delta) CW:Wheel(delta) end)
        row.clock = clock
        -- canal en petit, dans sa couleur, juste avant l'heure (absent quand l'onglet le sous-entend)
        local tag = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tag:SetJustifyH("RIGHT")
        tag:SetWordWrap(false)
        tag:SetPoint("RIGHT", clock, "LEFT", -6, 0)
        row.tag = tag
    end
    local body = box:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    body:SetNonSpaceWrap(true)
    body:SetIndentedWordWrap(false)
    row.body = body
    return row
end

-- polices : taille réglée pour le texte, un peu plus petite pour le nom et l'heure
function CW:FontRow(row)
    local size = self.fontSize or 13
    local path = self.fontPath or fontPath()
    local small = max(9, size - 2)
    row.body:SetFont(path, size, "")
    row.body:SetShadowColor(0, 0, 0, 0.9)
    row.body:SetShadowOffset(1, -1)
    if row.tag then
        row.tag:SetFont(path, small, "")
        row.clock.text:SetFont(path, small, "")
    end
    row.fontKey = path .. size
end

-- fond d'un message : teinte de tes messages (bleu) et des chuchotements reçus (leur couleur), rien sinon
local function backOf(e)
    if e.mine then return ns.THEME.accent2, 0.14 end
    if e.cat == "whisper" then return { e.r or 1, e.g or 0.5, e.b or 1 }, 0.10 end
    return nil, 0
end

function CW:PaintBack(row, hover)
    local bg = row.bubble
    if not bg then return end
    local c, a = row.backColor, row.backAlpha or 0
    if hover and row.hoverable then
        if c then a = a + 0.06 else c, a = ns.THEME.text, 0.05 end
    end
    if c then bg:SetColor(c, a) end
    bg:SetShown(c ~= nil)
end

-- message (mode messagerie) : « Nom : texte » sur toute la largeur, canal et heure en petit à droite (pas pour un
-- message collé au précédent du même joueur) ; renvoie sa hauteur
function CW:PaintBubble(row, e, isGrouped, viewW)
    local rowW = max(80, viewW - RIGHT_INSET)
    local metaW, metaH = 0, 0
    freshText(row.clock.text)
    freshText(row.tag)
    if isGrouped then
        row.clock:Hide()
        row.tag:Hide()
    else
        row.clock.text:SetText(e.time)
        local clockW = naturalWidth("small", e.time) + 4
        metaH = max(9, (self.fontSize or 13) - 2) + 2
        row.clock:SetSize(max(1, clockW), metaH)
        row.clock:Show()
        metaW = clockW + 10                                   -- (10 : air entre le texte et l'heure)
        local label = (e.label and e.label ~= IMPLIED[self.tab]) and e.label or nil
        if label then
            label = shownLabel(label)
            row.tag:SetText(label)
            row.tag:SetTextColor(e.r or 1, e.g or 1, e.b or 1, 0.85)
            row.tag:Show()
            metaW = metaW + naturalWidth("small", label) + 6
        else
            row.tag:Hide()
        end
    end
    local text = whoOf(e) .. paint(headTint(), " : ") .. e.body
    freshText(row.body)
    row.body:SetText(text)
    row.body:SetTextColor(bodyColor(e))
    local textW = max(40, rowW - TEXT_X - PAD_R - metaW)
    row.body:SetWidth(textW)
    local bodyH = wrappedHeight("body", text, textW)
    row.body:ClearAllPoints()
    row.body:SetPoint("TOPLEFT", row.box, "TOPLEFT", TEXT_X, -PAD_Y)
    local h = PAD_Y + max(bodyH, metaH) + PAD_Y
    row.bodyH, row.minH, row.padH = bodyH, metaH, 2 * PAD_Y      -- (revérifiés par CheckHeights)
    row.box:SetSize(rowW, h)
    row.box:ClearAllPoints()
    row.box:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.bar:SetColorTexture(e.r or 1, e.g or 1, e.b or 1, 0.85)
    row.bar:Show()
    row.hoverable = true
    row.backColor, row.backAlpha = backOf(e)
    self:PaintBack(row, false)
    return h
end

-- ligne simple : message du jeu tel quel, ou mode compact « 15:27 [Guilde] Bob : salut » ; renvoie sa hauteur
function CW:PaintLine(row, e, viewW)
    local T = ns.THEME
    freshText(row.body)
    local text
    if e.conv then
        local label = labelOf(e, true)
        text = clockOf(e) .. " " .. (label and (label .. " ") or "") .. whoOf(e) .. paint(T.dim, " : ") .. e.body
        row.body:SetText(text)
        row.body:SetTextColor(bodyColor(e))
    else
        text = e.text or ""
        row.body:SetText(text)
        row.body:SetTextColor(e.r or 1, e.g or 1, e.b or 1)
    end
    if e.centered then row.body:SetJustifyH("CENTER") else row.body:SetJustifyH("LEFT") end
    row.body:SetWidth(viewW)
    local h = wrappedHeight("body", text, viewW)
    row.bodyH, row.minH, row.padH = h, 0, 0
    row.body:ClearAllPoints()
    row.body:SetPoint("TOPLEFT", row.box, "TOPLEFT", 0, 0)
    row.box:SetSize(viewW, h)
    row.box:ClearAllPoints()
    row.box:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    return h
end

-- ligne protégée : le texte tel que le jeu l'a écrit (valeur secrète : ni lu, ni mesuré), dans la couleur de son
-- type ; dans une bulle quand c'est une conversation. Sa hauteur est laissée au jeu (voir Place).
function CW:PaintSecret(row, e, viewW)
    local T = ns.THEME
    local styled = db("chatWinTwoLines") and e.secretConv          -- conversation : même allure qu'un message
    local boxW = styled and max(80, viewW - RIGHT_INSET) or viewW
    local padX, padY = styled and TEXT_X or 0, styled and PAD_Y or 0
    row.body:SetWidth(max(1, boxW - padX - (styled and PAD_R or 0)))
    row.body:SetText(e.text)
    if styled and not db("chatWinChannelText") then
        row.body:SetTextColor(T.text[1], T.text[2], T.text[3])
    else
        row.body:SetTextColor(e.r or 1, e.g or 1, e.b or 1)
    end
    row.bar:SetShown(styled and true or false)
    if styled then row.bar:SetColorTexture(e.r or 1, e.g or 1, e.b or 1, 0.85) end
    row.hoverable = styled and true or false
    if styled then row.backColor, row.backAlpha = backOf(e) else row.backColor, row.backAlpha = nil, 0 end
    self:PaintBack(row, false)
    row.boxW, row.padX, row.padY = boxW, padX, padY
    row.estimate = (self.fontSize or 13) * 1.25 + 2 * padY   -- au moins une ligne (pour savoir quand s'arrêter)
end

-- pose une ligne au-dessus de « dessous » (emplacement plus récent, ou le bas de la vue), à « gap » pixels
function CW:Place(row, below, gap)
    row:ClearAllPoints()
    if row.kind ~= "secret" then
        row:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, gap)
        row:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, gap)
        row:SetHeight(max(1, row.h or 1))
        return
    end
    -- le texte protégé est posé sur la ligne d'en dessous ; l'emplacement le suit (bas : la ligne d'en dessous, haut :
    -- le haut du texte) : aucune mesure, le jeu fait le calcul
    local body, box = row.body, row.box
    body:ClearAllPoints()
    body:SetPoint("BOTTOMLEFT", below, "TOPLEFT", row.padX, gap + row.padY)
    row:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, gap)
    local ok = not self.noSelfAnchor and pcall(row.SetPoint, row, "TOPLEFT", body, "TOPLEFT", -row.padX, row.padY)
    if not ok then
        -- le jeu refuse : hauteur fixe (quelques lignes au plus), texte posé dans l'emplacement
        self.noSelfAnchor = true
        row:ClearAllPoints()
        local lines = SECRET_LINES
        if body.SetMaxLines then body:SetMaxLines(lines) end
        local h = lines * (self.fontSize or 13) * 1.2 + 2 * row.padY
        row:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, gap)
        row:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, gap)
        row:SetHeight(h)
        row.estimate = h
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", row, "TOPLEFT", row.padX, -row.padY)
    end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    box:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    box:SetWidth(row.boxW)
end

-- une ligne pour ce message : celle déjà affichée si rien n'a changé, sinon une libre de la bonne forme, redessinée
function CW:RowFor(list, i, viewW, keep)
    local e = list[i]
    local kind = kindOf(e)
    local isGrouped = kind == "bubble" and grouped(list, i)
    local key = table.concat({ kind, isGrouped and 1 or 0, viewW, (self.fontPath or "") .. (self.fontSize or 13),
        self.tab, db("chatWinChannelText") and 1 or 0 }, "|")
    local row = self.shown[e]
    if row and row.key == key then
        self.shown[e] = nil
        keep[e] = row
        return row
    end
    if row then                                    -- affiché, mais plus à jour : rendu à sa réserve
        self.shown[e] = nil
        self:Release(row)
    end
    local pool = self.pools[kind]
    row = table.remove(pool) or newRow(kind, self.content)
    row.e, row.key = e, key
    local ok, err = pcall(function()
        if row.fontKey ~= (self.fontPath or fontPath()) .. (self.fontSize or 13) then self:FontRow(row) end
        if kind == "bubble" then
            row.h = self:PaintBubble(row, e, isGrouped, viewW)
        elseif kind == "line" then
            row.h = self:PaintLine(row, e, viewW)
        else
            row.h = nil
            self:PaintSecret(row, e, viewW)
        end
    end)
    if not ok then
        self:Release(row)
        error(err, 0)
    end
    row:Show()
    keep[e] = row
    return row
end

function CW:Release(row)
    row:Hide()
    row:ClearAllPoints()
    row.e, row.key = nil, nil
    local pool = self.pools[row.kind]
    pool[#pool + 1] = row
end

-- taille de la vue ; si le cadre n'est pas encore mis en page (taille 0), d'après celle de la fenêtre
function CW:ViewSize()
    local f = self.frame
    local w, h = num(self.view:GetWidth(), 0), num(self.view:GetHeight(), 0)
    if w < 1 then w = max(60, num(f:GetWidth(), 0) - 24) end
    if h < 1 then h = max(40, num(f:GetHeight(), 0) - 34 - (self.editOpen and 38 or 10)) end
    return floor(w + 0.5), h
end

-- dessine la vue : le message « offset » crans au-dessus du plus récent en bas, les plus anciens au-dessus, tant
-- qu'il reste de la place (ce qui dépasse en haut est coupé par la vue)
function CW:Layout()
    if not self.view then return end
    local viewW, viewH = self:ViewSize()
    self.viewW = viewW
    self.content:SetWidth(viewW)
    local list = self.list
    local n = #list
    self.offset = max(0, min(self.offset or 0, max(0, n - 1)))
    local keep, rows = {}, {}
    local below, used = self.floor, 0
    local i = n - self.offset
    local bottomIndex = i
    while i >= 1 and #rows < MAX_ROWS and used <= viewH + 40 do
        local ok, row = pcall(self.RowFor, self, list, i, viewW, keep)
        if ok and row then
            local gap = (i == bottomIndex) and 0 or gapBetween(list, i)
            self:Place(row, below, gap)
            used = used + gap + (row.h or row.estimate or 14)
            rows[#rows + 1] = row
            below = row
        else
            stats.drawErrors = (stats.drawErrors or 0) + 1
            CW.lastError = tostring(row)
            ns:Debug("fenêtre de chat (message) :", row)
        end
        i = i - 1
    end
    -- plus d'anciens au-dessus ? (messages pas dessinés, ou le dernier dessiné dépasse en haut)
    self.moreAbove = i >= 1 or used > viewH
    for e, row in pairs(self.shown) do self:Release(row) end
    self.shown = keep
    -- (ordre de lecture : du plus ancien en haut au plus récent en bas)
    wipe(self.rows)
    for k = #rows, 1, -1 do self.rows[#self.rows + 1] = rows[k] end
    self:PaintThumb()
    self:CheckLater(0)
end

-- Une hauteur mesurée peut être fausse : au chargement la police n'est pas toujours prête, et les longs messages de la
-- session précédente débordaient sur les suivants. Un peu plus tard, on relit la hauteur du texte réellement affiché
-- (si elle est lisible : posé sur une ligne protégée, il ne l'est pas) et on agrandit ou réduit la ligne.
function CW:CheckHeights()
    local changed = false
    for _, row in ipairs(self.rows or {}) do
        if row.kind ~= "secret" and row.bodyH and row.e then
            local ok, h = pcall(row.body.GetStringHeight, row.body)
            h = ok and num(h, nil) or nil
            if h and h >= 1 and math.abs(h - row.bodyH) > 1 then
                row.bodyH = h
                row.h = row.padH + max(h, row.minH)
                row:SetHeight(row.h)
                row.box:SetHeight(row.h)
                changed = true
            end
        end
    end
    if changed then
        stats.heightFixes = (stats.heightFixes or 0) + 1
        self:Layout()          -- (lignes reprises telles quelles : recompte ce qui tient, « plus haut », curseur)
    end
    return changed
end

-- vérification groupée : une seule en attente par délai
function CW:CheckLater(delay)
    local timer = api("C_Timer")
    if not (timer and timer.After) then return end
    self.checkQueued = self.checkQueued or {}
    if self.checkQueued[delay] then return end
    self.checkQueued[delay] = true
    timer.After(delay, function()
        self.checkQueued[delay] = nil
        if self.active then try("hauteurs", self.CheckHeights, self) end
    end)
end

-- refait la liste de l'onglet (onglet, recherche) puis la vue, en bas
function CW:Render()
    if not self.view then return end
    local list = {}
    for k = #self.store, 1, -1 do
        local e = self.store[k]
        if self:Matches(e) then
            list[#list + 1] = e
            if #list >= MAX_SHOW then break end
        end
    end
    local ordered = {}
    for k = #list, 1, -1 do ordered[#ordered + 1] = list[k] end
    if self.search ~= "" and #ordered == 0 then
        ordered[1] = { id = -1, text = ns.Tf("Aucun message ne contient « %s ».", self.search), r = 0.6, g = 0.63, b = 0.7,
            time = "", stamp = 0, cat = "all" }
    end
    self.list = ordered
    self.offset, self.newCount = 0, 0
    self.newBtn:Hide()
    self:Layout()
end

-- un message qui vient d'arriver : en bas ; la vue suit si elle y était, sinon elle reste en place (« Nouveaux messages »)
function CW:Append(e)
    local list = self.list
    list[#list + 1] = e
    if #list > MAX_SHOW then table.remove(list, 1) end
    if (self.offset or 0) > 0 then
        self.offset = self.offset + 1
        self.newCount = (self.newCount or 0) + 1
        self:PaintNewButton()
    end
    self:Layout()
end

function CW:FindEntry(id)
    for i = #self.store, 1, -1 do
        if self.store[i].id == id then return self.store[i] end
    end
end

---------------------------------------------------------------------------
-- Défilement : par message, comme la fenêtre de chat du jeu
---------------------------------------------------------------------------
function CW:ScrollBy(steps)
    local before = self.offset or 0
    if steps > 0 and not self.moreAbove then return end           -- déjà tout en haut
    self.offset = max(0, min(before + steps, max(0, #self.list - 1)))
    if self.offset == 0 then
        self.newCount = 0
        self.newBtn:Hide()
    end
    if self.offset ~= before then self:Layout() end
end

function CW:ScrollToBottom()
    self.offset, self.newCount = 0, 0
    self.newBtn:Hide()
    self:Layout()
end

function CW:ScrollToTop()
    -- remonte message par message jusqu'à voir le plus ancien en haut (les lignes déjà dessinées sont reprises telles quelles)
    local guard = #self.list
    while self.moreAbove and guard > 0 and (self.offset or 0) < #self.list - 1 do
        self.offset = (self.offset or 0) + 1
        self:Layout()
        guard = guard - 1
    end
end

function CW:Wheel(delta)
    if IsShiftKeyDown and IsShiftKeyDown() then
        if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
    else
        local step = (IsControlKeyDown and IsControlKeyDown()) and 5 or 1
        self:ScrollBy(delta > 0 and step or -step)
    end
end

-- la vue suit-elle les nouveaux messages ? (en bas)
function CW:Following()
    return (self.offset or 0) == 0
end
CW.AtBottom = CW.Following

-- fine barre de position à droite de la vue (d'après le rang du message en bas)
function CW:PaintThumb()
    local thumb = self.thumb
    if not thumb then return end
    local n = #self.list
    if n <= 1 or not (self.moreAbove or (self.offset or 0) > 0) then
        thumb:Hide()
        return
    end
    local _, viewH = self:ViewSize()
    local shown = max(1, #self.rows)
    local h = max(16, min(viewH, viewH * shown / n))
    local pos = 1 - (self.offset or 0) / max(1, n - 1)              -- 1 : en bas, 0 : en haut
    thumb:Show()
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", self.view, "TOPRIGHT", 7, -(viewH - h) * pos)
end

function CW:PaintNewButton()
    local n = self.newCount or 0
    if n <= 0 then self.newBtn:Hide() return end
    self.newBtn.label:SetText(n == 1 and ns.T("1 nouveau message") or ns.Tf("%d nouveaux messages", n))
    self.newBtn:SetWidth(num(self.newBtn.label:GetStringWidth(), 110) + 16)
    self.newBtn:Show()
end

-- un message reçu : ajouté à la vue s'il est dans l'onglet affiché, sinon compté sur son onglet
function CW:OnEntry(e)
    if not (self.frame and self.frame:IsShown() and self.view) then return end
    if self:Matches(e) then
        if not try("message", self.Append, self, e) then self:Render() end
    elseif e.cat ~= GAME and e.cat ~= "all" then
        -- (pas de compteur sur Jeu : il grimperait sans arrêt)
        self.unread[e.cat] = (self.unread[e.cat] or 0) + 1
        self:PaintTabs()
    end
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local function textButton(parent, text, onClick)
    local T = ns.THEME
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(ns.T(text))
    b.label = label
    b:SetWidth(num(label:GetStringWidth(), 40) + 16)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.card[1], T.card[2], T.card[3], 0.0)
    b.bg = bg
    local line = b:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", 6, 0)
    line:SetPoint("BOTTOMRIGHT", -6, 0)
    line:SetHeight(2)
    line:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.95)
    line:Hide()
    b.line = line
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b:SetScript("OnClick", onClick)
    return b
end

function CW:PaintTabs()
    local T = ns.THEME
    for _, tab in ipairs(self.tabs or {}) do
        local active = tab.id == self.tab
        local n = self.unread[tab.id] or 0
        local text = ns.T(tab.def.label)
        if n > 0 and not active then text = text .. " " .. paint(T.gold, tostring(n)) end
        tab.label:SetText(text)
        tab:SetWidth(num(tab.label:GetStringWidth(), 40) + 16)
        local c = active and T.text or T.dim
        tab.label:SetTextColor(c[1], c[2], c[3])
        tab.line:SetShown(active)
        if tab.bg then tab.bg:SetColorTexture(1, 1, 1, active and 0.08 or 0) end   -- léger fond sur l'onglet actif
    end
end

function CW:SelectTab(id)
    self.tab = id
    self.unread[id] = 0
    self:PaintTabs()
    self:Render()
end

local function setSearch(text)
    CW.search = (text or ""):lower()
    CW:Render()
end

function CW:ApplyLook()
    local f = self.frame
    if not f then return end
    local W, T = ns.W, ns.THEME
    local alpha = tonumber(db("chatWinAlpha")) or 0.85
    if f.round then f.round:SetColor(W.C.bg, alpha) else f.flat:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], alpha) end
    self.fontSize = tonumber(db("chatWinFontSize")) or 13
    self.fontPath = fontPath()
end

-- position et taille : celles gardées, sinon par-dessus la fenêtre de chat principale du jeu
function CW:PlaceWindow()
    local f = self.frame
    local pos = db("chatWinPos")
    f:ClearAllPoints()
    if type(pos) == "table" and pos.x and pos.y and pos.w and pos.h then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        f:SetSize(max(pos.w, 380), max(pos.h, 140))   -- (au moins la place des onglets)
        return
    end
    local cf = api("ChatFrame1")
    local left, bottom = cf and num(cf:GetLeft(), nil), cf and num(cf:GetBottom(), nil)
    local w, h = cf and num(cf:GetWidth(), nil), cf and num(cf:GetHeight(), nil)
    if left and bottom and w and h and w > 50 and h > 50 then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - 8, max(4, bottom - 40))
        f:SetSize(max(380, w + 16), h + 40 + 34)
    else
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 110)
        f:SetSize(440, 240)
    end
end

function CW:SavePosition()
    local f = self.frame
    if not f then return end
    local left, bottom = num(f:GetLeft(), nil), num(f:GetBottom(), nil)
    if not (left and bottom) then return end
    ns.db.chatWinPos = { x = floor(left + 0.5), y = floor(bottom + 0.5), w = floor(num(f:GetWidth(), 440) + 0.5),
        h = floor(num(f:GetHeight(), 240) + 0.5) }
end

function CW:ResetPosition()
    ns.db.chatWinPos = {}
    if self.frame then self:PlaceWindow() end
end

onHyperlink = function(link, text, button)
    if type(link) ~= "string" or not readable(link) then return end
    if link:sub(1, #COPY_PREFIX) == COPY_PREFIX then
        copyEntry(CW:FindEntry(tonumber(link:sub(#COPY_PREFIX + 1))))
        return
    end
    if link:sub(1, #URL_PREFIX) == URL_PREFIX then
        if ns.Chat and ns.Chat.ShowCopy then ns.Chat:ShowCopy(ns.T("Lien web"), link:sub(#URL_PREFIX + 1)) end
        return
    end
    local setRef = api("SetItemRef")
    if setRef then try("lien", setRef, link, text, button, api("ChatFrame1")) end
end
CW.OnHyperlink = function(_, link, text, button) onHyperlink(link, text, button) end

local function build()
    local W, T = ns.W, ns.THEME
    local f = CreateFrame("Frame", "PlatyplusChatWindow", UIParent)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(380, 140) end
    f:Hide()
    if W and W.Round then
        f.round = W.Round(f, "BACKGROUND", -6, 10)
        W.Stroke(f, "BORDER", 0, 10):SetColor(W.C.white, 0.07)
    else
        f.flat = f:CreateTexture(nil, "BACKGROUND")
        f.flat:SetAllPoints()
    end

    -- bandeau : onglets, recherche ; on le tire pour déplacer la fenêtre
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 6, -4)
    head:SetPoint("TOPRIGHT", -6, -4)
    head:SetHeight(22)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() f:StartMoving() end)
    head:SetScript("OnDragStop", function() f:StopMovingOrSizing(); CW:SavePosition() end)
    f.head = head
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 4, -3)
    rule:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -4, -3)
    rule:SetHeight(1)
    rule:SetColorTexture(1, 1, 1, 0.07)

    CW.tabs = {}
    local prev
    for _, def in ipairs(CW.TABS) do
        local b = textButton(head, def.label, function(self) CW:SelectTab(self.id) end)
        b.id, b.def = def.id, def
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function() f:StartMoving() end)
        b:SetScript("OnDragStop", function() f:StopMovingOrSizing(); CW:SavePosition() end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("LEFT", head, "LEFT", 0, 0) end
        prev = b
        CW.tabs[#CW.tabs + 1] = b
    end

    -- recherche : la loupe ouvre une zone de texte à la place des onglets
    local search = CreateFrame("EditBox", nil, head)
    search:SetAutoFocus(false)
    search:SetFontObject("GameFontHighlightSmall")
    search:SetPoint("LEFT", head, "LEFT", 4, 0)
    search:SetPoint("RIGHT", head, "RIGHT", -28, 0)
    search:SetHeight(20)
    search:SetTextInsets(6, 6, 0, 0)
    local sbg = search:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(T.panel[1], T.panel[2], T.panel[3], 0.95)
    search:Hide()
    local function closeSearch()
        search:SetText("")
        search:ClearFocus()
        search:Hide()
        for _, b in ipairs(CW.tabs) do b:Show() end
        setSearch("")
    end
    search:SetScript("OnTextChanged", function(self) setSearch(self:GetText()) end)
    search:SetScript("OnEscapePressed", closeSearch)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.search = search
    local loupe = textButton(head, "Chercher", function()
        if search:IsShown() then
            closeSearch()
        else
            for _, b in ipairs(CW.tabs) do b:Hide() end
            search:Show()
            search:SetFocus()
        end
    end)
    loupe:SetPoint("RIGHT", head, "RIGHT", 0, 0)
    f.loupe = loupe

    -- messages : une zone qui coupe ce qui dépasse ; les lignes s'empilent depuis son bas (« floor »)
    local view = CreateFrame("Frame", nil, f)
    view:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    if view.SetClipsChildren then view:SetClipsChildren(true) end
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta) CW:Wheel(delta) end)
    local content = CreateFrame("Frame", nil, view)
    content:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
    local floorFrame = CreateFrame("Frame", nil, content)
    floorFrame:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, BOTTOM_PAD)
    floorFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, BOTTOM_PAD)
    floorFrame:SetHeight(1)
    local lastW, lastH
    view:SetScript("OnSizeChanged", function(_, w, h)
        w, h = floor(num(w, 0) + 0.5), floor(num(h, 0) + 0.5)
        if CW.active and (w ~= lastW or h ~= lastH) then
            lastW, lastH = w, h
            CW:Layout()
        end
    end)
    CW.view, CW.content, CW.floor = view, content, floorFrame
    CW.scroll = view     -- (ancien nom, gardé pour les autres fichiers)
    CW.rows, CW.shown, CW.list, CW.offset = {}, {}, {}, 0
    CW.pools = { bubble = {}, line = {}, secret = {} }

    local thumb = f:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.22)
    thumb:Hide()
    CW.thumb = thumb

    -- « nouveaux messages » quand on est remonté dans l'historique
    local newBtn = textButton(f, "Nouveaux messages", function() CW:ScrollToBottom() end)
    newBtn:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 2)
    newBtn:SetFrameLevel((view:GetFrameLevel() or 1) + 20)
    newBtn.bg:SetColorTexture(T.accent2[1], T.accent2[2], T.accent2[3], 0.95)
    newBtn:Hide()
    CW.newBtn = newBtn

    -- coin pour redimensionner
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel((view:GetFrameLevel() or 1) + 21)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); CW:SavePosition(); CW:Layout() end)

    CW.frame = f
    CW:PaintTabs()
    return f
end

---------------------------------------------------------------------------
-- Fenêtres de Blizzard rangées, zone de saisie posée chez nous
---------------------------------------------------------------------------
local stash = { parents = {}, edits = {} }
local hiddenParent
local editHooked = setmetatable({}, { __mode = "k" })   -- (rien n'est écrit dans les cadres de Blizzard)

local function chatFrames()
    if ns.ChatPlus and ns.ChatPlus.Frames then return ns.ChatPlus.Frames() end
    local list = {}
    for i = 1, tonumber(api("NUM_CHAT_WINDOWS")) or 10 do
        local f = api("ChatFrame" .. i)
        if f then list[#list + 1] = f end
    end
    return list
end

local function hide(frame)
    if not frame or stash.parents[frame] then return end
    stash.parents[frame] = frame:GetParent() or UIParent
    frame:SetParent(hiddenParent)
end

-- la zone de message laisse la place à la zone de saisie quand elle est ouverte
local function layoutForEdit()
    local f = CW.frame
    if not f then return end
    local open = false
    for eb in pairs(stash.edits) do
        if eb:IsShown() then open = true end
    end
    if open == CW.editOpen then return end
    CW.editOpen = open
    CW.view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, open and 38 or 10)
    CW:Layout()
end

local function takeEditBox(eb)
    if not eb or stash.edits[eb] then return end
    local points = {}
    for i = 1, eb:GetNumPoints() do points[i] = { eb:GetPoint(i) } end
    stash.edits[eb] = { parent = eb:GetParent(), points = points }
    eb:SetParent(CW.frame)
    eb:ClearAllPoints()
    eb:SetPoint("BOTTOMLEFT", CW.frame, "BOTTOMLEFT", 4, 2)
    eb:SetPoint("BOTTOMRIGHT", CW.frame, "BOTTOMRIGHT", -18, 2)
    if not editHooked[eb] then
        editHooked[eb] = true
        eb:HookScript("OnShow", function() if CW.active then layoutForEdit() end end)
        eb:HookScript("OnHide", function() if CW.active then layoutForEdit() end end)
    end
end

function CW:HideBlizzard()
    hiddenParent = hiddenParent or CreateFrame("Frame")
    hiddenParent:Hide()
    for _, frame in ipairs(chatFrames()) do
        local name = frame:GetName()
        takeEditBox(frame.editBox)
        hide(frame)
        if name then hide(api(name .. "Tab")) end
    end
    for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }) do
        hide(api(name))
    end
    layoutForEdit()
end

function CW:RestoreBlizzard()
    for frame, parent in pairs(stash.parents) do frame:SetParent(parent) end
    wipe(stash.parents)
    for eb, saved in pairs(stash.edits) do
        eb:SetParent(saved.parent)
        eb:ClearAllPoints()
        for _, p in ipairs(saved.points) do eb:SetPoint(unpack(p)) end
    end
    wipe(stash.edits)
end

---------------------------------------------------------------------------
-- Branchement
---------------------------------------------------------------------------
local hooked = setmetatable({}, { __mode = "k" })
local function hookFrames()
    for _, frame in ipairs(chatFrames()) do
        if not hooked[frame] and type(frame.AddMessage) == "function" then
            if pcall(hooksecurefunc, frame, "AddMessage", afterAddMessage) then hooked[frame] = true end
        end
    end
end

function CW:Apply()
    local want = db("chatWindow") and true or false
    if want then
        if self.broken then return end
        if not self.frame then
            -- si la fenêtre ne peut pas être construite, le chat du jeu reste tel quel
            if not try("création", build) or not self.frame then
                self.broken = true
                ns:Print("la fenêtre de chat n'a pas pu s'ouvrir : le chat du jeu reste affiché (/pp debug on pour le détail)")
                return
            end
        end
        self:ApplyLook()
        if not self.active then
            self:PlaceWindow()
            self.frame:Show()
            self.active = true
            self:HideBlizzard()
        end
        self:Render()
    elseif self.active then
        self:RestoreBlizzard()
        self.frame:Hide()
        self.active = false
    end
end

-- /pp chat : où en est la fenêtre
function CW:Status()
    local n = 0
    for _ in pairs(hooked) do n = n + 1 end
    local log = savedLog()
    local lines = {
        "fenêtre Platyplus : " .. (self.active and "affichée" or "coupée") .. ", " .. n .. " fenêtre(s) du jeu écoutée(s)",
        "messages en mémoire : " .. #self.store .. " (dont " .. (self.restoredCount or 0) .. " de la session précédente), "
            .. "journal sauvé pour ce personnage : " .. (log and #log or 0) .. " ligne(s), " .. (self.savedAtLoad or 0) .. " au chargement",
        "reçus depuis le chargement : " .. self.stats.withEvent .. " avec leur type, " .. self.stats.textOnly .. " lus dans le texte, "
            .. self.stats.secret .. " protégé(s), " .. self.stats.dropped .. " en erreur, " .. (self.stats.duplicates or 0)
            .. " doublon(s) d'une autre fenêtre écarté(s)",
        "vue : onglet " .. tostring(self.tab) .. ", " .. #(self.list or {}) .. " message(s), " .. #(self.rows or {})
            .. " dessiné(s), " .. (self.offset or 0) .. " cran(s) au-dessus du bas, " .. (self.stats.drawErrors or 0)
            .. " erreur(s) de dessin, " .. (self.stats.heightFixes or 0) .. " correction(s) de hauteur" .. (self.noSelfAnchor and ", lignes protégées en hauteur fixe" or ""),
    }
    if self.lastError then lines[#lines + 1] = "dernière erreur : " .. self.lastError end
    return lines
end

function CW:Init()
    if self.initialized then return end
    self.initialized = true
    local ok, n = pcall(self.Restore, self)
    if not ok then self.lastError = tostring(n); ns:Debug("fenêtre de chat (journal) :", n) end
    try("branchement", hookFrames)
    try("affichage", self.Apply, self)
    ns:OnChange("chatWindow", function() CW:Apply() end)
    ns:OnChange("chatWinTwoLines", function() if CW.active then CW:ApplyLook(); CW:Render() end end)
    ns:OnChange("chatWinChannelText", function() if CW.active then CW:Render() end end)
    ns:OnChange("chatWinFontSize", function() if CW.active then CW:ApplyLook(); CW:Render() end end)
    ns:OnChange("chatWinAlpha", function() if CW.active then CW:ApplyLook() end end)
    -- polices prêtes après l'écran de chargement : les hauteurs des messages déjà dessinés sont revérifiées
    local loading = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED" }) do pcall(loading.RegisterEvent, loading, ev) end
    loading:SetScript("OnEvent", function() CW:CheckLater(1); CW:CheckLater(4) end)
    CW:CheckLater(1)
    CW:CheckLater(4)
    -- fenêtres de chuchotement créées plus tard : écoutées et rangées elles aussi
    if api("FCF_OpenTemporaryWindow") then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            hookFrames()
            if CW.active then try("fenêtre", CW.HideBlizzard, CW) end
        end)
    end
end
