#!/bin/zsh
# =============================================================================
#  AI STAR CUBE · macOS · Init hub — static panel (zsh builtin runtime)
#  Inherits the upstream static-screen contract (D-009/D-010/D-012/D-013):
#    - static screen: repaint only on state change; zero repaint while typing
#    - three zones: HEADER / 1 LIST (Cyan) / 2 AGENT (Magenta) / 3 COMMAND
#    - line input: wz> / agent N — bright yellow prompt prefix
#    - two-step grammar: <num> -> agent · <t><a> one-shot · n<num> force-new
#    - a = all-view toggle · d = grok dashboard · c = wizard · s = shell
#    - bright yellow = the ONLY input-affordance color; frames never yellow
#    - short-lived tab (D-012): agent spawned -> panel exits -> tab closes
#  Agent source: workbench/agents.tsv — the SAME registry agents.lua reads.
#  WZ_ROOTS_FILE / WZ_AGENTS_FILE / WZ_LIB env overrides exist for the harness.
# =============================================================================
emulate -L zsh
set -u

WZ_DIR="$HOME/.config/wezterm"
ROOTS_FILE="${WZ_ROOTS_FILE:-$WZ_DIR/workbench/desk-roots.tsv}"
AGENT_FILE="${WZ_AGENTS_FILE:-$WZ_DIR/workbench/agents.tsv}"
SPLASH_FILE="$WZ_DIR/splash.txt"
WEZ="$(command -v wezterm 2>/dev/null || echo "$HOME/.local/bin/wezterm")"

source "${WZ_LIB:-$WZ_DIR/wzlib.zsh}"

# ---- state ----
typeset -a TASKS_NAME TASKS_PATH TASKS_AGENT
typeset step=1
typeset pending_idx=0
typeset force_new=0
typeset show_all=0
typeset hint=""
typeset now=""

