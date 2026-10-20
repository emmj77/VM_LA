#!/usr/bin/dash
# french in code is forbidden
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

SEVERE=$(printf '\140')
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
TABLE=${LA_CONFIG:-$CONF_DIR/la_tools.yaml}
active_skill

[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
TABLE=${LA_CONFIG:-$CONF_DIR/la_tools.yaml}
active_skill


_MODELS_PORT=$(conf_num models port 8091)
export LA_EMBED_PORT=${LA_EMBED_PORT:-$_MODELS_PORT}
export LA_RERANK_PORT=${LA_RERANK_PORT:-$_MODELS_PORT}
export LA_LOCAL_PORT=${LA_LOCAL_PORT:-$_MODELS_PORT}
export LA_EMBED_MODEL=${LA_EMBED_MODEL:-$(conf_str models embed harrier-oss-v1-270M-Q8_0)}
export LA_RERANK_MODEL=${LA_RERANK_MODEL:-$(conf_str models rerank bge-reranker-v2-m3-Q4_K_M)}
export LA_LOCAL_MODEL=${LA_LOCAL_MODEL:-$(conf_str models local LFM2.5-1.2B-Instruct-Q4_K_M)}

export LA_ASR_PORT=${LA_ASR_PORT:-$(conf_num asr port 8080)}
export LA_TTS_PORT=${LA_TTS_PORT:-$(conf_num tts port 8090)}
export LA_KRITA_HOST=${LA_KRITA_HOST:-$(conf_str krita host)}
export LA_KRITA_PORT=${LA_KRITA_PORT:-$(conf_num krita port)}

blender() {
  [ "$#" -gt 0 ] || { printf '%s\n' "$(msg blender_none)" >&2 ; exit 1 ; }
  BIN=$(conf_str blender bin)
  [ -x "$BIN" ] || { printf '%s\n' "$(msg blender_bin)" >&2 ; exit 1 ; }
  DELAI=$(conf_num blender timeout 110)
  ARGV=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
  PY="$(cat <<'END'
import json
import sys
import traceback

import bpy

def _arguments(argv):
    op, args, file = None, {}, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--op" and i + 1 < len(argv):
            op = argv[i + 1]
            i += 2
        elif a == "--arg" and i + 1 < len(argv):
            k, _, v = argv[i + 1].partition("=")
            if v != "":
                args[k] = v
            i += 2
        elif a == "--fichier" and i + 1 < len(argv):
            file = argv[i + 1]
            i += 2
        else:
            i += 1
    return op, args, file


def convertir(prop, value):
    t = prop.type

    def un(raw):
        b = raw.strip()
        if t == "INT":
            return int(float(b))
        if t in ("FLOAT", "FLOAT_COLOR"):
            return float(b)
        if t == "BOOLEAN":
            return b.lower() in ("1", "true", "vrai", "oui")
        return raw

    if getattr(prop, "is_array", False):
        pieces = [m for m in value.replace(" ", ",").split(",") if m != ""]
        vals = [un(m) for m in pieces]
        manque = getattr(prop, "array_length", 0) - len(vals)
        if manque > 0:
            vals += [1.0 if (t == "FLOAT_COLOR" and i == prop.array_length - 1) else un("0")
                     for i in range(len(vals), prop.array_length)]
        return vals[:prop.array_length] if manque < 0 else vals
    return un(value)


def _appeler(argv):
    op, args, file = _arguments(argv)
    res = {"op": op, "args": {}, "result": None, "error": None}
    if not op:
        res["error"] = "refused: --op is missing"
        return res
    try:
        if file:
            bpy.ops.wm.open_mainfile(filepath=file)
        path = op.split(".")
        target = bpy.ops
        for piece in path[:-1]:
            target = getattr(target, piece)
        function = getattr(target, path[-1])
        rna = function.get_rna_type()
        clean = {}
        for name, raw in args.items():
            if raw == "":
                continue
            if name not in rna.properties:
                res["error"] = "refused: %s has no property %s" % (op, name)
                return res
            clean[name] = convertir(rna.properties[name], raw)
        res["args"] = {k: (v if not hasattr(v, "to_list") else list(v)) for k, v in clean.items()}
        result = function(**clean)
        res["result"] = sorted(result)
        if "CANCELLED" in result:
            res["error"] = "refused: the operator cancelled (CANCELLED) -- a selection or a mode"
    except RuntimeError as e:
        res["error"] = "refused: %s" % e
    except (TypeError, ValueError, AttributeError, KeyError) as e:
        res["error"] = "refused: call impossible (%s: %s)" % (type(e).__name__, e)
    finally:
        try:
            bpy.ops.ed.undo_push(message="la: " + str(op))
        except Exception:
            pass
    return res

END
)"
  EXPR="$PY
print('@@OP@@' + json.dumps(_appeler($ARGV), ensure_ascii=False) + '@@END@@')"
  OUT=$(timeout "$DELAI" "$BIN" --background --factory-startup --python-expr "$EXPR" 2>&1)
  LINE=$(printf '%s' "$OUT" | sed -n 's/.*@@OP@@\(.*\)@@END@@.*/\1/p' | tail -1)
  [ -n "$LINE" ] || { printf '%s\n' "$(msg blender_fail "$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')")" >&2 ; exit 1 ; }
  ERROR=$(printf '%s' "$LINE" | jq -r '.error // empty')
  [ -z "$ERROR" ] || { printf '%s\n' "$ERROR" >&2 ; exit 1 ; }
  printf '%s\n' "$LINE" | jq -c '{op, args, result}'
}

blender_cli() {
  BIN=$(conf_str blender bin)
  [ -x "$BIN" ] || { printf '%s\n' "$(msg blender_bin)" >&2 ; exit 1 ; }
  OP=${2:-}
  [ -n "$OP" ] || { printf '%s\n' "$(msg blender_none)" >&2 ; exit 1 ; }
  env -u DISPLAY timeout "$(conf_num blender timeout 110)" "$BIN" --background --factory-startup --command "$OP" </dev/null
}

krita_url() {
  HOST=$(conf_str krita host)
  PORT=$(conf_num krita port)
  [ -n "$HOST" ] && [ -n "$PORT" ] || { printf '%s\n' "$(msg krita_noport)" >&2 ; exit 1 ; }
  SERVICE="http://$HOST:$PORT"
  curl -sf --max-time 10 "$SERVICE/health" >/dev/null 2>&1 \
    || { printf '%s\n' "$(msg krita_down "$SERVICE")" >&2 ; exit 1 ; }
  printf '%s\n' "$SERVICE"
}

case "${1:-}" in
  carrier)
    shift
    M=${1:-}
    [ -n "$M" ] || { printf '%s\n' "$(msg tool_unknown vide)" >&2 ; exit 1 ; }
    shift
    case "$M" in
      blender) blender "$@" ;;
      blender-cli) blender_cli "$@" ;;
      krita-url) krita_url ;;
      *) printf '%s\n' "$(msg tool_unknown "$M")" >&2 ; exit 1 ;;
    esac
    exit $? ;;
