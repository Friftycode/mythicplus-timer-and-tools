local _, ns = ...

local cfg, mptPrint = ns.cfg, ns.print

-- ── Auto-slot the keystone ───────────────────────────────────────────────
-- Opening the Font of Power drops your keystone into it. Reacts to the player
-- opening the receptacle; a checkbox turns it off. PickupContainerItem then
-- SlotKeystone (both unprotected); bails in combat since pickup is blocked there.

-- Every keystone item link carries "Hkeystone", in every expansion and every
-- locale, so matching the LINK finds the key without an item id that a future
-- patch can retire out from under us.
local KEYSTONE_LINK_TAG = "Hkeystone"
-- The receptacle event and the frame's OnShow both fire for one interaction, and
-- the window is still opening when the first lands. A short delay collapses them
-- into a single insert and lets the frame settle before an item lands on the
-- cursor.
local KEY_INSERT_DELAY = 0.35
local keyInsertPending = false

local function isKeystoneLink(link)
  return type(link) == "string" and link:find(KEYSTONE_LINK_TAG, 1, true) ~= nil
end

-- Bag, slot, link of the first keystone in the player's bags, or nil.
local function findKeystone()
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemLink) then
    return nil
  end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
    for slot = 1, (okN and slots or 0) do
      local okL, link = pcall(C_Container.GetContainerItemLink, bag, slot)
      if okL and isKeystoneLink(link) then return bag, slot, link end
    end
  end
  return nil
end

-- Never disturb a key that is already in: it may be a group member's, and
-- swapping it for ours would change which dungeon the party is about to run.
local function keySlotted()
  if not (C_ChallengeMode and C_ChallengeMode.HasSlottedKeystone) then return false end
  local ok, slotted = pcall(C_ChallengeMode.HasSlottedKeystone)
  return (ok and slotted) and true or false
end

-- No "is this key for this dungeon" guard on purpose: the two ids that would
-- answer it aren't documented to share an id space, and comparing them refused
-- every insert in a live key. The already-slotted guard protects others' keys.

-- Reports why the last attempt did nothing, for /mpt key.
local keyLastReason = "not tried yet"

local function autoSlotKeystone(verbose)
  local function bail(reason)
    keyLastReason = reason
    if verbose then mptPrint(reason .. ".") end
  end
  if not cfg("autoslotkey") then return bail("the auto-slot setting is off") end
  if keyInsertPending then return bail("an insert is already pending") end
  if InCombatLockdown and InCombatLockdown() then return bail("you are in combat") end
  if keySlotted() then return bail("a keystone is already in the font") end
  local bag, slot = findKeystone()
  if not bag then return bail("no keystone found in your bags") end

  keyInsertPending = true
  C_Timer.After(KEY_INSERT_DELAY, function()
    keyInsertPending = false
    -- Re-read everything: bags can be rearranged and another player can slot
    -- their own key inside that window, and either would make the pickup below
    -- grab the wrong item.
    local okL, link = pcall(C_Container.GetContainerItemLink, bag, slot)
    if not (okL and isKeystoneLink(link)) then return bail("the keystone moved out of its bag slot") end
    if keySlotted() then return bail("someone slotted a keystone first") end
    if InCombatLockdown and InCombatLockdown() then return bail("combat started") end
    -- Anything already on the cursor would be dropped into the font instead.
    if ClearCursor then pcall(ClearCursor) end
    if not pcall(C_Container.PickupContainerItem, bag, slot) then
      return bail("the game refused to pick the keystone up")
    end
    -- Confirm it actually reached the cursor before telling the font to take
    -- it; a failed pickup would otherwise slot whatever else was being held.
    if C_Cursor and C_Cursor.GetCursorItem then
      local okC, held = pcall(C_Cursor.GetCursorItem)
      if okC and not held then
        return bail("the keystone did not reach the cursor")
      end
    end
    if not (C_ChallengeMode and C_ChallengeMode.SlotKeystone) then
      return bail("this client has no SlotKeystone API")
    end
    pcall(C_ChallengeMode.SlotKeystone)
    keyLastReason = "placed the keystone"
  end)
end

-- The receptacle event (plus the frame hook below) covers interacting with the
-- Font of Power; keyInsertPending collapses ones that land together into a
-- single insert.
--
-- PLAYER_INTERACTION_MANAGER_FRAME_SHOW is deliberately not used. It fires for
-- every interactable frame, and Enum.PlayerInteractionType has no member for the
-- Font of Power, so nothing in its payload can single the font out. Listening to
-- it meant a profession table, mailbox, bank or vendor put the key on the cursor
-- and asked the server to slot it, which answered "That keystone is for a
-- different dungeon".
local keyEvents = CreateFrame("Frame")
-- pcall: RegisterEvent throws on an event name a given client build lacks.
pcall(keyEvents.RegisterEvent, keyEvents, "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
keyEvents:SetScript("OnEvent", function()
  pcall(autoSlotKeystone)
end)

local keystoneHooked = false
local function hookKeystoneFrame()
  if keystoneHooked then return end
  local kf = _G.ChallengesKeystoneFrame
  if not kf then return end
  keystoneHooked = true
  kf:HookScript("OnShow", function() pcall(autoSlotKeystone) end)
end

-- ChallengesKeystoneFrame is load-on-demand, so hook it on ADDON_LOADED (or at
-- login if already loaded). This frame hook is a backstop for the events above.
local keyLoader = CreateFrame("Frame")
keyLoader:RegisterEvent("ADDON_LOADED")
keyLoader:RegisterEvent("PLAYER_LOGIN")
keyLoader:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_ChallengesUI" then return end
  hookKeystoneFrame()
  if keystoneHooked then self:UnregisterAllEvents() end
end)
