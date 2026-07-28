local _, ns = ...

local cfg = ns.cfg

-- ── Social: party, queue, invite, and block conveniences ──────────────────
-- Ported from Leatrix Plus. Every behaviour reacts to a Blizzard event and
-- runs only unprotected client functions, each guarded. A single friend gate
-- decides who the accept/invite/block options apply to; guild and community
-- members count as friends when their toggles are on.

-- Newer clients can hand us "secret" values (a name, a GUID) that error on any
-- real use. Treat one as data we don't have, the same as nil.
local function usable(v)
  return v ~= nil and not ns.isSecret(v)
end

-- Name with any "-realm" removed, so a same/other-realm invite compares the
-- same way the friend and guild rosters store it.
local function baseName(name)
  if type(name) ~= "string" then return name end
  local base = strsplit("-", name, 2)
  return base
end

-- ── Friend gate ───────────────────────────────────────────────────────────
-- True when `name` is a character friend, a Battle.net friend's WoW character,
-- or (when enabled) an online guild or community member. GUID is checked when
-- both sides have one; the realm is not, since some callers don't know it.

local function isCharacterFriend(name, guid)
  if type(C_FriendList) ~= "table" then return false end
  if type(C_FriendList.ShowFriends) == "function" then pcall(C_FriendList.ShowFriends) end
  local count = (type(C_FriendList.GetNumFriends) == "function" and C_FriendList.GetNumFriends()) or 0
  for i = 1, count do
    local info = C_FriendList.GetFriendInfoByIndex(i)
    if type(info) == "table" and type(info.name) == "string" then
      if baseName(info.name) == name and (not guid or not info.guid or guid == info.guid) then
        return true
      end
    end
  end
  return false
end

local function isBattleNetFriend(name)
  if type(BNGetNumFriends) ~= "function" or type(C_BattleNet) ~= "table" then return false end
  local numFriends = BNGetNumFriends() or 0
  for i = 1, numFriends do
    local numToons = (type(C_BattleNet.GetFriendNumGameAccounts) == "function"
      and C_BattleNet.GetFriendNumGameAccounts(i)) or 0
    for j = 1, numToons do
      local acct = C_BattleNet.GetFriendGameAccountInfo(i, j)
      if type(acct) == "table" and acct.clientProgram == "WoW" and acct.characterName == name then
        return true
      end
    end
  end
  return false
end

local function isGuildFriend(name, guid)
  if not IsInGuild or not IsInGuild() then return false end
  if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then return false end
  local count = GetNumGuildMembers() or 0
  for i = 1, count do
    local gName, _, _, _, _, _, _, _, gOnline, _, _, _, _, gMobile, _, _, gGUID = GetGuildRosterInfo(i)
    -- A member logged in through the companion app can't be grouped with, so
    -- they don't count as present for these options.
    if gOnline and not gMobile and type(gName) == "string" then
      if baseName(gName) == name and (not guid or not gGUID or guid == gGUID) then
        return true
      end
    end
  end
  return false
end

local function isCommunityFriend(name, guid)
  if type(C_Club) ~= "table" or type(C_Club.GetSubscribedClubs) ~= "function"
    or type(CommunitiesUtil) ~= "table" then return false end
  local clubs = C_Club.GetSubscribedClubs() or {}
  local charType = Enum and Enum.ClubType and Enum.ClubType.Character
  local offline = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Offline
  local onlineMobile = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.OnlineMobile
  for _, club in pairs(clubs) do
    if type(club) == "table" and club.clubId and club.clubType == charType then
      local ids = CommunitiesUtil.GetMemberIdsSortedByName(club.clubId)
      local members = CommunitiesUtil.GetMemberInfo(club.clubId, ids)
      for _, m in pairs(members or {}) do
        if type(m) == "table" and type(m.name) == "string"
          and m.presence ~= offline and m.presence ~= onlineMobile then
          if baseName(m.name) == name and (not guid or not m.guid or guid == m.guid) then
            return true
          end
        end
      end
    end
  end
  return false
end

function ns.friendCheck(name, guid)
  if not usable(name) or type(name) ~= "string" then return false end
  if not usable(guid) then guid = nil end
  name = baseName(name)

  local ok, result = pcall(function()
    if isCharacterFriend(name, guid) then return true end
    if isBattleNetFriend(name) then return true end
    if cfg("friendlyguild") and isGuildFriend(name, guid) then return true end
    if cfg("friendlycommunities") and isCommunityFriend(name, guid) then return true end
    return false
  end)
  return ok and result or false
end

-- Queued for any dungeon/raid finder: an invite or a whisper-invite would pull
-- you out of the queue, so those are held while you wait.
local function inLFGQueue()
  if type(GetLFGMode) ~= "function" then return false end
  local cats = { LE_LFG_CATEGORY_LFD, LE_LFG_CATEGORY_LFR, LE_LFG_CATEGORY_RF,
    LE_LFG_CATEGORY_SCENARIO, LE_LFG_CATEGORY_FLEXRAID }
  for _, c in ipairs(cats) do
    if c and select(1, GetLFGMode(c)) then return true end
  end
  return false
