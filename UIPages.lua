-- Platyplus : contenu des onglets de la fenêtre d'options (ns.Pages)
-- Une page = une pile de cartes (voir UIWidgets.lua), construite à la première visite de l'onglet.
-- Les appels vers les autres modules (Junk, Float, Misc, Interact, ResourceBar, Launcher, GameSettings)
-- sont toujours gardés : ils sont écrits en parallèle et peuvent manquer.
local ADDON, ns = ...

local Pages = {}
ns.Pages = Pages

local W = ns.W
local floor, max = math.floor, math.max

---------------------------------------------------------------------------
-- Petits outils
---------------------------------------------------------------------------
local function db(key)
    return ns.db and ns.db[key]
end

-- Conditions d'activation des sous-options
local function whenInteract() return db("interact") end
local function whenDialog() return db("interact") and db("dialog") end
local function whenFloat() return db("floatLoot") end
local function whenSellGear() return db("sellGear") end
local function whenAuction() return db("ahAssist") end
local function whenRepair() return db("autoRepair") end
local function whenBagWarn() return db("bagWarn") end
local function whenZoom() return db("cameraZoom") end
local function whenLauncher() return db("launcher") end
local function whenDock() return db("launcher") and db("dock") end
local function whenSparklesNear()
    return db("sparkleHerbs") or db("sparkleQuestObjects") or db("sparkleCorpses")
end

-- Valeurs affichées dans les pastilles des curseurs
local function percent(v)
    return floor(v * 100 + 0.5) .. " %"
end

local function seconds(v)
    if v == floor(v) then return ns.Tf("%d s", v) end
    return (ns.Tf("%.1f s", v):gsub("%.", ","))
end

local function pixels(v)
    return floor(v + 0.5) .. " px"
end

-- Texte « Action actuelle » (action lue dans le jeu, avec nom lisible)
local function boundActionText()
    if not db("interact") then
        return "|cff999999" .. ns.T("aucune (interaction rapide coupée)") .. "|r"
    end
    local action
    if ns.Interact and ns.Interact.CurrentAction then
        local ok, res = pcall(ns.Interact.CurrentAction, ns.Interact)
        if ok then action = res end
    end
    if not action or action == "" then
        return W.Color("gold", ns.T("rien pour l'instant")) .. " |cff888888" .. ns.T("(en combat : après le combat)") .. "|r"
    end
    if action:find("^CLICK PlatyplusAdvance") then
        return W.Color("accent", ns.T("Avancer le dialogue du PNJ"))
    end
    if action:find("^CLICK PlatyplusQuestItem") then
        return W.Color("gold", ns.T("Utiliser l'objet de quête")) .. " |cff888888" .. ns.T("(Maj + touche : interagir)") .. "|r"
    end
    local name = _G["BINDING_NAME_" .. action]
    if name and name ~= action then
        return W.Color("accent", name)
    end
    return W.Color("accent", action)
end

-- Lecture / écriture d'un CVar du jeu (protégées)
local function cvarNumber(name)
    local ok, v = pcall(GetCVar, name)
    if ok and v ~= nil then return tonumber(v) end
    return nil
end

local function setCvar(name, value)
    pcall(SetCVar, name, tostring(value))
end

-- Appelle module:method() si le module (écrit en parallèle) l'expose ; sinon message
local function call(moduleName, method, missing)
    local m = ns[moduleName]
    if m and m[method] then
        local ok, err = pcall(m[method], m)
        if not ok then geterrorhandler()(err) end
        return true
    end
    if missing then ns:Print(missing) end
    return false
end

---------------------------------------------------------------------------
-- 1. Général
---------------------------------------------------------------------------
local function buildGeneral(p)
    local c = p:Card("Ta touche", "Une seule touche pour tout : PNJ, coffres, plantes, cadavres à dépouiller, "
        .. "dialogues et quêtes.")
    c:Key({
        key = "key",
        label = "Touche d'interaction",
    })
    c:Info({
        label = "Action actuelle",
        text = boundActionText,
        tip = "Ce que le jeu fait réellement quand tu appuies sur ta touche, en ce moment. "
            .. "Hors dialogue c'est l'interaction rapide ; pendant un dialogue de PNJ c'est l'avance du dialogue.",
    })

    c = p:Card("Ce que fait la touche")
    c:Switch({
        key = "interact",
        label = "Interaction rapide",
        desc = "Interagit avec ce que tu survoles, sinon avec la cible la plus proche.",
        tip = "La touche choisie interagit d'abord avec ce que la souris survole, sinon avec la cible d'interaction "
            .. "la plus proche : PNJ, coffre, plante, cadavre à dépouiller. Coupée, Platyplus ne lie plus aucune touche.",
    })
    c:Switch({
        key = "dialog",
        label = "Valider les quêtes et les dialogues",
        indent = 1,
        enabled = whenInteract,
        requires = "Nécessite « Interaction rapide ».",
        tip = "Quand une fenêtre de PNJ est ouverte, la même touche accepte la quête, la rend ou fait avancer le dialogue, "
            .. "une étape à chaque appui. Les confirmations de Blizzard (choix de récompense, coût...) restent actives.",
    })
    c:Switch({
        key = "gossipOptions",
        label = "Choisir aussi la 1re option de dialogue",
        indent = 2,
        enabled = whenDialog,
        requires = "Nécessite « Valider les quêtes et les dialogues ».",
        tip = "Quand il n'y a plus de quête à accepter ni à rendre, la touche choisit la première option disponible "
            .. "du PNJ (formation, marchand, maître de vol...). Coupe-le si tu préfères choisir toi-même.",
    })
    c:Switch({
        key = "questItemKey",
        label = "Utiliser l'objet de quête au bon endroit",
        desc = "Maj + touche pour interagir quand même.",
        indent = 1,
        enabled = whenInteract,
        requires = "Nécessite « Interaction rapide ».",
        tip = "Quand une quête de ton journal a un objet à utiliser (torche, fiole...) et que tu es là où il faut "
            .. "l'utiliser, la touche utilise cet objet. Maj + touche interagit "
            .. "quand même (pour parler à un PNJ à côté). En combat, la touche loote ou interagit (jamais le mob "
            .. "vivant sous la souris) et l'objet passe sur Maj + touche.",
    })
    c:Switch({
        key = "questItemHint",
        label = "Bandeau à l'écran",
        desc = "« F : [objet]   Maj+F : interagir » quand la touche utilise l'objet.",
        indent = 2,
        enabled = function() return whenInteract() and db("questItemKey") end,
        requires = "Nécessite « Utiliser l'objet de quête au bon endroit ».",
        tip = "Un bandeau au milieu de l'écran te signale que la touche utilisera l'objet de quête. Éteint, la touche "
            .. "marche pareil, sans rien afficher.",
    })

    local function choice(roleId)
        return function()
            if ns.Eat and ns.Eat.ChoiceText then
                local ok, res = pcall(ns.Eat.ChoiceText, ns.Eat, roleId)
                if ok and res then return res end
            end
            return "|cff999999indisponible|r"
        end
    end
    c = p:Card("Manger et boire", "Deux touches qui prennent le meilleur de tes sacs : à manger ou à boire hors combat, "
        .. "une potion en combat.")
    c:Key({
        key = "eatKey",
        label = "Touche pour manger",
        tip = "Hors combat : mange la nourriture la plus haute que tu peux utiliser. En combat : boit ta meilleure potion "
            .. "de soins. « La plus haute » = niveau requis, puis niveau de l'objet. Remettre « aucune » coupe la touche.",
    })
    c:Info({
        label = "Hors combat",
        text = choice("eat"),
        tip = "Nourriture choisie hors combat, puis la potion de soins prise en combat. Mis à jour quand tes sacs changent.",
    })
    c:Key({
        key = "drinkKey",
        label = "Touche pour boire",
        tip = "Hors combat : boit la boisson la plus haute (eau, jus...) pour la mana. En combat : boit ta meilleure potion "
            .. "de mana. Remettre « aucune » coupe la touche.",
    })
    c:Info({
        label = "Hors combat",
        text = choice("drink"),
        tip = "Boisson choisie hors combat, puis la potion de mana prise en combat. Mis à jour quand tes sacs changent.",
    })

    c = p:Card("Quêtes", "Quand une quête propose plusieurs objets, c'est toujours toi qui choisis : Platyplus ne prend jamais une récompense à ta place.")
    c:Switch({
        key = "questCards",
        label = "Récompenses en grandes cartes",
        desc = "Les objets au choix s'affichent au milieu de l'écran, colorés selon leur rareté.",
        tip = "Quand une quête propose plusieurs objets, chacun devient une grande carte : rareté, niveau d'objet, "
            .. "caractéristiques, prix de vente et comparaison avec ton équipement. La carte « Recommandée » est un conseil "
            .. "(la pièce qui améliore le plus ton équipement, sinon la plus chère à la vente) : rien n'est choisi tant que "
            .. "tu n'as pas cliqué. Clic pour choisir, double-clic (ou ta touche) pour rendre la quête. "
            .. "Maintiens Maj en ouvrant la fenêtre pour garder la fenêtre classique.",
    })
    c:Buttons({
        {
            text = "Voir un aperçu", width = 150,
            enabled = function() return ns.db.questCards end,
            requires = "Nécessite « Récompenses en grandes cartes ».",
            tip = "Affiche les cartes avec des objets d'exemple (ou tape /pp cartes). Rien n'est envoyé au jeu.",
            onClick = function() call("QuestCards", "Demo", "cartes indisponibles") end,
        },
    })
    c:Switch({
        key = "autoQuest",
        label = "Accepter et rendre les quêtes automatiquement",
        desc = "Sans appuyer sur rien. Maintiens Maj en parlant au PNJ pour faire une pause.",
        tip = "Dès qu'un dialogue de quête s'ouvre, Platyplus accepte la quête ou la rend tout seul, sans touche. "
            .. "Si elle propose plusieurs récompenses, il attend que tu en choisisses une. "
            .. "Maintiens Maj en ouvrant le dialogue pour lire tranquillement.",
    })

    -- CVar du jeu : affiché seulement s'il existe sur ce client
    if cvarNumber("SoftTargetInteractRange") ~= nil then
        c = p:Card("Avancé", "Réglage du jeu (et non de Platyplus) : il est conservé par le jeu.")
        c:Slider({
            label = "Portée d'interaction",
            min = 5, max = 40, step = 1,
            format = "%d m",
            get = function() return cvarNumber("SoftTargetInteractRange") end,
            set = function(v) setCvar("SoftTargetInteractRange", v) end,
            enabled = function() return not whenSparklesNear() end,
            requires = "Les étincelles (onglet Butin) règlent cette portée : coupe-les pour la changer ici.",
            tip = "Distance maximale, en mètres, de la cible d'interaction automatique (réglage du jeu "
                .. "« SoftTargetInteractRange »). Une valeur trop grande peut te faire cibler des objets lointains. Expérimental.",
        })
    end
end

---------------------------------------------------------------------------
-- 2. Butin
---------------------------------------------------------------------------
local function buildLoot(p)
    local c = p:Card("Ramassage")
    c:Switch({
        key = "instantLoot",
        label = "Loot instantané",
        desc = "Tout est ramassé dès l'ouverture, sans fenêtre de butin.",
        tip = "Ramasse tout le contenu d'un cadavre ou d'un coffre dès son ouverture, sans fenêtre de loot. "
            .. "Maintiens la touche de loot manuel du jeu (Maj par défaut) pour afficher la fenêtre normale.",
    })
    c:Switch({
        key = "confirmBind",
        label = "Confirmer seul les objets « lié quand ramassé »",
        tip = "Valide automatiquement la fenêtre de confirmation de Blizzard quand tu ramasses un objet "
            .. "qui se lie à toi. Tu ne verras plus cette question.",
    })

    local how = " Utilise le ciblage d'interaction du jeu : l'objet le plus proche, jusqu'à environ 15 m, tout autour de toi. "
        .. "Pour cela Platyplus allume « Activer la touche d'interaction » et les icônes d'interaction des objets du monde "
        .. "du jeu, et les remet comme avant quand tu coupes toutes les étincelles ci-dessous. Pas d'étincelle pendant un combat."
    c = p:Card("Étincelles", "Rien ne t'échappe : ce que tu peux ramasser brille quand tu t'en approches.")
    c:Switch({
        key = "sparkleLoot",
        label = "Étincelle des objets de quête",
        desc = "Garde l'étincelle de butin du jeu allumée.",
        tip = "Le jeu fait briller les objets de quête à ramasser (une caisse, une torche par terre...), mais un préréglage "
            .. "graphique coupe cette étincelle. Platyplus la remet à la connexion et juste après chaque changement "
            .. "graphique. Ton mode de contour (outline) n'est pas touché. Couper cette option ne prend effet qu'après "
            .. "un redémarrage du jeu : /reload ne suffit pas.",
    })
    c:Switch({
        key = "sparkleHerbs",
        label = "Plantes",
        desc = "De petits éclats dorés sur la plante la plus proche.",
        tip = "Une plante à cueillir scintille quand tu t'en approches, terne de loin, vive à portée, "
            .. "grise si ta compétence est trop basse. Un seul objet brille à la fois." .. how,
    })
    c:Switch({
        key = "sparkleQuestObjects",
        label = "Objets de quête du monde",
        desc = "Aussi sur les objets de quête par terre (coupé par défaut).",
        tip = "Le jeu marque déjà la plupart des objets de quête avec son étincelle de butin. Ceci en ajoute une autre sur "
            .. "ceux que ton journal demande encore, d'après le nom de l'objectif (« Caisse de provisions »...). "
            .. "Coupé par défaut." .. how,
    })
    c:Switch({
        key = "sparkleCorpses",
        label = "Cadavres avec du butin",
        desc = "Un cadavre qui a encore du butin pour toi brille à l'approche.",
        tip = "L'étincelle du jeu oublie certains cadavres, les boss notamment. Une fois le combat fini, un cadavre qui a "
            .. "encore du butin pour toi brille quand tu t'en approches. Elle dit seulement « il reste du butin », pas "
            .. "quoi. Le jeu pose alors sa plaque de nom (nom et barre de vie) sur ce cadavre : c'est elle qui porte "
            .. "l'étincelle." .. how,
    })
    c:Help("Un souci ? Tape /pp etincelles : il montre ce que Platyplus voit autour de toi.")

    c = p:Card("Flux à l'écran", "Ce que tu ramasses, fabriques, achètes ou vends s'affiche près de ton personnage, "
        .. "les objets identiques se cumulent, puis tout s'estompe.")
    c:Switch({
        key = "floatLoot",
        label = "Afficher le flux",
        tip = "Affiche à l'écran les objets et l'argent que tu ramasses : les lignes s'empilent, "
            .. "les mêmes objets se cumulent, puis tout s'estompe tout seul.",
    })
    c:Switch({
        key = "gainFeed",
        label = "Objets fabriqués, achetés ou reçus",
        indent = 1,
        enabled = whenFloat,
        requires = "Nécessite « Afficher le flux ».",
        tip = "Affiche aussi les objets qui arrivent dans tes sacs autrement qu'en les ramassant : "
            .. "fabrication, achat chez un marchand, courrier, récompense de quête, échange. "
            .. "Chaque ligne porte sa source (Fabriqué, Acheté, Quête...).",
    })
    c:Switch({
        key = "sellFeed",
        label = "Objets vendus et leur prix",
        indent = 1,
        enabled = whenFloat,
        requires = "Nécessite « Afficher le flux ».",
        tip = "Chaque objet vendu apparaît dans le flux avec son prix, puis le total encaissé.",
    })
    c:Slider({
        key = "rows",
        label = "Lignes au maximum",
        min = 1, max = 12, step = 1,
        format = "%d",
        indent = 1,
        enabled = whenFloat,
        requires = "Nécessite « Afficher le flux ».",
        tip = "Combien de lignes le flux peut afficher en même temps. Les plus anciennes disparaissent en premier.",
    })
    c:Slider({
        key = "duration",
        label = "Durée d'affichage",
        min = 1, max = 15, step = 0.5,
        format = seconds,
        indent = 1,
        enabled = whenFloat,
        requires = "Nécessite « Afficher le flux ».",
        tip = "Temps pendant lequel une ligne reste affichée avant de s'estomper.",
    })
    c:Slider({
        key = "floatScale",
        label = "Taille",
        min = 0.6, max = 2, step = 0.05,
        format = percent,
        indent = 1,
        enabled = whenFloat,
        requires = "Nécessite « Afficher le flux ».",
        tip = "Agrandit ou réduit tout le flux (100 % = taille normale).",
    })
    c:Dropdown({
        key = "feedGrow",
        label = "Sens d'empilement",
        indent = 1,
        enabled = whenFloat,
        requires = "Nécessite « Afficher le flux ».",
        options = {
            { value = "UP", text = "Vers le haut" },
            { value = "DOWN", text = "Vers le bas" },
        },
        tip = "Vers le haut : chaque nouvelle ligne pousse les anciennes vers le haut. Vers le bas : l'inverse.",
    })
    c:Buttons({
        {
            text = "Déplacer", width = 120,
            enabled = whenFloat,
            requires = "Nécessite « Afficher le flux ».",
            tip = "Affiche une poignée : glisse le flux où tu veux, puis reclique ici (ou tape /pp move) pour valider.",
            onClick = function() call("Float", "ToggleMove", "flux indisponible") end,
        },
        {
            text = "Tester", width = 110, primary = true,
            enabled = whenFloat,
            requires = "Nécessite « Afficher le flux ».",
            tip = "Fait apparaître quelques lignes d'exemple pour voir le résultat.",
            onClick = function() call("Float", "Test", "flux indisponible") end,
        },
        {
            text = "Remettre en place", width = 160,
            tip = "Replace le flux à son emplacement par défaut.",
            onClick = function()
                for _, key in ipairs({ "point", "relPoint", "x", "y" }) do ns:Reset(key) end
                call("Float", "ApplyPosition")
            end,
        },
    })

    c = p:Card("Jets de dés en groupe", "En donjon ou en raid, une fenêtre suit chaque objet mis aux dés : "
        .. "le choix de chaque joueur (Besoin, Cupidité, Passe), son dé, sa classe, qui mène et qui gagne.")
    c:Switch({
        key = "lootRolls", label = "Suivre les jets de butin",
        desc = "Objet par objet, boss par boss. /pp jets ouvre la fenêtre.",
        tip = "Lit l'historique de butin du jeu : rien n'est envoyé aux autres joueurs.",
    })
    c:Switch({
        key = "lootRollsManual", label = "Suivre aussi les /roll", indent = 1,
        enabled = function() return db("lootRolls") end, requires = "Nécessite « Suivre les jets de butin ».",
        desc = "Les dés lancés à la main, rangés du plus haut au plus bas, avec l'objet lié juste avant dans le chat.",
        tip = "Un 2e /roll du même joueur pour le même objet est signalé et ne compte pas. "
            .. "Une égalité au plus haut dé est signalée.",
    })
    c:Switch({
        key = "lootRollsAuto", label = "Ouvrir toute seule", indent = 1,
        enabled = function() return db("lootRolls") end, requires = "Nécessite « Suivre les jets de butin ».",
        desc = "Dès qu'un objet est mis aux dés dans ton groupe.",
    })
    c:Switch({
        key = "lootRollsAutoClose", label = "Refermer après les jets", indent = 1,
        enabled = function() return db("lootRolls") and db("lootRollsAuto") end,
        requires = "Nécessite « Ouvrir toute seule ».",
        desc = "20 secondes après le dernier dé, si elle s'est ouverte toute seule.",
    })
    c:Slider({
        key = "lootRollsScale", label = "Taille de la fenêtre", min = 0.7, max = 1.5, step = 0.05,
        format = function(v) return math.floor(v * 100 + 0.5) .. " %" end,
    })
    c:Buttons({
        { text = "Ouvrir", width = 110, onClick = function() call("LootRolls", "Toggle", "suivi des jets indisponible") end },
        {
            text = "Exemple", width = 110, primary = true,
            tip = "Montre la fenêtre avec des jets inventés, pour voir à quoi elle ressemble.",
            onClick = function() call("LootRolls", "Demo", "suivi des jets indisponible") end,
        },
        {
            text = "Remettre en place", width = 160,
            onClick = function()
                ns:Reset("lootRollsPos")
                local f = rawget(_G, "PlatyplusLootRolls")
                if f and ns.Win then ns.Win.Place(f) end
            end,
        },
    })
