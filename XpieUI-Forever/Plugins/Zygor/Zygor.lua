-- Zygor.lua  (XpieUI-Forever plugin)
-- Zygor Guides Viewer (Forever edition) in the native WoW Forever style.
-- Ported from XpieHUD_Zygor. Style "xpieui" (default):
--   * Zygor's window chrome (backdrops) transparent, its title-bar logo hidden
--   * Blizzard's font (STANDARD_TEXT_FONT) instead of Zygor's Open Sans
--   * a native background panel behind the window (Core/Panels.lua), its gold
--     header bar laid over Zygor's title bar, titled "Zygor"
--   * title bar: Blizzard's gold settings gear and red close button
--   * toolbar on the tracker's section-header art: gold step number, flat arrows
--   * guide tabs in Blizzard's chat-tab art, gold glow on the selected tab
--   * step boxes in Zygor's state colours at an adjustable opacity, no edges
--   * "XpieUI Gold" waypoint arrow skin (Media/arrow.tga), with a toggle
-- Style "original" leaves Zygor's look alone (restored live).
--
-- Zygor internals used (checked against ZygorGuidesViewerForever 1.6):
--   _G.ZGV, ZGV.Frame (ZygorGuidesViewerFrame, Skins/Default/Skin.lua)
--   ZGV.Frame:ApplySkin()      re-skins the window (backdrops, logo, steps)
--   ZGV.Frame.Border / .Back / .TabContainer / .Toolbar  (BackdropTemplate)
--   ZGV.Frame.Controls.TitleBar / .Logo / .StepNum.Step
--   ZGV.Font / ZGV.FontBold    read live when the guide redraws
--   ZGV:UpdateFrame(full)
--   ZGV_DefaultSkin_DefaultStep_Mixin:ApplySkin / :SetBackgroundForStep
--   ZGV.Frame.stepFramePools, ZGV.Tabs (Pool, ApplySkin, SetAsCurrent, ReanchorTabs)
--   ZGV.Pointer:AddArrowSkin / :SetArrowSkin / .ArrowSkins, ZGV.ARROWSDIR
--   ZGV.Sync:UpdateButtonColor
-- Zygor isn't secure code, so hooking it can't taint Blizzard's UI.
--
-- Load order: "XpieUI-Forever" sorts before "ZygorGuidesViewerForever", so the
-- shell sees Zygor's ADDON_LOADED and calls OnTargetLoaded once Zygor's files
-- have run, before Zygor builds its window (that happens after login, in
-- Zygor's own startup thread, so Apply also retries after login).

local core = XpieUI

local TARGET = "ZygorGuidesViewerForever"
local SKIN_ID    = "XpieUI"
local SKIN_NAME  = "XpieUI Gold"
local MEDIA_DIR  = "Interface\\AddOns\\XpieUI-Forever\\Plugins\\Zygor\\Media\\"

-- Zygor's panel defaults: the core's, titled "Zygor".
local PANEL_DEFAULTS = CopyTable(core.PANEL_DEFAULTS)
PANEL_DEFAULTS.title = "Zygor"

local plugin = core:RegisterPlugin("zygor", {
    title       = "Zygor Guides",
    description = "Zygor's guide window in Blizzard's native style: transparent window, native panel, buttons, tabs and a gold arrow.",
    addon       = TARGET,
    defaults = {
        -- "xpieui": native style. "original": leave Zygor's look alone.
        style     = "xpieui",
        goldArrow = true,   -- "XpieUI Gold" arrow skin (XpieUI style)
        stepAlpha = 50,     -- step box tint, %
        panel     = PANEL_DEFAULTS,   -- deep-copied into the saved settings
        -- prevArrowSkin: the Zygor arrow skin to restore when goldArrow is off
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

-- Step number styled like a tracker section header ("Campaign", "Quests"):
-- native font, Blizzard's gold, the header font's 1px drop shadow. (Zygor
-- caches its font at load, so it's set directly.)
local function ApplyStepNumberFont(frame)
    local step = frame and frame.Controls and frame.Controls.StepNum and frame.Controls.StepNum.Step
    if not step then return end
    local _, size, flags = step:GetFont()
    if XpieStyle() then
        if not step.xuiFont then step.xuiFont = { step:GetFont() } end
        step:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
        step:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        step:SetShadowColor(0, 0, 0, 1)
        step:SetShadowOffset(1, -1)
    elseif step.xuiFont then
        step:SetFont(step.xuiFont[1], step.xuiFont[2] or size or 12, step.xuiFont[3] or "")
        step:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())   -- Zygor's template white
        step.xuiFont = nil
    end
end

-- ---------------------------------------------------------------------------
-- Step boxes (2g): Zygor's state colours (dark normal, green complete, red
-- unavailable) kept at an adjustable opacity, without edges.
-- ---------------------------------------------------------------------------
local function StyleStep(step)
    if clearing or not XpieStyle() or not step.GetBackdropColor then return end
    clearing = true
    local r, g, b = step:GetBackdropColor()
    if r then step:SetBackdropColor(r, g, b, (plugin.db.stepAlpha or 50) / 100) end
    local br, bg, bb = step:GetBackdropBorderColor()
    if br then step:SetBackdropBorderColor(br, bg, bb, 0) end
    clearing = false
end

local stepMixinHooked = false
local function HookStepMixin()
    local mixin = _G.ZGV_DefaultSkin_DefaultStep_Mixin
    if stepMixinHooked or not mixin then return end
    stepMixinHooked = true
    -- Step frames copy these methods when the pool creates them, so hooking the
    -- mixin before Zygor builds its window covers every step.
    hooksecurefunc(mixin, "ApplySkin", StyleStep)
    hooksecurefunc(mixin, "SetBackgroundForStep", StyleStep)
end

local function ForEachStep(fn)
    local frame = _G.ZGV and _G.ZGV.Frame
    local pools = frame and frame.stepFramePools
    if not pools then return end
    for _, pool in pairs(pools) do
        for step in pool:EnumerateActive() do fn(step) end
    end
end

-- Safety net for step frames created before the mixin hook (load-order race).
local function HookStepInstance(step)
    local mixin = _G.ZGV_DefaultSkin_DefaultStep_Mixin
    if mixin and step.SetBackgroundForStep ~= mixin.SetBackgroundForStep and not step.xuiHooked then
        step.xuiHooked = true
        hooksecurefunc(step, "ApplySkin", StyleStep)
        hooksecurefunc(step, "SetBackgroundForStep", StyleStep)
    end
end

-- ---------------------------------------------------------------------------
-- Gold arrow (2h): "XpieUI Gold" arrow skin.
-- 1024x1024 sprite sheet (Media/arrow.tga): 160 frames of the gold arrowhead,
-- 2.25 deg apart counter-clockwise, in 96x64 cells (Zygor's arrow texture is
-- 50x33, same 1.5 aspect, so the arrowhead shows ~33px tall).
-- ---------------------------------------------------------------------------
local function RegisterArrowSkin()
    local ZGV = _G.ZGV
    local Pointer = ZGV and ZGV.Pointer
    if not (Pointer and Pointer.AddArrowSkin) or Pointer.ArrowSkins[SKIN_ID] then return end

    local skin = Pointer:AddArrowSkin(SKIN_ID, SKIN_NAME)
    skin.GetDir = function() return MEDIA_DIR end
    skin.features = { smooth = true }
    skin.options = {
        spr_w = 96, spr_h = 64, img_w = 1024, img_h = 1024,
        spritecount = 160,
        mirror = false,
        precise = { range = 3, smooth = false, r = 1, g = 1, b = 1 },
        -- white gradient = no tint: the arrow stays gold
        ar = 1, ag = 1, ab = 1,
        br = 1, bg = 1, bb = 1,
        cr = 1, cg = 1, cb = 1,
        texture = MEDIA_DIR .. "arrow",
        template = "ZygorGuidesViewerFrame_ArrowSkin_Template",
    }
    -- Stairs / taxi / ship / waiting / error icons: reuse Zygor's Stealth set.
    skin.icons = {
        here = { 1, 1, 40, 40 }, upstairs = { 2, 1, 60, 60 }, error = { 3, 1, 40, 40 },
        instance = { 4, 1, 40, 40 }, taxi = { 5, 1, 40, 40 }, ship = { 6, 1, 40, 40 },
        waiting = { 1, 2, 40, 40 }, downstairs = { 2, 2, 60, 60 }, instancehide = { 4, 2, 40, 40 },
        file = (ZGV.ARROWSDIR or ("Interface\\AddOns\\" .. TARGET .. "\\Arrows\\")) .. "Stealth\\specials",
        cols = 8, rows = 2, width = 1024, height = 256, padding = 0,
        default = "wait",
    }
    local createFrame = skin.CreateFrame
    skin.CreateFrame = function(self)
        local f = createFrame(self)   -- runs Zygor's Setup(), which builds the icon helpers
        -- The "metal" option swaps in an -specular texture we don't ship.
        f.SetOption = function() end
        -- "You're here" marker: our gold arrowhead pointing down (sheet frame
        -- 80 = 180 deg, row 8 / column 0) at the arrow's own 50x33 size,
        -- instead of Zygor's green down-arrow. Zygor's bounce still plays.
        local here = f.icons and f.icons.here
        if here then
            here.AssignToTexture = function(_, texture)
                texture:SetTexture(MEDIA_DIR .. "arrow")
                texture:SetTexCoord(0, 96 / 1024, 512 / 1024, 576 / 1024)
                texture:SetVertexColor(1, 1, 1)
                texture:SetSize(50, 33)
            end
        end
        return f
    end
end

local function ApplyArrow()
    local ZGV = _G.ZGV
    local Pointer = ZGV and ZGV.Pointer
    local profile = ZGV and ZGV.db and ZGV.db.profile
    -- Pointer builds its arrow parent during Zygor's threaded startup.
    if not (Pointer and Pointer.ArrowSkins and Pointer.ArrowSkins[SKIN_ID] and Pointer.ArrowFrameCtrl and profile) then
        return
    end
    if InCombatLockdown() then   -- the arrow frame uses a secure state driver
        core.applyPending = true
        return
    end

    local db = plugin.db
    local want = XpieStyle() and db.goldArrow
    local current = profile.arrowskin
    if want and current ~= SKIN_ID then
        db.prevArrowSkin = current
        Pointer:SetArrowSkin(SKIN_ID)
        Pointer:UpdateArrowVisibility()
    elseif not want and current == SKIN_ID then
        local prev = db.prevArrowSkin
        if not (prev and Pointer.ArrowSkins[prev]) then prev = "Starlight" end
        Pointer:SetArrowSkin(prev)
        Pointer:UpdateArrowVisibility()
    end
end

-- ---------------------------------------------------------------------------
-- Title bar and toolbar buttons (2d, 2e)
-- Zygor's buttons stay the real buttons (clicks, menus, dragging, tooltips are
-- Zygor's own). We only change how they look:
--   * Zygor's button art is hidden by alpha (Zygor repaints it with
--     SetTexture/SetTexCoord and never touches alpha, except the highlight
--     alpha in ApplySkin, which our post-hook re-hides).
--   * Our art is extra textures on the button that Zygor doesn't know about:
--       menu  -> the Damage Meter's gold settings gear (left end of the bar)
--       close -> Blizzard's red close button (UIPanelCloseButton art and size)
--       prev/next -> Blizzard's flat arrows; tab "+" -> the tracker's "+"
--     The HIGHLIGHT layer gives the native hover; mouse down/up swap in the
--     pressed art.
-- The Original style hides our art and restores Zygor's alpha, size, anchors
-- and frame level.
-- ---------------------------------------------------------------------------
local BUTTON_STYLES = {
    MenuSettingsButton = {
        normal = "common-dropdown-a-button-settings-shadowless",
        pushed = "common-dropdown-a-button-settings-pressed-shadowless",
        hover  = "common-dropdown-a-button-settings-hover-shadowless", hoverBlend = "BLEND",
        size = 27, point = "LEFT", x = 4,   -- Blizzard's size (Damage Meter settings button)
        y = -2,   -- the gear art sits high in its box; Blizzard nudges it 2px down too
    },
    CloseButton = {
        normal = "RedButton-Exit",
        pushed = "RedButton-exit-pressed",
        hover  = "RedButton-Highlight", hoverBlend = "ADD",
        -- The gear art has empty margin in its 27px box; at 20px the red X
        -- looks the same size, and x mirrors the gear's visible edge gap.
        size = 20, point = "RIGHT", x = -7,
    },
    -- Toolbar step arrows: Blizzard's flat arrow icons (drawn 8x13 as Blizzard
    -- does), hover brightens the arrow. They keep Zygor's position and size.
    PrevButton = {
        normal = "common-icon-backarrow", pushed = "common-icon-backarrow",
        hover  = "common-icon-backarrow", hoverBlend = "ADD",
        keepPosition = true, artW = 8, artH = 13,
    },
    NextButton = {
        normal = "common-icon-forwardarrow", pushed = "common-icon-forwardarrow",
        hover  = "common-icon-forwardarrow", hoverBlend = "ADD",
        keepPosition = true, artW = 8, artH = 13,
    },
    -- Add-tab "+": the Objective Tracker's own + button at its native atlas
    -- size, tracker yellow hover.
    TabsAddButton = {
        normal = "ui-questtrackerbutton-secondary-expand",
        pushed = "ui-questtrackerbutton-secondary-expand-pressed",
        hover  = "ui-questtrackerbutton-yellow-highlight", hoverBlend = "ADD",
        keepPosition = true, atlasSize = true,
    },
}

local skins = {}       -- [button] = { art, glow, spec, saved = { points, level } }

local function SetZygorArtShown(button, shown)
    for _, tx in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(),
                          button:GetHighlightTexture(), button:GetDisabledTexture() }) do
        if tx then tx:SetAlpha(shown and 1 or 0) end
    end