esac
export LA_UNITY_CLI=${LA_UNITY_CLI:-$(conf_str unity cli)}
export LA_UNITY_MCP=${LA_UNITY_MCP:-$(conf_str unity mcp)}
export LA_BLENDER_BIN=${LA_BLENDER_BIN:-$(conf_str blender bin)}

TS=$(ts)
TOOL=unknown
ARGS_LINE=
NAMES_STDIN=' '
NAMES_TEXT=' '
BASE=
STDIN_FREE=no
TMPD=

CAP_BYTES=${LA_CAP_BYTES:-$(conf_num limits engine_bytes 4000)}
CAP_LINES=${LA_CAP_LINES:-$(conf_num limits engine_lines 200)}
TIMEOUT=${LA_TIMEOUT:-$(conf_num limits engine_timeout 600)}

command -v jq >/dev/null 2>&1 || {
  printf '{"status":"refused","tool":"unknown","line":"jq is missing from the machine","result":"refused: jq is missing, the engine could not write the single shape","ts":"%s"}\n' "$(ts)"
  exit 0
}

one_line() {   # $1 = a multi-line message -> ONE line for the human
  printf '%s' "$1" | tr '\n\t' '  ' | jq -Rr 'if length > 400 then .[0:400] + " ..." else . end' 2>/dev/null
}
shape() {       # $1 status - $2 tool - $3 line - $4 result - $5 return id (optional)
  jq -cn --arg st "$1" --arg t "$2" --arg l "$3" --arg r "$4" --arg ts "$TS" --argjson rid "${5:-null}" \
    '{status:$st,tool:$t,line:$l,result:$r,ts:$ts} + (if $rid == null then {} else {return:$rid} end)' 2>/dev/null \
  || printf '{"status":"refused","tool":"engine","line":"the single shape could not be built","result":"refused: the engine could not write the single shape","ts":"%s"}\n' "$TS"
  exit 0
}
file_shape() {   # the same shape, the result read AS IS from a file (exact bytes)
  if jq -cn --arg st "$1" --arg t "$2" --arg l "$3" --arg ts "$TS" --rawfile r "$4" --argjson rid "${5:-null}" \
       '{status:$st,tool:$t,line:$l,result:$r,ts:$ts} + (if $rid == null then {} else {return:$rid} end)' 2>/dev/null; then
    exit 0
  fi
  shape "$1" "$2" "$3" ""
}

