-- Test : plates des mobs (Plates.lua) dans le simulateur strict
-- Fausses plates de nom (barre de vie StatusBar), menace pilotée par le test, infobulle de quête, valeurs secrètes.
-- Vérifie : rôle auto/forcé, couleurs tank et DPS, autre tank, alerte « il t'échappe », menace secrète, icône de quête,
-- « Rare », retrait des plates, interrupteur, commande /pp plates.
-- Usage : python -I dev\lua.py run dev\test_plates.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local impl, S = M.impl, M.state

---------------------------------------------------------------------------
-- Valeurs secrètes
---------------------------------------------------------------------------
local SecretMT = {}
local function secret(v) return setmetatable({ v = v }, SecretMT) end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__lt", "__le", "__len", "__call", "__concat", "__eq" }) do
    SecretMT[op] = function() error("opération interdite sur une valeur secrète (" .. op .. ")", 2) end
end
SecretMT.__index = function() error("lecture interdite dans une valeur secrète", 2) end
def("issecretvalue", function(x) return getmetatable(x) == SecretMT end)

---------------------------------------------------------------------------
-- Monde simulé
---------------------------------------------------------------------------
local sim = {
    forms = {},              -- { { active = bool, spellID = n } }
    roles = {},              -- [unité] = "TANK"...
    party = 0,
    mobs = {},               -- [jeton] = { canAttack, tapped, combat, class, threat = { tanking, status } , lines }
    partyThreat = {},        -- [membre .. "|" .. jeton] = statut
    plates = {},             -- [jeton] = plate
    quests = {},             -- journal : { { questID, objectives = {...} } }
    sounds = 0,
}

-- la plate du jeu : UnitFrame.healthBar est une vraie StatusBar (de notre point de vue : un cadre à part)
M.cvars.nameplateStyle, M.cvars.nameplateSize = "1", "2"   -- défauts de Forever : fine, normale
local function makePlate(token)
    local bar = CreateFrame("StatusBar")
    bar.bgTexture = bar:CreateTexture(nil, "BACKGROUND")       -- cadre du jeu (atlas avec ombre)
    local plate = { namePlateUnitToken = token, UnitFrame = { unit = token, healthBar = bar } }
    sim.plates[token] = plate
    sim.mobs[token] = sim.mobs[token] or {
        canAttack = true, tapped = false, combat = true, class = "normal", threat = { false, nil }, lines = {},
        reaction = 2, player = false,
    }
    return plate, bar
end

