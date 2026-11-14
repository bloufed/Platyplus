-- Test de la fenêtre d'options (UIWidgets / UIPages / UIConfig) dans le simulateur
-- Usage : python -I dev\lua.py run dev\test_ui.lua <dossier Platyplus> <dossier dev> [fichiers séparés par des virgules]
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
M.enableStrict()

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

-- Échap sur Forever : système par priorités (Blizzard_GameMenuEsc). Un addon NE DOIT PAS s'y inscrire (taint :
-- « Platyplus a été bloqué... » constaté en jeu) ; on compte les inscriptions pour le vérifier.
local escRegistrations = 0
def("GameMenuEscPriority", { Dialog = 1, Menu = 2, Casting = 4, FrameworkPre = 5, Framework = 6, AddOn = 8, AddOnPost = 9 })
def("RegisterGameMenuEscHandler", function() escRegistrations = escRegistrations + 1 end)
-- ce que fait le jeu à Échap pour les fenêtres d'addons : CloseAllWindows -> CloseSpecialWindows (UISpecialFrames)
local function gameEscape()
    local found = false
    for _, name in pairs(UISpecialFrames) do
        local frame = rawget(_G, name)
        if frame and frame:IsShown() then
            frame:Hide()
            found = true
        end
    end
    return found
end

-- API réelles absentes du simulateur (ajoutées ici, pas dans wowmock.lua)
def("C_Item", {
    GetItemInfoInstant = function(id) id = tonumber(tostring(id):match("(%d+)")) ; if id and id < 100000 then return id, "x", "y", "", 134400 end end,
    GetItemNameByID = function(id) return "Objet test " .. id end,
    RequestLoadItemDataByID = function() end,
})

