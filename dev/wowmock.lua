-- Simulateur minimal de l'API WoW pour exécuter Platyplus hors du jeu (LuaJIT / Lua 5.1).
-- But : attraper les erreurs d'exécution (nil, noms d'API faux, globales oubliées), pas valider le comportement réel du jeu.
local M = {}
local G = _G

local st = setmetatable({}, { __mode = "k" })   -- état caché de chaque frame
M.errors = {}
M.allFrames = {}
M.newGlobals = {}
M.time = 0
M.timers = {}
M.printed = {}

local function recordError(where, err)
    M.errors[#M.errors + 1] = where .. " : " .. tostring(err)
end

local function safe(where, fn, ...)
    local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end, ...)
    if not ok then recordError(where, err) end
    return ok, err
end
M.safe = safe

-- print : on garde aussi une copie pour pouvoir tester les messages
local realPrint = print
G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    M.printed[#M.printed + 1] = line
    if M.verbose then realPrint("   > " .. line) end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local NOOP = {}
for name in ([[
SetSize SetWidth SetHeight SetAllPoints SetParent SetAlpha SetScale SetFrameStrata SetFrameLevel Raise Lower
SetToplevel SetMovable SetResizable SetClampedToScreen SetClampRectInsets EnableMouse EnableMouseWheel
EnableKeyboard SetPropagateKeyboardInput RegisterForDrag RegisterForClicks StartMoving StopMovingOrSizing
SetHitRectInsets SetFixedFrameStrata SetFixedFrameLevel SetIgnoreParentScale SetIgnoreParentAlpha SetID
SetTexCoord SetVertexColor SetBlendMode SetDesaturated SetAtlas SetDrawLayer SetRotation SetGradient
SetFont SetFontObject SetTextColor SetJustifyH SetJustifyV SetWordWrap SetNonSpaceWrap SetMaxLines
SetShadowColor SetShadowOffset SetSpacing SetIndentedWordWrap SetTextInsets SetMaxLetters SetNumeric SetAutoFocus
SetMultiLine HighlightText SetCursorPosition SetBlinkSpeed
SetNormalTexture SetPushedTexture SetHighlightTexture SetDisabledTexture SetNormalFontObject SetHighlightFontObject
SetDisabledFontObject SetButtonState LockHighlight UnlockHighlight SetPushedTextOffset SetMotionScriptsWhileDisabled
SetOrientation SetThumbTexture SetObeyStepOnDrag SetValueStep UpdateScrollChildRect SetHorizontalScroll
SetOwner SetText AddLine AddDoubleLine ClearLines SetHyperlink SetBagItem SetItemByID SetPadding
SetBackdrop SetBackdropColor SetBackdropBorderColor ClearBackdrop SetMask SetColorTexture SetTexture SetFormattedText
SetUnit SetInventoryItem SetClipsChildren SetHorizontalScroll EnableDrawLayer SetDontSavePosition SetUserPlaced
SetStatusBarTexture SetStatusBarColor SetFocus ClearFocus SetCooldown SetFontHeight SetTexture
SetDuration SetFromAlpha SetToAlpha SetOffset SetScaleFrom SetScaleTo SetOrigin SetOrder SetSmoothing SetStartDelay
SetEndDelay SetLooping SetChildKey SetTarget SetToFinalAlpha SetReverseFill SetFillStyle SetRotatesTexture
SetSnapToPixelGrid SetTexelSnappingBias SetTextureSliceMargins SetTextureSliceMode SetMouseClickEnabled
SetMouseMotionEnabled SetPassThroughButtons SetResizeBounds SetHighlightAtlas SetNormalAtlas SetPushedAtlas
SetDesaturation SetVertTile SetHorizTile SetTextScale SetAlphaGradient SetIgnoreParentScale SetDegrees SetRadians
SetAllPointsTo SetCollapsesLayout SetFrameBuffer SetFlattensRenderLayers SetDrawEdge SetSwipeColor SetHideCountdownNumbers
AddMaskTexture RemoveMaskTexture SetMask SetHyperlinksEnabled StartSizing
]]):gmatch("%S+") do NOOP[name] = true end

local function noop() end

local impl = {}

local function newState(kind, name, parent)
    return {
        kind = kind, name = name, parent = parent, shown = true, scripts = {}, events = {},
        w = 0, h = 0, alpha = 1, scale = 1, strata = "MEDIUM", level = 1, text = "", points = {},
        enabled = true, value = 0, min = 0, max = 100, step = 0, checked = false, id = 0, vscroll = 0,
        frames = {}, regions = {}, focus = false,
    }
end

local Class = {}
Class.__index = function(f, k)
    if impl[k] then return impl[k] end
    if NOOP[k] then return noop end
    return nil
end
Class.__tostring = function(f) return "[" .. st[f].kind .. ":" .. tostring(st[f].name) .. "]" end

local function newObject(kind, name, parent)
    local f = setmetatable({}, Class)
    st[f] = newState(kind, name, parent)
    M.allFrames[#M.allFrames + 1] = f
    return f
end
M.state = function(f) return st[f] end

local function fire(f, script, ...)
    local fn = st[f].scripts[script]
    if fn then safe("script " .. script .. " de " .. tostring(st[f].name or st[f].kind), fn, f, ...) end
end
M.fire = fire

-- comme dans le jeu : poser un script OnKeyDown / OnKeyUp active le clavier du cadre (KeybindListener de Blizzard)
function impl.SetScript(f, name, fn)
    st[f].scripts[name] = fn
    if (name == "OnKeyDown" or name == "OnKeyUp") and fn then st[f].keyboard = true end
end
function impl.EnableKeyboard(f, v) st[f].keyboard = v and true or false end
function impl.IsKeyboardEnabled(f) return st[f].keyboard == true end
function impl.GetScript(f, name) return st[f].scripts[name] end
function impl.HasScript() return true end
function impl.HookScript(f, name, fn)
    local s = st[f]
    local old = s.scripts[name]
    s.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end

function impl.RegisterEvent(f, e) st[f].events[e] = true end
function impl.UnregisterEvent(f, e) st[f].events[e] = nil end
function impl.UnregisterAllEvents(f) st[f].events = {} end
function impl.IsEventRegistered(f, e) return st[f].events[e] == true end

function impl.Show(f) local s = st[f]; if not s.shown then s.shown = true; fire(f, "OnShow") end end
function impl.Hide(f) local s = st[f]; if s.shown then s.shown = false; fire(f, "OnHide") end end
function impl.IsShown(f) return st[f].shown end
function impl.IsVisible(f)
    local s = st[f]
    if not s.shown then return false end
    if s.parent and s.parent ~= f then return impl.IsVisible(s.parent) end
    return true
end
function impl.SetShown(f, v) if v then impl.Show(f) else impl.Hide(f) end end
function impl.GetParent(f) return st[f].parent end
function impl.GetName(f) return st[f].name end
function impl.GetObjectType(f) return st[f].kind end
function impl.IsObjectType(f, kind)
    local k = st[f].kind
    if k == kind then return true end
    if kind == "Button" then return k == "CheckButton" end
    if kind == "Frame" then return k ~= "Texture" and k ~= "FontString" and k ~= "MaskTexture" and k ~= "Font" end
    return false
end
function impl.GetID(f) return st[f].id end
function impl.SetID(f, v) st[f].id = v end

function impl.SetSize(f, w, h) st[f].w, st[f].h = w, h end
function impl.SetWidth(f, w) st[f].w = w end
function impl.SetHeight(f, h) st[f].h = h end
function impl.GetWidth(f) return st[f].w end
function impl.GetHeight(f) return st[f].h end
function impl.SetAlpha(f, a) st[f].alpha = a end
function impl.GetAlpha(f) return st[f].alpha end
function impl.SetScale(f, s) st[f].scale = s end
function impl.GetScale(f) return st[f].scale end
function impl.GetEffectiveScale(f) return st[f].scale end
function impl.SetFrameStrata(f, v) st[f].strata = v; st[f].strataSet = true end
function impl.GetFrameStrata(f) return st[f].strata end
function impl.SetFrameLevel(f, v) st[f].level = v; st[f].levelSet = true end
function impl.GetFrameLevel(f) return st[f].level end
function impl.GetCenter() return 683, 384 end
function impl.GetLeft() return 100 end
function impl.GetRight() return 200 end
function impl.GetTop() return 200 end
function impl.GetBottom() return 100 end
function impl.GetRect() return 100, 100, 100, 100 end
function impl.IsMouseOver() return false end
function impl.IsMovable() return true end

function impl.SetPoint(f, point, a, b, c, d)
    local rel, relPoint, x, y = a, b, c, d
    if type(a) == "number" then rel, relPoint, x, y = nil, point, a, b end
    if a == nil then x, y = 0, 0 end
    if type(a) ~= "number" and type(b) == "number" then relPoint, x, y = point, b, c end
    table.insert(st[f].points, { point, rel or st[f].parent, relPoint or point, x or 0, y or 0 })
end
function impl.ClearAllPoints(f) st[f].points = {} end
function impl.GetNumPoints(f) return #st[f].points end
function impl.GetPoint(f, i)
    local p = st[f].points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end

function impl.CreateTexture(f, name, layer, template, sublevel)
    local t = newObject("Texture", name, f)
    st[t].layer, st[t].sublevel = layer, sublevel or 0
    table.insert(st[f].regions, t)
    return t
end
function impl.CreateFontString(f, name, layer, template)
    local t = newObject("FontString", name, f)
    st[t].layer, st[t].fontObject = layer, template
    table.insert(st[f].regions, t)
    return t
end
function impl.CreateMaskTexture(f, name, layer)
    local t = newObject("MaskTexture", name, f)
    st[t].layer = layer
    return t
end
function impl.GetChildren(f) return unpack(st[f].frames) end
function impl.GetRegions(f) return unpack(st[f].regions) end
function impl.GetNumChildren(f) return #st[f].frames end

function impl.SetTexture(f, t) st[f].texture = t; st[f].color = nil end
function impl.GetTexture(f) return st[f].texture end
function impl.SetColorTexture(f, r, g, b, a) st[f].texture = "color"; st[f].color = { r or 1, g or 1, b or 1, a or 1 } end

-- style mémorisé (sert au rendu des « captures » de dev\render_preview.lua)
function impl.EnableMouse(f, v) st[f].mouse = v and true or false end
function impl.IsMouseEnabled(f) return st[f].mouse == true end
-- 4 valeurs (gauche, droite, haut, bas) ou 8 (coins haut-gauche, bas-gauche, haut-droite, bas-droite : rotation)
function impl.SetTexCoord(f, a, b, c, d, e, f2, g, h)
    if h ~= nil then
        st[f].texcoord8, st[f].texcoord = { a, b, c, d, e, f2, g, h }, nil
    elseif d ~= nil then
        st[f].texcoord, st[f].texcoord8 = { a, b, c, d }, nil
    end
end
function impl.SetVertexColor(f, r, g, b, a) st[f].vertex = { r or 1, g or 1, b or 1, a or 1 } end
function impl.SetDesaturated(f, v) st[f].desat = v and true or false end
function impl.SetBlendMode(f, m) st[f].blend = m end
function impl.SetDrawLayer(f, layer, sub) st[f].layer, st[f].sublevel = layer, sub or 0 end
function impl.SetFont(f, path, size, flags) st[f].fontSize, st[f].fontFlags = size, flags; return true end
function impl.SetFontObject(f, obj) st[f].fontObject = obj end
function impl.GetFontObject(f) return st[f].fontObject end
function impl.SetTextColor(f, r, g, b, a) st[f].textColor = { r or 1, g or 1, b or 1, a or 1 } end
function impl.SetJustifyH(f, j) st[f].justifyH = j end
function impl.SetJustifyV(f, j) st[f].justifyV = j end
function impl.SetShadowOffset(f, x, y) st[f].shadow = { x or 0, y or 0 } end
function impl.SetClipsChildren(f, v) st[f].clips = v and true or false end
function impl.SetAtlas(f, atlas) st[f].texture = "atlas:" .. tostring(atlas) end
function impl.GetAtlas(f)
    local t = st[f].texture
    if type(t) == "string" and t:sub(1, 6) == "atlas:" then return t:sub(7) end
end
function impl.SetAllPoints(f, rel)
    rel = rel or st[f].parent
    table.insert(st[f].points, { "TOPLEFT", rel, "TOPLEFT", 0, 0 })
    table.insert(st[f].points, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 })
end

function impl.SetText(f, t)
    local s = st[f]
    s.text = t == nil and "" or t
    if s.kind == "EditBox" then fire(f, "OnTextChanged", false) end
end
function impl.GetText(f) return st[f].text end
function impl.SetFormattedText(f, fmt, ...) st[f].text = string.format(fmt, ...) end
function impl.Insert(f, t) st[f].text = st[f].text .. t end
-- largeur approchée comme en jeu : sans les codes de couleur / lien / texture, en caractères UTF-8
function impl.GetStringWidth(f)
    local t = tostring(st[f].text or "")
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "WW")
    local n = 0
    for _ in t:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n * (st[f].fontSize or 12) * 0.55
