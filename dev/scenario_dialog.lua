-- Scénario : touche de dialogue et mode « quêtes automatiques » (autoQuest)
local ADDON_DIR, SCRATCH = ARGS[1], ARGS[2]
local M = dofile(SCRATCH .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

-- PNJ simulé : une quête disponible et une option de dialogue
local calls = {}
local available = { { questID = 777, title = "Une quête", isIgnored = false } }
def("C_GossipInfo", {
    GetActiveQuests = function() return {} end,
    GetAvailableQuests = function() return available end,
    GetOptions = function() return { { orderIndex = 1, status = 0, gossipOptionID = 9, name = "Formation" } } end,
    SelectActiveQuest = function(id) calls[#calls + 1] = "active:" .. id end,
    SelectAvailableQuest = function(id) calls[#calls + 1] = "available:" .. id end,
    SelectOptionByIndex = function(i) calls[#calls + 1] = "option:" .. i end,
})
local function frame(name) local f = CreateFrame("Frame", name, UIParent); f:Hide(); return f end
local gossip, quest = frame("GossipFrame"), frame("QuestFrame")
local detail, progress, reward = frame("QuestFrameDetailPanel"), frame("QuestFrameProgressPanel"), frame("QuestFrameRewardPanel")
local function button(name, label)
    local b = CreateFrame("Button", name, UIParent)
    b:SetScript("OnClick", function() calls[#calls + 1] = label end)
    return b
end
local accept = button("QuestFrameAcceptButton", "accept")
local progressBtn = button("QuestFrameCompleteButton", "progress")
local complete = button("QuestFrameCompleteQuestButton", "complete")
def("GetNumQuestChoices", function() return 3 end)
def("GetQuestItemInfo", function() return "Objet", 1, 1, 2, true end)
def("GetQuestItemLink", function() return nil end)
local questInfo = { itemChoice = 0 }
def("QuestInfoFrame", questInfo)

local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Interact.lua", "Dialog.lua", "Quests.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.2)

local function reset() calls = {} end
local function hideAll() gossip:Hide(); quest:Hide(); detail:Hide(); progress:Hide(); reward:Hide() end

section("mode manuel (par défaut)")
gossip:Show(); M.fireEvent("GOSSIP_SHOW"); M.advance(0.3)
check(#calls == 0, "rien ne se passe sans appui sur la touche")
check(M.overrides["F"] == "CLICK PlatyplusAdvance:LeftButton", "la touche est liée au dialogue")
PlatyplusAdvance:GetScript("OnClick")(PlatyplusAdvance, "LeftButton", true)
check(calls[1] == "available:777", "la touche accepte la quête (" .. tostring(calls[1]) .. ")")
hideAll(); M.fireEvent("GOSSIP_CLOSED", false); M.advance(0.2); reset()

section("mode automatique")
ns:Set("autoQuest", true)
gossip:Show(); M.fireEvent("GOSSIP_SHOW"); M.advance(0.3)
check(calls[1] == "available:777", "quête choisie toute seule (" .. tostring(calls[1]) .. ")")
reset(); available = {}
M.fireEvent("GOSSIP_SHOW"); M.advance(0.3)
check(#calls == 0, "pas d'option de dialogue choisie automatiquement (formation, marchand...)")
hideAll(); available = { { questID = 777, title = "Une quête", isIgnored = false } }; reset()

quest:Show(); detail:Show(); M.fireEvent("QUEST_DETAIL"); M.advance(0.3)
check(calls[1] == "accept", "quête acceptée toute seule")
hideAll(); reset()

quest:Show(); progress:Show(); progressBtn:Disable()
local printed = #M.printed
M.fireEvent("QUEST_PROGRESS"); M.advance(0.3)
check(#calls == 0 and #M.printed == printed, "quête pas finie : ni clic ni message répété")
progressBtn:Enable(); hideAll(); reset()

quest:Show(); reward:Show(); M.fireEvent("QUEST_COMPLETE"); M.advance(0.3)
check(#calls == 0, "plusieurs récompenses : Platyplus ne choisit pas, on attend le joueur")
questInfo.itemChoice = 2; M.fireEvent("QUEST_COMPLETE"); M.advance(0.3)
check(calls[1] == "complete", "récompense choisie par le joueur : quête rendue")
hideAll(); reset(); questInfo.itemChoice = 0

M.shift = true
gossip:Show(); M.fireEvent("GOSSIP_SHOW"); M.advance(0.3)
check(#calls == 0, "Maj tenu : pause")
M.shift = false; hideAll(); reset()

ns:Set("autoQuest", false)
gossip:Show(); M.fireEvent("GOSSIP_SHOW"); M.advance(0.3)
check(#calls == 0, "mode coupé : plus rien d'automatique")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
