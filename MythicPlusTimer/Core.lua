-- Shared core: palette, config, and the registries features use to plug in.
-- Features depend on Core; Core depends on nothing.

local _, ns = ...

-- Armory gold, one source: the |cff text color and the RGB texture tint both
-- derive from this hex.
local GOLD_HEX = "e0a54e"
ns.GOLD_HEX = GOLD_HEX
ns.GOLD, ns.GREY, ns.WHITE = "|cff" .. GOLD_HEX, "|cff9d9d9d", "|cffffffff"
ns.GREEN, ns.RED, ns.ENDC = "|cff40c057", "|cffe0524e", "|r"
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
}
ns.DEFAULTS = DEFAULTS

-- One row per user-facing option; drives both the settings panel and /mpt.
-- Rows in the same `group` must stay adjacent (the panel opens a section per
-- group change).
ns.OPTIONS = {
  { key = "mythicplustimer", group = "Run overlay", label = "M+ run timer overlay", tooltip = "Show a movable overlay during an active Mythic+ run: time remaining, the +2/+3 upgrade windows, enemy forces, bosses, and deaths." },
  { key = "autonameplates", group = "Run overlay", label = "Enable enemy nameplates in keys", tooltip = "Turn on enemy nameplates at the start of a Mythic+ key, then restore your setting when the key ends." },
  { key = "letmefocus", group = "Run overlay", label = "Let me focus", tooltip = "Click the clock or the deaths on the overlay to hide them. Click again to bring them back." },
  { key = "guildkeys", group = "Mythic+ window", label = "Guild keys this week", tooltip = "Show your guild's best keys for the current week inside the Mythic+ Dungeons window." },
  { key = "autoslotkey", group = "Mythic+ window", label = "Auto-slot your keystone", tooltip = "Place your keystone automatically when the Font of Power is opened." },
  { key = "seasontp", group = "Mythic+ window", label = "Teleport from Season Best icons", tooltip = "Click a dungeon under Season Best in the Mythic+ Dungeons window to teleport there." },
  { key = "chatlinks", group = "Chat", label = "Clickable links in chat", tooltip = "Turn web addresses in chat into a link. Click one to copy it." },
  { key = "chatcopy", group = "Chat", label = "Copy button on the chat window", tooltip = "Add a Copy button to each chat window. It opens that window's text in a box you can select and copy." },
  { key = "joinpopup", group = "Alerts", label = "Show which key you joined", tooltip = "When you join a group through the Group Finder, show the dungeon you were accepted into, with a teleport button when you have one." },
  { key = "bloodlust", group = "Alerts", label = "Alert when bloodlust is called", tooltip = "Show a short on-screen alert when someone in your group types bl, hero, lust, drums, or the like." },
  { key = "showaffixes", group = "Display", label = "Show affixes", tooltip = "Draw this week's affix icons on the overlay." },
  { key = "showforces", group = "Display", label = "Show enemy forces", tooltip = "Draw the enemy forces percentage on the overlay." },
  { key = "showbosses", group = "Display", label = "Show bosses", tooltip = "Draw the bosses section on the overlay." },
  { key = "showdeaths", group = "Display", label = "Show deaths", tooltip = "Draw the deaths section on the overlay." },
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
local POINT_KEYS = { "mppoint", "jppoint", "blpoint" }

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
  for _, key in ipairs(POINT_KEYS) do
    local p = src[key]
    if type(p) == "table" and type(p.point) == "string"
      and type(p.x) == "number" and type(p.y) == "number" then
      clean[key] = { point = p.point, x = p.x, y = p.y }
    end
  end
  return clean
end

-- Picks the profile for the current character: the one it last used, else the
-- account's main profile, else Default. Records the choice so it sticks.
local function resolveActiveProfile()
  local c = config()
  local name = c.charProfile[charKey()]
  if type(c.profiles[name]) ~= "table" then name = nil end
  if not name and c.mainProfile and type(c.profiles[c.mainProfile]) == "table" then
    name = c.mainProfile
  end
  name = name or DEFAULT_PROFILE
  ensureProfile(name)
  c.charProfile[charKey()] = name
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

-- A table view of the active profile, for APIs that read and write config
-- through a table rather than functions (Blizzard's Settings binder). Every
-- access routes to cfg/setCfg, so a checkbox bound to it follows the active
-- profile even after the profile is switched.
ns.cfgProxy = setmetatable({}, {
  __index = function(_, k) return ns.cfg(k) end,
  __newindex = function(_, k, v) ns.setCfg(k, v) end,
})

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
  for k in pairs(DEFAULTS) do if t[k] ~= nil then emit(k, t[k]) end end
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
-- one already on screen.
function ns.previewFrame(name, show, hide)
  ns.previews[#ns.previews + 1] = { name = name, show = show, hide = hide }
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
