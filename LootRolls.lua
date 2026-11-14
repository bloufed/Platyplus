-- Platyplus : suivi des jets de butin (donjon, raid)
-- Une fenêtre Platyplus qui montre, boss par boss, chaque objet mis aux dés : qui a choisi Besoin, Cupidité ou Passer,
-- la valeur de son dé, sa classe (nom à la couleur de la classe), qui mène, qui a gagné, et le temps qui reste.
--
-- Source : l'historique de butin du jeu (C_LootHistory), le même que la fenêtre GroupLootHistoryFrame de Blizzard.
-- Vérifié dans le code de Forever : Blizzard_FrameXML.toc charge Mainline\LootHistory.lua (Camelot ne fait que couper
-- l'ouverture automatique) ; LootHistoryDocumentation.lua : GetAllEncounterInfos() -> { encounterName, encounterID,
-- startTime, duration } ; GetSortedDropsForEncounter(id) / GetSortedInfoForDrop(id, lootListKey) -> { lootListKey,
-- itemHyperlink, playerRollState, currentLeader, isTied, winner, allPassed, rollInfos = { playerName, playerClass, isSelf,
-- state, isWinner, roll? }, startTime, duration } ; GetLootHistoryTime() (même base de temps que startTime : la barre de
-- Blizzard fait (GetLootHistoryTime() - startTime) / duration). Événements LOOT_HISTORY_UPDATE_DROP (encounterID,
-- lootListKey), LOOT_HISTORY_UPDATE_ENCOUNTER (encounterID), LOOT_HISTORY_CLEAR_HISTORY ; START_LOOT_ROLL (rollID, ...).
-- Enum.EncounterLootDropRollState : NeedMainSpec 0, NeedOffSpec 1, Transmog 2, Greed 3, NoRoll 4 (pas encore choisi), Pass 5.
-- Aucun drapeau secret sur ces retours ; par prudence un nom, une classe ou un dé secret est affiché tel quel (SetText),
-- sans comparaison. NON VÉRIFIÉ en jeu : l'unité de startTime/duration (secondes supposées ; > 1000 = millisecondes).
--
-- Pas de boucle permanente : la fenêtre ne tourne (OnUpdate, 5 fois par seconde) que si un objet affiché est en cours.
local ADDON, ns = ...

local LR = {}
ns.LootRolls = LR

local floor, max, min = math.floor, math.max, math.min

local WIDTH, HEIGHT = 440, 500
local NAV_H = 34
local CARD_GAP = 8
local CARD_PAD = 10
local ICON = 34
local ROW_H = 20
local PILL_W = 64
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CHECK_TEX = "Interface\\RaidFrame\\ReadyCheck-Ready"
local AUTO_CLOSE_DELAY = 20              -- s après le dernier jet terminé (fenêtre ouverte toute seule)

local NO_ROLL = 4
local STATES = {                         -- état du joueur -> pastille
    [0] = { text = "Besoin",   color = { 0.95, 0.60, 0.22 } },
    [1] = { text = "Spé 2",    color = { 0.90, 0.75, 0.35 }, tip = "Besoin pour sa 2e spécialisation" },
    [2] = { text = "Transmo",  color = { 0.75, 0.55, 1.00 } },
    [3] = { text = "Cupidité", color = { 0.40, 0.82, 0.40 } },
    [4] = { text = "Attente",  color = { 0.55, 0.58, 0.64 } },
    [5] = { text = "Passe",    color = { 0.55, 0.58, 0.64 } },
}
local CLASS_FR = {
    WARRIOR = "Guerrier", PALADIN = "Paladin", HUNTER = "Chasseur", ROGUE = "Voleur", PRIEST = "Prêtre",
    SHAMAN = "Chaman", MAGE = "Mage", WARLOCK = "Démoniste", DRUID = "Druide", DEATHKNIGHT = "Chevalier de la mort",
    MONK = "Moine", DEMONHUNTER = "Chasseur de démons", EVOKER = "Évocateur",
}

