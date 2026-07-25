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

-- ── Test frames ───────────────────────────────────────────────────────────
-- Puts every registered preview frame on screen at once for positioning, and
-- takes them away again. Knows nothing about which frames exist.

local previewShown = false

local function togglePreviews()
  previewShown = not previewShown
  for _, p in ipairs(ns.previews) do
    pcall(previewShown and p.show or p.hide)
  end
  ns.print(previewShown
    and "test frames are up. Drag them where you want them, then use this again."
    or "test frames hidden.")
end

ns.optionButton("Test frames", "Show or hide test frames",
  "Put every movable frame on screen at once so you can drag them where you want them. Use it again to hide them.",
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
