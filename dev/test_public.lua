-- Test : Platyplus SANS le dossier DungeonJournal (version publique, archive faite par le packager qui retire les
-- blocs do-not-package), puis avec l'addon DungeonJournal d'Exehn installé à part ; marqueurs do-not-package du
-- .toc et de Bindings.xml.
-- Usage : python -I dev\lua.py run dev\test_public.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end
local S = M.state

---------------------------------------------------------------------------
section("marqueurs do-not-package")
local function slurp(f) local h = assert(io.open(ADDON_DIR .. "\\" .. f, "rb")); local s = h:read("*a"); h:close(); return (s:gsub("\r", "")) end
local toc, bind = slurp("Platyplus.toc"), slurp("Bindings.xml")
local function pos(s, needle) return s:find(needle, 1, true) end
local a, b, c, d = pos(toc, "\n#@do-not-package@\n"), pos(toc, "\n# >>> DungeonJournal"), pos(toc, "\n# <<< DungeonJournal"),
    pos(toc, "\n#@end-do-not-package@\n")
check(a and b and c and d and a < b and b < c and c < d, ".toc : le bloc DungeonJournal est entre #@do-not-package@ et #@end-do-not-package@")
check(a and b and not toc:sub(a + 1, b):find("%.lua"), "  rien d'autre entre le marqueur et le bloc")
check(select(2, toc:gsub("#@do%-not%-package@", "")) == 1 and select(2, toc:gsub("#@end%-do%-not%-package@", "")) == 1,
    "  une seule paire")
-- tout ce qui touche au journal est dans le bloc (rien dehors, hors Skin/Plus qui ont des gardes)
local outside = toc:sub(1, a) .. toc:sub(d)
check(not outside:find("DungeonJournalGlue.lua", 1, true) and not outside:find("DungeonJournal\\", 1, true),
    "  Glue et DungeonJournal\\ seulement dans la partie retirée")
local ba, bb, bc, bd = pos(bind, "<!--@do-not-package@-->"), pos(bind, "<!-- >>> DungeonJournal"),
    pos(bind, "<!-- <<< DungeonJournal -->"), pos(bind, "<!--@end-do-not-package@-->")
check(ba and bb and bc and bd and ba < bb and bb < bc and bc < bd, "Bindings.xml : le bloc est entre <!--@do-not-package@--> et <!--@end-do-not-package@-->")
check(not (bind:sub(1, ba) .. bind:sub(bd)):find("PlatyplusDungeon_", 1, true), "  aucun raccourci du journal hors de la partie retirée")
check(toc:find("## Author: Blouf", 1, true) ~= nil, ".toc : Author Blouf")

---------------------------------------------------------------------------
-- monde : comme le test du journal, mais SANS DungeonJournalGlue.lua ni DungeonJournal\
dofile(DEV .. "\\preview_dungeon.lua")(M, def, { level = 24, done = {} })
local standaloneLoaded = false
def("C_AddOns", {
    IsAddOnLoaded = function(name) return name == "ForeverDungeonJournal" and standaloneLoaded end,
    GetAddOnMetadata = function() return nil end,
})
def("hooksecurefunc", function(a1, b1, c1)
    local tbl, name, hook
    if type(a1) == "string" then tbl, name, hook = _G, a1, b1 else tbl, name, hook = a1, b1, c1 end
    local orig = rawget(tbl, name)
    if type(orig) ~= "function" then return end
    rawset(tbl, name, function(...) local r = { orig(...) }; hook(...); return unpack(r) end)
end)
def("StaticPopupDialogs", {})
def("DEFAULT_CHAT_FRAME", { AddMessage = function(_, msg) print(msg) end })
def("ReloadUI", function() end)
def("debugprofilestop", function() return os.clock() * 1000 end)
def("LibStub", setmetatable({ GetLibrary = function() return nil end, NewLibrary = function() return {} end },
    { __call = function() return nil end }))
def("PlatyplusDB", { welcomeSeen = true })

local files, skip = {}, false
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    line = line:gsub("\r", "")
    if line == "#@do-not-package@" then skip = true end   -- ce que fait le packager
    if not skip then
        local f = line:match("^([%w_%.\\]+%.lua)")
        if f then files[#files + 1] = f end
    end
    if line == "#@end-do-not-package@" then skip = false end
end

section("sans le dossier DungeonJournal")
local hasGlue = false
for _, f in ipairs(files) do if f:find("^DungeonJournal") and f ~= "DungeonJournalSkin.lua" and f ~= "DungeonJournalPlus.lua" then hasGlue = true end end
check(not hasGlue, "fichiers : ni Glue ni DungeonJournal\\ (" .. #files .. " fichiers)")
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus"); M.fireEvent("PLAYER_LOGIN"); M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(1)
check(#M.errors == 0, "chargement et Init sans erreur (" .. #M.errors .. ")")
if #M.errors > 0 then M.report() M.errors = {} end
local P = ns.DungeonPlus
check(ns.Dungeon == nil, "ns.Dungeon absent")
check(P and not P.Bundled() and not P.Standalone() and not P.Available(), "Bundled/Standalone/Available : faux")
local before = #M.printed
P.Toggle()
local said = table.concat(M.printed, "\n", before + 1)
check(said:find("pas inclus dans cette version", 1, true) and said:find("Exehn", 1, true), "Toggle() : message « pas inclus dans cette version »")
before = #M.printed
SlashCmdList.PLATYPLUS("donjons")
check(#M.printed > before, "/pp donjons : écrit le message")
before = #M.printed
SlashCmdList.PLATYPLUS("donjons etat")
check(table.concat(M.printed, "\n", before + 1):find("non inclus", 1, true), "/pp donjons etat : cohérent")
check(not P.OpenOptions(), "OpenOptions() : faux")

local Pages = ns.Pages
local idx
for i = 1, Pages:Count() do if Pages:GetInfo(i).id == "dungeons" then idx = i end end
check(idx ~= nil, "onglet Donjons présent")
ns.UI:Open(); ns.UI:SelectTab(idx); M.advance(0.3)
local page = ns.UI.pages[idx]
check(page ~= nil and #M.errors == 0, "l'onglet Donjons se construit sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
ns.UI:Close()

ns.Launcher:ShowMenu()
check(ns.Launcher.journalRow == nil, "menu de l'icône : pas de ligne « Journal des donjons »")
check(#M.errors == 0, "menu sans erreur")
if #M.errors > 0 then M.report() M.errors = {} end
ns.Launcher:HideMenu()

section("avec l'addon DungeonJournal séparé")
standaloneLoaded = true
local opened = 0
def("ForeverDungeonJournal_Toggle", function() opened = opened + 1 end)
check(P.Standalone() and P.Available() and not P.Bundled(), "Standalone et Available vrais, pas de journal intégré")
before = #M.printed
P.Toggle()
check(opened == 1, "Toggle() appelle ForeverDungeonJournal_Toggle")
check(#M.printed == before, "  sans message d'erreur")
SlashCmdList.PLATYPLUS("donjons")
check(opened == 2, "/pp donjons l'ouvre aussi")
check(table.concat(P:Status(), " "):find("installé à part", 1, true) ~= nil, "Status() : addon séparé")
check(#M.errors == 0, "sans erreur")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s), " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