end

---------------------------------------------------------------------------
-- 3. Vente
---------------------------------------------------------------------------
local SELL_KEYS = {
    sellJunk = true, sellGear = true, gearMaxQuality = true, gearMargin = true,
    gearIncludeBoE = true, keepUnknownTransmog = true, gearMaxPerVisit = true,
    neverSell = true, alwaysSell = true,
}

local function buildSell(p)
    p:Note("Maintiens Maj en ouvrant un marchand pour ne rien vendre cette fois-là. "
        .. "Le rachat du marchand garde les 12 derniers objets vendus.")

    local c = p:Card("Vente automatique", "À l'ouverture d'un marchand, Platyplus vend ce que tu as choisi ici.")
    c:Switch({
        key = "sellJunk",
        label = "Vendre les objets gris",
        tip = "Vend tous les objets de qualité médiocre (gris) de tes sacs dès que tu ouvres un marchand.",
    })
    c:Switch({
        key = "sellGear",
        label = "Vendre l'équipement inutile",
        desc = "Les pièces nettement moins bonnes que ce que tu portes.",
        tip = "Vend aussi les pièces d'équipement nettement moins bonnes que ce que tu portes déjà, "
            .. "selon les réglages ci-dessous. Les objets de « Ne jamais vendre » sont toujours épargnés. "
            .. "Vérifie d'abord avec l'aperçu en bas de page.",
    })
    c:Dropdown({
        key = "gearMaxQuality",
        label = "Qualité maximale vendue",
        indent = 1,
        width = 170,
        enabled = whenSellGear,
        requires = "Nécessite « Vendre l'équipement inutile ».",
        options = {
            { value = 0, text = W.Quality(0, "Médiocre") },
            { value = 1, text = W.Quality(1, "Commun") },
            { value = 2, text = W.Quality(2, "Inhabituel") },
            { value = 3, text = W.Quality(3, "Rare") },
            { value = 4, text = W.Quality(4, "Épique") },
        },
        tip = "Aucune pièce d'équipement de qualité supérieure à celle-ci n'est vendue. "
            .. "Évite de monter jusqu'à Rare ou Épique si tu veux garder une marge de sécurité.",
    })
    c:Slider({
        key = "gearMargin",
        label = "Écart de niveau d'objet",
        min = 1, max = 30, step = 1,
        format = "%d",
        indent = 1,
        enabled = whenSellGear,
        requires = "Nécessite « Vendre l'équipement inutile ».",
        tip = "Une pièce n'est vendue que si son niveau d'objet est inférieur d'au moins ce nombre de points "
            .. "à celui de la pièce équivalente que tu portes.",
    })
    c:Switch({
        key = "gearIncludeBoE",
        label = "Inclure les objets « lié quand équipé »",
        indent = 1,
        enabled = whenSellGear,
        requires = "Nécessite « Vendre l'équipement inutile ».",
        tip = "Vend aussi les pièces « lié quand équipé » qui ne sont pas encore liées à toi. "
            .. "Elles peuvent parfois se vendre plus cher à l'hôtel des ventes, donc c'est coupé par défaut.",
    })
    c:Switch({
        key = "keepUnknownTransmog",
        label = "Garder les apparences que je n'ai pas",
        indent = 1,
        enabled = whenSellGear,
        requires = "Nécessite « Vendre l'équipement inutile ».",
        tip = "Ne vend pas une pièce dont l'apparence n'est pas encore dans ta collection.",
    })
    c:Slider({
        key = "gearMaxPerVisit",
        label = "Pièces vendues par visite",
        min = 1, max = 50, step = 1,
        format = "%d",
        indent = 1,
        enabled = whenSellGear,
        requires = "Nécessite « Vendre l'équipement inutile ».",
        tip = "Limite le nombre de pièces d'équipement vendues à chaque visite. Le rachat de Blizzard ne garde que "
            .. "les 12 derniers objets vendus : au-delà de 12, tu ne pourrais plus tout racheter en cas d'erreur.",
    })

    c = p:Card("Ne jamais vendre", "Ces objets sont toujours épargnés, quelle que soit leur qualité.")
    c:ItemList({
        list = "neverSell",
        label = "Ne jamais vendre",
        tip = "Dépose ici un objet de tes sacs : il ne sera jamais vendu automatiquement.",
    })

    c = p:Card("Toujours vendre", "Ces objets sont vendus à chaque marchand, même s'ils ne sont pas gris.")
    c:ItemList({
        list = "alwaysSell",
        label = "Toujours vendre",
        tip = "Dépose ici un objet de tes sacs : il sera vendu à chaque visite chez un marchand.",
    })

    c = p:Card("Aperçu", "Ce qui serait vendu chez un marchand avec les réglages actuels. "
        .. "Mis à jour à l'ouverture de l'onglet et à chaque changement de réglage.")
    local preview = W.Preview(c, { keys = SELL_KEYS })
    c:Buttons({
        {
            text = "Actualiser l'aperçu", width = 170,
            tip = "Recalcule la liste à partir du contenu actuel de tes sacs.",
            onClick = function() preview:Update() end,
        },
        {
            text = "Vendre maintenant", width = 170, primary = true,
            tip = "Vend tout de suite ce qui est listé. Un marchand doit être ouvert.",
            onClick = function()
                if call("Junk", "SellNow", "module de vente indisponible") and C_Timer and C_Timer.After then
                    C_Timer.After(1.5, function() if preview:IsVisible() then preview:Update() end end)
                end
            end,
        },
    })
    c:Add(preview)

    -- Hôtel des ventes (Auction.lua)
    c = p:Card("Hôtel des ventes", "À l'ouverture de l'HDV, un panneau cherche le prix de tes objets. Tu coches ce que "
        .. "tu veux vendre (c'est retenu pour la prochaine fois), puis un clic ou une touche par mise en vente : "
        .. "Blizzard l'exige, aucun addon ne peut tout poster seul.")
    c:Switch({
        key = "ahAssist",
        label = "Assistant d'hôtel des ventes",
        desc = "Un panneau à droite de la fenêtre de l'HDV.",
        tip = "Liste les objets de tes sacs que l'HDV accepte, avec un prix pour chacun. Ne sont jamais proposés : objets "
            .. "liés, équipement blanc ou gris, outils de métier (pioche, couteau à dépecer, canne à pêche...), objets "
            .. "d'un ensemble d'équipement. Clic sur une ligne : cocher / décocher. Seuls les objets cochés sont mis en "
            .. "vente. Clic droit : ne plus jamais proposer cet objet.",
    })
    c:Switch({
        key = "ahAutoScan",
        label = "Chercher les prix dès l'ouverture",
        indent = 1,
        enabled = whenAuction,
        requires = "Nécessite « Assistant d'hôtel des ventes ».",
        tip = "Demande les prix dès que tu ouvres l'HDV : une seule recherche groupée pour tes marchandises (minerais, "
            .. "herbes, tissus...), puis une par pièce d'équipement. Tu peux mettre en vente pendant que la recherche "
            .. "continue. Coupé : clique « Rechercher à nouveau » dans le panneau.",
    })
    c:Key({
        key = "ahKey",
        label = "Touche de mise en vente",
        tip = "Pendant que l'HDV est ouvert, cette touche fait comme un clic sur « Mettre en vente » : une mise en vente "
            .. "par appui. Ailleurs, la touche garde son rôle habituel. « Aucune » : seulement le bouton "
            .. "(ou une macro « /click PlatyplusAHPost »).",
    })
    c:Slider({
        key = "ahUndercut",
        label = "Moins cher que les autres de",
        min = 0, max = 100, step = 1,
        format = "%d pc",
        indent = 1,
        enabled = whenAuction,
        requires = "Nécessite « Assistant d'hôtel des ventes ».",
        tip = "Ton prix = le moins cher des autres vendeurs, moins ce montant en pièces de cuivre (au moins 1 pc de moins, "
            .. "pour passer devant). Si le moins cher est déjà à toi, tu t'alignes dessus au lieu de te concurrencer.",
    })
    c:Switch({
        key = "ahVendorCheck",
        label = "Jamais moins que le marchand",
        desc = "Si le marchand t'en donne autant ou plus, l'objet n'est pas mis en vente.",
        indent = 1,
        enabled = whenAuction,
        requires = "Nécessite « Assistant d'hôtel des ventes ».",
        tip = "L'HDV garde 5 % de chaque vente. Exemple : minerai à 18 pc à l'HDV, il te reste 17 pc, contre 5 pc chez le "
            .. "marchand : il est mis en vente. À 5 pc à l'HDV, il ne te resterait que 4 pc : il est marqué "
            .. "« marchand mieux » et reste dans tes sacs.",
    })
    c:Slider({
        key = "ahNoCompetition",
        label = "Personne n'en vend (x prix marchand)",
        min = 1, max = 20, step = 0.5,
        format = function(v) return (string.format(v == floor(v) and "x%d" or "x%.1f", v):gsub("%.", ",")) end,
        indent = 1,
        enabled = whenAuction,
        requires = "Nécessite « Assistant d'hôtel des ventes ».",
        tip = "Quand personne ne vend l'objet : dernier prix vu à l'HDV ces 14 derniers jours, sinon le prix du marchand "
            .. "multiplié par ce nombre. Un objet sans prix marchand et jamais vu n'est pas proposé.",
    })
    c:Dropdown({
        key = "ahDuration",
        label = "Durée des ventes",
        indent = 1,
        width = 170,
        enabled = whenAuction,
        requires = "Nécessite « Assistant d'hôtel des ventes ».",
        options = {
            { value = 1, text = "12 heures" },
            { value = 2, text = "24 heures" },
            { value = 3, text = "48 heures" },
        },
        tip = "Plus c'est long, plus le dépôt demandé par l'HDV est élevé (il est rendu si l'objet se vend).",
    })
    c:Dropdown({
        key = "ahGearMinQuality",
        label = "Équipement proposé à partir de",
        indent = 1,
        width = 170,
        enabled = whenAuction,
        requires = "Nécessite « Assistant d'hôtel des ventes ».",
        options = {
            { value = 1, text = W.Quality(1, "Commun") },
            { value = 2, text = W.Quality(2, "Inhabituel") },
            { value = 3, text = W.Quality(3, "Rare") },
            { value = 4, text = W.Quality(4, "Épique") },
        },
        tip = "Les armes et armures de qualité inférieure ne sont pas proposées. Par défaut Inhabituel (vert) : "
            .. "l'équipement blanc ou gris ne se vend pas à l'HDV, il part chez le marchand. Les marchandises "
            .. "(minerais, herbes, tissus...) sont toujours proposées.",
    })
    c:Buttons({
        {
            text = "Vider « jamais à l'HDV »", width = 260,
            getText = function()
                local n = 0
                for _, on in pairs(type(db("ahNever")) == "table" and db("ahNever") or {}) do
                    if on then n = n + 1 end
                end
                return ns.Tf("Vider « jamais à l'HDV » (%d)", n)
            end,
            confirm = "Clique encore pour vider",
            tip = "Les objets exclus d'un clic droit dans le panneau de l'HDV seront de nouveau proposés.",
            onClick = function() ns:Set("ahNever", {}) end,
        },
    })

    -- Prix de l'HDV partout (Prices.lua, Craft.lua)
    c = p:Card("Prix de l'HDV", "Le prix de tes objets à l'hôtel des ventes, partout : dans les infobulles et avant de "
        .. "fabriquer. Les prix viennent d'un scan complet de l'HDV et de ce que l'assistant trouve.")
    c:Switch({
        key = "ahTooltip",
        label = "Prix dans les infobulles",
        desc = "Une ligne « HDV » sur les objets : sacs, équipement porté, liens...",
        tip = "Affiche le prix le plus bas vu à l'HDV, à l'unité, et pour toute la pile quand l'objet est dans tes sacs. "
            .. "Si le prix date de plus d'un jour, son âge est indiqué.",
    })
    c:Switch({
        key = "craftPrices",
        label = "Coût et bénéfice des recettes",
        desc = "À côté de la fenêtre de métier, pour la recette affichée.",
        tip = "Prix de l'objet fabriqué à l'HDV, coût de chaque composant (le moins cher entre l'HDV et le marchand), "
            .. "puis ce que tu gagnes ou perds en fabriquant pour revendre (l'HDV garde 5 % de la vente). "
            .. "Les prix d'achat des marchands (fils, fioles...) sont relevés quand tu les visites.",
    })
    c:Switch({
        key = "ahFullScan",
        label = "Scan complet automatique",
        desc = "À l'ouverture de l'HDV, au plus une fois par heure.",
        tip = "Relève d'un coup le prix de tout ce qui est en vente à l'HDV (quelques secondes). Le serveur ne l'autorise "
            .. "qu'une fois toutes les 15 min. Coupé : bouton « Scan complet » du panneau de l'HDV, ou /pp hdv complet.",
    })
    c:Info({
        label = "Prix connus",
        text = function()
            if not (ns.Prices and ns.Prices.Count) then return "|cff999999indisponible|r" end
            local n, last = ns.Prices:Count(), ns.Prices:LastFullScan()
            local when = last and ns.Tf("dernier scan complet %s", ns.Prices.AgeText((rawget(_G, "time") and time() or 0) - last))
                or ns.T("aucun scan complet pour l'instant")
            return ns.Tf("%s |cff999999· %s|r", W.Color("accent", ns.Tf("%d objet(s)", n)), when)
        end,
        tip = "Nombre d'objets dont Platyplus connaît le prix à l'HDV sur ce royaume.",
    })
end

