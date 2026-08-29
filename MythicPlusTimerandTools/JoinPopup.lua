local _, ns = ...

local GOLD, GREY, WHITE, ENDC, MP_PAD, cfg = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC, ns.PAD, ns.cfg
local isSecret = ns.isSecret
local jpFindTeleport = ns.findTeleport

-- ── "You joined" popup ───────────────────────────────────────────────────
-- On LFG_LIST_JOINED_GROUP, names the dungeon you were accepted into (from the
-- activity table) and its party. There's no API field for the key level (the
-- leader types it into the title), so the title is shown verbatim, never parsed.

-- Wide enough for a cross-realm leader name without it running under the close
-- button.
local JP_W = 320
local jpFrame
local jpTeleport   -- { spellID, name, icon } for this dungeon, or nil

local JP_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- Both the headings and the rows are laid out from this, so a value cannot
-- drift out from under its own column.
local JP_COL = {
  name  = { x = MP_PAD,       w = 150, justify = "LEFT" },
  ilvl  = { x = MP_PAD + 150, w = 60,  justify = "CENTER" },
  score = { x = MP_PAD + 210, w = JP_W - MP_PAD * 2 - 210, justify = "CENTER" },
}

local jpIlvlCache = {}  -- unit guid -> item level, from a completed inspect
local jpInspectGUID     -- guid of the inspect currently in flight, or nil
local jpLeader          -- { name, score } from the listing you joined, or nil

-- LFG reports "Name-Realm"; unit names are the short form.
local function jpPlainName(full)
  return (tostring(full or ""):gsub("%-.*$", ""))
end

local function jpIsSelf(unit)
  if type(UnitIsUnit) ~= "function" then return unit == "player" end
  local ok, v = pcall(UnitIsUnit, unit, "player")
  return (ok and v) and true or false
end

local function jpGUID(unit)
  local ok, g = pcall(UnitGUID, unit)
  return ok and g or nil
end

-- nil when the client has no rating loaded for that unit, which is most of the
-- group until everyone is close enough to inspect.
local function jpScore(unit)
  if not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then return nil end
  local ok, s = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
  if ok and type(s) == "table" and type(s.currentSeasonScore) == "number" then return s.currentSeasonScore end
  return nil
end

-- Your own comes from the character sheet, because the inspect API answers 0 for
-- yourself. Everyone else needs a completed inspect (see jpRequestInspect).
local function jpIlvl(unit)
  if jpIsSelf(unit) then
    if type(GetAverageItemLevel) ~= "function" then return nil end
    local ok, _, equipped = pcall(GetAverageItemLevel)
    if ok and type(equipped) == "number" and equipped > 0 then return math.floor(equipped) end
    return nil
  end
  local guid = jpGUID(unit)
  if guid and jpIlvlCache[guid] then return jpIlvlCache[guid] end
  if not (C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel) then return nil end
  local ok, n = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
  if ok and type(n) == "number" and n > 0 then return math.floor(n) end
  return nil
end

-- The client answers one inspect at a time, and only for someone in range. Ask
-- about the first member we have no number for; the rest follow as each
-- INSPECT_READY lands. Nobody is in range the instant you join a group.
local function jpRequestInspect()
  if jpInspectGUID or type(NotifyInspect) ~= "function" then return end
  if InCombatLockdown and InCombatLockdown() then return end
  -- The client holds one inspect target. While the player has their own inspect
  -- window open, asking for ours would retarget it under them.
  local insp = _G.InspectFrame
  if insp and type(insp.IsShown) == "function" then
    local ok, shown = pcall(insp.IsShown, insp)
    if ok and shown then return end
  end
  for _, unit in ipairs(JP_UNITS) do
    if UnitExists(unit) and not jpIsSelf(unit) then
      local guid = jpGUID(unit)
      if guid and not jpIlvlCache[guid] then
        local ok, can = pcall(CanInspect, unit)
        if ok and can then
          jpInspectGUID = guid
          pcall(NotifyInspect, unit)
          return
        end
      end
    end
  end
end

-- Returns true when this taught us something, so the caller knows to redraw.
-- INSPECT_READY fires for every inspect on the client, including the player's
-- own right-click one. Only the reply to our own request is ours to read and to
-- clear: clearing anyone else's leaves Blizzard's inspect window with nothing to
-- show, which reads in game as "this addon broke inspect".
local function jpInspectReady(guid)
  if not guid or guid ~= jpInspectGUID then return false end
  jpInspectGUID = nil
  local learned = false
  if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
    for _, unit in ipairs(JP_UNITS) do
      if UnitExists(unit) and jpGUID(unit) == guid then
        local ok, n = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
        if ok and type(n) == "number" and n > 0 then
          jpIlvlCache[guid] = math.floor(n)
          learned = true
        end
        break
      end
    end
  end
  pcall(ClearInspectPlayer)
  jpRequestInspect()
  return learned
