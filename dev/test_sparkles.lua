-- Test : étincelles sur ce qu'on peut ramasser (Sparkles.lua), en mode strict.
-- Le jeu est simulé : cible d'interaction « softinteract » (objet, PNJ ou cadavre), plaque de nom qui n'existe que si
-- SoftTargetNameplateInteract = 1, icône de curseur, portée d'interaction, butin restant. Valide la logique
-- (réglages du jeu gardés puis remis, plaque ouverte seulement pour ce qui brille, états, combat, valeurs secrètes),
-- pas le rendu réel dans le jeu.
-- Usage : python -I dev\lua.py run dev\test_sparkles.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

-- réglages du jeu tels qu'un joueur les a avant Platyplus
M.cvars.outlineModeShowLootEffectWhenDisabled = "0"
M.cvars.graphicsquality = "5"
M.cvars.raidgraphicsquality = "5"
M.cvars.SoftTargetInteract = "1"
M.cvars.SoftTargetInteractRange = "10"
M.cvars.SoftTargetInteractArc = "1"
M.cvars.SoftTargetInteractOnlyInRange = "1"
M.cvars.SoftTargetIconGameObject = "0"
M.cvars.SoftTargetNameplateInteract = "0"

-- cible d'interaction simulée
-- kind : "object" | "npc" | "corpse" ; cursor : chemin du curseur ; inRange ; related : objectif de quête
local target
local secretExists = false
local plate   -- la plaque de nom du jeu, créée après le chargement
def("issecretvalue", function(v) return type(v) == "table" and v.secret == true end)
def("UnitExists", function(unit)
    if secretExists then return { secret = true } end
    if unit == "softinteract" then return target ~= nil and target.kind ~= "object" end
    return false
end)
def("UnitIsGameObject", function(unit)
    if secretExists then return { secret = true } end
    return target ~= nil and target.kind == "object"
end)
def("UnitName", function() return target and target.name end)
def("UnitGUID", function() return target and ("Creature-0-" .. target.name) end)
def("UnitIsDead", function() return target ~= nil and target.kind == "corpse" end)
def("UnitIsUnit", function() return false end)
def("CanLootUnit", function() return target and target.loot == true, true end)
def("UnitIsInInteractRange", function() return target and target.inRange end)
def("SetUnitCursorTexture", function(tex)
    if not (target and target.cursor) then return false end
    tex:SetTexture(target.cursor)
    return true
end)
def("C_QuestLog", {
    UnitIsRelatedToActiveQuest = function() return target ~= nil and target.related == true end,
})
def("C_NamePlate", {
    -- comme dans le jeu : la cible d'interaction n'a une plaque que si SoftTargetNameplateInteract vaut 1
    GetNamePlateForUnit = function(unit)
        if unit == "softinteract" and target and M.cvars.SoftTargetNameplateInteract == "1" then return plate end
    end,
})

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Interact.lua", "Sparkles.lua" })
plate = CreateFrame("Frame", nil, UIParent)
M.fireEvent("ADDON_LOADED", "Platyplus")
local SP = ns.Sparkles
local function gate() return M.cvars.SoftTargetNameplateInteract end
local function sparkleState()
    local anchor, state, frame = SP:Current()
    return anchor, state, frame
end
local function shown()
    local anchor, _, frame = SP:Current()
    return anchor ~= nil and frame ~= nil and S(frame).shown
end

-- les catégories d'objets : tous les gestes d'un joueur qui s'approche
local function herb(extra)
    local t = { kind = "object", name = "Pacifique", cursor = "Interface\\Cursor\\GatherHerbs", inRange = false }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