# =============================================================================
# data load
# =============================================================================
load_tasks() {
  TASKS_NAME=(); TASKS_PATH=(); TASKS_AGENT=()
  local name ppath agent
  if [[ -f "$ROOTS_FILE" ]]; then
    while IFS=$'\t' read -r name ppath agent; do
      [[ -z "$name" || "$name" == \#* || "$name" == .* ]] && continue
      ppath="${ppath%/}"
      [[ -d "$ppath" ]] || continue
      TASKS_NAME+=("$name")
      TASKS_PATH+=("$ppath")
      TASKS_AGENT+=("${agent:-}")
    done < "$ROOTS_FILE"
  fi
}

task_mtime() {  # task_mtime <path> -> "MM-dd HH:mm"
  stat -f '%Sm' -t '%m-%d %H:%M' "$1" 2>/dev/null || print -n "??-?? ??:??"
}

default_agent_idx() {  # pending task bound agent (D-005) else first installed
  local bound bi
  if (( pending_idx >= 1 && pending_idx <= ${#TASKS_NAME} )); then
    bound="${TASKS_AGENT[$pending_idx]}"
    bi=$(agent_index_of "$bound")
    (( bi > 0 )) && { print -n $bi; return; }
  fi
  (( ${#A_ID} > 0 )) && print -n 1
}

# =============================================================================
# render (static screen — called only on state change)
# =============================================================================
render() {
  print -n $'\e[2J\e[H'
  local list_active=$(( step == 1 ))
  local chipTok rowTok
  local i n t

  # LIST column widths + 2-cell gap between columns (upstream ColGap)
  local W_DATE=13 W_TAG=6 W_PROJ=14 W_AGENT=8 GAP=2
  local W_PATH=$(( INNER - 1 - 3 - 3 - (W_DATE+GAP) - (W_TAG+GAP) - (W_PROJ+GAP) - GAP - W_AGENT ))
  (( W_PATH < 8 )) && W_PATH=8

  # ----- HEADER -----
  local view_txt
  if (( show_all == 1 )); then
    view_txt="ALL non-noise (combo off)"
  else
    view_txt="top 9 · <t><a> combo on"
  fi
  box_top "WZ INIT" "$D"
  box_line "$now   rows ${#TASKS_NAME}   $view_txt" "$D"
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
    "D:  " \
    "D:$(pad 'Tag' $W_TAG)" \
    "D:  " \
    "D:$(pad 'Project' $W_PROJ)" \
    "D:  " \
    "D:$(pad 'Path' $W_PATH)" \
    "D:  " \
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
        "${rowTok}:  " \
        "${rowTok}:$(pad '[任务]' $W_TAG)" \
        "${rowTok}:  " \
        "${rowTok}:$(pad "${TASKS_NAME[$i]}" $W_PROJ)" \
        "${rowTok}:  " \
        "${rowTok}:$(pad "${TASKS_PATH[$i]}" $W_PATH)" \
        "${rowTok}:  " \
        "${rowTok}:$(pad "${TASKS_AGENT[$i]}" $W_AGENT)"
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
  if (( ${#A_ID} == 0 )); then
    box_line "(no agent CLI detected — registry empty or exes missing)" "$D"
  else
    local a_chipTok a_nameTok a_modeTok
    if (( agt_active )); then a_chipTok="Y"; a_nameTok="W"; a_modeTok="G"; else a_chipTok="D"; a_nameTok="G"; a_modeTok="D"; fi
    local def_idx
    def_idx=$(default_agent_idx)
    i=1
    while (( i <= ${#A_ID} )); do
      local mode="new"
      if (( agt_active && force_new == 0 )) && [[ "${A_ID[$i]}" == "${TASKS_AGENT[$pending_idx]}" ]]; then mode="resume"; fi
      local tag=""
      (( i == def_idx )) && tag=" (default)"
      local segs=()
      segs+=("${a_chipTok}:[$i]")
      segs+=("${a_nameTok}: ${A_LABEL[$i]}")
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
  elif (( show_all == 0 && ${#TASKS_NAME} >= 1 && ${#TASKS_NAME} <= 9 )); then
    field="step 1 ACTIVE: task # · or one-shot <t><a> = task+agent launch"
  else
    field="step 1 ACTIVE: task number + Enter  (n<num> = new session)"
  fi
  key_row "$D" "Y: >_" "W:  $field"
  box_rule "$D"
  key_row "$D" "Y:[ <num> ]" "G: open task → pick agent in 2 AGENT" "D:  " "Y:[ <t><a> ]" "G: one-shot launch"
  key_row "$D" "Y:[ n<num> ]" "G: new session → pick agent" "D:  " "Y:[ c ]" "W: NEW TASK wizard" "D:  " "Y:[ s ]" "G: shell"
  box_rule "$D"
  key_row "$D" "Y:[a]" "D: all view  " "Y:[r]" "D: refresh  " "Y:[d]" "D: dash(grok)  " "Y:[q]" "D: quit panel"
  box_bottom "$D"
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
  local def_id
  (( ${#A_ID} > 0 )) && def_id="${A_ID[1]}" || def_id="codex"
  printf '%s\t%s\t%s\n' "$name" "$root" "$def_id" >> "$ROOTS_FILE"
  local di
  di=$(agent_index_of "$def_id")
  launch_agent "$name" "$root" $di
}

# =============================================================================
# input handling
# =============================================================================
step2_input() {
  local line def_idx
  def_idx=$(default_agent_idx)
  print -n "${Y}  agent 1-${#A_ID} (Enter = default, q = cancel) ${X}"
  read -r line || { print ""; exit 0 }
  line="${line// /}"
  if [[ -z "$line" ]]; then
    launch_agent "${TASKS_NAME[$pending_idx]}" "${TASKS_PATH[$pending_idx]}" $def_idx
  fi
  if [[ "$line" == "q" || "$line" == "Q" ]]; then
    step=1; pending_idx=0; force_new=0
    hint="launch cancelled"
    return
  fi
  if [[ "$line" =~ ^[0-9]+$ ]]; then
    local n=$line
    if (( n >= 1 && n <= ${#A_ID} )); then
      launch_agent "${TASKS_NAME[$pending_idx]}" "${TASKS_PATH[$pending_idx]}" $n
    fi
  fi
  hint="no such agent — Enter = default, 1-${#A_ID}, q = cancel"
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
  if [[ "$line" == "r" || "$line" == "R" ]]; then load_agents; load_tasks; hint="refreshed"; return; fi
  if [[ "$line" == "a" || "$line" == "A" ]]; then
    if (( show_all == 0 )); then show_all=1; else show_all=0; fi
    return
  fi
  if [[ "$line" == "d" || "$line" == "D" ]]; then
    if open_dash; then
      hint="Dashboard opened (grok only, not a project session)"
    else
      hint="Dashboard 需要 grok CLI（当前未安装）— d 已禁用"
    fi
    return
  fi
  if [[ "$line" == "s" || "$line" == "S" ]]; then
    if [[ -n "$WEZ" ]]; then
      open_shell
      hint="shell tab opened"
    else
      hint="wezterm not alive — cannot spawn shell tab"
    fi
    return
  fi
  # D-010 combo fast path: <t><a> two digits, one-shot launch (default view only)
  if [[ "$line" =~ ^[0-9]{2}$ ]] && (( show_all == 0 && ${#TASKS_NAME} >= 1 && ${#TASKS_NAME} <= 9 )); then
    local t="${line[1]}" a="${line[2]}"
    if (( t >= 1 && t <= ${#TASKS_NAME} && a >= 1 && a <= ${#A_ID} )); then
      launch_agent "${TASKS_NAME[$t]}" "${TASKS_PATH[$t]}" $a
    fi
    hint="combo agent digit must be 1-${#A_ID}"
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
  hint="unknown — <num>=task · n<num>=new · <t><a>=one-shot · a/c/s/r/d/q"
}

# =============================================================================
# main loop
# =============================================================================
load_agents
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
