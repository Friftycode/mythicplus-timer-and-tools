local _, ns = ...

local GOLD, GREY, WHITE, ENDC = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC
local cfg, setCfg = ns.cfg, ns.setCfg

-- ── Minimap button ─────────────────────────────────────────────────────────
-- A small launcher on the minimap. Clicking it opens a menu: Settings, a
-- "Let me focus" toggle, and "Hide minimap button". Dragging it moves it around
-- the ring, and where it lands is remembered per profile. Nothing here casts or
-- sends anything: it only reads config and opens Blizzard's own settings/menu.

local BUTTON_ICON = "Interface\\AddOns\\MythicPlusTimerandTools\\Media\\minimap-icon.tga"
-- Lua 5.1 (the client) has math.atan2; a 5.3+ build folds it into atan(y, x).
local atan2 = math.atan2 or math.atan

local button

-- Where the button sits around the minimap, from the stored angle. The radius is
-- read from the minimap so a resized minimap still keeps the button on its edge.
local function positionButton()
  if not (button and Minimap) then return end
  local angle = math.rad(cfg("minimapangle") or 225)
  local r = (Minimap:GetWidth() / 2) + 8
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

-- Follows the cursor while dragging: the angle is the direction from the
-- minimap's center to the pointer. Both are put in the minimap's own coordinate
-- space first, or the two would be measured against different scales.
local function dragUpdate()
  if not Minimap then return end
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local px, py = GetCursorPosition()
  if not (mx and my and scale and scale > 0 and px and py) then return end
  px, py = px / scale, py / scale
  setCfg("minimapangle", math.deg(atan2(py - my, px - mx)))
  positionButton()
end

local function applyVisibility()
  if not button then return end
  if cfg("minimapbutton") then button:Show() else button:Hide() end
end

-- ── The menu ─────────────────────────────────────────────────────────────
-- Built with the client's own context-menu system when it's there, so it looks
-- like every other minimap-button menu; pcall-guarded so an API change drops the
-- menu rather than the button.

local function toggleFocus()
  setCfg("letmefocus", not cfg("letmefocus"))
  local changed = ns.optionChanged["letmefocus"]
  if changed then pcall(changed) end
end

local function hideButton()
  setCfg("minimapbutton", false)
  applyVisibility()
end

local function openMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    -- No menu system to build on: at least open Settings, the main action.
    if ns.openSettings then pcall(ns.openSettings) end
    return
  end
  pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
    root:CreateTitle("Mythic+ Timer and Tools")
    root:CreateButton("Settings", function()
      if ns.openSettings then ns.openSettings() end
    end)
    root:CreateCheckbox("Let me focus",
      function() return cfg("letmefocus") and true or false end,
      function() toggleFocus() end)
    root:CreateDivider()
    root:CreateButton("Hide minimap button", hideButton)
  end)
end

-- ── Creation ─────────────────────────────────────────────────────────────

local function createButton()
  if button or type(Minimap) ~= "table" then return end
  local b = CreateFrame("Button", "MythicPlusTimerMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")

  -- The texture is a self-contained round button: it bakes its own gold ring
  -- and transparent corners, so there is no separate minimap tracking border to
  -- add (that stock border is sized and offset for Blizzard's own layout and
  -- sits mis-centered over a custom icon).
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(30, 30)
  b.icon:SetTexture(BUTTON_ICON)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)

  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local hl = b:GetHighlightTexture()
  if hl then hl:ClearAllPoints(); hl:SetPoint("CENTER", b, "CENTER", 0, 0); hl:SetSize(30, 30) end

  b:SetScript("OnClick", function(self) openMenu(self) end)

  -- A left-drag consumes the click, so this never fires alongside OnClick.
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", dragUpdate)
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(GOLD .. "Mythic+ Timer and Tools" .. ENDC)
    GameTooltip:AddLine(GREY .. "Click for the menu." .. ENDC)
    GameTooltip:AddLine(GREY .. "Drag to move it around the minimap." .. ENDC)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  button = b
  positionButton()
  applyVisibility()
end

-- The Settings checkbox flips this; reflect it on the button at once.
ns.onOptionChanged("minimapbutton", applyVisibility)

-- A profile switch can bring a different show/hide with it. Chain the existing
-- hook so the overlay and panels still get theirs (Panel.lua wraps this again).
local prevProfileHook = ns.onProfileChanged
ns.onProfileChanged = function()
  if type(prevProfileHook) == "function" then pcall(prevProfileHook) end
  pcall(positionButton)
  pcall(applyVisibility)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() pcall(createButton) end)
