-- Probe.lua  (XpieUI-Forever, Quest module: Delivery 0)
-- A test build with no features: it checks, in game, the things the Quest
-- plan (docs/quest-plan.md) depends on. Every line it prints is also kept in
-- XpieUIForeverDB.probeLog, so it can be read from the saved variables after
-- a /reload.
--
--   /xui probe                 report: APIs, atlases, modes, Spoken, DialogueUI
--   /xui probe move            shared-position test on Blizzard's quest, gossip
--                              and book windows (drag the title bar), toggles
--   /xui probe camera [steps]  arm the speaker-zoom test for the next NPC;
--                              steps: any of zoom focus shoulder fov (default all)
--   /xui probe font            do QuestFont's children follow it live?
--   /xui probe spoken host     toggle Spoken:SetPlayerHost(hidden frame)
--   /xui probe spoken row      try Spoken:CreateDialogueUIRow on the open window
--   /xui probe addons          one-vs-all-characters test of Enable/DisableAddOn
--                              (DialogueUI, put back exactly as it was)
--   /xui probe clear           empty the saved log
--
-- Watched the whole time: ADDON_ACTION_FORBIDDEN / _BLOCKED, input-mode
-- transitions, and Blizzard's experimental-camera warning.

local core = XpieUI

local LOG_MAX = 400
local QUEST_WINDOWS = { "QuestFrame", "GossipFrame", "ItemTextFrame" }