end

-- Returns the row count, so the popup can size itself to the group.
local function jpRenderParty(f)
  for _, row in ipairs(f.partyRows) do row.name:Hide(); row.ilvl:Hide(); row.score:Hide() end
  local n = 0
  for _, unit in ipairs(JP_UNITS) do
    if UnitExists(unit) then
      n = n + 1
      local row = f.partyRows[n]
      if not row then
        row = {}
        local y = -MP_PAD - 102 - (n - 1) * 15
        for _, col in ipairs({ "name", "ilvl", "score" }) do
          local c = JP_COL[col]
          local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          fs:SetPoint("TOPLEFT", f, "TOPLEFT", c.x, y)
          fs:SetWidth(c.w)
          fs:SetJustifyH(c.justify)
          fs:SetWordWrap(false)
          row[col] = fs
        end
        f.partyRows[n] = row
      end
      local okName, nm = pcall(UnitName, unit)
      local name = (okName and type(nm) == "string" and not isSecret(nm) and nm) or "?"
      local okC, cl = pcall(UnitClassBase, unit)
      row.name:SetText(ns.classColoredName(name, (okC and type(cl) == "string") and cl or nil))
      local il = jpIlvl(unit)
      row.ilvl:SetText(il and (WHITE .. il .. ENDC) or (GREY .. "-" .. ENDC))
      -- The listing carries the leader's score, and is the only source that
      -- needs no inspect. A zero from the client means "not loaded", not "no
      -- rating", so it loses to the listing too.
      local sc = jpScore(unit)
      if (not sc or sc == 0) and jpLeader and jpLeader.score and name == jpLeader.name then
        sc = jpLeader.score
      end
      row.score:SetText(ns.scoreColored(sc))
      row.name:Show(); row.ilvl:Show(); row.score:Show()
    end
  end
  return n
end

local function ensureJoinFrame()
  if jpFrame then return jpFrame end
  local f = CreateFrame("Frame", "MythicPlusTimerJoinFrame", UIParent, "BackdropTemplate")
  f:SetSize(JP_W, 108)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.savePosition(self, "jppoint")
  end)
  f:SetClampedToScreen(true)
  ns.restorePosition(f, "jppoint", "TOP", 0, -300)
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

  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.label:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD)
  f.label:SetText(GOLD .. "Joined" .. ENDC)

  f.dungeon = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.dungeon:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD - 16)
  f.dungeon:SetWidth(JP_W - MP_PAD * 2 - 30)
  f.dungeon:SetJustifyH("LEFT")
  f.dungeon:SetWordWrap(false)

  -- The leader's own listing text, kept verbatim. Any key level lives in here.
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD - 38)
  f.title:SetWidth(JP_W - MP_PAD * 2)
  f.title:SetJustifyH("LEFT")

  f.leader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.leader:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD - 54)
  f.leader:SetWidth(JP_W - MP_PAD * 2)
  f.leader:SetJustifyH("LEFT")

  f.partyHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.partyHeader:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD - 74)
  f.partyHeader:SetText(GOLD .. "Party" .. ENDC)
  f.partyCols = {}
  for col, text in pairs({ name = "member", ilvl = "ilvl", score = "score" }) do
    local c = JP_COL[col]
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", c.x, -MP_PAD - 88)
    fs:SetWidth(c.w)
    fs:SetJustifyH(c.justify)
    fs:SetText(GREY .. text .. ENDC)
    f.partyCols[col] = fs
  end
  f.partyRows = {}

  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(24, 24)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  f.close:SetScript("OnClick", function() f:Hide() end)

  -- Casting is protected, so the teleport is a real secure button. Its spell
  -- attribute can only be set out of combat (see jpArmTeleport).
  f.tp = CreateFrame("Button", "MythicPlusTimerTeleportButton", f, "SecureActionButtonTemplate")
  f.tp:SetSize(34, 34)
  f.tp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -MP_PAD, MP_PAD)
  f.tp:RegisterForClicks("AnyUp", "AnyDown")
  f.tp:SetAttribute("type", "spell")
  -- A gold edge, so the icon reads as a button and not as decoration.
  f.tp.border = f.tp:CreateTexture(nil, "BACKGROUND")
  f.tp.border:SetPoint("TOPLEFT", f.tp, "TOPLEFT", -2, 2)
  f.tp.border:SetPoint("BOTTOMRIGHT", f.tp, "BOTTOMRIGHT", 2, -2)
  f.tp.border:SetColorTexture(0.88, 0.65, 0.31, 0.9)
  f.tp.icon = f.tp:CreateTexture(nil, "ARTWORK")
  f.tp.icon:SetAllPoints()
  f.tp.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.tp:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
  local tpHL = f.tp:GetHighlightTexture()
  if tpHL and tpHL.SetVertexColor then tpHL:SetVertexColor(1, 1, 1, 0.22) end
  f.tp:SetScript("OnEnter", function(self)
    if not self.spellName then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(GOLD .. "Teleport" .. ENDC)
    GameTooltip:AddLine(WHITE .. self.spellName .. ENDC)
    GameTooltip:AddLine(GREY .. "Click to travel to this dungeon." .. ENDC)
    GameTooltip:Show()
  end)
  f.tp:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.tp:Hide()

  -- The portrait alone gives no clue that it is clickable, or where it sends you.
  f.tpLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.tpLabel:SetPoint("BOTTOMRIGHT", f.tp, "BOTTOMLEFT", -8, 3)
  f.tpLabel:SetWidth(JP_W - MP_PAD * 2 - 52)
  f.tpLabel:SetJustifyH("RIGHT")
  f.tpLabel:Hide()

  f.tpNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.tpNote:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MP_PAD, MP_PAD + 8)
  f.tpNote:SetWidth(JP_W - MP_PAD * 2 - 40)
  f.tpNote:SetJustifyH("LEFT")

  f:Hide()
  jpFrame = f
  return f
