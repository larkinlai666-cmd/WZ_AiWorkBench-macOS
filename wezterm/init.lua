-- =============================================================================
--  AI STAR CUBE · macOS · Init hub (M3, pure Lua)
--  Contract distilled from upstream D-009/D-010/D-012 (bf1f6ef):
--    - Cold start / new tab land on the Init hub, never a bare shell.
--    - Two-step flow: task picker -> agent picker (default = desk-roots column 3
--      routed first; Enter = default; Esc/q = cancel, zero spawn).
--    - Gate R1: agent spawns only with a strong project root as cwd.
--    - Short-lived Init tab: after a successful spawn it closes itself (D-012).
--  Equal footing (D-M1-004): registry-driven; missing agents hide, never block.
-- =============================================================================

local wezterm = require("wezterm")
local act = wezterm.action
local desk = require("desk")
local agents = require("agents")

local M = {}

local home = wezterm.home_dir
local welcome_file = home .. "/.config/wezterm/workbench/welcome.txt"

local function toast(window, title, msg, ms)
  pcall(function()
    window:toast_notification(title, msg, nil, ms or 3000)
  end)
end

--- Welcome screen: static text file printed by default_prog (no config-load IO)
function M.welcome_args()
  return {
    "/bin/zsh",
    "-l",
    "-c",
    "cat " .. welcome_file .. " 2>/dev/null; exec zsh -l",
  }
end

--- Spawn a new tab and activate it; returns mux tab + pane
local function spawn_tab(window, pane, opts)
  local mux_window = window:mux_window()
  local tab, main = mux_window:spawn_tab(opts)
  if main then
    pcall(function()
      main:activate()
    end)
  end
  return tab, main
end

--- D-012: close the short-lived Init tab after a successful spawn
local function close_init_tab(window, pane)
  pcall(function()
    window:perform_action(act.CloseCurrentTab({ confirm = false }), pane)
  end)
end

--- Open an agent under a strong root (gate R1 enforced upstream of this call)
function M.open_task(window, pane, name, root, agent_id)
  root = desk.normalize(root)
  if not desk.is_strong_path(root) then
    toast(window, "AI STAR CUBE", "弱路径不能作为任务启动 — 先绑定真实项目", 4500)
    return
  end
  local agent = agent_id or agents.default_for(root)
  if not agent or not agents.is_installed(agent) then
    toast(window, "AI STAR CUBE", "未检测到可用 agent — 请先安装（codex/deepseek/kimi/grok 任一）", 4500)
    return
  end
  local entry = agents.entry(agent)
  local args = agents.new_args(agent, root)
  local tab, main = spawn_tab(window, pane, { args = args, cwd = root })
  if tab then
    pcall(function()
      tab:set_title(name .. " | " .. entry.display)
    end)
  end
  if main then
    desk.bind_tab(tab, root, main)
  end
  toast(window, "AI STAR CUBE", entry.display .. " · " .. name .. " · " .. desk.short_path(root, 42), 3000)
  -- D-012: this pane lives on the Init tab -> close it after successful spawn
  pcall(function()
    local title = ""
    pcall(function()
      title = tostring(pane:get_title() or "")
    end)
    if title:find("Init", 1, true) then
      close_init_tab(window, pane)
    end
  end)
end

--- Step 2: agent picker (equal footing). Single installed agent skips picker.
local function pick_agent(window, pane, name, root)
  local installed = agents.installed()
  if #installed == 0 then
    toast(window, "AI STAR CUBE", "未检测到 agent CLI — 请先安装一个（codex 等）", 4500)
    return
  end
  if #installed == 1 then
    M.open_task(window, pane, name, root, installed[1])
    return
  end
  local preferred = desk.agent_for_path(root)
  local choices = {}
  for _, id in ipairs(installed) do
    local entry = agents.entry(id)
    local label = entry.display
    if id == preferred then
      label = label .. "  ★默认(绑定)"
    elseif not preferred and id == agents.registry_order[1] then
      label = label .. "  ★默认"
    end
    table.insert(choices, { id = id, label = label })
  end
  window:perform_action(
    act.InputSelector({
      title = "2 AGENT · " .. name,
      fuzzy = false,
      choices = choices,
      action = wezterm.action_callback(function(w, p, id, _)
        if id then
          M.open_task(w, p, name, root, id)
        end
      end),
    }),
    pane
  )
end

