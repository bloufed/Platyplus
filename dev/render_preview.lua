-- Rendu des « captures » de Platyplus hors du jeu :
-- charge l'addon dans le simulateur, met en scène l'écran (flux, barre de ressource, icône, menu, options),
-- calcule la position réelle de chaque texture / texte comme le moteur de WoW (ancres, tailles, échelles,
-- strates, couches) et écrit une scène JSON par capture. dev\preview_html.py les transforme en pages HTML.
-- Usage : python -I lua.py run render_preview.lua <dossier Platyplus> <dossier dev> <dossier de sortie>
local ADDON_DIR, DEV, OUT = ARGS[1], ARGS[2], ARGS[3]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local SW, SH = 1600, 900
M.state(UIParent).w, M.state(UIParent).h = SW, SH

---------------------------------------------------------------------------
-- Monde simulé : guerrier niveau 42, 45 de rage, sorts sur la barre, sacs, argent
---------------------------------------------------------------------------
local power = { cur = 45, max = 100 }
def("UnitExists", function(u) return u == "player" end)
def("UnitPowerType", function() return 1, "RAGE", 0, 0, 0 end)
def("UnitPower", function() return power.cur end)
def("UnitPowerMax", function() return power.max end)
def("UnitLevel", function() return 42 end)
def("UnitXP", function() return 4520 end)
def("UnitXPMax", function() return 12000 end)
def("GetXPExhaustion", function() return 1500 end)
def("IsPlayerAtEffectiveMaxLevel", function() return false end)
def("PowerBarColor", { RAGE = { r = 1, g = 0, b = 0 }, MANA = { r = 0, g = 0, b = 1 }, [1] = { r = 1, g = 0, b = 0 } })
def("GetFramerate", function() return 144 end)
def("GetNetStats", function() return 0, 0, 38, 42 end)
M.money = 1234567
def("C_Map", {
    GetBestMapForUnit = function() return 1429 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.4523, 0.6612 end } end,
    GetMapInfo = function() return { name = "Forêt d'Elwynn" } end,
})
def("GetInventoryAlertStatus", function() return 0 end)
def("GetInventoryItemDurability", function(slot) return 72, 100 end)