RETURN_DB=${LA_RETURN_DB:-$CONF_DIR/terminal_return.db}
RETURN_MAX=$(conf_num limits return_bytes 4000)
q() { printf '%s' "$1" | sed "s/'/''/g" ; }
keep_return() {   # $1 tool - $2 line - $3 file holding the exact bytes -> prints the id (or nothing)
  command -v sqlite3 >/dev/null 2>&1 || return 1
  [ -f "$RETURN_DB" ] || sqlite3 "$RETURN_DB" 'CREATE TABLE IF NOT EXISTS terminal_return (id INTEGER PRIMARY KEY AUTOINCREMENT, exchange INTEGER, tool TEXT NOT NULL, line TEXT, bytes INTEGER, lines INTEGER, path TEXT, body TEXT, stamp TEXT) ;' >/dev/null 2>&1 || return 1
  [ -f "$3" ] || return 1
  CO=$(count "$3")
  RB=${CO%% *} ; RL=${CO##* }
  RP=
  case "$3" in "$W"/*) RP=${3#"$ROOT"/} ;; esac
  if [ "${RB:-0}" -le "$RETURN_MAX" ] ; then RQ="readfile('$(q "$3")')" ; else RQ=NULL ; fi
  RID=$(sqlite3 "$RETURN_DB" "INSERT INTO terminal_return (exchange, tool, line, bytes, lines, path, body, stamp) VALUES (${LA_EXCHANGE:-NULL}, '$(q "$1")', '$(q "$2")', ${RB:-0}, ${RL:-0}, NULLIF('$(q "$RP")',''), $RQ, '$(ts)') ; SELECT last_insert_rowid() ;" 2>/dev/null | tr -d ' ')
  if [ -n "$RID" ] && [ "${RB:-0}" -gt "$RETURN_MAX" ] && [ -n "${W:-}" ] ; then
    [ -d "$RETURNS" ] || mkdir -p "$RETURNS" 2>/dev/null
    cp "$3" "$RETURNS/$RID-$1.txt" 2>/dev/null && \
      sqlite3 "$RETURN_DB" "UPDATE terminal_return SET path = '$(q "${RETURNS#"$ROOT"/}/$RID-$1.txt")' WHERE id = $RID ;" 2>/dev/null
  fi
  printf '%s' "$RID"
}
refuse_tool() {       # $1 = the detail ; the refusal is NAMED, it is never silent
  shape refused "$TOOL" "$(one_line "refused: $1")" "refused: $1"
}
refuse_preformed() {   # $1 = the already-formed message (the command's, as is)
  shape refused "$TOOL" "$(one_line "$1")" "$1"
}

count() {   # $1 = file ; writes "<bytes> <lines>" on the standard output
  O=$(wc -c < "$1" 2>/dev/null | tr -d ' ')
  L=$(wc -l < "$1" 2>/dev/null | tr -d ' ')
  case "$O" in ''|*[!0-9]*) O=0 ;; esac
  case "$L" in ''|*[!0-9]*) L=0 ;; esac
  if [ -s "$1" ] && [ -n "$(tail -c 1 "$1" 2>/dev/null)" ]; then L=$((L + 1)); fi
  printf '%s %s' "$O" "$L"
}
bound_file() {   # $1 = raw file ; the cut ALWAYS goes through iconv
  F=$1
  set -- $(count "$F")
  O=$1
  L=$2
  if [ "$O" -le "$CAP_BYTES" ] && [ "$L" -le "$CAP_LINES" ]; then
    return 1
  fi
  FRAME=$(conf_num limits frame_bytes 400)
  CONTENT=$((CAP_BYTES - FRAME))
  [ "$CONTENT" -gt 200 ] || CONTENT=200
  HT=$((CONTENT * 3 / 5))
  QT=$((CONTENT - HT))
  if iconv -f UTF-8 -t UTF-8 "$F" >/dev/null 2>&1; then
    HEAD_PART=$(head -c "$HT" "$F" 2>/dev/null | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
    TAIL_PART=$(tail -c "$QT" "$F" 2>/dev/null | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
  else
    HEAD_PART=$(head -c "$HT" "$F" 2>/dev/null)
    TAIL_PART=$(tail -c "$QT" "$F" 2>/dev/null)
  fi
  FILE_NAME="truncated-output-$(date -u +%Y%m%dT%H%M%SZ)-${TOOL}.txt"
  OUT_PATH="$W/$FILE_NAME"
  if ! cp "$F" "$OUT_PATH" 2>/dev/null; then OUT_PATH=; fi
  printf '[TRUNCATED] the raw output is %s byte(s) and %s line(s) ; the caps are %s byte(s) and %s line(s).\n' "$O" "$L" "$CAP_BYTES" "$CAP_LINES"
  if [ -n "$OUT_PATH" ]; then
    REL=${OUT_PATH#"$ROOT"/}
    printf 'complete output (as is) : %s (%s byte(s), %s line(s))\n' "$REL" "$O" "$L"
  else
    printf 'the complete output could not be written under $W (%s)\n' "$W"
  fi
  printf -- '--- HEAD_PART (start) ---\n%s\n--- TAIL_PART (end) ---\n%s\n' "$HEAD_PART" "$TAIL_PART"
  printf '[TRUNCATED] head and tail only ; the rest is in the file above.\n'
  return 0
}

ID=${1:-}
case "$ID" in
  ''|*[!0-9]*)
    refuse_tool "the id is missing or off-form (${1:-none}) ; an id is a number, and it is the one of the table line" ;;
esac
shift

[ -e "$TABLE" ] || refuse_tool "the table is missing ($TABLE)"
[ -f "$TABLE" ] || refuse_tool "the table is not a file ($TABLE)"
[ -r "$TABLE" ] || refuse_tool "the table is unreadable ($TABLE)"

BLOCK=$(table_block "$TABLE" "$ID")
[ -n "$BLOCK" ] || refuse_tool "the id $ID is not in the table : no line carries that id ($TABLE)"

TOOL=$(printf '%s\n' "$BLOCK" | sed -n 's/^    tool:[[:space:]]*//p' | head -n 1)
FAMILY=$(printf '%s\n' "$BLOCK" | sed -n 's/^    family:[[:space:]]*//p' | head -n 1)
[ -n "$TOOL" ] || refuse_tool "the line $ID is unreadable : it carries no tool field"
case "$TOOL" in *[!a-z0-9_]*) refuse_tool "the line $ID carries an off-form tool ($TOOL)" ;; esac
case "$FAMILY" in
  READ|WRITE|MANAGE|REPLY|PLAN|VISION|BLENDER|UNITY|KRITA|IMAGE) ;;
  *) refuse_tool "the line $ID ($TOOL) carries an off-form family (${FAMILY:-absent}) ; the families are READ, WRITE, MANAGE, REPLY, PLAN, VISION, BLENDER, UNITY, KRITA, IMAGE" ;;
