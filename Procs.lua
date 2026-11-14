-- Platyplus : alerte de proc avec la touche à presser
-- Quand un sort de tes barres d'action devient utilisable « sur événement », une grande icône apparaît sous ton
-- personnage avec, dessous et en gros, la touche à presser (« 3 », « Maj+E », « Souris 4 »...) :
--  * sorts réactifs : Fulgurance (la cible a esquivé), Vengeance (tu as bloqué, esquivé ou paré), Exécution et
--    Marteau de courroux (cible sous 20 % de vie), Ivresse de la victoire (tu viens de tuer un ennemi), Riposte,
--    Contre-attaque, Morsure de la mangouste. Ils comptent
--    dès que le jeu les dit utilisables (C_ActionBar.IsUsableAction : posture, cible, rage comprises) ;
--  * tout sort que le jeu fait briller lui-même sur les barres (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / HIDE et
--    C_SpellActivationOverlay.IsSpellOverlayed, exactement comme les boutons de Blizzard).
-- Dans les deux cas, pas d'alerte tant que le sort est en recharge (hors temps global) : elle apparaît quand il
-- redevient lançable. Lu avec C_ActionBar.GetActionCooldownDuration(action, true), qui marche aussi en combat.
-- La touche est celle du bouton qui contient le sort : sa liaison (button.bindingAction : « ACTIONBUTTON3 »,
-- « MULTIACTIONBAR1BUTTON5 »...) ou un clic direct sur le bouton, comme le texte que Blizzard écrit sur le bouton.
-- Un sort rangé sur plusieurs boutons : on garde celui qui a une touche, visible de préférence.
--
-- Vérifié dans le code de Forever (Blizzard_ActionBar/Shared/ActionButton.lua et la doc API générée) :
--  * GetActionInfo(emplacement) -> "spell", spellID (ou "macro", spellID, "spell") ; button.action = emplacement
--    affiché (page et posture comprises) ; button.bindingAction = commande de la touche (UpdateHotkeys) ;
--  * IsUsableAction et IsSpellOverlayed ne renvoient pas de valeurs secrètes ;
--  * C_ActionBar.GetActionCooldown peut être secret en combat (SecretWhenCooldownsRestricted) ; GetActionCooldownDuration
--    (objet durée, argument ignoreGCD) n'est pas marqué ainsi et son IsActive() renvoie un booléen. NON VÉRIFIÉ en
--    jeu : si IsActive() est quand même secret, retour à GetActionCooldown et l'alerte reste affichée en recharge.
-- Numéros des sorts vérifiés dans la table SpellName du client (build 1.60.1.70245) : 7384, 7887, 11584 et 11585
-- = « Fulgurance », etc. Ivresse de la victoire : 402927 et 403434 (version « rune » ; le 34428 classique n'existe pas
-- dans Forever), vérifiés dans SpellName (wago.tools, build 1.60.1.70245, frFR « Ivresse de la victoire »).
-- NON VÉRIFIÉ en jeu : si Forever fait briller Fulgurance lui-même (sinon c'est la liste des sorts réactifs qui la
-- trouve), et le moment exact où le jeu signale le changement d'état utilisable.
--
-- Sorts surveillés, toutes les classes (demande du joueur : « on a trop spécialisé nos procs sur le war ») :
--  * procReactive : les sorts réactifs de la liste ci-dessus (guerrier, voleur, chasseur, paladin) ;
--  * procGlow : tout sort que le jeu fait briller. C'est ce qui couvre mage, démoniste, prêtre, druide et chaman :
--    leurs procs et leurs runes passent par la brillance du jeu, pas par une liste ici (NON VÉRIFIÉ en jeu : aucun sort
--    de ces classes n'est confirmé « utilisable sur événement » par SpellName/SpellCooldowns) ;
--  * procExtra : sorts ajoutés par le joueur, annoncés dès qu'ils sont sur une barre, utilisables et hors recharge ;
--  * procIgnore : jamais d'alerte, même si le sort brille ; reconnu aussi par son nom (tous les rangs).
-- Affichage : procMax (1 à 6 alertes), procShowKey / procShowName (la hauteur suit : pas de trou), procAnim
-- (« vif » = l'animation d'origine, « doux » = le halo respire seulement, « aucune » = icône fixe), procSound (un petit
-- son à l'apparition, au plus 1 par seconde ; SOUNDKIT.UI_BNET_TOAST, vérifié dans le code de Forever : BNet.lua et
-- Blizzard_DelvesToast.lua), procOpacity. Réglages par défaut = comportement d'origine du guerrier.
--
-- Animation (retour du joueur : « pas assez animé ») :
--  * entrée : l'icône jaillit (petite -> un peu trop grande -> sa taille) avec un éclair blanc et un éclat du halo ;
--  * ensuite un battement toutes les 1,1 s : deux ondes dorées partent de l'icône, le halo s'allume puis
--    s'éteint doucement et la pastille de la touche gonfle en virant à l'or ; un reflet balaie l'icône toutes les 2 s ;
--  * sortie : « pouf », l'alerte grossit un peu en s'effaçant ; les autres glissent pour se recentrer.
-- Optimisation : relecture pilotée par les événements (Resources.lib regroupe ceux des barres d'action, le reste
-- est regroupé ici aussi) ; la boucle OnUpdate ne tourne que pendant qu'une alerte est affichée ou sort (animation,
-- contrôle 4 fois par seconde pour qu'une alerte ne traîne jamais) ; alertes réutilisées, rien créé par image.
--
-- Icône de Maîtrise du blocage (réglage procBlock ; demande du joueur : « mon nombre de stacks de Maîtrise du blocage
-- à côté des procs », puis « détecte juste si j'ai la Maîtrise du blocage d'active, c'est tout » : donc pas de
-- chiffre) : une petite icône posée à droite des alertes (ou seule, au centre, quand aucune alerte n'est affichée) tant
-- que le buff est sur toi. « Maîtrise du blocage » est le nom français de Shield Block (sort 2565, vérifié dans
-- SpellName, wago.tools, build 1.60.1.70245, frFR ; 7 s, 2 charges).
-- Vérifié dans le code de Forever (doc API générée) : les auras du joueur sont secrètes quand le jeu les restreint
-- (SecretWhenUnitAuraRestricted) et GetPlayerAuraBySpellID ne renvoie alors RIEN (RequiresNonSecretAura) ; la
-- réponse de C_Secrets.ShouldSpellAuraBeSecret dit si « rien » veut dire « pas d'aura ». Retour du joueur en jeu
-- (2026-11-07) : en combat le jeu cache bien ce buff. Alors on le suit par son numéro d'instance (voir trackIDs) :
-- ton lancer est lisible (UNIT_SPELLCAST_SUCCEEDED), le buff qui apparaît juste après est le tien, et la disparition de
-- son numéro retire l'icône aussitôt. Sans numéros lisibles : icône pendant la durée du buff après ton lancer.
-- Aucun calcul sur une valeur secrète.
-- Charges (retour du joueur 2026-11-07 : l'icône restait jusqu'à la fin du buff alors que tous les blocages étaient
-- partis ; il veut voir les charges restantes et une animation à chacune) : 2 charges (ProcCharges de 2565), chaque
-- coup bloqué en retire une (UNIT_COMBAT, lisible en combat, voir onBlocked) ; à zéro l'icône s'en va. Le compte
-- est corrigé par l'aura dès que le jeu la montre, et le maximum lu y est retenu (procBlockMax, talents).
-- NON VÉRIFIÉ en jeu : que GetUnitAuraInstanceIDs donne des nombres lisibles pour toi en combat, le moment exact où le
-- buff apparaît par rapport à ton lancer, et qu'UNIT_COMBAT arrive pour chaque blocage partiel (/pp proc affiche
-- l'état de chaque étape et le nombre de blocages comptés ; /pp proc debug les écrit dans le chat).
local ADDON, ns = ...

local Procs = {}
ns.Procs = Procs

local NAME = "alertes de proc"     -- nom affiché par le garde-fou s'il coupe les alertes
local ICON = 52                    -- côté de l'icône
local PILL_H = 26                  -- pastille de la touche, à cheval sur le bas de l'icône
local PILL_OVERLAP = 10
local NAME_GAP, NAME_H = 3, 14     -- nom du sort sous la pastille
local NAME_MAX_W = 140
local GAP = 18                     -- écart entre deux alertes
local MAX_ALERTS = 3                -- valeur par défaut de procMax
local MAX_ALERTS_LIMIT = 6
local SOUND_EVERY = 1              -- au plus un son par seconde
local GCD_MAX = 1.6                -- recharge plus longue que ça : ce n'est plus le temps global
local RECHECK = 0.25               -- contrôle pendant qu'une alerte est affichée
local FLUSH_DELAY = 0.05           -- regroupe les rafales d'événements
-- animation
local FADE_IN = 0.12                       -- fondu d'entrée
local POP_TIME, POP_FROM = 0.32, 0.35      -- l'icône jaillit : 35 % -> un peu plus grande -> sa taille
local FLASH_TIME = 0.25                    -- éclair blanc sur l'icône à l'apparition
local BURST = 0.35                         -- éclat du halo à l'apparition
local BEAT = 1.1                           -- un battement toutes les 1,1 s : ondes, halo, touche qui gonfle
local RINGS, RING_GAP, RING_TIME = 2, 0.16, 0.7   -- deux ondes dorées par battement, à 0,16 s d'écart
local HEART_TIME = 0.28                    -- la pastille de la touche gonfle puis revient
local GLOW_DECAY = 0.7                     -- le halo s'éteint doucement après chaque battement
local SHINE_EVERY, SHINE_TIME = 2.0, 0.5   -- reflet qui balaie l'icône
local SHINE_ANGLE = math.rad(-30)
local OUT_TIME = 0.2                       -- sortie : « pouf », l'alerte grossit un peu et s'efface
local SLIDE_SPEED = 14                     -- vivacité du glissement quand une alerte arrive ou part
local PREVIEW_SECONDS = 5
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local SAMPLE_SPELL, SAMPLE_KEY = 7384, "3"   -- aperçu sans sort réactif sur les barres : Fulgurance sur « 3 »
-- Maîtrise du blocage (Shield Block)
local BLOCK_IDS = { 2565, 467891, 12169 }      -- le sort et ses autres numéros ; leur nom est aussi reconnu
local BLOCK_SET = {}
for _, id in ipairs(BLOCK_IDS) do BLOCK_SET[id] = true end
local BLOCK_GUARD = "icône de blocage"         -- nom affiché par le garde-fou : une erreur ici ne coupe pas les alertes
local BLOCK_DURATION = 7                       -- durée du buff (SpellDuration, build 1.60.1.70245) tant qu'on ne l'a pas lue
local BLOCK_WINDOW = 1.5                       -- après ton lancer, on cherche le nouveau buff pendant ce temps (secondes)
local BLOCK_GRACE = 3                          -- au plus ce délai au-delà de la durée, même si le numéro suivi est toujours là
local BLOCK_SETTLE = 0.35                      -- on choisit le buff ce temps après ton lancer (secondes)
local BLOCK_RACE = 0.4                         -- point de départ : ta liste de buffs d'il y a ce temps (secondes)
local CHIP_ICON = 40                           -- côté de l'icône du buff
-- charges : nombre de blocages que le buff encaisse (ProcCharges, table SpellAuraOptions du client, build 1.60.1.70245 :
-- 2565 = 2 ; 12169 et 467891 = 1). Relu sur l'aura quand le jeu la montre (talents), et retenu.
local BLOCK_CHARGES = { [2565] = 2, [12169] = 1, [467891] = 1 }
local BLOCK_DEFAULT_CHARGES = 2
local PIPS_MAX, PIP_H, PIP_GAP, PIP_SPACING = 5, 4, 5, 3   -- jauge sous l'icône : une barrette par charge
local BADGE = 20                               -- pastille du nombre de charges, au coin de l'icône
local CHIP_ENTER, CHIP_LOSE, CHIP_OUT = 0.3, 0.6, 0.28     -- animations : apparition, charge perdue, départ
local CHIP_LEAVE_DELAY = 0.25                  -- dernière charge : on voit la perte, puis l'icône s'en va
local SPENT = { 0.22, 0.24, 0.30, 0.85 }       -- barrette d'une charge consommée

-- sorts réactifs, tous les rangs ; leurs noms sont relus dans le jeu pour reconnaître aussi un autre numéro
local REACTIVE_IDS = {
    7384, 7887, 11584, 11585,                  -- Fulgurance (guerrier, après une esquive de la cible)
    6572, 6574, 7379, 11600, 11601, 25288,     -- Vengeance (guerrier, après un blocage, une esquive ou une parade)
    5308, 20658, 20660, 20661, 20662,          -- Exécution (guerrier, cible sous 20 % de vie)
    402927, 403434,                            -- Ivresse de la victoire (guerrier, rune ; après avoir tué un ennemi)
    14251,                                     -- Riposte (voleur, après une parade)
    19306, 20909, 20910,                       -- Contre-attaque (chasseur, après une parade)
    1495, 14269, 14270, 14271,                 -- Morsure de la mangouste (chasseur, après une esquive de la cible)
    24275, 24274, 24239,                       -- Marteau de courroux (paladin, cible sous 20 % de vie)
    409379,                                    -- Ordre de tuer (chasseur, rune ; après un coup critique) ; les autres
                                               -- numéros du même nom (409396, 409418) sont reconnus par leur nom
}
local REACTIVE = {}
for _, id in ipairs(REACTIVE_IDS) do REACTIVE[id] = true end
Procs.REACTIVE = REACTIVE

-- Recharge propre de ces sorts, en secondes (table SpellCooldowns du client, build 1.60.1.70245 : le plus long de
-- RecoveryTime et CategoryRecoveryTime). Ivresse de la victoire : 30 s dans Forever. Retour du joueur (2026-11-07) :
-- « des fois ça me dit que je peux faire Ivresse de la victoire pourtant il est CD » : en combat le jeu cache la
-- recharge (valeurs secrètes, isOnGCD parfois absent), alors on retient aussi l'heure de TON lancer (lisible) et
-- cette durée. Exécution n'a pas de recharge (0) : absente.
local BASE_CD = {
    [7384] = 5, [7887] = 5, [11584] = 5, [11585] = 5,                         -- Fulgurance
    [6572] = 5, [6574] = 5, [7379] = 5, [11600] = 5, [11601] = 5, [25288] = 5, -- Vengeance
    [402927] = 30, [403434] = 30,                                             -- Ivresse de la victoire
    [14251] = 6,                                                              -- Riposte
    [19306] = 5, [20909] = 5, [20910] = 5,                                    -- Contre-attaque
    [1495] = 5, [14269] = 5, [14270] = 5, [14271] = 5,                        -- Morsure de la mangouste
    [24275] = 6, [24274] = 6, [24239] = 6,                                    -- Marteau de courroux
    [409379] = 60,                                                            -- Ordre de tuer (RecoveryTime 60000 ms)
}
Procs.BASE_CD = BASE_CD

-- Sorts réactifs par classe (jeton anglais de UnitClass), pour les afficher dans les options : { numéro d'un rang, nom
-- français de repli si le jeu ne le donne pas }. Noms et numéros vérifiés dans SpellName (wago.tools, build 1.60.1.70245,
-- frFR) ; « utilisable sur événement » vient de la liste de sorts réactifs ci-dessus, NON VÉRIFIÉ en jeu pour
-- Ordre de tuer (chasseur, rune) : si le jeu ne le dit pas utilisable au bon moment, il reste annoncé s'il brille.
-- Mage, démoniste, prêtre, druide, chaman : rien ici, leurs procs passent par la brillance du jeu (procGlow).
local CLASS_REACTIVE = {
    WARRIOR = { { 7384, "Fulgurance" }, { 6572, "Vengeance" }, { 5308, "Exécution" }, { 402927, "Ivresse de la victoire" } },
    ROGUE   = { { 14251, "Riposte" } },
    HUNTER  = { { 19306, "Contre-attaque" }, { 1495, "Morsure de la mangouste" }, { 409379, "Ordre de tuer" } },
    PALADIN = { { 24239, "Marteau de courroux" } },
}

local EVENTS = {
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "UPDATE_BINDINGS",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local lib                                      -- Resources.lib (barres d'action, garde-fou), branché dans Init
local isSecret = function() return false end
local root, mover, events
local pool, active, order = {}, {}, {}         -- alertes libres ; [spellID] = alerte affichée ; ordre d'affichage
local dying = {}                               -- alertes en train de sortir (animation « pouf »)
local overlayed = {}                           -- [spellID] = true : le jeu le fait briller
local reactiveNames, reactiveCache = nil, {}
local previewUntil = 0
local queued, recheck = false, 0
local waiting = false                              -- un réveil est déjà prévu pour la fin d'une recharge
local refresh                                  -- relecture protégée par le garde-fou (créée dans Init)
local chip                                     -- icône de Maîtrise du blocage (créée dans build)
local chipKind                                 -- true tant que l'icône est montrée
local rowTotal = 0                             -- largeur de la rangée d'alertes (l'icône se pose à sa droite)
local blockUntil, blockDuration = 0, nil       -- fin supposée du buff d'après ton lancer ; durée lue sur l'aura
local idHistory, pendingBase, pendingUntil, castAt = {}, nil, 0, 0   -- numéros d'instance de tes buffs : historique ; ceux d'avant ton lancer
local blockInstance, blockCandidates = nil, 0  -- numéro d'instance de TON buff de blocage, quand le jeu cache les auras
local blockTimer, blockQueued = 0, false
local blockCharges, blockMax = nil, nil        -- charges restantes / au départ (comptées : voir onBlocked)
local blockSpent, spentAt = false, 0           -- toutes les charges consommées depuis ton dernier lancer
local blocksCounted = 0                        -- (pour /pp proc)
local refreshBlock                             -- relecture du buff protégée par le garde-fou (créée dans Init)
local lastCast, lastCastByName, learnedCD = {}, {}, {}   -- tes lancers (heure par sort, par nom) ; recharges lues en jeu

Procs.active = active
Procs.order = order
Procs.dying = dying

---------------------------------------------------------------------------
-- Lecture du jeu
---------------------------------------------------------------------------
local function api(name) return rawget(_G, name) end

local function plain(v)
    if v == nil or isSecret(v) then return nil end
    return v
end

local function spellAPI(method)
    local s = api("C_Spell")
    return type(s) == "table" and s[method] or nil
end

-- les noms ne changent pas pendant la session : cache (jamais un nil ni un secret)
local nameCache = {}

local function spellName(id)
    local cached = nameCache[id]
    if cached then return cached end
    local fn = spellAPI("GetSpellName")
    if fn then
        local ok, name = pcall(fn, id)
        name = ok and plain(name)
        if type(name) == "string" and name ~= "" then
            if id ~= nil then nameCache[id] = name end
            return name
        end
    end
    local info = spellAPI("GetSpellInfo")
    if info then
        local ok, t = pcall(info, id)
        if ok and type(t) == "table" then
            local name = plain(t.name)
            if type(name) == "string" and name ~= "" then
                if id ~= nil then nameCache[id] = name end
                return name
            end
        end
    end
    return nil
end

local function spellTexture(id, action)
    local bar = api("C_ActionBar")
    if action and type(bar) == "table" and type(bar.GetActionTexture) == "function" then
        local ok, tex = pcall(bar.GetActionTexture, action)
        tex = ok and plain(tex)
        if tex then return tex end
    end
    local fn = spellAPI("GetSpellTexture")
    if fn and id then
        local ok, tex = pcall(fn, id)
        tex = ok and plain(tex)
        if tex then return tex end
    end
    return QUESTION
end

local function reactiveNameSet()
    if reactiveNames then return reactiveNames end
    local set, any = {}, false
    for _, id in ipairs(REACTIVE_IDS) do
        local name = spellName(id)
        if name then set[name], any = true, true end
    end
    if any then reactiveNames = set end        -- noms pas encore chargés par le jeu : on réessaiera
    return set
end

-- sort réactif (Fulgurance, Vengeance...) ? Par numéro, sinon par nom (autre rang)
function Procs.IsReactive(id)
    if not id then return false end
    if REACTIVE[id] then return true end
    local known = reactiveCache[id]
    if known ~= nil then return known end
    local name = spellName(id)
    local set = reactiveNameSet()
    local yes = name ~= nil and set[name] == true
    if reactiveNames then reactiveCache[id] = yes end   -- on ne retient un « non » qu'une fois les noms connus
    return yes
end

-- ta classe (jeton anglais : « WARRIOR »), nil si illisible
local function playerClass()
    local fn = api("UnitClass")
    if type(fn) ~= "function" then return nil end
    local ok, _, token = pcall(fn, "player")
    if ok and not isSecret(token) and type(token) == "string" then return token end
    return nil
end

-- sorts réactifs connus pour ta classe : { { spellID, nom }, ... } (pour les options et /pp proc)
function Procs.ClassDefaults()
    local out = {}
    for _, e in ipairs(CLASS_REACTIVE[playerClass()] or {}) do
        out[#out + 1] = { spellID = e[1], name = spellName(e[1]) or e[2] }
    end
    return out
end

-- liste du joueur (procExtra / procIgnore) -> ensemble de numéros et ensemble de noms (tous les rangs)
-- Mémorisé tant que la table du réglage reste la même (ns:Set en écrit une nouvelle) et
-- tant que tous les noms sont connus.
local setsCache = {}
local function listSets(key)
    local list = ns.db and ns.db[key]
    local hit = setsCache[key]
    if hit and hit.list == list then return hit.ids, hit.names end
    local ids, names = {}, {}
    local complete = true
    if type(list) == "table" then
        for id, on in pairs(list) do
            id = tonumber(id)
            if on and id then
                ids[id] = true
                local name = spellName(id)
                if name then names[name] = true else complete = false end
            end
        end
    end
    if complete then setsCache[key] = { list = list, ids = ids, names = names } end
    return ids, names
end

local function inSets(id, ids, names)
    if ids[id] then return true end
    if next(names) == nil then return false end
    local name = spellName(id)
    return name ~= nil and names[name] == true
end

-- nombre d'alertes en même temps (1 à 6)
local function maxAlerts()
    local n = tonumber(ns.db.procMax)
    if not n then return MAX_ALERTS end
    n = math.floor(n + 0.5)
    if n < 1 then return 1 end
    if n > MAX_ALERTS_LIMIT then return MAX_ALERTS_LIMIT end
    return n
end

local function animMode()
    local a = ns.db.procAnim
    if a == "doux" or a == "aucune" then return a end
    return "vif"
end

local function isOverlayed(id)
    if overlayed[id] then return true end
    local o = api("C_SpellActivationOverlay")
    if type(o) == "table" and type(o.IsSpellOverlayed) == "function" then
        local ok, v = pcall(o.IsSpellOverlayed, id)
        return ok and not isSecret(v) and v == true
    end
    return false
end

-- utilisable, manque de ressource (booléens)
local function usableState(action)
    local bar = api("C_ActionBar")
    local fn = (type(bar) == "table" and bar.IsUsableAction) or api("IsUsableAction")
    if type(fn) ~= "function" then return false, false end
    local ok, usable, lacking = pcall(fn, action)
    if not ok or isSecret(usable) or isSecret(lacking) then return false, false end
    return usable and true or false, lacking and true or false
end

-- en recharge (hors temps global) ? Renvoie « en recharge », « secondes restantes (ou nil) ».
-- 1) objet durée de l'action, sans le temps global : fonctionne même en combat, où GetActionCooldown est secret.
--    Dans le jeu c'est un userdata (LuaDurationObjectAPI : ObjectType = "Userdata"), pas une table : ne tester
--    que « table » le faisait toujours ignorer en jeu (retour du joueur : alerte pendant la recharge de Fulgurance) ;
-- 2) sinon GetActionCooldown : début et durée peuvent être secrets en combat, mais isActive et isOnGCD ne le sont
--    jamais (SpellSharedDocumentation.lua : NeverSecret) -> « active et pas le temps global » = en recharge.
--    Seulement si isOnGCD manque : on ne sait pas, donc « pas en recharge ».
-- 0) avant tout : ton propre lancer, lisible même en combat (UNIT_SPELLCAST_SUCCEEDED), plus la recharge connue du sort
--    (BASE_CD, ou celle lue quand le jeu la montrait) : lancé il y a moins que sa recharge = en recharge, quoi que
--    disent les autres moyens (retour du joueur : Ivresse de la victoire annoncée pendant sa recharge).
-- nom -> recharge de base, précalculé (refait tant que des noms manquent)
local baseCdNames
local function baseCdByName()
    if baseCdNames then return baseCdNames end
    local set, all = {}, true
    for other, cd in pairs(BASE_CD) do
        local n = spellName(other)
        if n then set[n] = cd else all = false end
    end
    if all then baseCdNames = set end
    return set
end

local function cooldownOf(id)
    if not id then return nil end
    if learnedCD[id] then return learnedCD[id] end
    if BASE_CD[id] then return BASE_CD[id] end
    local name = spellName(id)
    if name then return baseCdByName()[name] end
    return nil
end

-- secondes de recharge qu'il reste d'après ton dernier lancer de ce sort (ou d'un sort du même nom) ; nil sinon
local function castCooldownLeft(id)
    local cd = cooldownOf(id)
    if not cd or cd <= GCD_MAX then return nil end
    local t = lastCast[id]
    local name = spellName(id)
    if name and lastCastByName[name] and (not t or lastCastByName[name] > t) then t = lastCastByName[name] end
    if not t then return nil end
    local left = t + cd - GetTime()
    if left > 0.05 then return left end
    return nil
end
Procs.CastCooldownLeft = castCooldownLeft

-- tu viens de lancer un sort (lisible pour toi) : retenu pour savoir qu'il est en recharge
local function noteCast(id)
    if id == nil or isSecret(id) or type(id) ~= "number" then return end
    local now = GetTime()
    lastCast[id] = now
    local name = spellName(id)
    if name then lastCastByName[name] = now end
end

local function onCooldown(action, spellID)
    local castLeft = castCooldownLeft(spellID)
    if castLeft then return true, castLeft end
    local bar = api("C_ActionBar")
    if type(bar) ~= "table" then return false end
    if type(bar.GetActionCooldownDuration) == "function" then
        local ok, d = pcall(bar.GetActionCooldownDuration, action, true)
        local kind = ok and type(d)
        if (kind == "userdata" or kind == "table") and type(d.IsActive) == "function" then
            local okActive, active = pcall(d.IsActive, d)
            if okActive and not isSecret(active) and type(active) == "boolean" then
                if not active then return false end
                local left
                if type(d.GetRemainingDuration) == "function" then
                    local okLeft, v = pcall(d.GetRemainingDuration, d)
                    if okLeft and not isSecret(v) then left = tonumber(v) end
                end
                return true, left
            end
        end
    end
    if type(bar.GetActionCooldown) ~= "function" then return false end
    local ok, info = pcall(bar.GetActionCooldown, action)
    if not ok or type(info) ~= "table" then return false end
    if info.isActive == false then return false end
    local start, duration = info.startTime, info.duration
    if isSecret(start) or isSecret(duration) then
        if info.isActive == true and info.isOnGCD == false then return true, nil end   -- vraie recharge, durée inconnue
        return false
    end
    start, duration = tonumber(start), tonumber(duration)
    if not start or not duration or duration <= GCD_MAX then return false end
    if spellID and info.isOnGCD ~= true and not learnedCD[spellID] then learnedCD[spellID] = duration end   -- recharge lue : retenue
    local left = start + duration - GetTime()
    return left > 0.1, left
end

local function bindingKey(command)
    local fn = api("GetBindingKey")
    if type(fn) ~= "function" or type(command) ~= "string" then return nil end
    local ok, key = pcall(fn, command)
    if ok and type(key) == "string" and key ~= "" then return key end
    return nil
end

-- touche du bouton : sa commande (comme Blizzard dans UpdateHotkeys), sinon un clic direct sur le bouton
local function keyOf(button)
    if not button then return nil end
    local key = bindingKey(button.bindingAction) or bindingKey(button.commandName)
    if not key and button.GetName then
        local name = button:GetName()
        if name then key = bindingKey("CLICK " .. name .. ":LeftButton") end
    end
    return key
end

---------------------------------------------------------------------------
-- Texte de la touche : « SHIFT-3 » -> « Maj+3 », « BUTTON4 » -> « Souris 4 »...
---------------------------------------------------------------------------
local MODIFIERS = { SHIFT = "Maj", CTRL = "Ctrl", ALT = "Alt", META = "Cmd" }
local KEY_NAMES = {
    BUTTON1 = "Clic gauche", BUTTON2 = "Clic droit", MOUSEWHEELUP = "Molette haut", MOUSEWHEELDOWN = "Molette bas",
    SPACE = "Espace", ESCAPE = "Échap", ENTER = "Entrée", BACKSPACE = "Retour", TAB = "Tab",
    PLUS = "+", MINUS = "-", MULTIPLY = "*", DIVIDE = "/", DECIMAL = ",",
}

function Procs.KeyText(key)
    if type(key) ~= "string" or key == "" then return nil end
    local parts, main = {}, key
    while true do
        local mod, rest = main:match("^(%u+)%-(.+)$")
        if not (mod and MODIFIERS[mod]) then break end
        parts[#parts + 1] = ns.T(MODIFIERS[mod])
        main = rest
    end
    local text
    local mouse = main:match("^BUTTON(%d+)$")
    local pad = main:match("^NUMPAD(.+)$")
    if KEY_NAMES[main] then
        text = ns.T(KEY_NAMES[main])
    elseif mouse then
        text = ns.Tf("Souris %s", mouse)
    elseif pad then
        text = ns.Tf("Pavé %s", ns.T(KEY_NAMES[pad]) or pad)
    elseif #main > 1 then
        local localized = rawget(_G, "KEY_" .. main)   -- nom du jeu (« Page préc. »...) ; nil sans être une erreur
        text = (type(localized) == "string" and localized ~= "") and localized or main
    else
        text = main
    end
    parts[#parts + 1] = text
    return table.concat(parts, "+")
end

---------------------------------------------------------------------------
-- Sorts à annoncer maintenant
---------------------------------------------------------------------------
-- le rappel de buffs (Buffs.lua : Cri de guerre manquant en combat) passe aussi par ces alertes
local function buffsWanted()
    local B = ns.Buffs
    return B ~= nil and B.WantsAlerts ~= nil and B:WantsAlerts()
end

-- liste { spellID, action, button, key, usable, lacking, glow[, name] } dans l'ordre des barres (barre principale
-- d'abord), puis les buffs manquants (Buffs.lua)
function Procs:Collect()
    local list, bySpell = {}, {}
    Procs.waitFor = nil
    if not lib then return list end
    -- un sort sur plusieurs boutons : on garde celui qui a une touche, visible de préférence
    local function add(id, action, button, usable, lacking, glow, name)
        local key = keyOf(button)
        local visible = (button and button.IsVisible and button:IsVisible()) and true or false
        local score = (key and 2 or 0) + (visible and 1 or 0)
        local e = bySpell[id]
        if not e then
            e = { spellID = id, score = -1 }
            bySpell[id] = e
            list[#list + 1] = e
        end
        if score > e.score then
            e.action, e.button, e.key, e.score = action, button, key, score
            e.usable, e.lacking, e.glow, e.name = usable, lacking, glow, name
        end
    end
    if ns.db.procAlert then
        local useReactive, useGlow = ns.db.procReactive ~= false, ns.db.procGlow ~= false
        local ignoreIds, ignoreNames = listSets("procIgnore")
        local extraIds, extraNames = listSets("procExtra")
        for _, a in ipairs(lib.actions()) do
            local id, action, button = a.spellID, a.action, a.button
            if id and action and not inSets(id, ignoreIds, ignoreNames) then
                local glow = useGlow and isOverlayed(id)
                local usable, lacking = usableState(action)
                local candidate = glow or (usable and ((useReactive and Procs.IsReactive(id))
                    or inSets(id, extraIds, extraNames)))
                local cooling, left = false, nil
                if candidate then cooling, left = onCooldown(action, id) end
                if candidate and cooling then
                    -- proc là mais sort pas lançable (recharge) : pas d'alerte, on regarde quand il revient
                    local wait = left or RECHECK
                    if not Procs.waitFor or wait < Procs.waitFor then Procs.waitFor = wait end
                elseif candidate then
                    add(id, action, button, usable, lacking, glow)
                end
            end
        end
    end
    if buffsWanted() then
        for _, r in ipairs(ns.Buffs:Reminders()) do
            if r.spellID and r.action and not (bySpell[r.spellID] and bySpell[r.spellID].name == nil) then
                local usable, lacking = usableState(r.action)
                add(r.spellID, r.action, r.button, usable, lacking, false, r.name)
            end
        end
    end
    return list
end

-- sorts surveillés (réactifs si activés, ajoutés par toi ; pas les ignorés) rangés sur les barres, un par sort, avec la
-- touche d'un de ses boutons s'il en a une
local function reactiveOnBars()
    local list, bySpell = {}, {}
    if not lib then return list end
    local useReactive = ns.db.procReactive ~= false
    local ignoreIds, ignoreNames = listSets("procIgnore")
    local extraIds, extraNames = listSets("procExtra")
    for _, a in ipairs(lib.actions()) do
        local id = a.spellID
        if id and not inSets(id, ignoreIds, ignoreNames)
            and ((useReactive and Procs.IsReactive(id)) or inSets(id, extraIds, extraNames)) then
            local e = bySpell[id]
            if not e then
                e = { spellID = id, action = a.action, button = a.button, usable = true }
                bySpell[id] = e
                list[#list + 1] = e
            end
            if not e.key then
                local key = keyOf(a.button)
                if key then e.key, e.action, e.button = key, a.action, a.button end
            end
        end
    end
    return list
end

-- aperçu : un sort réactif de tes barres (avec une touche de préférence), sinon Fulgurance sur « 3 »
local function sample()
    local list = reactiveOnBars()
    for _, e in ipairs(list) do
        if e.key then return e end
    end
    if list[1] then return list[1] end
    return { spellID = SAMPLE_SPELL, key = SAMPLE_KEY, usable = true, name = spellName(SAMPLE_SPELL) or "Fulgurance" }
end

-- /pp proc : sorts réactifs rangés sur les barres et leur touche (pour vérifier en jeu, même hors combat)
function Procs:Describe()
    local lines = {}
    for _, e in ipairs(reactiveOnBars()) do
        local text = Procs.KeyText(e.key)
        local sname = spellName(e.spellID) or ns.Tf("sort %d", e.spellID)
        lines[#lines + 1] = sname .. " : "
            .. (text and ns.Tf("touche |cffffd133%s|r", text) or ns.T("|cffff6060aucune touche|r"))
    end
    return lines
end

-- noms des sorts d'une liste du joueur (procExtra / procIgnore), triés
local function listNames(key)
    local out = {}
    local list = ns.db[key]
    if type(list) == "table" then
        for id, on in pairs(list) do
            id = tonumber(id)
            if on and id then out[#out + 1] = (spellName(id) or ns.T("sort")) .. " (" .. id .. ")" end
        end
    end
    table.sort(out)
    return out
end

-- /pp proc : sorts surveillés de ta classe, ajoutés et ignorés
function Procs:Summary()
    local lines = {}
    local names = {}
    for _, e in ipairs(Procs.ClassDefaults()) do names[#names + 1] = e.name end
    lines[#lines + 1] = ns.Tf("réactifs de ta classe (%s) : %s",
        ns.db.procReactive ~= false and ns.T("actifs") or ns.T("coupés"),
        #names > 0 and table.concat(names, ", ") or ns.T("aucun, ta classe passe par la brillance du jeu"))
    lines[#lines + 1] = ns.Tf("brillance du jeu (%s)", ns.db.procGlow ~= false and ns.T("active") or ns.T("coupée"))
    local extra, ignored = listNames("procExtra"), listNames("procIgnore")
    lines[#lines + 1] = ns.Tf("ajoutés : %s", #extra > 0 and table.concat(extra, ", ") or ns.T("aucun"))
    lines[#lines + 1] = ns.Tf("ignorés : %s", #ignored > 0 and table.concat(ignored, ", ") or ns.T("aucun"))
    return lines
end

---------------------------------------------------------------------------
-- Charges de Maîtrise du blocage (lecture)
---------------------------------------------------------------------------
local function inCombatNow()
    local fn = api("InCombatLockdown")
    return type(fn) == "function" and fn() and true or false
end

-- le jeu cache-t-il cette aura en ce moment ? (alors « aucune aura trouvée » ne prouve rien)
local function blockAuraHidden()
    local sec = api("C_Secrets")
    if type(sec) == "table" and type(sec.ShouldSpellAuraBeSecret) == "function" then
        local ok, hidden = pcall(sec.ShouldSpellAuraBeSecret, BLOCK_IDS[1])
        return (not ok) or isSecret(hidden) or hidden == true
    end
    return inCombatNow()                       -- API absente : en combat, « rien » ne veut rien dire
end

-- l'aura sur toi : par numéro, sinon par nom (autre numéro du même sort). Second résultat : trouvée par le nom.
local function blockAura()
    local ua = api("C_UnitAuras")
    if type(ua) ~= "table" then return nil end
    if type(ua.GetPlayerAuraBySpellID) == "function" then
        for _, id in ipairs(BLOCK_IDS) do
            local ok, a = pcall(ua.GetPlayerAuraBySpellID, id)
            if ok and a ~= nil then return a end
        end
    end
    if type(ua.GetAuraDataBySpellName) == "function" then
        local name = spellName(BLOCK_IDS[1])
        if name then
            local ok, a = pcall(ua.GetAuraDataBySpellName, "player", name, "HELPFUL")
            if ok and a ~= nil then return a, true end
        end
    end
    return nil
end

-- Aura cachée par le jeu (retour du joueur : le buff n'est pas lisible en combat) : on ne peut pas la reconnaître par son
-- sort, mais ton propre lancer est lisible et les numéros d'instance de tes buffs (GetUnitAuraInstanceIDs) sont de
-- simples nombres. On retient donc ceux que tu avais avant de lancer ; le buff qui apparaît juste après (BLOCK_WINDOW)
-- est le tien, et quand son numéro disparaît de la liste (fin du buff ou dernier blocage consommé) l'icône part.
-- journal pour /pp proc debug : écrit dans le chat ce que l'addon voit autour de ton lancer, pour comprendre un défaut
local debugOn, lastLogged = false, nil
local function dbg(...)
    if not debugOn then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    print("|cff33ccff[blocage]|r " .. table.concat(parts, " "))
end
local function dbgChange(key, ...)                 -- une ligne seulement quand l'état change
    if debugOn and key ~= lastLogged then
        lastLogged = key
        dbg(...)
    end
end

local idsSource, idsError                          -- d'où viennent les numéros ; pourquoi ils sont illisibles

-- numéros d'instance de tes buffs : GetUnitAuraInstanceIDs, sinon parcours GetAuraDataByIndex (auraInstanceID est un
-- nombre ordinaire) ; nil si illisibles. Une liste vide est suspecte (en combat tu as presque toujours un buff) : on
-- essaie alors l'autre moyen.
local function currentAuraIDs()
    idsSource, idsError = nil, nil
    local ua = api("C_UnitAuras")
    if type(ua) ~= "table" then idsError = "C_UnitAuras absent" return nil end
    local best
    if type(ua.GetUnitAuraInstanceIDs) == "function" then
        local ok, list = pcall(ua.GetUnitAuraInstanceIDs, "player", "HELPFUL")
        if not ok then
            idsError = "GetUnitAuraInstanceIDs : " .. tostring(list)
        elseif type(list) ~= "table" or isSecret(list) then
            idsError = "GetUnitAuraInstanceIDs : liste secrète"
        else
            local set, good = {}, true
            for _, id in ipairs(list) do
                if isSecret(id) or type(id) ~= "number" then good = false break end
                set[id] = true
            end
            if good then best, idsSource = set, "GetUnitAuraInstanceIDs" else idsError = "GetUnitAuraInstanceIDs : numéros secrets" end
        end
    end
    if (best == nil or next(best) == nil) and type(ua.GetAuraDataByIndex) == "function" then
        local set, good = {}, true
        for i = 1, 40 do
            local ok, a = pcall(ua.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then
                idsError, good = (idsError and (idsError .. " ; ") or "") .. "GetAuraDataByIndex : " .. tostring(a), false
                break
            end
            if a == nil then break end
            local id = (type(a) == "table" and not isSecret(a)) and a.auraInstanceID or nil
            if id == nil or isSecret(id) or type(id) ~= "number" then
                idsError, good = (idsError and (idsError .. " ; ") or "") .. "GetAuraDataByIndex : n° d'instance illisible", false
                break
            end
            set[id] = true
        end
        if good and (best == nil or next(set) ~= nil) then best, idsSource, idsError = set, "GetAuraDataByIndex", nil end
    end
    return best
end

-- historique de ta liste de buffs (un état à chaque changement vu) : ta liste d'il y a un instant sert de point de
-- départ au lancer, que le jeu ajoute le buff juste avant ou juste après avoir signalé le lancer
local function sameSet(a, b)
    for id in pairs(a) do if not b[id] then return false end end
    for id in pairs(b) do if not a[id] then return false end end
    return true
end

local function noteIDs(ids)
    local last = idHistory[#idHistory]
    if last and sameSet(last.ids, ids) then return end
    idHistory[#idHistory + 1] = { t = GetTime(), ids = ids }
    if #idHistory > 12 then table.remove(idHistory, 1) end
end

local function idsAt(t)                        -- ta liste à l'instant t (la plus ancienne connue avant)
    local found
    for _, e in ipairs(idHistory) do
        if e.t <= t then found = e.ids else break end
    end
    return found or (idHistory[1] and idHistory[1].ids)
end

-- relit les numéros d'instance : retrouve ton buff après un lancer, constate sa fin ; renvoie les numéros lus
local function trackIDs()
    local ids = currentAuraIDs()
    if not ids then
        dbgChange("ids:" .. tostring(idsError), "numéros d'instance illisibles :", idsError or "?")
        return nil
    end
    local n = 0
    for _ in pairs(ids) do n = n + 1 end
    dbgChange("ids:ok:" .. tostring(idsSource), "numéros d'instance lisibles (" .. tostring(idsSource) .. ") :", n, "buffs")
    noteIDs(ids)
    local now = GetTime()
    if pendingBase and now > pendingUntil then
        pendingBase = nil                      -- fenêtre close : plus de recherche
        if not blockInstance then dbg("fenêtre close : aucun nouveau buff trouvé après ton lancer") end
    end
    -- on attend un instant après le lancer (BLOCK_SETTLE) : le buff peut arriver un peu avant ou après le signal du
    -- lancer, et un autre buff peut s'y mêler ; les numéros croissent, le plus récent des nouveaux est le tien
    if pendingBase and now >= castAt + BLOCK_SETTLE then
        local newest, count, found = nil, 0, {}
        for id in pairs(ids) do
            if not pendingBase[id] then
                count = count + 1
                found[#found + 1] = id
                if newest == nil or id > newest then newest = id end
            end
        end
        if newest then
            blockInstance, pendingBase, blockCandidates = newest, nil, count
            table.sort(found)
            dbg("buff retenu : n°", newest, "parmi", count, "nouveau(x) :", table.concat(found, ","))
        end
    end
    if blockInstance and not ids[blockInstance] then
        dbg("n°", blockInstance, "a disparu de ta liste :", pendingBase and "remplacé, on cherche le nouveau" or "buff fini")
        blockInstance = nil
        if not pendingBase then blockUntil = 0 end     -- tu viens de relancer : le nouveau buff va arriver
    end
    return ids
end

-- as-tu le buff maintenant ? Lu directement quand le jeu le permet ; sinon suivi par son numéro d'instance (voir
-- trackIDs) ; à défaut (numéros illisibles), supposé actif pendant sa durée après ton lancer. Garde-fou : un buff suivi
-- n'est jamais gardé plus de BLOCK_GRACE secondes après sa durée normale (mauvais buff retenu, numéro figé...).
local chipLose                                 -- animation « une charge en moins » (définie avec l'icône)

-- charges lues sur l'aura quand le jeu la montre : elles corrigent le compte (et apprennent le maximum, talents compris)
local function syncCharges(aura)
    local n = aura.applications
    if n == nil or isSecret(n) or (tonumber(n) or 0) <= 0 then n = aura.charges end
    if n == nil or isSecret(n) then return end
    n = tonumber(n)
    if not n or n <= 0 then return end
    local most = aura.maxCharges
    most = (most ~= nil and not isSecret(most)) and tonumber(most) or nil
    if blockCharges and n < blockCharges and chipKind and chipLose then
        blockCharges = n
        chipLose()
    end
    blockCharges = n
    local learnt = (most and most > 0) and most or ((GetTime() - castAt < 1.5 or n > (blockMax or 0)) and n or nil)
    if learnt and learnt ~= blockMax then
        blockMax = learnt
        if ns.db then ns.db.procBlockMax = learnt end
    end
end

local function blockActive()
    trackIDs()
    local aura, byName = blockAura()
    if aura ~= nil and type(aura) == "table" and not isSecret(aura) then
        local dur = aura.duration
        if not isSecret(dur) then
            dur = tonumber(dur)
            if byName and (dur or 0) <= 0 then
                aura = nil                     -- même nom, sans durée : le talent passif, pas ton buff
            elseif dur and dur > 0 then
                blockDuration = dur
            end
        end
    end
    -- dernière charge consommée il y a un instant : l'aura peut encore traîner une fraction de seconde
    if aura ~= nil and blockSpent and GetTime() - spentAt < 1 then aura = nil end
    local result, why
    if aura ~= nil then
        if type(aura) == "table" and not isSecret(aura) then syncCharges(aura) end
        blockSpent = false
        result, why = true, "aura lue par son sort"
    elseif blockSpent then                     -- toutes les charges parties (blocages comptés) : plus de buff
        result, why = false, "toutes les charges consommées"
        blockUntil, blockInstance = 0, nil
    elseif blockAuraHidden() then              -- « rien trouvé » ne prouve rien : on se fie au suivi
        if blockInstance then
            result, why = GetTime() < blockUntil + BLOCK_GRACE, "buff suivi n° " .. blockInstance
        else
            result, why = GetTime() < blockUntil, "supposé actif depuis ton lancer (pas de numéro)"
        end
        if not result then blockUntil, blockInstance = 0, nil end
    else
        blockUntil, blockInstance = 0, nil     -- lisible et absente : plus de buff
        result, why = false, "aura lisible et absente"
    end
    dbgChange("active:" .. tostring(result) .. ":" .. tostring(why), "icône", result and "affichée" or "cachée", "(" .. why .. ")")
    return result
end

local function isBlockSpell(id)
    if id == nil or isSecret(id) then return false end
    if BLOCK_SET[id] then return true end
    local name = spellName(BLOCK_IDS[1])
    return name ~= nil and spellName(id) == name
end

-- une ligne pour /pp proc
function Procs:BlockStatus()
    local name = spellName(BLOCK_IDS[1]) or ns.T("Maîtrise du blocage")
    local active = blockActive()
    local text = active and ns.T("active") or ns.T("pas active")
    if active and blockCharges then text = text .. ", " .. ns.Tf("%s/%s charge(s)", tostring(blockCharges), tostring(blockMax or "?")) end
    if blockAuraHidden() then text = text .. ns.T(" (le jeu cache tes buffs : suivi par son numéro et tes blocages, voir détail)") end
    return name .. " : " .. text .. " (" .. (ns.db.procBlock and ns.T("affichage ON") or ns.T("affichage OFF")) .. ")"
end

-- ligne de diagnostic pour /pp proc : où en est chaque étape de la lecture
function Procs:BlockDetails()
    local aura = blockAura()
    local ids = currentAuraIDs()
    local n = 0
    if ids then for _ in pairs(ids) do n = n + 1 end end
    local nOk = blockAuraHidden() and ns.T("oui") or ns.T("non")
    local auraTxt = aura ~= nil and (isSecret(aura) and ns.T("secrète") or ns.T("oui")) or ns.T("non")
    local idsTxt = ids and ns.Tf("%d lisibles (%s)", n, tostring(idsSource)) or ns.Tf("illisibles : %s", tostring(idsError))
    local instTxt
    if blockInstance then
        instTxt = ns.Tf(blockCandidates > 1 and "n° %s (%d candidats)" or "n° %s (%d candidat)", tostring(blockInstance), blockCandidates)
    else
        instTxt = pendingBase and ns.T("recherché") or ns.T("aucun")
    end
    return ns.Tf("  détail : auras cachées %s, aura lue par son sort %s, numéros d'instance %s, buff suivi %s, charges %s (maximum %s), blocages comptés depuis le chargement : %d",
        nOk, auraTxt, idsTxt, instTxt,
        blockCharges and tostring(blockCharges) or ns.T("inconnues"), tostring(blockMax or ns.db.procBlockMax or BLOCK_DEFAULT_CHARGES),
        blocksCounted)
end

-- /pp proc debug : active ou coupe le journal du suivi dans le chat
function Procs:ToggleDebug()
    debugOn, lastLogged = not debugOn, nil
    if debugOn then
        ns:Print("journal du blocage : ON. Clique Maîtrise du blocage en combat, bloque des coups, laisse finir le buff, "
            .. "puis recopie les lignes [blocage] du chat.")
    else
        ns:Print("journal du blocage : OFF")
    end
    return debugOn
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------
local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function fontString(parent, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, flags or "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
    fs:SetWordWrap(false)
    return fs
end

-- icône aux coins arrondis si le client sait masquer une texture (sinon icône carrée, rognée) ; renvoie le masque
local function addMask(owner, tex)
    if not (owner.CreateMaskTexture and tex.AddMaskTexture) then return nil end
    local ok, mask = pcall(function()
        local m = owner:CreateMaskTexture()
        m:SetTexture(ns.MEDIA .. "Round", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(tex)
        tex:AddMaskTexture(m)
        return m
    end)
    return ok and mask or nil
end

-- courbes d'animation (t de 0 à 1)
local function easeOut(t) return 1 - (1 - t) * (1 - t) end
local function smooth(t) return t * t * (3 - 2 * t) end
local function easeOutBack(t)                          -- dépasse 1 (~1,18) avant de se poser : effet « jaillit »
    local c1 = 2.4
    t = t - 1
    return 1 + (c1 + 1) * t * t * t + c1 * t * t
end

-- rectangle arrondi en 9 morceaux (comme ResourceBar.lua) ; cut = part de l'image occupée par un coin
local function nineSlice(parent, layer, sublevel, file, cut, corner)
    local c1, c2 = cut, 1 - cut
    local parts = {}
    local function piece(left, right, top, bottom)
        local tex = parent:CreateTexture(nil, layer, nil, sublevel)
        tex:SetTexture(file)
        tex:SetTexCoord(left, right, top, bottom)
        parts[#parts + 1] = tex
        return tex
    end
    local tl = piece(0, c1, 0, c1); tl:SetSize(corner, corner); tl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local tr = piece(c2, 1, 0, c1); tr:SetSize(corner, corner); tr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    local bl = piece(0, c1, c2, 1); bl:SetSize(corner, corner); bl:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    local br = piece(c2, 1, c2, 1); br:SetSize(corner, corner); br:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    local t = piece(c1, c2, 0, c1); t:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT", 0, 0)
    local b = piece(c1, c2, c2, 1); b:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    local l = piece(0, c1, c1, c2); l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT", 0, 0)
    local r = piece(c2, 1, c1, c2); r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT", 0, 0); r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
    local c = piece(c1, c2, c1, c2); c:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0); c:SetPoint("BOTTOMRIGHT", br, "TOPLEFT", 0, 0)
    return {
        SetColor = function(_, red, green, blue, a)
            for _, tex in ipairs(parts) do tex:SetVertexColor(red, green, blue, a or 1) end
        end,
    }
end

-- une alerte : halo doré qui bat, ondes, icône arrondie cerclée d'or avec reflet, pastille de la touche, nom du sort.
-- f (fixe, placé dans la rangée) porte f.body, qui grossit et rétrécit autour de son centre sans se déplacer.
local function newAlert()
    local T = ns.THEME
    local gold = T.gold
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(ICON, ICON)
    local body = CreateFrame("Frame", nil, f)
    body:SetSize(ICON, ICON)
    body:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.body = body
    f.glow = body:CreateTexture(nil, "BACKGROUND", nil, -3)
    f.glow:SetTexture(ns.MEDIA .. "Glow")
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(gold[1], gold[2], gold[3], 0.7)
    f.glow:SetPoint("CENTER", body, "CENTER", 0, 0)
    f.glow:SetSize(ICON * 2, ICON * 2)
    f.rings = {}
    for i = 1, RINGS do                                -- ondes dorées qui partent de l'icône à chaque battement
        local ring = body:CreateTexture(nil, "BACKGROUND", nil, -2)
        ring:SetTexture(ns.MEDIA .. "RoundStroke")
        ring:SetBlendMode("ADD")
        ring:SetVertexColor(gold[1], gold[2], gold[3], 1)
        ring:SetPoint("CENTER", body, "CENTER", 0, 0)
        ring:SetSize(ICON, ICON)
        ring:SetAlpha(0)
        f.rings[i] = ring
    end
    f.back = body:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.back:SetTexture(ns.MEDIA .. "Round")
    f.back:SetVertexColor(0, 0, 0, 0.9)
    f.back:SetPoint("TOPLEFT", body, "TOPLEFT", -3, 3)
    f.back:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 3, -3)
    f.icon = body:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(body)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = addMask(body, f.icon)
    f.flash = body:CreateTexture(nil, "ARTWORK", nil, 2)    -- éclair blanc à l'apparition
    f.flash:SetColorTexture(1, 1, 1, 1)
    f.flash:SetBlendMode("ADD")
    f.flash:SetAllPoints(f.icon)
    f.flash:SetAlpha(0)
    if mask then
        pcall(f.flash.AddMaskTexture, f.flash, mask)
        -- reflet : une bande de lumière inclinée qui traverse l'icône, découpée par le même masque arrondi
        -- (sans masque, elle déborderait de l'icône : pas de reflet)
        f.shine = body:CreateTexture(nil, "ARTWORK", nil, 3)
        f.shine:SetTexture(ns.MEDIA .. "Glow")
        f.shine:SetBlendMode("ADD")
        f.shine:SetVertexColor(1, 1, 1, 1)
        f.shine:SetSize(ICON * 0.45, ICON * 2)
        if f.shine.SetRotation then pcall(f.shine.SetRotation, f.shine, SHINE_ANGLE) end
        pcall(f.shine.AddMaskTexture, f.shine, mask)
        f.shine:SetPoint("CENTER", body, "CENTER", -ICON, 0)
        f.shine:SetAlpha(0)
    end
    f.stroke = body:CreateTexture(nil, "OVERLAY", nil, 1)
    f.stroke:SetTexture(ns.MEDIA .. "RoundStroke")
    f.stroke:SetVertexColor(gold[1], gold[2], gold[3], 1)
    f.stroke:SetPoint("TOPLEFT", body, "TOPLEFT", -3, 3)
    f.stroke:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 3, -3)
    -- pastille ancrée par son centre : elle gonfle sur place à chaque battement
    f.pill = CreateFrame("Frame", nil, body)
    f.pill:SetHeight(PILL_H)
    f.pill:SetPoint("CENTER", body, "BOTTOM", 0, PILL_OVERLAP - PILL_H / 2)
    f.pill:SetFrameLevel((body:GetFrameLevel() or 1) + 2)
    nineSlice(f.pill, "BACKGROUND", 0, ns.MEDIA .. "Round", 0.25, 8):SetColor(T.bg[1], T.bg[2], T.bg[3], 0.95)
    nineSlice(f.pill, "BORDER", 0, ns.MEDIA .. "RoundStroke", 0.25, 8):SetColor(gold[1], gold[2], gold[3], 0.9)
    f.key = fontString(f.pill, 18, "OUTLINE")
    f.key:SetPoint("CENTER", f.pill, "CENTER", 0, 0)
    f.name = fontString(body, 11, "OUTLINE")
    f.name:SetPoint("TOP", body, "BOTTOM", 0, PILL_OVERLAP - PILL_H - NAME_GAP)
    f.name:SetTextColor(T.text[1], T.text[2], T.text[3])
    return f
end

-- icône de Maîtrise du blocage : petite icône ronde cerclée de bleu (un témoin « le buff est actif », pas un appel à
-- presser une touche), avec le nombre de charges restantes dans une pastille au coin et une jauge dessous (une
-- barrette par charge). Demande du joueur (2026-11-07) : « voir le nombre de stack restant et avoir une animation à
-- chaque stack en moins » : l'icône encaisse (se tasse puis rebondit), une onde bleue part, la pastille gonfle en
-- rouge, la barrette perdue clignote puis s'éteint et un « -1 » s'envole ; à la dernière charge l'icône s'en va.
-- f (placé) porte f.body, qui grossit et rétrécit autour de son centre ; l'onde et le « -1 » restent hors de body.
local function newChip()
    local T = ns.THEME
    local blue = T.accent
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(CHIP_ICON, CHIP_ICON)
    local body = CreateFrame("Frame", nil, f)
    body:SetSize(CHIP_ICON, CHIP_ICON)
    body:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.body = body
    f.ring = f:CreateTexture(nil, "BACKGROUND", nil, -2)       -- onde quand une charge part
    f.ring:SetTexture(ns.MEDIA .. "RoundStroke")
    f.ring:SetBlendMode("ADD")
    f.ring:SetVertexColor(blue[1], blue[2], blue[3], 1)
    f.ring:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.ring:SetSize(CHIP_ICON, CHIP_ICON)
    f.ring:SetAlpha(0)
    f.glow = body:CreateTexture(nil, "BACKGROUND", nil, -3)
    f.glow:SetTexture(ns.MEDIA .. "Glow")
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(blue[1], blue[2], blue[3], 0.35)
    f.glow:SetPoint("CENTER", body, "CENTER", 0, 0)
    f.glow:SetSize(CHIP_ICON * 1.7, CHIP_ICON * 1.7)
    f.back = body:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.back:SetTexture(ns.MEDIA .. "Round")
    f.back:SetVertexColor(0, 0, 0, 0.9)
    f.back:SetPoint("TOPLEFT", body, "TOPLEFT", -2, 2)
    f.back:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 2, -2)
    f.icon = body:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(body)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = addMask(body, f.icon)
    f.flash = body:CreateTexture(nil, "ARTWORK", nil, 2)       -- éclair blanc quand un coup est bloqué
    f.flash:SetColorTexture(1, 1, 1, 1)
    f.flash:SetBlendMode("ADD")
    f.flash:SetAllPoints(f.icon)
    f.flash:SetAlpha(0)
    if mask then pcall(f.flash.AddMaskTexture, f.flash, mask) end
    f.stroke = body:CreateTexture(nil, "OVERLAY", nil, 1)
    f.stroke:SetTexture(ns.MEDIA .. "RoundStroke")
    f.stroke:SetVertexColor(blue[1], blue[2], blue[3], 1)
    f.stroke:SetPoint("TOPLEFT", body, "TOPLEFT", -2, 2)
    f.stroke:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 2, -2)
    -- pastille du nombre de charges, ancrée par son centre sur un point du coin : elle gonfle sur place
    local corner = body:CreateTexture(nil, "OVERLAY")
    corner:SetSize(1, 1)
    corner:SetPoint("CENTER", body, "BOTTOMRIGHT", -3, 3)
    f.badge = CreateFrame("Frame", nil, body)
    f.badge:SetSize(BADGE, BADGE)
    f.badge:SetPoint("CENTER", corner, "CENTER", 0, 0)
    f.badge:SetFrameLevel((body:GetFrameLevel() or 1) + 3)
    local bb = f.badge:CreateTexture(nil, "BACKGROUND")
    bb:SetTexture(ns.MEDIA .. "Round")
    bb:SetVertexColor(T.bg[1], T.bg[2], T.bg[3], 0.96)
    bb:SetAllPoints(f.badge)
    local bs = f.badge:CreateTexture(nil, "BORDER")
    bs:SetTexture(ns.MEDIA .. "RoundStroke")
    bs:SetVertexColor(blue[1], blue[2], blue[3], 1)
    bs:SetAllPoints(f.badge)
    f.count = fontString(f.badge, 13, "OUTLINE")
    f.count:SetPoint("CENTER", f.badge, "CENTER", 1, 0)
    f.count:SetTextColor(1, 1, 1)
    -- jauge : une barrette par charge, sous l'icône
    f.pipHolder = CreateFrame("Frame", nil, f)
    f.pipHolder:SetSize(CHIP_ICON, PIP_H)
    f.pipHolder:SetPoint("TOP", f, "BOTTOM", 0, -PIP_GAP)
    f.pips = {}
    -- « -1 » qui s'envole
    f.float = fontString(f, 14, "OUTLINE")
    f.float:SetTextColor(1, 0.42, 0.38)
    f.float:SetText("-1")
    f.float:SetPoint("BOTTOM", f, "TOP", 0, 2)
    f.float:SetAlpha(0)
    f:Hide()
    return f
end

local function paint(f, e)
    local T = ns.THEME
    f.icon:SetTexture(spellTexture(e.spellID, e.action))
    if e.usable == false and e.lacking then
        f.icon:SetVertexColor(0.5, 0.5, 1.0)          -- comme le bouton : bleu quand la ressource manque
    elseif e.usable == false then
        f.icon:SetVertexColor(0.55, 0.55, 0.55)
    else
        f.icon:SetVertexColor(1, 1, 1)
    end
    local showKey, showName = ns.db.procShowKey ~= false, ns.db.procShowName ~= false
    local text = Procs.KeyText(e.key)
    f.hasKey = showKey and text ~= nil
    f.pill:SetShown(showKey)
    f.name:SetShown(showName)
    if f.nameUnder ~= showKey then                    -- le nom monte sous l'icône quand la touche est cachée
        f.nameUnder = showKey
        f.name:ClearAllPoints()
        f.name:SetPoint("TOP", f.body, "BOTTOM", 0, showKey and (PILL_OVERLAP - PILL_H - NAME_GAP) or -NAME_GAP)
    end
    if text then
        f.key:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
        f.key:SetTextColor(1, 1, 1)
        f.key:SetText(text)
    else
        f.key:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        f.key:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
        f.key:SetText(ns.T("aucune touche"))
    end
    local pillW = math.max(PILL_H + 4, math.ceil((tonumber(f.key:GetStringWidth()) or 0) + 18))
    f.pill:SetWidth(pillW)
    f.name:SetText(e.name or spellName(e.spellID) or "")
    local nameW = math.min(tonumber(f.name:GetStringWidth()) or 0, NAME_MAX_W)
    f.width = math.max(ICON + 6, showKey and pillW or 0, showName and nameW or 0)
end

-- hauteur d'une alerte : l'icône, plus la pastille de la touche et le nom s'ils sont affichés (pas de trou)
local function alertHeight()
    local h = ICON
    if ns.db.procShowKey ~= false then h = h + PILL_H - PILL_OVERLAP end
    if ns.db.procShowName ~= false then h = h + NAME_GAP + NAME_H end
    return h
end
Procs.AlertHeight = alertHeight

local function place(f)
    f:ClearAllPoints()
    f:SetPoint("TOP", root, "TOP", f.cx or 0, 0)
end

-- icône du buff : centrée sur l'icône des alertes, à droite de la rangée (ou seul au centre sans alerte)
local function placeChip()
    chip:ClearAllPoints()
    chip:SetPoint("TOP", root, "TOP", chip.cx or 0, -(ICON - CHIP_ICON) / 2)
end

-- place visée de l'icône du buff (tx) ; elle apparaît directement à sa place, puis glisse quand la rangée change
local function chipTarget()
    if not (chip and chipKind) then return end
    chip.width = CHIP_ICON + 6
    chip.tx = (rowTotal > 0) and (rowTotal / 2 + GAP + chip.width / 2) or 0
    if chip.cx == nil then
        chip.cx = chip.tx
        placeChip()
    end
end

local function snapChip()                              -- plus d'animation en cours : on le pose tout de suite
    if chip and chipKind and chip.tx and chip.cx ~= chip.tx then
        chip.cx = chip.tx
        placeChip()
    end
end

-- place visée de chaque alerte (tx) ; une nouvelle apparaît directement à sa place, les autres y glissent
local function layout()
    local total = 0
    for i, f in ipairs(order) do total = total + f.width + (i > 1 and GAP or 0) end
    rowTotal = total
    local x = -total / 2
    for _, f in ipairs(order) do
        f.tx = x + f.width / 2
        if f.cx == nil then
            f.cx = f.tx
            place(f)
        end
        x = x + f.width + GAP
    end
    if total > 0 then root:SetSize(math.max(total, ICON), alertHeight()) end
    chipTarget()
end

-- petit son à l'apparition d'une alerte (réglage procSound), au plus un par seconde.
-- Vérifié dans le code de Forever : SOUNDKIT.UI_BNET_TOAST (BNet.lua, Blizzard_DelvesToast.lua), un « tic » discret.
local lastSound = -100
local function playSound()
    if not ns.db.procSound then return end
    local now = GetTime()
    if now - lastSound < SOUND_EVERY then return end
    local kit, play = api("SOUNDKIT"), api("PlaySound")
    local id = type(kit) == "table" and (kit.UI_BNET_TOAST or kit.MAP_PING)
    if id and type(play) == "function" then
        lastSound = now
        pcall(play, id)
    end
end

-- opacité des alertes (corps de chaque alerte ; f.alpha sert à l'animation d'apparition)
local function alertOpacity()
    return clamp(ns.db.procOpacity or 1, 0.3, 1)
end

local function acquire()
    local f = table.remove(pool) or newAlert()
    f.body:SetAlpha(alertOpacity())
    f.born, f.dying, f.cx, f.tx = GetTime(), nil, nil, nil
    local mode = animMode()
    f:SetAlpha(mode == "aucune" and 1 or 0)             -- « aucune » : l'icône est là tout de suite, immobile
    f.body:SetScale(mode == "vif" and POP_FROM or 1)
    f.pill:SetScale(1)
    f.flash:SetAlpha(0)
    for _, ring in ipairs(f.rings) do ring:SetAlpha(0) end
    if f.shine then f.shine:SetAlpha(0) end
    f:Show()
    return f
end

local function release(f)
    f:Hide()
    f.spellID, f.dying = nil, nil
    pool[#pool + 1] = f
end

local animate

-- le cadre est visible tant qu'il y a une alerte (animée), une alerte qui sort, ou l'icône du buff (immobile)
local function settleRoot()
    if #order > 0 or #dying > 0 then
        root:Show()
        root:SetScript("OnUpdate", animate)
    else
        root:SetScript("OnUpdate", nil)
        if chipKind or (chip and chip.leaving) then root:Show() else root:Hide() end
    end
end

-- tout retirer d'un coup, sans animation (réglage coupé)
local function releaseAll()
    for id, f in pairs(active) do
        active[id] = nil
        release(f)
    end
    for i = #dying, 1, -1 do
        release(dying[i])
        dying[i] = nil
    end
    wipe(order)
    rowTotal = 0
    chipTarget()
    snapChip()
    settleRoot()
end

local function render(list)
    wipe(order)
    local keep = {}
    for i = 1, math.min(#list, maxAlerts()) do
        local e = list[i]
        local f = active[e.spellID]
        if not f then
            for j = #dying, 1, -1 do                   -- revient pendant sa sortie : on la garde, sans rejaillir
                if dying[j].spellID == e.spellID then
                    f = table.remove(dying, j)
                    f.dying = nil
                    break
                end
            end
            if not f then
                f = acquire()                          -- nouvelle alerte : elle jaillit
                playSound()
            end
            f.spellID = e.spellID
            active[e.spellID] = f
        end
        paint(f, e)
        keep[e.spellID] = true
        order[#order + 1] = f
    end
    for id, f in pairs(active) do
        if not keep[id] then
            active[id] = nil
            f.dying = GetTime()                        -- « pouf » : animate la libère à la fin
            dying[#dying + 1] = f
        end
    end
    layout()
    if #order == 0 and #dying == 0 then snapChip() end     -- rien n'anime plus : l'icône se pose tout de suite
    settleRoot()
end

-- une image d'animation pour une alerte ; false quand sa sortie est finie
local function animateAlert(f, now, elapsed)
    local mode = animMode()
    if f.tx and f.cx ~= f.tx then                      -- glissement vers sa place (« aucune » : direct)
        local d = f.tx - f.cx
        f.cx = (mode == "aucune" or math.abs(d) < 0.5) and f.tx or (f.cx + d * math.min(1, elapsed * SLIDE_SPEED))
        place(f)
    end
    if f.dying then
        if mode == "aucune" then return false end      -- icône fixe : elle disparaît sans effet
        local p = (now - f.dying) / OUT_TIME
        if p >= 1 then return false end
        f:SetAlpha(math.min(f:GetAlpha() or 1, 1 - p))
        f.body:SetScale(mode == "vif" and (1 + 0.3 * easeOut(p)) or 1)
        for _, ring in ipairs(f.rings) do ring:SetAlpha(0) end
        if f.shine then f.shine:SetAlpha(0) end
        return true
    end
    local age = now - (f.born or now)
    if mode ~= "vif" then
        -- pas d'ondes, de reflet, d'éclair ni de pastille qui gonfle
        f.body:SetScale(1)
        f.pill:SetScale(1)
        f.flash:SetAlpha(0)
        for _, ring in ipairs(f.rings) do ring:SetAlpha(0) end
        if f.shine then f.shine:SetAlpha(0) end
        if f.hasKey then f.key:SetTextColor(1, 1, 1) end
        if mode == "aucune" then                       -- icône fixe : halo constant
            f:SetAlpha(1)
            f.glow:SetSize(ICON * 2, ICON * 2)
            f.glow:SetAlpha(0.45)
        else                                           -- « doux » : fondu d'entrée, puis le halo respire
            f:SetAlpha(age >= FADE_IN * 2 and 1 or age / (FADE_IN * 2))
            local breath = 0.5 + 0.5 * math.sin(2 * math.pi * age / (BEAT * 2))
            local k = 1 + 0.12 * breath
            f.glow:SetSize(ICON * 2 * k, ICON * 2 * k)
            f.glow:SetAlpha(0.3 + 0.4 * breath)
        end
        return true
    end
    f:SetAlpha(age >= FADE_IN and 1 or age / FADE_IN)
    f.body:SetScale(age < POP_TIME and (POP_FROM + (1 - POP_FROM) * easeOutBack(age / POP_TIME)) or 1)
    f.flash:SetAlpha(age < FLASH_TIME and 0.85 * (1 - age / FLASH_TIME) or 0)

    -- battement : le premier part à la fin du jaillissement
    local t = age - POP_TIME * 0.6
    local phase = (t >= 0) and (t % BEAT) or nil
    for i, ring in ipairs(f.rings) do
        local rp = phase and (phase - (i - 1) * RING_GAP) / RING_TIME
        if rp and rp >= 0 and rp < 1 then
            local size = ICON + 6 + ICON * 0.8 * easeOut(rp)
            ring:SetSize(size, size)
            ring:SetAlpha(0.85 * (1 - rp))
        else
            ring:SetAlpha(0)
        end
    end
    local beat = phase and math.max(0, 1 - phase / GLOW_DECAY) or 0
    if age < BURST then
        local k = 1 + 1.2 * (1 - age / BURST)          -- éclat : le halo part grand et se resserre
        f.glow:SetSize(ICON * 2 * k, ICON * 2 * k)
        f.glow:SetAlpha(1)
    else
        local k = 1 + 0.18 * beat
        f.glow:SetSize(ICON * 2 * k, ICON * 2 * k)
        f.glow:SetAlpha(0.3 + 0.55 * beat)
    end
    local heart = (phase and phase < HEART_TIME) and math.sin(math.pi * phase / HEART_TIME) or 0
    f.pill:SetScale(1 + 0.15 * heart)
    if f.hasKey then
        local gold = ns.THEME.gold
        f.key:SetTextColor(1 + (gold[1] - 1) * heart, 1 + (gold[2] - 1) * heart, 1 + (gold[3] - 1) * heart)
    end

    if f.shine then                                    -- reflet juste après l'entrée, puis toutes les 2 s
        local s = age - POP_TIME
        if s >= 0 then s = s % SHINE_EVERY end
        if s >= 0 and s < SHINE_TIME then
            local p = s / SHINE_TIME
            f.shine:ClearAllPoints()
            f.shine:SetPoint("CENTER", f.body, "CENTER", -ICON + 2 * ICON * smooth(p), 0)
            f.shine:SetAlpha(0.75 * math.sin(math.pi * p))
        else
            f.shine:SetAlpha(0)
        end
    end
    return true
end

animate = function(_, elapsed)
    local now = GetTime()
    elapsed = elapsed or 0
    for _, f in ipairs(order) do animateAlert(f, now, elapsed) end
    for i = #dying, 1, -1 do
        local f = dying[i]
        if not animateAlert(f, now, elapsed) then
            table.remove(dying, i)
            release(f)
        end
    end
    if chip and chipKind and chip.tx and chip.cx and chip.cx ~= chip.tx then   -- l'icône glisse avec la rangée
        local d = chip.tx - chip.cx
        chip.cx = (math.abs(d) < 0.5) and chip.tx or (chip.cx + d * math.min(1, elapsed * SLIDE_SPEED))
        placeChip()
    end
    if #order == 0 and #dying == 0 then
        snapChip()
        settleRoot()                                   -- plus rien à animer : la boucle s'arrête (l'icône reste)
        return
    end
    recheck = recheck - elapsed
    if recheck <= 0 then
        recheck = RECHECK
        if refresh then refresh() end                  -- une alerte ne traîne jamais, même si un événement manque
    end
end

---------------------------------------------------------------------------
-- Icône de Maîtrise du blocage : charges et animations
---------------------------------------------------------------------------
-- charges à montrer (aperçu : la jauge pleine)
local function chipCounts()
    if chip.preview then
        local most = blockMax or tonumber(ns.db.procBlockMax) or BLOCK_DEFAULT_CHARGES
        return most, most
    end
    return blockCharges, blockMax
end

local function colorPip(p, full)
    local blue = ns.THEME.accent
    if full then p:SetVertexColor(blue[1], blue[2], blue[3], 1) else p:SetVertexColor(SPENT[1], SPENT[2], SPENT[3], SPENT[4]) end
end

-- pastille et jauge d'après le compte ; cachées si on ne le connaît pas
local function paintCharges()
    if not chip then return end
    local n, most = chipCounts()
    if not (n and most and most >= 1) then
        chip.badge:Hide()
        chip.pipHolder:Hide()
        return
    end
    n = math.max(0, n)
    chip.count:SetText(tostring(n))
    chip.badge:Show()
    local shown = math.min(most, PIPS_MAX)
    local w = (CHIP_ICON - (shown - 1) * PIP_SPACING) / shown
    for i = 1, shown do
        local p = chip.pips[i]
        if not p then
            p = chip.pipHolder:CreateTexture(nil, "ARTWORK")
            p:SetColorTexture(1, 1, 1, 1)
            chip.pips[i] = p
        end
        p:SetSize(w, PIP_H)
        p:ClearAllPoints()
        p:SetPoint("LEFT", chip.pipHolder, "LEFT", (i - 1) * (w + PIP_SPACING), 0)
        colorPip(p, i <= n)
        p:Show()
    end
    for i = shown + 1, #chip.pips do chip.pips[i]:Hide() end
    chip.pipHolder:Show()
end

local function resetChipLook()
    chip.body:SetScale(1)
    chip:SetAlpha(1)
    chip.ring:SetAlpha(0)
    chip.flash:SetAlpha(0)
    chip.float:SetAlpha(0)
    chip.badge:SetScale(1)
    chip.count:SetTextColor(1, 1, 1)
end

local function finishLeave()
    chip.leaving, chip.loseAt, chip.enterAt = nil, nil, nil
    chip:SetScript("OnUpdate", nil)
    resetChipLook()
    chip:Hide()
    chip.cx = nil                                      -- elle réapparaîtra directement à sa place
    settleRoot()
end

-- une image d'animation de l'icône (apparition, charge perdue, départ) ; la boucle s'arrête d'elle-même
local function chipAnimate()
    local now = GetTime()
    local busy, scale, alpha = false, 1, 1
    if chip.enterAt then                               -- apparition (ou nouvelles charges) : elle jaillit
        local p = (now - chip.enterAt) / CHIP_ENTER
        if p >= 1 or p < 0 then
            chip.enterAt = nil
        else
            busy = true
            scale = POP_FROM + (1 - POP_FROM) * easeOutBack(p)
            alpha = math.min(1, p / 0.35)
        end
    end
    if chip.loseAt then                                -- une charge en moins
        local t = now - chip.loseAt
        if t >= CHIP_LOSE or t < 0 then
            chip.loseAt = nil
            chip.ring:SetAlpha(0)
            chip.flash:SetAlpha(0)
            chip.float:SetAlpha(0)
            chip.badge:SetScale(1)
            chip.count:SetTextColor(1, 1, 1)
            paintCharges()
        else
            busy = true
            -- le coup est encaissé : l'icône se tasse, rebondit un peu trop, puis se pose
            local bump = 1
            if t < 0.08 then bump = 1 - 0.18 * (t / 0.08)
            elseif t < 0.22 then bump = 0.82 + 0.26 * smooth((t - 0.08) / 0.14)
            elseif t < 0.34 then bump = 1.08 - 0.08 * smooth((t - 0.22) / 0.12) end
            scale = scale * bump
            local rp = math.min(1, t / 0.5)                -- onde bleue
            local size = CHIP_ICON + 4 + CHIP_ICON * 0.9 * easeOut(rp)
            chip.ring:SetSize(size, size)
            chip.ring:SetAlpha(0.9 * (1 - rp))
            chip.flash:SetAlpha(t < 0.18 and 0.7 * (1 - t / 0.18) or 0)
            local bp = math.min(1, t / 0.35)               -- la pastille gonfle en rouge puis revient
            chip.badge:SetScale(1 + 0.6 * (1 - easeOut(bp)))
            local red = 1 - bp
            chip.count:SetTextColor(1, 1 - 0.6 * red, 1 - 0.65 * red)
            local pip = chip.lostPip and chip.pips[chip.lostPip]
            if pip and pip:IsShown() then                  -- la barrette perdue : blanche, puis éteinte
                local k = 1 - math.min(1, t / 0.45)
                pip:SetVertexColor(SPENT[1] + (1 - SPENT[1]) * k, SPENT[2] + (1 - SPENT[2]) * k,
                    SPENT[3] + (1 - SPENT[3]) * k, SPENT[4] + (1 - SPENT[4]) * k)
            end
            local fp = math.min(1, t / CHIP_LOSE)          -- « -1 » qui s'envole
            chip.float:ClearAllPoints()
            chip.float:SetPoint("BOTTOM", chip, "TOP", 0, 2 + 18 * easeOut(fp))
            chip.float:SetAlpha(fp < 0.2 and fp / 0.2 or (1 - (fp - 0.2) / 0.8))
        end
    end
    if chip.leaving then                               -- départ : « pouf », elle grossit un peu en s'effaçant
        local p = (now - chip.leaving) / CHIP_OUT
        if p >= 1 then
            finishLeave()
            return
        end
        if p > 0 then
            scale = scale * (1 + 0.35 * easeOut(p))
            alpha = math.min(alpha, 1 - p)
        end
        busy = true
    end
    chip.body:SetScale(math.max(0.05, scale))
    chip:SetAlpha(math.max(0, alpha))
    if not busy then chip:SetScript("OnUpdate", nil) end
end
Procs.ChipAnimate = function() if chip then chipAnimate() end end

local function startChipAnim()
    chip:SetScript("OnUpdate", chipAnimate)
end

-- une charge vient de partir (compte déjà mis à jour) : animation sur l'icône affichée
chipLose = function()
    if not (chip and chip:IsShown()) then return end
    paintCharges()
    chip.lostPip = (blockCharges or 0) + 1
    chip.loseAt = GetTime()
    startChipAnim()
end

-- relit l'état du buff de Maîtrise du blocage et montre ou cache son icône
local function updateChip()
    if not (chip and root) then return end
    local on, preview = false, false
    if ns.db.procBlock then
        on = blockActive()
        -- aperçu, ou alerte déverrouillée pour la placer : l'icône est là même sans le buff
        if not on and ns.db.procAlert and (GetTime() < previewUntil or ns.db.procLocked == false) then
            on, preview = true, true
        end
    end
    if on then
        local fresh = not chipKind or chip.leaving ~= nil
        chipKind = true
        chip.preview = preview
        if chip.leaving then
            chip.leaving = nil
            resetChipLook()
        end
        chip.icon:SetTexture(spellTexture(BLOCK_IDS[1]))
        if not chip.loseAt then paintCharges() end
        chip:Show()
        chipTarget()
        if #order == 0 and #dying == 0 then snapChip() end
        if fresh then
            chip.enterAt = GetTime()
            startChipAnim()
        end
    else
        if chipKind and chip:IsShown() then
            -- elle s'en va en douceur ; après une dernière charge, on laisse d'abord voir la perte
            chip.leaving = math.max(GetTime(), (chip.loseAt or -100) + CHIP_LEAVE_DELAY)
            startChipAnim()
        elseif not chip.leaving then
            chip:Hide()
            chip.cx = nil
        end
        chipKind = nil
    end
    settleRoot()
end

local function doRefresh()
    if not root then return end
    if not (ns.db.procAlert or buffsWanted()) then
        releaseAll()
        if refreshBlock then refreshBlock() end
        return
    end
    local list = Procs:Collect()
    if #list == 0 and ns.db.procAlert and (GetTime() < previewUntil or ns.db.procLocked == false) then
        list = { sample() }                            -- aperçu, ou déverrouillée pour la placer
    end
    render(list)
    if refreshBlock then refreshBlock() end
    -- un proc est là mais son sort est en recharge : rien ne tourne à l'écran, donc on se réveille nous-mêmes
    -- pour montrer l'alerte dès que le sort redevient lançable
    local wait = Procs.waitFor
    if wait and not waiting then
        waiting = true
        C_Timer.After(clamp(wait + 0.05, 0.1, 1), function()
            waiting = false
            Procs:Request()
        end)
    end
end

function Procs:Request()
    if queued then return end
    queued = true
    C_Timer.After(FLUSH_DELAY, function()
        queued = false
        if refresh then refresh() end
    end)
end

---------------------------------------------------------------------------
-- Position, déplacement, aperçu
---------------------------------------------------------------------------
local function applyPosition()
    if not root then return end
    root:SetScale(clamp(ns.db.procScale or 1, 0.5, 3))
    root:SetAlpha(1)                                    -- l'opacité ne touche que les alertes, pas la puce ni le cadre de déplacement
    for _, f in ipairs(pool) do f.body:SetAlpha(alertOpacity()) end
    for _, f in pairs(active) do f.body:SetAlpha(alertOpacity()) end
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", tonumber(ns.db.procX) or 0, tonumber(ns.db.procY) or -115)
end

-- décalage du centre par rapport au centre de l'écran, dans l'échelle des alertes (comme ResourceBar.lua)
local function savePosition()
    local cx, cy = root:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s, u = root:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (cx and cy and ux and uy and s and u and s > 0) then return end
    ns:Set("procX", math.floor(cx - ux * u / s + 0.5))
    ns:Set("procY", math.floor(cy - uy * u / s + 0.5))
end

local function build()
    if root then return end
    local T = ns.THEME
    root = CreateFrame("Frame", "PlatyplusProcs", UIParent)
    root:SetSize(ICON, ICON)
    root:SetFrameStrata("MEDIUM")
    root:SetFrameLevel(20)
    root:SetClampedToScreen(true)
    root:SetMovable(true)
    root:EnableMouse(false)                            -- les alertes ne bloquent jamais les clics
    if root.SetDontSavePosition then pcall(root.SetDontSavePosition, root, true) end
    root:Hide()

    mover = CreateFrame("Frame", nil, root)
    mover:SetPoint("TOPLEFT", root, "TOPLEFT", -24, 30)
    mover:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 24, -10)
    mover:SetFrameLevel(60)
    local A = T.accent
    nineSlice(mover, "BACKGROUND", 0, ns.MEDIA .. "Round", 0.25, 8):SetColor(A[1], A[2], A[3], 0.20)
    nineSlice(mover, "BORDER", 0, ns.MEDIA .. "RoundStroke", 0.25, 8):SetColor(A[1], A[2], A[3], 0.95)
    local title = fontString(mover, 12, "OUTLINE")
    title:SetPoint("TOP", mover, "TOP", 0, -6)
    title:SetTextColor(A[1], A[2], A[3])
    title:SetText(ns.T("Alerte de proc — glisse-moi"))
    local hint = fontString(mover, 10, "")
    hint:SetPoint("BOTTOM", mover, "BOTTOM", 0, 2)
    hint:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    hint:SetText(ns.T("clic droit : verrouiller"))
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function() root:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        if root.SetUserPlaced then pcall(root.SetUserPlaced, root, false) end
        savePosition()
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Procs:ToggleMove() end
    end)
    mover:Hide()

    chip = newChip()

    events = CreateFrame("Frame")
    Procs.frames = { root = root, mover = mover, events = events, chip = chip }
end

-- relecture du buff seule, sans repasser les barres d'action en revue (UNIT_AURA arrive très souvent en combat)
function Procs:RequestBlock()
    if blockQueued then return end
    blockQueued = true
    C_Timer.After(FLUSH_DELAY, function()
        blockQueued = false
        if refreshBlock then refreshBlock() end
    end)
end

-- tu viens de lancer Maîtrise du blocage : si le jeu cache l'aura, on sait au moins qu'elle est là pour quelque temps
local function onBlockCast(spellID)
    -- charges pleines : le maximum lu en jeu (talents compris) sinon celui du sort
    blockMax = tonumber(ns.db.procBlockMax) or BLOCK_CHARGES[spellID] or BLOCK_DEFAULT_CHARGES
    blockCharges, blockSpent = blockMax, false
    if chip and chipKind then                          -- relancé pendant le buff : charges refaites, elle rejaillit
        chip.loseAt = nil
        resetChipLook()
        paintCharges()
        chip.enterAt = GetTime()
        startChipAnim()
    end
    -- tes buffs d'il y a un instant : le nouveau sera le tien (le jeu peut le poser juste avant ou juste après avoir
    -- signalé le lancer ; NON VÉRIFIÉ en jeu)
    local now = GetTime()
    castAt, pendingBase, pendingUntil = now, idsAt(now - BLOCK_RACE), now + BLOCK_WINDOW
    local duration = blockDuration or BLOCK_DURATION
    blockUntil = now + duration
    blockTimer = blockTimer + 1
    local token = blockTimer
    -- des réveils au moment de choisir le buff, à la fin de la recherche, à la fin du buff et à la fin du délai de grâce :
    -- l'icône ne dépend jamais d'un autre événement
    for _, delay in ipairs({ BLOCK_SETTLE + 0.05, BLOCK_WINDOW + 0.05, duration + 0.05, duration + BLOCK_GRACE + 0.05 }) do
        C_Timer.After(delay, function()
            if token == blockTimer then Procs:RequestBlock() end
        end)
    end
    dbg("lancer repéré ; avant :", pendingBase and "liste connue" or "liste inconnue", "; durée supposée", duration, "s ;",
        blockCharges, "charge(s)")
    Procs:RequestBlock()
end

-- Un coup bloqué : une charge en moins. UNIT_COMBAT est lisible même en combat (Forever, UnitDocumentation : seul le
-- montant est secret ; l'événement et son drapeau ne le sont pas) ; le jeu s'en sert pour le texte « Bloqué » sur le
-- portrait (CombatFeedback.lua) : événement « BLOCK » (coup bloqué en entier), ou « WOUND » avec le drapeau
-- « BLOCK_REDUCED » (blocage partiel) ou « BLOCK ». Chaque blocage consomme une charge de Maîtrise du blocage.
local function onBlocked(what, flag)
    blocksCounted = blocksCounted + 1
    if not (chipKind and chip and not chip.preview and blockCharges and blockCharges > 0) then
        dbg("coup bloqué (", what, flag, ") : pas de buff suivi, rien à retirer")
        return
    end
    blockCharges = blockCharges - 1
    dbg("coup bloqué (", what, flag, ") : il reste", blockCharges, "charge(s)")
    chipLose()
    if blockCharges <= 0 then
        blockSpent, spentAt = true, GetTime()
        blockUntil, blockInstance, pendingBase = 0, nil, nil
        C_Timer.After(0.05, function() Procs:RequestBlock() end)
    end
end
Procs.OnBlocked = onBlocked

local function onEvent(_, event, a1, a2, a3)
    if event == "UNIT_AURA" then
        if a1 ~= nil and not isSecret(a1) and a1 ~= "player" then return end     -- a1 : l'unité
        if debugOn and GetTime() < blockUntil + BLOCK_GRACE + 1 then               -- seulement autour d'un lancer
            local info = a2
            if type(info) ~= "table" or isSecret(info) then
                dbg("UNIT_AURA : charge utile", isSecret(info) and "secrète" or type(info))
            else
                local function size(t)
                    if t == nil then return 0 end
                    return (type(t) == "table" and not isSecret(t)) and #t or "?"
                end
                dbg("UNIT_AURA : ajoutés", size(info.addedAuras), "retirés", size(info.removedAuraInstanceIDs),
                    "modifiés", size(info.updatedAuraInstanceIDs))
            end
        end
        Procs:RequestBlock()
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- le lancer n'est lisible que pour toi (SecretWhenUnitSpellCastRestricted) : une unité secrète n'est pas toi
        if isSecret(a1) or a1 ~= "player" then return end
        noteCast(a3)                                                              -- a3 : le sort lancé (sa recharge part)
        if ns.db.procBlock and isBlockSpell(a3) then onBlockCast(a3) end
        if ns.db.procAlert and cooldownOf(a3) then Procs:Request() end           -- l'alerte part aussitôt
        return
    elseif event == "UNIT_COMBAT" then
        if isSecret(a1) or a1 ~= "player" or isSecret(a2) or isSecret(a3) then return end
        if a2 == "BLOCK" or a3 == "BLOCK" or a3 == "BLOCK_REDUCED" then onBlocked(a2, a3) end
        return
    end
    local spellID = a1                                                            -- lueur : le sort
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        if spellID ~= nil and not isSecret(spellID) then overlayed[spellID] = true end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if spellID ~= nil and not isSecret(spellID) then overlayed[spellID] = nil end
    end
    Procs:Request()
end

function Procs:Apply()
    if not (lib and root) then return end
    local on = (ns.db.procAlert or buffsWanted()) and true or false     -- le rappel de buffs a besoin des alertes
    lib.setWanted("Procs", on)
    for _, event in ipairs(EVENTS) do
        if on then lib.registerEvent(events, event) else pcall(events.UnregisterEvent, events, event) end
    end
    -- tes lancers : la recharge d'Ivresse de la victoire & co. (alertes) et le buff de blocage
    if on or ns.db.procBlock then
        lib.registerUnitEvent(events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        pcall(events.UnregisterEvent, events, "UNIT_SPELLCAST_SUCCEEDED")
    end
    if ns.db.procBlock then                            -- Maîtrise du blocage : événements de toi seulement
        lib.registerUnitEvent(events, "UNIT_AURA", "player")
        lib.registerUnitEvent(events, "UNIT_COMBAT", "player")
    else
        pcall(events.UnregisterEvent, events, "UNIT_AURA")
        pcall(events.UnregisterEvent, events, "UNIT_COMBAT")
        blockUntil, blockCharges, blockSpent = 0, nil, false
    end
    if not ns.db.procAlert then wipe(overlayed) end
    applyPosition()
    mover:SetShown(ns.db.procAlert and ns.db.procLocked == false)
    if refresh then refresh() end
end

function Procs:ToggleMove()
    local unlock = ns.db.procLocked ~= false
    ns:Set("procLocked", not unlock)
    if unlock then
        ns:Print("alerte de proc : glisse-la où tu veux, puis clic droit dessus (ou Verrouiller) pour la verrouiller")
    else
        ns:Print("alerte de proc : position enregistrée")
    end
end

function Procs:ResetPosition()
    ns:Reset("procX")
    ns:Reset("procY")
end

-- montre l'alerte quelques secondes, même hors combat
function Procs:Preview(seconds)
    if not root then return end
    if not ns.db.procAlert then
        ns:Print("alertes de proc coupées : active-les pour voir l'aperçu")
        return
    end
    seconds = tonumber(seconds) or PREVIEW_SECONDS
    previewUntil = GetTime() + seconds
    if refresh then refresh() end
    C_Timer.After(seconds + 0.05, function() Procs:Request() end)
end

function Procs:Init()
    lib = ns.Resources and ns.Resources.lib
    if not lib then
        ns:Debug("Procs : Resources.lua absent, alertes de proc désactivées")
        return
    end
    isSecret = lib.isSecret
    build()
    refresh = lib.guard(NAME, doRefresh)
    refreshBlock = lib.guard(BLOCK_GUARD, updateChip)
    events:SetScript("OnEvent", onEvent)
    lib.subscribe(function()                       -- barres d'action ou état utilisable changés (déjà regroupés)
        if ns.db.procAlert and refresh then refresh() end
    end)
    ns:OnChange("procAlert", function()
        lib.resetFailures(NAME)
        Procs:Apply()
    end)
    ns:OnChange("procLocked", function() Procs:Apply() end)
    ns:OnChange("procBlock", function()
        lib.resetFailures(BLOCK_GUARD)
        Procs:Apply()
    end)
    for _, key in ipairs({ "procScale", "procX", "procY", "procOpacity" }) do
        ns:OnChange(key, applyPosition)
    end
    -- liste, nombre, touche, nom : la mise en page se refait tout de suite (hauteur et positions)
    for _, key in ipairs({ "procReactive", "procGlow", "procExtra", "procIgnore", "procMax", "procShowKey", "procShowName" }) do
        ns:OnChange(key, function()
            Procs:Request()
        end)
    end
    ns:OnChange("procAnim", function()                 -- repart de l'aspect de base, puis la nouvelle animation s'applique
        for _, f in ipairs(order) do
            f.body:SetScale(1)
            f.pill:SetScale(1)
            f.flash:SetAlpha(0)
            for _, ring in ipairs(f.rings) do ring:SetAlpha(0) end
            if f.shine then f.shine:SetAlpha(0) end
            f:SetAlpha(1)
        end
        Procs:Request()
    end)
    self:Apply()
end
