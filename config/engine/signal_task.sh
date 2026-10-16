#!/bin/sh
# signal_task : tool called by THE LOOP, AT THE END OF A TASK (after answer, or after a stop
# bound) ; NEVER by the LLM ('04 - LE FILTRE'). Family READ : it only READS what is already
# written, and returns ONE LINE - a signal to the human ('11 - LE RETOUR DES OUTILS').
# The register that holds is THE SESSION BASE (sessions.db) : that is where the turn is
# transcribed (law 1607 : a session is a REGISTER). It writes NO file : 'a signal has only one
# reader' ('04 - LE FILTRE'), so no template carries its shape - its JSON line is built by
# jq -cn ('13 - LES PROCS').
# Input : a JSON object on stdin (this tool takes no argument). Output : one JSON line
# {status,line,result,ts}. A refusal is a RESULT : same text in line and result, rc=0, nothing
# on stderr.
# TRAP : no backtick in this file - dash would open a command substitution.
refuse_signal() {
  jq -cn --arg r "refused: $1" --arg ts "$TS" \
    '{status:"refused",line:$r,result:$r,ts:$ts}'
  exit 0
}

INPUT=$(cat)
exec 2>/dev/null

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STAMP=$(date -u +'%Y-%m-%d %H:%M')

# --- [1] the session base : the register that holds, placed by the loop (config/sessions.db).
#     The proc guesses no path : the base lives next to the engine, LA_SESSIONS_DB overrides it.
HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
CONF_DIR=$(dirname "$HERE")
DB=${LA_SESSIONS_DB:-$CONF_DIR/sessions.db}
[ -f "$DB" ] || refuse_signal "sessions.db missing ($DB)"
command -v sqlite3 >/dev/null 2>&1 || refuse_signal "sqlite3 missing on the machine"

# --- [2] what is already written : the exchanges, then the tool calls of the base.
N=$(sqlite3 "$DB" 'SELECT COUNT(DISTINCT exchange) FROM messages;' 2>/dev/null)
case "${N:-}" in ''|*[!0-9]*) N=0 ;; esac
M=$(sqlite3 "$DB" "SELECT COUNT(*) FROM messages WHERE COALESCE(tool_calls,'') <> '';" 2>/dev/null)
case "${M:-}" in ''|*[!0-9]*) M=0 ;; esac

LINE="$STAMP  signal_task  sessions.db  ->  $N exchanges, $M tool calls"
jq -cn --arg l "$LINE" --arg ts "$TS" '{status:"ok",line:$l,result:$l,ts:$ts}'
exit 0
