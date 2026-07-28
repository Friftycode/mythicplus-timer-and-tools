local _, ns = ...

local GOLD, GREY, WHITE, ENDC = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC
local cfg, isSecret, mptPrint = ns.cfg, ns.isSecret, ns.print

-- ── Party key share ──────────────────────────────────────────────────────
-- Group members running this addon quietly tell each other which keystone they
-- hold, so the create-a-group panel can offer a dropdown of everyone's keys.
-- Picking one fills in that dungeon and a "+level" title; the difficulty and
-- playstyle are left to the defaults the Automation hook already applies, so a
-- shared key lists exactly the way your own would.
--
-- The share wire is one addon-message prefix. A member broadcasts "K:mapID:level"
-- for the key they own; "REQ" asks everyone to (re)broadcast. That traffic is
-- hidden and only runs while grouped. Separately, a "!keys" chat command posts a
-- visible keystone link (see the bottom of the file), which anyone can ask for.

local KS_PREFIX = "MPTTKey"
local KS_STALE = 60 * 20  -- drop a peer's key we haven't heard in 20 minutes

-- name -> { mapID, level, at }. Our own key is read live rather than stored here.
local peers = {}

local ksMyNameCache
local function ksMyName()
  if ksMyNameCache then return ksMyNameCache end
  local ok, n = pcall(UnitName, "player")
  ksMyNameCache = (ok and type(n) == "string" and n) or "?"
  return ksMyNameCache
end

-- The create-a-group panel. In current clients this is LFGListFrame.EntryCreation;
-- the flat global LFGListEntryCreation is not reliably present, which is why an
-- earlier version that keyed off it never built the dropdown.
local function ksPanel()
  local f = _G.LFGListFrame
  if type(f) == "table" and type(f.EntryCreation) == "table" then return f.EntryCreation end
  return _G.LFGListEntryCreation
end

-- The dungeon the client names a challenge-map id, or nil.
local function ksDungeonName(mapID)
  if not (mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
  local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
  return (ok and type(name) == "string" and name ~= "" and not isSecret(name)) and name or nil
end

-- The player's own keystone as (mapID, level), or nil when they hold none.
local function ksOwnKey()
  if not C_MythicPlus then return nil end
  local getMap = C_MythicPlus.GetOwnedKeystoneChallengeMapID
  local getLvl = C_MythicPlus.GetOwnedKeystoneLevel
  if not (type(getMap) == "function" and type(getLvl) == "function") then return nil end
  local okM, mapID = pcall(getMap)
  local okL, level = pcall(getLvl)
  if not (okM and okL) then return nil end
  if type(mapID) ~= "number" or mapID <= 0 or isSecret(mapID) then return nil end
  if type(level) ~= "number" or level <= 0 or isSecret(level) then return nil end
  return mapID, level
end

-- ── The wire ──────────────────────────────────────────────────────────────

local function ksInGroup()
  return type(IsInGroup) == "function" and IsInGroup() and true or false
end

-- INSTANCE_CHAT for a finder-formed group, else PARTY, matching the buff-reminder
-- coordination so both ride the same channel.
local function ksChannel()
  if type(IsPartyLFG) == "function" and IsPartyLFG() then return "INSTANCE_CHAT" end
  return "PARTY"
end

local function ksSend(msg)
  if not ksInGroup() then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, KS_PREFIX, msg, ksChannel())
  end
end

-- Tell the group which key we hold. No-op when we hold none, so a member with an
-- empty keystone slot simply never appears in anyone's dropdown.
local function ksBroadcastOwn()
  if not cfg("keyshare") then return end
  local mapID, level = ksOwnKey()
  if not mapID then return end
  ksSend("K:" .. mapID .. ":" .. level)
end

-- Debounce the roster/bag churn: several events can fire for one real change, and
-- one broadcast per burst is plenty.
local ksBroadcastPending = false
local function ksBroadcastOwnSoon()
  if ksBroadcastPending then return end
  ksBroadcastPending = true
  C_Timer.After(1, function()
    ksBroadcastPending = false
    pcall(ksBroadcastOwn)
  end)
end

