-- Platyplus : réglages du jeu en un clic
-- Chaque entrée est un ou plusieurs CVars de confort, dont le nom et les valeurs viennent du code des options de Forever
-- (Blizzard_SettingsDefinitions_Frame). Platyplus ne touche à rien tant que tu ne le demandes pas ; tes valeurs d'origine
-- sont sauvegardées (ns.db.cvarBackup) et « Rétablir » les remet. Un réglage que le client ne connaît pas est ignoré.
local ADDON, ns = ...

local GameSettings = {}
ns.GameSettings = GameSettings

local FLAGS = (Enum and Enum.SoftTargetEnableFlags) or {}
local FLAG_ANY = FLAGS.Any or 3
local FLAG_GAMEPAD = FLAGS.Gamepad or 1

-- cvars = { { nom, valeur "activé", valeur "désactivé" }, ... }
GameSettings.list = {
    {
        id = "actionTargeting",
        label = "Cibler l'ennemi qui est devant moi",
        tip = "Option « Ciblage d'action » du jeu : ton personnage cible automatiquement l'ennemi le plus proche devant lui, "
            .. "sans clic. Très pratique quand on enchaîne les sorts.",
        cvars = { { "softTargetEnemy", tostring(FLAG_ANY), tostring(FLAG_GAMEPAD) } },
    },
    {
        id = "cooldownNumbers",
        label = "Chiffres sur les temps de recharge",
        tip = "Affiche le temps restant en chiffres sur les icônes de sorts en recharge.",
        cvars = { { "countdownForCooldowns", "1", "0" } },
    },
    {
        id = "statusNumbers",
        label = "Chiffres sur les barres de vie et de ressource",
        tip = "Texte de statut du jeu : écrit les valeurs exactes sur les barres de vie et de ressource.",
        cvars = { { "statusTextDisplay", "NUMERIC", "NONE" }, { "statusText", "1", "0" } },
    },
    {
        id = "keyDown",
        label = "Lancer les sorts à l'appui de la touche",
        tip = "Le sort part quand tu appuies, pas quand tu relâches. Disponible seulement si le client connaît ce réglage.",
        cvars = { { "ActionButtonUseKeyDown", "1", "0" } },
    },
    {
        id = "targetOfTarget",
        label = "Afficher la cible de la cible",
        tip = "Affiche le petit cadre de la cible de ta cible.",
        cvars = { { "showTargetOfTarget", "1", "0" } },
    },
}

local function cvarGet(name)
    local ok, value = pcall(GetCVar, name)
    if ok then return value end
    return nil
end

local function cvarSet(name, value)
    return pcall(SetCVar, name, value)
end

-- "1" et 1 sont égaux ; les chaînes comme "NUMERIC" se comparent telles quelles
local function same(a, b)
    if a == nil or b == nil then return false end
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na == nb end
    return tostring(a) == tostring(b)
end

-- le client connaît-il tous les CVars de ce réglage ?
function GameSettings:Available(entry)
    for _, c in ipairs(entry.cvars) do
        if cvarGet(c[1]) == nil then return false end
    end
    return true
end

function GameSettings:IsOn(entry)
    for _, c in ipairs(entry.cvars) do
        if not same(cvarGet(c[1]), c[2]) then return false end
    end
    return true
end

local function backupTable()
    if type(ns.db.cvarBackup) ~= "table" then ns.db.cvarBackup = {} end
    return ns.db.cvarBackup
end

-- on = true : applique la valeur recommandée (en gardant l'ancienne) ; on = false : remet l'ancienne valeur
function GameSettings:Set(entry, on)
    if not self:Available(entry) then return false end
    local backup = backupTable()
    for _, c in ipairs(entry.cvars) do
        local name = c[1]
        if on then
            if backup[name] == nil then backup[name] = cvarGet(name) end   -- valeur d'origine, gardée une seule fois
            cvarSet(name, c[2])
        elseif backup[name] ~= nil then
            cvarSet(name, backup[name])
            backup[name] = nil
        else
            cvarSet(name, c[3])
        end
    end
    ns:Notify("cvarBackup")
    return true
end

function GameSettings:ApplyRecommended()
    local applied, skipped = 0, 0
    for _, entry in ipairs(self.list) do
        if not self:Available(entry) then
            skipped = skipped + 1
        elseif not self:IsOn(entry) then
            self:Set(entry, true)
            applied = applied + 1
        end
    end
    if skipped > 0 then
        ns:Print(ns.Tf("%d réglage(s) du jeu appliqué(s), %d inconnu(s) de ce client. /sf preset restore remet tes anciennes valeurs.", applied, skipped))
    else
        ns:Print(ns.Tf("%d réglage(s) du jeu appliqué(s). /sf preset restore remet tes anciennes valeurs.", applied))
    end
    return applied
end

function GameSettings:RestoreAll()
    local backup = backupTable()
    local restored = 0
    for name, value in pairs(backup) do
        cvarSet(name, value)
        restored = restored + 1
    end
    ns.db.cvarBackup = {}
    ns:Notify("cvarBackup")
    ns:Print(ns.Tf("%d réglage(s) du jeu remis comme avant", restored))
    return restored
end

function GameSettings:Init()
    backupTable()
end
