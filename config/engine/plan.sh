#!/bin/sh
# plan.sh - THE PLAN LIVES IN THE SKILL (config/engine/plan.sh).
#
# WHERE THE PLAN LIVES : in the PLAN: section of the ACTIVE skill, that is $SKROOT/skill.yaml.
# There is no more plans folder, no more file per plan : the plan is a SEQUENCE OF INDEXED LINES
# of the skill, like the rest of its material. The lines of a plan carry the numbers 4xx (401 for
# the first point, and so on) : that is the hundreds of the PLAN.
#
# THE SHAPE OF A PLAN LINE (the same as any skill line : at most 100 bytes)
#   401: "[todo] open the file"
#   402: "[doing] re-read it"
#   403: "[complete] place the line"
# and the FIRST line of the plan, 400, carries the goal :
#   400: "PLAN <name> : <goal>"
#
# THE STATES, and nothing else : todo, doing, complete. advance moves ONLY the first point that
# is not complete, and by a SINGLE state at a time (never todo -> complete at once).
#
# THE CLEANUP POINT : the plan ADD ITSELF last at the opening, and close_plan REFUSES to close a
# plan whose last point is not that one.
#
# THE SUBCOMMANDS (one per table tool)
#   start <name> <goal>   opens a plan ; the points arrive one per line on the standard input
#   load                returns the open plan, or says there is none
#   advance             moves the first non-complete point, by a single state
#   revise <pattern>    rewrites the NOT-CROSSED points ; the complete points do not move
#   close <pattern>     closes the plan (its section becomes empty again) ; refuses if the last
#                       point is not the cleanup point
#   abort <pattern>     closes the plan by interrupting it
#
# THE REFUSAL : a single line, code 1, NOTHING written in the skill. POSIX sh (dash), ASCII,
# no backtick. The writes are atomic (temporary file then mv).

LC_ALL=C
export LC_ALL

TARGET=${PLAN_FILE:-${SKROOT:+$SKROOT/skill.yaml}}
[ -n "$TARGET" ] || { echo 'refused: the active skill is unknown (SKROOT is empty) ; the plan does not know where to live' >&2 ; exit 1 ; }
[ -f "$TARGET" ] || { echo "refused: the active skill is missing ($TARGET)" >&2 ; exit 1 ; }
[ -w "$TARGET" ] || { echo "refused: the active skill is not writable ($TARGET)" >&2 ; exit 1 ; }

START=$(grep -n '^PLAN:[[:space:]]*$' "$TARGET" | head -n 1 | cut -d: -f1)
[ -n "$START" ] || START=$(grep -n '^PLAN:' "$TARGET" | head -n 1 | cut -d: -f1)
[ -n "$START" ] || { echo 'refused: the active skill carries no PLAN: section' >&2 ; exit 1 ; }
END_POS=$(awk -v d="$START" 'NR > d && /^[^[:space:]]/ { print NR; exit }' "$TARGET")
TOTAL=$(wc -l < "$TARGET")
END_POS=${END_POS:-$((TOTAL + 1))}

# the plan lines, as they are (2 spaces, a number, a colon, the text in quotes)
lines() { sed -n "$((START + 1)),$((END_POS - 1))p" "$TARGET" | grep -E '^  [0-9]{3}: "' ; }
text()  { printf '%s' "$1" | sed -e 's/^  [0-9][0-9][0-9]: "//' -e 's/"$//' ; }
state()   { printf '%s' "$1" | sed -n 's/^\[\([a-z]*\)\].*/\1/p' ; }

