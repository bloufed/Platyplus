-- Platyplus : fenêtre du personnage (ns.CharWindow), à la place de la fenêtre du jeu (touche C)
--  * une fenêtre Platyplus à onglets : Personnage (équipement, modèle 3D, caractéristiques), Réputation, Compétences,
--    JcJ, Monnaies (s'il y en a) ; déplaçable par son bandeau, taille réglable
--  * elle suit les touches du jeu : C, U (réputation), K... ouvrent le bon onglet, la même touche la referme, Échap aussi
--  * Personnage : les cases d'équipement sont celles du jeu, posées dans la fenêtre (clic pour prendre ou poser un
--    objet, clic droit pour utiliser un bijou, Alt pour les objets de rechange, réparation, sertissage... tout marche
--    pareil) ; niveau d'objet sur chaque case ; modèle 3D à tourner à la souris ; caractéristiques calculées par le
--    jeu lui-même (mêmes valeurs et mêmes infobulles), dans le style Platyplus
--  (Réputation, Compétences, JcJ et Monnaies : CharacterTabs.lua)
--
-- Comment : la fenêtre du jeu (CharacterFrame) s'ouvre comme d'habitude mais reste hors de l'écran (ns.Win.Conceal) ;
-- ses volets (PaperDollFrame, ReputationFrame...) continuent de recevoir leurs événements. Changer d'onglet ici
-- appelle ToggleCharacter(volet, true), comme les onglets du jeu ; un volet ouvert par une touche (CharacterFrame:
-- ShowSubFrame, suivi par hooksecurefunc) change l'onglet ici. Les cases d'équipement du jeu (CharacterHeadSlot...)
-- sont seulement déplacées (SetParent / SetPoint) et remises à leur place si l'option est coupée.
-- Vérifié dans le code de Forever : Camelot/CharacterFrame.lua (ToggleCharacter, ShowSubFrame, activeSubframe,
-- CHARACTERFRAME_SUBFRAMES), Camelot/PaperDollFrame.xml (cases CharacterXxxSlot, BorderFrame et popoutButton posés
-- sous la case), Camelot/PaperDollFrame.lua (PAPERDOLL_STATINFO[stat].updateFunc(cadre, unité) remplit cadre.Label,
-- cadre.Value, cadre.tooltip / tooltip2 / onEnterFunc ; PaperDollStatTooltip), Camelot/PaperDollFrameConstants.lua
-- (PAPERDOLL_STATCATEGORIES).
local ADDON, ns = ...

local CW = { tabs = {}, order = {}, current = nil }
ns.CharWindow = CW

local floor, max, min = math.floor, math.max, math.min

local function api(name) return rawget(_G, name) end
local function db(key) return ns.db and ns.db[key] end

