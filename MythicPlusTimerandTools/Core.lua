-- Shared core: palette, config, and the registries features use to plug in.
-- Features depend on Core; Core depends on nothing.

local _, ns = ...

-- Armory gold, one source: the |cff text color and the RGB texture tint both
-- derive from this hex.
local GOLD_HEX = "e0a54e"
ns.GOLD_HEX = GOLD_HEX
-- Secondary text. Kept light enough to clear WCAG AA (4.5:1) against the addon's
-- own dark backdrops, rather than the dim mid-grey it used to be.
ns.GOLD, ns.GREY, ns.WHITE = "|cff" .. GOLD_HEX, "|cffc8c8c8", "|cffffffff"
-- Brighter, more saturated than before so the green/red still separate for
-- red-green color vision and both clear AA on a dark background.
ns.GREEN, ns.RED, ns.ENDC = "|cff4ade68", "|cffff6b66", "|r"
-- Same gold as 0-1 RGB for SetColorTexture (WoW takes floats, not |cff hex), so
-- the thin rule under section headers is the exact color as the gold text.
ns.GOLD_RGB = {
  tonumber(GOLD_HEX:sub(1, 2), 16) / 255,
  tonumber(GOLD_HEX:sub(3, 4), 16) / 255,
  tonumber(GOLD_HEX:sub(5, 6), 16) / 255,
}

-- Vertical breathing room (px) above AND below a section-header rule, and the
-- height of one text row. Shared so the overlay, the guild panel and the popups
-- line up with each other instead of each picking its own spacing.
ns.RULE_GAP, ns.PAD, ns.LINE = 4, 10, 14

local GOLD, GREY, ENDC = ns.GOLD, ns.GREY, ns.ENDC

-- ── Config (SavedVariables) ──────────────────────────────────────────────

local DEFAULTS = {
  mythicplustimer = true,  -- live M+ run timer overlay
  autonameplates = true, -- turn on enemy nameplates at the start of a key
  guildkeys = true,   -- "Guild keys this week" panel in the Mythic+ window
  -- On by default: opening the Font of Power IS the request to put your key in
  -- it, and it stays a reaction to that (never in combat, never over a key
  -- someone else already slotted, and it says in chat what it moved).
  autoslotkey = true, -- put your keystone in the Font of Power when it opens
  joinpopup = true,   -- "you joined this key" popup, with a teleport button
  seasontp = true,    -- click a Season Best icon to teleport to that dungeon
  chatlinks = true,   -- turn web addresses in chat into a link you can click
  chatcopy = true,    -- Copy button on each chat window, opens a selectable box
  bloodlust = true,   -- on-screen alert when someone calls bloodlust in chat
  -- Off by default: it changes what the overlay shows, and someone who never
  -- asked for it would just find numbers missing.
  letmefocus = false, -- let a click on the overlay's clock or deaths hide them
  blpoint = nil,      -- { point, x, y } of the last place the alert was dragged to
  jppoint = nil,      -- { point, x, y } of the last place the popup was dragged to
  -- Set by the overlay's own lock icon / resize grip rather than a checkbox,
  -- so these deliberately stay out of OPTIONS (and the Settings panel).
  mplocked = false,   -- overlay pinned: no dragging, no resizing
  mpscale = 1,        -- overlay scale, 0.6-2.0, dragged from the corner grip
  mppoint = nil,      -- { point, x, y } of the last place it was dragged to
  -- Set by clicking the overlay itself once "Let me focus" is on, so these are
  -- out of OPTIONS for the same reason the lock and the scale are.
  focushidetime = false,   -- clock, upgrade windows and time bar hidden
  focushidedeaths = false, -- death total and per-player rows hidden
  -- Display: which blocks of the overlay to draw at all. On by default; turning
  -- one off drops that block for good, unlike the per-run "Let me focus" click.
  showaffixes = true,
  showforces = true,
  showbosses = true,
  showdeaths = true,
  -- Minimap button: a small launcher on the minimap. Its menu opens Settings,
  -- toggles "Let me focus", and can hide the button itself. The angle is where
  -- it sits around the ring, and is set by dragging the button.
  minimapbutton = true,
  minimapangle = 225,
  -- Thin white tick marks on the run's time bar at the +2 and +3 upgrade windows.
  showbarticks = true,

  -- Buff reminder: flags a class party buff missing from a member for a while,
  -- but only for classes actually in the group. Delivery and the anti-spam
  -- cooldown are configurable; each class buff can be tracked or not.
  buffreminder = true,
  buffthreshold = 20,        -- seconds a buff must be missing before it counts (15-60)
  buffdelivery = "chat",     -- "chat" | "popup" | "both"
  buffcooldown = true,       -- gate alerts behind a cooldown instead of always firing
  buffcooldownmins = 5,      -- minutes between alerts while buffcooldown is on (1-30)
  buffmage = true,           -- Arcane Intellect
  buffpriest = true,         -- Power Word: Fortitude
  buffwarrior = true,        -- Battle Shout
  buffdruid = true,          -- Mark of the Wild
  buffshaman = true,         -- Skyfury
  buffevoker = true,         -- Blessing of the Bronze
  buffpoint = nil,           -- { point, x, y } of the popup alert

  -- Instance notepad: a small note window tied to the dungeon you are in. The
  -- note text itself is account-wide (MythicPlusTimerNotes), not a profile value.
  -- Off by default: a note window appearing unasked would surprise people.
  notepad = false,
  notepadmode = "indungeon", -- "everywhere" | "indungeon" | "hideatstart"
  notepadlocked = false,
  notepadpoint = nil,        -- { point, x, y } of the note window
  notebossauto = true,       -- follow the fight: open a boss's tab near/at it, else the dungeon tab
  -- The note window's section column: shown or collapsed, toggled by a button on
  -- the window itself (not a settings checkbox), so it stays out of OPTIONS.
  notepadmenu = true,
  -- The note window's size and the width of its section column, both set by
  -- dragging (a corner grip and the divider between the column and the note), so
  -- like the overlay's scale they stay out of OPTIONS.
  notepadw = 360,
  notepadh = 260,
  notepadcolw = 100,

  -- Automation: the vendor/quest/difficulty conveniences.
  autorepair = true,         -- repair on visiting a merchant
  autorepairguild = true,    -- prefer guild-bank funds before personal gold
  autosell = false,          -- sell grey (junk) items on a merchant visit
  autoquestmode = "dungeon", -- "always" | "never" | "dungeon" (auto accept/turn-in)
  mythicwarn = false,        -- warn when the dungeon isn't set to Mythic difficulty
  -- Default difficulty for a new group listing as you switch dungeons: "off", or
  -- "normal"/"heroic"/"mythic"/"mythicplus".
  defaultdifficulty = "mythicplus",
  -- Default "Select Playstyle" for a new listing: "off", or the playstyle value
  -- ("1" Learning, "2" Relaxed, "3" Competitive, "4" Carry offered).
  groupplaystyle = "3",
  -- Party-key share: broadcast your own keystone to group members running this
  -- addon, and offer their keys as a dropdown on the create-a-group panel so one
  -- click fills in the dungeon and the "+level" title.
  keyshare = true,
  -- Reply to "!keys" in party/guild/instance chat with your own keystone link, so
  -- anyone (addon or not) can ask for it. Works without this addon on their end.
  keylink = true,

  -- Social automation: party/invite/duel conveniences ported from Leatrix Plus.
  -- Each accept/block behaviour is off by default (one acting unasked would
  -- surprise people). Guild members count as friends by default; communities do
  -- not, since a large community is a wider net than most people expect.
  acceptpartyfriends = false,     -- auto accept a party invite from a friend
  confirmqueuerole = "off",       -- role check from a friend: "off" | "last" | "roles"
  -- Roles to confirm as when confirmqueuerole is "roles", intersected at confirm
  -- time with the roles the current spec can fill, so a set that lists a role this
  -- character can't play simply drops it. All three by default.
  confirmqueueroles = { tank = true, healer = true, dps = true },
  invitefromwhisper = false,      -- invite someone who whispers the keyword below
  invitekeyword = "inv",          -- the whisper that triggers an invite
  invitefriendsonly = true,       -- only invite friends who whisper the keyword
  blockpartyinvites = false,      -- decline party invites from non-friends
  blockrequestedinvites = false,  -- decline "requested to join" confirmations from non-friends
  blockduels = false,             -- decline duel requests from non-friends
  -- Guild members and community members count as friends for everything above.
  friendlyguild = true,
  friendlycommunities = false,
}
ns.DEFAULTS = DEFAULTS

