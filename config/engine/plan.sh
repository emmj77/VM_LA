#!/bin/sh
# plan.sh - THE PLAN LIVES IN THE SKILL (config/engine/plan.sh).
#
# WHERE THE PLAN LIVES : in the PLAN: section of the ACTIVE skill ($SKROOT/skill.yaml). The plan
# is a SEQUENCE OF INDEXED LINES, the hundreds of the PLAN (4xx) : 400 carries the goal, 401 and
# after carry the points.
#
# THE SHAPE OF A PLAN LINE (like any skill line : at most 100 bytes)
#   400: "PLAN <slug> : <goal>"
#   401: "[progress] the point being done"
#   402: "[todo] a point not started"
#   403: "[complete] a point done"
#
# THE STATES, and nothing else : todo, progress, complete. The FIRST point opens as [progress] :
# the plan opens on its first point. progress NEVER jumps : it touches ONLY the current point
# (the [progress] one), and a complete opens the NEXT point as [progress].
#
# THE SUBCOMMANDS (the plan layer, behind the tools)
#   todo <name> <goal>   opens a plan ; the points arrive one per line on the standard input ;
#                        the first point opens as [progress], the rest as [todo]
#   progress <state>     state is progress or complete ; marks the CURRENT point : progress keeps
#                        it going (rewritten as-is), complete closes it and the NEXT opens
#   status               returns the open plan as text, or says there is none (READ by the
#                        secondary head ; it writes NOTHING). `load` is an alias.
#
# THE REFUSAL : a single line, code 1, NOTHING written in the skill. POSIX sh (dash), ASCII, no
# backtick. The writes are atomic (a temporary file, then mv).

LC_ALL=C
export LC_ALL

# LE PLAN SE RESOUT ICI, PAS DANS UN EXPORT (meme defaut que le docteur : une brique qui depend de
# l ordre des appels refuse seule, et pour de mauvaises raisons). SKROOT reste prioritaire quand la
# boucle l a pose ; sinon on le resout par la bibliotheque commune, au meme endroit que le canon.
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${SKROOT:-}" ] && [ -z "${PLAN_FILE:-}" ]; then
  [ -f "$HERE/lib.sh" ] || { echo "refused: the common library is missing ($HERE/lib.sh)" >&2 ; exit 2 ; }
  ROOT=${LA_ROOT:-$(CDPATH= cd -- "$HERE/../.." && pwd)}
  . "$HERE/lib.sh"
  active_skill ; SKROOT=$(dirname "$SKILL")   # elle POSE NAME et SKILL : jamais par $(...)
fi
TARGET=${PLAN_FILE:-${SKROOT:+$SKROOT/skill.yaml}}
[ -n "$TARGET" ] || { echo 'refused: the active skill is unknown (SKROOT is empty) ; the plan does not know where to live' >&2 ; exit 1 ; }
[ -f "$TARGET" ] || { echo "refused: the active skill is missing ($TARGET)" >&2 ; exit 1 ; }

START=$(grep -n '^PLAN:[[:space:]]*$' "$TARGET" | head -n 1 | cut -d: -f1)
[ -n "$START" ] || START=$(grep -n '^PLAN:' "$TARGET" | head -n 1 | cut -d: -f1)
[ -n "$START" ] || { echo 'refused: the active skill carries no PLAN: section' >&2 ; exit 1 ; }
END_POS=$(awk -v d="$START" 'NR > d && /^[^[:space:]]/ { print NR; exit }' "$TARGET")
TOTAL=$(wc -l < "$TARGET")
END_POS=${END_POS:-$((TOTAL + 1))}

lines() { sed -n "$((START + 1)),$((END_POS - 1))p" "$TARGET" | grep -E '^  [0-9]{3}: "' ; }
text()  { printf '%s' "$1" | sed -e 's/^  [0-9][0-9][0-9]: "//' -e 's/"$//' ; }
state() { printf '%s' "$1" | sed -n 's/^\[\([a-z]*\)\].*/\1/p' ; }
body()  { printf '%s' "$1" | sed -e 's/^\[[a-z]*\][[:space:]]*//' ; }

