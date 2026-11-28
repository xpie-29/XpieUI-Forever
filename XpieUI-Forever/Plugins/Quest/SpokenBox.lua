-- SpokenBox.lua  (XpieUI-Forever, Quest module)
-- Spoken Integration, part three: a small box in Blizzard's tooltip look, at
-- the top centre of the screen, for the lines no quest window shows.
--
--   Narrator    the box is also a Spoken narrator style ("XpieUI",
--               Spoken:RegisterNarrator). Chosen in Spoken's settings, Spoken
--               shows none of its own windows and hands every line here:
--               zone lore, bosses, books, chatter. A quest, gossip or book
--               window that shows the line itself keeps it; any other line
--               shows in the box, with the window open or not.
--   Hand-off    with another narrator style, a window closing while its
--               line is still being read passes the line to the box
--
--   Contents    the speaker's round face (Spoken:CreateSpeakerFace), the
--               speaker and the quest title, Spoken's control row, and the
--               line's text with the words being read in Dark Highlight
--   Gone        fades out when the line ends or is skipped; opening a window
--               hides it at once (the window takes the line over)
--
-- Named XpieUIForever... so Hide UI While Talking leaves it alone.

local addonName = ...
local core = XpieUI
local plugin = core.questPlugin

local NARRATOR_ID = "xpieui"
local WATCH_TICK = 0.1

local WIDTH = 340
local PAD = 10
local FACE = 44
local GAP = 8
local ROW_ROOM = 112         -- the control row at the top right
local MAX_TEXT = 150         -- taller lines scroll inside the box
local TICK = 0.05
local FADE_TIME = 0.3
local SCROLL_LEAD = 0.2
local SCROLL_EDGE = 0.85
local TOP_OFFSET = -60       -- below the top edge of the screen

local box, face, header, label, scroll, child, text
local line                  -- { clip, paragraphs, map, span, lit, neighbor, cutP, cutByte, full }
local fading = nil          -- seconds into the fade-out
local elapsedSince = 0
local narratorClip          -- the line Spoken last handed us as the narrator
local watcher = CreateFrame("Frame")

local function Api() return plugin.SpokenApi and plugin.SpokenApi() end

local function Call(method, ...)
    local spoken = Api()
    if spoken and type(spoken[method]) == "function" then
        local ok, result = pcall(spoken[method], spoken, ...)
        if ok then return result end
    end
end

-- ---------------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------------
local function Build()
    box = CreateFrame("Frame", "XpieUIForeverSpokenBox", UIParent, "TooltipBackdropTemplate")
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    box:SetWidth(WIDTH)
    box:Hide()

    local spoken = Api()
    if spoken and type(spoken.CreateSpeakerFace) == "function" then
        local ok, made = pcall(spoken.CreateSpeakerFace, spoken, box, FACE)
        if ok and made then
            face = made
            face:SetPoint("TOPLEFT", PAD, -PAD)
        end
    end

    local left = face and (PAD + FACE + GAP) or PAD
    header = box:CreateFontString(nil, "ARTWORK", "GameTooltipHeaderText")
    header:SetPoint("TOPLEFT", left, -PAD - 4)
    header:SetWidth(WIDTH - left - ROW_ROOM)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    header:SetTextColor(NORMAL_FONT_COLOR:GetRGB())

    label = box:CreateFontString(nil, "ARTWORK", "GameTooltipTextSmall")
    label:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    label:SetWidth(WIDTH - left - PAD)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(0.8, 0.8, 0.8)

    scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", PAD, -(PAD + FACE + GAP))
    scroll:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
    child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(WIDTH - 2 * PAD)
    scroll:SetScrollChild(child)
    text = child:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    text:SetPoint("TOPLEFT")
    text:SetWidth(WIDTH - 2 * PAD)
    text:SetJustifyH("LEFT")
    text:SetTextColor(1, 1, 1)

    plugin:AddSpokenRowHost(box, function(rowFrame)
        rowFrame:SetPoint("TOPRIGHT", box, "TOPRIGHT", -PAD + 2, -PAD + 2)
    end)
end

local function SetSpeaker(present)
    if not face then return end
    local portrait = type(present.portrait) == "table" and present.portrait or nil
    local speaker
    if portrait and portrait.kind == "model" and portrait.creatureID then
        speaker = { creatureID = portrait.creatureID, bullet = present.bullet }
    elseif portrait and portrait.kind == "texture" and portrait.texture then
        speaker = { objectOrItem = true, icon = portrait.texture, iconCrop = portrait.texCoord, bullet = present.bullet }
    end
    pcall(face.SetSpeaker, face, speaker)
