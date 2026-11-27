-- HideUI.lua  (XpieUI-Forever, Quest module)
-- Hide UI While Talking: while a quest, gossip or book window is open, the
-- rest of the interface fades out, leaving the world, the speaker and the
-- window.
--
-- Every child of UIParent that's showing when the window opens fades to alpha
-- 0. Frames that open later (bags, a merchant from a gossip option) are left
-- alone. Alpha only: nothing is hidden or re-parented (SetUIVisibility(false)
-- would take Blizzard's quest windows with it).
--
-- Kept visible: the quest windows and their model, tooltips, popups,
-- Blizzard's controller cursor and prompts, XpieUI's own windows, Spoken, and
-- a chat window while you're typing in it. The minimap is moved off-screen
-- instead (it draws blips that ignore alpha). Combat brings everything back
-- at once; it fades again if the window is still open afterwards.
-- Ported from XpieHUD_Core/QuestDialog.lua (FadeUI, RestoreUI, minimap).

local core = XpieUI
local plugin = core.questPlugin

local WINDOWS = { "QuestFrame", "GossipFrame", "ItemTextFrame" }
local KEEP = {
    "QuestFrame", "GossipFrame", "ItemTextFrame", "QuestModelScene",
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip",
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
    "SmartNavigation", "SoftCursor", "GamepadScrollBarHint", "GamepadPersistentInputLegend",
    "GamepadItemPickupCursor", "GamepadRadial", "GamepadReticle",
}
local KEEP_PREFIXES = { "XpieUIForever", "Spoken" }
local RESTORE_DELAY = 0.15   -- gossip -> quest: one window closes before the next opens
local FADE_TIME = 0.3

local keep              -- [frame] = true, built on first use
local faded = {}        -- [frame] = alpha to restore
local fading = {}       -- [frame] = { from, to } while animating
local fadeTime = 0
local isFaded = false
local inCombat = false
local restoreToken = 0
local driver = CreateFrame("Frame")

local function BuildKeep()
    keep = {}
    for _, name in ipairs(KEEP) do
        local frame = _G[name]
        if frame then keep[frame] = true end
    end
end

local function Keep(frame)
    if keep[frame] then return true end
    local name = frame:GetName()
    if name then
        for _, prefix in ipairs(KEEP_PREFIXES) do
            if name:sub(1, #prefix) == prefix then return true end
        end
    end
    local spoken = _G.Spoken
    if spoken and spoken.GetPlayerFrame then
        local ok, player = pcall(spoken.GetPlayerFrame, spoken)
        if ok and player == frame then return true end
    end
    -- A chat window being typed in stays (its edit box is checked too).
    local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if editBox and (editBox == frame or editBox:GetParent() == frame or editBox.chatFrame == frame) then
        return true
    end
    return false
end

local function AnyWindowShown()
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame and frame:IsShown() then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Alpha animation
-- ---------------------------------------------------------------------------
local function Animate(elapsed)
    fadeTime = fadeTime + elapsed
    local t = math.min(fadeTime / FADE_TIME, 1)
    for frame, step in pairs(fading) do
        if not frame:IsForbidden() then frame:SetAlpha(step.from + (step.to - step.from) * t) end
    end
    if t >= 1 then
        wipe(fading)
        driver:SetScript("OnUpdate", nil)
    end
end

local function StartAnimation()
    fadeTime = 0
    driver:SetScript("OnUpdate", function(_, elapsed) Animate(elapsed) end)
end

-- ---------------------------------------------------------------------------
-- Minimap: moved off-screen and back. Never Hide() it: that runs Blizzard's
-- minimap scripts as XpieUI and taints them.
-- ---------------------------------------------------------------------------
local minimapSaved
local movingMinimap = false
local minimapHooked = false

local function SaveMinimapPoints()
    local points = {}
    for i = 1, Minimap:GetNumPoints() do points[i] = { Minimap:GetPoint(i) } end
    return points
end

local function MoveMinimapAway()
    movingMinimap = true
    Minimap:SetClampedToScreen(false)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -4000, -4000)
    movingMinimap = false
end

local function SetMinimapAway(away)
    if not Minimap or Minimap:IsForbidden() then return end
    if InCombatLockdown() and Minimap:IsProtected() then return end
    if away and not minimapSaved then
        if not minimapHooked then
            minimapHooked = true
            -- Re-anchored while away (Edit Mode, another addon): remember the
            -- new spot and send it away again.
            hooksecurefunc(Minimap, "SetPoint", function()
                if movingMinimap or not minimapSaved then return end
                minimapSaved.points = SaveMinimapPoints()
                MoveMinimapAway()
            end)
        end
        minimapSaved = { points = SaveMinimapPoints(), clamped = Minimap:IsClampedToScreen() }
        MoveMinimapAway()
    elseif not away and minimapSaved then
        local saved = minimapSaved
        minimapSaved = nil
        movingMinimap = true
        Minimap:ClearAllPoints()
        for _, point in ipairs(saved.points) do Minimap:SetPoint(unpack(point)) end
        Minimap:SetClampedToScreen(saved.clamped)
        movingMinimap = false
    end
end

-- ---------------------------------------------------------------------------
-- Fade / restore
-- ---------------------------------------------------------------------------
local function FadeUI()
    if not keep then BuildKeep() end
    for _, frame in ipairs({ UIParent:GetChildren() }) do
        -- IsForbidden first: it's the only call a forbidden (Blizzard-locked)
        -- frame accepts from addon code.
        if not frame:IsForbidden() and not faded[frame] and frame:IsShown() and not Keep(frame) then
            local alpha = frame:GetAlpha()
            -- Still fading back in from the last window: its real alpha is
            -- where that fade was heading.
            local original = fading[frame] and fading[frame].to or alpha
            if alpha > 0 or original > 0 then
                faded[frame] = original
                fading[frame] = { from = alpha, to = 0 }
            end
        end
    end
    StartAnimation()
    SetMinimapAway(true)
    isFaded = true
end

-- instant: combat, or the setting turned off.
local function RestoreUI(instant)
    for frame, alpha in pairs(faded) do
        if frame:IsForbidden() then
            fading[frame] = nil   -- locked since we faded it: leave it be
        else
            -- Something else changed the alpha while we were faded: keep theirs.
            local current = fading[frame] and 0 or frame:GetAlpha()
            if current == 0 then
                if instant then
                    fading[frame] = nil
                    frame:SetAlpha(alpha)
                else
                    fading[frame] = { from = frame:GetAlpha(), to = alpha }
                end
            else
                fading[frame] = nil
            end
        end
    end
    wipe(faded)
    if instant then
        wipe(fading)
        driver:SetScript("OnUpdate", nil)
    else
        StartAnimation()
    end
    SetMinimapAway(false)
    isFaded = false
end

-- Bring back the chat window you started typing in.
local function ShowChatWhileTyping()
    if not isFaded then return end
    local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if not editBox then return end
    for frame, alpha in pairs(faded) do
        if Keep(frame) then
            fading[frame] = nil
            frame:SetAlpha(alpha)
            faded[frame] = nil
        end
    end
end

local function Update()
    local want = plugin:IsLive() and plugin.db.hideUI and AnyWindowShown()
        and not inCombat and not InCombatLockdown()
    if want and not isFaded then
        FadeUI()
    elseif not want and isFaded then
        RestoreUI(inCombat or InCombatLockdown() or not plugin.db.hideUI)
    end
end
plugin.UpdateHideUI = Update

-- Run on the next frame: the window's OnShow fires inside Blizzard's panel
-- manager (ShowUIPanel), and nothing of ours should run inside that.
local function OnWindowShow()
    restoreToken = restoreToken + 1
    C_Timer.After(0, Update)
end

local function OnWindowHide()
    restoreToken = restoreToken + 1
    local token = restoreToken
    C_Timer.After(RESTORE_DELAY, function()
        if token == restoreToken then Update() end
    end)
end

function plugin:InitHideUI()
    if self.hideUIReady or not self:IsLive() then return end
    self.hideUIReady = true
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame then
            frame:HookScript("OnShow", OnWindowShow)
            frame:HookScript("OnHide", OnWindowHide)
        end
    end
    if ChatEdit_ActivateChat then hooksecurefunc("ChatEdit_ActivateChat", ShowChatWhileTyping) end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        -- InCombatLockdown() can still be false during REGEN_DISABLED.
        inCombat = event == "PLAYER_REGEN_DISABLED"
        Update()
    end)
    Update()
end
