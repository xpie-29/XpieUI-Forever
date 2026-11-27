# XpieUI-Forever

A WoW Forever addon (Interface 16001): a settings shell with built-in plugins that make popular addons look like part of Blizzard's native interface. Ported from XpieHUD.

| Plugin | Styles | Status |
|---|---|---|
| Zygor Guides | ZygorGuidesViewerForever | Deliveries 1–3 done |
| Quest Windows | Blizzard's quest, gossip and book windows (not compatible with DialogueUI: you choose one at login) | Delivery 1: module choice, shared window position ([plan](docs/quest-plan.md)) |

Each plugin only runs when the addon it styles is loaded, and can be turned off in settings (takes a `/reload`).

## Develop and test

- The addon itself is the `XpieUI-Forever/` folder; the rest of the repo (docs, tools) never ships.
- `Tools/deploy.sh` copies it into `/Applications/World of Warcraft/_forever_/Interface/AddOns/XpieUI-Forever/` (set `WOW_FOREVER_ADDONS` to use another AddOns folder). Then `/reload` in game, or restart WoW if files were added.
- Build plan: [docs/plan.md](docs/plan.md).

## Slash commands

| Command | |
|---|---|
| `/xui`, `/xpieui` | Open or close the settings window (also reachable from Options > AddOns > XpieUI Forever) |
| `/xui status` | Each plugin's state |
| `/xui reset` | Reset all settings (type twice) |
| `/xui zygor` | Check the Zygor plugin can see Zygor (testing) |
| `/xui zygorpos` | Report Zygor's window position and clamping (testing) |
| `/xui arrowdebug` | Report Zygor arrow state changes in chat (troubleshooting) |