end
function impl.SetWordWrap(f, v) st[f].wordWrap = v and true or false end
-- hauteur approchée comme en jeu : un texte à largeur fixe (SetWidth) passe à la ligne
function impl.GetStringHeight(f)
    local s = st[f]
    local size = s.fontSize or 12
    local lines = 1
    if s.wordWrap ~= false and (s.w or 0) > 0 then
        lines = math.max(1, math.ceil(impl.GetStringWidth(f) / s.w))
    end
    local _, breaks = tostring(s.text or ""):gsub("\n", "")
    return (lines + breaks) * size * 1.2
end
function impl.GetNumber(f) return tonumber(st[f].text) or 0 end
function impl.GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function impl.GetTextColor(f) local c = st[f].textColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function impl.SetFocus(f) st[f].focus = true end
function impl.ClearFocus(f) st[f].focus = false end
function impl.HasFocus(f) return st[f].focus end

function impl.Enable(f) st[f].enabled = true end
function impl.Disable(f) st[f].enabled = false end
function impl.SetEnabled(f, v) st[f].enabled = v and true or false end
function impl.IsEnabled(f) return st[f].enabled end
function impl.Click(f, button)
    if st[f].enabled then fire(f, "OnClick", button or "LeftButton", false) end
end
function impl.GetFontString(f)
    local s = st[f]
    if not s.fontString then s.fontString = newObject("FontString", nil, f) end
    return s.fontString