end

-- Registers `frame` for `event` when `on()` is true, unregisters otherwise. The
-- one path used at login and on every relevant option change, so a toggle takes
-- effect without a reload just as it does in the source addon.
local function bindEvent(frame, event, on)
  if on() then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
end

-- ── Party invites: accept from friends, block from non-friends ─────────────
-- Both react to the same event, so one handler settles it: a friend's invite is
-- accepted when that option is on, a non-friend's is declined when blocking is
-- on. With neither on the event isn't even registered.

local function hideInvitePopups()
  StaticPopup_Hide("PARTY_INVITE")
  StaticPopup_Hide("PARTY_INVITE_XREALM")
end

local partyFrame = CreateFrame("Frame")
partyFrame:SetScript("OnEvent", function(_, _, name, ...)
  local guid = select(6, ...)
  local friend = ns.friendCheck(name, guid)
  if cfg("acceptpartyfriends") and friend and not inLFGQueue() then
    if type(AcceptGroup) == "function" then AcceptGroup() end
    if type(StaticPopup_ForEachShownDialog) == "function" then
      StaticPopup_ForEachShownDialog(function(self)
        if self.which == "PARTY_INVITE" or self.which == "PARTY_INVITE_XREALM" then
          self.inviteAccepted = 1
        end
      end)
    end
    hideInvitePopups()
  elseif cfg("blockpartyinvites") and not friend then
    if type(DeclineGroup) == "function" then DeclineGroup() end
    hideInvitePopups()
  end
end)

local function partyOn()
  return cfg("acceptpartyfriends") or cfg("blockpartyinvites")
end
local function updateParty()
  bindEvent(partyFrame, "PARTY_INVITE_REQUEST", partyOn)
end
ns.onOptionChanged("acceptpartyfriends", updateParty)
ns.onOptionChanged("blockpartyinvites", updateParty)

-- ── Block requested invites ────────────────────────────────────────────────
-- The "has requested to join your group" confirmation, e.g. from your own group
-- listing. Declined for non-friends, left for friends.

local requestFrame = CreateFrame("Frame")
requestFrame:SetScript("OnEvent", function()
  if not cfg("blockrequestedinvites") then return end
  if type(StaticPopup_FindVisible) ~= "function" then return end
  local popup = StaticPopup_FindVisible("GROUP_INVITE_CONFIRMATION")
  if not (popup and popup.data) then return end
  if type(GetInviteConfirmationInfo) ~= "function" then return end
  local _, name, guid = GetInviteConfirmationInfo(popup.data)
  if ns.friendCheck(name, guid) then return end
  if type(RespondToInviteConfirmation) == "function" then
    RespondToInviteConfirmation(popup.data, false)
  end
  StaticPopup_Hide("GROUP_INVITE_CONFIRMATION")
end)
local function updateRequests()
  bindEvent(requestFrame, "GROUP_INVITE_CONFIRMATION", function() return cfg("blockrequestedinvites") end)
end
ns.onOptionChanged("blockrequestedinvites", updateRequests)

-- ── Block duels ────────────────────────────────────────────────────────────

local duelFrame = CreateFrame("Frame")
duelFrame:SetScript("OnEvent", function(_, _, challenger)
  if not cfg("blockduels") then return end
  if ns.friendCheck(challenger) then return end
  if type(CancelDuel) == "function" then CancelDuel() end
  StaticPopup_Hide("DUEL_REQUESTED")
end)
local function updateDuels()
  bindEvent(duelFrame, "DUEL_REQUESTED", function() return cfg("blockduels") end)
end
ns.onOptionChanged("blockduels", updateDuels)

-- ── Queue from friends: confirm the role check ─────────────────────────────
-- When the group leader who started a ready/role check is a friend, accept it
-- for you. Hooks the accept button's OnShow so it fires whenever the popup
-- appears, matching the source addon.

-- The role-check popup's three role buttons, and the config value that maps to
-- each. A button is only "available" when its check box is enabled, which the
-- client does per the current spec, so a role the spec cannot fill is never set.
local ROLE_BUTTON = {
  tank   = "LFDRoleCheckPopupRoleButtonTank",
  healer = "LFDRoleCheckPopupRoleButtonHealer",
  dps    = "LFDRoleCheckPopupRoleButtonDPS",
}

local function roleCheckBox(role)
  local rb = _G[ROLE_BUTTON[role] or ""]
  local cb = rb and rb.checkButton
  return (type(cb) == "table" and type(cb.GetChecked) == "function") and cb or nil
end

local function roleAvailable(role)
  local cb = roleCheckBox(role)
  if not (cb and type(cb.IsEnabled) == "function") then return false end
  local ok, enabled = pcall(cb.IsEnabled, cb)
  return ok and enabled and true or false
end