def("C_NamePlate", {
    GetNamePlateForUnit = function(unit)
        if unit == "target" then return sim.target and sim.plates[sim.target] or nil end
        return sim.plates[unit]
    end,
    GetNamePlates = function()
        local list = {}
        for _, p in pairs(sim.plates) do list[#list + 1] = p end
        return list
    end,
})
def("UnitName", function(unit) if unit == "player" then return "Heros" end return nil end)
def("UnitIsUnit", function(a, b) return a == b end)
def("IsInRaid", function() return false end)
def("GetNumSubgroupMembers", function() return sim.party end)
def("GetNumGroupMembers", function() return sim.party + 1 end)
def("UnitGroupRolesAssigned", function(unit) return sim.roles[unit] or "NONE" end)
def("UnitHasEffectivelyTankAura", function() return false end)
def("GetNumShapeshiftForms", function() return #sim.forms end)
def("GetShapeshiftFormInfo", function(i)
    local f = sim.forms[i]
    return 1, f.active, true, f.spellID
end)
def("UnitCanAttack", function(_, u) return sim.mobs[u] and sim.mobs[u].canAttack or false end)
def("UnitIsTapDenied", function(u) return sim.mobs[u] and sim.mobs[u].tapped or false end)
def("UnitAffectingCombat", function(u) return sim.mobs[u] and sim.mobs[u].combat or false end)
def("UnitReaction", function(u) return sim.mobs[u] and sim.mobs[u].reaction or nil end)
def("UnitIsPlayer", function(u) return sim.mobs[u] and sim.mobs[u].player or false end)
def("UnitClassification", function(u) return sim.mobs[u] and sim.mobs[u].class or "normal" end)
def("UnitDetailedThreatSituation", function(_, u)
    local m = sim.mobs[u]
    if not m then return nil end
    return m.threat[1], m.threat[2], 0, 0, 0
end)
def("UnitThreatSituation", function(member, u) return sim.partyThreat[member .. "|" .. u] end)
def("CreateColor", function(r, g, b, a) return { r = r, g = g, b = b, a = a } end)
def("SOUNDKIT", { RAID_WARNING = 8959 })
def("PlaySound", function() sim.sounds = sim.sounds + 1 end)
def("C_TooltipInfo", {
    GetUnit = function(u)
        local m = sim.mobs[u]
        if not m or not m.lines then return nil end
        return { lines = m.lines }
    end,
})
def("C_QuestLog", {
    GetNumQuestLogEntries = function() return #sim.quests end,
    GetInfo = function(i) return { questID = sim.quests[i].questID, isHeader = false } end,
    GetQuestObjectives = function(id)
        for _, q in ipairs(sim.quests) do if q.questID == id then return q.objectives end end
        return {}
    end,
})

-- SetVertexColorFromBoolean : mémorise l'appel (la valeur n'est jamais lue, comme dans le jeu)
impl.SetVertexColorFromBoolean = function(tex, value, ifTrue, ifFalse)
    S(tex).fromBool = { value = value, ifTrue = ifTrue, ifFalse = ifFalse }
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Resources.lua", "Plates.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(1)
local P = ns.Plates
-- les réglages plates* sont appliqués une image plus tard (regroupés) : on avance d'une image après chaque écriture
do
    local realSet, realReset = ns.Set, ns.Reset
    ns.Set = function(self, ...) realSet(self, ...) M.advance(0.05) end
    ns.Reset = function(self, ...) realReset(self, ...) M.advance(0.05) end
end

local COLORS = P.COLOR_DEFAULTS
local function near(c, ref) return c and math.abs(c[1] - ref[1]) < 0.01 and math.abs(c[2] - ref[2]) < 0.01 and math.abs(c[3] - ref[3]) < 0.01 end

-- éléments de Platyplus sur une barre : régions de la barre = ..., tint, border, back ; enfants : root (quest,
-- questText, tag) puis glowFrame (glow)
local function parts(bar)
    local root, glowFrame = S(bar).frames[1], S(bar).frames[2]
    local r, own = S(root).regions, S(bar).regions
    return { root = root, tint = own[#own - 3], border = own[#own - 2], targetBorder = own[#own - 1], back = own[#own],
        quest = r[1],
        questText = r[2], tag = r[3], glow = S(glowFrame).regions[1] }
end
local function tintShown(el) return S(el.tint).shown == true end
local function tintIs(el, kind) return tintShown(el) and near(S(el.tint).vertex, COLORS[kind]) end

local n = 0
-- ajoute une plate de mob, la configure, puis annonce la plate au module
local function addMob(opts)
    n = n + 1
    local token = "nameplate" .. n
    local plate, bar = makePlate(token)
    local m = sim.mobs[token]
    for k, v in pairs(opts or {}) do m[k] = v end
    M.fireEvent("NAME_PLATE_UNIT_ADDED", token)
    return token, parts(bar), bar
end
local function setThreat(token, tanking, status)
    sim.mobs[token].threat = { tanking, status }
    M.fireEvent("UNIT_THREAT_LIST_UPDATE", token)
end
local function setForm(on)
    sim.forms = on and { { active = true, spellID = 71 } } or {}
    M.fireEvent("UPDATE_SHAPESHIFT_FORM")
    M.advance(0.3)
end

---------------------------------------------------------------------------
section("rôle")
local isTank = P:IsTank()
check(isTank == false, "sans posture défensive : DPS")
setForm(true)
check(P:IsTank() == true, "posture défensive (sort 71 actif) : tank")
setForm(false)
check(P:IsTank() == false, "posture quittée : DPS")
ns:Set("platesRole", "tank")
check(P:IsTank() == true, "réglage « tank » force le tank sans posture")
ns:Set("platesRole", "dps")
setForm(true)
check(P:IsTank() == false, "réglage « dps » force DPS même en posture défensive")
ns:Set("platesRole", "auto")
check(P:IsTank() == true, "retour en auto : posture défensive -> tank")

---------------------------------------------------------------------------
section("tank : couleurs de menace")
local tA, eA = addMob({ threat = { true, 3 } })
check(tintIs(eA, "safe"), "statut 3 : vert")
setThreat(tA, false, 2)
check(tintIs(eA, "warn"), "statut 2 : orange")
setThreat(tA, false, 1)
check(tintIs(eA, "warn"), "statut 1 : orange")
setThreat(tA, false, 0)
check(tintIs(eA, "loose"), "statut 0 : rouge")
setThreat(tA, false, nil)
check(tintIs(eA, "hostile"), "pas sur sa liste de menace (idle reaction) : couleur hostile")
ns:Set("platesIdle", "game")
check(not tintShown(eA), "pas sur sa liste de menace (idle game) : teinte cachée")
local tB, eB = addMob({ threat = { true, 3 }, canAttack = false })
check(not tintShown(eB), "mob non attaquable (idle game) : teinte cachée")
local tC, eC = addMob({ threat = { true, 3 }, tapped = true })
check(not tintShown(eC), "mob tapé par d'autres (idle game) : teinte cachée")
ns:Set("platesIdle", "reaction")
check(tintIs(eA, "hostile"), "retour en idle reaction : hostile")
check(tintIs(eC, "tapped"), "mob tapé (idle reaction) : couleur tapé")

---------------------------------------------------------------------------
section("hors combat : couleur selon la réaction")
local _, eH1 = addMob({ canAttack = true, reaction = 2 })
check(tintIs(eH1, "hostile"), "réaction 2 : hostile")
local _, eH2 = addMob({ canAttack = true, reaction = 4 })
check(tintIs(eH2, "neutral"), "réaction 4 : neutre")
local _, eH3 = addMob({ canAttack = false, reaction = 5 })
check(tintIs(eH3, "friendly"), "réaction 5, non attaquable : amical")
local _, eH4 = addMob({ canAttack = true, tapped = true, reaction = 2 })
check(tintIs(eH4, "tapped"), "tapé : couleur tapé")
local _, eH5 = addMob({ canAttack = true, reaction = 2, player = true })
check(not tintShown(eH5), "joueur : rien (couleurs du jeu)")
ns:Set("platesColHostile", { 0.1, 0.2, 0.3 })
check(near(S(eH1.tint).vertex, { 0.1, 0.2, 0.3 }), "couleur hostile personnalisée prise en compte")
ns:Reset("platesColHostile")
check(tintIs(eH1, "hostile"), "couleur hostile remise par défaut")

---------------------------------------------------------------------------
section("DPS : l'inverse")
ns:Set("platesRole", "dps")
local tD, eD = addMob({ threat = { true, 3 } })
check(P:IsTank() == false, "rôle DPS")
check(tintIs(eD, "loose"), "DPS statut 3 : rouge")
setThreat(tD, false, 0)
check(tintIs(eD, "safe"), "DPS statut 0 : vert")
setThreat(tD, false, 2)
check(tintIs(eD, "loose"), "DPS statut 2 : rouge (il te tape encore)")
ns:Set("platesRole", "tank")

---------------------------------------------------------------------------
section("autre tank du groupe")
sim.party = 1
sim.roles.party1 = "TANK"
M.fireEvent("GROUP_ROSTER_UPDATE")
M.advance(0.3)
local tE, eE = addMob({ threat = { false, 0 } })
sim.partyThreat["party1|" .. tE] = 3
M.fireEvent("UNIT_THREAT_LIST_UPDATE", tE)
check(tintIs(eE, "other"), "l'autre tank le tient, tu es à 0 : bleu")
ns:Set("platesOfftank", false)
check(tintIs(eE, "loose"), "option « autre tank » coupée : rouge")
ns:Set("platesOfftank", true)
check(tintIs(eE, "other"), "option rallumée : bleu")
sim.partyThreat["party1|" .. tE] = 0
M.fireEvent("UNIT_THREAT_LIST_UPDATE", tE)
check(tintIs(eE, "loose"), "l'autre tank ne le tient pas non plus : rouge")

---------------------------------------------------------------------------
section("alerte : le mob échappe au tank")
local tF, eF = addMob({ threat = { true, 3 } })
check(tintIs(eF, "safe") and S(eF.glow).shown ~= true, "tenu : vert, pas d'alerte")
setThreat(tF, false, 0)
check(tintIs(eF, "loose"), "perdu : rouge")
check(S(eF.glow).shown == true, "liseré d'alerte affiché")
check(S(eF.root).scripts.OnUpdate ~= nil, "clignotement en cours (OnUpdate)")
M.advance(0.5)
check(S(eF.glow).shown == true, "toujours affiché à 0,5 s")
M.advance(1.2)
check(S(eF.glow).shown ~= true, "liseré caché après le clignotement")
check(S(eF.root).scripts.OnUpdate == nil, "OnUpdate retiré")

-- pas d'alerte quand c'est l'autre tank qui le prend
local tG, eG = addMob({ threat = { true, 3 } })
sim.partyThreat["party1|" .. tG] = 3
setThreat(tG, false, 0)
check(tintIs(eG, "other") and S(eG.glow).shown ~= true, "l'autre tank le prend : bleu, pas d'alerte")

-- option coupée
ns:Set("platesAlert", false)
local tH, eH = addMob({ threat = { true, 3 } })
setThreat(tH, false, 0)
check(tintIs(eH, "loose") and S(eH.glow).shown ~= true, "alerte coupée : rouge sans liseré")
ns:Set("platesAlert", true)

-- pas d'alerte pour un DPS qui perd la menace
ns:Set("platesRole", "dps")
local tI, eI = addMob({ threat = { true, 3 } })
setThreat(tI, false, 0)
check(S(eI.glow).shown ~= true, "DPS : jamais d'alerte")
ns:Set("platesRole", "tank")
sim.party, sim.roles.party1 = 0, nil
M.fireEvent("GROUP_ROSTER_UPDATE")
M.advance(0.3)

---------------------------------------------------------------------------
section("menace secrète")
local tS, eS = addMob({ threat = { secret(true), secret(2) } })
local fb = S(eS.tint).fromBool
check(fb ~= nil, "SetVertexColorFromBoolean appelé sur la teinte")
check(tintShown(eS), "teinte affichée (mob en combat)")
check(fb and getmetatable(fb.value) == SecretMT, "la valeur secrète est passée telle quelle")
check(fb and near({ fb.ifTrue.r, fb.ifTrue.g, fb.ifTrue.b }, COLORS.safe) and near({ fb.ifFalse.r, fb.ifFalse.g, fb.ifFalse.b }, COLORS.loose),
    "tank : tanke = vert, sinon rouge")
local tT, eT = addMob({ threat = { secret(true), secret(2) }, combat = false })
check(tintIs(eT, "hostile") and S(eT.tint).fromBool == nil, "secret, mob pas en combat : couleur hostile (pas de booléen)")
ns:Set("platesIdle", "game")
check(not tintShown(eT), "secret, mob pas en combat, idle game : cachée")
ns:Set("platesIdle", "reaction")
ns:Set("platesRole", "dps")
local fb2 = S(eS.tint).fromBool
check(fb2 and near({ fb2.ifTrue.r, fb2.ifTrue.g, fb2.ifTrue.b }, COLORS.loose), "DPS : tanke = rouge")
ns:Set("platesRole", "tank")
check(#M.errors == 0, "aucune erreur d'exécution avec des valeurs secrètes")

---------------------------------------------------------------------------
section("quête")
local function questLines(...)
    local l = { { leftText = "Loup", type = 0 } }
    for _, x in ipairs({ ... }) do l[#l + 1] = x end
    return l
end
local TITLE = { leftText = "La chasse aux loups", type = 17 }
-- journal vide : aucune infobulle lue (pas d'icône)
local _, eQ0 = addMob({ lines = questLines(TITLE, { leftText = "Loup tué : 3/8", type = 8 }) })
check(S(eQ0.quest).shown ~= true, "journal sans objectif : pas d'icône (infobulles non lues)")
sim.quests = { { questID = 10, objectives = { { text = "Loup tué : 0/8", type = "monster" } } } }
M.fireEvent("QUEST_LOG_UPDATE")
M.advance(1.1)
local tQ, eQ = addMob({ lines = questLines(TITLE, { leftText = " - Loup tué : 3/8", type = 8 }) })
check(S(eQ.quest).shown == true, "objectif en cours : icône visible")
check(S(eQ.quest).texture == "Interface\\GossipFrame\\AvailableQuestIcon", "icône « ! » pour un mob à tuer")
check(S(eQ.questText).text == "3/8" and S(eQ.questText).shown == true, "texte « 3/8 »")

local _, eQ2 = addMob({ lines = questLines(TITLE, { leftText = "Loup tué : 8/8", type = 8 }) })
check(S(eQ2.quest).shown ~= true, "8/8 : caché")
local _, eQ3 = addMob({ lines = questLines(TITLE, { leftText = "Loup tué : 3/8", type = 8, completed = true }) })
check(S(eQ3.quest).shown ~= true, "completed=true : caché")
local _, eQ4 = addMob({ lines = questLines({ leftText = "Autre", type = 18 }, { leftText = "Loup tué : 1/8", type = 8 }) })
check(S(eQ4.quest).shown ~= true, "objectif d'un autre membre du groupe : ignoré")
local _, eQ5 = addMob({ lines = questLines({ leftText = "Heros", type = 18 }, { leftText = "Loup tué : 1/8", type = 8 }) })
check(S(eQ5.quest).shown == true, "ses propres objectifs (ligne à son nom) : affichés")
local _, eQ6 = addMob({ lines = questLines(TITLE, { leftText = "Sauvé : 40%", type = 8 }) })
check(S(eQ6.quest).shown == true and S(eQ6.questText).text == "40%", "objectif en pourcentage : « 40% »")

-- journal en retard sur l'infobulle (0/5 contre 2/5) : le type est quand même retrouvé
sim.quests = { { questID = 10, objectives = { { text = "Loup tué : 3/8", type = "monster" } } },
    { questID = 11, objectives = { { text = "Peau de loup : 0/5", type = "item" } } } }
M.fireEvent("QUEST_LOG_UPDATE")
M.advance(1.1)
local _, eQ7 = addMob({ lines = questLines(TITLE, { leftText = "Peau de loup : 2/5", type = 8 }) })
check(S(eQ7.quest).texture == "Interface\\GossipFrame\\VendorGossipIcon", "objet à récupérer : icône de sac")
check(S(eQ7.questText).text == "2/5", "progression « 2/5 »")

local _, eQ8 = addMob({ lines = questLines(TITLE, { leftText = secret("x"), type = 8 }) })
check(S(eQ8.quest).shown ~= true and #M.errors == 0, "texte secret : rien, sans erreur")

-- QUEST_LOG_UPDATE rafraîchit après le délai
sim.mobs[tQ].lines = questLines(TITLE, { leftText = " - Loup tué : 4/8", type = 8 })
M.fireEvent("QUEST_LOG_UPDATE")
check(S(eQ.questText).text == "3/8", "avant le délai : pas encore relu")
M.advance(1.1)
check(S(eQ.questText).text == "4/8", "après le délai : « 4/8 »")
ns:Set("platesQuest", false)
check(S(eQ.quest).shown ~= true and S(eQ.questText).shown ~= true, "option quête coupée : caché")
ns:Set("platesQuest", true)
check(S(eQ.quest).shown == true, "option rallumée : revient")

---------------------------------------------------------------------------
section("rare, élite, boss")
ns:Set("platesRare", true)
ns:Set("platesElite", true)
local tR, eR = addMob({ class = "rare" })
check(S(eR.tag).shown == true and S(eR.tag).text == "Rare", "mob rare : « Rare » visible")
local _, eR2 = addMob({ class = "rareelite" })
check(S(eR2.tag).shown == true, "rare élite : visible")
local _, eR3 = addMob({ class = "normal" })
check(S(eR3.tag).shown ~= true, "mob normal : pas de « Rare »")
ns:Set("platesRare", false)
check(S(eR.tag).shown ~= true, "option rare coupée : caché")
ns:Set("platesRare", true)
check(S(eR.tag).shown == true, "option rallumée : visible")
sim.mobs[tR].class = "normal"
M.fireEvent("UNIT_CLASSIFICATION_CHANGED", tR)
check(S(eR.tag).shown ~= true, "classification changée : caché")
check(S(eR2.tag).text == "Rare élite", "rare élite : « Rare élite »")
local _, eE1 = addMob({ class = "elite" })
check(S(eE1.tag).shown == true and S(eE1.tag).text == "Élite", "élite : « Élite »")
local _, eE2 = addMob({ class = "worldboss" })
check(S(eE2.tag).shown == true and S(eE2.tag).text == "Boss", "boss : « Boss »")
ns:Set("platesElite", false)
check(S(eE1.tag).shown ~= true and S(eE2.tag).shown ~= true, "option élite coupée : Élite et Boss cachés")
check(S(eR2.tag).text == "Rare", "élite coupée : rare élite devient « Rare »")
ns:Set("platesElite", true)
check(S(eE1.tag).shown == true, "élite rallumée")

---------------------------------------------------------------------------
section("retrait et interrupteur")
local tX, eX = addMob({ threat = { true, 3 }, class = "rare", lines = questLines(TITLE, { leftText = "Loup tué : 1/8", type = 8 }) })
check(tintShown(eX) and S(eX.tag).shown == true and S(eX.quest).shown == true, "plate complète affichée")
M.fireEvent("NAME_PLATE_UNIT_REMOVED", tX)
check(not tintShown(eX) and S(eX.tag).shown ~= true and S(eX.quest).shown ~= true and S(eX.questText).shown ~= true,
    "NAME_PLATE_UNIT_REMOVED : tout caché")

ns:Set("plates", false)
check(not tintShown(eA) and not tintShown(eD) and S(eQ.quest).shown ~= true, "plates coupées : tout caché")
n = n + 1
local tY = "nameplate" .. n
local _, barY = makePlate(tY)
sim.mobs[tY].threat = { true, 3 }
M.fireEvent("NAME_PLATE_UNIT_ADDED", tY)
check(#S(barY).frames == 0, "plates coupées : une nouvelle plate n'est pas prise en charge")
ns:Set("plates", true)
local eY = parts(barY)
check(tintShown(eY), "rallumées : les plates visibles sont reprises (GetNamePlates)")
check(tintIs(eY, "safe"), "reprise : couleur de menace posée")

---------------------------------------------------------------------------
section("look : contour fin, taille")
check(S(barY.bgTexture).alpha == 0 and S(eY.back).shown == true, "contour fin : cadre du jeu transparent, notre fond affiché")
ns:Set("platesSlim", false)
check(math.abs(S(barY.bgTexture).alpha - 0.85) < 0.001 and S(eY.back).shown ~= true,
    "contour fin coupé : cadre du jeu revenu (à l'opacité choisie)")
ns:Set("platesSlim", true)
check(S(barY.bgTexture).alpha == 0, "contour fin rallumé")
ns:Set("plates", false)
check(S(barY.bgTexture).alpha == 1 and S(eY.back).shown ~= true, "plates coupées : cadre du jeu revenu")
ns:Set("plates", true)
check(S(barY.bgTexture).alpha == 0, "plates rallumées : contour fin")
-- opacité : fond et teinte à 85 % ; teinte affichée -> remplissage du jeu caché dessous
check(math.abs(S(eY.back).alpha - 0.85 * ns.db.platesBackAlpha / 100) < 0.001 and math.abs(S(eY.tint).alpha - 0.85) < 0.001, "opacité 85 % : teinte, fond selon platesBackAlpha")
local fillY = barY:GetStatusBarTexture()
if fillY then check(S(fillY).alpha == 0, "teinte affichée : remplissage du jeu caché") end
ns:Set("platesOpacity", 50)
check(math.abs(S(eY.back).alpha - 0.5 * ns.db.platesBackAlpha / 100) < 0.001 and math.abs(S(eY.tint).alpha - 0.5) < 0.001, "curseur à 50 % appliqué")
ns:Set("platesIdle", "game")
sim.mobs[tY].threat = { false, nil }
M.fireEvent("UNIT_THREAT_LIST_UPDATE", tY)
if fillY then check(math.abs(S(fillY).alpha - 0.5) < 0.001, "hors combat (idle game) : remplissage du jeu à 50 %") end
ns:Set("platesIdle", "reaction")
ns:Set("plates", false)
if fillY then check(S(fillY).alpha == 1, "plates coupées : remplissage du jeu opaque") end
ns:Set("plates", true)
ns:Set("platesOpacity", 85)
sim.mobs[tY].threat = { true, 3 }
M.fireEvent("UNIT_THREAT_LIST_UPDATE", tY)
-- passage unique en « épaisse » + « grande » (3 s après le chargement : déjà fait plus haut dans le test)
check(ns.db.platesBigDone == true, "passage unique en grandes plates fait")
check(tonumber(M.cvars.nameplateStyle) == 0 and tonumber(M.cvars.nameplateSize) == 3, "barre épaisse + taille grande")
M.inCombat = true
check(P.SetGameSetting("nameplateSize", 5) == false and tonumber(M.cvars.nameplateSize) == 3, "en combat : taille non changée")
M.inCombat = false
check(P.SetGameSetting("nameplateSize", 4) and tonumber(M.cvars.nameplateSize) == 4, "hors combat : taille changée")

---------------------------------------------------------------------------
section("look : bord, cible, texture, couleurs, quête")
ns:Set("platesTarget", true)
ns:Set("platesBorder", 1)
check(S(eY.border).shown == true, "bord affiché (cadre à nous)")
check(S(eY.border).points[1][4] == -1, "bord : 1 px autour de la barre")
sim.target = tY
M.fireEvent("PLAYER_TARGET_CHANGED")
check(S(eY.targetBorder).shown == true and S(eY.border).shown ~= true and S(eY.targetBorder).points[1][4] == -2,
    "cible : bord de cible (+1 px) à la place du bord")
check(near(S(eY.targetBorder).vertex, COLORS.target), "cible : couleur de cible")
check(S(eY.border).points[1][4] == -1, "le bord normal n'est pas ré-ancré au changement de cible")
ns:Set("platesColTarget", { 1, 0, 1 })
check(near(S(eY.targetBorder).vertex, { 1, 0, 1 }), "couleur de cible personnalisée")
ns:Reset("platesColTarget")
local tZ, eZ = addMob({ threat = { true, 3 } })
check(math.abs(S(eZ.tint).alpha - 0.85) < 0.001, "non ciblée à 100 % : opacité normale")
ns:Set("platesNonTarget", 60)
check(math.abs(S(eZ.tint).alpha - 0.85 * 0.6) < 0.001, "non ciblée à 60 % : teinte atténuée")
check(math.abs(S(eY.tint).alpha - 0.85) < 0.001, "la cible garde son opacité")
sim.target = nil
M.fireEvent("PLAYER_TARGET_CHANGED")
check(math.abs(S(eZ.tint).alpha - 0.85) < 0.001 and S(eY.border).shown == true and S(eY.targetBorder).shown ~= true,
    "plus de cible : tout revient")
ns:Set("platesNonTarget", 100)
ns:Set("platesBorder", 0)
check(S(eY.border).shown ~= true, "bord 0 : bord caché")
ns:Set("platesBorder", 3)
check(S(eY.border).shown == true and S(eY.border).points[1][4] == -3, "bord 3 px")
ns:Set("platesBorder", 1)
ns:Set("platesTexture", "flat")
check(S(eY.tint).texture == "Interface\\Buttons\\WHITE8X8", "texture « flat » appliquée à la teinte")
ns:Set("platesTexture", "smooth")
check(S(eY.tint).texture == "Interface\\AddOns\\Platyplus\\Media\\Bar", "texture « smooth » rétablie")
ns:Set("platesColSafe", { 0, 0, 1 })
check(near(S(eY.tint).vertex, { 0, 0, 1 }), "couleur « sûre » personnalisée : la teinte d'un mob tenu devient bleue")
ns:Reset("platesColSafe")
check(tintIs(eY, "safe"), "couleur par défaut revenue")
-- quête : côté, texte
check(S(eQ.quest).points[1][1] == "RIGHT", "quête à gauche : ancrée par sa droite")
ns:Set("platesQuestSide", "right")
check(S(eQ.quest).points[1][1] == "LEFT" and S(eQ.quest).points[1][3] == "RIGHT", "quête à droite de la barre")
ns:Set("platesQuestSide", "top")
check(S(eQ.quest).points[1][1] == "BOTTOMLEFT" and S(eQ.quest).points[1][3] == "TOPLEFT", "quête au-dessus de la barre")
ns:Set("platesQuestSide", "left")
ns:Set("platesQuestText", false)
check(S(eQ.quest).shown == true and S(eQ.questText).shown ~= true, "texte de quête coupé : icône seule")
ns:Set("platesQuestText", true)
check(S(eQ.questText).shown == true, "texte de quête rallumé")
ns:Set("platesAlertTime", 3)
local tAT, eAT = addMob({ threat = { true, 3 } })
setThreat(tAT, false, 0)
M.advance(2)
check(S(eAT.glow).shown == true, "durée d'alerte 3 s : encore affiché à 2 s")
M.advance(1.2)
check(S(eAT.glow).shown ~= true, "alerte finie après 3 s")
ns:Reset("platesAlertTime")

---------------------------------------------------------------------------
section("aperçu des options")
local box = P.NewPreview(CreateFrame("Frame"), 550)
check(#box.samples == 4, "4 plates d'exemple")
check(pcall(box.Refresh, box), "Refresh sans erreur")
local s1, s4 = box.samples[1].o, box.samples[4].o
check(tintIs(s1, "safe"), "exemple 1 : vert")
check(tintIs(box.samples[3].o, "loose"), "exemple 3 : rouge")
check(tintIs(s4, "hostile"), "exemple 4 (hors combat, idle reaction) : hostile")
check(S(s4.tag).shown == true and S(s4.tag).text == "Rare", "exemple 4 : « Rare »")
check(S(s4.questText).text == "3/8", "exemple 4 : quête 3/8")
ns:Set("plates", false)
check(tintIs(s1, "safe") and S(s1.back).shown == true, "plates coupées : l'aperçu reste stylé")
ns:Set("platesColSafe", { 0, 0.5, 0 })
check(near(S(s1.tint).vertex, { 0, 0.5, 0 }), "l'aperçu suit les réglages de couleur")
ns:Reset("platesColSafe")
ns:Set("plates", true)

---------------------------------------------------------------------------
section("styles et remise à zéro")
check(P.ApplyPreset("threat") == true and P.ApplyPreset("nimporte") == false, "ApplyPreset : connu / inconnu")
check(near(ns.db.platesColSafe, { 0, 1, 0 }) and ns.db.platesRadius == 0, "style threat : sûre = vert pur, radius 0")
check(near(S(eY.tint).vertex, { 0, 1, 0 }), "style threat : plates repeintes")
P.ApplyPreset("minimal")
check(ns.db.platesBorder == 0 and S(eY.border).shown ~= true, "style minimal : bord 0, caché")
check(tintIs(eY, "safe"), "style minimal : couleurs par défaut remises")
P.ResetLook()
check(near(ns.db.platesColSafe, COLORS.safe) and ns.db.platesRadius == ns.DEFAULTS.platesRadius, "ResetLook : défauts")
check(ns.db.platesTexture == ns.DEFAULTS.platesTexture and ns.db.platesBorder == ns.DEFAULTS.platesBorder, "ResetLook : texture et bord")
check(#M.errors == 0, "aucune erreur d'exécution")

---------------------------------------------------------------------------
section("commande /pp plates")
local before = #M.printed
SlashCmdList["PLATYPLUS"]("plates")
check(#M.printed > before, "/pp plates imprime l'état")
SlashCmdList["PLATYPLUS"]("plates tank")
check(ns.db.platesRole == "tank", "/pp plates tank : rôle forcé")
SlashCmdList["PLATYPLUS"]("plates dps")
check(ns.db.platesRole == "dps" and P:IsTank() == false, "/pp plates dps : rôle DPS")
SlashCmdList["PLATYPLUS"]("plates auto")
check(ns.db.platesRole == "auto", "/pp plates auto")

---------------------------------------------------------------------------
-- Barres d'incantation des ennemis
---------------------------------------------------------------------------
sim.casts, sim.channels, sim.spells, sim.cd, sim.usable = {}, {}, {}, {}, {}
def("IsPlayerSpell", function(id) return sim.spells[id] or false end)
def("C_Spell", {
    GetSpellCooldown = function(id) return sim.cd[id] or { isActive = false, isOnGCD = false } end,
    IsSpellUsable = function(id) if sim.usable[id] == nil then return true end return sim.usable[id] end,
})
def("UnitCastingInfo", function(u)
    local c = sim.casts[u]
    if not c then return nil end
    return c.name, c.name, 136243, 1000, c.endMs, false, "cast1", c.notInt, 100
end)
def("UnitChannelInfo", function(u)
    local c = sim.channels[u]
    if not c then return nil end
    return c.name, c.name, 136243, 1000, c.endMs, false, c.notInt
end)

local castN = 0
-- plate d'un mob avec barre d'incantation ; renvoie jeton, barre d'incantation et ses éléments
local function addCaster()
    castN = castN + 1
    local token = "castplate" .. castN
    local plate, bar = makePlate(token)
    local cb = CreateFrame("StatusBar")
    cb.Background = cb:CreateTexture(nil, "BACKGROUND")
    plate.UnitFrame.castBar = cb
    return token, cb, bar
end
local function castParts(cb)
    local own = S(cb).regions
    local root = S(cb).frames[1]
    return { tint = own[#own - 2], border = own[#own - 1], back = own[#own], timer = S(root).regions[1], root = root,
        fill = cb:GetStatusBarTexture() }
end
local function startCast(token, c)
    sim.casts[token] = c
    M.fireEvent("UNIT_SPELLCAST_START", token)
    M.advance(0.1)
end
-- fin normale : la teinte reste pendant le fondu du jeu, puis la barre du jeu se cache (OnHide de notre cadre enfant)
local castEnds = {}
local function endCast(token, el)
    sim.casts[token], sim.channels[token] = nil, nil
    M.fireEvent("UNIT_SPELLCAST_STOP", token)
    if el then
        castEnds[#castEnds + 1] = S(el.tint).shown == true and S(el.timer).shown ~= true
        M.fire(el.root, "OnHide")
    end
end
local function tintCol(el, kind) return S(el.tint).shown == true and near(S(el.tint).vertex, COLORS[kind]) end
local function endIn(sec) return (GetTime() + sec) * 1000 end

section("incantation : couleurs")
ns:Set("platesCastKick", true)
local ctok, ccb, cbar = addCaster()
M.fireEvent("NAME_PLATE_UNIT_ADDED", ctok)
local ce = castParts(ccb)
check(S(ce.tint).shown ~= true, "pas d'incantation : teinte cachée")
startCast(ctok, { name = "Boule de feu", endMs = endIn(2), notInt = false })
check(tintCol(ce, "castInterrupt"), "incantation interruptible, aucune interruption connue : couleur platesColCastInterrupt")
check(S(ce.fill).alpha == 0, "teinte affichée : remplissage du jeu à alpha 0")

sim.spells[6552] = true
M.fireEvent("SPELL_UPDATE_USABLE")
check(tintCol(ce, "castKick"), "Volée de coups connue, prête et utilisable : couleur castKick")
sim.cd[6552] = { isActive = true, isOnGCD = false }
M.fireEvent("SPELL_UPDATE_COOLDOWN")
check(tintCol(ce, "castInterrupt"), "interruption en recharge : repasse en interruptible")
sim.cd[6552] = { isActive = true, isOnGCD = true }
M.fireEvent("SPELL_UPDATE_COOLDOWN")
check(tintCol(ce, "castKick"), "seulement le temps de recharge global : compte comme prête")
sim.cd[6552] = nil
sim.usable[6552] = false
M.fireEvent("SPELL_UPDATE_USABLE")
check(tintCol(ce, "castInterrupt"), "interruption inutilisable : interruptible")
sim.usable[6552] = nil
M.fireEvent("SPELL_UPDATE_USABLE")
check(tintCol(ce, "castKick"), "de nouveau utilisable : castKick")
ns:Set("platesCastKick", false)
M.fireEvent("UNIT_SPELLCAST_START", ctok)
check(tintCol(ce, "castInterrupt"), "platesCastKick coupé : interruptible")
ns:Set("platesCastKick", true)
sim.spells[6552] = nil
M.fireEvent("SPELL_UPDATE_COOLDOWN")
check(tintCol(ce, "castInterrupt"), "sort inconnu : interruptible")

section("incantation : pas interruptible")
sim.casts[ctok].notInt = true
M.fireEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", ctok)
check(tintCol(ce, "castShield"), "notInterruptible : couleur castShield")
sim.casts[ctok].notInt = false
M.fireEvent("UNIT_SPELLCAST_INTERRUPTIBLE", ctok)
check(tintCol(ce, "castInterrupt"), "UNIT_SPELLCAST_INTERRUPTIBLE : recolore en interruptible")
sim.casts[ctok].notInt = true
M.fireEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", ctok)
check(tintCol(ce, "castShield"), "UNIT_SPELLCAST_NOT_INTERRUPTIBLE : recolore en bouclier")
sim.spells[6552] = true
M.fireEvent("SPELL_UPDATE_COOLDOWN")
check(tintCol(ce, "castShield"), "prête mais pas interruptible : reste bouclier")
sim.spells[6552] = nil
M.fireEvent("SPELL_UPDATE_COOLDOWN")

section("incantation : valeurs secrètes")
sim.casts[ctok].notInt = secret(true)
M.fireEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", ctok)
local cfb = S(ce.tint).fromBool
check(cfb ~= nil and getmetatable(cfb.value) == SecretMT, "notInterruptible secret : SetVertexColorFromBoolean sur la teinte")
check(cfb and near({ cfb.ifTrue.r, cfb.ifTrue.g, cfb.ifTrue.b }, COLORS.castShield)
    and near({ cfb.ifFalse.r, cfb.ifFalse.g, cfb.ifFalse.b }, COLORS.castInterrupt), "secret : vrai = bouclier, faux = interruptible")
check(S(ce.tint).shown == true, "teinte affichée malgré le secret")
endCast(ctok)
local stok, scb = addCaster()
M.fireEvent("NAME_PLATE_UNIT_ADDED", stok)
local se = castParts(scb)
startCast(stok, { name = secret("Sort"), endMs = secret(5), notInt = secret(false) })
check(S(se.tint).shown == true, "nom secret : considéré comme incantation en cours")
check(S(se.timer).shown ~= true, "endMs secret : minuteur caché")
check(#M.errors == 0, "aucune erreur avec une incantation secrète")
endCast(stok, se)
check(S(se.tint).shown ~= true, "secrète terminée : teinte cachée")

section("incantation : canalisation, arrêt, minuteur")
sim.channels[ctok] = { name = "Drain d'âme", endMs = endIn(4), notInt = false }
M.fireEvent("UNIT_SPELLCAST_CHANNEL_START", ctok)
M.advance(0.1)
check(tintCol(ce, "castInterrupt"), "canalisation (UnitChannelInfo seul) : teinte visible")
check(S(ce.timer).shown == true, "canalisation : minuteur affiché")
sim.channels[ctok] = nil
M.fireEvent("UNIT_SPELLCAST_CHANNEL_STOP", ctok)
check(S(ce.tint).shown == true and S(ce.timer).shown ~= true, "fin de canalisation : teinte gardée pendant le fondu, minuteur caché")
M.fire(ce.root, "OnHide")
check(S(ce.tint).shown ~= true, "fin de canalisation : teinte cachée quand la barre du jeu se cache")

startCast(ctok, { name = "Éclair", endMs = endIn(2.5), notInt = false })
M.advance(0.2)
check(S(ce.timer).shown == true and S(ce.timer).text:match("^%d+%.%d$") ~= nil, "platesCastTimer : texte « x.x » (" .. tostring(S(ce.timer).text) .. ")")
check(S(ce.root).scripts.OnUpdate ~= nil, "minuteur : OnUpdate en cours")
ns:Set("platesCastTimer", false)
M.fireEvent("UNIT_SPELLCAST_DELAYED", ctok)
check(S(ce.timer).shown ~= true, "platesCastTimer coupé : minuteur caché")
ns:Set("platesCastTimer", true)
endCast(ctok, ce)
check(castEnds[#castEnds] == true, "UNIT_SPELLCAST_STOP : teinte gardée pendant le fondu")
check(S(ce.tint).shown ~= true, "UNIT_SPELLCAST_STOP puis barre cachée : teinte cachée")
check(S(ce.fill).alpha == 1, "arrêt : remplissage du jeu à alpha 1")
check(S(ce.timer).shown ~= true and S(ce.root).scripts.OnUpdate == nil, "arrêt : minuteur caché, OnUpdate retiré")

section("incantation : look")
check(S(ccb.Background).alpha == 0 and S(ce.back).shown == true, "style + contour fin : fond du jeu transparent, notre fond affiché")
ns:Set("platesCastStyle", false)
check(S(ccb.Background).alpha == 1 and S(ce.back).shown ~= true, "platesCastStyle coupé : fond du jeu revenu")
ns:Set("platesCastStyle", true)
ns:Set("platesSlim", false)
check(S(ccb.Background).alpha == 1, "contour fin coupé : fond du jeu revenu")
ns:Set("platesSlim", true)
startCast(ctok, { name = "Éclair", endMs = endIn(2), notInt = false })
ns:Set("platesCast", false)
check(S(ccb.Background).alpha == 1 and S(ce.tint).shown ~= true and S(ce.back).shown ~= true,
    "platesCast coupé : rien de Platyplus sur la barre")
check(S(ce.fill).alpha == 1, "platesCast coupé : remplissage du jeu visible")
M.fireEvent("UNIT_SPELLCAST_START", ctok)
check(S(ce.tint).shown ~= true, "platesCast coupé : une nouvelle incantation n'est pas teintée")
ns:Set("platesCast", true)
M.fireEvent("UNIT_SPELLCAST_START", ctok)
check(S(ce.tint).shown == true, "platesCast rallumé : teinte revenue")
endCast(ctok)

section("incantation : son, ajout, retrait")
ns:Set("platesCastSound", true)
local ptok, pcb = addCaster()
M.fireEvent("NAME_PLATE_UNIT_ADDED", ptok)
sim.target = nil
M.fireEvent("PLAYER_TARGET_CHANGED")
local s0 = sim.sounds
startCast(ptok, { name = "Peur", endMs = endIn(2), notInt = false })
check(sim.sounds == s0, "pas la cible : pas de son")
endCast(ptok)
sim.target = ptok
M.fireEvent("PLAYER_TARGET_CHANGED")
M.advance(2)
startCast(ptok, { name = "Peur", endMs = endIn(2), notInt = false })
check(sim.sounds == s0 + 1, "cible + interruptible : son joué")
endCast(ptok)
M.advance(2)
s0 = sim.sounds
startCast(ptok, { name = "Soin", endMs = endIn(2), notInt = true })
check(sim.sounds == s0, "cible mais pas interruptible : pas de son")
endCast(ptok)
M.advance(2)
ns:Set("platesCastSound", false)
s0 = sim.sounds
startCast(ptok, { name = "Peur", endMs = endIn(2), notInt = false })
check(sim.sounds == s0, "son coupé : rien")
endCast(ptok)
sim.target = nil
M.fireEvent("PLAYER_TARGET_CHANGED")

local atok, acb = addCaster()
sim.casts[atok] = { name = "Rage", endMs = endIn(3), notInt = false }
M.fireEvent("NAME_PLATE_UNIT_ADDED", atok)
local ae = castParts(acb)
check(tintCol(ae, "castInterrupt"), "incantation déjà en cours à l'apparition de la plate : teinte posée")
M.fireEvent("NAME_PLATE_UNIT_REMOVED", atok)
check(S(ae.tint).shown ~= true and S(ae.timer).shown ~= true, "plate retirée : incantation arrêtée")
check(S(ae.root).scripts.OnUpdate == nil, "plate retirée : minuteur arrêté")
M.fireEvent("UNIT_SPELLCAST_START", atok)
check(#M.errors == 0, "événement d'une plate retirée : sans erreur")

section("aperçu en une colonne")
local pv = P.NewPreview(CreateFrame("Frame"), 300, 1)
check(#pv.samples == 4, "4 échantillons")
check(pv:GetHeight() == 84 * 4 + 8, "une colonne : hauteur de 4 rangées")
local pv2 = P.NewPreview(CreateFrame("Frame"), 300, 2)
check(pv2:GetHeight() == 84 * 2 + 8, "deux colonnes : hauteur de 2 rangées")
check(pv.samples[1].o.cast == nil and pv.samples[4].o.cast == nil, "échantillons 1 et 4 : pas de barre d'incantation")
local p2, p3 = pv.samples[2].o.cast, pv.samples[3].o.cast
check(p2 ~= nil and p3 ~= nil, "échantillons 2 et 3 : barre d'incantation imitée")
pv:Refresh()
check(S(p2.tint).shown == true and near(S(p2.tint).vertex, COLORS.castKick), "échantillon 2 : couleur castKick")
check(S(p3.tint).shown == true and near(S(p3.tint).vertex, COLORS.castShield), "échantillon 3 : couleur castShield")
check(S(p2.bar).shown == true, "barres d'incantation de l'aperçu affichées")
ns:Set("platesCastKick", false)
pv:Refresh()
check(near(S(p2.tint).vertex, COLORS.castInterrupt), "kick coupé : échantillon 2 en interruptible")
ns:Set("platesCastKick", true)
ns:Set("platesCast", false)
pv:Refresh()
check(S(p2.bar).shown ~= true and S(p3.bar).shown ~= true, "platesCast coupé : barres d'incantation de l'aperçu cachées")
ns:Set("platesCast", true)
check(#M.errors == 0, "aucune erreur d'exécution (incantations)")

section("mise en évidence d'une plate (fenêtre de menace)")
local htok, _, hbar = addMob({})
local htok2, _, hbar2 = addMob({})
local function litOf(bar)
    for _, f in ipairs(S(bar).frames or {}) do
        local r = S(f).regions[1]
        if r and S(r).vertex and S(r).vertex[2] == 0.95 and S(r).vertex[4] == 0.95 and S(f).shown then return true end
    end
    return false
end
check(P.Highlight(htok) == true and litOf(hbar), "Highlight(jeton) : liseré clair posé sur la barre de la plate")
check(not litOf(hbar2), "l'autre plate n'est pas éclairée")
P.Highlight(htok2)
check(litOf(hbar2) and not litOf(hbar), "une seule plate éclairée à la fois")
check(P.Highlight("boss1") == false and not litOf(hbar2), "jeton sans plate : rien (et l'ancienne mise en évidence est retirée)")
P.Highlight(htok)
P.Highlight(nil)
check(not litOf(hbar), "Highlight(nil) : retirée")
P.Highlight(htok)
M.fireEvent("NAME_PLATE_UNIT_REMOVED", htok)
check(not litOf(hbar), "plate qui disparaît : mise en évidence retirée")
P.Highlight(htok2)
sim.plates[htok2] = nil
sim.plates[htok2] = { namePlateUnitToken = "nameplate9", UnitFrame = { unit = "nameplate9", healthBar = hbar2 } }
sim.mobs.nameplate9 = { canAttack = true, combat = true, class = "normal", threat = { false, nil }, lines = {}, reaction = 2, player = false }
sim.plates.nameplate9 = sim.plates[htok2]
M.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate9")
check(not litOf(hbar2), "cadre de plate réutilisé pour un autre mob : plus éclairé")
check(P.Highlight(5) == false and P.Highlight(nil) == false, "argument invalide : sans erreur")
check(#M.errors == 0, "aucune erreur d'exécution (mise en évidence)")

---------------------------------------------------------------------------
section("bilan"); M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
