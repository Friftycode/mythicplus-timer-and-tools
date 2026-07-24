local _, ns = ...

local GOLD, GREY, WHITE, ENDC = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC
local cfg, setCfg = ns.cfg, ns.setCfg

-- Blizzard's own Settings panel stacks checkboxes vertically. To group them
-- under horizontal tabs instead, and to give profiles a home, we draw two of
-- our own frames and register them as sub-pages of the addon's Settings
-- category (the "+" in the AddOns list). Every control reads and writes through
-- cfg/setCfg, so this and the flat panel always agree.

local TAB_H, TAB_GAP, STRIP_Y = 26, 4, -14
local DESC_Y, CONTENT_Y = -48, -74
local ROW_H, SECTION_GAP = 26, 14

-- Tab and row colours, kept here so the two pages can't drift apart.
local C_TAB_ON = { 0.24, 0.19, 0.10, 0.95 }
local C_TAB_OFF = { 0.09, 0.09, 0.09, 0.75 }
local C_GOLD = { 0.88, 0.65, 0.31 }
local C_DIM = { 0.62, 0.62, 0.62 }

-- ── Controls ───────────────────────────────────────────────────────────────

-- GetStringWidth is only meaningful once a font is applied and the string has
-- been laid out; fall back to a per-character estimate so sizing never breaks.
local function textWidth(fs, text)
  local w = fs:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then w = #text * 7 end
  return w
end

local function paint(tex, c)
  tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- Hover art for a button. Goes through SetHighlightTexture rather than a texture
-- on the HIGHLIGHT layer, so the client shows it on mouseover and nowhere else.
local function hoverTint(b, alpha)
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
  local hl = b:GetHighlightTexture()
  if hl and hl.SetVertexColor then hl:SetVertexColor(1, 1, 1, alpha) end
end

