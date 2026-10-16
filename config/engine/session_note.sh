#!/bin/sh
# session_note.sh - THE END-OF-TURN GESTURE (config/engine/session_note.sh).
#
# WHAT IT DOES
#   it takes ONE EXCHANGE (the human's request, the agent's reply), it asks the LOCAL MODEL
#   to compact both sides, and it PLACES a timestamped entry in config/memory.db (the TABLE :
#   the summary of the exchanges). It returns nothing on its standard output : the turn's reply
#   has already gone to the human, and this script does not speak in its place.
#
# THE ARGUMENTS
#   $1  the turn's REQUEST     $2  the turn's REPLY
#
# THE SHAPE IT HOLDS (declared in memory.db, held here)
#   exchange the NUMBER of the exchange it covers : the LINK with the BODY (sessions.db)
#   stamp   the UTC timestamp, placed by THIS SCRIPT (never by the model)
#   human   at most TWO lines : what the human asked, and what he got
#   agent   at most TWO lines : what the agent did, and where it stands
#   The compaction comes from the MODEL (safe mode of summary.sh, 6 lines / 400 bytes) ; when
#   the model does not separate its two blocks, we SAY so in the human block and the text goes
#   into the agent block : NEVER a block invented by this script.
#
# THE REFUSAL
#   one line on the error output, code 1, and NOTHING written : without a local model that
#   answers, or without a reply, there is no exchange to compact, so no entry.
#
# POSIX sh (dash) + coreutils, ASCII without backtick, no key.

LC_ALL=C
export LC_ALL

HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
BRICK="$HERE/summary.sh"
MEM=${LA_MEMORY_DB:-$CONF_DIR/memory.db}
DB=${LA_SESSIONS_DB:-$CONF_DIR/sessions.db}

REQUEST=${1:-}
REPLY=${2:-}

[ -f "$BRICK" ] || { echo "refused: the compacting brick is missing ($BRICK)" >&2 ; exit 1 ; }
[ -f "$MEM" ] || { echo "refused: the memory base is missing ($MEM)" >&2 ; exit 1 ; }
[ -w "$MEM" ] || { echo "refused: the memory base is not writable ($MEM)" >&2 ; exit 1 ; }
[ -n "$REQUEST" ] || { echo 'refused: no request to compact' >&2 ; exit 1 ; }
[ -n "$REPLY" ] || { echo 'refused: no reply to compact' >&2 ; exit 1 ; }

# the exchange carried to the model, bounded : the request keeps 4000 bytes, the reply 19000,
# so the whole stays under the brick's input bound (24000 bytes).
REQUEST=$(printf '%s' "$REQUEST" | head -c 4000)
REPLY=$(printf '%s' "$REPLY" | head -c 19000)

TEXT="HUMAN REQUEST :
$REQUEST

AGENT REPLY :
$REPLY"

# THE COMPACTION, IN TWO CALLS. Each asks ONLY ONE side, with no mark to respect : the small
# local model does not hold a format, it holds a single, short question.
# (measured : an instruction with two blocks and two marks, it returns prose.)
compact() {  # $1 = human|agent ; returns the block on the standard output
  case "$1" in
    agent) FRAME="WHAT THE AGENT DID, AND WHERE IT STANDS" ;;
    *)     FRAME="WHAT THE HUMAN ASKED, AND WHAT HE GOT" ;;
  esac
  printf '%s\n\n%s' "$FRAME" "$TEXT" | LA_SUMMARY_BRIEF=1 sh "$BRICK" 2>/dev/null
}

HUMAN_SIDE=$(compact human | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | head -n 2)
[ -n "$HUMAN_SIDE" ] || HUMAN_SIDE='the local model returned nothing on the human side'
AGENT_SIDE=$(compact agent | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | head -n 2)
[ -n "$AGENT_SIDE" ] || AGENT_SIDE='the local model returned nothing on the agent side'

STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# THE ENTRY GOES INTO THE BASE (memory.db), NEVER INTO A FILE. The model does not hold a format,
# so the SCRIPT holds it. THE LINK WITH THE BODY (sessions.db) IS THE EXCHANGE : the summary
# names the exchange it covers, and the body carries that number -- that is what makes the
# summary usable (choose here, read there). Same hand as db_add in loop.sh : one quote becomes
# two, then an INSERT. Nothing is invented : without the model's two sides, no entry.
EX=$(sqlite3 "$DB" 'SELECT COALESCE(MAX(exchange),0) FROM messages;' 2>/dev/null || printf '')
case "${EX:-}" in ''|*[!0-9]*) EX=0 ;; esac
_H=$(printf '%s' "$HUMAN_SIDE" | sed "s/'/''/g")
_A=$(printf '%s' "$AGENT_SIDE" | sed "s/'/''/g")
sqlite3 "$MEM" "INSERT INTO memory(exchange, stamp, human, agent) VALUES($EX, '$STAMP', '$_H', '$_A');" 2>/dev/null \
  || { echo "refused: the entry could not be placed ($MEM)" >&2 ; exit 1 ; }

echo "session_note : exchange compacted and placed at $STAMP (exchange $EX, $MEM)"

# --- THE MICRO-SUMMARY OF THE SECONDARY HEAD (laws 110, 810, 1716, 1915) ------------------
# THE EXCHANGES THAT LEFT THE WINDOW are summarized by the local model, and the place of the
# secondary head is OVERWRITTEN at each rewrite : it REPLACES itself, it does not grow.
# The SOURCE is the BODY (sessions.db), never the window : what left the context is precisely
# what the window no longer carries.
#   THE WINDOW keeps TWENTY exchanges (law 1915) ; the summary covers the LAST TEN that left (810).
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
    TEXT=$(sqlite3 "$DB" "SELECT (CASE role WHEN 'user' THEN 'ME : ' ELSE 'AGENT : ' END) || COALESCE(content,'') FROM messages WHERE exchange >= $WINDOW_START AND exchange <= $WINDOW_END AND COALESCE(content,'') <> '' ORDER BY id;" 2>/dev/null | head -c 20000)
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
