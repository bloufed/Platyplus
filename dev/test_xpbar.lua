-- Test : barre d'expérience masquable (Tweaks.lua, hideXpBar), anciennes clés effacées, et fiche / options du jeu
-- laissées à Blizzard (le tableau de bord des stats et le style des options ont été retirés à la demande du joueur).
-- Usage : python -I dev\lua.py run dev\test_xpbar.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

for _, name in ipairs({ "CharacterFrame", "PaperDollFrame", "CharacterLevelText", "ContainerFrame1", "ContainerFrame2",
    "ContainerFrame3", "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "ContainerFrame7",
    "ContainerFrameCombinedBags", "OpenAllMail", "PaperDollItemSlotButton_Update", "ContainerFrame_UpdateAll" }) do
    M.optional[name] = true
end
def("C_Item", { GetItemInfoInstant = function() return nil end })

-- barre d'XP de Blizzard (StatusTrackingBarManager, non protégée), panneau des stats et fenêtre d'options
local manager = CreateFrame("Frame", "StatusTrackingBarManager", UIParent)
local pane = CreateFrame("Frame", "CharacterStatsPaneScrollBox", UIParent)
pane.ScrollBox = CreateFrame("Frame", nil, pane)
pane.Border = pane:CreateTexture()
local options = CreateFrame("Frame", "SettingsPanel", UIParent)
options.Bg = CreateFrame("Frame", nil, options)

-- réglages sauvegardés d'une version précédente (avec les deux fonctions retirées)
def("PlatyplusDB", { charStats = true, settingsSkin = true, key = "G" })

M.enableStrict()
local ns = M.loadAddon(ADDON_DIR, "Platyplus", { "Core.lua", "Float.lua", "Junk.lua", "GameSettings.lua", "Tweaks.lua" })
M.fireEvent("ADDON_LOADED", "Platyplus")
M.loggedIn = true
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD", true, false)
M.advance(0.2)
local T = ns.Tweaks

section("anciennes fonctions retirées")
check(PlatyplusDB.charStats == nil and PlatyplusDB.settingsSkin == nil, "leurs réglages sont effacés du fichier sauvegardé")
check(PlatyplusDB.key == "G", "les autres réglages sont gardés")
check(T.StatsState == nil and ns.SettingsSkin == nil, "plus de tableau de bord ni de style des options")
check(S(pane.ScrollBox).alpha ~= 0 and S(pane.Border).alpha ~= 0 and #S(pane).frames == 1, "fiche du personnage : intacte")
check(S(options.Bg).alpha ~= 0 and #S(options).regions == 0, "fenêtre d'options : intacte")

section("barre d'expérience")
check(ns.db.hideXpBar == false and S(manager).shown, "affichée par défaut")
ns:Set("hideXpBar", true)
check(not S(manager).shown and T:XpBarHidden(), "masquée")
manager:Show()
check(not S(manager).shown, "remontrée par le jeu : recachée")
ns:Set("hideXpBar", false)
check(S(manager).shown, "option coupée : elle revient")
manager:Hide(); manager:Show()
check(S(manager).shown, "ensuite le jeu décide seul")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
