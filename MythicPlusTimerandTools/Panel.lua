local _, ns = ...

local GOLD, GREY, WHITE, ENDC = ns.GOLD, ns.GREY, ns.WHITE, ns.ENDC
local GOLD_RGB = ns.GOLD_RGB
local cfg, setCfg = ns.cfg, ns.setCfg

-- Writes a setting and runs its live-update hook, the one path every control uses.
local function applySet(key, v)
  setCfg(key, v)
  local ch = ns.optionChanged[key]
  if ch then pcall(ch) end
end

-- The addon's settings screen: horizontal tabs over Blizzard's vertical stack,
-- and the Profiles page. Every control reads and writes through cfg/setCfg.

local TAB_H, TAB_GAP, STRIP_Y = 26, 4, -14
-- Right edge the tab strip wraps at, so a long row of tabs drops to a new line
-- rather than running off the settings panel.
local TAB_WRAP = 600
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

-- Sizes a vertical scrollbar thumb to the visible fraction of its content, so it
-- reads as a real position indicator instead of a fixed block that swamps a
-- short box. Shared by every scrollbar the panel draws. Exposed so other files
-- (the note window) keep the same proportions.
local SCROLL_THUMB_MIN = 18
function ns.sizeScrollThumb(thumb, viewH, contentH)
  if not (thumb and viewH and contentH) or viewH <= 0 or contentH <= 0 then return end
  local h = math.max(SCROLL_THUMB_MIN, math.min(viewH, viewH * (viewH / contentH)))
  thumb:SetHeight(h)
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

local function button(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

-- A labelled row control: the label sits at the left, the control (an entry box
-- or a cycling button) at CONTROL_X. Shared shape so number and choice rows line
-- up under a heading the same way the checkboxes do.
local CONTROL_X = 250

local function labelledRow(parent, label, tooltip)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(440, 26)
  c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  c.label:SetPoint("LEFT", c, "LEFT", 0, 0)
  c.label:SetText(label)
  if tooltip and tooltip ~= "" then
    c.help = helpIcon(c, c.label, label, tooltip)
    attachTooltip(c, label, tooltip)
  end
  return c
end

-- The dark box + tooltip border shared by the entry boxes and the dropdowns, so
-- they all line up at the control column with the same left edge and look.
local function boxBackdrop(f, r, g, b, a)
  if not f.SetBackdrop then return end
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(r, g, b, a)
  f:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)
end

-- A whole-number entry, clamped to [minv, maxv] on commit. Same box as the
-- dropdowns, anchored at the control column, so it lines up with them.
local function numberControl(parent, label, get, set, minv, maxv, tooltip)
  local c = labelledRow(parent, label, tooltip)
  local e = CreateFrame("EditBox", nil, c, "BackdropTemplate")
  e:SetSize(52, 22)
  e:SetPoint("LEFT", c, "LEFT", CONTROL_X, 0)
  boxBackdrop(e, 0.10, 0.10, 0.12, 1)
  e:SetAutoFocus(false)
  e:SetNumeric(true)
  e:SetMaxLetters(4)
  e:SetJustifyH("LEFT")
  e:SetTextInsets(8, 6, 0, 0)
  e:SetFontObject("ChatFontNormal")
  local function commit(self)
    local v = tonumber(self:GetText()) or minv
    v = math.max(minv, math.min(maxv, math.floor(v + 0.5)))
    set(v)
    self:SetText(tostring(v))
    self:ClearFocus()
  end
  e:SetScript("OnEnterPressed", commit)
  e:SetScript("OnEditFocusLost", commit)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); c.refresh() end)
  c.editbox = e
  c.refresh = function() e:SetText(tostring(get())) end
  c.refresh()
  return c
end

