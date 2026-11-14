-- Platyplus : la place du journal des donjons (DungeonJournal, par Exehn) dans Platyplus.
--
-- Le dossier DungeonJournal/ est l'addon ForeverDungeonJournal recopié tel quel par dev/make_dungeonjournal.py
-- (voir DungeonJournal/PLATYPLUS.txt). Ce fichier, écrit à la main et chargé juste avant lui, lui prépare :
--   * son propre espace de noms, ns.Dungeon : chaque fichier du journal commence par « FDJ = FDJ.Dungeon », ses
--     noms ne se mélangent donc pas à ceux de Platyplus ;
--   * la veille : si l'addon DungeonJournal séparé est chargé, c'est lui qui tourne et la copie de Platyplus ne
--     fait rien du tout. Pendant ce temps, Platyplus garde une copie de ses réglages, favoris et progression
--     (ForeverDungeonJournalDB -> PlatyplusDungeonDB) : en désactivant l'addon séparé, on retrouve tout ;
--   * les points d'accroche ajoutés par le script (FDJ.PpC, FDJ.PpBackdrop, FDJ.PpViewChanged...) : ils passent
--     la main au style (DungeonJournalSkin.lua, D.PpSkin) et à la liste des donjons (DungeonJournalPlus.lua,
--     D.PpPlus). Sans eux, ils rendent ce qu'on leur donne : le journal garde son propre look.
local ADDON, ns = ...

local D = {}
ns.Dungeon = D

local STANDALONE = "ForeverDungeonJournal"
local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

local function standaloneLoaded()
    if type(isLoaded) ~= "function" then return false end
    local ok, loaded = pcall(isLoaded, STANDALONE)
    return ok and loaded and true or false
end

-- ForeverDungeonJournal est dans les OptionalDeps de Platyplus.toc : s'il est activé, le jeu l'a déjà chargé
D.PpStandby = standaloneLoaded()

---------------------------------------------------------------------------
-- Points d'accroche du style (DungeonJournalSkin.lua remplit D.PpSkin)
---------------------------------------------------------------------------
-- chaque couleur posée par le journal : kind = "bg" (fond), "edge" (liseré), "tex" (aplat), "text" (texte)
function D.PpC(kind, ...)
    local skin = D.PpSkin
    if skin then return skin.C(kind, ...) end
    return ...
end

-- chaque fond (SetBackdrop) : le style peut l'aplatir (liseré fin, pas de pierre ni de parchemin)
function D.PpBackdrop(frame, backdrop)
    local skin = D.PpSkin
    if skin and type(backdrop) == "table" then backdrop = skin.Backdrop(frame, backdrop) end
    return frame:SetBackdrop(backdrop)
end

-- couleur écrite dans un texte (« |cff... ») : role = "done" (objectif rempli), "muted" (texte secondaire) ;
-- nil sans style (le journal garde la sienne)
function D.PpInk(role)
    local skin = D.PpSkin
    return skin and skin.Ink and skin.Ink(role) or nil
end

-- surbrillance au survol : la lueur dorée de Blizzard devient le voile clair de Platyplus
function D.PpHighlight(frame, ...)
    frame:SetHighlightTexture(...)
    local skin = D.PpSkin
    if skin and skin.Highlight then skin.Highlight(frame) end
end

-- bouton ou barre de défilement de Blizzard qui vient d'être créé (template = son modèle) : repeint
function D.PpWidget(template, frame)
    local skin = D.PpSkin
    if skin and skin.Widget and frame then
        local ok, err = pcall(skin.Widget, template, frame)
        if not ok then geterrorhandler()(err) end
    end
    return frame
end

-- pas de parchemin sous les pages quand le style est allumé (fond sombre, texte clair)
function D.PpNoParchment()
    return D.PpSkin ~= nil
end

---------------------------------------------------------------------------
-- Points d'accroche des pages (DungeonJournalPlus.lua remplit D.PpPlus)
---------------------------------------------------------------------------
-- le journal change de page ou de donjon : la liste de gauche suit (au prochain affichage, une seule fois)
function D.PpViewChanged()
    local plus = D.PpPlus
    if plus and plus.ViewChanged then plus.ViewChanged() end
end

-- l'accueil vient d'être redessiné : niveau conseillé et progression sur les cartes
function D.PpAfterHome(cards, shown)
    local plus = D.PpPlus
    if not (plus and plus.AfterHome) then return end
    local ok, err = pcall(plus.AfterHome, cards, shown)
    if not ok then geterrorhandler()(err) end
end

-- la fenêtre du journal vient d'être construite (connexion)
function D.PpAfterBuild()
    local skin = D.PpSkin
    if not (skin and skin.AfterBuild) then return end
    local ok, err = pcall(skin.AfterBuild, rawget(_G, "PlatyplusDungeonFrame"))
    if not ok then geterrorhandler()(err) end