local ksComm = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, KS_PREFIX)
end
ksComm:RegisterEvent("CHAT_MSG_ADDON")
-- A key changes when you loot or downgrade one (bags) and when the weekly maps
-- refresh; leaving/joining changes who should hear about it.
ksComm:RegisterEvent("GROUP_ROSTER_UPDATE")
ksComm:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(ksComm.RegisterEvent, ksComm, "CHALLENGE_MODE_MAPS_UPDATE")
ksComm:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
  if event ~= "CHAT_MSG_ADDON" then
    -- A roster or key change: re-announce ours. Peers we can no longer hear age
    -- out on their own via KS_STALE.
    if cfg("keyshare") then ksBroadcastOwnSoon() end
    return
  end
  if prefix ~= KS_PREFIX or not cfg("keyshare") then return end
  if type(sender) ~= "string" or isSecret(sender) then return end
  -- Sender arrives as "Name-Realm"; keep just the name for the short label.
  local name = sender:match("^([^%-]+)") or sender
  message = tostring(message)
  if message == "REQ" then
    if name ~= ksMyName() then ksBroadcastOwnSoon() end
    return
  end
  local mapID, level = message:match("^K:(%d+):(%d+)$")
  mapID, level = tonumber(mapID), tonumber(level)
  if not (mapID and level and mapID > 0 and level > 0) then return end
  local now = (type(GetTime) == "function" and GetTime()) or 0
  peers[name] = { mapID = mapID, level = level, at = now }
end)

-- ── The list the dropdown draws ────────────────────────────────────────────

-- Shorten only the dungeon name, so the row stays "Name - Dungeon +Level" with the
-- name and level always visible; a long dungeon is cut with a trailing "...". The
-- box clips the end otherwise, hiding the level, which is the part people scan for.
local KS_DUNGEON_MAX = 16
local function ksShortDungeon(name)
  if type(name) ~= "string" then return "?" end
  if #name <= KS_DUNGEON_MAX then return name end
  return name:sub(1, KS_DUNGEON_MAX - 3):gsub("%s+$", "") .. "..."
end

