-- Platyplus : touche d'interaction rapide
-- Hors dialogue, ta touche (F) est liée à INTERACTMOUSEOVER. D'après le code Blizzard, cette commande
-- interagit d'abord avec ce que la souris survole, sinon avec la cible d'interaction la plus proche
-- ("anyinteract") : PNJ, objets, coffres, plantes, minerais, cadavres à looter.
-- Pendant qu'un dialogue PNJ est ouvert (voir Dialog.lua), la même touche est liée au bouton
-- "PlatyplusAdvance" qui fait avancer le dialogue (accepter, rendre, choisir une option...), et les touches
-- 1 à 9 aux boutons "PlatyplusChoice1..9" (les choix numérotés de la fenêtre de quête), seulement quand la
-- fenêtre de quête Platyplus est active : les barres d'action retrouvent ces touches dès que le dialogue se ferme.
-- SoftTargetInteract = 3 active la cible d'interaction automatique devant le personnage.
--
-- Objet de quête (questItemKey) : quand une quête de ton journal a un objet à utiliser et que tu es là où il faut
-- l'utiliser, la touche utilise cet objet ; Maj + touche interagit quand même. Vérifié dans le code de Forever
-- (Blizzard_ObjectiveTracker, QuestUtils.lua) : le suivi des quêtes lit GetQuestLogSpecialItemInfo(index)
-- -> lien, icône, charges, montrer-une-fois-finie, et IsQuestLogSpecialItemInRange(index) -> 1 à portée, 0 trop
-- loin, nil sans zone (relu toutes les 0,2 s). On ne bascule que sur 1. L'objet est utilisé par un bouton sécurisé
-- « item:ID » (SecureTemplates : UseItemByName), comme la touche pour manger.
-- Combat : les liaisons sont reposées à PLAYER_REGEN_DISABLED (juste avant le verrou du combat) : la touche devient
-- INTERACTTARGET (« anyinteract » seul, sans passer par la souris) : sinon INTERACTMOUSEOVER prenait le mob vivant
-- sous le curseur au lieu du corps à looter. L'objet de quête passe alors sur Maj + touche.
-- Optimisation : le contrôle de portée (4 fois par seconde) ne tourne que si une quête a un objet à utiliser.
local ADDON, ns = ...

local Interact = {}
ns.Interact = Interact

local BINDING = "INTERACTMOUSEOVER"
local COMBAT_BINDING = "INTERACTTARGET"
local ADVANCE_BUTTON = "PlatyplusAdvance"
local QUEST_BUTTON = "PlatyplusQuestItem"
local RANGE_EVERY = 0.25
local owner = CreateFrame("Frame")
local pending = false      -- un changement attend la fin du combat
local dialogMode = false   -- true : la touche fait avancer le dialogue
local fighting = false     -- entre PLAYER_REGEN_DISABLED et PLAYER_REGEN_ENABLED

-- objets de quête : quêtes qui en ont un, celui qu'on utilise maintenant, bouton, contrôle, repère à l'écran
local quest = { list = {}, active = nil, bound = nil, button = nil, ticker = nil, hint = nil }

local function api(name) return rawget(_G, name) end

local function ensureSoftTarget()
    local ok, current = pcall(GetCVar, "SoftTargetInteract")
    if ok and current ~= nil and current ~= "3" then
        pcall(SetCVar, "SoftTargetInteract", "3")
        ns:Debug("SoftTargetInteract -> 3")
    end
end

---------------------------------------------------------------------------
-- Repère à l'écran : « F : [Torche]   Maj+F : interagir »
local function hintFrame()
    if quest.hint then return quest.hint end
    local f = CreateFrame("Frame", "PlatyplusQuestHint", UIParent)
    f:SetSize(360, 30)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(false)
    local T = ns.THEME
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.75)
    local edge = f:CreateTexture(nil, "ARTWORK")
    edge:SetWidth(3)
    edge:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    edge:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 1)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", f, "LEFT", 10, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetJustifyH("LEFT")
    f.icon, f.text = icon, text
    f:Hide()
    quest.hint = f
    return f
end

local function updateHint()
    local e = quest.bound
    if not e or not ns.db.questItemHint then
        if quest.hint then quest.hint:Hide() end
        return
    end
    local f = hintFrame()
    local key = ns.db.key or "?"
    f.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local extra = key:find("-", 1, true) and "" or ns.Tf("   |cff999999Maj+%s : interagir|r", key)
    f.text:SetText(ns.Tf("|cffffd133%s|r : %s%s", key, e.link or ns.T("objet de quête"), extra))
    f:SetWidth(math.max(200, (f.text:GetStringWidth() or 200) + 52))
    f:Show()
end