-- One row per user-facing option. `group` is the tab it lands on and `section`
-- the heading above it; rows sharing either must stay adjacent, or the heading
-- would be drawn twice.
ns.OPTIONS = {
  { key = "minimapbutton", group = "General", section = "Minimap button", label = "Show the minimap button", tooltip = "Show a small button on the minimap. Click it for a menu: open Settings, toggle Let me focus, or hide the button. Drag the button to move it around the minimap." },
  { key = "mythicplustimer", group = "Mythic+ timer", section = "The overlay", label = "M+ run timer overlay", tooltip = "Show a movable overlay during an active Mythic+ run: time remaining, the +2/+3 upgrade windows, enemy forces, bosses, and deaths." },
  { key = "letmefocus", group = "Mythic+ timer", section = "The overlay", label = "Let me focus", tooltip = "Click the clock or the deaths on the overlay to hide them. Click again to bring them back. Useful on a pull where the timer is a distraction." },
  { key = "showaffixes", group = "Mythic+ timer", section = "What the overlay shows", label = "Show affixes", tooltip = "Draw this week's affix icons on the overlay. Turning this off removes the block for good, rather than hiding it for one run." },
  { key = "showforces", group = "Mythic+ timer", section = "What the overlay shows", label = "Show enemy forces", tooltip = "Draw the enemy forces percentage on the overlay, and turn the row green once the count is done." },
  { key = "showbosses", group = "Mythic+ timer", section = "What the overlay shows", label = "Show bosses", tooltip = "Draw the bosses section on the overlay, with each one ticked off as it dies." },
  { key = "showdeaths", group = "Mythic+ timer", section = "What the overlay shows", label = "Show deaths", tooltip = "Draw the deaths section on the overlay, with the time they have cost the run." },
  { key = "showbarticks", group = "Mythic+ timer", section = "What the overlay shows", label = "Show +2/+3 tick marks", tooltip = "Draw thin white tick lines on the time bar marking the +2 and +3 upgrade windows." },
  { key = "autoslotkey", group = "Mythic+ timer", section = "Starting a key", label = "Auto-slot your keystone", tooltip = "Place your keystone into the Font of Power automatically when it is opened, so you do not have to drag it in." },
  { key = "autonameplates", group = "Mythic+ timer", section = "During a key", label = "Enable enemy nameplates in keys", tooltip = "Turn on enemy nameplates at the start of a Mythic+ key, then put your own setting back when the key ends." },
  { key = "seasontp", group = "Mythic+ Window", section = "Season Best", label = "Teleport from Season Best icons", tooltip = "Click a dungeon under Season Best in the Mythic+ Dungeons window to teleport there, when you have earned that teleport." },
  { key = "guildkeys", group = "Mythic+ Window", section = "Your guild", label = "Guild keys this week", tooltip = "Add a panel to the Mythic+ Dungeons window listing your guild's best keys for the current week." },
  { key = "chatlinks", group = "Chat", section = "Links", label = "Clickable links in chat", tooltip = "Turn web addresses in chat into a link. Click one to copy it." },
  { key = "chatcopy", group = "Chat", section = "Copying", label = "Copy button on the chat window", tooltip = "Add a Copy button to each chat window. It opens that window's text in a box you can select and copy." },
  { key = "joinpopup", group = "Alerts", section = "Group finder", label = "Show which key you joined", tooltip = "When you join a group through the Group Finder, show the dungeon you were accepted into, its party, and a teleport button when you have one." },
  { key = "bloodlust", group = "Alerts", section = "Group chat", label = "Alert when bloodlust is called", tooltip = "Show a short on-screen alert when someone in your group types bl, hero, lust, drums, or the like." },
  { key = "buffreminder", group = "Alerts", section = "Buff reminder", label = "Remind about missing party buffs", tooltip = "Flag a class party buff that has been missing from a group member for a while. Only classes actually in the group are checked. It posts only inside a dungeon once the key is under way, never out in the world, in a raid, or while the group is still buffing before the run." },
  { key = "buffthreshold", type = "number", min = 15, max = 60, group = "Alerts", section = "Buff reminder", label = "Missing for at least (seconds)", tooltip = "How long a buff must be missing from a member before it is flagged. Between 15 and 60 seconds." },
  { key = "buffdelivery", type = "choice", choices = { { value = "chat", label = "Party chat" }, { value = "popup", label = "Popup" }, { value = "both", label = "Both" } }, group = "Alerts", section = "Buff reminder", label = "Show the reminder as", tooltip = "A message in party chat, an on-screen popup, or both. Party-chat messages are coordinated between group members running this addon, so only one is posted and they share the wait below." },
  { key = "buffcooldown", group = "Alerts", section = "Buff reminder", label = "Limit how often it reminds", tooltip = "Wait between reminders instead of flagging every missing buff. Turn off to be reminded whenever a buff is missing. The wait is shared with other group members running this addon." },
  { key = "buffcooldownmins", type = "number", min = 1, max = 30, group = "Alerts", section = "Buff reminder", label = "Wait between reminders (minutes)", tooltip = "Minutes to wait between reminders while the limit above is on. Between 1 and 30." },
  { key = "buffmage", group = "Alerts", section = "Which buffs", label = "Arcane Intellect (Mage)", tooltip = "Track Arcane Intellect when a Mage is in the group." },
  { key = "buffpriest", group = "Alerts", section = "Which buffs", label = "Power Word: Fortitude (Priest)", tooltip = "Track Power Word: Fortitude when a Priest is in the group." },
  { key = "buffwarrior", group = "Alerts", section = "Which buffs", label = "Battle Shout (Warrior)", tooltip = "Track Battle Shout when a Warrior is in the group." },
  { key = "buffdruid", group = "Alerts", section = "Which buffs", label = "Mark of the Wild (Druid)", tooltip = "Track Mark of the Wild when a Druid is in the group." },
  { key = "buffshaman", group = "Alerts", section = "Which buffs", label = "Skyfury (Shaman)", tooltip = "Track Skyfury when a Shaman is in the group." },
  { key = "buffevoker", group = "Alerts", section = "Which buffs", label = "Blessing of the Bronze (Evoker)", tooltip = "Track Blessing of the Bronze when an Evoker is in the group." },
  { key = "notepad", group = "Note", section = "The note window", label = "Show the note window", tooltip = "A note window that appears in a dungeon, with a general dungeon note plus a note per boss. Each dungeon keeps its own notes, and they survive a reload or wipe." },
  { key = "notepadmode", type = "choice", choices = { { value = "everywhere", label = "Always" }, { value = "indungeon", label = "Just inside dungeon" }, { value = "hideatstart", label = "Hide at key start" } }, group = "Note", section = "The note window", label = "When to show it", tooltip = "Shown everywhere the note is turned on; only while you are inside a dungeon; or inside the dungeon until a keystone starts and then hidden for the run." },
  { key = "notepadlocked", group = "Note", section = "The note window", label = "Lock the note window", tooltip = "Stop the note window from being dragged. You can also lock it from the window itself." },
  { key = "notebossauto", group = "Note", section = "The note window", label = "Follow the fight", tooltip = "Automatically open a boss's tab as you get near it or pull it, and go back to the Dungeon tab once the boss is down or you leave. Turn off to switch tabs yourself." },
  { key = "autorepair", group = "Automation", section = "At a merchant", label = "Auto repair", tooltip = "Repair your gear automatically when you talk to a merchant that can repair." },
  { key = "autorepairguild", group = "Automation", section = "At a merchant", label = "Use guild funds first", tooltip = "Repair from the guild bank when you are allowed to, and only fall back to your own gold otherwise." },
  { key = "autosell", group = "Automation", section = "At a merchant", label = "Auto sell junk", tooltip = "Sell all grey (junk) quality items automatically when you talk to a merchant." },
  { key = "autoquestmode", type = "choice", choices = { { value = "dungeon", label = "In dungeons" }, { value = "always", label = "Always" }, { value = "never", label = "Never" } }, group = "Automation", section = "Quests", label = "Auto accept and turn in quests", tooltip = "Automatically accept and hand in quests. In dungeons only, everywhere, or never. Quests that reward a choice of items are left for you." },
  { key = "defaultdifficulty", type = "choice", choices = { { value = "off", label = "Off" }, { value = "normal", label = "Normal" }, { value = "heroic", label = "Heroic" }, { value = "mythic", label = "Mythic" }, { value = "mythicplus", label = "Mythic+" } }, group = "Automation", section = "Start a Dungeon Group", label = "Default difficulty", tooltip = "When you create a group listing, keep it on this difficulty as you switch dungeons instead of letting it reset. You can still pick another difficulty yourself. Off leaves it alone." },
  { key = "groupplaystyle", type = "choice", choices = { { value = "off", label = "Off" }, { value = "1", label = "Learning" }, { value = "2", label = "Relaxed" }, { value = "3", label = "Competitive" }, { value = "4", label = "Carry offered" } }, group = "Automation", section = "Start a Dungeon Group", label = "Default playstyle", tooltip = "Preselect the required \"Select Playstyle\" on a new group listing. Off leaves it for you to pick; otherwise it defaults to the chosen playstyle, which you can still change." },
  { key = "mythicwarn", group = "Automation", section = "Start a Dungeon Group", label = "Warn if not set to Mythic", tooltip = "Warn you when you enter a dungeon that is not set to Mythic difficulty." },
  { key = "keyshare", group = "Automation", section = "Start a Dungeon Group", label = "Party key dropdown", tooltip = "Share your own keystone with group members running this addon, and add a dropdown to the create-a-group panel listing everyone's keys. Pick one to fill in that dungeon and a \"+level\" title; the difficulty and playstyle stay on your defaults above." },
  { key = "keylink", group = "Chat", section = "Keystone", label = "Reply to \"!keys\" with your key", tooltip = "When someone types !keys in party, instance, or guild chat, post a link to the keystone you are carrying. Works for anyone asking, whether or not they run this addon." },

  { key = "acceptpartyfriends", group = "Automation", section = "Accept from friends", label = "Accept party invites from friends", tooltip = "Automatically accept a party invite from a friend, unless you are queued for a dungeon or raid. Guild and community members can count as friends below." },
  { key = "confirmqueuerole", type = "choice", choices = { { value = "off", label = "Off" }, { value = "last", label = "Last used role" }, { value = "roles", label = "Chosen roles" } }, group = "Automation", section = "Accept from friends", label = "Confirm role when a friend queues", tooltip = "Automatically confirm the ready/role check when the group leader who started it is a friend. \"Last used role\" confirms with whatever roles you last queued as; \"Chosen roles\" confirms with the roles ticked below. Guild and community members can count as friends below." },
  { key = "confirmqueueroles", type = "multichoice", choices = { { value = "tank", label = "Tank" }, { value = "healer", label = "Healer" }, { value = "dps", label = "DPS" } }, group = "Automation", section = "Accept from friends", label = "Roles to confirm as", tooltip = "Which roles to confirm as when \"Confirm role when a friend queues\" is set to \"Chosen roles\". Pick any combination. Only roles your current spec can actually fill are used, so a set with all three still queues an alt that can only DPS as DPS. If none of the ticked roles fit this spec, the last used role is kept instead." },
  { key = "invitefromwhisper", group = "Automation", section = "Invite from whispers", label = "Invite when whispered a keyword", tooltip = "Invite anyone who whispers you the keyword below to your group, as long as you are the leader (or not in a group) and not queued." },
  { key = "invitekeyword", type = "text", default = "inv", group = "Automation", section = "Invite from whispers", label = "Keyword", tooltip = "The whisper that triggers an invite. Case is ignored. Defaults to \"inv\"." },
  { key = "invitefriendsonly", group = "Automation", section = "Invite from whispers", label = "Only invite friends", tooltip = "Only send an invite when the person who whispered the keyword is a friend. Turn off to invite anyone who whispers it. Battle.net whispers always invite the friend who sent them." },
  { key = "blockpartyinvites", group = "Automation", section = "Block", label = "Block party invites", tooltip = "Decline party invites from anyone who is not a friend. Guild and community members can count as friends below." },
  { key = "blockrequestedinvites", group = "Automation", section = "Block", label = "Block requested invites", tooltip = "Decline \"has requested to join your group\" confirmations from anyone who is not a friend, such as clicks on your group listing. Guild and community members can count as friends below." },
  { key = "blockduels", group = "Automation", section = "Block", label = "Block duels", tooltip = "Decline duel requests from anyone who is not a friend. Guild and community members can count as friends below." },
  { key = "friendlyguild", group = "Automation", section = "Also count as friends", label = "Treat guild members as friends", tooltip = "Count online guild members as friends for the accept, invite, and block options above. New members may need a roster refresh (press J) before they are recognised." },
  { key = "friendlycommunities", group = "Automation", section = "Also count as friends", label = "Treat community members as friends", tooltip = "Count online members of your communities as friends for the accept, invite, and block options above." },
}