--- Step 1: task picker (bound tasks + new project + shell escape)
function M.show_hub(window, pane)
  local choices = {}
  for _, item in ipairs(desk.roots_list()) do
    local agent_label = item.agent and agents.entry(item.agent) and agents.entry(item.agent).display or "?"
    table.insert(choices, {
      id = item.name,
      label = "[任务] " .. item.name .. " · " .. agent_label .. " → " .. desk.short_path(item.path, 40),
    })
  end
  table.insert(choices, { id = "__new__", label = "➕ 新建项目（冻结 name+path）" })
  table.insert(choices, { id = "__shell__", label = "■ 纯 Shell（不走任务流）" })

  local ok, err = pcall(function()
    window:perform_action(
      act.InputSelector({
        title = "1 TASK · AI STAR CUBE",
        fuzzy = true,
        fuzzy_description = "type to filter: ",
        choices = choices,
        action = wezterm.action_callback(function(w, p, id, _)
          if not id or id == "" then
            return
          end
          if id == "__new__" then
            M.new_project(w, p)
            return
          end
          if id == "__shell__" then
            spawn_tab(w, p, { args = { "/bin/zsh", "-l" }, cwd = home })
            return
          end
          local root = desk.get_root(id)
          if root then
            pick_agent(w, p, id, root)
          else
            toast(w, "AI STAR CUBE", "任务路径失效: " .. id, 4000)
          end
        end),
      }),
      pane
    )
  end)
  if not ok then
    toast(window, "AI STAR CUBE", "任务面板打开失败: " .. tostring(err), 5000)
  end
end

--- Scan one directory level for the parent picker (event-time spawn is legal)
local function scan_parents(root)
  local out = {}
  local ok, stdout = wezterm.run_child_process({
    "/bin/zsh",
    "-lc",
    "ls -d " .. root:gsub("'", "'\\''") .. "/*/ 2>/dev/null | head -n 40",
  })
  if ok and stdout then
    for line in tostring(stdout):gmatch("[^\r\n]+") do
      line = line:gsub("/$", "")
      if line ~= "" then
        table.insert(out, line)
      end
    end
  end
  return out
end

--- New project wizard (simplified, pure Lua): name -> parent -> freeze -> launch
function M.new_project(window, pane)
  local parent_choices = {
    { id = home, label = "🏠 Home（" .. home .. "）" },
    { id = home .. "/wz_build", label = "📁 wz_build（开发主目录）" },
    { id = home .. "/Documents", label = "📄 Documents" },
  }
  for _, p in ipairs(scan_parents(home .. "/wz_build")) do
    table.insert(parent_choices, { id = p, label = "📁 " .. desk.basename(p) .. "（" .. p .. "）" })
  end

  window:perform_action(
    act.PromptInputLine({
      description = "新建项目 · 输入项目名（q 取消）",
      action = wezterm.action_callback(function(w, p, line)
        if not line or line == "" or line == "q" or line == "Q" then
          return
        end
        local name = line:match("^%s*(.-)%s*$")
        if desk.is_reserved_name(name) then
          toast(w, "AI STAR CUBE", "保留名不可用: " .. name, 3500)
          return
        end
        w:perform_action(
          act.InputSelector({
            title = "选择父目录 · " .. name,
            fuzzy = false,
            choices = parent_choices,
            action = wezterm.action_callback(function(w2, p2, parent, _)
              if not parent then
                return
              end
              local root = parent .. "/" .. name
              local ok, out = wezterm.run_child_process({ "mkdir", "-p", root })
              if not ok then
                toast(w2, "AI STAR CUBE", "创建目录失败: " .. tostring(out), 4500)
                return
              end
              -- Freeze identity: marker + desk-roots row
              pcall(function()
                local f = io.open(root .. "/.wz-project", "w")
                if f then
                  f:write("# AI STAR CUBE project identity\n")
                  f:write("name=" .. name .. "\n")
                  f:write("path=" .. root .. "\n")
                  f:close()
                end
              end)
              desk.ensure_roots_dir()
              if desk.set_root(name, root) then
                toast(w2, "AI STAR CUBE", "已冻结: " .. name .. " → " .. desk.short_path(root, 42), 3500)
                pick_agent(w2, p2, name, root)
              else
                toast(w2, "AI STAR CUBE", "绑定失败（弱路径或保留名）", 4500)
              end
            end),
          }),
          p
        )
      end),
    }),
    pane
  )
end

function M.apply(config)
  wezterm.on("gui-startup", function(cmd)
    local tab, pane, window
    pcall(function()
      if cmd and cmd.args and #cmd.args > 0 then
        tab, pane, window = wezterm.mux.spawn_window(cmd)
      else
        tab, pane, window = wezterm.mux.spawn_window({
          args = M.welcome_args(),
          cwd = home,
        })
      end
    end)
    if tab then
      pcall(function()
        tab:set_title("Init")
      end)
    end
    pcall(function()
      local gui = window:gui_window()
      if gui then
        wezterm.time.call_after(0.8, function()
          pcall(function()
            local p = gui:active_pane()
            if p then
              M.show_hub(gui, p)
            end
          end)
        end)
      end
    end)
  end)
end

return M
