-- Test : la touche d'interaction utilise l'objet de quête au bon endroit (Interact.lua, questItemKey), en mode strict.
-- Le journal simulé suit le code de Forever (Blizzard_ObjectiveTracker, QuestUtils.lua) :
-- C_QuestLog.GetNumQuestLogEntries / GetInfo / IsComplete, GetQuestLogSpecialItemInfo(index) -> lien, icône, charges,
-- montrer-une-fois-finie ; IsQuestLogSpecialItemInRange(index) -> 1 à portée, 0 trop loin, nil sans zone.
-- Usage : python -I dev\lua.py run dev\test_questitem.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

-- journal : entrées (en-têtes compris) ; range[index] = 1 / 0 / nil
local log = {
    { header = true, title = "Forêt d'Elwynn" },
    { questID = 100, title = "Loups affamés" },                                   -- pas d'objet
    { questID = 200, title = "Brûler les tentes", item = 5001, done = false },
    { questID = 300, title = "Fiole de purification", item = 5002, done = true, showDone = false },
}
local range = {}
local function link(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[Objet " .. id .. "]|h|r" end
def("C_QuestLog", {
    GetNumQuestLogEntries = function() return #log, #log end,
    GetInfo = function(i)
        local q = log[i]; if not q then return nil end
        return { title = q.title, questLogIndex = i, questID = q.questID, isHeader = q.header or false, isHidden = false }
    end,
    IsComplete = function(id) for _, q in ipairs(log) do if q.questID == id then return q.done or false end end return false end,
})
def("GetQuestLogSpecialItemInfo", function(i)
    local q = log[i]
    if q and q.item then return link(q.item), "Interface\\Icons\\INV_Torch_Lit", 1, q.showDone or false end
end)
def("IsQuestLogSpecialItemInRange", function(i) return range[i] end)

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Interact.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.3)
local I = ns.Interact
local button = rawget(_G, "PlatyplusQuestItem")
local function tickers()
    local n = 0
    for _, t in ipairs(M.timers) do if t.repeating and not t.cancelled then n = n + 1 end end
    return n
end
local function hintShown()
    local h = rawget(_G, "PlatyplusQuestHint")
    return h ~= nil and S(h).shown, h
end

section("au repos")
check(ns.db.questItemKey == true, "activé par défaut")
check(ns.db.questItemHint == false, "bandeau éteint par défaut")
ns.db.questItemHint = true   -- (la suite vérifie aussi le bandeau)
check(button and S(button).template == "SecureActionButtonTemplate" and button:GetAttribute("type") == "item"
    and button:GetAttribute("useOnKeyDown") == true, "bouton sécurisé PlatyplusQuestItem (type item, à l'appui)")