local W, C, Win
local frame, area, navTitle, navCount, prevBtn, nextBtn, emptyText
local cards = {}                         -- cartes réutilisées
local encounters = {}                    -- liste triée (la plus récente d'abord)
local index = 1                          -- rencontre affichée (1 = la plus récente)
local followLatest = true                -- la vue suit le dernier boss tant qu'on n'a pas remonté l'historique
local seen = {}                          -- ["enc:clé"] = true : objets déjà vus (ouverture auto seulement sur un nouveau)
local pending = {}                       -- cartes dont les jets sont en cours (minuteur)
local events, refreshQueued, openedAuto, closeToken = nil, false, false, 0
local demo                               -- données d'exemple (/pp jets demo) ou nil
local closedByUser, autoHiding = false, false   -- fermée à la main : pas de réouverture auto avant le prochain boss
local lastEncounter                      -- dernier encounterID vu dans les événements
local EVENT_DELAY = 0.25                 -- en raid, les choix arrivent en rafale : une relecture par quart de seconde
local mode = "loot"                      -- onglet affiché : "loot" (dés du jeu) ou "roll" (/roll tapés à la main)
local series = {}                        -- séries de /roll, la plus récente d'abord
local lastItem                           -- dernier objet lié dans le chat du groupe : { link, at, used }
local tabs = {}                          -- boutons d'onglet du bandeau
local clearBtn

local function api(name) return rawget(_G, name) end

local function isSecret(v)
    local f = api("issecretvalue")
    return f and f(v) and true or false
end

-- valeur lisible, ou nil si secrète
local function plain(v)
    if isSecret(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- Données : le jeu, ou l'exemple
---------------------------------------------------------------------------
local Live = {}

function Live.now()
    local H = api("C_LootHistory")
    if H and H.GetLootHistoryTime then
        local ok, t = pcall(H.GetLootHistoryTime)
        if ok and type(plain(t)) == "number" then return t end
    end
    return GetTime and GetTime() or 0
end

function Live.encounters()
    local H = api("C_LootHistory")
    if not (H and H.GetAllEncounterInfos) then return {} end
    local ok, list = pcall(H.GetAllEncounterInfos)
    if not ok or type(list) ~= "table" then return {} end
    return list
end

function Live.drops(id)
    local H = api("C_LootHistory")
    if not (H and H.GetSortedDropsForEncounter) then return {} end
    local ok, list = pcall(H.GetSortedDropsForEncounter, id)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for i, drop in ipairs(list) do
        local info = drop
        -- la version « triée » d'un objet (joueurs rangés comme dans l'infobulle de Blizzard)
        if H.GetSortedInfoForDrop and not isSecret(drop.lootListKey) and drop.lootListKey ~= nil then
            local ok2, sorted = pcall(H.GetSortedInfoForDrop, id, drop.lootListKey)
            if ok2 and type(sorted) == "table" then info = sorted end
        end
        out[i] = info
    end
    return out
end

local Demo = {}

function Demo.now() return GetTime and GetTime() or 0 end
function Demo.encounters() return demo and demo.encounters or {} end
function Demo.drops(id) return demo and demo.drops[id] or {} end

local function source() return demo and Demo or Live end

local function buildDemo()
    local t = Demo.now()
    local function r(name, class, state, roll, win, self)
        return { playerName = name, playerClass = class, state = state, roll = roll, isWinner = win or false, isSelf = self or false }
    end
    local link = function(hex, id, name) return "|cff" .. hex .. "|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r" end
    local winner = r("Brakmar", "WARRIOR", 0, 91, true, true)
    local d1 = {
        lootListKey = 1, itemHyperlink = link("a335ee", 19019, "Lame du crépuscule"), playerRollState = 0, demoSlot = "Deux mains",
        winner = winner, allPassed = false, startTime = t - 90, duration = 60,
        rollInfos = { winner, r("Ysolde", "PALADIN", 0, 64), r("Kerrigane", "ROGUE", 1, 88),
            r("Morwen", "MAGE", 3, 97), r("Tilda", "PRIEST", 5) },
    }
    local leader = r("Ysolde", "PALADIN", 3, 72)
    local d2 = {
        lootListKey = 2, itemHyperlink = link("0070dd", 13965, "Bottes de l'éclaireur"), playerRollState = 3, demoSlot = "Pieds",
        currentLeader = leader, allPassed = false, startTime = t - 12, duration = 60,
        rollInfos = { leader, r("Brakmar", "WARRIOR", 3, 41, false, true), r("Kerrigane", "ROGUE", 5),
            r("Morwen", "MAGE", NO_ROLL), r("Tilda", "PRIEST", NO_ROLL) },
    }
    local d3 = {
        lootListKey = 3, itemHyperlink = link("1eff00", 2140, "Anneau de cuivre terne"), playerRollState = 5, demoSlot = "Doigt",
        allPassed = true, startTime = t - 80, duration = 60,
        rollInfos = { r("Brakmar", "WARRIOR", 5, nil, false, true), r("Ysolde", "PALADIN", 5), r("Kerrigane", "ROGUE", 5),
            r("Morwen", "MAGE", 5), r("Tilda", "PRIEST", 5) },
    }
    local function m(name, class, roll, low, high, again, self)
        return { name = name, class = class, roll = roll, low = low or 1, high = high or 100, again = again or false, isSelf = self or false }
    end
    local date = api("date")
    local clock = date and date("%H:%M") or "21:42"
    return {
        series = {
            { clock = clock, item = link("a335ee", 18832, "Marteau de l'aube"), rolls = {
                m("Brakmar", "WARRIOR", 87, 1, 100, false, true), m("Ysolde", "PALADIN", 92), m("Kerrigane", "ROGUE", 45),
                m("Tilda", "PRIEST", 30, 1, 50), m("Kerrigane", "ROGUE", 99, 1, 100, true) } },
            { clock = clock, rolls = { m("Morwen", "MAGE", 64), m("Brakmar", "WARRIOR", 12, 1, 100, false, true) } },
        },
        encounters = {
            { encounterID = 2, encounterName = "Edwin VanCleef (exemple)", startTime = t - 100, duration = 0 },
            { encounterID = 1, encounterName = "Cookie (exemple)", startTime = t - 600, duration = 0 },
        },
        drops = {
            [2] = { d2, d1, d3 },
            [1] = { {
                lootListKey = 1, itemHyperlink = link("0070dd", 5197, "Gourdin du cuistot"), playerRollState = 3, demoSlot = "Une main",
                winner = r("Morwen", "MAGE", 3, 77, true), startTime = t - 610, duration = 60,
                rollInfos = { r("Morwen", "MAGE", 3, 77, true), r("Brakmar", "WARRIOR", 3, 12, false, true),
                    r("Tilda", "PRIEST", 5), r("Ysolde", "PALADIN", 5), r("Kerrigane", "ROGUE", 5) },
            } },
        },
    }
end

---------------------------------------------------------------------------
-- Petites aides d'affichage
---------------------------------------------------------------------------
local function classColorHex(class)
    class = plain(class)
    local colors = api("RAID_CLASS_COLORS")
    local c = type(class) == "string" and type(colors) == "table" and colors[class]
    if not c then return "ffffff" end
    return string.format("%02x%02x%02x", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5))
end

local function className(class)
    class = plain(class)
    if type(class) ~= "string" then return "" end
    local loc = api("LOCALIZED_CLASS_NAMES_MALE")
    return (CLASS_FR[class] and ns.T(CLASS_FR[class])) or (type(loc) == "table" and loc[class]) or class
end

-- texte « Nom » à la couleur de sa classe (nom secret : renvoyé brut, à passer seul à SetText)
local function coloredName(info)
    local name = info and info.playerName
    if isSecret(name) then return name, true end
    return "|cff" .. classColorHex(info.playerClass) .. tostring(name or "?") .. "|r", false
end

local function stateOf(info)
    local s = plain(info and info.state)
    return type(s) == "number" and STATES[s] and s or nil
end