-- Every fresh key, our own included, highest level first (ties broken by name).
-- Each row: { name, mapID, dungeon, level, label }, where label is
-- "Name - Dungeon +Level", the shape the request asked for.
local function ksList()
  local now = (type(GetTime) == "function" and GetTime()) or 0
  local rows = {}

  local myMap, myLevel = ksOwnKey()
  if myMap then rows[#rows + 1] = { name = ksMyName(), mapID = myMap, level = myLevel } end
  for name, k in pairs(peers) do
    if name ~= ksMyName() and (now - (k.at or 0)) <= KS_STALE then
      rows[#rows + 1] = { name = name, mapID = k.mapID, level = k.level }
    end
  end

  table.sort(rows, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return a.name < b.name
  end)

  for _, r in ipairs(rows) do
    r.dungeon = ksDungeonName(r.mapID) or "?"
    r.label = r.name .. " - " .. ksShortDungeon(r.dungeon) .. " +" .. r.level
  end
  return rows
end
ns.keyShareList = ksList

-- ── Turning a chosen key into a listing ────────────────────────────────────

-- The (groupID, activityID) whose activity names `dungeonName` in the create
-- panel's category, preferring a keystone activity. The difficulty the listing
-- ends on is left to the Automation hook, so any matching activity for the
-- dungeon will do to select the group. Returns nil if the dungeon isn't found.
local function ksActivityForDungeon(categoryID, dungeonName)
  if not (C_LFGList and C_LFGList.GetAvailableActivities and C_LFGList.GetActivityInfoTable) then return nil end
  if type(dungeonName) ~= "string" or dungeonName == "" then return nil end
  local ok, ids = pcall(C_LFGList.GetAvailableActivities, categoryID)
  if not (ok and type(ids) == "table") then return nil end
  local fallback
  for _, id in ipairs(ids) do
    local okI, info = pcall(C_LFGList.GetActivityInfoTable, id)
    if okI and type(info) == "table" and type(info.fullName) == "string"
      and info.fullName:find(dungeonName, 1, true) then
      local group = info.groupFinderActivityGroupID or info.groupID
      if info.isMythicPlusActivity then return group, id end
      fallback = fallback or { group = group, id = id }
    end
  end
  if fallback then return fallback.group, fallback.id end
  return nil
end
ns.keyShareActivityForDungeon = ksActivityForDungeon

-- Fills the create panel in from a chosen key: selects that dungeon's group and
-- writes the "+level" title. Best-effort against the protected panel; every step
-- is guarded and a manual change still wins afterwards.
local function ksApply(entry)
  if type(entry) ~= "table" then return end
  local frame = ksPanel()
  if type(frame) ~= "table" then return end
  local categoryID = frame.selectedCategory
  local groupID, activityID = ksActivityForDungeon(categoryID, entry.dungeon)
  if activityID and type(LFGListEntryCreation_Select) == "function" then
    pcall(LFGListEntryCreation_Select, frame, frame.selectedFilters, categoryID, groupID, activityID)
  end
  -- Write the "+level" title for the chosen key. Selecting the activity above
  -- auto-fills the title box with the activity's default name, so an
  -- "only if empty" write never fired; picking a key is an explicit request for
  -- that title, so set it outright. Do it again a frame later, since the panel's
  -- own post-select refresh can re-stamp the default title after we return.
  -- Note: for a Mythic+ activity Blizzard owns the title (a prebuilt "+level"
  -- plus the required playstyle, via C_LFGList.SetEntryTitle), so it may append the
  -- playstyle on top of ours; that is the client's mandated format, not a bug here.
  local function setTitle()
    local nameBox = frame.Name
    if type(nameBox) == "table" and type(nameBox.SetText) == "function" then
      nameBox:SetText("+" .. entry.level)
    end
  end
  setTitle()
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, function() pcall(setTitle) end)
  end
end
ns.keyShareApply = ksApply

-- ── The dropdown on the create panel ───────────────────────────────────────

-- The two Blizzard dropdowns on the create panel we line the row up with: the
-- dungeon ("Nexus-Point…") and the difficulty ("Mythic+"). Names per the Blizzard
-- GroupFinder frame (the same refs ElvUI skins). Returned left-to-right by their
-- on-screen position, so we never care which is which. nil until the panel lays out.
local function ksRowDropdowns()
  local frame = ksPanel()
  if type(frame) ~= "table" then return nil end
  local a, b = frame.GroupDropdown, frame.ActivityDropdown
  if type(a) ~= "table" or type(b) ~= "table" then return nil end
  if type(a.GetLeft) ~= "function" or type(b.GetLeft) ~= "function" then return nil end
  local la, lb = a:GetLeft(), b:GetLeft()
  if not (la and lb) then return nil end
  if la <= lb then return a, b else return b, a end
end

-- Classic dropdown chrome carries a phantom margin: the visible box starts inside
-- the frame's left edge and ends inside its right. These insets bring our row's
-- edges onto the visible box edges of the dropdowns below. Tweak if a client's
-- dropdown art differs.
local KS_DD_INSET_L, KS_DD_INSET_R = 16, 16

-- Anchor the row (backing, caption, selector) to the dungeon/difficulty dropdowns
-- so the caption's left sits on the left box's left edge, the selector's right sits
-- on the right box's right edge, and the backing spans exactly between them. Relies
-- on the panel being laid out (GetLeft populated); no-ops and is retried otherwise.
local KS_ROW_GAP, KS_ROW_H = 21, 22  -- lift above the dropdown row; selector height
local KS_BG_PAD = 4                  -- how far the band spills past the row each side
local function ksLayoutRow(d)
  if not d then return false end
  local leftDD, rightDD = ksRowDropdowns()
  if not (leftDD and rightDD) then return false end
  local GAP, H = KS_ROW_GAP, KS_ROW_H

  -- Selector: right edge on the right box's edge, stretched to fill the column.
  local left = leftDD:GetLeft() + KS_DD_INSET_L
  local right = rightDD:GetRight() - KS_DD_INSET_R
  local labelW = d.label:GetStringWidth() or 0
  local width = (right - left) - labelW - 12
  if width < 80 then width = 80 end
  d:SetBoxWidth(width)
  d:ClearAllPoints()
  d:SetPoint("BOTTOMRIGHT", rightDD, "TOPRIGHT", -KS_DD_INSET_R, GAP)

  -- Band: symmetric a few px around the selector's height, a touch wider each side.
  d.bg:ClearAllPoints()
  d.bg:SetPoint("BOTTOMLEFT", leftDD, "TOPLEFT", KS_DD_INSET_L - KS_BG_PAD, GAP - KS_BG_PAD)
  d.bg:SetPoint("TOPRIGHT", rightDD, "TOPRIGHT", -KS_DD_INSET_R + KS_BG_PAD, GAP + H + KS_BG_PAD)

  -- Caption: left edge on the left box's edge (with the same inner padding the box
  -- text has), vertically centred on the band so it lines up with the selector bar.
  d.label:ClearAllPoints()
  d.label:SetPoint("LEFT", d.bg, "LEFT", KS_BG_PAD + 8, 0)
  return true