end

-- ---------------------------------------------------------------------------
-- The line's text, marked
-- ---------------------------------------------------------------------------
local function Layout()
    text:SetText(line.full)
    local height = math.ceil(text:GetStringHeight() or 0)
    child:SetHeight(math.max(1, height))
    local view = math.min(height, MAX_TEXT)
    scroll:SetHeight(math.max(1, view))
    scroll:SetVerticalScroll(0)
    box:SetHeight(PAD + FACE + GAP + view + PAD)
    line.height = height
end

local function ScrollToWord(word)
    if not (word and word.first and line.height and line.height > MAX_TEXT) then return end
    local y = line.height * (word.first / math.max(1, #line.full))
    local view = scroll:GetHeight() or 0
    local current = scroll:GetVerticalScroll() or 0
    if y >= current and y <= current + view * SCROLL_EDGE then return end
    scroll:SetVerticalScroll(math.max(0, math.min(line.height - view, y - view * SCROLL_LEAD)))
end

local function Draw(marks, caption)
    if not line.map then return end
    local lit, neighbor
    if caption.highlight then
        lit, neighbor = marks.Pick(line.map, caption.speaking and caption.activeWord or nil)
    end
    local cutP, cutByte = marks.Cut(caption, line.map, line.span, line.paragraphs)
    if not line.force and lit == line.lit and neighbor == line.neighbor and cutP == line.cutP and cutByte == line.cutByte then
        return
    end
    line.force = nil
    line.lit, line.neighbor, line.cutP, line.cutByte = lit, neighbor, cutP, cutByte
    local spans = marks.Spans(line.map, line.paragraphs, lit, neighbor)
    local para = line.paragraphs[1]
    text:SetText(marks.Want(para, 1, line.span, cutP, cutByte, spans, plugin.SpokenHighlightColor(true)))
    local at = lit and line.map[lit]
    if at then ScrollToWord(para.words[at.w]) end
end

-- ---------------------------------------------------------------------------
-- Showing and hiding
-- ---------------------------------------------------------------------------
local function Finish()
    box:SetScript("OnUpdate", nil)
    box:Hide()
    box:SetAlpha(1)
    fading, line = nil, nil
    if plugin.RefreshSpokenRows then plugin.RefreshSpokenRows() end
    if plugin.UpdateSpokenWords then plugin.UpdateSpokenWords() end
end

local function FadeOut()
    if not fading then fading = 0 end
end

local function Tick(elapsed)
    if fading then
        fading = fading + elapsed
        if fading >= FADE_TIME then Finish() return end
        box:SetAlpha(1 - fading / FADE_TIME)
        return
    end
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < TICK then return end
    elapsedSince = 0
    local caption = Call("GetCaption")
    if line.narrated then
        -- Spoken says when the line ends (Update(nil) or the next line).
        if not (caption and caption.clip == line.clip) then return end
    elseif not caption or caption.clip ~= line.clip or Call("GetCurrent") ~= line.clip then
        -- The line ended, was skipped or another took its place.
        FadeOut()
        return
    end
    local marks = plugin.SpokenMarks and plugin.SpokenMarks()
    if marks and line.paragraphs and not line.map then
        line.map, line.span = marks.Align(caption.words, line.paragraphs)
        line.force = true
    end
    if marks and (caption.highlight or caption.typewriter) then Draw(marks, caption) end
end

local function OnUpdate(_, elapsed)
    local ok, err = pcall(Tick, elapsed)
    if not ok then
        Finish()
        geterrorhandler()(err)
    end
end

-- Show `clip` in the box. narrated: handed over by Spoken as the narrator,
-- so it may have no text (header and face only) and its caption may come a
-- moment later. True when the box took the line.
local function ShowLine(clip, narrated)
    if box and box:IsShown() and not fading and line and line.clip == clip then
        line.narrated = narrated or line.narrated
        return true
    end
    local caption = Call("GetCaption")
    local captioned = caption and caption.clip == clip
    if not narrated and not (captioned and Call("GetCurrent") == clip) then return false end
    local present = type(clip.present) == "table" and clip.present or {}
    local full = present.transcript or clip.text
    if type(full) ~= "string" then full = "" end
    if full == "" and not narrated then return false end
    if not box then Build() end

    line = { clip = clip, full = full, force = true, narrated = narrated }
    local marks = plugin.SpokenMarks and plugin.SpokenMarks()
    local spoken = Api()
    if full ~= "" and marks and spoken and spoken.SplitCaption then
        local ok, words = pcall(spoken.SplitCaption, spoken, full)
        if ok and type(words) == "table" and #words > 0 then
            line.paragraphs = { { text = full, words = marks.MarkLinks and marks.MarkLinks(full, words) or words } }
            if captioned then line.map, line.span = marks.Align(caption.words, line.paragraphs) end
        end
    end

    header:SetText(present.header or "")
    label:SetText(present.label or "")
    SetSpeaker(present)
    Layout()

    box:ClearAllPoints()
    box:SetPoint("TOP", UIParent, "TOP", 0, TOP_OFFSET)
    fading, elapsedSince = nil, TICK
    box:SetAlpha(1)
    box:Show()
    box:SetScript("OnUpdate", OnUpdate)
    if plugin.RefreshSpokenRows then plugin.RefreshSpokenRows() end
    return true
end

-- offer = { clip, left, top, scale } from the window that closed. True when
-- the box took the line.
function plugin.ShowSpokenBox(offer)
    local clip = offer and offer.clip
    if not clip then return false end
    return ShowLine(clip, false)
end

-- instant: a window opened (it takes the line over) or the setting went off.
function plugin.HideSpokenBox(instant)
    if not (box and box:IsShown()) then return end
    if instant then Finish() else FadeOut() end
end

function plugin.SpokenBoxShown()
    return box ~= nil and box:IsShown() and not fading
end

-- ---------------------------------------------------------------------------
-- Narrator style
-- ---------------------------------------------------------------------------
function plugin.SpokenNarratorActive()
    return Call("GetPlayerStyle") == NARRATOR_ID
end

local WINDOWS = { "QuestFrame", "GossipFrame", "ItemTextFrame" }
local function WindowShown()
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if frame and frame:IsShown() then return true end
    end
    return false
end

-- Where the narrator's line goes now: a window that shows it keeps it,
-- otherwise the box. With Spoken Integration off, or a Spoken too old for
-- word matching, nothing matches lines to the window's text, so an open
-- window keeps them all rather than the box repeating what it already shows.
local function Decide()
    local clip = narratorClip
    if not clip then
        if line and line.narrated then FadeOut() end
        return
    end
    local matching = plugin.SpokenWordsOn and plugin.SpokenWordsOn()
    if (not matching and WindowShown())
        or (plugin.SpokenWindowHolds and plugin.SpokenWindowHolds(clip)) then
        if box and box:IsShown() and line and line.narrated then Finish() end
        return
    end
    ShowLine(clip, true)
end

-- Windows open and close, and pages turn, without Spoken telling us: look
-- again a few times a second while there's a line.
local watchSince = 0
local function Watch(_, elapsed)
    watchSince = watchSince + elapsed
    if watchSince < WATCH_TICK then return end
    watchSince = 0
    if not narratorClip then
        watcher:SetScript("OnUpdate", nil)
        return
    end
    local ok, err = pcall(Decide)
    if not ok then
        watcher:SetScript("OnUpdate", nil)
        geterrorhandler()(err)
    end
end

local function NarratorUpdate(clip)
    narratorClip = clip
    Decide()
    if clip then
        watchSince = 0
        watcher:SetScript("OnUpdate", Watch)
    end
    if plugin.UpdateSpokenWords then plugin.UpdateSpokenWords() end
end

-- Registered while we load (Spoken loads first: OptionalDeps), so the card is
-- there when Spoken builds its narrator page.
do
    local spoken = Api() or (type(_G.Spoken) == "table" and _G.Spoken.IsCompatible
        and _G.Spoken:IsCompatible(1) and _G.Spoken) or nil
    if spoken and type(spoken.RegisterNarrator) == "function" then
        pcall(spoken.RegisterNarrator, spoken, NARRATOR_ID, {
            addon = addonName,
            title = "XpieUI",
            description = "A small box in Blizzard's tooltip look at the top of the screen, with the words "
                .. "highlighted as they're read. Lines a quest, gossip or book window shows stay in that window.",
            Update = function(clip) NarratorUpdate(clip) end,
        })
    end
end

-- Offered once, ever, by Spoken itself (never when it's the style already).
function plugin.SuggestSpokenNarrator()
    Call("SuggestNarrator", NARRATOR_ID)
end