-- Drawn under the tab strip: a tab name alone does not say what it changes.
ns.TAB_DESC = {
  ["Mythic+ timer"] = "The overlay during a run, what it shows, and what happens as a key starts.",
  ["Mythic+ Window"] = "What this addon adds inside Blizzard's own Mythic+ Dungeons window.",
  ["Chat"] = "What it adds to your chat windows.",
  ["Alerts"] = "Notices that appear on screen while you play.",
  ["Note"] = "Per-dungeon notes: a general dungeon note plus a note per boss, and where to prepare them ahead of time.",
  ["Automation"] = "Hands-off conveniences: merchants, quest givers, the group finder, and handling invites, whispers, and duels from other players.",
  ["General"] = "The minimap button, the movable test frames, and other addon-wide settings.",
  ["About"] = "Which version you are on, and where to find the addon.",
}

-- ── Profiles ─────────────────────────────────────────────────────────────
-- Every setting above lives in a named profile, so one account can keep more
-- than one look and pick which a character uses. MythicPlusTimerConfig holds:
--   profiles     name -> { option key -> value }
--   charProfile  "Name-Realm" -> the profile that character last loaded
--   mainProfile  the profile a brand-new character starts on
-- cfg()/setCfg() read and write the active profile's table; a value it does not
-- override falls back to DEFAULTS.

