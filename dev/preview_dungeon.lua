-- Monde simulé pour le journal des donjons intégré (DungeonJournal/) : guerrier humain de l'Alliance, et ce que le
-- journal demande au jeu en plus de ce que fait wowmock.lua (fonds BackdropTemplate dessinés comme par Blizzard,
-- quelques méthodes de cadre). Utilisé par test_dungeonjournal.lua et render_preview.lua.
-- À charger AVANT l'addon : dofile(DEV .. "\\preview_dungeon.lua")(M, def, { level = 24 })
return function(M, def, opts)
    opts = opts or {}
    local S = M.state
    local function noop() end

    -- méthodes de cadre que le journal appelle et que le simulateur n'a pas
    for _, name in ipairs({ "ClearModel", "SetCreature", "SetDisplayInfo", "SetGradientAlpha", "SetPortraitZoom",
        "SetCamDistanceScale", "SetPosition", "SetFacing", "SetModelScale", "SetKeepModelOnHide", "RefreshCamera",
        "SetUnit", "SetSecondsPerFrame", "SetHyperlinkFormat", "SetCountInvisibleLetters", "SetHistoryLines",
        "SetHorizontalScroll", "EnableKeyboard", "SetPropagateKeyboardInput", "SetDontSavePosition",
        "SetFrameBuffer", "SetIsFrameBuffer", "AddFontStrings", "SetMinimumWidth" }) do
        if not M.impl[name] then M.impl[name] = noop end
    end
    M.impl.GetDisplayInfo = function() return 0 end
    M.impl.GetTexCoord = function(t)
        local c = S(t).texcoord
        if c then return c[1], c[2], c[3], c[4] end
        return 0, 1, 0, 1
    end
    -- le simulateur ignore SetParent : les cadres déplacés d'un parent à l'autre doivent vraiment suivre
    M.impl.SetParent = function(f, parent) S(f).parent = parent end

    -- Fonds BackdropTemplate : comme BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua de Forever), qui
    -- repasse par SetBackdropColor / SetBackdropBorderColor de l'objet après chaque SetBackdrop. Dessinés (une
    -- texture de fond, quatre bords) seulement pour les cadres du journal : les autres captures ne changent pas.
    local function inJournal(f)
        local cur = f
        while cur do
            local n = S(cur).name
            if type(n) == "string" and n:find("^PlatyplusDungeon") then return true end
            cur = S(cur).parent
        end
        return opts.drawAll == true
    end
    M.impl.SetBackdrop = function(f, bd)
        local s = S(f)
        s.backdropInfo = bd
        if not bd then
            if s.bdBg then s.bdBg:Hide(); for _, e in ipairs(s.bdEdges) do e:Hide() end end
            return
        end
        if not s.bdBg and inJournal(f) then
            s.bdBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
            s.bdEdges = {}
            for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                                   { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
                local e = f:CreateTexture(nil, "BORDER", nil, 7)
                e:SetPoint(pts[1]); e:SetPoint(pts[2])
                s.bdEdges[i] = e
            end
        end
        if s.bdBg then
            local inset = bd.insets and bd.insets.left or 0
            s.bdBg:ClearAllPoints()
            s.bdBg:SetPoint("TOPLEFT", inset, -inset)
            s.bdBg:SetPoint("BOTTOMRIGHT", -inset, inset)
            s.bdBg:SetShown(bd.bgFile ~= nil)
            if bd.bgFile and not tostring(bd.bgFile):find("WHITE8X8") then s.bdBg:SetTexture(bd.bgFile)
            else s.bdBg:SetColorTexture(1, 1, 1, 1) end
            local thick = math.max(1, math.min(3, math.floor((bd.edgeSize or 12) / 5)))
            for i, e in ipairs(s.bdEdges) do
                e:SetShown(bd.edgeFile ~= nil)
                if i <= 2 then e:SetHeight(thick) else e:SetWidth(thick) end
            end
        end
        f:SetBackdropColor(1, 1, 1, 1)
        f:SetBackdropBorderColor(1, 1, 1, 1)
    end
    M.impl.SetBackdropColor = function(f, r, g, b, a)
        local s = S(f)
        s.backdropColor = { r, g, b, a or 1 }
        if s.bdBg then
            if s.bdBg and S(s.bdBg).texture == "color" then s.bdBg:SetColorTexture(r, g, b, a or 1)
            else s.bdBg:SetVertexColor(r, g, b, a or 1) end
        end
    end
    M.impl.SetBackdropBorderColor = function(f, r, g, b, a)
        local s = S(f)
        s.backdropBorderColor = { r, g, b, a or 1 }
        if s.bdEdges then for _, e in ipairs(s.bdEdges) do e:SetColorTexture(r, g, b, a or 1) end end
    end
    M.impl.GetBackdropColor = function(f) local c = S(f).backdropColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
    M.impl.GetBackdropBorderColor = function(f) local c = S(f).backdropBorderColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
    M.impl.GetBackdrop = function(f) return S(f).backdropInfo end
    -- la surbrillance d'un bouton : une vraie texture (le journal la règle après SetHighlightTexture)
    M.impl.SetHighlightTexture = function(f, file, blend)
        local s = S(f)
        if not s.hlTex then
            s.hlTex = f:CreateTexture(nil, "HIGHLIGHT")
            s.hlTex:SetAllPoints(f)
        end
        if file then s.hlTex:SetTexture(file) end
        if blend then s.hlTex:SetBlendMode(blend) end
    end
    local getHighlight = M.impl.GetHighlightTexture
    M.impl.GetHighlightTexture = function(f) return S(f).hlTex or getHighlight(f) end

    -- un personnage qui a déjà choisi le mode du journal (sinon il le demande 3 s après la connexion)
    if rawget(_G, "PlatyplusDungeonCharacterDB") == nil then def("PlatyplusDungeonCharacterDB", { journalMode = "gamer" }) end
    def("BackdropTemplateMixin", rawget(_G, "BackdropTemplateMixin") or {})
    def("GetLocale", function() return "frFR" end)
    def("UnitFactionGroup", function() return "Alliance", "Alliance" end)
    def("UnitLevel", function() return opts.level or 24 end)
    def("UnitRace", function() return "Humain", "Human", 1 end)
    def("UnitClass", function() return "Guerrier", "WARRIOR", 1 end)
    def("UnitGUID", function() return "Player-1-0001" end)
    def("GetRealmName", function() return "Forever" end)
    def("IsInInstance", function() return false, "none" end)
    def("GetInstanceInfo", function() return "Forêt d'Elwynn", "none", 0, "", 5, 0, false, 0 end)
    def("GetRealZoneText", function() return "Forêt d'Elwynn" end)
    def("GetSubZoneText", function() return "" end)
    def("GetNumGroupMembers", function() return 0 end)
    def("GetNumSkillLines", function() return 0 end)
    -- quêtes : celles de opts.done sont rendues
    local done = opts.done or {}
    def("C_QuestLog", {
        IsQuestFlaggedCompleted = function(id) return done[id] == true end,
        GetLogIndexForQuestID = function() return nil end,
        GetQuestObjectives = function() return {} end,
        RequestLoadQuestByID = function() end,
        GetTitleForQuestID = function() return nil end,
    })
    def("IsQuestFlaggedCompleted", function(id) return done[id] == true end)
    def("GetQuestLogIndexByID", function() return 0 end)
end
