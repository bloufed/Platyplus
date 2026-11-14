-- Test de la fenêtre « Jets de butin » (LootRolls.lua) dans le simulateur, en mode strict.
-- Simule C_LootHistory, IsInGroup, RAID_CLASS_COLORS, C_Item.GetItemInfoInstant, issecretvalue.
-- Usage : python -I dev\lua.py run dev\test_lootrolls.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state
local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

M.impl.SetText = function(f, t) S(f).text = t end
M.impl.GetText = function(f) return S(f).text end

-- valeurs secrètes : toute opération (comparaison, calcul, concaténation, tostring...) lève une erreur
local secrets = setmetatable({}, { __mode = "k" })
local function boom() error("opération sur une valeur secrète", 2) end
local function secret(v)
    local t = setmetatable({}, { __index = boom, __newindex = boom, __call = boom, __concat = boom, __len = boom,
        __add = boom, __sub = boom, __mul = boom, __div = boom, __lt = boom, __le = boom, __unm = boom,
        __tostring = boom, __eq = boom })
    secrets[t] = v
    return t
end
def("issecretvalue", function(v) return type(v) == "table" and secrets[v] ~= nil end)

-- monde simulé
local grouped = true
def("IsInGroup", function() return grouped end)
def("RAID_CLASS_COLORS", {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    MAGE = { r = 0.41, g = 0.8, b = 0.94 }, PRIEST = { r = 1, g = 1, b = 1 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
})
def("INVTYPE_FEET", "Pieds")
def("C_Item", { GetItemInfoInstant = function() return 13965, "Armure", "Tissu", "INVTYPE_FEET", "Interface\\Icons\\Boots" end })

local function r(name, class, state, roll, win, self)
    return { playerName = name, playerClass = class, state = state, roll = roll, isWinner = win or false, isSelf = self or false }
end
local function link(id, name) return "|cff0070dd|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r" end

local data
local function build()
    local t = M.time
    local win = r("Brakmar", "WARRIOR", 0, 91, true, true)
    local lead = r("Ysolde", "PALADIN", 3, 72)
    data = {
        encounters = {
            { encounterID = 1, encounterName = "Cookie", startTime = t - 600, duration = 0 },
            { encounterID = 2, encounterName = "VanCleef", startTime = t - 100, duration = 0 },
        },
        drops = {
            [2] = {
                { lootListKey = 1, itemHyperlink = link(19019, "Lame du crépuscule"), winner = win, allPassed = false,
                  startTime = t - 90, duration = 60,
                  rollInfos = { win, r("Ysolde", "PALADIN", 0, 64), r("Kerrigane", "ROGUE", 3, 88), r("Tilda", "PRIEST", 5) } },
                { lootListKey = 2, itemHyperlink = link(13965, "Bottes"), currentLeader = lead, allPassed = false,
                  startTime = t - 10, duration = 60,
                  rollInfos = { lead, r("Brakmar", "WARRIOR", 3, 41, false, true), r("Morwen", "MAGE", 4) } },
                { lootListKey = 3, itemHyperlink = link(2140, "Anneau"), allPassed = true, startTime = t - 80, duration = 60,
                  rollInfos = { r("Brakmar", "WARRIOR", 5, nil, false, true), r("Ysolde", "PALADIN", 5) } },
            },
            [1] = {
                { lootListKey = 1, itemHyperlink = link(5197, "Gourdin"), winner = r("Morwen", "MAGE", 3, 77, true),
                  startTime = t - 610, duration = 60, rollInfos = { r("Morwen", "MAGE", 3, 77, true) } },
            },
        },
    }
end
def("C_LootHistory", {
    GetAllEncounterInfos = function() return data.encounters end,
    GetSortedDropsForEncounter = function(id) return data.drops[id] or {} end,
    GetSortedInfoForDrop = function(id, key)
        for _, d in ipairs(data.drops[id] or {}) do if d.lootListKey == key then return d end end
    end,
    GetLootHistoryTime = function() return M.time end,
})

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "UIWidgets.lua", "Windows.lua", "LootRolls.lua" })
local LR = ns.LootRolls

