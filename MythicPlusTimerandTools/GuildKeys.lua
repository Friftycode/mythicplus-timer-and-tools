local _, ns = ...

local GOLD, GREY, WHITE, ENDC, MP_PAD, MP_LINE = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC, ns.PAD, ns.LINE
local cfg, isSecret, mptPrint = ns.cfg, ns.isSecret, ns.print
local mpClassColoredName = ns.classColoredName

-- ── Guild keys this week ─────────────────────────────────────────────────
-- The guild's best Mythic+ runs this reset, from C_ChallengeMode.GetGuildLeaders.
-- The server fills the list per dungeon on request, so opening the window asks for
-- every dungeon in the current rotation and redraws as the answers land on
-- CHALLENGE_MODE_LEADERS_UPDATE. Until they do, the honest state is "asking",
-- not an empty list.

local GUILD_ROWS = 5
local guildFrame

local function guildLeaders()
  if not (C_ChallengeMode and C_ChallengeMode.GetGuildLeaders) then return {} end
  local ok, list = pcall(C_ChallengeMode.GetGuildLeaders)
  if not (ok and type(list) == "table") then return {} end
  local out = {}
  for _, e in ipairs(list) do
    if type(e) == "table" and type(e.keystoneLevel) == "number" and not isSecret(e.keystoneLevel) then
      out[#out + 1] = e
    end
  end
  -- Highest key first; the API doesn't promise an order.
  table.sort(out, function(a, b) return (a.keystoneLevel or 0) > (b.keystoneLevel or 0) end)
  return out
end

-- Asks the server for every dungeon in the current rotation. Cheap and
-- idempotent; the answers arrive asynchronously as CHALLENGE_MODE_LEADERS_UPDATE.
local function requestGuildLeaders()
  if not (C_ChallengeMode and C_ChallengeMode.RequestLeaders and C_ChallengeMode.GetMapTable) then return end
  local ok, maps = pcall(C_ChallengeMode.GetMapTable)
  if not (ok and type(maps) == "table") then return end
  for _, mapID in ipairs(maps) do
    if type(mapID) == "number" then pcall(C_ChallengeMode.RequestLeaders, mapID) end
  end
end

local function guildDungeonName(mapID)
  if not (mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
  local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
  return (ok and type(name) == "string" and name ~= "") and name or nil
end

-- Narrow enough to clear the centered "Mythic+ Rating" text in ChallengesFrame.
local GUILD_W = 208
-- Row columns: key level (right-aligned), dungeon, who ran it. The dungeon is
-- named exactly as the client names it (no abbreviation table to maintain), so
-- it gets the widest column and a long name clips.
local GUILD_LEVEL_W, GUILD_DUNGEON_W, GUILD_COL_GAP = 24, 96, 4
-- Fixed height: always room for GUILD_ROWS, so the box doesn't jump as keys land.
local GUILD_H = MP_PAD + 16 + GUILD_ROWS * MP_LINE + MP_PAD
local guildHooked = false
local ensureGuildFrame, renderGuildFrame  -- mutually recursive

-- Party roster on hover, from GetGuildLeaders' own .members list. Class-colored;
-- secret values skipped.
local function guildRowOnEnter(rowFrame)
  local members = rowFrame.members
  if type(members) ~= "table" or #members == 0 then return end
  GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
  GameTooltip:AddLine(GOLD .. "+" .. (rowFrame.level or "?") .. ENDC
    .. " " .. WHITE .. (rowFrame.dungeon or "?") .. ENDC)
  for _, m in ipairs(members) do
    if type(m) == "table" and type(m.name) == "string" and not isSecret(m.name) then
      GameTooltip:AddLine(mpClassColoredName(m.name, m.classFileName))
    end
  end
  GameTooltip:Show()
end

-- Builds the panel inside ChallengesFrame, lower-left. Nil until that frame exists.
function ensureGuildFrame()
  if guildFrame then return guildFrame end
  if not ChallengesFrame then return nil end
  local f = CreateFrame("Frame", "MythicPlusTimerGuildFrame", ChallengesFrame, "BackdropTemplate")
  f:SetSize(GUILD_W, GUILD_H)
  f:SetFrameStrata("HIGH")
  f:ClearAllPoints()
  if ChallengesFrame.DungeonIcons and ChallengesFrame.DungeonIcons[1] then
    f:SetPoint("BOTTOMLEFT", ChallengesFrame.DungeonIcons[1], "TOPLEFT", 0, 16)
  else
    f:SetPoint("TOPLEFT", ChallengesFrame, "TOPLEFT", 14, -60)
  end
  if f.SetBackdrop then
    -- Same warm near-black + armory-gold border the M+ overlay uses, so the
    -- panel reads as part of the same addon. Fully opaque here (unlike the
    -- floating overlays): this panel sits inside ChallengesFrame, so anything
    -- another addon parents there must be hidden behind it, not bleed through.
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.04, 0.03, 1)
    f:SetBackdropBorderColor(0.88, 0.65, 0.31, 0.9)
  end

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD)
  f.title:SetText(GOLD .. "Guild keys this week" .. ENDC)

  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.note:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD - 16)
  f.note:SetJustifyH("LEFT")
  f.note:SetWidth(GUILD_W - MP_PAD * 2)

  f.rows = {}
  local inner = GUILD_W - MP_PAD * 2
  local dungeonX = MP_PAD + GUILD_LEVEL_W + GUILD_COL_GAP
  local whoX = dungeonX + GUILD_DUNGEON_W + GUILD_COL_GAP
  local function rowCell(top, x, width, justify)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, top)
    fs:SetJustifyH(justify)
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    return fs
  end
  for i = 1, GUILD_ROWS do
    local top = -MP_PAD - 16 - (i - 1) * MP_LINE
    local level = rowCell(top, MP_PAD, GUILD_LEVEL_W, "RIGHT")
    local dungeon = rowCell(top, dungeonX, GUILD_DUNGEON_W, "LEFT")
    -- Whatever is left over, and a long name simply clips.
    local who = rowCell(top, whoX, inner - (whoX - MP_PAD), "LEFT")
    -- A transparent mouse-catcher over the whole row so hovering it can show the
    -- key's party (the font strings themselves don't take mouse input). Hidden
    -- until renderGuildFrame gives the row a run to describe.
    local rowFrame = CreateFrame("Frame", nil, f)
    rowFrame:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, top)
    rowFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -MP_PAD, top)
    rowFrame:SetHeight(MP_LINE)
    rowFrame:EnableMouse(true)
    rowFrame:SetScript("OnEnter", guildRowOnEnter)
    rowFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rowFrame:Hide()
    f.rows[i] = { level = level, dungeon = dungeon, who = who, frame = rowFrame }
  end

  f:Hide()
  guildFrame = f

  -- The panel is a child of ChallengesFrame, so it hides with the window on its
  -- own; the OnShow hook is what re-asks the server and redraws on each open.
  if not guildHooked then
    guildHooked = true
    ChallengesFrame:HookScript("OnShow", function()
      if not guildFrame then return end
      if not cfg("guildkeys") then guildFrame:Hide() return end
      guildFrame:Show()
      renderGuildFrame()
      requestGuildLeaders()
    end)
  end
  return f
