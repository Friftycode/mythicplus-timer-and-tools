-- A small mock of the WoW client API: enough for the addon to load and draw.
-- Unimplemented frame methods degrade to no-op stubs, so tests fail on behavior.

Mock = {
  now = 1000,          -- GetTime()
  timers = {},         -- pending C_Timer.After callbacks
  frames = {},         -- every frame ever created
  prints = {},         -- captured print() output
  cvars = { nameplateShowEnemies = "0" },
  settings = { category = nil, checkboxes = {}, buttons = {}, headers = {}, callbacks = {} },
}

time = os.time
date = os.date

function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  Mock.prints[#Mock.prints + 1] = table.concat(parts, " ")
end

-- ── Frames ────────────────────────────────────────────────────────────────

local FrameMT = {}

local function newRegion(kind, parent)
  local r = setmetatable({
    __kind = kind, __parent = parent, __shown = kind ~= "Frame",
    __text = "", __scripts = {}, __events = {}, __hooks = {},
    __scale = 1, __point = nil, __children = {},
  }, FrameMT)
  return r
end

-- Unimplemented methods become no-op stubs. Only PascalCase names are stubbed;
-- lowercase data fields read nil, as they do on a real frame.
FrameMT.__index = function(t, k)
  local impl = FrameMT.methods[k]
  if impl then return impl end
  if type(k) ~= "string" or not k:match("^%u") then return nil end
  local stub = function() end
  rawset(t, k, stub)
  return stub
end

FrameMT.methods = {
  Show = function(self) self.__shown = true end,
  Hide = function(self) self.__shown = false end,
  IsShown = function(self) return self.__shown end,
  SetChecked = function(self, v) self.__checked = v and true or false end,
  GetChecked = function(self) return self.__checked end,
  SetEnabled = function(self, v) self.__enabled = v and true or false end,
  IsEnabled = function(self) return self.__enabled ~= false end,
  IsVisible = function(self) return self.__shown end,
  SetShown = function(self, v) self.__shown = v and true or false end,
  SetText = function(self, v) self.__text = tostring(v or "") end,
  GetText = function(self) return self.__text end,
  SetScale = function(self, v) self.__scale = v end,
  GetScale = function(self) return self.__scale end,
  -- Tracked so tests can assert the guild panel sizes itself to its content.
  SetHeight = function(self, v) self.__height = v end,
  GetHeight = function(self) return self.__height or 0 end,
  GetWidth = function(self) return self.__width or 0 end,
  SetSize = function(self, w, h) self.__width, self.__height = w, h end,
  SetPoint = function(self, point, _, _, x, y) self.__point = { point, x or 0, y or 0 } end,
  ClearAllPoints = function(self) self.__point = nil end,
  GetPoint = function(self)
    local p = self.__point or { "TOP", 0, 0 }
    return p[1], nil, nil, p[2], p[3]
  end,
  SetScript = function(self, k, fn) self.__scripts[k] = fn end,
  GetScript = function(self, k) return self.__scripts[k] end,
  GetParent = function(self) return self.__parent end,
  GetFrameLevel = function(self) return self.__level or 1 end,
  SetFrameLevel = function(self, v) self.__level = v end,
  HookScript = function(self, k, fn) self.__hooks[k] = self.__hooks[k] or {}; table.insert(self.__hooks[k], fn) end,
  RegisterEvent = function(self, ev) self.__events[ev] = true end,
  UnregisterEvent = function(self, ev) self.__events[ev] = nil end,
  UnregisterAllEvents = function(self) self.__events = {} end,
  CreateFontString = function(self, _, _, _)
    local fs = newRegion("FontString", self)
    table.insert(self.__children, fs)
    table.insert(Mock.frames, fs)
    return fs
  end,
  CreateTexture = function(self)
    local tx = newRegion("Texture", self)
    table.insert(self.__children, tx)
    table.insert(Mock.frames, tx)
    return tx
  end,
}

function CreateFrame(kind, name, parent, _template)
  local f = newRegion(kind, parent)
  f.__shown = false
  f.__name = name
  if parent and parent.__children then table.insert(parent.__children, f) end
  table.insert(Mock.frames, f)
  if name then _G[name] = f end
  return f
end

-- Fires an event at every frame registered for it, exactly as the client would.
function Mock.fire(event, ...)
  for _, f in ipairs(Mock.frames) do
    if f.__events and f.__events[event] and f.__scripts.OnEvent then
      f.__scripts.OnEvent(f, event, ...)
    end
  end
end

function Mock.showFrame(f)
  f.__shown = true
  for _, fn in ipairs((f.__hooks or {}).OnShow or {}) do fn(f) end
end

-- Advances the clock and runs the OnUpdate ticker + any due C_Timer callbacks.
function Mock.advance(seconds, step)
  step = step or 0.25
  local left = seconds
  while left > 0 do
    local dt = math.min(step, left)
    Mock.now = Mock.now + dt
    left = left - dt
    for _, f in ipairs(Mock.frames) do
      if f.__scripts.OnUpdate then f.__scripts.OnUpdate(f, dt) end
    end
    Mock.runTimers()
  end
end

function Mock.runTimers()
  local due, keep = {}, {}
  for _, t in ipairs(Mock.timers) do
    if t.at <= Mock.now then due[#due + 1] = t else keep[#keep + 1] = t end
  end
  Mock.timers = keep
  for _, t in ipairs(due) do t.fn() end
end

-- Every font string a frame (or its descendants) currently shows, joined.
-- Hidden ones are skipped on purpose: mpRender pools its cells and hides the
-- unused ones, so counting those would read last frame's text as this frame's.
function Mock.textOf(f, out)
  out = out or {}
  if f.__kind == "FontString" and f.__shown and f.__text ~= "" then out[#out + 1] = f.__text end
  for _, c in ipairs(f.__children or {}) do Mock.textOf(c, out) end
  return out
end

function Mock.rendered(f)
  return table.concat(Mock.textOf(f), "\n")
end

-- ── Client API ────────────────────────────────────────────────────────────

function GetTime() return Mock.now end
C_Timer = { After = function(delay, fn) table.insert(Mock.timers, { at = Mock.now + delay, fn = fn }) end }

Mock.state = {
  mapID = 375, level = 10, affixes = { 9, 6, 3 }, timeLimit = 1800,
  inInstance = true, deathCount = 0, dead = {},
  criteria = {
    { description = "Enemy Forces", isWeightedProgress = true, quantityString = "45 / 260", totalQuantity = 260, completed = false },
    { description = "Bloodtwisted Overseer", isWeightedProgress = false, completed = false },
    { description = "Sanguine Overseer", isWeightedProgress = false, completed = false },
  },
  guildLeaders = {},
  inGuild = true,
}

C_ChallengeMode = {
  GetActiveChallengeMapID = function() return Mock.state.mapID end,
  GetActiveKeystoneInfo = function() return Mock.state.level, Mock.state.affixes end,
  GetMapUIInfo = function(mapID)
    local names = { [375] = "Mists of Tirna Scithe", [376] = "The Necrotic Wake", [377] = "De Other Side" }
    return names[mapID] or "Unknown", 0, Mock.state.timeLimit
  end,
  GetMapTable = function() return { 375, 376, 377 } end,
  GetDeathCount = function() return Mock.state.deathCount end,
  GetAffixInfo = function(id) return "Affix " .. tostring(id), "Does a thing", 100 + id end,
  GetChallengeCompletionInfo = function() return { time = 1200 * 1000, onTime = true } end,
  GetGuildLeaders = function() return Mock.state.guildLeaders end,
  RequestLeaders = function() end,
}

-- Bags, for the keystone auto-slot. Mock.bags[bag][slot] = item LINK, the same
-- shape the real API returns, since the addon identifies a keystone by the
-- "Hkeystone" tag in its link rather than by item id.
NUM_BAG_SLOTS = 4
Mock.KEY_LINK = "|cffa335ee|Hkeystone:180653:375:14:9:6:3|h[Keystone: Mists (14)]|h|r"
Mock.JUNK_LINK = "|cffffffff|Hitem:12345::::::::70:::::|h[Healing Potion]|h|r"
Mock.bags = { [0] = {}, [1] = { Mock.JUNK_LINK, Mock.KEY_LINK }, [2] = {}, [3] = {}, [4] = {} }
Mock.cursor = nil
Mock.slotted = false
Mock.inCombat = false
Mock.inserts = 0

C_Container = {
  GetContainerNumSlots = function(bag) return #(Mock.bags[bag] or {}) end,
  GetContainerItemLink = function(bag, slot) return (Mock.bags[bag] or {})[slot] end,
  PickupContainerItem = function(bag, slot) Mock.cursor = (Mock.bags[bag] or {})[slot] end,
}
function ClearCursor() Mock.cursor = nil end

C_ChallengeMode.HasSlottedKeystone = function() return Mock.slotted end
C_ChallengeMode.SlotKeystone = function()
  if Mock.cursor == Mock.KEY_LINK then
    Mock.slotted, Mock.cursor = true, nil
    Mock.inserts = Mock.inserts + 1
  end
end

-- Which dungeon our key is for, against which one we're standing in. Equal by
-- default; a test sets them apart to check the mismatch guard.
Mock.ownedKeyMapID = 2290
Mock.instanceID = 2290
C_MythicPlus = { GetOwnedKeystoneMapID = function() return Mock.ownedKeyMapID end }

ChallengesKeystoneFrame = CreateFrame("Frame", "ChallengesKeystoneFrame")

-- ── Group Finder ──────────────────────────────────────────────────────────
-- One search result keyed by id, shaped like the real GetSearchResultInfo.
Mock.searchResults = {
  [77] = {
    name = "+18 AA  need dps  link io",
    leaderName = "Keypusher",
    activityIDs = { 1301 },
  },
  [78] = { name = "Heroic raid", leaderName = "Raidlead", activityIDs = { 9001 } },
}
Mock.activities = {
  [1301] = { fullName = "Algeth'ar Academy (Mythic Keystone)", isMythicPlusActivity = true },
  [9001] = { fullName = "Liberation of Undermine (Heroic)", isMythicPlusActivity = false },
}

C_LFGList = {
  GetSearchResultInfo = function(id) return Mock.searchResults[id] end,
  GetActivityInfoTable = function(id) return Mock.activities[id] end,
}

-- ── Spellbook (for teleport discovery) ────────────────────────────────────
-- Hero's Path flyouts hold the dungeon teleports; their slots may be matched by
-- description.
Mock.flyouts = {
  [500] = {
    name = "Hero's Path: Dragonflight", known = true,
    slots = {
      { spellID = 393256, name = "Path of the Scholar", known = true, desc = "Teleports you to Algeth'ar Academy." },
      { spellID = 393262, name = "Path of the Clutch", known = true, desc = "Teleports you to Ruby Life Pools." },
      -- Deliberately NOT named after its destination, which is the common real
      -- case: only the description identifies where this one goes.
      { spellID = 354463, name = "Path of the Ascended", known = true, desc = "Teleports you to Mists of Tirna Scithe." },
    },
  },
}
-- An ordinary spell that happens to be named after a dungeon still matches, but
-- only by NAME: descriptions are not read for the class-ability bulk of the
-- spellbook.
Mock.plainSpells = {
  { spellID = 131204, name = "Teleport: Skyreach", desc = "Teleports you to Skyreach." },
  -- A class ability whose description mentions a dungeon must NOT be matched.
  { spellID = 999001, name = "Lunar Beam", desc = "Recalls your travels through The Necrotic Wake." },
}
-- One flat list: flyout entries first, then plain spells.
Mock.spellBookItems = {
  { itemType = "flyout", actionID = 500 },
  { itemType = "spell", spellID = 131204 },
  { itemType = "spell", spellID = 999001 },
}

C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function(_)
    return { itemIndexOffset = 0, numSpellBookItems = #Mock.spellBookItems }
  end,
  GetSpellBookItemType = function(i)
    local it = Mock.spellBookItems[i]
    if not it then return nil end
    if it.itemType == "flyout" then return "FLYOUT", it.actionID, nil end
    return "SPELL", it.spellID, it.spellID
  end,
}
function GetFlyoutInfo(id)
  local fo = Mock.flyouts[id]
  if not fo then return nil end
  return fo.name, "", #fo.slots, fo.known
end
function GetFlyoutSlotInfo(id, slot)
  local s = Mock.flyouts[id] and Mock.flyouts[id].slots[slot]
  if not s then return nil end
  return s.spellID, nil, s.known, s.name
end

local function findSpell(spellID)
  for _, fo in pairs(Mock.flyouts) do
    for _, s in ipairs(fo.slots) do if s.spellID == spellID then return s end end
  end
  for _, s in ipairs(Mock.plainSpells) do if s.spellID == spellID then return s end end
  return nil
end
C_Spell = {
  GetSpellInfo = function(id) local s = findSpell(id); return s and { name = s.name } or nil end,
  GetSpellDescription = function(id) local s = findSpell(id); return s and s.desc or "" end,
  GetSpellTexture = function(id) return 100000 + id end,
}

C_Scenario = { GetStepInfo = function() return "Step", 1, #Mock.state.criteria end }
C_ScenarioInfo = { GetCriteriaInfo = function(i) return Mock.state.criteria[i] end }

-- Real signature: name, instanceType, difficultyID, difficultyName, maxPlayers,
-- dynamicDifficulty, isDynamic, instanceID, ... The addon reads the 8th value,
-- so the shape matters here, not just the first three.
function GetInstanceInfo()
  if Mock.state.inInstance then
    return "Mists", "party", 8, "Mythic Keystone", 5, 0, false, Mock.instanceID
  end
  return "Elwynn", "none", 0, "", 0, 0, false, 0
end

function GetWorldElapsedTimers() return { 1 } end
function GetWorldElapsedTime(_) return nil, 0, 1 end

Mock.units = {
  -- score/ilvl model the join popup's party table: your own ilvl is known, a
  -- party member's usually isn't until the client has an inspect for them.
  player = { name = "Testchar", class = "PALADIN", guid = "P-1", score = 2450, ilvl = 489 },
  party1 = { name = "Healer", class = "PRIEST", guid = "P-2", score = 2380 },
  party2 = { name = "Dpsguy", class = "MAGE", guid = "P-3", score = 2510 },
}
C_PlayerInfo = {
  GetPlayerMythicPlusRatingSummary = function(u)
    local x = Mock.units[u]
    return x and x.score and { currentSeasonScore = x.score } or nil
  end,
}
-- The inspect API reports 0 for yourself, exactly as the live one does; your own
-- gear is read from the character sheet instead.
C_PaperDollInfo = {
  GetInspectItemLevel = function(u)
    if u == "player" then return 0 end
    return (Mock.units[u] or {}).ilvl or 0
  end,
}
function GetAverageItemLevel()
  local il = (Mock.units.player or {}).ilvl or 0
  return il, il
end
function CanInspect(u) return Mock.state.canInspect ~= false and Mock.units[u] ~= nil end
-- Records who was asked about, so a test can answer with INSPECT_READY itself.
function NotifyInspect(u) Mock.state.inspected = (Mock.units[u] or {}).guid end
function ClearInspectPlayer() Mock.state.inspected = nil end
function UnitExists(u) return Mock.units[u] ~= nil end
function UnitGUID(u) return (Mock.units[u] or {}).guid end
function UnitIsUnit(a, b)
  local ua, ub = Mock.units[a], Mock.units[b]
  return ua ~= nil and ub ~= nil and ua.guid == ub.guid
end
function UnitName(u) return (Mock.units[u] or {}).name end
function UnitClassBase(u) return (Mock.units[u] or {}).class end
function UnitIsDeadOrGhost(u) return Mock.state.dead[u] and true or false end
function UnitIsFeignDeath() return false end
function IsMouseButtonDown() return false end
function GetCursorPosition() return 0, 0 end
function InCombatLockdown() return Mock.inCombat end
function IsInGuild() return Mock.state.inGuild end
function hooksecurefunc(tbl, name, fn)
  local orig = tbl[name]
  tbl[name] = function(...) orig(...) ; fn(...) end
end

C_CVar = {
  GetCVar = function(k) return Mock.cvars[k] end,
  SetCVar = function(k, v) Mock.cvars[k] = v; return true end,
}

RAID_CLASS_COLORS = {
  PALADIN = { colorStr = "fff58cba" }, PRIEST = { colorStr = "ffffffff" }, MAGE = { colorStr = "ff3fc7eb" },
}

GameTooltip = CreateFrame("Frame", "GameTooltip")
GameTooltip.lines = {}
GameTooltip.SetOwner = function(self) self.lines = {} end
GameTooltip.AddLine = function(self, txt) table.insert(self.lines, txt) end
GameTooltip.AddDoubleLine = function(self, l, r) table.insert(self.lines, l .. " | " .. r) end

Enum = {
  StartTimerType = { ChallengeModeCountdown = 1 },
  PlayerInteractionType = { ChallengeMode = 53 },
  SpellBookItemType = { Spell = "SPELL", Flyout = "FLYOUT" },
  SpellBookSpellBank = { Player = 0 },
}

Settings = {
  VarType = { Boolean = "boolean" },
  RegisterVerticalLayoutCategory = function(name)
    Mock.settings.category = name
    -- Shaped like the real category object: it carries an ID, and that ID (not
    -- the object) is what OpenToCategory accepts.
    local cat = { name = name, ID = 1 }
    cat.GetID = function(self) return self.ID end
    return cat, Settings.__layout
  end,
  -- Custom-frame sub-pages (the tabbed Settings and the Profiles page). We only
  -- record their names and frames so tests can assert both were registered.
  RegisterCanvasLayoutSubcategory = function(_, frame, name)
    Mock.settings.subcategories = Mock.settings.subcategories or {}
    table.insert(Mock.settings.subcategories, { name = name, frame = frame })
    return { name = name }, Settings.__layout
  end,
  RegisterAddOnSetting = function(_, id, key, _tbl, _type, label, _default)
    local s = { id = id, key = key, label = label }
    s.SetValueChangedCallback = function(self, fn) Mock.settings.callbacks[self.key] = fn end
    return s
  end,
  CreateCheckbox = function(_, setting, tooltip)
    table.insert(Mock.settings.checkboxes, { key = setting.key, label = setting.label, tooltip = tooltip })
  end,
  -- Headings and buttons are added to this layout as initializers; we only model
  -- which of the two each one is, and the order.
  __layout = {
    AddInitializer = function(_, init)
      if type(init) == "table" and init.header then
        table.insert(Mock.settings.headers, init.header)
      else
        table.insert(Mock.settings.buttons, init)
      end
    end,
  },
  RegisterAddOnCategory = function() end,
  -- Strict on purpose: the real client throws "bad argument #1 to
  -- 'OpenSettingsPanel'" when handed the category object instead of its id, and
  -- a permissive mock let exactly that bug ship.
  OpenToCategory = function(id)
    if type(id) ~= "number" and type(id) ~= "string" then
      error("bad argument #1 to 'OpenSettingsPanel' (expected a category id, got " .. type(id) .. ")")
    end
    Mock.settings.opened = true
  end,
}
function CreateSettingsListSectionHeaderInitializer(name) return { header = name } end
-- Real signature: name, label, onButtonClick, description, addSearchTags.
function CreateSettingsButtonInitializer(name, label, onClick, description)
  return { name = name, label = label, run = onClick, description = description }
end

SlashCmdList = {}

-- Blizzard_ChallengesUI: the Mythic+ Dungeons window the guild panel parks in.
ChallengesFrame = CreateFrame("Frame", "ChallengesFrame")
-- The "Season Best" row. Icon 1's dungeon has a teleport in the mock spellbook;
-- icon 2's does not, so the "no teleport, no button" path is covered too.
ChallengesFrame.DungeonIcons = {
  CreateFrame("Frame", nil, ChallengesFrame),
  CreateFrame("Frame", nil, ChallengesFrame),
}
ChallengesFrame.DungeonIcons[1].mapID = 375  -- Mists of Tirna Scithe
ChallengesFrame.DungeonIcons[2].mapID = 376  -- The Necrotic Wake
ScenarioObjectiveTracker = CreateFrame("Frame", "ScenarioObjectiveTracker")
ScenarioObjectiveTracker.__shown = true

-- ── Chat ──────────────────────────────────────────────────────────────────
-- Enough of the chat surface for the clickable-links filter: the filter
-- registry, the numbered chat windows, and the hyperlink scripts on them.

UISpecialFrames = {}
NUM_CHAT_WINDOWS = 3
Mock.chatFilters = {}

function ChatFrame_AddMessageEventFilter(event, fn)
  Mock.chatFilters[event] = Mock.chatFilters[event] or {}
  table.insert(Mock.chatFilters[event], fn)
end

-- Chat window contents, oldest first. Each line has an r/g/b (see chatColors)
-- the way GetMessageInfo returns one.
Mock.chatHistory = {
  "|cffffffffPlayer|r says: check |Hitem:12345::::::::70:::::|h[Healing Potion]|h",
  "|TInterface\\Icons\\foo:14|t Guildie: wipe on trash again",
  "Guild Message of the Day: secret",
  -- The named color form current clients use for item quality.
  "|cnIQ4:|Hitem:9999::::::::70:::::|h[Thunderfury]|h|r dropped",
}
-- Guild green, the color Blizzard's own chat window uses for that channel.
Mock.chatColors = {
  { 0.25, 0.75, 0.25 },
  { 0.25, 0.75, 0.25 },
  { 0.25, 0.75, 0.25 },
  { 0.25, 0.75, 0.25 },
}

-- Models which values are "secret", but not the throw-on-compare a real one
-- does, so secret-ordering bugs still have to be caught by reading the code.
Mock.secrets = { [Mock.chatHistory[3]] = true }
function issecretvalue(v) return Mock.secrets[v] == true end

for i = 1, NUM_CHAT_WINDOWS do
  local cf = CreateFrame("Frame", "ChatFrame" .. i)
  cf.__shown = true
  cf.GetNumMessages = function() return #Mock.chatHistory end
  cf.GetMessageInfo = function(_, idx)
    local c = Mock.chatColors[idx]
    if not c then return Mock.chatHistory[idx] end
    return Mock.chatHistory[idx], c[1], c[2], c[3]
  end
  -- Blizzard's own click handler, which every non-addon link goes through.
  -- It throws on a link type it does not know, exactly like SetItemRef does,
  -- so a hook that let our own links reach it would fail this test.
  cf:SetScript("OnHyperlinkClick", function(_, link)
    Mock.blizzLinks[#Mock.blizzLinks + 1] = link
    if not tostring(link):match("^item:") then
      error("SetItemRef: unknown link type " .. tostring(link))
    end
  end)
end
Mock.blizzLinks = {}

-- Runs one chat line through the registered filters, the way the client does,
-- and hands back the message as it would be drawn.
function Mock.chat(event, msg)
  for _, fn in ipairs(Mock.chatFilters[event] or {}) do
    local suppress, rewritten = fn(_G.ChatFrame1, event, msg, "Sender")
    if suppress then return nil end
    if rewritten ~= nil then msg = rewritten end
  end
  return msg
end

-- Clicks the first hyperlink in a rendered chat line, on the given window.
function Mock.clickLink(msg, frameIndex)
  local frame = _G["ChatFrame" .. (frameIndex or 1)]
  local link = msg:match("|H(.-)|h")
  frame.__scripts.OnHyperlinkClick(frame, link, msg, "LeftButton")
  return link
end