-- ---------------------------------------------------------------------------
-- Log
-- ---------------------------------------------------------------------------
local function Log(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    core:Print("|cffffd200probe|r " .. text)
    if XpieUIForeverDB then
        local log = XpieUIForeverDB.probeLog
        if type(log) ~= "table" then log = {}; XpieUIForeverDB.probeLog = log end
        log[#log + 1] = date("%H:%M:%S ") .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        while #log > LOG_MAX do table.remove(log, 1) end
    end
end

local function YesNo(v) return v and "yes" or "no" end

local function DialogueUILoaded()
    return C_AddOns.IsAddOnLoaded("DialogueUI") and true or false
end

local function IsGamepadUI()
    if InputUtil and InputUtil.IsGamepadUIEnabled then
        local ok, on = pcall(InputUtil.IsGamepadUIEnabled)
        if ok then return on and true or false end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Watchers (always on while this build is installed)
-- ---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
        "INPUT_DEVICE_INTERFACE_TRANSITION", "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local who, what = ...
        Log("|cffff4040%s|r %s -> %s", event, tostring(who), tostring(what))
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        Log("input mode changed (%s); gamepad UI now: %s",
            table.concat({ tostringall(...) }, ", "), tostring(IsGamepadUI()))
    elseif event == "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED" then
        Log("|cffff8000experimental-camera warning fired|r (%s)", table.concat({ tostringall(...) }, ", "))
    end
end)

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
local ATLASES = {
    -- keyboard focus / badges / native highlight art the plan uses
    "gamepad-largecursor-white", "UI-Frame-Metal-CornerTopLeft",
    "Tooltip-NineSlice-CornerTopLeft", "Tooltip-NineSlice-Center",
    "QuestBG-Parchment", "QuestBG-Parchment-Accessibility4",
    "minimal-scrollbar-track-top", "common-dropdown-textholder",
    "coin-gold", "gamepad-xbox1-buttona-normal", "gamepad-ps-buttoncrox-normal",
}

local function Report()
    Log("---- report (XpieUI %s, client %s) ----", core.version, tostring((select(4, GetBuildInfo()))))
    Log("gamepad UI on: %s (InputUtil.IsGamepadUIEnabled %s)", tostring(IsGamepadUI()),
        YesNo(InputUtil and InputUtil.IsGamepadUIEnabled))
    Log("C_GamePad active device: %s", tostring(C_GamePad and C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID()))
    Log("DialogueUI loaded: %s%s", YesNo(DialogueUILoaded()),
        DialogueUILoaded() and " (move / camera tests need it off: they test Blizzard's own windows)" or "")
    for _, name in ipairs(QUEST_WINDOWS) do
        local f = _G[name]
        Log("%s: %s, protected %s, parent %s", name, f and "exists" or "MISSING",
            f and YesNo(f:IsProtected()) or "-", f and f:GetParent() and (f:GetParent():GetName() or "?") or "nil")
    end
    Log("Texture:ClearTextureSlice: %s", YesNo(UIParent:CreateTexture().ClearTextureSlice))
    Log("CameraZoomIn/Out: %s/%s, GetCameraZoom: %s (now %.2f)", YesNo(CameraZoomIn), YesNo(CameraZoomOut),
        YesNo(GetCameraZoom), GetCameraZoom and GetCameraZoom() or -1)
    for _, cvar in ipairs({ "cameraFov", "test_cameraOverShoulder", "test_cameraTargetFocusInteractEnable",
            "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement" }) do
        Log("cvar %s = %s", cvar, tostring(GetCVar(cvar)))
    end
    Log("UIParent listens for the experimental-camera warning: %s",
        YesNo(UIParent:IsEventRegistered("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")))
    local missing = {}
    for _, atlas in ipairs(ATLASES) do
        if not C_Texture.GetAtlasInfo(atlas) then missing[#missing + 1] = atlas end
    end
    Log("atlases: %d checked, missing: %s", #ATLASES, #missing > 0 and table.concat(missing, ", ") or "none")
    local file, size = QuestFont:GetFont()
    Log("QuestFont: %s %s; QuestTitleFont: %s %s", tostring(file), tostring(size), QuestTitleFont:GetFont())

    local S = _G.Spoken
    if S then
        local fields = {}
        for _, key in ipairs({ "GetCaption", "WordMarks", "SetPlayerHost", "CreateRoundButton",
                "CreateSpeakerFace", "CreateDialogueUIRow", "GetPlayerStyle", "TogglePause", "Skip",
                "Previous", "RegisterCallback", "IsGamepadUI", "GetCaptionOptions", "SplitCaption" }) do
            if type(S[key]) ~= "function" then fields[#fields + 1] = key end
        end
        local ok, compat = pcall(S.IsCompatible, S, 1)
        Log("Spoken %s: IsCompatible(1) %s, style %s, missing API: %s", tostring(S.ADDON_VERSION),
            tostring(ok and compat), tostring(S.GetPlayerStyle and S:GetPlayerStyle()),
            #fields > 0 and table.concat(fields, ", ") or "none")
    else
        Log("Spoken: not loaded")
    end
    Log("---- end ----")
end

-- ---------------------------------------------------------------------------
-- Move: one shared top-left point for the three windows
-- ---------------------------------------------------------------------------
local move = { on = false, hooked = {}, handles = {}, positioning = false }

local function ApplyPoint(frame)
    if not move.on or move.positioning or not move.point then return end
    move.positioning = true
    local ok, err = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", move.point[1], move.point[2])
    end)
    move.positioning = false
    if not ok then Log("|cffff4040SetPoint failed|r on %s: %s", frame:GetName(), tostring(err)) end
end

local function SavePoint(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    move.point = { math.floor(left * scale + 0.5), math.floor(top * scale + 0.5) }
    XpieUIForeverDB.probeMovePoint = move.point
end

local function HookWindow(frame)
    if move.hooked[frame] then return end
    move.hooked[frame] = true
    hooksecurefunc(frame, "SetPoint", function(self)
        if move.on and not move.positioning then ApplyPoint(self) end
    end)
    frame:HookScript("OnShow", function(self)
        if not move.on then return end
        Log("%s shown (combat %s, gamepad UI %s); moving it", self:GetName(),
            YesNo(InCombatLockdown()), tostring(IsGamepadUI()))
        ApplyPoint(self)
    end)
    local handle = CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", 60, 0)
    handle:SetPoint("TOPRIGHT", -28, 0)
    handle:SetHeight(22)
    handle:SetFrameLevel(frame:GetFrameLevel() + 10)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local tint = handle:CreateTexture(nil, "OVERLAY")
    tint:SetAllPoints()
    tint:SetColorTexture(1, 0.82, 0, 0.18)   -- visible during the probe only
    handle:SetScript("OnDragStart", function()
        frame:SetMovable(true)
        frame:StartMoving()
        Log("drag start on %s (gamepad UI %s)", frame:GetName(), tostring(IsGamepadUI()))
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
        SavePoint(frame)
        Log("drag stop: shared point %d, %d", move.point[1], move.point[2])
        ApplyPoint(frame)
    end)
    move.handles[frame] = handle
end

local function ToggleMove()
    if DialogueUILoaded() then
        Log("move test skipped: DialogueUI is loaded and owns the quest windows. Turn it off, /reload, try again.")
        return
    end
    move.on = not move.on
    if move.on then
        move.point = XpieUIForeverDB.probeMovePoint
        if not move.point then
            -- Start 200px right of where Blizzard puts the quest window.
            move.point = { 216, math.floor(UIParent:GetHeight() - 116) }
        end
        for _, name in ipairs(QUEST_WINDOWS) do
            local f = _G[name]
            if f then HookWindow(f); if f:IsShown() then ApplyPoint(f) end end
        end
        for _, h in pairs(move.handles) do h:Show() end
        Log("move ON at %d, %d. Open quests, gossip and a book with mouse and with the pad; drag the gold strip "
            .. "on a title bar (also try the soft cursor). Watch for red FORBIDDEN lines.", move.point[1], move.point[2])
    else
        for _, h in pairs(move.handles) do h:Hide() end
        Log("move OFF (windows go back to Blizzard's spot next time they open)")
    end
end

-- ---------------------------------------------------------------------------
-- Camera: DialogueUI's Zoom In at multiplier 4 (2.5x), FOV on
-- ---------------------------------------------------------------------------
local ZOOM_MULTIPLIER = 2.5
local FOV_ZOOMED = 75
local SHOULDER = 1.5
local EASE_TIME = 1.0
local FOCUS_CVARS = {
    test_cameraTargetFocusInteractEnable = 1,
    test_cameraTargetFocusInteractStrengthPitch = 0,
    test_cameraTargetFocusInteractStrengthYaw = 0,
    test_cameraHeadMovementStrength = 0,
    CameraKeepCharacterCentered = 0,
    CameraReduceUnexpectedMovement = 0,
}

local cam = { armed = false, steps = nil, active = false, backup = {} }
local camFrame = CreateFrame("Frame")
local scene, actor

local function ZoomForHeight(h)
    local z
    if h < 2 then z = 2 elseif h < 2.6 then z = 3 elseif h < 4 then z = 4
    elseif h < 5.1 then z = 5 elseif h < 6.1 then z = 6 elseif h < 8 then z = 10
    else z = h + 2; if z > 28.5 then return nil end end
    return z * ZOOM_MULTIPLIER
end

local function SetBackedUp(cvar, value)
    if cam.backup[cvar] == nil then cam.backup[cvar] = GetCVar(cvar) or false end
    local ok, err = pcall(SetCVar, cvar, value)
    if not ok then Log("|cffff4040SetCVar %s failed|r: %s", cvar, tostring(err)) end
end

local function ZoomTo(goal)
    local now = GetCameraZoom()
    local diff = now - goal
    if diff > 0.1 then CameraZoomIn(diff) elseif diff < -0.1 then CameraZoomOut(-diff) end
end

local function MeasureNPC(callback)
    if not scene then
        scene = CreateFrame("ModelScene")
        scene:SetSize(1, 1)
        actor = scene:CreateActor()
    end
    local ok = pcall(actor.SetModelByUnit, actor, "npc")
    if not ok then callback(nil, "SetModelByUnit failed"); return end
    local tries = 0
    local function Poll()
        tries = tries + 1
        local x1, y1, z1, x2, y2, z2 = actor:GetActiveBoundingBox()
        if z1 and z2 then
            actor:ClearModel()
            callback(z2 - z1)
        elseif tries < 20 then
            C_Timer.After(0.1, Poll)
        else
            actor:ClearModel()
            callback(nil, "no bounding box after 2s")
        end
    end
    C_Timer.After(0.05, Poll)
end

local function WindowOnRight()
    for _, name in ipairs(QUEST_WINDOWS) do
        local f = _G[name]
        if f and f:IsShown() and f:GetCenter() then
            return f:GetCenter() > UIParent:GetWidth() / 2
        end
    end
    return false
end

local function CameraStart()
    if cam.active then return end
    cam.active = true
    local s = cam.steps
    cam.oldZoom = GetCameraZoom()
    Log("camera start: zoom %.2f, gamepad UI %s, steps %s", cam.oldZoom, tostring(IsGamepadUI()),
        table.concat((function() local t = {} for k in pairs(s) do t[#t + 1] = k end return t end)(), " "))

    if s.focus then
        for cvar, value in pairs(FOCUS_CVARS) do SetBackedUp(cvar, value) end
    end
    if s.shoulder then
        local offset = WindowOnRight() and SHOULDER or -SHOULDER
        SetBackedUp("test_cameraOverShoulder", offset)
        Log("shoulder offset %.1f (window on the %s)", offset, WindowOnRight() and "right" or "left")
    end
    local fovStart = tonumber(GetCVar("cameraFov")) or 90
    if s.fov then cam.backup.cameraFov = cam.backup.cameraFov or GetCVar("cameraFov") or false end

    cam.t = 0
    camFrame:SetScript("OnUpdate", function(_, elapsed)
        cam.t = cam.t + elapsed
        local p = math.min(cam.t / EASE_TIME, 1)
        local ease = math.sin(p * math.pi / 2)
        if s.focus then
            pcall(SetCVar, "test_cameraTargetFocusInteractStrengthPitch", ease)
            ConsoleExec("pitchlimit " .. math.floor(88 - 73 * ease + 0.5))
        end
        if s.fov then pcall(SetCVar, "cameraFov", fovStart + (FOV_ZOOMED - fovStart) * ease) end
        if p >= 1 then
            camFrame:SetScript("OnUpdate", nil)
            Log("camera eased in: zoom %.2f, fov %s, pitch strength %s, shoulder %s", GetCameraZoom(),
                tostring(GetCVar("cameraFov")), tostring(GetCVar("test_cameraTargetFocusInteractStrengthPitch")),
                tostring(GetCVar("test_cameraOverShoulder")))
        end
    end)

    if s.zoom then
        MeasureNPC(function(height, err)
            if not cam.active then return end
            if not height then
                Log("NPC height: %s; using 2.6 (medium)", err or "?")
                height = 2.6
            end
            local goal = ZoomForHeight(height)
            Log("NPC height %.2f -> zoom goal %s (from %.2f)", height, tostring(goal), GetCameraZoom())
            if goal and goal < GetCameraZoom() then ZoomTo(goal) end
            C_Timer.After(1.2, function()
                if cam.active then Log("zoom after move: %.2f", GetCameraZoom()) end
            end)
        end)
    end
end

local function CameraRestore()
    if not cam.active then return end
    cam.active = false
    camFrame:SetScript("OnUpdate", nil)
    for cvar, value in pairs(cam.backup) do
        if value ~= false then pcall(SetCVar, cvar, value) end
    end
    wipe(cam.backup)
    if cam.steps.focus then ConsoleExec("pitchlimit 88") end
    if cam.steps.zoom and cam.oldZoom then ZoomTo(cam.oldZoom) end
    C_Timer.After(1.2, function()
        Log("camera restored: zoom %.2f (was %.2f), fov %s, shoulder %s, focus %s", GetCameraZoom(),
            cam.oldZoom or -1, tostring(GetCVar("cameraFov")), tostring(GetCVar("test_cameraOverShoulder")),
            tostring(GetCVar("test_cameraTargetFocusInteractEnable")))
    end)
    cam.armed = false
    Log("camera test done; /xui probe camera to arm again")
end

local function AnyWindowShown()
    for _, name in ipairs(QUEST_WINDOWS) do
        local f = _G[name]
        if f and f:IsShown() then return true end
    end
    return false
end

camFrame:RegisterEvent("GOSSIP_SHOW")
camFrame:RegisterEvent("QUEST_GREETING")
camFrame:RegisterEvent("QUEST_DETAIL")
camFrame:RegisterEvent("QUEST_PROGRESS")
camFrame:RegisterEvent("QUEST_COMPLETE")
camFrame:RegisterEvent("GOSSIP_CLOSED")
camFrame:RegisterEvent("QUEST_FINISHED")
camFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
camFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if cam.active then Log("combat: restoring camera now"); CameraRestore() end
    elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
        -- Gossip -> quest swaps close one window before opening the next.
        C_Timer.After(0.15, function()
            if cam.active and not AnyWindowShown() then CameraRestore() end
        end)
    elseif cam.armed and not cam.active then
        CameraStart()
    end
end)

local function ArmCamera(arg)
    if DialogueUILoaded() then
        Log("camera test skipped: DialogueUI is loaded and runs its own camera. Turn it off, /reload, try again.")
        return
    end
    local steps = {}
    for word in (arg or ""):gmatch("%a+") do
        if word == "zoom" or word == "focus" or word == "shoulder" or word == "fov" then steps[word] = true end
    end
    if not next(steps) then steps = { zoom = true, focus = true, shoulder = true, fov = true } end
    cam.steps, cam.armed = steps, true
    Log("camera armed: talk to an NPC (try with mouse and with the pad). Close the window to restore.")
end

-- ---------------------------------------------------------------------------
-- Font inheritance
-- ---------------------------------------------------------------------------
local function FontTest()
    local file, size, flags = QuestFont:GetFont()
    local _, leftBefore = QuestFontLeft:GetFont()
    QuestFont:SetFont(file, size + 4, flags)
    local _, leftAfter = QuestFontLeft:GetFont()
    QuestFont:SetFont(file, size, flags)
    local _, leftRestored = QuestFontLeft:GetFont()
    Log("QuestFont %s -> %s: QuestFontLeft %s -> %s (restored %s). Children follow live: %s",
        tostring(size), tostring(size + 4), tostring(leftBefore), tostring(leftAfter), tostring(leftRestored),
        YesNo(leftAfter and leftBefore and math.abs(leftAfter - leftBefore - 4) < 0.5))
end

-- ---------------------------------------------------------------------------
-- Spoken
-- ---------------------------------------------------------------------------
local hostFrame
local function SpokenTest(arg)
    local S = _G.Spoken
    if not S then Log("Spoken isn't loaded"); return end
    if arg == "host" then
        if not S.SetPlayerHost then Log("Spoken:SetPlayerHost missing"); return end
        if not hostFrame then
            hostFrame = CreateFrame("Frame", nil, UIParent)
            hostFrame:SetAllPoints()
            hostFrame:Hide()
        end
        hostFrame.on = not hostFrame.on
        local ok, err = pcall(S.SetPlayerHost, S, hostFrame.on and hostFrame or nil)
        Log("SetPlayerHost(%s): %s. Play a line: are Spoken's player and subtitles hidden?",
            hostFrame.on and "hidden frame" or "nil", ok and "ok" or tostring(err))
    elseif arg == "row" then
        local target
        for _, name in ipairs(QUEST_WINDOWS) do
            if _G[name] and _G[name]:IsShown() then target = _G[name] end
        end
        if not target then Log("open a quest, gossip or book window first"); return end
        if not S.CreateDialogueUIRow then Log("Spoken:CreateDialogueUIRow missing"); return end
        local ok, row = pcall(S.CreateDialogueUIRow, S, target, function() return GameTooltip end, true)
        Log("CreateDialogueUIRow(%s): %s", target:GetName(), ok and (type(row) == "table" and "row created" or tostring(row))
            or ("error: " .. tostring(row)))
        if ok and type(row) == "table" and row.frame then
            pcall(function()
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPRIGHT", target, "TOPRIGHT", -30, -26)
                row.frame:Show()
            end)
            Log("row placed at the window's top right; it stays until /reload")
        end
    else
        Log("use /xui probe spoken host  or  /xui probe spoken row")
    end
end

-- ---------------------------------------------------------------------------
-- AddOn enable scope (DialogueUI, always put back)
-- ---------------------------------------------------------------------------
local function AddonsTest()
    local name = "DialogueUI"
    local _, _, _, _, reason = C_AddOns.GetAddOnInfo(name)
    if reason == "MISSING" then Log("DialogueUI isn't installed"); return end
    local me = UnitName("player")
    local function State(char)
        local ok, state = pcall(C_AddOns.GetAddOnEnableState, name, char)
        return ok and state or ("error: " .. tostring(state))
    end
    local start = State(me)
    local startAll = State(nil)
    Log("DialogueUI enable state: this character %s, no-name query %s (0 off, 1 some, 2 all)",
        tostring(start), tostring(startAll))
    if start ~= 2 and start ~= 0 then
        Log("mixed state; skipping the change test so nothing is disturbed")
        return
    end
    local on = start == 2
    local flip, back = on and C_AddOns.DisableAddOn or C_AddOns.EnableAddOn, on and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn
    flip(name, me)
    Log("after %s(name, me): this character %s, no-name %s", on and "Disable" or "Enable", tostring(State(me)), tostring(State(nil)))
    back(name, me)
    flip(name)
    Log("after %s(name): this character %s, no-name %s", on and "Disable" or "Enable", tostring(State(me)), tostring(State(nil)))
    back(name)
    local final = State(me)
    if final == start and State(nil) == startAll then
        Log("put back as it was (%s). Nothing saved; no reload needed.", tostring(final))
    else
        Log("|cffff4040state differs from the start (%s vs %s)|r: check DialogueUI in the AddOns list", tostring(final), tostring(start))
    end
end

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------
core:RegisterCommand("probe", function(arg)
    local verb, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    verb = (verb or ""):lower()
    if verb == "" then Report()
    elseif verb == "move" then ToggleMove()
    elseif verb == "camera" then ArmCamera(rest)
    elseif verb == "font" then FontTest()
    elseif verb == "spoken" then SpokenTest(rest:lower())
    elseif verb == "addons" then AddonsTest()
    elseif verb == "clear" then XpieUIForeverDB.probeLog = {}; core:Print("probe log cleared")
    else Log("unknown: %s (report, move, camera, font, spoken host|row, addons, clear)", verb) end
end, "Quest module test build (report, move, camera, font, spoken, addons, clear)")