-- repli d'icône : le fichier du dernier onglet « n'existe pas » (SetTexture renvoie false comme le vrai jeu)
local realSetTexture = M.impl.SetTexture
M.impl.SetTexture = function(f, t)
    realSetTexture(f, t)
    if type(t) == "string" and t:find("Trade_Engineering", 1, true) then return false end   -- (icône de l'onglet Avancé)
    return true
end

local files = {}
if ARGS[3] then
    for f in ARGS[3]:gmatch("[^,]+") do files[#files + 1] = f end
else
    for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
        local f = line:match("^([%w_%.]+%.lua)%s*$")
        if f then files[#files + 1] = f end
    end
end
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
-- deux dictionnaires (le .toc les liste sous Locales\, que la boucle ci-dessus ne prend pas) : changement de langue
for _, code in ipairs({ "enUS", "deDE" }) do assert(loadfile(ADDON_DIR .. "\\Locales\\" .. code .. ".lua"))("Platyplus", ns) end
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(0.2)

local UI, W, Pages = ns.UI, ns.W, ns.Pages
local S = M.state


-- descend la hiérarchie : f est-il dans la fenêtre d'options ?
local function inside(f, root)
    local p = f
    for _ = 1, 40 do
        if p == root then return true end
        local s = S(p)
        if not s or not s.parent or s.parent == p then return false end
        p = s.parent
    end
    return false
end

local function rowsOf(page)
    local list = {}
    for _, card in ipairs(page.widgets) do
        for _, w in ipairs(card.widgets or {}) do list[#list + 1] = { card = card, w = w } end
    end
    return list
end

---------------------------------------------------------------------------
section("API et géométrie")
check(UI and UI.Init and UI.Open and UI.Close and UI.Toggle and UI.Refresh, "ns.UI : Init, Open, Close, Toggle, Refresh")
check(Pages:Count() == 14, "14 onglets (" .. Pages:Count() .. ")")
check(Pages:GetInfo(1).id == "modes", "1er onglet : Modes (ce qu'on voit à la 1re ouverture)")
check(W.ROW_W + 2 * W.CARD_PAD == W.PAGE_W, "largeur ligne + marges = largeur carte")
check(rawget(_G, "PlatyplusMinimapButton") == nil, "aucun bouton de minicarte")
check(UI.frame == nil, "fenêtre pas construite avant la première ouverture")

local before = #M.allFrames
UI:Open()
local f = UI.frame
check(f and S(f).shown, "fenêtre ouverte")
check(S(f).w == 990 and S(f).h == 780, "taille 990 x 780")
check(S(f).alpha < 1, "apparition en fondu")
M.advance(0.3)
check(S(f).alpha == 1 and S(f).scripts.OnUpdate == nil, "fondu terminé, OnUpdate retiré")
local found = false
for _, n in ipairs(UISpecialFrames) do if n == "PlatyplusConfigFrame" then found = true end end
check(found, "fermeture par Échap (UISpecialFrames)")
M.realPrint("   objets créés à la 1re ouverture : " .. (#M.allFrames - before))

---------------------------------------------------------------------------
section("présentation de bienvenue (première installation)")
check(rawget(_G, "PlatyplusWelcome") == nil, "pas tout de suite : un instant après l'arrivée en jeu")
M.advance(2.5)
local welcome = rawget(_G, "PlatyplusWelcome")
check(welcome ~= nil and welcome:IsShown(), "première connexion : la présentation s'ouvre seule")
check(ns.db.welcomeSeen == true, "marquée comme vue (elle ne reviendra pas d'elle-même)")
check(welcome.steps and #welcome.steps == 10, "visite en 10 étapes dans la colonne de gauche (" .. tostring(welcome.steps and #welcome.steps) .. ")")
check(welcome.step == 1 and welcome.start:IsShown() and welcome.go:IsShown() and not welcome.back:IsShown(),
    "étape 1 : présentation, boutons « Commencer la visite » et « Passer la visite »")
local hasLogo = false
for _, r in ipairs(S(welcome.pages[1]).regions) do if S(r).texture == ns.LOGO then hasLogo = true end end
check(hasLogo, "logo Platyplus en tête de la présentation")
M.fire(welcome.start, "OnClick", "LeftButton")
check(welcome.step == 2 and welcome.next:IsShown() and welcome.back:IsShown(), "« Commencer » : étape 2 (le mode), Précédent / Suivant")
local picker = welcome.pages[2].widgets and welcome.pages[2].widgets[1]
check(picker and picker.tiles and #picker.tiles == 4, "étape 2 : quatre modes à choisir")

-- modes prêts à l'emploi
section("modes prêts à l'emploi")
local function tileOf(id) for _, t in ipairs(picker.tiles) do if t.mode.id == id then return t end end end
check(ns:CurrentMode() == "recommended" and tileOf("recommended").active, "au départ : mode Recommandé (= réglages par défaut), tuile surlignée")
for _, mode in ipairs(ns.MODES) do
    for _, key in ipairs(ns.ModeKeys()) do
        if type(ns:ModeValue(mode, key)) ~= "boolean" then check(false, "mode " .. mode.id .. " : " .. key .. " n'est pas un interrupteur") end
    end
    for key in pairs(mode.set) do check(type(ns.DEFAULTS[key]) == "boolean", "mode " .. mode.id .. " : clé connue " .. key) end
end
M.fire(tileOf("complete"), "OnClick", "LeftButton")
check(ns:CurrentMode() == "complete" and ns.db.acceptSummon and ns.db.autoOpenMail and ns.db.instantLoot,
    "clic sur Complet : appliqué tout de suite (invocations, courrier... allumés)")
check(tileOf("complete").active and not tileOf("recommended").active, "la tuile Complet est surlignée")
ns:Set("procAlert", false)
check(ns:CurrentMode() == nil and not tileOf("complete").active, "un réglage changé : réglages personnalisés, plus aucune tuile surlignée")
check(S(picker.status).text:find("Complet", 1, true) ~= nil, "ligne d'état : personnalisés à partir de Complet")
M.fire(tileOf("minimal"), "OnClick", "LeftButton")
check(tileOf("minimal").armed and ns.db.procAlert == false and ns.db.interact == true, "réglages personnalisés : 1er clic = confirmation demandée, rien ne change")
M.advance(3.5)
check(not tileOf("minimal").armed, "la demande de confirmation s'efface après 3 s")
M.fire(tileOf("minimal"), "OnClick", "LeftButton")
M.fire(tileOf("minimal"), "OnClick", "LeftButton")
check(ns:CurrentMode() == "minimal" and not ns.db.interact and not ns.db.plates and not ns.db.chatWindow and ns.db.launcher
    and not ns.db.dock, "Minimal (2e clic) : tout coupé sauf l'icône")
check(ns.db.key == "F" and ns.db.swingOffHand == true, "un mode ne touche ni la touche ni les sous-réglages hors liste")
M.inCombat = true
local okCombat = ns:ApplyMode("recommended")
M.inCombat = false
check(not okCombat and ns:CurrentMode() == "minimal", "refusé en combat")
SlashCmdList.PLATYPLUS("mode immersif")
check(ns:CurrentMode() == "immersive" and ns.db.questWindow and not ns.db.procAlert and ns.db.hideErrors
    and not ns.db.gossipOptions, "/pp mode immersif")
SlashCmdList.PLATYPLUS("mode n'importe")
check(ns:CurrentMode() == "immersive", "/pp mode inconnu : rien ne change")
M.fire(tileOf("recommended"), "OnClick", "LeftButton")
local same = true
for _, key in ipairs(ns.ModeKeys()) do if ns.db[key] ~= ns.DEFAULTS[key] then same = false end end
check(same and ns:CurrentMode() == "recommended" and ns.db.mode == "recommended", "retour à Recommandé : tous les interrupteurs par défaut")

section("visite guidée (suite)")
M.fire(welcome.next, "OnClick", "LeftButton")
check(welcome.step == 3 and welcome.pages[3].widgets and welcome.pages[3].widgets[1] ~= nil, "étape 3 : capture de la touche d'interaction")
for _ = 4, 10 do M.fire(welcome.next, "OnClick", "LeftButton") end
check(welcome.step == 10 and welcome.open:IsShown() and welcome.finish:IsShown() and not welcome.next:IsShown(),
    "dernière étape : « Ouvrir les options » et « Terminer »")
M.fire(welcome.steps[6], "OnClick", "LeftButton")
check(welcome.step == 6, "clic dans la colonne : va à l'étape (Butin)")
local loot = welcome.pages[6].widgets
check(loot and #loot == 3, "étape Butin : trois réglages rapides")
local before = ns.db.instantLoot
M.fire(loot[1], "OnClick", "LeftButton")
check(ns.db.instantLoot == not before, "un interrupteur de la visite change le réglage")
M.fire(loot[1], "OnClick", "LeftButton")
check(ns.db.instantLoot == before, "et le remet")
for _, page in pairs(welcome.pages) do
    for _, w in ipairs(page.widgets or {}) do
        if w.opts and w.opts.key then check(ns.DEFAULTS[w.opts.key] ~= nil, "réglage rapide connu : " .. w.opts.key) end
    end
end
-- lien « onglet « Butin » › » : options ouvertes sur cet onglet, la visite reprendra ici
local link
for _, c in ipairs(S(welcome.pages[6]).frames) do
    if S(c).scripts and S(c).scripts.OnClick and c ~= welcome.pages[6] then
        for _, r in ipairs(S(c).regions) do
            if type(S(r).text) == "string" and S(r).text:find("Butin", 1, true) then link = c end
        end
    end
end
check(link ~= nil, "lien vers l'onglet Butin")
if link then
    M.fire(link, "OnClick", "LeftButton")
    check(not welcome:IsShown() and UI.frame and UI.frame:IsShown(), "le lien ferme la visite et ouvre les options")
    check(Pages:GetInfo(UI.current).id == "loot", "options ouvertes sur l'onglet Butin")
    UI:ShowWelcome()
    check(welcome:IsShown() and welcome.step == 6, "/pp bienvenue reprend à l'étape du lien")
end
M.fire(welcome.finish, "OnClick", "LeftButton")
UI:ShowWelcome()
check(welcome.step == 1, "après une fermeture normale, la visite repart du début")
UI:Close()
gameEscape()
check(not welcome:IsShown(), "Échap ferme la présentation (UISpecialFrames)")
check(escRegistrations == 0, "aucune inscription au système d'Échap de Blizzard (source de « Platyplus a été bloqué »)")
SlashCmdList.PLATYPLUS("bienvenue")
check(welcome:IsShown(), "/pp bienvenue la réaffiche")
M.fire(welcome.open, "OnClick", "LeftButton")
check(not welcome:IsShown() and UI.frame and UI.frame:IsShown(), "« Ouvrir les options » : présentation fermée, options ouvertes")
M.advance(5)
check(not welcome:IsShown(), "elle ne se rouvre pas toute seule")

section("langue, en tête de la visite")
check(ns.DEFAULTS.language == "enUS", "installation neuve : Platyplus démarre en anglais")
UI:ShowWelcome(1)
local function chip(fr, code)
    for _, b in ipairs(fr.pages[1].langBlock and fr.pages[1].langBlock.chips or {}) do if b.code == code then return b end end
end
check(welcome.pages[1].langBlock and #welcome.pages[1].langBlock.chips == 7, "page d'accueil : une pastille par langue (7)")
M.fire(chip(welcome, "enUS"), "OnClick", "LeftButton")
local w2 = rawget(_G, "PlatyplusWelcome")
check(ns.db.language == "enUS" and ns.lang == "enUS", "clic sur English : langue changée tout de suite")
check(w2 ~= welcome and w2:IsShown() and not welcome:IsShown() and w2.step == 1, "la visite est reconstruite dans la nouvelle langue")
check(S(w2.steps[1].label).text == "Welcome", "colonne des étapes en anglais (" .. tostring(S(w2.steps[1].label).text) .. ")")
M.fire(chip(w2, "frFR"), "OnClick", "LeftButton")
welcome = rawget(_G, "PlatyplusWelcome")
check(ns.lang == "frFR" and ns.db.language == "frFR" and S(welcome.steps[1].label).text == "Bienvenue", "retour en français")
local esc = 0
for _, n in ipairs(UISpecialFrames) do if n == "PlatyplusWelcome" then esc = esc + 1 end end
check(esc == 1, "Échap : la visite reconstruite n'est inscrite qu'une fois")
welcome:Hide()
check(ns.Strings.deDE == nil and ns.Strings.enUS ~= nil, "visite fermée : dictionnaires inutiles libérés (anglais gardé)")
UI:ShowWelcome(1)
M.fire(chip(welcome, "deDE"), "OnClick", "LeftButton")
check(ns.db.language == "deDE" and ns.lang == "frFR" and rawget(_G, "PlatyplusWelcome") == welcome,
    "dictionnaire déjà libéré : choix gardé pour le /reload, la visite reste")
ns:Set("language", "frFR")
UI.langSwitched = nil
welcome:Hide()

---------------------------------------------------------------------------
section("onglets")
for i = 1, Pages:Count() do
    local n0 = #M.allFrames
    UI:SelectTab(i)
    M.advance(0.3)
    local page = UI.pages[i]
    check(page and S(page).shown and (page.contentHeight or 0) > 30,
        "onglet " .. i .. " « " .. Pages:GetTitle(i) .. " » : " .. #page.widgets .. " cartes, hauteur " .. math.floor(page.contentHeight or 0)
        .. ", " .. (#M.allFrames - n0) .. " objets")
    check(ns.db.uiTab == i, "onglet mémorisé (uiTab = " .. tostring(ns.db.uiTab) .. ")")
    check(S(page).alpha == 1, "fondu de page terminé")
end
local advIndex = 0   -- onglet « Avancé », cherché par son id (sa place change quand on ajoute un onglet)
for i, def in ipairs(Pages.list) do if def.id == "advanced" then advIndex = i end end
check(S(UI.tabs[advIndex].icon).texture == W.TEX.circle, "icône manquante (onglet Avancé) -> pastille avec l'initiale")

-- onglet par son id (leur ordre change quand on réorganise la barre latérale)
local function tabOf(id)
    for i, def in ipairs(Pages.list) do if def.id == id then return i end end
end

section("barre latérale : groupes et sommaire")
local groups = {}
for _, def in ipairs(Pages.list) do
    check(type(def.group) == "string", "onglet « " .. def.title .. " » rangé dans un groupe")
    if groups[#groups] ~= def.group then groups[#groups + 1] = def.group end
end
local seenGroup, splitGroup = {}, false
for _, g in ipairs(groups) do if seenGroup[g] then splitGroup = true end seenGroup[g] = true end
check(not splitGroup and #groups == 4, "4 groupes, chacun d'un seul tenant : " .. table.concat(groups, ", "))
check(UI.groupLabels and UI.groupLabels["Objets"] and S(UI.groupLabels["Objets"]).text == "OBJETS", "titres de groupe en capitales")
local combat = tabOf("resources")
UI:SelectTab(combat)
M.advance(0.3)
local subs = {}
for _, s in ipairs(UI.subs) do if S(s).shown then subs[#subs + 1] = s end end
check(#subs >= 5 and subs[1].card and subs[1].text:GetText() == "Barre de coups blancs", "sommaire de Combat sous son onglet : " .. #subs .. " cartes")
check(select(5, UI.tabs[combat + 1]:GetPoint(1)) < select(5, UI.tabs[combat]:GetPoint(1)) - 32 - 20 * #subs,
    "les onglets suivants descendent sous le sommaire")
check(subs[1].active and not subs[2].active, "en haut de la page : la première carte allumée")
M.fire(subs[3], "OnClick", "LeftButton")
M.advance(1)
check(math.abs((UI.scrollPos or 0) - math.min(UI:ScrollRange(), 8 + subs[3].card.stackY - 6)) < 1 and subs[3].active,
    "clic sur une entrée : la page défile jusqu'à sa carte, allumée")
local last = subs[#subs]
UI:SetScroll(UI:ScrollRange())
check(last.active, "tout en bas : la dernière carte allumée")
UI:SelectTab(tabOf("game"))
local shownSubs = 0
for _, s in ipairs(UI.subs) do if S(s).shown then shownSubs = shownSubs + 1 end end
check(shownSubs == 2 or shownSubs == 0, "autre onglet : le sommaire de Combat se referme (" .. shownSubs .. " entrées)")

---------------------------------------------------------------------------
section("interrupteurs, curseurs, menus")
local switches, sliders, dropdowns = 0, 0, 0
local nSw, nSl, nDd = 0, 0, 0
for i = 1, Pages:Count() do
    UI:SelectTab(i)
    for _, e in ipairs(rowsOf(UI.pages[i])) do
        local w = e.w
        local key = w.opts and w.opts.key
        if key and w.isEnabled then
            if w.knob then nSw = nSw + 1 elseif w.opts.min then nSl = nSl + 1 elseif w.OnMenuClosed then nDd = nDd + 1 end
        end
        if key and w.knob and w.isEnabled then
            local v0 = ns.db[key]
            M.fire(w, "OnClick", "LeftButton")
            local v1 = ns.db[key]
            M.fire(w, "OnClick", "LeftButton")
            if v1 == not v0 and ns.db[key] == v0 then switches = switches + 1
            else check(false, "interrupteur " .. key) end
        elseif key and w.opts.min and w.isEnabled then
            local slider
            for _, c in ipairs(S(w).frames) do if S(c).kind == "Slider" then slider = c end end
            M.fire(slider, "OnValueChanged", w.opts.max)
            local okMax = math.abs((ns.db[key] or 0) - w.opts.max) < 1e-6
            M.fire(w, "OnMouseUp", "RightButton")
            local okDef = ns.db[key] == ns.DEFAULTS[key]
            if okMax and okDef then sliders = sliders + 1
            else check(false, "curseur " .. key .. " (max " .. tostring(okMax) .. ", défaut " .. tostring(okDef) .. ")") end
        elseif key and w.OnMenuClosed and w.isEnabled then
            local v0 = ns.db[key]
            M.fire(w, "OnClick", "LeftButton")
            -- la liste partagée est le seul cadre FULLSCREEN_DIALOG de niveau 120
            local menu
            for _, fr in ipairs(M.allFrames) do
                local s = S(fr)
                if s.strata == "FULLSCREEN_DIALOG" and s.level == 120 then menu = fr end
            end
            local items = {}
            for _, c in ipairs(S(menu).frames) do if S(c).shown and S(c).scripts.OnClick then items[#items + 1] = c end end
            local target = items[#items]
            for _, it in ipairs(items) do if it.value ~= v0 then target = it break end end
            M.fire(target, "OnClick", "LeftButton")
            local changed = ns.db[key] == target.value and not S(menu).shown and not w.open
            ns:Set(key, v0)
            if changed then dropdowns = dropdowns + 1 else check(false, "menu " .. key) end
        end
    end
end
check(switches == nSw and nSw >= 45, "interrupteurs qui basculent la bonne clé : " .. switches .. " / " .. nSw)
check(sliders == nSl and nSl >= 10, "curseurs (max puis clic droit = défaut) : " .. sliders .. " / " .. nSl)
check(dropdowns == nDd and nDd >= 5, "menus déroulants (choix appliqué, liste refermée) : " .. dropdowns .. " / " .. nDd)

M.realPrint("-- sous-options grisées")
ns:Set("floatLoot", false)
UI:SelectTab(tabOf("loot"))
local grey
for _, e in ipairs(rowsOf(UI.pages[tabOf("loot")])) do if e.w.opts and e.w.opts.key == "rows" then grey = e.w end end
check(grey and grey.isEnabled == false, "« Lignes au maximum » grisé quand le flux est coupé")
local v = ns.db.rows
for _, c in ipairs(S(grey).frames) do if S(c).kind == "Slider" then M.fire(c, "OnValueChanged", 12) end end
check(ns.db.rows == v, "un curseur grisé n'écrit rien")
ns:Set("floatLoot", true)
check(grey.isEnabled == true, "réactivé quand le flux revient")

M.realPrint("-- ligne couleur")
do
    local cur, got, on = { 1, 1, 1 }, 0, true
    local host = CreateFrame("Frame", nil, UIParent)
    local card = W.Card(host, "Test couleur")
    local row = card:Color({
        label = "Couleur test",
        get = function() return cur end,
        set = function(v) cur = v; got = got + 1 end,
        enabled = function() return on end,
    })
    check(#row.dots == 6, "6 pastilles de palette")
    M.fire(row.dots[2], "OnClick", "LeftButton")
    check(got == 1 and cur[1] == 1 and cur[2] == 0.62 and cur[3] == 0.10, "clic pastille orange -> set reçoit {1,0.62,0.10}")
    local old = cur
    M.fire(row.dots[4], "OnClick", "LeftButton")
    check(cur ~= old and cur[1] == 0.25, "nouvelle table à chaque écriture")
    on = false
    row:Refresh()
    M.fire(row.dots[1], "OnClick", "LeftButton")
    check(got == 2 and row.isEnabled == false, "grisé : clic ignoré")
    on = true
    row:Refresh()
end

---------------------------------------------------------------------------
section("capteur de touche")
local GENERAL = tabOf("general")
UI:SelectTab(GENERAL)
local capture, eatCapture
for _, e in ipairs(rowsOf(UI.pages[GENERAL])) do
    if e.w.reset and e.w.opts and e.w.opts.key == "key" then capture = e.w end
    if e.w.reset and e.w.opts and e.w.opts.key == "eatKey" then eatCapture = e.w end
end
check(capture ~= nil and eatCapture ~= nil, "deux capteurs : touche d'interaction et touche pour manger")
local function zoneOf(w)
    for _, c in ipairs(S(w).frames) do if c.IsListening then return c end end
end
-- une touche du clavier, comme le jeu : elle va au cadre visible qui écoute le clavier ; s'il y en a plusieurs,
-- l'un d'eux la vole (le bug d'avant) ; s'il n'y en a aucun, elle part au jeu (raccourcis, Échap)
local function keyboardFrames()
    local list = {}
    for _, f in ipairs(M.allFrames) do
        if S(f).keyboard and f:IsVisible() then list[#list + 1] = f end
    end
    return list
end
local function pressKey(key)
    local list = keyboardFrames()
    if #list > 1 then return "volée" end
    if #list == 1 then
        local fn = S(list[1]).scripts.OnKeyDown
        if fn then fn(list[1], key) end
        return "cadre"
    end
    if key == "ESCAPE" then gameEscape() end
    return "jeu"
end
check(#keyboardFrames() == 0, "fenêtre ouverte, rien en écoute : aucun cadre n'avale le clavier")
local zone = zoneOf(capture)
M.fire(zone, "OnMouseDown", "LeftButton")
check(S(zone).scripts.OnUpdate ~= nil, "écoute : le contour respire (OnUpdate posé)")
check(#keyboardFrames() == 1 and keyboardFrames()[1] == zone, "en écoute : seul ce capteur reçoit le clavier")
M.shift = true
pressKey("LSHIFT")
pressKey("G")
M.shift = false
check(ns.db.key == "SHIFT-G", "Maj + G capturé (" .. tostring(ns.db.key) .. ")")
check(S(zone).scripts.OnUpdate == nil, "fin d'écoute : OnUpdate retiré")
check(W.PrettyKey("SHIFT-G") == "Maj + G", "affichage « Maj + G »")
M.fire(zone, "OnMouseDown", "LeftButton")
M.fire(zone, "OnMouseDown", "Button4")
check(ns.db.key == "BUTTON4", "bouton de souris 4 capturé")
M.fire(capture.reset, "OnClick", "LeftButton")
check(ns.db.key == "F", "« Remettre F »")
check(#keyboardFrames() == 0, "fin d'écoute : le clavier est rendu au jeu")
-- touche pour manger : même capteur, sa propre clé, « Remettre » = aucune
local eatZone = zoneOf(eatCapture)
M.fire(eatZone, "OnMouseDown", "LeftButton")
check(pressKey("H") == "cadre", "la touche arrive au capteur de la touche pour manger (l'autre ne la vole plus)")
check(ns.db.eatKey == "H" and ns.db.key == "F", "touche pour manger capturée (H) sans toucher à F")
M.fire(eatCapture.reset, "OnClick", "LeftButton")
check(ns.db.eatKey == "", "« Remettre » la touche pour manger = aucune")
-- Échap pendant l'écoute : annule l'écoute, la fenêtre reste ouverte
M.fire(eatZone, "OnMouseDown", "LeftButton")
pressKey("ESCAPE")
check(not eatZone.IsListening() and UI.frame:IsShown() and ns.db.eatKey == "", "Échap en écoute : annule seulement l'écoute")
-- Échap au repos : la fenêtre se ferme
check(pressKey("ESCAPE") == "jeu" and not UI.frame:IsShown(), "Échap au repos : ferme la fenêtre Platyplus")
UI:Open()
UI:SelectTab(GENERAL)
M.fire(zone, "OnMouseDown", "LeftButton")
UI:SelectTab(tabOf("resources"))
check(S(zone).scripts.OnUpdate == nil and #keyboardFrames() == 0, "changer d'onglet arrête l'écoute")

---------------------------------------------------------------------------
section("listes d'objets et aperçu")
UI:SelectTab(tabOf("sell"))
M.advance(0.5)
local list, preview
for _, e in ipairs(rowsOf(UI.pages[tabOf("sell")])) do
    if e.w.opts and e.w.opts.list == "neverSell" then list = e.w end
    if e.w.Update then preview = e.w end
end
local drop = S(list).frames[1]
M.cursor = { "item", 4242 }
M.fire(drop, "OnReceiveDrag")
check(ns.db.neverSell[4242] == true, "glisser-déposer : ajouté à « Ne jamais vendre »")
local h1 = S(list).h
local rowFrame = list.rows[1]
check(rowFrame and S(rowFrame).shown and rowFrame.itemID == 4242, "ligne affichée pour l'objet")
M.fire(rowFrame.remove, "OnClick", "LeftButton")
check(ns.db.neverSell[4242] == nil, "bouton × : retiré")
check(S(list).h < h1, "la liste rétrécit")
check(preview and (preview.entries ~= nil or preview.err ~= nil), "aperçu calculé à l'ouverture de l'onglet")

---------------------------------------------------------------------------
section("liste de sorts (onglet Procs)")
local ids = { 5308, 6572 }
local spellNames = { [5308] = "Exécution", [6572] = "Vengeance" }
def("C_Spell", { GetSpellInfo = function(x)
    if type(x) == "string" then
        for id, n in pairs(spellNames) do if n == x then return { name = n, iconID = 100 + id, spellID = id } end end
        return nil
    end
    if spellNames[x] then return { name = spellNames[x], iconID = 100 + x, spellID = x } end
end })
check(tabOf("procs") == tabOf("plates") + 1, "onglet Procs juste après Plates")
check(Pages.list[tabOf("procs")].group == "Jouer", "onglet Procs dans le groupe Jouer")
UI:SelectTab(tabOf("procs"))
M.advance(0.5)
local extra, ignored
for _, e in ipairs(rowsOf(UI.pages[tabOf("procs")])) do
    if e.w.opts and e.w.opts.list == "procExtra" then extra = e.w end
    if e.w.opts and e.w.opts.list == "procIgnore" then ignored = e.w end
end
check(extra and ignored, "deux listes de sorts : ajoutés et ignorés")
local sdrop = S(extra).frames[1]
M.cursor = { "spell", 3, "spell", 5308 }
M.fire(sdrop, "OnReceiveDrag")
check(ns.db.procExtra[5308] == true, "glisser un sort du grimoire : ajouté (numéro lu en 4e retour)")
check(M.cursor ~= nil, "sort glissé : gardé en main (pas de ClearCursor, il ne disparaît pas de la barre)")
M.cursor = { "spell", 3, "spell" }
M.fire(sdrop, "OnReceiveDrag")
check(ns.db.procExtra[3] == nil, "sort sans numéro en 4e retour : rien d'ajouté")
M.cursor = nil
local srow = extra.rows[1]
check(srow and S(srow).shown and srow.itemID == 5308 and S(srow.name).text == "Exécution", "ligne : nom du sort")
-- saisie : numéro, nom, inconnu, doublon
local sbox
for _, fr in ipairs(S(extra).frames) do if S(fr).kind == "EditBox" then sbox = fr end end
check(sbox ~= nil, "zone de saisie présente")
if sbox then
    sbox:SetText("6572")
    M.fire(sbox, "OnEnterPressed")
    check(ns.db.procExtra[6572] == true, "ajout par numéro")
    check(S(sbox).text == "", "zone vidée après l'ajout")
    sbox:SetText("Vengeance")
    M.fire(sbox, "OnEnterPressed")
    check(S(sbox).text == "Vengeance", "déjà présent : refusé, texte gardé")
    sbox:SetText("Sort qui n'existe pas")
    M.fire(sbox, "OnEnterPressed")
    check(ns.db.procExtra[0] == nil and S(sbox).text ~= "", "nom inconnu : refusé")
    sbox:SetText("999999")
    M.fire(sbox, "OnEnterPressed")
    check(ns.db.procExtra[999999] == nil, "numéro inconnu : refusé")
    sbox:SetText("")
end
check(ignored.rows[1] == nil or not S(ignored.rows[1]).shown, "la liste des ignorés reste vide")
local before = S(extra).h
M.fire(extra.rows[1].remove, "OnClick", "LeftButton")
check(ns.db.procExtra[5308] == nil and ns.db.procExtra[6572] == true, "bouton × : retiré (l'autre reste)")
ns:ResetAll(true)
check(ns.db.procExtra[6572] == true, "« tout réinitialiser » garde la liste des sorts ajoutés")
M.fire(extra.rows[1].remove, "OnClick", "LeftButton")

---------------------------------------------------------------------------
section("argent")
W.COIN_ICONS = true
check(W.FormatMoney(123456):find("UI-GoldIcon", 1, true) and W.FormatMoney(123456):find("34", 1, true), "icônes de pièces : " .. W.FormatMoney(123456))
W.COIN_ICONS = false
check(W.FormatMoney(123456):find("12 po", 1, true), "repli texte : " .. W.FormatMoney(123456))
W.COIN_ICONS = true

---------------------------------------------------------------------------
section("boutons à confirmation")
local ADV = 0   -- onglet « Avancé » (cherché par son id : sa place change quand on ajoute un onglet)
for i, def in ipairs(Pages.list) do if def.id == "advanced" then ADV = i end end
UI:SelectTab(ADV)
local resetBtn
for _, e in ipairs(rowsOf(UI.pages[ADV])) do
    if e.w.buttons then
        for _, b in ipairs(e.w.buttons) do if b.opts.danger then resetBtn = b end end
    end
end
ns:Set("rows", 9)
M.fire(resetBtn, "OnClick", "LeftButton")
check(resetBtn.armed and ns.db.rows == 9, "1er clic : demande confirmation, rien n'est fait")
M.advance(3.2)
check(not resetBtn.armed, "confirmation expirée après 3 s")
M.fire(resetBtn, "OnClick", "LeftButton")
M.fire(resetBtn, "OnClick", "LeftButton")
check(ns.db.rows == ns.DEFAULTS.rows, "2 clics : tout est réinitialisé")

---------------------------------------------------------------------------
section("défilement et position")
UI:SelectTab(tabOf("sell"))
local range = UI:ScrollRange()
check(range > 0, "la page Vente défile (plage " .. math.floor(range) .. ")")
UI:ScrollBy(120)
M.advance(1)
check(math.abs((UI.scrollPos or 0) - math.min(120, range)) < 0.6, "molette : défilement doux arrivé (" .. tostring(UI.scrollPos) .. ")")
check(S(UI.scroll).scripts.OnUpdate == nil, "défilement doux : OnUpdate retiré")
M.fire(UI.thumb, "OnMouseDown", "LeftButton")
check(S(UI.thumb).scripts.OnUpdate ~= nil, "glisser la barre : OnUpdate pendant le glissement")
M.fire(UI.thumb, "OnMouseUp", "LeftButton")
check(S(UI.thumb).scripts.OnUpdate == nil, "lâcher la barre : OnUpdate retiré")
UI:StopMoving()
check(ns.db.uiX ~= nil and ns.db.uiY ~= nil, "position sauvegardée (uiX " .. tostring(ns.db.uiX) .. ", uiY " .. tostring(ns.db.uiY) .. ")")

---------------------------------------------------------------------------
section("info-bulles")
UI:SelectTab(tabOf("loot"))
local sw = rowsOf(UI.pages[tabOf("loot")])[1].w
M.fire(sw, "OnEnter")
check(S(GameTooltip).text == sw.opts.label, "info-bulle d'une option : « " .. tostring(S(GameTooltip).text) .. " »")
M.fire(sw, "OnLeave")

---------------------------------------------------------------------------
section("barre latérale : défilement")
do
    local realToc = UI.TocCards
    local cur = UI.current
    local card = UI:TocCards(cur)[1] or UI.pages[cur].widgets[1]
    UI.TocCards = function() local l = {} for i = 1, 40 do l[i] = card end return l end
    UI:LayoutSide()
    check(UI.sideH > 780 - 88 - 10, "sommaire très long : le contenu dépasse la zone (" .. UI.sideH .. ")")
    check(UI:SideRange() > 0 and S(UI.sideBar).shown, "le défilement existe et la barre fine s'affiche")
    UI:SideScroll(9999)
    check(math.abs(UI.sidePos - UI:SideRange()) < 0.5, "défilement borné au bas du contenu")
    M.fire(UI.sideScroll, "OnMouseWheel", 1)
    check(UI.sidePos < UI:SideRange(), "la molette sur la barre latérale la fait défiler")
    UI:SideScroll(0)
    UI:SelectTab(cur, true, true, true)
    check(UI.sideCurTop ~= nil, "l'onglet actif est repéré")
    UI:SideScroll(9999)
    UI:SideReveal(UI.sideCurTop, UI.sideCurTop + 32)
    check(UI.sidePos <= UI.sideCurTop + 0.5, "SideReveal ramène l'onglet actif dans la zone")
    UI.TocCards = realToc
    UI:LayoutSide()
    UI:SideScroll(0)
end

section("optimisation")
M.advance(2)
local busy = {}
for _, fr in ipairs(M.allFrames) do
    local s = S(fr)
    if s.scripts and s.scripts.OnUpdate and inside(fr, f) then busy[#busy + 1] = tostring(fr) end
end
check(#busy == 0, "aucun OnUpdate permanent dans la fenêtre (" .. table.concat(busy, ", ") .. ")")
local n0 = #M.allFrames
for i = 1, Pages:Count() do UI:SelectTab(i) end
check(#M.allFrames == n0, "revisiter les onglets ne recrée rien")

---------------------------------------------------------------------------
section("fermeture et réouverture")
UI:Toggle()
check(not S(f).shown, "Toggle ferme")
ns:Set("interact", false)
UI:Toggle()
check(S(f).shown, "Toggle rouvre")
UI:SelectTab(GENERAL)
local interactRow
for _, e in ipairs(rowsOf(UI.pages[GENERAL])) do if e.w.opts and e.w.opts.key == "interact" then interactRow = e.w end end
check(interactRow.value == false, "un réglage changé fenêtre fermée est relu à la réouverture")
ns:Set("interact", true)
SlashCmdList.PLATYPLUS("")
check(not S(f).shown, "/pp ferme la fenêtre")

section("bouton : largeur au moins égale au texte, SetLabel traduit")
do
    local holder = CreateFrame("Frame", nil, UIParent)
    local longText = "Réinitialiser absolument tous les réglages de cette fenêtre"
    local b = W.Button(holder, { text = longText, width = 60 })
    local lw = b.label:GetStringWidth() or 0
    check(b:GetWidth() >= lw + 34 - 0.5 and lw > 60, "Button : width=60 mais texte long -> largeur >= texte + 34")
    local b2 = W.Button(holder, { text = "OK", width = 200 })
    check(b2:GetWidth() >= 200, "Button : width demandée conservée si le texte est court")
    local oldLang = ns.lang
    ns.lang = "enUS"
    b2:SetLabel("Annuler")
    check(b2.baseText == "Cancel", "SetLabel traduit le texte (Annuler -> Cancel)")
    ns.lang = oldLang
end

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
