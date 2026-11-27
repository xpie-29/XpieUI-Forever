-- Settings.lua  (XpieUI-Forever)
-- XpieUI's own settings window (/xui), built from Blizzard's native pieces so
-- it matches the HUD Edit Mode dialog: the gold-trimmed "Dialog" border, white
-- title, red close button, the Options inner frame, and Game Menu red buttons
-- for the page list on the left.
--
-- Gamepad: the window reads the controller itself (EnableGamePadButton) and
-- moves Blizzard's own gold arrow art between controls:
--   Page list   D-pad up/down pick a page, A or right opens it, B closes
--   Page        D-pad up/down move, A or left/right change, B (or left on a
--               control that doesn't use left/right) back to the page list
-- It does NOT join Blizzard's gamepad navigation (FrameControlsManager /
-- SmartNavigation): addon windows that do make Blizzard's binding cleanup call
-- protected functions (SetPreferredGamepadInteractTarget) and XpieUI gets
-- blamed, even through Blizzard's wrapped entry points.
--
-- Blizzard's Options > AddOns list gets a small entry that opens this window.
-- Built at PLAYER_LOGIN, once every plugin has registered.

local _, addon = ...

local CATEGORY_NAME = "XpieUI Forever"
local FRAME_WIDTH, FRAME_HEIGHT = 900, 620
local SIDEBAR_WIDTH = 220
-- Page list like the Game Menu: 36px red buttons stacked with no gap (the art
-- has its own margin), the same padding at the top and sides of the list.
local PAGE_BUTTON_HEIGHT = 36
local SIDEBAR_PADDING = 12

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------
-- Main page row: check box with the plugin's title and description, and its
-- live status to the right of the title.
local function PluginRow(page, plugin)
    local check = page:Checkbox({
        label = plugin.title,
        description = plugin.description or "",
        get = function() return plugin.db.enabled end,
        set = function(value) addon:SetPluginEnabled(plugin, value) end,
    })
    local status = page.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("LEFT", check, "LEFT", 300, 0)
    page.refreshers[#page.refreshers + 1] = function()
        status:SetText(addon:GetPluginStatus(plugin))
    end
end

local function BuildMainPage()
    local page = addon:NewSettingsPage({
        get = function(key) return XpieUIForeverDB[key] end,
        set = function(key, value) XpieUIForeverDB[key] = value; addon:SettingsChanged() end,
    })
    page:Title("General  |cff808080" .. addon.version .. "|r",
        "Plugins that make popular addons look like part of Blizzard's own interface. Each plugin has its own page in the list on the left.")

    page:Header("Plugins")
    page:Note("A plugin only runs when the addon it styles is loaded. Turning a plugin on or off takes a reload.")
    for _, plugin in ipairs(addon.plugins) do
        PluginRow(page, plugin)
    end

    -- Shown once a plugin was switched on or off; ReloadUI from a click is allowed.
    local reload = page:Button("Reload UI", function() ReloadUI() end)
    local reloadNote = page.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reloadNote:SetPoint("LEFT", reload, "RIGHT", 12, 0)
    page.refreshers[#page.refreshers + 1] = function()
        local needed = addon:NeedsReload()
        reload:SetEnabled(needed)
        reloadNote:SetText(needed and "|cffffd200Reload to apply your plugin changes.|r"
            or "|cff808080No changes waiting for a reload.|r")
    end

    page:Header("Commands")
    page:Note("/xui opens this window. /xui status lists each plugin's state. /xui reset resets every setting (type it twice).")
    page:Header("Gamepad")
    page:Note("Page list: D-pad up/down pick a page, A or D-pad right open it, B closes the window. On a page: D-pad up/down move, A changes the setting (on a dropdown it opens the list: up/down, A picks, B cancels), D-pad left/right change sliders and dropdowns, B (or D-pad left) goes back to the page list.")
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

    -- Settings that matter even while the plugin isn't running (the Quest
    -- module's choice of quest-window addon).
    if plugin.BuildModuleSettings then
        addon:SafeCall(plugin.BuildModuleSettings, plugin, page)
    end

    if addon:IsPluginRunning(plugin) then
        if plugin.BuildSettings then
            addon:SafeCall(plugin.BuildSettings, plugin, page)
        end
    elseif not plugin.active then
        if not plugin.BuildModuleSettings then
            page:Note("This plugin is turned off on the General page. Its settings appear here once it is on.")
        end
    else
        page:Note("Its settings appear here once " .. (plugin.addon or "its addon") .. " is installed and enabled.")
    end
    page:Finish()
    return page
end

-- ---------------------------------------------------------------------------
-- Native gold arrow (art and motion copied from SmartNavigationPointerTemplate:
-- atlas gamepad-largecursor-white at 0.8 scale, a 4px left-right bob).
-- ---------------------------------------------------------------------------
local window   -- the settings frame
local entries  -- { { title, page, button }, ... } in page-list order
local pointer

local POINTER_ATLAS = "gamepad-largecursor-white"

local function CreatePointer(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(10, 10)
    frame:SetFrameLevel(parent:GetFrameLevel() + 50)
    frame.Icon = CreateFrame("Frame", nil, frame)
    frame.Icon:SetAllPoints()
    local cursor = frame.Icon:CreateTexture(nil, "ARTWORK", nil, 2)
    if C_Texture.GetAtlasInfo(POINTER_ATLAS) then
        cursor:SetAtlas(POINTER_ATLAS, true)
        cursor:SetScale(0.8)
    else
        cursor:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        cursor:SetSize(24, 24)
    end
    cursor:SetPoint("LEFT")
    local color = GAMEPAD_SMARTNAV_CURSOR_COLOR
    if color and color.GetRGBA then
        cursor:SetVertexColor(color:GetRGBA())
    else
        cursor:SetVertexColor(1, 0.82, 0, 1)
    end

    local bob = frame.Icon:CreateAnimationGroup()
    bob:SetLooping("REPEAT")
    local out = bob:CreateAnimation("Translation")
    out:SetOffset(4, 0); out:SetDuration(1); out:SetOrder(1); out:SetSmoothing("IN_OUT")
    local back = bob:CreateAnimation("Translation")
    back:SetOffset(-4, 0); back:SetDuration(1); back:SetOrder(2); back:SetSmoothing("IN_OUT")
    frame:SetScript("OnShow", function() bob:Play() end)
    frame:SetScript("OnHide", function() bob:Stop() end)
    frame:Hide()
    return frame
end

-- Shared with plugin windows that draw the same arrow (Quest module choice).
addon.CreateGoldPointer = CreatePointer

-- Point the arrow at a frame's left edge (nil hides it). Only while a
-- controller is driving the window, so mouse users never see it.
function addon:PointAt(target)
    if not pointer then return end
    if not target or not (window and window.usingPad) then
        pointer:Hide()
        return
    end
    pointer:ClearAllPoints()
    pointer:SetPoint("RIGHT", target, "LEFT", -12, 0)
    pointer:Show()
end

-- ---------------------------------------------------------------------------
-- Choice list: a dropdown's choices, drawn like Blizzard's dropdown menu
-- (common-dropdown-bg). Mouse: click a choice, or anywhere else to cancel.
-- Gamepad: up/down move, A picks, B cancels. Blizzard's own menu isn't used:
-- closing it from addon code in gamepad mode gets XpieUI blamed for a
-- protected call, and our D-pad code couldn't drive it anyway.
-- ---------------------------------------------------------------------------
local CHOICE_ROWS, CHOICE_ROW_HEIGHT = 12, 22
local choice

local function CreateChoiceList(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetFrameLevel(parent:GetFrameLevel() + 40)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    if C_Texture.GetAtlasInfo("common-dropdown-bg") then
        bg:SetAtlas("common-dropdown-bg")
        bg:SetPoint("TOPLEFT", -10, 3)
        bg:SetPoint("BOTTOMRIGHT", 10, -3)
        bg:SetAlpha(0.925)
    else
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    end
    frame.rows = {}
    for i = 1, CHOICE_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(CHOICE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * CHOICE_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -8, -8 - (i - 1) * CHOICE_ROW_HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.check = row:CreateTexture(nil, "ARTWORK")
        row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.check:SetSize(18, 18)
        row.check:SetPoint("LEFT", 2, 0)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", 24, 0)
        row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self) addon:PickChoice(self.valueIndex) end)
        frame.rows[i] = row
    end
    frame:Hide()

    -- Click-away catcher over the window, just under the list.
    frame.blocker = CreateFrame("Button", nil, parent)
    frame.blocker:SetAllPoints(parent)
    frame.blocker:SetFrameLevel(frame:GetFrameLevel() - 1)
    frame.blocker:SetScript("OnClick", function() addon:CloseChoiceList() end)
    frame.blocker:Hide()
    frame:SetScript("OnHide", function(self)
        self.blocker:Hide()
        if self.owner then self.owner:SetOpen(false); self.owner = nil end
    end)
    return frame
end

-- Redraw the visible slice of the list around the focused choice.
local function UpdateChoiceList()
    local count = #choice.values
    if choice.index <= choice.offset then
        choice.offset = choice.index - 1
    elseif choice.index > choice.offset + CHOICE_ROWS then
        choice.offset = choice.index - CHOICE_ROWS
    end
    for i, row in ipairs(choice.rows) do
        local valueIndex = choice.offset + i
        local entry = choice.values[valueIndex]
        row:SetShown(entry ~= nil)
        if entry then
            row.valueIndex = valueIndex
            local selected = entry.key == choice.currentKey
            row.check:SetShown(selected)
            row.text:SetFontObject(selected and "GameFontNormal" or "GameFontHighlight")
            row.text:SetText(entry.label)
            if valueIndex == choice.index then row:LockHighlight() else row:UnlockHighlight() end
        end
    end
    choice:SetHeight(16 + math.min(count, CHOICE_ROWS) * CHOICE_ROW_HEIGHT)
    addon:PointAt(choice.rows[choice.index - choice.offset])
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local function CurrentPage()
    local entry = window and entries[window.selected or 1]
    return entry and entry.page
end

local function SelectPage(index)
    if not entries[index] then return end
    window.selected = index
    for i, entry in ipairs(entries) do
        local selected = i == index
        entry.page.frame:SetShown(selected)
        if not selected then entry.page:ReleaseTextFocus() end
        if selected then entry.button:LockHighlight() else entry.button:UnlockHighlight() end
    end
    entries[index].page:ClearFocus()
    if choice then choice:Hide() end
    if window.zone == "choice" then window.zone = "list" end
end

-- Controller zones: "list" (the red page buttons) or "page" (its settings).
local function SetZone(zone)
    window.zone = zone
    local page = CurrentPage()
    if zone == "page" then
        local entry = page.focusables[page.focusIndex or 0]
        if entry and entry.anchor:IsVisible() then
            page:ShowFocus()
        else
            page.focusIndex = nil
            if not page:MoveFocus(1) then
                window.zone = "list"   -- nothing to focus on this page
            end
        end
    end
    if window.zone == "list" then
        page:ReleaseTextFocus()
        page.focusIndex = nil
        addon:PointAt(entries[window.selected].button)
    end
end

function addon:OpenChoiceList(dropdown, values, currentKey, onPick)
    if choice:IsShown() then addon:CloseChoiceList() end
    choice.values, choice.currentKey, choice.onPick = values, currentKey, onPick
    choice.owner, choice.prevZone = dropdown, window.zone
    dropdown:SetOpen(true)
    choice.blocker:Show()
    choice.index, choice.offset = 1, 0
    for i, entry in ipairs(values) do
        if entry.key == currentKey then choice.index = i end
    end
    choice:ClearAllPoints()
    choice:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4)
    choice:SetWidth(math.max(dropdown:GetWidth(), 160))
    choice:Show()
    window.zone = "choice"
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
    UpdateChoiceList()
end

local function CloseChoiceList()
    if not choice:IsShown() then return end
    choice:Hide()
    window.zone = choice.prevZone == "list" and "list" or "page"
    if window.zone == "page" then CurrentPage():ShowFocus() end
end
addon.CloseChoiceList = function() CloseChoiceList() end

function addon:PickChoice(valueIndex)
    local entry = choice.values[valueIndex]
    CloseChoiceList()
    if entry then
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
        addon:SafeCall(choice.onPick, entry.key)
    end
end

-- Game Menu red button for the page list. The open page keeps the hover
-- highlight; the gold arrow shows the controller's position.
local function CreatePageButton(parent, index, title)
    local ok, button = pcall(CreateFrame, "Button", nil, parent, "MainMenuFrameButtonTemplate")
    if not ok then
        button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    end
    button:SetText(title)
    button:SetSize(SIDEBAR_WIDTH - 2 * SIDEBAR_PADDING, PAGE_BUTTON_HEIGHT)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", SIDEBAR_PADDING,
        -SIDEBAR_PADDING - (index - 1) * PAGE_BUTTON_HEIGHT)

    button:SetScript("OnClick", function()
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
        SelectPage(index)
        if window.usingPad then SetZone("list") end
    end)
    return button
end

-- Gamepad input. Hold-to-repeat for D-pad moves and slider steps.
local REPEAT_DELAY, REPEAT_RATE = 0.35, 0.08
local REPEATABLE = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true }
local CLOSE_BUTTONS = { PADBACK = true, PADFORWARD = true, PADMENU = true }