end
function impl.GetNormalTexture(f)
    local s = st[f]
    if not s.normalTexture then s.normalTexture = newObject("Texture", nil, f) end
    return s.normalTexture
end
function impl.GetHighlightTexture(f)
    local s = st[f]
    if not s.highlightTexture then s.highlightTexture = newObject("Texture", nil, f) end
    return s.highlightTexture
end
function impl.GetPushedTexture(f)
    local s = st[f]
    if not s.pushedTexture then s.pushedTexture = newObject("Texture", nil, f) end
    return s.pushedTexture
end
function impl.GetDisabledTexture(f)
    local s = st[f]
    if not s.disabledTexture then s.disabledTexture = newObject("Texture", nil, f) end
    return s.disabledTexture
end
function impl.GetThumbTexture(f)
    local s = st[f]
    if not s.thumb then s.thumb = newObject("Texture", nil, f) end
    return s.thumb
end
function impl.SetChecked(f, v) st[f].checked = v and true or false end
function impl.GetChecked(f) return st[f].checked end

function impl.SetMinMaxValues(f, a, b) st[f].min, st[f].max = a, b end
function impl.GetMinMaxValues(f) return st[f].min, st[f].max end
function impl.SetValueStep(f, v) st[f].step = v end
function impl.GetValueStep(f) return st[f].step end
function impl.SetValue(f, v)
    local s = st[f]
    v = math.max(s.min, math.min(s.max, v))
    if v ~= s.value then
        s.value = v
        fire(f, "OnValueChanged", v, false)
    end
