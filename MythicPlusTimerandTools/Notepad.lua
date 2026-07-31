local _, ns = ...

local GOLD, GREY, WHITE, ENDC, MP_PAD = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC, ns.PAD
local GOLD_RGB = ns.GOLD_RGB
local cfg, setCfg = ns.cfg, ns.setCfg

-- ── Notes ────────────────────────────────────────────────────────────────
-- A note window tied to the dungeon you are in: one general dungeon note plus a
-- note per boss. The dungeon note can be edited any time; a boss note only
-- outside its fight, so it stays a fixed reference while the boss is up. With
-- "Follow the fight" on it opens a boss's tab as you near or pull it and returns
-- to the dungeon tab afterwards. Notes render simple markdown when not being
-- edited, and can be prepared ahead of time from the Note settings tab. Text is
-- account-wide (MythicPlusTimerNotes), keyed by the Encounter Journal instance
-- id so the in-dungeon window and the prepared notes are the same store.

local NP_W, NP_H, NP_COL_W = 360, 260, 100
-- Bounds for the draggable size and section-column width. Kept in step with the
-- clamps in Core's cleanProfile.
local NP_MIN_W, NP_MIN_H, NP_MAX_W, NP_MAX_H = 260, 160, 900, 800
local NP_COL_MIN, NP_COL_MAX = 60, 260
local NP_GAP = 14  -- space between the section column and the note
local MD_FONT = "Fonts\\FRIZQT__.TTF"
local npFrame, npCurrentID, npLoading
local npKeyStarted = false
local npSection = "dungeon"  -- "dungeon" or a boss key

-- ── Note storage ─────────────────────────────────────────────────────────
-- MythicPlusTimerNotes[journalInstanceID] = { dungeon = "text", bosses = { [key] = "text" } }.

local function npNotes()
  if type(MythicPlusTimerNotes) ~= "table" then MythicPlusTimerNotes = {} end
  return MythicPlusTimerNotes
end

local function npNormalize(e)
  if type(e) == "string" then return { dungeon = e, bosses = {} } end
  if type(e) ~= "table" then return { dungeon = "", bosses = {} } end
  local dungeon = type(e.dungeon) == "string" and e.dungeon or ""
  local bosses = {}
  if type(e.bosses) == "table" then
    for k, v in pairs(e.bosses) do
      if type(v) == "string" and v ~= "" then bosses[tostring(k)] = v end
    end
  end
  return { dungeon = dungeon, bosses = bosses }
end

local function npEntry(key)
  local n = npNotes()
  local e = npNormalize(n[key])
  n[key] = e
  return e
end

local function npSanitize()
  local clean = {}
  for k, v in pairs(npNotes()) do
    local e = npNormalize(v)
    if e.dungeon ~= "" or next(e.bosses) then clean[k] = e end
  end
  MythicPlusTimerNotes = clean
end

-- ── Encounter Journal (dungeon list, bosses) ─────────────────────────────

local npJournalTried = false
local function npLoadJournal()
  if npJournalTried then return end
  npJournalTried = true
  if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal") end
end

