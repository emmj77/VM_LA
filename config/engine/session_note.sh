#!/usr/bin/dash
# french in code is forbidden

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
BRICK="$HERE/summary.sh"
MEM=${LA_MEMORY_DB:-$CONF_DIR/memory.db}

SIDE_LINES=$(conf_num note side_lines 2)
REQ_MAX=$(conf_num note request_bytes 4000)
REP_MAX=$(conf_num note reply_bytes 19000)
T_HUMAN=$(conf_str note t_human 'HUMAN REQUEST :')
T_AGENT=$(conf_str note t_agent 'AGENT REPLY :')
T_FRAME_H=$(conf_str note t_frame_human 'WHAT THE HUMAN ASKED, AND WHAT HE GOT')
T_FRAME_A=$(conf_str note t_frame_agent 'WHAT THE AGENT DID, AND WHERE IT STANDS')
T_EMPTY_H=$(conf_str note t_empty_human 'the local model returned nothing on the human side')
T_EMPTY_A=$(conf_str note t_empty_agent 'the local model returned nothing on the agent side')
DB=${LA_SESSIONS_DB:-$CONF_DIR/sessions.db}

REQUEST=${1:-}
REPLY=${2:-}

[ -f "$BRICK" ] || { echo "refused: the compacting brick is missing ($BRICK)" >&2 ; exit 1 ; }
[ -f "$MEM" ] || { echo "refused: the memory base is missing ($MEM)" >&2 ; exit 1 ; }
[ -w "$MEM" ] || { echo "refused: the memory base is not writable ($MEM)" >&2 ; exit 1 ; }
[ -n "$REQUEST" ] || { echo 'refused: no request to compact' >&2 ; exit 1 ; }
[ -n "$REPLY" ] || { echo 'refused: no reply to compact' >&2 ; exit 1 ; }

REQUEST=$(printf '%s' "$REQUEST" | head -c "$REQ_MAX")
REPLY=$(printf '%s' "$REPLY" | head -c "$REP_MAX")

TEXT="$T_HUMAN
$REQUEST

$T_AGENT
$REPLY"

compact() {  # $1 = human|agent ; returns the block on the standard output
  case "$1" in
    agent) FRAME="$T_FRAME_A" ;;
    *)     FRAME="$T_FRAME_H" ;;
  esac
  printf '%s\n\n%s' "$FRAME" "$TEXT" | LA_SUMMARY_BRIEF=1 sh "$BRICK" 2>/dev/null
}

HUMAN_SIDE=$(compact human | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | head -n "$SIDE_LINES")
[ -n "$HUMAN_SIDE" ] || HUMAN_SIDE=$T_EMPTY_H
AGENT_SIDE=$(compact agent | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | head -n "$SIDE_LINES")
[ -n "$AGENT_SIDE" ] || AGENT_SIDE=$T_EMPTY_A

STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

EX=$(sqlite3 "$DB" 'SELECT COALESCE(MAX(exchange),0) FROM messages;' 2>/dev/null || printf '')
case "${EX:-}" in ''|*[!0-9]*) EX=0 ;; esac
_H=$(printf '%s' "$HUMAN_SIDE" | sed "s/'/''/g")
_A=$(printf '%s' "$AGENT_SIDE" | sed "s/'/''/g")

EMB_PORT=${LA_EMBED_PORT:-$(conf_num models port 8091)}
EMB_MODEL=${LA_EMBED_MODEL:-$(conf_str models embed)}
if [ -z "${LA_EMBED_OFF:-}" ] && command -v curl >/dev/null 2>&1; then
  _BODY=$(printf '%s\n%s' "$HUMAN_SIDE" "$AGENT_SIDE" | jq -Rsc --arg m "$EMB_MODEL" '{model: $m, input: .}' 2>/dev/null || printf '')
  if [ -n "$_BODY" ]; then
    _OUT=$(curl -s --max-time "$(conf_num note timeout 20)" -H 'Content-Type: application/json' --data "$_BODY" \
             "http://127.0.0.1:$EMB_PORT/embedding" 2>/dev/null || printf '')
    VEC=$(printf '%s' "$_OUT" | jq -c '.[0].embedding[0] | map((. * 1000000 | round) / 1000000) // empty' 2>/dev/null || printf '')
  fi
