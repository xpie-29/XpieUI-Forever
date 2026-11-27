# XpieUI-Forever: Quest plugin (native quest windows)

## Decision

DialogueUI is dropped as the quest window. If both are installed, the user picks one on screen and XpieUI turns the other off (see section 0). Instead we keep **Blizzard's own** quest, gossip and book windows, with Blizzard's look and Blizzard's controller support left exactly as they are. We add only a few small things on top.

| Feature | Keyboard & mouse | Controller (Forever's gamepad UI) |
|---|---|---|
| One shared, saved window position | yes | yes |
| Font size | yes | yes |
| Hide the rest of the UI while talking | yes | yes |
| Camera: zoom in on the speaker (DialogueUI's "Zoom In" at multiplier 4), one fixed position | yes | yes (the user confirmed in game that DialogueUI's version works with the controller) |
| Keyboard controls, number badges, key hints, tooltips at the cursor | yes | off; Blizzard's prompts are used |
| Spoken integration (on by default when Spoken is installed): controls on the window, highlighted words in a colour the user picks, a small box when the window closes mid-line | yes | yes |

Not wanted:
- the XpieHUD Parchment look
- DialogueUI's options
- any custom window art
- trainer/vendor "follow" windows
- camera options or zoom levels

The point is as few settings as possible.

## What we reuse

From `_assets/XpieHUD-main/XpieHUD_Core/QuestDialog.lua` (GPL-3, the user's own code, which already ran on Forever), ported and slimmed down:

| XpieHUD part | Used for |
|---|---|
| Position: a post-hook on each window's `SetPoint`, centre saved in UIParent units, an invisible drag handle over the title bar, the `positioning` re-entry guard | The shared position |
| `FadeUI` / `RestoreUI` (alpha only, restored at once when combat starts, minimap moved away rather than faded) | Hiding the UI, as one switch with a fixed list |
| The key frame (`SetPropagateKeyboardInput` only out of combat, reset on key-up), `SelectGossip` through the gossip ScrollBox data provider, greeting buttons, reward choices, `HandleSpace` with the PvP and gold-cost exceptions | Keyboard controls |
| Badges (option, quest and reward styles) and the Space/Esc hints | Kept, with the refinements below |

| Tooltips at the cursor while talking: a `GameTooltip_SetDefaultAnchor` post-hook, plus moving the tooltip that's already open when the window appears | Keyboard & mouse only |

Not used: the Parchment addon, its 6 MB of masks, the quest-look hand-off, Guide Addons, followers, and the per-group hide toggles.

## The plugin

- **Files:** `Plugins/Quest/` holds `Quest.lua` (registration, settings, status), `Choice.lua` (the XpieUI-or-DialogueUI note), `Position.lua`, `Fonts.lua`, `HideUI.lua`, `Keys.lua`, `Badges.lua`, `Camera.lua` and `Spoken.lua`.
- **Registration:** `RegisterPlugin("quest", {...})` with no target addon, because it styles Blizzard's own windows.
- **If DialogueUI is loaded,** the user picks which quest module to use (see "Choosing between XpieUI and DialogueUI" below).

### 0. Choosing between XpieUI and DialogueUI

The two can't run together: DialogueUI takes over Blizzard's quest and gossip windows, and our plugin works on them.

**When the choice appears:** at login or reload, if DialogueUI is loaded and the Quest plugin is enabled.
- Until the user chooses, the Quest plugin stays inactive (no hooks, no keys, no camera) and DialogueUI works as normal.
- If the user is in combat, the choice waits until combat ends.

**The note:** a small XpieUI window in the middle of the screen, in the same native style as the XpieUI settings window. It's not a StaticPopup: those break the controller UI (see the gamepad-taint memory).
- It reads: "XpieUI's Quest module isn't compatible with DialogueUI. Which one would you like to use for quests and dialogue?"
- It has two buttons, **Use XpieUI** and **Use DialogueUI**, and both work with mouse, keyboard and controller:
  - Our own gamepad handler: D-pad moves the gold arrow, A picks.
  - Keyboard: Left/Right or Tab to move, Enter or Space to pick.

**The window doesn't close any other way.** No Esc and no close button, so the conflict is always settled.

| Choice | What happens |
|---|---|
| **Use XpieUI** | `C_AddOns.DisableAddOn("DialogueUI")` and `C_AddOns.SaveAddOns()`, then a reload from the button click. After the reload DialogueUI isn't loaded, and the Quest plugin runs. |
| **Use DialogueUI** | The Quest plugin is switched off (`db.enabled = false`). No reload is needed, because the plugin never hooked anything. The XpieUI settings page shows "Quest module: DialogueUI". |

**Remembered:** the choice is saved, so the note never repeats on its own. It only comes back if both end up on again. That happens when the user turns DialogueUI back on in the AddOns list while the Quest plugin is enabled, or turns the Quest plugin back on while DialogueUI is enabled.

**Switching later:** the Quest page has a **Quest Module: XpieUI / DialogueUI** choice that does the same thing in reverse.
- Choosing DialogueUI: `EnableAddOn("DialogueUI")`, the Quest plugin off, then a reload.
- Choosing XpieUI: the same as the table above.

**Which characters:**
- `DisableAddOn` and `EnableAddOn` are called **without** a character name: the probe showed that passing the player's name changes nothing on Forever, while no name changes every character.
- The default is **every character**, which matches how the AddOns list shows DialogueUI today.

**Spoken integration:** while DialogueUI is the chosen module, the Spoken integration puts nothing on Blizzard's windows, because those windows aren't in use. Spoken's own DialogueUI style takes over.

Settings page, the whole list:

| Setting | Default |
|---|---|
| Quest Module | XpieUI or DialogueUI (shown when DialogueUI is installed) |
| Enabled | on |
| Font Size | 100%, from 80 to 150% |
| Hide UI While Talking | on |
| Camera | on |
| Keyboard Controls | on (keyboard & mouse only) |
| Spoken Integration, two highlight colours | on when Spoken is installed (see section 6) |
| Move Windows / Reset Position | buttons |

### 1. Shared position

The windows that share one saved point:
- `QuestFrame`, for every quest page: greeting, detail, progress and reward
- `GossipFrame`
- `ItemTextFrame` (books, letters and plaques)

All three are 338 px wide "left area" panels, so one top-left point fits every one.

- **Moving:** dragging the title bar of any of them moves the shared point, and the window that's open moves with it.
  - The controller cursor wasn't confirmed to drag (the probe's working drag used the mouse). So the Quest page gets a **Move Windows** button: the quest window appears at the shared point, the D-pad nudges it (holding moves faster), A saves and B cancels. It uses our own gamepad handler, as the XpieUI settings window does.
- **Saving:** the point is saved in `XpieUIForeverDB`, so it survives reload, logout, exit and restart. WoW writes saved variables on logout, reload and normal exit. A crash loses only moves made since the last reload.
- **Staying on screen:** the point is clamped to the screen, so it is still valid after a resolution or UI-scale change.
- **Native positioning:** Blizzard's panel manager still decides when a window opens. We only move it afterwards, through the `SetPoint` post-hook XpieHUD used. We never write `UIPanelWindows` and never call `ShowUIPanel`.
- **Moving in combat** works (these panels aren't protected on Forever). The probe confirms it.
- The NPC model panel beside `QuestFrame` is anchored to it, so it moves with it.

### 2. Font size

The quest fonts are scaled with one percentage. They keep Blizzard's typeface, colours and flags, and the windows keep their size; long text simply scrolls.

| Font object | Used for |
|---|---|
| `QuestFont` | body text, objectives, reward text, greeting text, book text |
| `QuestFontLeft` | gossip and quest list rows |
| `QuestTitleFont` | titles and section headers |
| `QuestFontNormalSmall` | objective lines, timer |
| `QuestFont_Huge` / `QuestFont_Large` | seal text, large book text |

These are shared font objects, so the quest details in the world map and quest log grow too. That keeps quest text one size everywhere.

- **Method:** `SetFont(file, baseSize * pct, flags)` on each object, with the base sizes read once at login.
- **Linked fonts:** the probe confirmed that `QuestFontLeft` follows `QuestFont` live (13 → 17 → 13). So we only set the parent objects (`QuestFont`, `QuestTitleFont`, `QuestFontNormalSmall`, `QuestFont_Huge`, `QuestFont_Large`), and their children follow.
- **Reward names** use `GameFontHighlight`, which the whole UI shares, so they aren't scaled. Scaling them would grow every tooltip and panel.

### 3. Hide UI while talking

The goal matches the user's DialogueUI screenshot: nothing on screen except the world, the speaker and the dialogue window.

- **What fades:** every child of UIParent, by alpha.
- **What stays:**
  - the quest, gossip and book windows
  - `GameTooltip` and `ItemRefTooltip`
  - shown StaticPopups
  - Spoken's player
  - the controller prompts of Blizzard's gamepad UI
- **Minimap:** moved away, as XpieHUD did, because it draws blips that ignore alpha.
- **Coming back:** everything returns when the window closes, or at once if combat starts.

DialogueUI hides the UI with `SetUIVisibility(false)`. We can't do that: Blizzard's quest windows are children of UIParent, so they would vanish too. Fading by alpha gives the same picture.

### 3b. Tooltips at the cursor (keyboard & mouse only)

This is XpieHUD's behaviour, brought back as it was. While a dialog is open, tooltips that would sit in the screen corner (now faded away) appear at the mouse. The NPC's tooltip that's already open moves to the cursor as soon as the window opens. It's off under the controller UI, which has no cursor.

### 4. Keyboard controls (keyboard & mouse only)

- **Mode detection:** we check whether Forever's gamepad UI is on at login and listen to the `INPUT_DEVICE_INTERFACE_TRANSITION` event. While the controller UI is on, our key frame, badges and hints are off, and Blizzard's prompts and SmartNavigation work untouched. We never call `InputUtil.Register*` and never join Blizzard's gamepad navigation.

Keys, while a quest, gossip or book window is open and you're out of combat:

| Key | Action |
|---|---|
| W / S (and Up / Down) | Move the highlight through the gossip options, the greeting list or the reward choices |
| A / D (and Left / Right) | On a reward page: move between reward columns. On a book: turn the page. Anywhere else: pass through to the game |
| Space | Click the highlighted row. With nothing highlighted, Accept, Continue or Complete, or the next book page (as in XpieHUD) |
| 1–9, 0, Shift+1–9 | Pick that row directly (XpieHUD's numbering, up to 19) |
| Esc | Blizzard's own close |

- **Passing keys through:** any key that does nothing goes through to the game, so movement and the camera still work when nothing is picked.
- **WASD while the window is open:** W and S are taken for the highlight, so you can't walk forward or back with them while a window is open. Esc closes the window.
- **The highlight** is Blizzard's own `UI-QuestTitleHighlight` on rows and `UI-QuestItemHighlight` on rewards. The gold `gamepad-largecursor-white` arrow (the XpieUI settings window's focus mark) sits beside it, so the focus is easy to see.
- **Click-only cases:** PvP quests and quests that cost gold open a StaticPopup, so Space doesn't confirm them. They still need a click (XpieHUD's rule, to keep the popup system clean).
- **Badge refinements** (tuned against native screenshots):
  - one badge size for single and double digits
  - Blizzard's narrow number font
  - badges that line up with the text baseline at every font size
  - the Space/Esc hints placed under the buttons
  - badges and hints that scale with Font Size

### 5. Camera

One fixed behaviour, the same as DialogueUI's **Camera Movement: Zoom In** with **Zoom Multiplier 4** and **Change FOV** on (the user's setup in the screenshot). It works with both keyboard & mouse and the controller, and has no options beyond on/off.