local npBossCache = {}
local function npBossesFor(journalID)
  if not journalID then return {} end
  if npBossCache[journalID] then return npBossCache[journalID] end
  local list = {}
  if not (EJ_GetEncounterInfoByIndex and EJ_SelectInstance) then return list end
  npLoadJournal()
  pcall(EJ_SelectInstance, journalID)
  for i = 1, 20 do
    local ok, name, _, _, _, _, _, dungeonEncounterID = pcall(EJ_GetEncounterInfoByIndex, i, journalID)
    if not (ok and type(name) == "string" and name ~= "") then break end
    list[#list + 1] = { key = "b" .. tostring(dungeonEncounterID or i), name = name }
  end
  if #list > 0 then npBossCache[journalID] = list end
  return list
end

-- The instance's name for any journal id, even one no longer in the current
-- tiers, so a saved note for a rotated-out dungeon can still be labelled.
local function npResolveDungeonName(instID)
  if not (EJ_SelectInstance and EJ_GetInstanceInfo) then return nil end
  npLoadJournal()
  if not pcall(EJ_SelectInstance, instID) then return nil end
  local ok, name = pcall(EJ_GetInstanceInfo)
  if ok and type(name) == "string" and name ~= "" then return name end
  return nil
end

-- The current tiers' dungeons, scanned once (the journal doesn't change mid
-- session). Saved-but-rotated-out dungeons are added on top per call, so a note
-- saved this session for an out-of-tier dungeon shows up without a reload.
local npTierCache
local function npScanTiers()
  local out = {}
  if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return out end
  npLoadJournal()
  local ok, numTiers = pcall(EJ_GetNumTiers)
  if not (ok and type(numTiers) == "number" and numTiers > 0) then return out end
  local seen = {}
  for tier = numTiers, math.max(1, numTiers - 1), -1 do
    pcall(EJ_SelectTier, tier)
    for i = 1, 50 do
      local ok2, instID, name = pcall(EJ_GetInstanceByIndex, i, false)
      if not (ok2 and type(instID) == "number" and type(name) == "string") then break end
      if not seen[instID] then
        seen[instID] = true
        out[#out + 1] = { key = instID, name = name }
      end
    end
  end
  return out
end

local function npDungeonList()
  if not npTierCache then
    local scanned = npScanTiers()
    if #scanned > 0 then npTierCache = scanned end
  end
  local out, seen = {}, {}
  for _, d in ipairs(npTierCache or {}) do
    out[#out + 1] = { key = d.key, name = d.name }
    seen[d.key] = true
  end
  -- Dungeons that have saved notes but have rotated out of the current tiers are
  -- kept in the list so those notes stay reachable (and visibly are not lost)
  -- until the dungeon returns. Notes are never deleted for being out of season.
  for key, entry in pairs(npNotes()) do
    local id = tonumber(key) or key
    if type(id) == "number" and not seen[id] then
      local e = npNormalize(entry)
      if e.dungeon ~= "" or next(e.bosses) then
        local name = npResolveDungeonName(id)
        if name then
          seen[id] = true
          out[#out + 1] = { key = id, name = name, saved = true }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- ── Where the player is ──────────────────────────────────────────────────

local function npInstanceType()
  local ok, _, itype = pcall(GetInstanceInfo)
  return ok and itype or nil
end

local function npInDungeon()
  return npInstanceType() == "party"
end

local function npCurrentDungeonKey()
  if C_Map and C_Map.GetBestMapForUnit and EJ_GetInstanceForMap then
    local okM, uiMap = pcall(C_Map.GetBestMapForUnit, "player")
    if okM and uiMap then
      local okI, instID = pcall(EJ_GetInstanceForMap, uiMap)
      if okI and type(instID) == "number" and instID > 0 then return instID end
    end
  end
  local ok, _, _, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
  return (ok and type(instanceID) == "number" and instanceID > 0) and instanceID or nil
end

local function npKeyActiveNow()
  if not (C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID) then return false end
  local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
  return ok and type(id) == "number" and id > 0
end

local function npShouldShow()
  if not cfg("notepad") then return false end
  -- "everywhere": up wherever the note is on, in or out of a dungeon. The other
  -- two are dungeon-only: "indungeon" the whole visit, "hideatstart" from
  -- entering until a keystone starts, then hidden for the run.
  local mode = cfg("notepadmode")
  if mode == "everywhere" then return true end
  if not npInDungeon() then return false end
  if mode == "hideatstart" then
    return not (npKeyStarted or npKeyActiveNow())
  end
  return true
end

local function npInEncounter()
  return type(IsEncounterInProgress) == "function" and IsEncounterInProgress() and true or false
end

local function npCanEdit(section)
  if section == "dungeon" then return true end
  return not npInEncounter()
end

-- ── Shared note data (used by the prepare-ahead editor too) ───────────────

function ns.noteDungeonList() return npDungeonList() end

function ns.noteSectionList(key)
  local list = { { key = "dungeon", name = "Dungeon" } }
  for _, b in ipairs(npBossesFor(key)) do list[#list + 1] = b end
  return list
end

function ns.noteGet(key, section)
  if not key then return "" end
  local e = npEntry(key)
  if section == "dungeon" then return e.dungeon end
  return e.bosses[section] or ""
end

function ns.noteSet(key, section, text)
  if not key then return end
  local e = npEntry(key)
  if section == "dungeon" then
    e.dungeon = text or ""
  else
    e.bosses[section] = (text and text ~= "") and text or nil
  end
end

-- ── Markdown ─────────────────────────────────────────────────────────────
-- A light renderer for the display side: line-level headings and bullets at
-- real font sizes, plus inline **bold**. The stored text keeps the raw markdown;
-- only the view is rendered, so the syntax never shows in the window.
local HEAD_SIZE = { 18, 16, 14 }  -- #, ##, ###
local BODY_SIZE = 12
local BODY_RGB = { 0.86, 0.86, 0.86 }
local QUOTE_RGB = { 0.70, 0.70, 0.55 }

-- Inline styles, applied to every rendered line.
--   **bold**  __bold__      -> bright white
--   *italic*  _italic_      -> soft gold
--   `code`                  -> light blue
--   ~~strike~~              -> dim grey
-- Bold runs first so its inner text isn't eaten by the single-mark italic rule.
local function npInline(s)
  s = s:gsub("%*%*(.-)%*%*", "|cffffffff%1|r")
  s = s:gsub("__(.-)__", "|cffffffff%1|r")
  s = s:gsub("`(.-)`", "|cff9ecbff%1|r")
  s = s:gsub("~~(.-)~~", "|cff8a8a8a%1|r")
  s = s:gsub("%*(.-)%*", "|cffe6d3a3%1|r")
  s = s:gsub("_(.-)_", "|cffe6d3a3%1|r")
  return s
end

local function npIsRule(line)
  return line:match("^%s*%-%-%-+%s*$") or line:match("^%s*%*%*%*+%s*$")
    or line:match("^%s*___+%s*$")
end

-- Renders markdown `text` into pooled font strings (and rule textures) stacked in
-- `container`, wrapping to `width`. Returns the height used.
local function npRenderMarkdown(container, text, width)
  container.mdLines = container.mdLines or {}
  container.mdRules = container.mdRules or {}
  for _, fs in ipairs(container.mdLines) do fs:Hide() end
  for _, tx in ipairs(container.mdRules) do tx:Hide() end
  local used, rules, y = 0, 0, 0

  local function put(str, size, rgb, indent)
    used = used + 1
    local fs = container.mdLines[used]
    if not fs then
      fs = container:CreateFontString(nil, "OVERLAY")
      fs:SetJustifyH("LEFT")
      fs:SetJustifyV("TOP")
      fs:SetWordWrap(true)
      fs:SetSpacing(2)
      container.mdLines[used] = fs
    end
    fs:SetFont(MD_FONT, size, "")
    fs:SetTextColor(rgb[1], rgb[2], rgb[3])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", container, "TOPLEFT", indent or 0, -y)
    fs:SetWidth(width - (indent or 0))
    fs:SetText(str ~= "" and str or " ")
    fs:Show()
    local h = fs:GetStringHeight()
    if type(h) ~= "number" or h < size then h = size end
    y = y + h + 4
  end

  local function horizontalRule()
    rules = rules + 1
    local tx = container.mdRules[rules]
    if not tx then tx = container:CreateTexture(nil, "ARTWORK"); container.mdRules[rules] = tx end
    tx:ClearAllPoints()
    tx:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(y + 5))
    tx:SetSize(width, 1)
    tx:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.4)
    tx:Show()
    y = y + 14
  end

  for raw in (text .. "\n"):gmatch("(.-)\n") do
    local hashes, hrest = raw:match("^(#+)%s+(.*)")
    local quote = raw:match("^>%s?(.*)")
    local numlabel, numrest = raw:match("^(%d+%.)%s+(.*)")
    local bullet = raw:match("^[%-%*%+]%s+(.*)")
    if npIsRule(raw) then
      horizontalRule()
    elseif hashes then
      put(npInline(hrest), HEAD_SIZE[math.min(#hashes, 3)], GOLD_RGB)
    elseif quote then
      put("\226\148\130 " .. npInline(quote), BODY_SIZE, QUOTE_RGB, 6)
    elseif numlabel then
      put(numlabel .. " " .. npInline(numrest), BODY_SIZE, BODY_RGB, 8)
    elseif bullet then
      put("\226\128\162 " .. npInline(bullet), BODY_SIZE, BODY_RGB, 8)
    else
      put(npInline(raw), BODY_SIZE, BODY_RGB)
    end
  end
  container:SetHeight(math.max(1, y))
  return y
end

-- ── Frame ────────────────────────────────────────────────────────────────

local function npIsLocked() return cfg("notepadlocked") and true or false end

local function npApplyLock(f)
  if f.lockIcon then
    f.lockIcon:SetNormalTexture(npIsLocked()
      and "Interface\\Buttons\\LockButton-Locked-Up"
      or "Interface\\Buttons\\LockButton-Unlocked-Up")
  end
end

local function npMenuShown() return cfg("notepadmenu") ~= false end

-- The section column's width, clamped, from the value the divider drag saved.
local function npColW()
  return math.max(NP_COL_MIN, math.min(NP_COL_MAX, cfg("notepadcolw") or NP_COL_W))
end

-- Slim scrollbar, shown only when the content overflows.
local function npUpdateScroll(f)
  local child = f.scroll:GetScrollChild()
  local childH = (child and child:GetHeight()) or 0
  local viewH = f.scroll:GetHeight()
  local range = math.max(0, childH - viewH)
  f.scrollRange = range
  if range > 1 then
    local v = math.min(f.scroll:GetVerticalScroll(), range)
    f.scroll:SetVerticalScroll(v)
    f.sbar:SetMinMaxValues(0, range)
    f.sbar:SetValue(v)
    if type(ns.sizeScrollThumb) == "function" then ns.sizeScrollThumb(f.thumb, viewH, childH) end
    f.sbar:Show()
  else
    f.scroll:SetVerticalScroll(0)
    f.sbar:SetMinMaxValues(0, 0)
    f.sbar:Hide()
  end
end

-- Puts the note back at the very top of the scroll view. Called whenever a note
-- is (re)opened, so a long note starts at its first line rather than wherever the
-- last one was scrolled to.
local function npScrollTop(f)
  f.scroll:SetVerticalScroll(0)
  if f.sbar then f.sbar:SetValue(0) end
end

-- Shows or collapses the section column and re-flows the note into the freed
-- width. The arrow points left when the column is up (click to hide) and right
-- when it is down (click to show).
-- Lays out the column, the note area, and the note width for the current frame
-- size and column width. Called when the column is toggled, the frame is
-- resized, or the divider is dragged. The note reclaims the column's space when
-- it is collapsed. 30px on the right leaves room for the scrollbar and inset.
local function npApplyMenu(f)
  if not f.view then return end  -- fires during the creation-time SetSize
  local shown = npMenuShown()
  local colW = npColW()
  local frameW = f:GetWidth() or NP_W

  if f.col then f.col:SetShown(shown); f.col:SetWidth(colW) end
  if f.colRule then f.colRule:SetShown(shown) end
  if f.colDrag then f.colDrag:SetShown(shown) end
  if f.menuToggle and f.menuToggle.tex then
    f.menuToggle.tex:SetRotation(shown and math.pi or 0)
  end

  f.scroll:ClearAllPoints()
  f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, MP_PAD + 12)
  f.hint:ClearAllPoints()
  if shown then
    f.scroll:SetPoint("TOPLEFT", f.col, "TOPRIGHT", NP_GAP, 0)
    f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MP_PAD + colW + NP_GAP, MP_PAD - 2)
    f.contentW = frameW - MP_PAD - colW - NP_GAP - 30
  else
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -26)
    f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MP_PAD, MP_PAD - 2)
    f.contentW = frameW - MP_PAD - 30
  end
  f.contentW = math.max(80, f.contentW)
  if f.view then f.view:SetWidth(f.contentW) end
  if f.edit then f.edit:SetWidth(f.contentW) end
  if not f.editing and f.renderView then f.renderView() else npUpdateScroll(f) end
end

local function npBuildSections(f)
  f.sections = ns.noteSectionList(npCurrentID)
  f.sectionButtons = f.sectionButtons or {}
  for _, btn in ipairs(f.sectionButtons) do btn:Hide() end
  local y = 0
  for i, s in ipairs(f.sections) do
    local btn = f.sectionButtons[i]
    if not btn then
      btn = CreateFrame("Button", nil, f.col)
      btn:SetHeight(18)
      btn.bg = btn:CreateTexture(nil, "BACKGROUND")
      btn.bg:SetAllPoints()
      btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
      btn.hl:SetAllPoints()
      btn.hl:SetColorTexture(1, 1, 1, 0.10)
      btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.label:SetPoint("LEFT", btn, "LEFT", 6, 0)
      btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
      btn.label:SetJustifyH("LEFT")
      btn.label:SetWordWrap(false)
      f.sectionButtons[i] = btn
    end
    btn.section = s.key
    btn.plainName = s.name
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", f.col, "TOPLEFT", 0, y)
    btn:SetPoint("TOPRIGHT", f.col, "TOPRIGHT", 0, y)
    btn:SetScript("OnClick", function() f.selectSection(s.key) end)
    btn:Show()
    y = y - 20
  end
end

local function npHighlightSections(f)
  for _, btn in ipairs(f.sectionButtons or {}) do
    if btn.section == npSection then
      btn.bg:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.30)
      btn.label:SetText(GOLD .. (btn.plainName or "") .. ENDC)
    else
      btn.bg:SetColorTexture(1, 1, 1, 0.04)
      btn.label:SetText(WHITE .. (btn.plainName or "") .. ENDC)
    end
  end
