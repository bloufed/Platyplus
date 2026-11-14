-- Platyplus : coeur
--  * réglages sauvegardés (PlatyplusDB) avec valeurs par défaut
--  * ns:Set / ns:OnChange : tout changement de réglage passe par là, les modules réagissent
--  * commandes /platyplus, /pp et /sf
--  * thème partagé (couleurs, médias, sources du flux) : tous les modules visuels s'en servent
local ADDON, ns = ...

ns.version = "0.3.0"

-- Images de l'addon (Media/*.tga, générées par dev/make_media.py)
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.LOGO = ns.MEDIA .. "Logo"

-- Thème commun : interface, flux, barre de ressource et icône utilisent ces couleurs (r, g, b[, a])
ns.THEME = {
    accent  = { 0.20, 0.80, 1.00 },   -- bleu Platyplus
    accent2 = { 0.10, 0.45, 0.65 },
    gold    = { 1.00, 0.82, 0.20 },
    good    = { 0.40, 0.90, 0.50 },
    bad     = { 1.00, 0.40, 0.40 },
    text    = { 0.93, 0.94, 0.97 },
    dim     = { 0.60, 0.63, 0.70 },
    bg      = { 0.06, 0.07, 0.09, 0.96 },
    panel   = { 0.10, 0.11, 0.14, 0.98 },
    card    = { 0.13, 0.14, 0.18, 1.00 },
    line    = { 1.00, 1.00, 1.00, 0.08 },
}

-- Sources des lignes du flux flottant : libellé de la pastille et sa couleur (nil = pas de pastille)
ns.SOURCES = {
    loot     = { label = nil,         color = { 1.00, 1.00, 1.00 } },
    sold     = { label = "Vendu",     color = { 1.00, 0.45, 0.45 } },
    crafted  = { label = "Fabriqué",  color = { 0.30, 0.80, 1.00 } },
    bought   = { label = "Acheté",    color = { 1.00, 0.63, 0.25 } },
    mail     = { label = "Courrier",  color = { 0.55, 0.90, 0.55 } },
    quest    = { label = "Quête",     color = { 1.00, 0.82, 0.20 } },
    trade    = { label = "Échangé",   color = { 0.55, 0.90, 0.55 } },
    received = { label = "Reçu",      color = { 0.55, 0.90, 0.55 } },
    repair   = { label = "Réparé",    color = { 0.65, 0.75, 0.95 } },
    money    = { label = nil,         color = { 1.00, 0.82, 0.20 } },
    info     = { label = "Info",      color = { 0.20, 0.80, 1.00 } },
}

