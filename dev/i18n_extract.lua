-- Extraction des textes français de Platyplus qui passent par ns.T / ns.Tf (voir dev\i18n.py).
-- Réutilise le monde simulé de render_preview.lua (tout le .toc chargé, personnage guerrier),
-- puis construit toutes les pages d'options, la bienvenue et lance les commandes /pp d'aide.
-- Usage : python -I lua.py run i18n_extract.lua <dossier Platyplus> <dossier dev> <sortie.json> [langue] [vide|garde]
--   langue : langue simulée (défaut enUS) ; vide (défaut) = aucun dictionnaire chargé, donc toute clé rencontrée
--   est « manquante » ; garde = dictionnaires gardés : ne reste que ce qui n'est pas encore traduit.
local ADDON_DIR, DEV, OUT = ARGS[1], ARGS[2], ARGS[3]
local LANG = ARGS[4] or "enUS"
local MODE = ARGS[5] or "vide"

-- Lit render_preview.lua jusqu'à la mise en page : monde simulé + chargement de l'addon
local fh = assert(io.open(DEV .. "\\render_preview.lua", "rb"))
local src = fh:read("*a")
fh:close()
local cut = assert(src:find("\n-- Mise en page", 1, true), "marqueur « Mise en page » introuvable dans render_preview.lua")
src = src:sub(1, cut - 1)

local function patch(from, to)
    local a, b = src:find(from, 1, true)
    assert(a, "motif introuvable dans render_preview.lua : " .. from)
    src = src:sub(1, a - 1) .. to .. src:sub(b + 1)
end
do   -- réglages de départ : la langue demandée (render_preview la lit dans ARGS[4])
    local a, b = src:find('def("PlatyplusDB", {', 1, true)
    assert(a, "PlatyplusDB introuvable dans render_preview.lua")
    local close = src:find("})", b, true)
    src = src:sub(1, a - 1) .. 'def("PlatyplusDB", { welcomeSeen = true, language = "' .. LANG .. '" ' .. src:sub(close)
end
patch('local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)',
    'local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)\n'
    .. 'ns.i18nTrace = true\n'
    .. (MODE == "vide" and 'for k in pairs(ns.Strings) do ns.Strings[k] = nil end\n' or ''))
src = src .. "\nreturn ns, M\n"

local chunk, err = loadstring(src, "=render_preview(monde)")
assert(chunk, err)
ARGS[3] = OUT
local ns, M = chunk()

local function origin(name) ns.i18nOrigin = name end

local function run(label, fn)
    local ok, e = pcall(fn)
    if not ok then M.realPrint("  (ignoré) " .. label .. " : " .. tostring(e)) end
end

-- fenêtre d'options : chaque onglet (et le bas de page, pour les cartes sous la ligne de flottaison)
origin("options")
if ns.UI then
    run("ouverture des options", function() ns.UI:Open() end)
    M.advance(1)
    local count = (ns.Pages and ns.Pages.Count and ns.Pages:Count()) or 0
    for i = 1, count do
        local def = ns.Pages:GetInfo(i)
        origin("options/" .. tostring(def and def.id or i))
        run("onglet " .. i, function() ns.UI:SelectTab(i) end)
        M.advance(1)
        if ns.UI.SetScroll and ns.UI.ScrollRange and ns.UI:ScrollRange() > 0 then
            run("bas de page " .. i, function() ns.UI:SetScroll(ns.UI:ScrollRange()) end)
            M.advance(0.2)
            ns.UI:SetScroll(0)
        end
    end
    run("fermeture des options", function() ns.UI:Close() end)
end

