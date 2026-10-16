#!/bin/sh
# doctor.sh — THE LA DIAGNOSTIC. It READS, it repairs NOTHING, and it does not guess:
# every line is a NAMED check with its verdict. A doctor that says "all is well" without
# saying what it looked at is worth nothing.
#
#   doctor.sh          the full diagnostic
#   doctor.sh --short  only the faults
#
# The final count is the number of FAULTS: 0 = the machine holds.
set -u
HERE=$(dirname "$(readlink -f -- "$0")")
ROOT=${LA_ROOT:-$(dirname "$(dirname "$HERE")")}
TABLE=${LA_CONFIG:-$ROOT/config/la_tools.yaml}
# THE SPEC OF THE ACTIVE SKILL, not a fixed path: the name lives in skills/.active (fallback: la).
SKILLS="$ROOT/skills"
ACTIVE_SKILL=$(sed -n '1p' "$SKILLS/.active" 2>/dev/null | tr -d '\r' | tr -d '[:space:]')
[ -n "$ACTIVE_SKILL" ] && [ -f "$SKILLS/$ACTIVE_SKILL/spec.yaml" ] || ACTIVE_SKILL=la
SPEC="$SKILLS/$ACTIVE_SKILL/spec.yaml"
SURVEY="$ROOT/tools/embeddings-e5.txt"
SHORT=0
[ "${1:-}" = "--short" ] && SHORT=1
FAULTS=0
NOTES=0

ok()   { [ "$SHORT" = 1 ] || printf '  ok     %s\n' "$1"; }
fail() { printf '  FAULT  %s\n' "$1"; FAULTS=$((FAULTS+1)); }
note() { [ "$SHORT" = 1 ] || printf '  note   %s\n' "$1"; NOTES=$((NOTES+1)); }
title() { [ "$SHORT" = 1 ] || printf '\n%s\n' "$1"; }

title "THE ROOT AND THE TABLE"
[ -d "$ROOT" ] && [ -f "$TABLE" ] && ok "root $ROOT, table found" \
  || { fail "root or table missing ($ROOT, $TABLE)"; printf '%d fault(s)\n' "$FAULTS"; exit 1; }

title "THE SCRIPTS (dash syntax)"
N=0
for f in "$ROOT"/config/engine/*.sh; do
  [ -f "$f" ] || continue
  N=$((N+1))
  dash -n "$f" 2>/dev/null || fail "broken syntax : ${f##*/}"
done
[ "$N" -ge 7 ] && ok "$N scripts, syntax good" || fail "only $N scripts in config/engine"

title "THE TABLE"
IDS=$(grep -c '^  - id: ' "$TABLE")
TOOLS=$(grep -c '^    tool: ' "$TABLE")
FAM=$(grep -c '^    family: ' "$TABLE")
CMD=$(grep -c '^    command:' "$TABLE")
ok "$IDS tools declared"
[ "$IDS" = "$TOOLS" ] && ok "every id carries a tool" || fail "$IDS ids for $TOOLS tools"
[ "$IDS" = "$FAM" ]   && ok "every id carries a family" || fail "$IDS ids for $FAM families"
[ "$IDS" = "$CMD" ]   && ok "every id carries a command" || fail "$IDS ids for $CMD commands"
DUP=$(grep -oE '^  - id: [0-9]+' "$TABLE" | sort | uniq -d)
[ -z "$DUP" ] && ok "no duplicate id" || fail "duplicate ids : $(printf '%s' "$DUP" | tr '\n' ' ')"

title "THE FILES THE TABLE CALLS"
N=0
for p in $(grep -oE '/home/moussa[A-Za-z0-9_./+-]*\.(gguf|onnx|bin|py|sh|json)' "$TABLE" | sort -u); do
  N=$((N+1))
  [ -e "$p" ] || fail "called by the table and MISSING: $p"
done
ok "$N absolute paths checked, all present"

