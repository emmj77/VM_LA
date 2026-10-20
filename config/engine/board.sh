#!/usr/bin/dash
# french in code is forbidden
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
PANEL="$HERE/../programs/board.py"
[ -f "$PANEL" ] || { printf '%s\n' "$(msg board_absent "$PANEL")" >&2 ; exit 2 ; }
exec /usr/bin/python3 "$PANEL" "$@"