end

local ensureNpFrame

ensureNpFrame = function()
  if npFrame then return npFrame end
  local f = CreateFrame("Frame", "MythicPlusTimerNotepad", UIParent, "BackdropTemplate")
  local startW = math.max(NP_MIN_W, math.min(NP_MAX_W, cfg("notepadw") or NP_W))
  local startH = math.max(NP_MIN_H, math.min(NP_MAX_H, cfg("notepadh") or NP_H))
  f:SetSize(startW, startH)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if npIsLocked() then return end
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.savePosition(self, "notepadpoint")
  end)
  f:SetClampedToScreen(true)
  ns.restorePosition(f, "notepadpoint", "CENTER", 300, 0)
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

  -- A toggle for the section column, top-left, so the note can use the full width.
  f.menuToggle = CreateFrame("Button", nil, f)
  f.menuToggle:SetSize(16, 16)
  f.menuToggle:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD - 2, -7)
  f.menuToggle:SetAlpha(0.6)
  f.menuToggle.tex = f.menuToggle:CreateTexture(nil, "OVERLAY")
  f.menuToggle.tex:SetAllPoints()
  f.menuToggle.tex:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  f.menuToggle:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(GOLD .. "Show or hide the section list" .. ENDC)
    GameTooltip:Show()
  end)
  f.menuToggle:SetScript("OnLeave", function(self) self:SetAlpha(0.6); GameTooltip:Hide() end)
  f.menuToggle:SetScript("OnClick", function()
    setCfg("notepadmenu", not npMenuShown())
    npApplyMenu(f)
  end)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD + 18, -8)
  f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -26, -8)
  f.title:SetJustifyH("LEFT")
  f.title:SetText(GOLD .. "Notes" .. ENDC)

  f.lockIcon = CreateFrame("Button", nil, f)
  f.lockIcon:SetSize(16, 16)
  f.lockIcon:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  f.lockIcon:SetAlpha(0.5)
  f.lockIcon:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
  f.lockIcon:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
  f.lockIcon:SetScript("OnClick", function()
    setCfg("notepadlocked", not npIsLocked())
    npApplyLock(f)
  end)

  f.col = CreateFrame("Frame", nil, f)
  f.col:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -26)
  f.col:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MP_PAD, MP_PAD)
  f.col:SetWidth(npColW())

  f.colRule = f:CreateTexture(nil, "ARTWORK")
  f.colRule:SetWidth(1)
  f.colRule:SetPoint("TOPLEFT", f.col, "TOPRIGHT", 6, 0)
  f.colRule:SetPoint("BOTTOMLEFT", f.col, "BOTTOMRIGHT", 6, 0)
  f.colRule:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.3)

  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MP_PAD + NP_COL_W + 14, MP_PAD - 2)
  f.hint:SetText("")

  -- Scroll area. Its left edge and content width follow the section column: with
  -- it collapsed the note reclaims the column's space. npApplyMenu re-anchors both.
  local contentW = NP_W - NP_COL_W - MP_PAD - 44
  f.scroll = CreateFrame("ScrollFrame", nil, f)
  f.scroll:SetPoint("TOPLEFT", f.col, "TOPRIGHT", 14, 0)
  f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, MP_PAD + 12)
  f.scroll:EnableMouse(true)
  f.scroll:EnableMouseWheel(true)

  f.sbar = CreateFrame("Slider", nil, f)
  f.sbar:SetWidth(5)
  f.sbar:SetPoint("TOPLEFT", f.scroll, "TOPRIGHT", 4, 0)
  f.sbar:SetPoint("BOTTOMLEFT", f.scroll, "BOTTOMRIGHT", 4, 0)
  f.sbar:SetOrientation("VERTICAL")
  f.sbar:SetMinMaxValues(0, 0)
  f.sbar:SetValueStep(1)
  f.sbar:SetObeyStepOnDrag(true)
  local track = f.sbar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.05)
  f.thumb = f.sbar:CreateTexture(nil, "OVERLAY")
  f.thumb:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.55)
  f.thumb:SetSize(5, 24)
  f.sbar:SetThumbTexture(f.thumb)
  f.sbar:SetScript("OnValueChanged", function(self, v) f.scroll:SetVerticalScroll(v) end)
  f.sbar:Hide()

  f.scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = f.scrollRange or 0
    if range <= 0 then return end
    local v = math.min(range, math.max(0, self:GetVerticalScroll() - delta * 24))
    self:SetVerticalScroll(v)
    f.sbar:SetValue(v)
  end)

  -- View: rendered markdown (the scroll child when not editing).
  f.view = CreateFrame("Frame", nil, f.scroll)
  f.view:SetSize(contentW, 1)

  -- Edit: raw text (the scroll child while editing).
  f.edit = CreateFrame("EditBox", nil, f.scroll)
  f.edit:SetMultiLine(true)
  f.edit:SetAutoFocus(false)
  f.edit:SetFontObject("ChatFontNormal")
  f.edit:SetWidth(contentW)
  f.edit:SetTextInsets(0, 0, 0, 0)
  f.edit:Hide()

  f.contentW = contentW

  local function renderView()
    npRenderMarkdown(f.view, npCurrentID and ns.noteGet(npCurrentID, npSection) or "", f.contentW)
    npUpdateScroll(f)
  end
  f.renderView = renderView

  local function applyEditable()
    if f.editing then
      f.hint:SetText(GREY .. "Editing - click away to save" .. ENDC)
    elseif npCanEdit(npSection) then
      f.hint:SetText(GREY .. "Click to edit" .. ENDC)
    else
      f.hint:SetText(GREY .. "Read-only during the fight" .. ENDC)
    end
  end
  f.applyEditable = applyEditable

  local function toView()
    f.editing = false
    f.edit:Hide()
    f.scroll:SetScrollChild(f.view)
    f.view:Show()
    renderView()
    applyEditable()
  end

  local function commitEdit()
    if not f.editing then return end
    if npCurrentID and npCanEdit(npSection) then
      ns.noteSet(npCurrentID, npSection, f.edit:GetText())
    end
    f.edit:ClearFocus()
    toView()
  end
  f.commitEdit = commitEdit

  local function enterEdit()
    if f.editing or not npCanEdit(npSection) then return end
    f.editing = true
    f.view:Hide()
    npLoading = true
    f.edit:SetText(npCurrentID and ns.noteGet(npCurrentID, npSection) or "")
    -- SetText leaves the cursor at the end, which scrolls a long note to the
    -- bottom; put the cursor back at the start so editing begins at the top.
    f.edit:SetCursorPosition(0)
    npLoading = false
    f.scroll:SetScrollChild(f.edit)
    f.edit:Show()
    f.edit:SetFocus()
    npUpdateScroll(f)
    npScrollTop(f)
    applyEditable()
  end
  f.enterEdit = enterEdit

  f.scroll:SetScript("OnMouseUp", function() enterEdit() end)
  f.edit:SetScript("OnEscapePressed", function() commitEdit() end)
  f.edit:SetScript("OnEditFocusLost", function() commitEdit() end)
  f.edit:SetScript("OnTextChanged", function() npUpdateScroll(f) end)
  -- Keep the cursor in view while typing.
  f.edit:SetScript("OnCursorChanged", function(_, _, cy, _, ch)
    local top = -cy
    local vs = f.scroll:GetVerticalScroll()
    local viewH = f.scroll:GetHeight()
    if top < vs then
      f.scroll:SetVerticalScroll(top)
    elseif top + ch > vs + viewH then
      f.scroll:SetVerticalScroll(top + ch - viewH)
    end
    f.sbar:SetValue(f.scroll:GetVerticalScroll())
  end)

  local function loadSection()
    commitEdit()
    f.editing = false
    f.edit:Hide()
    f.scroll:SetScrollChild(f.view)
    f.view:Show()
    local name = "Notes"
    for _, s in ipairs(f.sections or {}) do if s.key == npSection then name = s.name end end
    f.title:SetText(GOLD .. name .. ENDC)
    npHighlightSections(f)
    renderView()
    npScrollTop(f)  -- a freshly opened section starts at its top, not last note's scroll
    applyEditable()
  end
  f.loadSection = loadSection

  f.selectSection = function(section)
    if section == npSection and f.editing then return end
    commitEdit()
    npSection = section
    loadSection()
  end

  -- A drag handle over the divider between the column and the note, to set how
  -- wide the section list is. Tracks the cursor while held, clamped, and saves.
  f.colDrag = CreateFrame("Button", nil, f)
  f.colDrag:SetWidth(9)
  f.colDrag:SetPoint("TOP", f.colRule, "TOP", 0, 2)
  f.colDrag:SetPoint("BOTTOM", f.colRule, "BOTTOM", 0, -2)
  f.colDrag:EnableMouse(true)
  f.colDrag:SetScript("OnEnter", function(self)
    if npIsLocked() then return end
    self.glow = self.glow or self:CreateTexture(nil, "HIGHLIGHT")
    self.glow:SetAllPoints()
    self.glow:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.25)
  end)
  f.colDrag:SetScript("OnMouseDown", function(self)
    if npIsLocked() or not npMenuShown() then return end
    self.dragging = true
  end)
  f.colDrag:SetScript("OnMouseUp", function(self) self.dragging = false end)
  f.colDrag:SetScript("OnUpdate", function(self)
    if not self.dragging then return end
    local scale, left = f:GetEffectiveScale(), f:GetLeft()
    if not (scale and scale > 0 and left) then return end
    local cx = (GetCursorPosition()) / scale
    local w = math.max(NP_COL_MIN, math.min(NP_COL_MAX, cx - left - MP_PAD))
    setCfg("notepadcolw", w)
    npApplyMenu(f)
  end)

  -- Corner resize grip, bottom-right. Saves the size and re-flows the note.
  f.resize = CreateFrame("Button", nil, f)
  f.resize:SetSize(16, 16)
  f.resize:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
  f.resize:SetAlpha(0.6)
  f.resize.tex = f.resize:CreateTexture(nil, "OVERLAY")
  f.resize.tex:SetAllPoints()
  f.resize.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.resize:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
  f.resize:SetScript("OnLeave", function(self) self:SetAlpha(0.6) end)
  f.resize:SetScript("OnMouseDown", function()
    if npIsLocked() then return end
    -- Pin the top-left corner where it currently is before sizing. Without this
    -- the frame's point/center anchor fights StartSizing and the first drag
    -- makes it jump to a huge size.
    local left, top = f:GetLeft(), f:GetTop()
    if left and top then
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    f:StartSizing("BOTTOMRIGHT")
  end)
  f.resize:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    setCfg("notepadw", f:GetWidth())
    setCfg("notepadh", f:GetHeight())
    -- The anchor moved to TOPLEFT for sizing; store it back the normal way.
    ns.savePosition(f, "notepadpoint")
    npApplyMenu(f)
  end)
  if f.SetResizeBounds then
    pcall(f.SetResizeBounds, f, NP_MIN_W, NP_MIN_H, NP_MAX_W, NP_MAX_H)
  elseif f.SetMinResize then
    pcall(f.SetMinResize, f, NP_MIN_W, NP_MIN_H)
    pcall(f.SetMaxResize, f, NP_MAX_W, NP_MAX_H)
  end

  -- Re-flow the note as the frame is dragged larger or smaller.
  f:SetScript("OnSizeChanged", function() npApplyMenu(f) end)

  -- Kept usable under the edit-mode overlay so the window can still be resized
  -- and its divider dragged while the test frames are up.
  f.mptEditPassthrough = { f.resize, f.colDrag }

  npApplyLock(f)
  npApplyMenu(f)
  f:Hide()
  npFrame = f
  return f