local spells = {
    [101] = { name = "Frappe héroïque", cost = 15, icon = "Interface\\Icons\\Ability_Rogue_Ambush" },
    [102] = { name = "Pourfendre", cost = 10, icon = "Interface\\Icons\\Ability_Gouge" },
    [103] = { name = "Exécution", cost = 10, full = 30, icon = "Interface\\Icons\\INV_Sword_48" },
    [104] = { name = "Frappe mortelle", cost = 30, icon = "Interface\\Icons\\Ability_Warrior_SavageBlow" },
    [105] = { name = "Cri de guerre", cost = 10, icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    [106] = { name = "Tourbillon", cost = 25, icon = "Interface\\Icons\\Ability_Whirlwind" },
    [107] = { name = "Charge", cost = 0, icon = "Interface\\Icons\\Ability_Warrior_Charge" },
    [108] = { name = "Enragé", cost = 60, icon = "Interface\\Icons\\Ability_Racial_BloodRage" },
}
local slots = { 101, 102, 103, 104, 105, 106, 107, 108 }
def("GetActionInfo", function(action) local id = slots[action]; if id then return "spell", id end end)
def("C_Spell", {
    GetSpellPowerCost = function(id)
        local s = spells[id]
        if not s or s.cost == 0 then return {} end
        return { { type = 1, name = "RAGE", cost = s.full or s.cost, minCost = s.cost } }
    end,
    IsSpellUsable = function(id) local s = spells[id]; local ok = s and s.cost <= power.cur; return ok, not ok end,
    GetSpellTexture = function(id) return spells[id] and spells[id].icon end,
    GetSpellInfo = function(id) local s = spells[id]; return s and { name = s.name, iconID = s.icon, spellID = id } end,
})
def("C_ActionBar", {
    IsUsableAction = function(action) local s = spells[slots[action] or 0]; local ok = s and s.cost <= power.cur; return ok, not ok end,
    HasAction = function(action) return slots[action] ~= nil end,
    GetActionTexture = function(action) local s = spells[slots[action] or 0]; return s and s.icon end,
})
def("ActionButtonUtil", { ActionBarButtonNames = { "ActionButton" } })
for i = 1, 8 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b:SetSize(45, 45)
    b:SetPoint("BOTTOM", UIParent, "BOTTOM", (i - 4.5) * 49, 18)
    b.action = i
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
    local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(spells[slots[i]].icon)
    b.icon = icon
    b.TextOverlayContainer = CreateFrame("Frame", nil, b)
    b.TextOverlayContainer:SetAllPoints()
end

-- cadre du joueur avec son portrait (chemins vérifiés dans PlayerFrame.xml de Forever)
local pf = CreateFrame("Frame", "PlayerFrame", UIParent)
pf:SetSize(232, 100)
pf:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
local pfbg = pf:CreateTexture(nil, "BACKGROUND"); pfbg:SetPoint("TOPLEFT", 70, -18); pfbg:SetSize(150, 44)
pfbg:SetColorTexture(0.08, 0.08, 0.1, 0.85)
pf.PlayerFrameContainer = CreateFrame("Frame", nil, pf)
pf.PlayerFrameContainer:SetAllPoints()
local portrait = pf.PlayerFrameContainer:CreateTexture(nil, "ARTWORK")
portrait:SetSize(60, 60); portrait:SetPoint("TOPLEFT", 24, -19)
portrait:SetTexture("Interface\\Icons\\Achievement_Character_Human_Male")
pf.PlayerFrameContainer.PlayerPortrait = portrait

-- sacs et objets (onglet Vente)
local items = {
    [1] = { name = "Chiffon déchiré", q = 0, ilvl = 1, equip = "", class = 15, price = 12 },
    [2] = { name = "Casque usé", q = 2, ilvl = 20, equip = "INVTYPE_HEAD", class = 4, price = 540, bind = 1 },
    [3] = { name = "Croc de loup", q = 0, ilvl = 1, equip = "", class = 15, price = 35 },
    [100] = { name = "Heaume du gardien", q = 3, ilvl = 30, equip = "INVTYPE_HEAD", class = 4, price = 0, bind = 1 },
}
local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. items[id].name .. "]|h|r" end
local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end
local bag = { 1, 2, 3 }
def("C_Container", {
    GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
    GetContainerNumFreeSlots = function(b) return b == 0 and 13 or 0, 0 end,
    GetContainerItemInfo = function(b, slot)
        local id = b == 0 and bag[slot]
        if not id then return nil end
        local it = items[id]
        return { iconFileID = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", stackCount = 1, isLocked = false, quality = it.q,
                 hyperlink = linkOf(id), hasNoValue = it.price == 0, itemID = id, isBound = it.bind == 1, itemName = it.name }
    end,
    GetContainerItemEquipmentSetInfo = function() return false, "" end,
})
def("C_Item", {
    GetItemInfo = function(link)
        local id = idOf(link); local it = items[id]
        if not it then return nil end
        return it.name, linkOf(id), it.q, it.ilvl, 1, "x", "y", 1, it.equip, 1, it.price, it.class, 1, it.bind or 0
    end,
    GetItemInfoInstant = function(link)
        local id = idOf(link) or tonumber(link); local it = items[id]
        if not it then return nil end
        return id, "x", "y", it.equip, "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", it.class, 1
    end,
    GetDetailedItemLevelInfo = function(link) local it = items[idOf(link)]; return it and it.ilvl end,
    GetItemNameByID = function(id) return items[id] and items[id].name end,
    RequestLoadItemDataByID = function() end,
    GetItemQualityByID = function(id) return items[id] and items[id].q end,
})
def("GetInventoryItemLink", function(unit, slot) if slot == 1 then return linkOf(100) end end)
def("ITEM_QUALITY_COLORS", {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 },
    [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
})

---------------------------------------------------------------------------
-- Compléments : vrai post-hook, classe et niveau d'objet du personnage (barre d'infos)
---------------------------------------------------------------------------
-- vrai post-hook (le simulateur n'a qu'un no-op) ; tolérant : une cible absente est ignorée
def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = rawget(tbl, name)
    if type(orig) ~= "function" then return end
    rawset(tbl, name, function(...)
        local results = { orig(...) }
        hook(...)
        return unpack(results)
    end)
end)
def("UnitClass", function() return "Guerrier", "WARRIOR", 1 end)
def("GetAverageItemLevel", function() return 33.8, 31.6 end)
-- fenêtre du personnage (avant le chargement : ses crochets se posent sur CharacterFrame)
dofile(DEV .. "\\preview_charworld.lua")(M, def)
-- journal des donjons intégré (DungeonJournal/) : fonds BackdropTemplate dessinés, quêtes, mode déjà choisi
dofile(DEV .. "\\preview_dungeon.lua")(M, def, { level = 42 })

-- dialogue avec un PNJ (fenêtre de quête) : fenêtres du jeu, discussion, quête à rendre
local function gameFrame(name, parent)
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:Hide()
    def(name, f)
    return f
end
local questFrame = gameFrame("QuestFrame")
local questPanels = {}
for _, n in ipairs({ "Greeting", "Detail", "Progress", "Reward" }) do
    questPanels[n] = gameFrame("QuestFrame" .. n .. "Panel", questFrame)
end
local gossipFrame = gameFrame("GossipFrame")
for _, n in ipairs({ "QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestFrameCompleteButton",
                     "QuestFrameGoodbyeButton", "QuestFrameCompleteQuestButton", "QuestFrameGreetingGoodbyeButton" }) do
    local b = CreateFrame("Button", n, questFrame)
    b:SetText(n == "QuestFrameAcceptButton" and "Accepter" or "Refuser")
    def(n, b)