section("connexion : étincelle de butin du jeu")
check(ns.db.sparkleLoot == true and ns.db.sparkleOre == nil and ns.db.sparkleHerbs == true
    and ns.db.sparkleCorpses == true and ns.db.sparkleQuestObjects == false, "valeurs par défaut (objets de quête coupés)")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.3)
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "1", "l'étincelle de butin du jeu est allumée à la connexion")
M.cvars.outlineModeShowLootEffectWhenDisabled = "0"      -- un préréglage graphique la coupe
M.cvars.graphicsquality = "3"
M.fireEvent("CVAR_UPDATE", "graphicsquality", "3")
M.advance(0.5)
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "0", "pas tout de suite : on attend la fin des changements")
M.advance(0.7)
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "1", "1 s après un changement graphique : remise")
M.cvars.outlineModeShowLootEffectWhenDisabled = "0"
M.fireEvent("CVAR_UPDATE", "OutlineModeShowLootEffectWhenDisabled", "0")
M.advance(1.2)
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "1", "le CVar lui-même coupé : remis aussi (nom en majuscules accepté)")
M.fireEvent("CVAR_UPDATE", "cameraDistanceMaxZoomFactor", "2")
local before = M.cvars.outlineModeShowLootEffectWhenDisabled
M.advance(1.2)
check(before == M.cvars.outlineModeShowLootEffectWhenDisabled and #M.errors == 0, "un autre CVar ne déclenche rien")

section("étincelle de butin : combat et réglage")
M.cvars.outlineModeShowLootEffectWhenDisabled = "0"
M.inCombat = true
M.fireEvent("CVAR_UPDATE", "graphicsquality", "4")
M.advance(1.2)
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "0", "en combat : rien n'est écrit")
M.inCombat = false
M.fireEvent("PLAYER_REGEN_ENABLED")
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "1", "fin du combat : remise")
M.printed = {}
ns:Set("sparkleLoot", false)
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "0", "option coupée : CVar à 0")
local said = false
for _, line in ipairs(M.printed) do if line:find("redémarre", 1, true) then said = true end end
check(said, "message : redémarrer le jeu (/reload ne suffit pas)")
M.cvars.graphicsquality = "2"
M.fireEvent("CVAR_UPDATE", "graphicsquality", "2")
M.advance(1.2)
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "0", "option coupée : un changement graphique ne la rallume pas")
ns:Set("sparkleLoot", true)
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "1", "option rallumée : tout de suite")

section("réglages du jeu pour les étincelles à l'approche")
check(M.cvars.SoftTargetInteract == "3", "touche d'interaction : 3 (Platyplus et étincelles)")
check(M.cvars.SoftTargetInteractRange == "60" and M.cvars.SoftTargetInteractArc == "2"
    and M.cvars.SoftTargetInteractOnlyInRange == "0" and M.cvars.SoftTargetIconGameObject == "1",
    "portée 60, arc 2, aussi hors de portée, plaques d'objets allumées")
local saved = ns.db.sparkleCVars
check(type(saved) == "table" and saved.SoftTargetInteractRange == "10" and saved.SoftTargetInteractArc == "1"
    and saved.SoftTargetInteractOnlyInRange == "1" and saved.SoftTargetIconGameObject == "0",
    "valeurs d'origine gardées (10, 1, 1, 0)")
check(gate() == "0", "aucune cible : plaque de la cible du jeu fermée")

