-- Badges.lua  (XpieUI-Forever, Quest module)
-- Number badges and key hints for the keyboard controls (keyboard & mouse
-- only; hidden in combat and under the controller UI).
--   gossip options     gold number centred on the dimmed option icon
--   quests             Blizzard's quest icon (!, ?, daily, campaign...) kept
--                      at full alpha, small gold number on its corner
--   reward choices     number in the item icon's top-left corner
--   Space / Esc        small grey hints beside Blizzard's bottom buttons
-- Badge and hint fonts are XpieUI copies of Blizzard's number fonts, scaled
-- with Font Size so they keep their place next to the text.
-- Ported from XpieHUD_Core/QuestDialog.lua (badges, key hints).

local core = XpieUI
local plugin = core.questPlugin

local MAX_CHOICES = 19
local ICON_DIM = 0.3     -- option icon alpha under its number
local HINT_GAP = 5

-- Our own font objects, so scaling them never touches Blizzard's.
local FONTS = {
    option = { name = "XpieUIForeverQuestBadgeOption", from = "GameFontNormal" },
    quest  = { name = "XpieUIForeverQuestBadgeQuest",  from = "NumberFontNormalSmall" },
    reward = { name = "XpieUIForeverQuestBadgeReward", from = "NumberFontNormal" },
    hint   = { name = "XpieUIForeverQuestKeyHint",     from = "GameFontDisableSmall" },
}
local STYLES = {
    option = { point = "CENTER",     x = 0,  y = -1.5, dim = true },
    quest  = { point = "BOTTOMLEFT", x = -1, y = -1,   gold = true },
    reward = { point = "TOPLEFT",    x = 2,  y = -2 },
}

local badges = {}      -- [row] = FontString
local dimmed = {}      -- [icon texture] = true
local hints = {}       -- [button] = FontString
local fontsMade, fontScale

local function MakeFonts()
    fontsMade = true
    for _, info in pairs(FONTS) do
        local source = _G[info.from]
        local font = CreateFont(info.name)
        if source then font:CopyFontObject(source) end
        local file, size, flags = font:GetFont()
        info.object, info.base = font, { file, size, flags }
    end
end

local function ScaleFonts()
    if not fontsMade then MakeFonts() end
    local scale = (tonumber(plugin.db.fontSize) or 100) / 100
    if scale == fontScale then return end
    fontScale = scale
    for _, info in pairs(FONTS) do
        local base = info.base
        if base[1] and base[2] then
            info.object:SetFont(base[1], math.floor(base[2] * scale * 2 + 0.5) / 2, base[3])
        end
    end
end

local function SetBadge(row, number, styleName)
    local style = STYLES[styleName]
    local icon = row.Icon
    local badge = badges[row]
    if not badge then
        badge = row:CreateFontString(nil, "OVERLAY")
        badges[row] = badge
    end
    -- Pooled rows can change role between refreshes: restyle when needed.
    if badge.style ~= styleName then
        badge.style = styleName
        badge:SetFontObject(FONTS[styleName].object)
        if style.gold then badge:SetTextColor(NORMAL_FONT_COLOR:GetRGB()) end
        badge:ClearAllPoints()
        badge:SetPoint(style.point, icon or row, style.point, style.x, style.y)
    end
    if icon and style.dim then
        icon:SetAlpha(ICON_DIM)
        dimmed[icon] = true
    end
    badge:SetText(number)
    badge:Show()
end

-- Bottom buttons: Space hints right of the left button, Esc hints left of
-- the right one.
local function HintButtons()
    return {
        { QuestFrameAcceptButton,          "Space", true },
        { QuestFrameCompleteButton,        "Space", true },
        { QuestFrameCompleteQuestButton,   "Space", true },
        { QuestFrameDeclineButton,         "Esc",   false },
        { QuestFrameGoodbyeButton,         "Esc",   false },
        { QuestFrameGreetingGoodbyeButton, "Esc",   false },
        { GossipFrame and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.GoodbyeButton, "Esc", false },
    }
end

-- Space does nothing on PvP quests and quests that cost gold (a click
-- confirms those), so no hint there.
local function SpaceWouldAct()
    if QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown() then
        return not QuestFlagsPVP()
    elseif QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() then
        local money = GetQuestMoneyToGet()
        return not (money and money > 0)
    end
    return true
end

local function RefreshHints(show)
    for _, entry in ipairs(HintButtons()) do
        local button, text, onRight = entry[1], entry[2], entry[3]
        if button then
            local hint = hints[button]
            if not hint and show then
                hint = button:CreateFontString(nil, "OVERLAY")
                hint:SetFontObject(FONTS.hint.object)
                hint:SetText(text)
                hints[button] = hint
            end
            if hint then
                local visible = show and (text ~= "Space" or SpaceWouldAct())
                if visible then
                    -- Vertically centred on the button's own label, wherever
                    -- the button's art puts it.
                    local label = button:GetFontString()
                    local _, labelY = label and label:GetCenter()
                    local _, buttonY = button:GetCenter()
                    local y = (labelY and buttonY) and (labelY - buttonY) or 0
                    hint:ClearAllPoints()
                    if onRight then
                        hint:SetPoint("LEFT", button, "RIGHT", HINT_GAP, y)
                    else
                        hint:SetPoint("RIGHT", button, "LEFT", -HINT_GAP, y)
                    end
                end
                hint:SetShown(visible)
            end
        end
    end
end

function plugin:RefreshBadges()
    for _, badge in pairs(badges) do badge:Hide() end
    for icon in pairs(dimmed) do icon:SetAlpha(1) end
    wipe(dimmed)

    local show = self.KeyboardControlsOn and self.KeyboardControlsOn() or false
    if show then ScaleFonts() end
    RefreshHints(show)
    if not show then return end

    for number, choice in ipairs((self:GetChoices())) do
        if number > MAX_CHOICES then break end
        if choice.frame and choice.frame:IsShown() then
            local style = choice.isReward and "reward" or (choice.isQuest and "quest" or "option")
            SetBadge(choice.frame, number, style)
        end
    end
end

-- Lists and pages that (re)build: badge them again.
function plugin:InitBadges()
    if self.badgesReady or not self:IsLive() then return end
    self.badgesReady = true
    local function Refresh() plugin:RefreshBadges() end
    if GossipFrame and GossipFrame.Update then hooksecurefunc(GossipFrame, "Update", Refresh) end
    -- Keyboard & mouse only (see Keys.lua).
    if self.AddGossipScrollCallback then self:AddGossipScrollCallback(FONTS, Refresh) end
    for _, panel in ipairs({ QuestFrameGreetingPanel, QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel }) do
        if panel then panel:HookScript("OnShow", Refresh) end
    end
    -- Called directly (not through OnShow) on QUEST_LOG_UPDATE / QUEST_ITEM_UPDATE.
    if QuestFrameGreetingPanel_OnShow then hooksecurefunc("QuestFrameGreetingPanel_OnShow", Refresh) end
    if QuestInfo_ShowRewards then hooksecurefunc("QuestInfo_ShowRewards", Refresh) end
end
