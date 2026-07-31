local _, ns = ...

local GOLD, GREY, WHITE, GREEN, RED, ENDC = ns.GOLD, ns.GREY, ns.WHITE, ns.GREEN, ns.RED, ns.ENDC
local GOLD_RGB, RULE_GAP, MP_PAD, MP_LINE, cfg, setCfg = ns.GOLD_RGB, ns.RULE_GAP, ns.PAD, ns.LINE, ns.cfg, ns.setCfg
local isSecret, mptPrint = ns.isSecret, ns.print
local mpClassColoredName = ns.classColoredName

-- Movable overlay for an active Mythic+ run: time, +2/+3 windows, affixes,
-- enemy forces, bosses, and deaths. Every value comes from the Challenge Mode /
-- Scenario API. +2/+3 thresholds are 60%/80% of the timer (patch 12.0.7).

local MP_UPGRADE3_FRACTION, MP_UPGRADE2_FRACTION = 0.60, 0.80
local MP_TICK = 0.2
local MP_W = 240
local MP_TITLE_LINE, MP_AFFIX_ICON, MP_AFFIX_LINE = 18, 20, 22
local MP_PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }

local mp = {
  active = false, mapID = nil, dungeonName = nil, level = nil, affixIDs = nil,
  timeLimit = 0, criteria = {}, numCriteria = 0, forcesIndex = nil,
  deathTotal = 0, deathByName = {}, deathOrder = {}, deadNow = {}, sinceTick = MP_TICK,
  -- Clock anchor. mp.startTime is the GetTime() value the scored clock is
  -- counting from; elapsed is derived locally off it every frame (see
  -- mpElapsedSeconds). clockAnchored flips true once we trust that anchor.
  startTime = nil, clockAnchored = false, startSyncRetries = 0,
  pendingOpensAt = nil, pendingStashedAt = nil,
  trackerHidden = false, trackerHookInstalled = false,
  -- Set the moment the key finishes: the run stays "active" (so presence
  -- tracking keeps hiding the default tracker and detects leaving) but frozen
  -- for review -- clock stopped, all bosses marked defeated, nothing re-polled.
  completed = false, frozenElapsed = nil, onTime = nil,
}
local mpFrame

-- Seconds since the scored clock started, counted locally off a start anchor
-- (mpAnchorStartTime) set once at key start.
local function mpElapsedSeconds()
  if mp.frozenElapsed then return mp.frozenElapsed end  -- finished run: frozen time
  if not mp.startTime then return 0 end
  return math.max(0, GetTime() - mp.startTime)
end

-- Seconds the challenge-mode world timer reports, or nil when not queryable.
-- The real timer IDs come from GetWorldElapsedTimers; the challenge-mode one is
-- timerType == 1.
local function mpWorldElapsed()
  if not (GetWorldElapsedTimers and GetWorldElapsedTime) then return nil end
  local ok, timers = pcall(function() return { GetWorldElapsedTimers() } end)
  if not (ok and type(timers) == "table") then return nil end
  for _, timerID in ipairs(timers) do
    local ok2, _, elapsedTime, timerType = pcall(GetWorldElapsedTime, timerID)
    if ok2 and timerType == 1 and type(elapsedTime) == "number" and elapsedTime > 0 then
      return elapsedTime
    end
  end
  return nil
end

-- Anchors the clock to the world timer, retrying briefly since it isn't always
-- queryable the instant the key starts. (START_TIMER is the preferred anchor.)
local function mpAnchorStartTime()
  if not mp.active or mp.clockAnchored then return end
  local elapsedSoFar = mpWorldElapsed()
  if elapsedSoFar then
    mp.startTime = GetTime() - elapsedSoFar
    mp.clockAnchored = true
    return
  end
  -- Not queryable yet: hold and poll again shortly (bounded).
  mp.startTime = mp.startTime or GetTime()
  mp.startSyncRetries = (mp.startSyncRetries or 0) + 1
  if mp.startSyncRetries <= 40 then
    C_Timer.After(0.5, mpAnchorStartTime)
  end
end

local function mpFmtTime(seconds)
  if not seconds or seconds < 0 then seconds = 0 end
  return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

-- Challenger's Burden: no death penalty below +4, 5s up to +11, 15s from +12.
local function mpDeathPenaltySeconds()
  local lvl = mp.level or 0
  if lvl < 4 then return 0 end
  if lvl >= 12 then return 15 end
  return 5
end

local function mpRefreshCriteria()
  local elapsed = mpElapsedSeconds()
  local ok, numCriteria = pcall(function() return select(3, C_Scenario.GetStepInfo()) end)
  numCriteria = (ok and type(numCriteria) == "number") and numCriteria or 0
  -- Outside the instance GetStepInfo reports 0 criteria; that's the API going
  -- quiet, not the run losing its bosses, so keep the last known state.
  if numCriteria == 0 then return end
  mp.numCriteria = numCriteria
  for i = 1, numCriteria do
    local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
    if ok2 and info then
      local row = mp.criteria[i]
      if not row then row = {}; mp.criteria[i] = row end
      row.desc = info.description
      if info.isWeightedProgress then
        mp.forcesIndex = i
        row.isForces = true
        -- Leading number only: quantityString is the absolute count but its
        -- trailing text differs by client ("182 / 260", "182%").
        row.quantity = info.quantityString and tonumber(info.quantityString:match("%d+%.?%d*"))
        row.totalQuantity = info.totalQuantity
        row.completed = info.completed  -- Blizzard's own "forces met" flag
      else
        row.isForces = false
        if info.completed and not row.completed then row.killElapsed = elapsed end
        row.completed = info.completed
      end
    end
  end
end

