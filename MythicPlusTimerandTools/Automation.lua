local _, ns = ...

local RED, ENDC = ns.RED, ns.ENDC
local cfg = ns.cfg

-- ── Automation: merchant, quest, and difficulty conveniences ─────────────
-- Everything here reacts to a Blizzard event (a merchant opening, a quest
-- giver, a zone-in) and calls only unprotected client functions, each guarded.

local function inDungeon()
  local ok, _, itype = pcall(GetInstanceInfo)
  return ok and itype == "party"
end

local function money(copper)
  if type(GetCoinTextureString) == "function" then
    local ok, s = pcall(GetCoinTextureString, copper)
    if ok and s then return s end
  end
  return tostring(copper) .. "c"
end

-- ── Auto repair (3a) ──────────────────────────────────────────────────────
-- Guild-bank funds first when allowed and they cover it, else personal gold.

local function autoRepair()
  if not cfg("autorepair") then return end
  if not (type(CanMerchantRepair) == "function" and CanMerchantRepair()) then return end
  if type(GetRepairAllCost) ~= "function" then return end
  local cost, canRepair = GetRepairAllCost()
  if not canRepair or type(cost) ~= "number" or cost <= 0 then return end
  if type(RepairAllItems) ~= "function" then return end

  local usedGuild = false
  if cfg("autorepairguild") and type(CanGuildBankRepair) == "function" and CanGuildBankRepair() then
    local avail = (type(GetGuildBankWithdrawMoney) == "function" and GetGuildBankWithdrawMoney()) or 0
    -- A withdraw limit of -1 means unlimited for the player's guild rank.
    if avail == -1 or avail >= cost then
      RepairAllItems(true)
      usedGuild = true
    end
  end

  if not usedGuild then
    local have = (type(GetMoney) == "function" and GetMoney()) or 0
    if have < cost then
      ns.print(RED .. "not enough gold to repair (" .. money(cost) .. ")" .. ENDC)
      return
    end
    RepairAllItems(false)
  end
end

-- ── Auto sell junk (3b) ───────────────────────────────────────────────────
-- Poor (grey) quality is quality 0; hasNoValue skips things that can't be sold.

local function autoSellJunk()
  if not cfg("autosell") then return end
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.UseContainerItem) then return end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.quality == 0 and not info.hasNoValue then
        pcall(C_Container.UseContainerItem, bag, slot)
      end
    end
  end
end

local merchant = CreateFrame("Frame")
merchant:RegisterEvent("MERCHANT_SHOW")
merchant:SetScript("OnEvent", function()
  pcall(autoRepair)
  pcall(autoSellJunk)
end)

-- ── Auto accept / turn in quests (3c) ─────────────────────────────────────

local function questAutoOn()
  local mode = cfg("autoquestmode")
  if mode == "always" then return true end
  if mode == "never" then return false end
  return inDungeon()  -- "dungeon": only inside a party dungeon / M+
end

local LEAVE_PATTERNS = {
  "leave", "teleport", "take me out", "out of the dungeon",
  "out of the instance", "out of this", "exit", "remove me", "port me",
}
local function isLeaveOption(name)
  if type(name) ~= "string" then return false end
  local low = name:lower()
  for _, p in ipairs(LEAVE_PATTERNS) do
    if low:find(p, 1, true) then return true end
  end
  return false
end

-- A gossip window: hand in any completed quest, then accept any offered one.
-- One action per fire; selecting re-opens the window for the rest. When there
-- are no quests, a single benign option is progressed (dungeon dialogs), but a
-- "leave the instance" option is always left for the player.
local function onGossip()
  if not questAutoOn() or not C_GossipInfo then return end
  if C_GossipInfo.GetActiveQuests then
    for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
      if q.isComplete and q.questID and C_GossipInfo.SelectActiveQuest then
        C_GossipInfo.SelectActiveQuest(q.questID)
        return
      end
    end
  end
  if C_GossipInfo.GetAvailableQuests then
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
      if q.questID and C_GossipInfo.SelectAvailableQuest then
        C_GossipInfo.SelectAvailableQuest(q.questID)
        return
      end
    end
  end
  -- Only inside a dungeon, and only a single unambiguous option, so we never
  -- pick a wrong branch or eject the player from a key.
  if inDungeon() and C_GossipInfo.GetOptions and C_GossipInfo.SelectOption then
    local opts = C_GossipInfo.GetOptions() or {}
    if #opts == 1 and not isLeaveOption(opts[1].name) and opts[1].gossipOptionID then
      C_GossipInfo.SelectOption(opts[1].gossipOptionID)
    end
  end