-- textes qui ne se disent qu'au survol / à l'usage : on les déclare ici
origin("options")
for _, s in ipairs({ "Par défaut : %s", "activé", "désactivé", "Carré", "Léger", "Doux", "Rond", "Très rond", "Aucun" }) do ns.T(s) end
-- journal des donjons absent (version publique) : onglet Donjons et messages de /pp donjons
for _, s in ipairs({
    "Le journal des donjons est celui de l'addon DungeonJournal d'Exehn, installé à part : Platyplus l'ouvre d'ici, depuis le menu de l'icône et avec /pp donjons.",
    "Le journal des donjons n'est pas inclus dans cette version de Platyplus. Installe l'addon DungeonJournal d'Exehn depuis CurseForge : Platyplus l'ouvrira ensuite depuis cet onglet, depuis le menu de l'icône et avec /pp donjons, et posera dessus sa liste des donjons, « À ton niveau » et son style.",
    -- surcharge de l'addon séparé (onglet Donjons quand DungeonJournalPlus.Overlay() est vrai)
    "L'addon DungeonJournal séparé est activé : c'est lui qui tourne, avec la liste des donjons, « À ton niveau » et le style de Platyplus posés dessus. Le journal intégré à Platyplus reste éteint et garde une copie de ses réglages, de tes favoris et de ta progression : désactive DungeonJournal dans la liste des addons (écran de choix du personnage) puis relance le jeu pour revenir au journal intégré.",
    "Le journal des donjons est celui de l'addon DungeonJournal d'Exehn, installé à part. Platyplus l'ouvre d'ici, depuis le menu de l'icône et avec /pp donjons, et pose dessus sa liste des donjons, « À ton niveau » et son style, sans rien changer dans l'addon.",
    "Chaque donjon : ses boss et leur butin, ses quêtes (où les prendre, les suites de quêtes, les récompenses), son plan et le chemin jusqu'à l'entrée. Ouvrir : /dj, /pp donjons, le menu de l'icône Platyplus, ou la touche de l'addon DungeonJournal.",
    "DungeonJournal, par Exehn : le journal, ses données (boss, butin, quêtes, plans, routes) et ses images viennent de son addon, installé à part ; Platyplus n'en embarque rien. Platyplus y ajoute la liste de gauche, « À ton niveau » et son style en passant derrière lui, sans rien modifier dans l'addon : éteins les trois réglages (puis /reload) et il retrouve son look d'origine.",
    "Ouvre le journal de l'addon DungeonJournal (aussi : /dj).",
    "le journal des donjons n'est pas inclus dans cette version : installe l'addon DungeonJournal d'Exehn (CurseForge), Platyplus l'ouvrira d'ici.",
    "journal des donjons indisponible (le dossier DungeonJournal n'a pas pu se charger).",
}) do ns.T(s) end

-- VAGUE 2 : fenêtres. Rendues dans le monde simulé (mêmes mises en scène que render_preview.lua, sans capture)
local function def(name, value) rawset(_G, name, value) end
local function hideAll()
    if ns.UI and ns.UI.Close then ns.UI:Close() end
    if ns.ChatWindow and ns.ChatWindow.frame then ns.ChatWindow.frame:Hide() end
end

-- barre d'infos + icône : chaque info-bulle (session démarrée pour les lignes d'XP/or par session)
origin("launcher")
run("launcher", function()
    local L = ns.Launcher
    if L.session then L.session.started = true; L.session.xpGained = 1200; L.session.killXP = 800; L.session.questXP = 400
        L.session.gained = 5000; L.session.spent = 1200; L.session.kills = 5; L.session.quests = 2 end
    if L.Refresh then L:Refresh() end
    M.advance(1)
    if L.button then run("icône", function() M.fire(L.button, "OnEnter") end) end
    for name, item in pairs(L.items or {}) do
        if item.frame then run("tip " .. name, function() M.fire(item.frame, "OnEnter") end) end
    end
    if L.ShowMenu then L:ShowMenu() M.advance(0.5) L:HideMenu() end
end)

