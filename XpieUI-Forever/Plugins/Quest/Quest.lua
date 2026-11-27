-- Quest.lua  (XpieUI-Forever, Quest module)
-- Blizzard's own quest, gossip and book windows, kept native, with a few
-- additions (plan: docs/quest-plan.md):
--   * Choice.lua    this module or an incompatible quest-window addon
--                   (INCOMPATIBLE below): only one can run
--   * Position.lua  one shared, saved position for the three windows
--   * Fonts.lua     Font Size for Blizzard's quest fonts
--   * HideUI.lua    the rest of the UI fades while a window is open
--   * Camera.lua    the camera turns to the speaker and zooms in a little
--   * Keys.lua      keyboard controls and tooltips at the cursor (keyboard
--                   & mouse only), Badges.lua their numbers and key hints
--
-- The module has no target addon: it works on Blizzard's frames. It stands
-- down (no hooks act) while one of those is loaded, until the player picks.

local core = XpieUI

-- Quest-window addons this module can't run beside. Folder names: used to
-- find them and in the text the player reads. To cover another one, add it
-- here; the choice window and the Quest Module setting follow.
local INCOMPATIBLE = {
    "DialogueUI",
    "Immersion",
}

local plugin = core:RegisterPlugin("quest", {
    title       = "Quest Windows",
    description = "Blizzard's quest, gossip and book windows with one shared position you can move.",
    defaults = {
        fontSize = 100,   -- % of Blizzard's quest font sizes
        hideUI   = true,  -- fade the rest of the UI while a window is open
        keyboard = true,  -- keyboard controls, badges and hints (keyboard & mouse only)
        camera   = true,  -- Speaker Camera
        -- cameraBackup: camera settings to put back, kept only mid-conversation
        -- point: { left, top } of the windows in UIParent units (absent =
        -- where Blizzard puts them). Set by dragging or Move Windows.
    },
})
core.questPlugin = plugin

-- ---------------------------------------------------------------------------
-- Incompatible quest-window addons
-- ---------------------------------------------------------------------------
local function IsInstalled(name)
    local _, _, _, _, reason = C_AddOns.GetAddOnInfo(name)
    return reason ~= "MISSING"
end

local function IsLoaded(name)
    return C_AddOns.IsAddOnLoaded(name) and true or false
end

