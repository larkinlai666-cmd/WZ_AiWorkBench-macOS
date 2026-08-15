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
WEZ="${WEZ:-$(command -v wezterm 2>/dev/null || echo "$HOME/.local/bin/wezterm")}"

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
  refresh_size
  local list_active=$(( step == 1 ))
  local chipTok rowTok
  local i n t

  # LIST column layout (upstream Update-ColLayout parity):
  #   - Project semi-flexible: INNER*14%, clamped [12, 22]
  #   - Path semi-flexible with a HARD cap of 34 — wide hosts never let it
  #     swallow the row; surplus becomes trailing whitespace (key_row pads
  #     flush-right), so columns stay aligned at any aspect ratio
  #   - narrow hosts squeeze in order Project -> Date -> Tag; ultra-narrow
  #     (<=68 cols) lets key_row hard-truncate the Agent tail, frame intact
  local W_DATE=13 W_TAG=6 W_AGENT=8 GAP=2
  local W_PROJ=$(( INNER * 14 / 100 ))
  (( W_PROJ > 22 )) && W_PROJ=22
  (( W_PROJ < 12 )) && W_PROJ=12
  local W_PATH=$(( INNER - 1 - 6 - W_DATE - W_TAG - W_AGENT - W_PROJ - 4 * GAP ))
  if (( W_PATH > 34 )); then
    W_PATH=34
  elif (( W_PATH < 16 )); then
    local need=$(( 16 - W_PATH ))
    local cut
    if (( need > 0 )) && (( W_PROJ > 12 )); then
      cut=$(( W_PROJ - 12 )); (( cut > need )) && cut=$need
      W_PROJ=$(( W_PROJ - cut )); need=$(( need - cut ))
    fi
    if (( need > 0 )) && (( W_DATE > 11 )); then
      cut=$(( W_DATE - 11 )); (( cut > need )) && cut=$need
      W_DATE=$(( W_DATE - cut )); need=$(( need - cut ))
    fi
    if (( need > 0 )) && (( W_TAG > 5 )); then
      cut=$(( W_TAG - 5 )); (( cut > need )) && cut=$need
      W_TAG=$(( W_TAG - cut )); need=$(( need - cut ))
    fi
    W_PATH=$(( INNER - 1 - 6 - W_DATE - W_TAG - W_AGENT - W_PROJ - 4 * GAP ))
    (( W_PATH < 10 )) && W_PATH=10
  fi

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
        "${rowTok}:$(pad_tail "${TASKS_PATH[$i]}" $W_PATH)" \
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

  # ----- 3 COMMAND (DarkGray frame; Yellow chips = sole input signal) -----
  # Regular 2-column grid: chip slot 11 + label slot 24, both columns flush.
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
  key_row "$D" "Y:$(pad '[ <num> ]' 11)" "D:  " "G:$(pad ' open task → pick agent' 24)" "D:  " "Y:$(pad '[ <t><a> ]' 11)" "D:  " "G: one-shot launch"
  key_row "$D" "Y:$(pad '[ n<num> ]' 11)" "D:  " "G:$(pad ' new session → agent' 24)" "D:  " "Y:$(pad '[ c ]' 11)" "D:  " "W: NEW TASK wizard"
  key_row "$D" "Y:$(pad '[ s ]' 11)" "D:  " "G:$(pad ' shell' 24)" "D:  " "Y:$(pad '[ a ]' 11)" "D:  " "G: all view"
  key_row "$D" "Y:$(pad '[ r ]' 11)" "D:  " "G:$(pad ' refresh' 24)" "D:  " "Y:$(pad '[ d ]' 11)" "D:  " "G: dash(grok)"
  key_row "$D" "Y:$(pad '[ q ]' 11)" "D:  " "G:$(pad ' quit panel' 24)"
  box_bottom "$D"
}

# =============================================================================
# new-task wizard (c): 4-step flow — name -> location -> agent -> confirm
# (upstream Invoke-NewTaskWizard 5-step distilled: CLI scan merges into step 3)
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

wizard_frame() {  # wizard_frame <step title>
  box_top "WZ NEW PROJECT · $1" "$M"
}

