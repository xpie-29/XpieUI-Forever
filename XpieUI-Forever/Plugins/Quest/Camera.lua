-- Camera.lua  (XpieUI-Forever, Quest module)
-- Speaker Camera: while a quest or gossip window is open, the camera turns to
-- the speaker, moves them to the side away from the window and zooms in a
-- little. One fixed behaviour, DialogueUI's "Zoom In" with Zoom Multiplier 4
-- and Change FOV, for keyboard & mouse and the controller alike.
--
--   Speaker (an NPC)       measure its model, zoom in (never out) by its
--                          height, ease in Blizzard's interact-focus camera
--                          (pitch), shoulder offset, field of view 75
--   No speaker (objects,   shoulder offset that follows the zoom, zoom in
--   boards, items)         to 3 (never out)
--   Books                  no camera (as DialogueUI)
--
-- Everything is put back when the window closes (gossip -> quest counts as
-- one conversation), at once if combat starts, and on logout. The values it
-- changes are also kept in the saved variables until restored, so a crash
-- mid-conversation is put right at the next login. Stands down while
-- DynamicCam is loaded.
--
-- Blizzard's experimental-camera warning (the test_camera* settings) is
-- switched off the way DialogueUI does it on Forever:
-- GameEvent.UnregisterInternalEvent removes Blizzard's own handler for it.
-- That runs as soon as our saved settings load; the camera never touches a
-- test_camera* setting unless it worked.
-- Ported from DialogueUI Code/Camera.lua and API.lua (EvaluateNPCSize).

local addonName = ...
local core = XpieUI
local plugin = core.questPlugin

local WINDOWS = { "QuestFrame", "GossipFrame" }
local RESTORE_DELAY = 0.15       -- gossip -> quest: one window closes before the next opens
local EASE_TIME = 1.0
local ZOOM_MULTIPLIER = 2.5      -- DialogueUI's Zoom Multiplier 4
local FALLBACK_HEIGHT = 3        -- NPC couldn't be measured
local FOV_ZOOMED = 75
local SHOULDER_DEFAULT = 1.5
local MOUNTED_MULTIPLIER = 4.8   -- DialogueUI "Maintain Offset While Mounted" (window on the right)
local FOCUS_CVARS = {
    test_cameraTargetFocusInteractEnable = 1,
    test_cameraTargetFocusInteractStrengthPitch = 0,
    test_cameraTargetFocusInteractStrengthYaw = 0,
    test_cameraHeadMovementStrength = 0,
    CameraKeepCharacterCentered = 0,
    CameraReduceUnexpectedMovement = 0,
}
-- Druid forms: shoulder offset per form (DialogueUI's table).
local FORM_OFFSET = { [1] = 1.0, [2] = 1.0, [3] = 1.1, [4] = 0.9, [5] = 0.9, [27] = 0.55, [29] = 0.55, [31] = 1.0 }

local GetCVar, SetCVar = C_CVar.GetCVar, C_CVar.SetCVar

local cam = {
    active = false,
    mode = nil,          -- "focus" (a speaker) or "pan" (no speaker)
    backup = nil,        -- [cvar] = value before we changed it
    oldZoom = nil,
    onRight = false,     -- window on the right half of the screen
    multiplier = 1,      -- shoulder side and mount scaling
    shoulder = SHOULDER_DEFAULT,
    panScale = 1,
    fovStart = nil,      -- set when the field of view is being changed
}
local driver = CreateFrame("Frame")
local events = CreateFrame("Frame")
local inCombat = false
local restoreToken = 0
local blocked = false
local scene, actor

local function OutSine(t, from, to)
    return (to - from) * math.sin(t / EASE_TIME * (math.pi / 2)) + from
end

local function Set(cvar, value)
    pcall(SetCVar, cvar, value)
end

local function DynamicCamLoaded()
    return C_AddOns.IsAddOnLoaded("DynamicCam") and true or false
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

-- As early as possible: our saved settings have just loaded, before login
-- (a leftover test_camera* value could raise it at login).
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    local all = XpieUIForeverDB and XpieUIForeverDB.plugins
    local db = type(all) == "table" and all.quest
    if type(db) ~= "table" or (db.enabled ~= false and db.camera ~= false) or db.cameraBackup then
        BlockWarning()
    end
end)

-- ---------------------------------------------------------------------------
-- Settings we change, backed up first (and saved, for a crash)
-- ---------------------------------------------------------------------------
local function Backup(cvar)
    if cam.backup[cvar] == nil then cam.backup[cvar] = GetCVar(cvar) end
end

local function BackupAndSet(cvar, value)
    Backup(cvar)
    if value ~= nil then Set(cvar, value) end
end

local function RestoreCVars(backup)
    for cvar, value in pairs(backup) do Set(cvar, value) end
    ConsoleExec("pitchlimit 88")
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

local function SetShoulder(value)
    cam.shoulderNow = value
    Set("test_cameraOverShoulder", value)
end

local function MoveToFinalOffset()
    if cam.mode == "focus" then
        SetShoulder(cam.multiplier * cam.shoulder)
    else
        SetShoulder(cam.multiplier * PanOffset())
    end
end

-- ---------------------------------------------------------------------------
-- Zoom
-- ---------------------------------------------------------------------------
local function ZoomTo(goal, inOnly)
    local diff = GetCameraZoom() - goal
    if inOnly and diff < 0 then return end
    if diff > 0.1 then CameraZoomIn(diff) elseif diff < -0.1 then CameraZoomOut(-diff) end
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
            C_Timer.After(0.1, Poll)
        else
            actor:ClearModel()
            callback(nil)
        end
    end
    C_Timer.After(0.05, Poll)
