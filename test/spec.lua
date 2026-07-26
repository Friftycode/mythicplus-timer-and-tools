-- Behavior tests for MythicPlusTimer, driven against the mock client in mockwow.lua.
-- These exercise the real render path (what the overlay actually draws), not
-- just that the file loads.

local failures, checks = {}, 0

local function ok(cond, what)
  checks = checks + 1
  if not cond then failures[#failures + 1] = what end
end

local function has(haystack, needle, what)
  ok(haystack:find(needle, 1, true) ~= nil, what .. "  [missing: " .. needle .. "]")
end

local function hasNot(haystack, needle, what)
  ok(haystack:find(needle, 1, true) == nil, what .. "  [unexpected: " .. needle .. "]")
end

local overlay = function() return _G.MythicPlusTimerFrame end
local guild = function() return _G.MythicPlusTimerGuildFrame end

-- ── Login ─────────────────────────────────────────────────────────────────

Mock.fire("PLAYER_LOGIN")

ok(Mock.settings.category == "Mythic+ Timer and Tools", "settings category is 'Mythic+ Timer and Tools'")

-- The tabbed page is the only settings surface, so every option is drawn there.
local settingsPages = MythicPlusTimerNamespace.panels.settings.pages
local keys, boxCount = {}, 0
for _, page in pairs(settingsPages) do
  for key in pairs(page.checks) do keys[key] = true; boxCount = boxCount + 1 end
end
ok(boxCount == 15, "fifteen checkboxes drawn, got " .. boxCount)
ok(keys.mythicplustimer and keys.autonameplates and keys.letmefocus and keys.guildkeys
  and keys.autoslotkey and keys.joinpopup and keys.seasontp and keys.chatlinks
  and keys.chatcopy and keys.bloodlust and keys.minimapbutton,
  "all the option keys present")

for _, o in ipairs(MythicPlusTimerNamespace.OPTIONS) do
  ok(o.group ~= nil, "option '" .. o.key .. "' declares a section")
  ok(settingsPages[o.group] ~= nil,
    "option '" .. o.key .. "' has a tab for its group '" .. tostring(o.group) .. "'")
  ok(settingsPages[o.group].checks[o.key] ~= nil,
    "option '" .. o.key .. "' is drawn on that tab")
end

-- Rows sharing a sub-heading have to stay adjacent, or it is drawn twice.
local seenSection, sectionDupes, lastSection = {}, 0, nil
for _, o in ipairs(MythicPlusTimerNamespace.OPTIONS) do
  ok(o.section ~= nil, "option '" .. o.key .. "' declares a sub-heading")
  local id = tostring(o.group) .. "/" .. tostring(o.section)
  if id ~= lastSection then
    if seenSection[id] then sectionDupes = sectionDupes + 1 end
    seenSection[id] = true
    lastSection = id
  end
end
ok(sectionDupes == 0, "no sub-heading is opened twice")

ok(SlashCmdList.MYTHICPLUSTIMER ~= nil, "/mpt slash command registered")
ok(#Mock.prints == 0, "login prints nothing (no data bundle to report)")

-- ── Key start ─────────────────────────────────────────────────────────────

Mock.fire("START_TIMER", 1, 10)
Mock.fire("CHALLENGE_MODE_START")
Mock.runTimers()

ok(overlay() ~= nil, "overlay frame created")
ok(overlay():IsShown(), "overlay shown at key start")
ok(Mock.cvars.nameplateShowEnemies == "1", "enemy nameplates turned on at key start")
ok(ScenarioObjectiveTracker:IsShown() == false, "Blizzard's own tracker hidden")
ok(MythicPlusTimerRun ~= nil and MythicPlusTimerRun.mapID == 375, "run mirrored into MythicPlusTimerRun")

-- The 10s activation countdown means the scored clock has not started yet.
Mock.advance(11)
local r = Mock.rendered(overlay())
has(r, "Mists of Tirna Scithe", "title shows the client's dungeon name")
has(r, "+10", "title shows the key level")
has(r, "elapsed", "elapsed row drawn")
has(r, "30:00 max", "time limit row drawn from GetMapUIInfo")
has(r, "Enemy forces", "enemy forces row drawn")
has(r, "17,31 %", "enemy forces percent formatted from quantityString (45/260)")
has(r, "Bosses", "bosses section drawn")
has(r, "Bloodtwisted Overseer", "boss row drawn from the criteria API")
has(r, "not done", "unkilled boss reads 'not done'")
has(r, "Deaths", "deaths section drawn")
has(r, "0 total", "death total drawn")
has(r, "+3 in", "the +3 upgrade window counts down")
has(r, "+2 in", "the +2 upgrade window counts down")

-- ── Upgrade windows expire ────────────────────────────────────────────────
-- 60% of 1800s is 1080s: past that, +3 is gone but +2 is still live.

Mock.advance(1100)
r = Mock.rendered(overlay())
has(r, "+3 missed", "+3 window closes past 60% of the timer")
has(r, "+2 in", "+2 window still open at 61%")

-- ── Deaths ────────────────────────────────────────────────────────────────

Mock.state.dead.party1 = true
Mock.state.deathCount = 1
Mock.fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
Mock.advance(1)
r = Mock.rendered(overlay())
has(r, "Healer", "the party member who died is named")
has(r, "1 total", "death total tracks Blizzard's own counter")
-- +10 key: 5s per death (Challenger's Burden below +12).
has(r, "-0:05", "lost time shown for the death penalty")

-- ── Enemy forces at 100% ──────────────────────────────────────────────────
-- "Can we leave yet" should be answerable from the color, without reading the
-- digits, so a finished count turns green.

has(Mock.rendered(overlay()), "|cffffffff17,31 %", "an unfinished count stays white")

Mock.state.criteria[1].quantityString = "260 / 260"
Mock.advance(1)
has(Mock.rendered(overlay()), "|cff4ade68100,00 %", "a finished count turns the row green")

-- The color has to agree with the number on screen. 259.99/260 displays as
-- "100,00 %" after rounding, so it must be green too: a white "100,00 %" would
-- have the row's own two halves contradicting each other.
Mock.state.criteria[1].quantityString = "259.99 / 260"
Mock.advance(1)
has(Mock.rendered(overlay()), "|cff4ade68100,00 %", "a count that rounds to 100 is green as well")

-- Blizzard's own completed flag is enough on its own, whatever the arithmetic.
Mock.state.criteria[1].quantityString = "45 / 260"
Mock.state.criteria[1].completed = true
Mock.advance(1)
has(Mock.rendered(overlay()), "|cff4ade6817,31 %", "the client calling it complete is enough")
Mock.state.criteria[1].completed = false
Mock.advance(1)
has(Mock.rendered(overlay()), "|cffffffff17,31 %", "and an unfinished count goes back to white")

-- ── Boss kill ─────────────────────────────────────────────────────────────

Mock.state.criteria[2].completed = true
Mock.advance(1)
r = Mock.rendered(overlay())
has(r, "killed", "a defeated boss reads 'killed' with its kill time")

-- ── Display toggles ───────────────────────────────────────────────────────
-- The Display settings drop a whole block from the overlay for good, unlike the
-- per-run "Let me focus" click.

MythicPlusTimerNamespace.setCfg("showbosses", false)
MythicPlusTimerNamespace.setCfg("showdeaths", false)
MythicPlusTimerNamespace.setCfg("showforces", false)
Mock.advance(1)
r = Mock.rendered(overlay())
hasNot(r, "Bosses", "turning off Show bosses drops the bosses section")
hasNot(r, "Deaths", "turning off Show deaths drops the deaths section")
hasNot(r, "Enemy forces", "turning off Show enemy forces drops that row")
has(r, "elapsed", "the timer itself stays")

MythicPlusTimerNamespace.setCfg("showaffixes", false)
Mock.advance(1)
ok(overlay().affixArea:IsShown() == false, "turning off Show affixes hides the affix row")

for _, k in ipairs({ "showbosses", "showdeaths", "showforces", "showaffixes" }) do
  MythicPlusTimerNamespace.setCfg(k, true)
end
Mock.advance(1)
r = Mock.rendered(overlay())
has(r, "Bosses", "the blocks come back when the toggles are turned on again")
has(r, "Enemy forces", "enemy forces is back too")

-- ── Completion ────────────────────────────────────────────────────────────

Mock.fire("CHALLENGE_MODE_COMPLETED")
Mock.runTimers()
r = Mock.rendered(overlay())
has(r, "20:00 elapsed", "clock freezes at Blizzard's own completion time")
hasNot(r, "not done", "every boss is marked defeated on completion")
ok(MythicPlusTimerRun == nil, "the saved run record is cleared once the key is over")
ok(Mock.cvars.nameplateShowEnemies == "0", "the player's nameplate setting is restored")

-- The frozen overlay must not keep ticking.
local frozen = Mock.rendered(overlay())
Mock.advance(30)
ok(Mock.rendered(overlay()) == frozen, "a finished run's overlay is frozen for review")

-- Leaving the instance closes it.
Mock.state.inInstance = false
Mock.advance(1)
ok(overlay():IsShown() == false, "overlay closes when the player leaves the dungeon")
ok(ScenarioObjectiveTracker:IsShown(), "Blizzard's tracker is handed back")

-- ── Guild keys this week ──────────────────────────────────────────────────

Mock.state.guildLeaders = {
  { keystoneLevel = 12, mapChallengeModeID = 376, name = "Topdps", classFileName = "MAGE",
    members = { { name = "Topdps", classFileName = "MAGE" }, { name = "Healer", classFileName = "PRIEST" } } },
  { keystoneLevel = 18, mapChallengeModeID = 377, name = "Keypusher", classFileName = "PALADIN", members = {} },
}
Mock.showFrame(ChallengesFrame)

ok(guild() ~= nil, "guild panel created inside ChallengesFrame")
ok(guild():IsShown(), "guild panel shown with the Mythic+ window")
local g = Mock.rendered(guild())
has(g, "Guild keys this week", "guild panel titled")
has(g, "+18", "highest key listed")
has(g, "De Other Side", "dungeon named from the client, not a bundled table")
has(g, "Keypusher", "the run's owner is named")
local plus18 = g:find("+18", 1, true)
local plus12 = g:find("+12", 1, true)
ok(plus18 and plus12 and plus18 < plus12, "rows sorted highest key first")

-- The level, the dungeon and the player are three separate columns now, so the
-- level right-aligns on its own and both names left-align.
local topRow = guild().rows[1]
ok(topRow.level:GetText():find("+18", 1, true) ~= nil, "the level is its own column")
ok(topRow.dungeon:GetText():find("De Other Side", 1, true) ~= nil,
  "the dungeon is its own column, named in full")
ok(topRow.who:GetText():find("Keypusher", 1, true) ~= nil, "the player is its own column")

-- Hovering a row lists that key's party, class-colored, with no score column.
-- Row 1 is the +18, whose roster Blizzard returned empty, so it must draw
-- nothing rather than an empty box. Row 2 is the +12 with a real party.
GameTooltip.lines = {}
local row1 = guild().rows[1].frame
row1.__scripts.OnEnter(row1)
ok(#GameTooltip.lines == 0, "a row with no recorded party opens no tooltip")

local row2 = guild().rows[2].frame
row2.__scripts.OnEnter(row2)
local tt = table.concat(GameTooltip.lines, "\n")
has(tt, "Topdps", "party member listed on hover")
has(tt, "Healer", "second party member listed on hover")
has(tt, "The Necrotic Wake", "the full dungeon name is one hover away from the short one")
hasNot(tt, " | ", "no score column (the character db is gone)")

-- ── Slash commands ────────────────────────────────────────────────────────

SlashCmdList.MYTHICPLUSTIMER("guild")
ok(guild():IsShown() == false, "/mpt guild toggles the panel off")
SlashCmdList.MYTHICPLUSTIMER("guild")
ok(guild():IsShown(), "/mpt guild toggles it back on")

SlashCmdList.MYTHICPLUSTIMER("")
ok(Mock.settings.opened, "/mpt with no argument opens the Settings panel")

MythicPlusTimerNamespace.setCfg("mpscale", 1.7)
SlashCmdList.MYTHICPLUSTIMER("reset")
ok(MythicPlusTimerNamespace.cfg("mpscale") == 1, "/mpt reset restores the default scale")
ok(MythicPlusTimerNamespace.cfg("mppoint") == nil, "/mpt reset clears the saved position")

-- Each feature file registers its own subcommands, so the set below is the
-- proof that every file was loaded AND that the .toc order let it register.
-- MythicPlusTimerNamespace is the runner's stand-in for the addon table the client
-- passes to every file; in game it has no global name.
local registered = {}
for _, c in ipairs(MythicPlusTimerNamespace.commands) do registered[c.name] = true end
ok(registered.lock and registered.reset, "the timer registered its commands")
ok(registered.guild, "the guild panel registered its command")

-- Every registered command has to actually run, since nothing else calls them.
for _, c in ipairs(MythicPlusTimerNamespace.commands) do
  local okRun = pcall(SlashCmdList.MYTHICPLUSTIMER, c.name)
  ok(okRun, "/mpt " .. c.name .. " runs without erroring")
end
-- That loop flipped whatever those commands toggle; put the stateful ones back
-- so the sections below start from a known state. /mpt frames put every test
-- frame on screen, so running it again takes them away.
MythicPlusTimerNamespace.setCfg("mplocked", false)
if not guild():IsShown() then SlashCmdList.MYTHICPLUSTIMER("guild") end
SlashCmdList.MYTHICPLUSTIMER("frames")

-- The help line is generated from the same list, so it can never drift from it.
Mock.prints = {}
SlashCmdList.MYTHICPLUSTIMER("nonsense")
local help = table.concat(Mock.prints, "\n")
has(help, "/mpt guild", "an unknown command prints the generated help")
has(help, "/mpt lock", "and it lists every command that declared help text")

-- ── Guild panel respects its setting ──────────────────────────────────────

MythicPlusTimerNamespace.setCfg("guildkeys", false)
Mock.showFrame(ChallengesFrame)
ok(guild():IsShown() == false, "guild panel stays hidden when the option is off")
MythicPlusTimerNamespace.setCfg("guildkeys", true)

-- ── Not in a guild ────────────────────────────────────────────────────────

Mock.state.inGuild = false
Mock.showFrame(ChallengesFrame)
has(Mock.rendered(guild()), "You are not in a guild.", "honest empty state when guildless")
Mock.state.inGuild = true

-- ── Guild panel keeps a fixed height ──────────────────────────────────────
-- Always room for five entries, so the box doesn't resize as keys land through
-- the week. It must also stay narrow enough to clear Blizzard's centered
-- "Mythic+ Rating" text, which is what the width is tuned against.

Mock.showFrame(ChallengesFrame)
local twoKeyHeight = guild().__height
ok(guild().__width and guild().__width <= 210,
  "panel is narrow enough to clear the centered rating text")

Mock.state.guildLeaders = {
  { keystoneLevel = 20, mapChallengeModeID = 375, name = "A", classFileName = "MAGE", members = {} },
  { keystoneLevel = 19, mapChallengeModeID = 376, name = "B", classFileName = "MAGE", members = {} },
  { keystoneLevel = 18, mapChallengeModeID = 377, name = "C", classFileName = "MAGE", members = {} },
  { keystoneLevel = 17, mapChallengeModeID = 375, name = "D", classFileName = "MAGE", members = {} },
  { keystoneLevel = 16, mapChallengeModeID = 376, name = "E", classFileName = "MAGE", members = {} },
}
Mock.showFrame(ChallengesFrame)
ok(guild().__height == twoKeyHeight, "five keys draw the same height as two")
local g5 = Mock.rendered(guild())
has(g5, "+20", "all five rows drawn when five keys exist")
has(g5, "+16", "the fifth row is drawn")

-- Back to two keys: the empty rows below must be blank, not last render's text.
Mock.state.guildLeaders = {
  { keystoneLevel = 14, mapChallengeModeID = 375, name = "Joemaama", classFileName = "MAGE", members = {} },
  { keystoneLevel = 8, mapChallengeModeID = 376, name = "Frifti", classFileName = "PALADIN", members = {} },
}
Mock.showFrame(ChallengesFrame)
local g2 = Mock.rendered(guild())
ok(guild().__height == twoKeyHeight, "two keys still draw the full-height box")
hasNot(g2, "+20", "stale rows from the previous render are cleared")
hasNot(g2, "+16", "the emptied rows draw nothing")

-- ── Keystone auto-slot ────────────────────────────────────────────────────

-- The Font of Power is inside the dungeon, and the earlier timer tests left the
-- player standing outside one.
Mock.state.inInstance = true

-- The insert is deferred by design, so every case below has to let the timer run.
local function openFont()
  Mock.fire("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
  Mock.advance(1)
end

-- On unless switched off: opening the Font of Power IS the request to put your
-- key in it, so nothing here waits for a second one.
ok(MythicPlusTimerNamespace.cfg("autoslotkey") ~= false, "auto-slot is on unless switched off")

-- The key goes in, and the player is told.
Mock.slotted, Mock.cursor, Mock.inserts = false, nil, 0
Mock.prints = {}
openFont()
ok(Mock.slotted, "the keystone is slotted when the Font of Power opens")
ok(Mock.cursor == nil, "the cursor is left empty afterwards")
has(table.concat(Mock.prints, "\n"), "placed", "it says so in chat rather than moving an item silently")

-- Already slotted: never disturb a key that is already in (it may be someone
-- else's, and swapping it changes which dungeon the party runs).
Mock.cursor, Mock.inserts = nil, 0
openFont()
ok(Mock.inserts == 0, "an already-slotted key is left alone")

-- Off: the setting still suppresses it entirely.
MythicPlusTimerNamespace.setCfg("autoslotkey", false)
Mock.slotted, Mock.cursor, Mock.inserts = false, nil, 0
openFont()
ok(Mock.slotted == false, "nothing is slotted while the option is off")
MythicPlusTimerNamespace.setCfg("autoslotkey", true)

-- Both events firing for one interaction must still insert exactly once.
Mock.slotted, Mock.cursor, Mock.inserts = false, nil, 0
Mock.fire("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
Mock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.ChallengeMode)
Mock.showFrame(ChallengesKeystoneFrame)
Mock.advance(1)
ok(Mock.inserts == 1, "three triggers for one interaction insert once, got " .. Mock.inserts)

-- A different interactable frame is not the Font of Power.
Mock.slotted, Mock.cursor, Mock.inserts = false, nil, 0
Mock.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 99)
Mock.advance(1)
ok(Mock.inserts == 0, "an unrelated interaction frame is ignored")

-- There is deliberately no key-matches-this-dungeon guard: the two ids that
-- would answer it are not documented to share an id space, and comparing them
-- refused every insert in a live key. Owning a key for another dungeon must
-- still slot it.
Mock.slotted, Mock.cursor, Mock.inserts = false, nil, 0
Mock.ownedKeyMapID = 1234
openFont()
ok(Mock.inserts == 1, "the key is slotted regardless of which dungeon it is for")
Mock.ownedKeyMapID = Mock.instanceID

-- The pickup silently failing must not slot whatever else was on the cursor.
Mock.slotted, Mock.cursor, Mock.inserts = false, nil, 0
local realPickup = C_Container.PickupContainerItem
C_Container.PickupContainerItem = function() end  -- nothing reaches the cursor
openFont()
ok(Mock.inserts == 0, "a pickup that never reached the cursor does not slot")
C_Container.PickupContainerItem = realPickup

-- In combat: item pickup is protected, so it must bail rather than throw.
Mock.slotted, Mock.cursor, Mock.inCombat = false, nil, true
openFont()
ok(Mock.slotted == false, "auto-slot is skipped in combat")
Mock.inCombat = false

-- No keystone in bags: nothing happens, no error.
local savedBags = Mock.bags
Mock.bags = { [0] = {}, [1] = { Mock.JUNK_LINK }, [2] = {}, [3] = {}, [4] = {} }
Mock.slotted, Mock.cursor = false, nil
openFont()
ok(Mock.slotted == false and Mock.cursor == nil, "no keystone in bags is a clean no-op")

-- The key moving out of the bag slot during the delay must abort the pickup,
-- not grab whatever took its place.
Mock.bags = { [0] = {}, [1] = { Mock.JUNK_LINK, Mock.KEY_LINK }, [2] = {}, [3] = {}, [4] = {} }
Mock.slotted, Mock.cursor, Mock.inserts = false, nil, 0
Mock.fire("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
Mock.bags[1][2] = Mock.JUNK_LINK
Mock.advance(1)
ok(Mock.inserts == 0 and Mock.cursor == nil, "a key that moved mid-delay is not blindly picked up")

Mock.bags = savedBags
MythicPlusTimerNamespace.setCfg("autoslotkey", nil)

-- ── "You joined" popup ────────────────────────────────────────────────────

local popup = function() return _G.MythicPlusTimerJoinFrame end

Mock.fire("LFG_LIST_JOINED_GROUP", 77)
ok(popup() ~= nil and popup():IsShown(), "joining an M+ group opens the popup")
local pj = Mock.rendered(popup())
has(pj, "Algeth'ar Academy", "the dungeon comes from the activity table")
hasNot(pj, "(Mythic Keystone)", "the boilerplate suffix is dropped from the name")
has(pj, "+18 AA  need dps  link io", "the leader's listing title is shown verbatim")
has(pj, "Keypusher", "the group leader is named")

-- The party table: one row per member, name + item level + M+ score. The score
-- comes from the client for everyone; item level only where an inspect exists.
has(pj, "Testchar", "the party table lists each member")
has(pj, "Healer", "including the other members")
has(pj, "2450", "with the player's own M+ score")
has(pj, "2510", "and each member's score from the client")
-- With Raider.IO installed the score is painted the exact color its API returns,
-- not a flat gold. The mock's API maps 2450 to #3399cc.
has(pj, "|cff3399cc2450", "the M+ score matches Raider.IO's own color for it")
has(pj, "489", "the player's item level shows when the client knows it")
has(pj, "-", "a member with no cached item level reads '-' rather than a guess")

-- The dungeon is structured data; a key level is not, so none is invented.
ok(popup().dungeonName == "Algeth'ar Academy", "the plain dungeon name is kept for matching")

-- Teleport: this character owns a Hero's Path flyout slot for that dungeon,
-- matched through the spell's description rather than a hardcoded spell id.
ok(popup().tp:IsShown(), "a teleport button appears when the character owns one")
ok(popup().tp.spellName == "Path of the Scholar", "the right teleport is armed")
-- The icon alone says nothing about where it sends you, so it is captioned.
ok(popup().tpLabel:IsShown(), "the teleport icon is labelled")
has(pj, "Teleport to", "and the caption says what clicking it does")

-- Column headings, and every value under its own heading. Both are laid out
-- from one table, so this catches the two drifting apart.
has(pj, "member", "the roster heads its name column")
has(pj, "ilvl", "and its item level column")
has(pj, "score", "and its score column")
for _, col in ipairs({ "name", "ilvl", "score" }) do
  local headX = select(4, popup().partyCols[col]:GetPoint())
  local rowX = select(4, popup().partyRows[1][col]:GetPoint())
  ok(headX == rowX,
    "the " .. col .. " heading sits over its column (" .. tostring(headX)
      .. " vs " .. tostring(rowX) .. ")")
end

-- Leaving the group drops a popup that no longer describes anything.
Mock.fire("GROUP_LEFT")
ok(popup():IsShown() == false, "leaving the group closes the popup")

-- A dungeon with no teleport known: the popup still opens, without a button.
Mock.activities[1301].fullName = "Pit of Saron (Mythic Keystone)"
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
ok(popup():IsShown(), "the popup still opens without a teleport")
ok(popup().tp:IsShown() == false, "no teleport button when the character owns none")
Mock.activities[1301].fullName = "Algeth'ar Academy (Mythic Keystone)"
Mock.fire("GROUP_LEFT")

-- Non-Mythic+ listings are not this addon's business.
Mock.fire("LFG_LIST_JOINED_GROUP", 78)
ok(popup():IsShown() == false, "joining a raid group opens nothing")

-- Off: the setting suppresses it entirely.
MythicPlusTimerNamespace.setCfg("joinpopup", false)
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
ok(popup():IsShown() == false, "the popup respects its setting")
MythicPlusTimerNamespace.setCfg("joinpopup", true)

-- Without Raider.IO installed, the score falls back to the client's own quality
-- color for its band (2450 is epic -> #a336ed in the mock).
local savedRIO = _G.RaiderIO
_G.RaiderIO = nil
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
has(Mock.rendered(popup()), "|cffa336ed2450", "score falls back to a quality color without Raider.IO")
_G.RaiderIO = savedRIO
Mock.fire("GROUP_LEFT")

-- Ours replaces Blizzard's "You have joined a group" acknowledgement, but only
-- for a Mythic+ join, only with the popup on, and never a live invite.
local blizNotice = function() return _G.LFGListInviteDialog end
blizNotice():Show()
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
ok(blizNotice():IsShown() == false, "Blizzard's join notice is hidden for a Mythic+ join")
Mock.fire("GROUP_LEFT")

blizNotice():Show()
blizNotice().AcceptButton:Show()
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
ok(blizNotice():IsShown(), "a live Accept/Decline invite is never hidden")
blizNotice().AcceptButton:Hide()
blizNotice():Hide()
Mock.fire("GROUP_LEFT")

blizNotice():Show()
Mock.fire("LFG_LIST_JOINED_GROUP", 78)
ok(blizNotice():IsShown(), "Blizzard's notice is left alone for a non-Mythic+ join")
blizNotice():Hide()

MythicPlusTimerNamespace.setCfg("joinpopup", false)
blizNotice():Show()
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
ok(blizNotice():IsShown(), "with the popup off, Blizzard's notice is left to do its job")
blizNotice():Hide()
MythicPlusTimerNamespace.setCfg("joinpopup", true)

-- A plain (non-flyout) teleport is found too, so the scan isn't flyout-only.
Mock.activities[1301].fullName = "Skyreach (Mythic Keystone)"
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
ok(popup().tp.spellName == "Teleport: Skyreach", "a non-flyout teleport is matched by name")
Mock.activities[1301].fullName = "Algeth'ar Academy (Mythic Keystone)"
Mock.fire("GROUP_LEFT")

-- A member's item level needs a completed inspect, so the column starts empty.
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
ok(Mock.state.inspected ~= nil, "the popup asks the client to inspect a member")
hasNot(Mock.rendered(popup()), "502", "a member's item level is absent before the inspect lands")
Mock.units.party1.ilvl = 502
Mock.fire("INSPECT_READY", Mock.units.party1.guid)
has(Mock.rendered(popup()), "502", "and appears once the client answers")
Mock.units.party1.ilvl = nil
Mock.fire("GROUP_LEFT")

-- The leader's score rides along on the listing, so it needs no inspect.
Mock.units.party3 = { name = "Keypusher", class = "WARRIOR", guid = "P-4" }
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
has(Mock.rendered(popup()), "3105", "the leader's score comes straight from the listing")
Mock.searchResults[77].leaderName = "Keypusher-Ravencrest"
Mock.fire("LFG_LIST_JOINED_GROUP", 77)
has(Mock.rendered(popup()), "3105", "and still matches when the listing carries a realm")
Mock.searchResults[77].leaderName = "Keypusher"
Mock.units.party3 = nil
Mock.fire("GROUP_LEFT")

-- ── Teleport from the Season Best icons ───────────────────────────────────

Mock.showFrame(ChallengesFrame)
local icon1 = ChallengesFrame.DungeonIcons[1]
local icon2 = ChallengesFrame.DungeonIcons[2]

ok(icon1.mptTeleport ~= nil, "a teleport button is laid over the Season Best icons")
ok(icon1.mptTeleport:IsShown(), "the icon whose dungeon has a teleport is armed")
-- The mock's teleport for that dungeon is NOT named after it, so this only
-- passes if the match fell through to the spell description.
ok(icon1.mptTeleport.spellName == "Path of the Ascended",
  "matched through the description when the spell is not named after the dungeon")
-- Icon 2 is The Necrotic Wake. A class ability's description mentions it, but
-- descriptions are only read for flyout slots, so it must not be matched.
ok(icon2.mptTeleport ~= nil and icon2.mptTeleport:IsShown() == false,
  "a class ability mentioning a dungeon is not mistaken for a teleport")

-- Hovering must still show Blizzard's own tooltip, not replace it.
local forwarded = false
icon1:SetScript("OnEnter", function() forwarded = true end)
icon1.mptTeleport.__scripts.OnEnter(icon1.mptTeleport)
ok(forwarded, "the icon's own hover handler still runs underneath")

-- Learning a teleport must take effect without a reload: the scan is cached,
-- so SPELLS_CHANGED has to drop it. Without that, a dungeon that once had no
-- teleport would keep reporting none for the rest of the session.
table.insert(Mock.flyouts[500].slots,
  { spellID = 354462, name = "Path of the Undertaker", known = true,
    desc = "Teleports you to The Necrotic Wake." })
Mock.showFrame(ChallengesFrame)
ok(icon2.mptTeleport:IsShown() == false, "a cached miss is still a miss until the spellbook changes")
Mock.fire("SPELLS_CHANGED")
Mock.showFrame(ChallengesFrame)
ok(icon2.mptTeleport:IsShown(), "a newly learned teleport is picked up after SPELLS_CHANGED")
ok(icon2.mptTeleport.spellName == "Path of the Undertaker", "and it is the right one")

MythicPlusTimerNamespace.setCfg("seasontp", false)
icon1.mptTeleport:Hide()
Mock.showFrame(ChallengesFrame)
ok(icon1.mptTeleport:IsShown() == false, "the Season Best teleports respect their setting")
MythicPlusTimerNamespace.setCfg("seasontp", true)

-- ── Clickable links in chat ───────────────────────────────────────────────

local function chatLine(msg) return Mock.chat("CHAT_MSG_GUILD", msg) end

ok(#(Mock.chatFilters.CHAT_MSG_GUILD or {}) == 1, "one chat filter is registered per channel")

-- The client reassigns arg1..arg14 from a filter's return, so a filter that
-- returns only what it reads nils the language, flags and line id.
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_SAY", "CHAT_MSG_GUILD" }) do
  Mock.chat(ev, "hello")
  local a = Mock.lastChatArgs
  ok(a[3] == "Common", ev .. " keeps its language argument through the filters")
  ok(a[11] == 11 and a[12] == "Player-1234-ABCDEF",
    ev .. " keeps its line id and guid through the filters")
end

local line = chatLine("check https://example.com/keys?a=1 for the list")
has(line, "|Hmpturl:https://example.com/keys?a=1|h", "a web address becomes a clickable link")
has(line, "check ", "the words before it are untouched")
has(line, " for the list", "the words after it are untouched")

-- Sentence punctuation belongs to the sentence, not to the address.
local dotted = chatLine("see www.example.com/x.")
has(dotted, "|Hmpturl:www.example.com/x|h", "a trailing period stays out of the address")
has(dotted, "|h|r.", "and stays in the message")

-- A line can hold both kinds of link at once.
local item = chatLine("got |cffffffff|Hitem:12345::::::::70:::::|h[Healing Potion]|h|r at www.example.com")
has(item, "|Hitem:12345", "an item link in the same line survives")
has(item, "|Hmpturl:www.example.com|h", "and the address beside it is still linked")

-- Filters can run over one message more than once; wrapping twice would make
-- a link that copies half of itself.
ok(chatLine(line) == line, "an already-linked message is left alone")

-- Nothing is guessed at: only an explicit scheme or a www. host is an address.
ok(chatLine("that pull was rough") == "that pull was rough", "a line with no address is unchanged")
ok(chatLine("meet me at example.com"):find("mpturl", 1, true) == nil, "a bare host is not guessed at")

-- Clicking: our link opens the copy box, and never reaches Blizzard's handler
-- (which throws on a link type it does not know).
Mock.blizzLinks = {}
local clicked = Mock.clickLink(line)
ok(clicked == "mpturl:https://example.com/keys?a=1", "the link carries the address")
local copy = _G.MythicPlusTimerCopyFrame
ok(copy ~= nil and copy:IsShown(), "clicking a link opens the copy box")
ok(copy.box:GetText() == "https://example.com/keys?a=1", "with the address ready to copy")
ok(#Mock.blizzLinks == 0, "our own link is consumed before Blizzard's handler")

-- Every other link still goes exactly where it always did.
Mock.clickLink(item)
ok(Mock.blizzLinks[1] ~= nil and Mock.blizzLinks[1]:find("item:12345", 1, true) ~= nil,
  "an item link still reaches Blizzard's own handler")

-- A chat window opened later is hooked too, so its links are not dead gold text.
local late = CreateFrame("Frame", "ChatFrame4")
Mock.fire("UPDATE_FLOATING_CHAT_WINDOWS")
ok(late:GetScript("OnHyperlinkClick") ~= nil, "a chat window that appears later is hooked")

MythicPlusTimerNamespace.setCfg("chatlinks", false)
ok(chatLine("see https://example.com") == "see https://example.com", "the filter respects its setting")
MythicPlusTimerNamespace.setCfg("chatlinks", true)

-- ── Copying a chat window ─────────────────────────────────────────────────

local cf1 = _G.ChatFrame1
ok(cf1.mptCopy ~= nil and cf1.mptCopy:IsShown(), "each chat window gets a Copy button")

cf1.mptCopy.__scripts.OnClick(cf1.mptCopy)
ok(copy:IsShown(), "clicking Copy opens the box")
local copied = copy.box:GetText()
has(copied, "Player says: check [Healing Potion]", "a link is copied as the words it displayed")
has(copied, "Guildie: wipe on trash again", "and every line of the window comes through")
hasNot(copied, "|T", "textures are not copied as escape codes")
hasNot(copied, "|Hitem", "nor the link markup itself")
-- The named color form current clients use for item quality survives the hex
-- pattern, so it needs stripping of its own or it lands mid-sentence as text.
has(copied, "[Thunderfury] dropped", "a named color escape is stripped too")
hasNot(copied, "|cnIQ4", "and does not leak into the box as literal text")
-- Each line carries the color the chat window drew it in, from the r/g/b
-- GetMessageInfo returns alongside the text, so the box reads like chat rather
-- than as one flat block. The mock draws every line guild green.
has(copied, "|cff40bf40", "each line keeps the color chat drew it in")
ok(select(2, copied:gsub("|cff40bf40", "")) == #Mock.chatHistory - 1,
  "every readable line is colored, and the secret one is still left out")
-- A chat window routinely holds secret values (the guild MOTD among them).
-- Note what this does NOT prove: the real ones throw when compared, so the
-- order of the checks around isSecret still has to be got right by reading.
hasNot(copied, "Message of the Day", "a secret line is left out rather than read")

-- A client that will not read a window back must say so, not copy nothing.
local realGet = cf1.GetNumMessages
cf1.GetNumMessages = nil
copy:Hide()
Mock.prints = {}
cf1.mptCopy.__scripts.OnClick(cf1.mptCopy)
ok(copy:IsShown() == false, "no box opens when the window cannot be read")
has(table.concat(Mock.prints, "\n"), "will not let an addon read", "and it says why")
cf1.GetNumMessages = realGet

MythicPlusTimerNamespace.setCfg("chatcopy", false)
Mock.fire("UPDATE_FLOATING_CHAT_WINDOWS")
ok(cf1.mptCopy:IsShown() == false, "the button respects its setting")
MythicPlusTimerNamespace.setCfg("chatcopy", true)
Mock.fire("UPDATE_FLOATING_CHAT_WINDOWS")
ok(cf1.mptCopy:IsShown(), "and comes back when it is switched on again")

-- ── Bloodlust called in chat ──────────────────────────────────────────────

local lust = function() return _G.MythicPlusTimerLustFrame end
local function partyLine(msg) return Mock.chat("CHAT_MSG_PARTY", msg) end

-- Every way people write it, and case must not matter.
for _, called in ipairs({ "bl", "BL", "Bl now", "hero", "lust pls", "HERO!", "drums",
                          "time warp", "primal rage", "pop bloodlust", "tw on pull" }) do
  Mock.prints = {}
  if lust() then lust():Hide() end
  partyLine(called)
  ok(lust() ~= nil and lust():IsShown(), "'" .. called .. "' raises the alert")
end

local alertText = Mock.rendered(lust())
has(alertText, "BLOODLUST", "the alert says what it is")
has(alertText, "Sender", "and who called it")

-- Words that merely contain one of the calls must not fire.
for _, quiet in ipairs({ "heroic dungeon after", "blame the tank", "that was lustrous",
                         "blizzard", "cast a spell" }) do
  lust():Hide()
  partyLine(quiet)
  ok(lust():IsShown() == false, "'" .. quiet .. "' is not a call")
end

-- It reads chat, it never eats it.
ok(partyLine("bl") == "bl", "the message still reaches the chat window unchanged")

-- The alert holds while the cursor is on it, so it can be dragged.
partyLine("bl")
lust().__scripts.OnEnter(lust())
Mock.advance(30)
ok(lust():IsShown(), "hovering the alert keeps it up long enough to move")
lust().__scripts.OnLeave(lust())
Mock.advance(5)
ok(lust():IsShown() == false, "and it goes away once the cursor leaves")

MythicPlusTimerNamespace.setCfg("bloodlust", false)
partyLine("bl")
ok(lust():IsShown() == false, "the alert respects its setting")
MythicPlusTimerNamespace.setCfg("bloodlust", true)

-- The alert is only for players who can answer the call: with no lust ability
-- known, a call in chat raises nothing.
Mock.playerSpells = {}
lust():Hide()
partyLine("bl")
ok(lust():IsShown() == false, "no alert when the player has no lust ability")
Mock.playerSpells = { [2825] = true }
partyLine("bl")
ok(lust():IsShown(), "the alert returns once a lust ability is known")

-- ── Test frames ───────────────────────────────────────────────────────────
-- Every movable frame only appears at its own moment, which is the worst time
-- to be arranging a screen. One button puts them all up and takes them away.

local firstTab = MythicPlusTimerNamespace.OPTIONS[1].group
local testBtn = MythicPlusTimerNamespace.panels.settings.pages[firstTab].buttons
  and MythicPlusTimerNamespace.panels.settings.pages[firstTab].buttons["Show or hide test frames"]
ok(testBtn ~= nil, "a test-frames button is drawn on the settings page")

-- Every movable frame declares itself; the button knows none of them by name.
local previewNames = {}
for _, p in ipairs(MythicPlusTimerNamespace.previews) do previewNames[p.name] = true end
ok(previewNames["run overlay"], "the run overlay registered a test frame")
ok(previewNames["join popup"], "the join popup registered a test frame")
ok(previewNames["bloodlust alert"], "the bloodlust alert registered a test frame")

lust():Hide()
popup():Hide()
overlay():Hide()
testBtn.__scripts.OnClick(testBtn)
ok(overlay():IsShown(), "the button puts the run overlay on screen")
ok(popup():IsShown(), "and the join popup")
ok(lust():IsShown(), "and the bloodlust alert")
has(Mock.rendered(lust()), "Test", "the alert marks itself as a test")
has(Mock.rendered(overlay()), "Preview", "so does the overlay")
has(Mock.rendered(popup()), "Preview", "and the popup")

-- The copy box is opened by clicking the thing you want copied, so it is
-- deliberately not one of the frames this puts up.
ok(_G.MythicPlusTimerCopyFrame:IsShown() == false, "the copy box is left out of the test frames")

-- A test alert must not time out while it is being dragged.
Mock.advance(30)
ok(lust():IsShown(), "a test alert stays up instead of timing out")

-- Dropping the alert saves where it was put.
lust():SetPoint("TOPLEFT", nil, nil, 40, -60)
lust().__scripts.OnDragStop(lust())
ok(MythicPlusTimerNamespace.cfg("blpoint") ~= nil and MythicPlusTimerNamespace.cfg("blpoint").point == "TOPLEFT",
  "dragging the alert saves its position")

-- The overlay remembers where it was dragged too, through Core's shared helper.
overlay():SetPoint("TOPLEFT", nil, nil, 20, -30)
overlay().__scripts.OnDragStop(overlay())
ok(MythicPlusTimerNamespace.cfg("mppoint") ~= nil,
  "dragging the overlay test frame remembers its position")

testBtn.__scripts.OnClick(testBtn)
ok(overlay():IsShown() == false and popup():IsShown() == false and lust():IsShown() == false,
  "pressing it again takes every test frame away")

-- And it is reachable without opening the panel.
SlashCmdList.MYTHICPLUSTIMER("frames")
ok(overlay():IsShown(), "/mpt frames shows them too")
SlashCmdList.MYTHICPLUSTIMER("frames")
ok(overlay():IsShown() == false, "and hides them again")

-- ── Let me focus ──────────────────────────────────────────────────────────
-- The clock and the death count are the two numbers people watch instead of
-- playing. Off by default; on, a click on either hides it.

ok(MythicPlusTimerNamespace.cfg("letmefocus") ~= true, "let me focus is off unless switched on")
SlashCmdList.MYTHICPLUSTIMER("frames")
ok(overlay().timeZone:IsShown() == false, "nothing on the overlay is clickable while it is off")

MythicPlusTimerNamespace.setCfg("letmefocus", true)
MythicPlusTimerNamespace.optionChanged.letmefocus()
ok(overlay().timeZone:IsShown(), "the clock becomes a click target")
ok(overlay().deathZone:IsShown(), "so do the deaths")

-- Hiding the clock is the whole time block: the countdown alone would leave the
-- elapsed row still saying it. The deaths are a separate click and stay put.
overlay().timeZone.__scripts.OnClick(overlay().timeZone)
local focused = Mock.rendered(overlay())
has(focused, "Hidden", "clicking the clock hides it")
hasNot(focused, "elapsed", "and the elapsed row with it")
has(focused, "0 total", "the deaths are a separate click and stay")
ok(MythicPlusTimerNamespace.cfg("focushidetime") == true, "which half is hidden survives a reload")

overlay().deathZone.__scripts.OnClick(overlay().deathZone)
focused = Mock.rendered(overlay())
has(focused, "Deaths", "the deaths keep their heading when hidden")
hasNot(focused, "0 total", "but not their count")

overlay().timeZone.__scripts.OnClick(overlay().timeZone)
overlay().deathZone.__scripts.OnClick(overlay().deathZone)
focused = Mock.rendered(overlay())
hasNot(focused, "Hidden", "clicking each again brings both back")
has(focused, "elapsed", "the clock is counted again")
has(focused, "0 total", "and so are the deaths")

MythicPlusTimerNamespace.setCfg("letmefocus", false)
MythicPlusTimerNamespace.optionChanged.letmefocus()
ok(overlay().timeZone:IsShown() == false, "switching the setting off removes the click targets")
SlashCmdList.MYTHICPLUSTIMER("frames")

-- ── Minimap button ─────────────────────────────────────────────────────────
-- A launcher on the minimap. Its menu opens Settings, toggles Let me focus, and
-- can hide the button, which the Settings checkbox brings back.

local minibtn = function() return _G.MythicPlusTimerMinimapButton end
ok(minibtn() ~= nil, "the minimap button is created")
ok(minibtn():IsShown(), "the minimap button shows by default")

-- Opening the menu builds it through the client's context-menu system.
minibtn().__scripts.OnClick(minibtn())
ok(Mock.menu ~= nil, "clicking the button opens a menu")
ok(Mock.menu.title == "Mythic+ Timer and Tools", "the menu is titled")

local function menuItem(text)
  for _, it in ipairs(Mock.menu.items) do if it.text == text then return it end end
end
ok(menuItem("Settings") ~= nil, "the menu offers Settings")
ok(menuItem("Let me focus") ~= nil, "the menu offers the Let me focus toggle")
ok(menuItem("Hide minimap button") ~= nil, "the menu offers Hide minimap button")

Mock.settings.opened = false
menuItem("Settings").click()
ok(Mock.settings.opened, "the Settings item opens the settings panel")

-- The Let me focus checkbox reads and writes the same setting the overlay does.
MythicPlusTimerNamespace.setCfg("letmefocus", false)
minibtn().__scripts.OnClick(minibtn())
ok(menuItem("Let me focus").isChecked() == false, "the toggle reads as off when the setting is off")
menuItem("Let me focus").toggle()
ok(MythicPlusTimerNamespace.cfg("letmefocus") == true, "toggling it from the menu turns the setting on")
minibtn().__scripts.OnClick(minibtn())
ok(menuItem("Let me focus").isChecked() == true, "and the toggle now reads as on")
MythicPlusTimerNamespace.setCfg("letmefocus", false)

-- Hiding it from the menu takes it off the minimap; the Settings checkbox is the
-- way back.
minibtn().__scripts.OnClick(minibtn())
menuItem("Hide minimap button").click()
ok(minibtn():IsShown() == false, "Hide minimap button takes it off the minimap")
ok(MythicPlusTimerNamespace.cfg("minimapbutton") == false, "and the setting remembers it is hidden")
MythicPlusTimerNamespace.setCfg("minimapbutton", true)
MythicPlusTimerNamespace.optionChanged.minimapbutton()
ok(minibtn():IsShown(), "turning the setting back on brings the button back")

-- ── SavedVariables hygiene ────────────────────────────────────────────────
-- A config from before profiles kept its options at the top level; it must fold
-- into a cleaned Default profile rather than being thrown away.

MythicPlusTimerConfig = { mythicplustimer = "yes please", mpscale = 99, bogus = 1, mppoint = { point = "TOP", x = 1, y = 2 } }
MythicPlusTimerRun = "not a table"
Mock.fire("PLAYER_LOGIN")
local migrated = MythicPlusTimerConfig.profiles and MythicPlusTimerConfig.profiles.Default
ok(migrated ~= nil, "a legacy flat config migrates into the Default profile")
ok(migrated.mythicplustimer == nil, "a wrong-typed config value is discarded")
ok(migrated.bogus == nil, "an unknown config key is dropped")
ok(migrated.mpscale == 2, "an out-of-range scale is clamped to the 0.6-2.0 range")
ok(migrated.mppoint ~= nil, "a well-formed saved position survives")
ok(MythicPlusTimerRun == nil, "a garbage run record is thrown away")

-- ── Profiles ──────────────────────────────────────────────────────────────
-- Every setting lives in a named profile; cfg/setCfg read and write the active
-- one, and a value it doesn't override falls back to the default.

local ns = MythicPlusTimerNamespace
ok(ns.activeProfile() == "Default", "the Default profile is active after a clean login")
ns.setCfg("guildkeys", false)
ok(ns.cfg("guildkeys") == false, "setCfg writes the active profile")

ns.createProfile("Raid")
ok(ns.activeProfile() == "Raid", "creating a profile makes it active")
ok(ns.cfg("guildkeys") == true, "a fresh profile falls back to defaults, not another profile's values")
ns.setCfg("bloodlust", false)

ns.loadProfile("Default")
ok(ns.cfg("bloodlust") == true, "switching profiles restores that profile's own values")

ns.copyProfileFrom("Raid")
ok(ns.cfg("bloodlust") == false, "copy-from overwrites the active profile with another's settings")

ns.resetProfile()
ok(ns.cfg("bloodlust") == true, "reset returns the active profile to defaults")

-- Export/import round-trips a profile through a copy-paste string.
ns.setCfg("chatlinks", false)
ns.setCfg("mpscale", 1.5)
local exported = ns.exportProfile()
ok(type(exported) == "string" and exported:find("MPTT1", 1, true) == 1, "a profile exports to a tagged string")
local imported = ns.importProfile(exported)
ok(imported ~= nil and ns.activeProfile() == imported, "importing a string creates and loads a new profile")
ok(ns.cfg("chatlinks") == false and ns.cfg("mpscale") == 1.5, "the imported profile carries the exported values")
ok(ns.importProfile("not one of ours") == nil, "a foreign string imports nothing")

ns.loadProfile("Default")
ns.deleteProfile("Raid")
local remaining = {}
for _, n in ipairs(ns.profileNames()) do remaining[n] = true end
ok(not remaining["Raid"], "a deleted profile is gone from the list")

-- ── Settings and Profiles sub-pages ────────────────────────────────────────
-- The tabbed Settings page and the Profiles page register as sub-pages of the
-- addon category (the "+" in the AddOns list) and drive the same config.

local panels = ns.panels
ok(panels and panels.settings and panels.profiles, "the Settings and Profiles sub-pages are built")
local subs = {}
for _, s in ipairs(Mock.settings.subcategories or {}) do subs[s.name] = true end
ok(subs["Settings"] and subs["Profiles"], "both sub-pages register under the addon category")
-- The addon's name and the "Settings" entry under it are the same screen.
ok(Mock.settings.canvas and Mock.settings.canvas.frame == panels.settings,
  "the addon's own category is the tabbed page")
local settingsSub
for _, s in ipairs(Mock.settings.subcategories or {}) do
  if s.name == "Settings" then settingsSub = s end
end
ok(settingsSub and settingsSub.frame == panels.settingsSub,
  "the Settings sub-page is a tabbed page too")
ok(panels.settingsSub ~= panels.settings,
  "and its own frame, since one frame cannot be in two categories")
for g in pairs(panels.settings.pages) do
  ok(panels.settingsSub.pages[g] ~= nil, "the sub-page has the '" .. g .. "' tab as well")
end

local settings = panels.settings
ok(settings.tabs["Mythic+ timer"] and settings.tabs["Dungeons window"] and settings.tabs["Chat"],
  "a horizontal tab exists for each option group")
ok(settings.tabs["Display"] == nil, "the display toggles no longer get a tab of their own")
settings.select("Chat")
ok(settings.pages["Chat"]:IsShown() and settings.pages["Mythic+ timer"]:IsShown() == false,
  "selecting a tab shows only that group's page")

for g in pairs(settings.tabs) do
  ok(ns.TAB_DESC[g] ~= nil, "tab '" .. g .. "' has a description")
  settings.select(g)
  ok(settings.desc:GetText():find(ns.TAB_DESC[g], 1, true) ~= nil,
    "selecting '" .. g .. "' shows its description")
end

local about = settings.pages["About"]
ok(about ~= nil and settings.tabs["About"] ~= nil, "there is an About tab")
has(about.version:GetText(), "2026.7.24", "About names the installed version")
has(about.updated:GetText(), "24 Jul 2026",
  "and turns the date-stamped version into a readable date")
ok(about.curseforge:GetText() == "https://www.curseforge.com/wow/addons/mythic-timer-and-tools/",
  "About carries the CurseForge address")
ok(about.github:GetText() == "https://github.com/Friftycode/mythicplus-timer-and-tools",
  "and the GitHub address")
-- An edit box cannot be made read-only, so typing over a link puts it back.
about.github:SetText("junk")
about.github.__scripts.OnTextChanged(about.github)
ok(about.github:GetText() == "https://github.com/Friftycode/mythicplus-timer-and-tools",
  "a link cannot be edited away")

settings.select("Mythic+ timer")
ns.setCfg("showbosses", true)
settings.refresh()
local cb = settings.pages["Mythic+ timer"].checks["showbosses"]
ok(cb.help ~= nil, "a row gets a help icon")
cb.help.__scripts.OnEnter(cb.help)
local helpTip = table.concat(GameTooltip.lines, "\n")
has(helpTip, "Show bosses", "the help tooltip names the setting")
has(helpTip, "Draw the bosses section",
  "hovering the help icon explains the setting")
cb.__scripts.OnEnter(cb)
has(table.concat(GameTooltip.lines, "\n"), "Draw the bosses section",
  "hovering the checkbox explains it as well")
ok(cb:GetChecked() == true, "a checkbox reflects the current setting")
cb:SetChecked(false)
cb.__scripts.OnClick(cb)
ok(ns.cfg("showbosses") == false, "clicking a checkbox writes the setting")
ns.setCfg("showbosses", true)

local profiles = panels.profiles
ok(profiles.current:GetText():find("Default", 1, true) ~= nil, "the profiles page names the active profile")
ns.createProfile("UI Test")
ok(ns.activeProfile() == "UI Test", "creating a profile from the page loads it")
local defaultRow
for _, r in ipairs(profiles.rows) do if r.profile == "Default" and r:IsShown() then defaultRow = r end end
ok(defaultRow ~= nil, "the profile list has a row per profile")
defaultRow.__scripts.OnClick(defaultRow)
ok(ns.activeProfile() == "Default", "clicking a profile row loads it")
ns.deleteProfile("UI Test")

-- ── Report ────────────────────────────────────────────────────────────────

-- print() is captured by the mock (the addon's own chat output is under test),
-- so the result goes back to the JS runner on Mock instead.
local lines = {}
if #failures == 0 then
  lines[1] = "PASS: " .. checks .. " checks"
else
  lines[1] = "FAIL: " .. #failures .. " of " .. checks .. " checks"
  for _, f in ipairs(failures) do lines[#lines + 1] = "  - " .. f end
end
Mock.report = table.concat(lines, "\n")
Mock.exitCode = #failures