end
function impl.GetValue(f) return st[f].value end

function impl.SetScrollChild(f, child) st[f].scrollChild = child end
function impl.GetScrollChild(f) return st[f].scrollChild end
function impl.SetVerticalScroll(f, v) st[f].vscroll = v end
function impl.GetVerticalScroll(f) return st[f].vscroll end
function impl.GetVerticalScrollRange(f)
    local child = st[f].scrollChild
    local ch = child and st[child].h or 0
    return math.max(0, ch - st[f].h)
end
function impl.GetHorizontalScroll() return 0 end

function impl.NumLines() return 0 end
function impl.GetOwner() return nil end
function impl.IsOwned() return false end

local function newFrame(kind, name, parent, template)
    local f = newObject(kind, name, parent)
    st[f].template = template
    st[f].attrs = {}
    if parent and st[parent] and kind ~= "Texture" and kind ~= "FontString" then
        table.insert(st[parent].frames, f)
    end
    if name then rawset(G, name, f) end
    return f
end

---------------------------------------------------------------------------
-- Globales WoW (mode strict : toute globale inconnue = erreur)
---------------------------------------------------------------------------
G.UIParent = newFrame("Frame", "UIParent", nil)
st[G.UIParent].w, st[G.UIParent].h = 1366, 768
G.Minimap = newFrame("Frame", "Minimap", G.UIParent)
st[G.Minimap].w, st[G.Minimap].h = 140, 140
G.GameTooltip = newFrame("GameTooltip", "GameTooltip", G.UIParent)
G.WorldFrame = newFrame("Frame", "WorldFrame", nil)