-- A short free-text entry on the shared row, committed on enter or focus loss.
-- An empty value falls back to `default` so a required keyword is never blank.
local function textControl(parent, label, get, set, default, tooltip)
  local c = labelledRow(parent, label, tooltip)
  local e = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
  e:SetSize(140, 22)
  e:SetPoint("LEFT", c, "LEFT", CONTROL_X + 6, 0)
  e:SetAutoFocus(false)
  e:SetFontObject("ChatFontNormal")
  e:SetTextInsets(4, 4, 0, 0)
  local function commit(self)
    local v = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" then v = default or "" end
    set(v)
    self:SetText(v)
    self:ClearFocus()
  end
  e:SetScript("OnEnterPressed", commit)
  e:SetScript("OnEditFocusLost", commit)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); c.refresh() end)
  c.editbox = e
  c.refresh = function() e:SetText(tostring(get() or default or "")) end
  c.refresh()
  return c
end

-- A checkbox on the shared row: label at the left, the box in the control
-- column, so it lines up with the entry boxes and dropdowns.
local function checkbox(parent, label, get, set, tooltip)
  local c = labelledRow(parent, label, tooltip)
  local cb = CreateFrame("CheckButton", nil, c)
  cb:SetSize(24, 24)
  cb:SetPoint("LEFT", c, "LEFT", CONTROL_X, 0)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  c.check = cb
  c.refresh = function() cb:SetChecked(get() and true or false) end
  c.refresh()
  return c
end

-- The down chevron on a dropdown, made by rotating the small triangle: it points
-- down when closed and flips up while the list is open, like a web select.
local ARROW_DOWN, ARROW_UP = -math.pi / 2, math.pi / 2

