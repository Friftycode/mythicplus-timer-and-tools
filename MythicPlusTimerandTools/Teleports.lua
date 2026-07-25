local _, ns = ...

local GOLD, GREY, WHITE, ENDC = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC
local cfg, mptPrint = ns.cfg, ns.print

-- ── Dungeon teleports ────────────────────────────────────────────────────
-- Answers "does this character own a teleport to <dungeon>". Spell ids change
-- each season, so the spellbook is scanned and matched by name (and by
-- description for the Hero's Path flyouts) rather than hardcoded.

-- Loose match between a dungeon name and a teleport spell's name/description.
-- Punctuation and case differ between the two (an apostrophe in one, none in
-- the other), so both sides are folded down before comparing.
local function jpFold(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("[^%w\128-\255]", "")):lower()
end

-- Two buckets from the spellbook scan. Hero's Path flyout slots hold the dungeon
-- teleports and may be matched on their description (they're often not named
-- after the destination); everything else is matched by name only, to avoid
-- hundreds of description lookups matching a class ability that mentions a place.
local jpFlyoutSpells, jpPlainSpells, jpScanned = {}, {}, false

local function jpScanSpellBook()
  if jpScanned then return end
  jpScanned = true
  jpFlyoutSpells, jpPlainSpells = {}, {}
  if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
  local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
  local flyoutType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout
  local okLines, numLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
  if not okLines then return end
  for line = 1, (numLines or 0) do
    local okInfo, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
    if okInfo and type(info) == "table" and info.itemIndexOffset and info.numSpellBookItems then
      for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local okType, itemType, actionID, spellID = pcall(C_SpellBook.GetSpellBookItemType, i, bank)
        if okType then
          if flyoutType and itemType == flyoutType and actionID and GetFlyoutInfo then
            local okF, flyoutName, _, numSlots, isKnown = pcall(GetFlyoutInfo, actionID)
            if okF and isKnown and GetFlyoutSlotInfo then
              for slot = 1, (numSlots or 0) do
                local okS, slotSpell, _, slotKnown, slotName = pcall(GetFlyoutSlotInfo, actionID, slot)
                if okS and slotKnown and slotSpell then
                  jpFlyoutSpells[#jpFlyoutSpells + 1] =
                    { spellID = slotSpell, name = slotName, group = flyoutName }
                end
              end
            end
          elseif spellID then
            local okN, nameInfo = pcall(C_Spell.GetSpellInfo, spellID)
            jpPlainSpells[#jpPlainSpells + 1] =
              { spellID = spellID, name = okN and type(nameInfo) == "table" and nameInfo.name or nil }
          end
        end
      end
    end
  end
end

-- Learning or unlearning a teleport changes the answer, so drop the scan and
-- the per-dungeon results rather than serving a stale "you have no teleport".
local jpMatchCache = {}
local jpSpellsChanged = CreateFrame("Frame")
pcall(jpSpellsChanged.RegisterEvent, jpSpellsChanged, "SPELLS_CHANGED")
jpSpellsChanged:SetScript("OnEvent", function()
  jpScanned, jpMatchCache = false, {}
end)

local function jpIcon(spellID)
  if not (C_Spell and C_Spell.GetSpellTexture) then return nil end
  local ok, t = pcall(C_Spell.GetSpellTexture, spellID)
  return ok and t or nil
end

-- The teleport that lands in `dungeon`, or nil when the player doesn't own one.
local function jpFindTeleport(dungeon)
  if not dungeon or dungeon == "" then return nil end
  local want = jpFold(dungeon)
  if want == "" then return nil end
  local cached = jpMatchCache[want]
  if cached ~= nil then return cached or nil end

  pcall(jpScanSpellBook)
  local found
  -- Pass 1: flyout slots, by name then description.
  for _, s in ipairs(jpFlyoutSpells) do
    local n = jpFold(s.name)
    local hit = n ~= "" and (n:find(want, 1, true) or want:find(n, 1, true))
    if not hit and C_Spell and C_Spell.GetSpellDescription then
      local okD, desc = pcall(C_Spell.GetSpellDescription, s.spellID)
      hit = okD and jpFold(desc):find(want, 1, true) ~= nil
    end
    if hit then found = { spellID = s.spellID, name = s.name, icon = jpIcon(s.spellID) } break end
  end
  -- Pass 2: ordinary spells, name only.
  if not found then
    for _, s in ipairs(jpPlainSpells) do
      local n = jpFold(s.name)
      if n ~= "" and (n:find(want, 1, true) or want:find(n, 1, true)) then
        found = { spellID = s.spellID, name = s.name, icon = jpIcon(s.spellID) }
        break
      end
    end
  end
  -- false, not nil: a miss is cached too, so a dungeon with no teleport doesn't
  -- rescan the whole spellbook every time the popup opens.
  jpMatchCache[want] = found or false
  return found
end

-- ── Teleport from the Season Best icons ──────────────────────────────────
-- A transparent secure button over each Season Best dungeon icon, forwarding
-- Blizzard's own hover tooltip. Icons with no known teleport keep it hidden.

local seasonTpHooked = false

local function armSeasonBestTeleports()
  if not cfg("seasontp") then return end
  if not (ChallengesFrame and ChallengesFrame.DungeonIcons) then return end
  -- Secure attributes are read-only in combat; the Mythic+ window is not
  -- something you open mid-pull, so simply skip rather than queueing.
  if InCombatLockdown and InCombatLockdown() then return end

  for i, icon in ipairs(ChallengesFrame.DungeonIcons) do
    local btn = icon.mptTeleport
    if not btn then
      btn = CreateFrame("Button", "MythicPlusTimerSeasonTeleport" .. i, icon, "SecureActionButtonTemplate")
      btn:SetAllPoints(icon)
      btn:RegisterForClicks("AnyUp", "AnyDown")
      btn:SetAttribute("type", "spell")
      local okLevel, lvl = pcall(icon.GetFrameLevel, icon)
      if okLevel and type(lvl) == "number" then btn:SetFrameLevel(lvl + 5) end
      -- Covering the icon would otherwise swallow its hover, so hand the
      -- mouse events straight back to it and only add a line of our own.
      btn:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        local onEnter = parent and parent.GetScript and parent:GetScript("OnEnter")
        if onEnter then pcall(onEnter, parent) end
        if self.spellName and GameTooltip:IsShown() then
          GameTooltip:AddLine(GOLD .. "Click to teleport" .. ENDC)
          GameTooltip:Show()
        end
      end)
      btn:SetScript("OnLeave", function(self)
        local parent = self:GetParent()
        local onLeave = parent and parent.GetScript and parent:GetScript("OnLeave")
        if onLeave then pcall(onLeave, parent) else GameTooltip:Hide() end
      end)
      icon.mptTeleport = btn
    end

    -- The icon carries the challenge map id it was built from; field name has
    -- differed between builds, so accept either.
    local mapID = icon.mapID or icon.mapChallengeModeID
    local dungeon
    if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
      local okN, n = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
      dungeon = (okN and type(n) == "string" and n ~= "") and n or nil
    end
    local tp = dungeon and jpFindTeleport(dungeon) or nil
    if tp then
      btn:SetAttribute("spell", tp.spellID)
      btn.spellName = tp.name
      btn:Show()
    else
      btn.spellName = nil
      btn:Hide()
    end
  end
end

local seasonTpLoader = CreateFrame("Frame")
seasonTpLoader:RegisterEvent("ADDON_LOADED")
seasonTpLoader:RegisterEvent("PLAYER_LOGIN")
seasonTpLoader:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_ChallengesUI" then return end
  if seasonTpHooked or not ChallengesFrame then return end
  seasonTpHooked = true
  -- Re-armed on every open: which dungeons the row shows, and which teleports
  -- the character knows, both change between openings.
  ChallengesFrame:HookScript("OnShow", function() pcall(armSeasonBestTeleports) end)
  pcall(armSeasonBestTeleports)
  self:UnregisterAllEvents()
end)

-- ── What this feature hands back ─────────────────────────────────────────

-- The one export: every surface that offers a teleport asks here.
ns.findTeleport = jpFindTeleport

-- The question this answers is "will a teleport button appear for this season's
-- dungeons", so it reports one line per dungeon in the rotation rather than
-- dumping the whole spellbook.
ns.command("tp", "list the teleports it can see", function()
  local maps
  if C_ChallengeMode and C_ChallengeMode.GetMapTable then
    local okM, m = pcall(C_ChallengeMode.GetMapTable)
    maps = okM and m or nil
  end
  if type(maps) ~= "table" or #maps == 0 then
    return mptPrint("could not read this season's dungeon list.")
  end
  local hits = 0
  for _, mapID in ipairs(maps) do
    local okN, dungeon = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    dungeon = (okN and type(dungeon) == "string" and dungeon ~= "") and dungeon or ("map " .. tostring(mapID))
    local tp = jpFindTeleport(dungeon)
    if tp then hits = hits + 1 end
    print(GREY .. "  " .. ENDC .. WHITE .. dungeon .. ENDC .. GREY .. "  ->  " .. ENDC
      .. (tp and (WHITE .. tostring(tp.name) .. ENDC .. GREY .. " (" .. tp.spellID .. ")" .. ENDC)
          or (GREY .. "no teleport known" .. ENDC)))
  end
  mptPrint("matched " .. hits .. " of " .. #maps .. " dungeons. Use "
    .. WHITE .. "/mpt tp all" .. ENDC .. GREY .. " to dump every spell it can see.")
end)

-- The raw scan, for when a dungeon above says "no teleport known" and we need
-- to see what the addon actually has to work with. Deliberately unlisted in
-- /mpt: the line above is where you find out it exists.
ns.command("tp all", nil, function()
  pcall(jpScanSpellBook)
  for _, s in ipairs(jpFlyoutSpells) do
    local desc = ""
    if C_Spell and C_Spell.GetSpellDescription then
      local okD, d = pcall(C_Spell.GetSpellDescription, s.spellID)
      if okD and type(d) == "string" then desc = d:gsub("%s+", " "):sub(1, 70) end
    end
    print(GREY .. "  [" .. tostring(s.group) .. "] " .. ENDC .. WHITE .. tostring(s.name) .. ENDC
      .. GREY .. "  " .. desc .. ENDC)
  end
  mptPrint(#jpFlyoutSpells .. " spell(s) in flyouts, plus "
    .. #jpPlainSpells .. " ordinary spells (not listed).")
end)