function G.CreateFrame(kind, name, parent, template)
    return newFrame(kind, name, parent or G.UIParent, template)
end

G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
-- vraies variables du jeu (chaînes localisées et constantes)
G.ALT_KEY_TEXT, G.CTRL_KEY_TEXT, G.SHIFT_KEY_TEXT, G.META_KEY_TEXT = "Alt", "Ctrl", "Maj", "Cmd"
G.STATICPOPUP_NUMDIALOGS = 4
function G.GetCursorPosition() return 683, 384 end
function G.HideUIPanel(f) if f then impl.Hide(f) end end
function G.ShowUIPanel(f) if f then impl.Show(f) end end
G.SettingsPanel = newFrame("Frame", "SettingsPanel", G.UIParent)
for name in ([[GameFontNormal GameFontNormalSmall GameFontNormalLarge GameFontNormalHuge GameFontHighlight
GameFontHighlightSmall GameFontHighlightLarge GameFontDisable GameFontDisableSmall GameFontWhite
ChatFontNormal SystemFont_Shadow_Small NumberFontNormal]]):gmatch("%S+") do
    rawset(G, name, newObject("Font", name, nil))
end
G.NUM_BAG_SLOTS = 4
-- espaces de noms présents par défaut : vides, les scénarios les remplacent selon leurs besoins
G.C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerNumFreeSlots = function() return 0, 0 end,
    GetContainerItemInfo = function() return nil end,
}
-- aucun autre addon chargé
G.C_AddOns = {
    IsAddOnLoaded = function() return false end,
    GetAddOnMetadata = function() return nil end,
}
G.SlashCmdList = {}
G.UISpecialFrames = {}
G.ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 },
    [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
}
G.Enum = {
    LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 },
    ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 },
    BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 },
    ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4, Unused1 = 5, Unused2 = 6,
        ToWoWAccount = 7, ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9 },
    ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Questitem = 12, Miscellaneous = 15 },
    ItemArmorSubclass = { Generic = 0, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Cosmetic = 5, Shield = 6 },
    GossipOptionStatus = { Available = 0, Unavailable = 1, Locked = 2, AlreadyComplete = 3 },
}

