#!/bin/zsh
# =============================================================================
#  AI STAR CUBE · macOS · Init hub — static panel (zsh builtin runtime)
#  Inherits the upstream static-screen contract (D-009/D-010/D-012/D-013):
#    - static screen: repaint only on state change; zero repaint while typing
#    - three zones: HEADER / 1 LIST (Cyan) / 2 AGENT (Magenta) / 3 COMMAND
#    - line input: wz> / agent N — bright yellow prompt prefix
#    - two-step grammar: <num> -> agent · <t><a> one-shot · n<num> force-new
#    - bright yellow = the ONLY input-affordance color; frames never yellow
#    - short-lived tab (D-012): agent spawned -> panel exits -> tab closes
#  Alignment discipline: every line inside a box goes through key_row/box_line
#  and has EXACTLY INNER+4 display cells (checked by scripts/panel_visual_check.py).
#  WZ_ROOTS_FILE env override exists for the visual regression harness.
# =============================================================================
emulate -L zsh
set -u

WZ_DIR="$HOME/.config/wezterm"
ROOTS_FILE="${WZ_ROOTS_FILE:-$WZ_DIR/workbench/desk-roots.tsv}"
SPLASH_FILE="$WZ_DIR/splash.txt"
WEZ="$(command -v wezterm 2>/dev/null || echo "$HOME/.local/bin/wezterm")"

# ---- ANSI palette (D-013: bright yellow = input affordance only) ----
typeset Y=$'\e[33;1m'    # bright yellow — chips + prompt prefixes ONLY
typeset C=$'\e[36m'      # cyan — LIST zone border / info hint
typeset M=$'\e[35;1m'    # magenta — AGENT zone border
typeset D=$'\e[90m'      # dark gray — frames, static notes, inactive text
typeset W=$'\e[97m'      # white — primary text / active agent names
typeset G=$'\e[37m'      # gray — table row text
typeset R=$'\e[31;1m'    # red — errors
typeset E=$'\e[32;1m'    # green — success / (default) tag
typeset X=$'\e[0m'

# ---- terminal size ----
typeset COLS=80
typeset sz
sz=$(stty size 2>/dev/null)
if [[ -n "$sz" ]]; then
  COLS=${sz##* }
fi
(( COLS < 54 )) && COLS=54
typeset INNER=$(( COLS - 6 ))
typeset TOT=$(( INNER + 4 ))   # every box line = INNER+4 display cells

# ---- state ----
typeset -a AGENTS
typeset -a TASKS_NAME TASKS_PATH TASKS_AGENT
typeset step=1
typeset pending_idx=0
typeset force_new=0
typeset hint=""
typeset now=""

# =============================================================================
# width helpers (display cells, CJK = 2 — same wcwidth semantics WezTerm uses)
# =============================================================================
dwidth() {
  local s="$1" w=0
  local c
  for c in ${(s::)s}; do
    case "$c" in
      [$'\u1100'-$'\u115f']|[$'\u2e80'-$'\ua4cf']|[$'\uac00'-$'\ud7a3']|[$'\uf900'-$'\ufaff']|[$'\ufe30'-$'\ufe4f']|[$'\uff00'-$'\uff60']|[$'\uffe0'-$'\uffe6'])
        w=$(( w + 2 )) ;;
      *)
        w=$(( w + 1 )) ;;
    esac
  done
  print -n $w
}

