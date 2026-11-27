-- Widgets.lua  (XpieUI-Forever)
-- Settings controls in the native HUD Edit Mode style, shared by the shell and
-- its plugins. Ported from XpieHUD_Core/Settings.lua (page kit part).
--
--   local page = XpieUI:NewSettingsPage(bind)
--   page:Header("Zygor Guides")
--   page:Note("...")
--   page:Checkbox({ key = "strip", label = "...", description = "..." })
--   page:CheckGrid("Fade while talking:", { { key = ..., label = ... }, ... })
--   page:Slider({ key = ..., label = ..., description = ..., min, max, step, format })
--   page:Dropdown({ key = ..., label = ..., values = function() return { { key, label }, ... } end })
--   page:TextInput({ key = ..., label = ..., description = ..., maxLetters })
--   page:PanelStyle(function() return plugin.db.panel end)   -- look / opacity / header / title / border / padding
--   page:Button("Reset", onClick)
--
-- bind = { get = function(key) end, set = function(key, value) end } connects
-- the controls to the shell's XpieUIForeverDB or a plugin's plugin.db.
--
-- Gamepad: each control registers a focus stop (AddFocus). The settings
-- window moves the native gold arrow between them with the D-pad and calls
-- activate(button) with PAD1, PADDLEFT or PADDRIGHT. Blizzard's own gamepad
-- navigation can't be used: addon windows that join it make Blizzard's
-- binding cleanup call protected functions and get blamed for it.

local _, addon = ...

local CONTENT_WIDTH = 600
local TEXT_WIDTH = 540

-- ---------------------------------------------------------------------------
-- Page
-- ---------------------------------------------------------------------------
local PageMixin = {}
local pages = {}