-- jets de butin (mode butin puis /roll), menace, flux de butin, cartes de récompense
origin("lootrolls")
run("lootrolls", function()
    hideAll()
    def("RAID_CLASS_COLORS", { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        ROGUE = { r = 1, g = 0.96, b = 0.41 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 },
        PRIEST = { r = 1, g = 1, b = 1 }, DRUID = { r = 1, g = 0.49, b = 0.04 } })
    ns.LootRolls:Demo() M.advance(0.5)
    local Wd = ns.W; if Wd and Wd.FinishAnimations then Wd.FinishAnimations() end
    M.advance(0.3)
    ns.LootRolls:SetMode("roll") M.advance(0.5)
    ns.LootRolls:SetMode("loot") ns.LootRolls:Close()
    ns.LootRolls:Close()
end)
origin("menace")
run("menace", function()
    hideAll()
    ns.Threat:Test() M.advance(0.5)
    ns.Threat:Test() M.advance(0.3)
end)
origin("flux")
run("flux", function()
    if ns.Float and ns.Float.Test then ns.Float:Test() M.advance(1) end
    if ns.Float and ns.Float.SetMoving then ns.Float:SetMoving(true) ns.Float:SetMoving(false) end
end)
origin("quetes")
run("cartes", function()
    hideAll()
    if ns.QuestCards and ns.QuestCards.Demo then ns.QuestCards:Demo() M.advance(0.5) ns.QuestCards:Hide() end
end)

-- fenêtre du personnage : chaque onglet
origin("personnage")
run("personnage", function()
    hideAll()
    if ns.CharWindow and rawget(_G, "ToggleCharacter") then
        ToggleCharacter("PaperDollFrame") M.advance(0.5)
        for _, tab in ipairs({ "ReputationFrame", "SkillsFrame", "PVPRankFrame", "TokenFrame" }) do
            run(tab, function() ToggleCharacter(tab, true) M.advance(0.5) end)
        end
        ToggleCharacter("PaperDollFrame") ToggleCharacter("PaperDollFrame")
    end
end)

-- dialogue avec un PNJ : discussion, quête à rendre
origin("dialogue")
run("dialogue", function()
    hideAll()
    if ns.QuestWindow then
        local gossip, quest = rawget(_G, "GossipFrame"), rawget(_G, "QuestFrame")
        ShowUIPanel(gossip) M.fireEvent("GOSSIP_SHOW") M.advance(0.5)
        gossip:Hide() M.fireEvent("GOSSIP_CLOSED")
        for _, panel in ipairs({ "Greeting", "Detail", "Progress", "Reward" }) do
            local f = rawget(_G, "QuestFrame" .. panel .. "Panel")
            ShowUIPanel(quest) f:Show()
            M.fireEvent(panel == "Reward" and "QUEST_COMPLETE" or panel == "Progress" and "QUEST_PROGRESS"
                or panel == "Detail" and "QUEST_DETAIL" or "QUEST_GREETING")
            M.advance(0.5)
            f:Hide() quest:Hide() M.fireEvent("QUEST_FINISHED") M.advance(0.3)
        end
    end
end)

-- fenêtre de chat : onglets et conversation
origin("chat")
run("chat", function()
    local CW = ns.ChatWindow
    if not (CW and CW.frame) then return end
    local src = CreateFrame("Frame", "ChatFrame1Preview", UIParent)
    def("Ambiguate", function(name) return (tostring(name):match("^[^%-]+")) end)
    def("GetPlayerInfoByGUID", function() return nil, "MAGE" end)
    CW.frame:Show()
    local n = 0
    local function talk(event, msg, author)
        n = n + 1
        local a = { msg, author, "", "", "", "", 0, 0, "", 0, 1000 + n, "Player-" .. author, 0, false, false, false, false, n = 17 }
        CW.AfterAddMessage(src, msg, 0.67, 0.67, 1, 1, 0, 0, event, a)
        M.advance(0.1)
    end
    talk("CHAT_MSG_PARTY", "We good to go", "Menethel-Royaume")
    talk("CHAT_MSG_WHISPER", "salut", "Sto-Royaume")
    CW.AfterAddMessage(src, "Vous recevez du butin", 1, 1, 0, 1, 0, 0, "CHAT_MSG_LOOT", nil)
    for _, tab in ipairs({ "group", "chat" }) do run(tab, function() CW:SelectTab(tab) M.advance(0.3) end) end
end)