end

local function npApply()
  if not npShouldShow() then
    if npFrame then npFrame:Hide() end
    return
  end
  local f = ensureNpFrame()
  local key = npCurrentDungeonKey()
  -- The map and Encounter Journal APIs settle a moment after zone-in, so the
  -- first pass on entering can resolve the dungeon but not its bosses yet,
  -- leaving only the Dungeon tab. Rebuild when the dungeon changes, and also
  -- once the boss tabs become available, so they fill in on entering rather
  -- than only when a keystone starts (the next thing that re-applies).
  local haveBosses = false
  for _, s in ipairs(f.sections or {}) do
    if s.key ~= "dungeon" then haveBosses = true break end
  end
  local bossesNow = key and #npBossesFor(key) > 0
  if key and (key ~= npCurrentID or (bossesNow and not haveBosses)) then
    if key ~= npCurrentID then npSection = "dungeon" end
    npCurrentID = key
    npBuildSections(f)
    f.loadSection()
  end
  npApplyLock(f)
  f:Show()
end

local function npRefreshEditable()
  if npFrame and npFrame:IsShown() then
    if npFrame.editing and not npCanEdit(npSection) then npFrame.commitEdit() end
    if npFrame.applyEditable then npFrame.applyEditable() end
  end
end

-- ── Follow the fight ─────────────────────────────────────────────────────
-- Auto-select a boss's tab as you near/pull it, and the dungeon tab otherwise.

