-- Test de la fenêtre du personnage Platyplus (CharacterWindow.lua, CharacterTabs.lua) dans le simulateur, en mode strict.
-- Reproduit ce que fait Forever : ToggleCharacter(volet, seulementOuvrir), CharacterFrame:ShowSubFrame et
-- activeSubframe, cases CharacterXxxSlot (BorderFrame, popoutButton), PAPERDOLL_STATINFO / PAPERDOLL_STATCATEGORIES,
-- C_Reputation, C_SkillInfo, C_MajorFactions (rang JcJ, faction 2800), C_CurrencyInfo.
-- Usage : python -I dev\lua.py run dev\test_charwindow.lua <dossier Platyplus> <dossier dev>
local ADDON_DIR, DEV = ARGS[1], ARGS[2]
local M = dofile(DEV .. "\\wowmock.lua")
local def = function(name, value) rawset(_G, name, value) end
local S = M.state

local failures = {}
local function check(cond, msg)
    if cond then M.realPrint("  ok   " .. msg) else M.realPrint("  ECHEC " .. msg); failures[#failures + 1] = msg end
end
local function section(t) M.realPrint("== " .. t .. " ==") end

def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook
    if type(a) == "string" then tbl, name, hook = _G, a, b else tbl, name, hook = a, b, c end
    local orig = tbl[name]
    rawset(tbl, name, function(...)
        local results = { orig(...) }
        hook(...)
        return unpack(results)
    end)
end)
M.impl.SetParent = function(f, parent) S(f).parent = parent end
M.impl.IsClampedToScreen = function(f) return S(f).clamped == true end
M.impl.SetClampedToScreen = function(f, v) S(f).clamped = v and true or false end
local modelUnits = {}
local createFrame = CreateFrame
def("CreateFrame", function(kind, ...)
    local f = createFrame(kind, ...)
    if kind == "PlayerModel" then
        f.SetUnit = function(_, unit) modelUnits[#modelUnits + 1] = unit end
        f.SetFacing = function(self, v) self.facing = v end
        f.SetCamDistanceScale = function(self, v) self.zoom = v end
    end
    return f
end)

---------------------------------------------------------------------------
-- Personnage simulé
---------------------------------------------------------------------------
def("UnitName", function(unit) if unit == "player" then return "Leo" end end)
def("UnitPVPName", function() return "Sergent Leo" end)
def("UnitLevel", function() return 42 end)
def("UnitRace", function() return "Humain" end)
def("UnitClass", function() return "Guerrier", "WARRIOR" end)
def("UnitSex", function() return 2 end)
def("UnitFactionGroup", function() return "Alliance" end)
def("UnitExists", function(unit) return unit == "player" end)
def("GetGuildInfo", function() return "Les Platypus" end)
def("RAID_CLASS_COLORS", { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } })
def("GetCursorPosition", function() return M.cursorX or 500, 400 end)
def("GetText", function(key) return rawget(_G, key) end)
def("MIN_PLAYER_LEVEL_FOR_ITEM_LEVEL_DISPLAY", 10)
def("GetInventoryItemLink", function(unit, slot) if slot == 1 then return "|Hitem:100|h[Casque]|h" end end)
def("GetInventoryItemQuality", function(unit, slot) if slot == 1 then return 3 end end)
-- comme le jeu : niveau effectif, aperçu, niveau de base (trois valeurs)
def("C_Item", { GetDetailedItemLevelInfo = function(link) if link then return 45, false, 40 end end })
def("GetAverageItemLevel", function() return 38.4, 37.9 end)
def("GetInventoryItemDurability", function(slot) if slot == 1 then return 18, 100 end if slot == 5 then return 60, 100 end end)
def("UnitResistance", function(unit, dc) return 0, dc * 2, dc * 3 end)
def("C_Texture", { GetAtlasInfo = function(atlas) if atlas == "UI-Character-Info-Honor-Icon-3" then return {} end end })