function addon:NewSettingsPage(bind)
    local page = Mixin({ bind = bind, refreshers = {}, focusables = {}, editBoxes = {}, y = -10 }, PageMixin)

    -- Hosted by the settings window; a scroll frame fills it.
    page.frame = CreateFrame("Frame")
    local sf = CreateFrame("ScrollFrame", nil, page.frame, "UIPanelScrollFrameTemplate")
    -- The scroll bar (16px, 6px right of the scroll frame, arrows inside its
    -- height) sits fully inside the inner frame's border, and only shows when
    -- the page is taller than the window.
    sf:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 4, -14)
    sf:SetPoint("BOTTOMRIGHT", page.frame, "BOTTOMRIGHT", -40, 14)
    sf.scrollBarHideable = true
    if sf.ScrollBar then sf.ScrollBar:Hide() end
    page.content = CreateFrame("Frame", nil, sf)
    page.content:SetSize(CONTENT_WIDTH, 1)
    sf:SetScrollChild(page.content)
    page.scroll = sf
    page.frame:SetScript("OnSizeChanged", function(_, w)
        page.content:SetWidth(math.max(CONTENT_WIDTH, w - 50))
    end)
    page.frame:SetScript("OnShow", function() page:Refresh() end)

    pages[#pages + 1] = page
    return page
end

local function Text(parent, font, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    return fs
end

function PageMixin:Title(text, subtitle)
    local title = Text(self.content, "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 16, self.y)
    title:SetText(text)
    self.y = self.y - 30
    if subtitle then
        local sub = Text(self.content, "GameFontHighlight", TEXT_WIDTH)
        sub:SetPoint("TOPLEFT", 16, self.y)
        sub:SetText(subtitle)
        self.y = self.y - math.max(20, math.ceil(sub:GetStringHeight() or 0)) - 14
    end
end

-- Gold section header, like Edit Mode's "Frames" / "Combat" / "Misc".
function PageMixin:Header(text)
    self.y = self.y - 6
    local header = Text(self.content, "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, self.y)
    header:SetText(text)
    self.y = self.y - 32
    return header
end

function PageMixin:Note(text)
    local note = Text(self.content, "GameFontHighlightSmall", TEXT_WIDTH)
    note:SetPoint("TOPLEFT", 20, self.y)
    note:SetText(text)
    -- Room for however many lines the text wraps to, plus a gap.
    self.y = self.y - math.max(24, math.ceil(note:GetStringHeight() or 0) + 12)
    return note
end

-- Grey text next to the last header, refreshed on show (e.g. "(not loaded)").
function PageMixin:Status(getText)
    local status = Text(self.content, "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 180, self.y + 28)
    self.refreshers[#self.refreshers + 1] = function() status:SetText(getText() or "") end
end

-- Edit Mode check box: 32px box with Blizzard's gold tick, white label.
local function NewCheckButton(parent, labelText, labelWidth)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(32, 32)
    check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    local label = Text(check, "GameFontHighlightMedium", labelWidth)
    label:SetPoint("LEFT", check, "RIGHT", 5, 0)
    label:SetWordWrap(false)
    label:SetText(labelText)
    check.Label = label
    -- Clicking the label toggles too, like Blizzard's rows.
    check:SetHitRectInsets(0, -math.min(labelWidth or 200, math.ceil(label:GetStringWidth() or 0) + 8), 0, 0)
    return check
end

local function PlayCheckSound(checked)
    if SOUNDKIT then
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

function PageMixin:Checkbox(opt)
    local page = self
    local check = NewCheckButton(self.content, opt.label, 300)
    check:SetPoint("TOPLEFT", 20, self.y)

    local height = 34
    if opt.description and opt.description ~= "" then
        local description = Text(self.content, "GameFontHighlightSmall", TEXT_WIDTH - 40)
        description:SetPoint("TOPLEFT", check.Label, "BOTTOMLEFT", 0, -1)
        description:SetText(opt.description)
        height = height + math.ceil(description:GetStringHeight() or 0) + 2
    end

    check:SetScript("OnClick", function(btn)
        PlayCheckSound(btn:GetChecked())
        page:SetValue(opt, btn:GetChecked())
    end)
    self.refreshers[#self.refreshers + 1] = function() check:SetChecked(page:GetValue(opt)) end
    self:AddFocus(check, function() check:Click() end)
    self.y = self.y - height - 6
    return check
end

-- Two-column grid of label-only check boxes (Edit Mode's option grid).
function PageMixin:CheckGrid(label, opts)
    local page = self
    if label and label ~= "" then
        local caption = Text(self.content, "GameFontNormal")
        caption:SetPoint("TOPLEFT", 22, self.y)
        caption:SetText(label)
        self.y = self.y - 22
    end
    for index, opt in ipairs(opts) do
        local column = (index - 1) % 2
        local check = NewCheckButton(self.content, opt.label, 190)
        check:SetPoint("TOPLEFT", 20 + column * 260, self.y)
        check:SetScript("OnClick", function(btn)
            PlayCheckSound(btn:GetChecked())
            page:SetValue(opt, btn:GetChecked())
        end)
        self.refreshers[#self.refreshers + 1] = function() check:SetChecked(page:GetValue(opt)) end
        self:AddFocus(check, function() check:Click() end)
        if column == 1 or index == #opts then
            self.y = self.y - 36
        end
    end
    self.y = self.y - 6
end

-- White label on the left, Blizzard's minimal slider (‹ diamond ›) and its
-- value on the right. D-pad left/right step it.
function PageMixin:Slider(cfg)
    local page = self
    local label = Text(self.content, "GameFontHighlightMedium", 190)
    label:SetPoint("TOPLEFT", 22, self.y - 8)
    label:SetText(cfg.label)

    local slider = CreateFrame("Frame", nil, self.content, "MinimalSliderWithSteppersTemplate")
    slider:SetSize(260, 32)
    slider:SetPoint("TOPLEFT", 220, self.y)
    local Label = MinimalSliderWithSteppersMixin.Label
    local formatters = {
        [Label.Right] = CreateMinimalSliderFormatter(Label.Right, function(value)
            return string.format(cfg.format, value)
        end),
    }
    local steps = math.max(1, math.floor((cfg.max - cfg.min) / cfg.step + 0.5))
    slider:Init(cfg.min, cfg.min, cfg.max, steps, formatters)
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        value = math.floor((value / cfg.step) + 0.5) * cfg.step
        if not page.refreshing and page:GetValue(cfg) ~= value then
            page:SetValue(cfg, value)
        end
    end, slider)

    -- Gamepad: one stop on the label; left/right (and A) step the slider.
    self:AddFocus(label, function(button)
        slider:OnStepperClicked(button ~= "PADDLEFT")
    end, true)

    local height = 34
    if cfg.description and cfg.description ~= "" then
        local description = Text(self.content, "GameFontHighlightSmall", TEXT_WIDTH - 20)
        description:SetPoint("TOPLEFT", 22, self.y - 34)
        description:SetText(cfg.description)
        height = height + math.ceil(description:GetStringHeight() or 0) + 4
    end

    self.refreshers[#self.refreshers + 1] = function()
        slider:SetValue(page:GetValue(cfg) or cfg.min)
    end
    self.y = self.y - height - 8
    return slider
end

function PageMixin:Button(text, onClick)
    local button = CreateFrame("Button", nil, self.content, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", 20, self.y)
    button:SetSize(220, 28)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    self:AddFocus(button, function() if button:IsEnabled() then button:Click() end end)
    self.y = self.y - 38
    return button
end

-- A control reads/writes through opt.get/opt.set when given (nested settings
-- such as a panel style), otherwise through the page's bind with opt.key.
function PageMixin:GetValue(opt)
    if opt.get then return opt.get() end
    return self.bind.get(opt.key)
end

function PageMixin:SetValue(opt, value)
    if opt.set then return opt.set(value) end
    self.bind.set(opt.key, value)
end

-- Blizzard's gold-arrow dropdown look (WowStyle1DropdownTemplate art:
-- common-dropdown-textholder + common-dropdown-a-button states), but a plain
-- Button that opens XpieUI's own choice list, for mouse and gamepad alike.
-- Blizzard's menu isn't used: in gamepad mode, closing a Blizzard menu opened
-- from addon code makes Blizzard's binding cleanup call protected functions
-- and XpieUI gets blamed (ADDON_ACTION_FORBIDDEN).
local ARROW = "common-dropdown-a-button"
local ARROW_STATES = { "", "-disabled", "-pressedhover", "-hover", "-pressed", "-open" }

local function AtlasExists(name)
    return C_Texture.GetAtlasInfo(name) ~= nil
end

-- If a patch renames the dropdown art, draw a plain dark box with the chat
-- frame's expand arrow instead of an invisible control.
local dropdownArtOK
local function DropdownArtExists()
    if dropdownArtOK == nil then
        dropdownArtOK = AtlasExists("common-dropdown-textholder")
        for _, state in ipairs(ARROW_STATES) do
            dropdownArtOK = dropdownArtOK and AtlasExists(ARROW .. state)
        end
    end
    return dropdownArtOK
end

local function NewDropdownButton(parent, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 25)
    local native = DropdownArtExists()
    local bg = button:CreateTexture(nil, "BACKGROUND")
    if native then
        bg:SetAtlas("common-dropdown-textholder")
        bg:SetPoint("TOPLEFT", -8, 7)
        bg:SetPoint("BOTTOMRIGHT", 8, -9)
    else
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.6)
    end
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetPoint("RIGHT", 1, -3)
    if not native then
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetSize(16, 16)
    end
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 8, -8)
    text:SetPoint("TOPRIGHT", arrow, "LEFT")
    text:SetHeight(10)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    button.Text = text

    local over, down = false, false
    local function UpdateArrow()
        if not native then
            arrow:SetDesaturated(not button:IsEnabled())
            return
        end
        local atlas = ARROW
        if not button:IsEnabled() then atlas = ARROW .. "-disabled"
        elseif down and over then atlas = ARROW .. "-pressedhover"
        elseif over then atlas = ARROW .. "-hover"
        elseif down then atlas = ARROW .. "-pressed"
        elseif button.isOpen then atlas = ARROW .. "-open" end
        arrow:SetAtlas(atlas, true)
    end
    button.UpdateArrow = UpdateArrow
    function button:SetOpen(open) self.isOpen = open; UpdateArrow() end
    button:SetScript("OnEnter", function() over = true; UpdateArrow() end)
    button:SetScript("OnLeave", function() over = false; UpdateArrow() end)
    button:SetScript("OnMouseDown", function() down = true; UpdateArrow() end)
    button:SetScript("OnMouseUp", function() down = false; UpdateArrow() end)
    button:SetScript("OnEnable", UpdateArrow)
    button:SetScript("OnDisable", UpdateArrow)
    UpdateArrow()
    return button
end

-- White label + dropdown. opt.values() returns { { key = ..., label = ... }, ... }.
-- Click or A opens the choice list (up/down, A picks, B cancels); D-pad
-- left/right step through the choices without opening it.
function PageMixin:Dropdown(opt)
    local page = self
    local label = Text(self.content, "GameFontHighlightMedium", 190)
    label:SetPoint("TOPLEFT", 22, self.y - 8)
    label:SetText(opt.label)

    local dropdown = NewDropdownButton(self.content, opt.width or 220)
    dropdown:SetPoint("TOPLEFT", 236, self.y - 2)

    local function Pick(key)
        if page:GetValue(opt) ~= key then page:SetValue(opt, key) end
        page:Refresh()
    end
    local function Open()
        local values = opt.values()
        if #values > 0 then addon:OpenChoiceList(dropdown, values, page:GetValue(opt), Pick) end
    end
    dropdown:SetScript("OnClick", function()
        if dropdown.isOpen then addon:CloseChoiceList() else Open() end
    end)

    self:AddFocus(dropdown, function(button)
        if button == "PAD1" then Open() return end
        local values = opt.values()
        if #values == 0 then return end
        local current = 1
        for i, entry in ipairs(values) do
            if entry.key == page:GetValue(opt) then current = i end
        end
        local direction = button == "PADDLEFT" and -1 or 1
        Pick(values[(current - 1 + direction) % #values + 1].key)
    end, true)

    self.refreshers[#self.refreshers + 1] = function()
        local value, text = page:GetValue(opt), ""
        for _, entry in ipairs(opt.values()) do
            if entry.key == value then text = entry.label end
        end
        dropdown.Text:SetText(text)
    end
    self.y = self.y - 42
    return dropdown
end

-- White label + single-line text box. Enter or clicking away saves; Esc cancels.
function PageMixin:TextInput(opt)
    local page = self
    local label = Text(self.content, "GameFontHighlightMedium", 190)
    label:SetPoint("TOPLEFT", 22, self.y - 8)
    label:SetText(opt.label)

    local box = CreateFrame("EditBox", nil, self.content, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", 242, self.y - 4)
    box:SetSize(opt.width or 214, 24)
    box:SetAutoFocus(false)
    box:SetMaxLetters(opt.maxLetters or 40)
    local function Commit(eb)
        local text = strtrim(eb:GetText() or "")
        if text ~= page:GetValue(opt) then page:SetValue(opt, text) end
    end
    box:SetScript("OnEnterPressed", function(eb) Commit(eb); eb:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Commit)
    box:SetScript("OnEscapePressed", function(eb)
        eb:SetText(page:GetValue(opt) or "")
        eb:ClearFocus()
    end)

    local height = 34
    if opt.description then
        local description = Text(self.content, "GameFontHighlightSmall", TEXT_WIDTH - 20)
        description:SetPoint("TOPLEFT", 22, self.y - 34)
        description:SetText(opt.description)
        height = height + math.ceil(description:GetStringHeight() or 0) + 4
    end
    self.refreshers[#self.refreshers + 1] = function()
        if not box:HasFocus() then box:SetText(page:GetValue(opt) or "") end
    end
    self.editBoxes[#self.editBoxes + 1] = box
    -- A toggles typing (a keyboard is needed to type); moving off the row,
    -- B or leaving the page saves and gives the keyboard back.
    self:AddFocus(label, function(button)
        if button ~= "PAD1" then return end
        if box:HasFocus() then box:ClearFocus() else box:SetFocus() end
    end)
    self.y = self.y - height - 8
    return box
end

-- White label, a row of colour swatches and a hex box ("rrggbb"). The value
-- is the hex string. opt.swatches = { { hex = "9c1a1a", name = "Spoken Red" }, ... }.
-- Gamepad: D-pad left/right step through the swatches, A toggles the hex box.
local SWATCH, SWATCH_GAP = 22, 6
local GOLD = { 1, 0.82, 0 }

local function HexToRGB(hex)
    hex = type(hex) == "string" and hex:match("^#?(%x%x%x%x%x%x)$")
    if not hex then return nil end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
addon.HexToRGB = HexToRGB

function PageMixin:ColorChoice(opt)
    local page = self
    local label = Text(self.content, "GameFontHighlightMedium", 190)
    label:SetPoint("TOPLEFT", 22, self.y - 8)
    label:SetText(opt.label)

    local swatches = {}
    for index, entry in ipairs(opt.swatches) do
        local button = CreateFrame("Button", nil, self.content)
        button:SetSize(SWATCH, SWATCH)
        button:SetPoint("TOPLEFT", 220 + (index - 1) * (SWATCH + SWATCH_GAP), self.y - 5)
        button.border = button:CreateTexture(nil, "BACKGROUND")
        button.border:SetAllPoints()
        button.fill = button:CreateTexture(nil, "ARTWORK")
        button.fill:SetPoint("TOPLEFT", 2, -2)
        button.fill:SetPoint("BOTTOMRIGHT", -2, 2)
        button.fill:SetColorTexture(HexToRGB(entry.hex))
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnClick", function()
            page:SetValue(opt, entry.hex)
            page:Refresh()
        end)
        button:SetScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(entry.name)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button.hex = entry.hex
        swatches[index] = button
    end

    local box = CreateFrame("EditBox", nil, self.content, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", 220 + #swatches * (SWATCH + SWATCH_GAP) + 12, self.y - 4)
    box:SetSize(70, 24)
    box:SetAutoFocus(false)
    box:SetMaxLetters(7)
    local function Commit(eb)
        local hex = (eb:GetText() or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
        if hex then
            hex = hex:lower()
            if hex ~= page:GetValue(opt) then page:SetValue(opt, hex) end
        end
        page:Refresh()
    end
    box:SetScript("OnEnterPressed", function(eb) Commit(eb); eb:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Commit)
    box:SetScript("OnEscapePressed", function(eb)
        eb:SetText(page:GetValue(opt) or "")
        eb:ClearFocus()
    end)
    self.editBoxes[#self.editBoxes + 1] = box

    self:AddFocus(label, function(button)
        if button == "PAD1" then
            if box:HasFocus() then box:ClearFocus() else box:SetFocus() end
            return
        end
        local current = 0
        for index, swatch in ipairs(swatches) do
            if swatch.hex == page:GetValue(opt) then current = index end
        end
        local step = button == "PADDLEFT" and -1 or 1
        if current == 0 then current = step > 0 and 0 or 1 end
        swatches[(current - 1 + step) % #swatches + 1]:Click()
    end, true)

    local height = 34
    if opt.description and opt.description ~= "" then
        local description = Text(self.content, "GameFontHighlightSmall", TEXT_WIDTH - 20)
        description:SetPoint("TOPLEFT", 22, self.y - 34)
        description:SetText(opt.description)
        height = height + math.ceil(description:GetStringHeight() or 0) + 4
    end

    self.refreshers[#self.refreshers + 1] = function()
        local value = page:GetValue(opt)
        for _, swatch in ipairs(swatches) do
            if swatch.hex == value then
                swatch.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3])
            else
                swatch.border:SetColorTexture(0, 0, 0, 0.8)
            end
        end
        if not box:HasFocus() then box:SetText(value or "") end
    end
    self.y = self.y - height - 8
end

-- Background panel controls for a style table from XpieUI.PANEL_DEFAULTS.
-- The art is always Blizzard's (Quest Tracker or Tooltip look); players get
-- the look, opacity, header/border on-off, title and padding. getStyle()
-- returns the live table (plugin.db.panel). `defaults` (optional) is what
-- Reset Panel goes back to, for a plugin whose defaults differ from the core's.
function PageMixin:PanelStyle(getStyle, defaults)
    local function field(key, extra)
        local o = {
            get = function() return getStyle()[key] end,
            set = function(value) getStyle()[key] = value; addon:SettingsChanged() end,
        }
        for k, v in pairs(extra) do o[k] = v end
        return o
    end

    self:Header("Background Panel")
    self:Dropdown(field("look", { label = "Look", values = function() return addon.PANEL_LOOKS end }))
    self:Slider(field("opacity", { label = "Background Opacity", description = "How solid the panel's background is (like Edit Mode's Background Opacity). The header bar stays solid.", min = 0, max = 100, step = 5, format = "%d%%" }))
    self:Checkbox(field("header", { label = "Show Header Bar", description = "Quest Tracker look: the gold objective header bar above the window." }))
    self:TextInput(field("title", { label = "Header Title", description = "Text on the header bar. Leave empty for no title.", maxLetters = 40 }))
    self:Checkbox(field("border", { label = "Show Border", description = "Tooltip look: Blizzard's tooltip border around the panel." }))
    self:Slider(field("padding", { label = "Padding", description = "Space between the window and the panel's edges. Negative values pull the panel inside the window.", min = -10, max = 30, step = 1, format = "%d" }))
    self:Button("Reset Panel", function()
        local style = getStyle()
        wipe(style)
        addon.CopyDefaults(style, defaults or addon.PANEL_DEFAULTS)
        addon:SettingsChanged()
    end)
end

-- ---------------------------------------------------------------------------
-- Gamepad focus stops. anchor: the frame the arrow points at (its left edge).
-- activate(button): PAD1, PADDLEFT or PADDRIGHT. leftRight: the control uses
-- D-pad left/right itself (slider, dropdown); elsewhere left goes back to the
-- page list.
-- ---------------------------------------------------------------------------
function PageMixin:AddFocus(anchor, activate, leftRight)
    self.focusables[#self.focusables + 1] = { anchor = anchor, activate = activate, leftRight = leftRight }
end

function PageMixin:FocusUsesLeftRight()
    local entry = self.focusables[self.focusIndex]
    return entry and entry.leftRight or false
end

-- Point the arrow at the focused stop and scroll it into view.
function PageMixin:ShowFocus()
    local entry = self.focusables[self.focusIndex]
    if not entry then
        addon:PointAt(nil)
        return
    end
    local top, rowTop, rowBottom = self.content:GetTop(), entry.anchor:GetTop(), entry.anchor:GetBottom()
    if top and rowTop and rowBottom then
        local offsetTop, offsetBottom = top - rowTop, top - rowBottom
        local view = self.scroll:GetHeight()
        local scroll = self.scroll:GetVerticalScroll()
        if offsetTop - 16 < scroll then
            self.scroll:SetVerticalScroll(math.max(0, offsetTop - 16))
        elseif offsetBottom + 16 > scroll + view then
            self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScrollRange(), offsetBottom + 16 - view))
        end
    end
    addon:PointAt(entry.anchor)
end

-- Next/previous stop that's visible (plugin pages can hide parts).
function PageMixin:MoveFocus(delta)
    self:ReleaseTextFocus()
    local count = #self.focusables
    if count == 0 then return false end
    local index = self.focusIndex or (delta > 0 and 0 or count + 1)
    repeat
        index = index + delta
        local entry = self.focusables[index]
        if entry and entry.anchor:IsVisible() then
            self.focusIndex = index
            self:ShowFocus()
            return true
        end
    until index < 1 or index > count
    if self.focusIndex then self:ShowFocus() end
    return false
end

function PageMixin:ActivateFocus(button)
    local entry = self.focusables[self.focusIndex]
    if entry then
        addon:SafeCall(entry.activate, button)
        self:ShowFocus()
    end
end

-- Take keyboard focus away from this page's text boxes (their focus-lost
-- handler saves the text).
function PageMixin:ReleaseTextFocus()
    for _, box in ipairs(self.editBoxes) do
        if box:HasFocus() then box:ClearFocus() end
    end
end

function PageMixin:ClearFocus()
    self:ReleaseTextFocus()
    self.focusIndex = nil
    self.scroll:SetVerticalScroll(0)
end

function PageMixin:Space(px)
    self.y = self.y - (px or 10)
end

function PageMixin:Refresh()
    self.refreshing = true
    for _, refresh in ipairs(self.refreshers) do addon:SafeCall(refresh) end
    self.refreshing = nil
end

function PageMixin:Finish()
    self.content:SetHeight(math.abs(self.y) + 30)
    if ScrollFrame_OnScrollRangeChanged then
        addon:SafeCall(ScrollFrame_OnScrollRangeChanged, self.scroll)
    end
end

-- Refresh every page that's on screen (after a setting changed elsewhere).
function addon:RefreshSettings()
    for _, page in ipairs(pages) do
        if page.frame:IsVisible() then page:Refresh() end
    end
end