-- une erreur est signalée une fois dans le chat (le reste de la fenêtre continue de s'afficher)
local reported = {}
local function try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        ns:Debug("fenêtre du personnage (" .. where .. ") :", err)
        if not reported[where] then
            reported[where] = true
            ns:Print("fenêtre du personnage : « " .. where .. " » n'a pas pu s'afficher (" .. tostring(err):sub(1, 160) .. ")")
        end
    end
    return ok, err
end
CW.Try = try

-- appel protégé d'une fonction du jeu qui peut manquer : renvoie ses valeurs, ou rien
local function call(fn, ...)
    if type(fn) == "string" then fn = api(fn) end
    if type(fn) ~= "function" then return end
    local res = { n = 0 }
    local function pack(...) res.n = select("#", ...); for i = 1, res.n do res[i] = (select(i, ...)) end end
    pack(pcall(fn, ...))
    if not res[1] then return end
    return unpack(res, 2, res.n)
end
CW.Call = call

CW.broken = false
local function enabledOption()
    return db("charWindow") and not CW.broken
end

CW.WIDTH = 880
CW.PAD = 18
CW.TAB_H = 34
CW.BODY_H = 390
CW.CONTENT_W = CW.WIDTH - 2 * CW.PAD

---------------------------------------------------------------------------
-- Onglets : id = nom du volet du jeu (ToggleCharacter(id) ouvre le même)
---------------------------------------------------------------------------
-- def : id, label, order, build(panel), refresh(panel), available() (facultatif), events = { ... } (facultatif)
function CW:RegisterTab(def)
    self.tabs[def.id] = def
    self.order[#self.order + 1] = def
    table.sort(self.order, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

local frame, body, tabBar
local tabButtons = {}

local function available(def)
    if not def.available then return true end
    local ok, v = pcall(def.available)
    return ok and v and true or false
end

function CW:PaintTabs()
    if not frame then return end
    local C = ns.W.C
    local prev
    for _, def in ipairs(self.order) do
        local b = tabButtons[def.id]
        if b then
            local show = available(def)
            b:SetShown(show)
            if show then
                b:ClearAllPoints()
                if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", tabBar, "LEFT", 0, 0) end
                prev = b
                local active = def.id == self.current
                ns.W.TextColor(b.label, active and C.text or C.dim)
                b.line:SetShown(active)
            end
        end
    end
end

-- rafraîchissement regroupé à l'image suivante (les événements du personnage arrivent en rafales)
local dirty = {}
local function refreshSoon(id)
    if dirty[id] then return end
    dirty[id] = true
    C_Timer.After(0.05, function()
        dirty[id] = nil
        CW:Refresh(id)
    end)
end
CW.RefreshSoon = refreshSoon

function CW:Refresh(id)
    id = id or self.current
    local def = id and self.tabs[id]
    if not (def and def.panel and frame and frame:IsShown() and self.current == id) then return end
    if def.refresh then try("contenu " .. id, def.refresh, def.panel) end
end

function CW:Select(id, fromGame)
    local def = self.tabs[id]
    if not (def and frame) then return end
    if not fromGame then
        local toggle = api("ToggleCharacter")
        local sub = api(id)
        if toggle and type(sub) == "table" and sub.IsShown and not sub.hidden then
            try("onglet", toggle, id, true)       -- le jeu change de volet (et joue son son) ; le crochet nous rappelle
            if self.current == id then return end
        end
    end
    local changed = self.current ~= id
    self.current = id
    if not def.panel then
        def.panel = CreateFrame("Frame", nil, body)
        def.panel:SetAllPoints(body)
        try("construction " .. id, def.build, def.panel)
    end
    for tid, t in pairs(self.tabs) do
        if t.panel and tid ~= id then t.panel:Hide() end
    end
    def.panel:Show()
    self:PaintTabs()
    if changed or fromGame then self:Refresh(id) end
end

---------------------------------------------------------------------------
-- Bandeau : nom, niveau, race, classe, guilde
---------------------------------------------------------------------------
local function classColor()
    local _, class = call("UnitClass", "player")
    local colors = api("RAID_CLASS_COLORS")
    local c = type(colors) == "table" and class and colors[class]
    if c and c.r then return { c.r, c.g, c.b, 1 } end
    return ns.W.C.text
end

function CW:PaintHeader()
    if not frame then return end
    local name = call("UnitPVPName", "player") or call("UnitName", "player") or "?"
    frame.title:SetText(name)
    ns.W.TextColor(frame.title, classColor())
    local parts = {}
    local level = call("UnitLevel", "player")
    if level then parts[#parts + 1] = ns.Tf("Niveau %s", tostring(level)) end
    local race = call("UnitRace", "player")
    if race then parts[#parts + 1] = race end
    local class = call("UnitClass", "player")
    if class then parts[#parts + 1] = class end
    local guild = call("GetGuildInfo", "player")
    if type(guild) == "string" and guild ~= "" then parts[#parts + 1] = "<" .. guild .. ">" end
    frame.sub:SetText(table.concat(parts, "  ·  "))
    -- emblème rond de la classe (image classique du jeu, découpée par CLASS_ICON_TCOORDS)
    local _, classFile = call("UnitClass", "player")
    local coords = api("CLASS_ICON_TCOORDS")
    local tc = type(coords) == "table" and classFile and coords[classFile]
    if tc then
        frame.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        frame.classIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        frame.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        frame.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    frame.classRing:SetColor(classColor(), 0.9)
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local function closeCharacter()
    local cf, hide = api("CharacterFrame"), api("HideUIPanel")
    if cf and cf:IsShown() and hide then try("fermeture", hide, cf) end
    if frame then frame:Hide() end
end
CW.Close = closeCharacter

local function build()
    local W, C, Win = ns.W, ns.W.C, ns.Win
    frame = Win.Create("PlatyplusCharacterWindow", {
        width = CW.WIDTH, height = Win.HEAD_H + CW.TAB_H + 10 + CW.BODY_H + 16,
        posKey = "charWinPos", scaleKey = "charWinScale", corner = "TOPLEFT", default = { "TOPLEFT", "TOPLEFT", 30, -100 },
        onClose = closeCharacter,
    })
    frame.title:ClearAllPoints()
    frame.classIcon = frame.head:CreateTexture(nil, "ARTWORK")
    frame.classIcon:SetSize(28, 28)
    frame.classIcon:SetPoint("LEFT", frame.head, "LEFT", CW.PAD - 2, 0)
    local ringHost = CreateFrame("Frame", nil, frame.head)
    ringHost:SetPoint("TOPLEFT", frame.classIcon, "TOPLEFT", -2, 2)
    ringHost:SetPoint("BOTTOMRIGHT", frame.classIcon, "BOTTOMRIGHT", 2, -2)
    frame.classRing = W.Stroke(ringHost, "OVERLAY", 0, 15)
    frame.title:SetPoint("LEFT", frame.classIcon, "RIGHT", 10, 0)
    frame.sub = W.Text(frame.head, "GameFontHighlight", C.dim, "OVERLAY", 13)
    frame.sub:SetPoint("LEFT", frame.title, "RIGHT", 12, -1)
    frame.sub:SetPoint("RIGHT", frame.head, "RIGHT", -48, 0)
    frame.sub:SetJustifyH("LEFT")
    if frame.sub.SetWordWrap then frame.sub:SetWordWrap(false) end

    tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", frame, "TOPLEFT", CW.PAD - 8, -(Win.HEAD_H + 4))
    tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CW.PAD, -(Win.HEAD_H + 4))
    tabBar:SetHeight(CW.TAB_H)
    for _, def in ipairs(CW.order) do
        local id = def.id
        local b = Win.FlatButton(tabBar, def.label, function() CW:Select(id) end, 28)
        b.label:SetFont(W.Font(), 14, "")
        b:SetLabel(def.label)
        local line = b:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT", 8, 0)
        line:SetPoint("BOTTOMRIGHT", -8, 0)
        line:SetHeight(2)
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        line:Hide()
        b.line = line
        tabButtons[id] = b
    end

    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", CW.PAD, -(Win.HEAD_H + CW.TAB_H + 10))
    body:SetSize(CW.CONTENT_W, CW.BODY_H)

    frame:SetScript("OnHide", function()
        local tip = api("GameTooltip")
        if tip and tip:IsOwned(frame) then tip:Hide() end
    end)
    CW.frame, CW.body, CW.tabButtons = frame, body, tabButtons
    return frame
end

---------------------------------------------------------------------------
-- Onglet Personnage : équipement (case du jeu + nom de l'objet), modèle, caractéristiques en cartes
---------------------------------------------------------------------------
local SLOTS_LEFT = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" }
local SLOTS_RIGHT = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" }
local SLOTS_BOTTOM = { "MainHand", "SecondaryHand", "Ranged", "Ammo" }
local SLOT_LABEL = {
    Head = "Tête", Neck = "Cou", Shoulder = "Épaules", Back = "Dos", Chest = "Torse", Shirt = "Chemise",
    Tabard = "Tabard", Wrist = "Poignets", Hands = "Mains", Waist = "Taille", Legs = "Jambes", Feet = "Pieds",
    Finger0 = "Doigt", Finger1 = "Doigt", Trinket0 = "Bijou", Trinket1 = "Bijou", MainHand = "Main droite",
    SecondaryHand = "Main gauche", Ranged = "À distance", Ammo = "Munitions",
}
local SLOT, ROW = 37, 43                 -- case du jeu, pas d'une ligne à l'autre
local INFO_W = 150                       -- nom de l'objet à côté de la case
local SIDE_W = SLOT + 8 + INFO_W
local MODEL_W = 164
local GUTTER = 10
local EQUIP_W = 2 * SIDE_W + 2 * GUTTER + MODEL_W
local COLUMN_H = 8 * ROW - (ROW - SLOT)
local WEAPON_Y = COLUMN_H + 14
local STATS_X = EQUIP_W + 24
local STATS_W = CW.CONTENT_W - STATS_X - 8
local ROW_H = 21
CW.Layout = { SLOT = SLOT, ROW = ROW, EQUIP_W = EQUIP_W, COLUMN_H = COLUMN_H, WEAPON_Y = WEAPON_Y, STATS_X = STATS_X }

local Equip = { saved = {}, info = {} }
CW.Equip = Equip

local function slotButton(name) return api("Character" .. name .. "Slot") end

-- Les cases du jeu, posées chez nous (on garde de quoi les remettre exactement en place)
function Equip:Borrow(holder)
    for _, list in ipairs({ SLOTS_LEFT, SLOTS_RIGHT, SLOTS_BOTTOM }) do
        for _, name in ipairs(list) do
            local b = slotButton(name)
            if b and not self.saved[b] then
                local points = {}
                for i = 1, (b:GetNumPoints() or 0) do points[i] = { b:GetPoint(i) } end
                self.saved[b] = {
                    parent = b:GetParent(), points = points, level = b:GetFrameLevel(),
                    border = b.BorderFrame and b.BorderFrame:GetFrameLevel(),
                    popout = b.popoutButton and b.popoutButton:GetFrameLevel(),
                }
                b:SetParent(holder)
                local level = holder:GetFrameLevel() + 10
                b:SetFrameLevel(level)
                if b.BorderFrame then b.BorderFrame:SetFrameLevel(level - 2) end
                if b.popoutButton then b.popoutButton:SetFrameLevel(level - 3) end
            end
        end
    end
end

function Equip:Return()
    for b, s in pairs(self.saved) do
        b:SetParent(s.parent)
        b:ClearAllPoints()
        for _, p in ipairs(s.points) do b:SetPoint(unpack(p)) end
        if s.level then b:SetFrameLevel(s.level) end
        if s.border and b.BorderFrame then b.BorderFrame:SetFrameLevel(s.border) end
        if s.popout and b.popoutButton then b.popoutButton:SetFrameLevel(s.popout) end
        self.saved[b] = nil
    end
end

-- bandeau derrière une case : fond arrondi, nom de l'objet (couleur de rareté), niveau et durabilité
local function slotInfo(holder, name)
    local o = Equip.info[name]
    if o then return o end
    local W, C = ns.W, ns.W.C
    o = CreateFrame("Frame", nil, holder)
    o:SetFrameLevel(holder:GetFrameLevel() + 4)          -- au-dessus de la scène et de ses fondus
    o.bg = W.Round(o, "BACKGROUND", 0, 8)
    o.bg:SetColor(C.card, 0.55)
    o.name = W.Text(o, "GameFontHighlight", C.text, "OVERLAY", 12)
    if o.name.SetWordWrap then o.name:SetWordWrap(false) end
    o.detail = W.Text(o, "GameFontHighlightSmall", { 0.70, 0.73, 0.79, 1 }, "OVERLAY", 11)   -- un peu plus clair que C.dim
    o:EnableMouse(true)
    o:SetScript("OnEnter", function(self)
        local tip = api("GameTooltip")
        if not (tip and self.slotID) then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        if not (tip.SetInventoryItem and call(tip.SetInventoryItem, tip, "player", self.slotID)) then
            tip:SetText(ns.T(SLOT_LABEL[name] or name), 1, 1, 1)
        end
        tip:Show()
    end)
    o:SetScript("OnLeave", function()
        local tip = api("GameTooltip")
        if tip then tip:Hide() end
    end)
    Equip.info[name] = o
    return o
end

-- side : "left" (texte à droite de la case), "right" (texte à gauche), largeur du bandeau
local function placeSlot(holder, name, x, y, side, width)
    local b = slotButton(name)
    if not (b and Equip.saved[b]) then return end
    local o = slotInfo(holder, name)
    o.slotID, o.side = b:GetID(), side
    o:ClearAllPoints()
    o:SetSize(width, SLOT)
    o.name:ClearAllPoints()
    o.detail:ClearAllPoints()
    local textW = width - SLOT - 14
    o.name:SetWidth(textW)
    o.detail:SetWidth(textW)
    b:ClearAllPoints()
    if side == "right" then
        o:SetPoint("TOPRIGHT", holder, "TOPLEFT", x + SLOT, -y)
        b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
        o.name:SetPoint("TOPRIGHT", o, "TOPRIGHT", -(SLOT + 8), -5)
        o.detail:SetPoint("TOPRIGHT", o, "TOPRIGHT", -(SLOT + 8), -21)
        o.name:SetJustifyH("RIGHT")
        o.detail:SetJustifyH("RIGHT")
    else
        o:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
        b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
        o.name:SetPoint("TOPLEFT", o, "TOPLEFT", SLOT + 8, -5)
        o.detail:SetPoint("TOPLEFT", o, "TOPLEFT", SLOT + 8, -21)
        o.name:SetJustifyH("LEFT")
        o.detail:SetJustifyH("LEFT")
    end
    o:SetShown(b:IsShown())
end

function Equip:Layout(holder)
    for i, name in ipairs(SLOTS_LEFT) do placeSlot(holder, name, 0, (i - 1) * ROW, "left", SIDE_W) end
    for i, name in ipairs(SLOTS_RIGHT) do placeSlot(holder, name, EQUIP_W - SLOT, (i - 1) * ROW, "right", SIDE_W) end
    -- armes : sous le modèle sur toute la largeur, seulement celles que le jeu affiche (pas de munitions sans arme à feu)
    local shown = {}
    for _, name in ipairs(SLOTS_BOTTOM) do
        local b = slotButton(name)
        if b and self.saved[b] then
            if b:IsShown() then shown[#shown + 1] = name elseif self.info[name] then self.info[name]:Hide() end
        end
    end
    local n = #shown
    if n == 0 then return end
    local blockW = min(SIDE_W, floor((EQUIP_W - (n - 1) * GUTTER) / n))
    local x0 = floor((EQUIP_W - (n * blockW + (n - 1) * GUTTER)) / 2)       -- centrées
    for i, name in ipairs(shown) do
        placeSlot(holder, name, x0 + (i - 1) * (blockW + GUTTER), WEAPON_Y, "left", blockW)
    end
end

local function readable(c)
    local lum = 0.30 * c[1] + 0.59 * c[2] + 0.11 * c[3]
    if lum >= 0.55 then return c end
    local t = (0.55 - lum) * 1.4
    return { c[1] + (1 - c[1]) * t, c[2] + (1 - c[2]) * t, c[3] + (1 - c[3]) * t, 1 }
end

local function qualityColor(q)
    local info = ns.W.QUALITY[tonumber(q) or 1]
    local hex = info and info.hex or "ffffff"
    return readable({ tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 })
end

-- durabilité d'une case en 0..1 (nil : objet sans durabilité)
local function durability(slotID)
    local cur, maxD = call("GetInventoryItemDurability", slotID)
    cur, maxD = tonumber(cur), tonumber(maxD)
    if cur and maxD and maxD > 0 then return cur / maxD end
    return nil
end

local function durabilityText(p)
    local pct = floor(p * 100 + 0.5) .. " %"
    if p < 0.25 then return ns.W.Color("bad", pct) end
    if p < 0.6 then return ns.W.Color("gold", pct) end
    return pct
end

-- une case à la fois : un objet qui pose problème n'empêche pas les autres (ni les caractéristiques) de s'afficher
local function paintSlot(name, o)
    local W, C = ns.W, ns.W.C
    local b = slotButton(name)
    if b and o.slotID then
            local link = call("GetInventoryItemLink", "player", o.slotID)
            if link then
                local I = api("C_Item")
                local itemName = I and I.GetItemInfo and call(I.GetItemInfo, link)
                if type(itemName) ~= "string" then itemName = (tostring(link):match("%[(.-)%]")) or ns.T(SLOT_LABEL[name]) end
                o.name:SetText(itemName)
                W.TextColor(o.name, qualityColor(call("GetInventoryItemQuality", "player", o.slotID)))
                local lvl = I and I.GetDetailedItemLevelInfo and tonumber((call(I.GetDetailedItemLevelInfo, link)))
                local parts = {}
                if lvl and lvl > 1 then parts[#parts + 1] = ns.Tf("niv. %d", lvl) end
                local d = durability(o.slotID)
                if d and d < 0.6 then parts[#parts + 1] = durabilityText(d) end
                if #parts == 0 then parts[1] = ns.T(SLOT_LABEL[name] or "") end
                o.detail:SetText(table.concat(parts, "  ·  "))
                o.bg:SetColor(C.card, 0.6)
            else
                o.name:SetText(ns.T(SLOT_LABEL[name] or name))
                W.TextColor(o.name, C.off)
                o.detail:SetText(ns.T("vide"))
                o.bg:SetColor(C.card, 0.3)
            end
    end
end

function Equip:Paint()
    for name, o in pairs(self.info) do try("case " .. name, paintSlot, name, o) end
end

-- Personnage 3D : la scène de la fenêtre du jeu (CharacterModelScene), posée au centre, derrière les cases.
-- Elle garde sa caméra de fiche de personnage (pieds au sol), son fond peint de la race et ses boutons pour
-- tourner et zoomer ; ses bords se fondent dans la fenêtre. Le jeu la remplit lui-même à l'ouverture
-- (PaperDollFrame_OnShow -> SetPaperDollBackground, ModelSceneUtil.SetUpCharacterSheetScene).
-- Repli (scène absente) : un modèle simple au même endroit.
CW.ClassColor = classColor

local Stage = {}
CW.Stage = Stage
local SCENE_RATIO = 0.95             -- largeur / hauteur de la scène du jeu, si on ne peut pas la mesurer

local function scene() return api("CharacterModelScene") end

local function savePoints(f)
    local points = {}
    for i = 1, (f:GetNumPoints() or 0) do points[i] = { f:GetPoint(i) } end
    return points
end

local function restorePoints(f, points)
    f:ClearAllPoints()
    for _, p in ipairs(points) do f:SetPoint(unpack(p)) end
end

function Stage:Borrow(holder)
    local sc = scene()
    if not sc or self.saved then return end
    local ctrl = sc.ControlFrame
    self.saved = {
        parent = sc:GetParent(), points = savePoints(sc), level = sc:GetFrameLevel(),
        w = sc:GetWidth(), h = sc:GetHeight(),
        ctrlPoints = ctrl and savePoints(ctrl), ctrlLevel = ctrl and ctrl:GetFrameLevel(),
    }
    local w, h = tonumber(self.saved.w) or 0, tonumber(self.saved.h) or 0
    local ratio = (w > 50 and h > 50) and (w / h) or SCENE_RATIO
    ratio = max(0.75, min(1.15, ratio))
    local sh = COLUMN_H
    local sw = floor(sh * ratio)
    sc:SetParent(holder)
    sc:ClearAllPoints()
    sc:SetPoint("TOP", holder, "TOPLEFT", floor(EQUIP_W / 2), 0)
    sc:SetSize(sw, sh)
    sc:SetFrameLevel(holder:GetFrameLevel() + 1)
    if ctrl then
        ctrl:ClearAllPoints()
        ctrl:SetPoint("BOTTOM", sc, "BOTTOM", 0, 14)
        ctrl:SetFrameLevel(holder:GetFrameLevel() + 8)
    end
    self.scene, self.width = sc, sw
    self:Fade()
end

function Stage:Return()
    local s = self.saved
    if not s then return end
    local sc = scene()
    if sc then
        sc:SetParent(s.parent)
        restorePoints(sc, s.points)
        if s.level then sc:SetFrameLevel(s.level) end
        local ctrl = sc.ControlFrame
        if ctrl and s.ctrlPoints then
            restorePoints(ctrl, s.ctrlPoints)
            if s.ctrlLevel then ctrl:SetFrameLevel(s.ctrlLevel) end
        end
    end
    if self.fader then self.fader:Hide() end
    self.saved, self.scene = nil, nil
end

-- fondus vers la couleur de la fenêtre sur les quatre bords de la scène (Gradient : opaque en haut, transparent en bas)
function Stage:Build(holder)
    local W, C = ns.W, ns.W.C
    local f = CreateFrame("Frame", nil, holder)
    f:SetFrameLevel(holder:GetFrameLevel() + 3)
    f:SetAllPoints(holder)
    local function edge(coords)
        local t = W.NewTex(f, W.TEX.grad, "ARTWORK", 0)
        t:SetTexCoord(unpack(coords))
        t:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
        return t
    end
    -- (8 coordonnées : haut-gauche, bas-gauche, haut-droite, bas-droite)
    f.left = edge({ 0, 0, 1, 0, 0, 1, 1, 1 })        -- opaque à gauche
    f.right = edge({ 0, 1, 1, 1, 0, 0, 1, 0 })       -- opaque à droite
    f.top = edge({ 0, 0, 0, 1, 1, 0, 1, 1 })         -- opaque en haut
    f.bottom = edge({ 0, 1, 0, 0, 1, 1, 1, 0 })      -- opaque en bas
    self.fader = f
    f:Hide()
    return f
end

function Stage:Fade()
    local f, sc = self.fader, self.scene
    if not (f and sc) then return end
    f:Show()
    f.left:ClearAllPoints()
    f.left:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
    f.left:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 0, 0)
    f.left:SetWidth(70)
    f.right:ClearAllPoints()
    f.right:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, 0)
    f.right:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0, 0)
    f.right:SetWidth(70)
    f.top:ClearAllPoints()
    f.top:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
    f.top:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, 0)
    f.top:SetHeight(36)
    f.bottom:ClearAllPoints()
    f.bottom:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 0, 0)
    f.bottom:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0, 0)
    f.bottom:SetHeight(48)
end

-- repli : modèle simple, glisser pour tourner, molette pour zoomer
local function buildFallbackModel(holder)
    local W, C = ns.W, ns.W.C
    local box = CreateFrame("Frame", nil, holder)
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", SIDE_W + GUTTER, 0)
    box:SetSize(MODEL_W, COLUMN_H)
    W.Round(box, "BACKGROUND", 0, 12):SetColor(C.panel, 1)
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, box)
    if not ok or not model then return box end
    model:SetAllPoints(box)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    local facing, zoom, dragging, lastX = 0, 1, false, 0
    local function cursorX() local x = call("GetCursorPosition"); return tonumber(x) or 0 end
    model:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then dragging, lastX = true, cursorX() end
    end)
    model:SetScript("OnMouseUp", function() dragging = false end)
    model:SetScript("OnUpdate", function(self)
        if not dragging then return end
        local x = cursorX()
        facing = facing + (x - lastX) * 0.015
        lastX = x
        if self.SetFacing then self:SetFacing(facing) end
    end)
    model:SetScript("OnMouseWheel", function(self, delta)
        zoom = max(0.45, min(1.3, zoom - delta * 0.1))
        if self.SetCamDistanceScale then self:SetCamDistanceScale(zoom) end
    end)
    function box:Refresh()
        if model.SetUnit then try("modèle", model.SetUnit, model, "player") end
        if model.SetFacing then model:SetFacing(facing) end
        if model.SetCamDistanceScale then model:SetCamDistanceScale(zoom) end
    end
    model:SetScript("OnShow", function()
        box:Refresh()
        C_Timer.After(0.1, function() if model:IsVisible() then box:Refresh() end end)
    end)
    box.model = model
    return box
end

-- la scène du jeu si elle existe, sinon le modèle simple ; renvoie un objet avec :Refresh()
local function buildModel(holder)
    if scene() then
        Stage:Build(holder)
        return { Refresh = function() end, stage = true }
    end
    return buildFallbackModel(holder)
end

---------------------------------------------------------------------------
-- Caractéristiques : niveau d'objet et durabilité en tête, puis une carte par catégorie ; les fonctions du jeu
-- remplissent nos lignes (mêmes valeurs, mêmes infobulles)
---------------------------------------------------------------------------
local stats = { rows = {}, cards = {}, used = { rows = 0, cards = 0 }, y = 0 }
CW.Stats = stats
local CARD_HEAD = 28

-- Texte « marqué » par une valeur protégée : dans Forever, SetText(valeur secrète) pose sur le texte l'aspect secret
-- « Text » (SimpleFontStringAPI : SecretArgumentsAddAspect), et il RESTE après un SetText ordinaire : seuls ClearText
-- et SetToDefaults l'enlèvent (SimpleFrameScriptObjectAPI). GetText rend alors une valeur protégée, et la moindre
-- comparaison plante. C'était la cause des caractéristiques disparues (retour du joueur 2026-11-07 : « Vie » et
-- « Rage » seulement) : après un combat (affichage brut), les lignes réutilisées gardaient la marque, la 3e ligne
-- plantait à la relecture, et comme la ligne fautive resservait à la suivante, toutes les suivantes tombaient aussi.
-- Renvoie false si la marque est toujours là (le texte doit alors être remplacé).
local function cleanText(fs)
    if fs.ClearText then pcall(fs.ClearText, fs) end
    local aspects = rawget(_G, "Enum") and Enum.SecretAspect
    if aspects and aspects.Text and fs.HasSecretAspect then
        local ok, has = pcall(fs.HasSecretAspect, fs, aspects.Text)
        if ok and has == true then return false end
    end
    return true
end
CW.CleanText = cleanText

local function newLabel(r)
    local W, C = ns.W, ns.W.C
    local fs = W.Text(r, "GameFontHighlight", C.dim, "OVERLAY", 13)
    fs:SetPoint("LEFT", r, "LEFT", 4, 0)
    fs:SetJustifyH("LEFT")
    return fs
end

local function newValue(r)
    local W, C = ns.W, ns.W.C
    local fs = W.Text(r, "GameFontHighlight", C.text, "OVERLAY", 14)
    fs:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    fs:SetJustifyH("RIGHT")
    return fs
end

local function statRow()
    stats.used.rows = stats.used.rows + 1
    local r = stats.rows[stats.used.rows]
    if not r then
        r = CreateFrame("Frame", nil, stats.area.child)
        r:SetSize(STATS_W - 16, ROW_H)
        r.Label = newLabel(r)
        r.Value = newValue(r)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.05)
        r.hl:Hide()
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.onEnterFunc then
                try("infobulle", self.onEnterFunc, self)
            elseif api("PaperDollStatTooltip") then
                try("infobulle", PaperDollStatTooltip, self)
            end
        end)
        r:SetScript("OnLeave", function(self)
            self.hl:Hide()
            local tip = api("GameTooltip")
            if tip then tip:Hide() end
            self.UpdateTooltip = nil
        end)
        stats.rows[stats.used.rows] = r
    end
    r.tooltip, r.tooltip2, r.tooltip3, r.onEnterFunc, r.UpdateTooltip, r.numericValue = nil, nil, nil, nil, nil, nil
    -- ligne réutilisée : enlève la marque d'une valeur protégée affichée avant ; sinon texte neuf
    if not cleanText(r.Value) then r.Value:Hide(); r.Value = newValue(r) end
    if not cleanText(r.Label) then r.Label:Hide(); r.Label = newLabel(r) end
    r.Label:SetText("")
    r.Value:SetText("")
    ns.W.TextColor(r.Value, ns.W.C.text)
    r:ClearAllPoints()
    r:Show()
    return r