rewrite() {
  T=$(mktemp "${TMPDIR:-/tmp}/plan.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
  trap 'rm -f "$T"' EXIT INT TERM HUP
  {
    awk -v d="$START" 'NR <= d { print }' "$TARGET"
    cat
    awk -v f="$END_POS" 'NR >= f { print }' "$TARGET"
  } > "$T" || { echo 'refused: reading the skill failed' >&2 ; exit 1 ; }
  [ -s "$T" ] || { echo 'refused: the rewrite returned an empty file ; nothing was touched' >&2 ; exit 1 ; }
  mv -f "$T" "$TARGET" || { echo 'refused: writing to the skill failed' >&2 ; exit 1 ; }
}

clear() {
  T=$(mktemp "${TMPDIR:-/tmp}/planc.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
  trap 'rm -f "$T"' EXIT INT TERM HUP
  awk -v d="$START" -v f="$END_POS" 'NR <= d || NR >= f { print }' "$TARGET" > "$T" || { echo 'refused: reading the skill failed' >&2 ; exit 1 ; }
  mv -f "$T" "$TARGET" || { echo 'refused: writing to the skill failed' >&2 ; exit 1 ; }
}

N_LINES=$(lines | wc -l | tr -d ' ')

mode=${1:-}
case "$mode" in
  todo)
    NAME=${2:-}
    GOAL=${3:-}
    [ -n "$NAME" ] || { echo 'refused: todo wants a plan name' >&2 ; exit 1 ; }
    [ -n "$GOAL" ] || { echo 'refused: todo wants a goal (what the task must produce)' >&2 ; exit 1 ; }
    SLUG=$(printf '%s' "$NAME" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//')
    [ -n "$SLUG" ] || { echo 'refused: the name yields no slug (lowercase, digits, dashes)' >&2 ; exit 1 ; }
    [ "$N_LINES" = 0 ] || { echo "refused: a plan is already open in $TARGET ; a single plan is active at a time" >&2 ; exit 1 ; }
    [ -w "$TARGET" ] || { echo "refused: the active skill is not writable ($TARGET)" >&2 ; exit 1 ; }
    N=400
    TMPL=$(mktemp "${TMPDIR:-/tmp}/plant.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL"' EXIT INT TERM HUP
    HEAD=$(printf 'PLAN %s : %s' "$SLUG" "$GOAL")
    [ $(( ${#HEAD} + 12 )) -le 100 ] || { echo "refused: the goal is too long for a skill line ($(( ${#HEAD} + 12 )) bytes, 100 at most)" >&2 ; exit 1 ; }
    printf '  %s: "%s"\n' "$N" "$HEAD" > "$TMPL"
    FIRST=1
    while IFS= read -r L || [ -n "$L" ]; do
      [ -n "$L" ] || continue
      N=$((N + 1))
      [ $(( ${#L} + 24 )) -le 100 ] || { echo "refused: a point exceeds the skill line ($(( ${#L} + 24 )) bytes, 100 at most) : $L" >&2 ; exit 1 ; }
      if [ "$FIRST" = 1 ]; then
        printf '  %s: "[progress] %s"\n' "$N" "$L" >> "$TMPL" ; FIRST=0
      else
        printf '  %s: "[todo] %s"\n' "$N" "$L" >> "$TMPL"
      fi
    done
    [ "$N" -gt 400 ] || { echo 'refused: todo wants at least one point, one per line on the standard input' >&2 ; exit 1 ; }
    rewrite < "$TMPL"
    echo "plan open in $TARGET ($((N - 400)) point(s))"
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  progress)
    STATE=${2:-}
    case "$STATE" in
      progress|complete) ;;
      *) { echo 'refused: progress wants its state : progress or complete' >&2 ; exit 1 ; } ;;
    esac
    [ "$N_LINES" -gt 0 ] || { echo 'refused: no open plan to mark' >&2 ; exit 1 ; }
    [ -w "$TARGET" ] || { echo "refused: the active skill is not writable ($TARGET)" >&2 ; exit 1 ; }
    TMPL=$(mktemp "${TMPDIR:-/tmp}/planp.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL"' EXIT INT TERM HUP
    NEXT=0
    lines | while IFS= read -r L; do
      NUM=$(printf '%s' "$L" | sed -n 's/^  \([0-9][0-9][0-9]\):.*/\1/p')
      T=$(text "$L")
      E=$(state "$T")
      if [ -z "$E" ]; then printf '  %s: "%s"\n' "$NUM" "$T" ; continue ; fi
      B=$(body "$T")
      if [ "$E" = progress ] && [ "$NEXT" = 0 ]; then
        if [ "$STATE" = complete ]; then E=complete ; NEXT=1 ; else E=progress ; fi
      elif [ "$NEXT" = 1 ] && [ "$E" = todo ]; then
        E=progress ; NEXT=0
      fi
      printf '  %s: "[%s] %s"\n' "$NUM" "$E" "$B"
    done > "$TMPL"
    [ -s "$TMPL" ] || { echo 'refused: the mark returned nothing ; nothing was touched' >&2 ; exit 1 ; }
    rewrite < "$TMPL"
    LEFT=$(lines | grep -c '\[todo\]\|\[progress\]' | tr -d ' ')
    if [ "$LEFT" = 0 ]; then
      clear
      echo 'plan complete ; the PLAN: section of the skill is empty'
      exit 0
    fi
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  status|load)
    if [ "$N_LINES" = 0 ]; then
      echo 'no open plan : the active skill carries no plan in its PLAN section'
      exit 0
    fi
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  *)
    echo 'refused: unknown subcommand ; todo, progress or status' >&2
    exit 1
    ;;
esac
