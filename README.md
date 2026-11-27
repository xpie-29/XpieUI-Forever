# XpieUI-Forever

A WoW Forever addon (Interface 16001): a settings shell with built-in plugins that make popular addons look like part of Blizzard's native interface. Ported from XpieHUD.

| Plugin | Styles | Status |
|---|---|---|
| Zygor Guides | ZygorGuidesViewerForever | in progress |

Each plugin only runs when the addon it styles is loaded, and can be turned off in settings (takes a `/reload`).

## Develop and test

- The addon itself is the `XpieUI-Forever/` folder; the rest of the repo (docs, tools) never ships.
- `Tools/deploy.sh` copies it into `/Applications/World of Warcraft/_forever_/Interface/AddOns/XpieUI-Forever/` (set `WOW_FOREVER_ADDONS` to use another AddOns folder). Then `/reload` in game, or restart WoW if files were added.
- Build plan: [docs/plan.md](docs/plan.md).

## Slash commands

| Command | |
|---|---|
| `/xui`, `/xpieui` | Open settings (Options > AddOns > XpieUI Forever) |
| `/xui status` | Each plugin's state |
| `/xui reset` | Reset all settings (type twice) |
| `/xui zygor` | Check the Zygor plugin can see Zygor (testing) |