local function HandlePadButton(button)
    if CLOSE_BUTTONS[button] then
        window:Hide()
        return true
    end
    local page = CurrentPage()
    if window.zone == "choice" then
        if button == "PADDUP" or button == "PADDDOWN" then
            local index = choice.index + (button == "PADDUP" and -1 or 1)
            if choice.values[index] then
                choice.index = index
                UpdateChoiceList()
            end
        elseif button == "PAD1" then
            addon:PickChoice(choice.index)
        elseif button == "PAD2" or button == "PADDLEFT" then
            CloseChoiceList()
        elseif button ~= "PADDRIGHT" then
            return false
        end
    elseif window.zone ~= "page" then
        if button == "PADDUP" or button == "PADDDOWN" then
            local index = window.selected + (button == "PADDUP" and -1 or 1)
            if entries[index] then
                if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
                SelectPage(index)
            end
            SetZone("list")
        elseif button == "PAD1" or button == "PADDRIGHT" then
            SetZone("page")
        elseif button == "PAD2" then
            window:Hide()
        else
            return false
        end
    else
        if button == "PADDUP" then
            page:MoveFocus(-1)
        elseif button == "PADDDOWN" then
            page:MoveFocus(1)
        elseif button == "PAD2" or (button == "PADDLEFT" and not page:FocusUsesLeftRight()) then
            SetZone("list")
        elseif button == "PAD1" or button == "PADDLEFT" or button == "PADDRIGHT" then
            page:ActivateFocus(button)
        else
            return false
        end
    end
    return true
