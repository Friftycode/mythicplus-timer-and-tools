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
- **Missing buff reminder**: flags a class party buff that has gone missing from
  a group member, but only for classes actually in the group (no nagging for
  Skyfury with no Shaman around). It only posts inside a dungeon once the key is
  actually under way, never out in the world, in a raid, or while the group is
  still buffing before the run. The wait before it flags, whether it shows in chat
  or as a popup, an anti-spam cooldown, and which class buffs to track are all
  configurable.
- **Note**: a note window tied to the dungeon you're standing in, with one
  general dungeon note plus a note per boss (pulled from the Encounter Journal).
  The dungeon note is editable any time; a boss note is editable only outside its
  fight, so it stays a fixed reference while the boss is up. Notes can also be
  **prepared ahead of time** from the Note settings tab — pick any dungeon and
  boss and write its note before you set foot inside. Each dungeon keeps its own
  notes, account-wide, surviving a reload or a wipe. They are also kept when a
  dungeon rotates out of the season, and stay listed in the prepare-ahead editor
  (labelled from the journal), so a note you wrote is still there if the dungeon
  returns. Choose whether the window is always up, appears only once a key
  starts, or stays hidden for the whole run.
  The window is resizable from its bottom-right grip, and the divider between the
  section list and the note is draggable to set how wide the list is; both are
  remembered.
- **Automation**: opt-in conveniences that react to the game's own events — auto
  repair (guild funds first, then your gold), auto sell grey junk, auto accept
  and turn in quests (everywhere or in dungeons only), a warning when a dungeon
  isn't set to Mythic, and keeping a new group listing on Mythic as you switch
  dungeons in the group finder.
- **Party, invites, and duels**: opt-in handling of what other players send you,
  ported from Leatrix Plus and living on the **Automation** tab. Auto-accept a
  party invite from a friend, auto-confirm the role check when a friend queues
  you (with your last used role, or a chosen set of Tank/Healer/DPS roles, using
  only the ones your spec can fill), invite anyone who whispers a keyword
  (friends-only optional), and block
  party invites, "requested to join" confirmations, or duels from anyone who
  isn't a friend. Guild members count as friends by default; communities are an
  opt-in. Every behaviour is off until you turn it on.
