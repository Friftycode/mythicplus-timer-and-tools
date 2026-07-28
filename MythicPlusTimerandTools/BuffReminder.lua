local _, ns = ...

local GOLD, GREY, WHITE, RED, ENDC, MP_PAD = ns.GOLD, ns.GREY, ns.WHITE, ns.RED, ns.ENDC, ns.PAD
local cfg, isSecret = ns.cfg, ns.isSecret

-- ── Missing party-buff reminder ──────────────────────────────────────────
-- Flags a class party buff that has been missing from a group member for a
-- while, but only for classes that are actually in the group (no point asking
-- for Skyfury with no Shaman around). Reads auras only; nothing is cast or sent.

local BR_TICK = 2  -- seconds between scans

-- One row per trackable buff: the class that grants it, its spell id, and the
-- config key that turns tracking of it on or off. Spell ids verified against
-- Wowhead for current retail.
local BR_BUFFS = {
  { class = "MAGE",    spellId = 1459,   name = "Arcane Intellect",       key = "buffmage" },
  { class = "PRIEST",  spellId = 21562,  name = "Power Word: Fortitude",  key = "buffpriest" },
  { class = "WARRIOR", spellId = 6673,   name = "Battle Shout",           key = "buffwarrior" },
  { class = "DRUID",   spellId = 1126,   name = "Mark of the Wild",       key = "buffdruid" },
  { class = "SHAMAN",  spellId = 462854, name = "Skyfury",                key = "buffshaman" },
  { class = "EVOKER",  spellId = 364342, name = "Blessing of the Bronze", key = "buffevoker" },
}

local function brNum(key, minv, maxv, default)
  local v = tonumber(cfg(key)) or default
  return math.max(minv, math.min(maxv, math.floor(v + 0.5)))
end

