-- AI STAR CUBE · macOS · appearance, window chrome, scrollback, mouse
local wezterm = require("wezterm")

local M = {}

function M.apply(config)
  ------------------------------------------------------------------
  -- Window chrome
  ------------------------------------------------------------------
  config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
  config.window_background_opacity = 0.97
  config.macos_window_background_blur = 20
  config.initial_cols = 140
  config.initial_rows = 40
  config.window_padding = { left = 8, right = 8, top = 6, bottom = 6 }
  config.window_close_confirmation = "NeverPrompt"
  config.adjust_window_size_when_changing_font_size = false
  config.warn_about_missing_glyphs = false

  ------------------------------------------------------------------
  -- Tabs / top nav bar (tab-first policy)
  ------------------------------------------------------------------
  config.use_fancy_tab_bar = true
  config.tab_bar_at_bottom = false
  config.hide_tab_bar_if_only_one_tab = false
  config.show_new_tab_button_in_tab_bar = true
  config.show_tab_index_in_tab_bar = false
  config.tab_max_width = 20
  config.switch_to_last_active_tab_when_closing_tab = true
  config.prefer_to_spawn_tabs = true

  ------------------------------------------------------------------
  -- Fonts (macOS stable chain)
  ------------------------------------------------------------------
  config.font = wezterm.font_with_fallback({ "Menlo", "Apple Color Emoji" })
  config.font_size = 13.0
  config.line_height = 1.08
  config.cell_width = 1.0

  ------------------------------------------------------------------
  -- Colors
  --  D-013: bright yellow reserved for input prompts only.
  --  Chrome palette: brand gold / path peach / active tab blue / surface mantle.
  ------------------------------------------------------------------
  config.color_scheme = "Catppuccin Mocha"
  config.inactive_pane_hsb = { saturation = 0.75, brightness = 0.55 }
  config.colors = {
    tab_bar = {
      background = "#11111b",
      active_tab = { bg_color = "#89b4fa", fg_color = "#11111b", intensity = "Bold" },
      inactive_tab = { bg_color = "#1e1e2e", fg_color = "#a6adc8" },
      inactive_tab_hover = { bg_color = "#45475a", fg_color = "#cdd6f4" },
      new_tab = { bg_color = "#11111b", fg_color = "#6c7086" },
      new_tab_hover = { bg_color = "#313244", fg_color = "#89b4fa" },
    },
    split = "#45475a",
  }

  ------------------------------------------------------------------
  -- Scrollback / selection
  ------------------------------------------------------------------
  config.scrollback_lines = 100000
  config.enable_scroll_bar = true
  config.min_scroll_bar_height = "2cell"

  ------------------------------------------------------------------
  -- Cursor & bell
  ------------------------------------------------------------------
  config.default_cursor_style = "BlinkingBar"
  config.cursor_blink_rate = 500
  config.visual_bell = { fade_in_function = "EaseIn", fade_in_duration_ms = 80, fade_out_function = "EaseOut", fade_out_duration_ms = 120 }
  config.audible_bell = "Disabled"

  ------------------------------------------------------------------
  -- Input / terminal capability (agent TUI friendly)
  ------------------------------------------------------------------
  config.term = "xterm-256color"
  config.enable_kitty_keyboard = true
  config.use_ime = true
  config.ime_preedit_rendering = "Builtin"

  ------------------------------------------------------------------
  -- Mouse: plain click completes selection only; open link = Cmd+Click
  -- (D-014 upstream semantics, launcher extensions never become links)
  ------------------------------------------------------------------
  config.hide_mouse_cursor_when_typing = true
  config.swallow_mouse_click_on_pane_focus = false
  config.swallow_mouse_click_on_window_focus = true
  config.mouse_bindings = {
    { event = { Up = { streak = 1, button = "Left" } }, mods = "NONE", action = wezterm.action.CompleteSelection("Clipboard") },
    { event = { Up = { streak = 1, button = "Left" } }, mods = "SUPER", action = wezterm.action.OpenLinkAtMouseCursor },
    { event = { Up = { streak = 1, button = "Middle" } }, mods = "NONE", action = wezterm.action.OpenLinkAtMouseCursor },
    { event = { Up = { streak = 1, button = "Right" } }, mods = "NONE", action = wezterm.action.PasteFrom("Clipboard") },
    { event = { Down = { streak = 3, button = "Left" } }, mods = "NONE", action = wezterm.action.SelectTextAtMouseCursor("Line") },
  }

  ------------------------------------------------------------------
  -- Shell / new-tab default: Init static panel (M4)
  ------------------------------------------------------------------
  local init = require("init")
  config.default_prog = init.panel_args()
  config.default_cwd = wezterm.home_dir

  ------------------------------------------------------------------
  -- Performance
  ------------------------------------------------------------------
  config.max_fps = 120
  config.animation_fps = 60
end

return M
