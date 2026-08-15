#!/bin/zsh
# =============================================================================
#  AI STAR CUBE · macOS · Explorer — static panel (zsh builtin runtime)
#  Inherits the upstream sidebar contract (F-006 + Show-Listing):
#    - static screen: HEADER / 1 LOCATION (green) / 2 FILES (cyan) / 3 COMMAND
#    - VIEW vs DESK split; out-of-tree VIEW gets a red warning + s returns
#    - numbered navigation; dirs descend, files open via `open`
#    - r force refresh · a auto-refresh toggle · g AI@VIEW · gd AI@DESK
#    - b bind VIEW as DESK · w shell tab · p copy path · f favorite · q quit
#    - D-013: bright yellow = input affordance only
#    - D-012: agent spawned -> panel exits -> sole-pane tab closes
#  Usage: explorer.sh [DESK]   (DESK = task root, passed by Cmd+Shift+E)
# =============================================================================
emulate -L zsh
set -u

WZ_DIR="$HOME/.config/wezterm"
ROOTS_FILE="${WZ_ROOTS_FILE:-$WZ_DIR/workbench/desk-roots.tsv}"
AGENT_FILE="${WZ_AGENTS_FILE:-$WZ_DIR/workbench/agents.tsv}"
FAV_FILE="${WZ_FAV_FILE:-$WZ_DIR/workbench/favorites.tsv}"
WEZ="${WEZ:-$(command -v wezterm 2>/dev/null || echo "$HOME/.local/bin/wezterm")}"

source "${WZ_LIB:-$WZ_DIR/wzlib.zsh}"

# ---- state ----
DESK="${1:-}"
VIEW=""
auto=0
hint=""
now=""
typeset -a FAV_NAME FAV_PATH DIRS FILES

is_weak_path() {
  [[ -z "$1" ]] && return 0
  [[ "$1" == "/" || "$1" == "/tmp" || "$1" == "/var" || "$1" == "/etc" || "$1" == "/usr" || "$1" == "/bin" || "$1" == "/Library" || "$1" == "/System" || "$1" == "/Applications" ]] && return 0
  [[ "$1" == "$HOME" || "$1" == "$HOME/Desktop" || "$1" == "$HOME/Documents" || "$1" == "$HOME/Downloads" || "$1" == "$HOME/Library" || "$1" == "$HOME/Applications" || "$1" == "$HOME/.config" ]] && return 0
  [[ "$1" == "$HOME/Library"* ]] && return 0
  return 1
}

resolve_desk() {
  DESK="${DESK%/}"
  if [[ -n "$DESK" && -d "$DESK" ]]; then
    return
  fi
  if [[ -f "$ROOTS_FILE" ]]; then
    local name ppath agent
    while IFS=$'\t' read -r name ppath agent; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      if [[ -d "$ppath" ]]; then
        DESK="${ppath%/}"
        return
      fi
    done < "$ROOTS_FILE"
  fi
  DESK="$HOME/wz_build"
}

under_desk() {  # VIEW inside DESK tree?
  [[ "$VIEW/" == "$DESK/"* ]]
}

workspace_name() {
  print -n "${DESK##*/}"
}

load_favs() {
  FAV_NAME=(); FAV_PATH=()
  local name ppath
  if [[ -f "$FAV_FILE" ]]; then
    while IFS=$'\t' read -r name ppath; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      FAV_NAME+=("$name")
      FAV_PATH+=("$ppath")
    done < "$FAV_FILE"
  fi
}