esac
TOOLFILE=$(tool_file_of "$TOOL") || refuse_tool "the tool $TOOL has no body : no file tool_$TOOL.yaml under config/tools/ carries a command ($ROOT/config/tools/*/tool_$TOOL.yaml)"
[ -r "$TOOLFILE" ] || refuse_tool "the file of the tool $TOOL is unreadable ($TOOLFILE)"
FCMD=$(awk '/^COMMAND: \|$/{f=1;next} f&&/^[^ ]/{exit} f{sub(/^  /,"");print}' "$TOOLFILE")
FMACH=$(sed -n 's/^machine:[[:space:]]*//p' "$TOOLFILE" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
FOP=$(sed -n 's/^op:[[:space:]]*//p' "$TOOLFILE" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
if [ -z "$FCMD" ] && [ -n "$FMACH" ]; then
  [ -n "$FOP" ] || refuse_tool "the tool $TOOL names a machine ($FMACH) without op : the carrier needs the operation to run"
  FCMD="$FMACH --op $FOP"
  CARRIER=yes
  for _an in $(sed -n 's/^  - {name:[[:space:]]*\([^,}]*\),.*/\1/p' "$TOOLFILE"); do
    FCMD="$FCMD --arg \"$_an={{$_an}}\""
  done
fi
FABLOC=$(awk '/^ARGS:/{f=1;next} f&&/^[^ ]/{exit} f{sub(/^  /,"      ");print}' "$TOOLFILE")
FTMO=$(sed -n 's/^  timeout:[[:space:]]*//p' "$TOOLFILE" | head -n 1)
FENB=$(sed -n 's/^  enabled:[[:space:]]*//p' "$TOOLFILE" | head -n 1)
FVER=$(sed -n 's/^tool:[[:space:]]*//p' "$TOOLFILE" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
[ "$FVER" = "$TOOL" ] || refuse_tool "the file of the tool $TOOL names another tool (${FVER:-rien}) : the file and the register must say the same name ($TOOLFILE)"
case "$FTMO" in
  '') ;;
  *[!0-9]*) refuse_tool "the file of the tool $TOOL carries an off-form timeout (${FTMO}) ; it carries seconds, and digits only" ;;
  *) TIMEOUT=$FTMO ;;
