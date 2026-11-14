-- Scénario : noyau + loot + flux flottant + interaction + dialogues
local ADDON_DIR, SCRATCH = ARGS[1], ARGS[2]
local M = dofile(SCRATCH .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end

-- API de loot simulée
local lootCalls, confirmCalls, popupHidden = {}, {}, {}
local slots = {
    { type = 1, icon = "icon1", name = "Epee rouillee", qty = 1, quality = 2, link = "|cff1eff00|Hitem:123::::::::|h[Epee rouillee]|h|r" },
    { type = 2, icon = "coin", name = "3 Argent\n20 Cuivre", qty = 0, quality = 0, link = nil },
}
def("GetNumLootItems", function() return #slots end)
def("GetLootSlotType", function(i) return slots[i] and slots[i].type or 0 end)
def("GetLootSlotInfo", function(i) local s = slots[i]; return s.icon, s.name, s.qty, nil, s.quality, false end)
def("GetLootSlotLink", function(i) return slots[i].link end)
def("LootSlot", function(i)
    lootCalls[#lootCalls + 1] = i
    M.fireEvent("LOOT_SLOT_CLEARED", i)
end)
def("ConfirmLootSlot", function(i) confirmCalls[#confirmCalls + 1] = i end)
def("StaticPopup_Hide", function(which) popupHidden[#popupHidden + 1] = which end)

-- dialogues simulés
local gossipCalls = {}
def("C_GossipInfo", {
    GetActiveQuests = function() return {} end,
    GetAvailableQuests = function() return { { questID = 777, title = "Une quete", isIgnored = false } } end,
    GetOptions = function() return { { orderIndex = 1, status = 0, gossipOptionID = 9, name = "Entrainement" } } end,
    SelectActiveQuest = function(id) gossipCalls[#gossipCalls + 1] = "active:" .. id end,
    SelectAvailableQuest = function(id) gossipCalls[#gossipCalls + 1] = "available:" .. id end,
    SelectOptionByIndex = function(i) gossipCalls[#gossipCalls + 1] = "option:" .. i end,
})
local gossip = CreateFrame("Frame", "GossipFrame", UIParent); gossip:Hide()
local quest = CreateFrame("Frame", "QuestFrame", UIParent); quest:Hide()

-- chargement
local files = {}
if ARGS[3] then
    for f in ARGS[3]:gmatch("[^,]+") do files[#files + 1] = f end   -- liste explicite de fichiers
else
    for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
        local f = line:match("^([%w_%.]+%.lua)%s*$")
        if f then files[#files + 1] = f end
    end
end
M.realPrint("fichiers du TOC : " .. table.concat(files, ", "))
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)

M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.2)

M.realPrint("== connexion ==")
check(ns.db ~= nil, "ns.db créé")
check(M.overrides["F"] == "INTERACTMOUSEOVER", "F liée à INTERACTMOUSEOVER (" .. tostring(M.overrides["F"]) .. ")")
check(M.cvars.SoftTargetInteract == "3", "SoftTargetInteract = 3")
check(M.cvars.autoLootDefault == "1", "autoLootDefault = 1")
ns:Set("instantLoot", false)
check(M.cvars.autoLootDefault == "0" and ns.db.cvarBackup.autoLootDefault == nil, "loot instantané coupé : loot auto du jeu remis comme avant (0)")
ns:Set("instantLoot", true)
check(M.cvars.autoLootDefault == "1" and ns.db.cvarBackup.autoLootDefault == "0", "rallumé : 1, valeur d'origine gardée")

M.realPrint("== loot ==")
M.fireEvent("LOOT_READY", true)
M.advance(0.1)
check(#lootCalls == 2 and lootCalls[1] == 2 and lootCalls[2] == 1, "LootSlot appelé en ordre inverse (" .. table.concat(lootCalls, ",") .. ")")
local rows = 0
for _, f in ipairs(M.allFrames) do
    local s = M.state(f)
    -- les cartes du flux sont les frames visibles posées dans le conteneur PlatyplusFeed
    if s.kind == "Frame" and s.parent == PlatyplusFeed and s.shown then rows = rows + 1 end
end
check(rows == 2, "2 lignes dans le flux flottant (" .. rows .. ")")
M.fireEvent("LOOT_CLOSED")
lootCalls = {}
M.fireEvent("LOOT_READY", false)
check(#lootCalls == 0, "rien ramassé quand autoloot = false (Maj tenu)")
M.fireEvent("LOOT_BIND_CONFIRM", 3)
M.advance(0.1)
check(confirmCalls[1] == 3, "ConfirmLootSlot(3) appelé")
check(popupHidden[1] == "LOOT_BIND", "popup LOOT_BIND fermée")
ns.Float:Test()
M.advance(5)   -- tout doit s'estomper sans erreur

M.realPrint("== dialogue ==")
gossip:Show()
M.fireEvent("GOSSIP_SHOW")
M.advance(0.1)
check(M.overrides["F"] == "CLICK PlatyplusAdvance:LeftButton", "F liée au bouton de dialogue (" .. tostring(M.overrides["F"]) .. ")")
PlatyplusAdvance:GetScript("OnClick")(PlatyplusAdvance, "LeftButton", true)
check(gossipCalls[1] == "available:777", "F accepte la quête dispo (" .. tostring(gossipCalls[1]) .. ")")
gossip:Hide()
M.fireEvent("GOSSIP_CLOSED", false)
M.advance(0.1)
check(M.overrides["F"] == "INTERACTMOUSEOVER", "F redevient interaction après fermeture")

M.realPrint("== réglages et commandes ==")
SlashCmdList.PLATYPLUS("key G")
check(M.overrides["G"] == "INTERACTMOUSEOVER" and M.overrides["F"] == nil, "/sf key G déplace la liaison")
SlashCmdList.PLATYPLUS("key F")
SlashCmdList.PLATYPLUS("loot off")
check(ns.db.instantLoot == false, "/sf loot off")
SlashCmdList.PLATYPLUS("interact off")
check(M.overrides["F"] == nil, "interaction coupée = plus de liaison")
SlashCmdList.PLATYPLUS("interact on")
check(M.overrides["F"] == "INTERACTMOUSEOVER", "interaction rétablie")
ns:Set("floatScale", 1.5)
SlashCmdList.PLATYPLUS("move"); SlashCmdList.PLATYPLUS("move")
SlashCmdList.PLATYPLUS("rows 3"); SlashCmdList.PLATYPLUS("time 2")
SlashCmdList.PLATYPLUS("cvars")
SlashCmdList.PLATYPLUS("cvar SoftTargetInteractRange 15")
SlashCmdList.PLATYPLUS("help")

-- /pp demo : tout s'affiche d'un coup pour une capture
SlashCmdList.PLATYPLUS("demo")
local cfg = rawget(_G, "PlatyplusConfigFrame")
check(cfg ~= nil and cfg:IsShown(), "/pp demo ouvre les options")
check(M.printed[#M.printed]:find("démo", 1, true) ~= nil, "/pp demo l'annonce dans le chat")
if cfg then cfg:Hide() end

-- /pp perf : sans API de mesure, le dit au lieu de planter
SlashCmdList.PLATYPLUS("perf")
check(M.printed[#M.printed]:find("indisponible", 1, true) ~= nil, "/pp perf sans API : « indisponible »")
-- avec les API du jeu (simulées) : chiffres réels
local asked
local savedEnum = rawget(_G, "Enum")
rawset(_G, "UpdateAddOnMemoryUsage", function() end)
rawset(_G, "GetAddOnMemoryUsage", function(name) asked = name; return 412.6 end)
rawset(_G, "Enum", { AddOnProfilerMetric = { RecentAverageTime = 1 } })
rawset(_G, "C_AddOnProfiler", { GetAddOnMetric = function(name, metric) return 0.0123 end })
SlashCmdList.PLATYPLUS("perf")
local line = M.printed[#M.printed]
check(asked == "Platyplus", "/pp perf demande la mémoire de Platyplus")
check(line:find("413 Ko", 1, true) ~= nil and line:find("0.012 ms", 1, true) ~= nil, "/pp perf affiche mémoire et temps : " .. line)
-- une API qui plante ne casse pas la commande
rawset(_G, "GetAddOnMemoryUsage", function() error("boom") end)
SlashCmdList.PLATYPLUS("perf")
check(M.printed[#M.printed]:find("mémoire indisponible", 1, true) ~= nil, "/pp perf survit à une API en erreur")
rawset(_G, "UpdateAddOnMemoryUsage", nil); rawset(_G, "GetAddOnMemoryUsage", nil)
rawset(_G, "Enum", savedEnum); rawset(_G, "C_AddOnProfiler", nil)

ns:ResetAll(true)
check(ns.db.key == "F" and ns.db.instantLoot == true, "ResetAll remet les défauts")

M.realPrint("== bilan ==")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