-- bienvenue
origin("bienvenue")
if ns.UI and ns.UI.ShowWelcome then
    run("bienvenue", function()
        ns.UI:ShowWelcome(1)
        local wf = ns.UI.welcome
        for i = 2, (wf and wf.steps and #wf.steps or 0) do wf:ShowStep(i) end   -- chaque page de la visite guidée
    end)
    M.advance(0.3)
end

-- commandes /pp (messages d'aide et d'état)
origin("commandes")
local slash = SlashCmdList and SlashCmdList.PLATYPLUS
if slash then
    for _, cmd in ipairs({ "help", "langue", "langue enUS", "langue xx", "perf", "list", "plates", "proc", "buffs",
                           "healer", "spam", "etincelles", "chat", "fenetres", "key", "rows", "time", "mode", "mode xx" }) do
        run("/pp " .. cmd, function() slash(cmd) end)
    end
end


-- VAGUE 3 : modules. Démos et sorties de statut (pcall : un module absent ou incomplet n'arrête rien)
local function try(label, fn) run(label, fn) end
origin("procs")
try("procs", function()
    local P = ns.Procs
    if P.Describe then P:Describe() end
    if P.Summary then P:Summary() end
    if P.BlockStatus then P:BlockStatus() end
    if P.BlockDetails then P:BlockDetails() end
    if P.KeyText then for _, k in ipairs({ "SHIFT-BUTTON4", "CTRL-NUMPAD5", "ALT-SPACE", "" }) do pcall(P.KeyText, k) end end
    if P.Preview then P:Preview() M.advance(0.3) end
    if P.ToggleMove then P:ToggleMove() P:ToggleMove() end
end)
origin("buffs")
try("buffs", function()
    local B = ns.Buffs
    for _, m in ipairs({ "Status", "Reminders", "Preview", "ToggleMove" }) do if B[m] then pcall(B[m], B) end end
    if B.ToggleMove then pcall(B.ToggleMove, B) end
end)
origin("plates")
try("plates", function()
    local P = ns.Plates
    for _, m in ipairs({ "Command", "IsTank" }) do if P[m] then pcall(P[m], P) end end
    if P.Command then for _, a in ipairs({ "", "taille", "taille 99", "on", "off", "test" }) do pcall(P.Command, P, a) end end
end)
origin("mobcontrols")
try("mobcontrols", function()
    local MC = ns.MobControls
    if MC.Command then pcall(MC.Command, MC, "") end
    if MC.When then for _, k in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }) do
        pcall(MC.When, k, 5, 10, 3, 3, 50, false); pcall(MC.When, k, 5, 10, 3, 3, nil, true); pcall(MC.When, k, 0, 0, 0, 0) end end
    if MC.Effect then for _, c in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }) do pcall(MC.Effect, c, 4); pcall(MC.Effect, c) end end
    for k in pairs(MC.CATS or {}) do local c = MC.CATS[k]; if type(c) == "table" then for _, v in pairs(c) do if type(v) == "string" then ns.T(v) end end elseif type(c) == "string" then ns.T(c) end end
end)
origin("healer")
try("healer", function()
    local H = ns.HealerMana
    for _, m in ipairs({ "Summary", "ToggleMove", "ToggleMove" }) do if H[m] then pcall(H[m], H) end end
end)
origin("auction")
try("auction", function()
    local A = ns.Auction
    for _, a in ipairs({ "", "touche", "exclus", "exclus vider", "on", "off", "xx" }) do if A.Command then pcall(A.Command, A, a) end end
    if A.STATUS then for _, v in pairs(A.STATUS) do ns.T(type(v) == "table" and v[1] or v) end end
end)
origin("prices")
try("prices", function()
    local P = ns.Prices
    if P.TooltipLine then pcall(P.TooltipLine, P, 6948, 1); pcall(P.TooltipLine, P, 6948, 5) end
end)
origin("sparkles")
try("sparkles", function() if ns.Sparkles and ns.Sparkles.Status then ns.Sparkles:Status() end end)
origin("gamesettings")
try("gamesettings", function()
    local G = ns.GameSettings
    if G.ApplyRecommended then pcall(G.ApplyRecommended, G) end
    if G.RestoreAll then pcall(G.RestoreAll, G) end
end)
origin("journal")
try("journal", function()
    if ns.DungeonPlus and ns.DungeonPlus.Status then ns.DungeonPlus:Status() end
    if ns.DungeonSkin and ns.DungeonSkin.Status then ns.DungeonSkin:Status() end
    if ns.Traducteur then
        if ns.Traducteur.Status then ns.Traducteur:Status() end
        if ns.Traducteur.Command then pcall(ns.Traducteur.Command, ns.Traducteur, "") end
    end
end)
origin("mots")
for _, s in ipairs({ "Ressource", "Focalisation", "Énergie",
    "Puissance runique", "Points de combo", "Fragments d'âme", "Puissance astrale", "Puissance sacrée", "Maelström",
    "Folie", "Charges arcaniques", "Fureur", "Douleur", "Essence", "Runes", "Mana", "Rage", "Chi",
    "De la nourriture", "De l'eau", "Une pierre de soins", "M'invoquer",
    "Étourdit", "Neutralise", "Apeure", "Contrôle l'esprit", "Immobilise", "Réduit au silence", "Désarme",
    "Repousse", "Ralentit", "Ralentit les attaques", "Maj", "Espace", "oui", "non", "secrète", "recherché", "aucun",
    "inconnues" }) do ns.T(s) end

