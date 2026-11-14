-- Test : contrôles des mobs (MobControls.lua + MobControlsData.lua générée), mode strict.
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "/wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

local secretMT = { __eq = function() error("comparaison d'une valeur secrète") end,
    __concat = function() error("secret") end, __len = function() error("secret") end,
    __lt = function() error("secret") end, __le = function() error("secret") end }
local SECRET = setmetatable({}, secretMT)
def("issecretvalue", function(v) return v == SECRET end)
-- rawequal pour ne pas déclencher __eq
def("issecretvalue", function(v) return rawequal(v, SECRET) end)

local function guid(npc, n) return "Creature-0-1-2-3-" .. npc .. "-abc" .. (n or 1) end
local units = {}
def("UnitGUID", function(u) return units[u] and units[u].guid end)
def("UnitName", function(u) return units[u] and units[u].name end)
local tipFns = {}
def("TooltipDataProcessor", { AddTooltipPostCall = function(t, fn) tipFns[t] = fn end })
Enum.TooltipDataType = { Item = 0, Unit = 2 }
local tipLines, shown = {}, 0
GameTooltip.AddLine = function(_, l) tipLines[#tipLines + 1] = { l } end
GameTooltip.AddDoubleLine = function(_, l, r) tipLines[#tipLines + 1] = { l, r } end
GameTooltip.Show = function() shown = shown + 1 end
GameTooltip.GetUnit = function() return nil end
local function hover(g)
    tipLines = {}
    tipFns[2](GameTooltip, { guid = g })
    return tipLines
end
local function find(lines, txt)
    for _, l in ipairs(lines) do if tostring(l[1]):find(txt, 1, true) then return l end end
end

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "MobControlsData.lua", "MobControls.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
local MC, D = ns.MobControls, ns.MobControlsData

section("chargement")
check(MC and D and D.spells and D.lists and D.mobs, "module et données chargés")
check(ns.db.mobControlTooltip == true, "infobulle activée par défaut")
check(type(tipFns[2]) == "function" and MC.tooltipHooked, "infobulle d'unité accrochée")

section("NpcID")
check(MC.NpcID("Creature-0-1-2-3-116-abc") == 116, "GUID de créature -> 116")
check(MC.NpcID("Player-1-0002") == nil, "joueur -> nil")
check(MC.NpcID(SECRET) == nil, "valeur secrète -> nil")

section("Lines")
local found
for _, l in ipairs(MC:Lines(116)) do if l.id == 8646 then found = l end end
check(found and found.cat == "stun" and found.duration == 2, "Bandit défias : sort 8646, étourdissement 2 s")
local snare
for _, l in ipairs(MC:Lines(474)) do if l.cat == "snare" then snare = l end end
check(snare ~= nil, "mob 474 : un ralentissement")
check(#MC:Lines(99999999) == 0, "mob inconnu : liste vide")

section("textes")
check(MC.When(0, 0, 0, 5, 9, 0, false) == "toutes les 5-9 s", "répétition 5-9 -> « toutes les 5-9 s »")
check(MC.When(0, 3, 3, 0, 0, 0, false):find("une fois", 1, true), "c=d=0 -> « une fois... »")
check(MC.When(0, 0, 0, 1, 2, 0, false) == "en boucle", "d<=2 -> « en boucle »")
check(MC.When(2, 30, 0, 0, 0, 0, false) == "sous 30 % de vie", "kind 2 -> « sous 30 % de vie »")
check(MC.When(0, 0, 0, 5, 9, 65, false):find("(65 % de chance)", 1, true), "chance 65 -> « (65 % de chance) »")
check(MC.When(0, 0, 0, 5, 9, 100, false):find("chance", 1, true) == nil, "chance 100 : rien")
check(MC.When(0, 1.5, 1.5, 0, 0, 0, false):find("1,5", 1, true), "décimale avec virgule")
check(MC.Effect("stun", 2) == "Étourdit 2 s", "Effect stun 2 -> « Étourdit 2 s »")
check(MC.Effect("snare", 0) == "Ralentit", "durée inconnue : pas de durée")

section("infobulle")
local lines = hover(guid(116))
check(find(lines, "Étourdit") ~= nil, "Bandit défias : ligne « Étourdit »")
check(shown == 0, "pas de Show dans le post-call (Blizzard le fait après, sinon OnShow teinté)")
ns:Set("mobControlTooltip", false)
check(#hover(guid(116)) == 0, "réglage coupé : rien")
ns:Set("mobControlTooltip", true)
check(#hover(SECRET) == 0, "GUID secret : rien")
check(#hover("Player-1-0002") == 0, "joueur : rien")
local big, count
for npc in pairs(D.mobs) do
    local n = #MC:Lines(npc)
    if n > 4 then big, count = npc, n; break end
end
if not big then
    -- aucun mob réel à plus de 4 sorts distincts : on en injecte un fictif (les données ont de toute façon <= 4)
    local ids, k = {}, 0
    for id in pairs(D.spells) do k = k + 1; ids[k] = id; if k == 7 then break end end
    local list = {}
    for _, id in ipairs(ids) do for _, v in ipairs({ id, 0, 0, 0, 5, 9, 0 }) do list[#list + 1] = v end end
    D.lists[#D.lists + 1] = list
    D.mobs[987654] = #D.lists
    big, count = 987654, #MC:Lines(987654)
end
check(big ~= nil and count > 4, "un mob à plus de 4 sorts (réel ou fictif)")
if big then
    lines = hover(guid(big))
    check(#lines == 5, "4 sorts puis une ligne de reste")
    check(lines[5] and tostring(lines[5][1]):find("+ " .. (count - 4) .. " autre(s)", 1, true), "« + " .. (count - 4) .. " autre(s) »")
end

section("/pp mob")
units.target = { guid = guid(116, 2), name = "Bandit défias" }
M.printed = {}
SlashCmdList["PLATYPLUS"]("mob")
local out = table.concat(M.printed, "\n")
check(out:find("Bandit défias", 1, true) and out:find("Étourdit", 1, true), "cible : nom et contrôles")
units.target = nil
M.printed = {}
SlashCmdList["PLATYPLUS"]("mob")
check(table.concat(M.printed, "\n"):find("contrôles des mobs : %d+ mobs") ~= nil, "sans cible : ligne d'état")

section("cohérence des données")
local badMob, badLen, badSpell, badCat = 0, 0, 0, 0
for _, list in pairs(D.lists) do
    if #list % 7 ~= 0 then badLen = badLen + 1 end
    for i = 1, #list - 6, 7 do
        local s = D.spells[list[i]]
        if not s then badSpell = badSpell + 1 elseif not MC.CATS[s[1]] then badCat = badCat + 1 end
    end
end
for _, idx in pairs(D.mobs) do if not D.lists[idx] then badMob = badMob + 1 end end
check(badMob == 0, "chaque mob pointe vers une liste existante")
check(badLen == 0, "chaque liste : longueur multiple de 7")
check(badSpell == 0, "chaque sort des listes a une entrée D.spells")
check(badCat == 0, "chaque catégorie est connue de MC.CATS")

M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
