# XpieUI-Forever: shell + Zygor plugin

## Context

Build **XpieUI-Forever**, a WoW Forever addon (client 1.60.1, Interface 16001). It is a settings shell with built-in plugins. Each plugin restyles a popular addon so it looks like Blizzard's native Forever UI. The first plugin is **Zygor Guides** (`ZygorGuidesViewerForever`).

The original XpieHUD (`_assets/XpieHUD-main`, git-ignored) is the reference. We port and adapt its Core, Panels, Settings and Zygor code. Its quest window features and other extensions are left out.

Decisions already made:

| Topic | Decision |
|---|---|
| Packaging | One addon folder, `XpieUI-Forever`, with plugins built in. Each plugin turns on only when its target addon is loaded, and has its own Enabled switch. |
| Shell scope | Settings panel, plugin registry, native background panels and settings widgets. No quest window features (DialogueUI is installed). |
| Art | Blizzard's built-in Forever art only. The one exception is Zygor's gold arrow, `arrow.tga`, copied from `_assets`. |
| Code | Port and adapt XpieHUD. |

Defaults for the small open points (change them at review if you like):

| Point | Default |
|---|---|
| Addon icon | A Blizzard icon path (native-only) |
| Slash command | `/xui` and `/xpieui` |
| Settings name | "XpieUI Forever" |
| Output | `/Applications/World of Warcraft/_forever_/Interface/AddOns/XpieUI-Forever/`, overwritten on each delivery |

## Repo layout

```
.gitignore                 _assets/, .DS_Store   (already written)
docs/plan.md               copy of this plan, committed so Orca worktrees see it
README.md
Tools/deploy.sh            rsync -a --delete XpieUI-Forever/ → AddOns/XpieUI-Forever/
XpieUI-Forever/            the addon (only this folder is deployed)
  XpieUI-Forever.toc       Interface 16001, SavedVariables XpieUIForeverDB
  Core/Core.lua            namespace XpieUI, CopyDefaults, Print, ApplyAll (+ after combat)
  Core/Plugins.lua         registry
  Core/Panels.lua          native background panel (Quest Tracker / Tooltip looks)
  Core/Widgets.lua         checkbox, slider, dropdown, edit box, panel section
  Core/Settings.lua        Blizzard Settings category + one sub-page per plugin
  Plugins/Zygor/Zygor.lua
  Plugins/Zygor/Media/arrow.tga
```

Code is ported from these source files in `_assets/XpieHUD-main/`:

| Source | Ported into |
|---|---|
| `XpieHUD_Core/Core.lua` (`RegisterModule`, `CopyDefaults`, `ApplyAll`) | `Core.lua` and `Plugins.lua` |
| `XpieHUD_Core/Panels.lua` (`CreatePanel`, `NormalizePanelStyle`, `PANEL_DEFAULTS`) | `Panels.lua` |
| `XpieHUD_Core/Settings.lua` (`Settings.RegisterCanvasLayoutCategory` / `Subcategory`) | `Widgets.lua` and `Settings.lua` |
| `XpieHUD_Zygor/Zygor.lua` (924 lines) | `Plugins/Zygor/Zygor.lua` |

## Phase 0: repo setup
- Write `Tools/deploy.sh`. It refuses to run if the AddOns folder is missing, and prints the version it deployed.
- Write a README stub.
- Commit `.gitignore` and `docs/plan.md` on branch `feat/shell-and-zygor`, so the Orca worktree session can find the plan.

## Phase 1: the shell → Delivery 1
1. **TOC and Core:**
   - Global `XpieUI`.
   - Saved variables use deep `CopyDefaults`.
   - `ApplyAll` runs after settings changes and on `PLAYER_REGEN_ENABLED`.
   - Nothing protected is touched in combat.
2. **Registry:** `XpieUI:RegisterPlugin(id, def)` takes the XpieHUD module fields (`title`, `defaults`, `Migrate`, `OnLogin`, `Apply`, `BuildSettings`), plus:
   - `addon`: the target addon's folder name. The shell watches `ADDON_LOADED` for it and also checks `C_AddOns.IsAddOnLoaded`, then calls `OnTargetLoaded` once. That is after the target's files have run and before it builds its windows.
   - `db.enabled`: changing it prompts for `/reload`.
   - If the target addon is missing, the plugin's page says so and the plugin does nothing.
