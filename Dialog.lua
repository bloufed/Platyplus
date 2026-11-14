-- Platyplus : la touche fait avancer les dialogues PNJ
-- Tant qu'un dialogue (gossip ou quête) est ouvert, la touche est liée au bouton "PlatyplusAdvance"
-- (voir Interact.lua). Chaque appui fait UNE étape, dans cet ordre :
--   quête terminée à rendre > quête à accepter > première option de dialogue (formation, marchand...)
-- Dans les fenêtres de quête on clique les vrais boutons Blizzard (Accepter / Continuer / Terminer),
-- donc leurs confirmations et vérifications (choix de récompense, quête JcJ, coût en or) restent actives.
-- Mode « quêtes automatiques » (autoQuest) : les mêmes étapes, mais seulement pour les quêtes, lancées toutes
-- seules à l'ouverture du dialogue ; maintenir Maj met en pause.
-- Touches numérotées : pendant un dialogue, les touches 1 à 9 sont liées aux boutons "PlatyplusChoice1..9"
-- (voir Interact.lua). La fenêtre de quête (QuestWindow.lua) écrit la touche sur chaque choix : la touche
-- d'interaction (F) sur celui que la touche prendrait, 1, 2, 3... sur les autres, et donne à Dialog:SetChoices
-- l'action de chaque numéro.
local ADDON, ns = ...

local Dialog = {}
ns.Dialog = Dialog

local OPTION_AVAILABLE = (Enum and Enum.GossipOptionStatus and Enum.GossipOptionStatus.Available) or 0
local AUTO_DELAY = 0.1      -- laisse Blizzard finir d'afficher la fenêtre avant d'agir

local function isShown(frame)
    return frame ~= nil and frame:IsShown()
end

local function dialogOpen()
    return isShown(QuestFrame) or isShown(GossipFrame)
end

local function clickButton(button)
    if button and button:IsShown() and button:IsEnabled() then
        button:Click()
        return true
    end
    return false
end

-- PNJ "à l'ancienne" : liste de quêtes sans fenêtre de dialogue
local function advanceGreeting()
    local numActive = GetNumActiveQuests()
    for i = 1, numActive do
        local _, isComplete = GetActiveTitle(i)
        if isComplete then
            SelectActiveQuest(i)
            return true
        end
    end
    if GetNumAvailableQuests() > 0 then
        SelectAvailableQuest(1)
        return true
    end
    return false
end

-- auto = true : déclenché tout seul (pas de message répétitif, pas de clic qui provoquerait une erreur)
local function advanceQuest(auto)
    if isShown(QuestFrameDetailPanel) then
        return clickButton(QuestFrameAcceptButton)
    elseif isShown(QuestFrameProgressPanel) then
        if clickButton(QuestFrameCompleteButton) then return true end
        if not auto then
            ns:Print("quête pas encore terminable : il te manque des objets ou des objectifs")
        end
        return true
    elseif isShown(QuestFrameRewardPanel) then
        -- plusieurs récompenses au choix : c'est toujours le joueur qui choisit (cartes ou fenêtre Blizzard)
        if ns.Quests and ns.Quests.NeedsChoice and ns.Quests:NeedsChoice() then
            if auto then return false end    -- quêtes automatiques : on attend le choix du joueur
            ns:Print("choisis d'abord ta récompense, puis appuie à nouveau")
            return true
        end
        return clickButton(QuestFrameCompleteQuestButton)
    elseif isShown(QuestFrameGreetingPanel) then
        return advanceGreeting()
    end
    return false
end

local function advanceGossip(questsOnly)
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
        if quest.isComplete then
            C_GossipInfo.SelectActiveQuest(quest.questID)
            return true
        end
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if not quest.isIgnored then
            C_GossipInfo.SelectAvailableQuest(quest.questID)
            return true
        end
    end
    if ns.db.gossipOptions and not questsOnly then
        for _, option in ipairs(C_GossipInfo.GetOptions() or {}) do
            if option.status == OPTION_AVAILABLE then
                -- même appel que le clic Blizzard sur une option
                C_GossipInfo.SelectOptionByIndex(option.orderIndex)
                return true
            end
        end
    end
    return false