end

-- Sizes to the rows plus a bottom strip for the teleport button and its label.
local function jpRedrawParty(f)
  local rows = jpRenderParty(f)
  f:SetHeight(MP_PAD + 102 + math.max(1, rows) * 15 + 48)
end

-- Arms the teleport button for `dungeon`, or leaves it hidden. Returns a short
-- line explaining why there's no button, or nil when there is one.
local function jpArmTeleport(f, dungeon)
  f.tp:Hide()
  f.tpLabel:Hide()
  f.tp.spellName = nil
  jpTeleport = jpFindTeleport(dungeon)
  if not jpTeleport then return nil end
  -- SetAttribute on a secure button is blocked in combat. Rather than silently
  -- doing nothing, say so: the button can be armed after combat drops.
  if InCombatLockdown and InCombatLockdown() then
    return "Teleport available, out of combat."
  end
  f.tp:SetAttribute("spell", jpTeleport.spellID)
  f.tp.spellName = jpTeleport.name
  if jpTeleport.icon then f.tp.icon:SetTexture(jpTeleport.icon) end
  f.tpLabel:SetText(GOLD .. "Teleport to" .. ENDC .. "\n" .. WHITE .. (dungeon or "") .. ENDC)
  f.tpLabel:Show()
  f.tp:Show()
  return nil
end

local function renderJoinFrame(dungeon, listingTitle, leaderName, leaderScore)
  local f = ensureJoinFrame()
  jpLeader = leaderName and { name = jpPlainName(leaderName), score = leaderScore } or nil
  -- Kept plain alongside the colored label: the rendered string carries |cff
  -- codes, so it can't be fed back into a name match.
  f.dungeonName = dungeon
  f.dungeon:SetText(GOLD .. (dungeon or "?") .. ENDC)
  f.title:SetText(listingTitle and listingTitle ~= "" and (WHITE .. listingTitle .. ENDC) or "")
  f.leader:SetText(leaderName and (GREY .. "Leader: " .. ENDC .. WHITE .. leaderName .. ENDC) or "")
  local note = jpArmTeleport(f, dungeon)
  f.tpNote:SetText(note and (GREY .. note .. ENDC) or "")
  jpRedrawParty(f)
  f:Show()
  jpRequestInspect()
end

