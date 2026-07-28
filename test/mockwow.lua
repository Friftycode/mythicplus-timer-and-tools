-- A small mock of the WoW client API: enough for the addon to load and draw.
-- Unimplemented frame methods degrade to no-op stubs, so tests fail on behavior.

Mock = {
  now = 1000,          -- GetTime()
  timers = {},         -- pending C_Timer.After callbacks
  frames = {},         -- every frame ever created
  prints = {},         -- captured print() output
  cvars = { nameplateShowEnemies = "0" },
  settings = { category = nil },
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
  inInstance = true, challengeActive = false, deathCount = 0, dead = {},
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
-- The player's own keystone, for the party-key share dropdown.
Mock.ownedChallengeMapID = 375
Mock.ownedKeyLevel = 12
C_MythicPlus = {
  GetOwnedKeystoneMapID = function() return Mock.ownedKeyMapID end,
  GetOwnedKeystoneChallengeMapID = function() return Mock.ownedChallengeMapID end,
  GetOwnedKeystoneLevel = function() return Mock.ownedKeyLevel end,
}

ChallengesKeystoneFrame = CreateFrame("Frame", "ChallengesKeystoneFrame")

-- ── Group Finder ──────────────────────────────────────────────────────────
-- One search result keyed by id, shaped like the real GetSearchResultInfo.
Mock.searchResults = {
  [77] = {
    name = "+18 AA  need dps  link io",
    leaderName = "Keypusher",
    -- The listing's copy of the leader's score, the one rating the client hands
    -- over before anybody is close enough to inspect.
    leaderOverallDungeonScore = 3105,
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
    return "Mists", "party", Mock.state.difficultyID or 8, "Mythic Keystone", 5, 0, false, Mock.instanceID
  end
  return "Elwynn", "none", 0, "", 0, 0, false, 0
end

-- The buff reminder gates delivery on being in a dungeon with the key under way.
function IsInInstance()
  if Mock.state.inInstance then return true, "party" end
  return false, "none"
end
C_ChallengeMode.IsChallengeModeActive = function() return Mock.state.challengeActive and true or false end

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

-- Which character is "logged in", for the per-character profile tests. charKey()
-- reads UnitFullName, so switching this and firing PLAYER_LOGIN stands in for
-- logging into a different character on the same (account-wide) SavedVariables.
Mock.state.char = { name = "Mainchar", realm = "Ravencrest" }
function Mock.setChar(name, realm) Mock.state.char = { name = name, realm = realm } end
function UnitFullName(unit)
  if unit ~= "player" then return nil end
  local c = Mock.state.char or {}
  return c.name, c.realm
end
function UnitIsDeadOrGhost(u) return Mock.state.dead[u] and true or false end
function UnitIsFeignDeath() return false end
function IsMouseButtonDown() return false end
function GetCursorPosition() return 0, 0 end
function InCombatLockdown() return Mock.inCombat end
function IsInGuild() return Mock.state.inGuild end
-- Supports both real forms: hooksecurefunc(name, fn) hooks a global, and
-- hooksecurefunc(table, name, fn) hooks a table field.
function hooksecurefunc(a, b, c)
  if type(a) == "string" then
    local name, fn = a, b
    local orig = _G[name]
    _G[name] = function(...) if orig then orig(...) end fn(...) end
  else
    local tbl, name, fn = a, b, c
    local orig = tbl[name]
    tbl[name] = function(...) orig(...) ; fn(...) end
  end
end

C_CVar = {
  GetCVar = function(k) return Mock.cvars[k] end,
  SetCVar = function(k, v) Mock.cvars[k] = v; return true end,
}

RAID_CLASS_COLORS = {
  PALADIN = { colorStr = "fff58cba" }, PRIEST = { colorStr = "ffffffff" }, MAGE = { colorStr = "ff3fc7eb" },
}

-- The mock character knows Bloodlust; a test can clear this to check the alert
-- is gated on actually having a lust ability.
Mock.playerSpells = { [2825] = true }
function IsPlayerSpell(id) return Mock.playerSpells[id] == true end

-- ── Group and auras (buff reminder) ────────────────────────────────────────
-- Off by default so the buff scanner stays dormant through the timer tests; the
-- buff-reminder section turns it on.
Mock.state.inGroup = false
Mock.state.inRaidGroup = false
Mock.groupMembers = 3
function IsInGroup() return Mock.state.inGroup and true or false end
function IsInRaid() return Mock.state.inRaidGroup and true or false end
function GetNumGroupMembers() return Mock.groupMembers or 0 end

-- Buffs a unit currently has, as a list of spell ids. GetAuraDataByIndex walks
-- the list; a unit absent from the table simply has no buffs.
Mock.auras = {}
C_UnitAuras = {
  GetAuraDataByIndex = function(unit, index)
    local id = Mock.auras[unit] and Mock.auras[unit][index]
    if not id then return nil end
    return { spellId = id, name = "Buff " .. id }
  end,
}

-- Encounter Journal + map, for the notepad's per-boss note list.
Mock.state.uiMap = 2000
Mock.state.ejInstance = 500
Mock.state.inEncounter = false
Mock.ejEncounters = {
  { name = "First Boss", deid = 111 },
  { name = "Last Boss", deid = 222 },
}
C_Map = C_Map or {}
C_Map.GetBestMapForUnit = function(_) return Mock.state.uiMap end
function EJ_GetInstanceForMap(_) return Mock.state.ejInstance end
function EJ_SelectInstance(id) Mock.state.ejSelected = id end
function EJ_GetEncounterInfoByIndex(i, instID)
  local e = (Mock.ejBossesByInstance and Mock.ejBossesByInstance[instID]) or Mock.ejEncounters
  local b = e[i]
  if not b then return nil end
  return b.name, "desc", 1000 + i, 0, "link", instID, b.deid, instID
end
function IsEncounterInProgress() return Mock.state.inEncounter and true or false end

-- The Encounter Journal dungeon list, for the prepare-ahead note picker.
Mock.ejTiers = 3
Mock.ejDungeons = {
  { instID = 500, name = "Test Dungeon" },
  { instID = 501, name = "Other Dungeon" },
}
Mock.ejBossesByInstance = {
  [500] = Mock.ejEncounters,
  [501] = { { name = "Lone Boss", deid = 333 } },
}
function EJ_GetNumTiers() return Mock.ejTiers end
function EJ_SelectTier(t) Mock.state.ejTier = t end
function EJ_GetInstanceByIndex(i, isRaid)
  if isRaid then return nil end
  local d = Mock.ejDungeons[i]
  if not d then return nil end
  return d.instID, d.name
end
-- Resolves a name for any instance id (even one not in the current tiers), so a
-- saved note for a rotated-out dungeon can still be labelled.
Mock.ejInstanceNames = { [500] = "Test Dungeon", [501] = "Other Dungeon", [900] = "Retired Dungeon" }
function EJ_GetInstanceInfo() return Mock.ejInstanceNames[Mock.state.ejSelected] end

-- Nameplates, for the note window's "follow the fight" proximity check.
Mock.namePlates = {}
C_NamePlate = { GetNamePlates = function() return Mock.namePlates end }

-- Party-chat announce + addon-message coordination for the buff reminder.
Mock.state.partyLFG = false
function IsPartyLFG() return Mock.state.partyLFG and true or false end
Mock.sentChat = {}
function SendChatMessage(msg, channel) Mock.sentChat[#Mock.sentChat + 1] = { msg = msg, channel = channel } end
Mock.sentAddon = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, channel)
    Mock.sentAddon[#Mock.sentAddon + 1] = { prefix = prefix, msg = msg, channel = channel }
    return true
  end,
}

-- ── Merchant (auto repair / sell junk) ─────────────────────────────────────
Mock.merchant = {
  canRepair = true, repairCost = 5000, canGuildRepair = false,
  guildWithdraw = 0, money = 1000000, repaired = nil,
}
function CanMerchantRepair() return Mock.merchant.canRepair end
function GetRepairAllCost() return Mock.merchant.repairCost, Mock.merchant.repairCost > 0 end
function RepairAllItems(guild) Mock.merchant.repaired = guild and "guild" or "self" end
function CanGuildBankRepair() return Mock.merchant.canGuildRepair end
function GetGuildBankWithdrawMoney() return Mock.merchant.guildWithdraw end
function GetMoney() return Mock.merchant.money end
function GetCoinTextureString(c) return tostring(c) .. "c" end
-- Only the 11th return (sell price) is read by the junk seller.
function GetItemInfo(_) return nil, nil, 0, 0, 0, 0, 0, 0, 0, 0, 25 end

local QUALITY_HEX = {
  ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2,
  ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5,
}
local function qualityOfLink(link)
  local hex = type(link) == "string" and link:match("|cff(%x%x%x%x%x%x)")
  return (hex and QUALITY_HEX[hex]) or 1
end
Mock.sold = {}
C_Container.GetContainerItemInfo = function(bag, slot)
  local link = (Mock.bags[bag] or {})[slot]
  if not link then return nil end
  return { hyperlink = link, quality = qualityOfLink(link), stackCount = 1, hasNoValue = false }
end
C_Container.UseContainerItem = function(bag, slot)
  local b = Mock.bags[bag]
  if b and b[slot] then Mock.sold[#Mock.sold + 1] = b[slot]; b[slot] = nil end
end

-- ── Quests / gossip (auto accept and turn in) ──────────────────────────────
Mock.gossip = {
  active = {}, available = {}, options = {},
  selectedActive = nil, selectedAvail = nil, selectedOption = nil,
}
C_GossipInfo = {
  GetActiveQuests = function() return Mock.gossip.active end,
  GetAvailableQuests = function() return Mock.gossip.available end,
  GetOptions = function() return Mock.gossip.options end,
  SelectActiveQuest = function(id) Mock.gossip.selectedActive = id end,
  SelectAvailableQuest = function(id) Mock.gossip.selectedAvail = id end,
  SelectOption = function(id) Mock.gossip.selectedOption = id end,
}
Mock.quest = {
  accepted = false, completed = false, rewardTaken = false, rewardIndex = nil,
  numChoices = 0, completable = true, numActive = 0, numAvail = 0,
  selActive = nil, selAvail = nil,
}
function AcceptQuest() Mock.quest.accepted = true end
function CompleteQuest() Mock.quest.completed = true end
function GetQuestReward(i) Mock.quest.rewardTaken = true; Mock.quest.rewardIndex = i end
function GetNumQuestChoices() return Mock.quest.numChoices end
function IsQuestCompletable() return Mock.quest.completable end
function GetNumActiveQuests() return Mock.quest.numActive end
function GetNumAvailableQuests() return Mock.quest.numAvail end
function SelectActiveQuest(i) Mock.quest.selActive = i end
function SelectAvailableQuest(i) Mock.quest.selAvail = i end

-- ── Group finder create panel (force Mythic) ───────────────────────────────
Mock.activities[2000] = { fullName = "Test Dungeon (Heroic)", isMythicPlusActivity = false, groupFinderActivityGroupID = 100 }
Mock.activities[2001] = { fullName = "Test Dungeon (Mythic)", isMythicPlusActivity = false, groupFinderActivityGroupID = 100 }
Mock.activities[2002] = { fullName = "Test Dungeon (Mythic Keystone)", isMythicPlusActivity = true, groupFinderActivityGroupID = 100 }
-- A second dungeon, named the way GetMapUIInfo names challenge map 375, so the
-- party-key share can map a shared key back to its create-panel activity.
Mock.activities[2003] = { fullName = "Mists of Tirna Scithe (Mythic Keystone)", isMythicPlusActivity = true, groupFinderActivityGroupID = 375 }
Mock.lfgGroupActivities = { [42] = { 2000, 2001, 2002, 2003 } }
C_LFGList.GetAvailableActivities = function(_, group)
  return Mock.lfgGroupActivities[group] or Mock.lfgGroupActivities[42]
end
Mock.lfgSelected = nil
function LFGListEntryCreation_Select(self, filters, cat, group, activity)
  Mock.lfgSelected = { cat = cat, group = group, activity = activity }
end
-- The create panel's own frame, with a playstyle dropdown that reports itself
-- shown (Mythic+ offers a playstyle). The addon sets generalPlaystyle on it via
-- LFGListEntryCreation_OnPlayStyleSelectedInternal, mirroring the real client.
-- (Enum.LFGEntryGeneralPlaystyle is defined with the other enums below.)
LFGListEntryCreation = {
  generalPlaystyle = nil,
  selectedCategory = 2,
  selectedFilters = 0,
  -- The title box, whose text the party-key share fills with "+level".
  Name = {
    text = "",
    GetText = function(self) return self.text end,
    SetText = function(self, t) self.text = t end,
  },
  PlayStyleDropdown = {
    shown = true,
    IsShown = function(self) return self.shown end,
    GenerateMenu = function() end,
  },
}
function LFGListEntryCreation_OnPlayStyleSelectedInternal(self, v) self.generalPlaystyle = v end

-- Item-quality colors, so the score coloring runs its real path. Approximate
-- Blizzard values, enough to tell the tiers apart.
local QUALITY_COLOR = {
  [2] = { 0.12, 1.00, 0.00 }, [3] = { 0.00, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 }, [5] = { 1.00, 0.50, 0.00 }, [6] = { 0.90, 0.80, 0.50 },
}
function GetItemQualityColor(q)
  local c = QUALITY_COLOR[q] or { 1, 1, 1 }
  return c[1], c[2], c[3]
end

-- Stand-in for an installed Raider.IO: its public API hands back a score's exact
-- color. Deterministic here so the popup's match-Raider.IO path can be checked;
-- clearing _G.RaiderIO exercises the item-quality fallback instead.
RaiderIO = {
  GetScoreColor = function(score)
    if type(score) ~= "number" then return end
    if score >= 3000 then return 1.00, 0.50, 0.00 end
    if score >= 2401 then return 0.20, 0.60, 0.80 end
    return 0.60, 0.60, 0.60
  end,
}

-- Blizzard's "You have joined a group" acknowledgement. A hidden AcceptButton is
-- its post-accept state (the one our popup replaces); showing the AcceptButton
-- stands in for a live Accept/Decline invite that must never be hidden.
LFGListInviteDialog = CreateFrame("Frame", "LFGListInviteDialog")
LFGListInviteDialog.AcceptButton = CreateFrame("Button", nil, LFGListInviteDialog)
LFGListInviteDialog.AcceptButton:Hide()
LFGListInviteDialog:Hide()

GameTooltip = CreateFrame("Frame", "GameTooltip")
GameTooltip.lines = {}
GameTooltip.SetOwner = function(self) self.lines = {} end
GameTooltip.AddLine = function(self, txt) table.insert(self.lines, txt) end
GameTooltip.AddDoubleLine = function(self, l, r) table.insert(self.lines, l .. " | " .. r) end

-- The minimap, and the ring the addon's own button parks on.
Minimap = CreateFrame("Frame", "Minimap")
Minimap:SetSize(140, 140)

-- The context-menu system the minimap button builds its dropdown with. The
-- generator is handed a root that records what it was asked to draw, so a test
-- can read the menu's items and invoke them.
MenuUtil = {
  CreateContextMenu = function(owner, generator)
    local root = { title = nil, items = {} }
    function root:CreateTitle(t) self.title = t end
    function root:CreateButton(t, fn) self.items[#self.items + 1] = { text = t, click = fn }; return {} end
    function root:CreateCheckbox(t, isChecked, toggle)
      self.items[#self.items + 1] = { text = t, isChecked = isChecked, toggle = toggle }
      return {}
    end
    function root:CreateDivider() self.items[#self.items + 1] = { divider = true } end
    generator(owner, root)
    Mock.menu = root
  end,
}

Enum = {
  StartTimerType = { ChallengeModeCountdown = 1 },
  PlayerInteractionType = { ChallengeMode = 53 },
  SpellBookItemType = { Spell = "SPELL", Flyout = "FLYOUT" },
  SpellBookSpellBank = { Player = 0 },
  LFGEntryGeneralPlaystyle = { None = 0, Learning = 1, FunRelaxed = 2, FunSerious = 3, Expert = 4 },
}

-- Version is date-shaped, the way the release job stamps it.
C_AddOns = {
  GetAddOnMetadata = function(_, field)
    local meta = { Version = "2026.7.24", Title = "Mythic+ Timer and Tools" }
    return meta[field]
  end,
  LoadAddOn = function() return true end,
}

Settings = {
  VarType = { Boolean = "boolean" },
  -- The addon's name in the AddOns list, whose page is the tabbed settings frame.
  RegisterCanvasLayoutCategory = function(frame, name)
    Mock.settings.category = name
    Mock.settings.canvas = { name = name, frame = frame }
    -- Shaped like the real category object: it carries an ID, and that ID (not
    -- the object) is what OpenToCategory accepts.
    local cat = { name = name, ID = 1 }
    cat.GetID = function(self) return self.ID end
    return cat
  end,
  RegisterCanvasLayoutSubcategory = function(_, frame, name)
    Mock.settings.subcategories = Mock.settings.subcategories or {}
    table.insert(Mock.settings.subcategories, { name = name, frame = frame })
    return { name = name }
  end,
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

local unpack = unpack or table.unpack

-- A player-typed line's full argument list, in the client's order: message,
-- sender, language, channel, target, flags, ... , line id, guid, and the
-- trailing booleans.
local function chatArgs(msg)
  return { msg, "Sender", "Common", "", "Target", "", 0, 0, "", 0, 11,
    "Player-1234-ABCDEF", 0, false, false, false, false }
end

-- Runs one chat line through the registered filters the way the client really
-- does: a filter is handed the whole argument list, and arg1..arg14 are then
-- reassigned from what it returns. A filter that returns only the values it
-- cares about therefore nils out the rest here too, so that mistake fails a
-- test instead of only erroring inside Blizzard's own message handler.
function Mock.chat(event, msg)
  local a = chatArgs(msg)
  for _, fn in ipairs(Mock.chatFilters[event] or {}) do
    local r = { fn(_G.ChatFrame1, event, unpack(a, 1, 17)) }
    if r[1] then return nil end
    if r[2] ~= nil then
      for i = 1, 14 do a[i] = r[i + 1] end
    end
  end
  Mock.lastChatArgs = a
  return a[1]
end

-- Clicks the first hyperlink in a rendered chat line, on the given window.
function Mock.clickLink(msg, frameIndex)
  local frame = _G["ChatFrame" .. (frameIndex or 1)]
  local link = msg:match("|H(.-)|h")
  frame.__scripts.OnHyperlinkClick(frame, link, msg, "LeftButton")
  return link
end
