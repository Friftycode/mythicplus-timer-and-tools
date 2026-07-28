-- The two shared surfaces: the Settings panel and /mpt, both built from Core's
-- registries so a new feature appears in both by declaring itself.

local _, ns = ...

local GREY, WHITE, ENDC = ns.GREY, ns.WHITE, ns.ENDC
local cfg = ns.cfg

-- ── Options panel ─────────────────────────────────────────────────────────
-- pcall-guarded throughout, so an API change drops the panel rather than the
-- addon.

local ADDON_TITLE = "Mythic+ Timer and Tools"
local settingsCategory

-- The addon's name in the AddOns list and the "Settings" entry under its "+"
-- are the same screen, so there is only ever one settings surface.
local function registerOptionsPanel()
  if not (Settings and Settings.RegisterAddOnCategory
    and Settings.RegisterCanvasLayoutCategory) then return end
  if type(MythicPlusTimerConfig) ~= "table" then MythicPlusTimerConfig = {} end
  pcall(function()
    local panels = type(ns.buildPanels) == "function" and ns.buildPanels() or nil
    if not panels then return end

    local parent = Settings.RegisterCanvasLayoutCategory(panels.settings, ADDON_TITLE)
    settingsCategory = parent
    ns.settingsCategory = parent

    if type(Settings.RegisterCanvasLayoutSubcategory) == "function" then
      pcall(Settings.RegisterCanvasLayoutSubcategory, parent, panels.settingsSub, "Settings")
      pcall(Settings.RegisterCanvasLayoutSubcategory, parent, panels.profiles, "Profiles")
    end

    -- Only the top-level entry is registered; the sub-pages come with it.
    Settings.RegisterAddOnCategory(parent)
  end)
end

-- Opens our Settings category, or false to let the caller say where it is.
-- OpenToCategory needs the category's id, not the object, so resolve an id.
local function openSettings()
  local cat = settingsCategory
  if not (Settings and Settings.OpenToCategory and cat) then return false end
  local id = cat
  if type(cat) == "table" then
    id = nil
    if type(cat.GetID) == "function" then
      local okID, v = pcall(cat.GetID, cat)
      if okID then id = v end
    end
    if id == nil then id = cat.ID end
  end
  if type(id) ~= "number" and type(id) ~= "string" then return false end
  return (pcall(Settings.OpenToCategory, id)) and true or false
end

-- Shared with the minimap button, which needs a way to open our Settings from
-- its own file. Prints the fallback path when the category isn't up yet.
function ns.openSettings()
  if openSettings() then return true end
  ns.print("open Settings, AddOns, Mythic+ Timer and Tools to configure.")
  return false
end

-- ── Test frames (edit mode) ─────────────────────────────────────────────────
-- Puts every registered preview frame on screen at once for positioning, each
-- under a light-blue overlay like Blizzard's Edit Mode: drag it to move, hover
-- it for "Click to edit", click it to jump to its settings. Knows nothing about
-- which frames exist beyond what each registered.

local GOLD = ns.GOLD

-- "run overlay" -> "Run overlay". The registered names are already readable; just
-- give them a capital.
local function titleCase(name)
  return (tostring(name or ""):gsub("^%l", string.upper))
end

-- The blue wash sits on the frame; brighter on hover. Kept dim enough that the
-- example content underneath still reads through it.
local TINT = { 0.12, 0.55, 0.95, 0.25 }
local TINT_HOVER = { 0.20, 0.62, 1.0, 0.42 }
local function tint(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4]) end

-- Declared before the closures below so they capture these upvalues, not globals.
local previewShown = false
local settingsWasOpen = false  -- reopen Settings on exit only if we hid it on enter
local setPreviews  -- forward declaration: the Esc catcher and overlay call it

