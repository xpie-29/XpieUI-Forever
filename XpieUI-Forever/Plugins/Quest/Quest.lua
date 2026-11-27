-- Quest.lua  (XpieUI-Forever, Quest module)
-- Blizzard's own quest, gossip and book windows, kept native, with a few
-- additions (plan: docs/quest-plan.md):
--   * Choice.lua    this module or another quest-window addon: the two can't
--                   run together
--   * Position.lua  one shared, saved position for the three windows
--   * Fonts.lua     Font Size for Blizzard's quest fonts
--   * HideUI.lua    the rest of the UI fades while a window is open
--   * Camera.lua    the camera turns to the speaker and zooms in a little
--   * Keys.lua      keyboard controls and tooltips at the cursor (keyboard
--                   & mouse only), Badges.lua their numbers and key hints
--
-- The module has no target addon: it works on Blizzard's frames. It stands
-- down (no hooks act) while that addon is loaded, until the player picks one.

local core = XpieUI

-- The quest-window addon this module can't run beside: its folder name, used
-- to find it and in the text the player reads. Named nowhere else.
local OTHER_ADDON = "DialogueUI"

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
plugin.otherAddon = OTHER_ADDON

-- ---------------------------------------------------------------------------
-- The other quest-window addon
-- ---------------------------------------------------------------------------
function plugin:OtherAddonInstalled()
    local _, _, _, _, reason = C_AddOns.GetAddOnInfo(OTHER_ADDON)
    return reason ~= "MISSING"
end

function plugin:OtherAddonLoaded()
    return C_AddOns.IsAddOnLoaded(OTHER_ADDON) and true or false
end

-- Running for real: turned on at load, and the other addon isn't holding the
-- quest windows. Every feature checks this before acting.
function plugin:IsLive()
    return core:IsPluginRunning(self) and not self:OtherAddonLoaded()
end

-- XpieUI's module: the other addon off for every character (Forever ignores the
-- character argument; the probe showed no-name calls change them all).
function plugin:UseXpieUI()
    C_AddOns.DisableAddOn(OTHER_ADDON)
    C_AddOns.SaveAddOns()
    self.db.enabled = true
    ReloadUI()
end

-- The other addon's windows. When it's already loaded (the choice window),
-- nothing of ours was hooked, so no reload is needed.
function plugin:UseOtherAddon()
    self.db.enabled = false
    if self:OtherAddonLoaded() then
        self.active = false   -- nothing installed: no "reload needed" notice
        core:RefreshSettings()
        core:Print(("Quest windows: using %s. You can switch back on the Quest Windows page of /xui."):format(OTHER_ADDON))
    else
        C_AddOns.EnableAddOn(OTHER_ADDON)
        C_AddOns.SaveAddOns()
        ReloadUI()
    end
end

function plugin:GetStatus()
    if self.active and self:OtherAddonLoaded() then
        return ("|cffffd200Waiting: choose XpieUI or %s|r"):format(OTHER_ADDON)
    end
    if not self.db.enabled and self:OtherAddonLoaded() then
        return ("|cff808080Off: %s handles quests|r"):format(OTHER_ADDON)
    end
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
function plugin:BuildModuleSettings(page)
    if not self:OtherAddonInstalled() then return end
    page:Header("Quest Module")
    page:Dropdown({
        label = "Quest Module",
        values = function()
            return {
                { key = "xpieui",     label = "XpieUI" },
                { key = "other",  label = OTHER_ADDON },
            }
        end,
        get = function()
            if plugin.active and plugin:OtherAddonLoaded() then return nil end   -- not chosen yet
            return plugin.db.enabled and "xpieui" or "other"
        end,
        set = function(value)
            if value == "xpieui" then plugin:UseXpieUI() else plugin:UseOtherAddon() end
        end,
    })
    page:Note(("XpieUI keeps Blizzard's own windows. %s replaces them. Only one can run: switching turns the other off and reloads the UI."):format(OTHER_ADDON))
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