---------------------------------------------------------------------------
-- 4. Combat : coups blancs, rappel de buffs, (fenêtre de menace : buildThreat), mana du healer, contrôles des mobs
---------------------------------------------------------------------------
-- Barre de coups blancs (SwingBar, ResourceBar.lua)
local function buildSwing(p)
    local c = p:Card("Barre de coups blancs", "Le minuteur de ton attaque automatique : la barre se remplit jusqu'au prochain "
        .. "coup blanc. Pratique pour placer Frappe héroïque ou Heurtoir au bon moment.")
    c:Switch({
        key = "swingBar",
        label = "Barre de coups blancs",
        desc = "En combat ; dorée quand Frappe héroïque attend le prochain coup.",
        tip = "Se remplit à la vitesse de ton arme et repart à chaque coup blanc (le jeu le signale lui-même). "
            .. "Le temps restant s'affiche à droite. Elle devient dorée quand Frappe héroïque ou Enchaînement attend le "
            .. "prochain coup, et pâlit quand ta cible est hors de portée.",
    })
    c:Switch({
        key = "swingOffHand",
        label = "Main gauche aussi",
        desc = "Une fine barre en dessous si tu as deux armes.",
        indent = 1,
        enabled = function() return db("swingBar") end,
        requires = "Nécessite la barre de coups blancs.",
        tip = "Avec deux armes, une seconde barre plus fine suit l'arme de la main gauche.",
    })
    c:Slider({
        key = "swingWidth",
        label = "Largeur",
        min = 140, max = 400, step = 10,
        format = "%d px",
        indent = 1,
        enabled = function() return db("swingBar") end,
        requires = "Nécessite la barre de coups blancs.",
        tip = "Largeur de la barre de coups blancs.",
    })
    c:Buttons({
        {
            text = "Déplacer", width = 120,
            getText = function() return db("swingLocked") == false and "Verrouiller" or "Déplacer" end,
            tip = "Déverrouille la barre pour la glisser où tu veux ; reclique pour la verrouiller.",
            onClick = function() ns:Set("swingLocked", not db("swingLocked")) end,
        },
        {
            text = "Aperçu", width = 110, primary = true,
            tip = "Montre la barre quelques secondes avec des coups simulés à la vitesse de ton arme.",
            onClick = function()
                local s = ns.SwingBar
                if s and s.Preview then s:Preview(6) end
            end,
        },
        {
            text = "Remettre en place", width = 160,
            tip = "Replace la barre sous ton personnage.",
            onClick = function()
                ns:Reset("swingX")
                ns:Reset("swingY")
            end,
        },
    })
end

-- Rappel de buffs (Buffs.lua)
local function buildBuffs(p)
    local c = p:Card("Rappel de buffs", "En combat, ton Cri de guerre s'il te manque. Hors combat, ce que tes alliés peuvent "
        .. "te donner et que tu n'as pas, et un clic droit pour le leur demander.")
    c:Switch({
        key = "buffShout",
        label = "Cri de guerre en combat",
        desc = "S'il te manque en combat : son icône et sa touche, comme une alerte de proc.",
        tip = "En combat seulement : si tu n'as pas ton Cri de guerre, son icône apparaît en grand avec la touche à "
            .. "presser (« Cri de guerre manquant »), bleutée tant que tu n'as pas assez de rage. Elle disparaît dès que "
            .. "tu cries. Il faut que le Cri de guerre soit rangé sur tes barres. Fonctionne même si l'alerte de proc "
            .. "est coupée.",
    })
    c:Switch({
        key = "buffAllies",
        label = "Buffs que mes alliés peuvent me donner",
        desc = "Hors combat : l'icône du buff manquant avec le nom de l'allié.",
        tip = "Exemple : un prêtre et un druide dans ton groupe, et tu n'as ni Robustesse ni Marque du fauve : deux "
            .. "icônes apparaissent au-dessus de ton personnage, avec « Ariane » et « Cléo » dessous. Proposés : "
            .. "Robustesse (prêtre), Marque du fauve (druide), Intelligence des arcanes (mage, si tu utilises de la "
            .. "mana), une bénédiction (paladin : puissance, ou sagesse si tu utilises de la mana ; n'importe "
            .. "laquelle compte). Cachée en combat.",
    })
    c:Switch({
        key = "buffAsk",
        label = "Demander un buff au clic droit",
        desc = "Clic droit sur un paladin, un prêtre, un mage… : « Demander un buff » lui chuchote ta demande.",
        tip = "Exemple : clic droit sur le portrait d'un paladin, « Demander un buff », « Bénédiction des rois » : il "
            .. "reçoit « Salut, rois stp ? Merci :) » (prêtre : « buff endu », mage : « buff int »…). La liste dépend de sa "
            .. "classe — paladin : les bénédictions ; prêtre : Robustesse, Esprit divin, Protection contre l'Ombre ; "
            .. "druide : Marque du fauve, Épines ; mage : Intelligence des arcanes, nourriture, eau ; démoniste : "
            .. "Respiration interminable, pierre de soins, invocation ; chaman : Respiration aquatique, Marche sur "
            .. "l'eau. En haut de la liste, « Tous ses buffs » envoie « Salut, buff stp ? Merci :) ». "
            .. "Marche aussi sur un nom cliqué dans le chat. En instance, si le jeu cache son nom, la demande "
            .. "part dans le chat du groupe.",
    })
    c:Dropdown({
        key = "buffAskLang",
        label = "Langue de la demande",
        indent = 1,
        enabled = function() return db("buffAsk") end,
        requires = "Nécessite « Demander un buff au clic droit ».",
        options = { { value = "fr", text = "Français" }, { value = "en", text = "Anglais" } },
        tip = "La langue du message envoyé (le menu reste en français). En anglais, avec les abréviations des "
            .. "joueurs : « Hi, could I get BoK pls? Thanks :) » (Fort, MotW, Int…) ; « Tous ses buffs » : « Hi, "
            .. "could I get buff pls? Thanks :) ».",
    })
    c:Buttons({
        {
            text = "Déplacer", width = 120,
            getText = function() return db("buffLocked") == false and "Verrouiller" or "Déplacer" end,
            enabled = function() return db("buffAllies") end,
            requires = "Nécessite « Buffs que mes alliés peuvent me donner ».",
            tip = "Déverrouille la rangée des buffs à demander pour la glisser où tu veux ; reclique (ou clic droit "
                .. "dessus) pour la verrouiller.",
            onClick = function() call("Buffs", "ToggleMove", "rappel de buffs indisponible") end,
        },
        {
            text = "Aperçu", width = 110, primary = true,
            tip = "Montre la rangée quelques secondes avec deux buffs d'exemple, et écrit dans le chat ce que "
                .. "Platyplus voit en ce moment (aussi : /pp buffs).",
            onClick = function()
                local B = ns.Buffs
                if not (B and B.Preview) then ns:Print("rappel de buffs indisponible") return end
                for _, line in ipairs(B:Status()) do ns:Print(line) end
                B:Preview()
            end,
        },
        {
            text = "Remettre en place", width = 160,
            tip = "Replace la rangée au-dessus de ton personnage.",
            onClick = function()
                if not call("Buffs", "ResetPosition") then
                    ns:Reset("buffX")
                    ns:Reset("buffY")
                end
            end,
        },
    })
end

-- Mana du healer du groupe (HealerMana.lua)
local function buildHealer(p)
    local function whenHealer() return db("healerBar") end
    local c = p:Card("Mana de mon healer", "Une barre de mana pour le soigneur de ton groupe, posée où tu veux à l'écran : "
        .. "son nom et « 4 320 / 6 800 ».")
    c:Switch({
        key = "healerBar",
        label = "Afficher la mana de mon healer",
        desc = "Visible seulement quand ton groupe a un healer.",
        tip = "Le healer est celui que le groupe désigne comme soigneur (file de donjon, ou rôle donné par le chef de "
            .. "groupe). Si personne n'a ce rôle, cible ton healer et clique « Mon healer = ma cible ». "
            .. "S'il y a plusieurs soigneurs, la barre suit le premier de la liste du groupe : choisis le tien avec le bouton.",
    })
    c:Info({
        label = "Healer suivi",
        text = function()
            local H = ns.HealerMana
            local who = H and H.Summary and H:Summary()
            if who then return who end
            return W.Color("gold", "aucun pour l'instant")
        end,
        tip = "Le joueur dont la barre montre la mana. « Aucun » : ton groupe n'a pas de soigneur désigné et tu n'as "
            .. "pas choisi ton healer à la main.",
    })
    c:Buttons({
        {
            text = "Mon healer = ma cible", width = 200,
            tip = "Cible ton healer, puis clique : la barre suit ce joueur tant qu'il est dans ton groupe, même si le "
                .. "groupe ne lui a pas donné le rôle de soigneur (aussi : /pp healer cible).",
            onClick = function() call("HealerMana", "PickTarget", "barre de mana du healer indisponible") end,
        },
        {
            text = "Laisser le jeu choisir", width = 200,
            enabled = function() return (db("healerName") or "") ~= "" end,
            requires = "Tu n'as choisi personne à la main.",
            tip = "Oublie le joueur choisi : la barre suit de nouveau le soigneur désigné par le groupe "
                .. "(aussi : /pp healer auto).",
            onClick = function() call("HealerMana", "ClearPick", "barre de mana du healer indisponible") end,
        },
    })
    local function whenHealerLow() return db("healerBar") and db("healerLow") end
    c:Switch({
        key = "healerLow",
        label = "Alerte « healer à sec »",
        desc = "Sous le seuil, la barre devient rouge et clignote.",
        enabled = whenHealer,
        requires = "Nécessite « Afficher la mana de mon healer ».",
        tip = "Exemple avec le seuil à 20 % : ton healer a 6 800 de mana au maximum ; dès qu'il passe sous 1 360, la barre "
            .. "et son contour deviennent rouges et la barre clignote une fois. L'alerte se retire quand il remonte "
            .. "à 25 %, pour ne pas clignoter autour du seuil. Pendant les combats où le jeu cache la mana des "
            .. "alliés, la barre devient seulement rouge (sans clignotement ni son).",
    })
    c:Slider({
        key = "healerLowPercent",
        label = "Seuil d'alerte",
        min = 5, max = 50, step = 5,
        format = "%d %%",
        indent = 1,
        enabled = whenHealerLow,
        requires = "Nécessite l'alerte « healer à sec ».",
        tip = "Pourcentage de mana sous lequel l'alerte se déclenche : à 20 %, un healer à 6 800 de mana maximum "
            .. "est à sec sous 1 360.",
    })
    c:Switch({
        key = "healerLowSound",
        label = "Avec un son",
        desc = "Seulement en combat.",
        indent = 1,
        enabled = whenHealerLow,
        requires = "Nécessite l'alerte « healer à sec ».",
        tip = "Joue un avertissement quand l'alerte se déclenche. Hors combat, pas de son : un healer qui boit est "
            .. "à sec exprès. Le bouton « Aperçu » le fait entendre.",
    })
    c:Slider({
        key = "healerWidth",
        label = "Largeur",
        min = 120, max = 400, step = 10,
        format = pixels,
        indent = 1,
        enabled = whenHealer,
        requires = "Nécessite « Afficher la mana de mon healer ».",
        tip = "Largeur de la barre, en points d'interface.",
    })
    c:Slider({
        key = "healerScale",
        label = "Taille",
        min = 0.6, max = 2, step = 0.05,
        format = percent,
        indent = 1,
        enabled = whenHealer,
        requires = "Nécessite « Afficher la mana de mon healer ».",
        tip = "Agrandit ou réduit toute la barre (100 % = taille normale).",
    })
    c:Buttons({
        {
            text = "Déplacer", width = 120,
            getText = function() return db("healerLocked") == false and "Verrouiller" or "Déplacer" end,
            tip = "Déverrouille la barre pour la glisser où tu veux ; reclique (ou clic droit sur la barre) pour la verrouiller.",
            onClick = function() call("HealerMana", "ToggleMove", "barre de mana du healer indisponible") end,
        },
        {
            text = "Aperçu", width = 110, primary = true,
            tip = "Montre la barre quelques secondes, même désactivée ou sans healer, avec des valeurs d'exemple : la mana "
                .. "d'exemple tombe sous le seuil pour te montrer l'alerte (et son son, s'il est coché).",
            onClick = function() call("HealerMana", "Preview", "barre de mana du healer indisponible") end,
        },
        {
            text = "Remettre en place", width = 160,
            tip = "Replace la barre à sa place d'origine (à gauche sous le centre de l'écran).",
            onClick = function()
                if not call("HealerMana", "ResetPosition") then
                    ns:Reset("healerX")
                    ns:Reset("healerY")
                end
            end,
        },
    })
end

-- Contrôles des mobs dans l'infobulle (MobControls.lua)
local function buildMobs(p)
    local c = p:Card("Contrôles des mobs", "Ce qu'un mob peut te faire subir, avant de le taper.")
    c:Switch({
        key = "mobControlTooltip",
        label = "Dans l'infobulle des mobs",
        desc = "Ex. « Coup de pied rapide — Étourdit 2 s   toutes les 5-9 s ».",
        tip = "Au survol d'un mob, liste ses sorts qui étourdissent, immobilisent, ralentissent, apeurent, "
            .. "repoussent ou désarment, avec leur durée et leur rythme. Les délais viennent du jeu d'origine "
            .. "(base VMaNGOS) : ce sont des ordres de grandeur. Cible un mob et tape /pp mob pour tout voir. "
            .. "En donjon, le jeu cache l'identité des mobs aux addons : rien ne s'affiche.",
    })
end