section("plante : à l'approche")
target = herb()
M.advance(0.3)
check(gate() == "1", "une plante à approcher : le jeu pose sa plaque")
check(shown(), "l'étincelle est accrochée à la plaque")
local anchor, state, frame = sparkleState()
local pt = S(frame).points[#S(frame).points]
check(anchor == plate and pt and pt[1] == "CENTER" and pt[2] == plate and pt[5] == -45, "accrochée à la plaque de la cible, 45 px plus bas")
check(state == "far", "hors de portée : terne (far)")
M.advance(1.0)
local lit = false
for _, g in ipairs(S(frame).regions) do if S(g).vertex and S(g).vertex[4] > 0.05 then lit = true end end
check(lit, "au moins un éclat est visible")
check(#S(frame).regions == 7 and S(S(frame).regions[1]).texture:find("Flare", 1, true), "7 éclats avec Media\\Flare")
check(S(S(frame).regions[1]).blend == "ADD", "éclats en fondu additif")
target.inRange = true
M.advance(0.1)
check(select(2, sparkleState()) == "far", "à portée depuis un instant : pas encore (pas de scintillement)")
M.advance(0.4)
check(select(2, sparkleState()) == "ready", "à portée : vif (ready)")
target.cursor = "Interface\\Cursor\\UnableGatherHerbs"
M.advance(0.4)
check(select(2, sparkleState()) == "ready", "curseur grisé depuis un instant : pas encore")
M.advance(0.8)
check(select(2, sparkleState()) == "locked", "à portée mais impossible (compétence trop basse) : gris (locked)")
target.inRange = false
M.advance(0.4)
check(select(2, sparkleState()) == "far", "on s'éloigne d'un objet grisé : terne")
target = nil
M.advance(0.3)
check(not shown() and gate() == "0", "plus de cible : l'étincelle disparaît, la plaque se ferme")

section("plantes, PNJ, autres objets")
target = { kind = "object", name = "Pacifique", cursor = "Interface\\Cursor\\GatherHerbs", inRange = true }
M.advance(0.3)
check(shown() and gate() == "1" and select(2, sparkleState()) == "ready", "une plante brille")
ns:Set("sparkleHerbs", false)
M.advance(0.3)
check(not shown() and gate() == "0", "plantes coupées : pas d'étincelle ni de plaque")
ns:Set("sparkleHerbs", true)
M.advance(0.3)
check(shown(), "plantes rallumées")
target = { kind = "npc", name = "Garde de Hurlevent", inRange = true }
M.advance(0.3)
check(not shown() and gate() == "0", "un PNJ : rien (la touche marche sans plaque)")
target = { kind = "object", name = "Coffre", cursor = "Interface\\Cursor\\PickLock", inRange = true }
M.advance(0.3)
check(not shown() and gate() == "0", "un coffre : rien")
target = { kind = "object", name = "Boîte aux lettres", cursor = "Interface\\Cursor\\Interact", inRange = true }
M.advance(0.3)
check(not shown() and gate() == "0", "une boîte aux lettres : rien")

section("objets de quête du monde")
target = { kind = "object", name = "Caisse de provisions", cursor = "Interface\\Cursor\\Interact", inRange = true, related = true }
M.advance(0.3)
check(not shown(), "coupé par défaut : pas d'étincelle (le jeu marque déjà la plupart)")
ns:Set("sparkleQuestObjects", true)
M.advance(0.3)
check(shown() and gate() == "1", "allumé : l'objet de quête brille")
target = { kind = "object", name = "Caisse de provisions", cursor = "Interface\\Cursor\\Quest", inRange = true }
M.advance(0.3)
check(shown(), "curseur de quête : brille aussi")
target = { kind = "object", name = "Caisse de provisions", cursor = "Interface\\Cursor\\Interact", inRange = true, related = false }
M.advance(0.3)
check(not shown(), "objet sans lien avec une quête : rien")
-- par le texte de l'objectif quand le jeu ne dit pas « lié à une quête »
def("C_QuestLog", {
    GetNumQuestLogEntries = function() return 1, 1 end,
    GetQuestIDForLogIndex = function() return 77 end,
    GetQuestObjectives = function() return { { text = "Provisions volées : 0/3", finished = false } } end,
})
M.fireEvent("QUEST_LOG_UPDATE")
target = { kind = "object", name = "Provisions volées", cursor = "Interface\\Cursor\\Interact", inRange = true }
M.advance(0.3)
check(shown(), "reconnu par le texte d'un objectif pas fini (« Provisions volées : 0/3 »)")
def("C_QuestLog", {
    GetNumQuestLogEntries = function() return 1, 1 end,
    GetQuestIDForLogIndex = function() return 77 end,
    GetQuestObjectives = function() return { { text = "Provisions volées : 3/3", finished = true } } end,
})
M.fireEvent("QUEST_LOG_UPDATE")
M.advance(0.3)
check(not shown(), "objectif fini : plus d'étincelle")
ns:Set("sparkleQuestObjects", false)

section("cadavres avec du butin")
target = { kind = "corpse", name = "Roi des Défias", loot = true, inRange = false }
M.advance(0.3)
check(shown() and gate() == "1", "un cadavre qui a du butin brille")
target.loot = false
M.advance(0.3)
check(not shown() and gate() == "0", "plus de butin : plus d'étincelle")
target.loot = true
ns:Set("sparkleCorpses", false)
M.advance(0.3)
check(not shown(), "option coupée : rien")
ns:Set("sparkleCorpses", true)
M.advance(0.3)
check(shown(), "option rallumée")

section("changement de cible : la plaque est recyclée")
target = herb({ inRange = true })
M.fireEvent("PLAYER_SOFT_INTERACT_CHANGED", "Creature-A", "GameObject-B")
M.advance(0.3)
check(shown() and select(2, sparkleState()) == "ready", "nouvelle cible : l'étincelle repart à neuf, vive")

section("combat")
M.inCombat = true
M.fireEvent("PLAYER_REGEN_DISABLED")
M.advance(0.3)
check(not shown(), "en combat : pas d'étincelle")
ns:Set("sparkleQuestObjects", false)
check(#M.errors == 0, "un réglage change en combat : sans erreur")
M.inCombat = false
M.fireEvent("PLAYER_REGEN_ENABLED")
M.advance(0.3)
check(shown(), "après le combat : l'étincelle revient")

section("valeurs secrètes (le client ne dit rien)")
secretExists = true
M.advance(0.3)
check(not shown() and gate() == "1" and #M.errors == 0, "cible illisible : pas d'étincelle, plaque ouverte (le jeu montre sa cible), sans erreur")
secretExists = false
target = nil
M.advance(0.3)
check(gate() == "0", "cible lisible de nouveau : plaque refermée")
target = herb({ inRange = true })
M.advance(0.3)

section("diagnostic /pp etincelles")
local lines = SP:Status()
local text = table.concat(lines, "\n")
check(#lines >= 4 and text:find("Pacifique", 1, true) and text:find("plante", 1, true), "montre la cible lue : nom et catégorie")
check(text:find("outlineModeShowLootEffectWhenDisabled = 1", 1, true), "montre le CVar de l'étincelle de butin")
M.printed = {}
SlashCmdList.PLATYPLUS("etincelles")
check(#M.printed >= 5, "la commande affiche l'état")
SlashCmdList.PLATYPLUS("etincelles off")
check(ns.db.sparkleLoot == false and ns.db.sparkleHerbs == false and ns.db.sparkleCorpses == false,
    "/pp etincelles off : tout est coupé")

section("tout coupé : les réglages du jeu sont remis")
M.advance(0.3)
check(M.cvars.SoftTargetInteractRange == "10" and M.cvars.SoftTargetInteractArc == "1"
    and M.cvars.SoftTargetInteractOnlyInRange == "1" and M.cvars.SoftTargetIconGameObject == "0"
    and M.cvars.SoftTargetNameplateInteract == "0", "portée, arc, hors de portée, plaques d'objets remis comme avant")
check(M.cvars.SoftTargetInteract == "3", "la touche d'interaction reste à 3 : l'interaction rapide de Platyplus en a besoin")
check(ns.db.sparkleCVars == nil and not shown(), "valeurs gardées effacées, plus d'étincelle")
check(M.cvars.outlineModeShowLootEffectWhenDisabled == "0", "étincelle de butin coupée")

section("tout remettre par défaut ne perd pas les valeurs d'origine")
SlashCmdList.PLATYPLUS("etincelles on")
M.advance(0.3)
check(M.cvars.SoftTargetInteractRange == "60" and ns.db.sparkleCVars and ns.db.sparkleCVars.SoftTargetInteractRange == "10",
    "/pp etincelles on : réglages posés, valeurs d'origine regardées")
ns:ResetAll(false)
M.advance(0.3)
check(ns.db.sparkleCVars and ns.db.sparkleCVars.SoftTargetInteractRange == "10", "ResetAll : les valeurs d'origine sont gardées")
SlashCmdList.PLATYPLUS("etincelles off")
M.advance(0.3)
check(M.cvars.SoftTargetInteractRange == "10", "puis tout coupé : la portée d'origine revient (10, pas 60)")

section("interaction rapide coupée : la touche d'interaction d'origine revient")
M.cvars.SoftTargetInteract = "1"
ns:Set("interact", false)
SlashCmdList.PLATYPLUS("etincelles on")
M.advance(0.3)
check(M.cvars.SoftTargetInteract == "3", "étincelles allumées : touche d'interaction à 3")
SlashCmdList.PLATYPLUS("etincelles off")
M.advance(0.3)
check(M.cvars.SoftTargetInteract == "1", "interaction rapide coupée : la valeur d'origine (1) revient")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
