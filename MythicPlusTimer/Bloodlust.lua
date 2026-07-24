local _, ns = ...

local GOLD, GREY, WHITE, ENDC, MP_PAD = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC, ns.PAD
local cfg, isSecret = ns.cfg, ns.isSecret

-- ── Bloodlust called in chat ─────────────────────────────────────────────
-- A short on-screen alert when someone in the group types "bl" (or similar) in
-- chat. Only reads chat and draws a frame: nothing is cast or sent.

local BL_SECONDS = 5      -- how long the alert stays up on its own
local BL_W = 300

-- The ways people write it, matched on whole words (so "hero" fires, "heroic"
-- doesn't). "go"/"push"/"pop" are left out on purpose: too common in normal talk.
local BL_PHRASES = {
  "bl", "blood lust", "bloodlust",
  "lust", "lusting", "lusted",
  "hero", "heroism",
  "tw", "time warp", "timewarp",
  "drums", "drum", "drums of rage", "drums of fury",
  "primal rage", "ancient hysteria", "netherwinds", "fury of the aspects",
}

-- Lowercase, non-alphanumeric runs to single spaces, space-padded both ends, so
-- a padded phrase matches only on whole-word boundaries.
local function blFold(s)
  if type(s) ~= "string" then return " " end
  return " " .. s:lower():gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "") .. " "
end

local BL_FOLDED = {}
for _, phrase in ipairs(BL_PHRASES) do
  BL_FOLDED[#BL_FOLDED + 1] = blFold(phrase)
end

-- The phrase that was called, or nil.
local function blCalled(msg)
  local hay = blFold(msg)
  for i = 1, #BL_FOLDED do
    -- Both sides are space-padded, so a plain find is already a word match.
    if hay:find(BL_FOLDED[i], 1, true) then
      return (BL_FOLDED[i]:gsub("^%s+", ""):gsub("%s+$", ""))
    end
  end
  return nil
end

local blFrame, blHideAt
-- Set while the alert is up as a test frame: it then stays put until it is
-- switched off again, rather than timing out mid-drag.
local blPreviewing = false

local function blRestorePosition(f)
  -- Above the middle of the screen by default: high enough to be out of the way
  -- of the action bars, low enough to be inside where you are already looking.
  ns.restorePosition(f, "blpoint", "CENTER", 0, 180)
end

local function ensureBlFrame()
  if blFrame then return blFrame end
  local f = CreateFrame("Frame", "MythicPlusTimerLustFrame", UIParent, "BackdropTemplate")
  f:SetSize(BL_W, 56)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.savePosition(self, "blpoint")
  end)
  f:SetClampedToScreen(true)
  blRestorePosition(f)
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
  f.headline:SetText(GOLD .. "BLOODLUST" .. ENDC)

  f.who = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.who:SetPoint("TOP", f, "TOP", 0, -MP_PAD - 22)
  f.who:SetWidth(BL_W - MP_PAD * 2)
  f.who:SetWordWrap(false)

  -- Hovering holds it open, which is what makes it draggable: the alert would
  -- otherwise vanish out from under the cursor while being moved.
  f:SetScript("OnEnter", function() blHideAt = nil end)
  f:SetScript("OnLeave", function() blHideAt = GetTime() + 2 end)
  f:SetScript("OnUpdate", function(self)
    if blPreviewing then return end
    if blHideAt and GetTime() >= blHideAt then
      blHideAt = nil
      self:Hide()
    end
  end)

  f:Hide()
  blFrame = f
  return f
end

-- `who` is the caller's name, or nil when there isn't one to show.
local function blShowAlert(phrase, who)
  local f = ensureBlFrame()
  f.who:SetText(who
    and (WHITE .. who .. ENDC .. GREY .. " called " .. ENDC .. WHITE .. phrase .. ENDC)
    or (GREY .. "called as " .. ENDC .. WHITE .. phrase .. ENDC))
  blHideAt = GetTime() + BL_SECONDS
  f:Show()
end

-- The client reassigns arg1..arg14 from a filter's return, so returning only
-- the values this reads nils the language and flags and breaks its own handler.
local function blOnChat(_, _, msg, sender, ...)
  if not cfg("bloodlust") then return false, msg, sender, ... end
  if type(msg) ~= "string" or isSecret(msg) then return false, msg, sender, ... end
  local phrase = blCalled(msg)
  if phrase then
    local who = (type(sender) == "string" and not isSecret(sender)) and sender or nil
    -- Never let a draw error swallow someone's chat line.
    pcall(blShowAlert, phrase, who)
  end
  -- Always false: this reads chat, it never eats it.
  return false, msg, sender, ...
end

-- Where a call actually comes from. Guild and whisper are deliberately out:
-- someone saying "bl" in guild chat is talking, not calling it for your pull.
local BL_CHAT_TYPES = {
  "PARTY", "PARTY_LEADER",
  "RAID", "RAID_LEADER", "RAID_WARNING",
  "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
  "SAY", "YELL",
}

local blInstalled = false
local function blInstall()
  if blInstalled or type(ChatFrame_AddMessageEventFilter) ~= "function" then return end
  blInstalled = true
  -- pcall each: the set of chat events differs by client build, and one unknown
  -- name would otherwise abort the rest of the install.
  for _, t in ipairs(BL_CHAT_TYPES) do
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_" .. t, blOnChat)
  end
end

local blLoader = CreateFrame("Frame")
blLoader:RegisterEvent("PLAYER_LOGIN")
blLoader:SetScript("OnEvent", function() pcall(blInstall) end)

-- Preview frame for positioning: stays up (blPreviewing) until switched off.
ns.previewFrame("bloodlust alert", function()
  blPreviewing = true
  blShowAlert("bl", "Test")
  blHideAt = nil
end, function()
  blPreviewing = false
  blHideAt = nil
  if blFrame then blFrame:Hide() end
end)