- **Test frames (edit mode)**: every movable frame only appears at its own
  moment, which is the worst possible time to be arranging your screen. One
  button in the Settings panel (or `/mpt frames`) puts them all up at once, each
  filled with example content (the run overlay shows a mid-key snapshot: clock,
  upgrade windows, enemy forces, boss kills, and a death per party member) and
  wearing a light-blue overlay like Blizzard's Edit Mode, centred on a large
  "Click to Edit". Hovering a frame names it in a tooltip by the cursor. Drag a
  frame to move it, resize the ones with a grip (the run overlay and the note
  window) right there, or click it to jump straight to that frame's settings.
  Opening the test frames hides the Settings window and puts up a small "Close
  test frames" control; closing them (its button or Escape) brings Settings back.

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
| Mythic+ Window | Guild keys this week | on | Show the guild panel in the Mythic+ Dungeons window |
| Mythic+ Window | Auto-slot your keystone | on | Put your keystone in the Font of Power when you open it |
| Mythic+ Window | Teleport from Season Best icons | on | Click a dungeon in the Mythic+ window to travel there |
| Chat | Clickable links in chat | on | Turn web addresses in chat into a link you can click to copy |
| Chat | Copy button on the chat window | on | Add a Copy button that opens the window's text in a selectable box |
| Alerts | Show which key you joined | on | Popup naming the dungeon (and the party's item level and M+ score) when a group accepts you |
| Alerts | Alert when bloodlust is called | on | On-screen alert when someone in the group calls it in chat |
| Alerts | Remind about missing party buffs | on | Flag a class buff missing from a member (only for classes in the group); delivery, wait, cooldown, and per-class tracking are configurable |
| Display | Show affixes / enemy forces / bosses / deaths | on | Drop any of these blocks from the overlay |
| Display | Show +2/+3 tick marks | on | Thin white ticks on the time bar at the upgrade windows |
| Note | Show the note window | on | A per-dungeon note window (dungeon note + a note per boss); choose always, just inside a dungeon, or hidden once the key starts. The tab also hosts a prepare-ahead editor |
| Note | Follow the fight | on | Auto-open a boss's tab as you near or pull it, and return to the Dungeon tab afterwards |
| Automation | Auto repair | on | Repair at a merchant, guild funds first when allowed, then your gold |
| Automation | Auto sell junk | off | Sell grey (junk) items at a merchant |
| Automation | Auto accept and turn in quests | in dungeons | Accept and hand in quests automatically; multi-choice rewards are left to you |
| Automation | Warn if not set to Mythic | off | Warn on entering a dungeon that isn't Mythic difficulty |
| Automation | Keep new listings on Mythic+ | on | Hold a group listing on the Mythic+ keystone as you switch dungeons; a manual pick is respected |
| Automation | Default playstyle | Competitive | Preselect the required "Select Playstyle" on a new listing (Off / Learning / Relaxed / Competitive / Carry offered) |
| Automation | Accept party invites from friends | off | Auto-accept a party invite from a friend (unless you're queued) |
| Automation | Confirm role when a friend queues | off | Auto-confirm the role check when the leader who started it is a friend; confirm with your last used role or a chosen set of roles |
| Automation | Roles to confirm as | Tank, Healer, DPS | Which roles "Chosen roles" confirms as; only roles your current spec can fill are used, so an all-roles set still queues a DPS-only alt as DPS |
| Automation | Invite when whispered a keyword | off | Invite whoever whispers your keyword (default "inv"); a "Keyword" box and an "Only invite friends" toggle sit beside it |
| Automation | Block party invites | off | Decline party invites from anyone who isn't a friend |
| Automation | Block requested invites | off | Decline "requested to join your group" confirmations from non-friends |
| Automation | Block duels | off | Decline duel requests from non-friends |
| Automation | Treat guild members as friends | on | Count online guild members as friends for the options above |
| Automation | Treat community members as friends | off | Count online community members as friends for the options above |
| General | Show the minimap button | on | A minimap button whose menu opens Settings, toggles Let me focus, or hides itself |

**Profiles** keeps more than one set of settings: create, reset, or delete
profiles, set one as the account **main**, copy another profile's settings into
the current one with the **Copy from** dropdown (so a new profile can start from
an existing look), and share a profile with an export/import string. Characters follow the main profile until you switch one to
another profile yourself; a character you switch stays on its choice, while every
character you have not switched moves with the main (so a brand-new character
starts on whatever the main currently is). The export string is complete: it
carries every setting the addon has, each at its current value, so an import
reproduces the whole profile on its own.

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
| `MythicPlusTimerandTools/MythicPlusTimerandTools.toc` | Addon manifest and load order |
| `MythicPlusTimerandTools/Core.lua` | Palette, config, and the registries features declare themselves into |
| `MythicPlusTimerandTools/Timer.lua` | The M+ run overlay |
| `MythicPlusTimerandTools/GuildKeys.lua` | Guild keys this week |
| `MythicPlusTimerandTools/Keystone.lua` | Auto-slot your keystone |
| `MythicPlusTimerandTools/Teleports.lua` | Spellbook teleport lookup, and the Season Best click targets |
| `MythicPlusTimerandTools/JoinPopup.lua` | Which key did I just join |
| `MythicPlusTimerandTools/Chat.lua` | Clickable links, and copying a chat window |
| `MythicPlusTimerandTools/Bloodlust.lua` | Bloodlust called in chat |
| `MythicPlusTimerandTools/BuffReminder.lua` | Missing party-buff reminder |
| `MythicPlusTimerandTools/Notepad.lua` | Per-dungeon and per-boss note window |
| `MythicPlusTimerandTools/Automation.lua` | Vendor, quest, and group-listing conveniences |
| `MythicPlusTimerandTools/Social.lua` | Party from friends, queue confirm, invite on whisper, and blocking invites/duels |
| `MythicPlusTimerandTools/KeystoneShare.lua` | Party key sharing and the "!keys" reply |
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
| `.github/workflows/release.yml` | Keep-alive job: releases when the repo has been idle 30+ days, keeping the interface current |

## Changelog

Kept here until the next tagged release picks it up.

### Unreleased

- **Timer counts the death penalty**: deaths add to the scored clock (Challenger's
  Burden), so the big countdown, the time bar, and the +2/+3 windows now work off
  run time plus the death penalty instead of wall time alone. The clock now runs
  out exactly when the key stops being timeable, rather than still showing time
  left after a death-heavy run has already blown the timer. The frozen completion
  screen is unchanged (it already uses Blizzard's final time).

- **Boss note tabs show on entering the dungeon**: the per-boss tabs used to
  appear only once the keystone started, because the map and journal data isn't
  ready the instant you zone in. The note now re-checks for a few seconds after
  entering, so its dungeon and boss tabs are there straight away.

- **Reworked "When to show it" for the note**: three clearer choices - "Always"
  (shown everywhere the note is on, in or out of a dungeon), "Just inside dungeon"
  (only while you are inside a dungeon), and "Hide at key start" (shown from
  entering the dungeon, then hidden once the key starts). Existing settings carry
  over: the old always-in-dungeon becomes "Just inside dungeon" and the old
  hide-during-the-run becomes "Hide at key start".

- **Guild keys panel is fully opaque**: the "Guild keys this week" box inside the
  Mythic+ window no longer lets anything another addon draws in the same spot bleed
  through it. Its background is now solid rather than slightly see-through.

- **Confirm as multiple roles**: "Confirm role when a friend queues" now offers
  "Chosen roles" with a Tank/Healer/DPS multi-select instead of a single role. Only
  the roles your current spec can fill are used, so one set carries across
  characters, an all-roles pick still confirms a DPS-only alt as DPS, and if none of
  the ticked roles fit the spec it keeps your last used role. An existing single-role
  setting migrates to "Chosen roles" with that role ticked.

- **Edit mode is clearer**: the test-frame overlay now shows a large, centred
  "Click to Edit", and names the frame you are pointing at in a tooltip by the
  cursor rather than inside the box. Opening the test frames hides the Settings
  window and shows a small movable "Close test frames" control (always at the same
  spot); closing edit mode (its button or Escape) brings Settings back.

- **Party key row shows the level**: the party-key dropdown truncates only the
  dungeon name with a trailing "...", so the character name and "+level" stay
  visible instead of the level being clipped off the end.

- **Party key dropdown moved inside the window**: the party-key selector now sits
  on its own row at the top of the Premade Groups Create screen, lined up with the
  dungeon and difficulty dropdowns below it (caption on the left box's edge, selector
  ending on the right box's edge, a solid dark band spanning between). It no longer
  floats to the right of the window over a Raider.IO-style overlay.

- **Buff reminder is dungeon-only**: the missing-buff reminder now posts only
  inside a dungeon once the key is under way. It no longer fires out in the world
  or in a raid, and still stays quiet while the group is buffing before the pull.
- **Party key title fixed**: picking a party key from the create-a-group dropdown
  now reliably writes the "+level" title. Selecting the dungeon activity had been
  auto-filling the title box first, so the "+level" write was skipped.
- **Party, invites, and duels** (Automation): opt-in social handling ported from
  Leatrix Plus, all off by default. Accept a party invite from a friend, confirm
  the role check when a friend queues you (as your last used role or a fixed
  Tank/Healer/Damage role your spec can fill), invite anyone who whispers a keyword
  (default "inv", with a friends-only toggle and Battle.net whispers inviting the
  sender), and block party invites, "requested to join" confirmations, or duels
  from non-friends. A shared friend gate decides who counts: character and
  Battle.net friends always, online guild members by default, community members
  as an opt-in. Each toggle takes effect without a reload.
- **Settings scroll**: a tab taller than the panel now scrolls, using the same
  slim scrollbar as the Note editor, so a long tab no longer runs off the frame.
- **Test frames become an edit mode**: the test frames now show example content
  (the run overlay draws a full mid-key snapshot) under a light-blue Edit
  Mode-style overlay. Drag a frame to move it, click it to jump to its settings
  section, or press Escape to close. Reached from the General tab or `/mpt
  frames`.
- **Complete profile export**: the export string now includes every setting at
  its effective value, not only the ones a profile changed, so a shared or
  backed-up profile is fully self-contained.
- **Copy from another profile**: a "Copy from" dropdown on the Profiles page
  copies a chosen profile's settings into the active one, so a new profile can
  start from an existing look rather than the defaults. An inline, fading line
  confirms what was copied (no popup).
- **Old notes kept across seasons**: dungeon and boss notes are never dropped for
  a dungeon rotating out of the season. They stay in the store and remain listed
  in the prepare-ahead editor, so they are still there if the dungeon returns.
- **Any profile is deletable**: the Default profile can now be deleted like any
  other, as long as one profile remains. Deleting the account main promotes the
  only other profile automatically, or asks you to pick a main first when there
  is more than one to choose from.
- **Boxes start at the top**: the profile export box (and any other multi-line
  box holding a lot of text) now opens scrolled to its first line instead of the
  bottom.
- **Resizable Note window**: the note window has a bottom-right resize grip and a
  draggable divider that sets the section-list width; both persist per profile.
  Frames that resize can be resized from within the test-frames edit mode too.
- **Right-sized scrollbars**: every scrollbar thumb is now sized to the visible
  fraction of its content (with a floor), through one shared helper, so a short
  box no longer shows a thumb that fills it and they all match.
- **Profiles follow the main**: a character now tracks the account main profile
  until you switch that character to another profile yourself. Un-switched
  characters (including brand-new ones) move with the main when it changes; a
  switched character keeps its own choice. The resolved default is no longer
  recorded as a per-character pin.
- **Missing buff reminder** (Alerts): flags a class party buff missing from a
  group member, but only for classes present in the group. Configurable wait
  (15–60 s), party-chat / popup / both delivery, an anti-spam cooldown, and
  per-class tracking of Arcane Intellect, Fortitude, Battle Shout, Mark of the
  Wild, Skyfury, and Blessing of the Bronze. The party-chat announcement is
  coordinated over an addon-message channel: when several group members run the
  addon, only one posts and they share the cooldown.
- **Note** (renamed from Notepad): a per-dungeon note window kept account-wide in
  `MythicPlusTimerNotes` (keyed by the Encounter Journal instance id), with three
  visibility modes. Holds a general dungeon note (editable any time) plus a note
  per boss (editable only outside the fight). **Follow the fight** (on by default)
  opens a boss's tab as you near or pull it and returns to the dungeon tab
  afterwards. Notes render **markdown** when shown — `#`/`##`/`###` headings,
  `-`/`1.` lists, `>` quotes, `---` dividers, `**bold**`, `*italic*`, `` `code` ``,
  `~~strike~~` — and are raw text while editing; the scrollbar is slim and
  appears only when the note overflows. Notes can be prepared ahead of time from
  the Note settings tab, sharing the same store. Old flat-string notes migrate
  into the dungeon slot.
- **Automation** (Automation): auto repair (guild funds first), auto sell junk,
  auto accept / turn in quests (always / never / in dungeons), a non-Mythic
  difficulty warning, and keeping a new group listing on **Mythic+** across
  dungeon changes. In dungeons a single unambiguous quest dialog is progressed,
  but a "leave the instance" option is never auto-clicked. The listing default is
  best-effort against Blizzard's protected create panel and wants in-game
  verification; it never touches the List Group action, and a manual difficulty
  pick is respected. A **default playstyle** (Off / Learning / Relaxed /
  Competitive / Carry offered, default Competitive) can likewise be preselected
  on a new listing — hardcoded values since `GetPlaystyleString` is protected.
- **+2/+3 tick marks** on the run timer's time bar (Display), on by default.
- **Settings**: the tab strip now wraps instead of running off the panel; choice
  settings are dropdowns that open below the box with a chevron that flips up when
  open; checkboxes, entry boxes and dropdowns line up in one control column;
  General is the first tab, and the test-frames button (which now also toggles the
  note window) lives there. The **Dungeons window** tab is renamed **Mythic+
  Window**.
- **Quieter**: routine confirmations (keystone slotted, repaired, junk sold,
  test frames) no longer print to chat.
- **Bug reports / feature requests**: the About tab and the CurseForge page now
  link the GitHub Issues page, and `.github/ISSUE_TEMPLATE/` carries bug and
  feature templates plus a config. Enabling Issues on the repo is a one-time
  GitHub setting.

## Releases

The `keep-alive release` workflow builds the addon zip and uploads it to
CurseForge with the BigWigsMods packager (`CF_API_KEY` secret), stamping the
current retail Interface number and tagging the release along the way.
`.pkgmeta` names `MythicPlusTimerandTools` as the addon folder and lists the
repo scaffolding to leave out of the zip.

What actually makes WoW/CurseForge flag an addon as out of date is the `##
Interface:` number in the `.toc` lagging the live client, not the file's age.
Keeping that number current for the live patch (and shipping a file for it) is
what this workflow automates, entirely in GitHub's cloud, so it happens whether
or not your computer is on. No external service is needed.

- **CI** (`test.yml`) runs the test gate on every push and pull request.
- **Keep-alive release** (`release.yml`) runs a daily scheduled check, but a
  `gate` job only lets a release through when 30+ days have passed since the last
  commit (a manual `workflow_dispatch` always releases). So an idle repo gets a
  fresh release every 30 days, while any commit you make resets that clock. When
  it releases it reads the current live retail interface number from Blizzard's
  own version service (the live `wow` product, never the PTR), stamps it into the
  `.toc`, re-runs the tests, commits, and pushes a `v<version>` tag, then
  packages and uploads to CurseForge. The keep-alive commit also keeps the cron
  itself alive (GitHub suspends schedules on repos idle for 60 days); the 30-day
  cadence resets that timer well before it can trip. For zero ambiguity over very
  long absences, set a `RELEASE_PAT` repository secret (a fine-grained PAT with
  Contents: read/write): the release then pushes with it, so the keep-alive
  commit counts unambiguously as user activity. Without it, the workflow falls
  back to the default token and still works.

## License

[MIT](LICENSE).