local function findFrame()
    for _, f in ipairs(M.allFrames) do if S(f).name == "PlatyplusLootRolls" then return f end end
end
local function isOpen() local f = findFrame() return f ~= nil and S(f).shown == true end
local function has(sub)
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "FontString" and M.impl.IsVisible(f) and (type(s.text) == "string" or type(s.text) == "number")
            and tostring(s.text):find(sub, 1, true) then
            return true
        end
    end
    return false
end
-- secondes affichées sur la ligne « Jets en cours · N s » (nil si absente)
local function secondsShown()
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "FontString" and M.impl.IsVisible(f) and type(s.text) == "string" and s.text:find("Jets en cours", 1, true) then
            return tonumber(s.text:match("(%d+) s"))
        end
    end
end
local function visibleChecks()
    local n = 0
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "Texture" and s.texture == "Interface\\RaidFrame\\ReadyCheck-Ready" and M.impl.IsVisible(f) then n = n + 1 end
    end
    return n
end
local function listening(ev)
    for _, f in ipairs(M.allFrames) do
        if S(f).events[ev] and S(f).scripts.OnEvent then return true end
    end
    return false
end

section("démarrage")
build()
M.fireEvent("ADDON_LOADED", "Platyplus"); M.fireEvent("PLAYER_LOGIN"); M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
check(#M.errors == 0, "démarrage sans erreur d'exécution")
check(ns.db.lootRolls == true and ns.db.lootRollsAuto == true and ns.db.lootRollsAutoClose == true,
    "réglages par défaut lootRolls / lootRollsAuto / lootRollsAutoClose vrais")
check(listening("LOOT_HISTORY_UPDATE_DROP"), "événements du butin écoutés au démarrage")
check(not isOpen(), "fenêtre fermée au départ")

section("ouverture automatique")
grouped = false
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 2, 1)
M.advance(0.5)
check(not isOpen(), "hors groupe : la fenêtre ne s'ouvre pas")
grouped = true
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 2, 2)
M.advance(0.5)
local frame = findFrame()
check(frame ~= nil and isOpen(), "en groupe, nouvel objet : la fenêtre PlatyplusLootRolls s'affiche")
check(LR:IsShown(), "LR:IsShown() vrai")
check(#M.errors == 0, "aucune erreur à l'ouverture")

section("contenu")
check(has("VanCleef"), "titre = rencontre la plus récente")
check(has("Lame du crépuscule") and has("Bottes") and has("Anneau"), "une carte par objet")
check(not has("Gourdin"), "l'objet de l'autre rencontre n'est pas affiché")
check(has("Pieds"), "emplacement de l'objet affiché")
check(has("Besoin") and has("Cupidité") and has("Passe") and has("Attente"), "pastilles Besoin / Cupidité / Passe / Attente")
check(has("Kerrigane") and has("Tilda") and has("Morwen") and has("Brakmar"), "une ligne par joueur")
check(has("(toi)"), "le joueur local est marqué")
check(has("91") and has("88") and has("41"), "dé de chaque joueur affiché")
check(visibleChecks() == 1, "une seule coche de gagnant visible (" .. visibleChecks() .. ")")
check(has("Gagné par") and has("Brakmar"), "ligne d'état « Gagné par … »")
check(has("Tout le monde a passé"), "ligne d'état « Tout le monde a passé »")
local before = secondsShown()
check(before ~= nil and before >= 45 and before <= 50, "objet en cours : « Jets en cours · N s » (" .. tostring(before) .. ")")
check(has("en tête") and has("Ysolde"), "meneur actuel affiché")

section("minuteur")
check(S(frame.ticker).scripts.OnUpdate ~= nil, "OnUpdate actif tant qu'un objet est en cours")
M.advance(5)
local after = secondsShown()
check(before and after and after >= before - 6 and after <= before - 4, "le compte à rebours avance de 5 s (" .. tostring(before) .. " -> " .. tostring(after) .. ")")
local d = data.drops[2][2]
d.winner = r("Ysolde", "PALADIN", 3, 72, true); d.currentLeader = nil
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 2, 2)
M.advance(0.5)
check(S(frame.ticker).scripts.OnUpdate == nil, "OnUpdate arrêté quand plus aucun objet n'est en cours")
d.winner = nil; d.startTime = M.time; d.duration = 60
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 2, 2)
M.advance(0.5)
check(S(frame.ticker).scripts.OnUpdate ~= nil, "OnUpdate relancé pour un nouvel objet en cours")
LR:Close()
check(not isOpen() and S(frame.ticker).scripts.OnUpdate == nil, "à la fermeture le minuteur s'arrête")