end

local function dropRow(r)
    r:Hide()
    stats.used.rows = stats.used.rows - 1
end

local function statCard(title)
    stats.used.cards = stats.used.cards + 1
    local c = stats.cards[stats.used.cards]
    if not c then
        local W, C = ns.W, ns.W.C
        c = CreateFrame("Frame", nil, stats.area.child)
        c:SetWidth(STATS_W)
        c.bg = W.Round(c, "BACKGROUND", 0, 10)
        c.bg:SetColor(C.card, 0.55)
        c.title = W.Text(c, "GameFontNormal", C.accent, "OVERLAY", 11)
        c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -10)
        stats.cards[stats.used.cards] = c
    end
    c.title:SetText(ns.Win.Upper(title))
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", stats.area.child, "TOPLEFT", 0, -stats.y)
    c:Show()
    return c
end

-- Valeurs « secrètes » : quand le jeu restreint les statistiques (Forever : UnitStat, UnitArmor, GetUnitSpeed,
-- UnitDamage, GetCritChance... sont « SecretWhenUnitStatsRestricted »), un addon peut les afficher telles quelles
-- (SetText, SetFormattedText) mais pas les comparer ni calculer avec : les fonctions du jeu qui les mettent en forme
-- échouent alors quand c'est nous qui les appelons. On passe dans ce cas à un affichage simplifié.
local function secret(v)
    local f = api("issecretvalue")
    if not f then return false end
    local ok, s = pcall(f, v)
    return ok and s and true or false