-- Lays the overlay over `frame` (once, then reused). Drag forwards to the
-- frame's own move scripts so the position saves exactly as a normal drag would;
-- a plain click (no drag) jumps to the frame's settings section.
local function attachEditOverlay(frame, preview)
  if not frame then return end
  local o = frame.mptEdit
  if not o then
    o = CreateFrame("Button", nil, frame)
    o:SetAllPoints(frame)
    -- Stay in the frame's own strata (the alert pop-ups sit above HIGH, so a
    -- fixed strata would put the overlay behind them); just sit a few levels up
    -- so the wash and label draw over the frame's content.
    local ok, strata = pcall(frame.GetFrameStrata, frame)
    if ok and strata then o:SetFrameStrata(strata) end
    local okL, level = pcall(frame.GetFrameLevel, frame)
    o:SetFrameLevel(((okL and level) or 1) + 10)
    o:RegisterForDrag("LeftButton")
    o.bg = o:CreateTexture(nil, "BACKGROUND")
    o.bg:SetAllPoints()
    o.title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    o.title:SetPoint("CENTER")
    o.title:SetJustifyH("CENTER")
    o.title:SetText(WHITE .. "Click to Edit" .. ENDC)
    o.title:Hide()
    -- "Click to Edit" shows only while hovered; the frame's own name rides the
    -- cursor in a tooltip rather than crowding the box, so even a small frame stays
    -- readable.
    o:SetScript("OnEnter", function(self)
      tint(self.bg, TINT_HOVER)
      self.title:Show()
      if GameTooltip and self.frameName then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(self.frameName, 1, 0.82, 0)
        GameTooltip:Show()
      end
    end)
    o:SetScript("OnLeave", function(self)
      tint(self.bg, TINT)
      self.title:Hide()
      if GameTooltip then GameTooltip:Hide() end
    end)
    -- Forward drags to the frame's own drag handlers, so StartMoving and the
    -- feature's savePosition both run just as they would without the overlay.
    o:SetScript("OnDragStart", function()
      local fn = frame:GetScript("OnDragStart")
      if fn then fn(frame) elseif frame.StartMoving then frame:StartMoving() end
    end)
    o:SetScript("OnDragStop", function()
      local fn = frame:GetScript("OnDragStop")
      if fn then fn(frame) elseif frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
    end)
    o:SetScript("OnClick", function(self)
      setPreviews(false)
      ns.openSettings()
      local t = self.target
      if t and type(ns.showSettingsSection) == "function" then
        ns.showSettingsSection(t.group, t.section)
      end
    end)
    frame.mptEdit = o
  end
  -- Re-assert placement each time: an alert frame may have raised itself when it
  -- was shown for the preview, which would otherwise leave the overlay behind it.
  local okS, strata = pcall(frame.GetFrameStrata, frame)
  if okS and strata then o:SetFrameStrata(strata) end
  local okL, level = pcall(frame.GetFrameLevel, frame)
  o:SetFrameLevel(((okL and level) or 1) + 10)
  -- Keep a frame's own controls that must still work in edit mode (a resize grip,
  -- the note's column divider) above the overlay, so they take the click there.
  for _, ctrl in ipairs(frame.mptEditPassthrough or {}) do
    pcall(function()
      ctrl:SetFrameStrata(o:GetFrameStrata())
      ctrl:SetFrameLevel(o:GetFrameLevel() + 2)
    end)
  end
  o.target = preview.target
  o.frameName = titleCase(preview.name)
  tint(o.bg, TINT)
  o.title:Hide()
  o:Show()
end

local function hideEditOverlay(frame)
  if frame and frame.mptEdit then frame.mptEdit:Hide() end
end

-- A named, hidden frame in UISpecialFrames so Escape closes edit mode the way it
-- closes any panel: Escape hides this frame, its OnHide switches previews off.
local escCatcher
local function ensureEscCatcher()
  if escCatcher then return end
  escCatcher = CreateFrame("Frame", "MythicPlusTimerEditModeEsc", UIParent)
  escCatcher:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "MythicPlusTimerEditModeEsc")
  end
  escCatcher:SetScript("OnHide", function()
    if previewShown then setPreviews(false) end
  end)