section("navigation")
d.winner = r("Ysolde", "PALADIN", 3, 72, true)
LR:Open()
check(has("VanCleef") and has("1 / 2"), "ouverture sur la rencontre la plus récente, compteur « 1 / 2 »")
LR:Step(1)
check(has("Cookie") and has("2 / 2") and has("Gourdin") and not has("Lame du crépuscule"),
    "Step(1) : rencontre précédente (titre, « 2 / 2 », ses objets)")
LR:Step(1)
check(has("2 / 2"), "Step(1) au bout de la liste : reste sur « 2 / 2 »")
LR:Step(-1)
check(has("VanCleef") and has("1 / 2") and has("Lame du crépuscule"), "Step(-1) : retour à la rencontre la plus récente")
LR:Close()

section("fermeture automatique")
M.advance(1)
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 2, 9)     -- même boss, fenêtre fermée à la main juste avant
M.advance(0.5)
check(not isOpen(), "fermée à la main : pas de réouverture automatique pour le même boss")
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 3, 1)     -- nouveau boss (tout est terminé)
M.advance(0.5)
check(isOpen(), "ouverte automatiquement au boss suivant")
M.advance(15)
check(isOpen(), "encore ouverte avant 20 s")
M.advance(7)
check(not isOpen(), "refermée toute seule 20 s après la fin des jets")
-- remontée de l'historique : plus de fermeture automatique
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 3, 2)      -- (refermée par le minuteur : réouverture permise)
M.advance(0.5)
LR:Step(1)
M.advance(40)
check(isOpen(), "après navigation dans l'historique : plus de fermeture automatique")
LR:Close()
-- ouverte à la main : jamais fermée seule
LR:Open()
M.advance(40)
check(isOpen(), "ouverte à la main : pas de fermeture automatique")
LR:Close()

section("exemple fermé par Échap, objet sans gagnant")
LR:Demo()
frame:Hide()                                        -- Échap (UISpecialFrames) : pas LR:Close()
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 4, 1)
M.advance(0.5)
check(isOpen() and not has("(exemple)"), "après l'exemple fermé par Échap, l'ouverture auto marche sur les vraies données")
LR:Close()
local stuck = data.drops[2][2]
stuck.winner, stuck.currentLeader, stuck.allPassed = nil, nil, false
stuck.startTime, stuck.duration = M.time - 100, 60
LR:Open()
M.advance(0.5)
check(has("Temps écoulé"), "objet sans gagnant 40 s après la fin : « Temps écoulé »")
check(S(frame.ticker).scripts.OnUpdate == nil, "objet sans gagnant : plus de minuteur")
stuck.winner = r("Ysolde", "PALADIN", 3, 72, true)
LR:Close()