end

-- la liste des quêtes (kind = "list") ou la page d'une quête ("detail") vient d'être dessinée
function D.PpAfterQuests(kind)
    local skin = D.PpSkin
    if not (skin and skin.AfterQuests) then return end
    local ok, err = pcall(skin.AfterQuests, kind, rawget(_G, "PlatyplusDungeonFrame"))
    if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Allègements (mesurés dans le simulateur, dev/test_dungeonjournal.lua)
---------------------------------------------------------------------------
-- Langues : le journal charge les textes de ses dix langues (≈ 1,7 Mo de mémoire Lua, dont les nouveaux donjons
-- traduits partout). Une fois les réglages chargés, Platyplus ne garde que la langue du jeu, l'anglais (base de
-- tous les textes) et celle choisie dans le menu du journal. Le menu de langue du journal ne propose plus qu'elles ;
-- toutes ses recherches de texte ont un repli sur l'anglais.
function D.PpLanguages(list)
    D.PpLanguageChoices = list
    return list
end

function D.PpPruneLocales()
    if D.ppPruned then return D.ppPruned end
    local keep = { enUS = true }
    for _, get in ipairs({ D.GetClientLanguage, D.GetLanguage }) do
        if type(get) == "function" then
            local ok, lang = pcall(get)
            if ok and type(lang) == "string" then keep[lang] = true end
        end
    end
    local removed = {}
    for _, field in ipairs({ "Locales", "ContentLocales" }) do
        local t = D[field]
        if type(t) == "table" then
            for lang in pairs(t) do
                if not keep[lang] then
                    t[lang] = nil
                    removed[lang] = true
                end
            end
        end
    end
    local choices = D.PpLanguageChoices
    if type(choices) == "table" then
        for i = #choices, 1, -1 do
            local c = choices[i]
            if type(c) == "table" and not keep[c.locale] then table.remove(choices, i) end
        end
    end
    local n = 0
    for _ in pairs(removed) do n = n + 1 end
    D.ppPruned = { removed = n, keep = keep }
    return D.ppPruned
end

-- Quêtes : chaque événement du journal de quêtes (QUEST_LOG_UPDATE arrive par rafales en ramassant, en parlant à
-- un PNJ...) redessinait le journal à l'image suivante. Maintenant : rien tant qu'il est fermé (il se redessine en
-- entier à l'ouverture), et au plus un dessin toutes les 0,3 s quand il est ouvert.
local QUEST_REFRESH_DELAY = 0.3
function D.PpThrottleQuestRefresh()
    local original = D.ScheduleQuestRefresh
    if type(original) ~= "function" or D.ppThrottled then return end
    D.ppThrottled = true
    local waiting = false
    D.ScheduleQuestRefresh = function(...)
        local f = rawget(_G, "PlatyplusDungeonFrame")
        if not (f and f:IsShown()) then return end
        if waiting then return end
        if not (C_Timer and C_Timer.After) then return original(...) end
        waiting = true
        C_Timer.After(QUEST_REFRESH_DELAY, function()
            waiting = false
            local ok, err = pcall(original)
            if not ok then geterrorhandler()(err) end
        end)
    end
end

---------------------------------------------------------------------------
-- Veille : copie des réglages de l'addon séparé
---------------------------------------------------------------------------
local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local t = {}
    seen[v] = t
    for k, x in pairs(v) do t[deepCopy(k, seen)] = deepCopy(x, seen) end
    return t
end
D.PpDeepCopy = deepCopy

-- tant que l'addon séparé tourne, ses réglages, favoris et progression sont recopiés dans ceux de Platyplus
-- (à la connexion et à la déconnexion : la copie suit la dernière session)
function D.PpMirror()
    if not D.PpStandby then return false end
    local db, char = rawget(_G, "ForeverDungeonJournalDB"), rawget(_G, "ForeverDungeonJournalCharacterDB")
    local copied = false
    if type(db) == "table" and next(db) ~= nil then
        PlatyplusDungeonDB = deepCopy(db)
        copied = true
    end
    if type(char) == "table" and next(char) ~= nil then
        PlatyplusDungeonCharacterDB = deepCopy(char)
        copied = true
    end
    return copied
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        if not D.PpStandby then
            self:UnregisterEvent("PLAYER_LOGOUT")
            if type(D.DB) == "table" then
                D.PpPruneLocales()
                D.PpThrottleQuestRefresh()
            end
            return
        end
        D.ppMirrored = D.PpMirror()
    elseif event == "PLAYER_LOGOUT" then
        D.PpMirror()
    end
end)

-- état, pour /pp donjons et l'onglet des réglages
function D.PpStatus()
    if D.PpStandby then return "standby" end
    if type(D.ORDER) ~= "table" or #D.ORDER == 0 then return "missing" end
    return "on"
end