-- caractéristiques : comme les fonctions du jeu, elles remplissent Label / Value / tooltip
local tooltipShown
def("PaperDollStatTooltip", function(self) tooltipShown = self.tooltip end)
local function setter(label, value, numeric)
    return { updateFunc = function(statFrame)
        statFrame.Label:SetText(label .. " :")
        statFrame.Value:SetText(value)
        statFrame.numericValue = numeric
        statFrame.tooltip = label .. " " .. value
        statFrame:Show()
    end }
end
def("PAPERDOLL_STATINFO", {
    ITEMLEVEL = setter("Niveau d'objet moyen", "38", 38),
    HEALTH = setter("Vie", "1 250", 1250),
    STRENGTH = setter("Force", "87", 87),
    OFFHAND_DAMAGE = setter("Dégâts main gauche", "0", 0),
    BLOCK = setter("Blocage", "5%", 5),
    ARMOR = setter("Armure", "1 840", 1840),
    BROKEN = { updateFunc = function() error("calcul cassé") end },
})
def("PAPERDOLL_STATCATEGORIES", {
    { categoryName = "Général", unit = "player", stats = { { stat = "HEALTH" }, { stat = "BROKEN" } } },
    { categoryName = "Attributs", unit = "player", stats = { { stat = "STRENGTH" } } },
    { categoryName = "Armes", unit = "player", stats = { { stat = "OFFHAND_DAMAGE", hideAt = 0 } } },
    { categoryName = "Défense", unit = "player", stats = { { stat = "BLOCK", showFunc = function() return false end }, { stat = "ARMOR" } } },
    { categoryName = "Général", unit = "pet", stats = { { stat = "HEALTH" } } },
})
def("PaperDollFrame_SetResistance", function(statFrame, unit, dc)
    statFrame.Label:SetText("Résistance " .. dc .. " :")
    statFrame.Value:SetText("10")
    statFrame:Show()
end)
rawget(_G, "Enum").Damageclass = { Physical = 0, Holy = 1, Fire = 2, Nature = 3, Frost = 4, Shadow = 5, Arcane = 6 }
rawget(_G, "Enum").PvPRanks = { Rank_1 = 5 }
def("PVP_RANK_7_1", "Sergent")