end

local function statsRestricted()
    local f = api("UnitStat")
    if not f then return false end
    local ok, _, effective = pcall(f, "player", 1)
    return ok and secret(effective)
end
CW.StatsRestricted = statsRestricted

-- une catégorie : list = { function(ligne) qui la remplit et renvoie sa valeur, valeur à cacher ou nil }, ... ;
-- raw = valeurs brutes (secrètes possibles) : on ne compare rien. Rien n'est affiché si tout est caché.
local function keepRow(r, result, hideAt, raw)
    if not r:IsShown() then return false end
    if raw then return true end
    -- comme le volet du jeu : la valeur renvoyée par la fonction décide (certaines s'arrêtent sans rien écrire) ;
    -- une valeur protégée ne se compare pas : elle s'affiche
    if hideAt ~= nil and not secret(result) and not secret(r.numericValue)
        and (result == hideAt or r.numericValue == hideAt) then return false end
    local text = r.Value:GetText()
    if secret(text) then return true end
    return type(text) ~= "string" or text ~= ""
end

-- entry = { remplit la ligne, valeur à cacher, [repli brut si la fonction du jeu échoue] }
local function addCategory(title, list, raw)
    local card
    local n = 0
    for _, entry in ipairs(list) do
        local r = statRow()
        local ok, result = pcall(entry[1], r)
        local rowRaw = raw
        if not ok and entry[3] then
            -- la fonction du jeu a échoué (valeur protégée en cours de route...) : la valeur brute du jeu à la place
            stats.fallbacks = (stats.fallbacks or 0) + 1
            stats.lastError = tostring(result)
            if not cleanText(r.Value) then r.Value:Hide(); r.Value = newValue(r) end
            r.Value:SetText("")
            r:Show()
            ok = pcall(entry[3], r)
            rowRaw = true
        elseif not ok then
            stats.lastError = tostring(result)
        end
        local okKeep, keep = false, false
        if ok then okKeep, keep = pcall(keepRow, r, result, entry[2], rowRaw) end
        if not (ok and okKeep and keep) then
            dropRow(r)
        else
            if not card then card = statCard(title) end
            local label = r.Label:GetText()
            if type(label) == "string" and not secret(label) then r.Label:SetText((label:gsub("%s*:%s*$", ""))) end
            r:SetParent(card)
            r:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -(CARD_HEAD + n * ROW_H))
            n = n + 1
        end
    end
    if card then
        local h = CARD_HEAD + n * ROW_H + 8
        card:SetHeight(h)
        stats.y = stats.y + h + 8
    end