end

local ksDropdown
local ksApplying = false  -- true while our own pick drives LFGListEntryCreation_Select
local function ksEnsureDropdown()
  if ksDropdown then return ksDropdown end
  local frame = ksPanel()
  if not (frame and type(ns.dropdownWidget) == "function") then return nil end
  -- Sit inside the create panel itself, its row lined up with the dungeon/difficulty
  -- dropdowns below (see ksLayoutRow): parenting to the panel makes it draw above the
  -- panel's chrome and hide with it, and keeps it in the window so it never overlaps a
  -- Raider.IO-style overlay drawn to the right. A solid dark backing spans the row so
  -- the panel's own text underneath can't bleed through; a gold caption sits at the
  -- left box's edge; the open list overlays the fields below on its own.
  local anchorTo = _G.PVEFrame or frame

  -- Opaque column behind the row, matching the field-box dark fill. Drawn one strata
  -- below the dropdown so it masks the panel text without hiding the selector.
  local bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  bg:SetFrameStrata("MEDIUM")
  if bg.SetBackdrop then
    bg:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    bg:SetBackdropColor(0.04, 0.04, 0.05, 1)
    bg:SetBackdropBorderColor(0.88, 0.65, 0.31, 0.9)
  end

  local d = ns.dropdownWidget(frame, 200)
  d.placeholder = "Party keys…"
  d:SetFrameStrata("HIGH")
  d:SetToplevel(true)
  d:ClearAllPoints()
  -- Fallback spot until the panel lays out and ksLayoutRow can anchor to the boxes.
  d:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", -14, -30)
  d.bg = bg

  local label = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("RIGHT", d, "LEFT", -6, 0)
  label:SetText(GOLD .. "Party keys" .. ENDC)
  d.label = label
  -- Selecting a key calls LFGListEntryCreation_Select, whose own hook would fire a
  -- refresh and reset the box back to the placeholder; a flag suppresses that so
  -- the chosen row stays shown.
  d.onSelect = function(v)
    ksApplying = true
    pcall(ksApply, v)
    ksApplying = false
  end
  ksDropdown = d
  return d
end

-- Repopulates the dropdown from the current list and shows or hides it.
local function ksRefreshDropdown()
  local d = ksEnsureDropdown()
  if not d then return end
  if not cfg("keyshare") then d:Hide(); if d.label then d.label:Hide() end; if d.bg then d.bg:Hide() end return end
  -- Our own pick is what re-entered here; leave the chosen row on the box.
  if ksApplying then return end
  local list = ksList()
  local choices = {}
  for _, e in ipairs(list) do choices[#choices + 1] = { value = e, label = e.label } end
  d:SetChoices(choices)
  if #choices == 0 then
    -- Solo with a key you still see your own, so an empty list means no key at all.
    d:SetValue(nil)
    d.text:SetText(GREY .. "No keys to show" .. ENDC)
  else
    d:SetValue(nil)
    d.text:SetText(WHITE .. "Pick a party key…" .. ENDC)
  end
  if d.bg then d.bg:Show() end
  if d.label then d.label:Show() end
  d:Show()

  -- Line the row up with the dungeon/difficulty boxes. On the first open the panel
  -- may not have positioned them yet (GetLeft nil), so retry a frame later; once it
  -- takes, the anchors are relative and hold on their own.
  if not ksLayoutRow(d) and C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, function() pcall(ksLayoutRow, d) end)
  end
end
ns.keyShareRefresh = ksRefreshDropdown

-- Hook the create panel's OnShow so the dropdown fills and a fresh REQ goes out
-- each time it opens. The panel is load-on-demand, so wait for it.
local ksPanelHooked = false
local function ksHideDropdown()
  if ksDropdown then
    ksDropdown:Hide()
    if ksDropdown.label then ksDropdown.label:Hide() end
    if ksDropdown.bg then ksDropdown.bg:Hide() end
    if ksDropdown.close then ksDropdown.close() end
  end