end

local function Window_OnGamePadButtonDown(self, button)
    -- In combat the window is mouse-only: every button goes to the game (set
    -- at PLAYER_REGEN_DISABLED, the last moment propagation can be changed),
    -- so abilities on the controller keep working while it's open.
    if InCombatLockdown() then return end
    if not self.usingPad then
        -- First press: show the arrow where the controller is.
        self.usingPad = true
        SetZone(self.zone or "list")
    end
    local handled = HandlePadButton(button)
    -- Unused buttons go on to the game.
    self:SetPropagateKeyboardInput(not handled)
    if handled and REPEATABLE[button] and self:IsShown() then
        self.repeatButton, self.repeatWait = button, REPEAT_DELAY
    end
end

local function Window_OnGamePadButtonUp(self, button)
    if self.repeatButton == button then self.repeatButton = nil end
end

local function Window_OnUpdate(self, elapsed)
    if not self.repeatButton then return end
    self.repeatWait = self.repeatWait - elapsed
    if self.repeatWait <= 0 then
        self.repeatWait = REPEAT_RATE
        HandlePadButton(self.repeatButton)
    end
end

-- Is a controller the active input? (Gamepad UI mode, or a pad in use.)
local function GamepadActive()
    if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then
        return true
    end
    return C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled() and GAME_PAD_ACTIVE or false
