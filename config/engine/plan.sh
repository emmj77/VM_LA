#!/usr/bin/dash
# french in code is forbidden

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

if [ -z "${SKROOT:-}" ] && [ -z "${PLAN_FILE:-}" ]; then
  active_skill ; SKROOT=$(dirname "$SKILL")   # elle POSE NAME et SKILL : jamais par $(...)
fi
IFS=" $(printf '\t')" ; LEVEL=${1:-} ; SECTION=PLAN ; WHAT=skill
if [ "$LEVEL" = big ]; then
  shift
  SECTION=PROJECT_PLAN ; WHAT=project
  active_project          # elle POSE PNAME (vide si aucun) et PROJECT (le chemin du project.yml)
  [ -n "$PNAME" ] || { echo 'refused: no project is active ; the big plan lives in a project (PROJECT_PLAN), and a project is loaded with load_project' >&2 ; exit 1 ; }
  TARGET=$PROJECT
  [ -f "$TARGET" ] || { echo "refused: the active project has no project.yml ($TARGET)" >&2 ; exit 1 ; }
else
  TARGET=${PLAN_FILE:-${SKROOT:+$SKROOT/skill.yaml}}
fi
[ -n "$TARGET" ] || { echo 'refused: the active skill is unknown (SKROOT is empty) ; the plan does not know where to live' >&2 ; exit 1 ; }
[ -f "$TARGET" ] || { echo "refused: the active $WHAT is missing ($TARGET)" >&2 ; exit 1 ; }

START=$(grep -n "^$SECTION:[[:space:]]*$" "$TARGET" | head -n 1 | cut -d: -f1)
[ -n "$START" ] || START=$(grep -n "^$SECTION:" "$TARGET" | head -n 1 | cut -d: -f1)
if [ -z "$START" ] && [ "$SECTION" = PLAN ]; then
  echo 'refused: the active skill carries no PLAN: section' >&2 ; exit 1
fi
[ -n "$START" ] || { echo "refused: the active project carries no $SECTION: section ($TARGET)" >&2 ; exit 1 ; }
END_POS=$(awk -v d="$START" 'NR > d && /^[^[:space:]]/ { print NR; exit }' "$TARGET")
TOTAL=$(wc -l < "$TARGET")
END_POS=${END_POS:-$((TOTAL + 1))}

lines() { sed -n "$((START + 1)),$((END_POS - 1))p" "$TARGET" | grep -E '^  [0-9]{3}: "' ; }
text()  { printf '%s' "$1" | sed -e 's/^  [0-9][0-9][0-9]: "//' -e 's/"$//' ; }
state() { printf '%s' "$1" | sed -n 's/^\[\([a-z]*\)\].*/\1/p' ; }
body()  { printf '%s' "$1" | sed -e 's/^\[[a-z]*\][[:space:]]*//' ; }

rewrite() {
  tmpfile plan ; T=$TMPFILE || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
  {
    awk -v d="$START" 'NR <= d { print }' "$TARGET"
    cat
    awk -v f="$END_POS" 'NR >= f { print }' "$TARGET"
  } > "$T" || { echo 'refused: reading the skill failed' >&2 ; exit 1 ; }
  [ -s "$T" ] || { echo 'refused: the rewrite returned an empty file ; nothing was touched' >&2 ; exit 1 ; }
  mv -f "$T" "$TARGET" || { echo 'refused: writing to the skill failed' >&2 ; exit 1 ; }
  rm -f "$T"
}

clear() {
  tmpfile planc ; T=$TMPFILE || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
  awk -v d="$START" -v f="$END_POS" 'NR <= d || NR >= f { print }' "$TARGET" > "$T" || { echo 'refused: reading the skill failed' >&2 ; exit 1 ; }
  mv -f "$T" "$TARGET" || { echo 'refused: writing to the skill failed' >&2 ; exit 1 ; }
}

N_LINES=$(lines | wc -l | tr -d ' ')

