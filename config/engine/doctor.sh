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
# --- LA SKILL ACTIVE ET LE CANON : les DEUX resolutions vivent dans la bibliotheque commune
# (config/engine/lib.sh) : le moteur, la boucle et le docteur passent par les memes.
[ -f "$HERE/lib.sh" ] || { printf 'doctor: the common library is missing (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"
active_skill
canon_path
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
ok "$IDS tools declared"
[ "$IDS" = "$TOOLS" ] && ok "every id carries a tool" || fail "$IDS ids for $TOOLS tools"
[ "$IDS" = "$FAM" ]   && ok "every id carries a family" || fail "$IDS ids for $FAM families"
# LA TABLE A DEUX FICHIERS : le registre porte l id, le nom et la famille ; le CORPS vit dans
# config/tools/<machine>/tool_<nom>.yaml (ARGS + COMMAND + RULES.timeout), et l ancienne forme
# (un `command:` sur la ligne) est lue le temps de la migration. On compte donc les CORPS la ou
# ils sont, et on NOMME chaque id qui n en a aucun : un id sans corps est un id mort.
NFILE=0 ; NLINE=0 ; NOBODY= ; ORPH=
while IFS=' ' read -r ID TN; do
  [ -n "$TN" ] || continue
  F=
  for TDIR in "$ROOT"/config/tools/*/ "$ROOT"/config/tools/; do
    [ -f "$TDIR/tool_$TN.yaml" ] && { F="$TDIR/tool_$TN.yaml" ; break ; }
  done
  if [ -n "$F" ]; then
    grep -q '^COMMAND:' "$F" && NFILE=$((NFILE+1)) || NOBODY="$NOBODY $TN"
  else
    BL=$(table_block "$TABLE" "$ID") || { NOBODY="$NOBODY $TN" ; continue ; }
    printf '%s\n' "$BL" | grep -q '^    command:' && NLINE=$((NLINE+1)) || NOBODY="$NOBODY $TN"
  fi
done <<EOF
$(awk '/^  - id: /{id=$3} /^    tool: /{print id" "$2}' "$TABLE")
EOF
[ -z "$NOBODY" ] && ok "$IDS ids carry a body ($NFILE in config/tools/, $NLINE on the line)" \
  || fail "no body at all, neither in config/tools/ nor on the line :$NOBODY"
# LE CHEMIN INVERSE : un fichier de corps que le registre ne nomme pas est INATTEIGNABLE (le moteur
# et la boucle ne lisent que le registre). C est un NOTE : ca ne casse rien, ca dort.
for F in "$ROOT"/config/tools/*/tool_*.yaml "$ROOT"/config/tools/tool_*.yaml; do
  [ -f "$F" ] || continue
  TN=$(sed -n 's/^tool:[[:space:]]*//p' "$F" | head -n 1 | tr -d '"')
  grep -q "^    tool: $TN\$" "$TABLE" || ORPH="$ORPH $TN"
done
[ -z "$ORPH" ] && ok "every body file carries its registry line" \
  || note "a body with NO line in the registry (unreachable):$ORPH"
DUP=$(grep -oE '^  - id: [0-9]+' "$TABLE" | sort | uniq -d)
[ -z "$DUP" ] && ok "no duplicate id" || fail "duplicate ids : $(printf '%s' "$DUP" | tr '\n' ' ')"

title "THE FILES THE TABLE CALLS"
N=0
# LES CHEMINS DES CORPS : ils s ecrivent en clair (/home/...) OU par $HOME. Le $HOME se resout
# ici une fois pour toutes, sinon un corps qui appelle un binaire absent passe pour vivant.
CORPS="$ROOT"/config/tools/*/tool_*.yaml
for p in $(grep -ohE '/home/moussa[A-Za-z0-9_./+-]*\.(gguf|onnx|bin|py|sh|json)' "$TABLE" $CORPS 2>/dev/null | sort -u); do
  N=$((N+1))
  [ -e "$p" ] || fail "called by the table and MISSING: $p"
done
for p in $(grep -ohE '\$HOME/[A-Za-z0-9_./+-]*' "$TABLE" $CORPS 2>/dev/null | sed "s|^\$HOME|$HOME|" | sort -u); do
  N=$((N+1))
  [ -e "$p" ] || fail "called by a tool body and MISSING: $p"
done
ok "$N file(s) called by the table and the bodies, all present"

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

title "THE ACTIVE PROJECT AND SKILL"
active_project
[ -n "$PNAME" ] && ok "the active project is $PNAME ($PROJECT)" \
  || ok "no project is loaded : the whole skillset is open (projects/.active is absent)"
if [ -n "$NAME" ] && [ -f "$SKILLS/$NAME/skill.yaml" ]; then
  ok "the .active says $NAME, and $NAME exists"
else
  fail "the .active names no skill that exists (skills/.active)"
fi

title "THE CANON"
ok "the canon is $CANON_WHY"
if [ -n "$SPEC" ] && [ -f "$SPEC" ]; then
  ok "canon found ($SPEC)"
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
else
  fail "NO canon to read : $CANON_WHY"
fi

title "THE TOOLSET (the escape hatch that opens the full list)"
grep -q '^    tool: toolset$' "$TABLE" && ok "the table carries toolset" \
  || fail "the table carries no toolset"
RPORT=${LA_RERANK_PORT:-8095}
RS=$(curl -s --max-time 3 "http://127.0.0.1:$RPORT/health" 2>/dev/null || true)
[ -n "$RS" ] && ok "the reranker answers on $RPORT" || note "the reranker does not answer on $RPORT (down ?)"

title "THE EMBEDDER (the memory table is read under a question, never under a word)"
EPORT=${LA_EMBED_PORT:-8096}
ES=$(curl -s --max-time 3 "http://127.0.0.1:$EPORT/health" 2>/dev/null || true)
[ -n "$ES" ] && ok "the embedder answers on $EPORT" || note "the embedder does not answer on $EPORT (down ? the entries then keep a NULL vector)"
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$ROOT/config/memory.db" ]; then
  NT=$(sqlite3 "$ROOT/config/memory.db" 'SELECT count(*) FROM memory;' 2>/dev/null || printf '')
  NV=$(sqlite3 "$ROOT/config/memory.db" 'SELECT count(vec) FROM memory;' 2>/dev/null || printf '')
  ok "the table carries ${NT:-0} entry(ies), ${NV:-0} with a vector"
  case "${NT:-0}" in
    0) note "the table is empty : the first entry comes from the compacteur, at the end of a turn" ;;
    *) [ "${NT:-0}" = "${NV:-0}" ] || note "$((NT - NV)) entry(ies) carry no vector (readable by words only)" ;;
  esac
fi

title "THE RETURN FORMS"
TRF="$ROOT/config/engine/trim_forms.sh"
[ -x "$TRF" ] && ok "the form selector is present and executable" || fail "no form selector ($TRF)"
grep -q 'trim_formes' "$ROOT/config/engine/loop.sh" && ok "the loop goes through the forms BEFORE the cap" \
  || fail "the loop does not go through the forms"

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