local list = I:QuestItems()
check(#list == 1 and list[1].itemID == 5001 and list[1].index == 3, "seule la quête en cours avec objet est retenue (finie sans objet : non)")
check(M.overrides["F"] == "INTERACTMOUSEOVER" and not hintShown(), "loin de la zone : F interagit, pas de repère")
check(tickers() == 1, "un seul contrôle de portée tourne (quête avec objet)")

section("au bon endroit")
range[3] = 1
M.advance(0.3)
check(M.overrides["F"] == "CLICK PlatyplusQuestItem:LeftButton", "à portée : F utilise l'objet de quête")
check(M.overrides["SHIFT-F"] == "INTERACTMOUSEOVER", "Maj+F interagit quand même")
check(button:GetAttribute("item") == "item:5001", "le bouton vise item:5001")
local shown, hint = hintShown()
check(shown and tostring(S(hint.text).text):find("Objet 5001", 1, true) and tostring(S(hint.text).text):find("Maj+F", 1, true),
    "repère à l'écran : « F : [Objet 5001]  Maj+F : interagir »")
check(select(1, I:CurrentAction()) == "CLICK PlatyplusQuestItem:LeftButton", "« Action actuelle » le reflète")
range[3] = 0
M.advance(0.3)
check(M.overrides["F"] == "INTERACTMOUSEOVER" and M.overrides["SHIFT-F"] == nil and not hintShown(),
    "trop loin : F redevient l'interaction, Maj+F libéré, repère caché")
range[3] = nil
M.advance(0.3)
check(M.overrides["F"] == "INTERACTMOUSEOVER", "objet sans zone (portée inconnue) : F reste l'interaction")

section("combat")
-- PLAYER_REGEN_DISABLED arrive juste avant le verrou : F passe à INTERACTTARGET (jamais le mob vivant sous la souris)
M.fireEvent("PLAYER_REGEN_DISABLED")
M.inCombat = true
check(M.overrides["F"] == "INTERACTTARGET" and M.overrides["SHIFT-F"] == nil, "début du combat : F = cible d'interaction seule (corps à looter)")
range[3] = 1
M.advance(0.5)
check(M.overrides["F"] == "INTERACTTARGET" and #M.errors == 0, "en combat : rien ne change (liaisons verrouillées), sans erreur")
M.inCombat = false
M.fireEvent("PLAYER_REGEN_ENABLED")
check(M.overrides["F"] == "CLICK PlatyplusQuestItem:LeftButton", "après le combat : F passe à l'objet")
M.fireEvent("PLAYER_REGEN_DISABLED")
M.inCombat = true
check(M.overrides["F"] == "INTERACTTARGET" and M.overrides["SHIFT-F"] == "CLICK PlatyplusQuestItem:LeftButton",
    "combat commencé à portée : F = looter, Maj+F = l'objet de quête")
range[3] = 0
M.advance(0.5)
M.inCombat = false
M.fireEvent("PLAYER_REGEN_ENABLED")
check(M.overrides["F"] == "INTERACTMOUSEOVER", "fin du combat, hors de portée : F redevient l'interaction")

section("dialogue de PNJ prioritaire")
range[3] = 1
M.advance(0.3)
I:SetDialogMode(true)
check(M.overrides["F"] == "CLICK PlatyplusAdvance:LeftButton" and not hintShown(), "dialogue ouvert : F fait avancer le dialogue")
I:SetDialogMode(false)
M.advance(0.3)
check(M.overrides["F"] == "CLICK PlatyplusQuestItem:LeftButton", "dialogue fermé, toujours à portée : F revient à l'objet")

section("plusieurs quêtes, journal qui change")
log[5] = { questID = 400, title = "Signal de fumée", item = 5003, done = false }
M.fireEvent("QUEST_LOG_UPDATE")
M.advance(0.3)
range[3], range[5] = 0, 1
M.advance(0.3)
check(button:GetAttribute("item") == "item:5003" and M.overrides["F"] == "CLICK PlatyplusQuestItem:LeftButton",
    "la quête à portée est choisie (item:5003)")
log[3].done, log[5] = true, nil
M.fireEvent("QUEST_LOG_UPDATE")
M.advance(0.5)
check(#I:QuestItems() == 0 and M.overrides["F"] == "INTERACTMOUSEOVER" and tickers() == 0,
    "plus de quête avec objet : F interagit, plus aucun contrôle de portée")
log[3].done = false
M.fireEvent("QUEST_LOG_UPDATE")
M.advance(0.5)

section("réglages")
range[3] = 1
M.advance(0.3)
ns:Set("questItemKey", false)
check(M.overrides["F"] == "INTERACTMOUSEOVER" and tickers() == 0 and not hintShown(), "option coupée : F interagit, contrôle arrêté")
ns:Set("questItemKey", true)
M.advance(0.3)
check(M.overrides["F"] == "CLICK PlatyplusQuestItem:LeftButton", "option remise : de retour")
ns:Set("key", "SHIFT-G")
M.advance(0.3)
check(M.overrides["SHIFT-G"] == "CLICK PlatyplusQuestItem:LeftButton" and M.overrides["SHIFT-SHIFT-G"] == nil,
    "touche avec modificateur : pas de « Maj+ » en plus")
ns:Set("key", "F")
ns:Set("interact", false)
check(M.overrides["F"] == nil and tickers() == 0, "interaction coupée : plus aucune liaison ni contrôle")
ns:Set("interact", true)
M.advance(0.3)
check(M.overrides["F"] == "CLICK PlatyplusQuestItem:LeftButton", "interaction rallumée")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