fi
case "${VEC:-}" in ''|null) VEC='' ;; esac
if [ -n "$VEC" ]; then
  _V="'$VEC'"
else
  _V='NULL'
  tpn "$(conf_str note t_no_vector 'note: no vector was posed (the embedder is silent on %s) : the entry stays readable by words')" "$EMB_PORT" >&2
fi

sqlite3 "$MEM" "INSERT INTO memory(exchange, stamp, human, agent, vec) VALUES($EX, '$STAMP', '$_H', '$_A', $_V);" 2>/dev/null \
  || { echo "refused: the entry could not be placed ($MEM)" >&2 ; exit 1 ; }

echo "session_note : exchange compacted and placed at $STAMP (exchange $EX, $MEM)"

RESF=${LA_SUMMARY_FILE:-$CONF_DIR/second.yaml}
WINDOW=${LA_WINDOW:-20}
KEPT=${LA_SUMMARY_EXCHANGES:-10}
MAX_LINES=${LA_SUMMARY_LINES:-12}
MAX_BYTES=${LA_SUMMARY_BYTES:-800}

if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  MAX_EXCHANGE=$(sqlite3 "$DB" 'SELECT COALESCE(MAX(exchange),0) FROM messages;' 2>/dev/null || printf '')
  case "${MAX_EXCHANGE:-}" in ''|*[!0-9]*) MAX_EXCHANGE=0 ;; esac
  WINDOW_END=$((MAX_EXCHANGE - WINDOW))   # the last exchange that LEFT the window
  if [ "$WINDOW_END" -ge 1 ]; then
    WINDOW_START=$((WINDOW_END - KEPT + 1))
    [ "$WINDOW_START" -ge 1 ] || WINDOW_START=1
MSG_CHARS=$(conf_num summary msg_chars 1000)
TEXT=$(sqlite3 "$DB" "SELECT (CASE role WHEN 'user' THEN 'ME : ' ELSE 'AGENT : ' END) || substr(COALESCE(content,''), 1, $MSG_CHARS) FROM messages WHERE exchange >= $WINDOW_START AND exchange <= $WINDOW_END AND COALESCE(content,'') <> '' ORDER BY id;" 2>/dev/null | head -c 20000)
    if [ -n "$TEXT" ]; then
      RES=$(printf '%s\n' "$TEXT" \
            | LA_SUMMARY_KIND=exchange sh "$BRICK" 2>/dev/null \
            | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' \
            | head -n "$MAX_LINES" | head -c "$MAX_BYTES")
      if [ -n "$RES" ]; then
        T=$(mktemp "${TMPDIR:-/tmp}/second.XXXXXX") || { echo 'refused: no temporary space' >&2 ; exit 1 ; }
        {
          printf '# THE MICRO-SUMMARY OF THE SECONDARY HEAD (config/second.yaml).\n'
          printf '# WRITTEN BY THE LOCAL MODEL ; OVERWRITTEN at each rewrite : it replaces itself, it does not grow.\n'
          printf 'stamp: "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          printf 'exchanges: "%s-%s"\n' "$WINDOW_START" "$WINDOW_END"
          printf 'bound: "%s lines, %s bytes, held by session_note.sh"\n' "$MAX_LINES" "$MAX_BYTES"
          printf 'summary:\n'
          printf '%s\n' "$RES" | sed -e 's/"/\\"/g' | awk -v d=100 '{ printf "  %d: \"%s\"\n", d + NR, $0 }'
        } > "$T" || { rm -f "$T"; echo 'refused: the summary could not be built' >&2 ; exit 1 ; }
        [ -s "$T" ] || { rm -f "$T"; echo 'refused: the summary wrote nothing' >&2 ; exit 1 ; }
        mv -f "$T" "$RESF" || { rm -f "$T"; echo "refused: the summary could not be placed ($RESF)" >&2 ; exit 1 ; }
        echo "session_note : secondary head summary rewritten ($RESF, exchanges $WINDOW_START-$WINDOW_END)"
      fi
    fi
  fi
fi