-- nom et couleur de l'objet tirés du lien (sans attendre le cache des objets)
local function itemFromLink(link)
    link = plain(link)
    if type(link) ~= "string" then return ns.T("Objet"), "ffffffff", DEFAULT_ICON, nil end
    local name = link:match("%[(.-)%]") or link
    -- Forever écrit aussi ses liens « |cnIQ4:|Hitem:… » (qualité au lieu de la couleur, voir Float.lua)
    local iq = tonumber(link:match("|cnIQ(%d+):") or "")
    local quality = iq and ns.W and ns.W.QUALITY and ns.W.QUALITY[iq]
    local color = quality and ("ff" .. quality.hex) or link:match("|c(%x%x%x%x%x%x%x%x)") or "ffffffff"
    local icon, equipLoc = DEFAULT_ICON, nil
    local items = api("C_Item")
    local instant = (items and items.GetItemInfoInstant) or api("GetItemInfoInstant")
    if instant then
        local ok, _, _, _, loc, tex = pcall(instant, link)
        if ok then
            if tex then icon = tex end
            if type(loc) == "string" and loc ~= "" then equipLoc = loc end
        end
    end
    local slot = equipLoc and type(api(equipLoc)) == "string" and api(equipLoc) or nil
    return name, color, icon, slot
end

-- début et durée des jets : ceux de l'objet, sinon ceux de la rencontre (le minuteur de Blizzard lit la rencontre)
local function timing(drop)
    local start, dur = plain(drop.startTime), plain(drop.duration)
    if type(start) == "number" and type(dur) == "number" and dur > 0 then return start, dur end
    local enc = drop.ppEnc
    start, dur = enc and plain(enc.startTime), enc and plain(enc.duration)
    if type(start) == "number" and type(dur) == "number" and dur > 0 then return start, dur end
end

-- secondes restantes, part restante 0..1, secondes de retard après la fin
local function remaining(drop, now)
    local start, dur = timing(drop)
    if not start then return nil end
    local left = dur - (now - start)
    local scale = dur > 1000 and 1000 or 1        -- millisecondes ?
    return max(0, left / scale), max(0, min(1, left / dur)), max(0, -left / scale)
end

local OVERDUE = 15                       -- s après la fin du temps : objet considéré terminé (gagnant jamais connu)

local function isDone(drop, now)
    if plain(drop.allPassed) == true or (drop.winner ~= nil and not isSecret(drop.winner)) then return true end
    local _, _, late = remaining(drop, now)
    return late ~= nil and late > OVERDUE
end

---------------------------------------------------------------------------
-- Cartes (une par objet) et lignes (une par joueur)
---------------------------------------------------------------------------
local function newRow(card)
    local r = CreateFrame("Frame", nil, card)
    r:SetHeight(ROW_H)
    r.hl = W.Round(r, "BACKGROUND", 1, 5)
    r.hl:SetColor(C.gold, 0.12)
    r.pill = CreateFrame("Frame", nil, r)
    r.pill:SetSize(PILL_W, 16)
    r.pill:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.pill.bg = W.Pill(r.pill, "ARTWORK", 0, 16)
    r.pill.text = W.Text(r.pill, nil, C.text, "OVERLAY", 10)
    r.pill.text:SetPoint("CENTER", 0, 0)
    r.name = W.Text(r, nil, C.text, "OVERLAY", 13)
    r.name:SetPoint("LEFT", r.pill, "RIGHT", 8, 0)
    r.name:SetWidth(150)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.class = W.Text(r, nil, C.dim, "OVERLAY", 11)
    r.class:SetPoint("LEFT", r, "LEFT", PILL_W + 170, 0)
    r.class:SetWidth(100)
    r.class:SetJustifyH("LEFT")
    if r.class.SetWordWrap then r.class:SetWordWrap(false) end
    r.roll = W.Text(r, nil, C.text, "OVERLAY", 14)
    r.roll:SetPoint("RIGHT", r, "RIGHT", -28, 0)
    r.roll:SetJustifyH("RIGHT")
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(14, 14)
    r.check:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.check:SetTexture(CHECK_TEX)
    return r
end

local function showTooltip(owner, link)
    local tip = api("GameTooltip")
    if not (tip and type(plain(link)) == "string") then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    pcall(tip.SetHyperlink, tip, link)
    tip:Show()
end

local function newCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c.bg = W.Round(c, "BACKGROUND", 0, 8)
    c.bg:SetColor(C.card, 1)

    c.iconBtn = CreateFrame("Button", nil, c)
    c.iconBtn:SetSize(ICON, ICON)
    c.iconBtn:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD, -CARD_PAD)
    c.icon = W.Icon(c.iconBtn, ICON, "ARTWORK")
    c.icon:SetPoint("CENTER")
    c.ring = W.Stroke(c.iconBtn, "OVERLAY", 0, 4)
    c.ring:AnchorBox(c.iconBtn, -1, -1, -1, -1)
    c.iconBtn:SetScript("OnEnter", function(self) showTooltip(self, c.link) end)
    c.iconBtn:SetScript("OnLeave", function(self)
        local tip = api("GameTooltip")
        if tip and (not tip.IsOwned or tip:IsOwned(self)) then tip:Hide() end
    end)
    c.iconBtn:SetScript("OnClick", function()
        local modified, handle = api("IsModifiedClick"), api("HandleModifiedItemClick")
        if c.link and modified and handle and modified() then pcall(handle, c.link) end   -- Maj+clic : lien dans le chat
    end)

    c.slot = W.Text(c, nil, C.dim, "OVERLAY", 11)
    c.slot:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -CARD_PAD - 2)
    c.slot:SetJustifyH("RIGHT")
    c.name = W.Text(c, nil, C.text, "OVERLAY", 14)
    c.name:SetPoint("TOPLEFT", c.iconBtn, "TOPRIGHT", 10, -1)
    c.name:SetPoint("RIGHT", c.slot, "LEFT", -8, 0)
    c.name:SetJustifyH("LEFT")
    if c.name.SetWordWrap then c.name:SetWordWrap(false) end
    c.status = W.Text(c, nil, C.dim, "OVERLAY", 12)
    c.status:SetPoint("BOTTOMLEFT", c.iconBtn, "BOTTOMRIGHT", 10, 1)
    c.status:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.status:SetJustifyH("LEFT")
    if c.status.SetWordWrap then c.status:SetWordWrap(false) end

    c.bar = Win.Bar(c, 5)
    c.bar:SetPoint("TOPLEFT", c.iconBtn, "BOTTOMLEFT", 0, -6)
    c.bar:SetPoint("RIGHT", c, "RIGHT", -CARD_PAD, 0)
    c.bar:SetColor(C.accent)
    c.rows = {}
    return c
