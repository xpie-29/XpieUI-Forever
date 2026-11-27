-- Choice.lua  (XpieUI-Forever, Quest module)
-- XpieUI's quest module and DialogueUI can't run together. When both are on at
-- login, this asks which one to keep:
--   Use XpieUI      DialogueUI is turned off (every character), UI reloads
--   Use DialogueUI  XpieUI's quest module turns itself off, no reload
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

local frame, pointer, buttons
local focus = 1          -- 1 = XpieUI, 2 = DialogueUI
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
    if index == 1 then plugin:UseXpieUI() else plugin:UseDialogueUI() end
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

local function CreateButton(index, text)
    local ok, button = pcall(CreateFrame, "Button", nil, frame, "MainMenuFrameButtonTemplate")
    if not ok then button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate") end
    button:SetText(text)
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:ClearAllPoints()
    button:SetPoint("BOTTOM", frame, "BOTTOM", (index == 1 and -1 or 1) * (BUTTON_WIDTH / 2 + 10), 24)
    button:SetScript("OnClick", function() Pick(index) end)
    button:HookScript("OnEnter", function() focus = index; UpdateFocus() end)
    return button
end

local function CreateChoiceWindow()
    frame = CreateFrame("Frame", "XpieUIForeverQuestChoice", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
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
    text:SetWidth(WIDTH - 60)
    text:SetText("XpieUI's Quest module isn't compatible with DialogueUI. Which one would you like to use for quests and dialogue?")

    local note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOP", text, "BOTTOM", 0, -8)
    note:SetWidth(WIDTH - 60)
    note:SetText("XpieUI turns DialogueUI off and reloads. You can switch later on the Quest Windows page of /xui.")

    buttons = { CreateButton(1, "Use XpieUI"), CreateButton(2, "Use DialogueUI") }
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

-- Called at login while DialogueUI is loaded and the module is on. A short
-- wait lets the loading screen and DialogueUI's own start-up finish.
function plugin:ShowChoice()
    C_Timer.After(2, function()
        if not (plugin.active and plugin:DialogueUILoaded()) then return end
        if not frame then CreateChoiceWindow() end
        if frame.done then return end
        if InCombatLockdown() then
            frame.waiting = true
        else
            frame:Show()
        end
    end)
end
