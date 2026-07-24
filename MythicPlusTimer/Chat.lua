local _, ns = ...

local GOLD, GREY, ENDC, MP_PAD = ns.GOLD, ns.GREY, ns.ENDC, ns.PAD
local cfg, isSecret, mptPrint = ns.cfg, ns.isSecret, ns.print

-- ── Clickable links in chat ──────────────────────────────────────────────
-- Web addresses in chat become real hyperlinks. Clicking one opens a small box
-- with the address selected, ready for Ctrl+C (there is no browser API to open).
--
-- The message itself is never rewritten: the address is wrapped in link and
-- color escapes, and every other character passes through as it was sent.

-- Our own link type, caught and consumed before Blizzard's SetItemRef (which
-- only knows its own types) sees it.
local CL_TAG = "mpturl"
local CL_W, CL_H = 460, 300
local CL_MAX_LINES = 500

-- Only an explicit scheme or a www. host counts; a bare "example.com" is a guess.
local function clIsURL(s)
  return s:match("^https?://.") ~= nil or s:match("^www%.[%w%-]+%.") ~= nil
end

local function clWrap(url)
  return GOLD .. "|H" .. CL_TAG .. ":" .. url .. "|h" .. url .. "|h" .. ENDC
end

-- Splits a word into surrounding brackets/punctuation and the address itself.
-- Returns before, address, after.
local function clSplitWord(word)
  -- A color or link escape can sit flush against an address. A URL never
  -- contains "|", so everything from the first one belongs to the message.
  local core, tail = word, ""
  local pipe = core:find("|", 1, true)
  if pipe then core, tail = core:sub(1, pipe - 1), core:sub(pipe) end
  local before, rest = core:match("^([%(%[<\"']*)(.*)$")
  local addr, trail = rest:match("^(.-)([%.,;:!%?%)%]>\"']*)$")
  return before, addr, trail .. tail
end

local function clLinkifyPlain(text)
  return (text:gsub("%S+", function(word)
    local before, addr, after = clSplitWord(word)
    -- nil keeps the word exactly as it was, which is the common case.
    if not clIsURL(addr) then return nil end
    return before .. clWrap(addr) .. after
  end))
end

-- Rewrites only plain-text parts; existing hyperlinks pass through untouched
-- (nesting a link inside one breaks both).
local function clLinkify(msg)
  local out, i = {}, 1
  while true do
    local s, e = msg:find("|H.-|h.-|h", i)
    if not s then
      out[#out + 1] = clLinkifyPlain(msg:sub(i))
      break
    end
    out[#out + 1] = clLinkifyPlain(msg:sub(i, s - 1))
    out[#out + 1] = msg:sub(s, e)
    i = e + 1
  end
  return table.concat(out)
end

local function clFilter(_, _, msg, ...)
  if not cfg("chatlinks") then return false, msg, ... end
  if type(msg) ~= "string" or isSecret(msg) then return false, msg, ... end
  -- A message can pass through the filters more than once, and wrapping an
  -- address that is already wrapped produces a link that clicks to nothing.
  if msg:find("|H" .. CL_TAG .. ":", 1, true) then return false, msg, ... end
  -- Cheap reject first: the overwhelming majority of chat has no address in it
  -- at all, and this runs on every line the player sees.
  if not (msg:find("://", 1, true) or msg:find("www.", 1, true)) then
    return false, msg, ...
  end
  local ok, rewritten = pcall(clLinkify, msg)
  if not (ok and type(rewritten) == "string") then return false, msg, ... end
  return false, rewritten, ...
end

-- ── The copy box ─────────────────────────────────────────────────────────
-- One EditBox (the only selectable/copyable widget) filled either with one
-- clicked address or a whole chat window's text.

local clFrame
local function ensureCopyFrame()
  if clFrame then return clFrame end
  local f = CreateFrame("Frame", "MythicPlusTimerCopyFrame", UIParent, "BackdropTemplate")
  f:SetSize(CL_W, CL_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  -- Above the chat frame it was opened from, and above any panel over it.
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then pcall(f.SetResizeBounds, f, 280, 120, 1200, 800) end
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:SetClampedToScreen(true)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
    f:SetBackdropBorderColor(0.88, 0.65, 0.31, 0.9)
  end

  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.label:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD)

  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(24, 24)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  f.close:SetScript("OnClick", function() f:Hide() end)

  f.scroll = CreateFrame("ScrollFrame", "MythicPlusTimerCopyScroll", f, "UIPanelScrollFrameTemplate")
  f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", MP_PAD, -MP_PAD - 18)
  f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -MP_PAD - 20, MP_PAD + 16)

  f.box = CreateFrame("EditBox", "MythicPlusTimerCopyBox", f.scroll)
  f.box:SetMultiLine(true)
  f.box:SetAutoFocus(false)
  f.box:SetFontObject("ChatFontNormal")
  f.box:SetMaxLetters(0)
  f.box:SetWidth(CL_W - MP_PAD * 2 - 20)
  f.box:EnableMouse(true)
  f.box:SetScript("OnEscapePressed", function() f:Hide() end)
  f.scroll:SetScrollChild(f.box)

  f:SetScript("OnSizeChanged", function() f.box:SetWidth(f.scroll:GetWidth()) end)

  -- Bottom-right grip, the same one Blizzard puts on its own resizable windows.
  f.grip = CreateFrame("Button", nil, f)
  f.grip:SetSize(16, 16)
  f.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  f.grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MP_PAD, MP_PAD)
  f.hint:SetText(GREY .. "Ctrl+A selects all, Ctrl+C copies. Esc closes." .. ENDC)

  -- Esc closes it. Mutating this Blizzard list is fine; reassigning it isn't.
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "MythicPlusTimerCopyFrame")
  end

  f:Hide()
  clFrame = f
  return f