build_wizard_locations() {
  # Candidate parents (upstream Build-LocationOptions distilled):
  # RECOMMENDED (~/wz_build) -> RECENT (task parents) -> CWD; weak/dedup filtered.
  LOC_PATH=(); LOC_TAG=()
  local -A wl_seen
  local name ppath agent
  if [[ -d "$HOME/wz_build" ]] && ! is_weak_path "$HOME/wz_build"; then
    LOC_PATH+=("$HOME/wz_build"); LOC_TAG+=("RECOMMENDED"); wl_seen[$HOME/wz_build]=1
  fi
  if [[ -f "$ROOTS_FILE" ]]; then
    while IFS=$'\t' read -r name ppath agent; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      ppath="${ppath%/}"
      local par="${ppath%/*}"
      [[ -d "$par" ]] || continue
      is_weak_path "$par" && continue
      (( ${+wl_seen[$par]} )) && continue
      wl_seen[$par]=1
      LOC_PATH+=("$par"); LOC_TAG+=("RECENT")
    done < "$ROOTS_FILE"
  fi
  if [[ -d "$PWD" ]] && ! is_weak_path "$PWD" && (( ! ${+wl_seen[$PWD]} )); then
    wl_seen[$PWD]=1
    LOC_PATH+=("$PWD"); LOC_TAG+=("CWD")
  fi
  while (( ${#LOC_PATH} > 8 )); do
    LOC_PATH[-1]=(); LOC_TAG[-1]=()
  done
}

wizard() {
  local w_step=1 w_name="" w_parent="" w_agent=1 w_err=""
  local line n i def_idx root_path
  local -a LOC_PATH LOC_TAG

  while true; do
    case $w_step in
      1)
        print -n $'\e[2J\e[H'
        wizard_frame "Step 1/4 · project name"
        box_line "binding name = default folder name (q = cancel)" "$D"
        box_line "reserved names refused: home desktop documents config tmp usr etc" "$D"
        [[ -n "$w_err" ]] && { box_rule "$M"; box_line "! $w_err" "$R"; w_err=""; }
        box_rule "$M"
        key_row "$M" "Y:[q]" "D: cancel wizard"
        box_bottom "$M"
        print ""
        print -n "${Y}  project name > ${X}"
        read -r line || { print ""; clean_exit 0 }
        line="${line// /}"
        [[ -z "$line" || "$line" == "q" || "$line" == "Q" ]] && { hint="wizard cancelled"; return; }
        if is_reserved "$line"; then w_err="reserved name '$line' — pick another"; continue; fi
        w_name="$line"
        w_step=2
        ;;
      2)
        build_wizard_locations
        print -n $'\e[2J\e[H'
        wizard_frame "Step 2/4 · create location"
        box_line "NAME    $w_name" "$W"
        box_rule "$M"
        box_line "LOCATIONS  (enter a number; final = parent/$w_name)" "$D"
        [[ -n "$w_err" ]] && { box_rule "$M"; box_line "! $w_err" "$R"; w_err=""; }
        i=1
        while (( i <= ${#LOC_PATH} )); do
          key_row "$M" "Y:[$i]" "G: $(pad "${LOC_TAG[$i]}" 12)" "D:${LOC_PATH[$i]}"
          i=$(( i + 1 ))
        done
        if (( ${#LOC_PATH} == 0 )); then
          box_line "(no candidates — press 0 to type a parent folder)" "$D"
        fi
        box_rule "$M"
        key_row "$M" "Y:[0]" "G: type parent folder" "D:  " "Y:[b]" "D: back" "D:  " "Y:[q]" "D: cancel"
        box_bottom "$M"
        print ""
        print -n "${Y}  location > ${X}"
        read -r line || { print ""; clean_exit 0 }
        [[ "$line" == "q" || "$line" == "Q" ]] && { hint="wizard cancelled"; return; }
        [[ "$line" == "b" || "$line" == "B" ]] && { w_step=1; continue; }
        if [[ "$line" == "0" ]]; then
          print -n "${Y}  parent dir > ${X}"
          read -r line || { print ""; clean_exit 0 }
          [[ "$line" == "q" || "$line" == "Q" ]] && { hint="wizard cancelled"; return; }
          [[ "$line" == "b" || "$line" == "B" ]] && continue
          line="${line/#\~/$HOME}"
          [[ -z "$line" ]] && { w_err="empty parent — type a path or b"; continue; }
          [[ -d "$line" ]] || { w_err="parent missing: $line"; continue; }
          is_weak_path "$line/$w_name" && { w_err="weak path refused — never a system/home root"; continue; }
          w_parent="$line"
        elif [[ "$line" =~ ^[0-9]+$ ]]; then
          n=$line
          if (( n >= 1 && n <= ${#LOC_PATH} )); then
            w_parent="${LOC_PATH[$n]}"
          else
            w_err="no location #$n (1-${#LOC_PATH})"
            continue
          fi
        else
          w_err="type a number 1-${#LOC_PATH}, 0 = type parent, b = back, q = cancel"
          continue
        fi
        w_step=3
        ;;
      3)
        def_idx=$(default_agent_idx)
        (( w_agent < 1 || w_agent > ${#A_ID} )) && w_agent=$def_idx
        print -n $'\e[2J\e[H'
        wizard_frame "Step 3/4 · default agent"
        box_line "AGENTS  (enter a number; Enter = default)" "$D"
        [[ -n "$w_err" ]] && { box_rule "$M"; box_line "! $w_err" "$R"; w_err=""; }
        if (( ${#A_ID} == 0 )); then
          box_line "(no agent CLI detected — b to go back)" "$D"
        else
          i=1
          while (( i <= ${#A_ID} )); do
            local tag=""
            (( i == def_idx )) && tag="  (default)"
            key_row "$M" "Y:[$i]" "G: ${A_LABEL[$i]}" "D:$tag"
            i=$(( i + 1 ))
          done
        fi
        box_rule "$M"
        key_row "$M" "Y:[b]" "D: back" "D:  " "Y:[q]" "D: cancel"
        box_bottom "$M"
        print ""
        print -n "${Y}  agent (Enter = default) > ${X}"
        read -r line || { print ""; clean_exit 0 }
        line="${line// /}"
        [[ "$line" == "q" || "$line" == "Q" ]] && { hint="wizard cancelled"; return; }
        [[ "$line" == "b" || "$line" == "B" ]] && { w_step=2; continue; }
        if (( ${#A_ID} == 0 )); then w_err="no agent CLI detected"; continue; fi
        if [[ -z "$line" ]]; then
          w_agent=$def_idx
        elif [[ "$line" =~ ^[0-9]+$ ]] && (( line >= 1 && line <= ${#A_ID} )); then
          w_agent=$line
        else
          w_err="no agent #$line (Enter = default, 1-${#A_ID})"
          continue
        fi
        w_step=4
        ;;
      4)
        root_path="$w_parent/$w_name"
        print -n $'\e[2J\e[H'
        wizard_frame "Step 4/4 · confirm"
        box_line "NAME    $w_name" "$W"
        box_line "PATH    $root_path" "$W"
        box_line "AGENT   ${A_LABEL[$w_agent]}" "$W"
        [[ -n "$w_err" ]] && { box_rule "$M"; box_line "! $w_err" "$R"; w_err=""; }
        box_rule "$M"
        key_row "$M" "Y:[y]" "W: create & launch" "D:  " "Y:[b]" "D: back" "D:  " "Y:[q]" "D: cancel"
        box_bottom "$M"
        print ""
        print -n "${Y}  confirm (y = create & launch) > ${X}"
        read -r line || { print ""; clean_exit 0 }
        line="${line// /}"
        [[ "$line" == "q" || "$line" == "Q" ]] && { hint="wizard cancelled"; return; }
        [[ "$line" == "b" || "$line" == "B" ]] && { w_step=3; continue; }
        if [[ "$line" != "y" && "$line" != "Y" ]]; then
          w_err="type y to create & launch, b = back, q = cancel"
          continue
        fi
        mkdir -p "$root_path" 2>/dev/null || { w_err="mkdir failed: $root_path"; w_step=2; continue; }
        printf 'name=%s\npath=%s\n' "$w_name" "$root_path" > "$root_path/.wz-project"
        printf '%s\t%s\t%s\n' "$w_name" "$root_path" "${A_ID[$w_agent]}" >> "$ROOTS_FILE"
        launch_agent "$w_name" "$root_path" $w_agent
        ;;
    esac
  done
}

# =============================================================================
# input handling
# =============================================================================
step2_input() {
  local line def_idx
  def_idx=$(default_agent_idx)
  print -n "${Y}  agent 1-${#A_ID} (Enter = default, q = cancel) ${X}"
  read -r line || { print ""; clean_exit 0 }
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
  read -r line || { print ""; clean_exit 0 }
  line="${line// /}"
  [[ -z "$line" ]] && return
  if [[ "$line" == "q" || "$line" == "Q" ]]; then
    print "${D}  left panel.${X}"
    clean_exit 0
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
# main loop (resize-adaptive: refresh_size re-reads width on every repaint)
# =============================================================================
load_agents
load_tasks
panel_guard "init panel"

while true; do
  now="$(date '+%Y-%m-%d %H:%M')"
  render
  if (( step == 2 )); then
    step2_input
  else
    step1_input
  fi
done