end

-- affichage simplifié : la valeur brute du jeu, sans calcul
local function rawValue(label, fn, ...)
    local args = { n = select("#", ...), ... }
    return function(r)
        local get = api(fn)
        if not get then error("absent : " .. fn) end
        local res = { get(unpack(args, 1, args.n)) }
        r.Label:SetText(ns.T(label))
        r.Value:SetText(res[1])
    end
end

local function rawPick(label, fn, index, ...)
    local args = { n = select("#", ...), ... }
    return function(r)
        local get = api(fn)
        if not get then error("absent : " .. fn) end
        local res = { get(unpack(args, 1, args.n)) }
        r.Label:SetText(label)
        r.Value:SetText(res[index])
    end
end

local function rawPercent(label, fn, ...)
    local args = { n = select("#", ...), ... }
    return function(r)
        local get = api(fn)
        if not get then error("absent : " .. fn) end
        r.Label:SetText(label)
        r.Value:SetFormattedText("%.2f %%", (get(unpack(args, 1, args.n))))
    end
end

local function g(name, fallback)
    local v = api(name)
    return type(v) == "string" and v ~= "" and v or fallback
end

local function fillRawStats()
    local _, powerToken = call("UnitPowerType", "player")
    addCategory(g("STAT_CATEGORY_GENERAL", "Général"), {
        { rawValue(g("HEALTH", "Vie"), "UnitHealthMax", "player") },
        { rawValue(powerToken and g(powerToken, "Énergie") or "Énergie", "UnitPowerMax", "player") },
    }, true)
    local attrs = {}
    for i, name in ipairs({ "Force", "Agilité", "Endurance", "Intelligence", "Esprit" }) do
        attrs[#attrs + 1] = { rawPick(g("SPELL_STAT" .. i .. "_NAME", name), "UnitStat", 2, "player", i) }
    end
    addCategory(g("STAT_CATEGORY_PRIMARY_ATTRIBUTES", "Attributs"), attrs, true)
    addCategory(g("STAT_CATEGORY_MODIFIERS", "Modificateurs"), {
        { rawPercent(g("CRIT_CHANCE", "Coup critique"), "GetCritChance") },
    }, true)
    local defense = {
        { rawPick(g("ARMOR", "Armure"), "UnitArmor", 2, "player") },
        { rawPercent(g("STAT_DODGE", "Esquive"), "GetDodgeChance") },
        { rawPercent(g("STAT_PARRY", "Parade"), "GetParryChance") },
    }
    local P = api("C_PaperDollInfo")
    if P and P.OffhandHasShield and call(P.OffhandHasShield) then
        defense[#defense + 1] = { rawPercent(g("STAT_BLOCK", "Blocage"), "GetBlockChance") }
    end
    addCategory(g("STAT_CATEGORY_DEFENSE", "Défense"), defense, true)
end

-- repli d'une ligne quand la fonction du jeu échoue : la valeur brute (clé de PAPERDOLL_STATINFO -> remplissage)
local function rawFallback(key, unit)
    unit = unit or "player"
    local stat = ({ STRENGTH = 1, AGILITY = 2, STAMINA = 3, INTELLECT = 4, SPIRIT = 5 })[key]
    if stat then
        local names = { "Force", "Agilité", "Endurance", "Intelligence", "Esprit" }
        return rawPick(g("SPELL_STAT" .. stat .. "_NAME", names[stat]), "UnitStat", 2, unit, stat)
    end
    if key == "HEALTH" then return rawValue(g("HEALTH", "Vie"), "UnitHealthMax", unit) end
    if key == "POWER" then
        local _, token = call("UnitPowerType", unit)
        return rawValue(token and g(token, "Énergie") or "Énergie", "UnitPowerMax", unit)
    end
    if key == "ARMOR" then return rawPick(g("ARMOR", "Armure"), "UnitArmor", 2, unit) end
    if unit ~= "player" then return nil end
    if key == "CRITCHANCE" then return rawPercent(g("CRIT_CHANCE", "Coup critique"), "GetCritChance") end
    if key == "DODGE" then return rawPercent(g("STAT_DODGE", "Esquive"), "GetDodgeChance") end
    if key == "PARRY" then return rawPercent(g("STAT_PARRY", "Parade"), "GetParryChance") end
    if key == "BLOCK" then return rawPercent(g("STAT_BLOCK", "Blocage"), "GetBlockChance") end
    return nil
end
CW.RawFallback = rawFallback

-- résistances : cinq pastilles colorées sur une ligne
local SCHOOLS = {
    { "Arcane", "Arcanes", { 0.78, 0.58, 1.00 } }, { "Fire", "Feu", { 1.00, 0.52, 0.22 } },
    { "Frost", "Givre", { 0.45, 0.76, 1.00 } }, { "Nature", "Nature", { 0.48, 0.90, 0.36 } },
    { "Shadow", "Ombre", { 0.66, 0.42, 0.88 } },
}

local function addResistances()
    local classes = Enum and Enum.Damageclass
    if type(classes) ~= "table" or not api("UnitResistance") then return end
    local W, C = ns.W, ns.W.C
    local card = statCard(ns.T("Résistances"))
    card.chips = card.chips or {}
    local chipW = floor((STATS_W - 16) / #SCHOOLS)
    for i, s in ipairs(SCHOOLS) do
        local chip = card.chips[i]
        if not chip then
            chip = CreateFrame("Frame", nil, card)
            chip:SetSize(chipW, 24)
            chip.dot = W.NewTex(chip, W.TEX.circle, "ARTWORK", 0)
            chip.dot:SetSize(10, 10)
            chip.dot:SetPoint("LEFT", chip, "LEFT", 8, 0)
            chip.value = W.Text(chip, "GameFontHighlight", C.text, "OVERLAY", 14)
            chip.value:SetPoint("LEFT", chip.dot, "RIGHT", 6, 0)
            chip:EnableMouse(true)
            chip:SetScript("OnEnter", function(self)
                local tip = api("GameTooltip")
                if not tip then return end
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText(ns.Tf("Résistance : %s", self.label), 1, 1, 1)
                tip:Show()
            end)
            chip:SetScript("OnLeave", function() local tip = api("GameTooltip"); if tip then tip:Hide() end end)
            card.chips[i] = chip
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", card, "TOPLEFT", 8 + (i - 1) * chipW, -CARD_HEAD)
        chip.dot:SetVertexColor(s[3][1], s[3][2], s[3][3], 1)
        chip.label = ns.T(s[2])
        local _, real, effective = call("UnitResistance", "player", classes[s[1]] or 0)
        local v = effective
        if v == nil then v = real end
        if v == nil then v = 0 end
        chip.value:SetText(secret(v) and v or tostring(v))   -- (valeur protégée : affichée telle quelle)
    end
    card:SetHeight(CARD_HEAD + 24 + 8)
    stats.y = stats.y + CARD_HEAD + 32 + 8
end

-- carte du haut : niveau d'objet moyen en grand, durabilité la plus basse
local function buildHero(area)
    local W, C, Win = ns.W, ns.W.C, ns.Win
    local h = CreateFrame("Frame", nil, area.child)
    h:SetSize(STATS_W, 78)
    h:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, 0)
    W.Round(h, "BACKGROUND", 0, 10):SetColor(C.card, 0.8)
    local shine = W.NewTex(h, W.TEX.grad, "BACKGROUND", 1)
    shine:SetPoint("TOPLEFT", h, "TOPLEFT", 4, -2)
    shine:SetPoint("TOPRIGHT", h, "TOPRIGHT", -4, -2)
    shine:SetHeight(40)
    shine:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.07)
    local l1 = W.Text(h, "GameFontNormal", C.dim, "OVERLAY", 11)
    l1:SetPoint("TOPLEFT", h, "TOPLEFT", 14, -12)
    l1:SetText(ns.T("NIVEAU D'OBJET"))
    h.ilvl = W.Text(h, "GameFontHighlightLarge", C.gold, "OVERLAY", 32)
    h.ilvl:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -4)
    local l2 = W.Text(h, "GameFontNormal", C.dim, "OVERLAY", 11)
    l2:SetPoint("TOPLEFT", h, "TOPLEFT", floor(STATS_W / 2) + 4, -12)
    l2:SetText(ns.T("DURABILITÉ"))
    h.dura = W.Text(h, "GameFontHighlight", C.text, "OVERLAY", 18)
    h.dura:SetPoint("TOPLEFT", l2, "BOTTOMLEFT", 0, -5)
    h.bar = Win.Bar(h, 6)
    h.bar:SetWidth(floor(STATS_W / 2) - 18)
    h.bar:SetPoint("TOPLEFT", h.dura, "BOTTOMLEFT", 0, -7)
    h.ilvl:SetText("—")
    return h