-- The member units of the current group: the raid frames in a raid, else the
-- player plus whichever party slots are filled.
local function brGroupUnits()
  local units = {}
  if type(IsInRaid) == "function" and IsInRaid() then
    local n = (type(GetNumGroupMembers) == "function" and GetNumGroupMembers()) or 0
    for i = 1, n do units[#units + 1] = "raid" .. i end
  else
    units[#units + 1] = "player"
    for i = 1, 4 do
      local u = "party" .. i
      if UnitExists(u) then units[#units + 1] = u end
    end
  end
  return units
end

local function brPresentClasses(units)
  local present = {}
  for _, u in ipairs(units) do
    local ok, cl = pcall(UnitClassBase, u)
    if ok and type(cl) == "string" then present[cl] = true end
  end
  return present
end

local function brInPartyDungeon()
  if type(IsInInstance) ~= "function" then return false end
  local ok, inside, itype = pcall(IsInInstance)
  return ok and inside and itype == "party" and true or false
end

local function brChallengeActive()
  if not (C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function") then return false end
  local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
  return ok and active and true or false
end

-- Only remind inside a dungeon once the key is under way. Never out in the world,
-- in a raid, or before the pull: the reminder is for a running Mythic+, so nothing
-- is posted while the group is buffing at the start or just grouped up questing.
local function brDeliveryAllowed()
  return brInPartyDungeon() and brChallengeActive()
end

-- Whether a unit currently has the given buff. On any client that can't answer
-- (no aura API, an error, a secret aura) we assume it's present, so an inability
-- to read is never reported as a missing buff.
local function brUnitHasBuff(unit, spellId)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return true end
  for i = 1, 60 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
    if not ok then return true end
    if not aura then break end
    if not isSecret(aura) and aura.spellId == spellId then return true end
  end
  return false
end

-- ── Popup ────────────────────────────────────────────────────────────────

local BR_W, BR_SECONDS = 300, 6
local brFrame, brHideAt
local brPreviewing = false

local function brRestorePosition(f)
  ns.restorePosition(f, "buffpoint", "CENTER", 0, 150)
end

local function ensureBrFrame()
  if brFrame then return brFrame end
  local f = CreateFrame("Frame", "MythicPlusTimerBuffFrame", UIParent, "BackdropTemplate")
  f:SetSize(BR_W, 80)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.savePosition(self, "buffpoint")
  end)
  f:SetClampedToScreen(true)
  brRestorePosition(f)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
    f:SetBackdropBorderColor(0.88, 0.65, 0.31, 0.9)
  end

  f.headline = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.headline:SetPoint("TOP", f, "TOP", 0, -MP_PAD)
  f.headline:SetText(GOLD .. "Missing buffs" .. ENDC)

  f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.body:SetPoint("TOP", f, "TOP", 0, -MP_PAD - 24)
  f.body:SetWidth(BR_W - MP_PAD * 2)
  f.body:SetJustifyH("CENTER")

  f:SetScript("OnEnter", function() brHideAt = nil end)
  f:SetScript("OnLeave", function() brHideAt = GetTime() + 2 end)
  f:SetScript("OnUpdate", function(self)
    if brPreviewing then return end
    if brHideAt and GetTime() >= brHideAt then
      brHideAt = nil
      self:Hide()
    end
  end)

  f:Hide()
  brFrame = f
  return f
end

local function brShowPopup(lines)
  local f = ensureBrFrame()
  f.body:SetText(table.concat(lines, "\n"))
  f:SetHeight(MP_PAD * 2 + 24 + #lines * ns.LINE + 6)
  brHideAt = GetTime() + BR_SECONDS
  f:Show()
end

-- ── Delivery ───────────────────────────────────────────────────────────────

-- Groups the flagged (member, buff) pairs by member. Returns a plain-text line
-- for party chat (readable by people without the addon) and colored popup lines.
local function brBuild(pending)
  local order, byName = {}, {}
  for _, p in ipairs(pending) do
    local row = byName[p.name]
    if not row then
      row = { name = p.name, class = p.class, buffs = {} }
      byName[p.name] = row
      order[#order + 1] = p.name
    end
    row.buffs[#row.buffs + 1] = p.buff
  end
  local chatParts, popupLines = {}, {}
  for _, name in ipairs(order) do
    local row = byName[name]
    local buffs = table.concat(row.buffs, ", ")
    chatParts[#chatParts + 1] = row.name .. ": " .. buffs
    popupLines[#popupLines + 1] = WHITE .. row.name .. ENDC
      .. GREY .. ": " .. ENDC .. RED .. buffs .. ENDC
  end
  local chatMsg = "Missing buffs -- " .. table.concat(chatParts, "; ")
  if #chatMsg > 240 then chatMsg = chatMsg:sub(1, 240) end
  return chatMsg, popupLines
end

-- ── Cross-addon coordination ──────────────────────────────────────────────
-- Several party members can run this addon at once. To keep them from all
-- announcing the same missing buff, the chat write is elected: whoever's name
-- sorts first among those trying at the same moment wins, and everyone shares
-- one cooldown broadcast over an addon-message channel. Only the chat delivery
-- is coordinated; the popup is local to each client.

local BR_PREFIX = "MPTTBuff"
local BR_CLAIM_WINDOW = 0.7  -- seconds to hear rivals before sending
local sharedCooldownUntil = 0
local brClaiming, brClaimBeaten = false, false
local brClaimMsg, brClaimCooldown
local brMyNameCache

local function brMyName()
  if brMyNameCache then return brMyNameCache end
  local ok, n = pcall(UnitName, "player")
  brMyNameCache = (ok and type(n) == "string" and n) or "?"
  return brMyNameCache
end

-- INSTANCE_CHAT for a group formed by the finder, else PARTY. Same choice is
-- used for the human message and the hidden addon message.
local function brChannel()
  if type(IsPartyLFG) == "function" and IsPartyLFG() then return "INSTANCE_CHAT" end
  return "PARTY"
end

local function brSendAddon(msg)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, BR_PREFIX, msg, brChannel())
  end
end

local function brResolveClaim()
  brClaiming = false
  if brClaimBeaten then return end  -- a party member with an earlier name is sending
  if type(SendChatMessage) == "function" then
    pcall(SendChatMessage, brClaimMsg, brChannel())
  end
  sharedCooldownUntil = GetTime() + (brClaimCooldown or 15)
  brSendAddon("SENT:" .. math.floor(brClaimCooldown or 15))
end

local function brBeginClaim(msg, cooldownSecs)
  brClaiming, brClaimBeaten = true, false
  brClaimMsg, brClaimCooldown = msg, cooldownSecs
  brSendAddon("CLAIM:" .. brMyName())
  C_Timer.After(BR_CLAIM_WINDOW, brResolveClaim)
end

local brComm = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, BR_PREFIX)
end
brComm:RegisterEvent("CHAT_MSG_ADDON")
brComm:SetScript("OnEvent", function(_, _, prefix, message)
  if prefix ~= BR_PREFIX then return end
  local kind, rest = tostring(message):match("^(%u+):(.*)$")
  if kind == "SENT" then
    sharedCooldownUntil = GetTime() + (tonumber(rest) or 15)
    if brClaiming then brClaimBeaten = true end  -- someone already announced
  elseif kind == "CLAIM" and brClaiming and rest ~= "" and rest < brMyName() then
    brClaimBeaten = true  -- their name sorts first: let them send
  end
end)

-- ── Scan ─────────────────────────────────────────────────────────────────

local missingSince = {}  -- "guid:spellId" -> GetTime() the buff went missing
local alerted = {}       -- "guid:spellId" -> already flagged this missing spell
local localPopupUntil = 0

local function brReset()
  missingSince, alerted = {}, {}
end

local function brScan()
  if not cfg("buffreminder") then return end
  if not (type(IsInGroup) == "function" and IsInGroup()) then
    if next(missingSince) or next(alerted) then brReset() end
    return
  end

  local units = brGroupUnits()
  local present = brPresentClasses(units)
  local now = GetTime()
  local threshold = brNum("buffthreshold", 15, 60, 20)
  local live, pending = {}, {}

  for _, b in ipairs(BR_BUFFS) do
    if present[b.class] and cfg(b.key) then
      for _, u in ipairs(units) do
        local okG, guid = pcall(UnitGUID, u)
        if okG and type(guid) == "string" and not isSecret(guid) then
          local key = guid .. ":" .. b.spellId
          if brUnitHasBuff(u, b.spellId) then
            missingSince[key], alerted[key] = nil, nil
          else
            live[key] = true
            missingSince[key] = missingSince[key] or now
            if now - missingSince[key] >= threshold and not alerted[key] then
              local okN, nm = pcall(UnitName, u)
              local name = (okN and type(nm) == "string" and not isSecret(nm)) and nm or "?"
              local okC, cl = pcall(UnitClassBase, u)
              pending[#pending + 1] = {
                key = key, name = name,
                class = (okC and type(cl) == "string") and cl or b.class,
                buff = b.name,
              }
            end
          end
        end
      end
    end
  end

  -- Forget state for members who left or whose buff is no longer tracked.
  for k in pairs(missingSince) do
    if not live[k] then missingSince[k], alerted[k] = nil, nil end
  end

  if #pending == 0 then return end

  -- Hold everything until a Mythic+ run has started. missingSince is left intact
  -- and nothing is marked alerted, so the moment the key goes live any buff still
  -- missing past the threshold is announced on the next scan.
  if not brDeliveryAllowed() then return end

  local delivery = cfg("buffdelivery")
  if delivery ~= "chat" and delivery ~= "popup" and delivery ~= "both" then delivery = "chat" end
  -- With the limit on, the shared cooldown paces the chat write; off, a short
  -- floor still keeps the election from firing many times a second.
  local cooldownSecs = cfg("buffcooldown") and (brNum("buffcooldownmins", 1, 30, 5) * 60) or 5

  local chatMsg, popupLines = brBuild(pending)
  if (delivery == "chat" or delivery == "both")
    and now >= sharedCooldownUntil and not brClaiming then
    brBeginClaim(chatMsg, cooldownSecs)
  end
  if (delivery == "popup" or delivery == "both") and now >= localPopupUntil then
    localPopupUntil = now + cooldownSecs
    pcall(brShowPopup, popupLines)
  end

  -- Each missing spell is announced once until the buff comes back.
  for _, p in ipairs(pending) do alerted[p.key] = true end
end

local brSince = 0
local brTicker = CreateFrame("Frame")
brTicker:SetScript("OnUpdate", function(_, elapsed)
  brSince = brSince + elapsed
  if brSince < BR_TICK then return end
  brSince = 0
  pcall(brScan)
end)

-- Leaving or joining a group resets the timers so an old member's missing buff
-- can't carry over.
local brEvents = CreateFrame("Frame")
brEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
brEvents:SetScript("OnEvent", function() brReset() end)

ns.onOptionChanged("buffreminder", function()
  brReset()
  if not cfg("buffreminder") and brFrame then pcall(brFrame.Hide, brFrame) end
end)

ns.previewFrame("buff reminder", function()
  brPreviewing = true
  brShowPopup({ WHITE .. "Healer" .. ENDC .. GREY .. ": " .. ENDC .. RED .. "Arcane Intellect" .. ENDC })
  brHideAt = nil
end, function()
  brPreviewing = false
  brHideAt = nil
  if brFrame then brFrame:Hide() end
end, function() return brFrame end, { group = "Alerts", section = "Buff reminder" })
