#!/bin/sh
# id: E08
# role: the door of the engine. it finds the root, loads the engine, and hands over to the command table of tab.sh.
# the commands are data (commands: in la_config.yaml): the cli, the page and the app read the same list, nobody doubles it.

_la_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
LA_DIR=$_la_here
export LA_DIR
unset _la_here
. "$LA_DIR/boot.sh" || exit 1

case ${1:-} in
  -h|--help)  cmd_usage ;;
  engine)     LA_FROM=engine; export LA_FROM; shift; run_call "$@" ;;
  "")         LA_FROM=engine; export LA_FROM; run_call engine.turn "text=$(cat)" ;;
  *)          LA_FROM=human; export LA_FROM; cmd_run "$@" ;;
esac