pad() {  # pad <text> <width> — display-width aware; hard-truncate with '~'
  local t="$1" w="$2"
  local dw
  dw=$(dwidth "$t")
  if (( dw > w )); then
    local s="$t"
    while (( $(dwidth "$s") > w - 1 )) && (( ${#s} > 1 )); do
      s="${s[1,-2]}"
    done
    print -n "${s}~"
  else
    print -n "$t"
    local i
    for (( i = dw; i < w; i++ )); do print -n " "; done
  fi
}

# =============================================================================
# box primitives — every line exactly TOT cells wide
# =============================================================================
box_top() {  # box_top <title> <color>
  local title="$1"
  local colr="$2"
  local t=" $title "
  local tw
  tw=$(dwidth "$t")
  local fill=$(( INNER - tw ))
  (( fill < 0 )) && fill=0
  local left=$(( fill / 2 ))
  local right=$(( fill - left ))
  print -n "${colr}  +"
  local i
  for (( i = 0; i < left; i++ )); do print -n -- "-"; done
  print -n "$t"
  for (( i = 0; i < right; i++ )); do print -n -- "-"; done
  print "+${X}"
}

box_rule() {  # box_rule <color>
  local colr="$1" i
  print -n "${colr}  |"
  for (( i = 0; i < INNER; i++ )); do print -n -- "-"; done
  print "|${X}"
}

box_line() {  # box_line <text> <color> — 3 + INNER + 1 = TOT
  local text="$1" colr="$2"
  print -n "${colr}  |${X}"
  pad " $text" $INNER
  print "${colr}|${X}"
}

box_bottom() {  # box_bottom <color>
  local colr="$1" i
  print -n "${colr}  +"
  for (( i = 0; i < INNER; i++ )); do print -n -- "-"; done
  print "+${X}"
}

# Multi-segment row: "tok:text" pairs; pads to TOT; right border always flush.
key_row() {  # key_row <color> "chip:Y" "label:G" [ ... ]
  local colr="$1"; shift
  local seg tok v
  local -a texts=() colors=()
  for seg in "$@"; do
    tok="${seg%%:*}"
    v="${seg#*:}"
    texts+=("$v")
    colors+=("$tok")
  done
  local budget=$(( INNER - 1 ))
  local used=0 i w
  for (( i = 1; i <= ${#texts}; i++ )); do
    w=$(dwidth "${texts[$i]}")
    used=$(( used + w ))
  done
  if (( used > budget )); then
    # shrink the last segment to fit (upstream Limit-Display discipline)
    local last_text="${texts[-1]}"
    local last_w
    last_w=$(dwidth "$last_text")
    local room=$(( budget - (used - last_w) ))
    if (( room < 1 )); then
      texts[-1]=""
    else
      local s="$last_text"
      while (( $(dwidth "$s") > room )) && (( ${#s} > 1 )); do
        s="${s[1,-2]}"
      done
      texts[-1]="$s"
    fi
  fi
  used=0
  for (( i = 1; i <= ${#texts}; i++ )); do
    w=$(dwidth "${texts[$i]}")
    used=$(( used + w ))
  done
  local pad=$(( budget - used ))
  print -n "${colr}  |${X} "
  for (( i = 1; i <= ${#texts}; i++ )); do
    case "${colors[$i]}" in
      Y) print -n "${Y}${texts[$i]}${X}" ;;
      W) print -n "${W}${texts[$i]}${X}" ;;
      G) print -n "${G}${texts[$i]}${X}" ;;
      D) print -n "${D}${texts[$i]}${X}" ;;
      E) print -n "${E}${texts[$i]}${X}" ;;
      *) print -n "${texts[$i]}" ;;
    esac
  done
  local j
  for (( j = 0; j < pad; j++ )); do print -n " "; done
  print "${colr}|${X}"
}

# =============================================================================
# data load
# =============================================================================
detect_agents() {
  AGENTS=()
  command -v codex    >/dev/null 2>&1 && AGENTS+=(codex)
  command -v deepseek >/dev/null 2>&1 && AGENTS+=(deepseek)
  command -v kimi     >/dev/null 2>&1 && AGENTS+=(kimi)
  command -v grok     >/dev/null 2>&1 && AGENTS+=(grok)
}

agent_label() {
  case "$1" in
    codex) print -n "Codex" ;;
    deepseek) print -n "DeepSeek" ;;
    kimi) print -n "Kimi" ;;
    grok) print -n "Grok" ;;
    *) print -n "$1" ;;
  esac
}

load_tasks() {
  TASKS_NAME=(); TASKS_PATH=(); TASKS_AGENT=()
  local name path agent
  if [[ -f "$ROOTS_FILE" ]]; then
    while IFS=$'\t' read -r name path agent; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      path="${path%/}"
      [[ -d "$path" ]] || continue
      TASKS_NAME+=("$name")
      TASKS_PATH+=("$path")
      TASKS_AGENT+=("${agent:-${AGENTS[1]:-}}")
    done < "$ROOTS_FILE"
  fi
}

task_mtime() {  # task_mtime <path> -> "MM-dd HH:mm"
  stat -f '%Sm' -t '%m-%d %H:%M' "$1" 2>/dev/null || print -n "??-?? ??:??"
}

default_agent() {
  if (( ${#TASKS_AGENT[@]} > 0 )); then
    print -n "${TASKS_AGENT[1]}"
  elif (( ${#AGENTS[@]} > 0 )); then
    print -n "${AGENTS[1]}"
  else
    print -n "codex"
  fi
}

# =============================================================================
# render (static screen — called only on state change)
# =============================================================================
render() {
  print -n $'\e[2J\e[H'
  local list_active=$(( step == 1 ))
  local chipTok rowTok
  local i n t

  # LIST column widths (identical for header and rows)
  local W_DATE=13 W_TAG=6 W_PROJ=14 W_AGENT=8
  local W_PATH=$(( INNER - 1 - 3 - 3 - W_DATE - W_TAG - W_PROJ - W_AGENT ))
  (( W_PATH < 8 )) && W_PATH=8

  # ----- HEADER -----
  box_top "WZ INIT" "$D"
  box_line "$now   rows ${#TASKS_NAME}   top 9 · <t><a> combo on" "$D"
  if [[ -n "$hint" ]]; then
    box_rule "$D"
    box_line "! $hint" "$C"
    hint=""
  fi
  box_bottom "$D"
  print ""

  # ----- 1 LIST (Cyan border) -----
  local list_title
  if (( list_active )); then list_title="1 LIST  << step 1 · type task number"; else list_title="1 LIST"; fi
  box_top "$list_title" "$C"
  key_row "$C" \
    "D:[#]" \
    "D:   " \
    "D:$(pad 'DateTime' $W_DATE)" \
    "D:$(pad 'Tag' $W_TAG)" \
    "D:$(pad 'Project' $W_PROJ)" \
    "D:$(pad 'Path' $W_PATH)" \
    "D:$(pad 'Agent' $W_AGENT)"
  box_rule "$C"

  if (( ${#TASKS_NAME} == 0 )); then
    box_line "(empty)  press  c  in COMMAND to create first task" "$G"
  else
    if (( list_active )); then chipTok="Y"; rowTok="G"; else chipTok="D"; rowTok="D"; fi
    i=1
    while (( i <= ${#TASKS_NAME} )); do
      key_row "$C" \
        "${chipTok}:[$i]" \
        "${chipTok}:   " \
        "${rowTok}:$(pad "$(task_mtime "${TASKS_PATH[$i]}")" $W_DATE)" \
        "${rowTok}:$(pad '[任务]' $W_TAG)" \
        "${rowTok}:$(pad "${TASKS_NAME[$i]}" $W_PROJ)" \
        "${rowTok}:$(pad "${TASKS_PATH[$i]}" $W_PATH)" \
        "${rowTok}:$(pad "$(agent_label "${TASKS_AGENT[$i]}")" $W_AGENT)"
      i=$(( i + 1 ))
    done
  fi
  box_bottom "$C"
  print ""

  # ----- 2 AGENT (Magenta border; always visible) -----
  local agt_active=$(( step == 2 ))
  local ag_title
  if (( agt_active )); then
    ag_title="2 AGENT  << step 2 · pick agent for ${TASKS_NAME[$pending_idx]}"
  else
    ag_title="2 AGENT"
  fi
  box_top "$ag_title" "$M"
  if (( ${#AGENTS} == 0 )); then
    box_line "(no codex/deepseek/kimi/grok CLI detected)" "$D"
  else
    local a_chipTok a_nameTok a_modeTok
    if (( agt_active )); then a_chipTok="Y"; a_nameTok="W"; a_modeTok="G"; else a_chipTok="D"; a_nameTok="G"; a_modeTok="D"; fi
    local def
    def=$(default_agent)
    i=1
    for n in "${AGENTS[@]}"; do
      local mode="new"
      if (( agt_active && force_new == 0 )) && [[ "$n" == "${TASKS_AGENT[$pending_idx]}" ]]; then mode="resume"; fi
      local tag=""
      [[ "$n" == "$def" ]] && tag=" (default)"
      local segs=()
      segs+=("${a_chipTok}:[$i]")
      segs+=("${a_nameTok}: $(agent_label "$n")")
      segs+=("${a_modeTok}:  ${mode}")
      [[ -n "$tag" ]] && segs+=("E:${tag}")
      key_row "$M" "${segs[@]}"
      i=$(( i + 1 ))
    done
  fi
  box_rule "$M"
  if (( agt_active )); then
    box_line "type: agent number + Enter = that agent · Enter alone = (default) · q = cancel" "$W"
  else
    box_line "idle — step 1 first: type a task number below; agents light up on demand" "$D"
  fi
  box_bottom "$M"
  print ""

  # ----- 3 COMMAND (DarkGray frame; yellow chips = sole input signal) -----
  box_top "3 COMMAND  << type keys here" "$D"
  local field
  if (( step == 2 )); then
    field="step 2 ACTIVE: agent number + Enter  (Enter = default, q = cancel)"
  elif (( ${#TASKS_NAME} >= 1 && ${#TASKS_NAME} <= 9 )); then
    field="step 1 ACTIVE: task # · or one-shot <t><a> = task+agent launch"
  else
    field="step 1 ACTIVE: task number + Enter  (n<num> = new session)"
  fi
  key_row "$D" "Y: >_" "W:  $field"
  box_rule "$D"
  key_row "$D" "Y:[ <num> ]" "G: open task → pick agent in 2 AGENT" "D:  " "Y:[ <t><a> ]" "G: one-shot launch"
  key_row "$D" "Y:[ n<num> ]" "G: new session → pick agent" "D:  " "Y:[ c ]" "W: NEW TASK wizard" "D:  " "Y:[ s ]" "G: shell"
  box_rule "$D"
  key_row "$D" "Y:[r]" "D: refresh  " "Y:[q]" "D: quit panel"
  box_bottom "$D"
}

# =============================================================================
# spawn + close (D-012)
# =============================================================================
launch_agent() {  # launch_agent <name> <path> <agent>
  local name="$1" root="$2" agent="$3"
  local safe_root="${root//\'/\'\\\'\'}"
  local cmd="cat '$SPLASH_FILE' 2>/dev/null; sleep 0.3"
  case "$agent" in
    codex)    cmd+="; exec codex -C '$safe_root'" ;;
    grok)     cmd+="; exec grok --cwd '$safe_root'" ;;
    deepseek) cmd+="; clear; exec deepseek" ;;
    kimi)     cmd+="; exec kimi" ;;
    *)        cmd+="; exec zsh -l" ;;
  esac
  "$WEZ" cli spawn --cwd "$root" -- /bin/zsh -lc "$cmd" >/dev/null 2>&1
  # D-012: panel pane exits -> sole-pane tab closes with it
  exit 0
}

open_shell() {
  "$WEZ" cli spawn -- /bin/zsh -l >/dev/null 2>&1
}

# =============================================================================
# new-task wizard (c): name -> parent -> confirm-freeze -> launch
# =============================================================================
is_reserved() {
  case "${1:l}" in
    home|desktop|documents|downloads|library|applications|config|tmp|usr|etc|bin|var|sbin) return 0 ;;
    *) return 1 ;;
  esac
}

is_weak_path() {
  [[ -z "$1" ]] && return 0
  [[ "$1" == "/" || "$1" == "/tmp" || "$1" == "/var" || "$1" == "/etc" || "$1" == "/usr" || "$1" == "/bin" || "$1" == "/Library" || "$1" == "/System" || "$1" == "/Applications" ]] && return 0
  [[ "$1" == "$HOME" || "$1" == "$HOME/Desktop" || "$1" == "$HOME/Documents" || "$1" == "$HOME/Downloads" || "$1" == "$HOME/Library" || "$1" == "$HOME/Applications" || "$1" == "$HOME/.config" ]] && return 0
  [[ "$1" == "$HOME/Library"* ]] && return 0
  return 1
}

wizard() {
  print -n $'\e[2J\e[H'
  print "${D}  ============================================${X}"
  print "${W}   NEW TASK wizard${X}  ${D}(q at any prompt cancels)${X}"
  print "${D}  ============================================${X}"
  print ""
  print -n "${Y}  project name > ${X}"
  local name
  read -r name || return
  name="${name// /}"
  [[ -z "$name" || "$name" == "q" || "$name" == "Q" ]] && return
  if is_reserved "$name"; then
    hint="reserved name — pick another"
    return
  fi
  print ""
  print -n "${Y}  parent dir > ${X}"
  local parent
  read -r parent || return
  [[ "$parent" == "q" || "$parent" == "Q" ]] && return
  parent="${parent/#\~/$HOME}"
  [[ -z "$parent" ]] && parent="$HOME"
  [[ -d "$parent" ]] || { hint="parent missing: $parent"; return }
  local root="$parent/$name"
  if is_weak_path "$root"; then
    hint="weak path refused — home/Desktop/Documents root etc. never project roots"
    return
  fi
  mkdir -p "$root" 2>/dev/null || { hint="mkdir failed: $root"; return }
  printf 'name=%s\npath=%s\n' "$name" "$root" > "$root/.wz-project"
  local def
  def=$(default_agent)
  printf '%s\t%s\t%s\n' "$name" "$root" "$def" >> "$ROOTS_FILE"
  launch_agent "$name" "$root" "$def"
}

# =============================================================================
# input handling
# =============================================================================
step2_input() {
  local line
  print -n "${Y}  agent 1-${#AGENTS} (Enter = default, q = cancel) ${X}"
  read -r line || { print ""; exit 0 }
  line="${line// /}"
  local def
  def=$(default_agent)
  if [[ -z "$line" ]]; then
    launch_agent "${TASKS_NAME[$pending_idx]}" "${TASKS_PATH[$pending_idx]}" "$def"
  fi
  if [[ "$line" == "q" || "$line" == "Q" ]]; then
    step=1; pending_idx=0; force_new=0
    hint="launch cancelled"
    return
  fi
  if [[ "$line" =~ ^[0-9]+$ ]]; then
    local n=$line
    if (( n >= 1 && n <= ${#AGENTS} )); then
      launch_agent "${TASKS_NAME[$pending_idx]}" "${TASKS_PATH[$pending_idx]}" "${AGENTS[$n]}"
    fi
  fi
  hint="no such agent — Enter = default, 1-${#AGENTS}, q = cancel"
}

step1_input() {
  local line
  print -n "${Y}  wz> ${X}"
  read -r line || { print ""; exit 0 }
  line="${line// /}"
  [[ -z "$line" ]] && return
  if [[ "$line" == "q" || "$line" == "Q" ]]; then
    print "${D}  left panel.${X}"
    exit 0
  fi
  if [[ "$line" == "c" || "$line" == "C" ]]; then wizard; return; fi
  if [[ "$line" == "r" || "$line" == "R" ]]; then detect_agents; load_tasks; hint="refreshed"; return; fi
  if [[ "$line" == "s" || "$line" == "S" ]]; then
    if [[ -n "$WEZ" ]]; then
      open_shell
      hint="shell tab opened"
    else
      hint="wezterm not alive — cannot spawn shell tab"
    fi
    return
  fi
  # D-010 combo fast path: <t><a> two digits, one-shot launch
  if [[ "$line" =~ ^[0-9]{2}$ ]] && (( ${#TASKS_NAME} >= 1 && ${#TASKS_NAME} <= 9 )); then
    local t="${line[1]}" a="${line[2]}"
    if (( t >= 1 && t <= ${#TASKS_NAME} && a >= 1 && a <= ${#AGENTS} )); then
      launch_agent "${TASKS_NAME[$t]}" "${TASKS_PATH[$t]}" "${AGENTS[$a]}"
    fi
    hint="combo agent digit must be 1-${#AGENTS}"
    return
  fi
  if [[ "$line" =~ ^[nN][0-9]+$ ]]; then
    local d="${line:1}"
    if (( ${#d} > 4 )); then hint="number too long — n<num>=new session · q=quit"; return; fi
    local t=$d
    if (( t >= 1 && t <= ${#TASKS_NAME} )); then
      pending_idx=$t; force_new=1; step=2
    else
      hint="no task #$t"
    fi
    return
  fi
  if [[ "$line" =~ ^[0-9]+$ ]]; then
    if (( ${#line} > 4 )); then hint="number too long — <num>=task · <t><a>=one-shot · q=quit"; return; fi
    local t=$line
    if (( t >= 1 && t <= ${#TASKS_NAME} )); then
      pending_idx=$t; force_new=0; step=2
    else
      hint="no row #$line"
    fi
    return
  fi
  hint="unknown — <num>=task · n<num>=new · <t><a>=one-shot · c/s/r/q"
}

# =============================================================================
# main loop
# =============================================================================
detect_agents
load_tasks

while true; do
  now="$(date '+%Y-%m-%d %H:%M')"
  render
  if (( step == 2 )); then
    step2_input
  else
    step1_input
  fi
done