end

-- ---------------------------------------------------------------------------
-- Easing
-- ---------------------------------------------------------------------------
local function Focus_OnUpdate(_, elapsed)
    cam.t = cam.t + elapsed
    local t = math.min(cam.t, EASE_TIME)
    Set("test_cameraTargetFocusInteractStrengthPitch", OutSine(t, 0, 1))
    if cam.fovStart then Set("cameraFov", OutSine(t, cam.fovStart, FOV_ZOOMED)) end
    if cam.t >= EASE_TIME then
        -- The lowered limit tipped the camera level; let go of it now (as DialogueUI).
        ConsoleExec("pitchlimit 88")
        driver:SetScript("OnUpdate", nil)
    else
        ConsoleExec("pitchlimit " .. math.floor(OutSine(t, 88, 15) + 0.5))
    end
end

-- No speaker: the offset follows the zoom.
local function Pan_OnUpdate(_, elapsed)
    cam.t = cam.t + elapsed
    if cam.t > 0.03 then
        cam.t = 0
        local goal = cam.multiplier * PanOffset()
        local amount = math.min(cam.blend * elapsed * 60, 1)
        SetShoulder(cam.shoulderNow + (goal - cam.shoulderNow) * amount)
    end
end

-- ---------------------------------------------------------------------------
-- Start / restore
-- ---------------------------------------------------------------------------
local function ListenWhileActive(on)
    local list = { "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_IS_GLIDING_CHANGED", "UPDATE_SHAPESHIFT_FORM" }
    for _, event in ipairs(list) do
        if on then pcall(events.RegisterEvent, events, event) else pcall(events.UnregisterEvent, events, event) end
    end
end

local function Start()
    if cam.active then return end
    BlockWarning()
    cam.active = true
    cam.backup = {}
    plugin.db.cameraBackup = cam.backup   -- saved until restored
    cam.oldZoom = GetCameraZoom()
    cam.onRight = WindowOnRight()
    cam.fovStart = nil
    cam.t = 0
    UpdateMultiplier()
    UpdateForm()
    ListenWhileActive(true)

    if HasSpeaker() then
        cam.mode = "focus"
        for cvar, value in pairs(FOCUS_CVARS) do BackupAndSet(cvar, value) end
        Backup("test_cameraOverShoulder")
        if not IsDynamicFlying() then
            -- Not while mounted or gliding: skyriding's speed effect changes it too.
            Backup("cameraFov")
            cam.fovStart = tonumber(GetCVar("cameraFov")) or 90
        end
        SetShoulder(cam.multiplier * cam.shoulder)
        driver:SetScript("OnUpdate", Focus_OnUpdate)
        MeasureSpeaker(function(height)
            if not (cam.active and cam.mode == "focus") then return end
            local goal = ZoomForHeight(height or FALLBACK_HEIGHT)
            if goal then ZoomTo(goal, true) end
        end)
    else
        cam.mode = "pan"
        BackupAndSet("test_cameraOverShoulder")
        BackupAndSet("CameraKeepCharacterCentered", 0)
        BackupAndSet("CameraReduceUnexpectedMovement", 0)
        cam.shoulderNow = tonumber(GetCVar("test_cameraOverShoulder")) or 0
        cam.blend = (cam.multiplier * PanOffset() - cam.shoulderNow > 8) and 0.06 or 0.10
        driver:SetScript("OnUpdate", Pan_OnUpdate)
        ZoomTo(3, true)
    end
end

local function Restore()
    if not cam.active then return end
    cam.active = false
    driver:SetScript("OnUpdate", nil)
    ListenWhileActive(false)
    RestoreCVars(cam.backup)
    cam.backup = nil
    plugin.db.cameraBackup = nil
    if cam.oldZoom then ZoomTo(cam.oldZoom) end
    cam.oldZoom, cam.mode, cam.fovStart = nil, nil, nil
end

local function CameraOn()
    return plugin:IsLive() and plugin.db.camera and blocked and not DynamicCamLoaded()
end

local function Update()
    local want = CameraOn() and ShownWindow() and not inCombat and not InCombatLockdown()
    if want and not cam.active then
        Start()
    elseif not want and cam.active then
        Restore()
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

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- InCombatLockdown() can still be false during REGEN_DISABLED.
        inCombat = event == "PLAYER_REGEN_DISABLED"
        Update()
    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then
        Restore()
    elseif not cam.active then
        return
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        UpdateForm()
        MoveToFinalOffset()
    else   -- mounted, dismounted, started or stopped gliding
        UpdateMultiplier()
        MoveToFinalOffset()
        if cam.fovStart and IsDynamicFlying() and cam.backup.cameraFov ~= nil then
            cam.fovStart = nil   -- the ease stops changing it
            Set("cameraFov", cam.backup.cameraFov)
        end
    end
end)

-- Turned on in the settings: block the warning before the first use.
function plugin:CameraSettingChanged()
    if self.db.camera and self:IsLive() then BlockWarning() end
end

function plugin:InitCamera()
    -- Left over from a crash or disconnect mid-conversation.
    local leftover = self.db.cameraBackup
    if leftover then
        BlockWarning()
        RestoreCVars(leftover)
        self.db.cameraBackup = nil
    end
    if self.cameraReady or not self:IsLive() then return end
    self.cameraReady = true
    if self.db.camera then BlockWarning() end
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame then
            frame:HookScript("OnShow", OnWindowShow)
            frame:HookScript("OnHide", OnWindowHide)
        end
    end
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
            "PLAYER_LOGOUT", "PLAYER_CAMPING", "PLAYER_QUITING" }) do
        pcall(events.RegisterEvent, events, event)
    end
    Update()
end
