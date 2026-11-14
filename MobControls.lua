-- Platyplus : ce que les mobs te font subir (ns.MobControls)
--  * Infobulle d'un mob : ses sorts de contrôle (étourdir, immobiliser, ralentir, apeurer, repousser...), leur durée
--    et leur rythme, par ex. sur un Bandit défias « Coup de pied rapide — Étourdit 2 s   toutes les 5-9 s ».
--  * /pp mob : la liste complète du mob ciblé, avec le moment du premier lancer.
--  * Les sorts par mob et leurs délais viennent de MobControlsData.lua, généré par dev/make_mobcontrols.py depuis la base
--    de VMaNGOS (GPL-2.0), qui reproduit le jeu d'origine : ce sont des ordres de grandeur, pas des minuteurs exacts.
--    Ce que fait chaque sort (mécanique, durée, temps d'incantation) vient des tables du client Forever (wago.tools).
-- Vérifié dans le code de Forever (wow-ui-source, branche forever) :
--  * TooltipInfoSharedDocumentation : Enum.TooltipDataType.Unit ; C_Spell.GetSpellName / GetSpellTexture (nil si absent)
--  * UnitGUID est secret quand l'identité des unités est restreinte (instances, JcJ) : rien n'est affiché alors
--  * Les incantations ennemies (UnitCastingInfo, UNIT_SPELLCAST_*) sont secrètes en combat : pas d'alerte en direct ici.
-- NON VÉRIFIÉ en jeu : data.guid dans les infobulles d'unité (repli sur GameTooltip:GetUnit()), identifiants des mobs de
--  Forever (ceux du WoW classique), délais réels du serveur Forever.
local ADDON, ns = ...

local MC = {}
ns.MobControls = MC

local MAX_LINES = 4   -- sorts au plus dans l'infobulle (la liste complète : /pp mob)

-- Catégories, de la plus gênante à la moins gênante. Couleurs : chaudes = tu ne joues plus, froides = tu bouges mal.
MC.CATS = {
    stun      = { order = 1, label = "Étourdit",          color = { 1.00, 0.35, 0.25 } },
    incap     = { order = 2, label = "Neutralise",        color = { 0.85, 0.45, 1.00 } },
    fear      = { order = 3, label = "Apeure",            color = { 0.80, 0.40, 0.90 } },
    charm     = { order = 4, label = "Contrôle l'esprit", color = { 0.95, 0.40, 0.75 } },
    root      = { order = 5, label = "Immobilise",        color = { 0.30, 0.85, 0.75 } },
    silence   = { order = 6, label = "Réduit au silence", color = { 0.45, 0.65, 1.00 } },
    disarm    = { order = 7, label = "Désarme",           color = { 1.00, 0.65, 0.25 } },
    knockback = { order = 8, label = "Repousse",          color = { 1.00, 0.85, 0.35 } },
    snare     = { order = 9, label = "Ralentit",          color = { 0.55, 0.80, 1.00 } },
    slowattack = { order = 10, label = "Ralentit les attaques", color = { 0.55, 0.80, 1.00 } },
}

local function api(name)
    return rawget(_G, name)
end

local function pack(ok, ...)
    if ok then return ... end
    return nil
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return pack(pcall(fn, ...))
end

-- Pas de « v == nil » avant issecretvalue : comparer un secret est interdit (issecretvalue(nil) rend false).
local function isSecret(v)
    local fn = api("issecretvalue")
    if type(fn) ~= "function" then return false end
    local ok, res = pcall(fn, v)
    return ok and res == true
end

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

local function data()
    local D = ns.MobControlsData
    if type(D) ~= "table" then return { spells = {}, lists = {}, mobs = {} } end
    return D
end

-- npcID d'un GUID de mob (« Creature-0-serveur-instance-zone-npcID-apparition »), nil pour un joueur, un objet...
function MC.NpcID(guid)
    if isSecret(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

---------------------------------------------------------------------------
-- Textes
---------------------------------------------------------------------------
-- 2 -> « 2 », 1.5 -> « 1,5 »
local function n(v)
    v = tonumber(v) or 0
    if v == math.floor(v) then return tostring(v) end
    return (string.format("%.1f", v):gsub("%.", ","))
end

-- « 5-9 s », « 4 s »
local function range(a, b, unit)
    unit = unit or "s"
    if a == b or b == 0 then return n(a) .. " " .. unit end
    return n(a) .. "-" .. n(b) .. " " .. unit
end
MC.Range = range

-- Quand le mob lance ce sort (texte court pour l'infobulle). first = ajouter le premier lancer.
function MC.When(kind, a, b, c, d, chance, first)
    local s
    if kind == 0 then
        if c == 0 and d == 0 then
            s = (a > 0 or b > 0) and ns.Tf("une fois, vers %s", range(a, b)) or ns.T("une fois, au début")
        elseif d <= 2 then
            s = ns.T("en boucle")
        else
            if first and (a > 0 or b > 0) then
                s = ns.Tf("toutes les %s (1er vers %s)", range(c, d), range(a, b))
            else
                s = ns.Tf("toutes les %s", range(c, d))
            end
        end
    elseif kind == 2 then
        s = ns.Tf("sous %s %% de vie", n(a))
    elseif kind == 4 then
        s = ns.T("à l'engagement")
    elseif kind == 9 then
        s = (b > 0) and ns.Tf("à %s", range(a, b, "m")) or ns.T("selon la distance")
    elseif kind == 12 then
        s = ns.Tf("quand ta vie < %s %%", n(a))
    elseif kind == 13 then
        s = ns.T("quand tu incantes")
    else
        s = ns.T("parfois")
    end
    if chance and chance > 0 and chance < 100 then
        s = ns.Tf("%s (%s %% de chance)", s, n(chance))
    end
    return s
end

-- « Étourdit 2 s », « Repousse », « Ralentit » (durée inconnue ou jusqu'à dissipation : rien)
function MC.Effect(cat, duration)
    local c = MC.CATS[cat]
    local s = ns.T(c and c.label or cat)
    if duration and duration > 0 then s = ns.Tf("%s %s s", s, n(duration)) end
    return s
end

local function spellName(id)
    local S = api("C_Spell")
    local name = S and plain(call(S.GetSpellName, id))
    if type(name) == "string" and name ~= "" then return name end
    return ns.Tf("sort n° %d", id)
end

local function spellIcon(id)
    local S = api("C_Spell")
    local tex = S and plain(call(S.GetSpellTexture, id))
    if tex == nil then return "" end
    return "|T" .. tostring(tex) .. ":0|t "
end

---------------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------------
-- Contrôles de ce mob : { id, name, cat, duration, cast, kind, a, b, c, d, chance }, du plus gênant au moins gênant.
-- Un même sort lancé de plusieurs façons n'apparaît qu'une fois (la première : minuteur avant seuil de vie...).
local function byOrder(x, y)
    local ox, oy = (MC.CATS[x.cat] or {}).order or 99, (MC.CATS[y.cat] or {}).order or 99
    if ox ~= oy then return ox < oy end
    return x.id < y.id
end

-- Les données sont fixes : chaque mob n'est lu qu'une fois (une infobulle de cadre d'unité se refait toutes les 0,2 s).
local cache, NONE = {}, {}

function MC:Lines(npcID)
    if not npcID then return NONE end
    local hit = cache[npcID]
    if hit then return hit end
    local out = self:Read(npcID)
    cache[npcID] = out
    return out
end

function MC:Read(npcID)
    local D = data()
    local index = npcID and D.mobs[npcID]
    local list = index and D.lists[index]
    if type(list) ~= "table" then return {} end
    local out, seen = {}, {}
    for i = 1, #list - 6, 7 do
        local id = list[i]
        local info = D.spells[id]
        if info and not seen[id] then
            seen[id] = true
            out[#out + 1] = { id = id, name = spellName(id), cat = info[1], duration = info[2], cast = info[3],
                kind = list[i + 1], a = list[i + 2], b = list[i + 3], c = list[i + 4], d = list[i + 5],
                chance = list[i + 6] }
        end
    end
    table.sort(out, byOrder)
    return out
end

---------------------------------------------------------------------------
-- Infobulle des mobs
---------------------------------------------------------------------------
local function leftText(l)
    local cast = (l.cast and l.cast > 0) and ns.Tf(" |cff999999(incant. %s s)|r", n(l.cast)) or ""
    return spellIcon(l.id) .. l.name .. " — " .. MC.Effect(l.cat, l.duration) .. cast
end

local function onUnitTooltip(tooltip, tipData)
    if not (ns.db and ns.db.mobControlTooltip) then return end
    if tooltip ~= api("GameTooltip") then return end
    local guid
    if type(tipData) == "table" then
        -- GUID secret (instance, JcJ) : on s'arrête là. GameTooltip:GetUnit() relit ce même GUID, inutile d'y revenir.
        if isSecret(tipData.guid) then return end
        guid = tipData.guid
    elseif tooltip.GetUnit then   -- anciens clients (OnTooltipSetUnit, sans tipData)
        local unit = plain(select(2, call(tooltip.GetUnit, tooltip)))
        if type(unit) == "string" then guid = plain(call(api("UnitGUID"), unit)) end
    end
    local lines = MC:Lines(MC.NpcID(guid))
    if #lines == 0 then return end
    local dim = ns.THEME.dim
    for i = 1, math.min(#lines, MAX_LINES) do
        local l = lines[i]
        local c = (MC.CATS[l.cat] or {}).color or ns.THEME.text
        tooltip:AddDoubleLine(leftText(l), MC.When(l.kind, l.a, l.b, l.c, l.d, nil, false),
            c[1], c[2], c[3], dim[1], dim[2], dim[3])
    end
    if #lines > MAX_LINES then
        tooltip:AddLine(ns.Tf("+ %d autre(s) : cible-le et tape /pp mob", #lines - MAX_LINES), dim[1], dim[2], dim[3])
    end
    -- Pas de tooltip:Show() : Blizzard le fait juste après les post-calls (TooltipDataHandler.lua), et le nôtre ferait
    -- tourner les OnShow de GameTooltip en mode teinté.
end

local function hookTooltip()
    local processor = api("TooltipDataProcessor")
    local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    if processor and processor.AddTooltipPostCall and unitType then
        processor.AddTooltipPostCall(unitType, function(tooltip, tipData)
            local ok, err = pcall(onUnitTooltip, tooltip, tipData)
            if not ok then ns:Debug("contrôles des mobs : infobulle :", tostring(err)) end
        end)
        return true
    end
    if GameTooltip and GameTooltip.HookScript then
        return pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
            pcall(onUnitTooltip, tooltip, nil)
            pcall(tooltip.Show, tooltip)   -- ici personne d'autre ne recalcule la taille
        end)
    end
    return false
end

---------------------------------------------------------------------------
-- Commande /pp mob
---------------------------------------------------------------------------
function MC:Command()
    local rawGuid = call(api("UnitGUID"), "target")
    local npc = MC.NpcID(plain(rawGuid))
    if npc then
        local name = plain(call(api("UnitName"), "target")) or ns.Tf("mob n° %d", npc)
        local lines = self:Lines(npc)
        if #lines == 0 then
            ns:Print(ns.Tf("%s (n° %d) : aucun contrôle connu.", name, npc))
            return
        end
        ns:Print(ns.Tf("%s (n° %d) peut :", name, npc))
        for _, l in ipairs(lines) do
            local c = (MC.CATS[l.cat] or {}).color or { 1, 1, 1 }
            local hex = string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
            local cast = (l.cast and l.cast > 0) and ns.Tf(", incantation %s s : interruptible", n(l.cast)) or ""
            print("  " .. hex .. MC.Effect(l.cat, l.duration) .. "|r  " .. l.name .. cast .. "  —  "
                .. MC.When(l.kind, l.a, l.b, l.c, l.d, l.chance, true))
        end
        print("  " .. ns.T("|cff999999Délais du jeu d'origine (base VMaNGOS) : des ordres de grandeur.|r"))
        return
    end
    if isSecret(rawGuid) then
        ns:Print("contrôles des mobs : l'identité de ta cible est cachée ici (instance, JcJ) : rien à lire.")
        return
    end
    local D = data()
    local mobs, spells = 0, 0
    for _ in pairs(D.mobs) do mobs = mobs + 1 end
    for _ in pairs(D.spells) do spells = spells + 1 end
    local state = ns.db and ns.db.mobControlTooltip and ns.T("activée") or ns.T("désactivée")
    ns:Print(ns.Tf("contrôles des mobs : %d mobs, %d sorts (base VMaNGOS). Infobulle %s%s. Cible un mob et tape /pp mob pour sa liste complète.",
        mobs, spells, state, self.tooltipHooked and "" or ns.T(", NON accrochée")))
end

function MC:Init()
    self.tooltipHooked = hookTooltip()
end
