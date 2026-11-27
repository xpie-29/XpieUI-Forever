-- Fonts.lua  (XpieUI-Forever, Quest module)
-- Font Size: Blizzard's quest fonts scaled by one percentage. Typeface,
-- colours and flags stay Blizzard's; the windows keep their size and long
-- text scrolls. These font objects are shared, so the quest text in the
-- world map and quest log grows too.
--
-- Each object is set from the size it had at login (base x percentage), so
-- applying again never compounds, whether or not a child font object follows
-- its parent (the probe showed QuestFontLeft follows QuestFont live).

local core = XpieUI
local plugin = core.questPlugin

local FONTS = {
    "QuestFont",              -- body, objectives text, rewards text, greeting, book text
    "QuestTitleFont",         -- titles, section headers (Morpheus)
    "QuestFontNormalSmall",   -- objective lines, timer, required money
    "QuestFont_Large",        -- large book text (Morpheus 15)
    "QuestFont_Huge",         -- seal text (Morpheus 18)
}

local base   -- [font object] = { file, size, flags } at login

local function ReadBase()
    base = {}
    for _, name in ipairs(FONTS) do
        local font = _G[name]
        if font and font.GetFont then
            local file, size, flags = font:GetFont()
            if file and size and size > 0 then base[font] = { file, size, flags } end
        end
    end
end

function plugin:ApplyFonts()
    if not self:IsLive() then return end
    if not base then ReadBase() end
    local scale = (tonumber(self.db.fontSize) or 100) / 100
    for font, info in pairs(base) do
        font:SetFont(info[1], math.floor(info[2] * scale * 2 + 0.5) / 2, info[3])
    end
end