# rewrite the section : the new lines arrive on the standard input
rewrite() {
  T=$(mktemp "${TMPDIR:-/tmp}/plan.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
  trap 'rm -f "$T"' EXIT INT TERM HUP
  # what PRECEDES the section (the PLAN: header included), THEN the new lines, THEN the rest of
  # the skill. The plan must land INSIDE its section, never at the end of the file.
  {
    awk -v d="$START" 'NR <= d { print }' "$TARGET"
    cat
    awk -v f="$END_POS" 'NR >= f { print }' "$TARGET"
  } > "$T" || { echo 'refused: reading the skill failed' >&2 ; exit 1 ; }
  [ -s "$T" ] || { echo 'refused: the rewrite returned an empty file ; nothing was touched' >&2 ; exit 1 ; }
  mv -f "$T" "$TARGET" || { echo 'refused: writing to the skill failed' >&2 ; exit 1 ; }
}

# place an empty PLAN: section (the close and abort cases)
clear() {
  T=$(mktemp "${TMPDIR:-/tmp}/plan.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
  trap 'rm -f "$T"' EXIT INT TERM HUP
  awk -v d="$START" -v f="$END_POS" 'NR <= d || NR >= f { print }' "$TARGET" > "$T" || { echo 'refused: reading the skill failed' >&2 ; exit 1 ; }
  mv -f "$T" "$TARGET" || { echo 'refused: writing to the skill failed' >&2 ; exit 1 ; }
}

# how many plan lines, and how many non-complete points
N_LINES=$(lines | wc -l | tr -d ' ')
N_OPEN=$(lines | grep -c '\[todo\]\|\[doing\]' | tr -d ' ')
PLAN_OPEN=0
[ "$N_OPEN" -gt 0 ] && PLAN_OPEN=1

point_status() { printf '%s' "$1" | sed -e 's/^\[[a-z]*\][[:space:]]*//'; }

mode=${1:-}
case "$mode" in
  start)
    NAME=${2:-}
    GOAL=${3:-}
    [ -n "$NAME" ] || { echo 'refused: start wants a plan name' >&2 ; exit 1 ; }
    [ -n "$GOAL" ] || { echo 'refused: start wants a goal (what the task must produce)' >&2 ; exit 1 ; }
    SLUG=$(printf '%s' "$NAME" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//')
    [ -n "$SLUG" ] || { echo 'refused: the name yields no slug (lowercase, digits, dashes)' >&2 ; exit 1 ; }
    [ "$PLAN_OPEN" = 0 ] || { echo "refused: a plan is already open in $TARGET ; a single plan is active at a time" >&2 ; exit 1 ; }
    N=400
    TMPL=$(mktemp "${TMPDIR:-/tmp}/planl.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL"' EXIT INT TERM HUP
    HEAD=$(printf 'PLAN %s : %s' "$SLUG" "$GOAL")
    [ $(( ${#HEAD} + 12 )) -le 100 ] || { echo "refused: the goal is too long for a skill line ($(( ${#HEAD} + 12 )) bytes, 100 at most)" >&2 ; exit 1 ; }
    printf '  %s: "%s"\n' "$N" "$HEAD" > "$TMPL"
    while IFS= read -r L || [ -n "$L" ]; do
      [ -n "$L" ] || continue
      N=$((N + 1))
      [ $(( ${#L} + 20 )) -le 100 ] || { echo "refused: a point exceeds the skill line ($(( ${#L} + 20 )) bytes, 100 at most) : $L" >&2 ; exit 1 ; }
      printf '  %s: "[todo] %s"\n' "$N" "$L" >> "$TMPL"
    done
    [ "$N" -gt 400 ] || { echo 'refused: start wants at least one point, one per line on the standard input' >&2 ; exit 1 ; }
    # THE CLEANUP POINT, added by the plan itself, last
    N=$((N + 1))
    printf '  %s: "[todo] CLEANUP : tidy the work, nothing left scattered"\n' "$N" >> "$TMPL"
    rewrite < "$TMPL"
    echo "plan open in $TARGET ($((N - 400)) points)"
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  load)
    if [ "$N_LINES" = 0 ]; then
      echo 'no open plan : the active skill carries no plan in its PLAN section'
      exit 0
    fi
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  advance)
    [ "$PLAN_OPEN" = 1 ] || { echo 'refused: no open plan to advance' >&2 ; exit 1 ; }
    TMPL=$(mktemp "${TMPDIR:-/tmp}/plana.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL"' EXIT INT TERM HUP
    SEEN=0
    lines | while IFS= read -r L; do
      T=$(text "$L")
      E=$(state "$T")
      if [ "$SEEN" = 0 ] && [ "$E" = todo ]; then
        SEEN=1; E=doing
      elif [ "$SEEN" = 0 ] && [ "$E" = doing ]; then
        SEEN=1; E=complete
      fi
      NUM=$(printf '%s' "$L" | sed -n 's/^  \([0-9][0-9][0-9]\):.*/\1/p')
      printf '  %s: "[%s] %s"\n' "$NUM" "$E" "$(point_status "$T")"
    done > "$TMPL"
    rewrite < "$TMPL"
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  revise)
    PATTERN=${2:-}
    [ -n "$PATTERN" ] || { echo 'refused: revise wants a pattern' >&2 ; exit 1 ; }
    [ "$PLAN_OPEN" = 1 ] || { echo 'refused: no open plan to revise' >&2 ; exit 1 ; }
    TMPL=$(mktemp "${TMPDIR:-/tmp}/planr.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL"' EXIT INT TERM HUP
    NEW=$(mktemp "${TMPDIR:-/tmp}/planrn.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL" "$NEW"' EXIT INT TERM HUP
    cat > "$NEW"
    # the points ALREADY CROSSED (complete) do not move ; the others are replaced
    lines | grep '\[complete\]' > "$TMPL"
    N=400
    while IFS= read -r L || [ -n "$L" ]; do
      [ -n "$L" ] || continue
      N=$((N + 1))
      [ $(( ${#L} + 20 )) -le 100 ] || { echo "refused: a point exceeds the skill line : $L" >&2 ; exit 1 ; }
      printf '  %s: "[todo] %s"\n' "$N" "$L" >> "$NEW.out"
    done < "$NEW"
    [ -s "$NEW.out" ] || { rm -f "$NEW.out" ; echo 'refused: revise wants at least one point on the standard input' >&2 ; exit 1 ; }
    N=$((N + 1))
    printf '  %s: "[todo] CLEANUP : tidy the work, nothing left scattered"\n' "$N" >> "$NEW.out"
    cat "$NEW.out" >> "$TMPL"
    rm -f "$NEW.out" "$NEW"
    rewrite < "$TMPL"
    echo "plan revised ($PATTERN)"
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  close)
    PATTERN=${2:-}
    [ "$N_LINES" -gt 0 ] || { echo 'refused: no open plan to close' >&2 ; exit 1 ; }
    LAST=$(lines | tail -n 1 | sed -e 's/^  [0-9][0-9][0-9]: "//' -e 's/"$//')
    case "$(point_status "$LAST")" in
      CLEANUP*) ;;
      *) echo "refused: the last point of the plan is not the cleanup point ; close_plan closes a tidy plan, not a plan in progress ($(point_status "$LAST"))" >&2 ; exit 1 ;;
    esac
    clear
    echo "plan closed${PATTERN:+ ($PATTERN)} ; the PLAN: section of the skill is empty"
    ;;
  abort)
    PATTERN=${2:-}
    [ "$N_LINES" -gt 0 ] || { echo 'refused: no open plan to interrupt' >&2 ; exit 1 ; }
    clear
    echo "plan interrupted${PATTERN:+ ($PATTERN)} ; the PLAN: section of the skill is empty"
    ;;
  *)
    echo 'refused: unknown subcommand ; start, load, advance, revise, close or abort' >&2
    exit 1
    ;;
esac