end

local StyleTitleButton   -- defined below; GetSkin's hook calls it

local function GetSkin(button, spec)
    local skin = skins[button]
    if skin then return skin end

    local art = button:CreateTexture(nil, "ARTWORK")
    local function Place(tx)   -- fill the button, or a fixed-size icon centred on it
        tx:ClearAllPoints()
        if spec.atlasSize then
            local info = C_Texture.GetAtlasInfo(spec.normal)
            tx:SetPoint("CENTER")
            tx:SetSize(info and info.width or 16, info and info.height or 16)
        elseif spec.artW then
            tx:SetPoint("CENTER"); tx:SetSize(spec.artW, spec.artH)
        else
            tx:SetAllPoints()
        end
    end
    Place(art)
    art:SetAtlas(spec.normal)
    local glow = button:CreateTexture(nil, "HIGHLIGHT")   -- shown on mouse-over
    Place(glow)
    glow:SetAtlas(spec.hover)
    glow:SetBlendMode(spec.hoverBlend)

    art:Hide()    -- shown only while the XpieUI style is on
    glow:Hide()
    skin = { art = art, glow = glow, spec = spec }
    skins[button] = skin

    button:HookScript("OnMouseDown", function(self)
        if skin.on and self:IsEnabled() then art:SetAtlas(spec.pushed) end
    end)
    local function Release() art:SetAtlas(spec.normal) end
    button:HookScript("OnMouseUp", Release)
    button:HookScript("OnHide", Release)

    -- Zygor re-skins its buttons on ApplySkin: hide its art and put the
    -- button back where we want it.
    if button.ApplySkin then
        hooksecurefunc(button, "ApplySkin", function(self)
            if skin.on then StyleTitleButton(self) end
        end)
    end
    return skin