-- A reusable dropdown: a box showing the current value, whose list opens right
-- below it (not a side menu). A full-screen catcher behind the list closes it on
-- an outside click. Wire it with :SetChoices, :SetValue, and .onSelect.
local function dropdownWidget(parent, width)
  local ROWH = 20
  local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
  d:SetSize(width or 180, 22)
  boxBackdrop(d, 0.10, 0.10, 0.12, 1)
  hoverTint(d, 0.06)
  d.text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.text:SetPoint("LEFT", d, "LEFT", 8, 0)
  d.text:SetPoint("RIGHT", d, "RIGHT", -20, 0)
  d.text:SetJustifyH("LEFT")
  d.arrow = d:CreateTexture(nil, "OVERLAY")
  d.arrow:SetSize(14, 14)
  d.arrow:SetPoint("RIGHT", d, "RIGHT", -5, 0)
  d.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  d.arrow:SetRotation(ARROW_DOWN)

  -- Parented to UIParent, not the settings canvas: the canvas is a ScrollBox that
  -- re-levels its children, which would push the open list behind sibling
  -- controls and make its rows unclickable. Anchored to the box across parents.
  local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("TOOLTIP")
  menu:SetWidth(width or 180)
  menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
  boxBackdrop(menu, 0.06, 0.06, 0.08, 0.98)
  menu:EnableMouse(true)
  menu:Hide()

  local closer = CreateFrame("Button", nil, UIParent)
  closer:SetAllPoints(UIParent)
  closer:SetFrameStrata("FULLSCREEN_DIALOG")
  closer:Hide()

  d.choices, d.rows = {}, {}
  local function labelFor(v)
    for _, ch in ipairs(d.choices) do if ch.value == v then return ch.label end end
    return d.placeholder or ""
  end
  local function close()
    menu:Hide(); closer:Hide(); d.arrow:SetRotation(ARROW_DOWN)
  end
  d.close = close
  closer:SetScript("OnClick", close)

  local function rebuild()
    for _, r in ipairs(d.rows) do r:Hide() end
    for i, ch in ipairs(d.choices) do
      local r = d.rows[i]
      if not r then
        r = CreateFrame("Button", nil, menu)
        r:SetHeight(ROWH)
        hoverTint(r, 0.14)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        d.rows[i] = r
      end
      r.text:SetText(ch.label)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * ROWH)
      r:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * ROWH)
      r:SetScript("OnClick", function()
        d.value = ch.value
        d.text:SetText(ch.label)
        close()
        if d.onSelect then d.onSelect(ch.value) end
      end)
      r:Show()
    end
    menu:SetHeight(math.max(1, #d.choices) * ROWH + 8)
  end

  -- Strata does the layering: the catcher sits above the settings canvas, the
  -- list above the catcher, so the rows always take the click.
  d:SetScript("OnClick", function()
    if menu:IsShown() then close() return end
    rebuild()
    closer:Show()
    menu:Show()
    menu:Raise()
    d.arrow:SetRotation(ARROW_UP)
  end)

  function d:SetChoices(list) d.choices = list or {} end
  function d:SetValue(v) d.value = v; d.text:SetText(labelFor(v)) end
  function d:GetValue() return d.value end
  -- Resize the box and its open list together, so a dropdown stretched to fit a
  -- host panel keeps the menu the same width as the button.
  function d:SetBoxWidth(w) if w and w > 0 then d:SetWidth(w); menu:SetWidth(w) end end
  return d
end

-- Shared so other files (e.g. the party-key dropdown on the create panel) get the
-- same dropdown look and open-below behaviour.
ns.dropdownWidget = dropdownWidget

-- A one-of-N setting bound to cfg get/set, drawn on the shared row.
local function choiceControl(parent, label, get, set, choices, tooltip)
  local c = labelledRow(parent, label, tooltip)
  local d = dropdownWidget(c, 180)
  d:SetPoint("LEFT", c, "LEFT", CONTROL_X, 0)
  d:SetChoices(choices)
  d.onSelect = function(v) set(v) end
  c.button = d
  c.refresh = function() d:SetValue(get()) end
  c.refresh()
  return c
end

-- Several independent on/off choices on one row (a set of roles), stored as a set
-- table { value = true, ... }. Each toggle writes a fresh table, so the saved value
-- is never a shared reference to another profile's set or to the default.
local function multichoiceControl(parent, label, get, set, choices, tooltip)
  local c = labelledRow(parent, label, tooltip)
  c.toggles = {}
  local x = CONTROL_X
  for _, ch in ipairs(choices) do
    local cb = CreateFrame("CheckButton", nil, c)
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", c, "LEFT", x, 0)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 3, 0)
    t:SetText(ch.label)
    cb.value = ch.value
    cb:SetScript("OnClick", function(self)
      local cur = get() or {}
      local nextSet = {}
      for _, o in ipairs(choices) do if cur[o.value] then nextSet[o.value] = true end end
      nextSet[self.value] = self:GetChecked() and true or nil
      set(nextSet)
    end)
    c.toggles[ch.value] = cb
    x = x + 20 + 3 + (t:GetStringWidth() or 30) + 10
  end
  c.refresh = function()
    local cur = get() or {}
    for value, cb in pairs(c.toggles) do cb:SetChecked(cur[value] and true or false) end
  end
  c.refresh()
  return c
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

-- A multi-line edit box that clips to a well and grows a slim scrollbar only when
-- the text overflows, so nothing spills outside the box.
local function scrollBox(parent, w, h)
  local box = well(parent, w, h)
  local scroll = CreateFrame("ScrollFrame", nil, box)
  scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -7)
  scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 7)
  scroll:EnableMouse(true)
  scroll:EnableMouseWheel(true)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(w - 24)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)

  local sbar = CreateFrame("Slider", nil, box)
  sbar:SetWidth(5)
  sbar:SetPoint("TOPRIGHT", box, "TOPRIGHT", -5, -7)
  sbar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -5, 7)
  sbar:SetOrientation("VERTICAL")
  sbar:SetMinMaxValues(0, 0)
  sbar:SetValueStep(1)
  sbar:SetObeyStepOnDrag(true)
  local track = sbar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.06)
  local thumb = sbar:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.55)
  thumb:SetSize(5, 30)
  sbar:SetThumbTexture(thumb)
  sbar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
  sbar:Hide()

  local function update()
    local childH = edit:GetHeight() or 0
    local viewH = scroll:GetHeight()
    local range = math.max(0, childH - viewH)
    box.range = range
    if range > 1 then
      sbar:SetMinMaxValues(0, range)
      sbar:SetValue(math.min(scroll:GetVerticalScroll(), range))
      ns.sizeScrollThumb(thumb, viewH, childH)
      sbar:Show()
    else
      scroll:SetVerticalScroll(0)
      sbar:Hide()
    end
  end

  scroll:SetScript("OnMouseWheel", function(self, delta)
    local r = box.range or 0
    if r <= 0 then return end
    local v = math.min(r, math.max(0, self:GetVerticalScroll() - delta * 24))
    self:SetVerticalScroll(v)
    sbar:SetValue(v)
  end)
  edit:SetScript("OnCursorChanged", function(_, _, cy, _, chh)
    local top = -cy
    local vs = scroll:GetVerticalScroll()
    local viewH = scroll:GetHeight()
    if top < vs then
      scroll:SetVerticalScroll(top)
    elseif top + chh > vs + viewH then
      scroll:SetVerticalScroll(top + chh - viewH)
    end
    sbar:SetValue(scroll:GetVerticalScroll())
  end)

  box.edit = edit
  box.scroll = scroll
  box.update = update
  return box
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
  -- Clips and scrolls, so a long profile string never spills outside the box.
  local box = scrollBox(parent, w or 200, height or 46)
  local e = box.edit
  e:SetScript("OnTextChanged", function() box.update() end)
  -- Callers position the well, not the edit box inside it.
  e.container = box
  return e
