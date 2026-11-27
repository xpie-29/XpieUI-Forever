-- Camera.lua  (XpieUI-Forever, Quest module)
-- Speaker Camera: while a quest or gossip window is open, the camera turns to
-- the speaker, moves them to the side away from the window and zooms in a
-- little. One fixed behaviour for keyboard & mouse and the controller alike
-- (the controller UI's own camera values are lifted while it runs).
--
--   Speaker (an NPC)       measure its model, zoom in (never out) by its
--                          height, Blizzard's interact-focus camera (pitch),
--                          shoulder offset, field of view 75
--   No speaker (objects,   shoulder offset that follows the zoom, zoom in
--   boards, items)         to 3 (never out)
--   Books                  no camera
--
-- Every change moves together on one clock (ease in and out over a second):
-- turn, side offset, field of view and zoom. The zoom is driven in small
-- steps along the same curve rather than handed to the game in one jump.
-- Closing the window eases everything back the same way (gossip -> quest
-- counts as one conversation); combat and logout put it back at once. Stands
-- down while a camera addon is loaded (CAMERA_ADDONS in Quest.lua).
--
-- Crash recovery: every clean logout saves the player's own values of the
-- settings the camera changes (the baseline). Saved variables only reach
-- disk at logout, so a crash mid-conversation leaves the baseline from the
-- last clean logout. At the next load, a setting that differs from it and
-- holds a value the camera sets is put back. This runs whether or not the
-- plugin is on.
--
-- Blizzard's experimental-camera warning (the test_camera* settings) is
-- switched off with GameEvent.UnregisterInternalEvent, which removes
-- Blizzard's own handler for it. That only happens when the camera is about
-- to be used, or a crash leftover is being put back; the camera never
-- touches a test_camera* setting unless it worked.

local addonName = ...
local core = XpieUI
local plugin = core.questPlugin

local WINDOWS = { "QuestFrame", "GossipFrame" }
local RESTORE_DELAY = 0.15       -- gossip -> quest: one window closes before the next opens
local EASE_TIME = 1.0
local MIN_ZOOM_TIME = 0.6        -- a zoom that starts late (model still loading) still eases
local ZOOM_MULTIPLIER = 2.5      -- camera distance per step of the height table
local FALLBACK_HEIGHT = 3        -- NPC couldn't be measured
local FOV_ZOOMED = 75
local SHOULDER_DEFAULT = 1.5
local MOUNTED_MULTIPLIER = 4.8   -- mounts: keep the speaker clear of the window (window on the right)
local STRENGTH = "test_cameraTargetFocusInteractStrengthPitch"
local SHOULDER = "test_cameraOverShoulder"
local FOCUS_CVARS = {
    test_cameraTargetFocusInteractEnable = 1,
    [STRENGTH] = 0,               -- eased to 1
    test_cameraTargetFocusInteractStrengthYaw = 0,
    test_cameraHeadMovementStrength = 0,
    CameraKeepCharacterCentered = 0,
    CameraReduceUnexpectedMovement = 0,
}
-- The controller UI lays temporary values over these (Blizzard_Gamepad), so
-- the camera follows and re-centres differently there. They're lifted for
-- the conversation, so it moves the same way with either input, and laid
-- back on afterwards.
local CONTROLLER_CVARS = {
    "CameraFollowYawSpeed", "CameraFollowPitchSpeed", "CameraFollowPitchStrength",
    "CameraFollowPitchDeadZone", "CameraReduceUnexpectedMovement", "CameraKeepCharacterCentered",
}
-- Druid forms: shoulder offset per form.
local FORM_OFFSET = { [1] = 1.0, [2] = 1.0, [3] = 1.1, [4] = 0.9, [5] = 0.9, [27] = 0.55, [29] = 0.55, [31] = 1.0 }

local GetCVar, SetCVar = C_CVar.GetCVar, C_CVar.SetCVar

local cam = {
    phase = nil,         -- "in" (easing in), "on", "out" (easing back), nil
    mode = nil,          -- "focus" (a speaker) or "pan" (no speaker)
    t = 0,               -- the phase's clock
    from = nil, to = nil,-- focus: { strength, shoulder, fov } at the ends of the ease
    zoom = nil,          -- zoom ease: { from, to, t, d, at }
    backup = nil,        -- [cvar] = value before we changed it
    lifted = nil,        -- [cvar] = the controller UI's temporary value we lifted
    oldZoom = nil,
    onRight = false,     -- window on the right half of the screen
    multiplier = 1,      -- shoulder side and mount scaling
    shoulder = SHOULDER_DEFAULT,
    panScale = 1,
    shoulderNow = 0,
    measureId = 0,
    measuring = false,
}
local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")
local inCombat = false
local restoreToken = 0
local blocked = false
local scene, actor

-- Slow at both ends, so nothing starts or stops with a jolt.
local function Ease(from, to, p)
    return from - (to - from) / 2 * (math.cos(math.pi * p) - 1)
end

local function Set(cvar, value)
    pcall(SetCVar, cvar, value)
end

local function Num(cvar, default)
    return tonumber(GetCVar(cvar)) or default
end

local function ControllerUI()
    if InputUtil and InputUtil.IsGamepadUIEnabled then
        local ok, on = pcall(InputUtil.IsGamepadUIEnabled)
        return ok and on
    end
    return false
end


-- ---------------------------------------------------------------------------
-- Blizzard's experimental-camera warning
-- ---------------------------------------------------------------------------
local function BlockWarning()
    if blocked then return end
    if GameEvent and GameEvent.UnregisterInternalEvent then
        blocked = true
        GameEvent.UnregisterInternalEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
    end
end

-- ---------------------------------------------------------------------------
-- Settings we change, backed up first
-- ---------------------------------------------------------------------------
-- pitchlimit is a console command. If the client also reads it as a setting,
-- the player's value is kept; otherwise Blizzard's default (88) is used.
local PITCH = "pitchlimit"
local PITCH_DEFAULT = 88

local function ReadPitchLimit()
    local ok, value = pcall(GetCVar, PITCH)
    return ok and tonumber(value) or PITCH_DEFAULT
end

local function SetPitchLimit(value)
    ConsoleExec(PITCH .. " " .. math.floor(value + 0.5))
end

local function Backup(cvar)
    if cam.backup[cvar] == nil then cam.backup[cvar] = GetCVar(cvar) end
end

local function BackupAndSet(cvar, value)
    Backup(cvar)
    if value ~= nil then Set(cvar, value) end
end

local function RestoreCVars(backup)
    for cvar, value in pairs(backup) do
        if cvar ~= PITCH then Set(cvar, value) end
    end
    SetPitchLimit(tonumber(backup[PITCH]) or PITCH_DEFAULT)
end

-- ---------------------------------------------------------------------------
-- Crash recovery (see the top of the file)
-- ---------------------------------------------------------------------------
-- [cvar] = the value the camera sets, or true for one it eases (any value).
local CAMERA_VALUES = {
    test_cameraTargetFocusInteractEnable = "1",
    [STRENGTH] = true,
    test_cameraTargetFocusInteractStrengthYaw = "0",
    test_cameraHeadMovementStrength = "0",
    CameraKeepCharacterCentered = "0",
    CameraReduceUnexpectedMovement = "0",
    [SHOULDER] = true,
    cameraFov = tostring(FOV_ZOOMED),
}
-- The controller UI lays temporary values over these, so at logout under it
-- the value read isn't the player's saved one: left out of the baseline.
local CONTROLLER_SET = {}
for _, cvar in ipairs(CONTROLLER_CVARS) do CONTROLLER_SET[cvar] = true end

local function SameValue(a, b)
    local x, y = tonumber(a), tonumber(b)
    if x and y then return math.abs(x - y) < 0.001 end
    return a == b
end

local function QuestDB()
    local all = XpieUIForeverDB and XpieUIForeverDB.plugins
    local db = type(all) == "table" and all.quest
    return type(db) == "table" and db or nil
end

local function RecoverFromCrash()
    local db = QuestDB()
    db = db and db.cameraBaseline
    if type(db) ~= "table" or plugin:CameraAddonPresent() then return end
    for cvar, ours in pairs(CAMERA_VALUES) do
        local saved, now = db[cvar], GetCVar(cvar)
        if saved ~= nil and now ~= nil and not SameValue(now, saved)
            and (ours == true or SameValue(now, ours)) then
            if cvar:find("^test_camera") then BlockWarning() end
            Set(cvar, saved)
        end
    end
end

local function SaveBaseline()
    local db = QuestDB()
    if not db then return end
    db.cameraBackup = nil   -- older builds' key
    if plugin:CameraAddonPresent() then db.cameraBaseline = nil; return end
    local baseline = {}
    local controller = ControllerUI()
    for cvar in pairs(CAMERA_VALUES) do
        if not (controller and CONTROLLER_SET[cvar]) then baseline[cvar] = GetCVar(cvar) end
    end
    db.cameraBaseline = baseline
end

-- Before any backup, so the backup holds the saved (keyboard) values and
-- never writes the controller's temporary ones into the saved settings.
local function LiftControllerCVars()
    if cam.lifted or not ControllerUI() or not C_CVar.RemoveTempCVar then return end
    cam.lifted = {}
    for _, cvar in ipairs(CONTROLLER_CVARS) do
        cam.lifted[cvar] = GetCVar(cvar)
        pcall(C_CVar.RemoveTempCVar, cvar)
    end
end

local function RelayControllerCVars()
    local lifted = cam.lifted
    cam.lifted = nil
    if not lifted or not ControllerUI() then return end   -- switched to keyboard meanwhile
    for cvar, value in pairs(lifted) do pcall(C_CVar.SetTempCVar, cvar, value) end
end

-- ---------------------------------------------------------------------------
-- Where things are
-- ---------------------------------------------------------------------------
local function ShownWindow()
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame and frame:IsShown() then return frame end
    end
end

local function WindowOnRight()
    local frame = ShownWindow()
    local x = frame and frame:GetCenter()
    if not x then return false end
    return x * frame:GetEffectiveScale() > UIParent:GetCenter() * UIParent:GetEffectiveScale()
end

local function IsDynamicFlying()
    if IsMounted() then return true end
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local isGliding, canGlide = C_PlayerInfo.GetGlidingInfo()
        if isGliding or canGlide then return true end
    end
    return false
end

-- A real speaker, not the player (quests from items) or nothing (objects).
local function HasSpeaker()
    if not UnitExists("npc") then return false end
    local same = UnitIsUnit("npc", "player")
    if canaccessvalue and not canaccessvalue(same) then return false end
    return not same
end

local function UpdateMultiplier()
    local mounted = IsMounted()
    if cam.onRight then
        cam.multiplier = mounted and MOUNTED_MULTIPLIER or 1
    else
        cam.multiplier = mounted and -0.3 or -1
    end
end

local function UpdateForm()
    local offset
    if select(3, UnitClass("player")) == 11 and GetShapeshiftFormID then
        offset = FORM_OFFSET[GetShapeshiftFormID() or 0]
    end
    cam.shoulder = offset or SHOULDER_DEFAULT
    cam.panScale = cam.shoulder / SHOULDER_DEFAULT
end

local function PanOffset()
    return (GetCameraZoom() * 0.4314 + 0.1057) * cam.panScale
end

-- Only written when it moves: each write fires CVAR_UPDATE for every listener.
local function SetShoulder(value)
    if cam.shoulderSent and math.abs(value - cam.shoulderSent) < 0.001 then
        cam.shoulderNow = value
        return
    end
    cam.shoulderNow, cam.shoulderSent = value, value
    Set(SHOULDER, value)
end

-- ---------------------------------------------------------------------------
-- Zoom: eased in small steps, so it moves with everything else
-- ---------------------------------------------------------------------------
-- Where the camera is heading (mid-ease, the game is still catching up).
local function ZoomTarget()
    return cam.zoom and cam.zoom.at or GetCameraZoom()
end

local function ZoomBy(delta)
    if delta > 0 then CameraZoomOut(delta) elseif delta < 0 then CameraZoomIn(-delta) end
end

local function EaseZoomTo(goal, duration)
    local from = ZoomTarget()
    if math.abs(from - goal) < 0.1 then cam.zoom = nil; return end
    cam.zoom = { from = from, to = goal, t = 0, d = duration, at = from }
end

-- true once there's no zoom left to do
local function StepZoom(elapsed)
    local z = cam.zoom
    if not z then return true end
    z.t = z.t + elapsed
    local p = math.min(z.t / z.d, 1)
    local want = Ease(z.from, z.to, p)
    ZoomBy(want - z.at)
    z.at = want
    if p >= 1 then cam.zoom = nil; return true end
    return false
end

local function ZoomForHeight(h)
    local z
    if h < 2 then z = 2
    elseif h < 2.6 then z = 3       -- Pandaren, elves
    elseif h < 4 then z = 4
    elseif h < 5.1 then z = 5
    elseif h < 6.1 then z = 6
    elseif h < 8 then z = 10
    else
        z = h + 2
        if z > 28.5 then return nil end   -- dragons and the like: leave the zoom
    end
    return z * ZOOM_MULTIPLIER
end

-- The speaker's height from its model's bounding box (a hidden ModelScene).
local function MeasureSpeaker(callback)
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret and C_Secrets.ShouldUnitIdentityBeSecret("npc") then
        callback(nil); return
    end
    if not scene then
        scene = CreateFrame("ModelScene")
        scene:SetSize(1, 1)
        actor = scene:CreateActor()
    end
    if not (actor and pcall(actor.SetModelByUnit, actor, "npc")) then callback(nil); return end
    local tries = 0
    local function Poll()
        tries = tries + 1
        local _, _, z1, _, _, z2 = actor:GetActiveBoundingBox()
        if z1 and z2 then
            actor:ClearModel()
            callback(z2 - z1)
        elseif tries < 20 then
            C_Timer.After(0.05, Poll)
        else
            actor:ClearModel()
            callback(nil)
        end
    end
    Poll()
end

-- ---------------------------------------------------------------------------
-- The clock: one update moves everything
-- ---------------------------------------------------------------------------
local Tick

local function StartDriver()
    driver:SetScript("OnUpdate", Tick)
end

local function Finish()
    driver:SetScript("OnUpdate", nil)
    events:UnregisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    pcall(events.UnregisterEvent, events, "PLAYER_IS_GLIDING_CHANGED")
    events:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
    if cam.backup then RestoreCVars(cam.backup) end
    cam.backup = nil
    RelayControllerCVars()
    cam.phase, cam.mode, cam.zoom, cam.oldZoom = nil, nil, nil, nil
    cam.shoulderSent = nil
    cam.measuring = false
end

function Tick(_, elapsed)
    cam.t = cam.t + elapsed
    local p = math.min(cam.t / EASE_TIME, 1)
    local phase = cam.phase

    if cam.mode == "focus" then
        if phase ~= "on" then
            local from, to = cam.from, cam.to
            Set(STRENGTH, Ease(from.strength, to.strength, p))
            SetShoulder(Ease(from.shoulder, to.shoulder, p))
            if from.fov and to.fov then Set("cameraFov", Ease(from.fov, to.fov, p)) end
            if phase == "in" then
                -- A lowered pitch limit tips the camera level; let go of it at the end.
                local base = tonumber(cam.backup[PITCH]) or PITCH_DEFAULT
                SetPitchLimit(p < 1 and Ease(base, 15, p) or base)
            end
        end
    elseif phase == "out" then
        SetShoulder(Ease(cam.from.shoulder, cam.to.shoulder, p))
    else
        -- No speaker: the offset follows the zoom.
        local goal = cam.multiplier * PanOffset()
        SetShoulder(cam.shoulderNow + (goal - cam.shoulderNow) * math.min(cam.blend * elapsed * 60, 1))
    end

    local zoomDone = StepZoom(elapsed)

    if p >= 1 then
        if phase == "in" then
            cam.phase = "on"
        elseif phase == "out" and zoomDone then
            Finish()
            return
        end
    end
    -- Settled: nothing left to move until something changes.
    if cam.phase == "on" and cam.mode == "focus" and zoomDone and not cam.measuring then
        driver:SetScript("OnUpdate", nil)
    end
end

-- ---------------------------------------------------------------------------
-- Start / restore
-- ---------------------------------------------------------------------------
local function Start()
    if cam.phase == "in" or cam.phase == "on" then return end
    BlockWarning()
    -- Opened again while easing back: carry on from here, same backup.
    local resuming = cam.phase == "out"
    if not resuming then
        LiftControllerCVars()
        cam.backup = { [PITCH] = ReadPitchLimit() }
        cam.oldZoom = GetCameraZoom()
    end
    local zoomNow = ZoomTarget()
    cam.zoom = nil
    cam.phase, cam.t = "in", 0
    cam.onRight = WindowOnRight()
    UpdateMultiplier()
    UpdateForm()
    events:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    pcall(events.RegisterEvent, events, "PLAYER_IS_GLIDING_CHANGED")
    events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

    if HasSpeaker() then
        cam.mode = "focus"
        for cvar, value in pairs(FOCUS_CVARS) do
            if cvar == STRENGTH then Backup(cvar) else BackupAndSet(cvar, value) end
        end
        Backup(SHOULDER)
        cam.from = { strength = Num(STRENGTH, 0), shoulder = Num(SHOULDER, 0) }
        cam.to = { strength = 1, shoulder = cam.multiplier * cam.shoulder }
        if not IsDynamicFlying() then
            -- Not while mounted or gliding: skyriding's speed effect changes it too.
            Backup("cameraFov")
            cam.from.fov, cam.to.fov = Num("cameraFov", 90), FOV_ZOOMED
        end
        cam.measuring = true
        cam.measureId = cam.measureId + 1
        local id = cam.measureId
        MeasureSpeaker(function(height)
            if id ~= cam.measureId or cam.mode ~= "focus" or not (cam.phase == "in" or cam.phase == "on") then return end
            cam.measuring = false
            local goal = ZoomForHeight(height or FALLBACK_HEIGHT)
            if goal and goal < zoomNow then
                EaseZoomTo(goal, math.max(EASE_TIME - cam.t, MIN_ZOOM_TIME))
            end
            StartDriver()
        end)
    else
        cam.mode = "pan"
        cam.measuring = false
        -- Back from a speaker mid-ease: everything the speaker camera set goes
        -- straight back (the pan sets its own below).
        for cvar in pairs(FOCUS_CVARS) do
            if cam.backup[cvar] ~= nil then Set(cvar, cam.backup[cvar]) end
        end
        if cam.backup.cameraFov ~= nil then Set("cameraFov", cam.backup.cameraFov) end
        if resuming then SetPitchLimit(tonumber(cam.backup[PITCH]) or PITCH_DEFAULT) end
        BackupAndSet(SHOULDER)
        BackupAndSet("CameraKeepCharacterCentered", 0)
        BackupAndSet("CameraReduceUnexpectedMovement", 0)
        cam.shoulderNow = Num(SHOULDER, 0)
        cam.blend = (cam.multiplier * PanOffset() - cam.shoulderNow > 8) and 0.06 or 0.10
        if zoomNow > 3 then EaseZoomTo(3, EASE_TIME) end
    end
    StartDriver()
end

-- instant: combat, logout, or the camera turned off.
local function Restore(instant)
    if not cam.phase then return end
    if instant then
        local goal = cam.oldZoom
        local now = ZoomTarget()
        Finish()
        if goal then ZoomBy(goal - now) end
        return
    end
    if cam.phase == "out" then return end
    if cam.phase == "in" then SetPitchLimit(tonumber(cam.backup[PITCH]) or PITCH_DEFAULT) end
    cam.phase, cam.t = "out", 0
    cam.measuring = false
    cam.measureId = cam.measureId + 1   -- a late measurement is ignored
    local backup = cam.backup
    cam.from = { strength = Num(STRENGTH, 0), shoulder = Num(SHOULDER, 0) }
    cam.to = { strength = tonumber(backup[STRENGTH]) or 0, shoulder = tonumber(backup[SHOULDER]) or 0 }
    if backup.cameraFov ~= nil then
        cam.from.fov, cam.to.fov = Num("cameraFov", 90), tonumber(backup.cameraFov)
    end
    if cam.oldZoom then EaseZoomTo(cam.oldZoom, EASE_TIME) end
    StartDriver()
end

local function CameraOn()
    return plugin:IsLive() and plugin.db.camera and blocked and not plugin:CameraAddonPresent()
end

local function Update()
    local fighting = inCombat or InCombatLockdown()
    local want = CameraOn() and ShownWindow() and not fighting
    if want then
        Start()
    elseif cam.phase then
        Restore(fighting or not CameraOn())
    end
end
plugin.UpdateCamera = Update

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function OnWindowShow()
    restoreToken = restoreToken + 1
    -- Next frame: after Blizzard's panel manager and our shared position.
    C_Timer.After(0, Update)
end

local function OnWindowHide()
    restoreToken = restoreToken + 1
    local token = restoreToken
    C_Timer.After(RESTORE_DELAY, function()
        if token == restoreToken then Update() end
    end)
end

-- Mounted, shapeshifted, started gliding: the side offset (and field of
-- view) follow.
local function OnPlayerChanged()
    if not (cam.phase == "in" or cam.phase == "on") then return end
    UpdateMultiplier()
    UpdateForm()
    if cam.mode ~= "focus" then return end   -- the pan follows on its own
    cam.to.shoulder = cam.multiplier * cam.shoulder
    if cam.phase == "on" then SetShoulder(cam.to.shoulder) end
    if cam.to.fov and IsDynamicFlying() and cam.backup.cameraFov ~= nil then
        cam.from.fov, cam.to.fov = nil, nil   -- the ease stops changing it
        Set("cameraFov", cam.backup.cameraFov)
    end
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- InCombatLockdown() can still be false during REGEN_DISABLED.
        inCombat = event == "PLAYER_REGEN_DISABLED"
        Update()
    elseif event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then
        Restore(true)
    else
        OnPlayerChanged()
    end
end)

-- Load and logout run whether or not the plugin is on: crash recovery, and
-- the baseline saved at every clean logout (after putting the camera back).
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGOUT" then
        Restore(true)
        SaveBaseline()
    elseif name == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        RecoverFromCrash()
    end
end)

local function CameraWanted()
    return plugin.db.camera and plugin:IsLive() and not plugin:CameraAddonPresent()
end

-- Turned on in the settings: block the warning before the first use.
function plugin:CameraSettingChanged()
    if CameraWanted() then BlockWarning() end
end

function plugin:InitCamera()
    if self.cameraReady or not self:IsLive() then return end
    self.cameraReady = true
    if CameraWanted() then BlockWarning() end
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame then
            frame:HookScript("OnShow", OnWindowShow)
            frame:HookScript("OnHide", OnWindowHide)
        end
    end
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
            "PLAYER_CAMPING", "PLAYER_QUITING" }) do
        pcall(events.RegisterEvent, events, event)
    end
    Update()
end