local function npBossNear(f)
  if not f.sections then return nil end
  -- Boss section names, lower-cased, so the match is case-insensitive.
  local byName = {}
  for _, s in ipairs(f.sections) do
    if s.key ~= "dungeon" and type(s.name) == "string" then byName[s.name:lower()] = s.key end
  end
  if not next(byName) then return nil end
  local function match(unit)
    if not (UnitExists and UnitExists(unit)) then return nil end
    local ok, n = pcall(UnitName, unit)
    if not (ok and type(n) == "string") then return nil end
    n = n:lower()
    if byName[n] then return byName[n] end
    -- Boss NPCs sometimes carry a title; fall back to a name that starts with a
    -- boss's name (or vice versa).
    for name, key in pairs(byName) do
      if n:find(name, 1, true) == 1 or name:find(n, 1, true) == 1 then return key end
    end
    return nil
  end
  -- Units you'd have up as you approach, then every visible nameplate.
  for _, u in ipairs({ "target", "focus", "mouseover", "boss1", "boss2", "boss3", "boss4", "boss5" }) do
    local k = match(u)
    if k then return k end
  end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for _, p in ipairs(plates) do
        local unit = p and (p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit))
        if unit then local kk = match(unit); if kk then return kk end end
      end
    end
  end
  return nil