end
def("ShowUIPanel", function(f) f:Show() end)
def("C_GossipInfo", {
    GetText = function() return "Salut, voyageur. Les loups rôdent près de la ferme, et le colis que tu as retrouvé va faire des heureux." end,
    GetAvailableQuests = function() return { { title = "Les loups de la ferme", questID = 101, isTrivial = false } } end,
    GetActiveQuests = function() return { { title = "Le colis perdu", questID = 102, isComplete = true } } end,
    GetOptions = function()
        return {
            { name = "Je voudrais acheter quelque chose.", icon = 132060, orderIndex = 2, status = 0 },
            { name = "Où est l'auberge ?", icon = 132053, orderIndex = 1, status = 0 },
            { name = "Peux-tu m'entraîner ?", icon = 132058, orderIndex = 3, status = 1, failureDescription = "Pas encore." },
        }
    end,
    SelectAvailableQuest = function() end, SelectActiveQuest = function() end, SelectOptionByIndex = function() end,
    CloseGossip = function() end,
})
def("GetQuestID", function() return 102 end)
def("GetTitleText", function() return "Le colis perdu" end)
def("GetRewardText", function() return "Merci ! Le colis est arrivé à bon port. Choisis ce qui te plaît." end)
def("GetNumQuestChoices", function() return 3 end)
def("GetNumQuestRewards", function() return 1 end)
def("GetRewardMoney", function() return 1250 end)
def("GetRewardXP", function() return 850 end)
def("GetQuestItemInfo", function(kind, i)
    local id = kind == "choice" and ({ 2, 100, 3 })[i] or 1
    local it = items[id]
    return it.name, 1000 + id, 1, it.q, true, id
end)
def("GetQuestItemLink", function(kind, i) return linkOf(kind == "choice" and ({ 2, 100, 3 })[i] or 1) end)
def("QuestInfoFrame", { itemChoice = 0 })
def("UnitName", function(u) if u == "npc" or u == "questnpc" then return "Garde Thomas" end return "Platy" end)

