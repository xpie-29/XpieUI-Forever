-- SpokenWords.lua  (XpieUI-Forever, Quest module)
-- Spoken Integration, part two: the words being read are marked in the quest,
-- gossip and book windows' own text, and Spoken's own player and subtitles
-- stay out of the way while one of those windows is open.
--
--   Matching    Spoken's helper (Spoken:WordMarks: Align, Pick, Cut, Spans,
--               Want) finds the line from Spoken:GetCaption() in our text
--   Drawing     colour codes written into the text itself, so nothing
--               rewraps; the text Blizzard set goes back when the line ends,
--               the page changes or the window closes. Spoken's Type Words
--               Out is honoured the same way: a paragraph being typed out
--               keeps its full height, so what Blizzard anchors below it
--               (objectives, rewards, the quest list) stays put.
--   Colours     Parchment Highlight on dark text, Dark Highlight on light
--               text (Quest Text Contrast, stone books)
--   Scrolling   the window scrolls to keep the word being read in view,
--               until the player scrolls it themselves (then until the
--               next line)
--   Player      hosted on a hidden frame (Spoken:SetPlayerHost) while a
--               window or the small box (SpokenBox.lua) is open, given back
--               when they close
--   Hand-off    a window closing mid-line offers that line to the small box
--
-- The quest text frames are shared with the world map: they're only marked
-- while the quest window owns them, and always put back first.

local core = XpieUI
local plugin = core.questPlugin

local WINDOWS = { "QuestFrame", "GossipFrame", "ItemTextFrame" }
local TICK = 0.05
local UNHOST_DELAY = 0.15          -- gossip -> quest: one window closes before the next opens
local SCROLL_LEAD = 0.2            -- share of the view kept above the word when scrolling
local SCROLL_EDGE = 0.85           -- scroll once the word passes this far down the view

plugin.SPOKEN_LIGHT = "0070dd"     -- bright blue, on parchment
plugin.SPOKEN_DARK = "ffd100"      -- Spoken's gold, on dark pages
plugin.SPOKEN_CLASS = "class"      -- the player's class colour

