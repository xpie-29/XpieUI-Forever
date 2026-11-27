-- Position.lua  (XpieUI-Forever, Quest module)
-- One shared, saved position for Blizzard's quest, gossip and book windows.
-- Move one and they all open there.
--
-- Blizzard's panel manager still opens and closes the windows. We only move
-- them afterwards: a post-hook on each window's SetPoint (and OnShow) puts the
-- window's top-left corner on the saved point. UIPanelWindows is never
-- written and ShowUIPanel / HideUIPanel are never called. (The probe build
-- moved QuestFrame this way under Forever's gamepad UI with no taint.)
--
-- Moving:
--   mouse        drag a window's title bar
--   controller   Quest Windows page > Move Windows: a stand-in window the
--                D-pad moves (hold to speed up), A saves, B cancels. Keyboard
--                arrows / Enter / Esc and mouse drag work there too.
-- The point is kept in UIParent units, clamped to the screen when applied.

local core = XpieUI
local plugin = core.questPlugin

local WINDOWS = { "QuestFrame", "GossipFrame", "ItemTextFrame" }
local HANDLE_LEFT, HANDLE_RIGHT, HANDLE_HEIGHT = 60, -28, 22   -- title bar, between portrait and close

local positioning = false   -- re-entry guard for the SetPoint post-hook
local dragging = {}

-- UIParent units per unit of `frame` (UI scale and the frame's own scale).
local function Ratio(frame)
    return frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function Clamp(left, top, width, height)
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    left = math.max(0, math.min(left, screenW - width))
    top = math.max(height, math.min(top, screenH))
    return left, top
end

local function Apply(frame)
    local point = plugin.db.point
    if positioning or dragging[frame] or not point or not plugin:IsLive() then return end
    local ratio = Ratio(frame)
    local left, top = Clamp(point[1], point[2], frame:GetWidth() * ratio, frame:GetHeight() * ratio)
    positioning = true
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / ratio, top / ratio)
    positioning = false
end

local function ApplyShown()
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame and frame:IsShown() then Apply(frame) end
    end
end

local function SaveFrom(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left then return end
    local ratio = Ratio(frame)
    plugin.db.point = { math.floor(left * ratio + 0.5), math.floor(top * ratio + 0.5) }
    core:RefreshSettings()
end

-- Invisible drag strip over the title bar. Clicks on the window's body land
-- on Blizzard's scroll frames, so the window itself can't take the drag.
local function AddDragHandle(frame)
    local handle = CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", frame, "TOPLEFT", HANDLE_LEFT, 0)
    handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", HANDLE_RIGHT, 0)
    handle:SetHeight(HANDLE_HEIGHT)
    handle:SetFrameLevel(frame:GetFrameLevel() + 10)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        dragging[frame] = true
        frame:SetMovable(true)
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        if not dragging[frame] then return end
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)   -- our saved point, not the layout cache
        dragging[frame] = nil
        SaveFrom(frame)
        ApplyShown()
    end)
    -- If the window closes mid-drag, end the drag cleanly.
    frame:HookScript("OnHide", function()
        if dragging[frame] then
            frame:StopMovingOrSizing()
            frame:SetUserPlaced(false)
            dragging[frame] = nil
            SaveFrom(frame)
        end
    end)
end

function plugin:InitPosition()
    if self.positionReady or not self:IsLive() then return end
    self.positionReady = true
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame then
            hooksecurefunc(frame, "SetPoint", function(f)
                if not positioning then Apply(f) end
            end)
            frame:HookScript("OnShow", Apply)
            AddDragHandle(frame)
        end
    end
    ApplyShown()
end

function plugin:ResetPosition()
    self.db.point = nil
    core:RefreshSettings()
    core:Print("Quest windows: back to Blizzard's position the next time they open.")
end

-- ---------------------------------------------------------------------------
-- Move Windows: a stand-in window for the controller (and keyboard / mouse)
-- ---------------------------------------------------------------------------
local mover
local STEP_START, STEP_MAX, STEP_RAMP = 2, 14, 1.2   -- px per tick, px, seconds to full speed
local TICK = 0.02
local DIRECTIONS = {
    PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 }, PADDUP = { 0, 1 }, PADDDOWN = { 0, -1 },
    LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 },
}

local function QuestPageIndex()
    for i, p in ipairs(core.plugins) do
        if p == plugin then return i + 1 end   -- page 1 is General
    end
end

-- The size Blizzard's quest window has on screen, in UIParent units.
local function WindowSize()
    local frame = QuestFrame
    if frame and frame:GetWidth() > 0 then
        local ratio = Ratio(frame)
        return frame:GetWidth() * ratio, frame:GetHeight() * ratio
    end
    return 338, 496
end

