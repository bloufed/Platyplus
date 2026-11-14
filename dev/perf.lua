-- Banc de performance de Platyplus (hors du jeu, moteur LuaJIT d'OBS : les temps absolus sont plus rapides qu'en jeu,
-- ce qui compte ce sont les tendances : rien qui tourne au repos, pas de mémoire qui grimpe, coût par événement minime).
-- Usage : python -I lua.py run perf.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end

-- monde : guerrier, rage qui varie, 8 sorts sur la barre, un sac plein d'objets
local rage = 0
def("UnitExists", function(u) return u == "player" end)
def("UnitPowerType", function() return 1, "RAGE", 0, 0, 0 end)
def("UnitPower", function() return rage end)
def("UnitPowerMax", function() return 100 end)
def("PowerBarColor", { RAGE = { r = 1, g = 0, b = 0 }, [1] = { r = 1, g = 0, b = 0 } })
def("GetFramerate", function() return 144 end)
def("GetNetStats", function() return 0, 0, 38, 42 end)
def("UnitXP", function() return 4520 end)
def("UnitXPMax", function() return 12000 end)
def("UnitLevel", function() return 42 end)
def("GetInventoryAlertStatus", function() return 0 end)
def("C_Map", { GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end })
local costs = { 15, 10, 30, 30, 10, 25, 0, 60 }
def("GetActionInfo", function(a) if costs[a] then return "spell", 100 + a end end)
def("C_Spell", {
    GetSpellPowerCost = function(id) local c = costs[id - 100]; if c and c > 0 then return { { type = 1, name = "RAGE", cost = c, minCost = c } } end return {} end,
    IsSpellUsable = function(id) local c = costs[id - 100] or 0; return c <= rage, c > rage end,
    GetSpellTexture = function() return "Interface\\Icons\\Ability_Warrior_Charge" end,
    GetSpellInfo = function(id) return { name = "Sort " .. id, iconID = 1, spellID = id } end,
})
def("C_ActionBar", { IsUsableAction = function(a) local c = costs[a] or 0; return c <= rage, c > rage end,
    HasAction = function(a) return costs[a] ~= nil end })
def("ActionButtonUtil", { ActionBarButtonNames = { "ActionButton" } })
for i = 1, 8 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b:SetSize(45, 45); b.action = i
    b.TextOverlayContainer = CreateFrame("Frame", nil, b)