end

-- texte de la ligne d'état d'un objet (temps compris pour un objet en cours)
local function statusText(drop, now)
    if plain(drop.allPassed) == true then
        return W.Color("dim", ns.T("Tout le monde a passé"))
    end
    local win = drop.winner
    if win and not isSecret(win) then
        local name, secret = coloredName(win)
        if secret then return name end
        local s = stateOf(win)
        local roll = plain(win.roll)
        local how = (s and ns.T(STATES[s].text) or "") .. (type(roll) == "number" and (" " .. roll) or "")
        return ns.Tf("Gagné par %s", name) .. (how ~= "" and W.Color("dim", " · " .. how) or "")
    end
    if isDone(drop, now) then return W.Color("dim", ns.T("Temps écoulé · gagnant inconnu")) end
    local text = W.Color("accent", ns.T("Jets en cours"))
    local secs = remaining(drop, now)
    if secs then text = text .. W.Color("dim", string.format(" · %d s", floor(secs + 0.5))) end
    local lead = drop.currentLeader
    if plain(drop.isTied) == true then
        text = text .. W.Color("dim", ns.T(" · égalité"))
    elseif lead and not isSecret(lead) then
        local name, secret = coloredName(lead)
        local roll = plain(lead.roll)
        if not secret then
            text = text .. W.Color("dim", ns.T(" · en tête : ")) .. name .. (type(roll) == "number" and W.Color("dim", " " .. roll) or "")
        end
    end
    return text
end

local function fillRow(r, info, done)
    local s = stateOf(info)
    local st = STATES[s or NO_ROLL]
    r.pill.text:SetText(s and ns.T(st.text) or "?")
    W.TextColor(r.pill.text, st.color)
    r.pill.bg:SetColor(st.color, s == NO_ROLL and 0.10 or 0.22)
    W.SetTip(r.pill, st.tip and st.text, st.tip)   -- (ligne réutilisée : l'infobulle d'avant est effacée)

    local name, secret = coloredName(info)
    if secret then r.name:SetText(name) else
        r.name:SetText(name .. (plain(info.isSelf) == true and W.Color("dim", ns.T(" (toi)")) or ""))
    end
    r.class:SetText(className(info.playerClass))

    local roll = info.roll
    if isSecret(roll) or roll ~= nil then r.roll:SetText(roll) else r.roll:SetText(s == NO_ROLL and not done and "…" or "") end
    local win = plain(info.isWinner) == true
    W.TextColor(r.roll, win and C.gold or (s == 5 and C.dim or C.text))
    r.check:SetShown(win)
    r.hl:SetShown(win)
    -- les joueurs qui passent ou n'ont pas choisi sont estompés
    local faded = (s == 5) or (s == NO_ROLL and done)
    r:SetAlpha(faded and 0.55 or 1)
end