end
addon.IsGamepadActive = GamepadActive

local function CreateWindow()
    local frame = CreateFrame("Frame", "XpieUIForeverSettingsFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName())   -- Esc closes it

    -- Edit Mode's border: "Dialog" nine-slice (gold diamond metal) over 80% black.
    local ok, border = pcall(CreateFrame, "Frame", nil, frame, "DialogBorderTranslucentTemplate")
    if ok then
        frame.Border = border
    else
        local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        backdrop:SetBackdropColor(0, 0, 0, 0.9)
    end

    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    frame.Title:SetPoint("TOP", 0, -15)
    frame.Title:SetText(CATEGORY_NAME)

    -- Red close button (our own OnClick: no HideUIPanel).
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.CloseButton = close

    return frame
end

-- Edit Mode's inner options frame (OptionsFrame nine-slice) around an area.
local function AddInnerFrame(parent, area)
    local inner = CreateFrame("Frame", nil, parent)
    inner:SetPoint("TOPLEFT", area, "TOPLEFT", -8, 8)
    inner:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 8, -8)
    inner:SetFrameLevel(math.max(0, area:GetFrameLevel() - 1))
    if NineSliceUtil and NineSliceUtil.GetLayout and NineSliceUtil.GetLayout("UniqueCornersLayout") then
        pcall(NineSliceUtil.ApplyLayoutByName, inner, "UniqueCornersLayout", "OptionsFrame")
    end
    return inner
