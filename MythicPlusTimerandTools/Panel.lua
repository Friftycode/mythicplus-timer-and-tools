local _, ns = ...

local GOLD, GREY, WHITE, ENDC = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC
local cfg, setCfg = ns.cfg, ns.setCfg

-- The addon's settings screen: horizontal tabs over Blizzard's vertical stack,
-- and the Profiles page. Every control reads and writes through cfg/setCfg.

local TAB_H, TAB_GAP, STRIP_Y = 26, 4, -14
local DESC_Y, CONTENT_Y = -48, -74
local ROW_H, SECTION_GAP = 26, 14

-- The active tab is a solid gold-brown; an inactive one is a distinct dark box
-- rather than a faint wash, so the strip reads as tabs against Blizzard's own
-- panel behind it. Both are opaque, so the game world never bleeds through them.
local C_TAB_ON = { 0.30, 0.23, 0.12, 1.0 }
local C_TAB_OFF = { 0.15, 0.15, 0.16, 1.0 }
local C_GOLD = { 0.90, 0.68, 0.34 }
-- Inactive-tab label: bright enough to read on its own, still clearly secondary
-- to the gold of the selected tab. The old 0.62 grey washed into the backdrop.
local C_DIM = { 0.82, 0.82, 0.82 }

-- ── Controls ───────────────────────────────────────────────────────────────

-- GetStringWidth reads 0 until the string has been laid out.
local function textWidth(fs, text)
  local w = fs:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then w = #text * 7 end
  return w
end

local function paint(tex, c)
  tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- SetHighlightTexture, not a texture on the HIGHLIGHT layer: only the former is
-- shown on mouseover alone.
local function hoverTint(b, alpha)
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
  local hl = b:GetHighlightTexture()
  if hl and hl.SetVertexColor then hl:SetVertexColor(1, 1, 1, alpha) end
end

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
  paint(h.disc, { 1, 1, 1, 0.14 })
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

local function well(parent, w, h)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(w, h)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.5)
    f:SetBackdropBorderColor(0.35, 0.3, 0.2, 0.9)
  end
  return f
end

-- InputBoxTemplate's art is drawn for one line and spills past a taller box, so
-- multi-line gets a plain edit box inside a well instead.
local function editbox(parent, w, multiline, height)
  if not multiline then
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w or 200, 22)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
  end
  local box = well(parent, w or 200, height or 46)
  local e = CreateFrame("EditBox", nil, box)
  e:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -7)
  e:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 7)
  e:SetAutoFocus(false)
  e:SetMultiLine(true)
  e:SetFontObject("ChatFontNormal")
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- Callers position the well, not the edit box inside it.
  e.container = box
  return e
end

local function place(widget, parent, x, y)
  local w = widget.container or widget
  w:ClearAllPoints()
  w:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  return widget
end

local function heading(parent, text, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(GOLD .. text .. ENDC)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  paint(line, { C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.35 })
  line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
  line:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + (width or 460), y - 16)
  return fs
end

-- ── Settings sub-page (horizontal tabs) ──────────────────────────────────────

-- Drawn rather than templated: the stock tab art is sized for Blizzard's own
-- frames and does not sit flush inside a settings canvas.
local function tabButton(parent, text)
  local t = CreateFrame("Button", nil, parent)
  t.bg = t:CreateTexture(nil, "BACKGROUND")
  t.bg:SetAllPoints()
  hoverTint(t, 0.08)
  -- On the strip's baseline, so the active tab reads as joined to the page.
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

-- ── About ────────────────────────────────────────────────────────────────────

local ABOUT = "About"
local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/mythic-timer-and-tools/"
local GITHUB_URL = "https://github.com/Friftycode/mythicplus-timer-and-tools"

local function addonVersion()
  local get = C_AddOns and C_AddOns.GetAddOnMetadata
  if type(get) ~= "function" then return nil end
  local ok, v = pcall(get, "MythicPlusTimerandTools", "Version")
  if ok and type(v) == "string" and v ~= "" then return v end
  return nil
end

-- Releases are version-stamped with the date they were cut ("2026.7.24"), so the
-- version doubles as the date. Any other shape gets no date rather than a guess.
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function versionDate(v)
  local y, m, d = tostring(v or ""):match("^(%d%d%d%d)%.(%d%d?)%.(%d%d?)")
  m, d = tonumber(m), tonumber(d)
  if not (y and m and d) or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
  return string.format("%d %s %s", d, MONTHS[m], y)
end

-- There is no read-only edit box, so typing into one puts the address back.
local function urlBox(parent, url, x, y)
  local e = editbox(parent, 430)
  e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  e:SetText(url)
  e:SetCursorPosition(0)
  e:SetScript("OnTextChanged", function(self)
    if self:GetText() ~= url then self:SetText(url) end
  end)
  e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  return e
end