---------------------------------------------------------------------------
-- Chargement (sans mode strict : on veut voir l'écran, pas traquer les globales)
---------------------------------------------------------------------------
def("GetLocale", function() return "frFR" end)
def("debugprofilestop", function() return os.clock() * 1000 end)
def("LibStub", setmetatable({ GetLibrary = function() return nil end, NewLibrary = function() return {} end }, { __call = function(_, name, silent) if not silent then error("pas de " .. name) end end }))
def("StaticPopupDialogs", {})
def("DEFAULT_CHAT_FRAME", { AddMessage = function() end })
def("EventUtil", { ContinueOnAddOnLoaded = function() end, RegisterOnceFrameEventAndCallback = function() end })
local files = {}
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    local f = line:match("^([%w_%.\\]+%.lua)")
    if f then files[#files + 1] = f end
end
def("PlatyplusDB", { welcomeSeen = true, language = ARGS[4] })   -- ARGS[4] : langue de Platyplus (frFR par défaut via GetLocale)   -- la présentation a sa propre capture, pas sur les autres
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(2)

---------------------------------------------------------------------------
-- Mise en page : position absolue de chaque région (coordonnées WoW, y vers le haut)
---------------------------------------------------------------------------
local S = M.state
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local FONTS = {
    GameFontNormal = { 13, { 1, 0.82, 0 } }, GameFontNormalSmall = { 11, { 1, 0.82, 0 } },
    GameFontNormalLarge = { 16, { 1, 0.82, 0 } }, GameFontNormalHuge = { 20, { 1, 0.82, 0 } },
    GameFontHighlight = { 13, { 1, 1, 1 } }, GameFontHighlightSmall = { 11, { 1, 1, 1 } },
    GameFontHighlightLarge = { 16, { 1, 1, 1 } }, GameFontDisable = { 13, { 0.5, 0.5, 0.5 } },
    GameFontDisableSmall = { 11, { 0.5, 0.5, 0.5 } }, GameFontWhite = { 13, { 1, 1, 1 } },
    NumberFontNormal = { 14, { 1, 1, 1 }, "OUTLINE" }, NumberFontNormalSmallGray = { 12, { 0.6, 0.6, 0.6 }, "OUTLINE" },
    GameFontHighlightSmallOutline = { 11, { 1, 1, 1 }, "OUTLINE" }, ChatFontNormal = { 14, { 1, 1, 1 } },
    SystemFont_Shadow_Small = { 11, { 1, 0.82, 0 } },
}
local isRegion = { Texture = true, FontString = true, MaskTexture = true }
local isFrameKind = function(s) return not isRegion[s.kind] end
local order = {}
for i, f in ipairs(M.allFrames) do order[f] = i end

local function frameOf(f)
    local s = S(f)
    if isRegion[s.kind] then return s.parent end
    return f
end

local function effScale(f)
    local scale, cur = 1, frameOf(f)
    while cur do
        local s = S(cur)
        scale = scale * (s.scale or 1)
        cur = s.parent
    end
    return scale
end

local strataCache, levelCache = {}, {}
local function strataOf(f)
    if strataCache[f] then return strataCache[f] end
    local s = S(f)
    local v = (s.strataSet and s.strata) or (s.parent and strataOf(s.parent)) or "MEDIUM"
    strataCache[f] = v
    return v
end
local function levelOf(f)
    if levelCache[f] then return levelCache[f] end
    local s = S(f)
    local v = (s.levelSet and s.level) or (s.parent and levelOf(s.parent) + 1) or 0
    levelCache[f] = v
    return v
end

local function stripCodes(t)
    t = tostring(t or "")
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "WW")
    return t
end
local function utf8len(t)
    local n = 0
    for _ in t:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n
end

local function fontInfo(s)
    local obj = s.fontObject
    local name = type(obj) == "string" and obj or (obj and S(obj) and S(obj).name)
    local base = FONTS[name or ""] or { 12, { 1, 1, 1 } }
    return s.fontSize or base[1], s.textColor or base[2], s.fontFlags or base[3]
end

local scrollParent = {}
for _, f in ipairs(M.allFrames) do
    local s = S(f)
    if s.kind == "ScrollFrame" and s.scrollChild then scrollParent[s.scrollChild] = f end
end

local cache = {}
local function pointXY(r, point)
    local x = point:find("LEFT") and r.l or point:find("RIGHT") and r.r or (r.l + r.r) / 2
    local y = point:find("TOP") and r.t or point:find("BOTTOM") and r.b or (r.t + r.b) / 2
    return x, y
end

local resolve
resolve = function(f, depth)
    if cache[f] ~= nil then return cache[f] or nil end
    depth = (depth or 0) + 1
    if depth > 80 then return nil end
    local s = S(f)
    if f == UIParent then
        cache[f] = { l = 0, r = SW, t = SH, b = 0 }
        return cache[f]
    end
    local es = effScale(f)
    local w, h = (s.w or 0) * es, (s.h or 0) * es
    if s.kind == "FontString" or (s.text and s.text ~= "" and isFrameKind(s)) then
        local size = fontInfo(s)
        if (s.w or 0) == 0 then w = utf8len(stripCodes(s.text)) * size * 0.55 * es end
        if (s.h or 0) == 0 then h = size * 1.3 * es end
    end
    -- remplissage d'une StatusBar : la part (valeur - min) / (max - min) du cadre de la barre
    if s.isBarFill then
        local bar = S(s.parent)
        local pr = resolve(s.parent, depth)
        if not pr or type(bar.value) ~= "number" then cache[f] = false return nil end
        local span = (bar.max or 1) - (bar.min or 0)
        local frac = span > 0 and math.max(0, math.min(1, (bar.value - (bar.min or 0)) / span)) or 0
        cache[f] = { l = pr.l, r = pr.l + (pr.r - pr.l) * frac, t = pr.t, b = pr.b }
        return cache[f]
    end
    local sf = scrollParent[f]
    if sf then
        local pr = resolve(sf, depth)
        if not pr then cache[f] = false return nil end
        local l, t = pr.l - (S(sf).hscroll or 0) * es, pr.t + (S(sf).vscroll or 0) * es
        cache[f] = { l = l, r = l + w, t = t, b = t - h }
        return cache[f]
    end
    local anchors, any = {}, false
    for _, p in ipairs(s.points) do anchors[p[1]] = p; any = true end
    if not any then cache[f] = false return nil end
    local L, R, T, B, CX, CY
    for name, p in pairs(anchors) do
        local rel = p[2] or s.parent or UIParent
        local rr = resolve(rel, depth)
        if not rr then cache[f] = false return nil end
        local x, y = pointXY(rr, p[3] or name)
        x, y = x + (p[4] or 0) * es, y + (p[5] or 0) * es
        if name:find("LEFT") then L = x elseif name:find("RIGHT") then R = x else CX = x end
        if name:find("TOP") then T = y elseif name:find("BOTTOM") then B = y else CY = y end
    end
    local l, r, t, b
    if L and R then l, r = L, R elseif L then l, r = L, L + w elseif R then l, r = R - w, R elseif CX then l, r = CX - w / 2, CX + w / 2 end
    if T and B then t, b = T, B elseif T then t, b = T, T - h elseif B then t, b = B + h, B elseif CY then t, b = CY + h / 2, CY - h / 2 end
    if not (l and t) then cache[f] = false return nil end
    cache[f] = { l = l, r = r, t = t, b = b }
    return cache[f]
end

-- le simulateur renvoie d'habitude une position fixe : ici on calcule la vraie, pour que les modules
-- qui choisissent un côté (barre d'infos à gauche ou à droite de l'icône) se comportent comme en jeu
local function liveRect(f)
    cache = {}
    return resolve(f)
end
M.impl.GetCenter = function(f)
    local r = liveRect(f)
    if not r then return nil end
    local es = effScale(f)
    return (r.l + r.r) / 2 / es, (r.t + r.b) / 2 / es
end
M.impl.GetLeft = function(f) local r = liveRect(f); return r and r.l / effScale(f) end
M.impl.GetRight = function(f) local r = liveRect(f); return r and r.r / effScale(f) end
M.impl.GetTop = function(f) local r = liveRect(f); return r and r.t / effScale(f) end
M.impl.GetBottom = function(f) local r = liveRect(f); return r and r.b / effScale(f) end

local function visible(f)
    local cur = f
    while cur do
        local s = S(cur)
        if not s.shown then return false end
        cur = s.parent
    end
    return true
end
local function alphaOf(f)
    local a, cur = 1, f
    while cur do
        local s = S(cur)
        a = a * (s.alpha or 1)
        cur = s.parent
    end
    return a
end
local function clipOf(f)
    local clip, cur = nil, S(f).parent
    while cur do
        local s = S(cur)
        if s.kind == "ScrollFrame" or s.clips then
            local r = resolve(cur)
            if r then
                if not clip then clip = { l = r.l, r = r.r, t = r.t, b = r.b }
                else
                    clip.l, clip.r = math.max(clip.l, r.l), math.min(clip.r, r.r)
                    clip.t, clip.b = math.min(clip.t, r.t), math.max(clip.b, r.b)
                end
            end
        end
        cur = s.parent
    end
    return clip
end

---------------------------------------------------------------------------
-- Export JSON
---------------------------------------------------------------------------
local function esc(str)
    return (tostring(str):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" end
        return string.format("\\u%04x", c:byte())
    end))
