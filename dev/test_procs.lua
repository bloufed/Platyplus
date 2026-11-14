-- Test : alerte de proc avec la touche à presser (Procs.lua) dans le simulateur, en mode strict.
-- Un guerrier : Fulgurance sur la touche 3, Exécution sur Maj+5, Vengeance sur la barre en bas à gauche (Souris 4),
-- Riposte dans une macro sans touche, un sort que le jeu fait briller sur Ctrl+Pavé 1, Frappe héroïque (pas réactive).
--  * texte des touches ; rien tant que rien n'est utilisable (et aucune boucle OnUpdate)
--  * Fulgurance utilisable -> alerte « 3 » ; disparaît quand elle ne l'est plus (événement ou contrôle régulier)
--  * recharge : cachée si lisible et longue, montrée pendant le temps global ou si la recharge est secrète ;
--    avec l'objet durée (GetActionCooldownDuration) cachée aussi en combat, pour un sort réactif comme pour un sort
--    qui brille, et l'alerte revient toute seule quand la recharge finit
--  * plusieurs alertes côte à côte (3 au plus), le bon bouton quand le sort est sur deux boutons, autre rang par nom
--  * lueur du jeu (événements et IsSpellOverlayed), macro, « aucune touche », valeurs secrètes
--  * réglage coupé, aperçu, déplacement, /pp proc
-- Usage : python -I dev\lua.py run dev\test_procs.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S, impl = M.state, M.impl

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

impl.GetCenter = function(f)                         -- centre propre à chaque cadre (déplacement)
    local c = S(f).center
    if c then return c[1], c[2] end
    return 683, 384
end

---------------------------------------------------------------------------
-- Faux jeu
---------------------------------------------------------------------------
local OVERPOWER, EXECUTE, REVENGE, RIPOSTE, HEROIC, PROC, OVERPOWER_OTHER = 7384, 20662, 6572, 14251, 78, 12345, 99001
local names = {
    [OVERPOWER] = "Fulgurance", [7887] = "Fulgurance", [11584] = "Fulgurance", [11585] = "Fulgurance",
    [EXECUTE] = "Exécution", [REVENGE] = "Vengeance", [RIPOSTE] = "Riposte", [HEROIC] = "Frappe héroïque",
    [PROC] = "Idées claires", [OVERPOWER_OTHER] = "Fulgurance",
    [19306] = "Contre-attaque", [1495] = "Morsure de la mangouste", [24239] = "Marteau de courroux",
    [409379] = "Ordre de tuer", [409396] = "Ordre de tuer",
}
local slots = {
    [2] = { "spell", OVERPOWER },          -- Fulgurance une 2e fois, sans touche
    [3] = { "spell", OVERPOWER },          -- Fulgurance sur la touche 3
    [5] = { "spell", EXECUTE },
    [7] = { "spell", HEROIC },
    [8] = { "macro", RIPOSTE, "spell" },   -- macro qui lance Riposte, sans touche
    [9] = { "spell", PROC },
    [10] = { "spell", OVERPOWER_OTHER },   -- autre numéro de Fulgurance (reconnu par son nom)
    [61] = { "spell", REVENGE },           -- barre en bas à gauche, bouton 1
}
def("GetActionInfo", function(action)
    local s = slots[action]
    if s then return s[1], s[2], s[3] end
end)
local usable, lacking, cooldowns, glowing = {}, {}, {}, {}
local durationLeft = {}                 -- [emplacement] = secondes restantes vues par l'objet durée
local SecretMT = { __tostring = function() return "secret" end }
for _, op in ipairs({ "__eq", "__lt", "__le", "__add", "__sub", "__concat" }) do
    SecretMT[op] = function() error("opération interdite sur une valeur secrète (" .. op .. ")", 2) end
end
local function secret() return setmetatable({}, SecretMT) end
def("issecretvalue", function(v) return getmetatable(v) == SecretMT end)
local usableCalls = 0
def("C_ActionBar", {
    IsUsableAction = function(action)
        usableCalls = usableCalls + 1
        local u = usable[action]
        if u == "secret" then return secret(), false end
        return u == true, lacking[action] == true
    end,
    GetActionCooldown = function(action)
        return cooldowns[action] or { startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1 }
    end,
    GetActionCooldownDuration = function(action, ignoreGCD)
        local left = durationLeft[action]                -- nil : API des objets durée absente (ancien chemin)
        if left == nil then return nil end
        -- comme dans le jeu : un userdata (LuaDurationObjectAPI, ObjectType = "Userdata"), pas une table
        local d = newproxy(true)
        getmetatable(d).__index = {
            IsActive = function() return left > 0 end,
            GetRemainingDuration = function() return left end,
        }
        return d
    end,
    GetActionTexture = function(action)
        local s = slots[action]
        return s and (1000 + s[2]) or nil
    end,
})
def("C_Spell", {
    GetSpellName = function(id) return names[id] end,
    GetSpellTexture = function(id) return 2000 + id end,
    GetSpellPowerCost = function() return {} end,
})
def("C_SpellActivationOverlay", { IsSpellOverlayed = function(id) return glowing[id] == true end })
-- auras du joueur (charges de Maîtrise du blocage) : comme en jeu, GetPlayerAuraBySpellID et GetAuraDataBySpellName ne
-- renvoient RIEN quand le jeu cache les auras (RequiresNonSecretAura) et ShouldSpellAuraBeSecret le dit
local BLOCK, BLOCK_PASSIVE, BLOCK_OTHER = 2565, 4760, 99777
names[BLOCK], names[BLOCK_PASSIVE], names[BLOCK_OTHER] = "Maîtrise du blocage", "Maîtrise du blocage", "Maîtrise du blocage"
local playerAuras, aurasHidden = {}, false
-- numéros d'instance de tes buffs (lisibles même quand le jeu cache les auras) : [numéro] = nombre d'applications
local instances, idsSecret = {}, false
def("C_UnitAuras", {
    GetUnitAuraInstanceIDs = function(unit, filter)
        local list = {}
        for id in pairs(instances) do list[#list + 1] = idsSecret and secret() or id end
        if not idsSecret then table.sort(list) end
        return list
    end,
    GetPlayerAuraBySpellID = function(id)
        if aurasHidden then return nil end
        return playerAuras[id]
    end,
    GetAuraDataBySpellName = function(unit, name)
        if aurasHidden then return nil end
        for id, a in pairs(playerAuras) do
            if names[id] == name then return a end
        end
        return nil
    end,
})
def("C_Secrets", { ShouldSpellAuraBeSecret = function() return aurasHidden end })
local bindings = {
    ACTIONBUTTON3 = "3", ACTIONBUTTON5 = "SHIFT-5", MULTIACTIONBAR1BUTTON1 = "BUTTON4", ACTIONBUTTON9 = "CTRL-NUMPAD1",
    ACTIONBUTTON10 = "ALT-SHIFT-E",
}
def("GetBindingKey", function(command) return bindings[command] end)
def("ActionButtonUtil", { ActionBarButtonNames = { "ActionButton", "MultiBarBottomLeftButton" } })
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.action, b.bindingAction, b.commandName = i, "ACTIONBUTTON" .. i, "ACTIONBUTTON" .. i
    local m = CreateFrame("CheckButton", "MultiBarBottomLeftButton" .. i, UIParent)
    m.action, m.bindingAction, m.commandName = 60 + i, "MULTIACTIONBAR1BUTTON" .. i, "MULTIACTIONBAR1BUTTON" .. i
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
def("PlatyplusDB", { powerPlayer = false, spellCost = false, hud = false, swingBar = false })
M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Resources.lua", "Procs.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.3)