local function buildAbout(page)
  local ver = addonVersion()
  local when = versionDate(ver)

  heading(page, "This addon", 0, 0, 440)
  local blurb = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  blurb:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -26)
  blurb:SetWidth(440)
  blurb:SetJustifyH("LEFT")
  blurb:SetText(GREY .. "A Mythic+ run timer overlay, plus the smaller tools around a key." .. ENDC)

  page.version = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.version:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -50)
  page.version:SetText(GREY .. "Version  " .. ENDC .. WHITE .. (ver or "unknown") .. ENDC)

  page.updated = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.updated:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -70)
  page.updated:SetText(when and (GREY .. "Updated  " .. ENDC .. WHITE .. when .. ENDC) or "")

  heading(page, "Links", 0, -106, 440)
  local cfLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cfLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -132)
  cfLabel:SetText(GREY .. "CurseForge" .. ENDC)
  page.curseforge = urlBox(page, CURSEFORGE_URL, 4, -150)

  local ghLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ghLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -182)
  ghLabel:SetText(GREY .. "GitHub" .. ENDC)
  page.github = urlBox(page, GITHUB_URL, 4, -200)

  local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -232)
  hint:SetWidth(440)
  hint:SetJustifyH("LEFT")
  hint:SetText(GREY .. "Click a link to select it, then copy with Ctrl+C." .. ENDC)
  return page
end

-- ── Settings sub-page ────────────────────────────────────────────────────────

local function buildSettings()
  local panel = CreateFrame("Frame")
  panel.name = "Settings"

  local order, byGroup = {}, {}
  for _, o in ipairs(ns.OPTIONS) do
    if not byGroup[o.group] then byGroup[o.group] = {}; order[#order + 1] = o.group end
    table.insert(byGroup[o.group], o)
  end

  panel.tabs, panel.pages = {}, {}

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

  local strip = panel:CreateTexture(nil, "ARTWORK")
  strip:SetHeight(1)
  paint(strip, { 1, 1, 1, 0.25 })
  strip:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, STRIP_Y - TAB_H)
  strip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, STRIP_Y - TAB_H)

  local x = 16
  local function addTab(g)
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
    panel.pages[g] = page
    return page
  end

  for _, g in ipairs(order) do
    local page = addTab(g)
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
    page.nextY = yy
  end

  -- Option buttons go on the first tab: the overlay is the frame people come
  -- here to move, and there is nowhere else for a non-checkbox control to live.
  local firstPage = panel.pages[order[1]]
  if firstPage and #ns.optionButtons > 0 then
    local yy = (firstPage.nextY or 0) - SECTION_GAP
    heading(firstPage, "Test frames", 0, yy, 440)
    yy = yy - 26
    firstPage.buttons = {}
    for _, b in ipairs(ns.optionButtons) do
      local btn = button(firstPage, b.label, 210, function() pcall(b.run) end)
      btn:SetPoint("TOPLEFT", firstPage, "TOPLEFT", 0, yy)
      attachTooltip(btn, b.name or b.label, b.tooltip)
      firstPage.buttons[b.label] = btn
      yy = yy - 26
    end
  end

  buildAbout(addTab(ABOUT))
  order[#order + 1] = ABOUT

  panel.refresh = function()
    for _, page in pairs(panel.pages) do
      for _, cb in pairs(page.checks) do cb.refresh() end
    end
  end
  -- Two of these pages exist (see ns.buildPanels), so each redraws as it is
  -- shown rather than trusting the other to have told it.
  panel:SetScript("OnShow", function() pcall(panel.refresh) end)

  select(order[1])
  return panel
end

-- ── Profiles sub-page ────────────────────────────────────────────────────────

-- Flat, so the profile list doesn't read as a stack of action buttons.
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

  local listWell = well(panel, 230, 150)
  listWell:SetPoint("TOPLEFT", 16, -98)

  -- Rows are pooled: the set changes as profiles are created and deleted.
  panel.rows = {}
  local function rebuildList()
    for _, r in ipairs(panel.rows) do r:Hide() end
    local names, y = ns.profileNames(), -8
    local active, main = ns.activeProfile(), ns.mainProfile()
    for i, name in ipairs(names) do
      local r = panel.rows[i]
      if not r then r = profileRow(listWell); panel.rows[i] = r end
      r.profile = name
      local isActive = name == active
      r.label:SetText(isActive and (GOLD .. name .. ENDC) or (WHITE .. name .. ENDC))
      r.tag:SetText(name == main and (GREY .. "main" .. ENDC) or "")
      paint(r.bg, isActive and { C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.18 } or { 1, 1, 1, 0 })
      r:SetScript("OnClick", function() ns.loadProfile(r.profile) end)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", listWell, "TOPLEFT", 10, y)
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
  panel.exportBox = place(editbox(panel, 470, true), panel, 16, -304)

  local importLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  importLabel:SetPoint("TOPLEFT", 16, -360)
  importLabel:SetText(GREY .. "Import - paste a profile string here, then Import:" .. ENDC)
  panel.importBox = place(editbox(panel, 470, true), panel, 16, -378)
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

-- Options.lua does the registering: the tabbed page is the addon's own category
-- rather than a sub-page, so it has to exist before that category is created.
function ns.buildPanels()
  if ns.panels then return ns.panels end
  local settings = buildSettings()
  -- The addon's entry and the "Settings" sub-page under it show the same thing,
  -- and one frame cannot be in two categories, so there are two of these.
  local settingsSub = buildSettings()
  local profiles = buildProfiles()
  ns.panels = { settings = settings, settingsSub = settingsSub, profiles = profiles }
  -- A profile switch changes every value on screen, so redraw all three (and
  -- re-tick the overlay through its own hook).
  local overlayHook = ns.onProfileChanged
  ns.onProfileChanged = function()
    if type(overlayHook) == "function" then pcall(overlayHook) end
    pcall(settings.refresh)
    pcall(settingsSub.refresh)
    pcall(profiles.refresh)
  end
  return ns.panels
end