-- Toggle a role's check box to `want` by clicking it, so Blizzard's own OnClick
-- runs (it records the roles and keeps the Accept button's enabled state right).
local function setRoleChecked(role, want)
  local cb = roleCheckBox(role)
  if not (cb and type(cb.Click) == "function") then return end
  local ok, checked = pcall(cb.GetChecked, cb)
  if not ok then return end
  if (checked and true or false) ~= want then pcall(cb.Click, cb) end
end

-- Force the popup to the chosen roles, but only the ones the current spec can fill,
-- so a set that lists a role this character cannot play just drops it (an alt that
-- can only DPS confirms as DPS even when Tank and Healer are ticked too). Returns
-- true once it has set the roles; false to leave the popup exactly as the client
-- left it (the last used role), which is the fallback when none of the chosen roles
-- fit this spec, so we never confirm with an empty, invalid role set.
local function applyPreferredRoles(wanted)
  if type(wanted) ~= "table" then return false end
  local anyFits = false
  for role in pairs(ROLE_BUTTON) do
    if wanted[role] and roleAvailable(role) then anyFits = true; break end
  end
  if not anyFits then return false end
  for role in pairs(ROLE_BUTTON) do
    setRoleChecked(role, (wanted[role] and roleAvailable(role)) and true or false)
  end
  return true
end

local roleHooked = false
local function installRoleConfirm()
  if roleHooked or type(LFDRoleCheckPopupAcceptButton) ~= "table" then return end
  roleHooked = true
  LFDRoleCheckPopupAcceptButton:HookScript("OnShow", function(self)
    local mode = cfg("confirmqueuerole")
    if mode == "off" or not mode then return end
    local leader, leaderGUID
    for i = 1, (GetNumSubgroupMembers() or 0) do
      local unit = "party" .. i
      if UnitIsGroupLeader(unit) then
        leader, leaderGUID = UnitName(unit), UnitGUID(unit)
        break
      end
    end
    if leader and ns.friendCheck(leader, leaderGUID) then
      -- "last" leaves the popup as the client pre-filled it; "roles" sets the ticked
      -- roles the spec can fill. Either way, then confirm.
      if mode == "roles" then pcall(applyPreferredRoles, cfg("confirmqueueroles")) end
      self:Click()
    end
  end)
end

-- ── Invite from whispers ───────────────────────────────────────────────────
-- Someone whispering the keyword is invited, as long as you can invite (leader,
-- assistant, or ungrouped) and aren't queued. "Only invite friends" gates a
-- normal whisper; a Battle.net whisper always invites the friend who sent it.

local function canInvite()
  return not UnitExists("party1") or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function matchesKeyword(text)
  local key = cfg("invitekeyword")
  if type(key) ~= "string" or key == "" then key = "inv" end
  return type(text) == "string" and strlower(strtrim(text)) == strlower(key)
end

local function inviteWhisperer(name)
  if type(C_PartyInfo) ~= "table" or type(C_PartyInfo.InviteUnit) ~= "function" then return end
  -- Drop our own realm from a same-realm name so InviteUnit takes it cleanly.
  local charName, charRealm = strsplit("-", name, 2)
  if charRealm then
    local _, myRealm = UnitFullName("player")
    if myRealm and charRealm == myRealm then name = charName end
  end
  C_PartyInfo.InviteUnit(name)
end

local function inviteBattleNet(presenceID)
  if not presenceID or type(BNIsFriend) ~= "function" or not BNIsFriend(presenceID) then return end
  local index = type(BNGetFriendIndex) == "function" and BNGetFriendIndex(presenceID)
  if not index or type(C_BattleNet) ~= "table" then return end
  local acct = C_BattleNet.GetFriendAccountInfo(index)
  local gameID = acct and acct.gameAccountInfo and acct.gameAccountInfo.gameAccountID
  if gameID and type(C_BattleNet.InviteFriend) == "function" then
    C_BattleNet.InviteFriend(gameID)
  end
end

local whisperFrame = CreateFrame("Frame")
whisperFrame:SetScript("OnEvent", function(_, event, text, sender, ...)
  if not cfg("invitefromwhisper") then return end
  if not usable(text) or not usable(sender) then return end
  if not matchesKeyword(text) or not canInvite() or inLFGQueue() then return end

  if event == "CHAT_MSG_WHISPER" then
    local guid = select(10, ...)
    if cfg("invitefriendsonly") and not ns.friendCheck(sender, guid) then return end
    inviteWhisperer(sender)
  elseif event == "CHAT_MSG_BN_WHISPER" then
    inviteBattleNet(select(11, ...))
  end
end)
local function updateWhisper()
  local on = function() return cfg("invitefromwhisper") end
  bindEvent(whisperFrame, "CHAT_MSG_WHISPER", on)
  bindEvent(whisperFrame, "CHAT_MSG_BN_WHISPER", on)
end
ns.onOptionChanged("invitefromwhisper", updateWhisper)

-- Set every event's initial state once the client is up, and install the role
-- hook (its frame may not exist before login).
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
  pcall(updateParty)
  pcall(updateRequests)
  pcall(updateDuels)
  pcall(updateWhisper)
  pcall(installRoleConfirm)
end)