section("valeurs secrètes")
local errorsBefore = #M.errors
local sw = r(secret("Brakmar"), secret("WARRIOR"), 0, secret(91), true, true)
data.drops[2] = {
    { lootListKey = 1, itemHyperlink = link(19019, "Lame"), winner = sw,
      startTime = M.time - 5, duration = 60,
      rollInfos = { sw, r(secret("Ysolde"), "PALADIN", secret(3), secret(64)) } },
    { lootListKey = 2, itemHyperlink = secret(link(1, "Secret")), currentLeader = r(secret("Morwen"), "MAGE", 3, secret(50)),
      startTime = M.time - 5, duration = 60,
      rollInfos = { r(secret("Morwen"), secret("MAGE"), 3, secret(50)), r("Tilda", "PRIEST", secret(4)) } },
}
def("issecretvalue", function(v) return type(v) == "table" and secrets[v] ~= nil end)
LR:Open()
M.advance(1)
check(isOpen(), "fenêtre affichée avec des noms, dés et classes secrets")
check(#M.errors == errorsBefore, "aucune erreur : le module ne compare ni ne calcule sur les valeurs secrètes")
check(has("Tilda"), "les valeurs lisibles restent affichées à côté des secrètes")
LR:Close()
build()

section("réglage coupé et exemple")
LR:Open()
check(isOpen(), "ouverte avant de couper")
ns:Set("lootRolls", false)
check(not isOpen(), "ns:Set(lootRolls,false) ferme la fenêtre")
check(not listening("LOOT_HISTORY_UPDATE_DROP") and not listening("START_LOOT_ROLL"), "événements désinscrits")
M.fireEvent("LOOT_HISTORY_UPDATE_DROP", 2, 20)
M.advance(0.5)
check(not isOpen(), "coupé : un nouvel objet n'ouvre rien")
ns:Set("lootRolls", true)
check(listening("LOOT_HISTORY_UPDATE_DROP"), "réactivé : événements réinscrits")
LR:Demo()
check(isOpen(), "LR:Demo() affiche la fenêtre")
check(has("Edwin VanCleef (exemple)") and has("Lame du crépuscule") and has("Tout le monde a passé"),
    "LR:Demo() montre les données d'exemple")
LR:Close()
check(not isOpen(), "fermeture de l'exemple")
check(#M.errors == errorsBefore, "aucune erreur sur l'ensemble")

---------------------------------------------------------------------------
-- onglet « /roll » : dés tapés à la main
---------------------------------------------------------------------------
def("RANDOM_ROLL_RESULT", "%s obtient un %d (%d-%d).")
local roster = {
    player = { "Brakmar", "WARRIOR" }, party1 = { "Ysolde", "PALADIN" }, party2 = { "Kerrigane", "ROGUE" },
    party3 = { "Tilda", "PRIEST" },
}
def("IsInRaid", function() return false end)
def("GetNumGroupMembers", function() return 4 end)
def("UnitName", function(u) local e = roster[u] return e and e[1] or nil end)
def("UnitClass", function(u) local e = roster[u] if e then return e[2], e[2] end end)

local function roll(name, n, low, high)
    M.fireEvent("CHAT_MSG_SYSTEM", string.format("%s obtient un %d (%d-%d).", name, n, low or 1, high or 100))
end
local function strip(t)
    local s = t:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end
local function textOf(sub)
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "FontString" and M.impl.IsVisible(f) and type(s.text) == "string" and s.text:find(sub, 1, true) then
            return strip(s.text)
        end
    end
end
-- nombre de cartes de série affichées (une ligne d'état « N joueur(s) » par carte)
local function nCards()
    local n = 0
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "FontString" and M.impl.IsVisible(f) and type(s.text) == "string" and s.text:find(" joueur", 1, true) then n = n + 1 end
    end
    return n
end
-- noms des joueurs affichés, du haut vers le bas
local NAMES = { Brakmar = true, Ysolde = true, Kerrigane = true, Tilda = true, Morwen = true }
local function order()
    local list = {}
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "FontString" and M.impl.IsVisible(f) and type(s.text) == "string" then
            local nm = s.text:match("^|cff%x%x%x%x%x%x([^|]+)|r")
            if nm and NAMES[nm] then
                local row = M.impl.GetParent(f)
                local p = S(row).points[1]
                list[#list + 1] = { name = nm, y = p and p[5] or 0 }
            end
        end
    end
    table.sort(list, function(a, b) return a.y > b.y end)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.name end
    return table.concat(out, ",")
end
local function clearRolls()
    LR:SetMode("roll")
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "FontString" and s.text == "Effacer" then
            local b = M.impl.GetParent(f)
            if b and S(b).scripts.OnClick then M.fire(b, "OnClick") return true end
        end
    end
    return false
end

section("/roll : lecture du message système")
LR:Close()
M.advance(61)
errorsBefore = #M.errors
M.fireEvent("CHAT_MSG_SYSTEM", "Ysolde a rejoint le groupe.")
M.advance(0.5)
check(not isOpen(), "un message système qui n'est pas un jet est ignoré")
grouped = false
roll("Brakmar", 57)
M.advance(0.5)
check(not isOpen(), "hors groupe : rien ne s'ouvre")
LR:SetMode("roll")
M.advance(0.5)
check(has("Dés lancés à la main") and not has("57"), "hors groupe : le /roll n'est pas enregistré")
LR:Close()
grouped = true
M.advance(61)
roll("Brakmar", 57)
M.advance(0.5)
check(not isOpen(), "en groupe : un /roll isolé (sans objet lié) n'ouvre rien")
M.fireEvent("CHAT_MSG_SYSTEM", "Ysolde rolls 64 (1-100)")
M.advance(0.5)
check(isOpen(), "en groupe : un 2e joueur qui lance ouvre la fenêtre")
check(has("Dés lancés à la main") and has("Jets /roll"), "elle s'ouvre sur l'onglet /roll")
check(has("57"), "le dé 57 de Brakmar est affiché")
check(has("2 joueurs") and has("64"), "repli anglais « Ysolde rolls 64 (1-100) » reconnu (motifs en cache, repli toujours ajouté)")
check(has("Paladin") or has("PALADIN"), "classe de Ysolde trouvée via le roster")
check(nCards() == 1, "les deux jets sont dans la même série")
clearRolls()
check(nCards() == 0 and has("Aucun /roll"), "bouton Effacer : la liste est vidée")

section("/roll : carte, rangement, gagnant")
M.advance(61)
LR:Close()
M.fireEvent("CHAT_MSG_RAID", "On tire : |cnIQ4:|Hitem:18832::::::::|h[Marteau]|h|r")   -- forme des liens de Forever
M.advance(1)
roll("Brakmar", 57); roll("Ysolde", 92); roll("Kerrigane", 88); roll("Ysolde", 99)
M.advance(0.5)
check(isOpen(), "l'objet lié puis les jets ouvrent la fenêtre")
check(has("Marteau"), "l'objet lié dans le chat du raid donne son nom à la série")
check(not has("Jets /roll"), "la série n'est plus anonyme")
check(order() == "Ysolde,Kerrigane,Brakmar,Ysolde", "rangé du plus haut au plus bas, 2e jet en dernier (" .. order() .. ")")
check(textOf("gagne avec") == "3 joueurs · 1-100 · Ysolde gagne avec 92", "statut « 3 joueurs · 1-100 · Ysolde gagne avec 92 » (" .. tostring(textOf("gagne avec")) .. ")")
check(visibleChecks() == 1, "une seule coche de gagnant (" .. visibleChecks() .. ")")
check(has("2e jet"), "le 2e jet de Ysolde est marqué « 2e jet »")
check(has("(toi)"), "Brakmar est marqué « (toi) »")
check(has("Rôdeur") or has("Voleur") or has("ROGUE"), "classe de Kerrigane trouvée via party2")

section("/roll : égalité et bornes")
clearRolls()
M.advance(61)
roll("Morwen", 92); roll("Tilda", 92); roll("Kerrigane", 10)
M.advance(0.5)
check(has("égalité à 92 : relancer"), "égalité : « égalité à 92 : relancer »")
check(visibleChecks() == 0, "égalité : aucune coche")
check(not has("gagne avec"), "égalité : pas de gagnant annoncé")
roll("Morwen", 40); roll("Tilda", 71)
M.advance(0.5)
check(nCards() == 2 and has("Départage") and tostring(textOf("gagne avec")):find("Tilda gagne avec 71", 1, true) ~= nil,
    "les relances des ex aequo forment un départage qui désigne le gagnant (" .. tostring(textOf("gagne avec")) .. ")")
clearRolls()
M.advance(61)
roll("Brakmar", 20); roll("Ysolde", 35); roll("Tilda", 49, 1, 50)
M.advance(0.5)
check(textOf("gagne avec") == "3 joueurs · 1-100 · Ysolde gagne avec 35", "les bornes 1-50 ne gagnent pas quand 1-100 existe (" .. tostring(textOf("gagne avec")) .. ")")
check(has("1-50"), "le jet 1-50 reste affiché avec ses bornes")
check(visibleChecks() == 1, "une coche, sur le gagnant 1-100")

section("/roll : séries")
clearRolls()
M.advance(61)
roll("Brakmar", 10)
M.advance(0.5)
check(nCards() == 1, "un premier jet : une série")
M.advance(30)
roll("Ysolde", 20)
M.advance(0.5)
check(nCards() == 1, "30 s plus tard : même série")
M.advance(61)
roll("Tilda", 30)
M.advance(0.5)
check(nCards() == 2, "après 61 s de silence : nouvelle série")
M.advance(2)
M.fireEvent("CHAT_MSG_PARTY", "Suivant : |cff0070dd|Hitem:2140::::::::|h[Anneau]|h|r")
M.advance(1)
roll("Morwen", 40)
M.advance(0.5)
check(nCards() == 3 and has("Anneau"), "un nouvel objet lié après le dernier jet : nouvelle série nommée d'après lui")
roll("Tilda", 50)
M.advance(0.5)
check(nCards() == 3, "le jet suivant reste dans la série de l'objet")

section("/roll : valeurs secrètes et réglage")
errorsBefore = #M.errors
M.fireEvent("CHAT_MSG_SYSTEM", secret("Brakmar obtient un 57 (1-100)."))
M.fireEvent("CHAT_MSG_RAID", secret("|cffa335ee|Hitem:18832::::::::|h[Marteau]|h|r"))
M.advance(0.5)
check(#M.errors == errorsBefore, "texte secret : aucune erreur")
check(nCards() == 3, "texte secret : ignoré, aucune série ajoutée")
check(listening("CHAT_MSG_SYSTEM") and listening("CHAT_MSG_RAID") and listening("CHAT_MSG_PARTY_LEADER"),
    "par défaut : message système et chats de groupe écoutés")
ns:Set("lootRollsManual", false)
check(not listening("CHAT_MSG_SYSTEM") and not listening("CHAT_MSG_RAID") and not listening("CHAT_MSG_PARTY")
    and not listening("CHAT_MSG_RAID_WARNING"), "lootRollsManual faux : CHAT_MSG_SYSTEM et chats de groupe désinscrits")
check(listening("LOOT_HISTORY_UPDATE_DROP"), "les événements du butin restent écoutés")
ns:Set("lootRollsManual", true)
check(listening("CHAT_MSG_SYSTEM") and listening("CHAT_MSG_RAID") and listening("CHAT_MSG_PARTY"),
    "lootRollsManual vrai : réinscrits")

section("/roll : onglets et exemple")
LR:SetMode("loot")
M.advance(0.5)
check(has("VanCleef") and not has("Dés lancés à la main"), "SetMode(loot) : retour aux boss")
LR:Close()
LR:Demo()
LR:SetMode("roll")
check(has("Marteau de l'aube"), "Demo puis SetMode(roll) : l'exemple montre « Marteau de l'aube »")
LR:Close()
check(#M.errors == errorsBefore, "aucune erreur sur l'onglet /roll")

section("bilan"); M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
