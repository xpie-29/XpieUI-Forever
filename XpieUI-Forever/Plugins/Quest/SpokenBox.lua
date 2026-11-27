-- SpokenBox.lua  (XpieUI-Forever, Quest module)
-- Spoken Integration, part three: when a quest, gossip or book window closes
-- while its line is still being read, the line carries on in a small box in
-- Blizzard's tooltip look, where the window was.
--
--   Contents    the speaker's round face (Spoken:CreateSpeakerFace), the
--               speaker and the quest title, Spoken's control row, and the
--               line's text with the words being read in Dark Highlight
--   Gone        fades out when the line ends or is skipped; opening a window
--               hides it at once (the window takes the line over)
--
-- Named XpieUIForever... so Hide UI While Talking leaves it alone.

local core = XpieUI
local plugin = core.questPlugin

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

local box, face, header, label, scroll, child, text
local line                  -- { clip, paragraphs, map, span, lit, neighbor, cutP, cutByte, full }
local fading = nil          -- seconds into the fade-out
local elapsedSince = 0

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
    -- The line ended, was skipped or another took its place.
    local caption = Call("GetCaption")
    if not caption or caption.clip ~= line.clip or Call("GetCurrent") ~= line.clip then
        FadeOut()
        return
    end
    local marks = plugin.SpokenMarks and plugin.SpokenMarks()
    if marks and (caption.highlight or caption.typewriter) then Draw(marks, caption) end
end

local function OnUpdate(_, elapsed)
    local ok, err = pcall(Tick, elapsed)
    if not ok then
        Finish()
        geterrorhandler()(err)
    end
end

-- offer = { clip, left, top, scale } from the window that closed. True when
-- the box took the line.
function plugin.ShowSpokenBox(offer)
    local clip = offer and offer.clip
    local caption = Call("GetCaption")
    if not (clip and caption and caption.clip == clip and Call("GetCurrent") == clip) then return false end
    local present = type(clip.present) == "table" and clip.present or {}
    local full = present.transcript or clip.text
    if type(full) ~= "string" or full == "" then return false end
    if not box then Build() end

    line = { clip = clip, full = full, force = true }
    local marks = plugin.SpokenMarks and plugin.SpokenMarks()
    local spoken = Api()
    if marks and spoken and spoken.SplitCaption then
        local ok, words = pcall(spoken.SplitCaption, spoken, full)
        if ok and type(words) == "table" and #words > 0 then
            line.paragraphs = { { text = full, words = marks.MarkLinks and marks.MarkLinks(full, words) or words } }
            line.map, line.span = marks.Align(caption.words, line.paragraphs)
        end
    end

    header:SetText(present.header or "")
    label:SetText(present.label or "")
    SetSpeaker(present)
    Layout()

    box:ClearAllPoints()
    if offer.left and offer.top then
        local ratio = (offer.scale or 1) / UIParent:GetEffectiveScale()
        box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", offer.left * ratio, offer.top * ratio)
    else
        box:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
    fading, elapsedSince = nil, TICK
    box:SetAlpha(1)
    box:Show()
    box:SetScript("OnUpdate", OnUpdate)
    if plugin.RefreshSpokenRows then plugin.RefreshSpokenRows() end
    return true
end

-- instant: a window opened (it takes the line over) or the setting went off.
function plugin.HideSpokenBox(instant)
    if not (box and box:IsShown()) then return end
    if instant then Finish() else FadeOut() end
end

function plugin.SpokenBoxShown()
    return box ~= nil and box:IsShown() and not fading
end