-- Shows a row's own explanation on hover. Drawn as a "?" font string rather than
-- an art file, so there is nothing to break on a patch, and it carries the same
-- text the flat Blizzard panel puts in its tooltips.
local function attachTooltip(frame, title, body)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(WHITE .. title .. ENDC)
    if body and body ~= "" then GameTooltip:AddLine(body, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function helpIcon(parent, anchorTo, title, body)
  local h = CreateFrame("Button", nil, parent)
  h:SetSize(16, 16)
  h:SetPoint("LEFT", anchorTo, "RIGHT", 6, 0)
  h.disc = h:CreateTexture(nil, "BACKGROUND")
  h.disc:SetAllPoints()
  paint(h.disc, { 1, 1, 1, 0.07 })
  h.mark = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  h.mark:SetPoint("CENTER")
  h.mark:SetText(GOLD .. "?" .. ENDC)
  hoverTint(h, 0.12)
  attachTooltip(h, title, body)
  return h
end

local function checkbox(parent, label, get, set, tooltip)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(22, 22)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.label:SetText(label)
  cb.refresh = function() cb:SetChecked(get() and true or false) end
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  if tooltip and tooltip ~= "" then
    cb.help = helpIcon(parent, cb.label, label, tooltip)
    -- The box itself explains too, so the "?" is a hint rather than the only way in.
    attachTooltip(cb, label, tooltip)
  end
  cb.refresh()
  return cb
end

local function button(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function editbox(parent, w, multiline)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w or 200, multiline and 44 or 22)
  e:SetAutoFocus(false)
  e:SetMultiLine(multiline and true or false)
  e:SetFontObject("ChatFontNormal")
  return e
end

-- A heading with a hairline under it, used above each block of related rows on
-- a tab page and above each block of controls on the Profiles page.
local function heading(parent, text, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(GOLD .. text .. ENDC)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  paint(line, { 1, 1, 1, 0.10 })
  line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
  line:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + (width or 460), y - 16)
  return fs
end

-- ── Settings sub-page (horizontal tabs) ──────────────────────────────────────

-- One clickable tab. Drawn rather than templated: the stock tab art is sized
-- for Blizzard's own frames and does not sit flush inside a settings canvas.
local function tabButton(parent, text)
  local t = CreateFrame("Button", nil, parent)
  t.bg = t:CreateTexture(nil, "BACKGROUND")
  t.bg:SetAllPoints()
  hoverTint(t, 0.08)
  -- Sits on the strip's baseline, so the active tab reads as joined to the page.
  t.underline = t:CreateTexture(nil, "OVERLAY")
  t.underline:SetHeight(2)
  t.underline:SetPoint("BOTTOMLEFT")
  t.underline:SetPoint("BOTTOMRIGHT")
  paint(t.underline, { C_GOLD[1], C_GOLD[2], C_GOLD[3], 1 })
  t.label = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t.label:SetPoint("CENTER")
  t.label:SetText(text)
  t:SetSize(textWidth(t.label, text) + 28, TAB_H)
  t.setActive = function(on)
    paint(t.bg, on and C_TAB_ON or C_TAB_OFF)
    t.underline:SetShown(on)
    local c = on and C_GOLD or C_DIM
    t.label:SetTextColor(c[1], c[2], c[3])
  end
  return t
end

local function buildSettings()
  local panel = CreateFrame("Frame")
  panel.name = "Settings"

  -- Group rows by tab, and inside a tab by section, both in declaration order.
  local order, byGroup = {}, {}
  for _, o in ipairs(ns.OPTIONS) do
    if not byGroup[o.group] then byGroup[o.group] = {}; order[#order + 1] = o.group end
    table.insert(byGroup[o.group], o)
  end

  panel.tabs, panel.pages = {}, {}

  -- Says what the tab you are on actually changes.
  panel.desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, DESC_Y)
  panel.desc:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, DESC_Y)
  panel.desc:SetJustifyH("LEFT")

  local function select(group)
    for g, page in pairs(panel.pages) do page:SetShown(g == group) end
    for g, tab in pairs(panel.tabs) do tab.setActive(g == group) end
    local d = (ns.TAB_DESC or {})[group]
    panel.desc:SetText(d and (GREY .. d .. ENDC) or "")
    panel.selected = group
  end
  panel.select = select

  -- The strip's baseline, which every tab's underline sits on.
  local strip = panel:CreateTexture(nil, "ARTWORK")
  strip:SetHeight(1)
  paint(strip, { 1, 1, 1, 0.12 })
  strip:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, STRIP_Y - TAB_H)
  strip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, STRIP_Y - TAB_H)

  local x = 16
  for _, g in ipairs(order) do
    local tab = tabButton(panel, g)
    tab:SetPoint("TOPLEFT", panel, "TOPLEFT", x, STRIP_Y)
    tab:SetScript("OnClick", function() select(g) end)
    panel.tabs[g] = tab
    x = x + tab:GetWidth() + TAB_GAP

    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, CONTENT_Y)
    page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    page:Hide()
    page.checks = {}
    page.sections = {}
    local yy, lastSection = 0, nil
    for _, o in ipairs(byGroup[g]) do
      local sec = o.section or g
      if sec ~= lastSection then
        if lastSection then yy = yy - SECTION_GAP end
        page.sections[#page.sections + 1] = heading(page, sec, 0, yy, 440)
        lastSection = sec
        yy = yy - 26
      end
      local cb = checkbox(page, o.label,
        function() return cfg(o.key) end,
        function(v) setCfg(o.key, v); local ch = ns.optionChanged[o.key]; if ch then pcall(ch) end end,
        o.tooltip)
      cb:SetPoint("TOPLEFT", page, "TOPLEFT", 0, yy)
      yy = yy - ROW_H
      page.checks[o.key] = cb
    end
    panel.pages[g] = page
  end

  panel.refresh = function()
    for _, page in pairs(panel.pages) do
      for _, cb in pairs(page.checks) do cb.refresh() end
    end
  end

  select(order[1])
  return panel
end

-- ── Profiles sub-page ────────────────────────────────────────────────────────

-- A flat list row, so the profile list doesn't read as a stack of action
-- buttons. The active one is called out in gold.
local function profileRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetSize(206, 22)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  hoverTint(r, 0.10)
  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
  r.label:SetJustifyH("LEFT")
  r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.tag:SetPoint("RIGHT", r, "RIGHT", -8, 0)
  r.tag:SetJustifyH("RIGHT")
  return r
end

local function buildProfiles()
  local panel = CreateFrame("Frame")
  panel.name = "Profiles"

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(GOLD .. "Profiles" .. ENDC)

  panel.current = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  panel.current:SetPoint("TOPLEFT", 16, -42)

  heading(panel, "Your profiles", 16, -76, 230)
  heading(panel, "Create", 266, -76, 220)
  heading(panel, "This profile", 266, -162, 220)
  heading(panel, "Move settings between characters", 16, -262, 470)

  -- A framed well for the list, so the rows read as one control.
  local well = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  well:SetSize(230, 150)
  well:SetPoint("TOPLEFT", 16, -98)
  if well.SetBackdrop then
    well:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    well:SetBackdropColor(0, 0, 0, 0.45)
    well:SetBackdropBorderColor(0.35, 0.3, 0.2, 0.9)
  end

  -- One row per profile, pooled and rebuilt whenever the set changes.
  panel.rows = {}
  local function rebuildList()
    for _, r in ipairs(panel.rows) do r:Hide() end
    local names, y = ns.profileNames(), -8
    local active, main = ns.activeProfile(), ns.mainProfile()
    for i, name in ipairs(names) do
      local r = panel.rows[i]
      if not r then r = profileRow(well); panel.rows[i] = r end
      r.profile = name
      local isActive = name == active
      r.label:SetText(isActive and (GOLD .. name .. ENDC) or (WHITE .. name .. ENDC))
      r.tag:SetText(name == main and (GREY .. "main" .. ENDC) or "")
      paint(r.bg, isActive and { C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.18 } or { 1, 1, 1, 0 })
      r:SetScript("OnClick", function() ns.loadProfile(r.profile) end)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", well, "TOPLEFT", 10, y)
      r:Show()
      y = y - 24
    end
  end

  local newBox = editbox(panel, 180)
  newBox:SetPoint("TOPLEFT", 266, -100)
  button(panel, "New profile", 120, function()
    local name = newBox:GetText()
    if name and name ~= "" then ns.createProfile(name); newBox:SetText("") end
  end):SetPoint("TOPLEFT", 266, -128)

  button(panel, "Reset", 110, function() ns.resetProfile() end):SetPoint("TOPLEFT", 266, -186)
  button(panel, "Set as main", 116, function() ns.setMainProfile(ns.activeProfile()) end):SetPoint("TOPLEFT", 382, -186)
  panel.deleteBtn = button(panel, "Delete", 110, function() ns.deleteProfile(ns.activeProfile()) end)
  panel.deleteBtn:SetPoint("TOPLEFT", 266, -212)

  local exportLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  exportLabel:SetPoint("TOPLEFT", 16, -286)
  exportLabel:SetText(GREY .. "Export this profile - select the text and copy it:" .. ENDC)
  panel.exportBox = editbox(panel, 470, true)
  panel.exportBox:SetPoint("TOPLEFT", 16, -304)

  local importLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  importLabel:SetPoint("TOPLEFT", 16, -360)
  importLabel:SetText(GREY .. "Import - paste a profile string here, then Import:" .. ENDC)
  panel.importBox = editbox(panel, 470, true)
  panel.importBox:SetPoint("TOPLEFT", 16, -378)
  button(panel, "Import", 110, function()
    local s = panel.importBox:GetText()
    if s and s ~= "" and ns.importProfile(s) then panel.importBox:SetText("") end
  end):SetPoint("TOPLEFT", 16, -430)

  panel.refresh = function()
    panel.current:SetText(WHITE .. "Active: " .. ENDC .. GOLD .. ns.activeProfile() .. ENDC)
    -- Never let the default profile be deleted out from under a fresh install.
    panel.deleteBtn:SetEnabled(ns.activeProfile() ~= "Default")
    panel.exportBox:SetText(ns.exportProfile() or "")
    rebuildList()
  end
  panel.refresh()
  return panel
end

-- ── Registration ─────────────────────────────────────────────────────────────

local function register()
  if not (Settings and Settings.RegisterCanvasLayoutSubcategory and ns.settingsCategory) then return end
  local settings = buildSettings()
  local profiles = buildProfiles()
  ns.panels = { settings = settings, profiles = profiles }
  pcall(Settings.RegisterCanvasLayoutSubcategory, ns.settingsCategory, settings, "Settings")
  pcall(Settings.RegisterCanvasLayoutSubcategory, ns.settingsCategory, profiles, "Profiles")
  -- Switching, creating, resetting or deleting a profile changes every value on
  -- screen, so redraw both pages (and re-tick the overlay through its own hook).
  local overlayHook = ns.onProfileChanged
  ns.onProfileChanged = function()
    if type(overlayHook) == "function" then pcall(overlayHook) end
    pcall(settings.refresh)
    pcall(profiles.refresh)
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() pcall(register) end)
