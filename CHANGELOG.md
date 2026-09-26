# Sharpie's Gear Judge - XP Bar (Changelog)
---
## 🚀 v1.0.1
### ⚔️ Gear Judge Integration
- **Upgrades Waiting in Your Bags**: Scans your bags for items SGJ rates as upgrades but that you're too low level to equip. The tooltip lists them by unlock level, and when one unlocks at the next level its icon sits at the end of the bar.
- **Level-Up Gear Alert**: On level-up, a "Ding!" alert lists the bag upgrades you can now equip (also printed to chat as clickable links) and any unspent talent points. Left-click opens your bags; right-click dismisses it.
- **Stat Weight Change Warning**: Within 2 levels of a leveling weight band change (e.g. 20 -> 21), the tooltip shows the likely new profile and the biggest weight changes, so you know which items may re-rank. When a profile changes name between bands (Paladin DPS: `Leveling_41_51` -> `Leveling_Ret_52_59`), the warning uses the next band's profile that doesn't continue from an earlier band.
- **Mail/Plate Training Look-Ahead**: Warriors and Paladins (Plate) and Hunters and Shamans (Mail) now see those items under "Upgrades Waiting" before 40, marked "Train Mail at 40". At 40, the level-up alert reminds you to visit your trainer.
- **Stats Box Matches the Tooltip**: The standalone box and the bar's tooltip are built from the same list of lines, so the box now shows everything the tooltip does (rested plan, full upgrade list, weight warning, quest details). It resizes to fit, supports Shift-click to reset, and the level-up alert anchors to the box when the bar is hidden.
- **Quest Turn-In Projection**: Adds up completed quests in your log. A translucent gold section on the bar shows where you'll land after turning them in, and the tooltip says how many of them reward an upgrade and whether turning them in will level you. Quests under collapsed quest log headers aren't counted.
- **Gear Score Tracking**: Shows your SGJ character score and how much it grew this level. It's logged per level for each character.
- **Rested XP Planning**: The tooltip shows how much of the level your rested XP covers and roughly how many kills it lasts.
- **New Options**: A "Gear Judge Integration" column in the XP Tracker tab toggles each feature, plus a new Quest Turn-In color swatch.

### 🐛 Bug Fixes
- **Session Reset**: `SGJ_ResetXPSession` was defined twice, and the second copy didn't reset kill/quest counts or refresh the bar.
- **Quest XP Tracking Never Worked**: `CHAT_MSG_SYSTEM` was handled but never registered. Quest XP now comes from `QUEST_TURNED_IN` where the client has it, and chat parsing is the fallback.
- **Session Reset on Every Loading Screen**: Zoning or entering an instance restarted the session timer without clearing its totals, which inflated XP/hour. The session now starts once per login.
- **XP Lost on Level-Up**: Leftover XP from the previous level was calculated with the new level's max XP.
- **Hardcoded Level 70 Cap**: The bar stayed visible at max level on Era and Forever. It now uses the client's max level.
- **Localized Kill Parsing**: Kill and quest messages are matched using the client's own message formats, so tracking works on non-English clients.
- **Forever / Era TOCs**: Added `SharpiesGearJudge_XP_Forever.toc` and `SharpiesGearJudge_XP_Vanilla.toc` so the plugin isn't flagged out of date on those clients.
- **Cleanup**: Removed the unused `L1`-`L7` stats-box font strings and the duplicate drag handlers.

## 🚀 v1.0.0
### ✨ Features & Updates
- **Rested XP UI Updates**: Upgraded the visual tracking of the experience bar. The bar now draws a classic, translucent blue "tail" extending outward to show exactly where your rested XP ends.
- **Rested Tooltips**: Added exact Rested XP mathematical data directly into the tooltip when hovering over the experience bar.