end

local function paintHero(h)
    local C = ns.W.C
    local avg, equipped = call("GetAverageItemLevel")
    local lvl = tonumber(equipped) or tonumber(avg)
    h.ilvl:SetText(lvl and tostring(floor(lvl)) or "—")
    local lowest
    for slotID = 1, 19 do
        local d = durability(slotID)
        if d and (not lowest or d < lowest) then lowest = d end
    end
    if lowest then
        h.dura:SetText(floor(lowest * 100 + 0.5) .. " %")
        h.bar:Show()
        h.bar:SetValue(lowest)
        h.bar:SetColor(lowest < 0.25 and C.bad or (lowest < 0.6 and C.gold or C.good))
    else
        h.dura:SetText("—")
        h.bar:Hide()
    end
end

local function fillStats(panel)
    local area = panel.stats
    stats.area = area
    for _, r in ipairs(stats.rows) do r:Hide() end
    for _, c in ipairs(stats.cards) do c:Hide() end
    stats.used.rows, stats.used.cards = 0, 0
    paintHero(panel.hero)
    stats.y = 78 + 10
    local info = api("PAPERDOLL_STATINFO")
    local catalog = api("PAPERDOLL_STATCATEGORIES")
    local restricted = statsRestricted()
    stats.restricted = restricted
    if restricted then
        fillRawStats()
    elseif type(info) == "table" and type(catalog) == "table" then
        local hasPet = call("UnitExists", "pet")
        for _, cat in ipairs(catalog) do
            local unit = cat.unit or "player"
            if unit == "player" or (unit == "pet" and hasPet) then
                local list = {}
                for _, stat in ipairs(cat.stats or {}) do
                    local def = info[stat.stat]
                    local show = def ~= nil
                    if show and stat.showFunc then
                        local ok, v = pcall(stat.showFunc)
                        show = ok and v and true or false
                    end
                    if show then
                        list[#list + 1] = { function(r) return def.updateFunc(r, unit) end, stat.hideAt,
                            rawFallback(stat.stat, unit) }
                    end
                end
                local title = cat.categoryName or ""
                if unit == "pet" then title = ns.Tf("Familier · %s", title) end
                addCategory(title, list)
            end
        end
    else
        -- repli : l'essentiel lu directement
        local list = { { function(r)
            r.Label:SetText(ns.T("Vie"))
            r.Value:SetText(tostring(call("UnitHealthMax", "player") or "?"))
        end } }
        for i, label in ipairs({ "Force", "Agilité", "Endurance", "Intelligence", "Esprit" }) do
            list[#list + 1] = { function(r)
                local _, effective = call("UnitStat", "player", i)
                r.Label:SetText(ns.T(label))
                r.Value:SetText(tostring(effective or "?"))
            end }
        end
        list[#list + 1] = { function(r)
            local _, effective = call("UnitArmor", "player")
            r.Label:SetText(ns.T("Armure"))
            r.Value:SetText(tostring(effective or "?"))
        end }
        addCategory(ns.T("Caractéristiques"), list)
    end
    addResistances()
    -- note sous les cartes quand le jeu protège les valeurs
    if not stats.note then
        stats.note = ns.W.Text(area.child, "GameFontHighlightSmall", ns.W.C.dim, "OVERLAY", 11)
        stats.note:SetJustifyH("LEFT")
        stats.note:SetWidth(STATS_W - 8)
        stats.note:SetText(ns.T("Le jeu protège une partie des caractéristiques en ce moment : affichage simplifié, sans détail au survol. Tout revient dès qu'il les rend lisibles."))
    end
    stats.note:ClearAllPoints()
    if restricted then
        stats.note:SetPoint("TOPLEFT", area.child, "TOPLEFT", 4, -stats.y)
        stats.note:Show()
        stats.y = stats.y + ns.W.Measure(stats.note, stats.note:GetText(), STATS_W - 8) + 8
    else
        stats.note:Hide()
    end
    area:SetContentHeight(stats.y)
