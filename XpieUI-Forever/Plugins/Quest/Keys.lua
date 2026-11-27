-- Keys.lua  (XpieUI-Forever, Quest module)
-- Keyboard controls for the quest, gossip and book windows, keyboard & mouse
-- only. While Forever's controller UI is on, none of this runs: Blizzard's
-- own controller support handles the windows.
--
--   W / S, Up / Down       move the highlight through the gossip list, the
--                          quest greeting list or the reward choices
--   A / D, Left / Right    reward choices: move across; book: turn the page
--   Space                  click the highlighted row; with none, Accept /
--                          Continue / Complete, or the book's next page
--   1-9, 0, Shift+1-9      pick row 1-19 directly
--   Esc                    Blizzard's own close
-- Keys with nothing to do pass through to the game (so you can still walk
-- off when there's no list). Never in combat: SetPropagateKeyboardInput is
-- restricted then, and the key frame is hidden.
--
-- PvP quests and quests that cost gold confirm through a StaticPopup: Space
-- leaves those to a click, so the popup system is never driven by addon code.
--
-- The highlight is Blizzard's own (the row's UI-QuestTitleHighlight, the
-- reward's selection), with XpieUI's gold arrow beside list rows.
-- Ported from XpieHUD_Core/QuestDialog.lua (keys, gossip selection).

local core = XpieUI
local plugin = core.questPlugin

local MAX_CHOICES = 19
local REWARD_COLUMNS = 2   -- Blizzard lays choices out in pairs

local keyFrame, pointer
local focus           -- index into the current list, nil = nothing highlighted
local lockedRow       -- the row we called LockHighlight on
local inCombat = false

-- ---------------------------------------------------------------------------
-- Mode
-- ---------------------------------------------------------------------------
local function GamepadUI()
    if InputUtil and InputUtil.IsGamepadUIEnabled then
        local ok, on = pcall(InputUtil.IsGamepadUIEnabled)
        return ok and on and true or false
    end
    return false
end

-- Keyboard & mouse mode with the window module running.
function plugin:KeyboardMode()
    return self:IsLive() and not GamepadUI()
end

local function ControlsOn()
    return plugin:KeyboardMode() and plugin.db.keyboard and not inCombat and not InCombatLockdown()
end
plugin.KeyboardControlsOn = ControlsOn

-- ---------------------------------------------------------------------------
-- What's on screen
-- ---------------------------------------------------------------------------
local function ClickIfUsable(button)
    if button and button:IsVisible() and button:IsEnabled() then
        button:Click("LeftButton")
        return true
    end
    return false
end

local function GossipScrollBox()
    local panel = GossipFrame and GossipFrame.GreetingPanel
    return panel and panel.ScrollBox
end

-- Callbacks on the gossip list's ScrollBox (keys and badges), registered only
-- in keyboard & mouse mode, so Blizzard's own list is untouched under the
-- controller UI. Synced when the input mode changes and when the window opens.
local gossipCallbacks = {}   -- [owner] = fn
local gossipRegistered = false

local function GossipScrollEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnDataRangeChanged
end

local function SyncGossipCallbacks()
    local box, event = GossipScrollBox(), GossipScrollEvent()
    if not (box and event and box.RegisterCallback and box.UnregisterCallback) then return end
    local want = plugin:KeyboardMode()
    if want == gossipRegistered then return end
    gossipRegistered = want
    for owner, fn in pairs(gossipCallbacks) do
        if want then box:RegisterCallback(event, fn, owner) else box:UnregisterCallback(event, owner) end
    end
end

function plugin:AddGossipScrollCallback(owner, fn)
    gossipCallbacks[owner] = fn
    local box, event = GossipScrollBox(), GossipScrollEvent()
    if gossipRegistered and box and event then box:RegisterCallback(event, fn, owner) end
    SyncGossipCallbacks()
end

-- The gossip list in Blizzard's order (available quests, active quests,
-- options), as element data with .index.
local function GossipEntries()
    local list = {}
    local scrollBox = GossipScrollBox()
    local provider = scrollBox and scrollBox:GetDataProvider()
    if not provider then return list end
    for _, data in provider:Enumerate() do
        if data.index and data.info then list[#list + 1] = data end
    end
    table.sort(list, function(a, b) return a.index < b.index end)
    return list
end

local function SelectGossip(data)
    if data.buttonType == GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST then
        C_GossipInfo.SelectAvailableQuest(data.info.questID)
    elseif data.buttonType == GOSSIP_BUTTON_TYPE_ACTIVE_QUEST then
        C_GossipInfo.SelectActiveQuest(data.info.questID)
    elseif data.buttonType == GOSSIP_BUTTON_TYPE_OPTION then
        C_GossipInfo.SelectOptionByIndex(data.info.orderIndex)
    else
        return false
    end
    return true
end

-- Quest greeting list: active quests first, then available (Blizzard's layout).
local function GreetingButtons()
    local list = {}
    local pool = QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool
    if not pool then return list end
    for button in pool:EnumerateActive() do
        if button:IsShown() then list[#list + 1] = button end
    end
    table.sort(list, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive == 1 end
        return a:GetID() < b:GetID()
    end)
    return list
end

local function RewardChoiceButtons()
    local list = {}
    local rewards = QuestInfoRewardsFrame
    if not (rewards and rewards.RewardButtons and rewards:IsVisible()) then return list end
    for _, button in ipairs(rewards.RewardButtons) do
        if button:IsShown() and button.type == "choice" then list[#list + 1] = button end
    end
    table.sort(list, function(a, b) return a:GetID() < b:GetID() end)
    return list
end

-- Which page is up: "gossip", "greeting", "detail", "progress", "reward",
-- "book" or nil.
local function Context()
    if GossipFrame and GossipFrame:IsShown() then return "gossip" end
    if QuestFrame and QuestFrame:IsShown() then
        if QuestFrameGreetingPanel:IsShown() then return "greeting" end
        if QuestFrameDetailPanel:IsShown() then return "detail" end
        if QuestFrameProgressPanel:IsShown() then return "progress" end
        if QuestFrameRewardPanel:IsShown() then return "reward" end
    end
    if ItemTextFrame and ItemTextFrame:IsShown() then return "book" end
end

-- The numbered rows of the current page, for badges and keys.
-- Each: { frame = row or nil (scrolled out of view), pick = function }.
function plugin:GetChoices()
    local context, list = Context(), {}
    if context == "gossip" then
        local scrollBox = GossipScrollBox()
        for _, data in ipairs(GossipEntries()) do
            list[#list + 1] = {
                frame = scrollBox:FindFrame(data), data = data,
                isQuest = data.buttonType ~= GOSSIP_BUTTON_TYPE_OPTION,
                pick = function() return SelectGossip(data) end,
            }
        end
    elseif context == "greeting" then
        for _, button in ipairs(GreetingButtons()) do
            list[#list + 1] = { frame = button, isQuest = true, pick = function() return ClickIfUsable(button) end }
        end
    elseif context == "reward" then
        for _, button in ipairs(RewardChoiceButtons()) do
            list[#list + 1] = { frame = button, isReward = true, pick = function() return ClickIfUsable(button) end }
        end
    end
    return list, context
end

-- ---------------------------------------------------------------------------
-- Highlight
-- ---------------------------------------------------------------------------
local function ClearHighlight()
    if lockedRow then lockedRow:UnlockHighlight(); lockedRow = nil end
    if pointer then pointer:Hide() end
end

local function ShowHighlight()
    ClearHighlight()
    if not focus then return end
    local choices, context = plugin:GetChoices()
    local choice = choices[focus]
    if not choice then focus = nil; return end

    if context == "reward" then
        -- The reward's own selection is the highlight: picking it selects it.
        return
    end
    if context == "gossip" and not choice.frame then
        -- Scrolled out of view: bring it in, the frame exists after that.
        local scrollBox = GossipScrollBox()
        if scrollBox and scrollBox.ScrollToElementData then
            scrollBox:ScrollToElementData(choice.data)
            choice.frame = scrollBox:FindFrame(choice.data)
        end
    end
    local row = choice.frame
    if not row then return end
    row:LockHighlight()
    lockedRow = row
    local window = row:GetParent()
    while window and window:GetParent() ~= UIParent do window = window:GetParent() end
    if not pointer then pointer = core.CreateGoldPointer(UIParent) end
    if window then
        pointer:SetParent(window)
        pointer:SetFrameStrata(window:GetFrameStrata())
        pointer:SetFrameLevel(window:GetFrameLevel() + 60)
    end
    pointer:ClearAllPoints()
    pointer:SetPoint("RIGHT", row, "LEFT", 2, 0)
    pointer:Show()
end

-- A page was built or rebuilt: nothing highlighted yet.
function plugin:ResetKeyFocus()
    focus = nil
    ClearHighlight()
end

local function MoveFocus(delta)
    local choices, context = plugin:GetChoices()
    local count = #choices
    if count == 0 then return false end
    if not focus then
        -- First press: the first row (or the last, going up).
        if context == "reward" then
            local selected = QuestInfoFrame and QuestInfoFrame.itemChoice
            focus = (selected and selected > 0 and selected <= count) and selected or 1
            if not (selected and selected > 0) then choices[focus].pick() end
            return true
        end
        focus = delta > 0 and 1 or count
    else
        local index = focus + delta
        if index < 1 or index > count then return true end   -- at the end: stay
        focus = index
    end
    if context == "reward" then
        choices[focus].pick()
    else
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
        ShowHighlight()
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------
local function PickNumber(number)
    local choice = plugin:GetChoices()[number]
    return choice and choice.pick() or false
end

local function HandleSpace()
    local choices, context = plugin:GetChoices()
    if focus and choices[focus] and context ~= "reward" then
        return choices[focus].pick()
    end
    if context == "detail" then
        if QuestFlagsPVP() then return false end   -- PvP confirm: click it
        return ClickIfUsable(QuestFrameAcceptButton)
    elseif context == "progress" then
        return ClickIfUsable(QuestFrameCompleteButton)
    elseif context == "reward" then
        local money = GetQuestMoneyToGet()
        if money and money > 0 then return false end   -- gold-cost confirm: click it
        return ClickIfUsable(QuestFrameCompleteQuestButton)
    elseif context == "book" then
        return ClickIfUsable(ItemTextNextPageButton)
    end
    return false
end

local function KeyToNumber(key)
    local digit = tonumber(key) or tonumber(key:match("^NUMPAD(%d)$") or "")
    if not digit then return nil end
    if IsShiftKeyDown() then return digit >= 1 and 10 + digit or nil end
    return digit == 0 and 10 or digit
end

local UP = { W = true, UP = true }
local DOWN = { S = true, DOWN = true }
local LEFT = { A = true, LEFT = true }
local RIGHT = { D = true, RIGHT = true }

-- true when the key was ours.
local function HandleKey(key)
    if IsControlKeyDown() or IsAltKeyDown() then return false end
    if key == "SPACE" then
        if IsShiftKeyDown() then return false end
        return HandleSpace()
    end
    local number = KeyToNumber(key)
    if number then
        return number <= MAX_CHOICES and PickNumber(number) or false
    end
    if IsShiftKeyDown() then return false end
    local context = Context()
    if UP[key] or DOWN[key] then
        local step = context == "reward" and REWARD_COLUMNS or 1
        return MoveFocus(UP[key] and -step or step)
    elseif LEFT[key] or RIGHT[key] then
        if context == "reward" then
            return MoveFocus(LEFT[key] and -1 or 1)
        elseif context == "book" then
            return ClickIfUsable(LEFT[key] and ItemTextPrevPageButton or ItemTextNextPageButton)
        end
    end
    return false   -- Esc and everything else: Blizzard / the game
end

local function CreateKeyFrame()
    keyFrame = CreateFrame("Frame", nil, UIParent)
    keyFrame:Hide()
    keyFrame:EnableKeyboard(true)
    -- Set only when allowed; OnKeyDown sets it for every key anyway.
    if not InCombatLockdown() then keyFrame:SetPropagateKeyboardInput(true) end
    keyFrame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end   -- hidden on REGEN_DISABLED; safety net
        local handled = false
        local ok, result = pcall(HandleKey, key)
        if ok then handled = result and true or false else geterrorhandler()(result) end
        self:SetPropagateKeyboardInput(not handled)
    end)
    -- Back to pass-through after every key, so a key handled just before
    -- combat can't leave the frame swallowing keys while the flag is locked.
    keyFrame:SetScript("OnKeyUp", function(self)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)
end

-- ---------------------------------------------------------------------------
-- Tooltips at the cursor (keyboard & mouse, while a window is open). With
-- the UI faded, tooltips in the screen corner feel detached.
-- ---------------------------------------------------------------------------
local function AnyWindowShown()
    return Context() ~= nil
end

local function MoveOpenTooltip()
    local tip = GameTooltip
    if not (tip and tip:IsShown() and tip.SetAnchorType) or tip:IsForbidden() then return end
    if tip:GetOwner() ~= UIParent or tip:GetAnchorType() ~= "ANCHOR_NONE" then return end
    tip:ClearAllPoints()
    tip:SetAnchorType("ANCHOR_CURSOR")
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local function Update()
    local open = AnyWindowShown()
    if keyFrame then keyFrame:SetShown(open and ControlsOn()) end
    if not open or not ControlsOn() then plugin:ResetKeyFocus() end
    if plugin.RefreshBadges then plugin:RefreshBadges() end
end
plugin.UpdateKeys = Update

function plugin:InitKeys()
    if self.keysReady or not self:IsLive() then return end
    self.keysReady = true
    CreateKeyFrame()

    for _, name in ipairs({ "QuestFrame", "GossipFrame", "ItemTextFrame" }) do
        local frame = _G[name]
        if frame then
            frame:HookScript("OnShow", function()
                plugin:ResetKeyFocus()
                C_Timer.After(0, Update)   -- out of Blizzard's ShowUIPanel
                if plugin:KeyboardMode() then MoveOpenTooltip() end
            end)
            frame:HookScript("OnHide", function() C_Timer.After(0.15, Update) end)
        end
    end
    -- Each page / list rebuild starts with nothing highlighted.
    for _, panel in ipairs({ QuestFrameGreetingPanel, QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel }) do
        if panel then panel:HookScript("OnShow", function() plugin:ResetKeyFocus() end) end
    end
    if GossipFrame and GossipFrame.Update then
        hooksecurefunc(GossipFrame, "Update", function() plugin:ResetKeyFocus() end)
    end
    -- The gossip list scrolled or re-laid out: put the highlight back on
    -- whichever recycled row now shows the focused entry.
    plugin:AddGossipScrollCallback(plugin, function()
        if focus and Context() == "gossip" then ShowHighlight() end
    end)
    if GossipFrame then GossipFrame:HookScript("OnShow", SyncGossipCallbacks) end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not (tooltip and tooltip.SetOwner) or tooltip:IsForbidden() then return end
        if parent and parent.IsForbidden and parent:IsForbidden() then return end
        if plugin:KeyboardMode() and AnyWindowShown() then
            tooltip:SetOwner(parent, "ANCHOR_CURSOR")
        end
    end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    pcall(events.RegisterEvent, events, "INPUT_DEVICE_INTERFACE_TRANSITION")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true   -- InCombatLockdown() can still be false here
            if keyFrame then keyFrame:Hide() end
            plugin:ResetKeyFocus()
            if plugin.RefreshBadges then plugin:RefreshBadges() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            Update()
        else
            -- switched between controller and keyboard
            C_Timer.After(0, function() SyncGossipCallbacks(); Update() end)
        end
    end)
    Update()
end