end

-- The Settings window would sit over the test frames, so hide it while editing and
-- put it back afterwards. Retail's frame is SettingsPanel; guard for older clients.
local function hideSettingsWindow()
  local p = _G.SettingsPanel
  if not (p and type(p.IsShown) == "function" and p:IsShown()) then return false end
  if type(HideUIPanel) == "function" then pcall(HideUIPanel, p) else pcall(p.Hide, p) end
  return true
end

-- A small control window shown alongside the test frames, with the one button that
-- ends edit mode. Movable, but reset to the same spot every time it opens so it is
-- always where you left it in muscle memory.
local controlPopup
local function ensureControlPopup()
  if controlPopup then return controlPopup end
  local f = CreateFrame("Frame", "MythicPlusTimerEditModeControls", UIParent, "BackdropTemplate")
  f:SetSize(230, 78)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 20,
      insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
  end

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText(GOLD .. "Edit Mode" .. ENDC)

  local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btn:SetSize(180, 24)
  btn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  btn:SetText("Close test frames")
  btn:SetScript("OnClick", function() setPreviews(false) end)

  controlPopup = f
  return f
end

setPreviews = function(on)
  if on == previewShown then return end
  previewShown = on
  -- Get the Settings window out of the way before the frames come up.
  if on then settingsWasOpen = hideSettingsWindow() end
  for _, p in ipairs(ns.previews) do
    pcall(on and p.show or p.hide)
    local ok, frame = false, nil
    if p.getFrame then ok, frame = pcall(p.getFrame) end
    if on and ok and frame then
      pcall(attachEditOverlay, frame, p)
    elseif not on and ok then
      pcall(hideEditOverlay, frame)
    end
  end
  ensureEscCatcher()
  if on then escCatcher:Show() else escCatcher:Hide() end

  local pop = ensureControlPopup()
  if on then
    pop:ClearAllPoints()
    pop:SetPoint("TOP", UIParent, "TOP", 0, -140)
    pop:Show()
  else
    pop:Hide()
    -- Bring Settings back only if we were the one who closed it.
    if settingsWasOpen then settingsWasOpen = false; pcall(ns.openSettings) end
  end
end

local function togglePreviews() setPreviews(not previewShown) end

ns.optionButton("Test frames", "Show or hide test frames",
  "Put every movable frame on screen at once so you can drag them where you want them. Each frame shows an edit overlay: drag it to move, or click it to jump to its settings. Press Escape to close.",
  togglePreviews)

ns.command("frames", "show or hide the test frames", togglePreviews)

-- ── Slash commands ───────────────────────────────────────────────────────
-- /mpt opens the panel; other args are whatever features registered. The help
-- line is generated from the same list, so it never drifts.

local function helpLine()
  local parts = {}
  for _, c in ipairs(ns.commands) do
    if c.help then
      parts[#parts + 1] = WHITE .. "/mpt " .. c.name .. ENDC .. GREY .. " (" .. c.help .. ")"
    end
  end
  return "commands: " .. WHITE .. "/mpt" .. ENDC .. GREY .. " (settings), "
    .. table.concat(parts, GREY .. ", ")
end

SLASH_MYTHICPLUSTIMER1, SLASH_MYTHICPLUSTIMER2 = "/mpt", "/mythicplustimer"
SlashCmdList.MYTHICPLUSTIMER = function(msg)
  local arg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "" then
    if not openSettings() then
      ns.print("open Settings, AddOns, Mythic+ Timer and Tools to configure.")
    end
    return
  end
  for _, c in ipairs(ns.commands) do
    if c.name == arg then return c.run() end
  end
  ns.print(helpLine())
end

-- Last frame created, so this login handler runs after every feature registered.
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", registerOptionsPanel)