end
local function enc(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local parts = {}
            for i = 1, #v do parts[i] = enc(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = '"' .. esc(k) .. '":' .. enc(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "number" then
        return string.format("%.3f", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif v == nil then
        return "null"
    end
    return '"' .. esc(v) .. '"'
end

local function shot(name)
    cache, strataCache, levelCache = {}, {}, {}
    for i, f in ipairs(M.allFrames) do order[f] = i end
    scrollParent = {}
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "ScrollFrame" and s.scrollChild then scrollParent[s.scrollChild] = f end
    end
    local out = {}
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        local drawable = (s.kind == "Texture" and s.texture ~= nil)
            or (s.kind == "FontString" and s.text ~= nil and s.text ~= "")
            or (isFrameKind(s) and s.text ~= nil and s.text ~= "" and (s.kind == "Button" or s.kind == "EditBox" or s.kind == "CheckButton"))
        if drawable and visible(f) and (s.layer ~= "HIGHLIGHT") then
            local r = resolve(f)
            local a = alphaOf(f)
            if r and a > 0.01 and (r.r - r.l) > 0.5 and (r.t - r.b) > 0.5 then
                local fr = frameOf(f)
                local e = {
                    kind = s.kind, x = r.l, y = SH - r.t, w = r.r - r.l, h = r.t - r.b, a = a,
                    k = { STRATA[strataOf(fr)] or 3, levelOf(fr), LAYER[s.layer or "ARTWORK"] or 3, s.sublevel or 0, order[f] },
                }
                local clip = clipOf(f)
                if clip then e.clip = { clip.l, SH - clip.t, clip.r, SH - clip.b } end
                if s.kind == "Texture" then
                    e.tex = s.texture
                    e.color = s.color
                    e.tc = s.texcoord
                    e.tc8 = s.texcoord8
                    e.vc = s.vertex
                    e.desat = s.desat
                    e.blend = s.blend
                else
                    local size, color, flags = fontInfo(s)
                    -- texte à largeur fixe : WoW passe à la ligne, la hauteur suit
                    local hasWidth = (s.w or 0) > 0
                    if not hasWidth then
                        local hl, hr = false, false
                        for _, p in ipairs(s.points) do
                            if p[1]:find("LEFT") then hl = true end
                            if p[1]:find("RIGHT") then hr = true end
                        end
                        hasWidth = hl and hr
                    end
                    if s.kind == "FontString" and s.wordWrap ~= false and hasWidth then
                        local es = effScale(f)
                        local est = utf8len(stripCodes(s.text)) * size * 0.55 * es
                        local lines = math.max(1, math.ceil(est / math.max(1, e.w)))
                        if lines > 1 then
                            e.wrap = true
                            e.h = math.max(e.h, lines * size * 1.2 * es)
                        end
                    end
                    e.text = tostring(s.text)
                    e.size = size * effScale(f)
                    e.color = color
                    e.flags = flags
                    e.jh = s.justifyH or (isFrameKind(s) and "CENTER") or "CENTER"
                    e.jv = s.justifyV or "MIDDLE"
                    e.shadow = s.shadow
                end
                out[#out + 1] = e
            end
        end
    end
    table.sort(out, function(p, q)
        for i = 1, 5 do
            if p.k[i] ~= q.k[i] then return p.k[i] < q.k[i] end
        end
        return false
    end)
    local fh = assert(io.open(OUT .. "\\" .. name .. ".json", "w"))
    fh:write('{"w":' .. SW .. ',"h":' .. SH .. ',"items":' .. enc(out) .. "}")
    fh:close()
    M.realPrint("capture " .. name .. " : " .. #out .. " éléments")
end

---------------------------------------------------------------------------
-- Mise en scène
---------------------------------------------------------------------------
ns.db.duration = 120
-- positions réelles disponibles : les modules recalculent leur placement
if ns.Launcher and ns.Launcher.Refresh then ns.Launcher:Refresh() end
if ns.Float and ns.Float.Test then ns.Float:Test() end
def("UnitAttackSpeed", function() return 2.6, 1.8 end)
def("C_SwingTimer", { IsTargetWithinSwingRange = function() return true end })
if ns.SwingBar and ns.SwingBar.Preview then ns.SwingBar:Preview(120) end
M.fireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 0)
M.advance(4)
shot("ecran")

if ns.Launcher and ns.Launcher.ShowMenu then ns.Launcher:ShowMenu() end
M.advance(0.5)
shot("menu")
if ns.Launcher and ns.Launcher.HideMenu then ns.Launcher:HideMenu() end

if ns.UI then
    ns.UI:Open()
    M.advance(1)
    local count = (ns.Pages and ns.Pages.Count and ns.Pages:Count()) or 8
    for i = 1, count do
        if ns.UI.SelectTab then ns.UI:SelectTab(i) end
        M.advance(1)
        shot(string.format("options_%d", i))
        -- bas de la page (cartes sous la ligne de flottaison, ex. « Manger » dans Général)
        if ns.UI.SetScroll and ns.UI.ScrollRange and ns.UI:ScrollRange() > 0 then
            ns.UI:SetScroll(ns.UI:ScrollRange())
            M.advance(0.2)
            shot(string.format("options_%d_bas", i))
            ns.UI:SetScroll(0)
        end
    end
end

-- cartes de récompense de quête (aperçu /pp cartes, par-dessus l'écran de jeu)
if ns.UI and ns.UI.Close then ns.UI:Close() end
M.advance(0.5)
if ns.QuestCards and ns.QuestCards.Demo then
    ns.QuestCards:Demo()
    M.advance(0.5)
    shot("cartes")
    ns.QuestCards:Hide()
end

-- présentation « Bienvenue dans Platyplus »
if ns.UI and ns.UI.ShowWelcome then
    if ns.UI.Close then ns.UI:Close() end
    ns.UI:ShowWelcome(1)
    M.advance(0.3)
    shot("bienvenue")
    -- une capture par étape de la visite guidée : bienvenue_2 (le mode) ... bienvenue_10 (fin)
    local wf = ns.UI.welcome
    for i = 2, (wf and wf.steps and #wf.steps or 0) do
        wf:ShowStep(i)
        M.advance(0.3)
        shot("bienvenue_" .. i)
    end
end

-- fenêtre du personnage : chaque onglet
if ns.CharWindow and rawget(_G, "ToggleCharacter") then
    if ns.UI and ns.UI.Close then ns.UI:Close() end
    if ns.UI and ns.UI.welcome then ns.UI.welcome:Hide() end
    ToggleCharacter("PaperDollFrame")
    M.advance(0.5)
    shot("perso")
    for _, tab in ipairs({ "ReputationFrame", "SkillsFrame", "PVPRankFrame" }) do
        ToggleCharacter(tab, true)
        M.advance(0.5)
        shot("perso_" .. tab)
    end
    ToggleCharacter("PaperDollFrame")
    ToggleCharacter("PaperDollFrame")
    M.advance(0.3)
end

-- dialogue avec un PNJ : discussion (touches F, 1, 2, 3), puis quête à rendre (récompenses numérotées)
if ns.QuestWindow then
    if ns.UI and ns.UI.Close then ns.UI:Close() end
    ShowUIPanel(gossipFrame)
    M.fireEvent("GOSSIP_SHOW")
    M.advance(0.5)
    shot("dialogue")
    gossipFrame:Hide()
    M.fireEvent("GOSSIP_CLOSED")
    ShowUIPanel(questFrame)
    questPanels.Reward:Show()
    M.fireEvent("QUEST_COMPLETE")
    M.advance(0.5)
    shot("dialogue_recompense")
    questFrame:Hide()
    questPanels.Reward:Hide()
    M.fireEvent("QUEST_FINISHED")
    M.advance(0.5)
end

-- fenêtre de chat Platyplus : une conversation de groupe (bulles), puis l'onglet Jeu
if ns.ChatWindow and ns.ChatWindow.frame then
    if ns.UI and ns.UI.Close then ns.UI:Close() end
    local CW = ns.ChatWindow
    local src = CreateFrame("Frame", "ChatFrame1Preview", UIParent)
    def("Ambiguate", function(name) return (tostring(name):match("^[^%-]+")) end)
    def("GetPlayerInfoByGUID", function(guid)
        local classes = { ["Player-Sto"] = "DRUID", ["Player-Ry"] = "MAGE", ["Player-Menethel"] = "WARRIOR" }
        return nil, classes[guid]
    end)
    def("RAID_CLASS_COLORS", { DRUID = { r = 1, g = 0.49, b = 0.04 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } })
    CW.frame:ClearAllPoints()
    CW.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 120)
    CW.frame:SetSize(560, 360)
    local clock = { "16:14", "16:16", "16:17", "16:17", "16:17", "16:18", "16:18", "16:18", "16:19" }
    local n = 0
    local function talk(event, msg, author, r, g, b)
        n = n + 1
        def("date", function() return clock[n] or "16:19" end)
        local a = { msg, author, "", "", "", "", 0, 0, "", 0, 1000 + n, "Player-" .. (author:match("^[^%-]+")), 0, false, false, false, false, n = 17 }
        CW.AfterAddMessage(src, msg, r, g, b, 1, 0, 0, event, a)
        M.advance(0.1)
    end
    local P = { 0.67, 0.67, 1 }
    talk("CHAT_MSG_PARTY", "We good to go", "Menethel-Royaume", P[1], P[2], P[3])
    talk("CHAT_MSG_PARTY", "come fast mates l", "Sto-Royaume", P[1], P[2], P[3])
    talk("CHAT_MSG_PARTY", "lets go", "Sto-Royaume", P[1], P[2], P[3])
    talk("CHAT_MSG_PARTY", "summ stone in forever or no ?", "Ry-Royaume", P[1], P[2], P[3])
    talk("CHAT_MSG_PARTY", "nop", "Menethel-Royaume", P[1], P[2], P[3])
    M.time = M.time + 70
    talk("CHAT_MSG_PARTY", "need to take zepp from under, I come asap, wait for me at the entrance please", "Ry-Royaume", P[1], P[2], P[3])
    talk("CHAT_MSG_PARTY", "ok on t'attend devant", "Platy-Royaume", P[1], P[2], P[3])
    talk("CHAT_MSG_WHISPER", "tu peux me résumer la strat ?", "Sto-Royaume", 1, 0.5, 1)
    CW.AfterAddMessage(src, "Vous recevez du butin : |cff1eff00[Épée du corbeau]|r", 1, 1, 0, 1, 0, 0, "CHAT_MSG_LOOT", nil)
    CW:SelectTab("group")
    M.advance(0.3)
    shot("chat_groupe")
    CW:SelectTab("chat")
    M.advance(0.3)
    shot("chat")
    ns:Set("chatWinTwoLines", false)
    M.advance(0.3)
    shot("chat_compact")
    ns:Set("chatWinTwoLines", true)
end

-- alertes de proc : l'aperçu (Fulgurance sur « 3 ») et l'icône de Maîtrise du blocage avec ses charges
if ns.Procs and ns.Procs.frames and ns.Procs.frames.chip then
    if ns.UI and ns.UI.Close then ns.UI:Close() end
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Hide() end
    ns.Procs:Preview(30)
    M.advance(1)
    shot("procs")
    -- une charge consommée pendant l'animation : « 1 », la barrette perdue qui s'éteint, le « -1 » qui s'envole
    local chip = ns.Procs.frames.chip
    chip.preview = false
    chip.lostPip, chip.loseAt = 2, GetTime() - 0.12
    chip.count:SetText("1")
    if ns.Procs.ChipAnimate then ns.Procs.ChipAnimate() end
    shot("procs_charge")
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Show() end
end

-- page d'une quête du journal (QuestPage.lua) sur une fausse page de Blizzard
if ns.QuestPage then
    if ns.UI and ns.UI.Close then ns.UI:Close() end
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Hide() end
    local holder = CreateFrame("Frame", "QuestMapFrame", UIParent)
    holder:SetSize(310, 600)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    holder:SetFrameStrata("DIALOG")
    local df = CreateFrame("Frame", nil, holder)
    df:SetAllPoints()
    holder.DetailsFrame = df
    df.ScrollFrame = CreateFrame("Frame", nil, df)
    df.ScrollFrame:SetPoint("TOPLEFT", df, "TOPLEFT", 5, -43)
    df.ScrollFrame:SetSize(298, 430)
    df.RewardsFrameContainer = CreateFrame("Frame", nil, df)
    df.BackFrame = CreateFrame("Frame", nil, df)
    df.BackFrame:SetPoint("TOPLEFT")
    df.BackFrame:SetPoint("TOPRIGHT")
    df.BackFrame:SetHeight(40)
    local back = CreateFrame("Button", nil, df.BackFrame)
    back:SetSize(90, 22)
    back:SetPoint("LEFT", df.BackFrame, "LEFT", 11, 4)
    back.Left, back.Middle, back.Right = back:CreateTexture(), back:CreateTexture(), back:CreateTexture()
    local bt = back:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bt:SetPoint("CENTER")
    bt:SetText("Retour")
    back.GetFontString = function() return bt end
    local x = 0
    for _, label in ipairs({ "Abandonner", "Partager", "Suivre" }) do
        local b = CreateFrame("Button", nil, df)
        b:SetSize(100, 22)
        b:SetPoint("BOTTOMLEFT", df, "BOTTOMLEFT", x, 2)
        x = x + 102
        b.Left, b.Middle, b.Right = b:CreateTexture(), b:CreateTexture(), b:CreateTexture()
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("CENTER")
        t:SetText(label)
        b.GetFontString = function() return t end
    end
    def("C_QuestLog", {
        GetTitleForQuestID = function() return "Les loups des bois" end,
        GetLogIndexForQuestID = function() return 3 end,
        GetInfo = function() return { level = 10, suggestedGroup = 0 } end,
        IsComplete = function() return false end,
        GetQuestObjectives = function()
            return { { text = "Pattes de loup : 4/8", finished = false }, { text = "Parler à Marshal Dughan", finished = true } }
        end,
    })
    def("GetQuestLogQuestText", function()
        return "Les loups rôdent près de la ferme Maclure depuis des semaines. Les fermiers n'osent plus sortir leurs "
            .. "bêtes, et le Marshal n'a pas assez d'hommes pour les chasser.", "Rapporte 8 pattes de loup au Marshal Dughan, à Comté-de-l'Or."
    end)
    def("GetNumQuestLogChoices", function() return 2 end)
    def("GetQuestLogChoiceInfo", function(i)
        if i == 1 then return "Bottes de chasseur", "Interface\\Icons\\INV_Boots_05", 1, 2, true end
        return "Gants de forestier", "Interface\\Icons\\INV_Gauntlets_04", 1, 3, true
    end)
    def("GetNumQuestLogRewards", function() return 1 end)
    def("GetQuestLogRewardInfo", function() return "Potion de soins", "Interface\\Icons\\INV_Potion_51", 3, 1, true end)
    def("GetQuestLogItemLink", function() return nil end)
    def("GetQuestLogRewardMoney", function() return 1250 end)
    def("GetQuestLogRewardXP", function() return 850 end)
    ns.QuestPage:Show(77)
    M.advance(0.2)
    shot("quete_page")
    ns.QuestPage:Hide()
    holder:Hide()
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Show() end
end

-- journal des donjons (DungeonJournal intégré) : style Platyplus et liste des donjons à gauche. Guerrier 42 :
-- Uldaman (38-48) est à son niveau. Les images du journal (Media/*.tga du dossier DungeonJournal) ne sont pas
-- lues par preview_html.py : pastilles de couleur à la place des illustrations des donjons et des portraits.
local djToggle = rawget(_G, "PlatyplusDungeon_Toggle")
if djToggle and ns.Dungeon and ns.Dungeon.PpSelectDungeon then
    djToggle()
    M.advance(0.5)
    shot("donjons_accueil")
    ns.Dungeon.PpSelectDungeon("Uldaman")
    M.advance(0.5)
    shot("donjons_boss")
    local dj = rawget(_G, "PlatyplusDungeonFrame")
    if dj and dj.questsTab then
        M.fire(dj.questsTab, "OnClick", "LeftButton")
        M.advance(0.5)
        shot("donjons_quetes")
    end
    if dj then dj:Hide() end
end

-- jets de butin (LootRolls) : données d'exemple
if ns.LootRolls and ns.LootRolls.Demo then
    if ns.UI and ns.UI.Close then ns.UI:Close() end
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Hide() end
    def("RAID_CLASS_COLORS", {
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        ROGUE = { r = 1, g = 0.96, b = 0.41 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 },
        PRIEST = { r = 1, g = 1, b = 1 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
    })
    for _, n in ipairs({ "PlatyplusFeed", "PlatyplusAnchor" }) do local f = rawget(_G, n); if f then f:Hide() end end
    ns.LootRolls:Demo()
    M.advance(0.5)
    local Wd = ns.W; if Wd and Wd.FinishAnimations then Wd.FinishAnimations() end   -- (voir bug OnUpdate écrasé : fondu bloqué à 0)
    M.advance(0.3)
    shot("jets")
    ns.LootRolls:Close()
    ns.LootRolls:Demo()
    ns.LootRolls:SetMode("roll")
    M.advance(0.5)
    if Wd and Wd.FinishAnimations then Wd.FinishAnimations() end
    M.advance(0.3)
    shot("jets_roll")
    ns.LootRolls:SetMode("loot")
    ns.LootRolls:Close()
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Show() end
end

-- fenêtre de menace (Threat) : mobs factices de l'aperçu /pp menace test
if ns.Threat and ns.Threat.Test then
    if ns.UI and ns.UI.Close then ns.UI:Close() end
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Hide() end
    ns.Threat:Test()
    M.advance(0.5)
    local Wd = ns.W; if Wd and Wd.FinishAnimations then Wd.FinishAnimations() end
    M.advance(0.3)
    shot("menace")
    ns.Threat:Test()
    M.advance(0.5)
    if Wd and Wd.FinishAnimations then Wd.FinishAnimations() end
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Show() end
end

M.realPrint("erreurs d'exécution pendant la mise en scène : " .. #M.errors)
for i, e in ipairs(M.errors) do if i <= 5 then M.realPrint("  " .. e:sub(1, 300)) end end
