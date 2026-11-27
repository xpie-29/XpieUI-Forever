-- Choice.lua  (XpieUI-Forever, Quest module)
-- XpieUI's quest module can't run beside the quest-window addons listed in
-- Quest.lua (INCOMPATIBLE). When one of them is on at login, this asks which
-- to keep, with a button for XpieUI and one for each that's running:
--   Use XpieUI      the others are turned off (every character), UI reloads
--   Use <addon>     XpieUI's quest module turns itself off (and any other
--                   listed addon), reloading only if something else was running
-- The window can't be dismissed any other way (no Esc, no close button).
--
-- Not a StaticPopup: addon popups break Forever's controller UI. The window
-- reads the controller itself (EnableGamePadButton) and draws Blizzard's gold
-- arrow; it never joins Blizzard's gamepad navigation. Keyboard: Left/Right
-- or Tab move, Enter or Space pick. Hidden during combat, back after it.

local core = XpieUI
local plugin = core.questPlugin

local WIDTH, HEIGHT = 520, 190
local BUTTON_WIDTH, BUTTON_HEIGHT = 200, 36

local BUTTON_GAP = 20

local frame, pointer, buttons
local choices            -- [index] = nil for XpieUI, else the addon's name
local focus = 1          -- 1 = XpieUI, then the running incompatible addons
local usingPad = false

local function UpdateFocus()
    for i, button in ipairs(buttons) do
        if i == focus then button:LockHighlight() else button:UnlockHighlight() end
    end
    if usingPad then
        pointer:ClearAllPoints()
        pointer:SetPoint("RIGHT", buttons[focus], "LEFT", -12, 0)
        pointer:Show()
    else
        pointer:Hide()
    end
end

local function Pick(index)
    if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
    frame:Hide()
    frame.done = true
    if index == 1 then plugin:UseXpieUI() else plugin:UseOtherAddon(choices[index]) end
end

local function Move(delta)
    local index = focus + delta
    if buttons[index] then
        focus = index
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
    end
    UpdateFocus()
end

-- true when the key/button was ours (the rest go on to the game).
local function HandleInput(key)
    if key == "LEFT" or key == "PADDLEFT" or (key == "TAB" and IsShiftKeyDown()) then
        Move(-1)
    elseif key == "RIGHT" or key == "PADDRIGHT" or key == "TAB" then
        Move(1)
    elseif key == "ENTER" or key == "SPACE" or key == "PAD1" then
        Pick(focus)
    else
        return false
    end
    return true
end

local function CreateButton(index, text, count)
    local ok, button = pcall(CreateFrame, "Button", nil, frame, "MainMenuFrameButtonTemplate")
    if not ok then button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate") end
    button:SetText(text)
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:ClearAllPoints()
    local x = (index - (count + 1) / 2) * (BUTTON_WIDTH + BUTTON_GAP)
    button:SetPoint("BOTTOM", frame, "BOTTOM", x, 24)
    button:SetScript("OnClick", function() Pick(index) end)
    button:HookScript("OnEnter", function() focus = index; UpdateFocus() end)
    return button
end

local function CreateChoiceWindow()
    frame = CreateFrame("Frame", "XpieUIForeverQuestChoice", UIParent)
    local others = plugin:LoadedOthers()
    choices = { false }
    for _, name in ipairs(others) do choices[#choices + 1] = name end
    local count = #choices
    local width = math.max(WIDTH, count * (BUTTON_WIDTH + BUTTON_GAP) + 40)
    frame:SetSize(width, HEIGHT)
    frame:SetPoint("CENTER", 0, 120)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:Hide()

    -- The XpieUI settings window's look: Edit Mode's "Dialog" border.
    local ok, border = pcall(CreateFrame, "Frame", nil, frame, "DialogBorderTranslucentTemplate")
    if not ok then
        border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        border:SetAllPoints()
        border:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        border:SetBackdropColor(0, 0, 0, 0.9)
    end

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("XpieUI Forever: Quest Module")

    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOP", title, "BOTTOM", 0, -14)
    text:SetWidth(width - 60)
    local other = plugin:JoinNames(others)
    text:SetText(("XpieUI's Quest module isn't compatible with %s. Which one would you like to use for quests and dialogue?"):format(other))

    local note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOP", text, "BOTTOM", 0, -8)
    note:SetWidth(width - 60)
    note:SetText(("XpieUI turns %s off and reloads. You can switch later on the Quest Windows page of /xui."):format(plugin:JoinNames(others, "and")))

    buttons = { CreateButton(1, "Use XpieUI", count) }
    for i = 2, count do buttons[i] = CreateButton(i, "Use " .. choices[i], count) end
    pointer = core.CreateGoldPointer(frame)
    pointer:SetFrameLevel(frame:GetFrameLevel() + 20)

    frame:SetScript("OnShow", function(self)
        usingPad = core.IsGamepadActive and core.IsGamepadActive() or false
        focus = 1
        UpdateFocus()
        if self.EnableGamePadButton then self:EnableGamePadButton(true) end
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(true)
    end)
    frame:SetScript("OnHide", function(self)
        if self.EnableGamePadButton then self:EnableGamePadButton(false) end
        self:EnableKeyboard(false)
        pointer:Hide()
    end)
    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not HandleInput(key))
    end)
    frame:SetScript("OnGamePadButtonDown", function(self, button)
        if InCombatLockdown() then return end
        if not usingPad then usingPad = true; UpdateFocus() end
        self:SetPropagateKeyboardInput(not HandleInput(button))
    end)

    -- Out of the way during combat, back once it ends.
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(self, event)
        if self.done then return end
        if event == "PLAYER_REGEN_DISABLED" then
            if self:IsShown() then self.waiting = true; self:Hide() end
        elseif self.waiting then
            self.waiting = nil
            self:Show()
        end
    end)
end

-- Called at login while an incompatible addon is loaded and the module is on.
-- A short wait lets the loading screen and that addon's own start-up finish.
function plugin:ShowChoice()
    C_Timer.After(2, function()
        if not (plugin.active and plugin:OtherAddonLoaded()) then return end
        if not frame then CreateChoiceWindow() end
        if frame.done then return end
        if InCombatLockdown() then
            frame.waiting = true
        else
            frame:Show()
        end
    end)
end