fav_contains() {  # <path> -> 1/0
  local p="$1" i
  i=1
  while (( i <= ${#FAV_PATH} )); do
    [[ "${FAV_PATH[$i]%/}" == "$p" ]] && { print -n 1; return; }
    i=$(( i + 1 ))
  done
  print -n 0
}

toggle_fav() {  # <name> <path>
  local name="$1"
  local ppath="$2"
  local found=0
  local tmpf
  tmpf=$(mktemp /tmp/wz-fav.XXXXXX)
  local n p
  if [[ -f "$FAV_FILE" ]]; then
    while IFS=$'\t' read -r n p; do
      [[ "${p%/}" == "$ppath" ]] && { found=1; continue; }
      printf '%s\t%s\n' "$n" "$p" >> "$tmpf"
    done < "$FAV_FILE"
  fi
  if (( found == 0 )); then
    printf '%s\t%s\n' "$name" "$ppath" >> "$tmpf"
  fi
  mv "$tmpf" "$FAV_FILE" 2>/dev/null
  load_favs
}

bind_view_as_desk() {  # write VIEW into desk-roots (update row if name exists)
  local name="${VIEW##*/}"
  local ppath="$VIEW"
  if is_weak_path "$ppath"; then
    hint="weak path refused — never a project root"
    return
  fi
  if [[ "$name" == .* ]]; then
    hint="hidden dir refused — metadata never a project root (use gd for AI here)"
    return
  fi
  local found=0
  local tmpf
  tmpf=$(mktemp /tmp/wz-roots.XXXXXX)
  local n p a
  if [[ -f "$ROOTS_FILE" ]]; then
    while IFS=$'\t' read -r n p a; do
      if [[ -z "$n" || "$n" == \#* ]]; then
        printf '%s\n' "$n" >> "$tmpf"
        continue
      fi
      if [[ "$n" == "$name" ]]; then
        found=1
        local def_a="${a:-}"
        printf '%s\t%s\t%s\n' "$n" "$ppath" "$def_a" >> "$tmpf"
      else
        printf '%s\t%s\t%s\n' "$n" "$p" "$a" >> "$tmpf"
      fi
    done < "$ROOTS_FILE"
  fi
  if (( found == 0 )); then
    local def_id
    (( ${#A_ID} > 0 )) && def_id="${A_ID[1]}" || def_id="codex"
    printf '%s\t%s\t%s\n' "$name" "$ppath" "$def_id" >> "$tmpf"
  fi
  mv "$tmpf" "$ROOTS_FILE" 2>/dev/null
  DESK="$ppath"
  hint="bound VIEW as DESK: $name"
}

list_view() {
  DIRS=(); FILES=()
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if [[ -d "$VIEW/$entry" ]]; then
      DIRS+=("$entry")
    else
      FILES+=("$entry")
    fi
  done < <(ls -1A "$VIEW" 2>/dev/null | head -n 40)
}

copy_path() {
  print -n "$VIEW" | pbcopy 2>/dev/null && hint="path copied" || hint="copy failed"
}

launch_at() {  # launch_at <path> — default agent (bound column-3 first)
  local root="$1"
  root="${root%/}"
  if is_weak_path "$root"; then
    hint="weak path refused — AI needs a real project root"
    return
  fi
  local idx=1 bound bi
  local n p a
  if [[ -f "$ROOTS_FILE" ]]; then
    while IFS=$'\t' read -r n p a; do
      [[ "${p%/}" == "$root" && -n "$a" ]] && bound="$a"
    done < "$ROOTS_FILE"
  fi
  if [[ -n "$bound" ]]; then
    bi=$(agent_index_of "$bound")
    (( bi > 0 )) && idx=$bi
  fi
  (( ${#A_ID} == 0 )) && { hint="no agent CLI detected"; return; }
  launch_agent "${root##*/}" "$root" $idx
}

# =============================================================================
# render
# =============================================================================
render() {
  print -n $'\e[2J\e[H'
  refresh_size
  local autoLabel
  if (( auto == 1 )); then autoLabel="AUTO-ON"; else autoLabel="AUTO-OFF"; fi

  # ----- HEADER -----
  box_top "EXPLORER  $(workspace_name)" "$D"
  box_line "refresh  $autoLabel  |  r force  |  a toggle auto" "$D"
  if [[ -n "$hint" ]]; then
    box_rule "$D"
    box_line "! $hint" "$C"
    hint=""
  fi
  box_bottom "$D"
  print ""

  # ----- 1 LOCATION (green) -----
  box_top "1 LOCATION" "$V"
  local maxp=$(( INNER - 8 ))
  (( maxp < 12 )) && maxp=12
  local view_label desk_label
  view_label=$(pad_tail "$VIEW" $maxp)
  desk_label=$(pad_tail "$DESK" $maxp)
  key_row "$V" "D:VIEW  " "W:${view_label}"
  if ! under_desk; then
    key_row "$V" "D:DESK  " "G:${desk_label}"
    box_rule "$V"
    box_line "! left DESK tree - press s to return" "$R"
  fi
  box_bottom "$V"
  print ""

  # ----- 2 FILES (cyan) -----
  box_top "2 FILES" "$C"
  local idx=1 i
  # favorites first
  if (( ${#FAV_NAME} > 0 )); then
    key_row "$C" "D:★ favorites" "D:  " "D:(f toggles)"
    box_rule "$C"
    i=1
    while (( i <= ${#FAV_NAME} )); do
      key_row "$C" "Y:[$idx]" "G: ★ ${FAV_NAME[$i]}" "D:  " "D:$(pad_tail "${FAV_PATH[$i]}" $(( INNER - 14 )))"
      idx=$(( idx + 1 ))
      i=$(( i + 1 ))
    done
  fi
  # dirs (cyan + trailing slash, upstream style)
  i=1
  while (( i <= ${#DIRS} )); do
    key_row "$C" "Y:[$idx]" "C:   ${DIRS[$i]}/"
    idx=$(( idx + 1 ))
    i=$(( i + 1 ))
  done
  # files
  i=1
  while (( i <= ${#FILES} )); do
    key_row "$C" "Y:[$idx]" "G:   ${FILES[$i]}"
    idx=$(( idx + 1 ))
    i=$(( i + 1 ))
  done
  if (( idx == 1 )); then
    box_line "(empty)" "$D"
  fi
  box_bottom "$C"
  print ""

  # ----- 3 COMMAND (dark gray) -----
  box_top "3 COMMAND  << type keys here" "$D"
  key_row "$D" "Y: >_" "W:  explorer> number = enter/open · q = quit"
  box_rule "$D"
  key_row "$D" "Y:[0/..]" "G: parent  " "Y:[s]" "G: back to DESK  " "Y:[r]" "G: refresh  " "Y:[a]" "D: auto"
  key_row "$D" "Y:[g]" "W: AI@VIEW  " "Y:[gd]" "W: AI@DESK  " "Y:[b]" "G: bind VIEW  " "Y:[w]" "G: shell"
  box_rule "$D"
  key_row "$D" "Y:[p]" "D: copy path  " "Y:[f]" "D: favorite  " "Y:[q]" "D: quit"
  box_bottom "$D"
}

# =============================================================================
# input
# =============================================================================
dispatch() {
  local line="$1"
  line="${line// /}"
  [[ -z "$line" ]] && return
  case "$line" in
    q|Q) print "${D}  left explorer.${X}"; exit 0 ;;
    r|R) list_view; load_favs; return ;;
    a|A) if (( auto == 0 )); then auto=1; else auto=0; fi; return ;;
    0|..|u|U)
      local parent="${VIEW%/*}"
      [[ -z "$parent" || "$parent" == "$VIEW" ]] && { hint="already at root"; return; }
      VIEW="$parent"
      list_view
      return ;;
    s|S) VIEW="$DESK"; list_view; return ;;
    g)
      launch_at "$VIEW"
      return ;;
    gd)
      launch_at "$DESK"
      return ;;
    b|B) bind_view_as_desk; return ;;
    w|W)
      open_shell
      hint="shell tab opened"
      return ;;
    p|P) copy_path; return ;;
    f|F)
      if (( $(fav_contains "$VIEW") == 1 )); then
        toggle_fav "${VIEW##*/}" "$VIEW"
        hint="favorite removed"
      else
        toggle_fav "${VIEW##*/}" "$VIEW"
        hint="favorite added"
      fi
      return ;;
  esac
  if [[ "$line" =~ ^[0-9]+$ ]]; then
    local n=$line total
    total=$(( ${#FAV_NAME} + ${#DIRS} + ${#FILES} ))
    if (( n < 1 || n > total )); then
      hint="no entry #$n (1-$total)"
      return
    fi
    local t=$n
    if (( t <= ${#FAV_NAME} )); then
      VIEW="${FAV_PATH[$t]}"
      list_view
      return
    fi
    t=$(( t - ${#FAV_NAME} ))
    if (( t <= ${#DIRS} )); then
      VIEW="$VIEW/${DIRS[$t]}"
      list_view
      return
    fi
    t=$(( t - ${#DIRS} ))
    open "$VIEW/${FILES[$t]}" 2>/dev/null
    hint="opened ${FILES[$t]}"
    return
  fi
  hint="unknown — number · 0/.. · s · g · gd · b · w · p · f · r · a · q"
}

# =============================================================================
# main loop
# =============================================================================
load_agents
resolve_desk
VIEW="$DESK"
load_favs
list_view

typeset line

while true; do
  now="$(date '+%Y-%m-%d %H:%M')"
  render
  print -n "${Y}  explorer> ${X}"
  if (( auto == 1 )); then
    read -r -t 5 line || { list_view; continue; }
  else
    read -r line || { print ""; exit 0 }
  fi
  dispatch "$line"
done