---------------------------------------------------------------------------
-- Les override bindings ne sont ni sauvegardés ni modifiables en combat :
-- on les repose à chaque connexion / rechargement, et après le combat si besoin.
function Interact:Apply()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    ClearOverrideBindings(owner)
    quest.bound = nil
    local key = ns.db.key
    if not (ns.db.interact and key and key ~= "") then
        updateHint()
        return
    end
    if dialogMode then
        SetOverrideBindingClick(owner, true, key, ADVANCE_BUTTON)
        ns:Debug("touche", key, "->", ADVANCE_BUTTON)
        if ns.db.questWindow and ns.Dialog then
            for i = 1, ns.Dialog.NUM_KEYS do
                SetOverrideBindingClick(owner, true, tostring(i), "PlatyplusChoice" .. i)
            end
        end
    elseif fighting then
        -- en combat : le corps à looter, l'objet ou le PNJ le plus proche, jamais le mob vivant sous la souris
        SetOverrideBinding(owner, true, key, COMBAT_BINDING)
        if quest.active and quest.button and ns.db.questItemKey and not key:find("-", 1, true) then
            SetOverrideBindingClick(owner, true, "SHIFT-" .. key, QUEST_BUTTON)
        end
        ns:Debug("touche", key, "->", COMBAT_BINDING, "(combat)")
    elseif quest.active and quest.button and ns.db.questItemKey then
        SetOverrideBindingClick(owner, true, key, QUEST_BUTTON)
        if not key:find("-", 1, true) then SetOverrideBinding(owner, true, "SHIFT-" .. key, BINDING) end
        quest.bound = quest.active
        ns:Debug("touche", key, "-> objet de quête", quest.active.itemID)
    else
        SetOverrideBinding(owner, true, key, BINDING)
        ns:Debug("touche", key, "->", BINDING)
    end
    updateHint()
    ensureSoftTarget()
end

-- Appelé par Dialog.lua : true quand un dialogue PNJ est ouvert
function Interact:SetDialogMode(on)
    on = on and true or false
    if on == dialogMode then return end
    dialogMode = on
    self:Apply()
end

function Interact:CurrentAction()
    if not ns.db.key then return nil end
    return GetBindingAction(ns.db.key, true)
end

---------------------------------------------------------------------------
-- Objets de quête
local function createQuestButton()
    if quest.button or InCombatLockdown() then return end
    local b = CreateFrame("Button", QUEST_BUTTON, UIParent, "SecureActionButtonTemplate")
    b:SetAttribute("type", "item")
    b:SetAttribute("useOnKeyDown", true)
    b:RegisterForClicks("AnyDown")
    quest.button = b
end

-- quêtes du journal qui ont un objet à utiliser (relu quand le journal change)
local function scanQuests()
    local list = quest.list
    for i = #list, 1, -1 do list[i] = nil end
    local log, getItem = api("C_QuestLog"), api("GetQuestLogSpecialItemInfo")
    if type(log) ~= "table" or type(log.GetNumQuestLogEntries) ~= "function" or type(log.GetInfo) ~= "function"
        or type(getItem) ~= "function" then
        return
    end
    local okN, n = pcall(log.GetNumQuestLogEntries)
    for index = 1, (okN and tonumber(n)) or 0 do
        local okI, info = pcall(log.GetInfo, index)
        if okI and type(info) == "table" and not info.isHeader and not info.isHidden then
            local okS, link, icon, _, showWhenComplete = pcall(getItem, index)
            if okS and type(link) == "string" then
                local complete = false
                if type(log.IsComplete) == "function" and info.questID then
                    local okC, c = pcall(log.IsComplete, info.questID)
                    complete = okC and c and true or false
                end
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID and (not complete or showWhenComplete) then
                    list[#list + 1] = { index = index, questID = info.questID, itemID = itemID, link = link, icon = icon }
                end
            end
        end
    end
end

-- l'objet de quête utilisable ici, maintenant (portée = 1 seulement)
local function entryInRange()
    local inRange = api("IsQuestLogSpecialItemInRange")
    if type(inRange) ~= "function" then return nil end
    for _, e in ipairs(quest.list) do
        local ok, v = pcall(inRange, e.index)
        if ok and (v == 1 or v == true) then return e end
    end
    return nil
end

local function check()
    if InCombatLockdown() then return end
    local e = (ns.db.questItemKey and ns.db.interact and not dialogMode) and entryInRange() or nil
    local now, before = e and e.itemID, quest.active and quest.active.itemID
    if now == before then return end
    quest.active = e
    if e then
        createQuestButton()
        if quest.button then quest.button:SetAttribute("item", "item:" .. e.itemID) end
    end
    Interact:Apply()
end

local function syncTicker()
    local want = ns.db.questItemKey and ns.db.interact and #quest.list > 0
    if want and not quest.ticker then
        quest.ticker = C_Timer.NewTicker(RANGE_EVERY, check)
    elseif not want and quest.ticker then
        quest.ticker:Cancel()
        quest.ticker = nil
    end
    check()
end

local function refreshQuests()
    scanQuests()
    syncTicker()
end

-- quêtes avec objet (tests, débogage)
function Interact:QuestItems()
    return quest.list, quest.active, quest.bound
end

---------------------------------------------------------------------------
local scheduled = false
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- (le verrou du combat n'est pas encore posé : les liaisons peuvent encore changer)
        fighting = true
        Interact:Apply()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        fighting = false
        Interact:Apply()
        check()
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        check()
        return
    end
    if event == "QUEST_LOG_UPDATE" then
        -- rafales d'événements : une seule relecture
        if not scheduled then
            scheduled = true
            C_Timer.After(0.2, function()
                scheduled = false
                refreshQuests()
            end)
        end
        return
    end
    -- PLAYER_ENTERING_WORLD
    createQuestButton()
    refreshQuests()
    Interact:Apply()
end)

function Interact:Init()
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    pcall(frame.RegisterEvent, frame, "QUEST_LOG_UPDATE")
    pcall(frame.RegisterEvent, frame, "PLAYER_TARGET_CHANGED")
    for _, key in ipairs({ "key", "interact" }) do
        ns:OnChange(key, function()
            Interact:Apply()
            syncTicker()
        end)
    end
    ns:OnChange("questItemKey", function()
        syncTicker()
        Interact:Apply()
    end)
    ns:OnChange("questItemHint", updateHint)
    if IsLoggedIn and IsLoggedIn() then
        createQuestButton()
        refreshQuests()
    end
end
