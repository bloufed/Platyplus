-- Monde simulé pour les captures de la fenêtre du personnage (render_preview.lua) : guerrier humain niveau 42 équipé,
-- fenêtre du jeu (CharacterFrame) et ses volets, cases d'équipement, caractéristiques, réputations, compétences, JcJ.
-- À charger AVANT l'addon : CharWindow:Init branche ses crochets sur CharacterFrame.
-- Usage (dans render_preview.lua) : dofile(DEV .. "\\preview_charworld.lua")(M, def)
return function(M, def)
    -- le simulateur ignore SetParent : les cases du jeu doivent vraiment changer de parent pour être dessinées
    M.impl.SetParent = function(f, parent) M.state(f).parent = parent end
    local ICON = "Interface\\Icons\\"
    local equip = {
        Head = { 201, "Heaume de Stromgarde", 3, 45, "INV_Helmet_03" },
        Neck = { 202, "Pendentif de l'ours", 2, 40, "INV_Jewelry_Necklace_07" },
        Shoulder = { 203, "Épaulières du chasseur", 2, 38, "INV_Shoulder_02" },
        Back = { 204, "Cape de lin renforcée", 2, 35, "INV_Misc_Cape_01" },
        Chest = { 205, "Cuirasse du crépuscule", 3, 44, "INV_Chest_Plate06" },
        Shirt = { 206, "Chemise blanche", 1, 1, "INV_Shirt_White_01" },
        Wrist = { 207, "Brassards de mailles", 2, 36, "INV_Bracer_07" },
        Hands = { 208, "Gantelets du vétéran", 2, 39, "INV_Gauntlets_04" },
        Waist = { 209, "Ceinture à boucle", 2, 37, "INV_Belt_03" },
        Legs = { 210, "Jambières de la garde", 3, 43, "INV_Pants_04" },
        Feet = { 211, "Bottes ferrées", 2, 40, "INV_Boots_Plate_01" },
        Finger0 = { 212, "Anneau de rubis", 2, 41, "INV_Jewelry_Ring_03" },
        Finger1 = { 213, "Anneau de cuivre", 1, 30, "INV_Jewelry_Ring_01" },
        Trinket0 = { 214, "Insigne du gladiateur", 3, 45, "INV_Jewelry_Talisman_07" },
        MainHand = { 216, "Lame de la marée noire", 3, 46, "INV_Sword_04" },
        SecondaryHand = { 217, "Bouclier de chêne", 2, 40, "INV_Shield_06" },
        Ranged = { 218, "Arc court renforcé", 2, 35, "INV_Weapon_Bow_02" },
    }
    local SLOT_IDS = { Head = 1, Neck = 2, Shoulder = 3, Shirt = 4, Chest = 5, Waist = 6, Legs = 7, Feet = 8, Wrist = 9,
        Hands = 10, Finger0 = 11, Finger1 = 12, Trinket0 = 13, Trinket1 = 14, Back = 15, MainHand = 16,
        SecondaryHand = 17, Ranged = 18, Tabard = 19, Ammo = 0 }
    local byId, bySlot = {}, {}
    for name, e in pairs(equip) do
        byId[e[1]] = { name = e[2], q = e[3], ilvl = e[4], icon = ICON .. e[5], slot = name }
        bySlot[SLOT_IDS[name]] = e[1]
    end
    local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. byId[id].name .. "]|h|r" end
    local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end

    def("GetInventoryItemLink", function(unit, slot) local id = bySlot[slot]; return id and linkOf(id) end)
    def("GetInventoryItemQuality", function(unit, slot) local id = bySlot[slot]; return id and byId[id].q end)
    def("GetInventoryItemTexture", function(unit, slot) local id = bySlot[slot]; return id and byId[id].icon end)
    def("GetInventoryItemDurability", function(slot) if slot == 5 then return 18, 100 end if bySlot[slot] then return 72, 100 end end)
    local I = rawget(_G, "C_Item") or {}
    local oldLevel, oldInfo = I.GetDetailedItemLevelInfo, I.GetItemInfo
    I.GetDetailedItemLevelInfo = function(link)
        local it = byId[idOf(link) or 0]
        if it then return it.ilvl, false, it.ilvl end   -- trois valeurs, comme le jeu
        return oldLevel and oldLevel(link)
    end
    I.GetItemInfo = function(link)
        local id = idOf(link)
        local it = byId[id or 0]
        if it then return it.name, linkOf(id), it.q, it.ilvl, 40, "Armure", "Plaques", 1, "", it.icon, 1200 end
        return oldInfo and oldInfo(link)
    end
    def("C_Item", I)

    def("UnitPVPName", function() return "Sergent Leo" end)
    def("UnitRace", function() return "Humain" end)
    def("UnitSex", function() return 2 end)
    def("UnitFactionGroup", function() return "Alliance" end)
    def("GetGuildInfo", function() return "Les Platypus" end)
    def("RAID_CLASS_COLORS", { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } })
    def("GetText", function(key) return rawget(_G, key) end)
    def("MIN_PLAYER_LEVEL_FOR_ITEM_LEVEL_DISPLAY", 10)
    def("PaperDollStatTooltip", function() end)

    local function stat(label, value, numeric)
        return { updateFunc = function(f)
            f.Label:SetText(label .. " :")
            f.Value:SetText(value)
            f.numericValue = numeric or 1
            f:Show()
        end }
    end
    def("PAPERDOLL_STATINFO", {
        ITEMLEVEL = stat("Niveau d'objet moyen", "41"),
        HEALTH = stat("Vie", "2 340"), POWER = stat("Rage", "100"), MOVESPEED = stat("Vitesse", "100%"),
        STRENGTH = stat("Force", "132"), AGILITY = stat("Agilité", "78"), STAMINA = stat("Endurance", "121"),
        INTELLECT = stat("Intelligence", "32"), SPIRIT = stat("Esprit", "45"),
        MAINHAND_DAMAGE = stat("Dégâts", "85 - 127"), ATTACK_AP = stat("Puissance d'attaque", "310"),
        HITCHANCE = stat("Toucher", "3%"), CRITCHANCE = stat("Coup critique", "6,20%"),
        DEFENSE = stat("Défense", "210"), DODGE = stat("Esquive", "5,10%"), PARRY = stat("Parade", "6,00%"),
        BLOCK = stat("Blocage", "4,80%"), ARMOR = stat("Armure", "2 140"),
    })
    def("PAPERDOLL_STATCATEGORIES", {
        { categoryName = "Général", unit = "player", stats = { { stat = "HEALTH" }, { stat = "POWER" }, { stat = "MOVESPEED" } } },
        { categoryName = "Attributs", unit = "player", stats = { { stat = "STRENGTH" }, { stat = "AGILITY" }, { stat = "STAMINA" },
            { stat = "INTELLECT" }, { stat = "SPIRIT" } } },
        { categoryName = "Armes", unit = "player", stats = { { stat = "MAINHAND_DAMAGE" }, { stat = "ATTACK_AP" } } },
        { categoryName = "Modificateurs", unit = "player", stats = { { stat = "HITCHANCE" }, { stat = "CRITCHANCE" } } },
        { categoryName = "Défense", unit = "player", stats = { { stat = "DEFENSE" }, { stat = "DODGE" }, { stat = "BLOCK" },
            { stat = "PARRY" }, { stat = "ARMOR" } } },
    })
    local res = { [6] = 5, [2] = 10, [4] = 0, [3] = 15, [5] = 0 }
    def("PaperDollFrame_SetResistance", function(f, unit, dc)
        local names = { [6] = "Arcanes", [2] = "Feu", [4] = "Givre", [3] = "Nature", [5] = "Ombre" }
        f.Label:SetText(names[dc] .. " :")
        f.Value:SetText(tostring(res[dc]))
        f:Show()
    end)
    local E = rawget(_G, "Enum")
    E.Damageclass = { Physical = 0, Holy = 1, Fire = 2, Nature = 3, Frost = 4, Shadow = 5, Arcane = 6 }
    E.PvPRanks = { Rank_1 = 5 }
    def("PVP_RANK_7_1", "Sergent")

    -- réputations
    def("FACTION_STANDING_LABEL4", "Neutre"); def("FACTION_STANDING_LABEL5", "Amical")
    def("FACTION_STANDING_LABEL6", "Honoré"); def("FACTION_STANDING_LABEL7", "Révéré")
    def("FACTION_BAR_COLORS", { [4] = { r = 0.75, g = 0.75, b = 0 }, [5] = { r = 0, g = 0.6, b = 0.1 },
        [6] = { r = 0, g = 0.6, b = 0.1 }, [7] = { r = 0, g = 0.6, b = 0.1 } })
    local factions = {
        { name = "Alliance", isHeader = true, isCollapsed = false },
        { factionID = 72, name = "Hurlevent", reaction = 7, currentReactionThreshold = 21000, nextReactionThreshold = 42000, currentStanding = 30500, isWatched = true },
        { factionID = 47, name = "Forgefer", reaction = 6, currentReactionThreshold = 9000, nextReactionThreshold = 21000, currentStanding = 14200 },
        { factionID = 54, name = "Gnomeregan en exil", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4100 },
        { factionID = 69, name = "Darnassus", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 1800 },
        { name = "Autre", isHeader = true, isCollapsed = false },
        { factionID = 21, name = "Baie-du-Butin", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 7700 },
        { factionID = 87, name = "La Voile sanglante", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 200, atWarWith = true },
    }
    def("C_Reputation", {
        GetNumFactions = function() return #factions end,
        GetFactionDataByIndex = function(i) return factions[i] end,
    })
    def("C_SkillInfo", {
        GetNumSkillLines = function() return 8 end,
        GetSkillLineInfo = function(i)
            return ({
                { name = "Métiers", isHeader = true },
                { skillID = 164, name = "Forge", rank = 185, maxRank = 225, modifier = 0 },
                { skillID = 186, name = "Minage", rank = 210, maxRank = 225, modifier = 0 },
                { name = "Compétences secondaires", isHeader = true },
                { skillID = 129, name = "Secourisme", rank = 150, maxRank = 225, modifier = 0 },
                { name = "Compétences d'armes", isHeader = true },
                { skillID = 43, name = "Épées", rank = 205, maxRank = 210, modifier = 5 },
                { skillID = 44, name = "Haches", rank = 150, maxRank = 210, modifier = 0 },
            })[i]
        end,
    })
    def("C_MajorFactions", {
        GetMajorFactionProgressionInfo = function(id)
            if id == 2800 then return { renownLevel = 3, renownReputationEarned = 1200, renownLevelThreshold = 5000, maxLevel = 14 } end
        end,
        GetRenownRewardsForLevel = function(id, level)
            if level == 5 then return { { icon = ICON .. "INV_Shirt_GuildTabard_01", name = "Tabard de sergent" } } end
            return {}
        end,
    })
    def("GetCurrentArenaSeason", function() return 2 end)
    def("C_SeasonInfo", { GetTimeUntilCurrentPVPSeasonEnd = function() return 3 * 86400 + 7200 end })
    def("GetPVPLifetimeStats", function() return 87 end)
    def("GetPVPSessionStats", function() return 4 end)

    -- fenêtre du jeu et ses volets
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
    def("ToggleCharacter", function(tab, onlyShow)
        local sub = _G[tab]
        if not sub then return end
        if cf:IsShown() then
            if sub:IsShown() then
                if not onlyShow then cf:Hide() end
            else
                cf:ShowSubFrame(tab)
            end
        else
            cf:ShowSubFrame(tab)
            cf:Show()
        end
    end)
    -- scène du personnage du jeu : fond peint de la race (ici une teinte), personnage (ici une silhouette), boutons
    local sc = CreateFrame("Frame", "CharacterModelScene", _G.PaperDollFrame)
    sc:SetSize(340, 360)
    sc:SetPoint("TOPLEFT", _G.PaperDollFrame, "TOPLEFT", 0, 0)
    local paint = sc:CreateTexture(nil, "BACKGROUND")
    paint:SetAllPoints()
    paint:SetColorTexture(0.30, 0.27, 0.22, 1)
    local sky = sc:CreateTexture(nil, "BACKGROUND", nil, 1)
    sky:SetPoint("TOPLEFT"); sky:SetPoint("TOPRIGHT"); sky:SetHeight(200)
    sky:SetColorTexture(0.36, 0.40, 0.46, 1)
    local hero = sc:CreateTexture(nil, "ARTWORK")
    hero:SetSize(70, 230)
    hero:SetPoint("BOTTOM", sc, "BOTTOM", 0, 40)
    hero:SetColorTexture(0.55, 0.45, 0.35, 1)
    sc.ControlFrame = CreateFrame("Frame", nil, sc)
    sc.ControlFrame:SetSize(120, 24)
    local ctl = sc.ControlFrame:CreateTexture(nil, "ARTWORK")
    ctl:SetAllPoints()
    ctl:SetColorTexture(0.15, 0.12, 0.08, 0.9)
    def("CharacterModelScene", sc)

    -- cases du jeu : icône de l'objet (ou du fond de case), bordure de rareté
    local itemsFrame = CreateFrame("Frame", "PaperDollItemsFrame", _G.PaperDollFrame)
    for name, id in pairs(SLOT_IDS) do
        local b = CreateFrame("Button", "Character" .. name .. "Slot", itemsFrame)
        b:SetSize(37, 37)
        b:SetID(id)
        b:SetPoint("TOPLEFT", itemsFrame, "TOPLEFT", 0, 0)
        local icon = b:CreateTexture(nil, "BORDER")
        icon:SetAllPoints()
        local itemID = bySlot[id]
        icon:SetTexture(itemID and byId[itemID].icon or ("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name))
        b.icon = icon
        b.BorderFrame = CreateFrame("Frame", nil, b)
        b.popoutButton = CreateFrame("Button", nil, b)
        if name == "Ammo" then b:Hide() end
        def("Character" .. name .. "Slot", b)
    end
end
