-- Plugins.lua  (XpieUI-Forever)
-- Plugin registry. Each plugin lives in Plugins/<Name>/ inside this addon and
-- describes itself once:
--
--   local plugin = XpieUI:RegisterPlugin("zygor", {
--       title       = "Zygor Guides",               -- settings page name
--       description = "...",                        -- one line for the main page
--       addon       = "ZygorGuidesViewerForever",   -- target addon folder (optional)
--       defaults    = { ... },                      -- plugin.db is filled from these
--       Migrate     = function(self, db) end,       -- optional, first run only
--       OnTargetLoaded = function(self) end,        -- target's files have run, its
--                                                   -- windows aren't built yet
--       OnLogin     = function(self) end,           -- after PLAYER_LOGIN
--       Apply       = function(self) end,           -- re-apply after settings / combat
--       BuildSettings = function(self, page) end,   -- optional settings sub-page
--   })
--
-- Every plugin gets an "enabled" setting (default on). It is read once when
-- XpieUI loads: a plugin that is off never hooks anything, and turning it on
-- or off takes a /reload (hooks can't be removed cleanly).
--
-- A plugin with a target addon only runs if that addon is loaded. OnTargetLoaded
-- is called on the target's ADDON_LOADED (or straight away if it loaded first),
-- then OnLogin and Apply as usual.

local _, addon = ...

addon.plugins = {}

local function PluginDefaults(plugin)
    local defaults = CopyTable(plugin.defaults or {})
    if defaults.enabled == nil then defaults.enabled = true end
    return defaults
end

function addon:InitPluginDB(plugin)
    local all = XpieUIForeverDB.plugins
    local db = all[plugin.id]
    if type(db) ~= "table" then
        db = {}
        all[plugin.id] = db
        if plugin.Migrate then self:SafeCall(plugin.Migrate, plugin, db) end
    end
    self.CopyDefaults(db, PluginDefaults(plugin))
    plugin.db = db
end

-- plugin:SetOption(key, value): sets a top-level plugin setting and re-applies.
local function PluginSetOption(plugin, key, value)
    local default = PluginDefaults(plugin)[key]
    if default == nil then return end
    if type(default) == "boolean" then value = not not value end
    plugin.db[key] = value
    addon:SettingsChanged()
end

function addon:RegisterPlugin(id, plugin)
    assert(type(id) == "string" and not self:GetPlugin(id), "XpieUI: bad or duplicate plugin id")
    plugin.id = id
    plugin.title = plugin.title or id
    plugin.SetOption = PluginSetOption
    self.plugins[#self.plugins + 1] = plugin
    return plugin
end

function addon:GetPlugin(id)
    for _, plugin in ipairs(self.plugins) do
        if plugin.id == id then return plugin end
    end
end

-- Running = turned on when XpieUI loaded, and its target (if any) is loaded.
function addon:IsPluginRunning(plugin)
    return plugin.active and (not plugin.addon or plugin.targetLoaded) or false
end

-- One-line status for the settings pages and /xui status.
function addon:GetPluginStatus(plugin)
    if plugin.addon and not plugin.targetLoaded then
        local _, _, _, _, reason = C_AddOns.GetAddOnInfo(plugin.addon)
        if reason == "MISSING" then
            return "|cff808080" .. plugin.addon .. " is not installed|r"
        elseif reason == "DISABLED" then
            return "|cff808080" .. plugin.addon .. " is turned off in the AddOns list|r"
        end
        return "|cff808080" .. plugin.addon .. " is not loaded|r"
    end
    if not plugin.active then
        if plugin.db and plugin.db.enabled then
            return "|cffffd200On after /reload|r"
        end
        return "|cff808080Off|r"
    end
    if plugin.db and not plugin.db.enabled then
        return "|cffffd200Off after /reload|r"
    end
    return "|cff40ff40Active|r"
end

local function CallTargetLoaded(plugin)
    if plugin.targetLoaded then return end
    plugin.targetLoaded = true
    if plugin.active and plugin.OnTargetLoaded then
        addon:SafeCall(plugin.OnTargetLoaded, plugin)
    end
end

-- Our own ADDON_LOADED: saved variables are ready, every plugin has registered.
function addon:OnShellLoaded()
    for _, plugin in ipairs(self.plugins) do
        self:InitPluginDB(plugin)
        plugin.active = plugin.db.enabled and true or false
        -- A target that loaded before us (load order isn't guaranteed).
        if plugin.addon and C_AddOns.IsAddOnLoaded(plugin.addon) then
            CallTargetLoaded(plugin)
        end
    end
end

function addon:OnOtherAddonLoaded(name)
    for _, plugin in ipairs(self.plugins) do
        if plugin.addon == name and plugin.db then
            CallTargetLoaded(plugin)
        end
    end
end

function addon:OnPlayerLogin()
    for _, plugin in ipairs(self.plugins) do
        if plugin.OnLogin and self:IsPluginRunning(plugin) then
            self:SafeCall(plugin.OnLogin, plugin)
        end
    end
end

-- Turning a plugin on or off: saved now, applied on /reload. No StaticPopup:
-- an addon-defined popup taints Blizzard's gamepad UI when it closes
-- (ADDON_ACTION_FORBIDDEN on SetPreferredGamepadInteractTarget). The settings
-- window shows a Reload UI button instead.
function addon:NeedsReload()
    for _, plugin in ipairs(self.plugins) do
        if plugin.db and (plugin.db.enabled and true or false) ~= plugin.active then
            return true
        end
    end
    return false
end

function addon:SetPluginEnabled(plugin, enabled)
    enabled = not not enabled
    if plugin.db.enabled == enabled then return end
    plugin.db.enabled = enabled
    self:RefreshSettings()
end
