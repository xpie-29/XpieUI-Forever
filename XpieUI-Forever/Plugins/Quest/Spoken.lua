-- Spoken.lua  (XpieUI-Forever, Quest module)
-- Spoken Integration: Spoken's controls on Blizzard's quest, gossip and book
-- windows, through Spoken's public API only (Spoken/API.lua, API_VERSION 1).
-- Every optional call is checked for first, as Spoken's docs ask.
--
--   Controls    Spoken's own row (Play/Stop, Previous, Next, Report) in the
--               window's title bar, left of the close button
--
-- Off (or Spoken not installed): nothing is drawn and Spoken works exactly
-- as it does on its own.

local core = XpieUI
local plugin = core.questPlugin

local WINDOWS = { "QuestFrame", "GossipFrame", "ItemTextFrame" }
local API_VERSION = 1

local rows = {}          -- [window] = Spoken's row
local hooked = false
local callbacksSet = false

-- Spoken, when it's installed and speaks our version of its API.
local function Api()
    local spoken = _G.Spoken
    if type(spoken) == "table" and type(spoken.IsCompatible) == "function" and spoken:IsCompatible(API_VERSION) then
        return spoken
    end
end

function plugin:SpokenAvailable()
    local spoken = Api()
    return spoken ~= nil and type(spoken.CreateDialogueUIRow) == "function"
end

local function On()
    return plugin:IsLive() and plugin.db.spoken and plugin:SpokenAvailable()
end

local function Words()
    local spoken = Api()
    local ok, words = pcall(function() return spoken.Words and spoken:Words() end)
    return ok and type(words) == "table" and words or {}
end

local function Call(method, ...)
    local spoken = Api()
    if spoken and type(spoken[method]) == "function" then
        local ok, result = pcall(spoken[method], spoken, ...)
        if ok then return result end
    end
end

-- The line at the head of Spoken's queue, and whether it's speaking now
-- (not paused or held by a gate).
local function Current()
    return Call("GetCurrent")
end

local function Speaking()
    return Call("GetNowPlaying") ~= nil and not Call("IsPaused")
end

-- The line's own Report action, as the module that queued it describes it.
local function ReportAction(clip)
    if not clip or Call("AreReportButtonsHidden") then return nil end
    local actions = type(clip.present) == "table" and clip.present.actions
    for _, action in ipairs(type(actions) == "table" and actions or {}) do
        if type(action) == "table" and action.id == "report" and type(action.onClick) == "function" then
            local visible = true
            if type(action.visible) == "function" then
                local ok, shown = pcall(action.visible)
                visible = ok and shown and true or false
            end
            return visible and action or nil
        end
    end
end

local function SetEnabled(button, on)
    if (button:IsEnabled() and true or false) ~= on then
        if on then button:Enable() else button:Disable() end
    end
end

local function CloseButton(window)
    return window.CloseButton or _G[window:GetName() .. "CloseButton"]
end

local function Tooltip()
    return GameTooltip
end

local Refresh

local function MakeRow(window)
    local spoken = Api()
    local ok, row = pcall(spoken.CreateDialogueUIRow, spoken, window, Tooltip, true)
    if not ok or type(row) ~= "table" or not row.frame then return nil end
    local words = Words()

    row:SetTip(row.play, function(tip)
        tip:SetText(Speaking() and (words.STOP or "Stop") or (words.PLAY or "Play"))
    end)
    row.play:SetScript("OnClick", function()
        Call("TogglePause")
        Refresh()
        row:RefreshTip(row.play)
    end)

    if row.report then
        row:SetTip(row.report, function(tip)
            local action = ReportAction(Current())
            if action and type(action.tooltip) == "function" then
                pcall(action.tooltip, tip)
            else
                tip:SetText(words.OPT_REPORT_PROBLEM or "Report a Problem")
            end
        end)
        row.report:SetScript("OnClick", function()
            local clip = Current()
            local action = ReportAction(clip)
            if action then pcall(action.onClick, clip) end
        end)
    end
    return row
end

local function RefreshWindow(window)
    local row = rows[window]
    if not (On() and window:IsShown()) then
        if row and row.frame:IsShown() then
            row.frame:Hide()
            row:HideTips()
        end
        return
    end
    if not row then
        row = MakeRow(window)
        if not row then return end
        rows[window] = row
    end

    local clip = Current()
    local speaking = Speaking()
    SetEnabled(row.play, clip ~= nil)
    local state = speaking and "stop" or "play"
    if row.play.state ~= state then
        row.play:SetState(state)
        row.play.state = state
    end
    SetEnabled(row.previous, Call("CanPrevious") and true or false)
    SetEnabled(row.skip, clip ~= nil)

    -- Right to left from the close button: Next, Previous, Play, Report.
    local buttons = { row.skip, row.previous, row.play }
    local showReport = row.report and ReportAction(clip) ~= nil
    if row.report then
        row.report:SetShown(showReport and true or false)
        if showReport then buttons[#buttons + 1] = row.report end
    end
    row:Place(buttons, CloseButton(window))
    row.frame:Show()
    for _, button in ipairs(buttons) do row:RefreshTip(button) end
end

function Refresh()
    for _, name in ipairs(WINDOWS) do
        local window = _G[name]
        if window then RefreshWindow(window) end
    end
end
plugin.UpdateSpoken = function() Refresh() end

function plugin:InitSpoken()
    if not self:IsLive() or not self:SpokenAvailable() then return end
    if not hooked then
        hooked = true
        for _, name in ipairs(WINDOWS) do
            local window = _G[name]
            if window then
                -- Next frame: after Blizzard has filled the window.
                window:HookScript("OnShow", function() C_Timer.After(0, Refresh) end)
                window:HookScript("OnHide", function() RefreshWindow(window) end)
            end
        end
    end
    if not callbacksSet and type(Api().RegisterCallback) == "function" then
        callbacksSet = true
        for _, event in ipairs({ "CLIP_STARTED", "CLIP_STOPPED", "AUDIO_CHANGED", "REPORT_SETTINGS_CHANGED" }) do
            pcall(Api().RegisterCallback, Api(), event, Refresh)
        end
    end
    Refresh()
end
