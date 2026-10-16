#!/bin/sh
# engine_switch.sh - THE ADDRESS MANAGER (config/engine/engine_switch.sh).
#
# WHY IT EXISTS. config/la_config.yaml carries the ADDRESSES of the engines, and ONLY ONE of
# them carries `active: "true"`. The canon says a declaration is changed "by a station tool,
# NEVER by hand, NEVER by the model" : this script IS that tool. It holds the `engines` section :
# it READS it (list) and changes the word `active` in it (take <alias>) - nothing else, and no
# other section.
#
# WHAT IT DOES NOT DO. It writes no secret value (the file carries only variable NAMES), it
# prints no provider address, it creates nothing.
#
# THE WRITE IS ATOMIC AND VERIFIED. A temporary, then a rename. Before the rename : the line
# count has not moved, and EXACTLY one address remains active. Otherwise nothing is written and
# the reason is named.
#
# MODES : list | take <alias> | help

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
CFG=${LA_CONFIG_FILE:-"$ROOT/config/la_config.yaml"}

refuse_cli() { printf '%s\n' "$1" >&2 ; exit 1 ; }
# the common library (ts, active_skill) : ONE definition, not one copy per brick.
[ -f "$HERE/lib.sh" ] || refuse_cli "the common library is missing ($HERE/lib.sh)"
. "$HERE/lib.sh"

# the declared addresses, as TSV : provider, alias, model, active
read_engines() {
  awk '
    /^engines:[[:space:]]*$/ { in_eng = 1 ; next }
    in_eng && /^[^[:space:]#]/ { in_eng = 0 }
    in_eng && /^  - provider:/ {
      if (seen) { print f "\t" a "\t" m "\t" act }
      seen = 1 ; f = $3 ; a = "" ; m = "" ; act = "false" ; next
    }
    in_eng && /^    alias:/     { a = $2 ; next }
    in_eng && /^    model:/     { m = $2 ; next }
    in_eng && /^    active:/    { act = $2 ; gsub(/"/, "", act) ; next }
    END { if (seen) { print f "\t" a "\t" m "\t" act } }
  ' "$CFG"
}

[ -f "$CFG" ] || refuse_cli "refused: the address config is missing ($CFG)"
[ -r "$CFG" ] || refuse_cli "refused: the address config is unreadable ($CFG)"

MODE=${1:-help}

case "$MODE" in
  list)
    read_engines | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t"))
      | map({provider: .[0], alias: .[1], model: .[2], active: (.[3] == "true")})' \
      || refuse_cli 'refused: the addresses could not be read'
    exit 0
    ;;

  take)
    ALIAS=${2:-}
    [ -n "$ALIAS" ] || refuse_cli 'refused: take wants an alias (take <alias>) ; list gives them'
    case "$ALIAS" in *[!a-zA-Z0-9_-]*) refuse_cli "refused: alias off-form ($ALIAS) ; letters, digits, dash and underscore" ;; esac
    [ -w "$CFG" ] || refuse_cli "refused: the address config is not writable ($CFG)"
    if ! read_engines | cut -f2 | grep -qx -- "$ALIAS"; then
      refuse_cli "refused: no declared address carries the alias $ALIAS ; the config carries: $(read_engines | cut -f2 | tr '\n' ' ')"
    fi

    TD=$(mktemp -d "${TMPDIR:-/tmp}/engine_switch.XXXXXX") || refuse_cli 'refused: no temporary space'
    trap 'rm -f "$TD/new"; rmdir "$TD" 2>/dev/null' EXIT INT TERM HUP

    BEFORE=$(wc -l < "$CFG" | tr -d ' ')
    awk -v target="$ALIAS" '
      /^engines:[[:space:]]*$/ { in_eng = 1 ; print ; next }
      in_eng && /^[^[:space:]#]/  { in_eng = 0 }
      in_eng && /^    alias:/    { a = $2 }
      in_eng && /^    active:/   {
        if (a == target) { print "    active: \"true\"" } else { print "    active: \"false\"" }
        next
      }
      { print }
    ' "$CFG" > "$TD/new" || refuse_cli "refused: building the addresses failed"
    [ -s "$TD/new" ] || refuse_cli 'refused: building the addresses wrote nothing'

    AFTER=$(wc -l < "$TD/new" | tr -d ' ')
    [ "$BEFORE" = "$AFTER" ] || refuse_cli "refused: the build changed the line count ($BEFORE -> $AFTER) ; nothing is written"

    NACT=$(grep -c '^    active: "true"$' "$TD/new" | tr -d ' ')
    [ "$NACT" = 1 ] || refuse_cli "refused: $NACT address(es) would remain active ; exactly one is needed ; nothing is written"

    OTHER=$(grep -vcE '^    active: ' "$TD/new" | tr -d ' ')
    EXPECTED=$(grep -vcE '^    active: ' "$CFG" | tr -d ' ')
    [ "$OTHER" = "$EXPECTED" ] || refuse_cli 'refused: a line outside active moved ; nothing is written'

    mv -f "$TD/new" "$CFG" || refuse_cli "refused: write impossible ($CFG)"
    printf 'the active address is %s (%s)\n' "$ALIAS" "$(ts)"
    exit 0
    ;;

  help|*)
    sed -n '2,24p' "$0"
    ;;
esac