end

StyleTitleButton = function(button)
    local skin = skins[button]
    local spec = skin.spec
    if not skin.saved then
        local points = {}
        for i = 1, button:GetNumPoints() do points[i] = { button:GetPoint(i) } end
        skin.saved = { points = points, level = button:GetFrameLevel() }
    end
    skin.on = true
    SetZygorArtShown(button, false)
    skin.art:SetAtlas(spec.normal)
    skin.art:Show()
    skin.glow:Show()

    if spec.keepPosition then return end   -- toolbar arrows stay where Zygor put them
    local header = plugin.panel.headerFrame
    button:SetSize(spec.size, spec.size)
    button:ClearAllPoints()
    button:SetPoint(spec.point, header, spec.point, spec.x, spec.y or 0)
    -- Zygor pins the menu button to an absolute frame level; keep both
    -- buttons above our header bar.
    local headerLevel = header:GetFrameLevel()
    if button:GetFrameLevel() <= headerLevel then button:SetFrameLevel(headerLevel + 2) end
end

local function RestoreTitleButton(button)
    local skin = skins[button]
    if not (skin and skin.on) then return end
    skin.on = false
    skin.art:Hide()
    skin.glow:Hide()
    SetZygorArtShown(button, true)
    if button.ApplySkin then button:ApplySkin() end   -- Zygor's own size and highlight alpha
    local saved = skin.saved
    if saved then
        button:ClearAllPoints()
        for _, p in ipairs(saved.points) do button:SetPoint(unpack(p)) end
        if saved.level then button:SetFrameLevel(saved.level) end
        skin.saved = nil
    end