end

function renderGuildFrame()
  local f = ensureGuildFrame()
  if not f then return end
  for _, r in ipairs(f.rows) do
    r.level:SetText(""); r.dungeon:SetText(""); r.who:SetText("")
    -- Drop any stale roster + hide the mouse-catcher so an emptied row can't
    -- still pop last week's party on hover.
    if r.frame then r.frame.members = nil; r.frame:Hide() end
  end

  if not IsInGuild() then
    f.note:SetText(GREY .. "You are not in a guild." .. ENDC)
    return
  end

  local list = guildLeaders()
  if #list == 0 then
    -- Deliberately NOT "no runs this week": an empty list this early just means
    -- the server hasn't answered yet, and claiming the guild timed nothing
    -- would be inventing a fact we don't have.
    f.note:SetText(GREY .. "No keys are"
      .. " recorded yet this week." .. ENDC)
    return
  end
  f.note:SetText("")

  for i = 1, math.min(GUILD_ROWS, #list) do
    local e = list[i]
    local dungeon = guildDungeonName(e.mapChallengeModeID) or "?"
    local who = (type(e.name) == "string" and not isSecret(e.name)) and e.name or "?"
    f.rows[i].level:SetText(GOLD .. "+" .. (e.keystoneLevel or "?") .. ENDC)
    f.rows[i].dungeon:SetText(WHITE .. dungeon .. ENDC)
    f.rows[i].who:SetText(mpClassColoredName(who, e.classFileName))
    -- Stash the run's party on the row's mouse-catcher for the hover roster.
    local rf = f.rows[i].frame
    if rf then
      rf.members = e.members
      rf.level = e.keystoneLevel
      rf.dungeon = dungeon
      rf:Show()
    end
  end
end


local guildEvents = CreateFrame("Frame")
guildEvents:RegisterEvent("CHALLENGE_MODE_LEADERS_UPDATE")
guildEvents:SetScript("OnEvent", function()
  if guildFrame and guildFrame:IsShown() then renderGuildFrame() end
end)

-- Create and attach the panel as soon as Blizzard's load-on-demand challenges
-- UI is available: on its ADDON_LOADED, or right away at login if something
-- else pulled it in first.
local guildLoader = CreateFrame("Frame")
guildLoader:RegisterEvent("ADDON_LOADED")
guildLoader:RegisterEvent("PLAYER_LOGIN")
guildLoader:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_ChallengesUI" then return end
  if ChallengesFrame and ensureGuildFrame() then self:UnregisterAllEvents() end
end)

-- ── What this feature hands back ─────────────────────────────────────────

-- The panel lives inside the Mythic+ Dungeons window, so this toggles it there
-- (or points the player at the window if it isn't open yet).
ns.command("guild", "toggle the guild keys panel", function()
  local f = ensureGuildFrame()
  if not f then
    mptPrint("open the Mythic+ Dungeons window to see guild keys this week.")
    return
  end
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
    renderGuildFrame()
    requestGuildLeaders()
  end
end)

ns.onOptionChanged("guildkeys", function()
  if not guildFrame then return end
  if cfg("guildkeys") then
    guildFrame:Show()
    renderGuildFrame()
    requestGuildLeaders()
  else
    guildFrame:Hide()
  end
end)
