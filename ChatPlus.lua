-- Platyplus : chat amélioré (ns.ChatPlus), en plus de ns.Chat (Misc.lua : liens web, canaux courts, copie)
--  1. chatSkin        : look Platyplus. Fond uni (la couleur et la transparence restent celles réglées dans le jeu),
--                       sans les bords arrondis ; onglets plats soulignés ; zone de saisie sombre bordée de bleu
--  2. chatTimestamps  : l'heure devant chaque message (réglage du jeu « showTimestamps », valeur d'origine gardée)
--     chatClassColors : noms colorés selon la classe partout (réglage du jeu « chatClassColorOverride »)
--     chatMentions    : ton nom surligné quand quelqu'un l'écrit, avec un son (une fois par message)
--  3. chatHistory     : les dernières lignes de chaque fenêtre gardées pour la prochaine session (/reload compris)
--     chatSentHistory : flèches haut / bas (sans Alt) pour retrouver ce que tu as tapé, gardé lui aussi
--  4. chatSpam        : masque les messages répétés et les annonces de vente d'or ; mots à masquer (chatFilterWords)
--
-- Vérifié dans le code de Forever (Blizzard_ChatFrameBase) :
-- * filtres : ChatFrameUtil.AddMessageEventFilter ; Blizzard ne les appelle pas si un argument est secret ;
-- * le fond et les bords des fenêtres sont fondus par FCF_FadeIn/OutChatFrame tant qu'ils sont « montrés » : on ne les
--   cache jamais, on change seulement leur image (et on remet l'image d'origine si l'option est coupée) ;
-- * FCFTab_UpdateColors(onglet, sélectionné) dit quel onglet est actif ; FCF_OpenTemporaryWindow crée les fenêtres
--   de chuchotement ; la zone de saisie a ignoreArrows="true" (SetAltArrowKeyMode) et AddHistoryLine ;
-- * le jeu joue déjà un son à chaque chuchotement reçu (SOUNDKIT.TELL_MESSAGE) : rien à ajouter.
-- Jamais : remplacer une fonction ou un champ de Blizzard (seulement hooksecurefunc et nos propres textures).
local ADDON, ns = ...

local ChatPlus = {}
ns.ChatPlus = ChatPlus

local floor, max, min = math.floor, math.max, math.min

local function api(name) return rawget(_G, name) end
local function db(key) return ns.db and ns.db[key] end

-- vrai si l'addon peut lire cette valeur (les valeurs « secrètes » ne se lisent pas)
local function readable(v)
    local can = api("canaccessvalue")
    if type(can) == "function" then
        local ok, r = pcall(can, v)
        if ok then return r and true or false end
    end
    local secret = api("issecretvalue")
    if type(secret) == "function" then
        local ok, r = pcall(secret, v)
        if ok and r then return false end
    end
    return true
end
ChatPlus.Readable = readable

local function try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns:Debug("chat (" .. where .. ") :", err) end
    return ok
end

-- toutes les fenêtres de chat, fenêtres de chuchotement comprises
local function chatFrames()
    local list, seen = {}, {}
    local function add(f)
        if f and not seen[f] then seen[f] = true; list[#list + 1] = f end
    end
    for i = 1, tonumber(api("NUM_CHAT_WINDOWS")) or 10 do add(api("ChatFrame" .. i)) end
    local names = api("CHAT_FRAMES")
    if type(names) == "table" then
        for _, name in ipairs(names) do add(api(name)) end
    end
    return list
end
ChatPlus.Frames = chatFrames

local function isCombatLog(frame)
    local fn = api("IsCombatLog")
    if type(fn) == "function" then
        local ok, r = pcall(fn, frame)
        if ok then return r and true or false end
    end
    return frame == api("COMBATLOG")
end

-- « Nom-Royaume » de ce personnage (clé des historiques)
local function charKey()
    local name, realm
    local full = api("UnitFullName")
    if full then name, realm = full("player") end
    name = name or (api("UnitName") and UnitName("player")) or "?"
    if not realm or realm == "" then realm = (api("GetRealmName") and GetRealmName()) or "?" end
    return name .. "-" .. realm
end

local function color(c, text)
    return string.format("|cff%02x%02x%02x%s|r", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5), text)
end

---------------------------------------------------------------------------
-- 1. Look
---------------------------------------------------------------------------
local Skin = { saved = {}, frames = {} }
ChatPlus.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FRAME_BORDERS = {
    "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
    "ButtonFrameBackground", "ButtonFrameTopLeftTexture", "ButtonFrameBottomLeftTexture", "ButtonFrameTopRightTexture",
    "ButtonFrameBottomRightTexture", "ButtonFrameLeftTexture", "ButtonFrameRightTexture", "ButtonFrameBottomTexture",
    "ButtonFrameTopTexture",
}
local TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight" }
local EDIT_ART = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

-- change l'image d'une texture de Blizzard en gardant l'originale (remise par restore)
local function swap(tex, file)
    if not (tex and tex.SetTexture) then return end
    if Skin.saved[tex] == nil then Skin.saved[tex] = tex:GetTexture() or false end
    tex:SetTexture(file)
end

local function restoreAll()
    for tex, orig in pairs(Skin.saved) do
        tex:SetTexture(orig or nil)
    end
    wipe(Skin.saved)
end

local function extras(owner)
    owner.PlatyplusSkin = owner.PlatyplusSkin or {}
    return owner.PlatyplusSkin
end

-- onglet : fond discret, souligné bleu quand il est actif
local function paintTab(tab, selected)
    local x = tab and tab.PlatyplusSkin
    if not x then return end
    local on = db("chatSkin") and true or false
    x.bg:SetShown(on)
    x.line:SetShown(on and selected and true or false)
end

local function skinTab(tab, frame)
    if not tab then return end
    for _, key in ipairs(TAB_ART) do swap(tab[key], nil) end
    local x = extras(tab)
    if not x.bg then
        local T = ns.THEME
        x.bg = tab:CreateTexture(nil, "BACKGROUND")
        x.bg:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -6)
        x.bg:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 2)
        x.bg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.55)
        x.line = tab:CreateTexture(nil, "ARTWORK")
        x.line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 4, 2)
        x.line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 2)
        x.line:SetHeight(2)
        x.line:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.9)
    end
    paintTab(tab, api("SELECTED_CHAT_FRAME") == frame)
