# Mythic+ Timer and Tools

![test](https://github.com/Friftycode/mythicplus-timer-and-tools/actions/workflows/test.yml/badge.svg)

A retail World of Warcraft addon with two pieces:

- **M+ run timer overlay**: a movable panel shown for the duration of an active
  Mythic+ run. Time remaining, the +2/+3 upgrade windows, this week's affixes,
  enemy forces, one row per boss with its kill time, and a death count with
  class-colored names and the clock time each death cost.
- **Guild keys this week**: your guild's best keys for the current weekly reset,
  drawn inside Blizzard's own Mythic+ Dungeons window. Key level, dungeon, and
  who ran it, in three columns. Hover a row for the whole dungeon name and that
  key's party.
- **Which key did I just join?**: apply to a dozen listings and it's easy to
  lose track of which one accepted you. Joining a Mythic+ group through the
  Group Finder pops up the dungeon, the leader, their listing text, and a table
  of the party (name, item level, M+ score), with a one-click teleport when your
  character owns one for that dungeon.
- **Teleport from Season Best**: click any dungeon in the Season Best row of the
  Mythic+ Dungeons window to travel there. Icons you have no teleport for stay
  as they were.
- **Clickable links in chat**: a web address someone posts arrives as plain text,
  and chat text can't be selected, so the only way to use it is to read it off
  the screen and type it back in. Addresses become real links instead. Click one
  and a box opens with it already selected, ready for Ctrl+C.
- **Copy the chat window**: a Copy button in each chat window's top-right corner
  opens that window's own history in the same box, links and textures flattened
  to the plain text they displayed, each line kept in the color chat drew it in.
- **Bloodlust alert**: when someone in your group types bl, hero, lust, drums, or
  any of the other ways people write it, a short alert says so on screen.
- **Minimap button**: a small button on the minimap. Click it for a menu that
  opens Settings, toggles Let me focus, or hides the button itself; drag it to
  move it around the minimap. Bring it back from **General** in the Settings.
- **Test frames**: every movable frame only appears at its own moment, which is
  the worst possible time to be arranging your screen. One button in the
  Settings panel (or `/mpt frames`) puts them all up at once so you can drag
  them where you want them, and takes them all away again.

Every number comes straight from the game client's own Challenge Mode /
Scenario API. There is no bundled data, no download, and no network access:
a WoW addon has none at runtime, and this one ships no data files at all.

## Install

Copy the `MythicPlusTimerandTools` folder into
`World of Warcraft/_retail_/Interface/AddOns`, then enable **Mythic+ Timer and Tools** in the
AddOns list.

## Settings

Open **Settings, AddOns, Mythic+ Timer and Tools** (or `/mpt`). Expand it (the
"+" in the AddOns list) for two sub-pages: **Settings**, which lays the options
out under horizontal tabs, and **Profiles**.

| Section | Option | Default | What it does |
| --- | --- | --- | --- |
| Run overlay | M+ run timer overlay | on | Show the overlay during an active key |
| Run overlay | Enable enemy nameplates in keys | on | Turn enemy nameplates on at key start, restore your setting when it ends |
| Run overlay | Let me focus | off | Click the clock or the deaths on the overlay to hide them |
| Mythic+ window | Guild keys this week | on | Show the guild panel in the Mythic+ Dungeons window |
| Mythic+ window | Auto-slot your keystone | on | Put your keystone in the Font of Power when you open it |
| Mythic+ window | Teleport from Season Best icons | on | Click a dungeon in the Mythic+ window to travel there |
| Chat | Clickable links in chat | on | Turn web addresses in chat into a link you can click to copy |
| Chat | Copy button on the chat window | on | Add a Copy button that opens the window's text in a selectable box |
| Alerts | Show which key you joined | on | Popup naming the dungeon (and the party's item level and M+ score) when a group accepts you |
| Alerts | Alert when bloodlust is called | on | On-screen alert when someone in the group calls it in chat |
| Display | Show affixes / enemy forces / bosses / deaths | on | Drop any of these blocks from the overlay |
| General | Show the minimap button | on | A minimap button whose menu opens Settings, toggles Let me focus, or hides itself |

**Profiles** keeps more than one set of settings and remembers which each
character uses: create, copy, reset, or delete profiles, set one as the default
for new characters, and share a profile with an export/import string.

Under the checkboxes is **Show or hide test frames**, which puts every movable
frame on screen at once with placeholder content so you can drag them where you
want them.

The overlay's position, lock state, and scale are set from the overlay itself:
drag it to move, the padlock in its top-right corner to pin it, the grip in the
bottom-right corner to resize.

| Command | |
| --- | --- |
| `/mpt` | Open the settings panel |
| `/mpt guild` | Toggle the guild keys panel |
| `/mpt lock` | Lock or unlock the overlay |
| `/mpt reset` | Put the overlay back at its default position and scale |
| `/mpt frames` | Show or hide every movable frame at once |

## Notes on what it does and doesn't do

- **Enemy forces** is the banked count only. As of patch 12, an enemy's
  `UnitGUID` and `C_ScenarioInfo.GetUnitCriteriaProgressValues` come back as
  secret values to addon code inside a key, and secrets can't be summed or
  deduped, so there is no honest way for an addon to total up what the current
  pull is worth. Blizzard renders that in its own secure mob tooltip.
- **Death attribution** is done by polling each party unit's dead/ghost state,
  not by reading the combat log: registering `COMBAT_LOG_EVENT_UNFILTERED`
  throws `ADDON_ACTION_FORBIDDEN` as of patch 12.
- **The +2/+3 thresholds** (finishing with more than 40%/20% of the timer left)
  are current keystone math as of patch 12.0.7. Blizzard has changed them
  before, so that's the one number worth rechecking if upgrades ever look off.
- **Auto-slot only ever reacts to you opening the Font of Power**, which is the
  request to put your key in it. It then calls
  `C_Container.PickupContainerItem` and `C_ChallengeMode.SlotKeystone`. Neither
  is protected. It stays out of the way when a key is already slotted (so it can
  never displace a group member's) and when you're in combat (item pickup is
  blocked there), it re-checks the bag slot before touching anything, and it
  prints to chat when it acts, so an item never moves silently. The checkbox
  turns it off.
- **Dungeons are named exactly as the client names them.** The guild panel's
  rows are narrow and a long name clips. That is on purpose: the client has one
  name per dungeon and no abbreviation of it, so any short form would be either
  a table this repo has to edit every season or initials derived from the name
  that come out wrong for half the dungeons. Blizzard's own string is the one
  thing that is always right and never needs maintaining, so the dungeon gets
  the widest column and hovering the row gives the whole name.
- **"Let me focus" hides, it never stops counting.** With it on, clicking the
  clock or the deaths on the overlay replaces that block with "Hidden". Both are
  still tracked the whole time, so clicking again shows the real state rather
  than a gap, and which one you hid survives a reload.
- **No key level is invented from a listing.** Blizzard exposes the dungeon of a
  Group Finder listing as structured data, but not the keystone level, because
  the leader types that into their title. So the title is shown exactly as
  written and no number is parsed out of it.
- **Teleports are read from your spellbook, never from a table of spell ids.**
  Those ids change every expansion, and a stale one would offer the wrong
  destination. Casting is protected, so the button is a real secure button and
  can only be armed out of combat.
- **A link click copies, it does not browse.** The client has no API that opens
  a browser, so there is nothing behind the box but your clipboard. Only an
  explicit `http://`, `https://`, or `www.` address is linked; a bare
  `something.com` in a sentence is a guess, and guessing would color ordinary
  words. Text that is already a link (an item, a spell, a player) is passed
  through untouched, and every other link still opens what it always did.
- Otherwise read-only and passive: it draws an overlay, reads the scenario API,
  and hides Blizzard's own duplicate tracker while ours is up. No automation of
  gameplay, no combat functions, no network access, no ads.

## Tests

There is no Lua interpreter or WoW client in CI, so the addon is exercised
under [fengari](https://fengari.io) against a mock of the client API
(`test/mockwow.lua`). `test/spec.lua` drives a whole key start to finish and
asserts on what the overlay actually renders. The runner loads exactly the files
the `.toc` lists, in `.toc` order, so a file that would not load in game is not
tested either.

The mock proves the addon's own logic, not the client's: anything that depends
on a real event firing or on how a frame lands on screen still has to be checked
in game.

```bash
npm test
```

## Layout

One file per feature. The `.toc` is the load order and the dependency order:
`Core.lua` first, features next, the shared surfaces last. A feature depends on
`Core.lua` and on nothing else.

| Path | Purpose |
| --- | --- |
| `MythicPlusTimerandTools/MythicPlusTimer.toc` | Addon manifest and load order |
| `MythicPlusTimerandTools/Core.lua` | Palette, config, and the registries features declare themselves into |
| `MythicPlusTimerandTools/Timer.lua` | The M+ run overlay |
| `MythicPlusTimerandTools/GuildKeys.lua` | Guild keys this week |
| `MythicPlusTimerandTools/Keystone.lua` | Auto-slot your keystone |
| `MythicPlusTimerandTools/Teleports.lua` | Spellbook teleport lookup, and the Season Best click targets |
| `MythicPlusTimerandTools/JoinPopup.lua` | Which key did I just join |
| `MythicPlusTimerandTools/Chat.lua` | Clickable links, and copying a chat window |
| `MythicPlusTimerandTools/Bloodlust.lua` | Bloodlust called in chat |
| `MythicPlusTimerandTools/Minimap.lua` | Minimap button and its menu |
| `MythicPlusTimerandTools/Media/minimap-icon.tga` | The minimap button and AddOns-list icon |
| `MythicPlusTimerandTools/Options.lua` | Settings panel and `/mpt`, generated from the registries |
| `MythicPlusTimerandTools/Panel.lua` | Tabbed Settings sub-page and the Profiles page |
| `test/mockwow.lua` | Mock WoW client API |
| `test/spec.lua` | Behavior tests |
| `test/run.js` | Runner: luaparse syntax gate, then fengari |
| `scripts/current-interface.mjs` | Reads the live retail interface number from Blizzard's version service |
| `scripts/apply-release.mjs` | Stamps a version (and interface) into the `.toc` and `package.json` |
| `scripts/generate-icon.mjs` | Renders the addon icon (`Media/minimap-icon.tga`) and the CurseForge image |
| `.pkgmeta` | Tells CurseForge's packager which folder is the addon |
| `.github/workflows/test.yml` | CI: runs `npm test` on every push and pull request |
| `.github/workflows/release.yml` | Monthly job that keeps the interface current and tags a release |

## Releases

The `monthly release` workflow builds the addon zip and uploads it to
CurseForge with the BigWigsMods packager (`CF_API_KEY` secret), stamping the
current retail Interface number and tagging the release along the way.
`.pkgmeta` names `MythicPlusTimerandTools` as the addon folder and lists the
repo scaffolding to leave out of the zip.

- **CI** (`test.yml`) runs the test gate on every push and pull request.
- **Monthly release** (`release.yml`) runs on the 1st of each month (and on
  demand). It reads the current live retail interface number from Blizzard's own
  version service (the live `wow` product, never the PTR), stamps it into the
  `.toc`, re-runs the tests, commits, and pushes a `v<version>` tag. CurseForge
  packages that tag. If nothing else changed, the fresh tag still re-publishes
  for the live client so the addon never shows as out of date.

## License

[MIT](LICENSE).