-- analyse statique : tout T("...") / Tf("...") dont le 1er argument est un littéral, dans les fichiers des fenêtres
-- (textes qui n'apparaissent qu'à l'usage : conditions rares, messages d'état...)
local STATIC_FILES = { "BagWindow", "CharacterWindow", "CharacterTabs", "QuestWindow", "QuestCards", "QuestPage",
    "ChatWindow", "ChatPlus", "Misc", "LootRolls", "Launcher", "Threat", "Windows", "Float",
    "Procs", "Buffs", "Plates", "MobControls", "HealerMana", "Auction", "Prices", "Craft", "ResourceBar",
    "Junk", "Tweaks", "Sparkles", "Dialog", "Interact", "Loot", "Gains", "Quests", "GameSettings",
    "DungeonJournalPlus", "DungeonJournalSkin", "Traducteur", "Core", "UIConfig", "Resources" }
local function scanFile(name)
    local fh = io.open(ADDON_DIR .. "\\" .. name .. ".lua", "rb")
    if not fh then return 0 end
    local code = fh:read("*a")
    fh:close()
    local found, init = 0, 1
    while true do
        local a, b, q = code:find("[^%w_]Tf?%(%s*([\"'])", init)
        if not a then break end
        local i, parts = b + 1, {}
        while i <= #code do
            local c = code:sub(i, i)
            if c == "\\" then parts[#parts + 1] = code:sub(i, i + 1); i = i + 2
            elseif c == q or c == "\n" then break
            else parts[#parts + 1] = c; i = i + 1 end
        end
        init = i + 1
        if code:sub(i, i) == q then
            local rest = code:match("^%s*(..?)", i + 1) or ""
            if rest:sub(1, 1) == ")" or rest:sub(1, 1) == "," then
                local f = loadstring("return " .. q .. table.concat(parts) .. q)
                local ok, v = pcall(f or function() end)
                if ok and type(v) == "string" and v ~= "" then
                    ns.i18nOrigin = name
                    ns.T(v)
                    found = found + 1
                end
            end
        end
    end
    return found
end
for _, name in ipairs(STATIC_FILES) do scanFile(name) end

-- sortie : objet JSON { "clé française": "origine", ... }
local function esc(s)
    return (s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        if c == "\n" then return "\\n" end
        if c == "\r" then return "\\r" end
        if c == "\t" then return "\\t" end
        return string.format("\\u%04x", c:byte())
    end))
end
local keys = {}
for k in pairs(ns.i18nMissing) do keys[#keys + 1] = k end
table.sort(keys)
local out = assert(io.open(OUT, "wb"))
out:write("{\n")
for i, k in ipairs(keys) do
    local o = ns.i18nMissing[k]
    out:write(string.format('  "%s": "%s"%s\n', esc(k), esc(type(o) == "string" and o or ""), i < #keys and "," or ""))
end
out:write("}\n")
out:close()
M.realPrint(string.format("i18n : %d chaîne(s) sans traduction en %s (%s)", #keys, LANG, MODE))
if #M.errors > 0 then
    M.realPrint("--- erreurs de chargement : " .. #M.errors)
    for i, e in ipairs(M.errors) do if i <= 8 then M.realPrint("  " .. e) end end
end