end

local function ApplyTitleButtons(controls)
    local on = XpieStyle() and plugin.panel ~= nil
    for key, spec in pairs(BUTTON_STYLES) do
        local button = controls[key]
        if button then
            GetSkin(button, spec)
            if on then StyleTitleButton(button) else RestoreTitleButton(button) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Gold glyphs: Blizzard has no native "share guide", "report step", "more"
-- (…) or "more tabs" (») icons, so these keep Zygor's glyphs, tinted
-- Blizzard's gold like the tracker's header controls. Only neutral colours
-- are tinted: Zygor colours the share button green during a party guide sync
-- (Sync:UpdateButtonColor), and that status stays visible. Dimmed states stay
-- dimmed (gold at the same brightness); Original converts gold back.
-- ---------------------------------------------------------------------------
local GOLD_GLYPHS = { "GuideShareButton", "ReportStep", "MenuAdditionalButton", "TabsMoreButton" }
local goldHooked = {}

local function Neutral(r, g, b)
    return r and math.abs(r - g) < 0.02 and math.abs(g - b) < 0.02
end

local function GoldLevel(r, g, b)   -- k if colour == gold * k, else nil
    local gr, gg, gb = NORMAL_FONT_COLOR:GetRGB()
    local k = r / gr
    if k > 0 and math.abs(g - gg * k) < 0.02 and math.abs(b - gb * k) < 0.02 then return k end
end

local function TintGlyph(button)
    local on = XpieStyle()
    local gr, gg, gb = NORMAL_FONT_COLOR:GetRGB()
    for _, tx in ipairs({ button:GetNormalTexture(), button:GetPushedTexture() }) do
        if tx then
            local r, g, b, a = tx:GetVertexColor()
            if on and Neutral(r, g, b) then
                tx:SetVertexColor(gr * r, gg * r, gb * r, a)
            elseif not on and r then
                local k = GoldLevel(r, g, b)
                if k then tx:SetVertexColor(k, k, k, a) end
            end
        end
    end
end