end
local pf = CreateFrame("Frame", "PlayerFrame", UIParent)
pf.PlayerFrameContainer = CreateFrame("Frame", nil, pf)
pf.PlayerFrameContainer.PlayerPortrait = pf.PlayerFrameContainer:CreateTexture()
def("C_Container", {
    GetContainerNumSlots = function(b) return b == 0 and 20 or 0 end,
    GetContainerNumFreeSlots = function(b) return b == 0 and 4 or 0, 0 end,
    GetContainerItemInfo = function(b, slot)
        if b ~= 0 then return nil end
        return { iconFileID = 1, stackCount = slot, isLocked = false, quality = slot % 4, itemID = 1000 + slot,
                 hyperlink = "|Hitem:" .. (1000 + slot) .. "|h[Objet " .. slot .. "]|h", hasNoValue = false, isBound = true }
    end,
    GetContainerItemEquipmentSetInfo = function() return false, "" end,
})
def("C_Item", {
    GetItemInfo = function() return "Objet", nil, 1, 10, 1, "", "", 1, "", 1, 25, 7, 0, 0 end,
    GetItemInfoInstant = function(l) return tonumber(tostring(l):match("item:(%d+)")), "", "", "", 1, 7, 0 end,
    GetDetailedItemLevelInfo = function() return 10 end,
})
def("GetInventoryItemLink", function() return nil end)
local lootQueue = {}
def("GetNumLootItems", function() return 2 end)
def("GetLootSlotType", function() return 1 end)
def("GetLootSlotInfo", function(i) return 1, "Objet " .. i, 1, nil, 2, false end)
def("GetLootSlotLink", function(i) return "|Hitem:" .. (2000 + i) .. "|h[Objet " .. i .. "]|h" end)
def("LootSlot", function(i) lootQueue[#lootQueue + 1] = i end)
def("StaticPopup_Hide", function() end)

local files = {}
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    local f = line:match("^([%w_%.]+%.lua)%s*$")
    if f then files[#files + 1] = f end
end
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(8)   -- fin des fondus et des délais de démarrage

local P = M.realPrint
local function kb() collectgarbage("collect"); return collectgarbage("count") end
local function activeOnUpdates()
    local list = {}
    for _, f in ipairs(M.allFrames) do
        local s = M.state(f)
        if s.scripts.OnUpdate and M.impl.IsVisible(f) then list[#list + 1] = tostring(s.name or s.kind) end
    end
    return list
end
local function activeTimers()
    local n = 0
    for _, t in ipairs(M.timers) do if not t.cancelled then n = n + 1 end end
    return n
end

P("== au repos (après la connexion, rien ne se passe) ==")
local idle = activeOnUpdates()
P(string.format("  OnUpdate actifs à chaque image : %d %s", #idle, #idle > 0 and ("(" .. table.concat(idle, ", ") .. ")") or ""))
P(string.format("  minuteries actives : %d (rafraîchissement 1 s de la barre d'infos + filet de sécurité 5 s des coûts)", activeTimers()))
local f0, p0 = #M.allFrames, #M.printed
local m0 = kb()
local t0 = os.clock()
M.advance(600)   -- 10 minutes de jeu sans rien faire
local idleMs = (os.clock() - t0) * 1000
local m1 = kb()
P(string.format("  objets d'interface créés pendant ces 10 min : %d ; lignes de chat : %d", #M.allFrames - f0, #M.printed - p0))
P(string.format("  10 min simulées : %.1f ms de calcul Platyplus au total, mémoire %.0f Ko -> %.0f Ko (%+.1f Ko)", idleMs, m0, m1, m1 - m0))
local mi = kb()
M.advance(600)
P(string.format("  10 min de plus : mémoire %+.1f Ko (une fuite ferait remonter à chaque fois)", kb() - mi))

P("== rage qui change en combat (UNIT_POWER_FREQUENT) ==")
local m2 = kb()
t0 = os.clock()
for i = 1, 10000 do
    rage = (i * 7) % 101
    M.fireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
    if i % 20 == 0 then M.advance(0.05) end   -- le jeu affiche une image entre deux rafales
end
local powerMs = (os.clock() - t0) * 1000
local m3 = kb()
P(string.format("  objets d'interface créés pendant ces événements : %d", #M.allFrames - f0))
-- deuxième passe identique : si la mémoire ne remonte pas, la hausse de la 1re passe était un cache qui s'est rempli
local m3b = kb()
for i = 1, 10000 do
    rage = (i * 7) % 101
    M.fireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
    if i % 20 == 0 then M.advance(0.05) end
end
P(string.format("  2e passe de 10 000 événements : mémoire %+.1f Ko (une fuite ferait remonter à chaque passe)", kb() - m3b))
P(string.format("  10 000 événements : %.1f ms (%.1f µs par événement), mémoire %+.1f Ko après nettoyage", powerMs, powerMs, m3 - m2))

P("== barres d'action qui changent (ACTION_USABLE_CHANGED / ACTIONBAR_SLOT_CHANGED) ==")
t0 = os.clock()
for i = 1, 2000 do
    M.fireEvent("ACTION_USABLE_CHANGED", {})
    M.fireEvent("ACTIONBAR_SLOT_CHANGED", (i % 8) + 1)
end
M.advance(0.2)
local abMs = (os.clock() - t0) * 1000
P(string.format("  4 000 événements en rafale : %.1f ms (regroupés en une seule relecture des barres)", abMs))

P("== sacs qui bougent (BAG_UPDATE / BAG_UPDATE_DELAYED) ==")
t0 = os.clock()
for i = 1, 500 do
    M.fireEvent("BAG_UPDATE", 0)
    M.fireEvent("BAG_UPDATE_DELAYED")
end
M.advance(0.5)
local bagMs = (os.clock() - t0) * 1000
P(string.format("  1 000 événements de sacs : %.1f ms (regroupés)", bagMs))

P("== butin (LOOT_READY + cases ramassées) ==")
t0 = os.clock()
for i = 1, 300 do
    M.fireEvent("LOOT_READY", true)
    for _, slot in ipairs(lootQueue) do M.fireEvent("LOOT_SLOT_CLEARED", slot) end
    lootQueue = {}
    M.fireEvent("LOOT_CLOSED")
    M.advance(0.05)
end
local lootMs = (os.clock() - t0) * 1000
P(string.format("  300 corps ramassés (600 objets) : %.1f ms, soit %.2f ms par corps (flux animé compris)", lootMs, lootMs / 300))
M.advance(10)
local after = activeOnUpdates()
P(string.format("  après le butin, le flux s'éteint seul : %d OnUpdate actif(s)", #after))

P("== bilan ==")
P(string.format("  erreurs d'exécution : %d", #M.errors))
for i, e in ipairs(M.errors) do if i <= 3 then P("  " .. e:sub(1, 200)) end end
