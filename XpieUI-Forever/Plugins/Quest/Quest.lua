-- Quest.lua  (XpieUI-Forever, Quest module)
-- Blizzard's own quest, gossip and book windows, kept native, with a few
-- additions (plan: docs/quest-plan.md):
--   * Choice.lua    XpieUI or DialogueUI: the two can't run together
--   * Position.lua  one shared, saved position for the three windows
--   * Fonts.lua     Font Size for Blizzard's quest fonts
--   * HideUI.lua    the rest of the UI fades while a window is open
--
-- The module has no target addon: it works on Blizzard's frames. It stands
-- down (no hooks act) while DialogueUI is loaded, until the player picks one.

local core = XpieUI

local DIALOGUEUI = "DialogueUI"

local plugin = core:RegisterPlugin("quest", {
    title       = "Quest Windows",
    description = "Blizzard's quest, gossip and book windows with one shared position you can move.",
    defaults = {
        fontSize = 100,   -- % of Blizzard's quest font sizes
        hideUI   = true,  -- fade the rest of the UI while a window is open
        -- point: { left, top } of the windows in UIParent units (absent =
        -- where Blizzard puts them). Set by dragging or Move Windows.
    },
})
core.questPlugin = plugin

-- ---------------------------------------------------------------------------
-- DialogueUI
-- ---------------------------------------------------------------------------
function plugin:DialogueUIInstalled()
    local _, _, _, _, reason = C_AddOns.GetAddOnInfo(DIALOGUEUI)
    return reason ~= "MISSING"
end

function plugin:DialogueUILoaded()
    return C_AddOns.IsAddOnLoaded(DIALOGUEUI) and true or false
end

-- Running for real: turned on at load, and DialogueUI isn't holding the
-- quest windows. Every feature checks this before acting.
function plugin:IsLive()
    return core:IsPluginRunning(self) and not self:DialogueUILoaded()
end

-- XpieUI's module: DialogueUI off for every character (Forever ignores the
-- character argument; the probe showed no-name calls change them all).
function plugin:UseXpieUI()
    C_AddOns.DisableAddOn(DIALOGUEUI)
    C_AddOns.SaveAddOns()
    self.db.enabled = true
    ReloadUI()
end

-- DialogueUI's module. When DialogueUI is already loaded (the choice window),
-- nothing of ours was hooked, so no reload is needed.
function plugin:UseDialogueUI()
    self.db.enabled = false
    if self:DialogueUILoaded() then
        self.active = false   -- nothing installed: no "reload needed" notice
        core:RefreshSettings()
        core:Print("Quest windows: using DialogueUI. You can switch back on the Quest Windows page of /xui.")
    else
        C_AddOns.EnableAddOn(DIALOGUEUI)
        C_AddOns.SaveAddOns()
        ReloadUI()
    end
end

function plugin:GetStatus()
    if self.active and self:DialogueUILoaded() then
        return "|cffffd200Waiting: choose XpieUI or DialogueUI|r"
    end
    if not self.db.enabled and self:DialogueUILoaded() then
        return "|cff808080Off: DialogueUI handles quests|r"
    end
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
function plugin:BuildModuleSettings(page)
    if not self:DialogueUIInstalled() then return end
    page:Header("Quest Module")
    page:Dropdown({
        label = "Quest Module",
        values = function()
            return {
                { key = "xpieui",     label = "XpieUI" },
                { key = "dialogueui", label = "DialogueUI" },
            }
        end,
        get = function()
            if plugin.active and plugin:DialogueUILoaded() then return nil end   -- not chosen yet
            return plugin.db.enabled and "xpieui" or "dialogueui"
        end,
        set = function(value)
            if value == "xpieui" then plugin:UseXpieUI() else plugin:UseDialogueUI() end
        end,
    })
    page:Note("XpieUI keeps Blizzard's own windows. DialogueUI replaces them. Only one can run: switching turns the other off and reloads the UI.")
end

function plugin:BuildSettings(page)
    if self:DialogueUILoaded() then return end   -- waiting for the choice
    page:Header("Reading")
    page:Slider({ key = "fontSize", label = "Font Size", min = 80, max = 150, step = 5, format = "%d%%",
        description = "Size of the quest text in the quest, gossip and book windows. The windows keep their size; long text scrolls. Quest text in the map and quest log follows." })
    page:Checkbox({ key = "hideUI", label = "Hide UI While Talking",
        description = "While a quest, gossip or book window is open, the rest of the interface fades out. It comes back when the window closes, or at once if combat starts." })

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

    if self:DialogueUILoaded() then
        self:ShowChoice()
    else
        self:InitPosition()
        self:InitHideUI()
        self:Apply()
    end
end

-- After a setting changed (and once at login).
function plugin:Apply()
    if not self:IsLive() then return end
    self:ApplyFonts()
    if self.UpdateHideUI then self.UpdateHideUI() end
end