3. **Panels:**
   - Quest Tracker look: Edit Mode background, gold header bar, optional title. The other look is Tooltip.
   - Settings: opacity, header/border, title, padding.
   - The panel follows the target frame's size, alpha and visibility.
   - Each atlas is checked with `C_Texture.GetAtlasInfo`. If one is missing, the panel falls back to the Tooltip look and says so once.
4. **Settings:**
   - Main page: version, plus each plugin with its Enabled switch and whether its target addon was found.
   - One sub-page per plugin.
5. **Slash commands:**
   - `/xui` opens settings.
   - `/xui reset` resets everything after two confirmations.
   - Plugins can add their own sub-commands.

## Phase 2: Zygor plugin → Delivery 2 (2a–2c), Delivery 3 (2d–2h)
The plugin offers two styles: **XpieUI** (default) and **Original** (leaves Zygor alone).

- **2a. Plumbing:**
  - Target `ZygorGuidesViewerForever`. Replace the 4 hard-coded `ZygorGuidesViewer` names, and build arrow paths from `ZGV.ARROWSDIR`.
  - In `OnTargetLoaded`, do what XpieHUD's `OnZygorLoaded` does: register the arrow skin, hook `ZGV_DefaultSkin_DefaultStep_Mixin`, and apply the font.
  - Post-hook `ZGV.Frame:ApplySkin`.
  - Re-apply to steps Zygor has already built (`ApplySkinToSteps`), in case it loaded first.
  - Confirmed present in Zygor Forever 1.6 under `Skins/Default/`: `SetBackgroundForStep`, `Border.Back`, `Border.TitleBar` (with `Logo`), `Border.Toolbar`, `Border.TabContainer`, `MenuButton`, `CloseButton`, and `ZGV.Pointer:AddArrowSkin`.
- **2b.** Make the window chrome transparent, hide the logo, and use `STANDARD_TEXT_FONT`.
- **2c.** Put the native background panel behind the guide window, titled "Leveling Guide".
- **2d.** Replace the title bar buttons with Blizzard's gold settings gear and red close button.
- **2e.** Put the toolbar on the tracker's section-header art, with a gold step number and flat arrows.
- **2f.** Restyle guide tabs with chat tab art and a gold glow on the selected tab.
- **2g.** Keep step boxes in Zygor's state colours at an adjustable opacity, without edges.
- **2h.** Register the gold arrow as the "XpieUI Gold" skin, with a toggle. Turning it off restores the previous skin. Add `/xui arrowdebug`.
- **Settings page:** Style, Gold Arrow, Step Box Opacity, the panel controls, and Reset Panel.

## Risks
- Some atlases or templates may differ from retail 12.1.5. Each one is checked at runtime and has a fallback.
- Zygor Forever's sizes and anchors may differ from retail Zygor. All frame access is nil-guarded, and layout gets tuned in game.
- Hooking Zygor can't cause taint because Zygor isn't secure code. The addon never calls `Hide()` or `Show()` on Blizzard Edit Mode frames.

## Verification
Each delivery follows the same steps:
1. Run `Tools/deploy.sh`.
2. In game, check:
   - BugSack shows no errors on login or after `/reload`.
   - Settings persist across `/reload`.
3. Check what each delivery adds:
   - **Delivery 1:** the "XpieUI Forever" settings category appears with the Zygor sub-page, and `/xui` opens settings.
   - **Delivery 2:** Zygor's window is transparent, uses Blizzard's font, and has the native panel behind it, which resizes and hides with the window. The Original style restores Zygor's own look after `/reload`.
   - **Delivery 3:** the gear and close buttons, toolbar and tabs are styled; the step box opacity slider works; the gold arrow appears while navigating, and toggling it restores the previous skin.
4. Commit once per delivery. You decide when to merge into `main`.
