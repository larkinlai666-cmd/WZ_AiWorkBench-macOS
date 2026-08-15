#!/bin/zsh
# =============================================================================
#  AI STAR CUBE · macOS · walking-cat splash
#  Upstream parity (Get-AgentSplashScript): a 5-frame animated progress cat
#  (~300ms) painted BEFORE the agent boots; the agent's own first paint then
#  overwrites it. No readiness polling, no boot dependency.
#  Redirected hosts (regression harness) get ONE static frame — no cursor math.
#  Magenta accent only (D-013: decoration never uses the reserved input Yellow).
#  Usage: splash.sh <project> <agent-label>
#  Env overrides (debug/slow-mo): WZ_SPLASH_FRAMES  WZ_SPLASH_MS
# =============================================================================
emulate -L zsh
set -u

project="${1:-}"
label="${2:-}"

COLS=80
typeset sz
sz=$(stty size 2>/dev/null)
if [[ -n "$sz" ]]; then COLS=${sz##* }; fi
(( COLS < 54 )) && COLS=54

typeset -i bw=$(( COLS - 26 ))
(( bw > 44 )) && bw=44
(( bw < 16 )) && bw=16

M=$'\e[35;1m'   # magenta — the ONLY decoration accent (D-013)
G=$'\e[37m'
D=$'\e[90m'
X=$'\e[0m'

typeset -i frames=5
typeset -i f i frac fill padn
[[ -t 1 ]] || frames=1
if [[ -n "${WZ_SPLASH_FRAMES:-}" && "${WZ_SPLASH_FRAMES}" =~ '^[0-9]+$' ]]; then
  frames=$WZ_SPLASH_FRAMES
  (( frames < 1 )) && frames=1
fi
typeset ms="0.075"
if [[ -n "${WZ_SPLASH_MS:-}" && "${WZ_SPLASH_MS}" =~ '^[0-9.]+$' ]]; then
  ms="$WZ_SPLASH_MS"
fi

for (( f = 0; f < frames; f++ )); do
  if (( frames == 1 )); then
    frac=100
  else
    frac=$(( f * 100 / (frames - 1) ))
  fi
  fill=$(( bw * frac / 100 ))
  padn=$(( 2 + (bw - 8) * frac / 100 ))
  typeset bar="" pad=""
  for (( i = 0; i < bw; i++ )); do
    if (( i < fill )); then bar+='█'; else bar+='░'; fi
  done
  for (( i = 0; i < padn; i++ )); do pad+=' '; done
  typeset face='( -.- )' legs=' > ^ <~'
  if (( f % 2 == 0 )); then face='( o.o )'; legs=' > ^ <'; fi
  if (( f == 0 )); then
    print -n $'\e[2J\e[H'
  else
    print -n $'\e[H'
  fi
  print -r "${M}${pad} /\_/\\${X}"
  print -r "${M}${pad}${face}${X}"
  print -r "${M}${pad}${legs}${X}"
  print -r "${M}  [${bar}] ${frac}%${X}"
  print -r "${G}  ${project} · ${label}${X}"
  print -r "${D}  starting...${X}"
  if (( f < frames - 1 )); then sleep "$ms"; fi
done
