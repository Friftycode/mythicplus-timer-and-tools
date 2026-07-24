local _, ns = ...

local GOLD, GREY, WHITE, ENDC, MP_PAD, cfg = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC, ns.PAD, ns.cfg
local isSecret = ns.isSecret
local jpFindTeleport = ns.findTeleport

-- ── "You joined" popup ───────────────────────────────────────────────────
-- On LFG_LIST_JOINED_GROUP, names the dungeon you were accepted into (from the
-- activity table) and its party. There's no API field for the key level (the
-- leader types it into the title), so the title is shown verbatim, never parsed.

local JP_W = 260
local jpFrame
local jpTeleport   -- { spellID, name, icon } for this dungeon, or nil

local JP_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- Mythic+ score for a unit, straight from the client's own rating summary (it
-- works for group members without an inspect). nil when there is none to show.
local function jpScore(unit)
  if not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then return nil end
  local ok, s = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
  if ok and type(s) == "table" and type(s.currentSeasonScore) == "number" then return s.currentSeasonScore end
  return nil
end

-- Average item level. Only your own is known right away; a party member's needs
-- an inspect the client may not have cached yet, so this is often nil for them.
local function jpIlvl(unit)
  if not (C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel) then return nil end
  local ok, n = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
  if ok and type(n) == "number" and n > 0 then return math.floor(n) end
  return nil
end

-- Draws one row per present party unit (name, item level, M+ score) and returns
-- the count, so the popup can size itself to the group.
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
        row.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, y)
        row.name:SetWidth(118); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.ilvl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ilvl:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD + 118, y)
        row.ilvl:SetWidth(50); row.ilvl:SetJustifyH("RIGHT")
        row.score = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.score:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD + 170, y)
        row.score:SetWidth(JP_W - MP_PAD * 2 - 170); row.score:SetJustifyH("RIGHT")
        f.partyRows[n] = row
      end
      local okName, nm = pcall(UnitName, unit)
      local name = (okName and type(nm) == "string" and not isSecret(nm) and nm) or "?"
      local okC, cl = pcall(UnitClassBase, unit)
      row.name:SetText(ns.classColoredName(name, (okC and type(cl) == "string") and cl or nil))
      local il = jpIlvl(unit)
      row.ilvl:SetText(il and (WHITE .. il .. ENDC) or (GREY .. "-" .. ENDC))
      local sc = jpScore(unit)
      row.score:SetText(sc and (GOLD .. sc .. ENDC) or (GREY .. "-" .. ENDC))
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

  -- Party roster: name, item level, M+ score.
  f.partyHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.partyHeader:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD - 74)
  f.partyHeader:SetText(GOLD .. "Party" .. ENDC)
  f.partyCols = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.partyCols:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD - 88)
  f.partyCols:SetWidth(JP_W - MP_PAD * 2)
  f.partyCols:SetJustifyH("RIGHT")
  f.partyCols:SetText(GREY .. "ilvl        score" .. ENDC)
  f.partyRows = {}

  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(24, 24)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  f.close:SetScript("OnClick", function() f:Hide() end)

  -- Casting is protected, so the teleport is a real secure button. Its spell
  -- attribute can only be set out of combat (see jpArmTeleport).
  f.tp = CreateFrame("Button", "MythicPlusTimerTeleportButton", f, "SecureActionButtonTemplate")
  f.tp:SetSize(30, 30)
  f.tp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -MP_PAD, MP_PAD)
  f.tp:RegisterForClicks("AnyUp", "AnyDown")
  f.tp:SetAttribute("type", "spell")
  f.tp.icon = f.tp:CreateTexture(nil, "ARTWORK")
  f.tp.icon:SetAllPoints()
  f.tp.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.tp:SetScript("OnEnter", function(self)
    if not self.spellName then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(GOLD .. "Teleport" .. ENDC)
    GameTooltip:AddLine(WHITE .. self.spellName .. ENDC)
    GameTooltip:Show()
  end)
  f.tp:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.tp:Hide()

  f.tpNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.tpNote:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MP_PAD, MP_PAD + 8)
  f.tpNote:SetWidth(JP_W - MP_PAD * 2 - 40)
  f.tpNote:SetJustifyH("LEFT")

  f:Hide()
  jpFrame = f
  return f
end

-- Arms the teleport button for `dungeon`, or leaves it hidden. Returns a short
-- line explaining why there's no button, or nil when there is one.
local function jpArmTeleport(f, dungeon)
  f.tp:Hide()
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
  f.tp:Show()
  return nil
end

local function renderJoinFrame(dungeon, listingTitle, leaderName)
  local f = ensureJoinFrame()
  -- Kept plain alongside the colored label: the rendered string carries |cff
  -- codes, so it can't be fed back into a name match.
  f.dungeonName = dungeon
  f.dungeon:SetText(GOLD .. (dungeon or "?") .. ENDC)
  f.title:SetText(listingTitle and listingTitle ~= "" and (WHITE .. listingTitle .. ENDC) or "")
  f.leader:SetText(leaderName and (GREY .. "Leader: " .. ENDC .. WHITE .. leaderName .. ENDC) or "")
  local note = jpArmTeleport(f, dungeon)
  f.tpNote:SetText(note and (GREY .. note .. ENDC) or "")
  local rows = jpRenderParty(f)
  -- Room for the roster plus a bottom strip for the teleport button and note.
  f:SetHeight(MP_PAD + 102 + math.max(1, rows) * 15 + 44)
  f:Show()
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
  renderJoinFrame(dungeon, title, leader)
end

-- Preview frame for positioning. "Preview" isn't a real dungeon, so no teleport
-- matches it.
ns.previewFrame("join popup",
  function() renderJoinFrame("Preview", nil, nil) end,
  function() if jpFrame then jpFrame:Hide() end end)

local joinEvents = CreateFrame("Frame")
for _, ev in ipairs({ "LFG_LIST_JOINED_GROUP", "GROUP_LEFT", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
  pcall(joinEvents.RegisterEvent, joinEvents, ev)
end
joinEvents:SetScript("OnEvent", function(_, event, arg1)
  if event == "LFG_LIST_JOINED_GROUP" then
    pcall(onJoinedGroup, arg1)
  elseif event == "GROUP_ROSTER_UPDATE" then
    -- People joining or leaving while the popup is up: redraw the roster and
    -- re-size to it. Left alone when the popup isn't showing.
    if jpFrame and jpFrame:IsShown() then
      local rows = jpRenderParty(jpFrame)
      jpFrame:SetHeight(MP_PAD + 102 + math.max(1, rows) * 15 + 44)
    end
  elseif event == "GROUP_LEFT" then
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