end

-- Opens the box on `text`, under `title`, with everything selected so a single
-- Ctrl+C takes it.
local function clShowCopy(title, text)
  local f = ensureCopyFrame()
  f.label:SetText(GOLD .. title .. ENDC)
  f.box:SetText(text)
  f:Show()
  f.scroll:SetVerticalScroll(0)  -- start at the top
  f.box:SetCursorPosition(0)
  f.box:HighlightText()
  f.box:SetFocus()
end

local function clIsOurs(link)
  return type(link) == "string" and link:sub(1, #CL_TAG + 1) == CL_TAG .. ":"
end

local clHooked = {}
local function clHookChatFrame(frame)
  if type(frame) ~= "table" or clHooked[frame] then return end
  clHooked[frame] = true
  -- Replace rather than HookScript: Blizzard's handler runs first and its
  -- SetItemRef throws on our link type. We call the original only for links that
  -- aren't ours, forwarding the full arg list it may use.
  local origClick = frame:GetScript("OnHyperlinkClick")
  frame:SetScript("OnHyperlinkClick", function(self, link, ...)
    if clIsOurs(link) then return clShowCopy("Link", link:sub(#CL_TAG + 2)) end
    if origClick then return origClick(self, link, ...) end
  end)
  local origEnter = frame:GetScript("OnHyperlinkEnter")
  frame:SetScript("OnHyperlinkEnter", function(self, link, ...)
    if clIsOurs(link) then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:AddLine(GOLD .. "Click to copy" .. ENDC)
      GameTooltip:Show()
      return
    end
    if origEnter then return origEnter(self, link, ...) end
  end)
  local origLeave = frame:GetScript("OnHyperlinkLeave")
  frame:SetScript("OnHyperlinkLeave", function(self, ...)
    GameTooltip:Hide()
    if origLeave then return origLeave(self, ...) end
  end)
end

-- ── Copy a chat window ───────────────────────────────────────────────────
-- A Copy button on each chat window puts that window's own history (read back
-- through GetNumMessages/GetMessageInfo) into the box.

-- Strips draw-only escapes so a line lands in the box as the words it showed.
local function clPlainText(msg)
  msg = msg:gsub("|T.-|t", "")            -- inline textures
  msg = msg:gsub("|A.-|a", "")            -- atlas markup
  msg = msg:gsub("|H.-|h(.-)|h", "%1")    -- links, keeping the display text
  msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
  msg = msg:gsub("|cn[%w_]+:", "")        -- named color form ("|cnIQ4:")
  msg = msg:gsub("|r", "")
  return msg
end

-- The color the window drew a line in (from GetMessageInfo's r/g/b), as a |cff
-- escape, so channel coloring survives into the box. nil when none was given.
local function clLineColor(r, g, b)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
  if isSecret(r) or isSecret(g) or isSecret(b) then return nil end
  local function chan(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return string.format("|cff%02x%02x%02x", chan(r), chan(g), chan(b))
end

-- The last CL_MAX_LINES lines of `frame`, each in the color the window drew it
-- in, or nil when this client does not let an addon read a chat window back.
local function clChatText(frame)
  if type(frame) ~= "table" or type(frame.GetNumMessages) ~= "function"
    or type(frame.GetMessageInfo) ~= "function" then
    return nil
  end
  local okN, count = pcall(frame.GetNumMessages, frame)
  if not (okN and type(count) == "number") then return nil end
  local lines = {}
  for i = math.max(1, count - CL_MAX_LINES + 1), count do
    local okM, msg, r, g, b = pcall(frame.GetMessageInfo, frame, i)
    -- isSecret must come before `msg ~= ""`: comparing a secret value throws.
    if okM and type(msg) == "string" and not isSecret(msg) and msg ~= "" then
      local color = clLineColor(r, g, b)
      local text = clPlainText(msg)
      lines[#lines + 1] = color and (color .. text .. ENDC) or text
    end
  end
  return table.concat(lines, "\n")
end

local function clCopyChatFrame(frame)
  local text = clChatText(frame)
  if not text then
    return mptPrint("this client will not let an addon read the chat window back.")
  end
  if text == "" then
    return mptPrint("that chat window has nothing in it yet.")
  end
  clShowCopy("Chat", text)
end

-- One button per chat window, so the visible one always belongs to the tab
-- you're looking at.
local function clAddCopyButton(frame)
  if frame.mptCopy then return end
  local b = CreateFrame("Button", nil, frame)
  b:SetSize(34, 14)
  b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
  b:SetFrameStrata("HIGH")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.text:SetAllPoints()
  b.text:SetText(GREY .. "Copy" .. ENDC)
  b:SetScript("OnEnter", function(self)
    self.text:SetText(GOLD .. "Copy" .. ENDC)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(GOLD .. "Copy this chat window" .. ENDC)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.text:SetText(GREY .. "Copy" .. ENDC)
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", function() clCopyChatFrame(frame) end)
  frame.mptCopy = b
end

-- Every ChatFrame, including popped-out windows. Bounded against a stray global.
local function clHookAllChatFrames()
  for i = 1, 50 do
    local f = _G["ChatFrame" .. i]
    if f then
      clHookChatFrame(f)
      if cfg("chatcopy") then
        clAddCopyButton(f)
        f.mptCopy:Show()
      elseif f.mptCopy then
        f.mptCopy:Hide()
      end
    end
  end
end

-- Player-typed channels only; system/combat text is left alone.
local CL_CHAT_TYPES = {
  "SAY", "YELL", "EMOTE", "GUILD", "OFFICER",
  "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
  "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
  "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM",
  "CHANNEL", "COMMUNITIES_CHANNEL",
}

local clFiltersAdded = false
local function clInstall()
  if not clFiltersAdded and type(ChatFrame_AddMessageEventFilter) == "function" then
    clFiltersAdded = true
    -- pcall each: the set of chat events differs by client build, and one
    -- unknown name would otherwise abort the rest of the install.
    for _, t in ipairs(CL_CHAT_TYPES) do
      pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_" .. t, clFilter)
    end
  end
  clHookAllChatFrames()
end

-- Re-scan when the chat windows change (a new one may have appeared).
local clLoader = CreateFrame("Frame")
clLoader:RegisterEvent("PLAYER_LOGIN")
for _, ev in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
  pcall(clLoader.RegisterEvent, clLoader, ev)
end
clLoader:SetScript("OnEvent", function() pcall(clInstall) end)

-- The Copy button's action for the window you're typing in (reachable with the
-- button off).
ns.command("copy", "copy the chat window", function()
  clCopyChatFrame(_G.SELECTED_CHAT_FRAME or _G.ChatFrame1)
end)

ns.onOptionChanged("chatcopy", function() pcall(clHookAllChatFrames) end)
