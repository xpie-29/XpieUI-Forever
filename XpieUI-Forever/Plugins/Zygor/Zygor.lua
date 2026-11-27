-- Zygor.lua  (XpieUI-Forever plugin)
-- Zygor Guides Viewer (Forever edition) in the native WoW Forever style.
--
-- Delivery 1 (shell): the plugin registers, finds Zygor, and has its settings
-- page. The styling itself is ported from XpieHUD_Zygor in the next deliveries.

local core = XpieUI

local TARGET = "ZygorGuidesViewerForever"

local plugin = core:RegisterPlugin("zygor", {
    title       = "Zygor Guides",
    description = "Zygor's guide window in Blizzard's native style: transparent window, native background panel, gold arrow.",
    addon       = TARGET,
    defaults = {
        -- "xpieui": native style. "original": leave Zygor's look alone.
        style = "xpieui",
    },
})

function plugin:OnTargetLoaded()
    -- Zygor's files have run (ZGV and its skin mixins exist) and its window
    -- isn't built yet: the place for the step mixin hook and arrow skin.
    self.zgvFound = _G.ZGV ~= nil
end

function plugin:BuildSettings(page)
    page:Header("Style")
    page:Dropdown({
        key = "style", label = "Style",
        values = function()
            return {
                { key = "xpieui",   label = "XpieUI" },
                { key = "original", label = "Original" },
            }
        end,
    })
    page:Note("XpieUI: Zygor's window in Blizzard's native style. Original: Zygor's own look.\n"
        .. "|cff808080The styling arrives in the next test build; this page will fill in then.|r")
end

core:RegisterCommand("zygor", function()
    core:Print(("Zygor: %s, ZGV %s, viewer frame %s"):format(
        core:GetPluginStatus(plugin),
        plugin.zgvFound and "found" or "not found",
        (_G.ZGV and _G.ZGV.Frame) and "built" or "not built"))
end, "Check the Zygor plugin can see Zygor (testing)")
