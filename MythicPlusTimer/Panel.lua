local _, ns = ...

local GOLD, GREY, WHITE, ENDC = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC
local cfg, setCfg = ns.cfg, ns.setCfg

-- Blizzard's own Settings panel stacks checkboxes vertically. To group them
-- under horizontal tabs instead, and to give profiles a home, we draw two of
-- our own frames and register them as sub-pages of the addon's Settings
-- category (the "+" in the AddOns list). Every control reads and writes through
-- cfg/setCfg, so this and the flat panel always agree.

-- ── Controls ───────────────────────────────────────────────────────────────

local function checkbox(parent, label, get, set)
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
  e:SetSize(w or 200, multiline and 90 or 22)
  e:SetAutoFocus(false)
  e:SetMultiLine(multiline and true or false)
  e:SetFontObject("ChatFontNormal")
  return e
end

-- ── Settings sub-page (horizontal tabs) ──────────────────────────────────────

local function buildSettings()
  local panel = CreateFrame("Frame")
  panel.name = "Settings"

  local order, byGroup = {}, {}
  for _, o in ipairs(ns.OPTIONS) do
    if not byGroup[o.group] then byGroup[o.group] = {}; order[#order + 1] = o.group end
    table.insert(byGroup[o.group], o)
  end

  panel.tabs, panel.pages = {}, {}
  local function select(group)
    for g, page in pairs(panel.pages) do page:SetShown(g == group) end
    for g, tab in pairs(panel.tabs) do
      if g == group then tab.label:SetTextColor(0.88, 0.65, 0.31) else tab.label:SetTextColor(0.7, 0.7, 0.7) end
    end
    panel.selected = group
  end
  panel.select = select

  local x = 16
  for _, g in ipairs(order) do
    local w = #g * 8 + 22
    local tab = CreateFrame("Button", nil, panel)
    tab:SetSize(w, 26)
    tab:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -16)
    tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.label:SetPoint("CENTER")
    tab.label:SetText(g)
    tab:SetScript("OnClick", function() select(g) end)
    panel.tabs[g] = tab
    x = x + w + 6

    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -56)
    page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    page:Hide()
    page.checks = {}
    local yy = 0
    for _, o in ipairs(byGroup[g]) do
      local cb = checkbox(page, o.label,
        function() return cfg(o.key) end,
        function(v) setCfg(o.key, v); local ch = ns.optionChanged[o.key]; if ch then pcall(ch) end end)
      cb:SetPoint("TOPLEFT", page, "TOPLEFT", 0, yy)
      yy = yy - 28
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

local function buildProfiles()
  local panel = CreateFrame("Frame")
  panel.name = "Profiles"

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(GOLD .. "Profiles" .. ENDC)

  panel.current = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  panel.current:SetPoint("TOPLEFT", 16, -42)

  -- A load button per profile, pooled and rebuilt whenever the set changes.
  panel.rows = {}
  local function rebuildList()
    for _, r in ipairs(panel.rows) do r:Hide() end
    local names, y = ns.profileNames(), -70
    for i, name in ipairs(names) do
      local r = panel.rows[i]
      if not r then r = button(panel, "", 200, nil); panel.rows[i] = r end
      r.profile = name
      r:SetText((name == ns.activeProfile() and "> " or "") .. name
        .. (name == ns.mainProfile() and "  (main)" or ""))
      r:SetScript("OnClick", function() ns.loadProfile(r.profile) end)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
      r:Show()
      y = y - 26
    end
  end

  local newBox = editbox(panel, 160)
  newBox:SetPoint("TOPLEFT", 240, -70)
  button(panel, "New profile", 110, function()
    local name = newBox:GetText()
    if name and name ~= "" then ns.createProfile(name); newBox:SetText("") end
  end):SetPoint("TOPLEFT", 240, -98)

  button(panel, "Reset", 110, function() ns.resetProfile() end):SetPoint("TOPLEFT", 240, -132)
  button(panel, "Set as main", 110, function() ns.setMainProfile(ns.activeProfile()) end):SetPoint("TOPLEFT", 240, -160)
  panel.deleteBtn = button(panel, "Delete", 110, function() ns.deleteProfile(ns.activeProfile()) end)
  panel.deleteBtn:SetPoint("TOPLEFT", 240, -188)

  local exportLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  exportLabel:SetPoint("TOPLEFT", 16, -240)
  exportLabel:SetText(GREY .. "Export (copy this):" .. ENDC)
  panel.exportBox = editbox(panel, 360, true)
  panel.exportBox:SetPoint("TOPLEFT", 16, -260)

  local importLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  importLabel:SetPoint("TOPLEFT", 16, -360)
  importLabel:SetText(GREY .. "Import (paste, then Import):" .. ENDC)
  panel.importBox = editbox(panel, 360, true)
  panel.importBox:SetPoint("TOPLEFT", 16, -380)
  button(panel, "Import", 110, function()
    local s = panel.importBox:GetText()
    if s and s ~= "" and ns.importProfile(s) then panel.importBox:SetText("") end
  end):SetPoint("TOPLEFT", 16, -480)

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