-- utilitaires Lua que WoW ajoute
G.tinsert, G.tremove = table.insert, table.remove
G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
G.strsplit = function(sep, s, n)
    local out, pos = {}, 1
    while true do
        local a, b = string.find(s, sep, pos, true)
        if not a or (n and #out >= n - 1) then out[#out + 1] = string.sub(s, pos) break end
        out[#out + 1] = string.sub(s, pos, a - 1)
        pos = b + 1
    end
    return unpack(out)
end
G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
G.format, G.strlower, G.strupper, G.strfind = string.format, string.lower, string.upper, string.find
G.floor, G.ceil, G.abs, G.max, G.min = math.floor, math.ceil, math.abs, math.max, math.min
G.Mixin = function(obj, ...)
    for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end
    return obj
end
G.CreateFromMixins = function(...) return G.Mixin({}, ...) end

function G.geterrorhandler() return function(e) recordError("geterrorhandler", e) end end
function G.hooksecurefunc() end
function G.GetTime() return M.time end
function G.GetServerTime() return 1700000000 end
function G.InCombatLockdown() return M.inCombat == true end
function G.IsLoggedIn() return M.loggedIn == true end
function G.IsShiftKeyDown() return M.shift == true end
function G.IsControlKeyDown() return M.ctrl == true end
function G.IsAltKeyDown() return M.alt == true end
M.clientLocale = "frFR"          -- langue du client simulée (les tests attendent le français ; Platyplus ne traduit pas en frFR)
function G.GetLocale() return M.clientLocale end

M.cvars = { autoLootDefault = "0", SoftTargetInteract = "0", SoftTargetInteractRange = "10", cameraDistanceMaxZoomFactor = "1.9" }
function G.GetCVar(name) return M.cvars[name] end
function G.SetCVar(name, value)
    if M.cvars[name] == nil then error("CVar inconnu : " .. tostring(name)) end
    M.cvars[name] = tostring(value)
    return true
end

M.money = 1000000
function G.GetMoney() return M.money end
function G.PlaySound() end
function G.GetCursorInfo() return M.cursor and M.cursor[1], M.cursor and M.cursor[2], M.cursor and M.cursor[3], M.cursor and M.cursor[4] end
function G.ClearCursor() M.cursor = nil end
function G.GetBindingAction(key, override)
    if override and M.overrides and M.overrides[key] then return M.overrides[key] end
    return M.bindings and M.bindings[key] or ""
end

-- bindings : comme dans le jeu, chaque liaison appartient à son « owner » ; ClearOverrideBindings(owner)
-- n'efface que les siennes. Interdit en combat (le jeu bloque l'action).
M.overrides = {}
M.overrideOwner = {}
local function bindingAllowed(fn)
    if M.inCombat then recordError(fn, "action bloquée en combat : " .. fn) return false end
    return true
end
function G.SetOverrideBinding(owner, priority, key, command)
    if not bindingAllowed("SetOverrideBinding") then return end
    M.overrides[key], M.overrideOwner[key] = command, owner
end
function G.SetOverrideBindingClick(owner, priority, key, button)
    if not bindingAllowed("SetOverrideBindingClick") then return end
    M.overrides[key], M.overrideOwner[key] = "CLICK " .. button .. ":LeftButton", owner
end
function G.ClearOverrideBindings(owner)
    if not bindingAllowed("ClearOverrideBindings") then return end
    for key, o in pairs(M.overrideOwner) do
        if o == owner then M.overrides[key], M.overrideOwner[key] = nil, nil end
    end
end

-- attributs des cadres ; ceux d'un cadre sécurisé (modèle Secure*) ne changent pas en combat
function impl.SetAttribute(f, name, value)
    local template = st[f].template
    if M.inCombat and type(template) == "string" and template:find("Secure", 1, true) then
        recordError("SetAttribute", "action bloquée en combat : SetAttribute(" .. tostring(name) .. ")")
        return
    end
    st[f].attrs[name] = value
end
function impl.GetAttribute(f, name) return st[f].attrs[name] end

-- timers
local function addTimer(delay, fn, repeating, iterations)
    local t = { due = M.time + delay, fn = fn, delay = delay, repeating = repeating, left = iterations, cancelled = false }
    function t.Cancel(self) self.cancelled = true end
    function t.IsCancelled(self) return self.cancelled end
    M.timers[#M.timers + 1] = t
    return t
end
G.C_Timer = {
    After = function(delay, fn) addTimer(delay, fn) end,
    NewTimer = function(delay, fn) return addTimer(delay, fn) end,
    NewTicker = function(delay, fn, n) return addTimer(delay, fn, true, n) end,
}

M.addTimer = addTimer

-- événements filtrés par unité : on les traite comme des événements simples
function impl.RegisterUnitEvent(f, e) st[f].events[e] = true end
function impl.GetStatusBarTexture(f)
    local s = st[f]
    if not s.barTexture then
        s.barTexture = newObject("Texture", nil, f)
        st[s.barTexture].isBarFill = true
        st[s.barTexture].layer = "ARTWORK"
    end
    return s.barTexture
end
function impl.SetStatusBarTexture(f, tex)
    local t = impl.GetStatusBarTexture(f)
    if type(tex) == "table" then return end
    st[t].texture = tex
end
function impl.SetStatusBarColor(f, r, g, b, a)
    local t = impl.GetStatusBarTexture(f)
    st[t].vertex = { r or 1, g or 1, b or 1, a or 1 }
end
function impl.IsDesaturated() return false end

-- groupes d'animation : Play() déclenche OnPlay puis OnFinished après la durée posée (ou tout de suite)
function impl.CreateAnimationGroup(f, name)
    return newObject("AnimationGroup", name, f)
end
function impl.CreateAnimation(g, kind, name)
    local a = newObject("Animation", name, g)
    return a
end
function impl.Play(g)
    local s = st[g]
    s.playing = true
    fire(g, "OnPlay")
    addTimer(s.duration or 0.01, function()
        if s.playing then
            s.playing = false
            fire(g, "OnFinished")
        end
    end)
end
function impl.Stop(g)
    local s = st[g]
    if s.playing then
        s.playing = false
        fire(g, "OnStop")
    end
end
function impl.Restart(g) impl.Stop(g); impl.Play(g) end
function impl.IsPlaying(g) return st[g].playing == true end
function impl.Finish(g) impl.Stop(g); fire(g, "OnFinished") end

-- avance le temps simulé par pas de 0,05 s : timers puis OnUpdate des frames visibles
function M.advance(seconds)
    local step = 0.05
    local n = math.floor(seconds / step + 0.5)
    for _ = 1, n do
        M.time = M.time + step
        local due = {}
        for _, t in ipairs(M.timers) do
            if not t.cancelled and t.due <= M.time + 1e-9 then due[#due + 1] = t end
        end
        table.sort(due, function(a, b) return a.due < b.due end)
        for _, t in ipairs(due) do
            if not t.cancelled then
                if t.repeating then
                    t.due = t.due + t.delay
                    if t.left then
                        t.left = t.left - 1
                        if t.left <= 0 then t.cancelled = true end
                    end
                else
                    t.cancelled = true
                end
                safe("timer", t.fn, t)
            end
        end
        for i = #M.timers, 1, -1 do if M.timers[i].cancelled then table.remove(M.timers, i) end end
        for _, f in ipairs(M.allFrames) do
            local s = st[f]
            if s.scripts.OnUpdate and impl.IsVisible(f) then
                safe("OnUpdate de " .. tostring(s.name or s.kind), s.scripts.OnUpdate, f, step)
            end
        end
    end
end

-- événements
function M.fireEvent(event, ...)
    local list = {}
    for _, f in ipairs(M.allFrames) do
        if st[f].events[event] and st[f].scripts.OnEvent then list[#list + 1] = f end
    end
    for _, f in ipairs(list) do
        safe("événement " .. event, st[f].scripts.OnEvent, f, event, ...)
    end
end

---------------------------------------------------------------------------
-- Mode strict pour les globales
---------------------------------------------------------------------------
-- globales qui peuvent légitimement valoir nil dans le jeu (frames Blizzard optionnelles, données sauvegardées...)
M.optional = {}
for name in ([[
PlatyplusDB MerchantFrame GossipFrame QuestFrame QuestFrameDetailPanel QuestFrameProgressPanel QuestFrameRewardPanel
QuestFrameGreetingPanel QuestFrameAcceptButton QuestFrameCompleteButton QuestFrameCompleteQuestButton
TalkingHeadFrame UIErrorsFrame MerchantFrameCloseButton PlatyplusAdvance PlatyplusConfig PlatyplusAnchor
]]):gmatch("%S+") do M.optional[name] = true end

M.optionalPatterns = { "^BINDING_NAME_", "^BINDING_HEADER_", "^KEY_", "^StaticPopup%d", "^Platyplus", "^MultiBar", "^ActionButton" }
for name in ([[PlayerFrame TargetFrame PowerBarColor ActionButtonUtil BankFrame GuildBankFrame AccountBankPanel BankPanel
ProfessionsFrame TradeSkillFrame CraftFrame MailFrame InboxFrame TradeFrame AuctionHouseFrame
QuestInfoFrame QuestInfoRewardsFrame QuestInfoItem_OnClick]]):gmatch("%S+") do M.optional[name] = true end
G.NUM_ACTIONBAR_BUTTONS = 12
G.BreakUpLargeNumbers = function(n)
    local s = tostring(math.floor(n))
    while true do
        local replaced
        s, replaced = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return s
end

function M.enableStrict()
    setmetatable(G, {
        __index = function(_, k)
            if M.optional[k] then return nil end
            -- recherches dynamiques _G["BINDING_NAME_"..x], _G["KEY_"..x], _G["StaticPopup"..i] : nil dans le jeu aussi
            if type(k) == "string" then
                for _, pattern in ipairs(M.optionalPatterns) do
                    if k:find(pattern) then return nil end
                end
            end
            error("globale inconnue (faute de frappe ou API absente du simulateur) : " .. tostring(k), 2)
        end,
        __newindex = function(t, k, v)
            M.newGlobals[#M.newGlobals + 1] = tostring(k)
            rawset(t, k, v)
        end,
    })
end

-- charge les fichiers d'un .toc dans l'ordre, comme le jeu : chaque fichier reçoit (nomAddon, ns)
function M.loadAddon(dir, addon, files)
    local ns = {}
    -- Locale.lua + dictionnaires toujours chargés d'abord (comme le .toc) : ns.T doit exister
    local all = { "Locale.lua", "Locales/enUS.lua", "Locales/deDE.lua", "Locales/esES.lua",
        "Locales/itIT.lua", "Locales/ptBR.lua", "Locales/ruRU.lua" }
    local seen = {}
    for _, f in ipairs(all) do seen[f] = true end
    for _, f in ipairs(files) do
        if not seen[f] then all[#all + 1] = f end
    end
    for _, file in ipairs(all) do
        local chunk, err = loadfile(dir .. "\\" .. file)
        if not chunk then
            recordError("chargement " .. file, err)
        else
            safe("chargement " .. file, chunk, addon, ns)
        end
    end
    return ns
end

function M.report()
    realPrint("--- erreurs : " .. #M.errors)
    for i, e in ipairs(M.errors) do realPrint(i .. ". " .. e) end
    if #M.newGlobals > 0 then realPrint("--- globales créées : " .. table.concat(M.newGlobals, ", ")) end
end

M.realPrint = realPrint
M.impl = impl
return M