-- Death total from Blizzard's own counter. We can't register
-- COMBAT_LOG_EVENT_UNFILTERED for attribution (it throws ADDON_ACTION_FORBIDDEN
-- as of patch 12.0), so who died is polled per tick instead (mpPollPartyDeaths).
local mpDeathFrame = CreateFrame("Frame")
mpDeathFrame:RegisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
mpDeathFrame:SetScript("OnEvent", function()
  if not mp.active then return end
  local ok, n = pcall(C_ChallengeMode.GetDeathCount)
  -- Deaths only ever go UP within a run, so a lower number means the counter is
  -- unavailable (outside the instance) rather than deaths being undone. Taking
  -- it verbatim is what reset the tally to 0 on stepping out and back in.
  if ok and type(n) == "number" and n > mp.deathTotal then mp.deathTotal = n end
end)

-- Attributes deaths to party members by watching each unit's dead/ghost state
-- for a false->true edge, class-colored via the client's own RAID_CLASS_COLORS
-- (never a hardcoded red). Replaces the forbidden combat-log parse above.
local function mpPollPartyDeaths()
  if not mp.active then return end
  mp.deadNow = mp.deadNow or {}
  for _, unit in ipairs(MP_PARTY_UNITS) do
    if UnitExists(unit) then
      local guid = UnitGUID(unit)
      if guid then
        local dead = UnitIsDeadOrGhost(unit) and true or false
        -- A feigning hunter reads as dead to the client but the game doesn't
        -- count it, so neither should we (GetDeathCount would never agree).
        if dead and UnitIsFeignDeath and UnitIsFeignDeath(unit) then dead = false end
        if dead and not mp.deadNow[guid] then
          local okN, nm = pcall(UnitName, unit)
          local name = (okN and type(nm) == "string" and nm) or nil
          if name and not isSecret(name) then
            local okC, cl = pcall(UnitClassBase, unit)
            local row = mp.deathByName[name]
            if not row then
              row = { count = 0, class = (okC and type(cl) == "string") and cl or nil }
              mp.deathByName[name] = row
              mp.deathOrder[#mp.deathOrder + 1] = name
            end
            row.count = row.count + 1
          end
        end
        mp.deadNow[guid] = dead
      end
    end
  end
end

-- Restores the dragged-to position, falling back to the default top-center
-- spot the overlay has always used. Both go through Core's shared helpers, which
-- anchor the overlay by its TOP edge: the overlay changes height whenever a
-- block is hidden ("Let me focus") or a boss row arrives, and a top anchor is
-- what keeps the title where the eye left it while only the bottom edge moves.
local function mpRestorePosition(f)
  ns.restorePosition(f, "mppoint", "TOP", 0, -160)
end

local function mpSavePosition(f)
  ns.savePosition(f, "mppoint")
end

local function mpIsLocked() return cfg("mplocked") and true or false end

-- Locking pins the overlay: no dragging, and the resize grip goes away so it
-- can't be scaled by accident mid-pull either. The lock icon itself stays
-- clickable (otherwise there'd be no way back).
local function mpApplyLock(f)
  local locked = mpIsLocked()
  if f.lockIcon then
    f.lockIcon:SetNormalTexture(locked
      and "Interface\\Buttons\\LockButton-Locked-Up"
      or "Interface\\Buttons\\LockButton-Unlocked-Up")
  end
  if f.grip then f.grip:SetShown(not locked) end
end

-- Run state is mirrored into MythicPlusTimerRun so stepping out of the dungeon
-- (or a /reload out there) doesn't lose it. Cleared when the key finishes.
local MP_STALE_GRACE = 3600
-- How long a run survives while the player is outside the instance (respec trip).
local MP_AWAY_GRACE = 900

local function mpInMythicInstance()
  local ok, _, instanceType, difficultyID = pcall(GetInstanceInfo)
  return ok and instanceType == "party" and difficultyID == 8
end

-- Active keystone map id, or nil when no key is running (or not yet queryable).
-- The one signal that a run is genuinely live where the player stands.
local function mpActiveChallengeMapID()
  if not (C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID) then return nil end
  local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
  if ok and type(id) == "number" and id > 0 then return id end
  return nil
end

local function mpSave()
  if not mp.active or not mp.mapID then return end
  MythicPlusTimerRun = {
    v = 1,
    mapID = mp.mapID, dungeonName = mp.dungeonName, level = mp.level,
    affixIDs = mp.affixIDs, timeLimit = mp.timeLimit,
    -- Wall clock, not GetTime(): these must survive a /reload and a logout.
    startedWall = time() - math.floor(mpElapsedSeconds()),
    awayWall = mp.awayWall,
    deathTotal = mp.deathTotal, deathByName = mp.deathByName, deathOrder = mp.deathOrder,
    criteria = mp.criteria, numCriteria = mp.numCriteria, forcesIndex = mp.forcesIndex,
    prevNameplateCVar = mp.prevNameplateCVar,
  }
end

local function mpClearSaved() MythicPlusTimerRun = nil end

-- Rebuilds mp from the saved record. Refuses anything impossible or long
-- expired, so a record left behind by a crash can't haunt a later session.
local function mpRestoreSaved()
  local r = MythicPlusTimerRun
  if type(r) ~= "table" or r.v ~= 1 or not r.mapID or not r.startedWall then return false end
  local elapsed = time() - r.startedWall
  if elapsed < 0 or elapsed > (r.timeLimit or 0) + MP_STALE_GRACE then
    mpClearSaved()
    return false
  end
  mp.mapID, mp.dungeonName, mp.level = r.mapID, r.dungeonName, r.level
  mp.affixIDs, mp.timeLimit = r.affixIDs, r.timeLimit or 0
  mp.deathTotal = r.deathTotal or 0
  mp.deathByName, mp.deathOrder = r.deathByName or {}, r.deathOrder or {}
  mp.criteria, mp.numCriteria = r.criteria or {}, r.numCriteria or 0
  mp.forcesIndex = r.forcesIndex
  mp.prevNameplateCVar = type(r.prevNameplateCVar) == "string" and r.prevNameplateCVar or nil
  mp.awayWall = type(r.awayWall) == "number" and r.awayWall or nil
  mp.startTime = GetTime() - elapsed
  mp.clockAnchored, mp.startSyncRetries = true, 0
  mp.sinceTick = MP_TICK
  mp.active = true
  -- A saved record is always an in-progress run (completion clears it), so a
  -- restore never resumes into the frozen review state.
  mp.completed, mp.frozenElapsed, mp.onTime = false, nil, nil
  -- Seed from the CURRENT dead/ghost state so a corpse-running party isn't
  -- re-counted as five fresh deaths on the first poll after restoring.
  mp.deadNow = {}
  for _, unit in ipairs(MP_PARTY_UNITS) do
    if UnitExists(unit) then
      local guid = UnitGUID(unit)
      if guid then mp.deadNow[guid] = UnitIsDeadOrGhost(unit) and true or false end
    end
  end
  return true
end

-- ── Enemy nameplates in keys ─────────────────────────────────────────────
-- Turn enemy nameplates on at the gate (out of combat, when the CVar is still
-- settable) and restore the player's setting at the end. prevNameplateCVar
-- holds the value to restore, and rides along in the saved run across a /reload.
local mpNameplateRestore
local function mpSetNameplateCVar(value)
  if not (C_CVar and C_CVar.SetCVar) then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  return (pcall(C_CVar.SetCVar, "nameplateShowEnemies", value)) and true or false
end

local function mpEnableEnemyNameplates()
  if not cfg("autonameplates") then return end
  if mp.prevNameplateCVar ~= nil then return end
  if not (C_CVar and C_CVar.GetCVar) then return end
  local ok, cur = pcall(C_CVar.GetCVar, "nameplateShowEnemies")
  if not ok or cur ~= "0" then return end
  if mpSetNameplateCVar("1") then mp.prevNameplateCVar = cur end
end

local function mpRestoreNameplates()
  if mp.prevNameplateCVar == nil then return end
  if mpSetNameplateCVar(mp.prevNameplateCVar) then
    mp.prevNameplateCVar = nil
  elseif mpNameplateRestore then
    -- Combat-locked right now (a key can end mid-fight): do it once combat drops.
    mpNameplateRestore:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
end

mpNameplateRestore = CreateFrame("Frame")
mpNameplateRestore:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_REGEN_ENABLED")
  mpRestoreNameplates()
end)

-- ── Let me focus ─────────────────────────────────────────────────────────
-- With the setting on, a click hides the clock or the deaths (still tracked,
-- just not shown). Which is hidden lives in config so it survives a reload.
local function mpFocusOn() return cfg("letmefocus") and true or false end
local function mpFocusHidden(key) return mpFocusOn() and cfg(key) and true or false end

-- Forward-declared: the click zones created in ensureMPlusFrame redraw the
-- overlay, and mpRender is defined below it.
local mpRender

-- A transparent click target over one overlay block: drag still moves the
-- overlay, a click toggles that block's config key.
local function mpFocusZone(f, key)
  local b = CreateFrame("Button", nil, f)
  b:EnableMouse(true)
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function()
    if mpIsLocked() then return end
    f:StartMoving()
  end)
  b:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    mpSavePosition(f)
  end)
  b:SetScript("OnClick", function()
    setCfg(key, not cfg(key))
    pcall(mpRender)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(cfg(key) and "Click to show" or "Click to hide")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local function ensureMPlusFrame()
  if mpFrame then return mpFrame end
  local f = CreateFrame("Frame", "MythicPlusTimerFrame", UIParent, "BackdropTemplate")
  f:SetSize(MP_W, 120)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if mpIsLocked() then return end
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    mpSavePosition(self)
  end)
  f:SetClampedToScreen(true)
  local scale = tonumber(cfg("mpscale")) or 1
  f:SetScale(math.max(0.6, math.min(2.0, scale)))
  mpRestorePosition(f)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.9)
    f:SetBackdropBorderColor(0.88, 0.65, 0.31, 0.9)
  end

  -- Lock toggle, top-right corner. Blizzard's own action-bar lock textures, so
  -- the open/closed padlock reads the same way it does everywhere else in the
  -- UI. Dimmed until hovered so it stays out of the way during a pull.
  f.lockIcon = CreateFrame("Button", nil, f)
  f.lockIcon:SetSize(16, 16)
  f.lockIcon:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  f.lockIcon:SetAlpha(0.45)
  f.lockIcon:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(mpIsLocked() and "Unlock to move" or "Lock in place")
    GameTooltip:Show()
  end)
  f.lockIcon:SetScript("OnLeave", function(self)
    self:SetAlpha(0.45)
    GameTooltip:Hide()
  end)
  f.lockIcon:SetScript("OnClick", function()
    setCfg("mplocked", not mpIsLocked())
    mpApplyLock(f)
  end)

  -- Corner resize grip: drags a uniform SetScale so everything inside scales too.
  f.grip = CreateFrame("Button", nil, f)
  f.grip:SetSize(16, 16)
  f.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
  f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  f.grip:SetAlpha(0.45)
  f.grip:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Drag to resize")
    GameTooltip:Show()
  end)
  f.grip:SetScript("OnLeave", function(self)
    self:SetAlpha(0.45)
    GameTooltip:Hide()
  end)
  local function mpEndResize(self)
    if not self:GetScript("OnUpdate") then return end
    self:SetScript("OnUpdate", nil)
    setCfg("mpscale", math.floor(f:GetScale() * 100 + 0.5) / 100)
    mpSavePosition(f)  -- rescaling moves where it lands, so re-save
  end
  f.grip:SetScript("OnMouseDown", function(self)
    if mpIsLocked() then return end
    self.startX, self.startY = GetCursorPosition()
    self.startScale = f:GetScale()
    self:SetScript("OnUpdate", function(g)
      -- Releasing off the grip never fires OnMouseUp, so poll the button instead.
      if not IsMouseButtonDown("LeftButton") then return mpEndResize(g) end
      local cx, cy = GetCursorPosition()
      local delta = ((cx - g.startX) + (g.startY - cy)) / 2  -- down-and-right grows
      f:SetScale(math.max(0.6, math.min(2.0, g.startScale + delta / 320)))
    end)
  end)
  f.grip:SetScript("OnMouseUp", mpEndResize)
  f.grip:SetScript("OnHide", mpEndResize)
  -- Kept usable under the edit-mode overlay so the overlay can still be resized
  -- while the test frames are up.
  f.mptEditPassthrough = { f.grip }

  mpApplyLock(f)
  f.cells = {}
  f.rules = {}  -- pooled section-header underlines
  f.affixArea = CreateFrame("Frame", nil, f)
  f.affixArea:SetHeight(MP_AFFIX_LINE)
  f.affixText = f.affixArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.affixText:SetPoint("LEFT")
  f.affixText:SetJustifyH("LEFT")
  f.affixText:SetWordWrap(false)
  f.affixIcons = {}

  f.timeBar = CreateFrame("StatusBar", nil, f)
  f.timeBar:SetHeight(8)
  f.timeBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  f.timeBar:SetMinMaxValues(0, 1)
  f.timeBar.bg = f.timeBar:CreateTexture(nil, "BACKGROUND")
  f.timeBar.bg:SetAllPoints()
  f.timeBar.bg:SetColorTexture(0, 0, 0, 0.5)
  -- Thin white ticks over the fill marking the +3 then +2 upgrade windows. The
  -- bar shows time REMAINING, so a threshold at X% of the timer elapsed sits at
  -- (1 - X) of the bar's width from the left. Positioned in mpRender.
  f.timeBar.ticks = {}
  for i = 1, 2 do
    local t = f.timeBar:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 0.85)
    t:SetWidth(1)
    t:Hide()
    f.timeBar.ticks[i] = t
  end

  f.timeZone = mpFocusZone(f, "focushidetime")
  f.deathZone = mpFocusZone(f, "focushidedeaths")
  -- Lift the lock and grip above the click zones so they still take clicks.
  f.lockIcon:SetFrameLevel(f:GetFrameLevel() + 5)
  f.grip:SetFrameLevel(f:GetFrameLevel() + 5)

  f:Hide()
  mpFrame = f
  return f