local activeProfile   -- name of the profile in use this session
local DEFAULT_PROFILE = "Default"
-- Point tables have a nil default, so they never appear in DEFAULTS; listed here
-- so profile export and per-profile sanitize still know about them.
local POINT_KEYS = { "mppoint", "jppoint", "blpoint", "buffpoint", "notepadpoint" }

local function charKey()
  local name, realm
  if type(UnitFullName) == "function" then
    local ok, n, r = pcall(UnitFullName, "player")
    if ok then name, realm = n, r end
  end
  if (not realm or realm == "") and type(GetNormalizedRealmName) == "function" then
    local ok, r = pcall(GetNormalizedRealmName)
    if ok then realm = r end
  end
  return (name or "player") .. "-" .. (realm or "")
end

local function config()
  if type(MythicPlusTimerConfig) ~= "table" then MythicPlusTimerConfig = {} end
  local c = MythicPlusTimerConfig
  if type(c.profiles) ~= "table" then c.profiles = {} end
  if type(c.charProfile) ~= "table" then c.charProfile = {} end
  return c
end

local function ensureProfile(name)
  local c = config()
  if type(c.profiles[name]) ~= "table" then c.profiles[name] = {} end
  return c.profiles[name]
end

-- One profile table, kept to known keys of the right type. Used both when
-- migrating an old flat config and when sanitizing each profile at login.
local function cleanProfile(src)
  local clean = {}
  for k, def in pairs(DEFAULTS) do
    local v = src[k]
    if v ~= nil and type(v) == type(def) then clean[k] = v end
  end
  if type(clean.mpscale) == "number" then
    clean.mpscale = math.max(0.6, math.min(2.0, clean.mpscale))
  end
  if type(clean.buffthreshold) == "number" then
    clean.buffthreshold = math.max(15, math.min(60, math.floor(clean.buffthreshold + 0.5)))
  end
  if type(clean.buffcooldownmins) == "number" then
    clean.buffcooldownmins = math.max(1, math.min(30, math.floor(clean.buffcooldownmins + 0.5)))
  end
  if type(clean.notepadw) == "number" then clean.notepadw = math.max(260, math.min(900, clean.notepadw)) end
  if type(clean.notepadh) == "number" then clean.notepadh = math.max(160, math.min(800, clean.notepadh)) end
  if type(clean.notepadcolw) == "number" then clean.notepadcolw = math.max(60, math.min(260, clean.notepadcolw)) end
  -- Choice keys accept only their known values; anything else falls to default.
  local CHOICES = {
    buffdelivery = { chat = true, popup = true, both = true },
    notepadmode = { everywhere = true, indungeon = true, hideatstart = true },
    autoquestmode = { always = true, never = true, dungeon = true },
    groupplaystyle = { off = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true },
    defaultdifficulty = { off = true, normal = true, heroic = true, mythic = true, mythicplus = true },
    confirmqueuerole = { off = true, last = true, roles = true },
  }
  -- notepadmode's options were reworked into show-everywhere / only-inside-a-
  -- dungeon / hide-once-the-key-starts. Carry the old (and interim) value names
  -- over so an existing setting keeps a sensible meaning.
  local NOTEPADMODE_MIGRATE = {
    always = "indungeon", hiddenuntilstart = "indungeon", duringkey = "indungeon",
    hiddenrun = "hideatstart", untilstart = "hideatstart",
  }
  if NOTEPADMODE_MIGRATE[clean.notepadmode] then
    clean.notepadmode = NOTEPADMODE_MIGRATE[clean.notepadmode]
  end
  -- confirmqueuerole was once a checkbox: carry the old boolean over to the
  -- matching choice so an existing setting is not silently reset.
  if clean.confirmqueuerole == true then clean.confirmqueuerole = "last"
  elseif clean.confirmqueuerole == false then clean.confirmqueuerole = "off" end
  -- A single-role choice ("tank"/"healer"/"dps") became the multi-role set: fold it
  -- into "Chosen roles" with that one role ticked, so an upgrade keeps its meaning.
  local ROLE_KEYS = { tank = true, healer = true, dps = true }
  if ROLE_KEYS[clean.confirmqueuerole] then
    clean.confirmqueueroles = { [clean.confirmqueuerole] = true }
    clean.confirmqueuerole = "roles"
  end
  for key, allowed in pairs(CHOICES) do
    if clean[key] ~= nil and not allowed[clean[key]] then clean[key] = nil end
  end
  -- Keep the role set to the three known role keys, each a plain boolean.
  if type(clean.confirmqueueroles) == "table" then
    local r = {}
    for role in pairs(ROLE_KEYS) do if clean.confirmqueueroles[role] then r[role] = true end end
    clean.confirmqueueroles = r
  end
  for _, key in ipairs(POINT_KEYS) do
    local p = src[key]
    if type(p) == "table" and type(p.point) == "string"
      and type(p.x) == "number" and type(p.y) == "number" then
      clean[key] = { point = p.point, x = p.x, y = p.y }
    end
  end
  return clean
