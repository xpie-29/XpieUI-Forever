-- Core.lua  (XpieUI-Forever)
-- Namespace, saved variables, slash commands and the re-apply loop.
-- Ported from XpieHUD_Core/Core.lua (quest window features left out).

local addonName, addon = ...

_G.XpieUI = addon

addon.name = addonName
addon.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

-- Shell-level settings. Plugin settings live in XpieUIForeverDB.plugins[id].
addon.defaults = {
    plugins = {},
}

-- Fill missing settings from defaults. Tables are deep-copied, and merged into
-- existing tables, so new fields added later appear without overwriting the
-- player's choices.
local function CopyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then
                db[key] = CopyTable(value)
            else
                CopyDefaults(db[key], value)
            end
        elseif db[key] == nil then
            db[key] = value
        end
    end
end
addon.CopyDefaults = CopyDefaults

function addon:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff70d5ffXpieUI:|r " .. tostring(message))
    end
end

-- Run fn, reporting any error to the error handler (BugSack) without stopping
-- the caller, so one broken plugin can't break the others.
function addon:SafeCall(fn, ...)
    return xpcall(fn, geterrorhandler(), ...)
end

-- ---------------------------------------------------------------------------
-- Slash commands: shell + plugin subcommands
-- ---------------------------------------------------------------------------
addon.commands = {}   -- ordered: { verb, fn, help }

function addon:RegisterCommand(verb, fn, help)
    self.commands[#self.commands + 1] = { verb = verb:lower(), fn = fn, help = help }
end

local function HandleSlashCommand(input)
    -- Lowercase only the command word; arguments keep their case.
    local verb, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    local command = string.lower(verb or "")
    local arg = rest ~= "" and rest or nil
    if command == "" then
        addon:OpenSettings()
        return
    end
    for _, entry in ipairs(addon.commands) do
        if entry.verb == command then
            entry.fn(arg)
            return
        end
    end
    addon:Print("Commands:")
    addon:Print("  |cffffffff/xui|r - open settings")
    for _, entry in ipairs(addon.commands) do
        addon:Print(("  |cffffffff/xui %s|r - %s"):format(entry.verb, entry.help or ""))
    end
end

SLASH_XPIEUI1 = "/xui"
SLASH_XPIEUI2 = "/xpieui"
SlashCmdList.XPIEUI = HandleSlashCommand

addon:RegisterCommand("reset", function()
    local now = GetTime()
    if addon.resetPendingUntil and now <= addon.resetPendingUntil then
        addon:Reset()
    else
        addon.resetPendingUntil = now + 15
        addon:Print("Type |cffffffff/xui reset|r again within 15 seconds to confirm.")
    end
end, "Reset all settings (confirm twice)")

addon:RegisterCommand("status", function()
    addon:Print(("version %s"):format(addon.version))
    for _, plugin in ipairs(addon.plugins) do
        addon:Print(("  %s: %s"):format(plugin.title, addon:GetPluginStatus(plugin)))
    end
end, "Show each plugin's state")

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
-- Central re-apply entry point: settings changes and post-combat catch-up.
-- Waits until combat ends so nothing is changed while frames are protected.
function addon:ApplyAll()
    if not self.ready or not XpieUIForeverDB then return end
    if InCombatLockdown() then
        self.applyPending = true
        return
    end
    for _, plugin in ipairs(self.plugins) do
        if plugin.Apply and self:IsPluginRunning(plugin) then
            self:SafeCall(plugin.Apply, plugin)
        end
    end
end

-- Called after a setting changed (directly or nested, e.g. a panel style).
function addon:SettingsChanged()
    self:ApplyAll()
    self:RefreshSettings()
end

function addon:Reset()
    wipe(XpieUIForeverDB)
    CopyDefaults(XpieUIForeverDB, self.defaults)
    for _, plugin in ipairs(self.plugins) do self:InitPluginDB(plugin) end
    self.resetPendingUntil = nil
    self:SettingsChanged()
    self:Print("Settings reset to defaults. |cffffffff/reload|r to apply plugin on/off changes.")
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            XpieUIForeverDB = type(XpieUIForeverDB) == "table" and XpieUIForeverDB or {}
            CopyDefaults(XpieUIForeverDB, addon.defaults)
            addon:OnShellLoaded()
        else
            addon:OnOtherAddonLoaded(arg1)
        end
    elseif event == "PLAYER_LOGIN" then
        addon.ready = true
        addon:CreateSettings()
        addon:OnPlayerLogin()
        addon:ApplyAll()
    elseif event == "PLAYER_REGEN_ENABLED" and addon.applyPending then
        addon.applyPending = nil
        addon:ApplyAll()
    end
end)
