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
ok(boxCount == 41, "forty-one checkboxes drawn, got " .. boxCount)
ok(keys.mythicplustimer and keys.autonameplates and keys.letmefocus and keys.guildkeys
  and keys.autoslotkey and keys.joinpopup and keys.seasontp and keys.chatlinks
  and keys.chatcopy and keys.bloodlust and keys.minimapbutton,
  "all the option keys present")

for _, o in ipairs(MythicPlusTimerNamespace.OPTIONS) do
  ok(o.group ~= nil, "option '" .. o.key .. "' declares a section")
  ok(settingsPages[o.group] ~= nil,
    "option '" .. o.key .. "' has a tab for its group '" .. tostring(o.group) .. "'")
  ok(settingsPages[o.group].controls[o.key] ~= nil,
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

-- The key goes in, silently (the item visibly moving is feedback enough).
Mock.slotted, Mock.cursor, Mock.inserts = false, nil, 0
Mock.prints = {}
openFont()
ok(Mock.slotted, "the keystone is slotted when the Font of Power opens")
ok(Mock.cursor == nil, "the cursor is left empty afterwards")
ok(#Mock.prints == 0, "slotting the keystone writes nothing to chat")

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
has(Mock.rendered(overlay()), "Ara-Kara", "so does the overlay")
has(Mock.rendered(popup()), "Preview", "and the popup")
-- The overlay's example content is populated, not an empty shell.
has(Mock.rendered(overlay()), "Enemy forces", "the overlay shows example enemy forces")
has(Mock.rendered(overlay()), "9 total", "and example deaths for each member")

-- Edit mode: each test frame wears a light-blue overlay you click to jump to its
-- settings, which closes edit mode and opens the panel.
ok(overlay().mptEdit ~= nil and overlay().mptEdit:IsShown(), "the run overlay wears an edit overlay")
ok(type(overlay().mptEditPassthrough) == "table" and #overlay().mptEditPassthrough >= 1,
  "the overlay keeps its resize grip usable under the edit overlay")
ok(type(MythicPlusTimerNamespace.showSettingsSection) == "function", "a settings-section jump is exposed")
overlay().mptEdit.__scripts.OnClick(overlay().mptEdit)
ok(overlay():IsShown() == false, "clicking an edit overlay closes edit mode")
ok(Mock.settings.opened, "and opens the settings panel")
-- Reopen edit mode for the drag assertions below.
testBtn.__scripts.OnClick(testBtn)

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
has(focused, "9 total", "the deaths are a separate click and stay")
ok(MythicPlusTimerNamespace.cfg("focushidetime") == true, "which half is hidden survives a reload")

overlay().deathZone.__scripts.OnClick(overlay().deathZone)
focused = Mock.rendered(overlay())
has(focused, "Deaths", "the deaths keep their heading when hidden")
hasNot(focused, "9 total", "but not their count")

overlay().timeZone.__scripts.OnClick(overlay().timeZone)
overlay().deathZone.__scripts.OnClick(overlay().deathZone)
focused = Mock.rendered(overlay())
hasNot(focused, "Hidden", "clicking each again brings both back")
has(focused, "elapsed", "the clock is counted again")
has(focused, "9 total", "and so are the deaths")

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

-- Export is complete: every setting key is present even at its default, so the
-- string is self-contained (spot-check one from each newer feature area).
for _, key in ipairs({ "blockduels", "invitekeyword", "friendlyguild", "buffreminder", "autorepair" }) do
  ok(exported:find("\n" .. key .. "=", 1, true) ~= nil, "export includes '" .. key .. "' even at default")
end

-- Scrollbar thumbs are sized to the visible fraction of the content, with a
-- floor, so a short box never gets a thumb that fills it.
local dummyThumb = { h = 0, SetHeight = function(self, v) self.h = v end }
ns.sizeScrollThumb(dummyThumb, 46, 200)
ok(dummyThumb.h == 18, "a mostly-overflowing short box gets the minimum thumb, not a full one")
ns.sizeScrollThumb(dummyThumb, 400, 700)
ok(dummyThumb.h > 100 and dummyThumb.h < 400, "a taller view gets a proportionally taller thumb")

-- Update reminder: a group member on a newer version is proof (and beats age);
-- otherwise a version older than the age threshold flags. Pure, clock-injected.
local vEpoch = time({ year = 2026, month = 7, day = 24, hour = 12 })
ok(ns.updateStatusFor("2026.7.24", nil, vEpoch) == nil, "a fresh version with no newer peer is up to date")
ok(ns.updateStatusFor("2026.7.24", nil, vEpoch + 10 * 86400) == nil, "ten days old does not flag yet")
ok(ns.updateStatusFor("2026.7.24", nil, vEpoch + 50 * 86400).reason == "age", "a version 50 days old flags by age")
local peer = ns.updateStatusFor("2026.7.24", "2026.9.1", vEpoch)
ok(peer and peer.reason == "peer", "a newer peer version flags regardless of age")
ok(ns.updateStatusFor("2026.9.1", "2026.7.24", vEpoch) == nil, "an older seen version is not treated as newer")

-- noteNewerVersion remembers only a strictly newer version (local is 2026.7.24
-- in the mock metadata), account-wide so it persists and keeps reminding.
MythicPlusTimerState = {}
ns.noteNewerVersion("2026.7.20")
ok(MythicPlusTimerState.newerVersion == nil, "an older peer version is not remembered")
ns.noteNewerVersion("2026.8.5")
ok(MythicPlusTimerState.newerVersion == "2026.8.5", "a newer peer version is remembered")
MythicPlusTimerState = nil

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
ok(settings.tabs["Mythic+ timer"] and settings.tabs["Mythic+ Window"] and settings.tabs["Chat"],
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
ok(cb.check:GetChecked() == true, "a checkbox reflects the current setting")
cb.check:SetChecked(false)
cb.check.__scripts.OnClick(cb.check)
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

-- Copy-from pulls another profile's settings into the active one. UI Test keeps
-- guildkeys off; copying it into the active Default turns Default's off too.
ns.loadProfile("UI Test"); ns.setCfg("guildkeys", false)
ns.loadProfile("Default"); ns.setCfg("guildkeys", true)
profiles.refresh()
local listsActive = false
for _, c in ipairs(profiles.copyDD.choices) do if c.value == "Default" then listsActive = true end end
ok(not listsActive, "the copy-from list leaves out the active profile")
profiles.copyDD.onSelect("UI Test")
ok(ns.activeProfile() == "Default" and ns.cfg("guildkeys") == false,
  "copy-from overwrites the active profile with another's settings")
ok(profiles.copyMsg:GetText():find("UI Test", 1, true) ~= nil,
  "an inline confirmation names what was copied (no popup)")

-- Delete via the button applies the main-profile policy. Reduce to a known
-- two-profile state first: Default (main, active) plus one other ("UI Test").
for _, n in ipairs(ns.profileNames()) do
  if n ~= "Default" and n ~= "UI Test" then ns.deleteProfile(n) end
end
ns.setMainProfile("Default")
ns.loadProfile("Default")
-- Deleting the active main with exactly one other promotes that other, then
-- removes Default.
profiles.refresh()
ok(profiles.deleteBtn:IsEnabled(), "delete is allowed once a second profile exists")
profiles.deleteBtn.__scripts.OnClick(profiles.deleteBtn)
local names = {}
for _, n in ipairs(ns.profileNames()) do names[n] = true end
ok(not names["Default"], "the Default profile can be deleted when another remains")
ok(ns.mainProfile() == "UI Test", "the only other profile is promoted to main")

-- With several other profiles, deleting the main can't guess a replacement, so
-- nothing is removed until a main is chosen.
ns.createProfile("Alt A")
ns.createProfile("Alt B")
ns.setMainProfile("UI Test")
ns.loadProfile("UI Test")
local before = #ns.profileNames()
profiles.deleteBtn.__scripts.OnClick(profiles.deleteBtn)
ok(#ns.profileNames() == before, "deleting the main is refused while several others could be main")
-- The next section resets the whole config, so no cleanup is needed here.

-- ── Default profile shared across characters ───────────────────────────────
-- The config is account-wide, so "Default" is one shared set of settings until a
-- character is put on its own profile. A brand-new character starts on Default
-- and sees whatever another character saved there; a character kept on its own
-- profile keeps it, and is remembered as such the next time it logs in.

MythicPlusTimerConfig = nil
Mock.setChar("Alpha", "RealmOne")
Mock.fire("PLAYER_LOGIN")
ok(ns.activeProfile() == "Default", "a fresh character starts on the Default profile")
ns.setCfg("bloodlust", false) -- a change made on Default, by Alpha

-- A second, never-seen character inherits Default and the settings saved on it.
Mock.setChar("Bravo", "RealmOne")
Mock.fire("PLAYER_LOGIN")
ok(ns.activeProfile() == "Default", "a new character defaults to the shared Default profile")
ok(ns.cfg("bloodlust") == false, "and sees the settings another character saved on Default")

-- Bravo makes and switches to its own profile. That must not move anyone else.
ns.createProfile("Bravo PvE")
ns.setCfg("bloodlust", true)
ok(ns.activeProfile() == "Bravo PvE", "a character can put itself on its own profile")

-- Alpha logs back in: remembered on Default, not dragged onto Bravo's profile.
Mock.setChar("Alpha", "RealmOne")
Mock.fire("PLAYER_LOGIN")
ok(ns.activeProfile() == "Default", "the first character is remembered on Default")
ok(ns.cfg("bloodlust") == false, "with Default's own settings intact")

-- A brand-new third character (different realm) still starts on Default.
Mock.setChar("Charlie", "RealmTwo")
Mock.fire("PLAYER_LOGIN")
ok(ns.activeProfile() == "Default", "another new character also starts on Default, across realms")

-- And the character with its own profile keeps it when it returns.
Mock.setChar("Bravo", "RealmOne")
Mock.fire("PLAYER_LOGIN")
ok(ns.activeProfile() == "Bravo PvE", "a character on its own profile keeps it")
ok(ns.cfg("bloodlust") == true, "along with that profile's own settings")

-- Un-pinned characters follow the account main; a manual switch pins a character
-- and survives a later main change. This mirrors: first login sets the main,
-- a renamed/new main is what fresh characters start on, and a character switched
-- to another profile keeps it until switched again.
MythicPlusTimerConfig = nil
Mock.setChar("Uno", "R")
Mock.fire("PLAYER_LOGIN")
ns.createProfile("Frifty")        -- Uno makes and switches to its own profile
ns.setMainProfile("Frifty")       -- and makes it the account main
Mock.setChar("Dos", "R")
Mock.fire("PLAYER_LOGIN")
ok(ns.activeProfile() == "Frifty", "a new character starts on the current main, not Default")
ns.loadProfile("Default")         -- Dos switches itself to Default
ok(ns.activeProfile() == "Default", "a character can switch to another profile")
Mock.setChar("Tres", "R")
Mock.fire("PLAYER_LOGIN")
ok(ns.activeProfile() == "Frifty", "a third new character also follows the main")
Mock.setChar("Dos", "R")
Mock.fire("PLAYER_LOGIN")
ok(ns.activeProfile() == "Default", "the switched character keeps its own choice after main changed")

-- ── New features (buffs, notepad, automation, bar ticks) ───────────────────
-- A clean run for the tick-mark and later feature checks.

Mock.state.inInstance = true
Mock.state.difficultyID = nil
Mock.instanceID = 2290
Mock.state.mapID = 375
Mock.fire("CHALLENGE_MODE_RESET"); Mock.runTimers()
Mock.fire("START_TIMER", 1, 10)
Mock.fire("CHALLENGE_MODE_START")
Mock.runTimers()
Mock.advance(15, 1)

-- Feature 4: +2/+3 tick marks on the time bar.
local ov = overlay()
ok(ov.timeBar.ticks[1]:IsShown(), "+3 tick shown on the time bar")
ok(ov.timeBar.ticks[2]:IsShown(), "+2 tick shown on the time bar")
local _, _, _, tx1 = ov.timeBar.ticks[1]:GetPoint()
local _, _, _, tx2 = ov.timeBar.ticks[2]:GetPoint()
-- Bar inner width is 220; +3 sits at 40% (88), +2 at 20% (44) from the left.
ok(math.abs(tx1 - 88) < 0.5, "+3 tick at 40% of the bar, got " .. tostring(tx1))
ok(math.abs(tx2 - 44) < 0.5, "+2 tick at 20% of the bar, got " .. tostring(tx2))
ns.setCfg("showbarticks", false)
Mock.advance(2, 1)
ok(not ov.timeBar.ticks[1]:IsShown(), "ticks hidden when the option is off")
ns.setCfg("showbarticks", true)
Mock.fire("CHALLENGE_MODE_RESET"); Mock.runTimers()

-- Feature 1: missing party-buff reminder. Present classes are Paladin (player),
-- Priest (party1), Mage (party2), so Fortitude and Arcane Intellect are tracked;
-- Skyfury etc. are not, since no Shaman/Warrior/Druid/Evoker is here. Chat
-- delivery announces to the party via SendChatMessage, coordinated by addon
-- message so only one client sends and they share the cooldown.
local function buffChat()
  local parts = {}
  for _, c in ipairs(Mock.sentChat) do parts[#parts + 1] = c.msg end
  return table.concat(parts, "\n")
end
Mock.state.inGroup = true
Mock.auras = {
  player = { 21562, 1459 },
  party1 = { 21562 },          -- Healer, missing Arcane Intellect
  party2 = { 21562, 1459 },
}
Mock.sentChat, Mock.sentAddon = {}, {}
Mock.advance(25, 1)  -- past the 20s default threshold, plus the claim window
local buffOut = buffChat()
has(buffOut, "Arcane Intellect", "buff reminder announces the missing Arcane Intellect")
has(buffOut, "Healer", "buff reminder names the member missing it")
hasNot(buffOut, "Skyfury", "no reminder for a class that isn't in the group")
hasNot(buffOut, "Fortitude", "no reminder for a buff everyone already has")
ok(Mock.sentChat[1] and (Mock.sentChat[1].channel == "PARTY" or Mock.sentChat[1].channel == "INSTANCE_CHAT"),
  "the reminder goes to party/instance chat")
local sawSent = false
for _, a in ipairs(Mock.sentAddon) do if a.msg:find("SENT:", 1, true) then sawSent = true end end
ok(sawSent, "the sender broadcasts the shared cooldown to other addon users")

-- Another client already announced (a SENT arrives): we hold off. Buff drops on
-- a fresh member so it would otherwise be flagged.
Mock.auras.party2 = { 21562 }  -- Dpsguy now missing Arcane Intellect
Mock.sentChat = {}
Mock.fire("CHAT_MSG_ADDON", "MPTTBuff", "SENT:300", "PARTY", "Someone")
Mock.advance(25, 1)
ok(#Mock.sentChat == 0, "holds off while another addon user's shared cooldown is active")
Mock.auras.party2 = { 21562, 1459 }

-- A rival with an earlier name claims during our window: we back off, they send.
ns.setCfg("buffcooldown", false)
Mock.fire("CHAT_MSG_ADDON", "MPTTBuff", "SENT:0", "PARTY", "x")  -- clear the shared cooldown
Mock.auras.party1 = { 21562, 1459 }; Mock.advance(3, 1)  -- buff back: reset the episode
Mock.auras.party1 = { 21562 }                            -- missing again
Mock.sentChat, Mock.sentAddon = {}, {}
-- Step until our own CLAIM goes out (before its window resolves), then a
-- lower-sorting name claims first.
local ourClaim = false
for _ = 1, 120 do
  Mock.advance(0.5, 0.5)
  for _, a in ipairs(Mock.sentAddon) do if a.msg == "CLAIM:Testchar" then ourClaim = true end end
  if ourClaim then break end
end
ok(ourClaim, "the client opens a claim before it sends")
Mock.fire("CHAT_MSG_ADDON", "MPTTBuff", "CLAIM:Aaa", "PARTY", "Aaa")
Mock.advance(1.5, 0.5)  -- our claim window resolves
ok(#Mock.sentChat == 0, "backs off when a party member with an earlier name is announcing")

-- Turning off that buff's class toggle stops tracking it.
ns.setCfg("buffmage", false)
Mock.auras.party1 = { 21562 }
Mock.sentChat = {}
Mock.advance(25, 1)
hasNot(buffChat(), "Arcane Intellect", "an untracked buff is never flagged")
ns.setCfg("buffmage", true)
ns.setCfg("buffcooldown", true)

-- Master toggle off: nothing is scanned or sent.
ns.setCfg("buffreminder", false)
Mock.sentChat = {}
Mock.advance(25, 1)
ok(#Mock.sentChat == 0, "no reminders while the feature is off")
ns.setCfg("buffreminder", true)
Mock.state.inGroup = false

-- Feature 2: the Note window, keyed by the Encounter Journal instance id (500)
-- so it shares its store with the prepare-ahead editor.
ns.setCfg("notepad", true)
ns.setCfg("notepadmode", "always")
Mock.state.inEncounter = false
Mock.state.ejInstance = 500
Mock.fire("PLAYER_ENTERING_WORLD"); Mock.runTimers()
local note = _G.MythicPlusTimerNotepad
ok(note ~= nil and note:IsShown(), "the note window shows in a dungeon on the 'always' mode")

-- Editing is a mode: click to edit, click away (commit) to save and re-render.
local function editNote(text)
  note.enterEdit()
  note.edit:SetText(text)
  note.commitEdit()
end

-- The default section is the dungeon note, saved under .dungeon.
editNote("skip left after first boss")
ok(MythicPlusTimerNotes[500] and MythicPlusTimerNotes[500].dungeon == "skip left after first boss",
  "the dungeon note is saved under the journal instance id")

-- Markdown renders in the view: a "---" line becomes a horizontal rule.
editNote("## Plan\n---\n- kick the cast")
ok(note.view.mdRules and note.view.mdRules[1] and note.view.mdRules[1]:IsShown(),
  "a --- line renders as a horizontal rule")
ok(note.view.mdLines and note.view.mdLines[1] and note.view.mdLines[1]:IsShown(),
  "and the other markdown lines render")
editNote("skip left after first boss")  -- restore

-- The journal's bosses each get their own section; selecting one edits its note.
ok(#note.sections == 3, "dungeon plus two bosses are listed, got " .. #note.sections)
local bossKey = note.sections[2].key
note.selectSection(bossKey)
editNote("interrupt the cast")
ok(MythicPlusTimerNotes[500].bosses[bossKey] == "interrupt the cast", "a boss note is saved under its own key")
ok(MythicPlusTimerNotes[500].dungeon == "skip left after first boss", "and the dungeon note is untouched")

-- A boss note is read-only once its fight is in progress; the dungeon note isn't.
Mock.state.inEncounter = true
note.selectSection(bossKey)
note.enterEdit()
ok(note.editing == false, "a boss note can't be entered for editing during the fight")
note.selectSection("dungeon")
editNote("edited during the run")
ok(MythicPlusTimerNotes[500].dungeon == "edited during the run", "the dungeon note is still editable during a fight")
Mock.state.inEncounter = false

-- Follow the fight: ENCOUNTER_START opens that boss's tab, ENCOUNTER_END returns
-- to the dungeon tab. Boss keys are "b" .. dungeonEncounterID (111 / 222).
ns.setCfg("notebossauto", true)
note.selectSection("dungeon")
ok(note.sections[2].key == "b111", "boss keys come from the dungeon encounter id")
Mock.fire("ENCOUNTER_START", 111)
ok(note.title:GetText():find("First Boss", 1, true) ~= nil, "ENCOUNTER_START opens the pulled boss's tab")
Mock.fire("ENCOUNTER_END", 111)
ok(note.title:GetText():find("Dungeon", 1, true) ~= nil, "ENCOUNTER_END returns to the dungeon tab")

-- Proximity: a boss-named target/nameplate auto-selects that boss's tab on the ticker.
Mock.units.target = { name = "First Boss", class = "PALADIN", guid = "B-1" }
Mock.advance(1.5, 0.5)
ok(note.title:GetText():find("First Boss", 1, true) ~= nil, "a nearby boss auto-selects its tab")
Mock.units.target = nil
Mock.advance(1.5, 0.5)
ok(note.title:GetText():find("Dungeon", 1, true) ~= nil, "with no boss near, it returns to the dungeon tab")

-- With follow-the-fight off, it stays put.
ns.setCfg("notebossauto", false)
note.selectSection("dungeon")
Mock.units.target = { name = "First Boss", class = "PALADIN", guid = "B-1" }
Mock.advance(1.5, 0.5)
ok(note.title:GetText():find("Dungeon", 1, true) ~= nil, "no auto-switch when following is off")
Mock.units.target = nil
ns.setCfg("notebossauto", true)

-- The section column can be collapsed from the window, widening the note area,
-- and the state persists in config.
note.selectSection("dungeon")
local toggleMenu = note.menuToggle:GetScript("OnClick")
ok(note.col:IsShown(), "the section column shows by default")
local narrowBefore = note.contentW
toggleMenu()
ok(not note.col:IsShown(), "clicking the toggle hides the section column")
ok(ns.cfg("notepadmenu") == false, "the collapsed state is saved")
ok(note.contentW > narrowBefore, "the note reclaims the column's width when it is hidden")
toggleMenu()
ok(note.col:IsShown() and ns.cfg("notepadmenu") == true, "clicking again brings the column back")

-- The window is resizable and the section column has an adjustable width. Both
-- are saved and reflowed: a wider window gives the note more room; a wider column
-- takes it back.
ok(note.resize ~= nil and note.colDrag ~= nil, "the note window has a resize grip and a column divider")
local roomBefore = note.contentW
note:SetSize(note:GetWidth() + 120, note:GetHeight())
note.__scripts.OnSizeChanged(note)
ok(note.contentW > roomBefore, "widening the window gives the note more room")
note.resize.__scripts.OnMouseUp(note.resize)
ok(ns.cfg("notepadw") == note:GetWidth(), "releasing the resize grip saves the new width")
local roomWide = note.contentW
ns.setCfg("notepadcolw", ns.cfg("notepadcolw") + 60)
-- Toggling the column off and back on re-runs the same layout that a divider
-- drag would, now with the wider column saved.
toggleMenu(); toggleMenu()
ok(note.contentW < roomWide, "a wider section column leaves the note less room")

-- An old flat-string note is migrated into the dungeon slot on next visit.
MythicPlusTimerNotes[777] = "legacy note"
Mock.state.ejInstance = 777
Mock.fire("PLAYER_ENTERING_WORLD"); Mock.runTimers()
ok(type(MythicPlusTimerNotes[777]) == "table" and MythicPlusTimerNotes[777].dungeon == "legacy note",
  "a legacy flat-string note becomes the dungeon note")
Mock.state.ejInstance = 500

-- A note saved for a dungeon that has rotated out of the current tiers is kept
-- and stays listed (never deleted for being out of season), so it is still there
-- if the dungeon returns.
MythicPlusTimerNotes[900] = { dungeon = "kept from an old season", bosses = {} }

-- Prepare-ahead: the shared note API lists dungeons and edits their notes without
-- being in the dungeon, and the in-window note reads the same store.
local dungeons = ns.noteDungeonList()
ok(#dungeons >= 2, "the prepare-ahead picker lists dungeons, got " .. #dungeons)
local hasRetired = false
for _, d in ipairs(dungeons) do if d.key == 900 then hasRetired = true end end
ok(hasRetired, "a dungeon with saved notes is listed even when out of the current tiers")
ok(ns.noteGet(900, "dungeon") == "kept from an old season", "and its old note is still readable")
ns.noteSet(501, "dungeon", "prepared before the run")
ok(ns.noteGet(501, "dungeon") == "prepared before the run", "a dungeon can be noted ahead of time")
local sections501 = ns.noteSectionList(501)
ok(#sections501 == 2, "the picker lists that dungeon's bosses too, got " .. #sections501)

-- The settings tab hosts the editor, wired to the same API.
local noteEditor = settings.pages["Note"].noteEditor
ok(noteEditor ~= nil, "the Note settings tab has a prepare-ahead editor")
noteEditor.selectDungeon(501)
noteEditor.selectSection("dungeon")
ok(noteEditor.edit:GetText() == "prepared before the run", "the editor loads a prepared note")
noteEditor.edit:SetText("edited from settings")
noteEditor.edit.__scripts.OnTextChanged(noteEditor.edit)
ok(ns.noteGet(501, "dungeon") == "edited from settings", "editing in settings writes the shared note")

-- Hidden-during-key mode hides it while a keystone is live (the mock always has one).
Mock.fire("PLAYER_ENTERING_WORLD"); Mock.runTimers()
ns.setCfg("notepadmode", "hiddenrun")
ns.optionChanged.notepadmode()
ok(not note:IsShown(), "the note window is hidden for the whole run on 'hidden during key'")
ns.setCfg("notepadmode", "always")
ns.optionChanged.notepadmode()

-- Feature 3a: auto repair. Personal gold first when no guild funds.
ns.setCfg("autorepair", true)
ns.setCfg("autorepairguild", true)
Mock.merchant.repaired = nil
Mock.merchant.canGuildRepair = false
Mock.prints = {}
Mock.fire("MERCHANT_SHOW")
ok(Mock.merchant.repaired == "self", "auto repair falls back to personal gold")
ok(#Mock.prints == 0, "auto repair does its work silently")
-- Guild funds when allowed and they cover it.
Mock.merchant.repaired = nil
Mock.merchant.canGuildRepair = true
Mock.merchant.guildWithdraw = -1  -- unlimited
Mock.fire("MERCHANT_SHOW")
ok(Mock.merchant.repaired == "guild", "auto repair prefers guild funds when it can")

-- Feature 3b: auto sell junk. Add a grey item; only that one sells.
Mock.GRAY_LINK = "|cff9d9d9d|Hitem:6948::::::::70:::::|h[Broken Fang]|h|r"
Mock.bags[2] = { Mock.GRAY_LINK }
Mock.sold = {}
ns.setCfg("autosell", false)
Mock.fire("MERCHANT_SHOW")
ok(#Mock.sold == 0, "nothing sold while auto sell is off")
ns.setCfg("autosell", true)
Mock.prints = {}
Mock.fire("MERCHANT_SHOW")
ok(#Mock.sold == 1 and Mock.sold[1] == Mock.GRAY_LINK, "auto sell sells the grey item")
ok(#Mock.prints == 0, "auto sell does its work silently")
ns.setCfg("autosell", false)

-- Feature 3c: auto accept and turn in. Default mode is dungeon-only; we're in one.
ns.setCfg("autoquestmode", "dungeon")
Mock.gossip.active = { { questID = 111, isComplete = true } }
Mock.gossip.available = {}
Mock.gossip.selectedActive = nil
Mock.fire("GOSSIP_SHOW")
ok(Mock.gossip.selectedActive == 111, "a completed quest is handed in at a gossip")
Mock.gossip.active = {}
Mock.gossip.available = { { questID = 222 } }
Mock.gossip.selectedAvail = nil
Mock.fire("GOSSIP_SHOW")
ok(Mock.gossip.selectedAvail == 222, "an offered quest is accepted at a gossip")
Mock.quest.accepted = false
Mock.fire("QUEST_DETAIL")
ok(Mock.quest.accepted, "a quest detail page is accepted")
Mock.quest.completed = false
Mock.quest.completable = true
Mock.fire("QUEST_PROGRESS")
ok(Mock.quest.completed, "a completable turn-in is completed")
Mock.quest.rewardTaken = false
Mock.quest.numChoices = 0
Mock.fire("QUEST_COMPLETE")
ok(Mock.quest.rewardTaken, "a no-choice reward is taken automatically")
Mock.quest.rewardTaken = false
Mock.quest.numChoices = 2
Mock.fire("QUEST_COMPLETE")
ok(not Mock.quest.rewardTaken, "a multi-choice reward is left for the player")
-- Never mode does nothing.
ns.setCfg("autoquestmode", "never")
Mock.quest.accepted = false
Mock.fire("QUEST_DETAIL")
ok(not Mock.quest.accepted, "nothing auto-accepts when the mode is never")
ns.setCfg("autoquestmode", "dungeon")

-- Feature 3d: mythic difficulty warning.
ns.setCfg("mythicwarn", true)
Mock.state.difficultyID = 2  -- Heroic
Mock.prints = {}
Mock.fire("PLAYER_ENTERING_WORLD"); Mock.runTimers()
has(table.concat(Mock.prints, "\n"), "not set to Mythic", "warns when the dungeon isn't Mythic")
Mock.state.difficultyID = 23  -- Mythic
Mock.prints = {}
Mock.fire("PLAYER_ENTERING_WORLD"); Mock.runTimers()
hasNot(table.concat(Mock.prints, "\n"), "not set to Mythic", "no warning when it is Mythic")
Mock.state.difficultyID = nil
ns.setCfg("mythicwarn", false)

-- Gossip with no quests: a single benign option is progressed in a dungeon, but
-- a "leave the instance" option is never auto-clicked.
Mock.gossip.active = {}
Mock.gossip.available = {}
Mock.gossip.options = { { name = "Continue", gossipOptionID = 55 } }
Mock.gossip.selectedOption = nil
Mock.fire("GOSSIP_SHOW")
ok(Mock.gossip.selectedOption == 55, "a single benign gossip option is progressed in a dungeon")
Mock.gossip.options = { { name = "Teleport me out of the dungeon", gossipOptionID = 66 } }
Mock.gossip.selectedOption = nil
Mock.fire("GOSSIP_SHOW")
ok(Mock.gossip.selectedOption == nil, "a leave-the-instance option is never auto-clicked")
Mock.gossip.options = {}

-- Feature 3e: default difficulty for a new listing. With Mythic+ chosen, a
-- dungeon change to a lower difficulty is bumped to that dungeon's keystone
-- activity; picking a difficulty yourself (same dungeon) is left alone.
ns.setCfg("defaultdifficulty", "mythicplus")
LFGListEntryCreation_Select({}, {}, 2, 42, 2000)  -- dungeon 42 auto-picks Heroic
ok(Mock.lfgSelected.activity == 2002, "a dungeon change is forced onto the Mythic+ keystone")
LFGListEntryCreation_Select({}, {}, 2, 42, 2000)  -- same dungeon, manual Heroic
ok(Mock.lfgSelected.activity == 2000, "a manual difficulty pick on the same dungeon is respected")
-- Choosing Heroic as the default keeps the listing on the Heroic activity.
ns.setCfg("defaultdifficulty", "heroic")
LFGListEntryCreation_Select({}, {}, 2, 46, 2001)  -- dungeon 46 picks Mythic (2001)
ok(Mock.lfgSelected.activity == 2000, "the chosen default difficulty (Heroic) is applied")
ns.setCfg("defaultdifficulty", "mythicplus")

-- Default playstyle preselected on a dungeon change (Competitive by default).
ns.setCfg("groupplaystyle", "3")
LFGListEntryCreation.generalPlaystyle = nil
LFGListEntryCreation_Select({}, {}, 2, 43, 2000)  -- new dungeon
ok(LFGListEntryCreation.generalPlaystyle == Enum.LFGEntryGeneralPlaystyle.FunSerious,
  "the default playstyle is preselected (Competitive)")
-- A different default value.
ns.setCfg("groupplaystyle", "1")
LFGListEntryCreation.generalPlaystyle = nil
LFGListEntryCreation_Select({}, {}, 2, 44, 2000)
ok(LFGListEntryCreation.generalPlaystyle == Enum.LFGEntryGeneralPlaystyle.Learning,
  "a chosen default playstyle (Learning) is used")
-- Off leaves the playstyle alone.
ns.setCfg("groupplaystyle", "off")
LFGListEntryCreation.generalPlaystyle = nil
LFGListEntryCreation_Select({}, {}, 2, 45, 2000)
ok(LFGListEntryCreation.generalPlaystyle == nil, "playstyle is left untouched when set to Off")
ns.setCfg("groupplaystyle", "3")

-- Feature: party key share. Group members broadcast the keystone they hold, and
-- the create panel offers everyone's keys as a dropdown.
ns.setCfg("keyshare", true)
Mock.state.inGroup = true
Mock.ownedChallengeMapID = 375  -- Mists of Tirna Scithe
Mock.ownedKeyLevel = 12

local function lastAddon(prefix)
  for i = #Mock.sentAddon, 1, -1 do
    if Mock.sentAddon[i].prefix == prefix then return Mock.sentAddon[i].msg end
  end
  return nil
end

-- A roster change re-announces our own key (after the debounce).
Mock.sentAddon = {}
Mock.fire("GROUP_ROSTER_UPDATE"); Mock.advance(1.5)
ok(lastAddon("MPTTKey") == "K:375:12", "own keystone is broadcast on a roster change")

-- A peer's key arrives and joins the list; the highest key sorts first.
Mock.fire("CHAT_MSG_ADDON", "MPTTKey", "K:376:15", "PARTY", "Frifty-Realm")
local kl = ns.keyShareList()
ok(#kl == 2, "the list holds our key and the peer's")
ok(kl[1].name == "Frifty" and kl[1].level == 15, "the higher peer key sorts above our own")
ok(kl[1].label == "Frifty - The Necrotic Wake +15", "a row reads 'name - dungeon +level'")
ok(kl[2].name ~= "Frifty" and kl[2].level == 12, "our own key is the other row")

-- Picking a key fills in that dungeon's activity and the "+level" title.
LFGListEntryCreation.Name.text = ""
Mock.lfgSelected = nil
local mine
for _, e in ipairs(kl) do if e.dungeon == "Mists of Tirna Scithe" then mine = e end end
ns.keyShareApply(mine)
ok(Mock.lfgSelected and Mock.lfgSelected.activity == 2003, "the chosen key selects that dungeon's activity")
ok(LFGListEntryCreation.Name.text == "+12", "the chosen key fills the title with '+level'")

-- Picking a key is an explicit request for its "+level" title, so it is written
-- even over a title already in the box (selecting the activity auto-fills that
-- box, so "only if empty" would never have fired for a real pick).
LFGListEntryCreation.Name.text = "chill run"
ns.keyShareApply(mine)
ok(LFGListEntryCreation.Name.text == "+12", "picking a key writes the '+level' title over any existing one")

-- A REQ from a peer prompts us to re-broadcast.
Mock.sentAddon = {}
Mock.fire("CHAT_MSG_ADDON", "MPTTKey", "REQ", "PARTY", "Someone-Realm")
Mock.advance(1.5)
ok(lastAddon("MPTTKey") == "K:375:12", "a REQ from a peer re-broadcasts our key")

-- With the feature off, nothing is broadcast and no key is collected.
ns.setCfg("keyshare", false)
Mock.sentAddon = {}
Mock.fire("GROUP_ROSTER_UPDATE"); Mock.advance(1.5)
ok(lastAddon("MPTTKey") == nil, "nothing is broadcast while the share is off")
Mock.fire("CHAT_MSG_ADDON", "MPTTKey", "K:377:20", "PARTY", "Latecomer-Realm")
local off = ns.keyShareList()
local sawLate = false
for _, e in ipairs(off) do if e.name == "Latecomer" then sawLate = true end end
ok(not sawLate, "a peer key is ignored while the share is off")
ns.setCfg("keyshare", true)
Mock.state.inGroup = false

-- Feature: reply to "!keys" in chat with the keystone link from your bags.
ns.setCfg("keylink", true)
Mock.sentChat = {}
Mock.fire("CHAT_MSG_PARTY", "!keys", "Someone"); Mock.advance(0.2)
local said = Mock.sentChat[#Mock.sentChat]
ok(said and said.channel == "PARTY" and said.msg:find("Hkeystone", 1, true),
  "!keys in party posts the keystone link to party")
Mock.sentChat = {}
Mock.fire("CHAT_MSG_GUILD", "  !KEYS  ", "Guildie"); Mock.advance(0.2)
ok(Mock.sentChat[1] and Mock.sentChat[1].channel == "GUILD", "!keys is case- and space-insensitive, and answers guild in guild")
-- A sentence that merely mentions it is ignored.
Mock.sentChat = {}
Mock.fire("CHAT_MSG_PARTY", "post your !keys please", "Someone"); Mock.advance(0.2)
ok(#Mock.sentChat == 0, "only a bare !keys triggers a reply")
-- Off switch.
ns.setCfg("keylink", false)
Mock.sentChat = {}
Mock.fire("CHAT_MSG_PARTY", "!keys", "Someone"); Mock.advance(0.2)
ok(#Mock.sentChat == 0, "no reply when the keystone linker is off")
ns.setCfg("keylink", true)

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