end

local function buildEquipment(panel)
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    holder:SetSize(EQUIP_W, CW.BODY_H)
    panel.holder = holder
    panel.model = buildModel(holder)
    local area = ns.Win.ScrollArea(panel, STATS_W, CW.BODY_H)
    area.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", STATS_X, 0)
    panel.stats = area
    stats.area = area
    panel.hero = buildHero(area)
    if enabledOption() then
        Equip:Borrow(holder)
        Stage:Borrow(holder)
    end
end

-- chaque partie à part : si l'une échoue (API du jeu inattendue), les autres s'affichent quand même
local function refreshEquipment(panel)
    if enabledOption() then
        try("cases", Equip.Borrow, Equip, panel.holder)
        try("scène", Stage.Borrow, Stage, panel.holder)
    end
    try("disposition", Equip.Layout, Equip, panel.holder)
    try("objets", Equip.Paint, Equip)
    if panel.model.Refresh then try("modèle", panel.model.Refresh, panel.model) end
    try("caractéristiques", fillStats, panel)
end

CW:RegisterTab({
    id = "PaperDollFrame", label = "Personnage", order = 1,
    build = buildEquipment, refresh = refreshEquipment,
    events = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_MODEL_CHANGED", "UNIT_STATS", "UNIT_RESISTANCES", "UNIT_ATTACK_POWER",
               "UNIT_RANGED_ATTACK_POWER", "UNIT_DAMAGE", "UNIT_ATTACK_SPEED", "UNIT_MAXHEALTH", "UNIT_MAXPOWER",
               "UNIT_AURA", "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS", "SKILL_LINES_CHANGED", "UNIT_PET",
               "UPDATE_INVENTORY_DURABILITY", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" },
})