end

-- Older, non-gossip multi-quest giver.
local function onQuestGreeting()
  if not questAutoOn() then return end
  local avail = (type(GetNumAvailableQuests) == "function" and GetNumAvailableQuests()) or 0
  if avail > 0 and type(SelectAvailableQuest) == "function" then
    SelectAvailableQuest(1)
    return
  end
  local active = (type(GetNumActiveQuests) == "function" and GetNumActiveQuests()) or 0
  if active > 0 and type(SelectActiveQuest) == "function" then
    SelectActiveQuest(1)
  end
end

local function onQuestDetail()
  if questAutoOn() and type(AcceptQuest) == "function" then AcceptQuest() end
end

local function onQuestProgress()
  if not questAutoOn() then return end
  if type(IsQuestCompletable) == "function" and IsQuestCompletable()
    and type(CompleteQuest) == "function" then
    CompleteQuest()
  end
end

local function onQuestComplete()
  if not questAutoOn() or type(GetQuestReward) ~= "function" then return end
  local choices = (type(GetNumQuestChoices) == "function" and GetNumQuestChoices()) or 0
  if choices > 1 then return end
  GetQuestReward(1)
end

local quests = CreateFrame("Frame")
quests:RegisterEvent("GOSSIP_SHOW")
quests:RegisterEvent("QUEST_GREETING")
quests:RegisterEvent("QUEST_DETAIL")
quests:RegisterEvent("QUEST_PROGRESS")
quests:RegisterEvent("QUEST_COMPLETE")
quests:SetScript("OnEvent", function(_, event)
  if event == "GOSSIP_SHOW" then pcall(onGossip)
  elseif event == "QUEST_GREETING" then pcall(onQuestGreeting)
  elseif event == "QUEST_DETAIL" then pcall(onQuestDetail)
  elseif event == "QUEST_PROGRESS" then pcall(onQuestProgress)
  elseif event == "QUEST_COMPLETE" then pcall(onQuestComplete)
  end
end)

-- ── Mythic difficulty warning (3d) ────────────────────────────────────────
-- DifficultyID 23 is Mythic, 8 is Mythic Keystone; anything else in a party
-- dungeon means it wasn't set to Mythic.

local function difficultyWarn()
  if not cfg("mythicwarn") then return end
  local ok, _, itype, diffID = pcall(GetInstanceInfo)
  if not ok or itype ~= "party" then return end
  if diffID == 23 or diffID == 8 then return end
  ns.print(RED .. "this dungeon is not set to Mythic difficulty." .. ENDC)
end

local zone = CreateFrame("Frame")
zone:RegisterEvent("PLAYER_ENTERING_WORLD")
zone:SetScript("OnEvent", function() pcall(difficultyWarn) end)

-- ── Default difficulty for a new group listing (3e) ───────────────────────
local function isMythicPlusActivity(info)
  if type(info) ~= "table" then return false end
  if info.isMythicPlusActivity then return true end
  local name = info.fullName
  return type(name) == "string" and (name:find("Keystone") or name:find("Mythic%+"))
end

-- Does an activity match the chosen difficulty? The keystone is its own case;
-- the rest match the "(Difficulty)" suffix, with Mythic excluding the keystone.
local function activityMatchesDifficulty(info, difficulty)
  if type(info) ~= "table" then return false end
  if difficulty == "mythicplus" then return isMythicPlusActivity(info) end
  local name = info.fullName
  if type(name) ~= "string" then return false end
  if difficulty == "mythic" then return name:match("%(Mythic%)") ~= nil end
  if difficulty == "heroic" then return name:match("%(Heroic%)") ~= nil end
  if difficulty == "normal" then return name:match("%(Normal%)") ~= nil end
  return false