local function ApplyGoldGlyphs(controls)
    if not controls then return end
    for _, key in ipairs(GOLD_GLYPHS) do
        local button = controls[key]
        if button then
            if not goldHooked[button] and button.ApplySkin then
                goldHooked[button] = true
                hooksecurefunc(button, "ApplySkin", TintGlyph)
            end
            TintGlyph(button)
        end
    end
    -- Re-tint after Zygor recolours the share button for sync status.
    local Sync = _G.ZGV and _G.ZGV.Sync
    if Sync and Sync.UpdateButtonColor and not goldHooked[Sync] then
        goldHooked[Sync] = true
        hooksecurefunc(Sync, "UpdateButtonColor", function()
            local share = controls.GuideShareButton
            if share then TintGlyph(share) end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Guide tabs (2f): Blizzard's chat tabs (ChatTabArtTemplate art).
--   background  ChatFrameTab-BG{Left,Mid,Right}           40% unless selected
--   selected    ChatFrameTab-Selected{Left,Mid,Right}     ADD, selected tab only
--   hover       ChatFrameTab-Highlight{Left,Mid,Right}    ADD, HIGHLIGHT layer
-- The chat art is 32px tall with the tab shape in its lower part; Zygor's tabs
-- are 20px, so only the art's bottom part shows, unscaled, sitting on the
-- toolbar's gold header line. Zygor's own tab art, separators and backdrops
-- are hidden, and ZGV.Tabs is hooked so new, moved and reselected tabs stay
-- styled.
-- ---------------------------------------------------------------------------
local TAB_ART = "Interface\\ChatFrame\\ChatFrameTab-"
local TAB_INACTIVE_ALPHA = 0.4   -- Blizzard's CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA
local TAB_GLOW_ALPHA = 0.25      -- selected glow + hover highlight: subtle
local TAB_ART_HEIGHT = 32
local TAB_BOTTOM_TRIM = 4        -- px cut off the art's bottom so the tab sits on the gold line
local tabSkins = {}              -- [tab] = { bg, sel, hl (triples), font = {Zygor's} }

local function MakeTabTriple(button, kind, layer, blend)
    local triple = {}
    for i, part in ipairs({ "Left", "Mid", "Right" }) do
        local tx = button:CreateTexture(nil, layer, nil, 7)
        tx:SetTexture(TAB_ART .. kind .. part)
        if blend then tx:SetBlendMode(blend) end
        tx:Hide()
        triple[i] = tx
    end
    return triple
end

local function LayoutTabTriple(triple, button)
    local h = button:GetHeight()
    if not h or h <= 0 or h > TAB_ART_HEIGHT then h = math.min(h and h > 0 and h or 20, TAB_ART_HEIGHT) end
    local shown = h - TAB_BOTTOM_TRIM
    local top = (TAB_ART_HEIGHT - h) / TAB_ART_HEIGHT
    local bottom = (TAB_ART_HEIGHT - TAB_BOTTOM_TRIM) / TAB_ART_HEIGHT
    local left, mid, right = triple[1], triple[2], triple[3]
    left:ClearAllPoints();  left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -2, TAB_BOTTOM_TRIM);   left:SetSize(16, shown)
    right:ClearAllPoints(); right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, TAB_BOTTOM_TRIM); right:SetSize(16, shown)
    mid:ClearAllPoints()
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    for _, tx in ipairs(triple) do tx:SetTexCoord(0, 1, top, bottom) end
end

local function SetTripleShown(triple, shown, alpha)
    for _, tx in ipairs(triple) do
        tx:SetShown(shown)
        if alpha then tx:SetAlpha(alpha) end
    end
end

local function ZygorTabArt(tab)
    return { tab.DecorLeft, tab.DecorMiddle, tab.DecorRight, tab.Separator }
end

local function StyleTab(tab)
    local button = tab.Button
    if not button then return end
    local skin = tabSkins[tab]
    if not skin then
        skin = {
            bg  = MakeTabTriple(button, "BG", "BACKGROUND"),
            sel = MakeTabTriple(button, "Selected", "BACKGROUND", "ADD"),
            hl  = MakeTabTriple(button, "Highlight", "HIGHLIGHT", "ADD"),
        }
        tabSkins[tab] = skin
        HookChrome(button)
        if tab.ButtonsContainer then HookChrome(tab.ButtonsContainer) end
    end
    skin.on = true

    for _, tx in pairs(ZygorTabArt(tab)) do tx:SetAlpha(0) end
    ClearBackdrop(button)
    if tab.ButtonsContainer then ClearBackdrop(tab.ButtonsContainer) end

    for _, triple in ipairs({ skin.bg, skin.sel, skin.hl }) do LayoutTabTriple(triple, button) end
    local active = tab.isActive and true or false
    SetTripleShown(skin.bg, true, active and 1 or TAB_INACTIVE_ALPHA)
    SetTripleShown(skin.sel, active, TAB_GLOW_ALPHA)
    SetTripleShown(skin.hl, true, TAB_GLOW_ALPHA)

    if tab.Text then
        if not skin.font then skin.font = { tab.Text:GetFont() } end
        local _, size, flags = tab.Text:GetFont()
        tab.Text:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
        local r, g, b = NORMAL_FONT_COLOR:GetRGB()
        tab.Text:SetTextColor(r, g, b, active and 1 or 0.6)
    end
end

local function RestoreTab(tab)
    local skin = tabSkins[tab]
    if not (skin and skin.on) then return end
    skin.on = false
    for _, triple in ipairs({ skin.bg, skin.sel, skin.hl }) do SetTripleShown(triple, false) end
    for _, tx in pairs(ZygorTabArt(tab)) do tx:SetAlpha(1) end
    if tab.Text and skin.font and skin.font[1] then
        tab.Text:SetFont(skin.font[1], skin.font[2], skin.font[3] or "")
    end
end

local restyling = false
local function StyleAllTabs()
    local Tabs = _G.ZGV and _G.ZGV.Tabs
    if restyling or not (Tabs and Tabs.Pool) then return end
    restyling = true
    local on = XpieStyle()
    local restored = false
    for _, tab in pairs(Tabs.Pool) do
        if on then
            StyleTab(tab)
        elseif tabSkins[tab] and tabSkins[tab].on then
            RestoreTab(tab)
            restored = true
        end
    end
    -- Let Zygor repaint its own tab colours (backdrops, active tab, text).
    if restored and Tabs.ApplySkin then Tabs:ApplySkin() end
    restyling = false
end

local tabsHooked = false
local function HookTabs()
    local Tabs = _G.ZGV and _G.ZGV.Tabs
    if tabsHooked or not Tabs then return end
    tabsHooked = true
    for _, method in ipairs({ "ApplySkin", "SetAsCurrent", "ReanchorTabs" }) do
        if Tabs[method] then hooksecurefunc(Tabs, method, StyleAllTabs) end
    end
end

-- A gold line under the tab strip (the Objective Tracker's
-- "UI-World-Quest-golden-line"), on its own layer of our panel: above the
-- panel body, below Zygor's content.
local TAB_LINE_ATLAS = "UI-World-Quest-golden-line"
local tabLine

local function ApplyTabLine(frame, panel)
    local strip = frame.Controls and frame.Controls.TabContainer or (frame.Border and frame.Border.TabContainer)
    if not (strip and panel) then return end
    if not tabLine then
        local holder = CreateFrame("Frame", nil, panel.frame)
        holder:SetAllPoints(panel.frame)
        holder:EnableMouse(false)
        tabLine = holder:CreateTexture(nil, "ARTWORK")
        local info = C_Texture.GetAtlasInfo(TAB_LINE_ATLAS)
        if info then
            tabLine:SetAtlas(TAB_LINE_ATLAS, false)
            tabLine:SetHeight(math.max(1, math.min(info.height or 2, 6)))
        else
            tabLine:SetColorTexture(0, 0, 0, 0.6)
            tabLine:SetHeight(1)
        end
        tabLine.holder = holder
    end
    tabLine.holder:SetFrameLevel(panel.headerFrame:GetFrameLevel())
    tabLine:ClearAllPoints()
    tabLine:SetPoint("LEFT", strip, "BOTTOMLEFT", 0, 0)
    tabLine:SetPoint("RIGHT", strip, "BOTTOMRIGHT", 0, 0)
    tabLine.holder:SetShown(XpieStyle())
end

-- ---------------------------------------------------------------------------
-- Toolbar row (2e): prev / step number / next / icons as a tracker section
-- header ("UI-QuestTracker-Secondary-Objective-Header", the art behind
-- "Campaign" and "Quests": 260 wide frame, art at native size, centred),
-- stretched across the toolbar with the tracker's overhang at both ends.
-- ---------------------------------------------------------------------------
local SECTION_HEADER_ATLAS = "UI-QuestTracker-Secondary-Objective-Header"
local sectionHeader

local function ApplyToolbarHeader(frame, panel)
    local toolbar = frame.Controls and frame.Controls.Toolbar or (frame.Border and frame.Border.Toolbar)
    if not (toolbar and panel) then return end
    local info = C_Texture.GetAtlasInfo(SECTION_HEADER_ATLAS)
    if not sectionHeader then
        if not info then return end   -- art missing in this client: leave the row plain
        local holder = CreateFrame("Frame", nil, panel.frame)
        holder:SetAllPoints(panel.frame)
        holder:EnableMouse(false)
        sectionHeader = holder:CreateTexture(nil, "ARTWORK")
        sectionHeader:SetAtlas(SECTION_HEADER_ATLAS, false)
        sectionHeader.holder = holder
    end
    local overhang = info and info.width and math.max(0, (info.width - 260) / 2) or 0
    sectionHeader.holder:SetFrameLevel(panel.headerFrame:GetFrameLevel())
    sectionHeader:ClearAllPoints()
    sectionHeader:SetPoint("LEFT", toolbar, "LEFT", -overhang, 0)
    sectionHeader:SetPoint("RIGHT", toolbar, "RIGHT", overhang, 0)
    sectionHeader:SetHeight(info and info.height or 26)
    sectionHeader.holder:SetShown(XpieStyle())
end

-- ---------------------------------------------------------------------------
-- Apply (shell calls this after login, settings changes and combat)
-- ---------------------------------------------------------------------------
-- Title on the header bar starts after the gear and stops before the close
-- button.
local TITLE_LEFT  = 4 + 27 + 5
local TITLE_RIGHT = 7 + 20 + 6

local frameHooked = false
local stripped = false

function plugin:Apply()
    local ZGV = _G.ZGV
    if not ZGV then return end
    local fontChanged = ApplyFont()

    local frame = ZGV.Frame
    if not frame then return end   -- Zygor's startup hasn't built the window yet

    RegisterArrowSkin()
    HookStepMixin()

    if frame.ApplySkin and not frameHooked then
        frameHooked = true
        hooksecurefunc(frame, "ApplySkin", function()
            if not XpieStyle() then return end
            StripChrome()
            ForEachStep(StyleStep)
            ApplyStepNumberFont(frame)
        end)
    end
    for _, f in ipairs(ChromeFrames()) do HookChrome(f) end
    ForEachStep(HookStepInstance)

    if XpieStyle() then
        StripChrome()
        ForEachStep(StyleStep)
        stripped = true
    elseif stripped then
        -- Original style: let Zygor repaint its own skin and step colours.
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

    if frame.Controls then ApplyTitleButtons(frame.Controls) end
    ApplyGoldGlyphs(frame.Controls)
    HookTabs()
    StyleAllTabs()
    ApplyTabLine(frame, self.panel)
    ApplyToolbarHeader(frame, self.panel)
    ApplyArrow()
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
    -- Before Zygor builds its window: arrow skin registered, step mixin hooked,
    -- font switched, so everything draws styled from the start.
    RegisterArrowSkin()
    HookStepMixin()
    ApplyFont()
end

-- ---------------------------------------------------------------------------
-- Zygor bug workaround (any style): a window dragged against the top edge
-- comes back ~20px lower after a reload.
-- Zygor's window may hang partly above the screen (its handle's clamp insets
-- allow 43px), and its top part is empty once the chrome is transparent, so
-- the window you see sits flush with the top while the frame overhangs it.
-- Zygor saves only its handle's anchor, which doesn't keep that overhang
-- (measured: saved y 0.0 while the window was 22px above the edge), so after
-- a reload the window is fully on screen and looks lower.
-- Fix: when a drag/resize ends, remember where the window itself is on
-- screen; after login, once Zygor's insets are set, move the handle by the
-- difference. We never write Zygor's own saved data.
-- ---------------------------------------------------------------------------
local anchorDone = false

