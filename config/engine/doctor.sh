#!/bin/sh
# doctor.sh — LE DIAGNOSTIC DE LA. Il LIT, il ne repare RIEN, et il ne devine pas :
# chaque ligne est un controle NOMME avec son verdict. Un doctor qui dit « tout va bien »
# sans dire ce qu il a regarde ne vaut rien.
#
#   doctor.sh          le diagnostic complet
#   doctor.sh --short  seulement les fautes
#
# Le compte final est le nombre de FAULTS : 0 = la machine tient.
set -u
HERE=$(dirname "$(readlink -f -- "$0")")
ROOT=${LA_ROOT:-$(dirname "$(dirname "$HERE")")}
TABLE=${LA_CONFIG:-$ROOT/config/la_tools.yaml}
# LE SPEC DU SKILL ACTIF, pas un chemin fige : le nom vit dans skills/.active (repli : la).
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
fail() { printf '  FAUTE  %s\n' "$1"; FAULTS=$((FAULTS+1)); }
note() { [ "$SHORT" = 1 ] || printf '  note   %s\n' "$1"; NOTES=$((NOTES+1)); }
title() { [ "$SHORT" = 1 ] || printf '\n%s\n' "$1"; }

title "LA RACINE ET LA TABLE"
[ -d "$ROOT" ] && [ -f "$TABLE" ] && ok "racine $ROOT, table trouvee" \
  || { fail "racine ou table introuvable ($ROOT, $TABLE)"; printf '%d fail(s)\n' "$FAULTS"; exit 1; }

title "LES SCRIPTS (syntaxe dash)"
N=0
for f in "$ROOT"/config/engine/*.sh; do
  [ -f "$f" ] || continue
  N=$((N+1))
  dash -n "$f" 2>/dev/null || fail "syntaxe cassee : ${f##*/}"
done
[ "$N" -ge 7 ] && ok "$N scripts, syntaxe bonne" || fail "seulement $N scripts dans config/engine"

title "LA TABLE"
IDS=$(grep -c '^  - id: ' "$TABLE")
TOOLS=$(grep -c '^    tool: ' "$TABLE")
FAM=$(grep -c '^    family: ' "$TABLE")
CMD=$(grep -c '^    command:' "$TABLE")
ok "$IDS tools declares"
[ "$IDS" = "$TOOLS" ] && ok "chaque id porte un tool" || fail "$IDS ids pour $TOOLS tools"
[ "$IDS" = "$FAM" ]   && ok "chaque id porte une family" || fail "$IDS ids pour $FAM families"
[ "$IDS" = "$CMD" ]   && ok "chaque id porte une command" || fail "$IDS ids pour $CMD commands"
DUP=$(grep -oE '^  - id: [0-9]+' "$TABLE" | sort | uniq -d)
[ -z "$DUP" ] && ok "aucun id en double" || fail "ids en double : $(printf '%s' "$DUP" | tr '\n' ' ')"

title "LES FILES QUE LA TABLE APPELLE"
N=0
for p in $(grep -oE '/home/moussa[A-Za-z0-9_./+-]*\.(gguf|onnx|bin|py|sh|json)' "$TABLE" | sort -u); do
  N=$((N+1))
  [ -e "$p" ] || fail "appele par la table et ABSENT : $p"
done
ok "$N chemins absolus verifies, tous presents"

title "LES SKILLS"
for d in "$SKILLS"/*/; do
  [ -f "$d/skill.yaml" ] || continue
  S="$d/skill.yaml"
  NM=$(basename "$d")
  grep -q '^PERIMETER:' "$S" || fail "skill $NM : pas de PERIMETER"
  grep -q '^  workspace:' "$S" || fail "skill $NM : PERIMETER sans workspace"
  while IFS= read -r T; do
    [ -n "$T" ] || continue
    grep -q "^    tool: $T\$" "$TABLE" || fail "skill $NM : ouvre un tool qui n existe pas ($T)"
  done <<EOF
$(sed -n '/^TOOLS:/,/^[A-Z][A-Z]*:/p' "$S" | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*"\([a-z_][a-z_0-9]*\)".*/\1/p')
EOF
  L=$(awk '/^SUMMARY:/,/^[A-Z][A-Z]*:/' "$S" | awk 'length($0) > 100' | wc -l)
  [ "$L" = 0 ] || fail "skill $NM : $L ligne(s) de resume au-dessus de 100 bytes"
done
ok "$(ls -1d "$SKILLS"/*/ | wc -l) skills examines"

title "LA SKILL ACTIVE"
A=$(sed -n '1p' "$SKILLS/.active" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if [ -n "$A" ] && [ -f "$SKILLS/$A/skill.yaml" ]; then
  ok "le .active dit $A, et $A existe"
else
  fail "le .active dit « $A » et ce dossier n existe pas"
fi

title "LE CANON"
[ -f "$SPEC" ] && ok "spec.yaml trouvee" || fail "spec.yaml absente ($SPEC)"
DUP=$(grep -oE '^  [0-9]+:' "$SPEC" | sort | uniq -d)
[ -z "$DUP" ] && ok "aucun numero de loi en double" \
  || fail "lois en double : $(printf '%s' "$DUP" | tr '\n' ' ' | cut -c1-80)"
S=$(grep -c '^SECTION : ' "$SPEC")
ok "$S sections"
L=$(awk 'length($0) > 100' "$SPEC" | wc -l)
[ "$L" = 0 ] && ok "aucune ligne au-dessus de 100 bytes" \
  || fail "$L ligne(s) au-dessus de 100 octets dans la spec"
M=$(grep -c 'coffre' "$SPEC" 2>/dev/null)
[ "$M" = 0 ] && ok "aucun « coffre » residuel dans le canon" \
  || note "$M ligne(s) disent encore « coffre » (l image disque)"

title "LE RELEVE DES PLONGEMENTS"
if [ -f "$SURVEY" ]; then
  if [ "$SURVEY" -nt "$TABLE" ]; then
    ok "le releve est plus recent que la table"
  else
    fail "le releve est PLUS VIEUX que la table : il faut rebatir (index_build)"
  fi
else
  fail "aucun releve : index_build n a jamais tourne"
fi

title "LE BRIDGE"
if command -v curl >/dev/null 2>&1; then
  R=$(curl -s --max-time 2 "http://127.0.0.1:8765/ping" 2>/dev/null || true)
  [ -n "$R" ] && ok "le bridge repond sur 8765" || note "le bridge ne repond pas sur 8765 (eteint ?)"
fi

title "LE VOCABULAIRE DE LA MACHINERIE"
# LE DOCTOR NE SE COMPTE PAS LUI-MEME : il nomme « coffre » dans ses propres controles.
OTHERS=$(ls "$ROOT"/config/engine/*.sh | grep -v '/doctor.sh$' | tr '\n' ' ')
C=$(grep -c 'coffre' $OTHERS "$TABLE" "$ROOT"/config/head.yaml 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
[ "$C" = 0 ] && ok "aucun identifiant « coffre » dans le code" || fail "$C « coffre » restants dans le code"
for O in coeur gestion musique rapport reseau systeme veille; do
  [ -d "$SKILLS/$O" ] && fail "l ancien nom de skill est revenu : skills/$O"
done

[ "$SHORT" = 1 ] && printf '%d fail(s), %d note(s)\n' "$FAULTS" "$NOTES"
[ "$FAULTS" = 0 ] && exit 0
exit 1