---------------------------------------------------------------------------
-- Ouverture / fermeture : on suit la fenêtre du jeu
---------------------------------------------------------------------------

local function activeSubframe()
    local cf = api("CharacterFrame")
    local active = cf and cf.activeSubframe
    if active and CW.tabs[active] then return active end
    for _, def in ipairs(CW.order) do
        local sub = api(def.id)
        if type(sub) == "table" and sub.IsShown and sub:IsShown() then return def.id end
    end
    return nil
end

function CW:Sync()
    if not enabledOption() then
        if frame then frame:Hide() end
        return
    end
    local cf = api("CharacterFrame")
    if cf and cf:IsShown() then
        if not frame then
            local ok = try("construction", build)
            if not ok then
                self.broken = true
                self:Apply()
                ns:Print("la fenêtre du personnage n'a pas pu s'ouvrir : fenêtre du jeu gardée")
                return
            end
        end
        self:PaintHeader()
        ns.Win.Open(frame)
        self:Select(activeSubframe() or self.current or "PaperDollFrame", true)
    elseif frame and frame:IsShown() then
        frame:Hide()
    end
end

local pending = false
local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        CW:Sync()
    end)
end
CW.Schedule = schedule

function CW:Apply()
    local cf = api("CharacterFrame")
    if enabledOption() then
        if cf then ns.Win.Conceal(cf) end
        local def = self.tabs.PaperDollFrame
        if def.panel then
            Equip:Borrow(def.panel.holder)
            Stage:Borrow(def.panel.holder)
        end
        schedule()
    else
        Equip:Return()
        Stage:Return()
        if cf then ns.Win.Reveal(cf) end
        if frame then frame:Hide() end
    end
end

function CW:ApplyScale()
    if frame then ns.Win.Place(frame) end
end

function CW:ResetPosition()
    ns.db.charWinPos = {}
    if frame then ns.Win.Reset(frame) end
end

local events = CreateFrame("Frame")
local eventTabs = {}          -- [événement] = { id d'onglet, ... }
local HEADER_EVENTS = { UNIT_NAME_UPDATE = true, PLAYER_LEVEL_UP = true, PLAYER_GUILD_UPDATE = true,
                        PLAYER_PVP_RANK_CHANGED = true }
events:SetScript("OnEvent", function(_, event, unit)
    if not (frame and frame:IsShown()) then return end
    if event:find("^UNIT_") and unit ~= "player" and event ~= "UNIT_PET" then return end
    if HEADER_EVENTS[event] then CW:PaintHeader() end
    for _, id in ipairs(eventTabs[event] or {}) do
        if CW.current == id then refreshSoon(id) end
    end
end)

function CW:Init()
    for _, def in ipairs(self.order) do
        for _, e in ipairs(def.events or {}) do
            eventTabs[e] = eventTabs[e] or {}
            table.insert(eventTabs[e], def.id)
        end
    end
    for e in pairs(eventTabs) do pcall(events.RegisterEvent, events, e) end
    for e in pairs(HEADER_EVENTS) do pcall(events.RegisterEvent, events, e) end
    local cf = api("CharacterFrame")
    if cf and cf.HookScript then
        cf:HookScript("OnShow", schedule)
        cf:HookScript("OnHide", schedule)
    end
    if api("hooksecurefunc") then
        -- un volet ouvert par une touche (U, K...) ou par nos onglets : l'onglet suit
        if cf and type(cf.ShowSubFrame) == "function" then
            hooksecurefunc(cf, "ShowSubFrame", function(_, name)
                if frame and frame:IsShown() and CW.tabs[name] then CW:Select(name, true) end
            end)
        end
        -- le jeu recalcule ses caractéristiques : les nôtres aussi
        if type(api("PaperDollFrame_UpdateStats")) == "function" then
            hooksecurefunc("PaperDollFrame_UpdateStats", function()
                if CW.current == "PaperDollFrame" then refreshSoon("PaperDollFrame") end
            end)
        end
    end
    ns:OnChange("charWindow", function() CW:Apply() end)
    ns:OnChange("charWinScale", function() CW:ApplyScale() end)
    try("application", function() CW:Apply() end)
end

function CW:Status()
    local lines = {}
    lines[1] = "fenêtre du personnage : " .. (db("charWindow") and (self.broken and "en panne (fenêtre du jeu gardée)" or "active") or "coupée")
    local n = 0
    for _ in pairs(Equip.saved) do n = n + 1 end
    lines[2] = "cases d'équipement posées : " .. n .. " ; onglet : " .. tostring(self.current or "aucun")
    lines[3] = "caractéristiques : " .. (stats.restricted and "protégées (affichage brut)" or "lisibles")
        .. ", " .. (stats.fallbacks or 0) .. " ligne(s) remplie(s) par la valeur brute"
        .. (stats.lastError and (" ; dernière erreur : " .. stats.lastError) or "")
    return lines
end
