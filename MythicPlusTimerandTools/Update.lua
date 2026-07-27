local _, ns = ...

-- ── Update reminder ───────────────────────────────────────────────────────
-- A WoW addon has no network access, so it cannot ask CurseForge or GitHub
-- whether a newer release exists. Two offline signals stand in for that:
--   * Age: releases are date-stamped versions ("2026.7.27"), so a version more
--     than 45 days old is very likely behind a newer one.
--   * A group member: members broadcast their version to the party. Seeing a
--     newer one is proof a newer release exists, so it is remembered account-wide
--     and keeps reminding, across sessions, until this client catches up.
-- The reminder surfaces on the settings window and the minimap menu; nothing
-- here sends anything outside the group or acts on its own.

local UPDATE_AGE_DAYS = 45
local VER_PREFIX = "MPTTVer"

-- Account-wide, kept out of the profile config so it is shared by every
-- character and survives a profile switch.
local function state()
  if type(MythicPlusTimerState) ~= "table" then MythicPlusTimerState = {} end
  return MythicPlusTimerState
end

-- "YYYY.M.D" -> a single comparable number (and its parts), or nil for anything
-- not in that shape, so a hand-typed or hostile version string is simply ignored.
local function parseVersion(v)
  if type(v) ~= "string" then return nil end
  local y, m, d = v:match("^(%d+)%.(%d+)%.(%d+)")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not (y and m and d) or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
  return y * 10000 + m * 100 + d, y, m, d
end

local function localVersion()
  local get = C_AddOns and C_AddOns.GetAddOnMetadata
  if type(get) ~= "function" then return nil end
  local ok, v = pcall(get, "MythicPlusTimerandTools", "Version")
  if ok and type(v) == "string" and v ~= "" then return v end
  return nil
end
ns.localVersion = localVersion

-- Whole days between the version's date and `nowEpoch`, or nil when either the
-- version or the client's time functions can't be read.
local function versionAgeDays(v, nowEpoch)
  local _, y, m, d = parseVersion(v)
  if not (y and nowEpoch and type(time) == "function") then return nil end
  local ok, epoch = pcall(time, { year = y, month = m, day = d, hour = 12 })
  if not (ok and type(epoch) == "number") then return nil end
  return math.floor((nowEpoch - epoch) / 86400)
end
ns.versionAgeDays = versionAgeDays

local UPDATE_MESSAGE =
  "Update available: Please update addon to ensure you are using the latest version."

-- The pure decision, split out so it can be tested without the clock or the
-- client: a peer running a newer version wins (it is proof), otherwise age. The
-- shown message is the same either way; `reason` is kept for callers/tests.
function ns.updateStatusFor(localVer, newerSeen, nowEpoch)
  local lk = parseVersion(localVer)
  local nk = parseVersion(newerSeen)
  if lk and nk and nk > lk then
    return { reason = "peer", version = newerSeen, message = UPDATE_MESSAGE }
  end
  if lk then
    local age = versionAgeDays(localVer, nowEpoch)
    if age and age >= UPDATE_AGE_DAYS then
      return { reason = "age", days = age, message = UPDATE_MESSAGE }
    end
  end
  return nil
end

-- The live status the UI reads. nil when up to date.
function ns.updateStatus()
  local now = (type(time) == "function") and time() or nil
  return ns.updateStatusFor(localVersion(), state().newerVersion, now)
end

-- Records a peer's version if it is newer than ours and newer than any we have
-- already noted, so the highest seen sticks.
local function noteNewer(v)
  local pk = parseVersion(v)
  local lk = parseVersion(localVersion())
  if not (pk and lk) or pk <= lk then return end
  local s = state()
  local have = parseVersion(s.newerVersion)
  if not have or pk > have then s.newerVersion = v end
end
ns.noteNewerVersion = noteNewer

-- Once this client has caught up (an update landed), the remembered newer
-- version is no longer newer, so drop it and the reminder goes away on its own.
local function reconcile()
  local s = state()
  local nk, ny = parseVersion(s.newerVersion)
  local lk = parseVersion(localVersion())
  if nk and lk and lk >= nk then s.newerVersion = nil end
  -- Drop an implausible far-future value (e.g. a leftover test sentinel), so it
  -- can never wedge the reminder on.
  if ny and ny > 2100 then s.newerVersion = nil end
end

-- ── Version broadcast ─────────────────────────────────────────────────────

local function inGroup()
  return type(IsInGroup) == "function" and IsInGroup() and true or false
end

local function channel()
  if type(IsPartyLFG) == "function" and IsPartyLFG() then return "INSTANCE_CHAT" end
  return "PARTY"
end

local function broadcast()
  if not inGroup() then return end
  local v = localVersion()
  if not v or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  pcall(C_ChatInfo.SendAddonMessage, VER_PREFIX, "V:" .. v, channel())
end

local pending = false
local function broadcastSoon()
  if pending then return end
  pending = true
  C_Timer.After(2, function() pending = false; pcall(broadcast) end)
end

local comm = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, VER_PREFIX)
end
comm:RegisterEvent("PLAYER_LOGIN")
comm:RegisterEvent("GROUP_ROSTER_UPDATE")
comm:RegisterEvent("CHAT_MSG_ADDON")
comm:SetScript("OnEvent", function(_, event, prefix, message)
  if event == "CHAT_MSG_ADDON" then
    if prefix ~= VER_PREFIX or type(message) ~= "string" then return end
    local v = message:match("^V:(.+)$")
    if v then noteNewer(v) end
    return
  end
  if event == "PLAYER_LOGIN" then pcall(reconcile) end
  broadcastSoon()
end)
