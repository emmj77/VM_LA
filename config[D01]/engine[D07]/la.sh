#!/bin/sh
# id: E08
# role: the door of the engine. it finds the root, loads the engine, reads the first word, and hands over.
# the table, the cli and the turn of a human belong to board.py: this file never doubles them.

_la_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
LA_DIR=$_la_here
export LA_DIR
unset _la_here
. "$LA_DIR/boot.sh" || exit 1

la_usage() {
  printf '%s\n' \
    "la <tool> [key=value ...]     call a tool through the door" \
    "la engine <tool> [k=v ...]    the same, as the engine" \
    "la service <name>             one of the services, in the foreground" \
    "la map                        rebuild the map of the names" \
    "la version                    what this is" \
    "" \
    "the table, the cli and one turn for a human: python3 board.py --once|--menu|--check|--say|--cli"
}

case ${1:-} in
  -h|--help|help) la_usage ;;
  version|-v)    printf 'LA %s, master %s\n' "$(cfg str date)" "$LA_CONF" ;;
  map)           LA_FROM=engine; export LA_FROM
                 run_call engine.map op=rebuild | jq -r '.result // .' 2>/dev/null || : ;;
  service)       shift; LA_FROM=engine; export LA_FROM
                 run_call engine.service "name=${1:-}" ;;
  tool)          shift; run_call "$@" ;;
  engine)        LA_FROM=engine; export LA_FROM; shift; run_call "$@" ;;
  "")            LA_FROM=engine; export LA_FROM; run_call engine.turn "text=$(cat)" ;;
  *)             run_call "$@" ;;
esac