end

local function BuildWindow(pageList)
    window = CreateWindow()

    -- Full height, like the settings area; buttons start at the top with the
    -- same padding at the top and sides.
    local sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", 22, -52)
    sidebar:SetPoint("BOTTOMLEFT", 22, 22)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    AddInnerFrame(window, sidebar)

    local host = CreateFrame("Frame", nil, window)
    host:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 28, 0)
    host:SetPoint("BOTTOMRIGHT", -22, 22)
    AddInnerFrame(window, host)

    entries = {}
    for index, item in ipairs(pageList) do
        item.page.frame:SetParent(host)
        item.page.frame:ClearAllPoints()
        item.page.frame:SetAllPoints(host)
        item.page.frame:Hide()
        entries[index] = {
            title = item.title,
            page = item.page,
            button = CreatePageButton(sidebar, index, item.title),
        }
    end

    choice = CreateChoiceList(window)
    pointer = CreatePointer(window)
    pointer:SetFrameLevel(choice:GetFrameLevel() + 10)

    window:SetScript("OnShow", function(self)
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPEN) end
        self.usingPad = GamepadActive()
        SelectPage(self.selected or 1)
        SetZone("list")
        if self.EnableGamePadButton then self:EnableGamePadButton(true) end
    end)
    window:SetScript("OnHide", function(self)
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE) end
        local page = CurrentPage()
        if page then page:ReleaseTextFocus() end
        -- Opened again in combat, it must let every button through.
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        if self.EnableGamePadButton then self:EnableGamePadButton(false) end
        self.repeatButton = nil
        choice:Hide()
        pointer:Hide()
    end)
    window:SetScript("OnGamePadButtonDown", Window_OnGamePadButtonDown)
    window:SetScript("OnGamePadButtonUp", Window_OnGamePadButtonUp)
    window:SetScript("OnUpdate", Window_OnUpdate)
    window:SetPropagateKeyboardInput(true)
    window:RegisterEvent("PLAYER_REGEN_DISABLED")
    window:RegisterEvent("PLAYER_REGEN_ENABLED")
    window:SetScript("OnEvent", function(self, event)
        if not self:IsShown() then return end
        if event == "PLAYER_REGEN_DISABLED" then
            self:SetPropagateKeyboardInput(true)
            self.repeatButton = nil
            if choice:IsShown() then CloseChoiceList() end
            pointer:Hide()
        elseif self.usingPad then
            SetZone(self.zone or "list")   -- combat over: show the arrow again
        end
    end)
end

-- Small entry in Options > AddOns that opens the real window.
local function RegisterBlizzardEntry()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local stub = CreateFrame("Frame")
    local title = stub:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(CATEGORY_NAME)
    local note = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    note:SetText("XpieUI Forever has its own settings window. Type /xui, or use the button below.")
    local open = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
    open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
    open:SetSize(220, 28)
    open:SetText("Open " .. CATEGORY_NAME)
    -- Opens on top of Blizzard's Options (higher strata) without closing it:
    -- closing Blizzard's panel from addon code risks the same gamepad taint
    -- as an addon StaticPopup. Closing ours returns to Options.
    open:SetScript("OnClick", function()
        addon:OpenSettings(nil, true)
    end)
    local category = Settings.RegisterCanvasLayoutCategory(stub, CATEGORY_NAME)
    Settings.RegisterAddOnCategory(category)
    addon.settingsCategory = category
end

function addon:CreateSettings()
    if window then return end
    local pageList = { { title = "General", page = BuildMainPage() } }
    for _, plugin in ipairs(self.plugins) do
        pageList[#pageList + 1] = { title = plugin.title, page = BuildPluginPage(plugin) }
    end
    BuildWindow(pageList)
    RegisterBlizzardEntry()
end

-- /xui: toggle the window. Optional page index (1 = General).
function addon:OpenSettings(index, keepOpen)
    if not window then
        self:Print("Settings aren't available yet. Try again after entering the world.")
        return
    end
    if window:IsShown() and not index and not keepOpen then
        window:Hide()
        return
    end
    if index then window.selected = index end
    window:Show()
    window:Raise()
end