local function CreateMover()
    mover = CreateFrame("Frame", "XpieUIForeverQuestMover", UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetToplevel(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    -- A plain stand-in in the quest window's look: rock backdrop, parchment,
    -- Blizzard's metal border (no portrait). Not ButtonFrameTemplate: its
    -- close button calls HideUIPanel.
    local rock = mover:CreateTexture(nil, "BACKGROUND", nil, -2)
    rock:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    rock:SetHorizTile(true)
    rock:SetVertTile(true)
    rock:SetPoint("TOPLEFT", 2, -21)
    rock:SetPoint("BOTTOMRIGHT", -2, 2)
    local parchment = mover:CreateTexture(nil, "BACKGROUND", nil, -1)
    if C_Texture.GetAtlasInfo("QuestBG-Parchment") then
        parchment:SetAtlas("QuestBG-Parchment")
    else
        parchment:SetColorTexture(0.85, 0.75, 0.55, 1)
    end
    parchment:SetPoint("TOPLEFT", 7, -30)
    parchment:SetPoint("BOTTOMRIGHT", -7, 8)
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        pcall(NineSliceUtil.ApplyLayoutByName, mover, "ButtonFrameTemplateNoPortrait")
    end

    local title = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Quest Windows")

    local text = mover:CreateFontString(nil, "OVERLAY", "QuestFont")
    text:SetPoint("TOPLEFT", 24, -60)
    text:SetPoint("TOPRIGHT", -24, -60)
    text:SetJustifyH("LEFT")
    text:SetText("Your quest, gossip and book windows will open here.\n\n"
        .. "Controller: D-pad moves (hold to speed up), A saves, B cancels.\n\n"
        .. "Keyboard: arrow keys move, Enter saves, Esc cancels.\n\n"
        .. "Mouse: drag this window.")
    local colors = GetMaterialTextColors and GetMaterialTextColors("Parchment")
    if colors then text:SetTextColor(colors[1], colors[2], colors[3]) else text:SetTextColor(0.18, 0.12, 0.06) end

    mover:SetScript("OnDragStart", mover.StartMoving)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)

    local held, heldTime, wait = nil, 0, 0
    local function Nudge(dir, px)
        local left, top = mover:GetLeft(), mover:GetTop()
        if not left then return end
        left, top = Clamp(left + dir[1] * px, top + dir[2] * px, mover:GetWidth(), mover:GetHeight())
        mover:ClearAllPoints()
        mover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    local function Finish(save)
        held = nil
        if save then
            local left, top = mover:GetLeft(), mover:GetTop()
            if left then plugin.db.point = { math.floor(left + 0.5), math.floor(top + 0.5) } end
            ApplyShown()
            if SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
        end
        mover:Hide()
        if mover.reopenSettings then core:OpenSettings(QuestPageIndex(), true) end
    end
    local function Input(key)
        local dir = DIRECTIONS[key]
        if dir then
            Nudge(dir, STEP_START)
            held, heldTime, wait = dir, 0, 0.25
        elseif key == "PAD1" or key == "ENTER" then
            Finish(true)
        elseif key == "PAD2" or key == "ESCAPE" or key == "PADBACK" then
            Finish(false)
        else
            return false
        end
        return true
    end
    local function Release(key)
        if DIRECTIONS[key] == held then held = nil end
    end

    mover:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not Input(key))
    end)
    mover:SetScript("OnKeyUp", function(_, key) Release(key) end)
    mover:SetScript("OnGamePadButtonDown", function(self, button)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not Input(button))
    end)
    mover:SetScript("OnGamePadButtonUp", function(_, button) Release(button) end)
    mover:SetScript("OnUpdate", function(_, elapsed)
        if not held then return end
        heldTime = heldTime + elapsed
        wait = wait - elapsed
        if wait > 0 then return end
        wait = TICK
        local speed = STEP_START + (STEP_MAX - STEP_START) * math.min(heldTime / STEP_RAMP, 1)
        Nudge(held, speed)
    end)
    mover:SetScript("OnShow", function(self)
        if self.EnableGamePadButton then self:EnableGamePadButton(true) end
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(true)
    end)
    mover:SetScript("OnHide", function(self)
        if self.EnableGamePadButton then self:EnableGamePadButton(false) end
        self:EnableKeyboard(false)
        held = nil
    end)
    mover:RegisterEvent("PLAYER_REGEN_DISABLED")
    mover:SetScript("OnEvent", function(self)
        if self:IsShown() then Finish(false) end   -- combat: cancel, controls back to the game
    end)
end

function plugin:StartMoveMode()
    if not self:IsLive() then return end
    if InCombatLockdown() then
        core:Print("Quest windows: Move Windows isn't available in combat.")
        return
    end
    if not mover then CreateMover() end
    local width, height = WindowSize()
    mover:SetSize(width, height)
    local point = self.db.point or { 16, UIParent:GetHeight() - 116 }
    local left, top = Clamp(point[1], point[2], width, height)
    mover:ClearAllPoints()
    mover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    -- The settings window would sit on top of the stand-in: hide it, and
    -- bring it back on the Quest Windows page afterwards.
    local settings = _G.XpieUIForeverSettingsFrame
    mover.reopenSettings = settings and settings:IsShown()
    if mover.reopenSettings then settings:Hide() end
    mover:Show()
end