end

-- zone de saisie : fond sombre, fin cadre bleu
local function skinEditBox(eb)
    if not eb then return end
    local name = eb:GetName()
    for _, key in ipairs(EDIT_ART) do
        swap(name and api(name .. key), nil)
    end
    local x = extras(eb)
    if not x.bg then
        local T = ns.THEME
        x.bg = eb:CreateTexture(nil, "BACKGROUND")
        x.bg:SetPoint("TOPLEFT", eb, "TOPLEFT", 4, -3)
        x.bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -4, 3)
        x.bg:SetColorTexture(T.panel[1], T.panel[2], T.panel[3], 0.92)
        x.edges = {}
        for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local e = eb:CreateTexture(nil, "BORDER")
            e:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.55)
            if side == "TOP" or side == "BOTTOM" then
                e:SetPoint(side .. "LEFT", x.bg, side .. "LEFT", 0, 0)
                e:SetPoint(side .. "RIGHT", x.bg, side .. "RIGHT", 0, 0)
                e:SetHeight(1)
            else
                e:SetPoint("TOP" .. side, x.bg, "TOP" .. side, 0, 0)
                e:SetPoint("BOTTOM" .. side, x.bg, "BOTTOM" .. side, 0, 0)
                e:SetWidth(1)
            end
            x.edges[i] = e
        end
    end
    x.bg:Show()
    for _, e in ipairs(x.edges) do e:Show() end
end

local function hideExtras(owner)
    local x = owner and owner.PlatyplusSkin
    if not x then return end
    if x.bg then x.bg:Hide() end
    if x.line then x.line:Hide() end
    for _, e in ipairs(x.edges or {}) do e:Hide() end