end

-- Parks a multi-line box at its first line: SetText leaves the cursor at the end,
-- which scrolls a long value to the bottom. Any box holding a lot of text is put
-- back to the top after its text is set.
local function multilineToTop(edit)
  if not edit then return end
  edit:SetCursorPosition(0)
  local box = edit.container
  if box then
    if box.scroll then box.scroll:SetVerticalScroll(0) end
    if box.update then box.update() end
  end
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

  local issuesLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  issuesLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -232)
  issuesLabel:SetWidth(440)
  issuesLabel:SetJustifyH("LEFT")
  issuesLabel:SetText(GREY .. "Found a bug, or want a feature? Open an issue on GitHub:" .. ENDC)
  page.issues = urlBox(page, GITHUB_URL .. "/issues", 4, -250)

  local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -282)
  hint:SetWidth(440)
  hint:SetJustifyH("LEFT")
  hint:SetText(GREY .. "Click a link to select it, then copy with Ctrl+C." .. ENDC)
  return page
end

-- ── Prepare-ahead note editor (Note tab) ─────────────────────────────────────
-- Pick any dungeon and boss and write its note before you set foot inside. It
-- reads and writes the same account-wide store the in-dungeon window uses.
local function buildNoteEditor(page, y)
  local ed = { dungeonKey = nil, section = "dungeon", loading = false }

  page.sections[#page.sections + 1] = heading(page, "Prepare notes ahead of time", 0, y, 452)
  y = y - 26

  -- Markdown is explained here (behind a help icon, to save space), not on the
  -- note window, so the window itself stays clean.
  local md = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  md:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
  md:SetText(GREY .. "Notes support markdown when shown." .. ENDC)
  helpIcon(page, md, "Markdown", table.concat({
    "Rendered when a note isn't being edited:",
    "",
    "#  ##  ###   headings",
    "-  or  1.    lists",
    ">            quote",
    "---          divider",
    "**bold**   *italic*   `code`   ~~strike~~",
    "",
    "Click a note to edit the raw text.",
  }, "\n"))
  y = y - 24

  local function labelAt(text, yy)
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", 0, yy)
    fs:SetText(text)
    return fs
  end

  labelAt("Dungeon", y + 3)
  ed.dungeonDD = dropdownWidget(page, 210)
  ed.dungeonDD:SetPoint("TOPLEFT", page, "TOPLEFT", CONTROL_X, y)
  ed.dungeonDD.placeholder = "Pick a dungeon"
  y = y - 28

  labelAt("Section", y + 3)
  ed.sectionDD = dropdownWidget(page, 210)
  ed.sectionDD:SetPoint("TOPLEFT", page, "TOPLEFT", CONTROL_X, y)
  ed.sectionDD.placeholder = "Dungeon"
  y = y - 30

  local box = scrollBox(page, 452, 92)
  box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
  ed.box = box
  ed.edit = box.edit
  ed.edit:SetScript("OnTextChanged", function(self)
    box.update()
    if ed.loading or not ed.dungeonKey then return end
    ns.noteSet(ed.dungeonKey, ed.section, self:GetText())
  end)

  local function load()
    ed.loading = true
    ed.edit:SetText(ed.dungeonKey and ns.noteGet(ed.dungeonKey, ed.section) or "")
    -- SetText parks the cursor at the end, scrolling a long note to the bottom;
    -- start it at the top instead.
    ed.edit:SetCursorPosition(0)
    box.scroll:SetVerticalScroll(0)
    ed.loading = false
    box.update()
  end

  ed.selectSection = function(section)
    ed.section = section
    ed.sectionDD:SetValue(section)
    load()
  end
  ed.sectionDD.onSelect = function(v) ed.selectSection(v) end

  ed.selectDungeon = function(key)
    ed.dungeonKey = key
    ed.dungeonDD:SetValue(key)
    local choices = {}
    for _, s in ipairs(ns.noteSectionList(key)) do
      choices[#choices + 1] = { value = s.key, label = s.name }
    end
    ed.sectionDD:SetChoices(choices)
    ed.selectSection("dungeon")
  end
  ed.dungeonDD.onSelect = function(v) ed.selectDungeon(v) end

  -- The journal may not have answered at login; repopulate the dungeon list each
  -- time the page is shown, and select one so the Section list is never empty.
  ed.refresh = function()
    local list = ns.noteDungeonList()
    local choices = {}
    for _, d in ipairs(list) do choices[#choices + 1] = { value = d.key, label = d.name } end
    ed.dungeonDD:SetChoices(choices)
    if not ed.dungeonKey and list[1] then
      ed.selectDungeon(list[1].key)
    elseif ed.dungeonKey then
      ed.dungeonDD:SetValue(ed.dungeonKey)
    end
  end
  ed.refresh()
  -- Bottom edge of the editor: the note box sits at `y` and is 92 tall.
  return ed, y - 92 - 8
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

  -- An update reminder across the top, above the tabs, when a newer version is
  -- likely out. Reserved at build time (its status is known by login); the rest
  -- of the layout shifts down by its height only when it is shown.
  local status = (type(ns.updateStatus) == "function") and ns.updateStatus() or nil
  local BANNER_H = status and 30 or 0
  if status then
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -4)
    box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -4)
    box:SetHeight(24)
    -- A calm, theme-matching alert: a warm dark backdrop with a soft gold rule,
    -- not an alarming red. Gold text reads as a notice, not a warning.
    if box.SetBackdrop then
      box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
      })
      box:SetBackdropColor(0.16, 0.13, 0.08, 0.94)
      box:SetBackdropBorderColor(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.45)
    else
      local bg = box:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(0.16, 0.13, 0.08, 0.94)
    end
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.text:SetPoint("LEFT", box, "LEFT", 10, 0)
    box.text:SetPoint("RIGHT", box, "RIGHT", -10, 0)
    box.text:SetJustifyH("LEFT")
    box.text:SetText(GOLD .. status.message .. ENDC)
    panel.banner = box
  end

  panel.desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.desc:SetJustifyH("LEFT")

  local function select(group)
    for g, page in pairs(panel.pages) do
      local shown = g == group
      if page.scroll then page.scroll:SetShown(shown) end
      page:SetShown(shown)
      if shown and page.updateScroll then page.updateScroll() end
    end
    for g, tab in pairs(panel.tabs) do tab.setActive(g == group) end
    local d = (ns.TAB_DESC or {})[group]
    panel.desc:SetText(d and (GREY .. d .. ENDC) or "")
    panel.selected = group
  end
  panel.select = select

  -- Every tab, About included, so the whole strip is laid out (and wrapped) as
  -- one before any page is placed under it.
  local tabOrder = {}
  for _, g in ipairs(order) do tabOrder[#tabOrder + 1] = g end
  tabOrder[#tabOrder + 1] = ABOUT

  -- The tab strip wraps to more rows when the next tab would run past the panel,
  -- so a growing set of features never pushes tabs off the right edge.
  local rowX, rowY, rows = 16, STRIP_Y - BANNER_H, 1
  for _, g in ipairs(tabOrder) do
    local tab = tabButton(panel, g)
    local w = tab:GetWidth()
    if rowX > 16 and rowX + w > TAB_WRAP then
      rowX = 16
      rowY = rowY - (TAB_H + TAB_GAP)
      rows = rows + 1
    end
    tab:SetPoint("TOPLEFT", panel, "TOPLEFT", rowX, rowY)
    tab:SetScript("OnClick", function() select(g) end)
    panel.tabs[g] = tab
    rowX = rowX + w + TAB_GAP
  end

  -- Everything below the strip shifts down by however many rows it grew to, plus
  -- the update banner's height when one is shown.
  local stripY = STRIP_Y - BANNER_H - (rows - 1) * (TAB_H + TAB_GAP) - TAB_H
  local strip = panel:CreateTexture(nil, "ARTWORK")
  strip:SetHeight(1)
  paint(strip, { 1, 1, 1, 0.25 })
  strip:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, stripY)
  strip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, stripY)

  panel.desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, stripY - 12)
  panel.desc:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, stripY - 12)
  local contentY = stripY - 34

  -- Each tab's content lives in a scroll viewport so a long page (Automation,
  -- once the social options are on it) scrolls rather than spilling past the
  -- settings frame. The slim gold scrollbar matches the Note editor's.
  local function newPage(g)
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, contentY)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 16)
    scroll:EnableMouseWheel(true)
    scroll:Hide()

    local page = CreateFrame("Frame", nil, scroll)
    page:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    page:SetSize(460, 1)
    scroll:SetScrollChild(page)

    local sbar = CreateFrame("Slider", nil, scroll)
    sbar:SetWidth(5)
    sbar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    sbar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    sbar:SetOrientation("VERTICAL")
    sbar:SetValueStep(1)
    sbar:SetObeyStepOnDrag(true)
    sbar:SetMinMaxValues(0, 0)
    local track = sbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.06)
    local thumb = sbar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.55)
    thumb:SetSize(5, 30)
    sbar:SetThumbTexture(thumb)
    sbar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
    sbar:Hide()

    -- Match the content to the viewport width and show the bar only when the
    -- content is taller than the view.
    local function update()
      local w = scroll:GetWidth() or 0
      if w > 0 then page:SetWidth(w) end
      local viewH = scroll:GetHeight() or 0
      local range = math.max(0, (page.contentH or 0) - viewH)
      if range > 1 then
        sbar:SetMinMaxValues(0, range)
        sbar:SetValue(math.min(scroll:GetVerticalScroll() or 0, range))
        ns.sizeScrollThumb(thumb, viewH, page.contentH or 0)
        sbar:Show()
      else
        scroll:SetVerticalScroll(0)
        sbar:Hide()
      end
    end
    page.updateScroll = update

    scroll:SetScript("OnSizeChanged", update)
    scroll:SetScript("OnShow", update)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local range = math.max(0, (page.contentH or 0) - (self:GetHeight() or 0))
      if range <= 0 then return end
      local v = math.min(range, math.max(0, (self:GetVerticalScroll() or 0) - delta * 30))
      self:SetVerticalScroll(v)
      sbar:SetValue(v)
    end)

    page.scroll = scroll
    page.checks = {}
    page.controls = {}
    page.sections = {}
    page.sectionY = {}
    panel.pages[g] = page
    return page
  end

  -- Scrolls a page so a named section's heading sits at the top of the view, and
  -- selects its tab first. Used by the edit-mode overlay's "Click to edit".
  function panel.showSection(group, section)
    select(group)
    local page = panel.pages[group]
    if not page or not page.scroll then return end
    local y = page.sectionY and page.sectionY[section]
    if not y then return end
    local range = math.max(0, (page.contentH or 0) - (page.scroll:GetHeight() or 0))
    local target = math.min(math.max(0, -y - 4), range)
    page.scroll:SetVerticalScroll(target)
    if page.updateScroll then page.updateScroll() end
  end

  for _, g in ipairs(order) do
    local page = newPage(g)
    local yy, lastSection = 0, nil
    for _, o in ipairs(byGroup[g]) do
      local sec = o.section or g
      if sec ~= lastSection then
        if lastSection then yy = yy - SECTION_GAP end
        page.sectionY[sec] = yy
        page.sections[#page.sections + 1] = heading(page, sec, 0, yy, 440)
        lastSection = sec
        yy = yy - 26
      end
      local get = function() return cfg(o.key) end
      local set = function(v) applySet(o.key, v) end
      local control
      if o.type == "number" then
        control = numberControl(page, o.label, get, set, o.min or 0, o.max or 100, o.tooltip)
      elseif o.type == "choice" then
        control = choiceControl(page, o.label, get, set, o.choices or {}, o.tooltip)
      elseif o.type == "multichoice" then
        control = multichoiceControl(page, o.label, get, set, o.choices or {}, o.tooltip)
      elseif o.type == "text" then
        control = textControl(page, o.label, get, set, o.default, o.tooltip)
      else
        control = checkbox(page, o.label, get, set, o.tooltip)
        page.checks[o.key] = control
      end
      control:SetPoint("TOPLEFT", page, "TOPLEFT", 0, yy)
      yy = yy - ROW_H
      page.controls[o.key] = control
    end
    page.nextY = yy
    page.bottomY = yy
  end

  -- Test-frame buttons live on the General tab (order[1]), alongside the other
  -- addon-wide controls.
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
    firstPage.bottomY = yy
  end

  -- The Note tab carries the prepare-ahead editor, below its options.
  local notePage = panel.pages["Note"]
  if notePage then
    local ed, noteBottom = buildNoteEditor(notePage, (notePage.nextY or 0) - SECTION_GAP)
    notePage.noteEditor = ed
    notePage.bottomY = noteBottom
  end

  local aboutPage = newPage(ABOUT)
  buildAbout(aboutPage)
  aboutPage.bottomY = -300
  order[#order + 1] = ABOUT

  -- Size each scroll child to its content now that every page is laid out, so
  -- the scrollbar knows the range before the panel is first shown.
  for _, page in pairs(panel.pages) do
    page.contentH = math.max(1, -(page.bottomY or 0) + 12)
    page:SetHeight(page.contentH)
    if page.updateScroll then page.updateScroll() end
  end

  panel.refresh = function()
    for _, page in pairs(panel.pages) do
      for _, control in pairs(page.controls) do
        if control.refresh then control.refresh() end
      end
      if page.noteEditor and page.noteEditor.refresh then pcall(page.noteEditor.refresh) end
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

  -- A short modal for when the main can't be inferred on deletion (more than one
  -- other profile to choose from), so the user picks one first.
  local function mustSetMainAlert()
    if type(StaticPopupDialogs) == "table" and type(StaticPopup_Show) == "function" then
      StaticPopupDialogs["MYTHICPLUSTIMER_SET_MAIN_FIRST"] =
        StaticPopupDialogs["MYTHICPLUSTIMER_SET_MAIN_FIRST"] or {
          text = "Set another profile as main first, then delete this one.",
          button1 = OKAY or "Okay",
          timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
      StaticPopup_Show("MYTHICPLUSTIMER_SET_MAIN_FIRST")
    else
      ns.print("set another profile as main first, then delete this one.")
    end
  end

  -- Deletes the active profile. Any profile (Default included) can go as long as
  -- another remains. Deleting the account main needs a replacement: with exactly
  -- one other profile that one is promoted automatically; with several, the user
  -- is asked to choose a main first.
  local function deleteActive()
    local active = ns.activeProfile()
    local names = ns.profileNames()
    if #names <= 1 then return end
    local others = {}
    for _, n in ipairs(names) do if n ~= active then others[#others + 1] = n end end
    if active == ns.mainProfile() then
      if #others == 1 then
        ns.setMainProfile(others[1])
      else
        mustSetMainAlert()
        return
      end
    end
    -- Deleting the active profile re-resolves to the main in one step (a valid
    -- main is guaranteed above), so this is a single refresh. Switching first
    -- with loadProfile would fire a second full panel refresh, the source of a
    -- visible hitch on delete.
    ns.deleteProfile(active)
  end

  button(panel, "Reset", 110, function() ns.resetProfile() end):SetPoint("TOPLEFT", 266, -186)
  -- setMainProfile only writes the value, so redraw the list at once for the
  -- "main" tag to move without waiting on a later refresh.
  button(panel, "Set as main", 116, function()
    ns.setMainProfile(ns.activeProfile())
    panel.refresh()
  end):SetPoint("TOPLEFT", 382, -186)
  panel.deleteBtn = button(panel, "Delete", 110, deleteActive)
  panel.deleteBtn:SetPoint("TOPLEFT", 266, -212)

  -- Copy another profile's settings into this one, so a new profile can start
  -- from an existing look rather than the defaults (like Ace3's "Copy From").
  local copyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  copyLabel:SetPoint("TOPLEFT", 266, -242)
  copyLabel:SetText(GREY .. "Copy from" .. ENDC)
  panel.copyDD = dropdownWidget(panel, 150)
  panel.copyDD:SetPoint("TOPLEFT", 336, -238)
  panel.copyDD.placeholder = "another profile"

  -- An inline confirmation instead of a popup: a green line that shows what was
  -- copied and fades out on its own.
  panel.copyMsg = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.copyMsg:SetPoint("TOPLEFT", 266, -262)
  panel.copyMsg:SetAlpha(0)
  local ag = panel.copyMsg.CreateAnimationGroup and panel.copyMsg:CreateAnimationGroup()
  if ag and ag.CreateAnimation then
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0)
    fade:SetDuration(1.4); fade:SetStartDelay(1.4)
    ag:SetScript("OnFinished", function() panel.copyMsg:SetAlpha(0) end)
    panel.copyFade = ag
  end
  local function showCopied(name)
    panel.copyMsg:SetText(ns.GREEN .. "Copied settings from " .. name .. ENDC)
    panel.copyMsg:SetAlpha(1)
    if panel.copyFade then panel.copyFade:Stop(); panel.copyFade:Play() end
  end

  panel.copyDD.onSelect = function(v)
    if v and v ~= "" then
      ns.copyProfileFrom(v)  -- refreshes every panel (resets this dropdown)
      showCopied(v)
    end
    panel.copyDD:SetValue(nil)
  end

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
    -- Any profile can be deleted, so long as one remains to fall back to.
    panel.deleteBtn:SetEnabled(#ns.profileNames() > 1)
    panel.exportBox:SetText(ns.exportProfile() or "")
    multilineToTop(panel.exportBox)
    -- Copy-from lists every profile but the active one (its own source).
    local active, others = ns.activeProfile(), {}
    for _, n in ipairs(ns.profileNames()) do
      if n ~= active then others[#others + 1] = { value = n, label = n } end
    end
    panel.copyDD:SetChoices(others)
    panel.copyDD:SetValue(nil)
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
  -- OpenToCategory shows the main `settings` panel, so the edit-mode overlay's
  -- jump drives that one. Deferred a frame so the panel has laid out (and knows
  -- its scroll height) before we scroll it.
  ns.showSettingsSection = function(group, section)
    C_Timer.After(0, function() pcall(settings.showSection, group, section) end)
  end
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