end

-- Picks the profile for the current character. A character sticks to a profile
-- only once it has been switched to one explicitly (loadProfile records that in
-- charProfile). Until then it is un-pinned and follows the account main, so
-- renaming or changing main moves every un-pinned character with it, and a
-- brand-new character starts on the current main. Falls back to Default before
-- any main is set. This does not write charProfile: the auto-resolved choice is
-- deliberately not recorded, or it would pin the character to whatever main was
-- at first login.
local function resolveActiveProfile()
  local c = config()
  local pinned = c.charProfile[charKey()]
  if type(c.profiles[pinned]) ~= "table" then pinned = nil end
  local name = pinned
  if not name and c.mainProfile and type(c.profiles[c.mainProfile]) == "table" then
    name = c.mainProfile
  end
  name = name or DEFAULT_PROFILE
  ensureProfile(name)
  if not c.mainProfile then c.mainProfile = name end
  activeProfile = name
  return name
end

local function activeTable()
  if not activeProfile then resolveActiveProfile() end
  return ensureProfile(activeProfile)
end

function ns.cfg(k)
  local t = activeTable()
  if t[k] ~= nil then return t[k] end
  return DEFAULTS[k]
end

function ns.setCfg(k, v)
  activeTable()[k] = v
end

-- ── Profile operations ───────────────────────────────────────────────────
-- The management a Profiles page needs. All name the active profile through
-- LoadProfile so the overlay and options redraw against the newly chosen set.