end

local function ksOnPanelShown()
  if not cfg("keyshare") then
    ksHideDropdown()
    return
  end
  ksSend("REQ")
  ksBroadcastOwnSoon()
  ksRefreshDropdown()
end

local function ksHookPanel()
  if ksPanelHooked then return end
  local frame = ksPanel()
  if not (type(frame) == "table" and type(frame.HookScript) == "function") then return end
  ksPanelHooked = true
  frame:HookScript("OnShow", ksOnPanelShown)
  -- The dropdown is parented to UIParent, so it doesn't hide with the panel on
  -- its own; hide it when the panel (or the whole window) closes.
  frame:HookScript("OnHide", ksHideDropdown)
  if type(_G.PVEFrame) == "table" and type(_G.PVEFrame.HookScript) == "function" then
    _G.PVEFrame:HookScript("OnHide", ksHideDropdown)
  end
  -- Selecting a dungeon/category is the reliable "the panel is in use" signal, and
  -- fires even if the OnShow hook is installed a frame late; refresh from it too.
  if type(hooksecurefunc) == "function" and type(LFGListEntryCreation_Select) == "function" then
    hooksecurefunc("LFGListEntryCreation_Select", function()
      if ksApplying then return end  -- our own pick; don't reset the chosen row
      local f = ksPanel()
      local shown = type(f) == "table" and type(f.IsShown) == "function" and f:IsShown()
      -- No IsShown (or hidden): still refresh, since a Select means the panel is
      -- the thing being driven; the refresh itself no-ops when the panel is gone.
      if shown or type(f) ~= "table" or type(f.IsShown) ~= "function" then pcall(ksOnPanelShown) end
    end)
  end
end

-- ── Reply to "!keys" in chat ───────────────────────────────────────────────
-- A KeyLinker-style responder: when anyone types "!keys" in a channel we're in,
-- post a link to the keystone we're carrying, so people without the addon can ask
-- for it too. The keystone is found by the "Hkeystone" tag every key link carries,
-- so no item id can retire it out from under us.

local function ksKeystoneLink()
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemLink) then return nil end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
    for slot = 1, (okN and slots or 0) do
      local okL, link = pcall(C_Container.GetContainerItemLink, bag, slot)
      if okL and type(link) == "string" and link:find("Hkeystone", 1, true) then return link end
    end
  end
  return nil
end

-- The chat channel to answer on, keyed to the event the "!keys" arrived on, so the
-- reply lands where it was asked.
local KS_KEYWORD_CHANNEL = {
  CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
  CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT", CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
  CHAT_MSG_GUILD = "GUILD",
}

local function ksOnKeyword(event, message)
  if not cfg("keylink") then return end
  if type(message) ~= "string" or isSecret(message) then return end
  -- Only a bare "!keys" (any case, ignoring surrounding spaces), so it never fires
  -- on a sentence that merely mentions it.
  if message:lower():gsub("%s+", "") ~= "!keys" then return end
  local channel = KS_KEYWORD_CHANNEL[event]
  if not channel then return end
  local link = ksKeystoneLink()
  if not link then return end
  -- A tick later, the way KeyLinker does it, so the link isn't dropped for
  -- arriving in the same frame as the triggering message.
  C_Timer.After(0.1, function()
    if type(SendChatMessage) == "function" then pcall(SendChatMessage, link, channel) end
  end)
end

local ksKeyword = CreateFrame("Frame")
for ev in pairs(KS_KEYWORD_CHANNEL) do pcall(ksKeyword.RegisterEvent, ksKeyword, ev) end
ksKeyword:SetScript("OnEvent", function(_, event, message) pcall(ksOnKeyword, event, message) end)

local ksLoader = CreateFrame("Frame")
ksLoader:RegisterEvent("PLAYER_LOGIN")
ksLoader:RegisterEvent("ADDON_LOADED")
ksLoader:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and type(name) == "string" and name:find("GroupFinder")) then
    ksHookPanel()
    if ksPanelHooked then self:UnregisterEvent("ADDON_LOADED") end
  end
end)

ns.onOptionChanged("keyshare", function()
  if cfg("keyshare") then ksBroadcastOwnSoon() end
  if ksDropdown then pcall(ksRefreshDropdown) end
end)