end

local function skinFrame(frame)
    local name = frame:GetName()
    if not name then return end
    swap(frame.Background or api(name .. "Background"), WHITE)   -- couleur et transparence : celles du jeu
    for _, key in ipairs(FRAME_BORDERS) do swap(api(name .. key), nil) end
    skinTab(api(name .. "Tab"), frame)
    skinEditBox(frame.editBox or api(name .. "EditBox"))
    Skin.frames[frame] = true
end

function Skin:Apply()
    if db("chatSkin") then
        for _, frame in ipairs(chatFrames()) do try("look", skinFrame, frame) end
    else
        restoreAll()
        for frame in pairs(self.frames) do
            local name = frame:GetName()
            hideExtras(api(name .. "Tab"))
            hideExtras(frame.editBox or api(name .. "EditBox"))
        end
        wipe(self.frames)
    end
end

---------------------------------------------------------------------------
-- 2. Lisibilité
---------------------------------------------------------------------------
-- réglages du jeu, comme dans l'onglet « Jeu » : valeur d'origine gardée dans ns.db.cvarBackup, remise si on coupe
local CVAR_SETTINGS = {
    -- (format 24 h du jeu, une des valeurs de son menu : « 15:27 »)
    chatTimestamps = { cvars = { { "showTimestamps", api("TIMESTAMP_FORMAT_HHMM_24HR") or "%H:%M ", "none" } } },
    chatClassColors = { cvars = { { "chatClassColorOverride", "0", "1" } } },
}

local function applyCvar(key, startup)
    local GS = ns.GameSettings
    local entry = CVAR_SETTINGS[key]
    if not (GS and entry and GS:Available(entry)) then return end
    local on = db(key) and true or false
    local backup = type(ns.db.cvarBackup) == "table" and ns.db.cvarBackup or {}
    local name = entry.cvars[1][1]
    if startup then
        -- au chargement : seulement la toute première fois (ensuite, un changement fait dans les options du jeu
        -- reste respecté) ; jamais pour remettre l'ancienne valeur
        if on and backup[name] == nil and not GS:IsOn(entry) then GS:Set(entry, true) end
        return
    end
    if on ~= GS:IsOn(entry) then GS:Set(entry, on) end
end

local MENTION_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_EMOTE",
}
local MENTION_COLOR = "|cffffd133"
local LETTER = "[%w\128-\255]"   -- lettres (octets UTF-8 compris) : un nom n'est pas trouvé au milieu d'un mot