-- paragraphs: { region, text (Blizzard's), shown (what we last set), words,
-- dark, scroll, html }. clip, map, span: the caption matched against them.
local state = { dirty = true }
local driver = CreateFrame("Frame")
local hostFrame
local hosted = false
local hostToken = 0
local settingOurs = false          -- our own SetText on the book page
local bookText                     -- what Blizzard last put on the book page
local offer                        -- { clip, left, top, scale }: the line of the window that just closed

local function Api() return plugin.SpokenApi and plugin.SpokenApi() end

local function Marks()
    local spoken = Api()
    if spoken and type(spoken.WordMarks) == "function" then
        local ok, marks = pcall(spoken.WordMarks, spoken)
        if ok and type(marks) == "table" and marks.Align then return marks end
    end
end

local function WordsOn()
    local spoken = Api()
    return plugin.SpokenOn and plugin.SpokenOn() and spoken
        and type(spoken.GetCaption) == "function" and type(spoken.SplitCaption) == "function"
        and Marks() ~= nil
end

local function ShownWindow()
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame and frame:IsShown() then return frame end
    end
end

local function ColorCode(hex)
    return "|cff" .. hex
end

-- The player's class colour, as rrggbb.
function plugin:ClassColorHex()
    local _, class = UnitClass("player")
    local color = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if not color then return nil end
    return ("%02x%02x%02x"):format(math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
end

local function HighlightColor(dark)
    local hex = dark and plugin.db.spokenDark or plugin.db.spokenLight
    if hex == plugin.SPOKEN_CLASS then hex = plugin:ClassColorHex() end
    if not core.HexToRGB(hex) then hex = dark and plugin.SPOKEN_DARK or plugin.SPOKEN_LIGHT end
    return ColorCode(hex)
end
plugin.SpokenHighlightColor = HighlightColor
plugin.SpokenMarks = function() return Marks() end

-- Light text means a dark page.
local function IsDark(r, g, b)
    return (r or 0) * 0.299 + (g or 0) * 0.587 + (b or 0) * 0.114 >= 0.5
end

-- ---------------------------------------------------------------------------
-- The text on each window
-- ---------------------------------------------------------------------------
-- The quest window owns QuestInfo's text (not the map's quest log).
local function QuestInfoOurs()
    if not QuestInfoFrame or QuestInfoFrame.questLog then return false end
    local parent = QuestInfoFrame:GetParent()
    while parent do
        if parent == QuestFrame then return true end
        parent = parent:GetParent()
    end
    return false
end

local function Showing(region)
    if region.GetText then
        return region:GetText() or ""
    end
end

local function AddFontString(list, fs, scroll)
    if not (fs and fs:IsVisible()) then return end
    local text = fs:GetText()
    if type(text) ~= "string" or text == "" then return end
    list[#list + 1] = { region = fs, text = text, dark = IsDark(fs:GetTextColor()), scroll = scroll }
end

local function BookIsDark()
    if QuestTextContrast and QuestTextContrast.UseLightText then
        local ok, light = pcall(QuestTextContrast.UseLightText)
        if ok and light then return true end
    end
    local material = ItemTextGetMaterial and ItemTextGetMaterial() or "Parchment"
    if GetMaterialTextColors then
        local ok, textColor = pcall(GetMaterialTextColors, material or "Parchment")
        if ok and type(textColor) == "table" then return IsDark(textColor[1], textColor[2], textColor[3]) end
    end
    return false
end

local function Collect()
    local list = {}
    if QuestFrame and QuestFrame:IsShown() then
        if QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown() and QuestInfoOurs() then
            AddFontString(list, QuestInfoDescriptionText, QuestDetailScrollFrame)
            AddFontString(list, QuestInfoObjectivesText, QuestDetailScrollFrame)
        elseif QuestFrameProgressPanel and QuestFrameProgressPanel:IsShown() then
            AddFontString(list, QuestProgressText, QuestProgressScrollFrame)
        elseif QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() and QuestInfoOurs() then
            AddFontString(list, QuestInfoRewardText, QuestRewardScrollFrame)
        elseif QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then
            AddFontString(list, GreetingText, QuestGreetingScrollFrame)
        end
    elseif GossipFrame and GossipFrame:IsShown() then
        local box = GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox
        if box and box.ForEachFrame then
            box:ForEachFrame(function(frame)
                if frame.GreetingText then AddFontString(list, frame.GreetingText) end
            end)
        end
    elseif ItemTextFrame and ItemTextFrame:IsShown() and ItemTextPageText and bookText then
        -- HTML pages are left alone: marks would land inside their tags.
        if not bookText:find("^%s*<[Hh][Tt][Mm][Ll]") then
            list[1] = { region = ItemTextPageText, text = bookText, dark = BookIsDark(),
                scroll = ItemTextScrollFrame, book = true }
        end
    end

    local spoken = Api()
    local marks = Marks()
    local paragraphs = {}
    for _, para in ipairs(list) do
        local ok, words = pcall(spoken.SplitCaption, spoken, para.text)
        if ok and type(words) == "table" and #words > 0 then
            para.words = marks.MarkLinks and marks.MarkLinks(para.text, words) or words
            para.shown = para.text
            paragraphs[#paragraphs + 1] = para
        end
    end
    return paragraphs
end

local function SetRegionText(para, text)
    local region = para.region
    if para.book then
        settingOurs = true
        region:SetText(text)
        settingOurs = false
    else
        -- These size to their text (height 0 in Blizzard's XML). Cut short,
        -- they'd pull up everything anchored below them, so they hold their
        -- full height until the whole text is back.
        local cut = #text < #para.text
        if cut and not para.pinned then
            para.pinned = true
            region:SetHeight(region:GetHeight())
        end
        region:SetText(text)
        if not cut and para.pinned then
            para.pinned = nil
            region:SetHeight(0)
        end
    end
    para.shown = text
end

-- Still showing what we last set (Blizzard may have filled it again since).
local function StillOurs(para)
    if para.book then return bookText == para.text and ItemTextFrame:IsShown() end
    return Showing(para.region) == para.shown
end

local function Restore()
    for _, para in ipairs(state.paragraphs or {}) do
        if para.shown ~= para.text and StillOurs(para) then
            SetRegionText(para, para.text)
        elseif para.pinned then
            para.pinned = nil
            para.region:SetHeight(0)
        end
        para.shown = para.text
    end
    state.lit, state.neighbor, state.cutP, state.cutByte = nil, nil, nil, nil
end

local function Invalidate()
    Restore()
    state.paragraphs, state.clip, state.map, state.span = nil, nil, nil, nil
    state.dirty, state.scrolledTo, state.scrollSet, state.userScrolled = true, nil, nil, nil
end
plugin.InvalidateSpokenWords = Invalidate

-- ---------------------------------------------------------------------------
-- Scrolling the word into view
-- ---------------------------------------------------------------------------
local function ScrollTo(para, word)
    local scroll = para.scroll
    if not (scroll and scroll.GetVerticalScroll and scroll:IsVisible()) then return end
    -- The player scrolled since we last did: leave it to them for this line.
    local set = state.scrollSet
    if state.userScrolled or (set and set.frame == scroll and math.abs((scroll:GetVerticalScroll() or 0) - set.value) > 1) then
        state.userScrolled = true
        return
    end
    local child = scroll:GetScrollChild()
    local childTop, top, bottom = child and child:GetTop(), para.region:GetTop(), para.region:GetBottom()
    if not (childTop and top and bottom) then return end
    -- Where in the paragraph the word sits, by its place in the text.
    local share = word and word.first and #para.text > 0 and (word.first / #para.text) or 0
    local y = (childTop - top) + (top - bottom) * share
    local view = scroll:GetHeight() or 0
    local current = scroll:GetVerticalScroll() or 0
    if y >= current and y <= current + view * SCROLL_EDGE then return end
    local range = scroll:GetVerticalScrollRange() or 0
    local value = math.max(0, math.min(range, y - view * SCROLL_LEAD))
    scroll:SetVerticalScroll(value)
    state.scrollSet = { frame = scroll, value = scroll:GetVerticalScroll() or value }
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local function Draw(marks, map, span, lit, neighbor, cutP, cutByte)
    local paragraphs = state.paragraphs
    local spans = marks.Spans(map, paragraphs, lit, neighbor)
    for p, para in ipairs(paragraphs) do
        local want = marks.Want(para, p, span, cutP, cutByte, spans, HighlightColor(para.dark))
        if want ~= para.shown then
            if not StillOurs(para) then
                Invalidate()   -- Blizzard filled it again: collect afresh next tick
                return
            end
            SetRegionText(para, want)
        end
    end
    state.lit, state.neighbor, state.cutP, state.cutByte = lit, neighbor, cutP, cutByte
    local at = lit and map[lit]
    local p = at and at.p or cutP
    local key = at and (at.p * 100000 + at.w) or cutP
    if p and paragraphs[p] and key ~= state.scrolledTo then
        state.scrolledTo = key
        ScrollTo(paragraphs[p], at and paragraphs[p].words[at.w] or nil)
    end
end

local function Tick()
    if not (WordsOn() and ShownWindow()) then
        Restore()
        state.clip, state.map = nil, nil
        return
    end
    local marks = Marks()
    if state.dirty then
        state.paragraphs, state.dirty = Collect(), false
        state.clip, state.map = nil, nil
    end
    local caption = Api():GetCaption()
    local clip = caption and caption.clip
    if clip and #state.paragraphs > 0 then
        if clip ~= state.clip then
            Restore()
            state.clip, state.scrolledTo = clip, nil
            state.scrollSet, state.userScrolled = nil, nil
            state.map, state.span = marks.Align(caption.words, state.paragraphs)
            if state.map then state.matchedClip = clip end
        end
    else
        state.clip, state.map = nil, nil
    end
    if state.map and (caption.highlight or caption.typewriter) then
        local lit, neighbor
        if caption.highlight then
            lit, neighbor = marks.Pick(state.map, caption.speaking and caption.activeWord or nil)
        end
        local cutP, cutByte = marks.Cut(caption, state.map, state.span, state.paragraphs)
        if state.force or lit ~= state.lit or neighbor ~= state.neighbor or cutP ~= state.cutP or cutByte ~= state.cutByte then
            state.force = nil
            Draw(marks, state.map, state.span, lit, neighbor, cutP, cutByte)
        end
        return
    end
    Restore()
end

local elapsedSince = 0
local function OnUpdate(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < TICK then return end
    elapsedSince = 0
    local ok, err = pcall(Tick)
    if not ok then
        driver:SetScript("OnUpdate", nil)
        pcall(Restore)
        geterrorhandler()(err)
    end
end

-- ---------------------------------------------------------------------------
-- Spoken's own player
-- ---------------------------------------------------------------------------
local function SetHosted(on)
    local spoken = Api()
    if on == hosted or not (spoken and type(spoken.SetPlayerHost) == "function") then return end
    if on and not hostFrame then
        hostFrame = CreateFrame("Frame", nil, UIParent)
        hostFrame:Hide()
    end
    if pcall(spoken.SetPlayerHost, spoken, on and hostFrame or nil) then hosted = on end
end

-- ---------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------
local function Update()
    local on = plugin.SpokenOn and plugin.SpokenOn()
    if not on and plugin.HideSpokenBox then plugin.HideSpokenBox(true) end
    local windowOpen = on and ShownWindow() ~= nil
    local open = windowOpen or (on and plugin.SpokenBoxShown and plugin.SpokenBoxShown())
    hostToken = hostToken + 1
    if open then
        SetHosted(true)
    end
    if not windowOpen and (hosted or offer) then
        -- After the gossip -> quest gap: the line carries on in the small box,
        -- or Spoken gets its player back.
        local token = hostToken
        C_Timer.After(UNHOST_DELAY, function()
            if token ~= hostToken then return end
            local line = offer
            offer = nil
            if line and plugin.ShowSpokenBox and plugin.ShowSpokenBox(line) then return end
            if not (plugin.SpokenBoxShown and plugin.SpokenBoxShown()) then SetHosted(false) end
        end)
    end
    if windowOpen and WordsOn() then
        state.force = true
        driver:SetScript("OnUpdate", OnUpdate)
    else
        driver:SetScript("OnUpdate", nil)
        Invalidate()
    end
end
plugin.UpdateSpokenWords = Update

function plugin:InitSpokenWords()
    if self.spokenWordsReady then return end
    self.spokenWordsReady = true
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame then
            frame:HookScript("OnShow", function()
                offer = nil
                if plugin.HideSpokenBox then plugin.HideSpokenBox(true) end
                Invalidate()
                Update()
            end)
            -- Put the text back at once: the map may take QuestInfo next.
            frame:HookScript("OnHide", function()
                local clip = state.matchedClip
                if clip and plugin.SpokenOn and plugin.SpokenOn() then
                    offer = { clip = clip, left = frame:GetLeft(), top = frame:GetTop(), scale = frame:GetEffectiveScale() }
                end
                Invalidate()
                Update()
            end)
        end
    end
    for _, panel in ipairs({ QuestFrameGreetingPanel, QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel }) do
        if panel then panel:HookScript("OnShow", Invalidate) end
    end
    if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", Invalidate) end
    if QuestFrameGreetingPanel_OnShow then hooksecurefunc("QuestFrameGreetingPanel_OnShow", Invalidate) end
    if GossipFrame and GossipFrame.Update then hooksecurefunc(GossipFrame, "Update", Invalidate) end
    if ItemTextPageText then
        hooksecurefunc(ItemTextPageText, "SetText", function(_, text)
            if settingOurs then return end
            bookText = type(text) == "string" and text or nil
            state.dirty = true
        end)
    end
    Update()
end