-- Tous les réglages et leur valeur par défaut. Les modules et l'interface ne lisent que ces clés.
local DEFAULTS = {
    -- Général
    key           = "F",     -- touche d'interaction
    interact      = true,    -- la touche déclenche l'interaction rapide
    dialog        = true,    -- F valide quêtes et dialogues
    gossipOptions = true,    -- F choisit aussi la 1re option de dialogue
    questItemKey  = true,    -- F utilise l'objet de quête quand tu es au bon endroit (Maj+F : interagir)
    questItemHint = false,   -- bandeau « F : [objet]  Maj+F : interagir » au milieu de l'écran (éteint : jugé trop envahissant)

    -- Loot
    instantLoot   = true,    -- ramasse tout dès l'ouverture
    confirmBind   = true,    -- confirme seul les objets "lié quand ramassé"
    floatLoot     = true,    -- flux de loot flottant
    rows          = 6,       -- lignes max du flux
    duration      = 4,       -- secondes avant disparition
    floatScale    = 1,       -- taille du flux (0.6 à 2)
    point         = "CENTER",
    relPoint      = "CENTER",
    x             = 260,
    y             = -40,

    -- Vente
    sellJunk      = true,    -- vend les objets gris
    sellGear      = true,    -- vend l'équipement inutile
    gearMaxQuality = 2,      -- qualité max vendue : 0 médiocre, 1 commun, 2 inhabituel, 3 rare, 4 épique
    gearMargin    = 1,       -- niveau d'objet : vendre si inférieur d'au moins N à ce que tu portes
    gearIncludeBoE = false,  -- vendre aussi l'équipement "lié à l'équipement" non lié
    keepUnknownTransmog = true, -- garder les apparences que tu n'as pas encore
    gearMaxPerVisit = 12,    -- pièces d'équipement vendues au maximum par visite (rachat = 12)
    neverSell     = {},      -- [itemID] = true : jamais vendu
    alwaysSell    = {},      -- [itemID] = true : toujours vendu

    -- Hôtel des ventes (Auction.lua)
    ahAssist      = true,    -- panneau Platyplus à côté de l'hôtel des ventes
    ahAutoScan    = true,    -- cherche les prix dès l'ouverture de l'HDV
    ahUndercut    = 1,       -- pc sous le moins cher des autres vendeurs (arrondi à 1 pa si l'HDV refuse le cuivre)
    ahVendorCheck = true,    -- pas de mise en vente si le marchand en donne autant ou plus (l'HDV garde 5 %)
    ahNoCompetition = 3,     -- personne n'en vend : dernier prix vu, sinon prix marchand x N
    ahDuration    = 2,       -- 1 = 12 h, 2 = 24 h, 3 = 48 h
    ahGearMinQuality = 2,    -- équipement proposé à partir de cette qualité (2 = vert : ni blanc ni gris)
    ahKey         = "",      -- touche « mettre en vente le suivant » pendant que l'HDV est ouvert ("" = aucune)
    ahChecked     = {},      -- [itemID] = true : coché, mis en vente (choix retenus d'une visite à l'autre)
    ahNever       = {},      -- [itemID] = true : jamais proposé à l'HDV
    ahPrices      = {},      -- derniers prix vus : [clé d'objet] = { p = prix unitaire, t = date }

    -- Prix de l'HDV partout (Prices.lua, Craft.lua)
    ahTooltip     = true,    -- ligne « HDV » dans les infobulles d'objets (sacs, équipement, liens...)
    craftPrices   = true,    -- coût des recettes face à l'HDV, à côté de la fenêtre de métier
    ahFullScan    = true,    -- scan complet de l'HDV à l'ouverture, au plus une fois par heure
    ahMarket      = {},      -- prix par royaume : ["Royaume-Faction"] = { p = { [itemID] = prix }, t = { [itemID] = date }, scan }
    vendorBuy     = {},      -- prix d'achat chez les marchands : [itemID] = prix à l'unité

    -- Confort
    autoRepair    = true,    -- répare chez les marchands
    repairGuild   = true,    -- avec l'argent de guilde si possible
    bagWarn       = true,    -- alerte "sacs presque pleins"
    bagWarnSlots  = 5,       -- seuil d'emplacements libres
    acceptInvites = false,   -- accepte les groupes des amis et de la guilde
    declineGuildInvites = false,
    declineDuels  = false,
    acceptSummon  = false,   -- accepte les invocations
    acceptRes     = false,   -- accepte les résurrections
    hideTalkingHead = false, -- masque les têtes parlantes
    cameraZoom    = false,   -- règle le zoom maximum de la caméra
    cameraZoomFactor = 2.6,

    -- Flux, quêtes et réglages du jeu
    sellFeed      = true,    -- chaque objet vendu apparaît dans le flux
    gainFeed      = true,    -- objets fabriqués, achetés, reçus par courrier ou par quête
    questCards    = true,    -- récompenses au choix en grandes cartes au milieu de l'écran
    cvarBackup    = {},      -- valeurs d'origine des réglages du jeu modifiés par Platyplus

    -- Étincelles sur ce qu'on peut ramasser (Sparkles.lua). Les valeurs d'origine des réglages du jeu qu'elles modifient
    -- sont dans ns.db.sparkleCVars, clé absente d'ici exprès : « tout réinitialiser » ne doit pas les perdre.
    sparkleLoot   = true,    -- l'étincelle de butin du jeu reste allumée sur les objets de quête, même après un préréglage graphique
    sparkleHerbs  = true,    -- les plantes brillent à l'approche
    sparkleQuestObjects = false, -- les objets de quête du monde brillent aussi (le jeu en marque déjà la plupart)
    sparkleCorpses = true,   -- un cadavre qui a encore du butin pour toi brille à l'approche, après le combat

    -- Ressources
    powerPlayer   = true,    -- chiffre de la ressource sur le portrait du joueur
    powerTarget   = false,   -- et sur celui de la cible
    powerFormat   = "cur",   -- "cur" = 45 ; "curmax" = 45 / 100
    powerPos      = "BOTTOM",-- TOP, CENTER ou BOTTOM
    powerSize     = 14,
    spellCost     = true,    -- coût en ressource sur chaque sort des barres d'action
    spellCostMana = false,   -- afficher aussi les coûts en mana
    spellCostPos  = "TOPLEFT",-- TOPLEFT, BOTTOMLEFT, TOP ou CENTER
    spellCostSize = 11,
    swingBar      = true,    -- barre de coups blancs (minuteur d'attaque automatique), en combat
    swingOffHand  = true,    -- et une fine barre pour la main gauche
    swingWidth    = 240,
    swingX        = 0,       -- décalage depuis le centre de l'écran
    swingY        = -275,    -- sous la barre de ressource et ses sorts si elle est allumée
    swingLocked   = true,
    procAlert     = true,    -- alerte de proc (Fulgurance, Vengeance...) avec la touche à presser (Procs.lua)
    procScale     = 1,
    procX         = 0,       -- décalage depuis le centre de l'écran
    procY         = -115,    -- sous le personnage
    procLocked    = true,
    procBlock     = true,    -- charges de Maîtrise du blocage à droite des alertes de proc (Procs.lua, guerrier)
    -- sorts surveillés (toutes classes)
    procReactive  = true,    -- sorts réactifs connus (Fulgurance, Riposte, Contre-attaque, Marteau de courroux...)
    procGlow      = true,    -- sorts que le jeu fait briller sur les barres (runes des autres classes comprises)
    procExtra     = {},      -- [spellID] = true : sorts ajoutés par le joueur (alerte dès qu'ils sont utilisables)
    procIgnore    = {},      -- [spellID] = true : jamais d'alerte, même s'ils brillent (reconnus aussi par leur nom)
    -- affichage
    procMax       = 3,       -- nombre d'alertes en même temps (1 à 6)
    procShowKey   = true,    -- la touche à presser sous l'icône
    procShowName  = true,    -- le nom du sort sous l'icône
    procAnim      = "vif",   -- "vif" (jaillit, ondes, reflet) | "doux" (le halo respire) | "aucune" (icône fixe)
    procSound     = false,   -- un petit son à l'apparition d'une alerte
    procOpacity   = 1,       -- 0,3 à 1
    -- Rappel de buffs (Buffs.lua)
    buffShout     = true,    -- en combat, sans ton Cri de guerre : son icône et sa touche, dans l'alerte de proc
    buffAllies    = true,    -- hors combat : les buffs que ton groupe peut te donner et que tu n'as pas
    mobControlTooltip = true, -- infobulle d'un mob : ses contrôles (étourdir, immobiliser, ralentir...) et leur rythme
    -- Plates des mobs (Plates.lua) : couleur de menace (comme Threat Plates), mobs de quête, rares
    plates        = true,    -- teinte de menace sur la barre de vie des mobs en combat
    platesRole    = "auto",  -- "auto" (posture défensive, forme d'ours, rôle tank) | "tank" | "dps"
    platesOfftank = true,    -- bleu quand un autre tank du groupe tient le mob
    platesAlert   = true,    -- tank : la plate clignote en rouge quand un mob t'échappe
    platesAlertSound = false, -- et un son
    platesQuest   = true,    -- icône de quête + « 3/8 » à gauche de la barre
    platesRare    = true,    -- « Rare » à droite de la barre
    platesSlim    = true,    -- cadre du jeu remplacé par le nôtre (fond + bord réglables)
    platesRadius  = 3,       -- arrondi des coins : 0 (carrés) .. 4 (très ronds) ; masques Media/PlateMask1..4
    platesBorder  = 1,       -- épaisseur du bord, en px (0 = sans bord)
    platesBackAlpha = 90,    -- opacité du fond sous la barre, en %
    platesOpacity = 85,      -- opacité des barres des plates, en % (100 = opaques)
    platesTexture = "smooth", -- texture de la barre colorée : "smooth" | "flat" | "blizzard" | "raid"
    platesIdle    = "reaction", -- hors combat : "reaction" (nos couleurs hostile/neutre/amical/tapé) | "game" (le jeu)
    platesTarget  = true,    -- ta cible : bord plus épais, couleur platesColTarget
    platesNonTarget = 100,   -- opacité des plates non ciblées quand tu as une cible, en % (100 = pas d'effet)
    platesQuestSize = 18,    -- taille de l'icône de quête (px)
    platesQuestSide = "left", -- "left" | "right" | "top"
    platesQuestText = true,  -- « 3/8 » à côté de l'icône
    platesElite   = false,   -- « Élite » / « Boss » au-dessus de la barre
    platesHideQuestie = true, -- coupe les icônes de quête de Questie sur les plates (en double avec les nôtres)
    platesQuestieOff = false, -- interne : c'est Platyplus qui les a coupées (on les rallume si on décoche)
    platesAlertTime = 1.4,   -- durée du clignotement d'alerte (s)
    -- couleurs des plates { r, g, b } (Plates.COLOR_DEFAULTS)
    platesColSafe    = { 0.20, 0.82, 0.30 },   -- tank : il te tape / DPS : il t'ignore
    platesColWarn    = { 1.00, 0.62, 0.10 },   -- ça se joue
    platesColLoose   = { 0.95, 0.18, 0.15 },   -- tank : il tape un allié / DPS : il te tape
    platesColOther   = { 0.25, 0.62, 0.98 },   -- un autre tank le tient
    platesColHostile = { 0.78, 0.20, 0.16 },   -- hors combat : hostile
    platesColNeutral = { 0.95, 0.80, 0.25 },   -- hors combat : neutre
    platesColFriendly = { 0.30, 0.78, 0.35 },  -- PNJ amical
    platesColTapped  = { 0.55, 0.55, 0.58 },   -- tapé par d'autres
    platesColBack    = { 0.04, 0.04, 0.05 },   -- fond sous la barre
    platesColBorder  = { 0, 0, 0 },            -- bord
    platesColTarget  = { 1, 1, 1 },            -- bord de ta cible
    platesColGlow    = { 1, 0.10, 0.05 },      -- clignotement « il t'échappe »
    platesColQuest   = { 1, 0.85, 0.20 },      -- texte « 3/8 »
    -- barres d'incantation des ennemis (Plates.lua)
    platesCast    = true,    -- couleurs Platyplus sur les barres d'incantation des mobs
    platesCastStyle = true,  -- même cadre que la barre de vie (fond, bord, arrondi)
    platesCastKick = true,   -- couleur à part quand ton interruption est prête
    platesCastTimer = true,  -- temps restant à droite de la barre
    platesCastSound = false, -- son quand ta cible commence un sort interruptible
    platesColCastInterrupt = { 1, 0.72, 0.10 },  -- interruptible
    platesColCastShield    = { 0.55, 0.55, 0.62 }, -- pas interruptible
    platesColCastKick      = { 0.25, 0.85, 1 },  -- interruptible et ton interruption est prête
    -- Fenêtre de menace (Threat.lua) : tous les mobs en combat avec le groupe, qui les tient, ta menace
    threatWindow  = true,    -- fenêtre active (se montre selon les options ci-dessous)
    threatAuto    = true,    -- seulement en combat : apparaît au début, fondu ~3 s après la fin
    threatGroupOnly = true,  -- seulement en groupe
    threatSort    = "danger",-- "danger" (ceux que tu n'as pas d'abord ; DPS : ceux qui te tapent) | "health" (vie la plus basse) | "arrival"
    threatOnlyLost = false,  -- tank : ne liste que les mobs que tu n'as pas
    threatRows    = 8,       -- lignes maximum (3 à 12)
    threatFlash   = true,    -- la ligne d'un mob qui vient de t'échapper clignote
    threatLocked  = true,    -- bandeau verrouillé (décoche pour déplacer la fenêtre)
    threatScale   = 1,
    threatPos     = {},      -- { x, y } du coin haut gauche ; vide = place par défaut
    platesBigDone = false,   -- une seule fois : plates du jeu passées en « épaisse » + « grande » (réglages du jeu)
    buffAsk       = true,    -- clic droit sur un joueur : « Demander un buff » (chuchotement selon sa classe)
    buffAskLang   = "fr",    -- langue du message envoyé : "fr" ou "en"
    buffX         = 0,       -- décalage depuis le centre de l'écran (rangée « buffs à demander »)
    buffY         = 160,     -- au-dessus du personnage
    buffLocked    = true,

    -- Flux flottant (style)
    feedGrow      = "UP",    -- "UP" : les nouvelles lignes poussent les anciennes vers le haut ; "DOWN" : vers le bas

    -- Barre de ressource (HUD lisible sous le personnage)
    hud           = false,   -- coupée par défaut (retour du joueur : le coût sur les sorts suffit)
    hudCombatOnly = false,   -- n'apparaît qu'en combat ou quand la ressource n'est pas au repos
    hudWidth      = 240,
    hudScale      = 1,
    hudX          = 0,       -- décalage depuis le centre de l'écran
    hudY          = -170,
    hudLocked     = true,
    hudMarkers    = true,    -- repères des coûts de tes sorts sur la barre
    hudSpells     = true,    -- icônes de tes sorts : allumées quand tu as assez de ressource
    hudSpellCount = 8,       -- nombre maximum d'icônes (assez pour voir aussi les sorts chers, grisés tant que la rage manque)

    -- Mana du healer (HealerMana.lua) : la mana du soigneur de ton groupe, dans une barre posée où tu veux
    healerBar     = false,   -- coupée par défaut : on l'allume dans les options
    healerName    = "",      -- "" : le soigneur désigné par le groupe ; sinon le joueur choisi (« Mon healer = ma cible »)
    healerLow     = true,    -- alerte « healer à sec » : la barre vire au rouge sous le seuil
    healerLowPercent = 20,   -- seuil, en % de mana
    healerLowSound = false,  -- et un son au moment de l'alerte (en combat seulement)
    healerWidth   = 200,
    healerScale   = 1,
    healerX       = -260,    -- décalage depuis le centre de l'écran
    healerY       = -120,
    healerLocked  = true,

    -- Jets de butin (LootRolls.lua) : fenêtre qui suit, objet par objet, les dés de chaque joueur en groupe
    lootRolls          = true,   -- suivi actif (événements écoutés)
    lootRollsAuto      = true,   -- la fenêtre s'ouvre toute seule quand un objet est mis aux dés en groupe
    lootRollsAutoClose = true,   -- et se referme 20 s après le dernier jet (si elle s'est ouverte toute seule)
    lootRollsManual    = true,   -- onglet /roll : les dés lancés à la main dans le chat, rangés par objet annoncé
    lootRollsScale     = 1,
    lootRollsPos       = {},     -- { x, y } du coin haut droit ; vide = place par défaut

    -- Icône Platyplus et barre d'infos (posée où tu veux, hors minicarte)
    launcher      = true,
    launcherPoint = "TOPRIGHT",
    launcherX     = -250,
    launcherY     = -30,
    launcherScale = 1,
    launcherLocked = false,
    dock          = true,    -- infos à côté de l'icône
    dockFps       = true,
    dockLatency   = true,
    dockGold      = true,
    dockBags      = true,
    dockDurability = true,
    dockIlvl      = true,    -- niveau d'objet moyen de l'équipement porté
    dockCoords    = false,
    dockXp        = true,    -- expérience (pourcentage, XP/h, temps avant le niveau, monstres restants)
    dockXpMode    = "pct",   -- ce que la barre montre : pct, rate, time, kills (clic sur la valeur = suivant)

    -- Petits plus (QoL)
    hideErrors    = false,   -- masque tous les messages d'erreur rouges
    autoOpenMail  = false,   -- ouvre tout le courrier dès l'ouverture de la boîte aux lettres
    autoQuest     = false,   -- accepte et rend les quêtes dès l'ouverture du dialogue, sans touche (Maj = pause)
    charIlvl      = true,    -- niveau d'objet sur la fiche du personnage
    bagIlvl       = true,    -- niveau d'objet et pièce « à vendre » sur les objets des sacs
    durabilityWarn = true,   -- alerte quand l'équipement est presque cassé
    chatLinks     = true,    -- liens web cliquables dans le chat (fenêtre pour les copier)
    chatShortChannels = true,-- « [1. Général - Zone] » -> « [1] », « [Guilde] » -> « [G] »...
    chatCopyButton = true,   -- petit bouton « copier le chat » sur les fenêtres de chat
    -- Chat amélioré (ChatPlus.lua)
    chatSkin      = true,    -- look Platyplus : fond uni, onglets soulignés, zone de saisie sombre
    chatTimestamps = true,   -- l'heure devant chaque message (réglage du jeu, valeur d'origine gardée)
    chatClassColors = true,  -- noms colorés selon la classe (réglage du jeu, valeur d'origine gardée)
    chatMentions  = true,    -- ton nom surligné quand quelqu'un l'écrit, avec un son
    chatHistory   = true,    -- les dernières lignes gardées pour la session suivante (/reload compris)
    chatSentHistory = true,  -- flèches haut / bas : ce que tu as tapé, gardé aussi
    chatSpam      = true,    -- masque les messages répétés et les ventes d'or
    chatFilterWords = {},    -- mots à masquer (minuscules)
    -- Fenêtre de chat Platyplus (ChatWindow.lua), à la place des fenêtres de chat du jeu
    chatWindow    = true,
    chatWinTwoLines = true,  -- true : façon messagerie (« Nom : texte », barre du canal, canal et heure à droite) ; false : ligne brute
    chatWinChannelText = false, -- true : le texte des messages dans la couleur du canal (comme le chat du jeu)
    chatWinFontSize = 13,
    chatWinAlpha  = 0.85,    -- opacité du fond
    chatWinPos    = {},      -- { x, y, w, h } (vide : par-dessus la fenêtre de chat du jeu)
    -- Traducteur (Traducteur.lua + programme Traducteur\Traducteur.pyw)
    tradChatLog   = false,   -- allume le journal du chat (/chatlog) à chaque connexion, pour le traducteur
    tradPersos    = {},      -- noms de mes personnages : le traducteur ne traduit pas mes messages
    -- Fenêtres Platyplus pour les dialogues des PNJ et les sacs (Windows.lua, QuestWindow.lua, BagWindow.lua)
    questWindow   = true,
    questWinScale = 1.1,     -- taille (1 = taille de base, déjà plus grande que la fenêtre du jeu)
    questWinPos   = {},      -- { x, y } coin haut gauche, en points de l'écran (vide : à gauche de l'écran)
    bagWindow     = true,
    bagWinScale   = 1.0,
    bagWinColumns = 10,
    bagWinGroup   = true,    -- objets rangés par type (quête, consommables, artisanat...) : l'affichage seulement
    bagWinPos     = {},      -- { x, y } coin bas droit, en points de l'écran (vide : en bas à droite)
    charWindow    = true,    -- fenêtre du personnage Platyplus (touche C), CharacterWindow.lua
    charWinScale  = 1.0,
    charWinPos    = {},      -- { x, y } coin haut gauche, en points de l'écran (vide : à gauche de l'écran)
    hideXpBar     = false,   -- masque les barres d'expérience et de réputation du bas de l'écran
    eatKey        = "",      -- touche : meilleure nourriture hors combat, meilleure potion de soins en combat ("" = aucune)
    drinkKey      = "",      -- touche : meilleure boisson hors combat, meilleure potion de mana en combat ("" = aucune)

    mapQuestPage  = true,    -- page d'une quête du journal : à faire, récompenses, histoire repliée (QuestPage.lua)
    questPageStory = false,  -- l'histoire de la quête dépliée sur cette page

    -- Journal des donjons : c'est DungeonJournal (Exehn), intégré dans le dossier DungeonJournal/. Ses réglages,
    -- favoris et progression sont les siens (PlatyplusDungeonDB, PlatyplusDungeonCharacterDB : DungeonJournalGlue.lua).
    dungeonSkin   = true,    -- journal aux couleurs de Platyplus (DungeonJournalSkin.lua ; effet au /reload)
    dungeonList   = true,    -- liste de tous les donjons à gauche du journal, niveau conseillé (DungeonJournalPlus.lua)
    dungeonFit    = true,    -- « À ton niveau » sur les cartes de l'accueil, qui s'ouvre sur les donjons de ton niveau

    -- Interface
    uiPoint       = "CENTER",
    uiX           = 0,
    uiY           = 0,
    uiTab         = 1,
    language      = "auto",  -- langue de l'addon : "auto" (celle du client) ou frFR/enUS/deDE/esES/itIT/ptBR/ruRU (/reload pour appliquer)
    welcomeSeen   = false,   -- la présentation « Qu'est-ce que Platyplus ? » a déjà été montrée
    debug         = false,
}
ns.DEFAULTS = DEFAULTS

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
ns.Copy = copy

-- Les textes français passés ici sont traduits (T laisse intacts les nombres, nil et valeurs secrètes)
function ns:Print(...)
    local n = select("#", ...)
    local args = { ... }
    for i = 1, n do args[i] = ns.T(args[i]) end
    print("|cff33ccffPlatyplus|r:", unpack(args, 1, n))
end

function ns:Debug(...)
    if ns.db and ns.db.debug then
        print("|cff888888Platyplus dbg|r:", ...)
    end
end

---------------------------------------------------------------------------
-- Réglages observables
---------------------------------------------------------------------------
local listeners = {}   -- [clé ou "*"] = { fonctions }

-- ns:OnChange("clé", function(key, value) ... end) ; "*" = n'importe quelle clé
function ns:OnChange(key, fn)
    listeners[key] = listeners[key] or {}
    table.insert(listeners[key], fn)
end

local function fire(list, key, value)
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, key, value)
        if not ok then geterrorhandler()(err) end
    end
end

function ns:Notify(key)
    local value = self.db and self.db[key]
    fire(listeners[key], key, value)
    fire(listeners["*"], key, value)
end

function ns:Set(key, value)
    self.db[key] = value
    self:Notify(key)
end

function ns:Reset(key)
    self:Set(key, copy(DEFAULTS[key]))
end

-- keepLists = true : garde les listes "jamais / toujours vendre", "jamais à l'HDV" et les prix vus à l'HDV
local LISTS = { chatFilterWords = true, tradPersos = true, neverSell = true, alwaysSell = true, procExtra = true, procIgnore = true, ahNever = true, ahPrices = true, ahChecked = true,
    ahMarket = true, vendorBuy = true }
function ns:ResetAll(keepLists)
    local keys = {}
    for key, default in pairs(DEFAULTS) do
        if not (keepLists and LISTS[key]) then
            self.db[key] = copy(default)
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do self:Notify(key) end
end

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------
local function onoff(v)
    return v and "|cff00ff00ON|r" or "|cffff4040OFF|r"
end

-- "on"/"off" explicite, sinon on inverse la valeur courante
local function parseSwitch(arg, current)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "1" then return true end
    if arg == "off" or arg == "0" then return false end
    return not current
end

local function cvarValue(name)
    local ok, v = pcall(GetCVar, name)
    if ok and v ~= nil then return tostring(v) end
    return "?"
end

-- Aide : { commande, description française } ; la commande n'est pas traduite
local HELP = {
    { "config", "ouvre la fenêtre d'options" },
    { "loot|float|interact|dialog|gossip|junk [on|off]", "active / coupe une fonction" },
    { "etincelles [on|off]", "état des étincelles (plantes, cadavres, objets de quête) | toutes allumées / coupées" },
    { "power|cost [on|off]", "ressource sur le portrait | coût des sorts sur les barres" },
    { "eat [TOUCHE|off|debug]", "touche pour manger (potion de soins en combat) : voir, changer, couper, diagnostic" },
    { "drink [TOUCHE|off]", "touche pour boire (potion de mana en combat) : voir, changer, couper" },
    { "donjons [etat|options]", "journal des donjons : l'ouvre | ce qu'il fait | ses réglages (aussi /dj)" },
    { "fenetres [reset]", "fenêtres de quête, de sacs et du personnage : état | remise en place" },
    { "bienvenue", "réaffiche la présentation de Platyplus" },
    { "copier", "ouvre le chat dans une zone de texte à copier" },
    { "chat", "état du chat amélioré (look, mémoire, anti-spam)" },
    { "trad [on|off]", "journal du chat pour le traducteur (programme Traducteur Platyplus)" },
    { "spam [ajouter|retirer MOT|voir]", "mots masqués par l'anti-spam, messages masqués" },
    { "swing [on|off]", "aperçu de la barre de coups blancs ; la montre ou la cache" },
    { "proc [on|off]", "aperçu de l'alerte de proc, sorts surveillés (ta classe, ajoutés, ignorés) et leurs touches ; l'active ou la coupe" },
    { "healer [on|off|cible|auto]", "barre de mana de ton healer : aperçu | l'allume ou l'éteint | suivre ta cible | laisser le groupe choisir" },
    { "jets [demo|auto|on|off]", "fenêtre des jets de butin (dés de chaque joueur, objet par objet) | exemple | ouverture auto" },
    { "buffs", "rappel de buffs : état (Cri de guerre, buffs de tes alliés) et aperçu" },
    { "mob", "contrôles du mob ciblé (étourdir, ralentir...) et leur rythme" },
    { "plates [on|off|tank|dps|auto]", "plates des mobs : état | allume/éteint | rôle (couleurs de menace)" },
    { "menace [on|off|test|reset]", "fenêtre de menace : tous les mobs en combat et qui les tient | allume/éteint | mobs factices | remet en place" },
    { "demo", "montre le flux, la barre de ressource et les options (pour une capture)" },
    { "cartes", "aperçu des cartes de récompense de quête (objets d'exemple)" },
    { "perf", "mémoire et temps de calcul de Platyplus mesurés par le jeu" },
    { "icon [on|off|reset]", "icône Platyplus : montrer, cacher, remettre en place" },
    { "preset [restore]", "applique les réglages du jeu recommandés | remet les anciens" },
    { "sell", "vend maintenant (marchand ouvert)" },
    { "hdv [scan|complet|touche X|exclus]", "hôtel des ventes : prix, scan complet, touche, objets exclus" },
    { "list", "liste ce qui serait vendu" },
    { "sort", "trie les sacs" },
    { "move | test | reset", "position du flux flottant : déplacer, tester, remettre" },
    { "rows <1-12> | time <1-15>", "lignes et durée du flux" },
    { "cvars | cvar <nom> <val>", "CVars utiles (SoftTarget*, autoLoot*)" },
    { "langue [code|auto]", "langue de Platyplus : voir | changer (frFR, enUS, deDE, esES, itIT, ptBR, ruRU, auto)" },
}

local function printHelp()
    local db = ns.db
    ns:Print(ns.Tf("v%s - tape /pp pour ouvrir les options. Commandes (/pp, /platyplus ou /sf) :", ns.version))
    for _, h in ipairs(HELP) do
        print("  " .. h[1] .. "  " .. ns.T(h[2]))
    end
    print("  key <TOUCHE>  " .. ns.Tf("touche actuelle : |cffffff00%s|r (liée à : %s)", tostring(db.key),
        tostring(ns.Interact and ns.Interact:CurrentAction() or ns.T("rien"))))
    print("  debug [on|off]  " .. ns.Tf("messages de debug : %s", onoff(db.debug)))
end

local commands = {}

local function switchCommand(key, label)
    return function(arg)
        ns:Set(key, parseSwitch(arg, ns.db[key]))
        ns:Print(ns.Tf("%s :", ns.T(label)), onoff(ns.db[key]))
    end
end

commands.config   = function() if ns.UI then ns.UI:Toggle() else ns:Print("interface indisponible") end end
commands.loot     = switchCommand("instantLoot", "loot instantané")
commands.float    = switchCommand("floatLoot", "loot flottant")
commands.interact = switchCommand("interact", "interaction rapide")
commands.dialog   = switchCommand("dialog", "F valide quêtes et dialogues")
commands.gossip   = switchCommand("gossipOptions", "F choisit la 1re option de dialogue")
commands.junk     = switchCommand("sellJunk", "vente des gris")
commands.power    = switchCommand("powerPlayer", "ressource sur le portrait")
commands.cost     = switchCommand("spellCost", "coût des sorts sur les barres d'action")

-- /pp demo : montre tout d'un coup (flux de butin, barre de ressource, options) pour une capture d'écran
commands.demo = function()
    if ns.Float and ns.Float.Test then ns.Float:Test() end
    if ns.ResourceBar and ns.ResourceBar.Preview then ns.ResourceBar:Preview(20) end
    if ns.UI and ns.UI.Open then ns.UI:Open() end
    ns:Print("démo : flux de butin, barre de ressource (20 s) et options affichés. Impr. écran = capture "
        .. "(enregistrée dans World of Warcraft\\_forever_\\Screenshots).")
end

-- /pp cartes : aperçu des cartes de récompense avec des objets d'exemple (rien n'est envoyé au jeu)
commands.cartes = function()
    if ns.QuestCards and ns.QuestCards.Demo then ns.QuestCards:Demo() else ns:Print("cartes indisponibles") end
end
commands.cards = commands.cartes

-- /pp perf : ce que Platyplus coûte vraiment, mesuré par le jeu (mémoire, et temps par image si le client le fournit)
commands.perf = function()
    local update = rawget(_G, "UpdateAddOnMemoryUsage")
    local memory = rawget(_G, "GetAddOnMemoryUsage")
    local kb
    if type(update) == "function" and type(memory) == "function" then
        pcall(update)
        local ok, v = pcall(memory, ADDON)
        if ok and type(v) == "number" then kb = v end
    end
    local ms
    local profiler = rawget(_G, "C_AddOnProfiler")
    local enum = rawget(_G, "Enum")
    local metric = enum and enum.AddOnProfilerMetric
    if profiler and profiler.GetAddOnMetric and metric and metric.RecentAverageTime then
        local ok, v = pcall(profiler.GetAddOnMetric, ADDON, metric.RecentAverageTime)
        if ok and type(v) == "number" then ms = v end
    end
    ns:Print(ns.Tf("mesures du jeu : mémoire %s ; temps moyen par image %s",
        kb and string.format("%.0f Ko", kb) or ns.T("indisponible"),
        ms and string.format("%.3f ms", ms) or ns.T("indisponible sur ce client")))
end

-- /pp eat | drink [TOUCHE|off|debug] : ce que la touche prendrait (hors combat / en combat), change cette touche,
-- ou (debug) montre chaque consommable des sacs et ce qu'il est pour Platyplus
local function eatCommand(roleId, setting)
    return function(arg)
        arg = strtrim(arg or "")
        if not ns.Eat then ns:Print("touches « manger » et « boire » indisponibles") return end
        if arg:lower() == "debug" then
            for _, line in ipairs(ns.Eat:Explain()) do ns:Print(line) end
            return
        end
        if arg ~= "" then
            ns:Set(setting, (arg:lower() == "off") and "" or arg:upper())   -- le module annonce le résultat
            return
        end
        ns:Print(ns.Eat:Describe(roleId))
    end
end
commands.eat = eatCommand("eat", "eatKey")
commands.manger = commands.eat
commands.drink = eatCommand("drink", "drinkKey")
commands.boire = commands.drink

-- /pp swing [on|off] : aperçu de la barre de coups blancs, ou la montre / la cache
commands.swing = function(arg)
    arg = strtrim(arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns:Set("swingBar", arg == "on")
        ns:Print("barre de coups blancs :", onoff(ns.db.swingBar))
        return
    end
    if ns.SwingBar and ns.SwingBar.Preview then ns.SwingBar:Preview(6) end
end

-- /pp healer [on|off|cible|auto] : barre de mana du healer. Sans argument : aperçu et qui est suivi ;
-- on / off : l'allume ou l'éteint ; cible : suit ta cible ; auto : le soigneur désigné par le groupe
commands.healer = function(arg)
    arg = strtrim(arg or ""):lower()
    local H = ns.HealerMana
    if not (H and H.Preview) then ns:Print("barre de mana du healer indisponible") return end
    if arg == "on" or arg == "off" then
        ns:Set("healerBar", arg == "on")
        ns:Print("mana du healer :", onoff(ns.db.healerBar))
    elseif arg == "cible" or arg == "target" then
        H:PickTarget()
    elseif arg == "auto" then
        H:ClearPick()
    else
        local who = H:Summary()
        ns:Print("mana du healer :", onoff(ns.db.healerBar), "- healer suivi :",
            who or "aucun (cible ton healer puis /pp healer cible)")
        H:Preview(6)
    end
end

-- /pp buffs : état du rappel de buffs (Cri de guerre, buffs que tes alliés peuvent te donner) et aperçu de la rangée
commands.jets = function(arg)
    if ns.LootRolls and ns.LootRolls.Command then ns.LootRolls:Command(arg) else ns:Print("suivi des jets indisponible") end
end
commands.des = commands.jets
commands.rolls = commands.jets

commands.buffs = function()
    local B = ns.Buffs
    if not (B and B.Status) then ns:Print("rappel de buffs indisponible") return end
    ns:Print("rappel de buffs :")
    for _, line in ipairs(B:Status()) do print("  " .. line) end
    B:Preview(6)
end
commands.buff = commands.buffs

-- /pp mob : contrôles du mob ciblé (étourdir, ralentir...) et leur rythme ; sans cible : état de la base
commands.mob = function()
    if ns.MobControls and ns.MobControls.Command then ns.MobControls:Command() else ns:Print("contrôles des mobs indisponibles") end
end
commands.controles = commands.mob

-- /pp plates [on|off|tank|dps|auto] : plates des mobs (couleurs de menace, quêtes). Sans argument : état de chaque plate
commands.plates = function(arg)
    arg = strtrim(arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns:Set("plates", arg == "on")
        ns:Print("plates des mobs :", onoff(ns.db.plates))
    elseif arg == "tank" or arg == "dps" or arg == "auto" then
        ns:Set("platesRole", arg)
        ns:Print("plates des mobs, rôle :", arg)
    elseif ns.Plates and ns.Plates.Command then
        ns.Plates:Command()
    else
        ns:Print("plates des mobs indisponibles")
    end
end
commands.plate = commands.plates

-- /pp menace [on|off|test|reset] : fenêtre de menace (tous les mobs en combat, qui les tient)
commands.threat = function(arg)
    if ns.Threat and ns.Threat.Command then ns.Threat:Command(arg) else ns:Print("fenêtre de menace indisponible") end
end
commands.menace = commands.threat
commands.aggro = commands.threat

-- /pp proc [on|off] : aperçu de l'alerte de proc et touche de chaque sort réactif rangé sur les barres ;
-- ou l'active / la coupe
commands.proc = function(arg)
    arg = strtrim(arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns:Set("procAlert", arg == "on")
        ns:Print("alerte de proc :", onoff(ns.db.procAlert))
        return
    end
    if arg == "debug" then                    -- journal du suivi de Maîtrise du blocage dans le chat
        local P = ns.Procs
        if P and P.ToggleDebug then P:ToggleDebug() else ns:Print("alertes de proc indisponibles") end
        return
    end
    local P = ns.Procs
    if not (P and P.Preview) then ns:Print("alertes de proc indisponibles") return end
    local lines = P:Describe()
    if P.Summary then                         -- sorts surveillés pour ta classe, ajoutés, ignorés
        ns:Print("alerte de proc : sorts surveillés")
        for _, line in ipairs(P:Summary()) do print("  " .. line) end
    end
    if #lines == 0 then
        ns:Print("alerte de proc : aucun sort surveillé sur tes barres. Les sorts que le jeu fait briller "
            .. "sont annoncés aussi ; ajoute les tiens dans l'onglet Procs.")
    else
        ns:Print("alerte de proc : sorts surveillés sur tes barres")
        for _, line in ipairs(lines) do print("  " .. line) end
    end
    if P.BlockStatus then
        print("  " .. P:BlockStatus())
        if P.BlockDetails then print(P:BlockDetails()) end
    end
    P:Preview()
end
commands.procs = commands.proc

-- /pp etincelles [on|off] : état des étincelles (réglages du jeu, cible d'interaction lue maintenant) ;
-- ou les allume toutes (valeurs par défaut) / les coupe toutes
local SPARKLE_KEYS = { "sparkleLoot", "sparkleHerbs", "sparkleQuestObjects", "sparkleCorpses" }
commands.etincelles = function(arg)
    arg = strtrim(arg or ""):lower()
    if arg == "on" or arg == "off" then
        for _, key in ipairs(SPARKLE_KEYS) do
            ns:Set(key, arg == "on" and DEFAULTS[key] or false)
        end
        ns:Print("étincelles :", onoff(arg == "on"), arg == "on" and "(réglages par défaut)" or "")
        return
    end
    if not (ns.Sparkles and ns.Sparkles.Status) then ns:Print("étincelles indisponibles") return end
    ns:Print("étincelles :")
    for _, line in ipairs(ns.Sparkles:Status()) do print("  " .. line) end
end
commands.sparkles = commands.etincelles
commands.etincelle = commands.etincelles

-- /pp chat : état du chat amélioré
commands.chat = function()
    if not (ns.ChatPlus and ns.ChatPlus.Status) then ns:Print("chat amélioré indisponible") return end
    ns:Print("chat :")
    for _, line in ipairs(ns.ChatPlus:Status()) do print("  " .. line) end
    if ns.ChatWindow and ns.ChatWindow.Status then
        for _, line in ipairs(ns.ChatWindow:Status()) do print("  " .. line) end
    end
end

-- /pp spam [ajouter MOT | retirer MOT | voir] : mots masqués, messages masqués
commands.spam = function(arg)
    local Spam = ns.ChatPlus and ns.ChatPlus.Spam
    if not Spam then ns:Print("anti-spam indisponible") return end
    local verb, word = (arg or ""):match("^(%S*)%s*(.-)$")
    verb = (verb or ""):lower()
    if verb == "ajouter" or verb == "add" then
        ns:Print(Spam:AddWord(word) and ns.Tf("mot ajouté : « %s »", word:lower()) or "mot vide ou déjà dans la liste")
    elseif verb == "retirer" or verb == "remove" then
        ns:Print(Spam:RemoveWord(word) and ns.Tf("mot retiré : « %s »", word:lower()) or "ce mot n'est pas dans la liste")
    elseif verb == "voir" or verb == "show" then
        Spam:ShowRecent()
    else
        local words = ns.db.chatFilterWords or {}
        ns:Print(ns.Tf("anti-spam : %d message(s) masqué(s) depuis le chargement ; mots : %s. /pp spam ajouter MOT, /pp spam retirer MOT, /pp spam voir",
            Spam.hidden, #words > 0 and table.concat(words, ", ") or ns.T("aucun")))
    end
end

-- /pp copier (ou copy) : ouvre les dernières lignes du chat dans une zone de texte à copier
commands.copier = function()
    if ns.Chat and ns.Chat.CopyChat then ns.Chat:CopyChat() else ns:Print("copie du chat indisponible") end
end
commands.copy = commands.copier

-- /pp fenetres [reset] : fenêtres Platyplus de quête et de sacs (état, remise en place)
commands.fenetres = function(arg)
    if (arg or ""):lower() == "reset" then
        if ns.QuestWindow then ns.QuestWindow:ResetPosition() end
        if ns.BagWindow then ns.BagWindow:ResetPosition() end
        if ns.CharWindow then ns.CharWindow:ResetPosition() end
        ns:Print("fenêtres de quête, de sacs et du personnage remises à leur place")
        return
    end
    ns:Print("fenêtres Platyplus :")
    for _, mod in ipairs({ ns.QuestWindow or false, ns.BagWindow or false, ns.CharWindow or false }) do
        if mod and mod.Status then
            for _, line in ipairs(mod:Status()) do print("  " .. line) end
        end
    end
end
commands.windows = commands.fenetres

-- /pp donjons : ouvre ou ferme le journal des donjons (DungeonJournal intégré) ; « etat » : ce qu'il fait ;
-- « options » : ses propres réglages (comme /dj options)
commands.donjons = function(arg)
    local P = ns.DungeonPlus
    if not P then ns:Print("journal des donjons indisponible") return end
    arg = strtrim(arg or ""):lower()
    if arg == "etat" or arg == "état" or arg == "status" then
        ns:Print("journal des donjons :")
        for _, line in ipairs(P:Status()) do print("  " .. line) end
    elseif arg == "options" or arg == "reglages" or arg == "réglages" then
        if not P.OpenOptions() then ns:Print("réglages du journal indisponibles") end
    else
        P.Toggle()
    end
end
commands.donjon = commands.donjons
commands.journal = commands.donjons
commands.dungeons = commands.donjons


-- /pp bienvenue (ou welcome) : réaffiche la présentation de Platyplus
commands.bienvenue = function()
    if ns.UI and ns.UI.ShowWelcome then ns.UI:ShowWelcome() else ns:Print("présentation indisponible") end
end
commands.welcome = commands.bienvenue

-- /pp icon [on|off|reset] : montre, cache ou remet en place l'icône flottante
commands.icon = function(arg)
    arg = (arg or ""):lower()
    if arg == "reset" then
        if ns.Launcher and ns.Launcher.ResetPosition then ns.Launcher:ResetPosition() end
        ns:Set("launcher", true)
        ns:Print("icône remise à sa place par défaut")
        return
    end
    ns:Set("launcher", parseSwitch(arg, ns.db.launcher))
    ns:Print("icône Platyplus :", onoff(ns.db.launcher))
end

commands.preset = function(arg)
    if not ns.GameSettings then return end
    if arg:lower() == "restore" then
        ns.GameSettings:RestoreAll()
    else
        ns.GameSettings:ApplyRecommended()
    end
end
commands.debug    = switchCommand("debug", "debug")

commands.key = function(arg)
    arg = (arg:upper():gsub("%s+", ""))
    if arg == "" then
        ns:Print("usage : /sf key F   (ou SHIFT-F, BUTTON4, ...)")
        return
    end
    ns:Set("key", arg)
    ns:Print("touche :", arg, "-> liée à", tostring(ns.Interact:CurrentAction() or "rien (en combat ? réessaie après)"))
end

commands.sell = function()
    if ns.Junk then ns.Junk:SellNow() end
end

-- /pp hdv (ou ah) : hôtel des ventes (voir Auction.lua)
commands.hdv = function(arg)
    if ns.Auction and ns.Auction.Command then ns.Auction:Command(arg) else ns:Print("module d'hôtel des ventes indisponible") end
end
commands.ah = commands.hdv

-- /pp trad : journal du chat pour le traducteur (voir Traducteur.lua)
commands.trad = function(arg)
    if ns.Trad and ns.Trad.Command then ns.Trad:Command(arg) else ns:Print("traducteur indisponible") end
end
commands.traducteur = commands.trad


commands.list = function()
    if not ns.Junk then return end
    local list = ns.Junk:BuildList()
    if #list == 0 then ns:Print("rien à vendre") return end
    for _, e in ipairs(list) do
        print("  [" .. tostring(e.reason) .. "] " .. tostring(e.link or e.itemID) .. " x" .. tostring(e.count or 1))
    end
    ns:Print(ns.Tf("%d objet(s)", #list))
end

commands.sort = function()
    if ns.Misc then ns.Misc:SortBags() end
end

commands.move = function() ns.Float:ToggleMove() end
commands.test = function() ns.Float:Test() end

commands.reset = function()
    for _, key in ipairs({ "point", "relPoint", "x", "y" }) do ns:Reset(key) end
    ns:Print("position remise par défaut")
end

commands.rows = function(arg)
    local n = tonumber(arg)
    if not n then ns:Print("usage : /sf rows 6") return end
    ns:Set("rows", math.max(1, math.min(12, math.floor(n))))
    ns:Print("lignes max :", ns.db.rows)
end

commands.time = function(arg)
    local n = tonumber(arg)
    if not n then ns:Print("usage : /sf time 4") return end
    ns:Set("duration", math.max(1, math.min(15, n)))
    ns:Print("durée d'affichage :", ns.db.duration, "s")
end

commands.cvars = function()
    for _, name in ipairs({
        "autoLootDefault",
        "SoftTargetInteract",
        "SoftTargetInteractArc",
        "SoftTargetInteractRange",
        "SoftTargetIconInteract",
        "cameraDistanceMaxZoomFactor",
    }) do
        print("  " .. name .. " = " .. cvarValue(name))
    end
end

commands.cvar = function(arg)
    local name, value = arg:match("^(%S+)%s+(%S+)$")
    if not name then ns:Print("usage : /sf cvar SoftTargetInteractRange 15") return end
    local lower = name:lower()
    if not (lower:find("^softtarget") or lower:find("^autoloot")) then
        ns:Print("seuls les CVars SoftTarget* et autoLoot* sont autorisés ici")
        return
    end
    local ok = pcall(SetCVar, name, value)
    ns:Print(name, "=", cvarValue(name), ok and "" or "(refusé par le jeu)")
end

-- /pp langue [code|auto] : langue de Platyplus (le changement s'applique après /reload)
commands.langue = function(arg)
    arg = strtrim(arg or "")
    if arg == "" then
        local choice = ns.db.language or "auto"
        ns:Print(ns.Tf("langue : %s (réglage : %s)", ns.Locale.Name(ns.lang),
            choice == "auto" and ns.T("automatique") or ns.Locale.Name(choice)))
        local codes = { "auto" }
        for _, l in ipairs(ns.LANGUAGES) do codes[#codes + 1] = l.code end
        ns:Print(ns.Tf("choix : %s", table.concat(codes, ", ")))
        return
    end
    if arg:lower() == "manque" then
        -- Textes sans traduction vus depuis l'activation du suivi (1er appel : active le suivi)
        if not ns.i18nTrace then
            ns.i18nTrace = true
            ns:Print(ns.T("suivi activé : ouvre les fenêtres puis retape /pp langue manque"))
            return
        end
        local list = {}
        for k in pairs(ns.i18nMissing) do list[#list + 1] = k end
        table.sort(list)
        ns:Print(ns.Tf("%d texte(s) sans traduction en %s", #list, ns.Locale.Name(ns.lang)))
        for i = 1, math.min(#list, 25) do ns:Print(" - " .. list[i]) end
        if #list > 25 then ns:Print(ns.Tf("… et %d autres", #list - 25)) end
        return
    end
    local want
    if arg:lower() == "auto" then
        want = "auto"
    else
        for _, l in ipairs(ns.LANGUAGES) do
            if l.code:lower() == arg:lower() or l.name:lower() == arg:lower() then want = l.code end
        end
    end
    if not want then
        ns:Print(ns.Tf("langue inconnue : %s (essaie auto, frFR, enUS, deDE, esES, itIT, ptBR ou ruRU)", arg))
        return
    end
    ns:Set("language", want)
    ns:Print(ns.Tf("langue réglée sur %s : tape /reload pour l'appliquer.",
        want == "auto" and ns.T("automatique") or ns.Locale.Name(want)))
end
commands.lang = commands.langue
commands.language = commands.langue

commands.help = printHelp

SLASH_PLATYPLUS1 = "/platyplus"
SLASH_PLATYPLUS2 = "/pp"
SLASH_PLATYPLUS3 = "/sf"
SlashCmdList["PLATYPLUS"] = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        if ns.UI then ns.UI:Toggle() else printHelp() end
        return
    end
    local fn = commands[cmd]
    if fn then fn(arg) else printHelp() end
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")

    PlatyplusDB = PlatyplusDB or {}
    -- réglages de fonctions retirées : effacés pour ne pas traîner dans le fichier sauvegardé
    for _, old in ipairs({ "charStats", "settingsSkin", "ahFloor", "ahMinQuality", "questDrops", "questDropTooltip",
        "guideWaypoint", "guideArrow", "arrowScale", "arrowPos", "guideHere", "guideHereRadius", "guideHereSound",
        "guideScale", "guideAlpha", "guidePos",
        "mapStitch", "mapReveal", "mapRevealDim", "mapDungeons", "mapFlights", "mapBoats", "mapQuestDark", "platesRound",
        -- carte OpenMap, alerte des filons et étincelles de minerai retirées (2026-11-14)
        "openMap", "mapSkin", "veinAlert", "veinWatch", "veinSound", "veinMinimap", "veinMode", "sparkleOre" }) do PlatyplusDB[old] = nil end
    -- (guide retiré : sa place et sa fenêtre étaient gardées par personnage)
    if type(PlatyplusCharDB) == "table" then
        PlatyplusCharDB.guide, PlatyplusCharDB.guideWindow = nil, nil
        PlatyplusCharDB.openMap = nil   -- réglages de la carte OpenMap retirée, gardés par personnage
    end
    for k, v in pairs(DEFAULTS) do
        if PlatyplusDB[k] == nil then PlatyplusDB[k] = copy(v) end
    end
    ns.db = PlatyplusDB
    if ns.SetupLocale then ns:SetupLocale() end   -- langue fixée avant tout texte (Locale.lua)

    for _, module in ipairs({ "Float", "Loot", "Sparkles", "Interact", "Dialog", "Junk", "Auction", "Prices", "Craft", "Misc", "Eat", "Chat", "ChatPlus", "ChatWindow", "Trad", "Resources", "ResourceBar", "HealerMana", "SwingBar", "Procs", "Buffs", "MobControls", "Plates", "Threat", "Gains", "Quests",
        "QuestCards", "QuestWindow", "BagWindow", "CharWindow", "GameSettings", "Tweaks", "QuestPage", "DungeonSkin", "DungeonPlus", "LootRolls", "Launcher", "UI" }) do
        -- un module qui plante au démarrage ne doit pas empêcher les suivants (icône, fenêtre d'options) : l'erreur
        -- part quand même dans le gestionnaire d'erreurs du jeu
        if ns[module] and ns[module].Init then
            local ok, err = pcall(ns[module].Init, ns[module])
            if not ok then
                local handler = rawget(_G, "geterrorhandler")
                if handler then pcall(handler(), "Platyplus " .. module .. " : " .. tostring(err)) end
            end
        end
    end
end)
