-- =============================================================================
--  AI STAR CUBE · macOS · top chrome
--  Three info classes only (upstream contract):
--    1) Brand  — fixed left anchor " ★ AI STAR CUBE " (gold, never moves)
--    2) Path   — full path, fixed left edge after brand, grows rightward (peach)
--    3) Tabs   — pure navigation "project · tool" (never paths, never literal Tab)
--  D-013: yellow is reserved for input only — never used in chrome.
-- =============================================================================

local wezterm = require("wezterm")
local desk = require("desk")
local agents = require("agents")

local M = {}

local STATUS_GEN = 1

local C = {
  brand_bg = "#f9e2af",
  brand_fg = "#11111b",
  path_bg = "#fab387",
  path_fg = "#11111b",
  path_empty_bg = "#1e1e2e",
  path_empty_fg = "#7f849c",
  gap_bg = "#11111b",
  tab_on_bg = "#89b4fa",
  tab_on_fg = "#11111b",
  tab_off_bg = "#1e1e2e",
  tab_off_fg = "#a6adc8",
  tab_hover_bg = "#45475a",
  tab_hover_fg = "#cdd6f4",
  tab_unseen_bg = "#1e1e2e",
  tab_unseen_fg = "#cdd6f4",
}

local BRAND_TEXT = "  ★  AI STAR CUBE   "
local BRAND_PATH_GAP = "   "

local function chip(cells, bg, fg, text, bold)
  table.insert(cells, { Background = { Color = bg } })
  table.insert(cells, { Foreground = { Color = fg } })
  if bold then
    table.insert(cells, { Attribute = { Intensity = "Bold" } })
  end
  table.insert(cells, { Text = text })
  table.insert(cells, "ResetAttributes")
end

local function path_display(root)
  root = desk.normalize(root)
  if not root or root == "" then
    return nil
  end
  if wezterm.home_dir and root:sub(1, #wezterm.home_dir) == wezterm.home_dir and #root > #wezterm.home_dir then
    root = "~" .. root:sub(#wezterm.home_dir + 1)
  end
  return root
end

local function tool_role(proc, title)
  proc = (proc or ""):lower()
  title = (title or ""):lower()
  for _, e in ipairs(agents.installed()) do
    if proc:find(e.id, 1, true) or title:find(e.id, 1, true) then
      return e.display
    end
  end
  if proc:find("zsh", 1, true) or proc:find("bash", 1, true) or proc:find("sh", 1, true) then
    return "Shell"
  end
  if title:find("init", 1, true) then
    return "Init"
  end
  if proc:find("node", 1, true) then
    return "AI"
  end
  -- Fallback: anything non-agent in the workbench is effectively a shell pane
  return "Shell"
end

local function nav_clean(label)
  if not label or label == "" then
    return nil
  end
  label = tostring(label):gsub("^%s+", ""):gsub("%s+$", "")
  if label:match("^/") then
    return desk.basename(label)
  end
  if label:match("^file:") then
    return desk.basename(label:gsub("^file:[/]*", ""))
  end
  local before = label:match("^(.-)%s*[·•|]%s*")
  if before and #before >= 1 then
    label = before
  end
  if #label > 16 then
    label = label:sub(1, 15) .. "..."
  end
  if label == "" or label == "." or label == ".." then
    return nil
  end
  return label
end

local function pane_has_unseen(p)
  if not p then
    return false
  end
  local hit = false
  pcall(function()
    if type(p) == "table" then
      if p.has_unseen_output == true then
        hit = true
        return
      end
      if p.pane ~= nil then
        local ok, v = pcall(function()
          return p.pane:has_unseen_output()
        end)
        if ok and v == true then
          hit = true
        end
      end
    else
      local ok, v = pcall(function()
        return p:has_unseen_output()
      end)
      if ok and v == true then
        hit = true
      end
    end
  end)
  return hit
end

local function tab_has_unseen(tab, pane, panes)
  local list = nil
  pcall(function()
    if tab and type(tab.panes) == "table" then
      list = tab.panes
    end
  end)
  if not list and type(panes) == "table" then
    list = panes
  end
  if type(list) == "table" then
    for _, p in ipairs(list) do
      if pane_has_unseen(p) then
        return true
      end
    end
  end
  return pane_has_unseen(pane)
end

local function build_left_status(root, bound)
  local left = {}
  chip(left, C.brand_bg, C.brand_fg, BRAND_TEXT, true)
  chip(left, C.gap_bg, C.gap_bg, BRAND_PATH_GAP)
  if not bound or not desk.is_strong_path(root) then
    chip(left, C.path_empty_bg, C.path_empty_fg, " (no project - Cmd+Shift+N) ", false)
  else
    chip(left, C.path_bg, C.path_fg, " " .. (path_display(root) or root) .. " ", true)
  end
  return wezterm.format(left)
end

local function paint_left(window, pane)
  pcall(function()
    local ap = window:active_pane()
    if ap then
      pane = ap
    end
  end)
  local _, root, bound = desk.resolve_active_for_hud(window, pane)
  pcall(function()
    window:set_left_status(build_left_status(root, bound))
  end)
end

function M.apply(config)
  wezterm.GLOBAL.macos_status_gen = STATUS_GEN
  config.status_update_interval = 500

  wezterm.on("update-status", function(window, pane)
    if wezterm.GLOBAL.macos_status_gen ~= STATUS_GEN then
      return
    end
    pcall(function()
      window:set_right_status("")
    end)
    paint_left(window, pane)
  end)

  wezterm.on("format-tab-title", function(tab, tabs, panes, conf, hover, max_width)
    if wezterm.GLOBAL.macos_status_gen ~= STATUS_GEN then
      return
    end
    local pane = tab.active_pane
    local proc = ""
    if pane then
      proc = desk.process_name(pane)
    end
    local title = tab.tab_title or ""
    local tool = tool_role(proc, title)
    if tool == "Tab" or tool == "tab" then
      tool = "App"
    end

    local project = nil
    local id = nil
    pcall(function()
      id = tab.tab_id
    end)
    local root = desk.get_tab_desk_by_id(id)
    if desk.is_strong_path(root) then
      project = desk.project_label(root)
    elseif title and tostring(title):find("|") then
      project = nav_clean(tostring(title):match("^(.-)%s*[|·•]%s*"))
    end
    if not project then
      local cwd = desk.cwd_from_pane(pane)
      if desk.is_strong_path(cwd) then
        project = desk.project_label(cwd)
      end
    end

    local label
    if project and project ~= "" and tool ~= "Init" and tool ~= "Shell" and tool ~= "App" then
      label = project .. " | " .. tool
    elseif project and project ~= "" then
      label = project
    else
      label = tool
    end
    local body = " " .. label .. " "

    local unseen = tab_has_unseen(tab, pane, panes)
    if tab.is_active then
      return {
        { Background = { Color = C.tab_on_bg } },
        { Foreground = { Color = C.tab_on_fg } },
        { Attribute = { Intensity = "Bold" } },
        { Text = body },
      }
    end
    if hover then
      return {
        { Background = { Color = C.tab_hover_bg } },
        { Foreground = { Color = C.tab_hover_fg } },
        { Text = body },
      }
    end
    if unseen then
      return {
        { Background = { Color = C.tab_unseen_bg } },
        { Foreground = { Color = C.tab_unseen_fg } },
        { Attribute = { Intensity = "Bold" } },
        { Text = body },
      }
    end
    return {
      { Background = { Color = C.tab_off_bg } },
      { Foreground = { Color = C.tab_off_fg } },
      { Text = body },
    }
  end)
end

return M
