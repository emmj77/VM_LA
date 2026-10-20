#!/usr/bin/dash
# french in code is forbidden
refuse_signal() {
  jq -cn --arg r "refused: $1" --arg ts "$TS" \
    '{status:"refused",line:$r,result:$r,ts:$ts}'
  exit 0
}

cat >/dev/null   # le JSON d entree n est pas lu : on vide le tube
exec 2>/dev/null

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STAMP=$(date -u +'%Y-%m-%d %H:%M')

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
CONF_DIR=$(dirname "$HERE")
DB=${LA_SESSIONS_DB:-$CONF_DIR/sessions.db}
[ -f "$DB" ] || refuse_signal "sessions.db missing ($DB)"
command -v sqlite3 >/dev/null 2>&1 || refuse_signal "sqlite3 missing on the machine"

N=$(sqlite3 "$DB" 'SELECT COUNT(DISTINCT exchange) FROM messages;' 2>/dev/null)
case "${N:-}" in ''|*[!0-9]*) N=0 ;; esac
M=$(sqlite3 "$DB" "SELECT COUNT(*) FROM messages WHERE COALESCE(tool_calls,'') <> '';" 2>/dev/null)
case "${M:-}" in ''|*[!0-9]*) M=0 ;; esac

LINE="$STAMP  signal_task  sessions.db  ->  $N exchanges, $M tool calls"
jq -cn --arg l "$LINE" --arg ts "$TS" '{status:"ok",line:$l,result:$l,ts:$ts}'
exit 0