end

-- Nameplate/target proximity, when there is no active encounter to key off.
local function npAutoSelect()
  local f = npFrame
  if not cfg("notebossauto") or not (f and f:IsShown()) or f.editing then return end
  if npInEncounter() then return end
  local nearKey = npBossNear(f)
  if nearKey then
    if npSection ~= nearKey then f.selectSection(nearKey) end
  elseif npSection ~= "dungeon" then
    f.selectSection("dungeon")
  end
end

-- The pulled boss's own tab, straight from ENCOUNTER_START's encounter id.
local function npEncounterSelect(encounterID)
  local f = npFrame
  if not cfg("notebossauto") or not (f and f:IsShown()) then return end
  local key = "b" .. tostring(encounterID)
  for _, s in ipairs(f.sections or {}) do
    if s.key == key then f.selectSection(key); return end
  end
end

local npSince = 0
local npTicker = CreateFrame("Frame")
npTicker:SetScript("OnUpdate", function(_, elapsed)
  npSince = npSince + elapsed
  if npSince < 1 then return end
  npSince = 0
  pcall(npAutoSelect)
end)

local npEvents = CreateFrame("Frame")
npEvents:RegisterEvent("PLAYER_LOGIN")
npEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
npEvents:RegisterEvent("CHALLENGE_MODE_START")
npEvents:RegisterEvent("CHALLENGE_MODE_COMPLETED")
npEvents:RegisterEvent("CHALLENGE_MODE_RESET")
npEvents:RegisterEvent("ENCOUNTER_START")
npEvents:RegisterEvent("ENCOUNTER_END")
npEvents:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    npSanitize()
  elseif event == "CHALLENGE_MODE_START" then
    npKeyStarted = true
  elseif event == "CHALLENGE_MODE_RESET" then
    npKeyStarted = false
  elseif event == "ENCOUNTER_START" then
    npRefreshEditable()
    pcall(npEncounterSelect, arg1)
    return
  elseif event == "ENCOUNTER_END" then
    npRefreshEditable()
    if cfg("notebossauto") and npFrame and npFrame:IsShown() then pcall(npFrame.selectSection, "dungeon") end
    return
  end
  if event == "PLAYER_ENTERING_WORLD" and not npInDungeon() then
    npKeyStarted = false
    npCurrentID = nil
  end
  pcall(npApply)
  if event == "PLAYER_ENTERING_WORLD" then
    -- Re-apply after the instance and journal APIs settle, so the boss tabs
    -- appear on entering the dungeon and not only once a key has started.
    C_Timer.After(1, function() pcall(npApply) end)
    C_Timer.After(3, function() pcall(npApply) end)
    C_Timer.After(6, function() pcall(npApply) end)
  end
end)

ns.onOptionChanged("notepad", function() pcall(npApply) end)
ns.onOptionChanged("notepadmode", function() pcall(npApply) end)
ns.onOptionChanged("notepadlocked", function() if npFrame then npApplyLock(npFrame) end end)

ns.previewFrame("instance notepad", function()
  local f = ensureNpFrame()
  if not npCurrentID then
    npBuildSections(f)
    f.loadSection()
  end
  f:Show()
end, function()
  if npFrame and not npShouldShow() then npFrame:Hide() end
end, function() return npFrame end, { group = "Note", section = "The note window" })
