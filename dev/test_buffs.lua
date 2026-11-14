-- Test : rappel de buffs (Buffs.lua + Procs.lua) dans le simulateur strict
-- Un guerrier : Cri de guerre sur la touche 2, Fulgurance sur la 3. Groupe : prêtre, druide, mage, paladin.
--  * Cri de guerre : rien hors combat ; en combat sans le cri -> alerte « Cri de guerre manquant » sur « 2 » ;
--    auras secrètes en combat (le jeu ne répond rien) : pas de fausse alerte grâce à l'heure de fin lue avant le combat
--    ou à ton propre lancer ; réveil à la fin du cri ; mort ; sans C_Secrets ; cri absent des barres ; réglages
--  * buffs des alliés : hors combat seulement ; prêtre / druide / mage (mana) / paladin (n'importe quelle bénédiction) ;
--    allié mort ou déconnecté ; auras illisibles -> rien ; aperçu, déplacement, /pp buffs ; pas de scrutation
-- Usage : python -I dev\lua.py run dev\test_buffs.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S, impl = M.state, M.impl

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

impl.RegisterUnitEvent = function(f, event, ...)
    local s = S(f)
    s.events[event] = true
    s.units = s.units or {}
    s.units[event] = { ... }
end
impl.SetVertexColor = function(f, r, g, b, a) S(f).vertex = { r, g, b, a or 1 } end
impl.SetTextColor = function(f, r, g, b) S(f).color = { r, g, b } end
impl.SetStatusBarTexture = function(f, file) S(f).barFile = file end
impl.SetStatusBarColor = function(f, r, g, b) S(f).barColor = { r, g, b } end
impl.GetStatusBarTexture = function(f)
    local s = S(f)
    if not s.barTexture then s.barTexture = impl.CreateTexture(f) end
    return s.barTexture
end
impl.GetCenter = function(f)
    local c = S(f).center
    if c then return c[1], c[2] end
    return 683, 384
end

local SecretMT = { __tostring = function() return "secret" end }
for _, op in ipairs({ "__eq", "__lt", "__le", "__add", "__sub", "__concat", "__index", "__len" }) do
    SecretMT[op] = function() error("opération interdite sur une valeur secrète (" .. op .. ")", 2) end
end
local function secret() return setmetatable({}, SecretMT) end
local function isSecretObj(v) return getmetatable(v) == SecretMT end
def("issecretvalue", isSecretObj)

---------------------------------------------------------------------------
-- Faux jeu
---------------------------------------------------------------------------
local SHOUT, OVERPOWER = 6673, 7384
local NAMES = {
    [6673] = "Cri de guerre", [5242] = "Cri de guerre", [6192] = "Cri de guerre", [11549] = "Cri de guerre",
    [11550] = "Cri de guerre", [11551] = "Cri de guerre", [25289] = "Cri de guerre",
    [OVERPOWER] = "Fulgurance",
    [1243] = "Mot de pouvoir : Robustesse", [21562] = "Prière de robustesse",
    [1126] = "Marque du fauve", [21849] = "Don du fauve",
    [1459] = "Intelligence des arcanes", [23028] = "Illumination des arcanes",
    [19740] = "Bénédiction de puissance", [25782] = "Bénédiction de puissance supérieure",
    [19742] = "Bénédiction de sagesse", [25894] = "Bénédiction de sagesse supérieure",
    [20217] = "Bénédiction des rois", [25898] = "Bénédiction des rois supérieure",
    [1038] = "Bénédiction de salut", [25895] = "Bénédiction de salut supérieure",
    [19977] = "Bénédiction de lumière", [25890] = "Bénédiction de lumière supérieure",
}
local slots = {
    [2] = { "spell", 11549 },           -- Cri de guerre (un rang) sur la touche 2
    [3] = { "spell", OVERPOWER },       -- Fulgurance sur la touche 3
}
def("GetActionInfo", function(action)
    local s = slots[action]
    if s then return s[1], s[2], s[3] end
end)
local usable, lacking = { [2] = true }, {}
def("C_ActionBar", {
    IsUsableAction = function(action) return usable[action] == true, lacking[action] == true end,
    GetActionCooldown = function() return { startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1 } end,
    GetActionTexture = function(action) local s = slots[action]; return s and (1000 + s[2]) or nil end,
})
def("C_Spell", {
    GetSpellName = function(id) return NAMES[id] end,
    GetSpellTexture = function(id) return 2000 + id end,
    GetSpellPowerCost = function() return {} end,
})
def("C_SpellActivationOverlay", { IsSpellOverlayed = function() return false end })
local bindings = { ACTIONBUTTON2 = "2", ACTIONBUTTON3 = "3" }
def("GetBindingKey", function(command) return bindings[command] end)
def("ActionButtonUtil", { ActionBarButtonNames = { "ActionButton" } })
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.action, b.bindingAction, b.commandName = i, "ACTIONBUTTON" .. i, "ACTIONBUTTON" .. i
end

-- mes auras : [nom] = { expirationTime, duration } ; secrètes = le jeu ne répond rien (RequiresNonSecretAura)
local world = { auras = {}, aurasSecret = false, mana = 0, units = {} }
local function auraData(name)
    local a = world.auras[name]
    if not a then return nil end
    return { name = name, expirationTime = a.exp, duration = a.dur, spellId = 0 }
end
local listCalls = 0
def("C_UnitAuras", {
    GetUnitAuras = function(unit, filter)
        listCalls = listCalls + 1
        local list = {}
        for name in pairs(world.auras) do
            if world.aurasSecret then list[#list + 1] = { name = secret() } else list[#list + 1] = auraData(name) end
        end
        return list
    end,
    GetAuraDataBySpellName = function(unit, name)
        if world.aurasSecret then return nil end
        return auraData(name)
    end,
    GetPlayerAuraBySpellID = function(id)
        if world.aurasSecret then return nil end
        return auraData(NAMES[id])
    end,
})
local secrets = {
    ShouldSpellAuraBeSecret = function() return world.aurasSecret end,
    ShouldAurasBeSecret = function() return world.aurasSecret end,
}
def("C_Secrets", secrets)
-- cri sur toi : encore « left » secondes, sur une durée totale de 2 min
local function giveShout(left) world.auras["Cri de guerre"] = { exp = M.time + left, dur = 120 } end

def("IsInRaid", function() return false end)
def("GetNumSubgroupMembers", function()
    local n = 0
    for u in pairs(world.units) do if u:find("^party") then n = n + 1 end end
    return n
end)
local function unitOf(u) return world.units[u] end
def("UnitExists", function(u) return u == "player" or unitOf(u) ~= nil end)
def("UnitIsUnit", function(a, b) return a == b end)
def("UnitName", function(u) local e = unitOf(u); return e and e.name end)
def("UnitClass", function(u)
    local e = unitOf(u)
    if not e then return "Guerrier", "WARRIOR", 1 end
    return e.class, e.classFile, 5
end)
def("UnitIsConnected", function(u) local e = unitOf(u); return not (e and e.offline) end)
def("UnitIsDeadOrGhost", function(u) local e = unitOf(u); return e and e.dead or false end)
def("UnitPowerMax", function(u, t) if u == "player" and t == 0 then return world.mana end return 100 end)
def("UnitPower", function() return 0 end)
def("UnitPowerType", function() return 1, "RAGE", 0, 0, 0 end)
def("PowerBarColor", { RAGE = { r = 1, g = 0, b = 0 }, MANA = { r = 0, g = 0, b = 1 }, [0] = { r = 0, g = 0, b = 1 }, [1] = { r = 1, g = 0, b = 0 } })
def("RAID_CLASS_COLORS", {
    PRIEST = { r = 1, g = 1, b = 1 }, DRUID = { r = 1, g = 0.49, b = 0.04 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
})
local function member(name, classFile, class) return { name = name, classFile = classFile, class = class } end
local function party(list)
    world.units = {}
    for i, e in ipairs(list) do world.units["party" .. i] = e end
    M.fireEvent("GROUP_ROSTER_UPDATE")
    M.advance(0.3)
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local menuHooks = {}
def("Menu", { ModifyMenu = function(tag, fn) menuHooks[tag] = fn end })
def("PlatyplusDB", { powerPlayer = false, spellCost = false, hud = false, swingBar = false })
M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Resources.lua", "ResourceBar.lua", "Procs.lua", "Buffs.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.3)

local P, B = ns.Procs, ns.Buffs
local BF = B.frames or {}
local function strip(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function alerts() return P.order end
local function shoutAlert()
    for _, f in ipairs(P.order) do
        if strip(S(f.name).text):find("Cri de guerre", 1, true) then return f end
    end
end
local function combat(on)
    M.inCombat = on
    M.fireEvent(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    M.advance(0.3)
end
local function auraChanged()
    M.fireEvent("UNIT_AURA", "player", {})
    M.advance(0.3)
end
local function shout(id)
    M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", id or 11549)
    M.advance(0.3)
end
local function shownNames()
    local list = {}
    for _, e in ipairs(B:Shown()) do list[#list + 1] = e.name .. "/" .. tostring(e.ally) end
    table.sort(list)
    return table.concat(list, ", ")
end
local function pollers(frames)
    local n = 0
    for _, f in ipairs(frames) do if S(f).scripts.OnUpdate and impl.IsVisible(f) then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
section("réglages par défaut")
check(ns.db.buffShout == true and ns.db.buffAllies == true and ns.db.buffLocked == true, "Cri de guerre et buffs des alliés allumés")
check(ns.db.buffX == 0 and ns.db.buffY == 160, "rangée au-dessus du personnage (0, 160)")
check(S(BF.events).units and S(BF.events).units.UNIT_AURA and S(BF.events).units.UNIT_AURA[1] == "player",
    "UNIT_AURA écouté pour le joueur seul")

---------------------------------------------------------------------------
section("Cri de guerre : hors combat")
check(shoutAlert() == nil, "pas de cri, hors combat : rien (« uniquement en combat »)")

section("Cri de guerre : en combat, lisible")
combat(true)
local f = shoutAlert()
check(f ~= nil, "en combat sans le cri : alerte")
check(f and strip(S(f.name).text) == "Cri de guerre manquant" and strip(S(f.key).text) == "2",
    "« Cri de guerre manquant » sur la touche 2 (" .. tostring(f and S(f.name).text) .. ")")
check(f and S(f.icon).texture == 1000 + 11549, "icône du bouton")
giveShout(120)
auraChanged()
check(shoutAlert() == nil, "le cri arrive (aura lisible) : alerte retirée")
world.auras["Cri de guerre"] = nil
auraChanged()
check(shoutAlert() ~= nil, "le cri tombe : alerte de retour")
lacking[2], usable[2] = true, false
M.advance(0.3)
f = shoutAlert()
local v = f and S(f.icon).vertex
check(v and v[1] == 0.5 and v[3] == 1, "pas assez de rage : icône bleutée, alerte quand même")
lacking[2], usable[2] = nil, true
combat(false)
M.advance(0.5)
check(shoutAlert() == nil, "fin du combat : alerte retirée")

section("Cri de guerre : en combat, auras cachées par le jeu")
giveShout(30)                                   -- crié avant le combat, encore 30 s
auraChanged()
world.aurasSecret = true
combat(true)
check(shoutAlert() == nil, "cri lu avant le combat (30 s) : pas de fausse alerte malgré le « rien » du jeu")
M.advance(31)
check(shoutAlert() ~= nil, "30 s plus tard : le cri est fini, alerte (réveil programmé, aucun événement)")
shout()
check(shoutAlert() == nil, "tu cries (ton lancer est lisible) : alerte retirée")
M.advance(119)
check(shoutAlert() == nil, "119 s plus tard (durée du cri lue sur l'aura avant le combat : 2 min) : pas encore")
M.advance(2)
check(shoutAlert() ~= nil, "le cri que tu as lancé est fini : alerte")
shout(SHOUT)
check(shoutAlert() == nil, "autre rang du cri (6673) : reconnu aussi")
M.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", secret())
M.advance(0.3)
check(#M.errors == 0, "numéro de sort secret : ignoré sans erreur")
M.fireEvent("PLAYER_DEAD")
M.advance(0.3)
check(shoutAlert() ~= nil, "mort : plus de cri, alerte (si tu te bats encore)")
combat(false)
world.aurasSecret = false
world.auras = {}
auraChanged()

section("Cri de guerre : sans C_Secrets")
def("C_Secrets", nil)
giveShout(60)
auraChanged()
world.aurasSecret = true
combat(true)
check(shoutAlert() == nil, "API absente : en combat, « rien » n'est pas cru ; le cri lu avant (60 s) compte")
M.advance(61)
check(shoutAlert() ~= nil, "puis l'alerte à sa fin")
combat(false)
world.aurasSecret = false
world.auras = {}
def("C_Secrets", secrets)
auraChanged()

section("Cri de guerre : barres et réglages")
slots[2] = nil
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 2)
M.advance(0.3)
combat(true)
check(shoutAlert() == nil, "cri absent des barres : pas d'alerte (pas de touche à montrer)")
slots[2] = { "spell", 11549 }
M.fireEvent("ACTIONBAR_SLOT_CHANGED", 2)
M.advance(0.5)
check(shoutAlert() ~= nil, "remis sur la barre : alerte")
ns:Set("buffShout", false)
M.advance(0.5)
check(shoutAlert() == nil, "réglage coupé : plus d'alerte")
ns:Set("buffShout", true)
ns:Set("procAlert", false)
M.advance(0.5)
check(shoutAlert() ~= nil, "alerte de proc coupée : le rappel du cri marche quand même")
usable[3] = true
M.fireEvent("ACTION_USABLE_CHANGED", {})
M.advance(0.3)
local fulgurance = false
for _, a in ipairs(alerts()) do if a.spellID == OVERPOWER then fulgurance = true end end
check(not fulgurance, "mais pas les procs (Fulgurance utilisable, non annoncée)")
ns:Set("procAlert", true)
M.advance(0.3)
fulgurance = false
for _, a in ipairs(alerts()) do if a.spellID == OVERPOWER then fulgurance = true end end
check(fulgurance and shoutAlert() ~= nil, "les deux allumés : Fulgurance et le cri côte à côte")
usable[3] = nil
combat(false)
M.advance(0.5)
check(#M.errors == 0, "aucune erreur Lua (" .. tostring(M.errors[1]) .. ")")

---------------------------------------------------------------------------
section("buffs des alliés")
check(not S(BF.root).shown and #B:Shown() == 0, "seul : rien")
party({ member("Ariane", "PRIEST", "Prêtre"), member("Cléo", "DRUID", "Druide"), member("Max", "MAGE", "Mage"),
    member("Paul", "PALADIN", "Paladin") })
check(S(BF.root).shown, "groupe avec prêtre, druide, mage, paladin : rangée visible")
check(shownNames() == "Bénédiction de puissance/Paul, Marque du fauve/Cléo, Mot de pouvoir : Robustesse/Ariane",
    "guerrier : Robustesse, Marque du fauve, Bénédiction de puissance ; pas l'Intelligence (pas de mana) (" .. shownNames() .. ")")
local item = B.items[1]
check(item and S(item.icon).texture == 2000 + B:Shown()[1].spellID, "icône du buff")
check(item and S(item.ally).text == B:Shown()[1].ally, "nom de l'allié dessous")
world.auras["Prière de robustesse"] = { exp = M.time + 3600, dur = 3600 }
auraChanged()
check(not shownNames():find("Robustesse", 1, true), "Prière de robustesse reçue : Robustesse n'est plus demandée")
world.auras["Bénédiction des rois"] = { exp = M.time + 300, dur = 300 }
auraChanged()
check(not shownNames():find("Bénédiction", 1, true), "une autre bénédiction (rois) : le paladin a déjà donné la sienne")
world.auras = {}
world.mana = 1000
auraChanged()
check(shownNames():find("Intelligence des arcanes/Max", 1, true) and shownNames():find("Bénédiction de sagesse/Paul", 1, true)
    and not shownNames():find("puissance", 1, true), "utilisateur de mana : Intelligence, et sagesse au lieu de puissance")
world.mana = 0
world.units.party1.dead = true
world.units.party2.offline = true
party({ world.units.party1, world.units.party2, world.units.party3, world.units.party4 })
check(not shownNames():find("Ariane", 1, true) and not shownNames():find("Cléo", 1, true), "allié mort ou déconnecté : pas proposé")
world.units.party1.dead, world.units.party2.offline = nil, nil
party({ world.units.party1, world.units.party2, world.units.party3, world.units.party4 })
check(#B:Shown() == 3, "de retour : 3 buffs")
combat(true)
check(not S(BF.root).shown, "en combat : rangée cachée")
combat(false)
M.advance(0.3)
check(S(BF.root).shown and #B:Shown() == 3, "fin du combat : de retour")
world.aurasSecret = true
auraChanged()
check(not S(BF.root).shown, "auras illisibles : rien plutôt qu'une fausse demande")
world.aurasSecret = false
auraChanged()
ns:Set("buffAllies", false)
check(not S(BF.root).shown, "réglage coupé : cachée")
ns:Set("buffAllies", true)
check(S(BF.root).shown, "rallumé : visible")

section("aperçu, déplacement, /pp buffs")
party({})
check(not S(BF.root).shown, "plus de groupe : cachée")
B:Preview()
check(S(BF.root).shown and #B:Shown() == 2 and B:Shown()[1].ally == "Ariane", "aperçu : deux buffs d'exemple")
M.advance(7)
check(not S(BF.root).shown, "fin de l'aperçu")
B:ToggleMove()
check(ns.db.buffLocked == false and S(BF.mover).shown and S(BF.root).shown, "déverrouillée : cadre « glisse-moi » et exemple")
S(BF.root).center = { 783, 284 }
M.fire(BF.mover, "OnDragStart")
M.fire(BF.mover, "OnDragStop")
check(ns.db.buffX == 100 and ns.db.buffY == -100, "position enregistrée (" .. tostring(ns.db.buffX) .. ", " .. tostring(ns.db.buffY) .. ")")
S(BF.root).center = nil
M.fire(BF.mover, "OnMouseUp", "RightButton")
check(ns.db.buffLocked == true and not S(BF.mover).shown and not S(BF.root).shown, "clic droit : verrouillée, cachée")
B:ResetPosition()
local p = S(BF.root).points[1]
check(p and p[4] == 0 and p[5] == 160, "remise en place")
M.printed = {}
party({ member("Cléo", "DRUID", "Druide") })
SlashCmdList.PLATYPLUS("buffs")
local printed = strip(table.concat(M.printed, "\n"))
check(printed:find("Cri de guerre en combat : ON", 1, true) and printed:find("Marque du fauve (Cléo)", 1, true),
    "/pp buffs : état du cri et buff à demander")
M.advance(7)

section("sans scrutation")
local before = listCalls
M.advance(30)
check(listCalls == before, "aucune relecture des auras sans événement")
check(pollers({ BF.root, BF.events, BF.mover }) == 0, "aucune boucle OnUpdate dans le rappel de buffs")

section("Demander un buff (clic droit)")
check(menuHooks.MENU_UNIT_PLAYER and menuHooks.MENU_UNIT_PARTY and menuHooks.MENU_UNIT_FRIEND,
    "le menu est enregistré pour joueur, groupe et ami")
local sent = {}
def("C_ChatInfo", { SendChatMessage = function(...) sent[#sent + 1] = { ... } end })
local askWorld = { class = "PALADIN", isPlayer = true, coop = true, inGroup = false }
local prevClass, prevIsUnit = rawget(_G, "UnitClass"), rawget(_G, "UnitIsUnit")
def("UnitClass", function(u)
    if u == "target" then return "Paladin", askWorld.class, 2 end
    return prevClass(u)
end)
def("UnitIsPlayer", function() return askWorld.isPlayer end)
def("UnitCanCooperate", function() return askWorld.coop end)
def("IsInGroup", function() return askWorld.inGroup end)
local function fakeMenu()
    local root = { divider = 0, subs = {} }
    local function node(list)
        return { CreateButton = function(self, text, fn)
            local n = node({}); n.text, n.fn, n.kids = text, fn, {}
            list[#list + 1] = n
            n.list = n.kids
            return n
        end }
    end
    root.CreateDivider = function(self) self.divider = self.divider + 1 end
    root.CreateButton = function(self, text, fn)
        local n = { text = text, fn = fn, kids = {} }
        n.CreateButton = function(s, t, f) n.kids[#n.kids + 1] = { text = t, fn = f }; return n end
        root.subs[#root.subs + 1] = n
        return n
    end
    return root
end
local function openMenu(data)
    local root = fakeMenu()
    menuHooks.MENU_UNIT_PLAYER(nil, root, data)
    return root
end

local root = openMenu({ unit = "target", name = "Uther" })
local sub = root.subs[1]
check(sub and sub.text == "Demander un buff" and root.divider == 1, "sous-menu « Demander un buff » créé après un séparateur")
check(sub and #sub.kids == 6, "paladin : « Tous ses buffs » + 5 bénédictions")
check(sub and sub.kids[1].text == "Tous ses buffs", "la première entrée est « Tous ses buffs »")
check(sub and sub.kids[2].text:find("Bénédiction des rois", 1, true), "la deuxième entrée porte le nom du sort Rois")
sub.kids[2].fn()
local s1 = sent[#sent]
check(s1 and s1[1] == "Salut, rois stp ? Merci :)" and s1[2] == "WHISPER"
    and s1[3] == nil and s1[4] == "Uther", "clic sur Rois : chuchotement à Uther")
sub.kids[1].fn()
check(sent[#sent][1] == "Salut, buff stp ? Merci :)" and sent[#sent][4] == "Uther",
    "clic sur « Tous ses buffs » : « buff stp »")
ns:Set("buffAskLang", "en")
sub.kids[2].fn()
check(sent[#sent][1] == "Hi, could I get BoK pls? Thanks :)", "anglais : « BoK pls »")
sub.kids[1].fn()
check(sent[#sent][1] == "Hi, could I get buff pls? Thanks :)", "anglais : « buff pls »")
ns:Set("buffAskLang", "fr")
sub = openMenu({ unit = "target", name = "Uther", surname = "Royaume" }).subs[1]
sub.kids[2].fn()
check(sent[#sent][4] == "Uther-Royaume", "avec un royaume : cible « Uther-Royaume »")

askWorld.class = "WARRIOR"
check(#openMenu({ unit = "target", name = "Thrall" }).subs == 0, "classe sans buff : aucune ligne")
askWorld.class = "PALADIN"
askWorld.isPlayer = false
check(#openMenu({ unit = "target", name = "Garde" }).subs == 0, "PNJ : aucune ligne")
askWorld.isPlayer = true
def("UnitIsUnit", function(a, b) return true end)
check(#openMenu({ unit = "target", name = "Moi" }).subs == 0, "soi-même : aucune ligne")
def("UnitIsUnit", prevIsUnit)
ns:Set("buffAsk", false)
check(#openMenu({ unit = "target", name = "Uther" }).subs == 0, "réglage coupé : aucune ligne")
ns:Set("buffAsk", true)

-- nom secret en groupe : repli sur le chat de groupe
party({ member("Paul", "PALADIN", "Paladin") })
askWorld.inGroup = true
sent = {}
sub = openMenu({ unit = "party1", name = secret() }).subs[1]
check(sub ~= nil, "nom secret : le menu est quand même proposé")
sub.kids[2].fn()
check(#sent == 1 and sent[1][2] == "PARTY" and sent[1][1] == "Paladin, rois stp ? Merci :)",
    "nom secret : demande dans le chat de groupe (PARTY)")
ns:Set("buffAskLang", "en")
sub.kids[1].fn()
check(sent[2] and sent[2][1] == "Paladin, could I get buff pls? Thanks :)" and sent[2][2] == "PARTY",
    "nom secret, anglais : « Paladin: buff pls »")
ns:Set("buffAskLang", "fr")
askWorld.inGroup = false

-- nom cliqué dans le chat (pas d'unit)
def("C_PlayerInfo", { GetClass = function() return "Mage", "MAGE", 8 end })
sub = openMenu({ name = "Jaina", playerLocation = {} }).subs[1]
local labels = {}
for _, k in ipairs(sub and sub.kids or {}) do labels[#labels + 1] = k.text end
local joined = table.concat(labels, "|")
check(joined:find("De la nourriture", 1, true) and joined:find("De l'eau", 1, true), "nom du chat : mage, nourriture et eau proposées")
sent = {}
for _, k in ipairs(sub.kids) do if k.text:find("De l'eau", 1, true) then k.fn() end end
check(sent[1] and sent[1][1] == "Salut, de l'eau stp ? Merci :)" and sent[1][2] == "WHISPER"
    and sent[1][4] == "Jaina", "clic sur « De l'eau » : chuchotement à Jaina")
check(#M.errors == 0, "aucune erreur Lua")

section("bilan")
local badGlobals = {}
for _, name in ipairs(M.newGlobals) do
    if not (name:find("^Platyplus") or name:find("^SLASH_PLATYPLUS")) then badGlobals[#badGlobals + 1] = name end
end
check(#badGlobals == 0, "aucune globale hors « Platyplus… » (" .. table.concat(badGlobals, ",") .. ")")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
