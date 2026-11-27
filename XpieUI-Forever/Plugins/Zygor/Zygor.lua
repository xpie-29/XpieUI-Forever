-- Zygor.lua  (XpieUI-Forever plugin)
-- Zygor Guides Viewer (Forever edition) in the native WoW Forever style.
-- Ported from XpieHUD_Zygor. Style "xpieui" (default):
--   * Zygor's window chrome (backdrops) transparent, its title-bar logo hidden
--   * Blizzard's font (STANDARD_TEXT_FONT) instead of Zygor's Open Sans
--   * a native background panel behind the window (Core/Panels.lua), its gold
--     header bar laid over Zygor's title bar, titled "Zygor"
-- Style "original" leaves Zygor's look alone (restored live).
--
-- Delivery 2 = this file's chrome, font and panel. Title-bar buttons, toolbar,
-- tabs, step boxes and the gold arrow follow in Delivery 3.
--
-- Zygor internals used (checked against ZygorGuidesViewerForever 1.6):
--   _G.ZGV, ZGV.Frame (ZygorGuidesViewerFrame, Skins/Default/Skin.lua)
--   ZGV.Frame:ApplySkin()      re-skins the window (backdrops, logo, steps)
--   ZGV.Frame.Border / .Back / .TabContainer / .Toolbar  (BackdropTemplate)
--   ZGV.Frame.Controls.TitleBar / .Logo / .StepNum.Step
--   ZGV.Font / ZGV.FontBold    read live when the guide redraws
--   ZGV:UpdateFrame(full)
-- Zygor isn't secure code, so hooking it can't taint Blizzard's UI.
--
-- Load order: "XpieUI-Forever" sorts before "ZygorGuidesViewerForever", so the
-- shell sees Zygor's ADDON_LOADED and calls OnTargetLoaded once Zygor's files
-- have run, before Zygor builds its window (that happens after login, in
-- Zygor's own startup thread, so Apply also retries after login).

local core = XpieUI

local TARGET = "ZygorGuidesViewerForever"

-- Zygor's panel defaults: the core's, titled "Zygor".
local PANEL_DEFAULTS = CopyTable(core.PANEL_DEFAULTS)
PANEL_DEFAULTS.title = "Zygor"

local plugin = core:RegisterPlugin("zygor", {
    title       = "Zygor Guides",
    description = "Zygor's guide window in Blizzard's native style: transparent window, native background panel, Blizzard's font.",
    addon       = TARGET,
    defaults = {
        -- "xpieui": native style. "original": leave Zygor's look alone.
        style = "xpieui",
        panel = PANEL_DEFAULTS,   -- deep-copied into the saved settings
    },
})

local function XpieStyle()
    return plugin.db and plugin.db.style == "xpieui" and _G.ZGV ~= nil
end

-- ---------------------------------------------------------------------------
-- Window chrome: Zygor's backdrops kept at zero alpha
-- ---------------------------------------------------------------------------
local clearing = false   -- re-entrancy guard for the setter post-hooks

local function ClearBackdrop(f)
    if not (f and f.GetBackdropColor) then return end
    clearing = true
    local r, g, b = f:GetBackdropColor()
    if r then f:SetBackdropColor(r, g, b, 0) end
    local br, bg, bb = f:GetBackdropBorderColor()
    if br then f:SetBackdropBorderColor(br, bg, bb, 0) end
    clearing = false
end

-- Title-bar "ZYGOR" logo (a texture). Zygor sets its image and size, never
-- its alpha, so hiding it by alpha sticks.
local function SetLogoShown(shown)
    local frame = _G.ZGV and _G.ZGV.Frame
    local logo = frame and frame.Controls and frame.Controls.Logo
    if logo then logo:SetAlpha(shown and 1 or 0) end
end

-- Zygor re-colours its window on skin changes and flashes the border when a
-- step completes; keep whatever colour it wants but at zero alpha.
local hookedChrome = {}
local function HookChrome(f)
    if not f or hookedChrome[f] or not f.SetBackdropColor then return end
    hookedChrome[f] = true
    local function reclear(self)
        if clearing or not XpieStyle() then return end
        ClearBackdrop(self)
    end
    hooksecurefunc(f, "SetBackdropColor", reclear)
    hooksecurefunc(f, "SetBackdropBorderColor", reclear)
end

local function ChromeFrames()
    local frame = _G.ZGV and _G.ZGV.Frame
    local border = frame and frame.Border
    if not border then return {} end
    return { border, border.Back, border.TabContainer, border.Toolbar }
end

local function StripChrome()
    for _, f in ipairs(ChromeFrames()) do ClearBackdrop(f) end
    SetLogoShown(false)
end

-- ---------------------------------------------------------------------------
-- Font: Zygor draws with its own Open Sans (ZGV.Font / ZGV.FontBold). The
-- guide's step text reads ZGV.Font each time it draws, so swapping it converts
-- the guide. A few Zygor files copy the font once at load (step number, tabs,
-- menus): the step number is set directly below; tabs come in Delivery 3.
-- ---------------------------------------------------------------------------
local zygorFont, zygorFontBold   -- Zygor's own fonts, for the Original style

local function ApplyFont()
    local ZGV = _G.ZGV
    if not ZGV then return false end
    if not zygorFont then zygorFont, zygorFontBold = ZGV.Font, ZGV.FontBold end
    local native = XpieStyle() and STANDARD_TEXT_FONT
    local font, bold = native or zygorFont, native or zygorFontBold
    if ZGV.Font == font and ZGV.FontBold == bold then return false end
    ZGV.Font, ZGV.FontBold = font, bold
    return true
end

-- Step number in the native font (Zygor caches its font at load).
local function ApplyStepNumberFont(frame)
    local step = frame and frame.Controls and frame.Controls.StepNum and frame.Controls.StepNum.Step
    if not step then return end
    local _, size, flags = step:GetFont()
    if XpieStyle() then
        if not step.xuiFont then step.xuiFont = { step:GetFont() } end
        step:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
    elseif step.xuiFont then
        step:SetFont(step.xuiFont[1], step.xuiFont[2] or size or 12, step.xuiFont[3] or "")
        step.xuiFont = nil
    end
end

-- ---------------------------------------------------------------------------
-- Apply (shell calls this after login, settings changes and combat)
-- ---------------------------------------------------------------------------
-- Title on the header bar starts after Zygor's menu button and stops before
-- its close button (Delivery 3 swaps those for Blizzard's gear and red X at
-- these sizes).
local TITLE_LEFT  = 4 + 27 + 5
local TITLE_RIGHT = 2 + 24 + 6

local frameHooked = false
local stripped = false

function plugin:Apply()
    local ZGV = _G.ZGV
    if not ZGV then return end
    local fontChanged = ApplyFont()

    local frame = ZGV.Frame
    if not frame then return end   -- Zygor's startup hasn't built the window yet

    if frame.ApplySkin and not frameHooked then
        frameHooked = true
        hooksecurefunc(frame, "ApplySkin", function()
            if not XpieStyle() then return end
            StripChrome()
            ApplyStepNumberFont(frame)
        end)
    end
    for _, f in ipairs(ChromeFrames()) do HookChrome(f) end

    if XpieStyle() then
        StripChrome()
        stripped = true
    elseif stripped then
        -- Original style: let Zygor repaint its own skin.
        stripped = false
        SetLogoShown(true)
        frame:ApplySkin()
        fontChanged = true
    end

    -- Native font: step number, then redraw the guide so its text picks up
    -- the swapped ZGV.Font.
    ApplyStepNumberFont(frame)
    if fontChanged and ZGV.UpdateFrame then ZGV:UpdateFrame(true) end

    -- Native background panel behind the guide window; it resizes, fades and
    -- hides with the window. Its gold header bar lies over Zygor's title bar.
    self.panel = self.panel or core:CreatePanel()
    self.panel:Attach(frame)
    local titleBar = (frame.Controls and frame.Controls.TitleBar) or (frame.Border and frame.Border.TitleBar)
    if titleBar then self.panel:SetHeaderAnchor(titleBar) end
    self.panel:SetTitleInsets(TITLE_LEFT, TITLE_RIGHT)
    self.panel:SetStyle(self.db.panel)
    self.panel:SetActive(XpieStyle())
end

-- Zygor's files have run (ZGV exists), its window isn't built yet: switch the
-- font now so the guide draws in Blizzard's font from the start.
function plugin:OnTargetLoaded()
    self.zgvFound = _G.ZGV ~= nil
    if self.db.panel then
        core.CopyDefaults(self.db.panel, PANEL_DEFAULTS)
        -- First test build defaulted the title to "Leveling Guide".
        if not self.db.titleDefaultV2 then
            self.db.titleDefaultV2 = true
            if self.db.panel.title == "Leveling Guide" then self.db.panel.title = PANEL_DEFAULTS.title end
        end
    end
    ApplyFont()
end

-- Zygor builds its window in a background thread after login; catch it.
function plugin:OnLogin()
    for _, delay in ipairs({ 1, 3, 6, 12 }) do
        C_Timer.After(delay, function() core:ApplyAll() end)
    end
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
    page:Note("XpieUI: Zygor's window in Blizzard's native style, with a native background panel. Original: Zygor's own look.\n"
        .. "|cff808080Title-bar buttons, tabs, step boxes and the gold arrow are styled in the next test build.|r")

    page:PanelStyle(function() return plugin.db.panel end, PANEL_DEFAULTS)
end

core:RegisterCommand("zygor", function()
    local frame = _G.ZGV and _G.ZGV.Frame
    core:Print(("Zygor: %s, ZGV %s, viewer frame %s, panel %s"):format(
        core:GetPluginStatus(plugin),
        _G.ZGV and "found" or "not found",
        frame and "built" or "not built",
        (plugin.panel and plugin.panel.frame:IsShown()) and "shown" or "hidden"))
end, "Check the Zygor plugin can see Zygor (testing)")