local function fillCard(c, drop, now, width)
    c.drop = drop
    c.link = plain(drop.itemHyperlink)
    local name, color, icon, slot = itemFromLink(drop.itemHyperlink)
    c.name:SetText("|c" .. color .. name .. "|r")
    c.slot:SetText(slot or drop.demoSlot or "")
    c.icon:SetTexture(icon)
    local r, g, b = tonumber(color:sub(3, 4), 16) or 255, tonumber(color:sub(5, 6), 16) or 255, tonumber(color:sub(7, 8), 16) or 255
    c.ring:SetRGBA(r / 255, g / 255, b / 255, 0.9)
    c.status:SetText(statusText(drop, now))

    local done = isDone(drop, now)
    local _, frac = remaining(drop, now)
    c.bar:SetShown(not done and frac ~= nil)
    if not done and frac then c.bar:SetValue(frac) end

    local rolls = type(drop.rollInfos) == "table" and drop.rollInfos or {}
    local y = -(CARD_PAD + ICON + 14)
    for i, info in ipairs(rolls) do
        local row = c.rows[i] or newRow(c)
        c.rows[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD - 4, y)
        row:SetPoint("TOPRIGHT", c, "TOPRIGHT", -CARD_PAD + 4, y)
        fillRow(row, info, done)
        row:Show()
        y = y - ROW_H
    end
    for i = #rolls + 1, #c.rows do c.rows[i]:Hide() end
    local h = -y + CARD_PAD - (#rolls == 0 and 6 or 0)
    c:SetSize(width, h)
    c:Show()
    return h, done
end

---------------------------------------------------------------------------
-- /roll tapés à la main
-- Le message système « Brakmar obtient un 57 (1-100). » (RANDOM_ROLL_RESULT, lu dans le jeu ; replis anglais et
-- français) est découpé en nom, dé, bornes. Les jets se rangent en séries : une nouvelle série commence après
-- SERIES_GAP s sans jet, ou quand un objet est lié dans le chat du groupe après le dernier jet (le chef annonce
-- l'objet suivant). La série prend le nom de cet objet. Un 2e jet du même joueur dans une série est marqué et
-- ne compte pas. Gagnant : le plus haut dé sur les bornes les plus jouées (1-100 en priorité).
-- Doc Forever : CHAT_MSG_SYSTEM est SecretInChatMessagingLockdown (texte secret pendant le verrouillage du chat,
-- en combat de boss) : un texte secret est ignoré. Les /roll se font d'habitude hors combat. NON VÉRIFIÉ en jeu.
---------------------------------------------------------------------------
local SERIES_GAP = 60                    -- s de silence qui ferment une série
local ITEM_WINDOW = 180                  -- un objet lié jusqu'à 3 min avant la série lui donne son nom
local MAX_SERIES, MAX_ROLLS = 10, 60
local DICE_ICON = "Interface\\Icons\\INV_Misc_Dice_01"
local ROLL_FALLBACKS = { "^(.+) rolls (%d+) %((%d+)%-(%d+)%)", "^(.+) obtient un (%d+) %((%d+)%-(%d+)%)" }
local rollPatterns

-- « %s obtient un %d (%d-%d). » -> motif Lua avec 4 captures
local function patternFromFormat(fmt)
    local s = fmt:gsub("%%%d%$", "%%")                       -- %1$s -> %s
    s = s:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")         -- caractères spéciaux
    s = s:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. s .. "$"
end

local function parseRoll(text)
    if not rollPatterns then
        rollPatterns = {}
        local fmt = api("RANDOM_ROLL_RESULT")
        if type(fmt) == "string" and fmt:find("%%") then
            local ok, p = pcall(patternFromFormat, fmt)
            if ok then rollPatterns[1] = p end
        end
        for _, p in ipairs(ROLL_FALLBACKS) do rollPatterns[#rollPatterns + 1] = p end
    end
    for _, p in ipairs(rollPatterns) do
        local name, roll, low, high = text:match(p)
        if name then return name, tonumber(roll), tonumber(low), tonumber(high) end
    end
end

local function gameTime() return GetTime and GetTime() or 0 end

-- classe d'un membre du groupe d'après son nom (rien si inconnu ou secret)
local function classOf(name)
    local short = name:match("^([^%-]+)") or name
    local units = { "player" }
    local raid = api("IsInRaid")
    local count = api("GetNumGroupMembers")
    local n = count and count() or 0
    if raid and raid() then
        for i = 1, n do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    local unitName, unitClass = api("UnitName"), api("UnitClass")
    if not (unitName and unitClass) then return nil end
    for _, unit in ipairs(units) do
        local ok, uname = pcall(unitName, unit)
        if ok and type(plain(uname)) == "string" and uname == short then
            local ok2, _, file = pcall(unitClass, unit)
            if ok2 and type(plain(file)) == "string" then return file, unit == "player" end
            return nil, unit == "player"
        end
    end
end

-- bornes jouées par le plus de monde (1-100 en priorité) et gagnant(s)
local function judge(s)
    local counts, best = {}, nil
    for _, r in ipairs(s.rolls) do
        if not r.again then
            local key = r.low .. "-" .. r.high
            counts[key] = (counts[key] or 0) + 1
            if key == "1-100" then best = key end
        end
    end
    if not best then
        local top = 0
        for key, n in pairs(counts) do if n > top then best, top = key, n end end
    end
    local high, winners = -1, {}
    for _, r in ipairs(s.rolls) do
        if not r.again and (r.low .. "-" .. r.high) == best then
            if r.roll > high then high, winners = r.roll, { r } elseif r.roll == high then winners[#winners + 1] = r end
        end
    end
    return best, winners, high
end

-- ajoute un jet ; renvoie (nouvelle série ?, série du jet)
local function addRoll(name, roll, low, high)
    local t = gameTime()
    local cur = series[1]
    local fresh = not cur or t - cur.last > SERIES_GAP or (lastItem and lastItem.at > cur.last and not lastItem.used)
    if fresh then
        local item = lastItem and not lastItem.used and t - lastItem.at <= ITEM_WINDOW and lastItem.link or nil
        if item then lastItem.used = true end
        local date = api("date")
        cur = { started = t, last = t, item = item, clock = date and date("%H:%M") or "", rolls = {} }
        table.insert(series, 1, cur)
        while #series > MAX_SERIES do table.remove(series) end
    end
    -- égalité au plus haut dé : la relance d'un ex aequo ouvre une série « départage » pour le même objet
    if not fresh then
        local _, winners = judge(cur)
        local tied = false
        if #winners > 1 then for _, w in ipairs(winners) do if w.name == name then tied = true end end end
        if tied then
            local date = api("date")
            cur = { started = t, last = t, item = cur.item, tiebreak = true, clock = date and date("%H:%M") or "", rolls = {} }
            table.insert(series, 1, cur)
            while #series > MAX_SERIES do table.remove(series) end
            fresh = true
        end
    end
    cur.last = t
    if #cur.rolls >= MAX_ROLLS then return fresh, cur end
    local again = false
    for _, r in ipairs(cur.rolls) do if r.name == name then again = true end end
    local class, self = classOf(name)
    cur.rolls[#cur.rolls + 1] = { name = name, class = class, isSelf = self, roll = roll, low = low, high = high, again = again }
    return fresh, cur
end

local function rollSeries() return demo and demo.series or series end

local function fillRollRow(r, roll, isWinner)
    local range = roll.low .. "-" .. roll.high
    local color = roll.again and C.bad or (range == "1-100" and C.accent or C.gold)
    r.pill.text:SetText(roll.again and ns.T("2e jet") or range)
    W.TextColor(r.pill.text, color)
    r.pill.bg:SetColor(color, 0.22)
    W.SetTip(r.pill, roll.again and "2e jet" or nil, roll.again and "Ce joueur avait déjà lancé les dés : ce jet ne compte pas." or nil)
    r.name:SetText("|cff" .. classColorHex(roll.class) .. roll.name .. "|r" .. (roll.isSelf and W.Color("dim", ns.T(" (toi)")) or ""))
    r.class:SetText(className(roll.class))
    r.roll:SetText(roll.roll)
    W.TextColor(r.roll, isWinner and C.gold or C.text)
    r.check:SetShown(isWinner)
    r.hl:SetShown(isWinner)
    r:SetAlpha(roll.again and 0.55 or 1)
end

local function fillRollCard(c, s, width)
    c.drop = nil
    c.link = s.item
    if s.item then
        local name, color, icon, slot = itemFromLink(s.item)
        c.name:SetText("|c" .. color .. name .. "|r")
        c.icon:SetTexture(icon)
        local r, g, b = tonumber(color:sub(3, 4), 16) or 255, tonumber(color:sub(5, 6), 16) or 255, tonumber(color:sub(7, 8), 16) or 255
        c.ring:SetRGBA(r / 255, g / 255, b / 255, 0.9)
        c.slot:SetText((s.tiebreak and ns.Tf("départage · %s", s.clock)) or ((slot and (slot .. " · ") or "") .. s.clock))
    else
        c.name:SetText(s.tiebreak and ns.T("Départage /roll") or ns.T("Jets /roll"))
        c.icon:SetTexture(DICE_ICON)
        c.ring:SetRGBA(1, 1, 1, 0.25)
        c.slot:SetText(s.clock)
    end
    local range, winners, high = judge(s)
    local players = 0
    for _, r in ipairs(s.rolls) do if not r.again then players = players + 1 end end
    local status = (players == 1 and ns.Tf("%d joueur", players) or ns.Tf("%d joueurs", players)) .. (range and (" · " .. range) or "")
    if #winners == 1 then
        local w = winners[1]
        status = W.Color("dim", status .. " · ") .. "|cff" .. classColorHex(w.class) .. w.name .. "|r" .. W.Color("dim", ns.T(" gagne avec ")) .. high
    elseif #winners > 1 then
        status = W.Color("dim", status .. " · ") .. W.Color("gold", ns.Tf("égalité à %s : relancer", tostring(high)))
    else
        status = W.Color("dim", status)
    end
    c.status:SetText(status)
    c.bar:Hide()

    -- du plus haut au plus bas ; les 2e jets en dernier
    local sorted = {}
    for i, r in ipairs(s.rolls) do sorted[i] = r end
    table.sort(sorted, function(a, b)
        if a.again ~= b.again then return not a.again end
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.name < b.name
    end)
    local isWin = {}
    for _, w in ipairs(winners) do isWin[w] = #winners == 1 end
    local y = -(CARD_PAD + ICON + 14)
    for i, roll in ipairs(sorted) do
        local row = c.rows[i] or newRow(c)
        c.rows[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD - 4, y)
        row:SetPoint("TOPRIGHT", c, "TOPRIGHT", -CARD_PAD + 4, y)
        fillRollRow(row, roll, isWin[roll] or false)
        row:Show()
        y = y - ROW_H
    end
    for i = #sorted + 1, #c.rows do c.rows[i]:Hide() end
    local h = -y + CARD_PAD
    c:SetSize(width, h)
    c:Show()
    return h
end

---------------------------------------------------------------------------
-- La fenêtre
---------------------------------------------------------------------------
local function tick()
    if not next(pending) then frame.ticker:SetScript("OnUpdate", nil) return end
    local now = source().now()
    local finished = false
    for c in pairs(pending) do
        local drop = c.drop
        local secs, frac = remaining(drop, now)
        if frac then c.bar:SetValue(frac) end
        c.status:SetText(statusText(drop, now))
        if secs == 0 or isDone(drop, now) then finished = true end
    end
    if finished then
        -- temps écoulé : le jeu envoie l'issue un peu après ; on relit une fois par seconde jusque-là
        LR:QueueRefresh(1)
    end
end

local function startTicker()
    local acc = 0
    -- sur un cadre enfant : l'OnUpdate de la fenêtre sert au fondu d'ouverture (W.Animate)
    frame.ticker:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + (elapsed or 0)
        if acc < 0.2 then return end
        acc = 0
        tick()
    end)
end

-- delay : AUTO_CLOSE_DELAY (butin) ; l'onglet /roll attend la fin d'une série (SERIES_GAP)
local function scheduleAutoClose(anyPending, delay)
    closeToken = closeToken + 1
    if not (openedAuto and ns.db.lootRollsAutoClose) or anyPending then return end
    local token = closeToken
    local timer = api("C_Timer")
    if not (timer and timer.After) then return end
    timer.After(delay or AUTO_CLOSE_DELAY, function()
        if token == closeToken and frame and frame:IsShown() and openedAuto then
            autoHiding = true
            frame:Hide()
            autoHiding = false
        end
    end)
end

local function paintTabs()
    for key, b in pairs(tabs) do
        local on = key == mode
        W.TextColor(b.label, on and C.text or C.dim)
        b.mark:SetShown(on)
    end
end

-- onglet /roll : une carte par série, la plus récente en haut
local function refreshRolls()
    local list = rollSeries()
    navTitle:SetText(ns.T("Dés lancés à la main"))
    navCount:SetText("")
    prevBtn:Hide()
    nextBtn:Hide()
    clearBtn:SetShown(#list > 0 and not demo)
    wipe(pending)
    frame.ticker:SetScript("OnUpdate", nil)
    local width = WIDTH - 2 * Win.PAD - 6
    local y = 0
    for i, s in ipairs(list) do
        local c = cards[i] or newCard(area.child)
        cards[i] = c
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, -y)
        y = y + fillRollCard(c, s, width) + CARD_GAP
    end
    for i = #list + 1, #cards do cards[i]:Hide() end
    emptyText:SetText(ns.T("Aucun /roll pour l'instant. Quand ton groupe tire un objet au /roll, chaque dé apparaît ici, rangé du plus haut au plus bas, avec le nom de l'objet lié juste avant dans le chat."))
    emptyText:SetShown(#list == 0)
    area:SetContentHeight(max(1, y - CARD_GAP))
    scheduleAutoClose(false, SERIES_GAP)
end

function LR:Refresh()
    refreshQueued = false
    if not (frame and frame:IsShown()) then return end
    paintTabs()
    if mode == "roll" then return refreshRolls() end
    prevBtn:Show()
    nextBtn:Show()
    clearBtn:Hide()
    emptyText:SetText(ns.T("Aucun objet mis aux dés pour l'instant. En groupe, chaque objet tiré au sort (Besoin, Cupidité, Passer) apparaît ici avec le dé de chaque joueur."))
    local src = source()
    local list = {}
    for _, e in ipairs(src.encounters()) do
        if type(e) == "table" and plain(e.encounterID) ~= nil then list[#list + 1] = e end
    end
    table.sort(list, function(a, b)
        local sa, sb = tonumber(plain(a.startTime)) or 0, tonumber(plain(b.startTime)) or 0
        return sa > sb
    end)
    -- garder la même rencontre affichée si la liste a bougé
    local current = not followLatest and encounters[index] and encounters[index].encounterID
    encounters = list
    index = 1
    if current then
        for i, e in ipairs(list) do if e.encounterID == current then index = i end end
    end
    if index > #list then index = max(1, #list) end

    local enc = list[index]
    if not enc then
        navTitle:SetText(ns.T("Jets de butin"))
    elseif isSecret(enc.encounterName) then
        navTitle:SetText(enc.encounterName)
    else
        navTitle:SetText(enc.encounterName or "?")
    end
    navCount:SetText(#list > 1 and (index .. " / " .. #list) or "")
    prevBtn:SetEnabled(index < #list)
    nextBtn:SetEnabled(index > 1)
    prevBtn:SetAlpha(index < #list and 1 or 0.3)
    nextBtn:SetAlpha(index > 1 and 1 or 0.3)

    wipe(pending)
    local drops = enc and src.drops(enc.encounterID) or {}
    local now = src.now()
    local width = WIDTH - 2 * Win.PAD - 6
    local y = 0
    local anyPending = false
    for i, drop in ipairs(drops) do
        local c = cards[i] or newCard(area.child)
        cards[i] = c
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, -y)
        if type(drop) == "table" then drop.ppEnc = enc end   -- repli du minuteur sur la rencontre
        local h, done = fillCard(c, drop, now, width)
        if not done then pending[c] = true anyPending = true end
        y = y + h + CARD_GAP
    end
    for i = #drops + 1, #cards do cards[i]:Hide() end
    emptyText:SetShown(#drops == 0)
    area:SetContentHeight(max(1, y - CARD_GAP))
    if anyPending then startTicker() else frame.ticker:SetScript("OnUpdate", nil) end
    scheduleAutoClose(anyPending)
end

-- relit au prochain passage (plusieurs événements d'un coup = une seule relecture)
function LR:QueueRefresh(delay)
    if refreshQueued or not (frame and frame:IsShown()) then return end
    refreshQueued = true
    local timer = api("C_Timer")
    if timer and timer.After then
        timer.After(delay or 0, function() LR:Refresh() end)
    else
        LR:Refresh()
    end
end

local function build()
    if frame then return frame end
    W, C, Win = ns.W, ns.W.C, ns.Win
    frame = Win.Create("PlatyplusLootRolls", {
        title = "Jets de butin", width = WIDTH, height = HEIGHT,
        posKey = "lootRollsPos", scaleKey = "lootRollsScale", corner = "TOPRIGHT",
        default = { "TOPRIGHT", "TOPRIGHT", -260, -180 },
        onClose = function() LR:Close() end,
    })
    frame.ticker = CreateFrame("Frame", nil, frame)   -- minuteur des jets en cours
    local specials = api("UISpecialFrames")
    if type(specials) == "table" then table.insert(specials, "PlatyplusLootRolls") end   -- Échap ferme

    -- onglets dans le bandeau : « Butin » (dés du jeu) et « /roll » (dés tapés à la main)
    local prev
    for _, def in ipairs({ { "roll", "/roll" }, { "loot", "Butin" } }) do   -- de droite à gauche
        local key = def[1]
        local b = Win.FlatButton(frame.head, def[2], function() LR:SetMode(key) end, 26)
        b:SetPoint("RIGHT", prev or frame.close, "LEFT", prev and -2 or -8, 0)
        b.mark = b:CreateTexture(nil, "OVERLAY")
        b.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        b.mark:SetHeight(2)
        b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, -1)
        b.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, -1)
        tabs[key] = b
        prev = b
    end
    W.SetTip(tabs.loot, "Butin", "Les objets tirés au sort par le jeu (Besoin, Cupidité, Passer), boss par boss.")
    W.SetTip(tabs.roll, "/roll", "Les dés lancés à la main dans le chat, rangés par objet annoncé.")
    frame.title:SetPoint("RIGHT", prev, "LEFT", -8, 0)
    tabs.roll:SetShown(ns.db.lootRollsManual and true or false)

    local nav = CreateFrame("Frame", nil, frame)
    nav:SetPoint("TOPLEFT", frame, "TOPLEFT", Win.PAD - 6, -Win.HEAD_H - 4)
    nav:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Win.PAD + 6, -Win.HEAD_H - 4)
    nav:SetHeight(NAV_H)
    prevBtn = Win.FlatButton(nav, "<", function() LR:Step(1) end, 26)
    prevBtn:SetPoint("LEFT", nav, "LEFT", 0, 0)
    W.SetTip(prevBtn, "Boss précédent")
    nextBtn = Win.FlatButton(nav, ">", function() LR:Step(-1) end, 26)
    nextBtn:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
    W.SetTip(nextBtn, "Boss suivant")
    navTitle = W.Text(nav, nil, C.text, "OVERLAY", 14)
    navTitle:SetPoint("LEFT", prevBtn, "RIGHT", 8, 0)
    navTitle:SetPoint("RIGHT", nextBtn, "LEFT", -64, 0)
    navTitle:SetJustifyH("LEFT")
    if navTitle.SetWordWrap then navTitle:SetWordWrap(false) end
    navCount = W.Text(nav, nil, C.dim, "OVERLAY", 12)
    navCount:SetPoint("RIGHT", nextBtn, "LEFT", -8, 0)
    navCount:SetJustifyH("RIGHT")
    clearBtn = Win.FlatButton(nav, "Effacer", function() wipe(series) LR:Refresh() end, 26)
    clearBtn:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
    W.SetTip(clearBtn, "Effacer", "Oublie tous les /roll de la liste.")
    clearBtn:Hide()

    local top = Win.HEAD_H + NAV_H + 10
    area = Win.ScrollArea(frame, WIDTH - 2 * Win.PAD, HEIGHT - top - Win.PAD)
    area.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", Win.PAD, -top)

    emptyText = W.Text(area.child, nil, C.dim, "OVERLAY", 13)
    emptyText:SetPoint("TOPLEFT", area.child, "TOPLEFT", 4, -12)
    emptyText:SetWidth(WIDTH - 2 * Win.PAD - 12)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText(ns.T("Aucun objet mis aux dés pour l'instant. En groupe, chaque objet tiré au sort (Besoin, Cupidité, Passer) apparaît ici avec le dé de chaque joueur."))
    emptyText:Hide()

    frame:SetScript("OnHide", function()
        frame.ticker:SetScript("OnUpdate", nil)
        wipe(pending)
        closeToken = closeToken + 1
        -- croix, Échap ou /pp jets : plus d'ouverture automatique jusqu'au prochain boss
        if not autoHiding and not demo then closedByUser = true end
        demo, openedAuto = nil, false
    end)
    return frame
end

---------------------------------------------------------------------------
-- Ouverture, navigation
---------------------------------------------------------------------------
function LR:Open(auto)
    if not ns.db then return end
    build()
    openedAuto = auto and true or false
    if not frame:IsShown() then
        followLatest = true
        Win.Open(frame)
    end
    self:Refresh()
end

function LR:Close()
    if frame then frame:Hide() end       -- (OnHide remet l'exemple et l'ouverture auto à zéro)
end

function LR:Toggle()
    if frame and frame:IsShown() then self:Close() else self:Open() end
end

function LR:IsShown() return frame and frame:IsShown() or false end

-- delta > 0 : boss plus ancien ; < 0 : plus récent
function LR:Step(delta)
    local n = #encounters
    if n == 0 then return end
    index = max(1, min(n, index + delta))
    followLatest = index == 1
    openedAuto = false                   -- on lit l'historique : plus de fermeture automatique
    self:Refresh()                       -- (Refresh retrouve la rencontre choisie par son ID)
end

-- "loot" : dés du jeu ; "roll" : /roll tapés à la main
function LR:SetMode(key)
    if key ~= "loot" and key ~= "roll" then return end
    mode = key
    openedAuto = false                   -- l'utilisateur choisit : plus de fermeture automatique
    if frame and frame:IsShown() then self:Refresh() else self:Open() end
end

function LR:Demo()
    demo = buildDemo()
    followLatest = true
    self:Open()
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local function inGroup()
    local f = api("IsInGroup")
    return f and f() and true or false
end

-- wanted : onglet concerné par l'événement ("loot" ou "roll")
local function autoOpen(wanted)
    if not (ns.db.lootRolls and ns.db.lootRollsAuto) or demo then return end
    if not inGroup() or closedByUser then return end
    if frame and frame:IsShown() then
        LR:QueueRefresh(EVENT_DELAY)     -- (jamais de changement d'onglet sous les yeux de l'utilisateur)
        return
    end
    mode = wanted
    LR:Open(true)
end

local GROUP_CHAT = {
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
}

local function onSystem(text)
    if isSecret(text) or type(text) ~= "string" or not inGroup() then return end
    local name, roll, low, high = parseRoll(text)
    if not (name and roll and low and high) then return end
    local fresh, s = addRoll(name, roll, low, high)
    -- un vrai tirage (objet lié, ou au moins 2 joueurs) ; un /roll « pour rire » n'ouvre rien
    local real = s and (s.item or #s.rolls >= 2)
    if real and not s.announced then
        -- 1re fois que ce tirage devient « vrai » : réouverture permise (une fermeture à la main ne vaut
        -- que pour le tirage en cours)
        s.announced = true
        closedByUser = false
    end
    if real then autoOpen("roll") end
    if mode == "roll" and not demo then LR:QueueRefresh(EVENT_DELAY) end
end

local function onEvent(_, event, a, b)
    if event == "CHAT_MSG_SYSTEM" then
        onSystem(a)
    elseif GROUP_CHAT[event] then
        -- un objet lié dans le chat du groupe : sans doute l'objet que l'on va tirer au /roll
        if isSecret(a) or type(a) ~= "string" then return end
        local link = a:match("(|c[^|]+|Hitem:.-|h|r)")
        if link then lastItem = { link = link, at = gameTime() } end
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        local enc = plain(a)
        if enc ~= nil and enc ~= lastEncounter then
            lastEncounter = enc
            closedByUser = false             -- nouveau boss : la fenêtre peut se rouvrir toute seule
        end
        local key = tostring(enc) .. ":" .. tostring(plain(b))
        if not seen[key] then
            seen[key] = true
            autoOpen("loot")
        end
        if not demo then LR:QueueRefresh(EVENT_DELAY) end
    elseif event == "START_LOOT_ROLL" then
        autoOpen("loot")
    elseif event == "LOOT_HISTORY_CLEAR_HISTORY" then
        wipe(seen)
        if not demo then LR:QueueRefresh(EVENT_DELAY) end
    elseif not demo then
        LR:QueueRefresh(EVENT_DELAY)
    end
end

local EVENTS = { "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY", "START_LOOT_ROLL" }

local function apply()
    local on = ns.db.lootRolls
    if on then
        for _, ev in ipairs(EVENTS) do pcall(events.RegisterEvent, events, ev) end
        local manual = ns.db.lootRollsManual
        for ev in pairs(GROUP_CHAT) do
            if manual then pcall(events.RegisterEvent, events, ev) else pcall(events.UnregisterEvent, events, ev) end
        end
        if manual then pcall(events.RegisterEvent, events, "CHAT_MSG_SYSTEM") else pcall(events.UnregisterEvent, events, "CHAT_MSG_SYSTEM") end
        if tabs.roll then tabs.roll:SetShown(manual and true or false) end
        if not manual and mode == "roll" then
            mode = "loot"
            if frame and frame:IsShown() then LR:Refresh() end
        end
    else
        events:UnregisterAllEvents()
        if frame and frame:IsShown() then LR:Close() end
    end
end

function LR:Command(arg)
    arg = strtrim(arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns:Set("lootRolls", arg == "on")
        ns:Print("suivi des jets de butin :", ns.db.lootRolls and "activé" or "coupé")
    elseif arg == "demo" or arg == "exemple" then
        self:Demo()
    elseif arg == "roll" or arg == "rolls" then
        self:SetMode("roll")
    elseif arg == "butin" or arg == "loot" then
        self:SetMode("loot")
    elseif arg == "auto" then
        ns:Set("lootRollsAuto", not ns.db.lootRollsAuto)
        ns:Print("ouverture automatique des jets :", ns.db.lootRollsAuto and "oui" or "non")
    else
        self:Toggle()
    end
end

function LR:Init()
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", onEvent)
    apply()
    ns:OnChange("lootRolls", apply)
    ns:OnChange("lootRollsManual", apply)
    ns:OnChange("lootRollsScale", function() if frame then Win.Place(frame) end end)
end