end

-- auto = true : appel du mode « quêtes automatiques » (quêtes seulement, jamais d'option de dialogue)
function Dialog:Advance(auto)
    if not ns.db.dialog and not auto then return end
    local handled = false
    if isShown(QuestFrame) then
        handled = advanceQuest(auto)
    elseif isShown(GossipFrame) then
        handled = advanceGossip(auto)
    end
    ns:Debug(auto and "quête automatique :" or "touche dans un dialogue :", handled and "action faite" or "rien à faire")
    if not isShown(QuestFrame) and not isShown(GossipFrame) then
        self:Refresh()
    end
    return handled
end

---------------------------------------------------------------------------
-- Touches affichées dans la fenêtre de quête
local NUM_KEYS = 9
Dialog.NUM_KEYS = NUM_KEYS
Dialog.choices = {}        -- [n] = action de la touche n, posées par la fenêtre de quête

-- la touche d'interaction, si elle fait avancer les dialogues ; nil sinon
function Dialog:KeyLabel()
    if not (ns.db.dialog and ns.db.interact) then return nil end
    local key = ns.db.key
    if type(key) ~= "string" or key == "" then return nil end
    return key
end

-- Même règle qu'Advance : parmi des choix { kind = "complete" | "available" | "active" | "option" | "locked" },
-- l'indice de celui que la touche prendrait, ou nil si elle ne ferait rien
function Dialog:DefaultChoice(choices)
    if not self:KeyLabel() then return nil end
    for i, c in ipairs(choices) do if c.kind == "complete" then return i end end
    for i, c in ipairs(choices) do if c.kind == "available" then return i end end
    if ns.db.gossipOptions then
        for i, c in ipairs(choices) do if c.kind == "option" then return i end end
    end
    return nil
end

-- list[n] = function : ce que fait la touche n ; nil = plus rien de numéroté
function Dialog:SetChoices(list)
    self.choices = list or {}
end

function Dialog:Choose(n)
    local action = self.choices[n]
    if not action or not dialogOpen() then return false end
    ns:Debug("touche", n, "dans un dialogue")
    local ok, err = pcall(action)
    if not ok then ns:Debug("choix", n, ":", err) end
    return ok
end

for i = 1, NUM_KEYS do
    local b = CreateFrame("Button", "PlatyplusChoice" .. i, UIParent)
    b:RegisterForClicks("AnyDown")
    b:SetScript("OnClick", function() Dialog:Choose(i) end)
end

---------------------------------------------------------------------------
-- Remet la touche en mode "interagir" ou "avancer le dialogue" selon ce qui est affiché
function Dialog:Refresh()
    ns.Interact:SetDialogMode(ns.db.dialog and dialogOpen())
end

local button = CreateFrame("Button", "PlatyplusAdvance", UIParent)
button:RegisterForClicks("AnyDown")
button:SetScript("OnClick", function()
    Dialog:Advance()
end)

local AUTO_EVENTS = {
    GOSSIP_SHOW = true, QUEST_GREETING = true, QUEST_DETAIL = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
    -- on attend l'image suivante : les fenêtres Blizzard sont alors dans leur état final
    C_Timer.After(0, function() Dialog:Refresh() end)
    if ns.db.autoQuest and AUTO_EVENTS[event] and not IsShiftKeyDown() then
        C_Timer.After(AUTO_DELAY, function()
            if not IsShiftKeyDown() then Dialog:Advance(true) end
        end)
    end
end)

function Dialog:Init()
    for _, event in ipairs({
        "GOSSIP_SHOW", "GOSSIP_CLOSED",
        "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
    }) do
        frame:RegisterEvent(event)
    end
    ns:OnChange("dialog", function() Dialog:Refresh() end)
end