local function Filter(test)
    local list = {}
    for _, name in ipairs(INCOMPATIBLE) do
        if test(name) then list[#list + 1] = name end
    end
    return list
end

-- The ones in the AddOns folder, and the ones running now.
function plugin:InstalledOthers() return Filter(IsInstalled) end
function plugin:LoadedOthers() return Filter(IsLoaded) end

function plugin:OtherAddonLoaded()
    return #self:LoadedOthers() > 0
end

-- "A", "A or B", "A, B or C" (or "and")
function plugin:JoinNames(list, word)
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. " " .. (word or "or") .. " " .. list[#list]
end

-- Running for real: turned on at load, and no other addon is holding the
-- quest windows. Every feature checks this before acting.
function plugin:IsLive()
    return core:IsPluginRunning(self) and not self:OtherAddonLoaded()
end

-- XpieUI's module: every incompatible addon off, for every character
-- (Forever ignores the character argument; the probe showed no-name calls
-- change them all).
function plugin:UseXpieUI()
    for _, name in ipairs(self:InstalledOthers()) do C_AddOns.DisableAddOn(name) end
    C_AddOns.SaveAddOns()
    self.db.enabled = true
    ReloadUI()
end

-- Another addon's windows: that one on, the rest of the list off. When it's
-- the only one already running (the choice window), nothing of ours was
-- hooked, so no reload is needed.
function plugin:UseOtherAddon(chosen)
    self.db.enabled = false
    local reload = not IsLoaded(chosen)
    C_AddOns.EnableAddOn(chosen)
    for _, name in ipairs(self:InstalledOthers()) do
        if name ~= chosen then
            C_AddOns.DisableAddOn(name)
            if IsLoaded(name) then reload = true end
        end
    end
    C_AddOns.SaveAddOns()
    if reload then
        ReloadUI()
    else
        self.active = false   -- nothing installed: no "reload needed" notice
        core:RefreshSettings()
        core:Print(("Quest windows: using %s. You can switch back on the Quest Windows page of /xui."):format(chosen))
    end
end

function plugin:GetStatus()
    if self.active and self:OtherAddonLoaded() then
        return ("|cffffd200Waiting: choose XpieUI or %s|r"):format(self:JoinNames(self:LoadedOthers()))
    end
    if not self.db.enabled and self:OtherAddonLoaded() then
        return ("|cff808080Off: %s handles quests|r"):format(self:JoinNames(self:LoadedOthers()))
    end
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
function plugin:BuildModuleSettings(page)
    local installed = self:InstalledOthers()
    if #installed == 0 then return end
    page:Header("Quest Module")
    page:Dropdown({
        label = "Quest Module",
        values = function()
            local values = { { key = "xpieui", label = "XpieUI" } }
            for _, name in ipairs(installed) do values[#values + 1] = { key = name, label = name } end
            return values
        end,
        get = function()
            if plugin.active and plugin:OtherAddonLoaded() then return nil end   -- not chosen yet
            if plugin.db.enabled then return "xpieui" end
            return plugin:LoadedOthers()[1] or installed[1]
        end,
        set = function(value)
            if value == "xpieui" then plugin:UseXpieUI() else plugin:UseOtherAddon(value) end
        end,
    })
    page:Note(("XpieUI keeps Blizzard's own windows. %s replace%s them. Only one can run: switching turns the others off and reloads the UI."):format(
        self:JoinNames(installed, "and"), #installed == 1 and "s" or ""))
end

function plugin:BuildSettings(page)
    if self:OtherAddonLoaded() then return end   -- waiting for the choice
    page:Header("Reading")
    page:Slider({ key = "fontSize", label = "Font Size", min = 80, max = 150, step = 5, format = "%d%%",
        description = "Size of the quest text in the quest, gossip and book windows. The windows keep their size; long text scrolls. Quest text in the map and quest log follows." })
    page:Checkbox({ key = "hideUI", label = "Hide UI While Talking",
        description = "While a quest, gossip or book window is open, the rest of the interface fades out. It comes back when the window closes, or at once if combat starts." })

    page:Header("Camera")
    page:Checkbox({ key = "camera", label = "Speaker Camera",
        description = "While talking to an NPC, the camera turns to them, moves them to the side away from the window and zooms in a little (never out). It goes back when the window closes, or at once if combat starts. Off while DynamicCam is loaded." })

    page:Header("Keyboard")
    page:Checkbox({ key = "keyboard", label = "Keyboard Controls",
        description = "Keyboard & mouse only (off while the controller UI is on): W/S or arrows move the highlight, A/D move across rewards or turn book pages, Space picks or accepts, 1-9 pick directly, Esc closes. Adds number badges and Space/Esc hints." })
    page:Note("While a window is open, tooltips appear at the mouse instead of the screen corner (keyboard & mouse).")

    page:Header("Window Position")
    page:Note("The quest, gossip and book windows share one position. Drag any of them by its title bar, or use Move Windows (works with a controller: D-pad moves, A saves, B cancels).")
    page:Button("Move Windows", function() plugin:StartMoveMode() end)
    page:Button("Reset Position", function() plugin:ResetPosition() end)
    local where = page:Note("")
    page.refreshers[#page.refreshers + 1] = function()
        local point = plugin.db.point
        where:SetText(point and ("Saved position: %d, %d"):format(point[1], point[2])
            or "Using Blizzard's position.")
    end
end

-- ---------------------------------------------------------------------------
-- Start-up
-- ---------------------------------------------------------------------------
function plugin:OnLogin()
    -- Leftovers from the probe build (Delivery 0). Its dragged spot becomes
    -- the saved position if none was set yet.
    if XpieUIForeverDB.probeMovePoint and not self.db.point then
        self.db.point = XpieUIForeverDB.probeMovePoint
    end
    XpieUIForeverDB.probeMovePoint = nil
    XpieUIForeverDB.probeLog = nil

    if self:OtherAddonLoaded() then
        self:ShowChoice()
    else
        self:InitPosition()
        self:InitHideUI()
        self:InitCamera()
        self:InitKeys()
        self:InitBadges()
        self:Apply()
    end
end

-- After a setting changed (and once at login).
function plugin:Apply()
    if not self:IsLive() then return end
    self:ApplyFonts()
    if self.UpdateHideUI then self.UpdateHideUI() end
    self:CameraSettingChanged()
    if self.UpdateCamera then self.UpdateCamera() end
    if self.UpdateKeys then self.UpdateKeys() end
end
