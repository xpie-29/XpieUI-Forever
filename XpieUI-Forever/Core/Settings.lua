-- Settings.lua  (XpieUI-Forever)
-- One "XpieUI Forever" category in Blizzard's Settings panel (Options > AddOns):
-- a main page listing the plugins with their on/off switches, and one
-- sub-page per plugin. Built at PLAYER_LOGIN, once every plugin has registered.

local _, addon = ...

local CATEGORY_NAME = "XpieUI Forever"

-- Main page row: checkbox with the plugin's title and description, and its
-- live status to the right of the title.
local function PluginRow(page, plugin)
    local check = page:Checkbox({
        label = plugin.title,
        description = plugin.description or "",
        get = function() return plugin.db.enabled end,
        set = function(value) addon:SetPluginEnabled(plugin, value) end,
    })
    local status = page.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("LEFT", check, "RIGHT", 220, 1)
    page.refreshers[#page.refreshers + 1] = function()
        status:SetText(addon:GetPluginStatus(plugin))
    end
end

local function BuildMainPage()
    local page = addon:NewSettingsPage({
        get = function(key) return XpieUIForeverDB[key] end,
        set = function(key, value) XpieUIForeverDB[key] = value; addon:SettingsChanged() end,
    })
    page:Title(CATEGORY_NAME .. "  |cff808080" .. addon.version .. "|r",
        "Plugins that make popular addons look like part of Blizzard's own interface. Each plugin has its own page below.")

    page:Header("Plugins")
    page:Note("A plugin only runs when the addon it styles is loaded. Turning a plugin on or off takes a /reload.")
    for _, plugin in ipairs(addon.plugins) do
        PluginRow(page, plugin)
    end

    page:Space(6)
    page:Header("Commands")
    page:Note("/xui opens this page. /xui status lists each plugin's state. /xui reset resets every setting (type it twice).")
    page:Finish()
    return page
end

local function BuildPluginPage(plugin)
    local page = addon:NewSettingsPage({
        get = function(key) return plugin.db[key] end,
        set = function(key, value) plugin:SetOption(key, value) end,
    })
    page:Title(plugin.title)

    local status = page:Note("")
    page.refreshers[#page.refreshers + 1] = function()
        status:SetText("Status: " .. addon:GetPluginStatus(plugin))
    end

    if addon:IsPluginRunning(plugin) then
        if plugin.BuildSettings then
            addon:SafeCall(plugin.BuildSettings, plugin, page)
        end
    elseif not plugin.active then
        page:Note("This plugin is turned off on the " .. CATEGORY_NAME .. " page. Its settings appear here once it is on.")
    else
        page:Note("Its settings appear here once " .. (plugin.addon or "its addon") .. " is installed and enabled.")
    end
    page:Finish()
    return page
end

function addon:CreateSettings()
    if self.settingsCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then
        self:Print("Blizzard's Settings panel isn't available; settings pages were not created.")
        return
    end

    local mainPage = BuildMainPage()
    local category = Settings.RegisterCanvasLayoutCategory(mainPage.frame, CATEGORY_NAME)

    for _, plugin in ipairs(self.plugins) do
        local page = BuildPluginPage(plugin)
        Settings.RegisterCanvasLayoutSubcategory(category, page.frame, plugin.title)
    end

    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
end

function addon:OpenSettings()
    if self.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    else
        self:Print("Settings aren't available yet. Try again after entering the world.")
    end
end