-- réputations
local factions = {
    { name = "Alliance", isHeader = true, isCollapsed = false },
    { factionID = 72, name = "Hurlevent", reaction = 6, currentReactionThreshold = 9000, nextReactionThreshold = 21000,
      currentStanding = 12000, description = "La capitale des humains.", canToggleAtWar = false, canSetInactive = true },
    { factionID = 47, name = "Forgefer", reaction = 2, currentReactionThreshold = -6000, nextReactionThreshold = -3000,
      currentStanding = -4500, atWarWith = true, canToggleAtWar = true, canSetInactive = true },
    { name = "Autre", isHeader = true, isCollapsed = true },
}
local repCalls = {}
local active = { true, true, true, true }
def("FACTION_STANDING_LABEL6", "Honoré")
def("FACTION_STANDING_LABEL2", "Hostile")
def("FACTION_BAR_COLORS", { [2] = { r = 1, g = 0.3, b = 0 }, [6] = { r = 0, g = 0.6, b = 0.1 } })
local function visibleFactions()
    local list, hide = {}, false
    for _, f in ipairs(factions) do
        if f.isHeader then hide = f.isCollapsed; list[#list + 1] = f
        elseif not hide then list[#list + 1] = f end
    end
    return list
end
def("C_Reputation", {
    GetNumFactions = function() return #visibleFactions() end,
    GetFactionDataByIndex = function(i) return visibleFactions()[i] end,
    ExpandFactionHeader = function(i) visibleFactions()[i].isCollapsed = false; repCalls[#repCalls + 1] = "expand:" .. i end,
    CollapseFactionHeader = function(i) visibleFactions()[i].isCollapsed = true; repCalls[#repCalls + 1] = "collapse:" .. i end,
    SetWatchedFactionByIndex = function(i) repCalls[#repCalls + 1] = "watch:" .. i end,
    ToggleFactionAtWar = function(i) repCalls[#repCalls + 1] = "war:" .. i end,
    IsFactionActive = function(i) return active[i] end,
    SetFactionActive = function(i, v) active[i] = v; repCalls[#repCalls + 1] = "active:" .. i .. ":" .. tostring(v) end,
})

-- compétences
def("C_SkillInfo", {
    GetNumSkillLines = function() return 4 end,
    GetSkillLineInfo = function(i)
        return ({
            { name = "Métiers", isHeader = true, isCollapsed = false },
            { skillID = 393, name = "Dépeçage", rank = 120, maxRank = 150, modifier = 0, description = "Retirer la peau." },
            { skillID = 98, name = "Commun", rank = 300, maxRank = 300, modifier = 5, description = "Langue." },
            { skillID = 414, name = "Armure en cuir", rank = 1, maxRank = 1, modifier = 0, description = "" },
        })[i]
    end,
    ExpandSkillHeader = function() end,
    CollapseSkillHeader = function() end,
})

-- rang JcJ
def("C_MajorFactions", {
    GetMajorFactionProgressionInfo = function(id)
        if id == 2800 then return { renownLevel = 3, renownReputationEarned = 1200, renownLevelThreshold = 5000, maxLevel = 14 } end
    end,
    GetRenownRewardsForLevel = function(id, level)
        if level == 5 then return { { icon = 132483, name = "Tabard de sergent", description = "Un tabard." } } end
        return {}
    end,
})
def("GetCurrentArenaSeason", function() return 2 end)
def("C_SeasonInfo", { GetTimeUntilCurrentPVPSeasonEnd = function() return 3 * 86400 + 7200 end })
def("GetPVPLifetimeStats", function() return 87, 0, 0 end)
def("GetPVPSessionStats", function() return 4, 0 end)

-- monnaies : aucune au début
local currencies = {}
def("C_CurrencyInfo", {
    GetCurrencyListSize = function() return #currencies end,
    GetCurrencyListInfo = function(i) return currencies[i] end,
    ExpandCurrencyList = function() end,
})

---------------------------------------------------------------------------
-- Fenêtre du jeu (CharacterFrame) et ses volets
---------------------------------------------------------------------------
local SUBFRAMES = { "PaperDollFrame", "ReputationFrame", "SkillsFrame", "PVPRankFrame" }
local cf = CreateFrame("Frame", "CharacterFrame", UIParent)
cf:Hide()
def("CharacterFrame", cf)
for _, name in ipairs(SUBFRAMES) do
    local f = CreateFrame("Frame", name, cf)
    f:Hide()
    def(name, f)
end
cf.ShowSubFrame = function(self, name)
    self.activeSubframe = name
    for _, n in ipairs(SUBFRAMES) do if n ~= name then _G[n]:Hide() end end
    _G[name]:Show()
end
cf.RefreshDisplay = function() end
def("ShowUIPanel", function(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Show()
end)
local toggles = {}
def("ToggleCharacter", function(tab, onlyShow)
    toggles[#toggles + 1] = tab
    local sub = _G[tab]
    if not sub then return end
    if cf:IsShown() then
        if sub:IsShown() then
            if not onlyShow then HideUIPanel(cf) end
        else
            cf:ShowSubFrame(tab)
        end
    else
        cf:ShowSubFrame(tab)
        ShowUIPanel(cf)
    end
end)

-- cases d'équipement du jeu, sous PaperDollItemsFrame
local items = CreateFrame("Frame", "PaperDollItemsFrame", _G.PaperDollFrame)
local SLOT_IDS = { Head = 1, Neck = 2, Shoulder = 3, Shirt = 4, Chest = 5, Waist = 6, Legs = 7, Feet = 8, Wrist = 9,
    Hands = 10, Finger0 = 11, Finger1 = 12, Trinket0 = 13, Trinket1 = 14, Back = 15, MainHand = 16, SecondaryHand = 17,
    Ranged = 18, Tabard = 19, Ammo = 0 }
local slots = {}
for name, id in pairs(SLOT_IDS) do
    local b = CreateFrame("Button", "Character" .. name .. "Slot", items)
    b:SetID(id)
    b:SetPoint("TOPLEFT", items, "TOPLEFT", id * 3, -id * 2)
    b:SetFrameLevel(101)
    b.BorderFrame = CreateFrame("Frame", nil, b)
    b.BorderFrame:SetFrameLevel(99)
    b.popoutButton = CreateFrame("Button", nil, b)
    def("Character" .. name .. "Slot", b)
    slots[name] = b
end
slots.Ammo:Hide()                    -- pas d'arme à feu : le jeu cache les munitions

-- scène du personnage du jeu (CharacterModelScene) et ses boutons pour tourner / zoomer
local modelScene = CreateFrame("Frame", "CharacterModelScene", _G.PaperDollFrame)
modelScene:SetPoint("TOPLEFT", _G.PaperDollFrame, "TOPLEFT", 20, -30)
modelScene:SetSize(342, 360)
modelScene:SetFrameLevel(50)
modelScene.ControlFrame = CreateFrame("Frame", nil, modelScene)
modelScene.ControlFrame:SetPoint("TOP", modelScene, "TOP", 0, -40)
def("CharacterModelScene", modelScene)

---------------------------------------------------------------------------
-- Chargement de tout l'addon, comme le jeu
---------------------------------------------------------------------------
M.enableStrict()
local files = {}
for line in io.lines(ADDON_DIR .. "\\Platyplus.toc") do
    local f = line:match("^([%w_%.]+%.lua)%s*$")
    if f then files[#files + 1] = f end
end
local ns = M.loadAddon(ADDON_DIR, "Platyplus", files)
M.fireEvent("ADDON_LOADED", "Platyplus")
M.fireEvent("PLAYER_LOGIN")
M.fireEvent("PLAYER_ENTERING_WORLD")
M.advance(1)

local CW = ns.CharWindow
local function win() return rawget(_G, "PlatyplusCharacterWindow") end
local function winShown() local f = win(); return f ~= nil and S(f).shown end
local function offscreen(f) local p = S(f).points[1]; return p ~= nil and p[4] == -6000 and S(f).alpha == 0 end
local function listRows(id)
    local list = CW.tabs[id].panel.list
    local out = {}
    for i = 1, list.used.row do out[i] = list.pools.row[i] end
    return out, list
end
local function rowText(r) return tostring(S(r.name).text) end
local function findRow(id, text)
    for _, r in ipairs((listRows(id))) do if rowText(r) == text then return r end end
end

section("réglages et fenêtre du jeu cachée")
check(CW and CW.Sync and CW.Select and CW.Apply, "ns.CharWindow : Sync, Select, Apply")
check(ns.db.charWindow == true and ns.db.charWinScale == 1, "active par défaut")
check(offscreen(cf), "CharacterFrame hors de l'écran, transparente")
check(#CW.order == 5, "5 onglets connus (" .. #CW.order .. ")")

section("touche C : onglet Personnage")
ToggleCharacter("PaperDollFrame")
M.advance(0.3)
check(winShown(), "fenêtre du personnage ouverte")
check(offscreen(cf), "fenêtre du jeu replacée hors de l'écran après ShowUIPanel")
check(CW.current == "PaperDollFrame", "onglet Personnage")
check(S(win().title).text == "Sergent Leo", "nom avec titre")
local sub = tostring(S(win().sub).text)
check(sub:find("Niveau 42", 1, true) and sub:find("Guerrier", 1, true) and sub:find("<Les Platypus>", 1, true),
    "niveau, classe et guilde (" .. sub .. ")")
check(not S(CW.tabButtons.TokenFrame).shown, "pas d'onglet Monnaies sans monnaie")
local panel = CW.tabs.PaperDollFrame.panel
local head, hands = slots.Head, slots.Hands
check(S(head).parent == panel.holder and S(hands).parent == panel.holder, "cases du jeu posées dans la fenêtre")
local ph = S(head).points[1]
check(ph and ph[2] == panel.holder and ph[4] == 0 and ph[5] == 0, "Tête en haut à gauche")
local pr = S(hands).points[1]
check(pr and pr[4] == CW.Layout.EQUIP_W - 37, "Mains en haut de la colonne de droite")
check(S(head.BorderFrame).level == S(head).level - 2 and S(head.popoutButton).level == S(head).level - 3,
    "cadre décoratif et flèche de rechange restent sous la case")
local mh, oh = S(slots.MainHand).points[1], S(slots.SecondaryHand).points[1]
check(mh and oh and mh[5] == oh[5] and oh[4] > mh[4] and mh[5] == -CW.Layout.WEAPON_Y,
    "armes côte à côte sous le modèle")
check(not (CW.Equip.info.Ammo and S(CW.Equip.info.Ammo).shown), "munitions cachées par le jeu : pas de bandeau")
local headInfo = CW.Equip.info.Head
check(S(headInfo.name).text == "Casque", "nom de l'objet à côté de la case (" .. tostring(S(headInfo.name).text) .. ")")
local detail = tostring(S(headInfo.detail).text)
check(detail:find("niv. 45", 1, true) and detail:find("18 %", 1, true), "niveau et durabilité basse (" .. detail .. ")")
check(S(CW.Equip.info.Neck.detail).text == "vide", "case vide marquée")
check(S(CW.tabs.PaperDollFrame.panel.hero.ilvl).text == "37", "niveau d'objet moyen en grand")
check(S(CW.tabs.PaperDollFrame.panel.hero.dura).text == "18 %", "durabilité la plus basse")
check(S(modelScene).parent == panel.holder, "scène du personnage du jeu posée dans la fenêtre")
check(S(modelScene).h == CW.Layout.COLUMN_H and S(modelScene).w == math.floor(CW.Layout.COLUMN_H * 342 / 360),
    "même proportions que dans le jeu (" .. S(modelScene).w .. " x " .. S(modelScene).h .. ")")
local sp = S(modelScene).points[1]
check(sp and sp[1] == "TOP" and sp[4] == math.floor(CW.Layout.EQUIP_W / 2), "centrée entre les deux colonnes")
check(S(modelScene.ControlFrame).points[1][1] == "BOTTOM", "boutons tourner / zoomer en bas de la scène")
check(S(CW.Stage.fader).shown, "bords fondus dans la fenêtre")
check(#modelUnits == 0, "pas de modèle de repli quand la scène du jeu existe")

section("caractéristiques")
local labels = {}
for i = 1, CW.Stats.used.rows do labels[#labels + 1] = tostring(S(CW.Stats.rows[i].Label).text) end
local all = table.concat(labels, ",")
check(all:find("Vie", 1, true) and not all:find("Vie :", 1, true), "« Vie » sans les deux-points (" .. all .. ")")
check(not all:find("Dégâts main gauche", 1, true), "ligne à 0 cachée comme dans le jeu (hideAt)")
check(not all:find("Blocage", 1, true), "ligne réservée (showFunc) cachée")
local heads = {}
for i = 1, CW.Stats.used.cards do heads[#heads + 1] = tostring(S(CW.Stats.cards[i].title).text) end
local hs = table.concat(heads, ",")
check(hs == "GÉNÉRAL,ATTRIBUTS,DÉFENSE,RÉSISTANCES", "une carte par catégorie, titres en majuscules accentuées (" .. hs .. ")")
local resCard = CW.Stats.cards[CW.Stats.used.cards]
check(resCard.chips and #resCard.chips == 5 and S(resCard.chips[1].value).text == "18", "5 résistances, Arcanes = 18")
local vieRow
for i = 1, CW.Stats.used.rows do if S(CW.Stats.rows[i].Label).text == "Vie" then vieRow = CW.Stats.rows[i] end end
M.fire(vieRow, "OnEnter")
check(tooltipShown == "Vie 1 250", "survol : l'infobulle du jeu")

section("caractéristiques protégées par le jeu (valeurs secrètes)")
-- comme Forever quand les statistiques sont restreintes : UnitStat & co. renvoient des valeurs secrètes ;
-- les fonctions de mise en forme du jeu échouent alors (comparaison d'une valeur secrète)
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local restricted = true
def("issecretvalue", function(v) return v == SECRET end)
def("UnitStat", function() if restricted then return SECRET, SECRET, SECRET, SECRET end return 80, 87, 7, 0 end)
def("UnitArmor", function() return SECRET, SECRET end)
def("UnitHealthMax", function() return 428 end)
def("UnitPowerMax", function() return 100 end)
def("UnitPowerType", function() return 1, "RAGE" end)
def("RAGE", "Rage")
def("GetDodgeChance", function() return 5.1 end)
def("GetParryChance", function() error("valeur secrète comparée") end)
-- comme Forever : SetText(valeur secrète) laisse sur le texte l'aspect secret « Text », qui reste après un SetText
-- ordinaire ; seul ClearText l'enlève. Ensuite GetText rend une valeur protégée et la comparer plante (ici : GetText
-- échoue directement, faute de pouvoir faire planter une comparaison dans le simulateur).
local baseSetText, baseGetText = M.impl.SetText, M.impl.GetText
M.impl.SetText = function(f, t)
    if t == SECRET then S(f).secretAspect = true end
    return baseSetText(f, t)
end
M.impl.SetFormattedText = function(f, fmt, ...)
    for i = 1, select("#", ...) do if select(i, ...) == SECRET then S(f).secretAspect = true; S(f).text = SECRET; return end end
    S(f).text = string.format(fmt, ...)
end
M.impl.GetText = function(f)
    if S(f).secretAspect then error("attempt to compare a secret value (texte marqué)") end
    return baseGetText(f)
end
M.impl.ClearText = function(f) S(f).secretAspect = nil; S(f).text = "" end
M.impl.HasSecretAspect = function(f) return S(f).secretAspect == true end
def("Enum", setmetatable({ SecretAspect = { Text = 8 } }, { __index = rawget(_G, "Enum") }))
local info = rawget(_G, "PAPERDOLL_STATINFO")
local oldStrength = info.STRENGTH.updateFunc
info.STRENGTH.updateFunc = function(f, unit)
    local _, effective = UnitStat(unit, 1)
    if effective == SECRET then error("attempt to compare a secret value") end
    return oldStrength(f, unit)
end
CW:Refresh("PaperDollFrame")
local rawLabels, rawValues = {}, {}
for i = 1, CW.Stats.used.rows do
    rawLabels[#rawLabels + 1] = tostring(S(CW.Stats.rows[i].Label).text)
    rawValues[tostring(S(CW.Stats.rows[i].Label).text)] = S(CW.Stats.rows[i].Value).text
end
local rl = table.concat(rawLabels, ",")
check(CW.Stats.restricted, "valeurs protégées détectées (issecretvalue)")
check(rawValues["Force"] == SECRET and rawValues["Armure"] == SECRET, "Force et Armure : la valeur du jeu affichée telle quelle (" .. rl .. ")")
check(rawValues["Vie"] == 428 and rawValues["Rage"] == 100, "vie et rage")
check(rl:find("Esquive", 1, true) and not rl:find("Parade", 1, true), "une valeur qui échoue est seulement omise (" .. rl .. ")")
check(S(CW.Stats.note).shown, "note : affichage simplifié")
restricted = false
info.STRENGTH.updateFunc = oldStrength
def("issecretvalue", function() return false end)
local marked = 0
for i = 1, #CW.Stats.rows do if S(CW.Stats.rows[i].Value).secretAspect then marked = marked + 1 end end
check(marked >= 5, "après l'affichage brut, des textes gardent la marque secrète (" .. marked .. ")")
CW:Refresh("PaperDollFrame")
check(not CW.Stats.restricted and not S(CW.Stats.note).shown, "valeurs de nouveau lisibles : affichage complet, sans note")
local back = {}
for i = 1, CW.Stats.used.rows do back[#back + 1] = tostring(S(CW.Stats.rows[i].Label).text) end
local bl = table.concat(back, ",")
check(bl == "Vie,Force,Armure",
    "retour du joueur (seulement Vie et Rage) : toutes les caractéristiques reviennent après le combat (" .. bl .. ")")
-- une fonction du jeu qui échoue (valeur protégée en route) : la valeur brute à la place, pas une ligne vide
info.STRENGTH.updateFunc = function() error("attempt to compare a secret value") end
CW:Refresh("PaperDollFrame")
local forceValue
for i = 1, CW.Stats.used.rows do
    if S(CW.Stats.rows[i].Label).text == "Force" then forceValue = S(CW.Stats.rows[i].Value).text end
end
check(forceValue == 87, "Force : fonction du jeu en échec, valeur brute affichée (" .. tostring(forceValue) .. ")")
info.STRENGTH.updateFunc = oldStrength
M.impl.SetText, M.impl.GetText = baseSetText, baseGetText
CW:Refresh("PaperDollFrame")

section("onglet Réputation (clic sur l'onglet)")
CW.tabButtons.ReputationFrame:Click()
M.advance(0.2)
check(toggles[#toggles] == "ReputationFrame" and cf.activeSubframe == "ReputationFrame", "le jeu change de volet aussi")
check(CW.current == "ReputationFrame" and not S(panel).shown, "onglet Réputation affiché")
local rows = listRows("ReputationFrame")
check(#rows == 4 and rowText(rows[1]) == "Alliance", "groupe Alliance, 2 factions, groupe Autre (" .. #rows .. ")")
local stormwind = findRow("ReputationFrame", "Hurlevent")
local right = tostring(S(stormwind.right).text)
check(right == "3,000 / 12,000" and S(stormwind.pillText).text == "Honoré", "chiffres à droite, rang en pastille (" .. right .. ")")
check(math.abs((stormwind.value or 0) - 0.25) < 0.001 and S(stormwind.fill.tl).shown, "ligne remplie au quart")
local fillLevel = S(stormwind.fill.tl).layer
check(fillLevel == "BORDER" and S(stormwind.right).layer == "OVERLAY" and S(stormwind.fill.tl).parent == stormwind,
    "remplissage dessiné sous les chiffres, dans la même ligne (rien ne les cache)")
local ironforge = findRow("ReputationFrame", "Forgefer")
check(S(ironforge.name).textColor[1] == ns.W.C.bad[1], "faction en guerre en rouge")
stormwind:Click()
M.advance(0.2)
local _, list = listRows("ReputationFrame")
check(list.used.text == 1 and list.used.button == 2, "détail : description et 2 actions (" .. list.used.button .. ")")
list.pools.button[1]:Click()
check(repCalls[#repCalls] == "watch:2", "« Suivre sur la barre » : SetWatchedFactionByIndex(2)")
list.pools.button[2]:Click()
check(repCalls[#repCalls] == "active:2:false", "« Ranger (inactive) »")
findRow("ReputationFrame", "Alliance"):Click()
M.advance(0.2)
rows = listRows("ReputationFrame")
check(repCalls[#repCalls] == "collapse:1" and #rows == 2, "groupe replié : ses factions disparaissent")

section("touche K : onglet Compétences")
ToggleCharacter("SkillsFrame", false)
M.advance(0.2)
check(CW.current == "SkillsFrame", "l'onglet suit le volet ouvert par une touche")
local skin = findRow("SkillsFrame", "Dépeçage")
check(skin and S(skin.right).text == "120 / 150" and math.abs(skin.value - 0.8) < 0.001, "Dépeçage 120 / 150, ligne remplie à 80 %")
local common = findRow("SkillsFrame", "Commun")
check(common and S(common.pillText).text == "+5" and S(common.pillText).shown, "bonus en pastille (+5)")
local leather = findRow("SkillsFrame", "Armure en cuir")
check(leather and not S(leather.fill.tl).shown and S(leather.pillText).text == "connue", "compétence sans niveau : pas de remplissage, « connue »")

section("onglet JcJ")
CW.tabButtons.PVPRankFrame:Click()
M.advance(0.2)
local pvp = CW.tabs.PVPRankFrame.panel
check(S(pvp.rank).text == "Sergent", "rang 3 de l'Alliance : Sergent (" .. tostring(S(pvp.rank).text) .. ")")
check(tostring(S(pvp.progress).text):find("1200 / 5000", 1, true) or tostring(S(pvp.progress).text):find("1,200 / 5,000", 1, true),
    "progression du rang (" .. tostring(S(pvp.progress).text) .. ")")
check(tostring(S(pvp.season).text) == "Saison 2 · fin dans 3 j 2 h", "saison et fin (" .. tostring(S(pvp.season).text) .. ")")
check(S(pvp.badge).texture == "atlas:UI-Character-Info-Honor-Icon-3", "insigne du rang")
check(S(pvp.tiles[2].value).text == "87" and S(pvp.tiles[1].value).text == "4", "victoires du jour et au total")
check(findRow("PVPRankFrame", "Tabard de sergent") ~= nil, "prochaine récompense")

section("monnaies")
currencies = { { name = "JcJ", isHeader = true, isHeaderExpanded = true }, { name = "Marque d'honneur", quantity = 12, maxQuantity = 100, iconFileID = 1 } }
CW:PaintTabs()
check(S(CW.tabButtons.TokenFrame).shown, "onglet Monnaies affiché quand il y en a")
CW.tabButtons.TokenFrame:Click()
M.advance(0.2)
check(CW.current == "TokenFrame" and S(findRow("TokenFrame", "Marque d'honneur").right).text == "12 / 100", "monnaie et plafond")

section("fermeture")
ToggleCharacter("PaperDollFrame")
M.advance(0.2)
check(CW.current == "PaperDollFrame" and winShown(), "C depuis un autre onglet : onglet Personnage")
ToggleCharacter("PaperDollFrame")
M.advance(0.2)
check(not winShown() and not cf:IsShown(), "C une deuxième fois : fermée")
ToggleCharacter("PaperDollFrame")
M.advance(0.2)
win().close:Click()
M.advance(0.2)
check(not winShown() and not cf:IsShown(), "la croix ferme la fenêtre du jeu aussi")

section("taille et position")
ns:Set("charWinScale", 1.2)
check(S(win()).scale == 1.2, "taille appliquée")
CW:ResetPosition()
check(next(ns.db.charWinPos) == nil, "position remise à zéro")

section("option coupée : fenêtre du jeu")
ns:Set("charWindow", false)
check(S(head).parent == items and S(head).points[1][4] == 3 and S(head).level == 101, "cases rendues au jeu, à leur place")
check(S(head.BorderFrame).level == 99, "niveaux d'origine remis")
check(S(modelScene).parent == _G.PaperDollFrame and S(modelScene).points[1][4] == 20 and S(modelScene).level == 50,
    "scène rendue au jeu, à sa place")
check(S(modelScene.ControlFrame).points[1][1] == "TOP", "boutons de la scène remis")
check(S(cf).alpha == 1, "fenêtre du jeu visible")
ToggleCharacter("PaperDollFrame")
M.advance(0.2)
check(not winShown() and S(cf).points[1][4] == 16, "C ouvre la fenêtre du jeu")
ToggleCharacter("PaperDollFrame")
ns:Set("charWindow", true)
ToggleCharacter("PaperDollFrame")
M.advance(0.2)
check(winShown() and S(head).parent == panel.holder and S(modelScene).parent == panel.holder,
    "option remise : cases et scène reprises, fenêtre Platyplus")

section("bilan")
M.report()
if #M.errors > 0 or #failures > 0 then error(#M.errors .. " erreur(s) d'exécution, " .. #failures .. " échec(s)") end
M.realPrint("TOUT EST BON")
