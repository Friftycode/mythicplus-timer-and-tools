# Mythic+ Timer and Tools

A lightweight Retail WoW addon built around a Mythic+ key: a clean run timer overlay plus the smaller conveniences you reach for before, during, and after a dungeon. Everything is optional and configurable, and nothing runs outside a party dungeon unless you ask it to.

***

## During a run

* **Timer overlay:** a movable, scalable overlay showing time remaining, the +2 and +3 upgrade windows (with tick marks on the bar), this week's affixes, live enemy forces %, per-boss kill times, and a death counter with class colors and time lost.
* **Let me focus:** click the clock or the death list to hide it for a pull, click again to bring it back.
* **Auto-slot your keystone:** opening the Font of Power drops your key straight in. Never in combat, and never over a key someone else already slotted.
* **Enemy nameplates:** turn nameplates on as a key starts and put your setting back when it ends.
* **Note window:** a per-dungeon note plus a note per boss (from the Encounter Journal), rendered as light markdown. Follow the fight opens a boss's tab as you pull it and returns to the dungeon tab afterward. A one-click toggle collapses the section list to widen the note. Notes survive reloads and wipes, and can be written ahead of time from the settings.

## Around the group

* **Guild keys:** your guild's best keys this reset, shown inside Blizzard's own Mythic+ window, with party composition on hover.
* **Party key dropdown:** group members running the addon share the keystone they hold, so the create-a-group panel offers a dropdown of everyone's keys (your own included, even solo). Pick one to fill in that dungeon and a +level title, while difficulty and playstyle stay on your defaults.
* **Keystone on request:** when someone types !keys in party, instance, or guild chat, the addon links the keystone you're carrying. Works for anyone asking, whether or not they run the addon.
* **Group Finder details:** when you're accepted into a group, see the dungeon, leader, listing text, and a teleport button when you have one.
* **Missing buff reminder:** flags a class buff missing from a group member, but only for classes actually present. Choose party chat, a popup, or both, set a per-class list, a missing-time threshold, and an anti-spam cooldown. Announcements are coordinated so only one addon user posts.
* **Bloodlust alert:** an on-screen notice when someone calls bl, hero, lust, or drums in chat.

## Conveniences

* **Season Best teleports:** click a dungeon in your Season Best row to cast its teleport.
* **Start a group defaults:** keep a new listing on your preferred difficulty and playstyle as you switch dungeons, and get warned when a dungeon isn't set to Mythic.
* **At a merchant:** auto repair (guild funds first, if you allow it) and auto-sell grey junk.
* **At quest givers:** auto accept and turn in quests, everywhere or in dungeons only. A "leave the instance" option is never auto-clicked.
* **Chat:** turn URLs into click-to-copy popups, and add a Copy button to each chat tab that exports its history as plain text.
* **Minimap button:** a small launcher for Settings and Let me focus. Drag it around the ring, or hide it.
* **Test frames:** show every movable frame at once to place and scale your UI before a run.

***

## Commands

* `/mpt` - open the settings panel
* `/mpt frames` - show or hide the test frames
* `/mpt guild` - toggle the guild keys panel
* `/mpt lock` - lock or unlock the overlay
* `/mpt reset` - put the overlay back where it started

***

## Bug reports & feature requests

Found a bug or have an idea? Head to the [GitHub Issues page](https://github.com/Friftycode/mythicplus-timer-and-tools/issues).