end

local function pickActivityForDifficulty(categoryID, groupID, difficulty)
  if not (C_LFGList and C_LFGList.GetAvailableActivities and C_LFGList.GetActivityInfoTable) then return nil end
  local ok, ids = pcall(C_LFGList.GetAvailableActivities, categoryID, groupID)
  if not ok or type(ids) ~= "table" then return nil end
  for _, id in ipairs(ids) do
    local ok2, info = pcall(C_LFGList.GetActivityInfoTable, id)
    if ok2 and activityMatchesDifficulty(info, difficulty) then return id end
  end
  return nil
end

-- The create panel stores the playstyle as `generalPlaystyle`, an
-- Enum.LFGEntryGeneralPlaystyle value. Our "1".."4" map to Learning / FunRelaxed
-- / FunSerious / Expert (Learning / Relaxed / Competitive / Carry offered).
local function playstyleValue(pref)
  local E = Enum and Enum.LFGEntryGeneralPlaystyle
  local byPref = E and {
    ["1"] = E.Learning, ["2"] = E.FunRelaxed, ["3"] = E.FunSerious, ["4"] = E.Expert,
  }
  return (byPref and byPref[pref]) or tonumber(pref)
end

-- Preselects the required "Select Playstyle" on the create panel to the chosen
-- default, the same way clicking a radio would. Best-effort against a protected
-- panel: guarded, and no-ops if the layout differs. A manual pick still wins
-- (this runs only on a dungeon change).
local function applyPlaystyle(self)
  local pref = cfg("groupplaystyle")
  if not pref or pref == "off" then return end
  local val = playstyleValue(pref)
  if not val then return end
  local frame = (type(self) == "table" and self.PlayStyleDropdown) and self or _G.LFGListEntryCreation
  if type(frame) ~= "table" then return end
  local dd = frame.PlayStyleDropdown
  if type(dd) ~= "table" then return end
  if type(dd.IsShown) == "function" and not dd:IsShown() then return end  -- activity without playstyles

  if type(LFGListEntryCreation_OnPlayStyleSelectedInternal) == "function" then
    pcall(LFGListEntryCreation_OnPlayStyleSelectedInternal, frame, val)
  else
    frame.generalPlaystyle = val
  end
  -- Refresh the dropdown's shown selection and the List button's enabled state.
  if type(dd.GenerateMenu) == "function" then pcall(dd.GenerateMenu, dd) end
  if type(LFGListEntryCreation_UpdateValidState) == "function" then
    pcall(LFGListEntryCreation_UpdateValidState, frame)
  end
end

local forceMythicState = { groupID = nil, forcing = false }
local forceMythicInstalled = false
local function installForceMythic()
  if forceMythicInstalled then return end
  if type(LFGListEntryCreation_Select) ~= "function" or type(hooksecurefunc) ~= "function" then return end
  forceMythicInstalled = true
  hooksecurefunc("LFGListEntryCreation_Select", function(self, filters, categoryID, groupID, activityID)
    local groupChanged = groupID ~= forceMythicState.groupID
    forceMythicState.groupID = groupID
    -- Only act on a dungeon change, so choosing a difficulty/playstyle yourself
    -- is left alone.
    if forceMythicState.forcing or not groupChanged then return end

    local diff = cfg("defaultdifficulty")
    if diff and diff ~= "off" then
      local ok, info = pcall(C_LFGList.GetActivityInfoTable, activityID)
      if not (ok and activityMatchesDifficulty(info, diff)) then
        local target = pickActivityForDifficulty(categoryID, groupID, diff)
        if target and target ~= activityID then
          forceMythicState.forcing = true
          pcall(LFGListEntryCreation_Select, self, filters, categoryID, groupID, target)
          forceMythicState.forcing = false
        end
      end
    end

    pcall(applyPlaystyle, self)
  end)
end

local lfg = CreateFrame("Frame")
lfg:RegisterEvent("PLAYER_LOGIN")
lfg:RegisterEvent("ADDON_LOADED")
lfg:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and type(name) == "string" and name:find("GroupFinder")) then
    pcall(installForceMythic)
  end
end)