local function Master()
    local ZGV = _G.ZGV
    return ZGV and ZGV.Frame and ZGV.Frame:GetParent()
end

-- The window's top-left in screen pixels, measured from the screen's top-left.
local function WindowScreenPos()
    local frame = _G.ZGV and _G.ZGV.Frame
    if not (frame and frame:GetTop() and frame:GetLeft()) then return end
    local s = frame:GetEffectiveScale()
    local screenTop = UIParent:GetTop() * UIParent:GetEffectiveScale()
    return frame:GetLeft() * s, screenTop - frame:GetTop() * s
end

local masterHooked = false
local function HookMaster()
    local master = Master()
    if masterHooked or not master then return end
    masterHooked = true
    hooksecurefunc(master, "StopMovingOrSizing", function()
        -- Zygor re-aligns right after; measure once that has run.
        C_Timer.After(0, function()
            local left, top = WindowScreenPos()
            if left then plugin.db.windowPos = { left = left, top = top } end
        end)
    end)
end

local function RestoreWindowPos()
    local ZGV = _G.ZGV
    local master = Master()
    local want = plugin.db.windowPos
    if anchorDone or not (master and want) then return end
    if ZGV.framemoving or (MerchantFrame and MerchantFrame:IsShown()) then return end
    -- Wait until Zygor has set the handle's clamp insets (right inset > 0).
    local _, right = master:GetClampRectInsets()
    if not (right and right > 0) then return end

    local left, top = WindowScreenPos()
    if not left then return end
    if math.abs(left - want.left) >= 1 then
        -- Moved sideways without us (e.g. XpieUI off): forget our copy.
        plugin.db.windowPos = { left = left, top = top }
        anchorDone = true
        return
    end
    local delta = top - want.top   -- px the window sits too low (+) or too high (-)
    if math.abs(delta) < 1 then
        anchorDone = true          -- in place
        return
    end
    local point, rel, relPoint, x, y = master:GetPoint(1)
    if not (point and y) then return end
    master:ClearAllPoints()
    master:SetPoint(point, rel or UIParent, relPoint, x, y + delta / master:GetEffectiveScale())
    -- Checked again on the next try.