-- surligne `name` (mot entier, sans tenir compte des majuscules) hors des liens |H...|h ; renvoie le texte et
-- vrai s'il a été trouvé
local function highlightName(msg, name)
    if type(msg) ~= "string" or type(name) ~= "string" or name == "" then return msg, false end
    local lname = name:lower()
    local found = false
    local function inPlain(plain)
        local low = plain:lower()
        local out, pos = {}, 1
        while true do
            local s, e = low:find(lname, pos, true)
            if not s then break end
            local before = s > 1 and low:sub(s - 1, s - 1) or ""
            local after = low:sub(e + 1, e + 1)
            if not before:find(LETTER) and not after:find(LETTER) then
                out[#out + 1] = plain:sub(pos, s - 1)
                out[#out + 1] = MENTION_COLOR .. plain:sub(s, e) .. "|r"
                found = true
            else
                out[#out + 1] = plain:sub(pos, e)
            end
            pos = e + 1
        end
        out[#out + 1] = plain:sub(pos)
        return table.concat(out)
    end
    local parts, pos = {}, 1
    while true do
        local s, e = msg:find("|H.-|h.-|h", pos)
        if not s then break end
        parts[#parts + 1] = inPlain(msg:sub(pos, s - 1))
        parts[#parts + 1] = msg:sub(s, e)
        pos = e + 1
    end
    parts[#parts + 1] = inPlain(msg:sub(pos))
    return table.concat(parts), found
end
ChatPlus.HighlightName = highlightName

local myName
local lastMentionLine, lastMentionSound = nil, nil

local function sameAsMe(author)
    if type(author) ~= "string" then return false end
    local short = api("Ambiguate") and Ambiguate(author, "short") or author:match("^[^%-]+") or author
    return short == myName
end

local function mentionFilter(_, event, msg, author, ...)
    if not db("chatMentions") or not myName or sameAsMe(author) then return false end
    local new, found = highlightName(msg, myName)
    if not found then return false end
    local lineID = select(9, ...)   -- 11e argument de l'événement
    if lineID == nil or lineID ~= lastMentionLine then
        lastMentionLine = lineID
        local now = api("GetTime") and GetTime() or 0
        if not lastMentionSound or now - lastMentionSound > 3 then
            lastMentionSound = now
            local kit = api("SOUNDKIT")
            if api("PlaySound") then pcall(PlaySound, kit and kit.TELL_MESSAGE or 3081) end
            if api("FlashClientIcon") then pcall(FlashClientIcon) end
        end
    end
    return false, new, author, ...
end

---------------------------------------------------------------------------
-- 3. Mémoire
---------------------------------------------------------------------------
local Memory = { restoring = false }
ChatPlus.Memory = Memory
local MAX_LINES = 100     -- par fenêtre
local MAX_SENT = 32       -- comme l'historique de la zone de saisie (historyLines="32")

local function store(kind)
    if type(ns.db[kind]) ~= "table" then ns.db[kind] = {} end
    local key = charKey()
    ns.db[kind][key] = ns.db[kind][key] or {}
    return ns.db[kind][key]
end

local function afterAddMessage(frame, text, r, g, b)
    if Memory.restoring or not db("chatHistory") or isCombatLog(frame) then return end
    if type(text) ~= "string" or not readable(text) or text == "" then return end
    local name = frame:GetName()
    if not name then return end
    if db("chatShortChannels") and ns.Chat and ns.Chat.Shorten then
        local ok, short = pcall(ns.Chat.Shorten, text)
        if ok and type(short) == "string" then text = short end
    end
    local log = store("chatLog")
    local lines = log[name]
    if not lines then lines = {}; log[name] = lines end
    lines[#lines + 1] = { text, readable(r) and tonumber(r) or 1, readable(g) and tonumber(g) or 1, readable(b) and tonumber(b) or 1 }
    while #lines > MAX_LINES do table.remove(lines, 1) end
end

local function afterHistoryLine(_, text)
    if Memory.restoring or not db("chatSentHistory") then return end
    if type(text) ~= "string" or text == "" or not readable(text) then return end
    local list = store("chatSent")
    if list[#list] == text then return end
    list[#list + 1] = text
    while #list > MAX_SENT do table.remove(list, 1) end
end

-- remet les lignes de la session précédente dans chaque fenêtre (une fois, au chargement)
function Memory:Restore()
    if self.restored then return end
    self.restored = true
    local log = type(ns.db.chatLog) == "table" and ns.db.chatLog[charKey()]
    local sent = type(ns.db.chatSent) == "table" and ns.db.chatSent[charKey()]
    self.restoring = true
    if db("chatHistory") and log then
        for name, lines in pairs(log) do
            local frame = api(name)
            if frame and frame.AddMessage and #lines > 0 then
                local dim = ns.THEME.dim
                for _, l in ipairs(lines) do
                    try("historique", frame.AddMessage, frame, l[1], (l[2] or 1) * 0.8, (l[3] or 1) * 0.8, (l[4] or 1) * 0.8)
                end
                try("historique", frame.AddMessage, frame, color(dim, ns.T("— fin de la session précédente —")), dim[1], dim[2], dim[3])
            end
        end
    end
    if db("chatSentHistory") and sent then
        for _, frame in ipairs(chatFrames()) do
            local eb = frame.editBox
            if eb and eb.AddHistoryLine then
                for _, text in ipairs(sent) do try("historique", eb.AddHistoryLine, eb, text) end
            end
        end
    end
    self.restoring = false
end

function Memory:Clear()
    if type(ns.db.chatLog) == "table" then ns.db.chatLog[charKey()] = nil end
    if type(ns.db.chatSent) == "table" then ns.db.chatSent[charKey()] = nil end
end

-- nombre de lignes gardées pour ce personnage
function Memory:Count()
    local n = 0
    local log = type(ns.db.chatLog) == "table" and ns.db.chatLog[charKey()]
    for _, lines in pairs(log or {}) do n = n + #lines end
    local sent = type(ns.db.chatSent) == "table" and ns.db.chatSent[charKey()]
    return n, sent and #sent or 0
end

---------------------------------------------------------------------------
-- 4. Anti-spam
---------------------------------------------------------------------------
local Spam = { hidden = 0, recent = {}, seen = {}, decided = {}, decidedCount = 0 }
ChatPlus.Spam = Spam

local SPAM_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_EMOTE" }
local REPEAT_WINDOW = 120      -- secondes : le même message du même joueur est masqué pendant ce temps
local REPEAT_EVENTS = { CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true }

-- « gold » en mot entier (pas « golden ») ; ses formes collées ou maquillées dans le texte sans espaces
local GOLD_COMPACT = { "wowgold", "g0ld", "piecesdor", "piècesdor", "buygold", "cheapgold", "goldfast" }
local SHOP_WORDS = { "cheap", "pascher", "bonprix", "price", "prix", "discount", "promo", "delivery", "livraison",
    "instant", "fast", "rapide", "buy", "achat", "acheter", "sell", "vente", "safe", "coupon", "code", "24/7", "24h" }
local URL_HINTS = { "www", "http", "%.com", "%.net", "%.org", "%.cn", "%.ru", "c0m", "dotcom", "%. ?com" }

-- texte sans couleurs ni liens, en minuscules ; et sans espaces ni ponctuation
local function plainText(msg)
    local s = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return s:lower()
end

local function compact(s)
    return (s:gsub("[%s%p]", ""))
end

local function countWords(s, words)
    local n = 0
    for _, w in ipairs(words) do
        if s:find(w, 1, true) then n = n + 1 end
    end
    return n
end

-- annonce de vente d'or : un mot « or » et (une adresse web, une monnaie réelle, ou deux mots de boutique)
function Spam.IsGoldSpam(msg)
    if type(msg) ~= "string" then return false end
    local s = plainText(msg)
    local c = compact(s)
    if not (s:find("%f[%w]golds?%f[%W]") or countWords(c, GOLD_COMPACT) > 0) then return false end
    for _, hint in ipairs(URL_HINTS) do
        if s:find(hint) then return true end
    end
    -- monnaie réelle (mots entiers : « eur » est dans « joueur »)
    if s:find("%$") or s:find("€", 1, true) or s:find("%f[%w]usd%f[%W]") or s:find("%f[%w]eur%f[%W]") then return true end
    return countWords(c, SHOP_WORDS) >= 2
end

-- un des mots choisis par le joueur ?
function Spam.HasWord(msg)
    local words = db("chatFilterWords")
    if type(words) ~= "table" or type(msg) ~= "string" then return nil end
    local s = plainText(msg)
    for _, w in ipairs(words) do
        if type(w) == "string" and w ~= "" and s:find(w:lower(), 1, true) then return w end
    end
    return nil
end

-- ne jamais masquer : toi, un MJ, un ami, quelqu'un de ta guilde ou de ton groupe
local function trusted(author, flags, guid)
    if sameAsMe(author) then return true end
    if flags == "GM" or flags == "DEV" then return true end
    if type(guid) == "string" and guid ~= "" then
        local fl = api("C_FriendList")
        if fl and fl.IsFriend then
            local ok, r = pcall(fl.IsFriend, guid)
            if ok and r then return true end
        end
        local guild = api("IsGuildMember")
        if guild then
            local ok, r = pcall(guild, guid)
            if ok and r then return true end
        end
    end
    if type(author) == "string" and author ~= "" then
        local short = api("Ambiguate") and Ambiguate(author, "none") or author
        if (api("UnitInParty") and UnitInParty(short)) or (api("UnitInRaid") and UnitInRaid(short)) then return true end
    end
    return false
end

local function remember(author, msg, why)
    Spam.hidden = Spam.hidden + 1
    local clean = ns.Chat and ns.Chat.CleanLine and ns.Chat.CleanLine(msg) or msg
    table.insert(Spam.recent, { api("date") and date("%H:%M") or "", tostring(author or "?"), tostring(clean), why })
    while #Spam.recent > 50 do table.remove(Spam.recent, 1) end
end

-- décision pour un message (true = masquer) ; why : raison lisible
function Spam.Judge(event, msg, author, flags, guid, now)
    if trusted(author, flags, guid) then return false end
    local word = Spam.HasWord(msg)
    if word then return true, ns.Tf("mot « %s »", word) end
    if Spam.IsGoldSpam(msg) then return true, ns.T("vente d'or") end
    if REPEAT_EVENTS[event] then
        local key = tostring(author) .. "\1" .. compact(plainText(msg))
        local last = Spam.seen[key]
        Spam.seen[key] = now
        if last and now - last < REPEAT_WINDOW then return true, ns.T("répété") end
    end
    return false
end

local function pruneSeen(now)
    local n = 0
    for key, t in pairs(Spam.seen) do
        if now - t > REPEAT_WINDOW then Spam.seen[key] = nil else n = n + 1 end
    end
    return n
end

local function spamFilter(_, event, msg, author, ...)
    if not db("chatSpam") or type(msg) ~= "string" then return false end
    local flags = select(4, ...)       -- 6e argument
    local lineID = select(9, ...)      -- 11e
    local guid = select(10, ...)       -- 12e
    -- un même message passe par chaque fenêtre de chat qui l'affiche : une seule décision par ligne
    if lineID ~= nil and Spam.decided[lineID] ~= nil then return Spam.decided[lineID] end
    local now = api("GetTime") and GetTime() or 0
    local hide, why = Spam.Judge(event, msg, author, flags, guid, now)
    if hide then remember(author, msg, why) end
    if lineID ~= nil then
        Spam.decided[lineID] = hide and true or false
        Spam.decidedCount = Spam.decidedCount + 1
        if Spam.decidedCount > 500 then
            wipe(Spam.decided)
            Spam.decidedCount = 0
            pruneSeen(now)
        end
    end
    return hide and true or false
end

-- /pp spam ajouter|retirer MOT, /pp spam (liste, compte, derniers messages masqués)
function Spam:AddWord(word)
    word = strtrim(word or ""):lower()
    if word == "" then return false end
    local list = ns.db.chatFilterWords
    if type(list) ~= "table" then list = {}; ns.db.chatFilterWords = list end
    for _, w in ipairs(list) do if w == word then return false end end
    list[#list + 1] = word
    ns:Notify("chatFilterWords")
    return true
end

function Spam:RemoveWord(word)
    word = strtrim(word or ""):lower()
    local list = ns.db.chatFilterWords
    if type(list) ~= "table" then return false end
    for i, w in ipairs(list) do
        if w == word then
            table.remove(list, i)
            ns:Notify("chatFilterWords")
            return true
        end
    end
    return false
end

-- texte des derniers messages masqués (pour la fenêtre de copie)
function Spam:RecentText()
    if #self.recent == 0 then return ns.T("Aucun message masqué depuis le chargement.") end
    local lines = {}
    for i = #self.recent, 1, -1 do
        local r = self.recent[i]
        lines[#lines + 1] = string.format("%s  [%s] (%s)  %s", r[1], r[2], r[4] or "?", r[3])
    end
    return table.concat(lines, "\n")
end

function Spam:ShowRecent()
    if ns.Chat and ns.Chat.ShowCopy then
        ns.Chat:ShowCopy(ns.T("Messages masqués par l'anti-spam"), self:RecentText())
    else
        print(self:RecentText())
    end
end

---------------------------------------------------------------------------
-- Branchement
---------------------------------------------------------------------------
local filtersOn = {}
local function setFilters(name, events, fn, want)
    local util = api("ChatFrameUtil")
    local add = util and util.AddMessageEventFilter or api("ChatFrame_AddMessageEventFilter")
    local remove = util and util.RemoveMessageEventFilter or api("ChatFrame_RemoveMessageEventFilter")
    want = want and true or false
    if (filtersOn[name] or false) == want or not add then return end
    for _, event in ipairs(events) do
        if want then pcall(add, event, fn) elseif remove then pcall(remove, event, fn) end
    end
    filtersOn[name] = want
end

local hookedFrames = setmetatable({}, { __mode = "k" })
local hookedEdits = setmetatable({}, { __mode = "k" })

local function hookFrames()
    for _, frame in ipairs(chatFrames()) do
        if not hookedFrames[frame] and type(frame.AddMessage) == "function" then
            if pcall(hooksecurefunc, frame, "AddMessage", afterAddMessage) then hookedFrames[frame] = true end
        end
        local eb = frame.editBox
        if eb and not hookedEdits[eb] and type(eb.AddHistoryLine) == "function" then
            if pcall(hooksecurefunc, eb, "AddHistoryLine", afterHistoryLine) then hookedEdits[eb] = true end
        end
        -- flèches haut / bas sans Alt pour l'historique de ce que tu as tapé
        if eb and eb.SetAltArrowKeyMode then pcall(eb.SetAltArrowKeyMode, eb, not db("chatSentHistory")) end
    end
end

function ChatPlus:Apply()
    hookFrames()
    Skin:Apply()
    setFilters("spam", SPAM_EVENTS, spamFilter, db("chatSpam"))
    setFilters("mentions", MENTION_EVENTS, mentionFilter, db("chatMentions"))
end

function ChatPlus:Init()
    if self.initialized then return end
    self.initialized = true
    myName = api("UnitName") and UnitName("player") or nil
    if type(ns.db.chatFilterWords) ~= "table" then ns.db.chatFilterWords = {} end

    -- les lignes de la session précédente d'abord (avant les nouveaux messages), sans les réenregistrer
    hookFrames()
    try("historique", Memory.Restore, Memory)
    self:Apply()
    applyCvar("chatTimestamps", true)
    applyCvar("chatClassColors", true)

    for _, key in ipairs({ "chatSkin", "chatSpam", "chatMentions", "chatSentHistory" }) do
        ns:OnChange(key, function() ChatPlus:Apply() end)
    end
    ns:OnChange("chatTimestamps", function() applyCvar("chatTimestamps") end)
    ns:OnChange("chatClassColors", function() applyCvar("chatClassColors") end)

    -- fenêtres de chuchotement créées plus tard ; onglet actif
    if api("FCF_OpenTemporaryWindow") then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() try("fenêtre", ChatPlus.Apply, ChatPlus) end)
    end
    if api("FCFTab_UpdateColors") then
        hooksecurefunc("FCFTab_UpdateColors", function(tab, selected) paintTab(tab, selected) end)
    end
end

-- /pp chat : état
function ChatPlus:Status()
    local onoff = function(v) return v and "|cff00ff00ON|r" or "|cffff4040OFF|r" end
    local lines, sent = Memory:Count()
    local words = db("chatFilterWords") or {}
    return {
        "look : " .. onoff(db("chatSkin")) .. " ; heure : " .. onoff(db("chatTimestamps"))
            .. " ; couleurs de classe : " .. onoff(db("chatClassColors")) .. " ; ton nom surligné : " .. onoff(db("chatMentions")),
        "mémoire : " .. onoff(db("chatHistory")) .. " (" .. lines .. " lignes gardées) ; ce que tu tapes : "
            .. onoff(db("chatSentHistory")) .. " (" .. sent .. " lignes)",
        "anti-spam : " .. onoff(db("chatSpam")) .. " ; " .. Spam.hidden .. " message(s) masqué(s) depuis le chargement ; mots : "
            .. (#words > 0 and table.concat(words, ", ") or "aucun"),
    }
end