local P = ns.Procs
local F = P.frames or {}
local root, mover = F.root, F.mover
local function strip(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function alerts() return P.order end
local function keyOf(f) return strip(S(f.key).text) end
local function nameOf(f) return S(f.name).text end
local function update(after)             -- le jeu signale un changement d'état, puis le temps passe
    M.fireEvent("ACTION_USABLE_CHANGED", {})
    M.advance(after or 0.2)
end

section("texte des touches")
local K = P.KeyText
check(K("3") == "3" and K("SHIFT-5") == "Maj+5" and K("BUTTON4") == "Souris 4" and K("CTRL-NUMPAD1") == "Ctrl+Pavé 1",
    "3 / Maj+5 / Souris 4 / Ctrl+Pavé 1")
check(K("ALT-SHIFT-E") == "Alt+Maj+E" and K("MOUSEWHEELUP") == "Molette haut" and K("SHIFT--") == "Maj+-"
    and K("NUMPADPLUS") == "Pavé +" and K("F5") == "F5", "Alt+Maj+E / Molette haut / Maj+- / Pavé + / F5")
check(K(nil) == nil and K("") == nil, "pas de touche : rien")

section("rien d'utilisable")
check(root and P.Collect and #P:Collect() == 0, "aucun sort à annoncer")
check(not S(root).shown and S(root).scripts.OnUpdate == nil, "alerte cachée, aucune boucle OnUpdate")
usable[7] = true
update()
check(#alerts() == 0, "Frappe héroïque utilisable : pas un sort réactif, pas d'alerte")

section("Fulgurance")
usable[3] = true
update(0.05)
local a = alerts()[1]
check(#alerts() == 1 and a and nameOf(a) == "Fulgurance" and keyOf(a) == "3", "la cible esquive : « Fulgurance », touche « 3 »")
check(S(root).shown and S(root).scripts.OnUpdate ~= nil, "alerte affichée, animée")
check(a and S(a.icon).texture == 1000 + OVERPOWER, "icône du bouton")
check(a and S(a).alpha < 1, "elle apparaît en fondu...")
local s0, flash0, maxScale = a and S(a.body).scale or 1, a and S(a.flash).alpha or 0, 0
for _ = 1, 8 do
    M.advance(0.05)
    maxScale = math.max(maxScale, a and S(a.body).scale or 0)
end
check(a and S(a).alpha == 1, "... puis reste bien visible")
check(s0 < 0.5 and maxScale > 1.05 and a and S(a.body).scale == 1,
    ("elle jaillit : %d %% -> %d %% -> 100 %%"):format(math.floor(s0 * 100 + 0.5), math.floor(maxScale * 100 + 0.5)))
check(flash0 > 0.5 and a and S(a.flash).alpha == 0, "éclair blanc à l'apparition, éteint ensuite")
local keyFont = a and S(a.key).fontSize
check(keyFont and keyFont >= 18, "touche écrite en gros (" .. tostring(keyFont) .. ")")

-- battement : ondes, halo, pastille de la touche ; reflet sur l'icône
local ringMax, ringBig, pillMax, keyGold, shineMax, glowMin, glowMax = 0, 0, 1, false, 0, 9, 0
local shineMin, shineMaxX = 999, -999
for _ = 1, 50 do
    M.advance(0.05)
    for _, r in ipairs(a.rings) do
        ringMax = math.max(ringMax, S(r).alpha)
        if S(r).alpha > 0 then ringBig = math.max(ringBig, S(r).w) end
    end
    pillMax = math.max(pillMax, S(a.pill).scale)
    local c = S(a.key).textColor
    if c and c[3] < 0.6 then keyGold = true end
    if a.shine and S(a.shine).alpha > 0 then
        shineMax = math.max(shineMax, S(a.shine).alpha)
        local sx = select(4, a.shine:GetPoint(1))
        shineMin, shineMaxX = math.min(shineMin, sx), math.max(shineMaxX, sx)
    end
    glowMin, glowMax = math.min(glowMin, S(a.glow).alpha), math.max(glowMax, S(a.glow).alpha)
end
check(ringMax > 0.5 and ringBig > 52 + 20, ("ondes dorées qui partent de l'icône (jusqu'à %d px)"):format(ringBig))
check(glowMax - glowMin > 0.3, "le halo bat : il s'allume puis s'éteint doucement")
check(pillMax > 1.1 and keyGold, ("la touche gonfle (%d %%) et vire à l'or à chaque battement"):format(math.floor(pillMax * 100 + 0.5)))
check(a.shine and shineMax > 0.5 and shineMaxX - shineMin > 52, "un reflet balaie l'icône de gauche à droite")
check(#M.errors == 0, "aucune erreur pendant l'animation")

usable[3] = false
update(0.15)
check(#alerts() == 0 and P.dying[1] == a and S(a.body).scale > 1 and S(a).alpha < 1,
    "plus utilisable : « pouf », elle grossit en s'effaçant")
M.advance(0.3)
check(#P.dying == 0 and not S(root).shown and S(root).scripts.OnUpdate == nil, "puis disparaît, la boucle s'arrête")

usable[3] = true
update()
local back = alerts()[1]
usable[3] = false
update(0.1)
usable[3] = true
update(0.1)
check(alerts()[1] == back and #P.dying == 0 and S(back.body).scale >= 1, "redevient utilisable pendant sa sortie : elle reste, sans rejaillir")
usable[3] = false
update(0.4)

usable[3] = true
update()
usable[3] = false                       -- sans aucun événement : le contrôle régulier la retire quand même
M.advance(0.4)
check(#alerts() == 0, "un événement manque : l'alerte ne traîne pas (contrôle 4 fois par seconde)")

section("recharge")
usable[3] = true
cooldowns[3] = { startTime = M.time, duration = 5, isEnabled = true, isActive = true, modRate = 1 }
update()
check(#alerts() == 0, "en recharge (5 s) : pas d'alerte")
cooldowns[3] = { startTime = M.time, duration = 1.5, isEnabled = true, isActive = true, modRate = 1 }
update()
check(#alerts() == 1, "temps global seulement : alerte")
cooldowns[3] = { startTime = secret(), duration = secret(), isEnabled = true, isActive = true, modRate = 1 }
update()
check(#alerts() == 1 and #M.errors == 0, "recharge secrète sans isOnGCD : on ne sait pas, alerte, sans erreur")
-- en jeu (Forever) : début et durée secrets en combat, mais isActive et isOnGCD jamais secrets
cooldowns[3] = { startTime = secret(), duration = secret(), isEnabled = true, isActive = true, isOnGCD = false, modRate = 1 }
update()
check(#alerts() == 0 and #M.errors == 0, "recharge secrète, active, pas le temps global : pas d'alerte (retour du joueur)")
cooldowns[3] = { startTime = secret(), duration = secret(), isEnabled = true, isActive = true, isOnGCD = true, modRate = 1 }
update()
check(#alerts() == 1, "recharge secrète mais seulement le temps global : alerte")
cooldowns[3] = { startTime = secret(), duration = secret(), isEnabled = true, isActive = false, isOnGCD = false, modRate = 1 }
update()
check(#alerts() == 1, "recharge secrète inactive : alerte")
cooldowns[3] = nil
M.advance(0.6)

section("recharge : objet durée (marche en combat)")
cooldowns[3] = { startTime = secret(), duration = secret(), isEnabled = true, isActive = true, modRate = 1 }
durationLeft[3] = 0
update()
check(#alerts() == 1 and #M.errors == 0, "objet durée : pas en recharge -> alerte")
durationLeft[3] = 4
update()
check(#alerts() == 0 and #M.errors == 0, "recharge secrète mais objet durée actif : pas d'alerte")
durationLeft[3] = 0
M.advance(1.2)
check(#alerts() == 1, "recharge finie sans aucun événement : l'alerte revient toute seule")
-- sort qui brille (proc signalé par le jeu) mais en recharge
usable[3] = false
glowing[PROC] = true
local procAction
for a, s in pairs(slots) do if s[2] == PROC then procAction = a end end
if procAction then
    durationLeft[procAction] = 3
    update()
    local shown = false
    for _, f in ipairs(alerts()) do if f.spellID == PROC then shown = true end end
    check(not shown, "sort qui brille mais en recharge : pas d'alerte")
    durationLeft[procAction] = 0
    M.advance(1.2)
    shown = false
    for _, f in ipairs(alerts()) do if f.spellID == PROC then shown = true end end
    check(shown, "il redevient lançable : l'alerte apparaît")
    durationLeft[procAction] = nil
end
glowing[PROC] = nil
durationLeft[3] = nil
cooldowns[3] = nil
usable[3] = true
update()
M.advance(0.6)                          -- tout se pose avant la suite

section("plusieurs alertes")
usable[5] = true
usable[61] = true
local before = alerts()[1] and alerts()[1].cx
update(0.05)
local list = alerts()
local first = list[1]
check(first and before and first.cx ~= before and first.cx ~= first.tx, "Fulgurance glisse vers sa nouvelle place...")
M.advance(0.4)
check(first and first.cx == first.tx and select(4, first:GetPoint(1)) == first.tx, "... et s'y pose")
check(#list == 3 and keyOf(list[1]) == "3" and keyOf(list[2]) == "Maj+5" and keyOf(list[3]) == "Souris 4",
    "Fulgurance « 3 », Exécution « Maj+5 », Vengeance « Souris 4 » (barre en bas)")
local function x(f) return f.tx end
local left, right = #list == 3 and x(list[1]) - list[1].width / 2, #list == 3 and x(list[3]) + list[3].width / 2
check(#list == 3 and math.abs(left + right) < 0.01 and x(list[1]) < x(list[2]) and x(list[2]) < x(list[3])
    and x(list[2]) - x(list[1]) >= (list[1].width + list[2].width) / 2, "côte à côte sans se chevaucher, centrées")
usable[2] = true
update()
check(#alerts() == 3 and keyOf(alerts()[1]) == "3", "Fulgurance sur deux boutons : une seule alerte, celle qui a une touche")
usable[8] = true
update()
check(#alerts() == 3, "4 sorts prêts : 3 alertes au plus")
usable[3], usable[2], usable[5], usable[61] = false, false, false, false
update()
a = alerts()[1]
check(#alerts() == 1 and a and nameOf(a) == "Riposte" and keyOf(a) == "aucune touche", "Riposte dans une macro sans touche : « aucune touche »")
usable[8] = false
usable[10] = true
update()
a = alerts()[1]
check(a and keyOf(a) == "Alt+Maj+E", "autre numéro de Fulgurance : reconnu par son nom")
usable[10] = false
update()

section("lueur du jeu")
M.fireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", PROC)
M.advance(0.2)
a = alerts()[1]
check(#alerts() == 1 and a and nameOf(a) == "Idées claires" and keyOf(a) == "Ctrl+Pavé 1", "sort qui brille : alerte « Ctrl+Pavé 1 »")
check(a and S(a.icon).vertex and S(a.icon).vertex[1] < 1, "pas encore utilisable : icône assombrie")
M.fireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", PROC)
M.advance(0.2)
check(#alerts() == 0, "la lueur s'éteint : l'alerte aussi")
glowing[PROC] = true
update()
check(#alerts() == 1, "déjà en train de briller (après un /reload) : retrouvé par IsSpellOverlayed")
glowing[PROC] = nil
update()

section("valeurs secrètes")
usable[3] = "secret"
update()
check(#alerts() == 0 and #M.errors == 0, "état utilisable secret : pas d'alerte, pas d'erreur")
M.fireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", secret())
M.advance(0.2)
check(#M.errors == 0, "lueur avec un numéro secret : ignorée sans erreur")
usable[3] = false

section("réglages")
usable[3] = true
update()
check(#alerts() == 1, "Fulgurance prête")
ns:Set("procAlert", false)
M.advance(0.1)
check(#alerts() == 0 and not S(root).shown, "réglage coupé : rien")
check(not S(F.events).events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW, "réglage coupé : plus d'événements")
ns:Set("procAlert", true)
M.advance(0.1)
check(#alerts() == 1, "réglage remis : l'alerte revient")
ns:Set("procScale", 1.5)
check(S(root).scale == 1.5, "taille 150 %")
ns:Set("procScale", 1)
usable[3] = false
update()

section("aperçu, déplacement")
P:Preview()
M.advance(0.1)
a = alerts()[1]
check(#alerts() == 1 and a and nameOf(a) == "Fulgurance" and keyOf(a) == "3", "aperçu : un de tes sorts réactifs avec sa vraie touche")
M.advance(5.2)
check(#alerts() == 0, "fin de l'aperçu")
P:ToggleMove()
M.advance(0.1)
check(ns.db.procLocked == false and S(mover).shown and #alerts() == 1, "déverrouillée : cadre à glisser et alerte d'exemple")
S(root).center = { 683 + 40, 384 - 150 }
M.fire(mover, "OnDragStop")
check(ns.db.procX == 40 and ns.db.procY == -150, "glissée : position enregistrée (40, -150)")
M.fire(mover, "OnMouseUp", "RightButton")
M.advance(0.4)
check(ns.db.procLocked == true and not S(mover).shown and #alerts() == 0, "clic droit : verrouillée, plus rien à l'écran")
P:ResetPosition()
check(ns.db.procX == 0 and ns.db.procY == -115, "remise en place")

section("Ivresse de la victoire (numéros de Forever)")
check(P.IsReactive(402927) and P.IsReactive(403434), "402927 et 403434 (version « rune ») sont des sorts réactifs")
local savedUsable = {}
for k, v in pairs(usable) do savedUsable[k] = v; usable[k] = nil end
names[402927] = "Ivresse de la victoire"
slots[11] = { "spell", 402927 }
bindings.ACTIONBUTTON11 = "4"
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 11)
M.advance(0.6)
check(#alerts() == 0, "rien de tué : pas d'alerte")
usable[11] = true                       -- un ennemi vient de mourir : le jeu la rend utilisable
update()
local vr = alerts()[1]
check(vr and vr.spellID == 402927 and nameOf(vr) == "Ivresse de la victoire" and keyOf(vr) == "4",
    "ennemi tué : alerte « Ivresse de la victoire » sur « 4 »")
cooldowns[11] = { startTime = secret(), duration = secret(), isEnabled = true, isActive = true, isOnGCD = false, modRate = 1 }
update()
check(#alerts() == 0, "en recharge en combat (valeurs secrètes) : pas d'alerte")
-- retour du joueur (2026-11-07) : « des fois ça me dit que je peux faire Ivresse de la victoire pourtant il est CD » :
-- en combat la recharge est secrète et isOnGCD peut manquer ; on retient ton lancer (lisible) et ses 30 s
cooldowns[11] = { startTime = secret(), duration = secret(), isEnabled = true, isActive = true, modRate = 1 }
update()
check(#alerts() == 1, "recharge secrète sans isOnGCD et aucun lancer connu : alerte (on ne sait pas)")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", 402927)
M.advance(0.3)
check(#alerts() == 0 or alerts()[1].spellID ~= 402927, "tu lances Ivresse de la victoire : l'alerte part aussitôt")
M.advance(10)
update()
check(#alerts() == 0, "un autre ennemi tué 10 s plus tard, sort encore en recharge (30 s) : pas d'alerte")
check(P.CastCooldownLeft(402927) and P.CastCooldownLeft(402927) > 18, "recharge connue d'après ton lancer : ~19 s restantes")
M.advance(20)
check(#alerts() == 1 and alerts()[1].spellID == 402927, "30 s après ton lancer : l'alerte revient toute seule")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-guid", 402927)
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", secret())
M.advance(0.3)
check(#alerts() == 1 and #M.errors == 0, "lancer d'un autre ou numéro secret : ignorés")
cooldowns[11] = nil
usable[11] = nil
slots[11], bindings.ACTIONBUTTON11 = nil, nil
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 11)
for k, v in pairs(savedUsable) do usable[k] = v end
update(0.6)

section("icône de Maîtrise du blocage")
for k in pairs(usable) do usable[k] = nil end
update(0.6)
local chip = F.chip
local function chipX() return select(4, chip:GetPoint(1)) end
-- (0,45 s : l'icône part en s'effaçant, 0,28 s)
local function auraChanged() M.fireEvent("UNIT_AURA", "player", {}); M.advance(0.45) end
check(chip and not S(chip).shown and not S(root).shown, "pas de buff : rien à l'écran")
check(S(F.events).events.UNIT_AURA and S(F.events).events.UNIT_SPELLCAST_SUCCEEDED and S(F.events).events.UNIT_COMBAT,
    "événements UNIT_AURA, lancer et coups reçus (blocages), pour toi")

-- buff lisible (hors combat)
playerAuras[BLOCK] = { applications = 2, duration = 6 }
auraChanged()
check(S(chip).shown and S(root).shown, "buff actif : l'icône s'affiche (le cadre aussi, tout seul)")
check(S(root).scripts.OnUpdate == nil, "immobile : aucune boucle OnUpdate")
check(chipX() == 0 and #alerts() == 0, "sans alerte : seule, au centre")
check(S(chip.icon).texture == 2000 + BLOCK, "icône du sort")
local function pipsOn()
    local n = 0
    for _, p in ipairs(chip.pips) do if S(p).shown and S(p).vertex and S(p).vertex[1] == ns.THEME.accent[1] then n = n + 1 end end
    return n
end
local function pipsShown() local n = 0 for _, p in ipairs(chip.pips) do if S(p).shown then n = n + 1 end end return n end
check(S(chip.badge).shown and S(chip.count).text == "2" and pipsShown() == 2 and pipsOn() == 2,
    "charges restantes : « 2 » dans la pastille, jauge de 2 barrettes pleines")
playerAuras[BLOCK] = { applications = 1, duration = 6 }
auraChanged()
check(S(chip).shown and S(chip.count).text == "1" and pipsOn() == 1, "une charge restante : toujours là, « 1 », une barrette éteinte")

-- à côté d'une alerte de proc : à droite de la rangée, glisse quand elle change, revient au centre quand elle part
usable[3] = true
update(0.05)
a = alerts()[1]
check(#alerts() == 1 and S(chip).shown and S(root).scripts.OnUpdate ~= nil, "Fulgurance + icône du buff")
M.advance(0.5)
check(chip.cx == chip.tx and chipX() == chip.tx and chip.tx > 0, "l'icône s'est posée à droite")
check(chip.tx - chip.width / 2 >= a.tx + a.width / 2 + 10, "sans chevaucher l'alerte (écart net)")
usable[5] = true
update(0.6)
local rightmost = alerts()[#alerts()]
check(#alerts() == 2 and chip.tx - chip.width / 2 >= rightmost.tx + rightmost.width / 2 + 10, "deux alertes : toujours à droite de la dernière")
usable[3], usable[5] = false, false
update(0.7)
check(#alerts() == 0 and #P.dying == 0 and chipX() == 0 and S(chip).shown and S(root).shown and S(root).scripts.OnUpdate == nil,
    "plus d'alerte : elle revient au centre, seule, sans boucle")

-- aura trouvée par le nom (autre numéro), talent passif de même nom ignoré
playerAuras[BLOCK] = nil
playerAuras[BLOCK_PASSIVE] = { applications = 0, duration = 0 }
auraChanged()
check(not S(chip).shown and not S(root).shown, "talent passif du même nom (sans durée) : pas ton buff, rien")
playerAuras[BLOCK_PASSIVE] = nil
playerAuras[BLOCK_OTHER] = { applications = 3, duration = 5 }
auraChanged()
check(S(chip).shown, "autre numéro du sort : reconnu par son nom")
playerAuras[BLOCK_OTHER] = nil
auraChanged()
check(not S(chip).shown and not S(root).shown, "buff fini : tout disparaît")
playerAuras[BLOCK] = { applications = secret(), duration = secret() }
auraChanged()
check(S(chip).shown and #M.errors == 0, "aura aux valeurs secrètes : présente, sans erreur")
playerAuras[BLOCK] = nil
auraChanged()
check(not S(chip).shown, "fini")

-- le jeu cache les auras (en combat) et ne donne pas de numéros d'instance : on ne sait que ton propre lancer
aurasHidden = true
idsSecret = true
instances = { [1] = 0 }
auraChanged()
check(not S(chip).shown, "auras cachées, sort pas lancé : rien")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-guid", BLOCK)
M.advance(0.2)
check(not S(chip).shown, "le sort d'un autre : ignoré")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", 78)
M.advance(0.2)
check(not S(chip).shown, "un autre sort de toi : ignoré")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", secret())
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", secret(), "Cast-guid", BLOCK)
M.advance(0.2)
check(not S(chip).shown and #M.errors == 0, "numéro ou unité secrets : ignorés sans erreur")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
M.advance(0.2)
check(S(chip).shown, "tu lances le sort, aura cachée : l'icône apparaît")
M.advance(1)
check(S(chip).shown, "elle reste tant que le buff dure")
M.advance(6.5)
check(not S(chip).shown and not S(root).shown, "buff fini (7 s) : elle s'efface toute seule, sans aucun événement")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", 12169)    -- l'autre numéro, reconnu aussi
M.advance(0.2)
check(S(chip).shown, "autre numéro lancé : l'icône aussi")
check(P:BlockDetails():find("illisibles", 1, true), "diagnostic : numéros illisibles")
idsSecret = false
instances = {}
aurasHidden = false
auraChanged()
check(not S(chip).shown, "auras lisibles de nouveau et aucune aura : plus de buff, plus d'icône")

-- réglage
playerAuras[BLOCK] = { applications = 2, duration = 6 }
auraChanged()
check(S(chip).shown, "buff actif")
ns:Set("procBlock", false)
M.advance(0.45)
check(not S(chip).shown and not S(root).shown and not S(F.events).events.UNIT_AURA
    and not S(F.events).events.UNIT_COMBAT, "réglage coupé : rien, plus d'événements de buff ni de blocage")
check(S(F.events).events.UNIT_SPELLCAST_SUCCEEDED, "tes lancers restent écoutés pour les alertes (recharge d'Ivresse de la victoire)")
ns:Set("procBlock", true)
M.advance(0.2)
check(S(chip).shown and S(F.events).events.UNIT_AURA, "réglage remis : l'icône revient")
ns:Set("procAlert", false)
M.advance(0.2)
check(S(chip).shown and S(root).shown, "alertes coupées : l'icône reste (réglage à part)")
ns:Set("procAlert", true)
M.advance(0.2)
ns:Set("procScale", 1.5)
check(S(root).scale == 1.5, "elle suit la taille des alertes (c'est un enfant du même cadre)")
ns:Set("procScale", 1)
playerAuras[BLOCK] = nil
auraChanged()

-- aperçu et déplacement : l'icône est montrée même sans le buff
P:Preview()
M.advance(0.2)
check(S(chip).shown and S(root).shown, "aperçu : l'icône, même sans le buff")
M.advance(5.2)
check(not S(chip).shown and not S(root).shown, "fin de l'aperçu : elle part avec l'alerte")
P:ToggleMove()
M.advance(0.3)
check(S(chip).shown and #alerts() == 1 and chip.tx > 0, "déverrouillée : l'alerte d'exemple et l'icône à sa droite")
P:ToggleMove()
M.advance(0.5)
check(not S(chip).shown and #alerts() == 0, "verrouillée : plus rien")

-- /pp proc : une ligne d'état
playerAuras[BLOCK] = { applications = 2, duration = 6 }
check(strip(P:BlockStatus()):find("Maîtrise du blocage : active", 1, true), "état : active")
playerAuras[BLOCK] = nil
auraChanged()
check(P:BlockStatus():find("pas active", 1, true), "état : pas active")
check(#M.errors == 0, "aucune erreur dans toute cette partie")

section("icône cachée : le buff est suivi par son numéro d'instance (en combat le jeu cache tes buffs)")
M.advance(2)                                    -- la fenêtre de recherche du lancer précédent est close
aurasHidden = true                              -- en combat le jeu cache tes auras
instances = { [101] = 0, [102] = 3 }            -- tes autres buffs
auraChanged()
check(not S(chip).shown and not S(root).shown, "buffs d'avant : pas le tien, rien")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
M.advance(0.2)
check(S(chip).shown, "tu cliques : l'icône apparaît tout de suite")
instances[240] = 2                              -- le jeu ajoute le buff juste après ton lancer
auraChanged()
M.advance(0.3)                                  -- on laisse passer l'instant de choix (0,35 s après le lancer)
check(S(chip).shown and P:BlockDetails():find("n° 240", 1, true), "le nouveau buff est le tien : suivi par son numéro")
instances[240] = 1                              -- un blocage de fait : même numéro
auraChanged()
check(S(chip).shown, "un blocage de fait : toujours là")
instances[260] = 5                              -- un autre buff arrive pendant que tu bloques
auraChanged()
check(S(chip).shown and P:BlockDetails():find("n° 240", 1, true), "un autre buff qui arrive ensuite n'est pas confondu")
local t0 = M.time
instances[240] = nil                            -- dernier blocage consommé : le buff disparaît
auraChanged()
check(not S(chip).shown and not S(root).shown and M.time - t0 < 0.5,
    "plus de buff : l'icône part tout de suite (sans attendre la fin du buff)")
M.advance(8)
check(not S(chip).shown, "et ne revient pas")

-- charges comptées par les coups bloqués (retour du joueur : l'icône restait jusqu'à la fin du buff alors que toutes
-- les charges étaient parties ; il veut voir les charges restantes et une animation à chaque charge en moins)
instances = { [101] = 0, [102] = 3 }
auraChanged()
M.advance(2)
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
instances[250] = 2
auraChanged()
check(S(chip).shown and S(chip.count).text == "2" and pipsOn() == 2, "en combat, tu lances : 2 charges (ProcCharges du sort)")
M.fireEvent("UNIT_COMBAT", "player", "WOUND", "CRITICAL", secret(), 1)
M.fireEvent("UNIT_COMBAT", "party1", "BLOCK", "", 0, 1)
M.fireEvent("UNIT_COMBAT", "player", secret(), secret(), secret(), 1)
M.advance(0.1)
check(S(chip.count).text == "2" and #M.errors == 0, "coup non bloqué, coup d'un autre, valeurs secrètes : rien ne change")
M.fireEvent("UNIT_COMBAT", "player", "WOUND", "BLOCK_REDUCED", secret(), 1)    -- blocage partiel
M.advance(0.1)
check(S(chip.count).text == "1" and chip.loseAt and S(chip).scripts.OnUpdate ~= nil, "blocage partiel : « 1 », l'animation part")
check(S(chip.float).alpha > 0 and S(chip.ring).alpha > 0, "un « -1 » s'envole et une onde part de l'icône")
check(chip.body and S(chip.body).scale ~= 1, "l'icône encaisse le coup (elle se tasse puis rebondit)")
M.advance(0.7)
check(S(chip).scripts.OnUpdate == nil and S(chip.body).scale == 1 and pipsOn() == 1, "animation finie : boucle arrêtée, une barrette éteinte")
t0 = M.time
M.fireEvent("UNIT_COMBAT", "player", "BLOCK", "", 0, 1)                        -- coup bloqué en entier
M.advance(0.7)
check(not S(chip).shown and not S(root).shown and M.time - t0 < 1,
    "dernière charge partie : l'icône s'en va, même si le jeu n'a pas encore retiré le buff")
auraChanged()
M.advance(2)
check(not S(chip).shown, "et ne revient pas tant que tu ne relances pas")
M.fireEvent("UNIT_COMBAT", "player", "BLOCK", "", 0, 1)
M.advance(0.2)
check(not S(chip).shown and #M.errors == 0, "blocage sans buff : rien")
instances[250] = nil
auraChanged()
-- le maximum lu sur l'aura (talents) est retenu pour les lancers suivants
aurasHidden = false
playerAuras[BLOCK] = { applications = 3, duration = 7 }
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
auraChanged()
check(S(chip.count).text == "3" and pipsShown() == 3 and ns.db.procBlockMax == 3, "aura lisible : 3 charges, retenu")
playerAuras[BLOCK] = nil
auraChanged()
aurasHidden = true
M.advance(2)
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
M.advance(0.5)
check(S(chip).shown and S(chip.count).text == "3", "lancer suivant, aura cachée : 3 charges")
ns.db.procBlockMax = nil
M.advance(12)
instances = { [101] = 0, [102] = 3 }
auraChanged()

-- relancer pendant que le buff dure : même numéro, on garde le suivi
instances = { [101] = 0, [102] = 3 }
auraChanged()
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
instances[300] = 2
auraChanged()
M.advance(0.3)
check(S(chip).shown and P:BlockDetails():find("n° 300", 1, true), "premier lancer : suivi")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
M.advance(0.6)
check(S(chip).shown and P:BlockDetails():find("n° 300", 1, true), "tu relances : le même buff (même numéro) reste suivi")
instances[300] = nil
instances[310] = 2                              -- le jeu a remplacé le buff par un nouveau numéro
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
auraChanged()
M.advance(0.3)
check(S(chip).shown and P:BlockDetails():find("n° 310", 1, true), "remplacé par un nouveau numéro : retrouvé")
instances[310] = nil
auraChanged()
check(not S(chip).shown, "fini : rien")
check(P:BlockDetails():find("lisibles", 1, true), "diagnostic : numéros lisibles")

-- le jeu ajoute le buff un instant AVANT de signaler le lancer : retrouvé quand même (point de départ = liste d'il y a 0,4 s)
M.advance(2)
instances = { [101] = 0 }
auraChanged()
M.advance(1)
instances[500] = 2
auraChanged()
check(not S(chip).shown, "buff apparu mais lancer pas encore signalé : rien")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
M.advance(0.6)
check(S(chip).shown and P:BlockDetails():find("n° 500", 1, true), "le lancer est signalé juste après le buff : retrouvé quand même")
instances[500] = nil
auraChanged()
check(not S(chip).shown, "fini : rien")

-- un autre buff apparu juste avant ton lancer : le plus récent des nouveaux est le tien
M.advance(2)
instances = { [101] = 0 }
auraChanged()
M.advance(1)
instances[600] = 1                              -- autre buff, gagné un instant avant de cliquer
auraChanged()
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
instances[610] = 2                              -- le buff de blocage arrive juste après
auraChanged()
M.advance(0.3)
check(S(chip).shown and P:BlockDetails():find("n° 610", 1, true) and P:BlockDetails():find("2 candidats", 1, true),
    "deux nouveaux buffs : le plus récent est celui du blocage")
instances[610] = nil
auraChanged()
check(not S(chip).shown, "il part avec son numéro, l'autre buff reste")
instances[600] = nil
auraChanged()

-- garde-fou : un numéro suivi qui ne disparaît jamais (mauvais buff) n'est pas gardé plus de 3 s après la durée du buff
M.advance(2)
instances = { [101] = 0 }
auraChanged()
M.advance(1)
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
instances[700] = 1                              -- ce buff-là restera : le mauvais
M.advance(0.5)
check(S(chip).shown and P:BlockDetails():find("n° 700", 1, true), "buff suivi")
M.advance(8.5)                                  -- 9 s après le lancer : 7 s de buff + 3 s de grâce pas encore écoulées
check(S(chip).shown, "numéro toujours là passé la durée : encore là pendant le délai de grâce")
M.advance(1.5)                                  -- 10,5 s après le lancer, sans aucun événement
check(not S(chip).shown and not S(root).shown, "garde-fou : plus de 10 s après le lancer, elle part même si le numéro reste")
instances = {}
auraChanged()

-- journal /pp proc debug
M.printed = {}
SlashCmdList["PLATYPLUS"]("proc debug")
check(strip(table.concat(M.printed, "\n")):find("journal du blocage : ON", 1, true), "/pp proc debug : journal allumé")
instances = { [101] = 0 }
auraChanged()
M.printed = {}
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
instances[800] = 2
auraChanged()
M.advance(0.3)
local log = strip(table.concat(M.printed, "\n"))
check(log:find("[blocage]", 1, true) and log:find("lancer repéré", 1, true) and log:find("buff retenu : n° 800", 1, true),
    "le journal dit le lancer repéré et le buff retenu")
instances[800] = nil
auraChanged()
log = strip(table.concat(M.printed, "\n"))
check(log:find("a disparu de ta liste", 1, true), "le journal dit la disparition")
M.printed = {}
SlashCmdList["PLATYPLUS"]("proc debug")
check(strip(table.concat(M.printed, "\n")):find("journal du blocage : OFF", 1, true), "journal coupé")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", BLOCK)
M.advance(0.3)
check(not strip(table.concat(M.printed, "\n")):find("[blocage]", 1, true), "journal coupé : plus rien d'écrit")
M.advance(12)
instances = {}
aurasHidden = false
auraChanged()
check(#M.errors == 0, "aucune erreur dans cette partie")

section("commande /pp proc")
M.printed = {}
SlashCmdList["PLATYPLUS"]("proc")
local printed = strip(table.concat(M.printed, "\n"))
check(printed:find("Fulgurance : touche 3", 1, true) and printed:find("Exécution : touche Maj+5", 1, true)
    and printed:find("Riposte : aucune touche", 1, true), "liste : « Fulgurance : touche 3 », « Riposte : aucune touche »...")
M.advance(0.1)
check(#alerts() == 1, "et montre l'aperçu")
M.advance(5.2)
SlashCmdList["PLATYPLUS"]("proc off")
check(ns.db.procAlert == false, "/pp proc off")
SlashCmdList["PLATYPLUS"]("proc on")
check(ns.db.procAlert == true, "/pp proc on")

section("aucun sort réactif sur les barres")
for _, s in pairs({ 2, 3, 5, 8, 10, 61 }) do slots[s] = nil end
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 3)
M.advance(0.2)
M.printed = {}
SlashCmdList["PLATYPLUS"]("proc")
M.advance(0.1)
a = alerts()[1]
check(table.concat(M.printed, "\n"):find("aucun sort surveillé", 1, true), "/pp proc : « aucun sort surveillé sur tes barres »")
check(a and nameOf(a) == "Fulgurance" and keyOf(a) == "3" and S(a.icon).texture == 2000 + OVERPOWER,
    "aperçu d'exemple : Fulgurance sur « 3 »")
M.advance(5.2)

---------------------------------------------------------------------------
-- Toutes classes, réglages de sorts surveillés et d'affichage
---------------------------------------------------------------------------
section("réglages par défaut (guerrier : comportement d'origine)")
local classToken = "WARRIOR"
def("UnitClass", function() return "Guerrier", classToken, 1 end)
check(ns.db.procReactive == true and ns.db.procGlow == true, "sorts réactifs et brillance : actifs")
check(type(ns.db.procExtra) == "table" and next(ns.db.procExtra) == nil
    and type(ns.db.procIgnore) == "table" and next(ns.db.procIgnore) == nil, "listes ajoutés / ignorés : vides")
check(ns.db.procMax == 3 and ns.db.procShowKey == true and ns.db.procShowName == true and ns.db.procAnim == "vif"
    and ns.db.procSound == false and ns.db.procOpacity == 1, "affichage : 3 alertes, touche, nom, animation vive, sans son, opacité 100 %")
local function clearState()
    for _, t in ipairs({ usable, lacking, cooldowns, glowing, durationLeft }) do for k in pairs(t) do t[k] = nil end end
end
local function setSlots(map)
    for k in pairs(slots) do slots[k] = nil end
    for k, v in pairs(map) do slots[k] = v end
    M.fireEvent("ACTIONBAR_SLOT_CHANGED", 3)
    M.advance(0.3)
end
clearState()
setSlots({ [3] = { "spell", OVERPOWER }, [5] = { "spell", EXECUTE }, [61] = { "spell", REVENGE } })
usable[3], usable[5], usable[61] = true, true, true
update(0.5)
check(#alerts() == 3 and keyOf(alerts()[1]) == "3" and keyOf(alerts()[2]) == "Maj+5" and keyOf(alerts()[3]) == "Souris 4",
    "guerrier : Fulgurance, Exécution et Vengeance, comme avant")
check(P.AlertHeight() == 85, "hauteur d'origine : 85")

section("sorts réactifs de chaque classe")
local function classNames(token)
    classToken = token
    local out = {}
    for _, e in ipairs(P.ClassDefaults()) do out[#out + 1] = e.name end
    return table.concat(out, ", ")
end
check(classNames("WARRIOR") == "Fulgurance, Vengeance, Exécution, Ivresse de la victoire", "guerrier : " .. classNames("WARRIOR"))
check(classNames("ROGUE") == "Riposte", "voleur : Riposte")
check(classNames("HUNTER") == "Contre-attaque, Morsure de la mangouste, Ordre de tuer", "chasseur : " .. classNames("HUNTER"))
check(classNames("PALADIN") == "Marteau de courroux", "paladin : Marteau de courroux")
check(classNames("MAGE") == "" and classNames("PRIEST") == "" and classNames("DRUID") == "", "mage, prêtre, druide : aucun (brillance du jeu)")
local allKnown = true
for _, token in ipairs({ "WARRIOR", "ROGUE", "HUNTER", "PALADIN" }) do
    classToken = token
    for _, e in ipairs(P.ClassDefaults()) do if not P.REACTIVE[e.spellID] then allKnown = false end end
end
check(allKnown, "chaque sort de ClassDefaults est dans la liste des sorts réactifs")
classToken = "WARRIOR"
check(P.BASE_CD[409379] == 60, "Ordre de tuer : recharge de 60 s")
local others = { { RIPOSTE, "Riposte" }, { 19306, "Contre-attaque" }, { 1495, "Morsure de la mangouste" },
    { 24239, "Marteau de courroux" }, { 409379, "Ordre de tuer" } }
for _, o in ipairs(others) do
    names[o[1]] = o[2]
    clearState()
    setSlots({ [3] = { "spell", o[1] } })
    usable[3] = true
    update(0.3)
    local a1 = alerts()[1]
    check(#alerts() == 1 and a1 and nameOf(a1) == o[2] and keyOf(a1) == "3", o[2] .. " : alerte avec sa touche")
end
names[409396] = "Ordre de tuer"
setSlots({ [3] = { "spell", 409396 } })
usable[3] = true
update(0.3)
check(#alerts() == 1, "autre numéro d'Ordre de tuer : reconnu par son nom")
M.printed = {}
SlashCmdList["PLATYPLUS"]("proc")
local txt = strip(table.concat(M.printed, "\n"))
check(txt:find("réactifs de ta classe", 1, true) and txt:find("Fulgurance, Vengeance, Exécution, Ivresse de la victoire", 1, true)
    and txt:find("ajoutés : aucun", 1, true) and txt:find("ignorés : aucun", 1, true), "/pp proc : sorts de ta classe, ajoutés, ignorés")
M.advance(5.2)

section("réactifs et brillance : interrupteurs")
clearState()
setSlots({ [3] = { "spell", OVERPOWER }, [9] = { "spell", PROC } })
usable[3] = true
glowing[PROC] = true
update(0.3)
check(#alerts() == 2, "Fulgurance + sort qui brille")
ns:Set("procReactive", false)
M.advance(0.3)
check(#alerts() == 1 and nameOf(alerts()[1]) == "Idées claires", "sorts réactifs coupés : il ne reste que celui qui brille")
ns:Set("procGlow", false)
M.advance(0.3)
check(#alerts() == 0, "brillance coupée aussi : rien")
ns:Set("procReactive", true)
M.advance(0.3)
check(#alerts() == 1 and nameOf(alerts()[1]) == "Fulgurance", "réactifs remis, brillance coupée : Fulgurance seule")
ns:Set("procGlow", true)
M.advance(0.3)
check(#alerts() == 2, "tout remis : deux alertes")

section("sorts ajoutés (procExtra)")
clearState()
setSlots({ [7] = { "spell", HEROIC } })
usable[7] = true
update(0.3)
check(#alerts() == 0, "Frappe héroïque n'est pas réactive : pas d'alerte")
ns:Set("procExtra", { [HEROIC] = true })
M.advance(0.3)
local ea = alerts()[1]
check(#alerts() == 1 and ea and nameOf(ea) == "Frappe héroïque", "sort ajouté, utilisable et hors recharge : alerte")
durationLeft[7] = 6
update(0.3)
check(#alerts() == 0, "sort ajouté en recharge : pas d'alerte")
durationLeft[7] = nil
update(0.3)
check(#alerts() == 1, "recharge finie : l'alerte revient")
usable[7] = false
update(0.3)
check(#alerts() == 0, "plus utilisable : l'alerte part")
usable[7] = true
update(0.3)
ns:Set("procExtra", {})
M.advance(0.3)
check(#alerts() == 0, "sort retiré de la liste : l'alerte part")

section("sorts ignorés (procIgnore)")
clearState()
setSlots({ [9] = { "spell", PROC }, [3] = { "spell", OVERPOWER }, [10] = { "spell", OVERPOWER_OTHER } })
glowing[PROC] = true
update(0.3)
check(#alerts() == 1 and nameOf(alerts()[1]) == "Idées claires", "sort qui brille : alerte")
ns:Set("procIgnore", { [PROC] = true })
M.advance(0.3)
check(#alerts() == 0, "sort ignoré : pas d'alerte même s'il brille")
names[12346] = "Idées claires"
ns:Set("procIgnore", { [12346] = true })
M.advance(0.3)
check(#alerts() == 0, "un autre rang (même nom) est ignoré aussi")
ns:Set("procIgnore", {})
M.advance(0.3)
check(#alerts() == 1, "liste vidée : l'alerte revient")
glowing[PROC] = nil
usable[3], usable[10] = true, true
ns:Set("procIgnore", { [OVERPOWER] = true })
update(0.3)
check(#alerts() == 0, "Fulgurance ignorée : l'autre numéro, de même nom, l'est aussi")
ns:Set("procExtra", { [OVERPOWER] = true })
M.advance(0.3)
check(#alerts() == 0, "ignoré l'emporte sur ajouté")
ns:Set("procIgnore", {})
ns:Set("procExtra", {})
usable[3], usable[10] = false, false
update(0.3)

section("nombre d'alertes (procMax)")
clearState()
setSlots({ [3] = { "spell", OVERPOWER }, [5] = { "spell", EXECUTE }, [61] = { "spell", REVENGE }, [8] = { "spell", RIPOSTE } })
usable[3], usable[5], usable[61], usable[8] = true, true, true, true
update(0.5)
check(#alerts() == 3, "défaut : 3 alertes sur 4 sorts prêts")
ns:Set("procMax", 2)
M.advance(0.4)
check(#alerts() == 2, "procMax = 2 : deux alertes")
ns:Set("procMax", 1)
M.advance(0.4)
check(#alerts() == 1, "procMax = 1 : une alerte")
ns:Set("procMax", 6)
M.advance(0.4)
check(#alerts() == 4, "procMax = 6 : les 4 sorts prêts")
ns:Set("procMax", 0)
M.advance(0.4)
check(#alerts() == 1, "procMax = 0 : borné à 1")
ns:Set("procMax", 3)
M.advance(0.4)

section("touche et nom : la hauteur suit")
local function relayout() M.advance(0.4) end
setSlots({ [3] = { "spell", OVERPOWER } })
usable[3], usable[5], usable[61], usable[8] = true, false, false, false
update(0.5)
a = alerts()[1]
local function nameY() return select(5, a.name:GetPoint(1)) end
check(P.AlertHeight() == 85 and S(root).h == 85 and S(a.pill).shown and S(a.name).shown and nameY() == -19,
    "touche et nom : 85, le nom sous la pastille")
ns:Set("procShowKey", false)
relayout()
a = alerts()[1]
check(P.AlertHeight() == 69 and S(root).h == 69 and not S(a.pill).shown and nameY() == -3,
    "touche cachée : 69, le nom remonte sous l'icône (pas de trou)")
ns:Set("procShowName", false)
relayout()
a = alerts()[1]
check(P.AlertHeight() == 52 and S(root).h == 52 and not S(a.name).shown and a.width == 58, "ni touche ni nom : 52, juste l'icône")
ns:Set("procShowKey", true)
relayout()
a = alerts()[1]
check(P.AlertHeight() == 68 and S(root).h == 68 and S(a.pill).shown and not S(a.name).shown, "touche seule : 68")
ns:Set("procShowName", true)
relayout()
check(P.AlertHeight() == 85 and S(root).h == 85, "tout remis : 85")

section("animation (procAnim)")
setSlots({ [3] = { "spell", OVERPOWER }, [5] = { "spell", EXECUTE } })
usable[3] = true
update(0.5)
local function look()
    local o = { rings = 0, glowA = S(a.glow).alpha, glowW = S(a.glow).w }
    for _, r in ipairs(a.rings) do o.rings = math.max(o.rings, S(r).alpha or 0) end
    o.shine = a.shine and (S(a.shine).alpha or 0) or 0
    o.pill, o.scale = S(a.pill).scale or 1, S(a.body).scale or 1
    return o
end
local function peak(seconds)
    local m = { rings = 0, shine = 0, pill = 1, scale = 1, glowMin = 9, glowMax = 0, widths = {} }
    for _ = 1, math.floor(seconds / 0.05) do
        M.advance(0.05)
        local o = look()
        m.rings, m.shine = math.max(m.rings, o.rings), math.max(m.shine, o.shine)
        m.pill, m.scale = math.max(m.pill, o.pill), math.max(m.scale, o.scale)
        m.glowMin, m.glowMax = math.min(m.glowMin, o.glowA or 0), math.max(m.glowMax, o.glowA or 0)
        m.widths[o.glowW or 0] = true
    end
    return m
end
a = alerts()[1]
local vivid = peak(3)
check(vivid.rings > 0.3 and vivid.shine > 0.3 and vivid.pill > 1.05, "vive : ondes, reflet, pastille qui gonfle")
ns:Set("procAnim", "doux")
M.advance(0.2)
a = alerts()[1]
local soft = peak(3)
check(soft.rings == 0 and soft.shine == 0 and soft.pill == 1 and soft.scale == 1, "douce : ni ondes, ni reflet, ni gonflement")
check(soft.glowMax - soft.glowMin > 0.2, "douce : le halo respire")
ns:Set("procAnim", "aucune")
M.advance(0.2)
a = alerts()[1]
local still = peak(3)
local nWidths = 0
for _ in pairs(still.widths) do nWidths = nWidths + 1 end
check(still.rings == 0 and still.shine == 0 and still.pill == 1 and still.scale == 1 and S(a).alpha == 1, "aucune : rien ne bouge")
check(still.glowMax == still.glowMin and nWidths == 1, "aucune : le halo reste fixe")
usable[5] = true
update(0.2)
local fresh = alerts()[2]
check(fresh and S(fresh).alpha == 1 and S(fresh.body).scale == 1, "aucune : nouvelle alerte visible tout de suite, à sa taille")
usable[5] = false
update(0.2)
check(#P.dying == 0 and #alerts() == 1, "aucune : l'alerte qui part disparaît sans animation")
ns:Set("procAnim", "vif")
M.advance(0.3)

section("opacité et son")
ns:Set("procOpacity", 0.5)
local function bodyAlphaOk(v)
    local list = alerts()
    for _, f in ipairs(list) do if S(f.body).alpha ~= v then return false end end
    return true
end
check(bodyAlphaOk(0.5) and S(root).alpha == 1, "opacité 50 % sur les alertes seulement (pas sur root)")
check(P.frames.chip == nil or S(P.frames.chip).alpha ~= 0.5, "opacité : la puce de blocage n'est pas atténuée")
check(P.frames.mover == nil or S(P.frames.mover).alpha ~= 0.5, "opacité : le cadre de déplacement n'est pas atténué")
ns:Set("procOpacity", 0)
check(bodyAlphaOk(0.3), "opacité bornée à 30 %")
ns:Set("procOpacity", 1)
check(bodyAlphaOk(1) and S(root).alpha == 1, "opacité 100 %")
local sounds = {}
def("SOUNDKIT", { UI_BNET_TOAST = 18019 })
def("PlaySound", function(id) sounds[#sounds + 1] = id end)
usable[3] = true
update(0.3)
check(#sounds == 0, "son coupé par défaut : silence")
usable[3] = false
update(0.3)
ns:Set("procSound", true)
usable[3] = true
update(0.3)
check(#sounds == 1 and sounds[1] == 18019, "son actif : un son à l'apparition d'une alerte")
usable[3] = false
update(0.3)
usable[3] = true
update(0.2)
check(#sounds == 1, "au plus un son par seconde")
usable[3] = false
update(0.3)
M.advance(1.5)
usable[3] = true
update(0.3)
check(#sounds == 2, "une seconde plus tard : le son revient")
ns:Set("procSound", false)
usable[3] = false
update(0.3)

section("pas d'erreur")
check(#M.errors == 0, "aucune erreur dans cette partie")

M.report()
if #failures > 0 or #M.errors > 0 then
    M.realPrint(("ÉCHEC : %d test(s), %d erreur(s)"):format(#failures, #M.errors))
else
    M.realPrint("TOUS LES TESTS PASSENT")
end