end

-- Zygor builds its window in a background thread after login; catch it.
function plugin:OnLogin()
    for _, delay in ipairs({ 1, 3, 6, 12 }) do
        C_Timer.After(delay, function() core:ApplyAll() end)
    end
    for _, delay in ipairs({ 2, 4, 8, 15 }) do
        C_Timer.After(delay, function()
            if core:IsPluginRunning(plugin) then
                core:SafeCall(HookMaster)
                core:SafeCall(RestoreWindowPos)
            end
        end)
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
    page:Note("XpieUI: Zygor's window in Blizzard's native style: native panel, gear and close buttons, tracker toolbar, chat-style tabs and a gold arrow. Original: Zygor's own look.")

    page:Header("XpieUI Style")
    page:Checkbox({ key = "goldArrow", label = "Gold Waypoint Arrow", description = "Use the XpieUI gold arrowhead as Zygor's arrow skin (also selectable as \"XpieUI Gold\" in Zygor's own options). Off returns to your previous arrow." })
    page:Slider({ key = "stepAlpha", label = "Step Box Opacity", description = "Tint behind each guide step. Zygor's colours are kept (dark normal, green complete, red unavailable).", min = 0, max = 100, step = 5, format = "%d%%" })

    page:PanelStyle(function() return plugin.db.panel end, PANEL_DEFAULTS)
end

