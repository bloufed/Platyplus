-- Platyplus : quêtes
--  * récompenses au choix : lecture, conseil (Quests:BestChoice, la carte « Recommandée » de QuestCards.lua)
--    et choix quand le joueur clique une carte. Platyplus ne choisit jamais une récompense à ta place.
--  * argent de la quête dans le flux flottant (les objets reçus passent par Gains.lua)
-- Vérifié dans le code de Forever (QuestInfo.lua, QuestFrame.lua) : le choix est QuestInfoFrame.itemChoice, écrit
-- par QuestInfoItem_OnClick(bouton) pour un bouton de type "choice" ; le bouton Terminer le relit puis appelle
-- GetQuestReward(itemChoice). On clique donc la récompense avec la fonction de Blizzard, ce qui la surligne aussi.
local ADDON, ns = ...

local Quests = {}
ns.Quests = Quests

local MONEY_SLOT = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local function formatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. " po" end
    if silver > 0 then parts[#parts + 1] = silver .. " pa" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. " pc" end
    return table.concat(parts, " ")
end

-- prix de vente d'une pile (0 si l'objet n'est pas encore en cache)
local function sellPrice(link, count)
    if not (link and C_Item and C_Item.GetItemInfo) then return 0 end
    local price = select(11, C_Item.GetItemInfo(link))
    return (tonumber(price) or 0) * (tonumber(count) or 1)
end

local function readChoices(n)
    local list = {}
    for i = 1, n do
        local name, texture, numItems, quality, isUsable = GetQuestItemInfo("choice", i)
        list[#list + 1] = {
            index = i, name = name, icon = texture, count = numItems or 1, quality = quality,
            usable = isUsable, link = GetQuestItemLink("choice", i),
        }
    end
    return list
end

-- Les récompenses au choix de la quête affichée (liste vide s'il n'y en a pas) ; sert aussi aux cartes (QuestCards.lua)
function Quests:ReadChoices()
    return readChoices(GetNumQuestChoices() or 0)
end

Quests.SellPrice = sellPrice

-- Conseil : d'abord l'objet qui améliore le plus ton équipement, sinon le plus cher à la vente.
-- Renvoie le choix, l'amélioration (niveaux d'objet, 0 si aucune) et son prix. Ne choisit rien dans le jeu.
function Quests:BestChoice()
    local n = GetNumQuestChoices() or 0
    if n < 1 then return nil end
    local best, bestUpgrade, bestPrice
    for _, choice in ipairs(readChoices(n)) do
        local upgrade = 0
        if choice.usable ~= false and ns.Junk and ns.Junk.UpgradeDelta then
            local delta = ns.Junk:UpgradeDelta(choice.link)
            if delta and delta >= 1 then upgrade = delta end
        end
        local price = sellPrice(choice.link, choice.count)
        if not best or upgrade > bestUpgrade or (upgrade == bestUpgrade and price > bestPrice) then
            best, bestUpgrade, bestPrice = choice, upgrade, price
        end
    end
    return best, bestUpgrade or 0, bestPrice or 0
end

local function findChoiceButton(index)
    local buttons = QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons
    if not buttons then return nil end
    for _, button in ipairs(buttons) do
        if button.type == "choice" and button:GetID() == index and button:IsShown() then return button end
    end
    return nil
end

-- Bouton de la fenêtre Blizzard qui montre la récompense au choix n° index (nil s'il n'est pas affiché)
function Quests:ChoiceButton(index)
    return findChoiceButton(index)
end

-- Choisit la récompense n° index comme un clic du joueur dans la fenêtre Blizzard (qui la surligne aussi)
function Quests:Select(index)
    if not (QuestInfoFrame and index) then return false end
    local button = findChoiceButton(index)
    if button and type(QuestInfoItem_OnClick) == "function" then
        QuestInfoItem_OnClick(button)            -- surligne la récompense et pose QuestInfoFrame.itemChoice
    else
        QuestInfoFrame.itemChoice = index        -- repli : le bouton Terminer lira cette valeur
    end
    return true
end

-- Récompense choisie en ce moment (0 = aucune)
function Quests:Chosen()
    return (QuestInfoFrame and tonumber(QuestInfoFrame.itemChoice)) or 0
end

-- La quête attend-elle que le joueur choisisse sa récompense ? (plusieurs objets au choix et aucun cliqué ;
-- avec un seul objet, Blizzard le prend tout seul)
function Quests:NeedsChoice()
    return (GetNumQuestChoices() or 0) > 1 and self:Chosen() == 0
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, _, _, money)
    if event ~= "QUEST_TURNED_IN" then return end
    if ns.Gains and ns.Gains.NoteTurnIn then ns.Gains:NoteTurnIn() end
    -- QUEST_TURNED_IN (questID, xpReward, moneyReward)
    if ns.db.gainFeed and ns.Float and tonumber(money) and money > 0 then
        ns.Float:Add({ icon = COIN_ICON, name = ns.Tf("Quête : %s", formatMoney(money)), money = money, source = "quest",
            qty = 0, quality = 0, type = MONEY_SLOT })
    end
end)

function Quests:Init()
    frame:RegisterEvent("QUEST_TURNED_IN")
end