esac

case "$FENB" in
  ''|true) ;;
  false) refuse_tool "the tool $TOOL is disabled : its file carries enabled: false, and the engine does not execute it ; reactivate it before calling it (${TOOLFILE:-line $ID})" ;;
  *)     refuse_tool "the enabled field of the tool $ID ($TOOL) is off-form (${FENB}) ; it carries true or false" ;;
esac

CMD=$FCMD
[ -n "$CMD" ] || refuse_tool "the file of the tool $TOOL carries no command ($TOOLFILE)"

[ -f "$SKILL" ] || refuse_tool "the ACTIVE SKILL is missing ($SKILL) : the engine has nowhere to read the registers of the active skill"
SKW=$(sed -n '/^PERIMETER:/,/^[^[:space:]]/p' "$SKILL" | sed -n 's/^[[:space:]]*workspace:[[:space:]]*//p' | head -n 1)
value() {   # $1 = the skill value ; cleans it, and refuses what leaves the project
  V=$(printf '%s' "$1" | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" -e 's:/*$::')
  [ -n "$V" ] || refuse_tool "the ACTIVE SKILL carries no PERIMETER.$2 ($SKILL)"
  case "$V" in *..*) refuse_tool "PERIMETER.$2 of the ACTIVE SKILL goes up ($V)" ;; esac
  case "$V" in
    /*) printf '%s' "$V" ;;
    *)  printf '%s' "$ROOT/$V" ;;
  esac
}
SKROOT=$(dirname "$SKILL")
W=$(value "$SKW" workspace)
canon_path
SPEC_FILE="$SPEC"
PROCS=$HERE
export ROOT SKROOT W PROCS SKILL SPEC_FILE
LA_CONFIG=$TABLE
export LA_CONFIG
LA_FROM=${LA_FROM:-agent_one}
export LA_FROM
state_paths

BASE=
case "$FAMILY" in
  READ|VISION)                       BASE=$ROOT ;;
  WRITE|BLENDER|UNITY|KRITA|IMAGE)   BASE=$W ;;
  MANAGE|PLAN|REPLY)                 BASE= ;;
esac

ABLOC=$FABLOC
NA=$(printf '%s\n' "$ABLOC" | grep -c '^      - {')
NOT_STDIN=$(printf '%s\n' "$ABLOC" | sed -n 's/^      - {\([^}]*\)}.*$/\1/p' | grep -c 'stdin:[[:space:]]*true')
DECLARES=$((NA - NOT_STDIN))
GIVEN=$#
[ "$GIVEN" -le "$DECLARES" ] \
  || refuse_tool "the arity of the line $ID ($TOOL) is exceeded : $DECLARES argument(s) outside stdin, $GIVEN received"

MAP='{}'
i=0
while [ "$i" -lt "$NA" ]; do
  i=$((i + 1))
  ARG_LINE=$(printf '%s\n' "$ABLOC" | grep '^      - {' | sed -n "${i}p")
  SPEC=$(printf '%s' "$ARG_LINE" | sed -n 's/^      - {\([^}]*\)}.*$/\1/p')
  [ -n "$SPEC" ] \
    || refuse_tool "the line $ID ($TOOL) is unreadable : the $i-th argument declaration cannot be read"

  VJ='null'
  case "$SPEC" in
    *'values:'*)
      VL=$(printf '%s' "$SPEC" | sed -n 's/.*values:[[:space:]]*\[\([^]]*\)\].*/\1/p')
      SPEC=$(printf '%s' "$SPEC" | sed 's/values:[[:space:]]*\[[^]]*\],\{0,1\}[[:space:]]*//')
      if [ -z "$VL" ]; then
        VJ='[]'
      else
        VJ=$(printf '%s\n' "$VL" | tr ',' '\n' \
             | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' \
             | jq -R . | jq -cs .)
      fi
      ;;
  esac

  ARG_NAME=$(printf '%s' "$SPEC" | sed -n 's/.*name:[[:space:]]*\([^,]*\).*/\1/p' | sed -e 's/[[:space:]]*$//')
  ARG_TYPE=$(printf '%s' "$SPEC" | sed -n 's/.*type:[[:space:]]*\([^,]*\).*/\1/p' | sed -e 's/[[:space:]]*$//')
  ARG_STDIN=$(printf '%s' "$SPEC" | sed -n 's/.*stdin:[[:space:]]*\([^,]*\).*/\1/p' | sed -e 's/[[:space:]]*$//')
  [ -n "$ARG_NAME" ] || refuse_tool "the line $ID ($TOOL) is unreadable : an argument declaration carries no name"
  case "$ARG_NAME" in *[!A-Za-z0-9_]*) refuse_tool "the line $ID ($TOOL) carries an off-form argument ($ARG_NAME)" ;; esac
  case "$ARG_TYPE" in
    path|enum|int|bool|text) ;;
    *) refuse_tool "the line $ID ($TOOL) carries an unknown type for $ARG_NAME (${ARG_TYPE:-absent}) ; the types are path, enum, int, bool, text" ;;
  esac
  case "$ARG_STDIN" in
    ''|true|false) ;;
    *) refuse_tool "the line $ID ($TOOL) carries an off-form stdin for $ARG_NAME ($ARG_STDIN)" ;;
  esac

  if [ "$ARG_STDIN" = true ]; then
    case "$ARG_TYPE" in
      text) ;;
      *) refuse_tool "the line $ID ($TOOL) marks $ARG_NAME (type $ARG_TYPE) on the standard input ; only a text enters it" ;;
    esac
    NAMES_STDIN="$NAMES_STDIN$ARG_NAME "
    STDIN_FREE=yes
    continue
  fi

  if [ $# -gt 0 ]; then ARG_VALUE=$1; shift; else ARG_VALUE=; fi
  [ "$ARG_TYPE" = text ] && NAMES_TEXT="$NAMES_TEXT$ARG_NAME "

  case "$ARG_TYPE" in
    enum)
      LIST=$(printf '%s' "$VJ" | jq -r 'join(" | ")')
      [ "$VJ" != 'null' ] \
        || refuse_tool "the line $ID ($TOOL) declares $ARG_NAME as enum without a closed list (values)"
      printf '%s' "$VJ" | jq -e --arg v "$ARG_VALUE" 'index($v) != null' >/dev/null 2>&1 \
        || refuse_tool "$TOOL : ${ARG_VALUE:-an empty value} is not in the closed list of $ARG_NAME ; values : $LIST"
      ;;
    int)
      case "$ARG_VALUE" in *[!0-9]*) refuse_tool "$TOOL : $ARG_NAME expects digits, or nothing to take the table default (${ARG_VALUE:-absent})" ;; esac
      ;;
    bool)
      case "$ARG_VALUE" in true|false) ;; *) refuse_tool "$TOOL : $ARG_NAME expects true or false (${ARG_VALUE:-absent})" ;; esac
      ;;
    text)
      ;;
    path)
      case "$ARG_VALUE" in
        /*) refuse_tool "$TOOL : $ARG_NAME is an ABSOLUTE path ($ARG_VALUE) ; a path is relative, and the engine resolves it" ;;
        \~*) refuse_tool "$TOOL : $ARG_NAME starts with ~ ($ARG_VALUE) ; a path is relative, and the engine resolves it" ;;
      esac
      case "$ARG_VALUE" in
        *..*) refuse_tool "$TOOL : $ARG_NAME goes up : a path never carries .. ($ARG_VALUE)" ;;
      esac
      case "$ARG_VALUE" in
        *'"'*)       refuse_tool "$TOOL : $ARG_NAME carries a quote ($ARG_VALUE)" ;;
        *\$*)        refuse_tool "$TOOL : $ARG_NAME carries a dollar ($ARG_VALUE)" ;;
        *"$SEVERE"*)  refuse_tool "$TOOL : $ARG_NAME carries a backtick ($ARG_VALUE)" ;;
        *\\*|*'*'*|*'?'*|*'['*|*']'*)
                     refuse_tool "$TOOL : $ARG_NAME carries a pattern, and a tool walks nothing ($ARG_VALUE)" ;;
      esac
      if printf '%s' "$ARG_VALUE" | grep -q '[[:cntrl:]]'; then
        refuse_tool "$TOOL : $ARG_NAME carries a control character"
      fi
      if [ "$FAMILY" = REPLY ]; then
        refuse_tool "$TOOL : the REPLY family carries no path, and $ARG_NAME is one ($ARG_VALUE)"
      fi
      if [ -n "$BASE" ] && [ -n "$ARG_VALUE" ]; then
        BCAN=$(readlink -f -- "$BASE" 2>/dev/null)
        TCAN=$(readlink -f -- "$BASE/$ARG_VALUE" 2>/dev/null)
        if [ -n "$BCAN" ] && [ -n "$TCAN" ]; then
          case "$TCAN" in
            "$BCAN"|"$BCAN"/*) ;;
            *) refuse_tool "$TOOL : the resolved path leaves the register of the family $FAMILY ($ARG_VALUE)" ;;
          esac
        fi
      fi
      ;;
  esac

  MAP=$(printf '%s' "$MAP" | jq -c --arg n "$ARG_NAME" --arg v "$ARG_VALUE" '. + {($n):$v}')
  ARGS_LINE="$ARGS_LINE $ARG_NAME=$ARG_VALUE"
done

[ $# -eq 0 ] || refuse_tool "the arity of the line $ID ($TOOL) is exceeded : $DECLARES argument(s) outside stdin, and $# remain"
ARGS_LINE=$(printf '%s' "$ARGS_LINE" | jq -Rr 'if length > 160 then .[0:160] + " ..." else . end' 2>/dev/null)

REMAINING=$CMD
BODY=
while case "$REMAINING" in *'{{'*) true ;; *) false ;; esac; do
  BEFORE=${REMAINING%%'{{'*}
  AFTER=${REMAINING#*'{{'}
  NAME=${AFTER%%[!A-Za-z0-9_]*}
  HOLE='{{'"$NAME"'}}'
  OKAY=hole
  [ -n "$NAME" ] || OKAY=no
  case "$REMAINING" in *"$HOLE"*) ;; *) OKAY=no ;; esac
  if [ "$OKAY" = no ]; then
    BODY="$BODY$BEFORE{{"
    REMAINING=$AFTER
  else
    VALUE=$HOLE
    case "$NAMES_STDIN" in
      *" $NAME "*) ;;                                  # the free text : it stays a template hole
      *)
        if printf '%s' "$MAP" | jq -e --arg n "$NAME" 'has($n)' >/dev/null 2>&1; then
          VALUE=$(printf '%s' "$MAP" | jq -r --arg n "$NAME" '.[$n]')
          case "$NAMES_TEXT" in
            *" $NAME "*)
              case "$VALUE" in
                *'"'*)      refuse_preformed "refused: $TOOL : the argument $NAME enters the command and carries a quote ; an argument is never interpreted text" ;;
                *'$'*)      refuse_preformed "refused: $TOOL : the argument $NAME enters the command and carries a dollar ; an argument is never interpreted text" ;;
                *"$SEVERE"*) refuse_preformed "refused: $TOOL : the argument $NAME enters the command and carries a backtick ; an argument is never interpreted text" ;;
                *'\'*)      refuse_preformed "refused: $TOOL : the argument $NAME enters the command and carries a backslash ; an argument is never interpreted text" ;;
              esac
              if printf '%s' "$VALUE" | grep -q '[[:cntrl:]]'; then
                refuse_preformed "refused: $TOOL : the argument $NAME enters the command and carries a control character"
              fi
              ;;
          esac
        fi
        ;;
    esac
    BODY="$BODY$BEFORE$VALUE"
    REMAINING=${REMAINING#*"$HOLE"}
  fi
done
BODY="$BODY$REMAINING"
BODY="ROOT='$ROOT' ; HERE='$ROOT/config/engine' ; . \"\$HERE/lib.sh\"
$BODY"


TMPD=$(mktemp -d "${TMPDIR:-/tmp}/engine.XXXXXX" 2>/dev/null)
[ -n "$TMPD" ] && [ -d "$TMPD" ] || refuse_tool "the engine could not open its temporary workspace (${TMPDIR:-/tmp})"
cleanup_tmp_engine() { rm -f "$TMPD"/* 2>/dev/null; rmdir "$TMPD" 2>/dev/null; }
trap 'cleanup_tmp_engine' EXIT INT TERM HUP

SH=$(shell_path)
[ -n "$SH" ] || refuse_tool "no sh (dash) on the machine"

TIMEOUT_BIN=$(command -v timeout 2>/dev/null)
[ -n "$TIMEOUT_BIN" ] || refuse_tool "timeout (coreutils) is missing from the machine : the engine cannot set a maximal delay on the command"

if [ -n "${CARRIER:-}" ]; then
  ( eval "$BODY" ) > "$TMPD/out" 2> "$TMPD/err" < /dev/null
  RC=$?
elif [ "$STDIN_FREE" = yes ]; then
  "$TIMEOUT_BIN" "$TIMEOUT" "$SH" -c "$BODY" > "$TMPD/out" 2> "$TMPD/err"
  RC=$?
else
  "$TIMEOUT_BIN" "$TIMEOUT" "$SH" -c "$BODY" > "$TMPD/out" 2> "$TMPD/err" < /dev/null
  RC=$?
fi

case "$RC" in
  0)
    LINE=$(jq -rn --rawfile r "$TMPD/out" --arg t "$TOOL" --arg a "$ARGS_LINE" '
      ($r | sub("[\n\t ]+$"; "")) as $x
      | (if ($x | length) == 0 then "done, 0 byte on the output"
         elif ($x | test("\n")) then (($x | length | tostring) + " bytes, " + ((($x | split("\n")) | length) | tostring) + " line(s)")
         else $x end) as $res
      | ($t + (if $a == "" then "" else "  " + $a end) + "  ->  "
         + (if ($res | length) > 140 then ($res[0:140] + " ...") else $res end))')
    case "$TOOL" in
      read_return) RID= ;;   # lire la base n y ajoute pas une ligne : ce serait un echo
      *) RID=$(keep_return "$TOOL" "$LINE" "$TMPD/out") ;;
    esac
    CAP_TXT=$(bound_file "$TMPD/out"); CAP_RC=$?
    if [ "$CAP_RC" -eq 0 ]; then
      shape ok "$TOOL" "$LINE" "$CAP_TXT" "$RID"
    fi
    file_shape ok "$TOOL" "$LINE" "$TMPD/out" "$RID"
    ;;
  3)
    R=$(cat "$TMPD/out" 2>/dev/null)
    [ -n "$R" ] || R="approval required by $TOOL, and its command said nothing"
    printf '%s' "$R" > "$TMPD/app"
    CAP_TXT=$(bound_file "$TMPD/app"); CAP_RC=$?
    [ "$CAP_RC" -eq 0 ] && [ -n "$CAP_TXT" ] && R=$CAP_TXT
    shape approval "$TOOL" "$(one_line "$R")" "$R"
    ;;
  124)
    refuse_preformed "refused: the command of $TOOL exceeded the maximal delay (${TIMEOUT} s) and was stopped ; no line hangs the loop"
    ;;
  *)
    E=$(cat "$TMPD/err" 2>/dev/null)
    O=$(cat "$TMPD/out" 2>/dev/null)
    M=$E
    [ -n "$M" ] || M=$O
    [ -n "$M" ] || M="refused: the command of $TOOL failed (code $RC) without saying anything"
    printf '%s' "$M" > "$TMPD/ref"
    CAP_TXT=$(bound_file "$TMPD/ref"); CAP_RC=$?
    [ "$CAP_RC" -eq 0 ] && [ -n "$CAP_TXT" ] && M=$CAP_TXT
    refuse_preformed "$M"
    ;;
esac
