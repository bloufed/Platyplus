-- Test du flux de butin (Float.lua) dans le simulateur, en mode strict
-- Usage : python -I dev\lua.py run dev\test_float.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end

-- Le simulateur ignore les couleurs (SetVertexColor / SetTextColor y sont vides) : on les enregistre pour les vérifier.
M.impl.SetVertexColor = function(f, r, g, b, a) local s = M.state(f); s.r, s.g, s.b, s.a = r, g, b, a end
M.impl.SetTextColor = function(f, r, g, b) local s = M.state(f); s.tr, s.tg, s.tb = r, g, b end
-- Le vrai GetStringWidth ne compte pas les codes de couleur ni de lien ; une icône |T...|t vaut environ deux lettres.
M.impl.GetStringWidth = function(f)
    local t = tostring(M.state(f).text)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  "):gsub("|H.-|h(.-)|h", "%1")
    return #t * 6
end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.01 end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Float.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.advance(0.1)
local Float = ns.Float
local feed, anchor = PlatyplusFeed, PlatyplusAnchor

local function S(f) return M.state(f) end
local function txt(fs) return tostring(S(fs).text) end
local function lastPoint(f) local p = S(f).points; return p[#p] end
local function posX(f) local p = lastPoint(f); return p and p[4] or 0 end
local function posY(f) local p = lastPoint(f); return p and p[5] or 0 end

-- lignes visibles, de la plus récente (sur l'ancre) à la plus ancienne
local function rows()
    local list = {}
    for _, f in ipairs(M.allFrames) do
        local s = S(f)
        if s.kind == "Frame" and s.parent == feed and s.shown then list[#list + 1] = f end
    end
    table.sort(list, function(a, b) return math.abs(a.ty or 0) < math.abs(b.ty or 0) end)
    return list
end
local function rowFrames()
    local n = 0
    for _, f in ipairs(M.allFrames) do if S(f).kind == "Frame" and S(f).parent == feed then n = n + 1 end end
    return n
end
local function findRow(sub)
    for _, r in ipairs(rows()) do
        if txt(r.title):find(sub, 1, true) then return r end
    end
end
local function clear()
    local d = ns.db.duration
    ns.db.duration = 0.01      -- écrit directement (sans ns:Set) : le flux endormi doit quand même le voir
    M.advance(0.2)
    ns.db.duration = d
end
local function printedHas(sub)
    for _, line in ipairs(M.printed) do if line:find(sub, 1, true) then return true end end
    return false
end
local function item(name, extra)
    local t = { icon = 100, name = name, qty = 1, quality = 1, type = 1, source = "loot" }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local EPIC = "|cffa335ee|Hitem:19019::::::::|h[Thunderfury]|h|r"
local GRAY = "|cff9d9d9d|Hitem:4865::::::::|h[Griffe brisée]|h|r"
local PA, PC, PO = " |cffc7c7cfpa|r", " |cffeda55fpc|r", " |cffffd100po|r"

section("chargement")
check(Float ~= nil and feed ~= nil and anchor ~= nil, "module, conteneur PlatyplusFeed et ancre PlatyplusAnchor créés")
check(S(feed).scripts.OnUpdate ~= nil, "un OnUpdate sur le conteneur")
check(not S(feed).shown, "conteneur caché au repos : l'OnUpdate ne tourne pas")
check(not S(anchor).shown, "ancre cachée hors déplacement")
check(Float.ROW_W == 300 and Float.ROW_H == 36, "cartes de 300 x 36")

---------------------------------------------------------------------------
section("une ligne par source")
ns:Set("rows", 12); ns:Set("duration", 30)
Float:Add({ icon = 101, link = EPIC, name = "Thunderfury", qty = 1, quality = 4, type = 1, source = "loot" })
Float:Add({ icon = 102, link = GRAY, name = GRAY, qty = 3, type = 1, price = 255, source = "sold" })
Float:Add(item("Barre de fer", { qty = 2, source = "crafted" }))
Float:Add(item("Potion", { source = "bought" }))
Float:Add(item("Lettre", { source = "mail" }))
Float:Add(item("Bottes", { quality = 2, source = "quest" }))
Float:Add(item("Gemme", { quality = 3, source = "trade" }))
Float:Add(item("Plume", { quality = 7, source = "received" }))
Float:Add({ icon = 109, name = "Message", source = "info" })
Float:Add({ icon = "coin", name = "Réparé : 1 po 12 pa 40 pc (guilde)", money = 11240, source = "repair", qty = 0, quality = 0, type = 2 })
Float:Add({ icon = "coin", name = "Quête : 2 pa 50 pc", money = 250, source = "quest", qty = 0, quality = 0, type = 2 })
Float:Add({ icon = "coin", name = "3 Argent\n20 Cuivre", qty = 0, quality = 0, type = 2, source = "loot" })
check(S(feed).shown, "conteneur affiché dès qu'il y a des lignes")
M.advance(0.5)
local list = rows()
check(#list == 12, "12 lignes visibles (" .. #list .. ")")

local epic = findRow("Thunderfury")
check(epic ~= nil and not txt(epic.title):find("[", 1, true), "objet épique : lien affiché sans crochets")
check(epic and txt(epic.tag) == "" and txt(epic.countText) == "" and txt(epic.value) == "", "loot : ni pastille, ni badge, ni prix")
check(epic and near(S(epic.accent).r, 0.64) and near(S(epic.accent).b, 0.93), "barre d'accent violette (ITEM_QUALITY_COLORS[4])")
check(epic and near(S(epic.border).g, 0.21), "bordure d'icône à la couleur de qualité")
check(epic and near(S(epic.glow).alpha, 0.40), "lueur épique derrière l'icône")
check(epic and S(epic.icon).texture == 101, "icône posée")
check(epic and posY(epic.title) == 0, "sans pastille : nom centré verticalement")

local sold = findRow("Griffe brisée")
check(sold and txt(sold.tag) == "Vendu", "vendu : pastille « Vendu »")
check(sold and txt(sold.countText) == "x3", "vendu : badge x3 (" .. (sold and txt(sold.countText) or "?") .. ")")
check(sold and txt(sold.value) == "2" .. PA .. " 55" .. PC, "vendu : prix 2 pa 55 pc (" .. (sold and txt(sold.value) or "?") .. ")")
check(sold and near(S(sold.accent).r, 0x9d / 255), "qualité absente : couleur lue dans le lien (gris)")
check(sold and posY(sold.title) == 7, "avec pastille : nom sur la ligne du haut")

local expected = {
    { "Barre de fer", "Fabriqué" }, { "Potion", "Acheté" }, { "Lettre", "Courrier" }, { "Bottes", "Quête" },
    { "Gemme", "Échangé" }, { "Plume", "Reçu" }, { "Message", "Info" },
}
for _, e in ipairs(expected) do
    local r = findRow(e[1])
    check(r and txt(r.tag) == e[2], e[1] .. " : pastille « " .. e[2] .. " » (" .. (r and txt(r.tag) or "absente") .. ")")
end
check(txt(findRow("Barre de fer").countText) == "x2", "fabriqué : badge x2")
local plume = findRow("Plume")
check(plume and near(S(plume.accent).g, 0.8) and near(S(plume.accent).b, 1), "qualité 7 absente de ITEM_QUALITY_COLORS : couleur de repli")
local crafted = findRow("Barre de fer")
local cc = ns.SOURCES.crafted.color
check(crafted and near(S(crafted.tag).tr, cc[1] + (1 - cc[1]) * 0.25) and near(S(crafted.tag).tg, cc[2] + (1 - cc[2]) * 0.25),
    "source écrite dans sa couleur (éclaircie)")

-- rien ne doit faire penser à un bouton : pas de cadre, pas d'ombre, pas de coins arrondis, pas de pastille,
-- pas de souris ; un voile qui s'efface vers la droite
local function textures(row)
    local list = {}
    for _, r in ipairs(S(row).regions) do if S(r).kind == "Texture" then list[#list + 1] = r end end
    return list
end
local cue
for _, t in ipairs(textures(epic)) do
    local file = tostring(S(t).texture):lower()
    if file:find("roundstroke", 1, true) or file:find("shadow", 1, true) or file:find("circle", 1, true)
        or file:find("\\round", 1, true) then cue = file end
end
check(epic and cue == nil, "aucun cadre, ombre, coin arrondi ni pastille (" .. tostring(cue) .. ")")
check(epic and #textures(epic) <= 8, "8 textures au plus par ligne (" .. (epic and #textures(epic) or "?") .. ")")
check(epic and not S(epic).mouse, "la ligne ne capte pas la souris")
local fade = epic and epic.scrim[2]
local tc = fade and S(fade).texcoord8
check(tc and tc[2] == 0 and tc[4] == 0 and tc[6] == 1 and tc[8] == 1, "voile : opaque à gauche, transparent à droite")
check(epic and near(S(epic.scrim[1]).a, 0.62) and near(S(epic.scrim[1]).r, 0.64 * 0.14), "voile sombre teinté de la qualité")
check(epic and near(S(epic.wash).r, 0.64) and near(S(epic.wash).a, 0.22), "lueur de qualité qui part du liseré")

local repair = findRow("Réparation")
check(repair and txt(repair.title) == "Réparation (guilde)", "réparation : titre (" .. (repair and txt(repair.title) or "?") .. ")")
check(repair and txt(repair.tag) == "Réparé", "réparation : pastille « Réparé »")
check(repair and txt(repair.value) == "-1" .. PO .. " 12" .. PA .. " 40" .. PC, "réparation : montant négatif (" .. (repair and txt(repair.value) or "?") .. ")")
check(repair and near(S(repair.value).tr, ns.THEME.bad[1]) and near(S(repair.value).tg, ns.THEME.bad[2]), "réparation : montant en rouge")
check(repair and near(S(repair.accent).r, ns.SOURCES.repair.color[1]), "argent : accent à la couleur de la source")

local questMoney = findRow("Récompense")
check(questMoney and txt(questMoney.tag) == "Quête" and txt(questMoney.value) == "2" .. PA .. " 50" .. PC, "argent de quête")
local lootMoney = findRow("Argent ramassé")
check(lootMoney and txt(lootMoney.value) == "3" .. PA .. " 20" .. PC, "argent ramassé « 3 Argent\\n20 Cuivre » lu et remis sur une ligne")
check(lootMoney and txt(lootMoney.tag) == "", "argent ramassé : pas de pastille")
check(lootMoney and near(S(lootMoney.accent).r, ns.SOURCES.money.color[1]) and near(S(lootMoney.accent).g, ns.SOURCES.money.color[2]),
    "argent ramassé : accent doré")
check(list[1] == lootMoney and posY(list[1]) == 0 and posY(list[2]) == 41 and posY(list[12]) == 41 * 11,
    "empilement vers le haut : la plus récente sur l'ancre, puis tous les 41 points")

---------------------------------------------------------------------------
section("fusion")
Float:Add({ icon = 102, link = GRAY, name = GRAY, qty = 2, type = 1, price = 170, source = "sold" })
check(sold.pulseAt ~= nil, "la ligne fusionnée « pulse »")
check(#rows() == 12, "pas de nouvelle ligne")
check(txt(sold.countText) == "x5", "quantités additionnées : x5 (" .. txt(sold.countText) .. ")")
check(txt(sold.value) == "4" .. PA .. " 25" .. PC, "prix additionnés : 4 pa 25 pc (" .. txt(sold.value) .. ")")
M.advance(0.15)
check(S(sold.icon).w > 28, "pulse : l'icône grossit (" .. S(sold.icon).w .. ")")
M.advance(0.5)
check(S(sold.icon).w == 28 and sold.pulseAt == nil, "pulse terminé : icône à 28")
Float:Add({ icon = "coin", name = "1 Argent\n5 Cuivre", qty = 0, quality = 0, type = 2, source = "loot" })
check(txt(lootMoney.value) == "4" .. PA .. " 25" .. PC, "argent ramassé cumulé (" .. txt(lootMoney.value) .. ")")
Float:Add({ icon = "coin", name = "Réparé : 1 pa", money = 100, source = "repair", qty = 0, type = 2 })
M.advance(0.5)
local perso
for _, r in ipairs(rows()) do if txt(r.title) == "Réparation" then perso = r end end
check(#rows() == 12 and perso and txt(perso.value) == "-1" .. PA and txt(repair.value):find("-1 |cffffd100po", 1, true) == 1,
    "réparation perso séparée de la réparation de guilde")

---------------------------------------------------------------------------
section("limite de lignes et pool")
clear()
check(#rows() == 0 and not S(feed).shown, "flux vidé, conteneur caché")
local framesBefore = rowFrames()
ns:Set("rows", 3)
for i = 1, 5 do Float:Add(item("Objet " .. i)) end
check(#rows() == 5, "les 2 lignes en trop sortent en fondu (encore visibles un instant)")
M.advance(0.5)
list = rows()
check(#list == 3, "3 lignes après la sortie (" .. #list .. ")")
check(list[1] and txt(list[1].title):find("Objet 5", 1, true) and txt(list[3].title):find("Objet 3", 1, true), "on garde les 3 plus récentes")
check(posY(list[1]) == 0 and posY(list[2]) == 41 and posY(list[3]) == 82, "réempilées à 0 / 41 / 82")
for i = 1, 30 do Float:Add(item("Encore " .. i)); M.advance(0.05) end
M.advance(0.5)
check(rowFrames() == framesBefore, "lignes réutilisées : aucune frame créée (" .. framesBefore .. " -> " .. rowFrames() .. ")")
ns:Set("rows", 1); M.advance(0.5)
check(#rows() == 1 and txt(rows()[1].title):find("Encore 30", 1, true), "réglage rows réduit en direct")
ns:Set("rows", 3)
Float:Add(item("Lin")); Float:Add(item("Lin", { source = "crafted" }))
local lin = 0
for _, r in ipairs(rows()) do if txt(r.title):find("Lin", 1, true) then lin = lin + 1 end end
check(lin == 2, "même objet, autre source : deux lignes")

---------------------------------------------------------------------------
section("sens d'empilement (feedGrow)")
clear(); ns:Set("rows", 3)
Float:Add(item("A")); Float:Add(item("B")); Float:Add(item("C")); M.advance(0.6)
local a, b, c = findRow("A"), findRow("B"), findRow("C")
check(posY(c) == 0 and posY(b) == 41 and posY(a) == 82, "UP : C 0, B 41, A 82")
ns:Set("feedGrow", "DOWN")
M.advance(0.05)
check(posY(b) < 41 and posY(b) > -41, "déplacement fluide, pas de saut (" .. posY(b) .. ")")
M.advance(0.6)
check(posY(c) == 0 and posY(b) == -41 and posY(a) == -82, "DOWN : C 0, B -41, A -82")
Float:Add(item("D")); M.advance(0.6)
check(posY(findRow("D")) == 0 and posY(c) == -41 and posY(b) == -82 and findRow("A") == nil, "DOWN : la nouvelle ligne pousse les autres vers le bas")
ns:Set("feedGrow", "UP"); M.advance(0.6)
check(posY(b) == 82, "retour à UP")

---------------------------------------------------------------------------
section("entrée, sortie, délai")
clear(); ns:Set("duration", 2)
Float:Add(item("Nouveau"))
local row = findRow("Nouveau")
check(S(row).alpha == 0 and posX(row) == 36, "entrée : transparente et décalée de 36 points")
M.advance(0.1)
check(S(row).alpha > 0 and S(row).alpha < 1 and posX(row) > 0 and posX(row) < 36, "entrée en cours : glisse et apparaît")
M.advance(0.3)
check(S(row).alpha == 1 and posX(row) == 0, "entrée finie : opaque, en place")
M.advance(1.2)
check(S(row).alpha > 0 and S(row).alpha < 1, "fin de vie : fondu en cours (" .. S(row).alpha .. ")")
M.advance(0.6)
check(#rows() == 0 and not S(feed).shown, "expirée : ligne rendue au pool, OnUpdate arrêté")
Float:Add(item("Relance")); M.advance(1.5)
Float:Add(item("Relance")); M.advance(1.0)
check(findRow("Relance") ~= nil and S(findRow("Relance")).alpha == 1, "une fusion relance le délai")
M.advance(1.5)
check(findRow("Relance") == nil, "puis la ligne expire")
local getCenter = M.impl.GetCenter
M.impl.GetCenter = function() return nil end   -- ancre jamais affichée : position lue dans les réglages
ns.db.point, ns.db.x = "TOPLEFT", 100
Float:Add(item("Gauche"))
check(posX(findRow("Gauche")) == -36, "ancre à gauche de l'écran : la ligne arrive par la gauche")
M.impl.GetCenter = getCenter
ns.db.point, ns.db.x = "CENTER", 260
clear()

---------------------------------------------------------------------------
section("repos : rien n'est recalculé")
ns:Set("duration", 30)
for i = 1, 3 do Float:Add(item("Calme " .. i)) end
M.advance(1)
local calls = 0
local impl = M.impl
local sp, sa, ss = impl.SetPoint, impl.SetAlpha, impl.SetSize
impl.SetPoint = function(...) calls = calls + 1; return sp(...) end
impl.SetAlpha = function(...) calls = calls + 1; return sa(...) end
impl.SetSize = function(...) calls = calls + 1; return ss(...) end
M.advance(2)
impl.SetPoint, impl.SetAlpha, impl.SetSize = sp, sa, ss
check(calls == 0, "lignes immobiles : aucun appel SetPoint / SetAlpha / SetSize (" .. calls .. ")")

---------------------------------------------------------------------------
section("mémoire : aucune table créée par image")
clear(); ns:Set("rows", 6); ns:Set("duration", 2)
for i = 1, 6 do Float:Add(item("Mem " .. i)) end
M.advance(0.3)
for i = 1, 3 do Float:Add(item("Mem " .. i)) end   -- fusions : pulses
Float:Add(item("Mem 7"))                           -- une ligne sort, les autres glissent
ns:Set("feedGrow", "DOWN")                         -- tout le monde se déplace
local jit = rawget(_G, "jit")
if jit then jit.off(); jit.flush() end
-- le simulateur crée des tables dans SetPoint / ClearAllPoints (le vrai jeu non) : on les neutralise pendant la mesure
local cap = impl.ClearAllPoints
impl.SetPoint, impl.ClearAllPoints = function() end, function() end
local onUpdate = S(feed).scripts.OnUpdate
collectgarbage("collect"); collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 400 do
    M.time = M.time + 0.01
    onUpdate(feed, 0.01)
end
local grown = collectgarbage("count") - before
collectgarbage("restart")
impl.SetPoint, impl.ClearAllPoints = sp, cap
if jit then jit.on() end
check(grown < 0.5, string.format("400 images (entrée, pulse, glissement, fondu, expiration) : %.3f Ko alloués", grown))
check(#rows() == 0 or not S(feed).shown, "tout a expiré pendant la mesure")
ns:Set("feedGrow", "UP")
clear()

---------------------------------------------------------------------------
section("déplacement de l'ancre")
Float:ToggleMove()
check(S(anchor).shown and Float:IsMoving(), "ToggleMove affiche l'ancre")
check(printedHas("glisse le cadre"), "message d'aide affiché")
anchor:ClearAllPoints()
anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100.4, -200.6)
M.fire(anchor, "OnDragStart"); M.fire(anchor, "OnDragStop")
check(ns.db.point == "TOPLEFT" and ns.db.relPoint == "TOPLEFT" and ns.db.x == 100 and ns.db.y == -201,
    "position sauvegardée (" .. tostring(ns.db.point) .. " " .. tostring(ns.db.x) .. " " .. tostring(ns.db.y) .. ")")
local p = lastPoint(anchor)
check(#S(anchor).points == 1 and p[1] == "TOPLEFT" and p[2] == UIParent and p[4] == 100 and p[5] == -201, "ancre replacée une seule fois")
M.fire(anchor, "OnMouseUp", "RightButton")
check(not S(anchor).shown and not Float:IsMoving(), "clic droit : déplacement validé")
check(printedHas("position du flux enregistrée"), "message de validation")
ns:Set("x", 50)
check(posX(anchor) == 50, "réglage x appliqué via OnChange")
SlashCmdList.PLATYPLUS("move"); check(S(anchor).shown, "/pp move ouvre")
SlashCmdList.PLATYPLUS("move"); check(not S(anchor).shown, "/pp move ferme")
SlashCmdList.PLATYPLUS("reset")
check(ns.db.point == "CENTER" and ns.db.x == 260 and lastPoint(anchor)[1] == "CENTER" and posX(anchor) == 260, "/pp reset remet la position par défaut")
check(lastPoint(feed)[2] == anchor, "le flux est accroché à l'ancre")

---------------------------------------------------------------------------
section("échelle")
ns:Set("floatScale", 1.5)
local box = S(anchor).frames[1]
check(S(feed).scale == 1.5, "conteneur à l'échelle 1,5")
check(S(anchor).w == 450 and S(anchor).h == 54 and box and S(box).scale == 1.5, "ancre agrandie avec le flux (450 x 54)")
ns:Set("floatScale", 1)
check(S(feed).scale == 1 and S(anchor).w == 300, "retour à l'échelle 1")

---------------------------------------------------------------------------
section("démonstration (Test)")
ns:Set("rows", 12); ns:Set("duration", 30)
Float:Test()
M.advance(0.05)
check(#rows() == 1, "les lignes arrivent en cascade")
M.advance(2)
list = rows()
check(#list == 7, "7 lignes, une par source (" .. #list .. ")")
local pills = {}
for _, r in ipairs(list) do pills[#pills + 1] = txt(r.tag) end
check(table.concat(pills, ",") == ",Vendu,Fabriqué,Quête,Acheté,Quête,Réparé", "pastilles : " .. table.concat(pills, ","))
check(txt(list[1].title):find("Lame du crépuscule", 1, true) and near(S(list[1].accent).r, 0.64), "épique en dernier, sur l'ancre")
check(txt(findRow("Rouleau").countText) == "x4", "fusion de démonstration : x4")
check(txt(findRow("Crâne").value):find("55", 1, true) ~= nil, "gris vendu avec son prix")
clear(); ns:Set("rows", 6)
Float:Test(); M.advance(2)
check(#rows() == 6 and findRow("Réparation") == nil, "avec 6 lignes max, la plus ancienne (réparation) sort")
clear()

---------------------------------------------------------------------------
section("anciens champs et cas limites")
Float:Add({ icon = 1, name = "Truc", quality = 1, type = 1, prefix = "|cffff8080Vendu|r " })
check(findRow("Truc") and txt(findRow("Truc").tag) == "Vendu", "ancien champ prefix reconnu : « Vendu »")
Float:Add({ icon = 1, name = "Bidule", quality = 1, type = 1, prefix = "Butin de raid : " })
check(findRow("Bidule") and txt(findRow("Bidule").tag) == "Butin de raid", "prefix inconnu : pastille neutre")
Float:Add({ icon = 1, name = "Lot", quality = 1, type = 1, source = "sold", prefix = "|cffff8080Reçu|r " })
check(findRow("Lot") and txt(findRow("Lot").tag) == "Vendu", "prefix ignoré quand source est donnée")
Float:Add({ name = "Beaucoup\nd'argent", type = 2, source = "loot" })
local odd = findRow("Beaucoup")
check(odd and txt(odd.title):find("Beaucoup d'argent", 1, true) and txt(odd.value) == "", "argent illisible : texte remis sur une ligne")
Float:Add({ name = "1 234 Or", type = 2, source = "loot" })
check(findRow("1 234 Or") ~= nil, "nombre à séparateur non compris : affiché tel quel, pas de montant faux")
Float:Add(item(string.rep("Nom très long ", 8), { qty = 12, price = 123456 }))
local long = findRow("Nom très long")
check(long and S(long.title).w >= 60 and S(long.title).w < 300 - 50 - 12 - 100,
    "nom trop long : tronqué avant le badge et le prix (" .. (long and S(long.title).w or "?") .. ")")
local short = findRow("Truc")
check(short and S(short.title).w == 0, "nom court : largeur libre (pas tronqué)")
check(long and txt(long.value) == "12" .. PO .. " 34" .. PA .. " 56" .. PC, "prix en or (" .. (long and txt(long.value) or "?") .. ")")
Float:Add(nil); Float:Add("texte")
check(true, "Add(nil) et Add(texte) sans erreur")
ns:Set("floatLoot", false)
check(#rows() == 0 and not S(feed).shown, "flux coupé : lignes retirées")
Float:Add(item("Ignoré"))
check(#rows() == 0, "flux coupé : Add ignoré")
Float:Test(); M.advance(2)
check(#rows() == 6, "Test montre l'aperçu même flux coupé")
ns:Set("floatLoot", true)
ns:ResetAll(true)
M.advance(1)

---------------------------------------------------------------------------
section("icônes de pièces")
-- 2e chargement (comme un /reload) sur un client où le code d'argent de Blizzard existe
def("GetCoinTextureString", function() return "" end)
local ns2 = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Float.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
feed = PlatyplusFeed
ns2.db.duration = 30
ns2.Float:Add({ icon = 1, link = GRAY, qty = 1, type = 1, price = 12345, source = "sold" })
local v = txt(findRow("Griffe").value)
check(v == "1|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t 23|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t 45|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
    "prix avec les icônes de pièces (" .. v .. ")")
-- 3e chargement : le client dit que l'icône n'existe pas -> repli texte
def("GetFileIDFromPath", function() return nil end)
local ns3 = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Float.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
feed = PlatyplusFeed
ns3.Float:Add({ icon = 1, link = GRAY, qty = 1, type = 1, price = 12345, source = "sold" })
v = txt(findRow("Griffe").value)
check(v == "1" .. PO .. " 23" .. PA .. " 45" .. PC, "icône absente : repli « po / pa / pc » (" .. v .. ")")
M.advance(1)

---------------------------------------------------------------------------
section("bilan")
local extra = {}
for _, name in ipairs(M.newGlobals) do
    if not (name:find("^SLASH_PLATYPLUS") or name == "PlatyplusDB") then extra[#extra + 1] = name end
end
check(#extra == 0, "aucune globale en dehors de celles du noyau (" .. table.concat(extra, ", ") .. ")")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