-- /xui zygorpos: where Zygor's frames are and what clamps them (testing the
-- top-edge position bug). Screen-pixel tops so different scales compare.
core:RegisterCommand("zygorpos", function()
    local ZGV = _G.ZGV
    local frame = ZGV and ZGV.Frame
    if not frame then core:Print("Zygor's window isn't built.") return end
    local screenTop = UIParent:GetTop() * UIParent:GetEffectiveScale()
    local function Describe(f, label)
        local point, rel, relPoint, x, y = f:GetPoint(1)
        local top = f:GetTop() and (screenTop - f:GetTop() * f:GetEffectiveScale()) or -1
        local l, r, t, b = f:GetClampRectInsets()
        core:Print(("%s: %s %s %s %.1f,%.1f | %.1fpx below screen top | size %.0fx%.0f scale %.2f | clamped %s insets L%.0f R%.0f T%.0f B%.0f"):format(
            label, tostring(point), rel and (rel:GetName() or "?") or "nil", tostring(relPoint), x or 0, y or 0,
            top, f:GetWidth(), f:GetHeight(), f:GetEffectiveScale(), tostring(f:IsClampedToScreen()),
            l or 0, r or 0, t or 0, b or 0))
    end
    Describe(frame:GetParent(), "Master")
    Describe(frame, "Window")
    if frame.Border then Describe(frame.Border, "Border") end
    local titleBar = frame.Controls and frame.Controls.TitleBar
    if titleBar then Describe(titleBar, "TitleBar") end
    if plugin.panel then Describe(plugin.panel.frame, "XpieUI panel") end
    local bar = ZGV.ActionBar and ZGV.ActionBar.Frame
    if bar then
        Describe(bar, "ActionBar")
        core:Print(("ActionBar shown %s, enabled %s, snapped %s"):format(tostring(bar:IsShown()),
            tostring(ZGV.db.profile.enable_actionbar), tostring(bar.snapped)))
    else
        core:Print("ActionBar frame: not created")
    end
    local saved = ZGV.db.profile.frame_anchor
    if saved then core:Print(("Saved: %s %s %.1f,%.1f"):format(tostring(saved[1]), tostring(saved[3]), saved[4] or 0, saved[5] or 0)) end
    local tabs = frame.Border and frame.Border.TabContainer
    core:Print(("Tab bar height %.1f, resizeup %s, scale option %s"):format(
        tabs and tabs:GetHeight() or -1, tostring(ZGV.db.profile.resizeup), tostring(ZGV.db.profile.framescale)))
end, "Report Zygor window position and clamping (testing)")

core:RegisterCommand("zygor", function()
    local frame = _G.ZGV and _G.ZGV.Frame
    core:Print(("Zygor: %s, ZGV %s, viewer frame %s, panel %s"):format(
        core:GetPluginStatus(plugin),
        _G.ZGV and "found" or "not found",
        frame and "built" or "not built",
        (plugin.panel and plugin.panel.frame:IsShown()) and "shown" or "hidden"))
end, "Check the Zygor plugin can see Zygor (testing)")

-- ---------------------------------------------------------------------------
-- /xui arrowdebug: report in chat whenever Zygor's arrow stops drawing our
-- gold sprite (special icon, error icon, another skin's frame showing).
-- Hooks stay installed once added; the toggle only mutes/unmutes them.
-- ---------------------------------------------------------------------------
local arrowDebug = false
local arrowDebugHooked = {}
local lastDebugMsg, lastDebugTime = nil, 0

local function DebugArrow(msg)
    if not arrowDebug then return end
    local now = GetTime()
    if msg == lastDebugMsg and now - lastDebugTime < 1 then return end   -- no spam
    lastDebugMsg, lastDebugTime = msg, now
    local Pointer = _G.ZGV and _G.ZGV.Pointer
    local skin = Pointer and Pointer.CurrentArrowSkin and Pointer.CurrentArrowSkin.id or "?"
    core:Print(("|cffffd200[arrow]|r %s  (active skin: %s)"):format(msg, skin))
end

local function HookArrowFrame(skinId, frame)
    if not frame or arrowDebugHooked[frame] then return end
    arrowDebugHooked[frame] = true
    if frame.ShowSpecial then
        hooksecurefunc(frame, "ShowSpecial", function(self, spec)
            self.xuiLastSpecial = true
            DebugArrow(("%s frame: special icon '%s'"):format(skinId, tostring(spec)))
        end)
    end
    if frame.ShowTraveling then
        hooksecurefunc(frame, "ShowTraveling", function(self)
            if self.xuiLastSpecial ~= false then
                self.xuiLastSpecial = false
                DebugArrow(("%s frame: back to the direction arrow"):format(skinId))
            end
        end)
    end
    frame:HookScript("OnShow", function(self)
        local Pointer = _G.ZGV and _G.ZGV.Pointer
        if Pointer and Pointer.ArrowFrame ~= self then
            DebugArrow(("%s frame SHOWN but it is not the active arrow frame"):format(skinId))
        end
    end)
end

core:RegisterCommand("arrowdebug", function()
    local Pointer = _G.ZGV and _G.ZGV.Pointer
    if not (Pointer and Pointer.ArrowSkins) then
        core:Print("Zygor isn't loaded.")
        return
    end
    for id, skin in pairs(Pointer.ArrowSkins) do
        HookArrowFrame(id, skin.frame)   -- skins create their frame on first use
    end
    arrowDebug = not arrowDebug
    lastDebugMsg = nil
    core:Print("Zygor arrow debug " .. (arrowDebug and "|cff40ff40ON|r: reproduce the problem, then read chat. Run /xui arrowdebug again to stop."
        or "|cffff4040OFF|r."))
    if arrowDebug then
        local frames = {}
        for id, skin in pairs(Pointer.ArrowSkins) do
            if skin.frame then
                frames[#frames + 1] = ("%s=%s"):format(id, skin.frame:IsShown() and "shown" or "hidden")
            end
        end
        core:Print("Arrow frames: " .. table.concat(frames, ", "))
    end
end, "Report Zygor arrow state changes in chat (troubleshooting)")