title "THE SKILLS"
for d in "$SKILLS"/*/; do
  [ -f "$d/skill.yaml" ] || continue
  S="$d/skill.yaml"
  NM=$(basename "$d")
  grep -q '^PERIMETER:' "$S" || fail "skill $NM : no PERIMETER"
  grep -q '^  workspace:' "$S" || fail "skill $NM : PERIMETER without workspace"
  while IFS= read -r T; do
    [ -n "$T" ] || continue
    grep -q "^    tool: $T\$" "$TABLE" || fail "skill $NM : opens a tool that does not exist ($T)"
  done <<EOF
$(sed -n '/^TOOLS:/,/^[A-Z][A-Z]*:/p' "$S" | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*"\([a-z_][a-z_0-9]*\)".*/\1/p')
EOF
  L=$(awk '/^SUMMARY:/,/^[A-Z][A-Z]*:/' "$S" | awk 'length($0) > 100' | wc -l)
  [ "$L" = 0 ] || fail "skill $NM : $L summary line(s) above 100 bytes"
done
ok "$(ls -1d "$SKILLS"/*/ | wc -l) skills examined"

title "THE ACTIVE SKILL"
A=$(sed -n '1p' "$SKILLS/.active" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if [ -n "$A" ] && [ -f "$SKILLS/$A/skill.yaml" ]; then
  ok "the .active says $A, and $A exists"
else
  fail "the .active says \"$A\" and that folder does not exist"
fi

title "THE CANON"
[ -f "$SPEC" ] && ok "spec.yaml found" || fail "spec.yaml missing ($SPEC)"
DUP=$(grep -oE '^  [0-9]+:' "$SPEC" | sort | uniq -d)
[ -z "$DUP" ] && ok "no duplicate law number" \
  || fail "duplicate laws : $(printf '%s' "$DUP" | tr '\n' ' ' | cut -c1-80)"
S=$(grep -c '^SECTION : ' "$SPEC")
ok "$S sections"
L=$(awk 'length($0) > 100' "$SPEC" | wc -l)
[ "$L" = 0 ] && ok "no line above 100 bytes" \
  || fail "$L line(s) above 100 bytes in the spec"
M=$(grep -c 'coffre' "$SPEC" 2>/dev/null)
[ "$M" = 0 ] && ok "no residual \"coffre\" in the canon" \
  || note "$M line(s) still say \"coffre\" (the disk image)"

title "THE EMBEDDING SURVEY"
if [ -f "$SURVEY" ]; then
  if [ "$SURVEY" -nt "$TABLE" ]; then
    ok "the survey is more recent than the table"
  else
    fail "the survey is OLDER than the table : it must be rebuilt (index_build)"
  fi
else
  fail "no survey : index_build never ran"
fi

title "THE BRIDGE"
if command -v curl >/dev/null 2>&1; then
  R=$(curl -s --max-time 2 "http://127.0.0.1:8765/ping" 2>/dev/null || true)
  [ -n "$R" ] && ok "the bridge answers on 8765" || note "the bridge does not answer on 8765 (down ?)"
fi

title "THE MACHINERY VOCABULARY"
# THE DOCTOR DOES NOT COUNT ITSELF : it names "coffre" in its own checks.
OTHERS=$(ls "$ROOT"/config/engine/*.sh | grep -v '/doctor.sh$' | tr '\n' ' ')
C=$(grep -c 'coffre' $OTHERS "$TABLE" "$ROOT"/config/head.yaml 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
[ "$C" = 0 ] && ok "no \"coffre\" identifier in the code" || fail "$C \"coffre\" left in the code"
for O in coeur gestion musique rapport reseau systeme veille; do
  [ -d "$SKILLS/$O" ] && fail "the old skill name came back : skills/$O"
done

[ "$SHORT" = 1 ] && printf '%d fault(s), %d note(s)\n' "$FAULTS" "$NOTES"
[ "$FAULTS" = 0 ] && exit 0
exit 1