-- Blizzard pops its own "You have joined a group" acknowledgement after you
-- accept an invite. When our popup is taking over for a Mythic+ join, hide that
-- one so there aren't two. Never the Accept/Decline invite itself: that fires
-- earlier and is how you actually join, and it still shows its Accept button.
local function jpHideBlizzardJoinNotice()
  local d = _G.LFGListInviteDialog
  if not d then return end
  if d.AcceptButton and d.AcceptButton.IsShown and d.AcceptButton:IsShown() then return end
  if type(StaticPopupSpecial_Hide) == "function" then
    pcall(StaticPopupSpecial_Hide, d)
  elseif d.Hide then
    pcall(d.Hide, d)
  end
end

local function onJoinedGroup(searchResultID)
  if not cfg("joinpopup") then return end
  if not (C_LFGList and C_LFGList.GetSearchResultInfo and searchResultID) then return end
  local okR, info = pcall(C_LFGList.GetSearchResultInfo, searchResultID)
  if not (okR and type(info) == "table" and type(info.activityIDs) == "table") then return end
  -- Only Mythic+ listings: joining a raid or a battleground is not this addon's
  -- business, and firing a keystone popup at one would be noise.
  local dungeon
  for _, activityID in ipairs(info.activityIDs) do
    local okA, activity = pcall(C_LFGList.GetActivityInfoTable, activityID)
    if okA and type(activity) == "table" and activity.isMythicPlusActivity then
      -- fullName reads "Algeth'ar Academy (Mythic Keystone)"; the parenthesised
      -- suffix is the same on every row, so it's dropped.
      dungeon = tostring(activity.fullName or ""):gsub("%s*%b()%s*$", "")
      break
    end
  end
  if not dungeon or dungeon == "" then return end
  local leader = (type(info.leaderName) == "string" and not isSecret(info.leaderName)) and info.leaderName or nil
  local title = (type(info.name) == "string" and not isSecret(info.name)) and info.name or nil
  -- The one rating available with no inspect and no proximity. Like the names,
  -- it can come back as a secret value.
  local leaderScore = info.leaderOverallDungeonScore
  if not (type(leaderScore) == "number" and not isSecret(leaderScore)) then leaderScore = nil end
  renderJoinFrame(dungeon, title, leader, leaderScore)
  -- Ours is up, so drop Blizzard's duplicate notice. Once now in case it is
  -- already showing, and once next frame in case Blizzard raises it just after
  -- this event (its "joined" state hides its own Accept button, which is how
  -- jpHideBlizzardJoinNotice tells it apart from a live invite).
  jpHideBlizzardJoinNotice()
  if type(C_Timer) == "table" and C_Timer.After then
    C_Timer.After(0, jpHideBlizzardJoinNotice)
  end
end

-- Preview frame for positioning. "Preview" isn't a real dungeon, so no teleport
-- matches it.
ns.previewFrame("join popup",
  function() renderJoinFrame("Preview", nil, nil) end,
  function() if jpFrame then jpFrame:Hide() end end,
  function() return jpFrame end, { group = "Alerts", section = "Group finder" })

local joinEvents = CreateFrame("Frame")
for _, ev in ipairs({ "LFG_LIST_JOINED_GROUP", "GROUP_LEFT", "GROUP_ROSTER_UPDATE",
  "PLAYER_REGEN_ENABLED", "INSPECT_READY" }) do
  pcall(joinEvents.RegisterEvent, joinEvents, ev)
end
joinEvents:SetScript("OnEvent", function(_, event, arg1)
  if event == "LFG_LIST_JOINED_GROUP" then
    pcall(onJoinedGroup, arg1)
  elseif event == "GROUP_ROSTER_UPDATE" then
    if jpFrame and jpFrame:IsShown() then
      jpRedrawParty(jpFrame)
      jpRequestInspect()
    end
  elseif event == "INSPECT_READY" then
    local learned = jpInspectReady(arg1)
    if learned and jpFrame and jpFrame:IsShown() then jpRedrawParty(jpFrame) end
  elseif event == "GROUP_LEFT" then
    -- A request still in flight will never be answered now, and a stale guid
    -- here would block every later one.
    jpInspectGUID = nil
    -- The group is gone, so the popup describing it is stale.
    if jpFrame and not (InCombatLockdown and InCombatLockdown()) then pcall(jpFrame.Hide, jpFrame) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- Combat dropped: arm a teleport that couldn't be set while it was up.
    if jpFrame and jpFrame:IsShown() and jpTeleport and not jpFrame.tp:IsShown() then
      local ok, note = pcall(jpArmTeleport, jpFrame, jpFrame.dungeonName)
      if ok then jpFrame.tpNote:SetText(note and (GREY .. note .. ENDC) or "") end
    end
  end
end)