function ns.activeProfile() return activeProfile or resolveActiveProfile() end

function ns.profileNames()
  local c, names = config(), {}
  for name in pairs(c.profiles) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function ns.loadProfile(name)
  local c = config()
  if type(c.profiles[name]) ~= "table" then return false end
  c.charProfile[charKey()] = name
  activeProfile = name
  if type(ns.onProfileChanged) == "function" then pcall(ns.onProfileChanged) end
  return true
end

function ns.createProfile(name)
  if type(name) ~= "string" or name == "" then return false end
  local c = config()
  if type(c.profiles[name]) ~= "table" then c.profiles[name] = {} end
  if not c.mainProfile then c.mainProfile = name end
  return ns.loadProfile(name)
end

-- Overwrites the active profile with a copy of another one's values, keeping the
-- active profile's own name/slot. Nothing is shared: the copy is by value.
function ns.copyProfileFrom(name)
  local c = config()
  local src = c.profiles[name]
  if type(src) ~= "table" or name == activeProfile then return false end
  local dst = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      local t = {}; for kk, vv in pairs(v) do t[kk] = vv end; dst[k] = t
    else
      dst[k] = v
    end
  end
  c.profiles[activeProfile] = dst
  if type(ns.onProfileChanged) == "function" then pcall(ns.onProfileChanged) end
  return true
end

-- Empties the active profile so every setting falls back to its default.
function ns.resetProfile()
  config().profiles[activeProfile or resolveActiveProfile()] = {}
  if type(ns.onProfileChanged) == "function" then pcall(ns.onProfileChanged) end
end

function ns.deleteProfile(name)
  local c = config()
  if type(c.profiles[name]) ~= "table" then return false end
  c.profiles[name] = nil
  if c.mainProfile == name then c.mainProfile = nil end
  for k, v in pairs(c.charProfile) do
    if v == name then c.charProfile[k] = nil end
  end
  if activeProfile == name then
    activeProfile = nil
    resolveActiveProfile()
    if type(ns.onProfileChanged) == "function" then pcall(ns.onProfileChanged) end
  end
  return true
end

function ns.setMainProfile(name)
  local c = config()
  if type(c.profiles[name]) == "table" then c.mainProfile = name; return true end
  return false
end

function ns.mainProfile() return config().mainProfile end

