#!/bin/sh
# id: E08
# role: the entry. it finds the root, loads the engine, reads the first word, and hands over.
# every gesture is a tool of the engine: this file neither works nor launches anything.

_la_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
LA_DIR=$_la_here
export LA_DIR
unset _la_here
. "$LA_DIR/boot.sh" || exit 1

la_usage() {
  printf '%s\n' \
    "la <tool> [key=value ...]     call a tool through the door" \
    "la engine <tool> [k=v ...]    the same, as the engine" \
    "la turn <text>                one turn of the loop (engine.turn)" \
    "la say <text>                 the same, for the voice" \
    "la check [short|light|all]    compare the master file with the disk" \
    "la board [once|menu|json]     the board" \
    "la app                        the page in its own window" \
    "la service <name>             one of the four services, in the foreground" \
    "la map                        rebuild the map of the names" \
    "la version                    what this is"
}

case ${1:-} in
  -h|--help|help) la_usage ;;
  version|-v)    printf 'LA %s, master %s\n' "$(cfg str date)" "$LA_CONF" ;;
  map)           LA_FROM=engine; export LA_FROM
                 run_call engine.map op=rebuild | jq -r '.result // .' 2>/dev/null || : ;;
  turn|say)      shift; LA_FROM=engine; export LA_FROM
                 run_call engine.turn "text=$*" | jq -r '.result // .' 2>/dev/null || : ;;
  service)       shift; LA_FROM=engine; export LA_FROM
                 run_call engine.service "name=${1:-}" ;;
  check|doctor)  LA_FROM=engine; export LA_FROM; shift
                 _op=${1:-short}; _op=${_op#--}
                 run_call engine.doctor "op=$_op" | jq -r '.result // .' 2>/dev/null || : ;;
  board)         LA_FROM=engine; export LA_FROM; shift
                 run_call engine.board "op=${1:-once}" | jq -r '.result // .' 2>/dev/null || : ;;
  app|--app)     LA_FROM=engine; export LA_FROM; shift
                 run_call engine.commands op=app | jq -r '.result // .' 2>/dev/null || : ;;
  cli|--cli)     LA_FROM=engine; export LA_FROM; shift
                 _b=$(cfg abs board.py 2>/dev/null)
                 [ -f "$_b" ] || _b="$LA_ROOT/config[D01]/programs[D10]/board.py"
                 exec python3 "$_b" --cli "$@" ;;
  tool)          shift; run_call "$@" ;;
  engine)        LA_FROM=engine; export LA_FROM; shift; run_call "$@" ;;
  "")            LA_FROM=engine; export LA_FROM; run_call engine.turn "text=$(cat)" ;;
  *)             run_call "$@" ;;
esac