How DialogueUI does it (`Code/Camera.lua`), rewritten in our own code:

1. **Measure the speaker.** A hidden ModelScene actor loads the NPC's model with `SetModelByUnit("npc")`, and its bounding-box height gives the NPC's size.
   - If that fails, a medium size is used. Objects and boards with no NPC model get only the gentler pan below.
2. **Pick the zoom.** DialogueUI's height table gives the distance, times 2.5 (multiplier 4):
   - under 2 → 2
   - under 2.6 → 3
   - under 4 → 4
   - under 5.1 → 5
   - under 6.1 → 6
   - under 8 → 10
   - otherwise height + 2, with no zoom past 28.5

   The camera only zooms in, never out. The zoom from before is saved with `GetCameraZoom()`.
3. **Turn to the speaker.**
   - Blizzard's interact-focus camera is set: `test_cameraTargetFocusInteractEnable` 1, eased in over 1 s with pitch strength and `pitchlimit`.
   - `test_cameraOverShoulder` moves the speaker away from the window's side of the screen.
   - The field of view narrows a little.
   - DialogueUI also changes `CameraKeepCharacterCentered` and `CameraReduceUnexpectedMovement`. We change the same settings, save each value first, and restore each one when the window closes.
4. **Put it back** when the window closes: the settings, the zoom (`CameraZoomOut` back to the saved zoom), `pitchlimit 88` and the field of view.
   - **Gossip → quest:** going from gossip to a quest page in the same conversation counts as one conversation (XpieHUD's 0.15 s restore delay), so the camera doesn't bounce.
   - **Combat:** if combat starts, everything is restored at once. DialogueUI marks the focus settings as safe in combat.
5. **Mounted and in instances:** mounted, the shoulder offset is scaled as DialogueUI does by default ("Maintain Offset While Mounted" on). In instances, the camera works too (that DialogueUI option is off by default).

**Blizzard's experimental-camera warning popup** (probe results):
- **DialogueUI's trick doesn't work on Forever.** The popup is raised by Blizzard's own event handler (`Blizzard_Game/Shared/EventRouting.lua`), not by UIParent, so unregistering it on UIParent does nothing.
- **When it shows:** once per login, the first time a `test_camera*` setting is turned on. After Accept it doesn't return until the next login.
- **What the buttons do:** Accept keeps the settings. Disable runs `ResetTestCVars()`.

**The user's choice: ask at login.**
- A couple of seconds after the loading screen, out of combat and only while the Quest camera is on, we set `test_cameraTargetFocusInteractEnable` to 1 with both strengths at 0. That has no visible effect, but it raises Blizzard's popup while the player is just standing there.
- The value stays at 1 for the session, with strengths 0. Its original value is saved in `XpieUIForeverDB` and put back at logout, and also at the next login if the game crashed.
- **If Disable is pressed:** the value reads back as 0. For the rest of that session the camera skips its experimental parts (focus and shoulder) and keeps only the field of view and the zoom. It doesn't ask again until the next login.
- We never touch the popup itself: no `StaticPopup_Hide`, no event unregistering.

**Probe results:** under the gamepad UI, the field of view (90 → 75 eased), the turn to the speaker (pitch strength 1) and the shoulder offset (±1.5, on the side away from the window, both sides seen) all applied. Everything came back exactly in all four tests. The zoom never moved, because the user's camera (4.93 to 5.35) was already closer than DialogueUI's goal for a 2.22-tall NPC (7.5). That matches DialogueUI, which only zooms in.

### 6. Spoken integration (part of the Quest module)

The integration is turned on automatically when Spoken is installed, and turned off with one checkbox on the Quest page:

| Setting | Default |
|---|---|
| Spoken Integration | **on** when Spoken is loaded; hidden when it isn't |
| Highlight Colour (parchment) | Spoken's deep red `#9c1a1a` |
| Highlight Colour (dark) | Spoken's gold `#ffd100` |

- **On:** Spoken's controls sit at the top of our window, the words are highlighted in our window's text, and the small tooltip-style box takes over when the window closes mid-line.
- **Off:** none of that is drawn. We call `Spoken:SetPlayerHost(nil)`, and Spoken works exactly as it does on its own: its own player window and subtitles, its own settings.

It's built on Spoken's documented public API (`Spoken/API.lua`, `API_VERSION` 1). The hard requirement is `Spoken:IsCompatible(1)`, and every optional call checks first that the field exists, as Spoken's docs ask. The file is `Plugins/Quest/Spoken.lua`.

**How Spoken highlights today** (read from the source):
- **Colours:** there are only two: deep red `#9c1a1a` on light (parchment) text and gold `#ffd100` on dark text (`Spoken/UI/WordMarks.lua:21-22`).
- **Picking the colour:** Spoken picks it per paragraph from the brightness of that paragraph's text colour (`Marks.ColorFor`, luminance ≥ 0.5 means dark page, gold). It's not by dialogue type: quests, gossip and books all use the same rule. Spoken's own caption window uses gold (`Transcript.lua:11`), and its DialogueUI and minimal looks pass the red.
- **Two words at a time:** the word being spoken and the next one (`Marks.Pick` returns `lit` and `neighbor`). That's why "dangerous if" shows as a pair in the screenshot.
- **Drawn in place:**
  - Marks are colour codes written into the paragraph's own text (`Marks.Want(..., color)`), so nothing moves or rewraps.
  - The original text is put back when the line ends.
  - Spoken's "Type Words Out" option blanks words that haven't been read yet. We honour it the same way.
- **Who does this for DialogueUI:** not Spoken itself, but `Spoken_Quests/UI/DialogueUIBridge.lua` (quests and gossip) and `Spoken_Readables/UI/DialogueUIBook.lua` (books). Both stand down without DialogueUI, and we do the same job on Blizzard's windows.

**Colour control:** `Marks.Want` takes the colour as an argument, so we pass our own instead of `Marks.ColorFor`'s:
- **Parchment colour:** for the quest, gossip and book windows on parchment.
- **Dark colour:** for the small tooltip-style box, for Quest Text Contrast's dark parchment, and for stone or metal books.
- **The control:** each colour has a row of native swatches (Spoken red, gold, Blizzard's quest blue, green, white and black-brown) plus a hex box for any other colour. It's our own widget, not Blizzard's ColorPickerFrame, so it works with the controller and stays clear of Blizzard dialogs (see the gamepad-taint memory).
- **Reset:** a Reset button puts Spoken's two colours back.
- **Live:** changes apply straight away, including to the line playing now.

**Controls at the top of the window:**
- **Buttons:** Spoken's round buttons (`Spoken:CreateRoundButton`) in a row at the top right of the quest, gossip and book windows, as on DialogueUI's window: Play/Pause, Previous, Skip, and Report (only if Spoken's "hide Report buttons" setting is off).
- **Calls and updates:** they call `Spoken:TogglePause`, `Previous` and `Skip`, and update on the `CLIP_STARTED`, `CLIP_STOPPED` and `AUDIO_CHANGED` callbacks.
- **Pre-built row:** the probe confirmed that `Spoken:CreateDialogueUIRow(QuestFrame, ...)` works on Blizzard's frames, so we use Spoken's own row, placed at the window's top right.

**Words highlighted in our window:**
- **Finding and matching the line:** `Spoken:GetCaption()` gives the line's words and the word being spoken. `Spoken:WordMarks()` gives `Align`, `Pick`, `Cut`, `Spans` and `Want`, which match them to our window's text, as the DialogueUI bridge does.
- **Which text:** quest description, objectives, progress and reward text, the gossip greeting, the quest greeting, and book pages.
- **Map safety:** QuestInfo's frames are shared with the world map, so we only mark them while `QuestFrame` owns them, and always put the clean text back first. This avoids XpieHUD's old map taint.
- **Scrolling:** the window scrolls to keep the word being read in view (Spoken's AutoScroll behaviour).

**Spoken's own player while the integration is on:**
- **The aim:** Spoken's own player and subtitles shouldn't show alongside ours.
- **The method:** we host them on a hidden frame of ours with `Spoken:SetPlayerHost(frame)`, the public call Spoken made for hosts that hide UIParent.
- **Turning it off** calls `SetPlayerHost(nil)`, and Spoken's normal setup comes back. We never change Spoken's saved settings.
- **Probe result:** `SetPlayerHost(hiddenFrame)` hides both Spoken's player and its subtitles. No fallback is needed.

**The small tooltip-style box** (the user's screenshot 1): if the window closes while a line is still being read, the line carries on in a small box.
- **Look:** Blizzard's tooltip look (`TooltipDefaultLayout` NineSlice, GameTooltip fonts).
- **Contents:**
  - the speaker's round face (`Spoken:CreateSpeakerFace`)
  - the speaker and quest title
  - the control row
  - the line's text with the highlight in the dark colour
- **Placement:** it sits where the dialog window was, using the shared position, and stays visible while the rest of the UI is still faded.
- **Gone:** when the line ends or is skipped, the box fades out. Opening a new dialog moves it back into the window.

## Deliveries

Each delivery: deploy, test in game with keyboard & mouse and with the controller UI, confirm BugSack is clean, and commit.

0. **Probe** (a test build, no features). `/xui quest probe` reports:
   - controller UI detection, and that the transition event fires
   - whether `SetPoint` on QuestFrame/GossipFrame from our hook runs with the controller UI on, with no `ADDON_ACTION_FORBIDDEN` after opening and closing gossip and quests with the pad
   - whether the soft cursor can drag our handle

   **Probe results (2026-11-27), all on the user's client with the gamepad UI on:**
   - no `ADDON_ACTION_FORBIDDEN` / `_BLOCKED` events in any test
   - QuestFrame moved to the shared point every time, and kept the dragged spot (mouse drag)
   - `QuestFont` children follow live
   - every atlas the plan uses exists
   - `ClearTextureSlice` exists
   - Spoken 3.13.1 is compatible and all API fields are present
   - addon enabling: no-name calls change every character
   - camera: see Camera
   - not covered: Gossip and ItemText weren't opened while moving was on. Delivery 1 tests those first.
   - whether inherited font objects follow `QuestFont` live
   - camera: the NPC height measurement, then zoom, focus, shoulder offset and field of view separately, in both modes; whether the warning popup appears; and that every setting comes back exactly when the window closes
   - which Spoken API fields exist, whether `CreateDialogueUIRow` accepts a Blizzard frame, and whether `SetPlayerHost(hiddenFrame)` hides Spoken's player and subtitles
   - whether `C_AddOns.DisableAddOn` / `EnableAddOn` with and without a character name change one character or every character on Forever, and that the reload button works from our window
1. **Module choice and the shared position:** the XpieUI-or-DialogueUI note and the Quest Module setting, then the shared position with saving and Reset.
2. **Font size.**
3. **Hide UI while talking.**
4. **Keyboard controls**, badges, hints (refined) and tooltips at the cursor.
5. **Camera**: DialogueUI's Zoom In at multiplier 4, both modes.
6. **Spoken integration**: the checkbox and controls row first, then word highlighting with the two colour settings, then the small tooltip-style box.

## Risks

- **Taint from moving Blizzard panels** under the controller UI. XpieHUD's method ran on Forever, but probably not with the controller UI on. Delivery 0 tests it before anything is built. If it taints, the fallback is to move windows only out of combat, or only in keyboard & mouse mode, and the user decides.
- **Font sizes.** Bigger fonts show more scrolling inside Blizzard's fixed window. Some lists (city guards) at 150% may get long. That's acceptable, since the window size stays native.
- **Camera.**
  - It changes several camera settings. A crash or a disconnect mid-conversation could leave them changed, so their saved values are kept in `XpieUIForeverDB` and restored at the next login.
  - Camera addons such as DynamicCam would fight it, so the camera turns itself off if one is loaded.
- **Spoken.** The highlight uses Spoken's public alignment helper, so it should survive Spoken updates. The row helper is marked "additive" and is checked for before use.