mode=${1:-}
CHG=
[ "$mode" = change ] && { CHG=1 ; mode=todo ; }
case "$mode" in
  todo)
    NAME=${2:-}
    GOAL=${3:-}
    [ -n "$NAME" ] || { echo 'refused: todo wants a plan name' >&2 ; exit 1 ; }
    [ -n "$GOAL" ] || { echo 'refused: todo wants a goal (what the task must produce)' >&2 ; exit 1 ; }
    SLUG=$(printf '%s' "$NAME" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//')
    [ -n "$SLUG" ] || { echo 'refused: the name yields no slug (lowercase, digits, dashes)' >&2 ; exit 1 ; }
    [ "$N_LINES" = 0 ] || [ -n "$CHG" ] || { echo "refused: a plan is already open in $TARGET ; a single plan is active at a time" >&2 ; exit 1 ; }
    [ -w "$TARGET" ] || { echo "refused: the active $WHAT is not writable ($TARGET)" >&2 ; exit 1 ; }
    N=400
    tmpfile plant ; TMPL=$TMPFILE || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
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
    # change REPLACES the section : rewrite already drops every old point, so the
    # section is never cleared first (clear + rewrite would cut the tail twice).
    rewrite < "$TMPL" ; rm -f "$TMPL"
    if [ -n "$CHG" ]; then
      echo "big plan REWRITTEN in $TARGET ($((N - 400)) point(s))"
    else
      echo "plan open in $TARGET ($((N - 400)) point(s))"
    fi
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  progress)
    PSTATE=${2:-}
    case "$PSTATE" in
      progress|complete) ;;
      *) { echo 'refused: progress wants its state : progress or complete' >&2 ; exit 1 ; } ;;
    esac
    [ "$N_LINES" -gt 0 ] || { echo 'refused: no open plan to mark' >&2 ; exit 1 ; }
    [ -w "$TARGET" ] || { echo "refused: the active $WHAT is not writable ($TARGET)" >&2 ; exit 1 ; }
    tmpfile planp ; TMPL=$TMPFILE || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
    NEXT=0
    lines | while IFS= read -r L; do
      NUM=$(printf '%s' "$L" | sed -n 's/^  \([0-9][0-9][0-9]\):.*/\1/p')
      T=$(text "$L")
      E=$(state "$T")
      if [ -z "$E" ]; then printf '  %s: "%s"\n' "$NUM" "$T" ; continue ; fi
      B=$(body "$T")
      if [ "$E" = progress ] && [ "$NEXT" = 0 ]; then
        if [ "$PSTATE" = complete ]; then E=complete ; NEXT=1 ; else E=progress ; fi
      elif [ "$NEXT" = 1 ] && [ "$E" = todo ]; then
        E=progress ; NEXT=0
      fi
      printf '  %s: "[%s] %s"\n' "$NUM" "$E" "$B"
    done > "$TMPL"
    [ -s "$TMPL" ] || { echo 'refused: the mark returned nothing ; nothing was touched' >&2 ; exit 1 ; }
    rewrite < "$TMPL" ; rm -f "$TMPL"
    LEFT=$(lines | grep -c '\[todo\]\|\[progress\]' | tr -d ' ')
    if [ "$LEFT" = 0 ]; then
      if [ "$SECTION" = PLAN ]; then
        clear
        echo "plan complete ; the $SECTION: section of the $WHAT is empty"
      else
        echo "big plan complete ; $TARGET KEEPS its points -- a long plan keeps its trace, and"
        echo 'change_big_todo is what rewrites it (and that one needs your validation)'
      fi
      exit 0
    fi
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  status|load)
    if [ "$N_LINES" = 0 ]; then
      echo "no open plan : the active $WHAT carries no plan in its $SECTION section"
      exit 0
    fi
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  *)
    echo 'refused: unknown subcommand ; todo, progress, status or change (a `big` prefix targets the project plan)' >&2
    exit 1
    ;;
esac