-- ── Profile export / import ──────────────────────────────────────────────
-- A profile is a copy-paste string so a look can be shared. No compression
-- library, so the format is deliberately small and hand-parsed: a version tag
-- then one `key=tag:value` field per line, tags b(ool) n(umber) s(tring)
-- p(oint). Only known keys and value types are read back, so a malformed or
-- hostile string can at worst be rejected, never run.
local function escape(s) return (s:gsub("[%%\n]", function(c) return string.format("%%%02X", c:byte()) end)) end
local function unescape(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

function ns.exportProfile(name)
  local c = config()
  local t = c.profiles[name or activeProfile]
  if type(t) ~= "table" then return nil end
  local lines = { "MPTT1" }
  local function emit(k, v)
    if type(v) == "boolean" then
      lines[#lines + 1] = k .. "=b:" .. (v and "1" or "0")
    elseif type(v) == "number" then
      lines[#lines + 1] = k .. "=n:" .. tostring(v)
    elseif type(v) == "string" then
      lines[#lines + 1] = k .. "=s:" .. escape(v)
    elseif type(v) == "table" and type(v.point) == "string" then
      lines[#lines + 1] = k .. "=p:" .. v.point .. "," .. tostring(v.x) .. "," .. tostring(v.y)
    end
  end
  -- Every setting, at its effective value: the profile's own when it set one,
  -- otherwise the default. So the string is complete and self-contained, and an
  -- import reproduces the same state whatever a later version's defaults become.
  for k, def in pairs(DEFAULTS) do
    local v = t[k]
    if v == nil then v = def end
    emit(k, v)
  end
  -- Positions have no default (nil), so only a set one is worth carrying.
  for _, k in ipairs(POINT_KEYS) do if t[k] ~= nil then emit(k, t[k]) end end
  return table.concat(lines, "\n")
end

-- Parses an export string into a fresh profile and loads it. Returns the new
-- profile's name, or nil when the string is not one of ours.
function ns.importProfile(str, name)
  if type(str) ~= "string" then return nil end
  local lines = {}
  for line in (str .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  if lines[1] ~= "MPTT1" then return nil end
  local data = {}
  local pointKey = {}
  for _, k in ipairs(POINT_KEYS) do pointKey[k] = true end
  for i = 2, #lines do
    local k, tag, val = lines[i]:match("^(%w+)=(%w):(.*)$")
    if k and (DEFAULTS[k] ~= nil or pointKey[k]) then
      if tag == "b" then
        data[k] = val == "1"
      elseif tag == "n" then
        data[k] = tonumber(val)
      elseif tag == "s" then
        data[k] = unescape(val)
      elseif tag == "p" then
        local pt, x, y = val:match("^(%u+),(-?%d+%.?%d*),(-?%d+%.?%d*)$")
        if pt then data[k] = { point = pt, x = tonumber(x), y = tonumber(y) } end
      end
    end
  end
  local c = config()
  name = name or "Imported"
  local n, base = name, name
  while type(c.profiles[n]) == "table" do n = base .. " " .. (tonumber(n:match("(%d+)$")) or 1) + 1 end
  c.profiles[n] = data
  ns.loadProfile(n)
  return n
end

-- Shared drag-position helpers for the overlay, join popup, and alert. They
-- always store the frame's TOP edge: StopMovingOrSizing can leave GetPoint's
-- point and relativePoint disagreeing, and a top anchor grows downward so a
-- frame that changes height keeps its title fixed. SetPoint offsets are in the
-- frame's own scaled space, so screen positions are divided back by its scale.
local function topAnchorOffsets(f)
  if type(UIParent) ~= "table" then return nil end
  local ok, x, y = pcall(function()
    local eff, uiEff = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local cx, top = f:GetCenter(), f:GetTop()
    local uiCX, uiTop = UIParent:GetCenter(), UIParent:GetTop()
    if type(eff) ~= "number" or eff <= 0 or type(uiEff) ~= "number" then return nil end
    if type(cx) ~= "number" or type(top) ~= "number"
      or type(uiCX) ~= "number" or type(uiTop) ~= "number" then return nil end
    return (cx * eff - uiCX * uiEff) / eff, (top * eff - uiTop * uiEff) / eff
  end)
  if not ok then return nil end
  return x, y
end

-- Re-anchors `f` by its top edge where it currently stands, and records that.
-- Called on every drop, so the stored position is one we wrote rather than
-- whatever the client's own move left behind.
function ns.savePosition(f, key)
  local x, y = topAnchorOffsets(f)
  if x and y then
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", x, y)
    ns.setCfg(key, { point = "TOP", x = x, y = y })
    return
  end
  -- Geometry not queryable (a frame with no resolvable anchor yet): store the
  -- anchor as it stands rather than losing where it was dropped.
  local point, _, _, px, py = f:GetPoint()
  if type(point) == "string" and type(px) == "number" and type(py) == "number" then
    ns.setCfg(key, { point = point, x = px, y = py })
  end
end

-- Puts `f` back where it was left, or at the default the feature names. Both
-- are a plain point/x/y against UIParent, since none of these frames is ever
-- anchored to anything else.
function ns.restorePosition(f, key, point, x, y)
  local p = ns.cfg(key)
  f:ClearAllPoints()
  if type(p) == "table" and type(p.point) == "string"
    and type(p.x) == "number" and type(p.y) == "number" then
    f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    -- Saved by an older version, which stored whichever anchor a drag left.
    -- Convert it once, in place, so this frame also grows downward from here on.
    if p.point ~= "TOP" then ns.savePosition(f, key) end
  else
    f:SetPoint(point, UIParent, point, x, y)
  end
end

-- ── What a feature hands back ────────────────────────────────────────────
-- Registries the shared surfaces read at login, so a feature is never named
-- outside its own file.

ns.commands = {}       -- ordered { name, help, run }; help = nil hides it from /mpt
ns.optionChanged = {}  -- config key -> fn(), run when its checkbox is flipped
ns.optionButtons = {}  -- ordered { name, label, tooltip, run }, drawn under the checkboxes
ns.previews = {}       -- ordered { name, show, hide }, the movable frames as a set

-- `help` is one short phrase for the /mpt list, or nil for a subcommand that is
-- documented by another one's output rather than by the list.
function ns.command(name, help, run)
  ns.commands[#ns.commands + 1] = { name = name, help = help, run = run }
end

function ns.onOptionChanged(key, fn)
  ns.optionChanged[key] = fn
end

-- A button in the Settings panel, for the things a checkbox cannot express:
-- "show me this so I can put it where I want it".
function ns.optionButton(name, label, tooltip, run)
  ns.optionButtons[#ns.optionButtons + 1] =
    { name = name, label = label, tooltip = tooltip, run = run }
end

-- A draggable frame, so the shared surfaces can put every movable frame up at
-- once for positioning. `show`/`hide` take no args and must not disturb a real
-- one already on screen. `getFrame` returns the frame itself (for the edit-mode
-- overlay to attach to), and `target` is { group, section } naming where the
-- overlay's "Click to edit" jumps to in Settings.
function ns.previewFrame(name, show, hide, getFrame, target)
  ns.previews[#ns.previews + 1] =
    { name = name, show = show, hide = hide, getFrame = getFrame, target = target }
end

-- ── Small helpers ────────────────────────────────────────────────────────

function ns.print(msg)
  print(GOLD .. "Mythic+ Timer and Tools" .. ENDC .. GREY .. ": " .. msg .. ENDC)
end

-- A player's name in their class color, from the client's own table so it
-- tracks whatever the player has themselves set. Shared: the overlay's death
-- list and the guild panel's party tooltip both name people.
function ns.classColoredName(name, englishClass)
  local c = RAID_CLASS_COLORS and englishClass and RAID_CLASS_COLORS[englishClass]
  if c and c.colorStr then return "|c" .. c.colorStr .. name .. ENDC end
  return ns.WHITE .. name .. ENDC
end

-- A Mythic+ rating painted the exact color Raider.IO would use. When Raider.IO
-- is installed we ask its public API, so our number matches theirs to the pixel
-- and tracks their seasonal gradient with nothing bundled or downloaded here.
-- Without Raider.IO we fall back to the client's item-quality color for the
-- score's band. nil/0 renders as a grey dash.
local SCORE_QUALITY = {
  { 3000, 6 },  -- artifact
  { 2560, 5 },  -- legendary
  { 2080, 4 },  -- epic
  { 1600, 3 },  -- rare
  { 0,    2 },  -- uncommon
}
local function scoreRGB(score)
  local rio = _G.RaiderIO
  if rio and rio.GetScoreColor then
    -- Returns nothing when it declines (e.g. mid-combat); fall through then.
    local ok, r, g, b = pcall(rio.GetScoreColor, score)
    if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  if type(GetItemQualityColor) == "function" then
    local quality = 2
    for i = 1, #SCORE_QUALITY do
      if score >= SCORE_QUALITY[i][1] then quality = SCORE_QUALITY[i][2]; break end
    end
    local r, g, b = GetItemQualityColor(quality)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  return nil
end
function ns.scoreColored(score)
  if type(score) ~= "number" or score <= 0 then return ns.GREY .. "-" .. ns.ENDC end
  local r, g, b = scoreRGB(score)
  local hex = GOLD_HEX
  if r then
    hex = string.format("%02x%02x%02x",
      math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
  end
  return "|cff" .. hex .. score .. ns.ENDC
end

-- Newer clients can hand addons "secret" values that error on any real use.
-- Treat those the same as data we don't have.
function ns.isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v)
end

-- Normalizes the SavedVariables once at login (a crash or hand-edit can leave a
-- shape this version doesn't expect), before any feature reads them. The run
-- mirror is validated more strictly in the timer's restore path.
local function sanitizeSavedVars()
  if type(MythicPlusTimerConfig) ~= "table" then
    MythicPlusTimerConfig = nil
  else
    local c = MythicPlusTimerConfig
    -- A config from before profiles kept its option keys at the top level. Fold
    -- them into a Default profile so an upgrade never loses someone's settings.
    if type(c.profiles) ~= "table" then
      local legacy = cleanProfile(c)
      c = { profiles = {}, charProfile = {} }
      if next(legacy) then c.profiles[DEFAULT_PROFILE] = legacy end
    end
    local profiles = {}
    for name, p in pairs(c.profiles) do
      if type(name) == "string" and type(p) == "table" then
        profiles[name] = cleanProfile(p)
      end
    end
    local charProfile = {}
    if type(c.charProfile) == "table" then
      for k, v in pairs(c.charProfile) do
        if type(k) == "string" and type(v) == "string" and profiles[v] then charProfile[k] = v end
      end
    end
    local main = (type(c.mainProfile) == "string" and profiles[c.mainProfile]) and c.mainProfile or nil
    MythicPlusTimerConfig = { profiles = profiles, charProfile = charProfile, mainProfile = main }
  end
  -- Force the active profile to re-resolve against the cleaned config.
  activeProfile = nil
  -- Run mirror: the timer validates it strictly; only guarantee the type.
  if MythicPlusTimerRun ~= nil and type(MythicPlusTimerRun) ~= "table" then MythicPlusTimerRun = nil end
end

local sanitizer = CreateFrame("Frame")
sanitizer:RegisterEvent("PLAYER_LOGIN")
sanitizer:SetScript("OnEvent", function() pcall(sanitizeSavedVars) end)

-- Taint diagnostics. A "blocked from an action only available to the Blizzard
-- UI" block is not a Lua error (pcall can't catch it), so we log it from
-- ADDON_ACTION_BLOCKED/FORBIDDEN to make it copyable. Once per session.
do
  local reported = false
  local taintFrame = CreateFrame("Frame")
  taintFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
  taintFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
  taintFrame:SetScript("OnEvent", function(_, event, addonName, funcName)
    if reported or type(addonName) ~= "string" then return end
    if not addonName:lower():find("mythicplustimer", 1, true) then return end
    reported = true
    -- Fires inside the tainted call stack; defer a frame so the print itself
    -- doesn't taint the chat frame too.
    C_Timer.After(0, function()
      print(GOLD .. "Mythic+ Timer and Tools" .. ENDC .. GREY .. ": blocked from calling " .. ENDC
        .. ns.WHITE .. tostring(funcName) .. ENDC .. GREY .. " (" .. event
        .. "). Please report this and what you were doing when it happened." .. ENDC)
    end)
  end)
end