---------------------------------------------------------------------------
-- 5. Confort
---------------------------------------------------------------------------
-- (rangée à la fin de l'onglet Vente & HDV)
---------------------------------------------------------------------------
-- Onglet « Procs » : alerte de proc (Procs.lua), toutes classes
---------------------------------------------------------------------------
-- jeton anglais de ta classe (« WARRIOR »), nil si illisible
local function playerClassToken()
    local fn = rawget(_G, "UnitClass")
    if type(fn) ~= "function" then return nil end
    local ok, _, token = pcall(fn, "player")
    if ok and type(token) == "string" and not (rawget(_G, "issecretvalue") and issecretvalue(token)) then
        return token
    end
    return nil
end

local function buildProcs(p)
    local function whenProc() return db("procAlert") end
    local need = "Nécessite l'alerte de proc."
    local c = p:Card("Alerte de proc", "Quand un sort devient utilisable (Fulgurance après une esquive, un sort qui brille...), "
        .. "son icône apparaît en grand sous ton personnage avec la touche à presser.")
    c:Switch({
        key = "procAlert",
        label = "Alerte de proc avec la touche",
        desc = "Ta cible esquive : l'icône de Fulgurance apparaît avec « 3 » dessous si elle est sur la touche 3.",
        tip = "L'alerte apparaît quand le sort est vraiment utilisable (bonne posture, assez de rage, pas en recharge) "
            .. "et disparaît dès qu'il ne l'est plus. La touche est celle du bouton où tu as rangé le sort : un sort "
            .. "absent de tes barres n'est pas annoncé. Choisis les sorts surveillés dans la carte du dessous. "
            .. "/pp proc liste tes sorts surveillés et leur touche.",
    })

    c = p:Card("Sorts surveillés", "Quels sorts déclenchent une alerte. Ils doivent être rangés sur une de tes barres.")
    c:Switch({
        key = "procReactive",
        label = "Sorts réactifs de ma classe",
        desc = "Ceux qui ne marchent qu'après un événement : Fulgurance après une esquive, Exécution sous 20 % de vie.",
        enabled = whenProc,
        requires = need,
        tip = "Guerrier : Fulgurance, Vengeance, Exécution, Ivresse de la victoire. Voleur : Riposte. Chasseur : "
            .. "Contre-attaque, Morsure de la mangouste, Ordre de tuer. Paladin : Marteau de courroux. Exemple : tu "
            .. "pares un coup, Riposte apparaît avec sa touche. Coupé, ces sorts ne sont plus annoncés (sauf s'ils "
            .. "brillent et que « Sorts qui brillent » est actif).",
    })
    c:Switch({
        key = "procGlow",
        label = "Sorts qui brillent",
        desc = "Tout sort que le jeu entoure d'une lueur sur tes barres : c'est le cas des procs des autres classes.",
        enabled = whenProc,
        requires = need,
        tip = "Exemple : un mage dont un sort se met à briller sur sa barre voit son icône apparaître en grand avec la "
            .. "touche. Mage, démoniste, prêtre, druide et chaman passent surtout par là, comme les sorts de rune. "
            .. "Les sorts réactifs du guerrier peuvent aussi briller : coupe cette option si tu ne veux que la liste "
            .. "des sorts réactifs.",
    })
    c:Info({
        label = "Pour ta classe",
        text = function()
            local P = ns.Procs
            local list = P and P.ClassDefaults and P.ClassDefaults() or {}
            if #list == 0 then return "aucun sort réactif connu (ses procs passent par la brillance du jeu)" end
            local names = {}
            for _, e in ipairs(list) do names[#names + 1] = e.name end
            return table.concat(names, ", ")
        end,
        tip = "Les sorts réactifs que Platyplus connaît pour ta classe. Pour en ajouter un autre, utilise la liste "
            .. "« Sorts ajoutés » juste en dessous.",
    })
    c:SpellList({
        list = "procExtra",
        label = "Sorts ajoutés",
        tip = "Un sort ajouté ici est annoncé dès qu'il est sur une de tes barres, utilisable et hors recharge, comme "
            .. "un sort réactif. Exemple : ajoute Coup de bouclier pour voir son icône et sa touche chaque fois qu'il "
            .. "est prêt. Glisse le sort depuis ton grimoire, ou tape son nom. En combat, si le jeu cache la "
            .. "recharge, un sort ajouté peut rester affiché pendant sa recharge.",
    })
    c:SpellList({
        list = "procIgnore",
        label = "Sorts ignorés",
        tip = "Un sort ignoré n'a jamais d'alerte, même s'il brille. Exemple : un sort qui brille tout le temps et "
            .. "t'encombre l'écran : ajoute-le ici. Tous les rangs du sort sont ignorés (reconnus par leur nom).",
    })

    c = p:Card("Affichage", "Taille, nombre, animation et son des alertes.")
    c:Slider({
        key = "procScale",
        label = "Taille",
        min = 0.6, max = 2, step = 0.05,
        format = percent,
        enabled = whenProc,
        requires = need,
        tip = "Agrandit ou réduit l'alerte (100 % = icône de 52 points, touche en gros dessous).",
    })
    c:Slider({
        key = "procMax",
        label = "Alertes en même temps",
        min = 1, max = 6, step = 1,
        format = "%d",
        enabled = whenProc,
        requires = need,
        tip = "Exemple : 3 = jusqu'à trois icônes côte à côte (Fulgurance, Exécution et Vengeance prêtes ensemble). "
            .. "Avec 1, seule la première est montrée.",
    })
    c:Switch({
        key = "procShowKey",
        label = "Montrer la touche",
        desc = "La touche à presser, en gros sous l'icône (« 3 », « Maj+E »).",
        enabled = whenProc,
        requires = need,
        tip = "Coupé, il ne reste que l'icône (et le nom si tu le gardes) : tu connais déjà ta touche.",
    })
    c:Switch({
        key = "procShowName",
        label = "Montrer le nom du sort",
        desc = "Le nom du sort, en petit sous la touche.",
        enabled = whenProc,
        requires = need,
        tip = "Exemple : « Fulgurance » écrit sous l'icône. Coupé, l'alerte est plus compacte.",
    })
    c:Dropdown({
        key = "procAnim",
        label = "Animation",
        enabled = whenProc,
        requires = need,
        options = {
            { value = "vif", text = "Vive" },
            { value = "doux", text = "Douce" },
            { value = "aucune", text = "Aucune" },
        },
        tip = "Vive : l'icône jaillit, des ondes dorées partent et un reflet la balaie. Douce : seulement le halo qui "
            .. "respire. Aucune : l'icône apparaît et reste fixe.",
    })
    c:Slider({
        key = "procOpacity",
        label = "Opacité",
        min = 0.3, max = 1, step = 0.05,
        format = percent,
        enabled = whenProc,
        requires = need,
        tip = "Rend l'alerte plus ou moins transparente. Exemple : 60 % pour qu'elle gêne moins la vue en plein combat.",
    })
    c:Switch({
        key = "procSound",
        label = "Son à l'apparition",
        desc = "Un petit « tic » quand une alerte apparaît.",
        enabled = whenProc,
        requires = need,
        tip = "Un son discret à chaque nouvelle alerte, au plus un par seconde. Exemple : Fulgurance devient prête, "
            .. "tu l'entends sans regarder. Le bouton Aperçu le joue aussi.",
    })
    c:Buttons({
        {
            text = "Déplacer", width = 120,
            getText = function() return db("procLocked") == false and "Verrouiller" or "Déplacer" end,
            tip = "Déverrouille l'alerte pour la glisser où tu veux ; reclique (ou clic droit dessus) pour la verrouiller.",
            onClick = function() call("Procs", "ToggleMove", "alertes de proc indisponibles") end,
        },
        {
            text = "Aperçu", width = 110, primary = true,
            tip = "Montre l'alerte quelques secondes avec un de tes sorts surveillés et sa vraie touche.",
            onClick = function() call("Procs", "Preview", "alertes de proc indisponibles") end,
        },
        {
            text = "Remettre en place", width = 160,
            tip = "Replace l'alerte sous ton personnage.",
            onClick = function()
                if not call("Procs", "ResetPosition") then
                    ns:Reset("procX")
                    ns:Reset("procY")
                end
            end,
        },
    })

    c = p:Card("Maîtrise du blocage", "Guerrier : une petite icône quand le buff est actif.")
    if playerClassToken() == "WARRIOR" then
        c:Switch({
            key = "procBlock",
            label = "Icône de Maîtrise du blocage",
            desc = "Une petite icône à droite des alertes tant que tu as le buff Maîtrise du blocage.",
            tip = "Quand tu as le buff Maîtrise du blocage, son icône apparaît à droite des alertes de proc (seule au "
                .. "centre s'il n'y a pas d'alerte) et disparaît dès que le buff finit ou que tu as bloqué avec ta dernière charge. "
                .. "En combat le jeu cache tes buffs : l'addon repère alors celui qui apparaît juste après ton clic. "
                .. "Elle suit la taille et la position des alertes. /pp proc donne l'état.",
        })
    else
        c:Help("Réservé au guerrier : cette icône suit le buff Maîtrise du blocage.")
    end
end

---------------------------------------------------------------------------
-- Onglet « Plates » : plates des mobs (Plates.lua), tout personnalisable, avec aperçu en direct
---------------------------------------------------------------------------
local function buildPlates(p)
    local P = ns.Plates
    local function whenPlates() return db("plates") end
    local function whenSlim() return db("plates") and db("platesSlim") end
    local need = "Nécessite « Plates Platyplus »."
    local needSlim = "Nécessite « Cadre Platyplus »."
    -- Plates.GetGameSetting / SetGameSetting (fonctions simples, sans self) ; module absent : rien
    local function gameSetting(name, fallback)
        return function() return (P and P.GetGameSetting(name)) or fallback end,
            function(v) if P then P.SetGameSetting(name, v) end end
    end
    local function colorRow(c, key, label, tip, enabled, requires, indent)
        c:Color({ key = key, label = label, tip = tip, enabled = enabled or whenPlates, requires = requires or need,
            indent = indent })
    end

    local c = p:Card("Plates des mobs", "Comme Threat Plates : qui tape qui, d'un coup d'œil, et un look à ton goût.")
    c:Switch({
        key = "plates",
        label = "Plates Platyplus",
        desc = "Vert : tout va bien, orange : ça se joue, rouge : danger. Les couleurs suivent ton rôle (tank ou DPS).",
        tip = "En combat, la barre de vie de chaque mob prend une couleur selon sa cible :\n"
            .. "|cff33d14dvert|r : il te tape (tank) — ou il t'ignore (DPS/soins) ;\n"
            .. "|cffff9e1aorange|r : ça se joue, quelqu'un est sur le point de prendre ou de perdre l'aggro ;\n"
            .. "|cfff22e26rouge|r : il tape un allié (tank) — ou il te tape (DPS/soins) ;\n"
            .. "|cff409ef9bleu|r : un autre tank du groupe le tient.\n"
            .. "Plus tout le look ci-dessous. Les plates s'affichent avec la touche V.",
    })
    c:Dropdown({
        key = "platesRole", label = "Je joue", indent = 1, enabled = whenPlates, requires = need,
        options = {
            { value = "auto", text = "Auto (posture défensive = tank)" },
            { value = "tank", text = "Toujours tank" },
            { value = "dps", text = "Toujours DPS / soins" },
        },
        tip = "Auto : tu es tank en Posture défensive (ou forme d'ours, ou rôle « tank » du groupe), "
            .. "sinon DPS. Ex. : tu passes en Posture de combat pour finir un mob seul : les couleurs s'inversent.",
    })
    -- Aperçu toujours visible : panneau collé à droite de la fenêtre d'options (à gauche s'il n'y a pas la place),
    -- affiché tant que cet onglet est ouvert, quel que soit le défilement de la page
    local window = ns.UI and ns.UI.frame
    if P and P.NewPreview and window then
        local DOCK_W, GAP = 290, 8
        local dock = CreateFrame("Frame", nil, window)
        dock:SetFrameLevel((window:GetFrameLevel() or 0) + 5)
        dock:EnableMouse(true)
        dock:SetClampedToScreen(true)          -- petit écran : il chevauche un peu la fenêtre plutôt que de sortir
        local shadow = W.Shadow(dock, 14, 16, 3)
        shadow:SetColor(W.C.black, 0.85)
        local bg = W.Round(dock, "BACKGROUND", -6, 12)
        bg:SetColor(W.C.bg)
        local stroke = W.Stroke(dock, "BORDER", 0, 12)
        stroke:SetColor(W.C.white, 0.09)
        local title = W.Text(dock, "GameFontNormal", W.C.text)
        title:SetPoint("TOPLEFT", dock, "TOPLEFT", 16, -14)
        title:SetText("Aperçu")
        local sub = W.Text(dock, "GameFontHighlightSmall", W.C.dim)
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        sub:SetText("Suit chaque réglage en direct.")
        local preview = P.NewPreview(dock, DOCK_W - 20, 1)
        preview:SetPoint("TOPLEFT", dock, "TOPLEFT", 10, -48)
        dock:SetSize(DOCK_W, preview:GetHeight() + 60)
        local function place()
            dock:ClearAllPoints()
            local right, screen = window:GetRight(), UIParent:GetRight()
            local left = window:GetLeft()
            if right and screen and right + DOCK_W + GAP > screen and left and left > screen - right then
                dock:SetPoint("TOPRIGHT", window, "TOPLEFT", -GAP, 0)      -- plus de place à gauche qu'à droite
            else
                dock:SetPoint("TOPLEFT", window, "TOPRIGHT", GAP, 0)
            end
        end
        dock:Hide()
        p:HookScript("OnShow", function() place() dock:Show() preview:Refresh() end)
        p:HookScript("OnHide", function() dock:Hide() end)
        -- la fenêtre se déplace par son en-tête (UI:StopMoving) : on replace le panneau après
        local hook = rawget(_G, "hooksecurefunc")
        if hook and ns.UI.StopMoving then hook(ns.UI, "StopMoving", function() if dock:IsShown() then place() end end) end
        if p:IsShown() then place() dock:Show() end
    end
    local presets = {}
    for _, preset in ipairs(P and P.PRESETS or {}) do
        presets[#presets + 1] = {
            text = preset.text, width = 130, enabled = whenPlates,
            onClick = function() P.ApplyPreset(preset.id) end,
            tip = "Applique ce style d'un coup (couleurs comprises). Tu peux ensuite tout retoucher.",
        }
    end
    if #presets > 0 then
        c:Help("Styles prêts à l'emploi :", { gap = 10 })
        c:Buttons(presets)
    end
    c:Buttons({ {
        text = "Tout remettre par défaut", width = 210, enabled = whenPlates, confirm = "Sûr ? (re-clique)",
        onClick = function() if P then P.ResetLook() end end,
        tip = "Remet le look et toutes les couleurs des plates comme à l'installation (pas le rôle).",
    } })

    c = p:Card("Barre", "Taille, épaisseur, texture, transparence.")
    local getSize, setSize = gameSetting("nameplateSize", 2)
    c:Dropdown({
        label = "Taille des plates", get = getSize, set = setSize,
        options = {
            { value = 1, text = "Petite" }, { value = 2, text = "Normale (jeu)" }, { value = 3, text = "Grande" },
            { value = 4, text = "Très grande" }, { value = 5, text = "Énorme" },
        },
        tip = "Réglage du jeu (Options > Plates d'unités). Grande = 25 % de plus que la taille normale, Énorme = 60 %. "
            .. "Se change hors combat.",
    })
    local getStyle, setStyle = gameSetting("nameplateStyle", 1)
    c:Dropdown({
        label = "Hauteur de la barre", get = getStyle, set = setStyle,
        options = {
            { value = 1, text = "Fine (jeu)" }, { value = 0, text = "Épaisse" }, { value = 2, text = "Bloc (incantation large)" },
            { value = 4, text = "Incantation en avant (jeu)" },
        },
        tip = "Réglage du jeu. Fine : 13 px de haut ; Épaisse : 20 px, bien plus lisible en combat ; "
            .. "Bloc : épaisse, et la barre d'incantation aussi. Se change hors combat.",
    })
    c:Dropdown({
        key = "platesTexture", label = "Texture", enabled = whenPlates, requires = need,
        options = {
            { value = "smooth", text = "Dégradé Platyplus" }, { value = "flat", text = "Unie" },
            { value = "blizzard", text = "Classique du jeu" }, { value = "raid", text = "Cadres de raid" },
        },
        tip = "L'aspect de la barre colorée. Unie = couleur plate, sans reflet.",
    })
    c:Slider({
        key = "platesOpacity", label = "Opacité des barres", min = 30, max = 100, step = 5, format = "%d%%",
        enabled = whenPlates, requires = need,
        tip = "100 % = barres pleines ; 70 % = on voit un peu le décor à travers. Le nom et le texte restent nets.",
    })

    c = p:Card("Cadre", "Le contour et le fond autour de la barre.")
    c:Switch({
        key = "platesSlim", label = "Cadre Platyplus", enabled = whenPlates, requires = need,
        desc = "Le gros cadre sombre du jeu remplacé par le nôtre, réglable ci-dessous.",
        tip = "Coupé : le cadre du jeu (large, avec une ombre en bas à droite) revient, coins carrés.",
    })
    c:Slider({
        key = "platesRadius", label = "Arrondi des coins", indent = 1, min = 0, max = 4, step = 1,
        enabled = whenSlim, requires = needSlim,
        format = function(v) return ns.T(({ [0] = "Carré", "Léger", "Doux", "Rond", "Très rond" })[v] or tostring(v)) end,
        tip = "De coins carrés (0) à des bouts bien ronds (4).",
    })
    c:Slider({
        key = "platesBorder", label = "Épaisseur du bord", indent = 1, min = 0, max = 4, step = 1,
        enabled = whenSlim, requires = needSlim,
        format = function(v) return v == 0 and ns.T("Aucun") or (v .. " px") end,
        tip = "0 = pas de bord, juste le fond ; 1 = un trait fin ; 3-4 = un contour bien marqué.",
    })
    colorRow(c, "platesColBorder", "Couleur du bord", "Noir par défaut.", whenSlim, needSlim, 1)
    c:Slider({
        key = "platesBackAlpha", label = "Opacité du fond", indent = 1, min = 0, max = 100, step = 5, format = "%d%%",
        enabled = whenSlim, requires = needSlim,
        tip = "Le fond visible là où le mob a perdu de la vie. 0 % = transparent.",
    })
    colorRow(c, "platesColBack", "Couleur du fond", "Presque noir par défaut.", whenSlim, needSlim, 1)

    c = p:Card("Incantations", "La barre de sort sous la plate d'un mob qui incante.")
    c:Switch({
        key = "platesCast", label = "Barres d'incantation Platyplus", enabled = whenPlates, requires = need,
        desc = "Couleur selon qu'on peut l'interrompre, et le temps restant.",
        tip = "Ex. un chaman kobold lance Éclair : la barre est jaune (interruptible), bleue si ta Volée de coups "
            .. "est prête, grise s'il est protégé (bouclier : rien à faire).",
    })
    local function whenCast() return db("plates") and db("platesCast") end
    local needCast = "Nécessite « Barres d'incantation Platyplus »."
    colorRow(c, "platesColCastInterrupt", "Interruptible", nil, whenCast, needCast, 1)
    c:Switch({
        key = "platesCastKick", label = "Couleur « interruption prête »", indent = 1, enabled = whenCast,
        requires = needCast,
        tip = "Quand ta Volée de coups (ou Coup de bouclier, Coup de pied, Contresort, Horion de terre) est prête "
            .. "et utilisable dans ta posture : fonce !",
    })
    colorRow(c, "platesColCastKick", "Couleur « interruption prête »", nil,
        function() return whenCast() and db("platesCastKick") end, "Nécessite « Couleur interruption prête ».", 2)
    colorRow(c, "platesColCastShield", "Pas interruptible", nil, whenCast, needCast, 1)
    c:Switch({
        key = "platesCastStyle", label = "Même cadre que la barre de vie", indent = 1,
        enabled = function() return whenCast() and db("platesSlim") end,
        requires = "Nécessite « Barres d'incantation » et « Cadre Platyplus ».",
        tip = "Fond, bord et coins arrondis comme réglés dans la carte « Cadre ».",
    })
    c:Switch({
        key = "platesCastTimer", label = "Temps restant", indent = 1, enabled = whenCast, requires = needCast,
        tip = "« 1.4 » à droite de la barre : le temps avant que le sort parte.",
    })
    c:Switch({
        key = "platesCastSound", label = "Son quand ta cible incante", indent = 1, enabled = whenCast, requires = needCast,
        tip = "Un son quand ta cible commence un sort que tu peux interrompre (au plus une fois par seconde).",
    })

    c = p:Card("Couleurs de menace", "En combat. Tank / DPS : les rôles s'inversent tout seuls.")
    colorRow(c, "platesColSafe", "Tout va bien", "Tank : le mob te tape. DPS/soins : il ne te regarde pas.")
    colorRow(c, "platesColWarn", "Ça se joue", "Quelqu'un est sur le point de prendre ou de perdre l'aggro.")
    colorRow(c, "platesColLoose", "Danger", "Tank : il tape un allié. DPS/soins : il te tape.")
    c:Switch({
        key = "platesOfftank", label = "Autre tank", enabled = whenPlates, requires = need,
        desc = "Une couleur à part quand un autre tank du groupe tient le mob.",
        tip = "En groupe avec deux tanks : un mob tenu par l'autre tank n'est pas « danger » (pas ton problème).",
    })
    colorRow(c, "platesColOther", "Couleur « autre tank »", nil,
        function() return db("plates") and db("platesOfftank") end, "Nécessite « Autre tank ».", 1)
    c:Switch({
        key = "platesAlert", label = "Clignote quand un mob t'échappe", enabled = whenPlates, requires = need,
        tip = "Tank : quand un mob qui te tapait part sur un allié, sa plate clignote pour que tu le reprennes "
            .. "(Provocation, Coup railleur...).",
    })
    local function whenAlert() return db("plates") and db("platesAlert") end
    local needAlert = "Nécessite « Clignote quand un mob t'échappe »."
    colorRow(c, "platesColGlow", "Couleur du clignotement", nil, whenAlert, needAlert, 1)
    c:Slider({
        key = "platesAlertTime", label = "Durée", indent = 1, min = 0.5, max = 4, step = 0.5, format = "%.1f s",
        enabled = whenAlert, requires = needAlert, tip = "Le clignotement fait toujours trois éclats, plus ou moins vite.",
    })
    c:Switch({
        key = "platesAlertSound", label = "Avec un son", indent = 1, enabled = whenAlert, requires = needAlert,
        tip = "Le son d'avertissement de raid, au plus une fois par seconde.",
    })

    c = p:Card("Hors combat", "Les mobs qui ne se battent pas avec toi.")
    c:Dropdown({
        key = "platesIdle", label = "Couleurs", enabled = whenPlates, requires = need,
        options = { { value = "reaction", text = "Les miennes" }, { value = "game", text = "Celles du jeu" } },
        tip = "Les miennes : hostile, neutre, amical et « tapé par d'autres » aux couleurs ci-dessous, avec ta texture. "
            .. "Celles du jeu : la barre normale du jeu. Les joueurs gardent toujours les couleurs du jeu.",
    })
    local function whenIdle() return db("plates") and db("platesIdle") == "reaction" end
    local needIdle = "Nécessite « Couleurs : les miennes »."
    colorRow(c, "platesColHostile", "Hostile", "Un mob qui t'attaquera si tu t'approches.", whenIdle, needIdle, 1)
    colorRow(c, "platesColNeutral", "Neutre", "Il ne t'attaque que si tu le tapes.", whenIdle, needIdle, 1)
    colorRow(c, "platesColFriendly", "Amical", "PNJ amicaux.", whenIdle, needIdle, 1)
    colorRow(c, "platesColTapped", "Tapé par d'autres", "Un autre joueur l'a touché en premier : pas d'XP ni de butin pour toi.",
        whenIdle, needIdle, 1)

    c = p:Card("Ta cible", "La repérer au milieu d'un pack.")
    c:Switch({
        key = "platesTarget", label = "Bord de couleur sur ta cible", enabled = whenSlim, requires = needSlim,
        tip = "Le bord de la plate de ta cible est plus épais et de la couleur choisie.",
    })
    colorRow(c, "platesColTarget", "Couleur du bord", nil, function() return whenSlim() and db("platesTarget") end,
        "Nécessite « Bord de couleur sur ta cible ».", 1)
    c:Slider({
        key = "platesNonTarget", label = "Plates non ciblées", min = 20, max = 100, step = 5, format = "%d%%",
        enabled = whenPlates, requires = need,
        tip = "Quand tu as une cible, les autres barres passent à cette opacité. 100 % = pas d'effet ; "
            .. "50 % = ta cible ressort nettement.",
    })

    c = p:Card("Icônes", "Quêtes et mobs spéciaux.")
    c:Switch({
        key = "platesQuest", label = "Mobs de quête", enabled = whenPlates, requires = need,
        desc = "Ex. « 3/8 » et un ! à côté de la barre d'un loup qu'il te reste à tuer.",
        tip = "Un ! jaune pour un mob à tuer, un sac pour un mob qui laisse un objet de quête, avec ta progression. "
            .. "Disparaît quand l'objectif est fini. Les objectifs de tes équipiers sont ignorés.",
    })
    local function whenQuest() return db("plates") and db("platesQuest") end
    local needQuest = "Nécessite « Mobs de quête »."
    c:Dropdown({
        key = "platesQuestSide", label = "Position", indent = 1, enabled = whenQuest, requires = needQuest,
        options = { { value = "left", text = "À gauche" }, { value = "right", text = "À droite" },
            { value = "top", text = "Au-dessus" } },
        tip = "À droite, l'icône peut couvrir celles des contrôles subis par le mob.",
    })
    c:Slider({
        key = "platesQuestSize", label = "Taille de l'icône", indent = 1, min = 10, max = 32, step = 2, format = "%d px",
        enabled = whenQuest, requires = needQuest,
    })
    c:Switch({
        key = "platesQuestText", label = "Progression « 3/8 »", indent = 1, enabled = whenQuest, requires = needQuest,
    })
    colorRow(c, "platesColQuest", "Couleur de la progression", nil,
        function() return whenQuest() and db("platesQuestText") end, "Nécessite « Progression ».", 2)
    c:Switch({
        key = "platesHideQuestie", label = "Cacher les icônes de Questie", indent = 1,
        enabled = whenQuest, requires = needQuest,
        desc = "Questie met aussi ses icônes sur les plates : on ne garde que les nôtres, avec la progression.",
        tip = "Coupe l'option « icônes d'objectif sur les plates » de Questie. Décoche pour la rallumer.",
    })
    c:Switch({
        key = "platesRare", label = "Repérer les rares", enabled = whenPlates, requires = need,
        tip = "Écrit « Rare » au-dessus du bout droit de la barre des mobs rares (souvent un bon butin).",
    })
    c:Switch({
        key = "platesElite", label = "Repérer les élites et les boss", enabled = whenPlates, requires = need,
        tip = "Écrit « Élite » (ou « Boss ») au-dessus du bout droit de la barre : à ne pas tirer à plusieurs.",
    })
    c:Help("Si l'addon Threat Plates est actif, il remplace les plates du jeu : désactive-le pour voir celles-ci. "
        .. "Les cadavres à fouiller ont déjà leurs étincelles (onglet Butin). /pp plates : ce que voit chaque plate.")
end

local function buildMerchant(p)
    local c = p:Card("Marchands, sacs et courrier")
    c:Switch({
        key = "autoRepair",
        label = "Réparer automatiquement",
        tip = "Répare tout ton équipement à l'ouverture d'un marchand qui sait réparer. Le coût s'affiche dans le flux.",
    })
    c:Switch({
        key = "repairGuild",
        label = "Avec l'argent de la guilde d'abord",
        indent = 1,
        enabled = whenRepair,
        requires = "Nécessite « Réparer automatiquement ».",
        tip = "Si ta guilde l'autorise, la réparation est payée par la banque de guilde ; sinon, avec ton argent.",
    })
    c:Switch({
        key = "bagWarn",
        label = "Alerte « sacs presque pleins »",
        tip = "Affiche une alerte quand il te reste peu d'emplacements libres dans tes sacs.",
    })
    c:Slider({
        key = "bagWarnSlots",
        label = "Emplacements libres restants",
        min = 1, max = 30, step = 1,
        format = "%d",
        indent = 1,
        enabled = whenBagWarn,
        requires = "Nécessite l'alerte des sacs presque pleins.",
        tip = "L'alerte se déclenche quand il te reste ce nombre d'emplacements libres, ou moins.",
    })
    c:Switch({
        key = "durabilityWarn",
        label = "Alerte « équipement presque cassé »",
        tip = "Prévient quand une pièce de ton équipement est presque cassée, pour penser à réparer.",
    })
    c:Switch({
        key = "autoOpenMail",
        label = "Ouvrir tout le courrier",
        desc = "Récupère objets et argent dès que tu ouvres la boîte aux lettres.",
        tip = "À l'ouverture de la boîte aux lettres, Platyplus prend tout le contenu des lettres (objets et argent). "
            .. "Les lettres contre remboursement ne sont pas payées.",
    })
    c:Buttons({
        {
            text = "Trier les sacs", width = 150,
            tip = "Range le contenu de tes sacs (même action que /pp sort).",
            onClick = function() call("Misc", "SortBags", "tri des sacs indisponible") end,
        },
    })
end

-- (rangée à la fin de l'onglet Fenêtres)
local function buildIlvl(p)
    local c = p:Card("Niveau d'objet")
    c:Switch({
        key = "charIlvl",
        label = "Sur la fiche du personnage",
        tip = "Écrit le niveau d'objet de chaque pièce sur la fiche de ton personnage, et la moyenne sous ton niveau.",
    })
    c:Switch({
        key = "bagIlvl",
        label = "Sur les objets des sacs",
        desc = "Avec une petite pièce sur ce qui serait vendu.",
        tip = "Écrit le niveau d'objet sur l'équipement de tes sacs, et marque d'une pièce les objets que Platyplus vendrait.",
    })
end

local function buildComfort(p)
    local c = p:Card("Groupes, duels et invocations")
    c:Switch({
        key = "acceptInvites",
        label = "Accepter les groupes des amis et de la guilde",
        tip = "Accepte automatiquement les invitations de groupe venant d'un ami ou d'un membre de ta guilde.",
    })
    c:Switch({
        key = "declineGuildInvites",
        label = "Refuser les invitations de guilde",
        tip = "Refuse automatiquement les invitations à rejoindre une guilde.",
    })
    c:Switch({
        key = "declineDuels",
        label = "Refuser les duels",
        tip = "Refuse automatiquement toute demande de duel.",
    })
    c:Switch({
        key = "acceptSummon",
        label = "Accepter les invocations",
        tip = "Accepte automatiquement les invocations (pierre de rencontre, démoniste...). "
            .. "Attention : tu seras téléporté sans confirmation.",
    })
    c:Switch({
        key = "acceptRes",
        label = "Accepter les résurrections",
        tip = "Accepte automatiquement les résurrections proposées par un autre joueur.",
    })

    c = p:Card("Interface et caméra")
    c:Switch({
        key = "hideErrors",
        label = "Masquer les messages d'erreur rouges",
        desc = "« Pas assez de rage », « Hors de portée »...",
        tip = "Cache les messages d'erreur rouges qui s'affichent au milieu de l'écran.",
    })
    c:Switch({
        key = "hideTalkingHead",
        label = "Masquer les têtes parlantes",
        tip = "Cache la fenêtre de dialogue animée (« tête parlante ») qui apparaît en haut de l'écran.",
    })
    c:Switch({
        key = "hideXpBar",
        label = "Masquer la barre d'expérience",
        desc = "Et celle de réputation, en bas de l'écran.",
        tip = "Cache les barres d'expérience et de réputation de Blizzard. L'XP reste lisible dans la barre d'infos "
            .. "de Platyplus (pourcentage, XP par heure, temps avant le niveau). Coupé, les barres reviennent tout de suite.",
    })
    c:Switch({
        key = "cameraZoom",
        label = "Régler le recul maximum de la caméra",
        tip = "Applique le facteur ci-dessous à la distance maximale de la caméra.",
    })
    c:Slider({
        key = "cameraZoomFactor",
        label = "Facteur de recul",
        min = 1, max = 2.6, step = 0.1,
        format = "%.1f",
        indent = 1,
        enabled = whenZoom,
        requires = "Nécessite « Régler le recul maximum de la caméra ».",
        tip = "Plus la valeur est grande, plus tu peux éloigner la caméra (2,6 = maximum du jeu).",
    })
end

---------------------------------------------------------------------------
-- Chat (Misc.lua : ns.Chat ; ChatPlus.lua : ns.ChatPlus)
---------------------------------------------------------------------------
local function whenSpam() return db("chatSpam") end
local function whenMemory() return db("chatHistory") or db("chatSentHistory") end

local function chatPlus() return ns.ChatPlus end

local function whenChatWindow() return db("chatWindow") end

local function buildChat(p)
    local c = p:Card("Fenêtre de chat Platyplus", "Remplace les fenêtres de chat du jeu par une fenêtre Platyplus : "
        .. "onglets Chat / Guilde / Groupe / Chuchot. / Canaux / Jeu (butin, expérience, système), recherche.")
    c:Switch({
        key = "chatWindow",
        label = "Utiliser la fenêtre de chat Platyplus",
        tip = "Les messages arrivent comme d'habitude (tes réglages de canaux du jeu restent valables) et s'affichent dans "
            .. "la fenêtre Platyplus, une bulle par message, le nom dans la couleur de sa classe, le texte en clair. "
            .. "L'onglet Chat montre ce que les joueurs disent, l'onglet Jeu le reste (butin, expérience, système). "
            .. "Tire le bandeau pour la déplacer, le coin en bas à droite pour la redimensionner. "
            .. "Clic sur l'heure d'un message : le copier. La zone de saisie reste celle du jeu (Entrée pour écrire). "
            .. "Coupé : les fenêtres de chat du jeu reviennent.",
    })
    c:Switch({
        key = "chatWinTwoLines",
        label = "Messages façon messagerie",
        desc = "« Nom : texte » sur une ligne, une barre de la couleur du canal à gauche, canal et heure en petit à droite. Tes messages et les chuchotements sur un fond teinté.",
        indent = 1,
        enabled = whenChatWindow,
        requires = "Nécessite « Utiliser la fenêtre de chat Platyplus ».",
        tip = "Coché : le nom en couleur puis le texte, sans bulle ; les messages qui se suivent du même joueur "
            .. "(moins d'une minute) se resserrent, sans répéter l'heure. Clic sur l'heure ou clic droit sur le message : copier. "
            .. "Coupé : une ligne brute par message (« 15:27 [Guilde] Bob : salut »).",
    })
    c:Switch({
        key = "chatWinChannelText",
        label = "Texte dans la couleur du canal",
        desc = "Comme le chat du jeu : vert pour la guilde, bleu pour le groupe...",
        indent = 1,
        enabled = whenChatWindow,
        requires = "Nécessite « Utiliser la fenêtre de chat Platyplus ».",
        tip = "Coupé : le texte des messages est en clair, seul le [canal] prend sa couleur. "
            .. "Coché : le texte aussi, comme dans le chat du jeu.",
    })
    c:Slider({
        key = "chatWinFontSize",
        label = "Taille du texte",
        min = 10, max = 18, step = 1,
        format = pixels,
        indent = 1,
        enabled = whenChatWindow,
        requires = "Nécessite « Utiliser la fenêtre de chat Platyplus ».",
        tip = "Taille des messages dans la fenêtre de chat Platyplus.",
    })
    c:Slider({
        key = "chatWinAlpha",
        label = "Opacité du fond",
        min = 0.2, max = 1, step = 0.05,
        format = percent,
        indent = 1,
        enabled = whenChatWindow,
        requires = "Nécessite « Utiliser la fenêtre de chat Platyplus ».",
        tip = "100 % : fond opaque. Plus bas : on voit le jeu à travers.",
    })
    c:Buttons({
        {
            text = "Remettre la fenêtre en place", width = 230,
            tip = "Replace la fenêtre de chat Platyplus par-dessus l'emplacement du chat du jeu.",
            onClick = function() call("ChatWindow", "ResetPosition", "fenêtre de chat indisponible") end,
        },
    })

    c = p:Card("Traducteur", "Traduit le chat des joueurs étrangers avec une petite IA qui tourne sur ton PC "
        .. "(programme « Traducteur Platyplus », à lancer à côté du jeu).")
    c:Switch({
        key = "tradChatLog",
        label = "Lien [FR] pour traduire",
        desc = "Au bout des messages en langue étrangère : un clic sur [FR] et la traduction s'affiche.",
        tip = "Un add-on n'a ni Internet ni IA : la traduction est faite par le programme Traducteur Platyplus "
            .. "(dossier Platyplus\\Traducteur), qui s'affiche par-dessus le jeu. Clic sur [FR] : une fine bande de "
            .. "couleurs apparaît une demi-seconde en haut à gauche de l'écran, le programme la lit et traduit. "
            .. "Clic droit sur [FR] : le message dans une zone à copier (Ctrl+C), si la bande ne passe pas. Dans le jeu, "
            .. "Ctrl+Entrée ouvre une zone où tu écris en français : la traduction est copiée, colle-la dans le "
            .. "chat avec Ctrl+V. Pas de lien sur les messages protégés par le jeu (en instance).",
    })
    c:Buttons({
        {
            text = "État du journal", width = 160,
            tip = "Dit dans le chat si le journal du chat est allumé.",
            onClick = function() if ns.Trad then ns:Print("traducteur :", ns.Trad:Status()) end end,
        },
    })

    c = p:Card("Apparence", "Les fenêtres de chat du jeu (quand la fenêtre Platyplus est coupée) et la zone de saisie, "
        .. "aux couleurs de Platyplus.")
    c:Switch({
        key = "chatSkin",
        label = "Look Platyplus",
        desc = "Fond uni, onglets plats, zone de saisie sombre.",
        tip = "Fond uni sans les bords arrondis (sa couleur et sa transparence restent celles réglées dans le jeu), onglets "
            .. "plats avec un trait bleu sous celui qui est actif, zone de saisie sombre bordée de bleu. Coupé : le chat "
            .. "redevient exactement comme avant.",
    })

    c = p:Card("Lisibilité")
    c:Switch({
        key = "chatTimestamps",
        label = "L'heure devant chaque message",
        desc = "« 15:27 » au début de chaque ligne.",
        tip = "Allume l'horodatage du jeu (format 24 h). Ta valeur d'avant est gardée et remise si tu coupes. Tu peux choisir "
            .. "un autre format dans les options du jeu (Social) : Platyplus ne le change plus ensuite.",
    })
    c:Switch({
        key = "chatClassColors",
        label = "Noms colorés selon la classe",
        desc = "Dans tous les canaux.",
        tip = "Allume la couleur de classe des noms dans tout le chat (réglage du jeu). Ta valeur d'avant est remise si tu "
            .. "coupes.",
    })
    c:Switch({
        key = "chatMentions",
        label = "Ton nom surligné, avec un son",
        desc = "Quand quelqu'un écrit ton nom (canaux, groupe, guilde...).",
        tip = "Ton nom apparaît en jaune dans le message, un petit son est joué (au plus toutes les 3 secondes) et l'icône "
            .. "du jeu clignote dans la barre des tâches si tu es sur une autre fenêtre. Les chuchotements ont déjà leur "
            .. "son dans le jeu.",
    })
    c:Switch({
        key = "chatShortChannels",
        label = "Noms de canaux courts",
        desc = "« [1. Général - Zone] » devient « [1] », « [Guilde] » devient « [G] ».",
        tip = "Raccourcit le nom des canaux devant chaque message : numéro seul pour les canaux publics, G (guilde), "
            .. "O (officiers), Gr (groupe), R (raid), AR (avertissement de raid), I (instance).",
    })
    c:Switch({
        key = "chatLinks",
        label = "Liens web cliquables",
        desc = "Un clic ouvre le lien, prêt à copier (Ctrl+C).",
        tip = "Les adresses web écrites dans le chat (https://..., www....) deviennent des liens bleus. Un clic ouvre une "
            .. "petite fenêtre avec le lien déjà sélectionné : Ctrl+C pour le copier. Les messages protégés par le jeu "
            .. "(instances, combats de boss) ne sont jamais touchés.",
    })

    c = p:Card("Mémoire", "Ne plus perdre le chat à chaque /reload ou déconnexion.")
    c:Switch({
        key = "chatHistory",
        label = "Garder les derniers messages",
        desc = "Les 100 dernières lignes de chaque fenêtre, pour la session suivante.",
        tip = "Au /reload ou à la reconnexion, les dernières lignes de chaque fenêtre de chat reviennent (un peu plus "
            .. "pâles), suivies de « fin de la session précédente ». Gardé pour chaque personnage. Les messages protégés "
            .. "par le jeu ne sont jamais gardés.",
    })
    c:Switch({
        key = "chatSentHistory",
        label = "Flèches haut / bas : ce que tu as tapé",
        desc = "Sans Alt, et gardé d'une session à l'autre.",
        tip = "Dans la zone de saisie, les flèches haut et bas remontent les messages et commandes que tu as déjà "
            .. "envoyés (les 32 derniers), même après un /reload. Coupé : il faut Alt + flèches, comme dans le jeu de base.",
    })
    c:Info({
        label = "Gardé pour ce personnage",
        text = function()
            local cp = chatPlus()
            if not (cp and cp.Memory) then return "?" end
            local lines, sent = cp.Memory:Count()
            return ns.Tf("%d ligne(s) de chat, %d ligne(s) tapée(s)", lines, sent)
        end,
        enabled = whenMemory,
    })
    c:Buttons({
        {
            text = "Effacer l'historique", width = 190,
            confirm = "Clique encore pour confirmer",
            tip = "Oublie les lignes de chat et ce que tu as tapé, gardés pour ce personnage (ce qui est à l'écran reste).",
            onClick = function()
                local cp = chatPlus()
                if cp and cp.Memory then cp.Memory:Clear() end
                ns:Print("historique du chat effacé pour ce personnage")
            end,
        },
    })

    c = p:Card("Anti-spam", "Masque ce qui encombre les canaux publics. Jamais tes amis, ta guilde, ton groupe "
        .. "ni les MJ.")
    c:Switch({
        key = "chatSpam",
        label = "Masquer le spam",
        desc = "Messages répétés et annonces de vente d'or.",
        tip = "Masque un message déjà envoyé par le même joueur dans les 2 dernières minutes (canaux, /dire, /crier), les "
            .. "annonces de vente d'or (avec un site web ou un prix en vraie monnaie), et les messages qui contiennent "
            .. "un de tes mots (ci-dessous). « Voir les messages masqués » montre ce qui a été caché.",
    })
    c:Info({
        label = "Tes mots à masquer",
        text = function()
            local words = db("chatFilterWords")
            if type(words) ~= "table" or #words == 0 then return "aucun" end
            return table.concat(words, ", ")
        end,
        tip = "Ajouter un mot : /pp spam ajouter MOT ; le retirer : /pp spam retirer MOT. Sans tenir compte des majuscules.",
        enabled = whenSpam,
    })
    c:Info({
        label = "Masqués depuis le chargement",
        text = function()
            local cp = chatPlus()
            return tostring(cp and cp.Spam and cp.Spam.hidden or 0)
        end,
        enabled = whenSpam,
    })
    c:Buttons({
        {
            text = "Voir les messages masqués", width = 230,
            tip = "Ouvre la liste des derniers messages masqués (heure, joueur, raison), pour vérifier qu'aucun message "
                .. "utile n'a été caché.",
            onClick = function()
                local cp = chatPlus()
                if cp and cp.Spam then cp.Spam:ShowRecent() end
            end,
        },
    })

    c = p:Card("Copie")
    c:Switch({
        key = "chatCopyButton",
        label = "Bouton « copier le chat »",
        desc = "Le petit logo en haut à droite de la fenêtre de chat.",
        tip = "Ouvre les dernières lignes de la fenêtre de chat dans une zone de texte, pour les copier (Ctrl+C). "
            .. "Aussi : /pp copier.",
    })
    c:Buttons({
        {
            text = "Copier le chat", width = 160,
            tip = "Ouvre les dernières lignes du chat dans une zone de texte (Ctrl+C pour copier).",
            onClick = function() call("Chat", "CopyChat", "copie du chat indisponible") end,
        },
    })
end

---------------------------------------------------------------------------
-- Fenêtres Platyplus : dialogues des PNJ et sacs
---------------------------------------------------------------------------
local function whenQuestWindow() return db("questWindow") end
local function whenBagWindow() return db("bagWindow") end

local function buildWindows(p)
    local c = p:Card("Fenêtre de quête", "Ce que te disent les PNJ dans une fenêtre Platyplus : discussion, quête "
        .. "proposée, objets à rapporter, récompenses. Texte en grand, déplaçable.")
    c:Switch({
        key = "questWindow",
        label = "Utiliser la fenêtre de quête Platyplus",
        desc = "Tire son bandeau pour la déplacer : elle s'ouvrira ensuite toujours à cet endroit.",
        tip = "Exemple : tu parles au garde, ses options et ses quêtes s'affichent en lignes cliquables ; tu choisis une "
            .. "quête, son texte, ses objectifs et ses récompenses s'affichent en grand avec les boutons Accepter / "
            .. "Refuser. Les récompenses sont des tuiles colorées selon leur rareté : survol pour l'infobulle, clic pour "
            .. "choisir, double-clic pour choisir et rendre la quête. Ta touche Platyplus et Échap marchent comme avant. "
            .. "Coupé : les fenêtres du jeu reviennent.",
    })
    c:Slider({
        key = "questWinScale",
        label = "Taille",
        min = 0.8, max = 1.6, step = 0.05,
        format = percent,
        indent = 1,
        enabled = whenQuestWindow,
        requires = "Nécessite « Utiliser la fenêtre de quête Platyplus ».",
        tip = "100 % : texte de 15 pixels, déjà plus grand que dans la fenêtre du jeu. 120 % : tout un cinquième plus grand.",
    })
    c:Buttons({
        {
            text = "Remettre la fenêtre en place", width = 230,
            enabled = whenQuestWindow,
            requires = "Nécessite « Utiliser la fenêtre de quête Platyplus ».",
            tip = "Replace la fenêtre de quête à gauche de l'écran, comme au premier jour.",
            onClick = function() call("QuestWindow", "ResetPosition", "fenêtre de quête indisponible") end,
        },
    })

    c = p:Card("Sacs", "Tous tes sacs dans une seule fenêtre Platyplus, avec recherche, tri, argent et places libres.")
    c:Switch({
        key = "bagWindow",
        label = "Utiliser les sacs Platyplus",
        desc = "S'ouvre avec la touche des sacs, chez le marchand, à la banque ou au courrier.",
        tip = "Tes sacs à la suite dans une grille. Les cases sont celles du jeu : clic droit pour utiliser ou vendre, "
            .. "glisser pour déplacer, Maj-clic pour lier ou partager une pile. Exemple : tape « lin » dans Chercher, "
            .. "seules tes Étoffes de lin restent allumées. Tire le bandeau pour déplacer la fenêtre. "
            .. "Coupé : les sacs du jeu reviennent.",
    })
    c:Slider({
        key = "bagWinScale",
        label = "Taille",
        min = 0.7, max = 1.6, step = 0.05,
        format = percent,
        indent = 1,
        enabled = whenBagWindow,
        requires = "Nécessite « Utiliser les sacs Platyplus ».",
        tip = "100 % : cases de 40 pixels (celles du jeu en font 37).",
    })
    c:Slider({
        key = "bagWinColumns",
        label = "Cases par ligne",
        min = 6, max = 20, step = 1,
        format = "%d",
        indent = 1,
        enabled = whenBagWindow,
        requires = "Nécessite « Utiliser les sacs Platyplus ».",
        tip = "Exemple : 10 cases par ligne et 80 places en tout font 8 lignes.",
    })
    c:Switch({
        key = "bagWinGroup",
        label = "Ranger par type",
        desc = "Quête, consommables, artisanat, équipement, divers et poubelle, chacun sous son titre.",
        indent = 1,
        enabled = whenBagWindow,
        requires = "Nécessite « Utiliser les sacs Platyplus ».",
        tip = "Exemple : ton Pain de seigle et tes Potions de soins s'affichent ensemble sous Consommables, ton Étoffe "
            .. "de lin sous Artisanat, tes Bottes sous Équipement. Sous Poubelle : l'Os brisé gris et tout ce que la vente "
            .. "automatique vendra chez le marchand. Tes places vides sont à la fin, sous Libre. Seul l'affichage change : "
            .. "les objets ne bougent pas dans tes sacs (le bouton Trier range toujours les sacs du jeu). "
            .. "Coupé : tes sacs à la suite, case par case.",
    })
    c:Buttons({
        {
            text = "Remettre la fenêtre en place", width = 230,
            enabled = whenBagWindow,
            requires = "Nécessite « Utiliser les sacs Platyplus ».",
            tip = "Replace la fenêtre des sacs en bas à droite de l'écran.",
            onClick = function() call("BagWindow", "ResetPosition", "sacs indisponibles") end,
        },
    })

    c = p:Card("Fenêtre du personnage", "Ce que tu ouvres avec C : équipement, caractéristiques, réputation, "
        .. "compétences, JcJ, dans une fenêtre Platyplus à onglets.")
    c:Switch({
        key = "charWindow",
        label = "Utiliser la fenêtre du personnage Platyplus",
        desc = "C, U et les autres touches du jeu ouvrent le bon onglet ; la même touche ou Échap la referme.",
        tip = "Personnage : tes cases d'équipement (celles du jeu : clic droit sur un bijou pour l'utiliser, Alt pour les "
            .. "objets de rechange), le niveau d'objet sur chaque case, ton personnage en 3D à tourner à la souris et tes "
            .. "caractéristiques calculées par le jeu (survol : le détail). Réputation : clic sur une faction pour la suivre "
            .. "sur la barre d'expérience ou lui déclarer la guerre. Coupé : la fenêtre du jeu revient.",
    })
    c:Slider({
        key = "charWinScale",
        label = "Taille",
        min = 0.7, max = 1.5, step = 0.05,
        format = percent,
        indent = 1,
        enabled = function() return db("charWindow") end,
        requires = "Nécessite « Utiliser la fenêtre du personnage Platyplus ».",
        tip = "100 % : la fenêtre fait 920 points de large, texte de 13 à 14 pixels.",
    })
    c:Buttons({
        {
            text = "Remettre la fenêtre en place", width = 230,
            enabled = function() return db("charWindow") end,
            requires = "Nécessite « Utiliser la fenêtre du personnage Platyplus ».",
            tip = "Replace la fenêtre du personnage à gauche de l'écran.",
            onClick = function() call("CharWindow", "ResetPosition", "fenêtre du personnage indisponible") end,
        },
    })

    c = p:Card("Page de quête du journal", "Le journal de quêtes de la carte du monde du jeu.")
    c:Switch({
        key = "mapQuestPage",
        label = "Page de quête Platyplus",
        tip = "Quand tu ouvres une quête dans le journal à côté de la carte : d'abord ce qu'il faut faire (le but et "
            .. "chaque objectif avec sa progression), puis les récompenses, et l'histoire repliée en bas (clic pour la "
            .. "déplier). Fond sombre, texte clair. Éteint : la page du jeu, sur parchemin.",
    })
end

---------------------------------------------------------------------------
-- 6. Icône & infos
---------------------------------------------------------------------------
local function buildLauncher(p)
    local c = p:Card("Icône Platyplus", "Une icône posée où tu veux à l'écran (hors minicarte). Clic gauche : cette "
        .. "fenêtre. Clic droit : un menu pour allumer ou couper les fonctions. Glisse-la pour la déplacer.")
    c:Switch({
        key = "launcher",
        label = "Afficher l'icône",
        tip = "Affiche l'icône de Platyplus à l'écran. Coupée, /pp ouvre toujours cette fenêtre.",
    })
    c:Switch({
        key = "launcherLocked",
        label = "Verrouiller sa position",
        indent = 1,
        enabled = whenLauncher,
        requires = "Nécessite « Afficher l'icône ».",
        tip = "Empêche de déplacer l'icône par erreur. Déverrouillée, glisse-la où tu veux.",
    })
    c:Slider({
        key = "launcherScale",
        label = "Taille",
        min = 0.6, max = 2, step = 0.05,
        format = percent,
        indent = 1,
        enabled = whenLauncher,
        requires = "Nécessite « Afficher l'icône ».",
        tip = "Agrandit ou réduit l'icône et sa barre d'infos (100 % = taille normale).",
    })
    c:Buttons({
        {
            text = "Remettre l'icône en place", width = 210,
            tip = "Replace l'icône à son emplacement par défaut (en haut à droite).",
            onClick = function()
                if not call("Launcher", "ResetPosition") then
                    for _, key in ipairs({ "launcherPoint", "launcherX", "launcherY" }) do ns:Reset(key) end
                end
            end,
        },
    })

    c = p:Card("Barre d'infos", "Des infos utiles à côté de l'icône, mises à jour sans rien coûter en jeu.")
    c:Switch({
        key = "dock",
        label = "Afficher la barre d'infos",
        enabled = whenLauncher,
        requires = "Nécessite « Afficher l'icône ».",
        tip = "Affiche une petite barre d'informations collée à l'icône de Platyplus.",
    })
    local items = {
        { "dockFps", "Images par seconde", "Fluidité du jeu (images par seconde)." },
        { "dockLatency", "Latence", "Temps de réponse du serveur, en millisecondes." },
        { "dockGold", "Or", "L'argent de ce personnage." },
        { "dockBags", "Places libres dans les sacs", "Nombre d'emplacements encore libres." },
        { "dockDurability", "Durabilité", "État de l'équipement le plus abîmé." },
        { "dockIlvl", "Niveau d'objet", "Niveau d'objet moyen de ton équipement porté (clic : fiche du personnage)." },
        { "dockCoords", "Coordonnées", "Ta position sur la carte de la zone." },
        { "dockXp", "Expérience", "Pourcentage du niveau. Clic sur la valeur : XP par heure, temps avant le niveau, "
            .. "monstres restants. Survol : tout le détail de la session." },
    }
    for _, it in ipairs(items) do
        c:Switch({
            key = it[1],
            label = it[2],
            indent = 1,
            enabled = whenDock,
            requires = "Nécessite « Afficher la barre d'infos ».",
            tip = it[3],
        })
    end
end

---------------------------------------------------------------------------
-- Donjons : le journal des donjons (DungeonJournal d'Exehn, dossier DungeonJournal/ ; DungeonJournalPlus.lua)
---------------------------------------------------------------------------
local function buildDungeons(p)
    local D, P = ns.Dungeon, ns.DungeonPlus
    -- surcharge : l'addon DungeonJournal d'Exehn installé à part, avec la liste, « À ton niveau » et le style de
    -- Platyplus posés dessus (DungeonJournalPlus.lua / DungeonJournalSkin.lua) : les trois réglages agissent
    local overlay = P and P.Overlay and P.Overlay() or false
    if overlay then
        -- (une mise à jour de l'addon a retiré ce sur quoi Platyplus se branche : dit ici, pas par une erreur)
        local missing = P.Health and P.attached and P.Health() or {}
        if #missing > 0 then p:Note(P.HealthText(missing), "warn") end
        if D and D.PpStandby then
            p:Note("L'addon DungeonJournal séparé est activé : c'est lui qui tourne, avec la liste des donjons, "
                .. "« À ton niveau » et le style de Platyplus posés dessus. Le journal intégré à Platyplus reste "
                .. "éteint et garde une copie de ses réglages, de tes favoris et de ta progression : désactive "
                .. "DungeonJournal dans la liste des addons (écran de choix du personnage) puis relance le jeu pour "
                .. "revenir au journal intégré.", "info")
        else
            p:Note("Le journal des donjons est celui de l'addon DungeonJournal d'Exehn, installé à part. Platyplus "
                .. "l'ouvre d'ici, depuis le menu de l'icône et avec /pp donjons, et pose dessus sa liste des "
                .. "donjons, « À ton niveau » et son style, sans rien changer dans l'addon.", "info")
        end
    elseif D and D.PpStandby then
        p:Note("L'addon DungeonJournal séparé est activé : c'est lui qui tourne, et la copie de Platyplus reste "
            .. "éteinte. Platyplus garde une copie de ses réglages, de tes favoris et de ta progression : désactive "
            .. "DungeonJournal dans la liste des addons (écran de choix du personnage) puis relance le jeu, et tu "
            .. "retrouves tout dans le journal de Platyplus.", "warn")
        p:Card("Journal des donjons"):Buttons({
            {
                text = "Ouvrir le journal", width = 160, primary = true,
                tip = "Ouvre le journal de l'addon séparé (aussi : /dj).",
                onClick = function() if P then P.Toggle() end end,
            },
        })
        return
    end
    if not D and not overlay then
        -- version publique : le dossier DungeonJournal n'est pas inclus
        if P and P.Standalone and P.Standalone() then
            p:Note("Le journal des donjons est celui de l'addon DungeonJournal d'Exehn, installé à part : Platyplus "
                .. "l'ouvre d'ici, depuis le menu de l'icône et avec /pp donjons.", "info")
            p:Card("Journal des donjons"):Buttons({
                {
                    text = "Ouvrir le journal", width = 160, primary = true,
                    tip = "Ouvre le journal de l'addon DungeonJournal (aussi : /dj).",
                    onClick = function() P.Toggle() end,
                },
            })
        else
            p:Note("Le journal des donjons n'est pas inclus dans cette version de Platyplus. Installe l'addon "
                .. "DungeonJournal d'Exehn depuis CurseForge : Platyplus l'ouvrira ensuite depuis cet onglet, depuis "
                .. "le menu de l'icône et avec /pp donjons, et posera dessus sa liste des donjons, « À ton niveau » "
                .. "et son style.", "info")
        end
        return
    end
    if not overlay and not (P and P.Available and P.Available()) then
        p:Note("Le journal des donjons est introuvable : le dossier Platyplus\\DungeonJournal manque ou n'a pas pu "
            .. "se charger.", "warn")
        return
    end

    local c = p:Card("Journal des donjons", overlay
        and ("Chaque donjon : ses boss et leur butin, ses quêtes (où les prendre, les suites de quêtes, les "
            .. "récompenses), son plan et le chemin jusqu'à l'entrée. Ouvrir : /dj, /pp donjons, le menu de l'icône "
            .. "Platyplus, ou la touche de l'addon DungeonJournal.")
        or ("Chaque donjon : ses boss et leur butin, ses quêtes (où les prendre, "
        .. "les suites de quêtes, les récompenses), son plan et le chemin jusqu'à l'entrée. Touche : Raccourcis > "
        .. "Journal des donjons. Aussi : /dj, /pp donjons, ou le menu de l'icône Platyplus."))
    c:Switch({
        key = "dungeonList",
        label = "Liste des donjons à gauche",
        tip = "Une colonne collée au journal, avec tous les donjons dans l'ordre des niveaux : un clic ouvre un "
            .. "donjon, depuis n'importe quelle page. La tranche de niveau est en couleur selon ton niveau (vert : "
            .. "à ton niveau, or : bientôt, rouge : trop dur, gris : dépassé), et à droite tes quêtes faites "
            .. "(par exemple 2/7, ✓ quand tout est fait). « Accueil » ramène aux grandes cartes.",
    })
    c:Switch({
        key = "dungeonFit",
        label = "« À ton niveau » sur l'accueil",
        tip = "Sur les grandes cartes de l'accueil, la tranche de niveau prend la même couleur et une pastille "
            .. "« À ton niveau » ou « Bientôt » s'ajoute. La première fois que tu ouvres l'accueil, il défile "
            .. "jusqu'aux donjons de ton niveau.",
    })
    c:Switch({
        key = "dungeonSkin",
        label = "Style Platyplus",
        tip = "Le journal aux couleurs de Platyplus : fond sombre arrondi, liserés fins, sélection en bleu, texte "
            .. "clair, et plus de parchemin sous les quêtes. Rien ne bouge : mêmes pages, mêmes boutons. Éteint : "
            .. "le look d'origine du journal (pierre, bronze et or). Prend effet après /reload.",
    })
    c:Buttons({
        {
            text = "Ouvrir le journal", width = 160, primary = true,
            tip = "Ouvre ou ferme le journal des donjons.",
            onClick = function() P.Toggle() end,
        },
        {
            text = "Ses réglages", width = 130,
            tip = "La fenêtre de réglages du journal lui-même : bouton de la minicarte, infobulles des objets, "
                .. "quêtes de classe et de métier, mode RPG... (aussi : /dj options).",
            onClick = function() if not P.OpenOptions() then ns:Print("réglages du journal indisponibles") end end,
        },
        {
            text = "/reload", width = 100,
            tip = "Recharge l'interface, pour appliquer « Style Platyplus ».",
            onClick = function() ReloadUI() end,
        },
    })

    if overlay then
        c = p:Card("À propos", "DungeonJournal, par Exehn : le journal, ses données (boss, butin, quêtes, plans, routes) et ses images viennent de son addon, installé à part ; Platyplus n'en embarque rien. Platyplus y ajoute la liste de gauche, « À ton niveau » et son style en passant derrière lui, sans rien modifier dans l'addon : éteins les trois réglages (puis /reload) et il retrouve son look d'origine.")
    else
        c = p:Card("À propos", ns.Tf("DungeonJournal %s, par Exehn : le journal, ses données (boss, butin, quêtes, plans, routes) et ses images. Platyplus l'intègre tel quel (dev/make_dungeonjournal.py) et y ajoute la liste de gauche, « À ton niveau » et son style. Tes réglages, favoris et progression du journal sont gardés par Platyplus.", tostring(D.PpVersion or "")))
    end
    c:Buttons({
        {
            text = "État du journal", width = 160,
            tip = "Écrit dans le chat ce que fait le journal (aussi : /pp donjons etat).",
            onClick = function()
                ns:Print("journal des donjons :")
                for _, line in ipairs(P:Status()) do print("  " .. line) end
            end,
        },
    })
end

---------------------------------------------------------------------------
-- 7. Réglages du jeu
---------------------------------------------------------------------------
local function buildGame(p)
    local GS = ns.GameSettings
    local c = p:Card("Réglages recommandés", "Quelques réglages du jeu rendent le jeu à la touche plus confortable. "
        .. "Platyplus n'y touche que si tu le demandes : tes valeurs d'origine sont gardées, et « Rétablir » les remet.")
    c:Buttons({
        {
            text = "Tout appliquer", width = 160, primary = true,
            tip = "Active tous les réglages de la liste ci-dessous que ton client connaît.",
            onClick = function() call("GameSettings", "ApplyRecommended", "module indisponible") end,
        },
        {
            text = "Rétablir mes anciens réglages", width = 250,
            confirm = "Clique encore pour confirmer",
            tip = "Remet chaque réglage du jeu à la valeur qu'il avait avant que Platyplus le change.",
            onClick = function() call("GameSettings", "RestoreAll", "module indisponible") end,
        },
    })

    c = p:Card("Détail", "Un réglage que ton client ne connaît pas est grisé.")
    if not (GS and GS.list) then
        c:Help("Module indisponible.")
        return
    end
    for _, entry in ipairs(GS.list) do
        c:Switch({
            label = entry.label,
            tip = entry.tip,
            get = function() return GS:IsOn(entry) end,
            set = function(on) GS:Set(entry, on) end,
            enabled = function() return GS:Available(entry) end,
            requires = "Ce réglage n'existe pas sur ton client.",
        })
    end
end

---------------------------------------------------------------------------
-- Fenêtre de menace (onglet Combat, après les cartes de buildResources)
---------------------------------------------------------------------------
local function whenThreat() return db("threatWindow") end

local function buildThreat(p)
    local c = p:Card("Fenêtre de menace", "Tous les mobs en combat avec ton groupe, et qui les tient.")
    c:Switch({
        key = "threatWindow", label = "Afficher la fenêtre de menace",
        desc = "Une ligne par mob : nom, vie, qui le tient, ta menace. Vert : tu l'as, orange : tu le perds, rouge : tu ne l'as plus, "
            .. "bleu : un autre tank le tient, gris : il n'a pas de cible. DPS : rouge = il te tape (compteur « N sur toi »).",
        tip = "Liste les mobs en combat (plates, boss, cibles de ton groupe). Les couleurs sont celles des plates "
            .. "(onglet Plates). En donjon, le jeu cache certaines valeurs aux addons : la couleur reste juste, "
            .. "mais le tri par vie et certains chiffres peuvent manquer. Pas de clic pour cibler : le jeu l'interdit en combat.",
    })
    c:Switch({
        key = "threatAuto", label = "Seulement en combat", indent = 1, enabled = whenThreat,
        requires = "Nécessite « Afficher la fenêtre de menace ».",
        desc = "Elle apparaît au début du combat et disparaît en fondu 3 s après la fin.",
        tip = "Décoché, la fenêtre reste affichée en permanence.",
    })
    c:Switch({
        key = "threatGroupOnly", label = "Seulement en groupe", indent = 1, enabled = whenThreat,
        requires = "Nécessite « Afficher la fenêtre de menace ».",
        tip = "Seul, tu sais déjà que les mobs te tapent : la fenêtre ne s'affiche pas.",
    })
    c:Dropdown({
        key = "threatSort", label = "Ordre des lignes", indent = 1, enabled = whenThreat,
        requires = "Nécessite « Afficher la fenêtre de menace ».",
        options = {
            { value = "danger", text = "Les plus dangereux d'abord" },
            { value = "health", text = "Vie la plus basse d'abord" },
            { value = "arrival", text = "Ordre d'arrivée" },
        },
        tip = "Tank : en haut, les mobs que tu n'as pas ou que tu perds. DPS : en haut, ceux qui te tapent. "
            .. "Par vie : impossible quand le jeu cache la vie des mobs (ordre d'arrivée dans ce cas).",
    })
    c:Switch({
        key = "threatOnlyLost", label = "Tank : seulement les mobs que je n'ai pas", indent = 1, enabled = whenThreat,
        requires = "Nécessite « Afficher la fenêtre de menace ».",
        tip = "Cache les mobs que tu tiens déjà ; la fenêtre ne montre que ce qui demande ton attention.",
    })
    c:Slider({
        key = "threatRows", label = "Lignes au maximum", indent = 1, min = 3, max = 12, step = 1, format = "%d",
        enabled = whenThreat, requires = "Nécessite « Afficher la fenêtre de menace ».",
    })
    c:Switch({
        key = "threatFlash", label = "Clignoter quand un mob m'échappe", indent = 1, enabled = whenThreat,
        requires = "Nécessite « Afficher la fenêtre de menace ».",
        desc = "Tank : un éclat rouge sur la ligne d'un mob qui te tapait et tape maintenant quelqu'un d'autre. Sans son.",
    })
    c:Switch({
        key = "threatLocked", label = "Verrouiller la position", indent = 1, enabled = whenThreat,
        requires = "Nécessite « Afficher la fenêtre de menace ».",
        desc = "Décoche pour déplacer la fenêtre en tirant son bandeau.",
    })
    c:Slider({
        key = "threatScale", label = "Taille de la fenêtre", indent = 1, min = 0.7, max = 1.5, step = 0.05,
        format = function(v) return math.floor(v * 100 + 0.5) .. " %" end,
        enabled = whenThreat, requires = "Nécessite « Afficher la fenêtre de menace ».",
    })
    c:Buttons({
        { text = "Aperçu", width = 110, enabled = whenThreat,
          onClick = function() call("Threat", "Test", "fenêtre de menace indisponible") end,
          tip = "Affiche des mobs factices pour régler la position ; recliquer les retire." },
        { text = "Remettre en place", width = 160,
          onClick = function() if ns.Threat then ns.Threat:Command("reset") end end },
    })
end

---------------------------------------------------------------------------
-- 8. Avancé
---------------------------------------------------------------------------
local COMMANDS = {
    { "/pp", "ouvre ou ferme cette fenêtre (aussi /pp config)" },
    { "/pp help", "liste toutes les commandes dans le chat" },
    { "/pp loot [on|off]", "loot instantané" },
    { "/pp float [on|off]", "flux à l'écran" },
    { "/pp interact [on|off]", "interaction rapide" },
    { "/pp dialog [on|off]", "la touche valide quêtes et dialogues" },
    { "/pp gossip [on|off]", "la touche choisit la 1re option de dialogue" },
    { "/pp junk [on|off]", "vente automatique des objets gris" },
    { "/pp etincelles [on|off]", "état des étincelles (ce que Platyplus voit autour de toi) | toutes allumées / coupées" },
    { "/pp preset [restore]", "réglages du jeu recommandés | remet les anciens" },
    { "/pp eat [TOUCHE|off|debug]", "touche pour manger (potion de soins en combat) | changer, couper | diagnostic" },
    { "/pp drink [TOUCHE|off]", "touche pour boire (potion de mana en combat) | changer, couper (aussi /pp boire)" },
    { "/pp donjons [etat|options]", "journal des donjons : l'ouvre | ce qu'il fait | ses propres réglages (aussi /dj)" },
    { "/pp bienvenue", "relance la visite guidée de Platyplus (aussi /pp tuto)" },
    { "/pp mode [recommande|complet|immersif|minimal]", "mode prêt à l'emploi : voir le mode actuel | en choisir un" },
    { "/pp copier", "ouvre le chat dans une zone de texte à copier (Ctrl+C)" },
    { "/pp chat", "état du chat amélioré (look, mémoire, anti-spam)" },
    { "/pp spam [ajouter|retirer MOT|voir]", "mots masqués par l'anti-spam | messages masqués" },
    { "/pp swing [on|off]", "aperçu de la barre de coups blancs | la montre ou la cache" },
    { "/pp proc [on|off]", "aperçu de l'alerte de proc, sorts surveillés (ta classe, ajoutés, ignorés) et leurs touches | l'active ou la coupe" },
    { "/pp buffs", "rappel de buffs : état (Cri de guerre, buffs de tes alliés) et aperçu" },
    { "/pp mob", "contrôles du mob ciblé (étourdir, ralentir...) et leur rythme" },
    { "/pp plates [on|off|tank|dps|auto]", "plates des mobs : état de chaque plate | allume/éteint | rôle pour les couleurs" },
    { "/pp menace [on|off|test|reset]", "fenêtre de menace : tous les mobs en combat et qui les tient | allume/éteint | mobs factices | remise en place" },
    { "/pp jets [roll|demo|auto|on|off]", "fenêtre des jets de butin : dés de chaque joueur, objet par objet | onglet /roll | exemple | ouverture auto" },
    { "/pp healer [on|off|cible|auto]", "barre de mana de ton healer : aperçu | l'allume ou l'éteint | suivre ta cible | laisser le groupe choisir" },
    { "/pp demo", "montre le flux, la barre de coups blancs et les options d'un coup" },
    { "/pp perf", "mémoire et temps de calcul de Platyplus mesurés par le jeu" },
    { "/pp key TOUCHE", "change la touche (F, SHIFT-F, BUTTON4...)" },
    { "/pp sell", "vend maintenant (marchand ouvert)" },
    { "/pp list", "liste ce qui serait vendu" },
    { "/pp sort", "trie les sacs" },
    { "/pp move", "déplace le flux (retape pour valider)" },
    { "/pp test", "affiche des lignes de flux d'exemple" },
    { "/pp reset", "remet le flux à sa place par défaut" },
    { "/pp rows 1-12", "nombre de lignes du flux" },
    { "/pp time 1-15", "durée d'affichage du flux (secondes)" },
    { "/pp cvars", "affiche les réglages du jeu utiles" },
    { "/pp cvar NOM VALEUR", "modifie un réglage SoftTarget* ou autoLoot*" },
    { "/pp debug [on|off]", "messages de diagnostic dans le chat" },
    { "/pp langue [code|auto]", "langue de Platyplus : voir | changer (frFR, enUS, deDE, esES, itIT, ptBR, ruRU, auto)" },
}

local function buildAdvanced(p)
    local c = p:Card("Diagnostic")
    c:Switch({
        key = "debug",
        label = "Messages de diagnostic dans le chat",
        tip = "Affiche dans le chat des détails sur ce que fait Platyplus. Utile pour comprendre un comportement "
            .. "ou signaler un problème.",
    })
    c:Info({
        label = "Version",
        text = function()
            return W.Color("accent", "Platy") .. W.Color("gold", "plus") .. " " .. W.Color("dim", tostring(ns.version or "?"))
        end,
    })
    c:Buttons({
        {
            text = "Revoir la visite guidée", width = 220,
            tip = "Relance la visite montrée à la première installation : une page par grande fonction, avec ses "
                .. "réglages principaux (aussi : /pp bienvenue).",
            onClick = function() if ns.UI and ns.UI.ShowWelcome then ns.UI:ShowWelcome(1) end end,
        },
    })

    c = p:Card("Langue", "Langue des textes de Platyplus. Les textes pas encore traduits restent en anglais, ou en français à défaut.")
    c:Dropdown({
        key = "language",
        label = "Langue de Platyplus",
        desc = "Automatique = la langue de ton client WoW.",
        width = 200,
        options = function()
            local list = { { value = "auto", text = "Automatique (langue du jeu)" } }
            for _, l in ipairs(ns.LANGUAGES) do list[#list + 1] = { value = l.code, text = l.name } end
            return list
        end,
        tip = "Le choix est gardé tout de suite, mais les fenêtres déjà construites gardent l'ancienne langue : recharge l'interface (bouton ci-dessous ou /reload).",
    })
    c:Buttons({
        {
            text = "Recharger l'interface", width = 220,
            confirm = "Clique encore pour recharger",
            tip = "Recharge l'interface du jeu (/reload) pour appliquer la langue. Impossible en combat.",
            onClick = function()
                if InCombatLockdown and InCombatLockdown() then
                    ns:Print("impossible en combat : réessaie après le combat")
                else
                    ReloadUI()
                end
            end,
        },
    })

    c = p:Card("Commandes", "À taper dans le chat. /pp, /platyplus et /sf sont équivalents.")
    c:Commands(COMMANDS)

    c = p:Card("Réinitialisation", "Remet les réglages à leur valeur par défaut. Chaque bouton demande une confirmation : "
        .. "reclique dessus dans les 3 secondes.")
    c:Buttons({
        {
            text = "Tout réinitialiser (garder mes listes)", width = 280,
            confirm = "Clique encore pour confirmer",
            tip = "Remet tous les réglages à zéro (touche, loot, vente, confort...) "
                .. "mais conserve tes listes « Ne jamais vendre » et « Toujours vendre ».",
            onClick = function()
                W.CancelCapture()
                ns:ResetAll(true)
                ns:Print("réglages réinitialisés (listes conservées)")
            end,
        },
        {
            text = "Tout réinitialiser", width = 200, danger = true,
            confirm = "Clique encore pour confirmer",
            tip = "Remet absolument tout à zéro, y compris tes listes « Ne jamais vendre » et « Toujours vendre ».",
            onClick = function()
                W.CancelCapture()
                ns:ResetAll(false)
                ns:Print("tous les réglages et listes ont été réinitialisés")
            end,
        },
    })
end

---------------------------------------------------------------------------
-- Modes prêts à l'emploi (Core.lua : ns.MODES, ns:ApplyMode, ns:CurrentMode)
-- Pages.ModePicker : une tuile par mode sur 2 colonnes, celle du mode actuel surlignée, une ligne d'état dessous.
-- Un clic applique le mode ; si les réglages sont personnalisés, il faut recliquer dans les 3 s (rien n'est perdu
-- par erreur). Sert dans l'onglet « Modes » et dans la visite guidée (UIConfig). opts.base / opts.hover : couleur
-- des tuiles (sur une carte : C.field ; sur le fond de la visite : C.card).
---------------------------------------------------------------------------
local TILE_GAP, TILE_PAD, TILE_ICON, TILE_HEAD = 12, 14, 30, 22
local ARM_TIME = 3

-- hauteur d'un texte à la largeur du FontString (W.Measure lit la hauteur du texte déjà posé)
local function textHeight(fs, text)
    fs:SetText(text)
    return W.Measure(fs, text, fs:GetWidth() or 200)
end

local function paintTile(t)
    local C = W.C
    local active, armed = t.active, t.armed
    if active then
        t.bg:SetColor(C.accent, 0.14)
        t.stroke:SetColor(C.accent, 0.85)
    else
        t.bg:SetColor(t.hover and t.colors.hover or t.colors.base)
        t.stroke:SetColor(armed and C.gold or C.white, armed and 0.7 or (t.hover and 0.16 or 0.07))
    end
    t.badge:SetShown(active)
    W.TextColor(t.name, (active or t.hover) and C.white or C.text)
    if armed then
        t.desc:SetText(ns.T("Clique encore pour remplacer tes réglages actuels par ce mode."))
        W.TextColor(t.desc, C.gold)
    else
        t.desc:SetText(ns.T(t.mode.desc))
        W.TextColor(t.desc, C.dim)
    end
    if t.icon.SetDesaturation then t.icon:SetDesaturation((active or t.hover) and 0 or 0.35) end
end

function Pages.ModePicker(parent, width, opts)
    opts = opts or {}
    local C = W.C
    width = width or W.InnerWidth(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    f.noDivider = true
    f.topGap = 6
    local colors = { base = opts.base or C.field, hover = opts.hover or C.fieldHover }
    local controlled = {}
    for _, key in ipairs(ns.ModeKeys()) do controlled[key] = true end

    local cols = 2
    local tileW = floor((width - TILE_GAP * (cols - 1)) / cols)
    local textX = TILE_PAD + TILE_ICON + 12
    local textW = tileW - textX - TILE_PAD
    local armText = ns.T("Clique encore pour remplacer tes réglages actuels par ce mode.")
    local tileH = 2 * TILE_PAD + TILE_ICON
    f.tiles = {}

    local function disarm()
        for _, t in ipairs(f.tiles) do
            if t.armed then
                t.armed = nil
                paintTile(t)
            end
        end
    end

    for i, mode in ipairs(ns.MODES) do
        local t = CreateFrame("Button", nil, f)
        t.mode, t.colors = mode, colors
        t:SetWidth(tileW)
        t.bg = W.Round(t, "BACKGROUND", 1, 9)
        t.stroke = W.Stroke(t, "BORDER", 0, 9)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(TILE_ICON, TILE_ICON)
        t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", TILE_PAD, -TILE_PAD)
        if mode.icon == "logo" then
            t.icon:SetTexture(ns.LOGO)
        else
            t.icon:SetTexture(mode.icon)
            t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        t.badge = W.Text(t, "GameFontHighlightSmall", C.accent, "OVERLAY", 11)
        t.badge:SetPoint("TOPRIGHT", t, "TOPRIGHT", -TILE_PAD, -(TILE_PAD + 3))
        local actif = ns.T("Actif")
        t.badge:SetText(ns.Win and ns.Win.Upper and ns.Win.Upper(actif) or actif:upper())
        t.name = W.Text(t, "GameFontHighlight", C.text, "OVERLAY", 15)
        t.name:SetPoint("TOPLEFT", t, "TOPLEFT", textX, -(TILE_PAD + 1))
        t.name:SetWidth(textW - 50)
        t.name:SetJustifyH("LEFT")
        t.name:SetWordWrap(false)
        t.name:SetText(ns.T(mode.name))
        t.desc = W.Text(t, "GameFontHighlightSmall", C.dim, "OVERLAY", 12)
        t.desc:SetPoint("TOPLEFT", t, "TOPLEFT", textX, -(TILE_PAD + TILE_HEAD))
        t.desc:SetWidth(textW)
        t.desc:SetJustifyH("LEFT")
        t.desc:SetJustifyV("TOP")
        t.desc:SetSpacing(2)
        -- hauteur commune : la plus haute des descriptions (et du texte de confirmation), deux lignes au moins
        local h = max(textHeight(t.desc, armText), textHeight(t.desc, ns.T(mode.desc)), 30)
        tileH = max(tileH, floor(TILE_PAD + TILE_HEAD + h + TILE_PAD + 4 + 0.5))

        t:SetScript("OnEnter", function(self) self.hover = true paintTile(self) end)
        t:SetScript("OnLeave", function(self) self.hover = false paintTile(self) end)
        t:SetScript("OnClick", function(self)
            if self.active then
                W.Sound("click")
                return
            end
            -- réglages personnalisés : un 2e clic confirme (ils seraient remplacés)
            if not ns:CurrentMode() and not self.armed then
                disarm()
                self.armed = true
                paintTile(self)
                W.Sound("click")
                local token = {}
                self.armToken = token
                if C_Timer and C_Timer.After then
                    C_Timer.After(ARM_TIME, function()
                        if self.armToken == token and self.armed then
                            self.armed = nil
                            paintTile(self)
                        end
                    end)
                end
                return
            end
            disarm()
            if ns:ApplyMode(self.mode.id) then W.Sound("on") end
            f:Refresh()
        end)
        W.SetTip(t, mode.name, mode.tip, nil, { side = opts.side })
        f.tiles[i] = t
    end

    local rows = math.ceil(#f.tiles / cols)
    for i, t in ipairs(f.tiles) do
        local row, col = floor((i - 1) / cols), (i - 1) % cols
        t:SetHeight(tileH)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", col * (tileW + TILE_GAP), -row * (tileH + TILE_GAP))
    end
    local gridH = rows * tileH + (rows - 1) * TILE_GAP

    -- ligne d'état : hauteur fixe (la plus haute des phrases possibles), pour que rien ne bouge en dessous
    local status = W.Text(f, "GameFontHighlightSmall", C.dim, "OVERLAY", 12)
    status:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(gridH + 12))
    status:SetWidth(width - 4)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    status:SetSpacing(2)
    f.status = status
    local function statusText(current)
        if current then
            return ns.Tf("Mode actuel : %s. Tu peux ensuite allumer ou couper chaque fonction comme tu veux.",
                W.Color("accent", ns.T(current.name)))
        end
        local base = ns:GetMode(ns.db and ns.db.mode) or ns.MODES[1]
        return ns.Tf("Réglages personnalisés, à partir du mode %s. Choisir un mode remet tous ses interrupteurs.",
            W.Color("accent", ns.T(base.name)))
    end
    local statusH = 14
    for _, mode in ipairs(ns.MODES) do statusH = max(statusH, textHeight(status, statusText(mode))) end
    statusH = max(statusH, textHeight(status, statusText(nil)))
    f:SetHeight(floor(gridH + 12 + statusH + 2 + 0.5))

    function f:Refresh(key)
        if key and key ~= "mode" and not controlled[key] then return end
        local _, current = ns:CurrentMode()
        for _, t in ipairs(self.tiles) do
            t.active = (current ~= nil and t.mode == current)
            paintTile(t)
        end
        status:SetText(statusText(current))
    end
    f:SetScript("OnHide", disarm)
    f:SetScript("OnShow", function(self) self:Refresh() end)
    -- un réglage change ailleurs (interrupteur de la visite, /pp, menu de l'icône) : l'état suit s'il est affiché
    ns:OnChange("*", function(key) if f:IsVisible() then f:Refresh(key) end end)
    f:Refresh()
    return f
end

local function buildModes(p)
    local c = p:Card("Mode de jeu", "Un mode allume ou coupe toutes les fonctions d'un coup : une base, que tu ajustes "
        .. "ensuite dans les autres onglets. Survole un mode pour voir exactement ce qu'il change.")
    c:Add(Pages.ModePicker(c, nil, { side = true }))
    c:Note("Un mode ne change pas ta touche d'interaction, tes listes (« Ne jamais vendre », sorts ajoutés…), les "
        .. "positions, les tailles, les couleurs ni les réglages du jeu.")
end

---------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------
-- icon : icône Blizzard classique (présente depuis toujours) ; letter : repli si elle manque
-- group : titre du groupe dans la barre latérale (les onglets d'un même groupe se suivent)
Pages.list = {
    { id = "modes", group = "Jouer", title = "Modes", icon = "Interface\\Icons\\INV_Scroll_03",
      desc = "Une base de réglages en un clic : Recommandé, Complet, Immersif ou Minimal.", build = buildModes },
    { id = "general", group = "Jouer", title = "La touche", icon = "Interface\\Icons\\INV_Misc_Key_03",
      desc = "Une touche pour interagir, parler et rendre les quêtes ; deux pour manger et boire.", build = buildGeneral },
    { id = "resources", group = "Jouer", title = "Combat", icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
      desc = "Barre de coups blancs, rappel de buffs, fenêtre de menace, mana de ton healer et contrôles des mobs.",
      build = function(p) buildSwing(p) buildBuffs(p) buildThreat(p) buildHealer(p) buildMobs(p) end },
    { id = "plates", group = "Jouer", title = "Plates", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
      desc = "Les barres de vie au-dessus des mobs : couleurs de menace, quêtes, rares, et tout leur look.", build = buildPlates },
    { id = "procs", group = "Jouer", title = "Procs", icon = "Interface\\Icons\\Ability_MeleeDamage",
      desc = "L'alerte quand une technique devient utilisable (Fulgurance, Riposte…) : quoi surveiller, comment l'afficher.", build = buildProcs },
    { id = "comfort", group = "Jouer", title = "Confort", icon = "Interface\\Icons\\INV_Misc_Gear_01",
      desc = "Groupes, duels et invocations acceptés ou refusés pour toi ; une interface plus calme.", build = buildComfort },
    { id = "loot", group = "Objets", title = "Butin", icon = "Interface\\Icons\\INV_Misc_Bag_08",
      desc = "Ramassage instantané, étincelles sur ce qui se ramasse, butin affiché à l'écran et jets de dés en groupe.", build = buildLoot },
    { id = "sell", group = "Objets", title = "Vente & HDV", icon = "Interface\\Icons\\INV_Misc_Coin_02",
      desc = "Vends le superflu chez le marchand, le reste à l'hôtel des ventes ; réparation et courrier.",
      build = function(p) buildSell(p) buildMerchant(p) end },
    { id = "windows", group = "Interface", title = "Fenêtres", icon = "Interface\\Icons\\INV_Misc_Bag_07",
      desc = "Quêtes, sacs et personnage dans des fenêtres Platyplus, en grand ; niveau d'objet.",
      build = function(p) buildWindows(p) buildIlvl(p) end },
    { id = "chat", group = "Interface", title = "Chat", icon = "Interface\\Icons\\INV_Misc_Note_01",
      desc = "Un chat plus beau, plus lisible, qui se souvient, sans spam.", build = buildChat },
    { id = "dungeons", group = "Interface", title = "Donjons", icon = "Interface\\Icons\\INV_Misc_Book_09",
      desc = "Le journal des donjons : boss, butin, quêtes et plans de chaque donjon.", build = buildDungeons },
    { id = "launcher", group = "Interface", title = "Icône & infos", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
      desc = "L'icône Platyplus et sa barre d'infos, où tu veux à l'écran.", build = buildLauncher },
    { id = "game", group = "Système", title = "Réglages du jeu", icon = "Interface\\Icons\\INV_Misc_Wrench_01",
      desc = "Réglages du jeu recommandés, en un clic.", build = buildGame },
    { id = "advanced", group = "Système", title = "Avancé", icon = "Interface\\Icons\\Trade_Engineering",
      desc = "Diagnostic, commandes et réinitialisation.", build = buildAdvanced },
}

function Pages:Count()
    return #self.list
end

function Pages:GetInfo(index)
    return self.list[index]
end

function Pages:GetTitle(index)
    local def = self.list[index]
    return def and ns.T(def.title) or "?"
end

-- Construit la page `index` dans `parent` et la renvoie (pile de cartes : :Refresh(clé), :PageShown())
function Pages:Create(index, parent)
    local def = self.list[index]
    if not def then return nil end
    local page = W.Page(parent)
    W.BeginBuild()
    local ok, err = pcall(def.build, page)
    W.EndBuild(page)
    if not ok then geterrorhandler()(err) end
    page:Hide()
    return page
end