end

function mpRender()
  local f = ensureMPlusFrame()
  for _, fs in ipairs(f.cells) do fs:Hide() end
  for _, tx in ipairs(f.rules) do tx:Hide() end
  for _, tk in ipairs(f.timeBar.ticks or {}) do tk:Hide() end
  local used, rulesUsed, y = 0, 0, 10
  local full = MP_W - MP_PAD * 2
  local function cell(text, x, width, justify, font)
    used = used + 1
    local fs = f.cells[used]
    if not fs then
      fs = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
      fs:SetWordWrap(false)
      f.cells[used] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(text)
    fs:Show()
    return fs
  end
  local function row(left, right)
    cell(left, MP_PAD, full * 0.55, "LEFT")
    if right then cell(right, MP_PAD + full * 0.55, full * 0.45, "RIGHT") end
    y = y + MP_LINE
  end
  -- Gold rule under a section header (Bosses/Deaths).
  local function underline()
    rulesUsed = rulesUsed + 1
    local tx = f.rules[rulesUsed]
    if not tx then
      tx = f:CreateTexture(nil, "OVERLAY")
      f.rules[rulesUsed] = tx
    end
    tx:ClearAllPoints()
    tx:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -y)
    tx:SetSize(full, 1)
    tx:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.4)
    tx:Show()
    y = y + RULE_GAP
  end
  -- Places a "Let me focus" click target over the block just drawn (top..bottom).
  local function zone(button, top, bottom)
    if not button then return end
    if not mpFocusOn() then button:Hide() return end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -top)
    button:SetSize(full, math.max(1, bottom - top))
    button:Show()
  end

  -- Title: dungeon + key level, in the larger font. Short of `full` to clear the lock icon.
  cell(GOLD .. (mp.dungeonName or "?") .. ENDC .. "  " .. GOLD .. "+" .. (mp.level or "?") .. ENDC,
    MP_PAD, full - 20, "LEFT", "GameFontNormal")
  y = y + MP_TITLE_LINE

  -- Affix icons from the client's own GetAffixInfo fileID.
  for _, icon in ipairs(f.affixIcons) do icon:Hide() end
  f.affixText:Hide()
  if cfg("showaffixes") then
    f.affixArea:Show()
    f.affixArea:ClearAllPoints()
    f.affixArea:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -y)
    f.affixArea:SetWidth(full)
    f.affixArea:SetHeight(MP_AFFIX_LINE)
    local shown = 0
    for _, id in ipairs(mp.affixIDs or {}) do
      local ok, _, _, iconID = pcall(C_ChallengeMode.GetAffixInfo, id)
      if ok and iconID then
        shown = shown + 1
        local icon = f.affixIcons[shown]
        if not icon then
          -- One Button per icon so a hover names only that affix.
          icon = CreateFrame("Button", nil, f.affixArea)
          icon.tex = icon:CreateTexture(nil, "ARTWORK")
          icon.tex:SetAllPoints()
          icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
          icon:SetScript("OnEnter", function(self)
            if not self.affixID then return end
            local okInfo, name, desc = pcall(C_ChallengeMode.GetAffixInfo, self.affixID)
            if not (okInfo and name) then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(GOLD .. name .. ENDC)
            if desc and desc ~= "" then GameTooltip:AddLine(desc, 1, 1, 1, true) end
            GameTooltip:Show()
          end)
          icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
          f.affixIcons[shown] = icon
        end
        icon.affixID = id
        icon:SetSize(MP_AFFIX_ICON, MP_AFFIX_ICON)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", f.affixArea, "LEFT", (shown - 1) * (MP_AFFIX_ICON + 4), 0)
        icon.tex:SetTexture(iconID)
        icon:Show()
      end
    end
    if shown == 0 then
      local affixNames = {}
      for _, id in ipairs(mp.affixIDs or {}) do
        local ok, name = pcall(C_ChallengeMode.GetAffixInfo, id)
        if ok and name then affixNames[#affixNames + 1] = name end
      end
      f.affixText:SetText(GREY .. table.concat(affixNames, " \194\183 ") .. ENDC)
      f.affixText:Show()
    end
    y = y + MP_AFFIX_LINE + 2
  else
    f.affixArea:Hide()
  end

  -- The whole clock block is one thing to hide: the countdown alone would leave
  -- the elapsed row, the bar and the upgrade windows all still saying the time.
  local timeTop = y
  -- Deaths add to the scored clock (Challenger's Burden), so the time that
  -- decides whether the key is still beatable is run time plus the death
  -- penalty, not wall time. The countdown, the bar and the +2/+3 windows all
  -- work off this scored time so they run out exactly when the key does. On the
  -- frozen completion screen mpElapsedSeconds is already Blizzard's final,
  -- penalty-inclusive time, so it must not be added to twice.
  local elapsed = mpElapsedSeconds()
  if not mp.frozenElapsed then
    elapsed = elapsed + mpDeathPenaltySeconds() * (mp.deathTotal or 0)
  end
  if mpFocusHidden("focushidetime") then
    f.timeBar:Hide()
    cell(GREY .. "Hidden" .. ENDC, MP_PAD, full, "CENTER", "GameFontNormalLarge")
    y = y + MP_LINE + 6
  else
    local remaining = (mp.timeLimit or 0) - elapsed
    local timeColor = remaining > 0 and GREEN or RED
    cell(timeColor .. mpFmtTime(remaining) .. ENDC, MP_PAD, full, "CENTER", "GameFontNormalLarge")
    y = y + MP_LINE + 6
    row(GREY .. mpFmtTime(elapsed) .. " elapsed" .. ENDC, GREY .. mpFmtTime(mp.timeLimit) .. " max" .. ENDC)
    y = y + 2

    f.timeBar:ClearAllPoints()
    f.timeBar:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -y)
    f.timeBar:SetWidth(full)
    local frac = (mp.timeLimit and mp.timeLimit > 0)
      and math.max(0, math.min(1, remaining / mp.timeLimit)) or 0
    f.timeBar:SetValue(frac)
    f.timeBar:SetStatusBarColor(remaining > 0 and 0.2 or 0.7, remaining > 0 and 0.7 or 0.2, 0.2)
    f.timeBar:Show()
    if cfg("showbarticks") then
      -- +3 first, then +2: at (1 - upgrade fraction) of the bar from the left.
      local tickFractions = { 1 - MP_UPGRADE3_FRACTION, 1 - MP_UPGRADE2_FRACTION }
      for i, tf in ipairs(tickFractions) do
        local tk = f.timeBar.ticks[i]
        if tk then
          tk:ClearAllPoints()
          tk:SetPoint("TOP", f.timeBar, "TOPLEFT", tf * full, 0)
          tk:SetPoint("BOTTOM", f.timeBar, "BOTTOMLEFT", tf * full, 0)
          tk:Show()
        end
      end
    end
    y = y + 12

    if mp.timeLimit and mp.timeLimit > 0 then
      local cutoff3, cutoff2 = mp.timeLimit * MP_UPGRADE3_FRACTION, mp.timeLimit * MP_UPGRADE2_FRACTION
      local line3 = elapsed < cutoff3
        and (GREEN .. "+3 in " .. mpFmtTime(cutoff3 - elapsed) .. ENDC)
        or (GREY .. "+3 missed" .. ENDC)
      local line2 = elapsed < cutoff2
        and (GREEN .. "+2 in " .. mpFmtTime(cutoff2 - elapsed) .. ENDC)
        or (GREY .. "+2 missed" .. ENDC)
      row(line3, line2)
    end
  end
  y = y + 4
  zone(f.timeZone, timeTop, y)

  -- Banked enemy forces only. A pull's "current" value can't be predicted: on
  -- patch 12 a mob's UnitGUID and GetUnitCriteriaProgressValues are secret to
  -- addons in a key, and secrets can't be summed.
  if cfg("showforces") and mp.forcesIndex and mp.criteria[mp.forcesIndex] then
    local fc = mp.criteria[mp.forcesIndex]
    local total = (type(fc.totalQuantity) == "number" and fc.totalQuantity > 0) and fc.totalQuantity or nil
    local done = type(fc.quantity) == "number" and fc.quantity or nil
    local pct = (total and done) and math.min(100, done / total * 100) or nil
    local shown = pct and string.format("%.2f", pct) or nil
    -- Green when met, tested on the rounded value actually shown (so 99.996%
    -- reading "100,00 %" is green too), or on Blizzard's own completed flag.
    local metForces = fc.completed or (shown and tonumber(shown) >= 100)
    row(GREY .. "Enemy forces" .. ENDC,
      shown and ((metForces and GREEN or WHITE) .. (shown:gsub("%.", ",")) .. " %" .. ENDC)
        or (GREY .. "-" .. ENDC))
  end
  y = y + 4

  if cfg("showbosses") and mp.numCriteria and mp.numCriteria > 0 then
    cell(GOLD .. "Bosses" .. ENDC, MP_PAD, full, "LEFT")
    y = y + MP_LINE
    underline()
    for i = 1, mp.numCriteria do
      local c = mp.criteria[i]
      if c and not c.isForces then
        local status = c.completed
          and (GREEN .. "killed " .. mpFmtTime(c.killElapsed or 0) .. ENDC)
          or (GREY .. "not done" .. ENDC)
        row((c.completed and WHITE or GREY) .. (c.desc or "?") .. ENDC, status)
      end
    end
    y = y + 4
  end

  -- Deaths, with the clock time each cost above +3 (Challenger's Burden).
  if cfg("showdeaths") then
    local deathTop = y
    local hideDeaths = mpFocusHidden("focushidedeaths")
    local penalty = mpDeathPenaltySeconds()
    local totalRight = WHITE .. mp.deathTotal .. " total" .. ENDC
    if penalty > 0 and mp.deathTotal > 0 then
      totalRight = totalRight .. RED .. "  -" .. mpFmtTime(penalty * mp.deathTotal) .. ENDC
    end
    cell(GOLD .. "Deaths" .. ENDC, MP_PAD, full * 0.4, "LEFT")
    cell(hideDeaths and (GREY .. "Hidden" .. ENDC) or totalRight,
      MP_PAD + full * 0.4, full * 0.6, "RIGHT")
    y = y + MP_LINE
    underline()
    if not hideDeaths then
      for _, name in ipairs(mp.deathOrder) do
        local d = mp.deathByName[name]
        if d then
          local right = GREY .. "x" .. d.count .. ENDC
          if penalty > 0 then right = right .. RED .. "  -" .. mpFmtTime(penalty * d.count) .. ENDC end
          row(mpClassColoredName(name, d.class), right)
        end
      end
    end
    y = y + 4
    zone(f.deathZone, deathTop, y)
  else
    f.deathZone:Hide()
  end

  -- Extra bottom room so the resize grip sits in padding, not over the last row.
  f:SetHeight(y + MP_PAD + 8)
end

-- Hides Blizzard's ScenarioObjectiveTracker while our overlay is up so the two
-- timers don't stack. Nil-guarded, so a UI restructure just no-ops.
local function mpSetDefaultTrackerHidden(hide)
  local sot = _G.ScenarioObjectiveTracker
  if not sot then return end
  if hide then
    if sot:IsShown() then pcall(sot.Hide, sot) end
    mp.trackerHidden = true
  elseif mp.trackerHidden then
    mp.trackerHidden = false
    pcall(sot.Show, sot)
  end
end

-- Blizzard re-Shows the tracker on every objective update, so a one-shot Hide
-- loses the race. A post-hook on Show re-hides it while our run is active.
local function mpInstallTrackerHook()
  if mp.trackerHookInstalled then return end
  local sot = _G.ScenarioObjectiveTracker
  if not sot or type(hooksecurefunc) ~= "function" then return end
  mp.trackerHookInstalled = true
  -- Gated on trackerHidden (cleared before our own unhide) so teardown's Show
  -- isn't re-hidden.
  hooksecurefunc(sot, "Show", function(self)
    if mp.active and mp.trackerHidden and cfg("mythicplustimer") then pcall(self.Hide, self) end
  end)
end

local function mpOnComplete()
  -- Freeze the clock at Blizzard's authoritative completion time if we have it.
  local finalElapsed = mpElapsedSeconds()
  local okInfo, info = pcall(function() return C_ChallengeMode.GetChallengeCompletionInfo() end)
  if okInfo and type(info) == "table" and type(info.time) == "number" and info.time > 0 then
    finalElapsed = info.time / 1000
  end
  -- Force every boss to defeated: completion means they're all down, but the
  -- criteria API can blank the final boss's kill just as the run ends.
  pcall(mpRefreshCriteria)
  for i = 1, (mp.numCriteria or 0) do
    local c = mp.criteria[i]
    if c and not c.isForces and not c.completed then
      c.completed = true
      c.killElapsed = c.killElapsed or finalElapsed
    end
  end
  -- Frozen review state: stay "active" (so the tracker stays hidden and presence
  -- still fires) but stop the clock and re-polling until the player leaves.
  mp.completed = true
  mp.frozenElapsed = finalElapsed
  mp.onTime = okInfo and type(info) == "table" and info.onTime or nil
  pcall(mpClearSaved)  -- key is over: don't let a /reload resurrect it
  pcall(mpRestoreNameplates)
  pcall(mpRender)
end

local function mpOnReset()
  mp.active = false
  mp.completed, mp.frozenElapsed, mp.onTime = false, nil, nil
  if mpFrame then mpFrame:Hide() end
  pcall(mpClearSaved)
  pcall(mpRestoreNameplates)
  pcall(mpSetDefaultTrackerHidden, false)
end

-- Keeps a still-active run in sync with where the player is: inside a live key
-- it runs; briefly outside it pauses (respec trip); outside too long, or a
-- different key is live, it ends. Called every tick and on zone changes.
local function mpEvaluatePresence()
  if not mp.active then return end

  if mpInMythicInstance() then
    -- Standing in a Mythic party instance. A DIFFERENT key being live here
    -- means ours is long gone (new key started in the same dungeon), so drop
    -- it. A nil map ID is tolerated: the API goes briefly unqueryable on zone
    -- in and right after a completion, and neither means "abandoned".
    local activeMap = mpActiveChallengeMapID()
    if activeMap and mp.mapID and activeMap ~= mp.mapID then
      mpOnReset()
      return
    end
    mp.awayWall = nil
    if mpFrame and not mpFrame:IsShown() then mpFrame:Show() end
    return
  end

  -- Outside the instance: never draw a running clock (could be a respec pause or
  -- a run that quietly ended; we can't tell from here).
  if mpFrame then mpFrame:Hide() end
  pcall(mpSetDefaultTrackerHidden, false)
  if mp.completed then mpOnReset() return end  -- nothing to resume
  mp.awayWall = mp.awayWall or time()
  if time() - mp.awayWall >= MP_AWAY_GRACE then mpOnReset() end
end

-- True when CHALLENGE_MODE_START is re-announcing the key we already track
-- (walking back in) rather than a fresh one. The world timer breaks ties: a
-- fresh key reads ~0 while our clock would be far along.
local function mpIsResumeOf(mapID, level)
  if not (mp.active and mp.mapID and mp.mapID == mapID and mp.level == level) then
    return false
  end
  local worldElapsed = mpWorldElapsed()
  if worldElapsed and math.abs(worldElapsed - mpElapsedSeconds()) > 90 then
    return false
  end
  return true
end

local function mpStart()
  if not cfg("mythicplustimer") then return end
  local okMap, activeMapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
  activeMapID = okMap and activeMapID or nil
  local okKey, activeLevel, activeAffixes = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
  activeLevel = okKey and activeLevel or nil

  -- Re-entering the dungeon: keep every death, boss kill, and the running clock.
  if mpIsResumeOf(activeMapID, activeLevel) then
    mpInstallTrackerHook()
    ensureMPlusFrame():Show()
    mpRender()
    if mpInMythicInstance() then pcall(mpSetDefaultTrackerHidden, true) end
    return
  end

  mp.active = true
  mp.completed, mp.frozenElapsed, mp.onTime = false, nil, nil
  mp.criteria, mp.numCriteria, mp.forcesIndex = {}, 0, nil
  mp.deathTotal, mp.deathByName, mp.deathOrder = 0, {}, {}
  mp.sinceTick = MP_TICK
  mp.awayWall = nil
  mp.mapID = activeMapID
  if mp.mapID then
    local ok2, name, _, timeLimit = pcall(C_ChallengeMode.GetMapUIInfo, mp.mapID)
    mp.dungeonName = ok2 and name or nil
    mp.timeLimit = ok2 and timeLimit or 0
  end
  mp.level = activeLevel
  mp.affixIDs = okKey and activeAffixes or nil

  -- Anchor the clock: prefer the START_TIMER countdown (exact), else world timer.
  mp.clockAnchored = false
  mp.startSyncRetries = 0
  mp.startTime = GetTime()
  if mp.pendingOpensAt and (GetTime() - (mp.pendingStashedAt or 0)) < 30 then
    mp.startTime = mp.pendingOpensAt
    mp.clockAnchored = true
  else
    mpAnchorStartTime()
  end
  mp.pendingOpensAt, mp.pendingStashedAt = nil, nil

  -- Seed death state so anyone already dead at the pull isn't logged as a
  -- fresh death on the first poll.
  mp.deadNow = {}
  for _, unit in ipairs(MP_PARTY_UNITS) do
    if UnitExists(unit) then
      local guid = UnitGUID(unit)
      if guid then mp.deadNow[guid] = UnitIsDeadOrGhost(unit) and true or false end
    end
  end

  mpInstallTrackerHook()
  ensureMPlusFrame():Show()
  mpRender()
  pcall(mpEnableEnemyNameplates)
  pcall(mpSave)
  pcall(mpSetDefaultTrackerHidden, true)
end

-- Restores the overlay after a /reload or zone-in, but only when the client
-- agrees a key is live here; otherwise mpEvaluatePresence decides. `retry`
-- gives the challenge-mode API one more look, since it's briefly unqueryable
-- right after a zone-in.
local function mpResume(retry)
  if not cfg("mythicplustimer") then return end
  if not mp.active and not mpRestoreSaved() then return end
  if not mpInMythicInstance() then
    mpEvaluatePresence()
    return
  end
  if not mpActiveChallengeMapID() then
    if not retry then
      C_Timer.After(3, function() mpResume(true) end)
      return
    end
    -- In the dungeon but no keystone running: the saved run is genuinely over.
    mpOnReset()
    return
  end
  mp.awayWall = nil
  mpInstallTrackerHook()
  ensureMPlusFrame():Show()
  mpRender()
  pcall(mpSetDefaultTrackerHidden, true)
end

local mpSinceSave = 0
local mpTicker = CreateFrame("Frame")
mpTicker:SetScript("OnUpdate", function(_, elapsed)
  if not mp.active then return end
  if not cfg("mythicplustimer") then
    -- Overlay switched off mid-run: hide ours but keep the run alive so ticking
    -- the setting back on restores it where it left off.
    if mpFrame and mpFrame:IsShown() then pcall(mpFrame.Hide, mpFrame) end
    pcall(mpSetDefaultTrackerHidden, false)
    return
  end
  mp.sinceTick = mp.sinceTick + elapsed
  if mp.sinceTick < MP_TICK then return end
  mpSinceSave = mpSinceSave + mp.sinceTick
  mp.sinceTick = 0
  mpEvaluatePresence()  -- may end the run; everything below assumes it's still live
  if not mp.active then return end
  if mpSinceSave >= 2 then
    mpSinceSave = 0
    pcall(mpSave)
  end
  if not mpInMythicInstance() then return end  -- out at the entrance: don't poll
  -- A finished run is frozen: keep drawing it but stop re-reading criteria/deaths.
  if not mp.completed then
    mpRefreshCriteria()
    mpPollPartyDeaths()
  end
  mpRender()
  pcall(mpSetDefaultTrackerHidden, true)
end)

-- CHALLENGE_MODE_* fire inside the protected keystone-activation chain, so
-- touching our frames directly here can taint. Defer a frame to run outside it.
-- START_TIMER only stashes a timestamp (never taints) and must be caught inline.
local mpLifecycle = CreateFrame("Frame")
mpLifecycle:RegisterEvent("CHALLENGE_MODE_START")
mpLifecycle:RegisterEvent("CHALLENGE_MODE_COMPLETED")
mpLifecycle:RegisterEvent("CHALLENGE_MODE_RESET")
mpLifecycle:RegisterEvent("START_TIMER")
mpLifecycle:RegisterEvent("PLAYER_ENTERING_WORLD")
mpLifecycle:SetScript("OnEvent", function(_, event, ...)
  if event == "CHALLENGE_MODE_START" then
    C_Timer.After(0, mpStart)
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Zoned or reloaded. The challenge-mode APIs aren't queryable the instant
    -- this fires, so give them a moment before deciding whether to resume.
    C_Timer.After(1, mpResume)
  elseif event == "CHALLENGE_MODE_COMPLETED" then
    C_Timer.After(0, mpOnComplete)
  elseif event == "CHALLENGE_MODE_RESET" then
    C_Timer.After(0, mpOnReset)
  elseif event == "START_TIMER" then
    -- The clock starts at now + timeRemaining. Filter to the challenge-mode
    -- countdown and sanity-bound the seconds.
    local timerType, timeRemaining = ...
    if type(timeRemaining) == "number" and timeRemaining > 0 and timeRemaining <= 60
      and (not (Enum and Enum.StartTimerType and Enum.StartTimerType.ChallengeModeCountdown)
        or timerType == Enum.StartTimerType.ChallengeModeCountdown) then
      if mp.active and (GetTime() - (mp.startTime or GetTime())) < 60 then
        mp.startTime = GetTime() + timeRemaining
        mp.clockAnchored = true
      else
        mp.pendingOpensAt = GetTime() + timeRemaining
        mp.pendingStashedAt = GetTime()
      end
    end
  end
end)

ns.command("lock", "lock or unlock the overlay", function()
  setCfg("mplocked", not mpIsLocked())
  if mpFrame then mpApplyLock(mpFrame) end
  mptPrint(mpIsLocked() and "overlay locked." or "overlay unlocked.")
end)

ns.command("reset", "put the overlay back where it started", function()
  setCfg("mppoint", nil)
  setCfg("mpscale", 1)
  if mpFrame then
    mpFrame:SetScale(1)
    mpRestorePosition(mpFrame)
  end
  mptPrint("overlay position and scale reset.")
end)

-- Take effect on the live run at once rather than on the next tick.
ns.onOptionChanged("mythicplustimer", function()
  if cfg("mythicplustimer") then
    pcall(mpResume)
  else
    if mpFrame then pcall(mpFrame.Hide, mpFrame) end
    pcall(mpSetDefaultTrackerHidden, false)
  end
end)

ns.onOptionChanged("letmefocus", function()
  if mpFrame and mpFrame:IsShown() then pcall(mpRender) end
end)

-- Preview frame for positioning: a mid-run snapshot so every block (clock,
-- upgrade windows, forces, bosses, deaths) shows real-looking content instead of
-- an empty shell. Drawn only when no run is live; mpStart rebuilds all of this
-- for the next real run.
local mpPreviewing = false

-- This week's affixes when the client will tell us, so the icons match; a static
-- set otherwise, which the render falls back to naming if an icon won't resolve.
local function mpPreviewAffixes()
  local ids = {}
  if C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
    local ok, list = pcall(C_MythicPlus.GetCurrentAffixes)
    if ok and type(list) == "table" then
      for _, a in ipairs(list) do if a and a.id then ids[#ids + 1] = a.id end end
    end
  end
  if #ids == 0 then ids = { 10, 9, 147 } end
  return ids
end

local function mpLoadPreviewData()
  mp.dungeonName, mp.level, mp.timeLimit = "Ara-Kara, City of Echoes", 12, 1980
  mp.affixIDs = mpPreviewAffixes()
  -- A fixed elapsed so the clock reads a steady figure without a running anchor.
  mp.frozenElapsed = 612
  mp.forcesIndex = 1
  mp.criteria = {
    { isForces = true, quantity = 235, totalQuantity = 286, completed = false },
    { desc = "Avanoxx", completed = true, killElapsed = 214 },
    { desc = "Anub'zekt", completed = true, killElapsed = 468 },
    { desc = "Ki'katal the Harvester", completed = false },
  }
  mp.numCriteria = 4
  mp.deathOrder = { "Frifti", "Vxmpi", "Daeihossein", "Samstmage", "Unholymaster" }
  mp.deathByName = {
    Frifti = { count = 2, class = "MAGE" },
    Vxmpi = { count = 1, class = "ROGUE" },
    Daeihossein = { count = 3, class = "PRIEST" },
    Samstmage = { count = 1, class = "SHAMAN" },
    Unholymaster = { count = 2, class = "DEATHKNIGHT" },
  }
  mp.deathTotal = 9
end

ns.previewFrame("run overlay", function()
  if mp.active or mpPreviewing then return end
  mpPreviewing = true
  mpLoadPreviewData()
  ensureMPlusFrame():Show()
  mpRender()
end, function()
  if not mpPreviewing then return end
  mpPreviewing = false
  mp.dungeonName, mp.level, mp.timeLimit, mp.affixIDs = nil, nil, 0, nil
  mp.frozenElapsed = nil
  mp.criteria, mp.numCriteria, mp.forcesIndex = {}, 0, nil
  mp.deathTotal, mp.deathByName, mp.deathOrder = 0, {}, {}
  if mpFrame then mpFrame:Hide() end
end, function() return mpFrame end, { group = "Mythic+ timer", section = "The overlay" })
