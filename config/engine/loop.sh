#!/usr/bin/dash
# french in code is forbidden
set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

conf_prime

conf_require models port
conf_require models embed
conf_require models rerank
conf_require models local
conf_require loop answer_tokens desc_chars error_chars load_tries max_calls max_seconds max_tokens max_turns msg_budget msg_max plan_every plan_family share speech_tries timeout update_every window
conf_require paths session_start
DB_BUSY=$(conf_num limits db_busy_ms 5000)
RERANK_TIMEOUT=$(conf_num limits rerank_timeout 15)

[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")

CONFD=$(dirname "$HERE")
TABLE=${LA_TABLE:-$CONFD/la_tools.yaml}
CONF=${LA_CONF:-$CONFD/la_config.yaml}
PROCS=${LA_PROCS:-$HERE}
ENGINE=${LA_ENGINE:-$PROCS/engine.sh}
active_skill
HEADF=$(_abs "$(conf_str paths head 'config/head.yaml')")   # LE HEAD GELE : lu sur place, jamais reecrit, donc le prefixe se met en cache
SECOND_HEAD=$(_abs "$(conf_str paths second_script 'config/engine/second.sh')")

DB=${LA_SESSIONS_DB:-$CONFD/sessions.db}
WINDOW=${LA_WINDOW:-$(conf_req_num loop window)}           # LA FENETRE GARDE QUATRE MESSAGES (loi 809) : le HEAD et le
MSG_MAX=${LA_MSG_MAX:-$(conf_req_num loop msg_max)}      # AUCUN message plus gros que ca : tete ET queue gardees
MSG_BUDGET=${LA_MSG_BUDGET:-$(conf_req_num loop msg_budget)}   # LE BUDGET de tout ce que le modele LIT (les tetes systeme a part)

db_init() {   # pose le schema si la base est neuve ; rend 1 si sqlite3 manque
  command -v sqlite3 >/dev/null 2>&1 || return 1
  sqlite3 "$DB" 'PRAGMA journal_mode=WAL; PRAGMA busy_timeout=$DB_BUSY;' >/dev/null 2>&1 || :
  sqlite3 "$DB" 'CREATE TABLE IF NOT EXISTS messages(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      exchange INTEGER NOT NULL,
      ts TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT,
      tool_calls TEXT,
      tool_call_id TEXT,
      name TEXT,
      reasoning TEXT);' 2>/dev/null || return 1
  sqlite3 "$DB" 'CREATE INDEX IF NOT EXISTS messages_exchange ON messages(exchange, id);' 2>/dev/null || :
  sqlite3 "$DB" 'ALTER TABLE messages ADD COLUMN reasoning TEXT;' 2>/dev/null || :
  return 0
}

trim_prog() {
  cat <<'JQ'
def clip($n):                       # one clip, one marker: a second pass cuts the text raw
  if (.content|type) != "string" then .
  elif (.content|utf8bytelength) <= $n then .
  elif (.content|test("TRUNCATED:")) then
    (.content[0:(($n/4)|floor)] + " … " + .content[-(($n/4)|floor):]) as $raw
    | .content = $raw
  else (.content|utf8bytelength) as $L
       | .content = ((.content[0:(($n/4)|floor)])
           + "\n[... TRUNCATED: " + ($L|tostring) + " bytes in total; the whole text is in config/sessions.db and in the turn trace ...]\n"
           + (.content[-(($n/4)|floor):]))
  end;
map(clip($cap))
| . as $m
| ($m | length) as $nl
| ($m | map(.content|length) | add // 0) as $tot
| ($m | map(select(.role == "tool") | (.content|length)) | add // 0) as $tl
| ($m | map(select(.role == "tool")) | length) as $nt
| if $tot <= $bud or $nt == 0 then $m
  else ((($bud - ($tot - $tl)) / $nt) | floor | if . < 260 then 260 else . end) as $al
       | ($m | to_entries
              | map(.value = (if (.value.role == "tool" and .key != ($nl - 1))
                              then (.value | clip($al)) else .value end))
              | map(.value))
  end
JQ
}

old_margin() {   # $1 = un fichier d historique -> octets disponibles pour les VIEUX retours
  jq -r --argjson bud "$MSG_BUDGET" '
    (map((.content // "") | if type == "string" then utf8bytelength else 0 end) | add // 0) as $tot
    | ([ .[] | select(.role == "tool")
         | ((.content // "") | if type == "string" then utf8bytelength else 0 end) ]
       | (.[0:(length - 1)] | add // 0)) as $old
    | ($bud - ($tot - $old)) | if . < 0 then 0 else . end' "$1" 2>/dev/null || printf '0'
}

trim_forms() {   # $1 = un fichier d historique -> le meme, formes choisies par le resident
  _m=$(old_margin "$1")
  case "${_m:-}" in ''|*[!0-9]*) cat "$1" ; return 0 ;; esac
  "$PROCS/trim_forms.sh" "$1" "${REQUEST:-}" "$_m" || cat "$1"
}

db_add() {    # $1 role, $2 content, $3 tool_calls, $4 tool_call_id, $5 name, $6 reasoning
  [ -f "$DB" ] || return 0
  _r=$(printf '%s' "$1" | sed "s/'/''/g"); _c=$(printf '%s' "$2" | sed "s/'/''/g")
  _t=$(printf '%s' "$3" | sed "s/'/''/g"); _i=$(printf '%s' "$4" | sed "s/'/''/g")
  _n=$(printf '%s' "$5" | sed "s/'/''/g"); _z=$(printf '%s' "${6:-}" | sed "s/'/''/g")
  if [ -n "$_t" ]; then _tr="'$_t'"; else _tr=NULL; fi
  if [ -n "$_i" ]; then _ir="'$_i'"; else _ir=NULL; fi
  if [ -n "$_n" ]; then _nr="'$_n'"; else _nr=NULL; fi
  if [ -n "$_z" ]; then _zr="'$_z'"; else _zr="''"; fi
  sqlite3 -cmd ".timeout 5000" "$DB" "INSERT INTO messages(exchange, ts, role, content, tool_calls, tool_call_id, name, reasoning) VALUES($EXCHANGE, '$(ts)', '$_r', '$_c', $_tr, $_ir, $_nr, $_zr);" 2>/dev/null || :
}

db_insert() {  # verse dans la base les messages NOUVEAUX de l historique du tour
  [ -f "$DB" ] || return 0
  _n=$(jq 'length' "$T/hist.json" 2>/dev/null || printf '0')
  case "${_n:-}" in ''|*[!0-9]*) return 0 ;; esac
  [ "$_n" -gt "$SENT" ] || return 0
  jq -c --argjson n "$SENT" '.[$n:][]' "$T/hist.json" 2>/dev/null | while IFS= read -r _m; do
    [ -n "$_m" ] || continue
    _r=$(printf '%s' "$_m" | jq -r '.reasoning // .reasoning_content // ""')
    if [ -z "$_r" ] && [ "$(printf '%s' "$_m" | jq -r '.role // ""')" = "assistant" ] && [ -s "$T/reason" ]; then
      _r=$(cat "$T/reason") ; : > "$T/reason"
    fi
    db_add "$(printf '%s' "$_m" | jq -r '.role // ""')" \
           "$(printf '%s' "$_m" | jq -r '.content // ""')" \
           "$(printf '%s' "$_m" | jq -c '.tool_calls // empty')" \
           "$(printf '%s' "$_m" | jq -r '.tool_call_id // ""')" \
           "$(printf '%s' "$_m" | jq -r '.name // ""')" \
           "$_r"
  done
  SENT=$_n
}

hist_window() {  # LA ZONE 3 : les WINDOW derniers MESSAGES, BRUTS, identifiants compris (loi 809)
  [ "$EXCHANGE" -gt 1 ] 2>/dev/null || { printf '[]'; return 0 ; }
  _s=0
  _sf=$(conf_req_str paths session_start)
  case "$_sf" in /*) ;; *) _sf="$ROOT/$_sf" ;; esac
  if [ -r "$_sf" ]; then
    _s=$(head -n 1 "$_sf" 2>/dev/null | tr -d ' \r')
    case "${_s:-}" in ''|*[!0-9]*) _s=0 ;; esac
  fi
  _b=$(sqlite3 "$DB" "SELECT MIN(id) FROM (SELECT id FROM messages WHERE id > $_s ORDER BY id DESC LIMIT $WINDOW);" 2>/dev/null || printf '')
  case "${_b:-}" in ''|*[!0-9]*) printf '[]'; return 0 ;; esac
  while [ "$_b" -gt $((_s + 1)) ]; do
    _r=$(sqlite3 "$DB" "SELECT role FROM messages WHERE id = $_b;" 2>/dev/null || printf '')
    [ "$_r" = tool ] || break
    _b=$((_b - 1))
  done
  [ "$_b" -ge 1 ] || _b=1
  [ "$_b" -gt "$_s" ] || { printf '[]'; return 0 ; }
  sqlite3 -json "$DB" "SELECT role, content, tool_calls, tool_call_id, name, coalesce(reasoning,'') AS reasoning FROM messages WHERE id >= $_b ORDER BY id;" 2>/dev/null \
   | jq -c --argjson echo "${ECHO_REASON:-0}" --arg k "${REASON_FIELD:-reasoning}" '[.[] | {role, content}
             + (if (.tool_calls // "") == "" then {} else {tool_calls: (.tool_calls | fromjson)} end)
             + (if (.tool_call_id // "") == "" then {} else {tool_call_id: .tool_call_id} end)
             + (if (.name // "") == "" then {} else {name: .name} end)
             + (if $echo == 1 then {($k): (.reasoning // "")} else {} end)]' 2>/dev/null || printf '[]'
}

TURNS_MAX=${LA_MAX_TURNS:-$(conf_req_num loop max_turns)}  # une BORNE de securite, jamais un frein : le PLAN, answer
TOKENS_MAX=${LA_MAX_TOKENS:-$(conf_req_num loop max_tokens)}  # la BORNE de JETONS d une task (0 = aucune). Elle se DIT d abord
CALLS_MAX=${LA_MAX_CALLS:-$(conf_req_num loop max_calls)}    # la BORNE du nombre TOTAL d APPELS d outil d une task (0 = aucune).
SECONDS_MAX=${LA_MAX_SECONDS:-$(conf_req_num loop max_seconds)}  # la BORNE de TEMPS MURAL de la task, en SECONDES (0 = aucune).
TRACE=${LA_TRACE:-0}
TIMEOUT=${LA_TIMEOUT:-$(conf_req_num loop timeout)}          # le delai de l APPEL AU MODELE. Un long run doit pouvoir
ENV1=${LA_ENV:-$CONF_DIR/.env}
LA_DEPTH=${LA_DEPTH:-0}
LA_VOICE=${LA_VOICE:-0}
LA_FROM=${LA_FROM:-$(conf_str agents main agent_one)}
case "$LA_FROM" in
  ''|*[!a-z0-9_-]*)
    printf 'loop: agent name off-form (%s) : this turn is called %s\n' \
      "$LA_FROM" "$(conf_str agents main agent_one)" >&2
    LA_FROM=$(conf_str agents main agent_one) ;;
esac
case "$LA_FROM" in
  ''|*[!a-z0-9_-]*)
    printf 'loop: the declared main agent is off-form (%s) : this turn is called agent_one\n' "$LA_FROM" >&2
    LA_FROM=agent_one ;;
esac
declare_agents() {  # la liste fermee, lue UNE fois, dans la config
  sed -n '/^agents:/,/^[^[:space:]]/p' "$CONF" 2>/dev/null \
    | sed -n 's/^[[:space:]]*names:[[:space:]]*//p' | head -n 1 \
    | sed -e 's/[[:space:]]*#.*$//' -e 's/^"//' -e 's/"$//'
}
MAIN_NAME=$(conf_str agents main agent_one)
AGENT_NAMES=$(declare_agents)
if [ -n "$AGENT_NAMES" ]; then
  case " $AGENT_NAMES " in
    *" $LA_FROM "*) ;;
    *)
      printf 'loop: agent name NOT DECLARED (%s) : this turn is called %s\n' "$LA_FROM" "$MAIN_NAME" >&2
      LA_FROM=$MAIN_NAME ;;
  esac
fi
state_paths
export LA_DEPTH LA_FROM LA_ROOT="$ROOT" LA_CONFIG="$TABLE"

die() {
  printf 'loop: %s\n' "$1" >&2
  printf '%s\n' "$(msg turn_stopped_no_reply "$(printf '%s' "$1" | cut -c1-"$(conf_req_num loop error_chars)")")"
  exit 2
}

TRACE_FILE=${LA_TRACE_FILE:-$(conf_str paths trace config/state/trace.jsonl)}
case "$TRACE_FILE" in /*) ;; *) TRACE_FILE="$ROOT/$TRACE_FILE" ;; esac

trace() {  # $1 = kind ; $2 = the line, already JSON ; the ONE live channel (dash /api/live, the panel)
  [ -n "$TRACE_FILE" ] || return 0
  printf '%s\n' "$2" >> "$TRACE_FILE" 2>/dev/null || :
}

log_to_stderr() {  # $1 = une ligne deja plate
  printf '%s\n' "$1" >&2
}

say_once() {  # $1 = la phrase a dire a l humain ; la meme phrase dans la fenetre ne se repete pas
  _so="$1"
  [ -n "$(printf '%s' "$_so" | tr -d '[:space:]')" ] || return 0
  _lastf="$STATE/last_spoken"
  _win=$(conf_num loop same_words_seconds 300)
  _last=""
  _lt=0
  if [ -f "$_lastf" ]; then
    _lt=$(sed -n '1p' "$_lastf" 2>/dev/null || printf '0')
    _last=$(sed -n '2p' "$_lastf" 2>/dev/null || true)
  fi
  case "$_lt" in ''|*[!0-9]*) _lt=0 ;; esac
  _now=$(date +%s)
  if [ "$_so" = "$_last" ] && [ $(( _now - _lt )) -le "$_win" ]; then
    log_to_stderr "$(ts)  turn $TURN  talk: the same sentence was already said, it is not repeated"
    return 1
  fi
  printf '%s\n' "$_so" >&2
  printf '%s\n%s\n' "$_now" "$_so" > "$_lastf" 2>/dev/null || true
  return 0
}

hist_apply() {
  jq -c "$@" "$T/hist.json" > "$T/hist.next" || return 1
  _src="$T/hist.next"
  _o=$(wc -c < "$T/hist.next" 2>/dev/null || printf '0')
  case "${_o:-}" in ''|*[!0-9]*) _o=0 ;; esac
  if [ "$_o" -gt "$MSG_BUDGET" ]; then
    trim_forms "$T/hist.next" > "$T/hist.forms" && _src="$T/hist.forms"
  fi
  jq -c --argjson cap "$MSG_MAX" --argjson bud "$MSG_BUDGET" "$(trim_prog)" "$_src" > "$T/hist.trim" \
    && mv "$T/hist.trim" "$T/hist.json"
}

result_of() { printf '%s' "$1" | jq -r --arg d "${2:-}" '.result // $d' 2>/dev/null || printf '%s' "${2:-}"; }

close_remaining() {  # lit $I (deja avance), $NTC et $TCS du tour
  _k=$I
  while [ "$_k" -lt "$NTC" ]; do
    _id=$(printf '%s' "$TCS" | jq -r ".[$_k].id" 2>/dev/null || true)
    [ -n "$_id" ] && hist_apply --arg id "$_id" --arg c "tour clos : cet appel n a pas ete execute" \
      '. + [{role:"tool",tool_call_id:$id,content:$c}]'
    _k=$((_k + 1))
  done
}

take_say() {  # rend le texte de l humain, une ligne par message ; rien s il n a rien dit
  _q="$STATE/say.queue"
  [ -f "$_q" ] || return 0
  _t="$STATE/.say.$$.$TURN"
  mv "$_q" "$_t" 2>/dev/null || return 0
  jq -r '.text // empty' "$_t" 2>/dev/null || :
  rm -f "$_t" 2>/dev/null
}

[ -n "${ROOT:-}" ] || die "LA_ROOT is not set : the loop does not know where the project is."
[ -d "$ROOT" ]     || die "the project is not there : $ROOT"
[ -f "$TABLE" ]      || die "the table is missing : $TABLE"
[ -f "$CONF" ]       || die "the engine config is missing : $CONF"
[ -f "$ENGINE" ]     || die "the engine is missing : $ENGINE"
command -v jq   >/dev/null 2>&1 || die "jq is missing"
command -v curl >/dev/null 2>&1 || die "curl is missing"
SH=$(shell_path)
[ -n "$SH" ] || die "no sh (dash) on the machine"

load_env() {  # $1 = un fichier KEY=VALUE
  [ -f "$1" ] || return 0
  while IFS= read -r L || [ -n "$L" ]; do
    case "$L" in ''|\#*) continue ;; esac
    case "$L" in *=*) ;; *) continue ;; esac
    K=${L%%=*}
    V=${L#*=}
    case "$K" in ''|*[!A-Za-z0-9_]*) continue ;; esac
    case "$K" in [0-9]*) continue ;; esac
    case "$V" in
      \"*\") V=$(printf '%s' "$V" | sed -e 's/^"//' -e 's/"$//') ;;
      \'*\') V=$(printf '%s' "$V" | sed -e "s/^'//" -e "s/'$//") ;;
    esac
    ALREADY=$(printenv "$K" 2>/dev/null || true)
    [ -n "$ALREADY" ] && continue
    export "$K=$V" 2>/dev/null || :
  done < "$1"
}
load_env "$ENV1"

active_block() {
  DEBS=$(grep -n '^  - provider:' "$CONF" | cut -d: -f1)
  [ -n "$DEBS" ] || return 1
  TOTAL=$(wc -l < "$CONF")
  N=$(printf '%s\n' "$DEBS" | grep -c .)
  i=0
  while [ "$i" -lt "$N" ]; do
    i=$((i + 1))
    D=$(printf '%s\n' "$DEBS" | sed -n "${i}p")
    F=$(printf '%s\n' "$DEBS" | sed -n "$((i + 1))p")
    F=${F:-$((TOTAL + 1))}
    B=$(sed -n "${D},$((F - 1))p" "$CONF")
    case "$B" in
      *'active: "true"'*|*'active: true'*)
        if [ -n "${LA_ALIAS:-}" ]; then
          case "$B" in *"alias: $LA_ALIAS"*) printf '%s' "$B"; return 0 ;; esac
        else
          printf '%s' "$B"; return 0
        fi
        ;;
    esac
  done
  return 1
}
FIELD() { printf '%s\n' "$1" | sed -n "s/^[[:space:]]*-\{0,1\}[[:space:]]*$2:[[:space:]]*//p" | head -n 1 | sed -e 's/^"//' -e 's/"$//' ; }

MB=$(active_block) || die "no engine is active in $CONF"
POST=$(FIELD "$MB" post)
MODEL=$(FIELD "$MB" model)
HEADER=$(FIELD "$MB" header)
VARIABLE=$(FIELD "$MB" variable)
MAX_TOKENS=$(FIELD "$MB" max_tokens)
TOOL_CHOICE=$(FIELD "$MB" tool_choice)
PROVIDER=$(FIELD "$MB" provider)
THINKING=$(FIELD "$MB" thinking)
EFFORT=$(FIELD "$MB" reasoning_effort)
ECHO_REASON=$(FIELD "$MB" reasoning_echo)
REASON_FIELD=$(FIELD "$MB" reasoning_field)
STREAM=$(FIELD "$MB" stream)
case "${THINKING:-}" in enabled|disabled) ;; *) THINKING='' ;; esac
case "${EFFORT:-}" in none|low|medium|high|max) ;; *) EFFORT='' ;; esac
case "${ECHO_REASON:-}" in true|1) ECHO_REASON=1 ;; *) ECHO_REASON=0 ;; esac
case "${REASON_FIELD:-}" in ''|*[!a-z_]*) REASON_FIELD='' ;; esac
case "${STREAM:-}" in true|1) STREAM=1 ;; *) STREAM=0 ;; esac
if [ "$STREAM" = 1 ]; then STREAM_JSON=true ; else STREAM_JSON=false ; fi
[ -n "$POST" ] || die "the active engine carries no address (post)"
[ -n "$MODEL" ] || die "the active engine carries no model (model)"
case "${TOOL_CHOICE:-}" in required|auto|none) ;; *) TOOL_CHOICE=auto ;; esac
case "${MAX_TOKENS:-}" in ''|*[!0-9]*) MAX_TOKENS=$(conf_req_num loop answer_tokens) ;; esac

KEY=""
AUTH=""
if [ -n "$VARIABLE" ]; then
  KEY=$(printenv "$VARIABLE" 2>/dev/null || true)
  if [ -n "$KEY" ]; then STATE_KEY="set"; else STATE_KEY="ABSENT"; fi
  printf 'loop: variable %s is %s (value never printed) ; engine %s / %s\n' \
    "$VARIABLE" "$STATE_KEY" "$PROVIDER" "$MODEL" >&2
  [ -n "$KEY" ] || die "variable $VARIABLE is empty : the engine cannot answer"
  case "$HEADER" in
    ""|Authorization) AUTH="Authorization: Bearer $KEY" ;;
    *) AUTH="$HEADER: $KEY" ;;
  esac
fi


head_schema() {  # $1 = le head ; rend la ligne de la section TOOLS_SCHEMA
  sed -n '/^TOOLS_SCHEMA:[[:space:]]*$/,/^[^[:space:]]/p' "$1" \
    | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' | head -n 1
}
TOOLS=$(head_schema "$HEADF")
[ -n "$TOOLS" ] || die "the head carries no TOOLS_SCHEMA section : $HEADF"
printf '%s' "$TOOLS" | jq -e 'type == "array" and length == 1 and .[0].type == "function" and .[0].function.name == "la"' >/dev/null 2>&1 \
  || die "the head schema is not an OpenAI tool : a one-element list, type:function, function.name:la"
printf 'loop: the single schema is read (%s, %s byte(s))\n' "$HEADF" "$(printf '%s' "$TOOLS" | wc -c)" >&2

read_prompt() {  # $1 = la cle ; rend le bloc, ou rien
  _pf=$(_abs "$(conf_str paths turn 'config/turn.yaml')")
  [ -f "$_pf" ] || return 0
  awk -v k="$1" '
    /^[a-z_]+: *\|/ { on = ($1 == k ":") ; next }
    /^[a-z_]+:/ { on = 0 ; next }
    on { print }
  ' "$_pf" 2>/dev/null
}

_PROMPT_TURN=$(read_prompt turn)
PROTOCOL=${_PROMPT_TURN:-'THE RULE OF THE TURN: you NEVER answer with text. You CHOOSE a tool of the table, and the engine of that tool runs it. You have only ONE tool, la: g names the NUMBER of the tool, a carries its arguments IN THE ORDER DECLARED by its line. The SURPLUS of a - the free text - goes on the STANDARD INPUT of the tool: it is not a named argument.
THE TOOL THAT REPLIES: its FIRST argument is the FORM (text, list, table, code) and ALL THE REST of a IS your answer, word for word. Example: a = ["list", "here is the inventory ..."]. A tool without text says NOTHING to the human: your text IS your answer.
What you do ALWAYS goes through a tool: a text without a tool is not an answer.'}

block_of_id() {  # $1 = l id ; rend le bloc, ou echoue -- UNE passe awk, pas neuf processus
  awk -v id="$1" '
    /^  - id: / {
      if (on) exit
      t = $0 ; sub(/^  - id:[ \t]*/, "", t) ; sub(/[^0-9].*$/, "", t)
      if (t + 0 == id + 0) on = 1
    }
    on { print }
    END { if (!on) exit 1 }
  ' "$TABLE"
}

args_block_of_tool() {  # $1 = le nom du tool
  TF=$(tool_file_of "$1" 2>/dev/null) || return 0
  awk '/^ARGS:/{f=1;next} f&&/^[^ ]/{exit} f{sub(/^  /,"      ");print}' "$TF"
}

stdin_tail_of_tool() {  # $1 = le nom du tool : "1" si le texte libre est le DERNIER argument declare
  TF=$(tool_file_of "$1" 2>/dev/null) || return 1
  [ -n "$TF" ] || return 1
  awk '
    /^ARGS:/ { f = 1 ; next }
    f && /^[^ ]/ { exit }
    f && /- \{/ { n++ ; spec[n] = $0 ; last2 = spec[n-1] }
    END {
      if (n < 2) exit 1
      if (spec[n] !~ /stdin:[[:space:]]*true/) exit 1
      if (spec[n-1] ~ /required:[[:space:]]*false/) print "1"
    }' "$TF"
}

count_non_stdin_of_tool() {  # $1 = le nom du tool
  A=$(args_block_of_tool "$1")
  NA=$(printf '%s\n' "$A" | grep -c '^[[:space:]]*- {')
  NS=$(printf '%s\n' "$A" | sed -n 's/^[[:space:]]*- {\(.*\)}[[:space:]]*$/\1/p' | grep -c 'stdin:[[:space:]]*true')
  printf '%s' "$((NA - NS))"
}

args_text() {  # $1 = le bloc ARGS (args_block_of_tool) ; rend les noms, leur FORME, et ce que la ligne FERME
  printf '%s\n' "$1" | sed -n 's/^      - {\(.*\)}[[:space:]]*$/\1/p' | while IFS= read -r SPEC; do
    NM=$(printf '%s' "$SPEC" | sed -n 's/.*name:[[:space:]]*\([A-Za-z0-9_]*\).*/\1/p')
    [ -n "$NM" ] || continue
    TY=$(printf '%s' "$SPEC" | sed -n 's/.*type:[[:space:]]*\([a-z]*\).*/\1/p')
    FO="$TY"
    case "$SPEC" in
      *'values:'*)
        LIST=$(printf '%s' "$SPEC" | sed -n 's/.*values:[[:space:]]*\[\([^]]*\)\].*/\1/p' \
          | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' \
          | jq -R . | jq -cs . | jq -r 'join(" | ")')
        [ -n "$LIST" ] && FO="$TY : $LIST"
        ;;
    esac
    case "$SPEC" in
      *'stdin: true'*) FO="$FO,stdin" ;;
    esac
    printf '%s(%s) ' "$NM" "$FO"
  done
}

tool_args_text() {  # $1 = le nom du tool
  TF=$(tool_file_of "$1" 2>/dev/null) || return 0
  A=$(awk '/^ARGS:/{f=1;next} f&&/^[^ ]/{exit} f{sub(/^  /,"      ");print}' "$TF")
  args_text "$(printf '    args:\n%s\n    fin\n' "$A")"
}

# aucune skill active n est pas une panne : le tour se fait avec les PERMANENTS (reply, skill_list,
# load_skill, todo...). Un tour qui meurt ici ne repond jamais a l humain.
[ -f "$SKILL" ] || log_to_stderr "$(ts)  turn: no skill active ($SKILL) ; the scope is the PERMANENTS"

DOC_READ=0
PLAN_DONE=0
TOOLSET_ARMED=0
PLAN_DUE=0                                    # le PLAN EST IMPOSE : il se leve tous les PLAN_EVERY tours,
PLAN_FAMILY=$(conf_req_str loop plan_family)
BIG_DUE=0                                     # LE GRAND PLAN EST IMPOSE AU CHARGEMENT D UN PROJET :
BIG_ACT=''                                  # lequel des deux est impose pour ce chargement-la
UPDATE_DUE=0                                     # LA MAJ PERIODIQUE (loi 1612) : tous les UPDATE_EVERY tours,
UPDATE_EVERY=${LA_UPDATE_EVERY:-$(conf_req_num loop update_every)}                 # l intervalle de la maj periodique (declarable)
PLAN_EVERY=${LA_PLAN_EVERY:-$(conf_req_num loop plan_every)}              # l intervalle de l imposition du plan (declarable) : la
SHARE_NAMES=''

SK_TOOLS_EMPTY=1
SKILLSET_TOOLS=''
SK_TOOLS=''
read_skill_tools() {
  SK_TOOLS_EMPTY=1; SK_TOOLS=''
  [ -f "$SKILL" ] || return 0

  LINE_TOOLS=$(sed -n 's/^TOOLS:[[:space:]]*//p' "$SKILL" | head -n 1)
  if [ -n "$LINE_TOOLS" ]; then
    case "$LINE_TOOLS" in
      \[*\])
        SK_TOOLS=$(printf '%s' "$LINE_TOOLS" | sed -e 's/^\[//' -e 's/\]$//' | tr ',' '\n' \
          | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' | grep -v '^$')
        ;;
    esac
  fi
  if [ -z "$SK_TOOLS" ]; then
    SK_TOOLS=$(sed -n '/^TOOLS:/,/^[^[:space:]]/p' "$SKILL" \
      | sed -n 's/^[[:space:]]*-[[:space:]]*//p; s/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
      | sed -e 's/^"//' -e 's/"$//' | grep -v '^$')
  fi
  [ -n "$SK_TOOLS" ] && SK_TOOLS_EMPTY=0
}

SK_DIRS=''
read_skill_dirs() {
  SK_DIRS=''
  [ -f "$SKILL" ] || return 0
  SK_DIRS=$(sed -n '/^PERIMETER:/,/^[^[:space:]]/p' "$SKILL" 2>/dev/null \
    | sed -n 's/^[[:space:]]*tools:[[:space:]]*//p' | head -n 1 \
    | sed -e 's/[[:space:]]*#.*$//' -e 's/^\[//' -e 's/\]$//' -e 's/,/ /g' -e 's/"//g' -e "s/'//g" \
          -e 's/[[:space:]]*$//')
}
read_guardrails() {  # les tools `guardrail: true` de la table, separes par un espace
  table_index
  _rg_o=
  while IFS='|' read -r _rg_id _rg_tn _rg_fa _rg_gu _rg_de; do
    [ -n "$_rg_id" ] || continue
    [ "$_rg_gu" = true ] && _rg_o="$_rg_o $_rg_tn"
  done <<EOF
$TABLE_INDEX
EOF
  printf '%s' "${_rg_o# }"
}
GUARDRAILS=$(read_guardrails)
[ -n "$GUARDRAILS" ] || die "the table declares no guardrail (guardrail: true) : the harness cannot arm a lock"

PERMANENTS=$(read_permanent)
if [ -z "$PERMANENTS" ]; then
  printf 'loop: the PERMANENT section is EMPTY or MISSING (%s) : only the guardrails are kept (reply, kill).\n' "$CONF" >&2
  PERMANENTS="$GUARDRAILS"
fi

permanent_actions() {  # $1 = nom
  printf '%s\n' "$PERMANENTS" | sed -n "s/^$1://p" | tr '\n' ' '
}
read_lock() {
  [ -f "$SKILL" ] || return 0
  sed -n '/^preconditions:/,/^[^[:space:]]/p' "$SKILL" 2>/dev/null \
    | sed -n 's/^[[:space:]]*requires_tool:[[:space:]]*//p' | head -n 1 \
    | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//'
}
LOCK=$(read_lock)

read_approval() {
  [ -f "$SKILL" ] || { printf 'false' ; return 0 ; }
  V=$(sed -n 's/^APPROVAL:[[:space:]]*//p' "$SKILL" 2>/dev/null | head -n 1 \
        | sed -e 's/#.*//' | tr -d "[:space:]\"'")
  [ "$V" = true ] && printf 'true' || printf 'false'
}

read_perm_todo() {
  [ -f "$SKILL" ] || { printf 'false' ; return 0 ; }
  V=$(sed -n 's/^PERMANENT_TODO:[[:space:]]*//p' "$SKILL" 2>/dev/null | head -n 1 \
        | sed -e 's/#.*//' | tr -d "[:space:]\"'")
  [ "$V" = true ] && printf 'true' || printf 'false'
}

step_record() {  # $1 = tool appele ; $2 = son status
  [ -n "$STEP_TOOLS" ] || return 0
  [ "$2" = ok ] || return 0
  case " $STEP_TOOLS " in *" $1 "*) ;; *) return 0 ;; esac
  F="$T/step.$(printf '%s' "$STEP_LINE" | cksum | cut -d' ' -f1)"
  grep -qxF "$1" "$F" 2>/dev/null || printf '%s\n' "$1" >> "$F"
  for W in $STEP_TOOLS; do
    grep -qxF "$W" "$F" 2>/dev/null || return 0
  done
  rm -f "$F"
  "${PROCS}/plan.sh" progress complete >/dev/null 2>&1 || return 0
  return 0
}

step_text() {
  [ -f "$SKILL" ] || return 0
  sed -n 's/^  [0-9][0-9][0-9]:[[:space:]]*"\[progress\][[:space:]]*//p' "$SKILL" 2>/dev/null \
    | head -n 1 | sed -e 's/"$//'
}

step_tools_of() {
  printf '%s\n' "$1" | sed -n 's/.*--[[:space:]]*tools:[[:space:]]*//p' | tr ',' ' '
}

approval_gate() {  # $1 = tool ; $2 = action ; 0 = le geste peut passer
  is_gated "$1" "$2" || return 0                  # un tool ordinaire ne demande rien
  [ "$APPROVAL" = true ] || return 1             # le skill n a pas ce droit
  F="$STATE/approve"
  [ -f "$F" ] || return 1
  HAVE=$(sed -n '1p' "$F" 2>/dev/null | tr -d '\r' | sed -e 's/[[:space:]]*$//')
  WANT=$(printf '%s %s' "$1" "$2" | sed -e 's/[[:space:]]*$//')
  [ "$HAVE" = "$WANT" ] || return 1               # un autre geste : pas le mien
  NOW=$(date +%s)
  MT=$(stat -c %Y "$F" 2>/dev/null || printf '0')
  WIN=$(conf_num approval window 300)
  [ "$(( NOW - MT ))" -le "$WIN" ] || return 1    # perime
  rm -f "$F"                                      # consomme : un feu vert = un geste
  return 0
}
approval_ask() {  # $1 = tool ; $2 = action : la demande, pour l humain
  OLD=$(sed -n '1p' "$STATE/approve.request" 2>/dev/null | awk '{print $1" "$2}')
  if [ -n "$2" ]; then printf '%s %s %s\n' "$1" "$2" "$(date +%s)" > "$STATE/approve.request" 2>/dev/null || true
  else printf '%s %s\n' "$1" "$(date +%s)" > "$STATE/approve.request" 2>/dev/null || true ; fi
  if [ "$OLD" != "$1 $2" ] || [ $(( $(date +%s) - ${BIP_AT:-0} )) -ge 30 ]; then
    BIP_AT=$(date +%s)
    bip notify     # un geste ATTEND : il s entend, il ne se cherche pas dans un panneau
  fi
}

in_plan_family() { case " $PLAN_FAMILY " in *" $1 "*) return 0 ;; esac; return 1; }

wake_resident() {  # le resident du rerank s endort quand il ne sert pas : on le reveille une fois
  log_to_stderr "$(ts)  loop: the reranker is silent on ${_rhost}:${_rport}, the resident is woken"
  systemctl --user start la-models >/dev/null 2>&1 || true
  _w=0
  while [ "$_w" -lt 10 ]; do
    curl -s -m 3 -o /dev/null -X POST "http://${_rhost}:${_rport}/v1/rerank" \
      -H 'Content-Type: application/json' \
      -d '{"model":"'"${LA_RERANK_MODEL:-bge-reranker-v2-m3-Q4_K_M}"'","query":"wake","documents":["wake"],"top_n":1}' && return 0
    sleep 2
    _w=$((_w + 2))
  done
  return 1
}

rank_share() {   # $1 = candidats (id|nom|description) ; $2 = la demande ; $3 = la PART ; pose SHARE_NAMES
  _cand=$1; _q=$2; _part_in=${3:-30}
  if [ ! -s "$_cand" ]; then   # rien a classer : le reranker repond 400 sur une liste vide, et le tour mourait pour ca
    log_to_stderr "$(ts)  loop: no candidate to rank, the reranker is not called"
    SHARE_NAMES=''
    return 0
  fi
  case "$_part_in" in ''|*[!0-9]*) _part_in=30 ;; esac
  SKILLSET_TOOLS=''
  if [ -n "${LA_SKILLSET:-}" ]; then
    for _ss in $(printf '%s' "$LA_SKILLSET" | tr ',' ' ') ; do
      case "$_ss" in ''|*[!a-z0-9_-]*) continue ;; esac
      _sf="$SKILLS_DIR/$_ss/skill.yaml"
      [ -f "$_sf" ] || continue
      SKILLSET_TOOLS="$SKILLSET_TOOLS $(sed -n '/^TOOLS:/,/^[A-Z_]/p' "$_sf" 2>/dev/null \
        | sed -n 's/^  [0-9][0-9]*:[[:space:]]*"\([a-z_][a-z_0-9]*\)".*/\1/p' | tr '\n' ' ')"
    done
  fi
  SHARE_NAMES=''
  [ -s "$_cand" ] || return 0
  [ -n "$_q" ] || _q=' '
  _port=${LA_RERANK_PORT:-$(conf_num models port 8091)}
  _k=$(wc -l < "$_cand" | tr -d ' ')
  _part=$(( (_k * _part_in + 99) / 100 )); [ "$_part" -ge 1 ] || _part=1
  [ "$_part" -le "$_k" ] || _part=$_k
  _rmdl=${LA_RERANK_MODEL:-bge-reranker-v2-m3-Q4_K_M}   # literal : le banc extrait cette fonction seule
  _req=$(jq -cn --arg q "$_q" --rawfile docs "$_cand" --argjson n "$_k" --arg m "$_rmdl" \
    '{model:$m, query:$q, documents:($docs|split("\n")|map(select(length>0))), top_n:$n}')
  _rt=${RERANK_TIMEOUT:-15}
  _rep=$(printf '%s' "$_req" | curl -sS --max-time "$_rt" -X POST \
    "http://127.0.0.1:$_port/v1/rerank" -H 'Content-Type: application/json' -d @- 2>/dev/null) || _rep=''
  if [ -z "$_rep" ]; then
    log_to_stderr "$(ts)  loop: rerank gave no answer (candidates=$(wc -l < "$_cand"), request=${#_req} bytes, timeout=${_rt}s)"
    return 1
  fi
  _names=$(jq -R 'split("|")[1]' "$_cand" | jq -s '.')
  SHARE_NAMES=$(printf '%s' "$_rep" | jq -r --argjson names "$_names" --argjson k "$_part" \
    '(.results // .) | sort_by(-.relevance_score) | .[0:$k] | .[] | $names[.index]' 2>/dev/null)
  [ -n "$SHARE_NAMES" ] || log_to_stderr "$(ts)  loop: rerank answered without names (candidates=$(wc -l < "$_cand"), answer=${#_rep} bytes): $(printf '%s' "$_rep" | head -c 160)"
  [ -n "$SHARE_NAMES" ]
}

INTERNAL_TOOLS=" $(awk '
  function flush(){ if (name != "" && hid) print name; name = ""; hid = 0 }
  /^  - id:/ { flush() }
  /^[[:space:]]*tool:[[:space:]]/ { name = $2 }
  /^[[:space:]]*visible:[[:space:]]*false/ { hid = 1 }
  END { flush() }
' "$TABLE" | tr '\n' ' ') "

in_dirs() {  # $1 = l id : sa famille est-elle un dossier declare par la skill active ?
  [ -n "${SK_DIRS:-}" ] || return 1
  printf '%s\n' "${TABLE_INDEX:-}" | awk -F'|' -v id="$1" \
    -v dirs=" $(printf '%s' "$SK_DIRS" | tr 'a-z' 'A-Z') " \
    '$1 == id { exit (index(dirs, " " toupper($3) " ") > 0) ? 0 : 1 }'
}

scope_has() {  # $1 = l id
  [ -f "$T/scope.idx" ] && grep -q "^$1|" "$T/scope.idx" && return 0
  in_dirs "$1"
}

scope_build() {
  _s0=$(date +%s%N)
  active_skill
  SKILL="$SKILLS_DIR/$NAME/skill.yaml"
  [ -f "$SKILL" ] || {
    SKILL=""
    log_to_stderr "$(ts)  turn: no skill active ; the scope is the PERMANENTS only"
  }
  _s1=$(date +%s%N)
  read_skill_tools
  read_skill_dirs
  _s2=$(date +%s%N)
  LOCK=$(read_lock)
  APPROVAL=$(read_approval)
  PERM_TODO=$(read_perm_todo)
  _s3=$(date +%s%N)
[ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_skill_setup "$(( (_s1-_s0)/1000000 ))" "$(( (_s2-_s1)/1000000 ))" "$(( (_s3-_s2)/1000000 ))")" >&2
  _guard_set=" $(printf '%s' "${GUARDRAILS:-}" | tr '\n' ' ') "
  _perm_set=" $(printf '%s' "${PERMANENTS:-}" | tr '\n' ' ') "
  _perm_act_set=" $(printf '%s\n' "${PERMANENTS:-}" | sed -n 's/:.*//p' | tr '\n' ' ') "
  _sk_set=" $(printf '%s' "${SK_TOOLS:-}" | tr '\n' ' ') "
  _plan_set=$(awk '
    /^  - id: / { id = $3 ; next }
    /^    tool: / { t = $2 ; gsub(/"/, "", t) ; next }
    /^    family: / { f = $2 ; gsub(/"/, "", f) ; if (f == "PLAN") printf " %s ", t ; next }
  ' "$TABLE" 2>/dev/null)
  STEP_LINE=''
  STEP_TOOLS=''
  if [ "$PERM_TODO" = true ]; then
    _s4=$(date +%s%N)
    STEP_LINE=$(step_text)
    STEP_TOOLS=$(step_tools_of "$STEP_LINE")
[ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_permanent_todo "$(( ($(date +%s%N)-_s4)/1000000 ))")" >&2
    [ "$STEP_TOOLS" = '' ] && STEP_LINE=''
  fi
  SHARE_NAMES=''
  if [ "$PERM_TODO" = true ]; then
    PLAN_DUE=0
  elif [ "$PLAN_DONE" != 1 ] || ! open_plan; then
    PLAN_DUE=0
  elif [ "$PLAN_DUE" != 1 ] && [ "$(( TURN % PLAN_EVERY ))" -eq 0 ]; then
    PLAN_DUE=1
  fi
  if [ "$UPDATE_DUE" = 0 ] && [ "$TURN" -gt 0 ] && [ "$(( TURN % UPDATE_EVERY ))" -eq 0 ]; then
    ACT_FILE=$(_abs "$(conf_str paths project_active 'projects/.active')")
    if [ -f "$ACT_FILE" ] && [ -n "$(sed -n '1p' "$ACT_FILE" 2>/dev/null | tr -d '\r')" ]; then
      UPDATE_DUE=1        # le chantier d abord (le projet est le cadre du travail)
    else
      UPDATE_DUE=2        # aucun projet : il reste le canon
    fi
  fi
  if [ -z "$LOCK" ] && [ "$DOC_READ" = 1 ] && [ "$PLAN_DONE" = 1 ] && [ "$TOOLSET_ARMED" != 1 ] \
     && [ "$PLAN_DUE" != 1 ]; then
    _cand="$T/share.cand"; : > "$_cand"
    _t0=$(date +%s%N)
    table_index
    [ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_table_index "$(( ($(date +%s%N) - _t0) / 1000000 ))")" >&2
    _ckey=$(printf '%s|%s|%s' "$SK_TOOLS" "$PERMANENTS" "$(stat -c %Y "$TABLE" 2>/dev/null)" | cksum | cut -d' ' -f1)
    _ccache="$STATE/scope.cand"
    if [ -f "$_ccache" ] && [ "$(sed -n 1p "$_ccache")" = "KEY $_ckey" ]; then
      sed -n '2,$p' "$_ccache" > "$_cand"
      [ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_candidates_cache "$(wc -l < "$_cand" | tr -d ' ')")" >&2
    else
    while IFS='|' read -r ID TN FA _ DE; do
      [ -n "$ID" ] || continue
      case "$_sk_set" in *" $TN "*) ;; *) continue ;; esac
      case "$_perm_set" in *" $TN "*) continue ;; esac
      case "$_perm_act_set" in *" $TN "*) continue ;; esac
      case "$TN" in load_doc|toolset) continue ;; esac
      printf '%s|%s|%s\n' "$ID" "$TN" "$DE" >> "$_cand"
    done <<EOF
$TABLE_INDEX
EOF
    { printf 'KEY %s\n' "$_ckey" ; cat "$_cand" ; } > "$_ccache"
    fi
    [ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_candidate_filter "$(( ($(date +%s%N) - _t0) / 1000000 ))" "$(wc -l < "$_cand" | tr -d ' ')")" >&2
    _pick=${LA_PICK:-$(conf_num models pick 60)}
    case "$_pick" in
      ''|*[!0-9]*) die "embed.pick is empty or malformed in la_config: it is the number of
candidates the reranker receives. It is not a turn." ;;
      *) [ "$_pick" -gt 0 ] && dash "$(_abs "$(conf_str paths pick 'config/engine/pick.sh')")" "$_cand" \
           "${REQUEST:-} ${PLAN_TXT:-}" "$_pick" ;;
    esac
    [ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_meaning_preselect "$(( ($(date +%s%N) - _t0) / 1000000 ))")" >&2
    _share=$(conf_req_num loop share)
    _rhost=${LA_RERANK_HOST:-$(conf_str models host 127.0.0.1)}
    _rport=${LA_RERANK_PORT:-$(conf_num models port 8091)}
    rank_share "$_cand" "${REQUEST:-} ${PLAN_TXT:-}" "$_share" \
      || { wake_resident && rank_share "$_cand" "${REQUEST:-} ${PLAN_TXT:-}" "$_share" ; } \
      || die "the reranker is silent on $_rhost:$_rport : the resident must be in RAM \
(la-models start). This is an ENGINE bug, not a turn."
    [ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_share_rerank "$(( ($(date +%s%N) - _t0) / 1000000 ))")" >&2
  fi
  SCOPE_IDS=' '
  _names=' '
  _add() { case "$_names" in *" $1 "*) ;; *) [ -n "$1" ] && _names="$_names$1 " ;; esac ; }
  for _n in $GUARDRAILS ; do _add "$_n" ; done
  _share_set=" $(printf '%s' "${SHARE_NAMES:-}" | tr '\n' ' ') "
  if [ -n "$LOCK" ]; then
    SCOPE_TXT="THE TOOLS REACHABLE THIS TURN - A LOCK IS ARMED (imposed tool: $LOCK): the scope is REDUCED to that single tool, PLUS the guardrails reply, kill. By their NUMBER:
"
    _add "$LOCK"
  elif [ "$UPDATE_DUE" != 0 ]; then
case "$UPDATE_DUE" in 2) _what='the CANON (update_spec)' ; _add update_spec ;;
      *) _what='the BIG PLAN (update_big_todo)' ; _add update_big_todo ;; esac
    SCOPE_TXT="THE TOOLS REACHABLE THIS TURN - THE PERIODIC UPDATE IS IMPOSED (every $UPDATE_EVERY turns, law 1612): $_what is being updated. The scope is REDUCED to that single gesture until it is done. By their NUMBER:
"
  elif [ "$BIG_DUE" = 1 ]; then
    SCOPE_TXT="THE TOOLS REACHABLE THIS TURN - THE BIG PLAN OF THE PROJECT IS IMPOSED: a loaded project carries a WORKSTREAM. The gesture of this turn is ${BIG_ACT:-big_todo} -- big_todo if the workstream is not written yet, update_big_todo if it exists and must be revised. Write it or revise it, and the turn passes. By their NUMBER:
"
    _add "${BIG_ACT:-big_todo}"
  elif [ "$PLAN_DUE" = 1 ]; then
    SCOPE_TXT="THE TOOLS REACHABLE THIS TURN - THE PLAN IS IMPOSED (every $PLAN_EVERY turns): mark YOUR CURRENT POINT with update_todo, and the turn passes. The skill toolset only comes back once the point is marked. By their NUMBER:
"
    _add update_todo
  else
    _add load_doc
    [ "$DOC_READ" = 1 ] && for _n in $_plan_set ; do [ "$_n" = toolset ] || _add "$_n" ; done
    if [ "$PLAN_DONE" = 1 ] && [ "$TOOLSET_ARMED" != 1 ]; then _add toolset ; fi
    for _n in $_perm_set $_perm_act_set ; do
      case " $_plan_set " in *" $_n "*) continue ;; esac
      _add "$_n"
    done
    if [ "$PLAN_DONE" = 1 ]; then
      if [ "$SK_TOOLS_EMPTY" = 1 ]; then
        _names='*'
      elif [ "$TOOLSET_ARMED" = 1 ]; then
        for _n in $_sk_set ; do _add "$_n" ; done
      else
        for _n in $_share_set ; do
          case "$_sk_set" in *" $_n "*) _add "$_n" ;; esac
        done
      fi
    fi
    if [ "$DOC_READ" != 1 ]; then
      SCOPE_TXT="THE TOOLS REACHABLE THIS TURN - THE DOC IS NOT READ YET: the PLAN family is CLOSED. Read the doc (load_doc) to open the plan. The permanents, by their NUMBER:
"
    elif [ "$PLAN_DONE" != 1 ]; then
      SCOPE_TXT="THE TOOLS REACHABLE THIS TURN - THE DOC IS READ, THE PLAN IS NOT DONE: the SKILL tools are CLOSED. Do the plan (todo) to open the toolset (goal: 100 bytes max). By their NUMBER:
"
    elif [ "$TOOLSET_ARMED" = 1 ]; then
      SCOPE_TXT="THE TOOLS REACHABLE THIS TURN - THE TOOLSET IS OPEN IN FULL (toolset was just named): the COMPLETE turn of the active skill, LESS the permanents. toolset is ABSENT from this turn. By their NUMBER:
"
    else
      SCOPE_TXT="THE TOOLS REACHABLE THIS TURN - THE TOOLSET OF THE SKILL (the 30% most likely for this task), PLUS the permanents. If a tool is missing, name toolset: the full list is returned to you. By their NUMBER:
"
    fi
  fi
  _dmax=$(conf_req_num loop desc_chars)      # read ONCE, not for every tool of the scope
  _q0=$(date +%s%N)
  table_index
  [ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_table_index_scope "$(( ($(date +%s%N)-_q0)/1000000 ))")" >&2

  if [ "$_names" = '*' ]; then
    printf '%s\n' "$TABLE_INDEX" > "$T/scope.idx"
  else
    printf '%s\n' "$TABLE_INDEX" | awk -v want="$_names" -v internal=" $INTERNAL_TOOLS " '
      BEGIN { n = split(want, a, " ") ; for (i = 1 ; i <= n ; i++) if (a[i] != "") w[a[i]] = 1 }
      { split($0, f, "|") ; if (w[f[2]] && index(internal, " " f[2] " ") == 0) print }
    ' > "$T/scope.idx"
  fi
  [ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_scope "$(printf '%s' "$_names" | wc -w | tr -d ' ')" "$(wc -l < "$T/scope.idx" | tr -d ' ')")" >&2
  while IFS='|' read -r ID TN FA _ DE; do
    [ -n "$ID" ] || continue
    if B=$(block_of_id "$ID"); then
      ARGS=$(tool_args_text "$TN")
      AP=$(permanent_actions "$TN")
      SCOPE_IDS="$SCOPE_IDS$ID "
      SCOPE_TXT="$SCOPE_TXT  $ID  $TN  [$FA]  $(printf '%s' "$DE" | cut -c1-"$_dmax")${ARGS:+  (args : $ARGS)}${AP:+  (permanent : $AP)}
"
    fi
  done < "$T/scope.idx"
  [ "$SCOPE_IDS" != ' ' ] || die "the scope is empty : no reachable tool"
  SCOPE_TXT="$SCOPE_TXT A number OUTSIDE this list is refused by the harness: it will tell you, and you will have a turn to correct yourself."
  if [ "${LA_SCOPE_TRACE:-0}" = 1 ]; then
    printf 'loop: SCOPE  lock=[%s]  doc_read=%s  plan_done=%s  toolset_armed=%s  plan_due=%s\n' \
      "${LOCK:-none}" "$DOC_READ" "$PLAN_DONE" "$TOOLSET_ARMED" "$PLAN_DUE" >&2
    printf 'loop: SCOPE  ids kept=%s\n' "$SCOPE_IDS" >&2
  fi
  if [ "$TOOLSET_ARMED" = 1 ]; then ARMED_THIS=1 ; TOOLSET_ARMED=0 ; else ARMED_THIS=0 ; fi
}

clean_head() {  # $1 = le fichier ; rend le preambule plat sur la sortie standard
  sed -e '/^TOOLS_SCHEMA:[[:space:]]*$/,/^[^[:space:]]/{/^TOOLS_SCHEMA:[[:space:]]*$/d;/^[^[:space:]]/!d;}' \
      -e 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/' \
      -e 's/^[[:space:]]*\([a-z_][a-z_0-9]*\):[[:space:]]*\(.*\)$/\1: \2/' \
      -e '/^[[:space:]]*# /d' -e '/^[[:space:]]*#$/d' -e '/^[[:space:]]*$/d' "$1"
}

HEAD_TXT=''
if [ -f "$HEADF" ] && [ -r "$HEADF" ]; then
  HEAD_TXT=$(clean_head "$HEADF")
  printf 'loop: the head is read (%s, %s byte(s))\n' "$HEADF" "$(printf '%s' "$HEAD_TXT" | wc -c)" >&2
else
  die "the head is missing : $HEADF (the loop does not run without a head)"
fi
[ -n "$HEAD_TXT" ] || die "the head is empty : $HEADF"

SECOND_OK=0
[ -x "$SECOND_HEAD" ] && SECOND_OK=1
if [ "$SECOND_OK" = 1 ]; then
  printf 'loop: the secondary head is read (%s), rebuilt at every turn\n' "$SECOND_HEAD" >&2
else
  printf 'loop: second.sh is MISSING (%s) : the plan layer is empty. It is read as soon as it exists.\n' "$SECOND_HEAD" >&2
fi
read_second() {
  SECOND_OK=0
  [ -x "$SECOND_HEAD" ] && SECOND_OK=1
  if [ "$SECOND_OK" = 1 ]; then
    S2=$("$SECOND_HEAD" "$REQUEST" 2>/dev/null) || S2=''
    CHAT_SEEN=$(printf '%s' "$S2" | sed -n 's/.*\[chat-seen:\([^]]*\)\].*/\1/p' | tail -n 1)
    case "${CHAT_SEEN:-}" in
      '') : ;;
      *)  S2=$(printf '%s' "$S2" | sed -e 's/\[chat-seen:[^]]*\]//')
          [ -n "${LA_TMP:-}" ] && printf '%s\n' "$CHAT_SEEN" > "$LA_TMP/chat_seen" 2>/dev/null
          : ;;
    esac
    PJ=$(printf '%s' "$S2" | jq -r '.result // .content // .text // empty' 2>/dev/null || true)
    [ -n "$PJ" ] && S2=$PJ
    printf '%s' "$S2"
  else
    printf '%s' "$(msg no_open_plan)"
  fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/loop.XXXXXX" 2>/dev/null)
export LA_TMP="$T"
[ -n "$T" ] && [ -d "$T" ] || die "the temp dir could not be opened (${TMPDIR:-/tmp})"
cleanup_tmp_loop() { rm -f "$T"/* 2>/dev/null; rmdir "$T" 2>/dev/null; rm -f "$TURN_MARK" 2>/dev/null; rm -f "${RUN_FILE:-}" 2>/dev/null; }
trap 'cleanup_tmp_loop' EXIT
trap 'printf "\n%s\n" "$(msg turn_interrupted)" >&2; exit 130' INT TERM HUP

TURN_MARK=${LA_TURN_MARK:-$STATE/turn.pid}
printf '%s\n' "$$" > "$TURN_MARK" 2>/dev/null || :

: > "$T/read_log"; : > "$T/written"; : > "$T/counter"; CAP_LAST=
: > "$TRACE_FILE" 2>/dev/null || :
printf '[]' > "$T/hist.json"; : > "$T/curl.err"

EXCHANGE=1; SENT=0; WINDOW_JSON='[]'
if db_init; then
  EXCHANGE=$(sqlite3 "$DB" 'SELECT COALESCE(MAX(exchange),0)+1 FROM messages;' 2>/dev/null || printf '')
  case "${EXCHANGE:-}" in ''|*[!0-9]*) EXCHANGE=1 ;; esac
  WINDOW_JSON=$(hist_window)
else
log_to_stderr "$(ts)  the session database could not be opened ($DB): the context leaves without the window"
fi

REQUEST=$(cat)
[ -n "$REQUEST" ] || die "no request on the input : a turn starts from a request."
db_add "user" "$REQUEST" "" "" ""     # la demande entre dans le corps, horodatee

RUN_FILE=$(tpn "$(conf_str paths run 'config/%s.run')" "$LA_FROM")
case "$RUN_FILE" in /*) ;; *) RUN_FILE="$ROOT/$RUN_FILE" ;; esac
if ! printf '%s %s %s\n' "$$" "$(ts)" \
      "$(printf '%s' "$REQUEST" | tr '\n\t' '  ' | cut -c1-"$(conf_num agents run_chars 120)")" > "$RUN_FILE" 2>/dev/null; then
  printf 'loop: the agents mark could not be written (%s)\n' "$RUN_FILE" >&2
fi

printf '%s' "$WINDOW_JSON" > "$T/window.raw"
if [ -s "$T/window.raw" ]; then
  WINDOW_JSON=$(trim_forms "$T/window.raw" \
    | jq -c --argjson cap "$MSG_MAX" --argjson bud "$MSG_BUDGET" "$(trim_prog)" 2>/dev/null || printf '[]')
fi

FACTS() { printf 'FACTS  date %s  time %s  locale UTC' "$(date -u +%Y-%m-%d)" "$(date -u +%H:%M)"; }

build_messages() {  # la demande est dans $REQUEST ; les faits dans $FACTS
  jq -cn \
    --arg head "$HEAD_TXT" --arg prot "$PROTOCOL" --arg scope "$SCOPE_TXT" \
    --arg plan "$PLAN_TXT" --arg request "$REQUEST" --arg facts "$FACTS" \
    --arg voice "$VOICE_TXT" \
    --argjson hist "$(cat "$T/hist.json")" --argjson window "$WINDOW_JSON" \
    '[{role:"system",content:$head},{role:"system",content:$prot}]
     + (if $plan == "" then [] else
          ($plan | split("\u001e") | map(select(length > 0)) | map({role:"system",content:.}))
        end)
     + [{role:"system",content:$scope}]
     + $window
     + (if $voice == "" then [] else [{role:"system",content:$voice}] end)
     + [{role:"user",content:$request}]
     + $hist
     + [{role:"system",content:$facts}]'
}

call() {  # $1 = le corps JSON ; rend la reply sur la sortie standard
  if [ "${STREAM:-0}" = 1 ]; then
    rm -f "$T/curl.rc"
    if [ -n "$AUTH" ]; then
      { curl -N -sS --max-time "$TIMEOUT" -X POST "$POST" \
          -H "$AUTH" -H 'Content-Type: application/json' -d "$1" 2>"$T/curl.err" ; \
        printf '%s' "$?" > "$T/curl.rc" ; } \
        | /usr/bin/python3 "$SCRIPTS/sse.py" --turn "${TURN:-0}" --state "$STATE" \
            --reason-field "${REASON_FIELD:-}"
    else
      { curl -N -sS --max-time "$TIMEOUT" -X POST "$POST" \
          -H 'Content-Type: application/json' -d "$1" 2>"$T/curl.err" ; \
        printf '%s' "$?" > "$T/curl.rc" ; } \
        | /usr/bin/python3 "$SCRIPTS/sse.py" --turn "${TURN:-0}" --state "$STATE" \
            --reason-field "${REASON_FIELD:-}"
    fi
    _rc=$(cat "$T/curl.rc" 2>/dev/null || true)
    case "${_rc:-}" in ''|*[!0-9]*) return 0 ;; *) return "$_rc" ;; esac
  fi
  if [ -n "$AUTH" ]; then
    curl -sS --max-time "$TIMEOUT" -X POST "$POST" \
      -H "$AUTH" -H 'Content-Type: application/json' -d "$1" 2>"$T/curl.err"
  else
    curl -sS --max-time "$TIMEOUT" -X POST "$POST" \
      -H 'Content-Type: application/json' -d "$1" 2>"$T/curl.err"
  fi
}

exec_engine() {  # $1 = g ; $2 = le nombre d arguments hors stdin ; $3 = le chemin de a.json
  local G N AF I V
  G=$1; N=$2; AF=$3
  set -- "$SH" "$ENGINE" "$G"
  I=0
  while [ "$I" -lt "$N" ]; do
    V=$(jq -r --argjson i "$I" '.[$i] // ""' "$AF")
    set -- "$@" "$V"
    I=$((I + 1))
  done
  jq -r --argjson n "$N" 'if length > $n then .[$n:] | join("\n") else "" end' "$AF" > "$T/stdin.txt"
  "$@" < "$T/stdin.txt" > "$T/engine.out" 2> "$T/engine.err" &
  local PID C D
  PID=$!
  C=0
  D=0
  while kill -0 "$PID" 2>/dev/null; do
    if [ "$C" -lt 100 ]; then
      sleep 0.02
      C=$((C + 1))
      kill -0 "$PID" 2>/dev/null || break
    else
      sleep 0.25
      D=$((D + 1))
      kill -0 "$PID" 2>/dev/null || break
      if [ $((D % 60)) -eq 0 ]; then
        printf 'loop: %s has been working for %s s\n' "${TN:-the tool}" "$((2 + D / 4))" >&2
      fi
    fi
  done
  wait "$PID"
  return $?
}

refuse_loop() {
  jq -cn --arg t "$(ts)" --arg m "$1" \
    '{status:"refused",tool:"la",line:($t+"  "+$m),result:("refused: "+$m),ts:$t}'
}

big_plan_txt() {  # ce que la brique dit du GRAND plan du projet actif (vide, ou ses points)
  "${PROCS}/plan.sh" big status 2>/dev/null || true
}
big_act() {     # LE GESTE DU CHANTIER : big_todo quand il n est pas ecrit, update_big_todo sinon
  printf '%s' "$(big_plan_txt)" | grep -qi 'no open plan' && { printf 'big_todo' ; return 0 ; }
  printf 'update_big_todo'
}
open_plan() {   # la COUCHE DE L ETAT rend-il un plan ouvert ? (sinon : termine, ou rien)
  printf '%s' "$PLAN_TXT" | grep -qi 'no open plan' && return 1
  printf '%s' "$PLAN_TXT" | grep -qi 'could not be obtained' && return 1
  # une couche qui REFUSE (skill absente, plan illisible) n est pas un plan ouvert : sinon le
  # perimetre se reduit a update_todo, qui refuse a son tour, et le tour boucle sans fin
  printf '%s' "$PLAN_TXT" | grep -qiE '^refused|is missing|forbidden' && return 1
  printf '%s' "$PLAN_TXT" | grep -q . || return 1
  return 0
}

TURN=0
SPOKE=0
NO_TOOL=0
SPEECH_NUDGE=0
ANSWERED=0
REPLY=''
LOADED=0
TOKENS_TOTAL=0
TOKENS_SPOKE=0
CALLS_TOTAL=0
CALLS_SPOKE=0
T0=$(date +%s)
SECONDS_SPOKE=0

while [ "$TURNS_MAX" -eq 0 ] || [ "$TURN" -lt "$TURNS_MAX" ]; do
  TURN=$((TURN + 1))
  _tp=$(date +%s%N)
  FACTS=$(FACTS)
  PLAN_TXT=$(read_second)
[ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_facts_secondary "$TURN" "$(( ($(date +%s%N) - _tp) / 1000000 ))")" >&2
  if [ -s "$T/chat_seen" ]; then
    CHAT_SEEN=$(cat "$T/chat_seen" 2>/dev/null || :)
    if [ -n "${CHAT_SEEN:-}" ]; then LA_CHAT_SEEN=$CHAT_SEEN ; export LA_CHAT_SEEN ; fi
  fi
  if [ -n "${PLAN_TXT:-}" ]; then
    HEAD_F=$(conf_str paths head_file config/second.head)
    case "$HEAD_F" in *%s*) HEAD_F=$(printf "$HEAD_F" "${LA_FROM:-agent_one}") ;; esac
    if [ "${LA_FROM:-}" != "${MAIN_NAME:-agent_one}" ]; then
      case "$HEAD_F" in
        *"$LA_FROM"*) ;;
        *) HEAD_F=$(tpn "$(_abs "$(conf_str paths agent_head 'config/%s.head')")" "$LA_FROM") ;;
      esac
    fi
    case "$HEAD_F" in /*) ;; *) HEAD_F="$ROOT/$HEAD_F" ;; esac
    mkdir -p "$(dirname "$HEAD_F")" 2>/dev/null || true
    if printf '%s' "$PLAN_TXT" > "$HEAD_F.tmp.$$" 2>/dev/null; then
      mv -f "$HEAD_F.tmp.$$" "$HEAD_F" 2>/dev/null || true
    fi
  fi
  _tp=$(date +%s%N)
  scope_build
[ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_scope_build "$TURN" "$(( ($(date +%s%N) - _tp) / 1000000 ))")" >&2
  VOICE_TXT=''
  if [ "$LA_VOICE" = 1 ]; then
    VOICE_TXT='THIS TURN COMES FROM THE VOICE: THE HUMAN EXPECTS TO HEAR YOU RIGHT NOW. Your FIRST action is talk, with ONE short sentence (under 120 characters) saying you heard and you are on it. No other tool before that talk. Then you work, and you name talk every time you have something to say. No free text: everything goes through a tool.'
  fi

  MESSAGES=$(build_messages) || die "the messages could not be built"
  PAYLOAD=$(jq -cn --arg model "$MODEL" --argjson tools "$TOOLS" --argjson max "$MAX_TOKENS" \
    --arg choice "$TOOL_CHOICE" --argjson messages "$MESSAGES" \
    --arg th "${THINKING:-}" --arg ef "${EFFORT:-}" --argjson st "${STREAM_JSON:-false}" \
    '{model:$model, tools:$tools, tool_choice:$choice, max_tokens:$max, stream:$st, messages:$messages}
     + (if $th == "" then {} else {thinking:{type:$th}} end)
     + (if $ef == "" then {} else {reasoning_effort:$ef} end)
     + (if $st then {stream_options:{include_usage:true}} else {} end)') \
    || die "the call could not be built"

  _tp=$(date +%s%N)
  REP=$(call "$PAYLOAD")
  CRC=$?   # PRIS ICI, PAS APRES : la ligne de trace suivante rend 1 quand LA_TRACE est vide, et le
  [ -n "${LA_TRACE:-}" ] && printf '%s\n' "$(msg trace_model_call "$TURN" "$(( ($(date +%s%N) - _tp) / 1000000 ))" "${#PAYLOAD}")" >&2
  if [ "$CRC" -ne 0 ]; then
    CURL_WHY=$(head -n 1 "$T/curl.err" 2>/dev/null | tr '\n\t' '  ' | cut -c1-"$(conf_req_num loop error_chars)")
log_to_stderr "$(ts)  turn $TURN  transport failure (curl $CRC : $CURL_WHY): the same call is sent ONCE more"
    REP=$(call "$PAYLOAD")
    CRC=$?
  fi
  if [ "$CRC" -ne 0 ]; then
    CURL_WHY=$(head -n 1 "$T/curl.err" 2>/dev/null | tr '\n\t' '  ' | cut -c1-"$(conf_req_num loop error_chars)")
    cp "$T/curl.err" "$STATE/curl.err" 2>/dev/null || :
    die "the engine did not answer (curl $CRC : $CURL_WHY) : network, or timeout"
  fi

  ERR=$(printf '%s' "$REP" | jq -r '.error.message // empty' 2>/dev/null || true)
  [ -z "$ERR" ] || die "the engine refused : $ERR"
  END=$(printf '%s' "$REP" | jq -r '.choices[0].finish_reason // ""' 2>/dev/null || true)
  MSG=$(printf '%s' "$REP" | jq -c '.choices[0].message // empty' 2>/dev/null || true)
  if [ "$END" = "load" ]; then
    LOADED=$((LOADED + 1))
    [ "$LOADED" -le "$(conf_req_num loop load_tries)" ] || die "the engine did not finish loading : $MODEL"
    printf 'loop: the engine is loading its model - same question asked again (attempt %s)\n' "$LOADED" >&2
    TURN=$((TURN - 1))
    continue
  fi
  if [ "$END" = "length" ]; then
    die "the engine hit its ceiling ($MAX_TOKENS tokens, engine $MODEL) : the reasoning took the whole budget and no gesture is left. Raise max_tokens for this alias, or ask for less."
  fi
  [ -n "$MSG" ] && [ "$MSG" != 'null' ] || die "the engine reply carries no message"

  USAGE_TOKENS=$(printf '%s' "$REP" | jq -r '.usage.total_tokens // 0' 2>/dev/null || true)
  case "${USAGE_TOKENS:-}" in ''|*[!0-9]*) USAGE_TOKENS=0 ;; esac
  TOKENS_TOTAL=$((TOKENS_TOTAL + USAGE_TOKENS))
  USAGE_FILE=$(conf_str paths usage 'config/usage.jsonl')
  case "$USAGE_FILE" in /*) ;; *) USAGE_FILE="$ROOT/$USAGE_FILE" ;; esac
  printf '{"ts":"%s","session":%s,"turn":%s,"agent":"%s","model":"%s","tokens":%s}\n' \
    "$(ts)" "${EXCHANGE:-0}" "$TURN" "$LA_FROM" "$MODEL" "$USAGE_TOKENS" \
    >> "$USAGE_FILE" 2>/dev/null \
    || printf 'loop: the usage line could not be written (%s)\n' "$USAGE_FILE" >&2

  NTC=$(printf '%s' "$MSG" | jq -r '(.tool_calls // []) | length')
  CONTENT=$(printf '%s' "$MSG" | jq -r '.content // ""')

  if [ "$NTC" != "0" ] && [ "$SPOKE" = 0 ] && [ "${SPEECH_NUDGE:-0}" -lt "$(conf_req_num loop speech_tries)" ]; then
    _TAB=$(printf '\t') ; HAS_SPEECH=0 ; HAS_WORDS=0
    printf '%s' "$MSG" | jq -r '.tool_calls[]?.function.arguments | (fromjson? // {}) |
      [(.g // ""), ((.a // [])[0] // ""),
       ((.a // [])[2] // ""),
       ((.a // [])[3] // "")] | @tsv' 2>/dev/null > "$T/speech.tsv" || : > "$T/speech.tsv"
    while IFS="$_TAB" read -r _id _mode _txt _next; do
      case "$_id" in ''|*[!0-9]*) continue ;; esac
      _name=$(printf '%s\n' "$(block_of_id "$_id" 2>/dev/null || true)" | sed -n 's/^    tool:[[:space:]]*//p' | head -n 1)
      [ "$_name" = reply ] || continue
      [ "$_mode" = talk ] && HAS_SPEECH=1
      [ "$_mode" = talk ] && [ -n "$(printf '%s' "$_txt" | tr -d '[:space:]')" ] && HAS_WORDS=1

      :
    done < "$T/speech.tsv"
    if [ "$HAS_SPEECH" = 0 ]; then
      SPEECH_NUDGE=$((SPEECH_NUDGE + 1))
      log_to_stderr "$(ts)  turn $TURN  NO REPLY: the message names no reply/talk - whole turn refused, re-asked ($SPEECH_NUDGE/2)"
      hist_apply --arg m "$(msg no_reply)" '. + [{role:"system",content:$m}]'
      continue
    fi
    [ "$HAS_WORDS" = 1 ] && { SPEECH_NUDGE=0 ; SPOKE=1 ; }
  fi
  if [ -n "${REASON_FIELD:-}" ]; then
    REASON=$(printf '%s' "$MSG" | jq -r --arg f "$REASON_FIELD" '.[$f] // ""' 2>/dev/null || true)
  else
    REASON=$(printf '%s' "$MSG" | jq -r '.reasoning // .reasoning_content // ""' 2>/dev/null || true)
  fi
  if [ -n "$REASON" ]; then
    printf '%s\n' "$REASON" | sed 's/^/thinking: /' >&2
    # the reasoning goes to the BASE, with the message it produced : one single place ;
    # the live channel only carries it for the duration of the turn
    printf '%s' "$REASON" > "$T/reason" 2>/dev/null || :
    trace think "$(jq -cn --arg t "${TURN:-0}" --arg ts "$(ts)" --arg x "$REASON" \
      '{turn:($t|tonumber),ts:$ts,kind:"think",text:$x}')"
    log_to_stderr "$(ts)  turn $TURN  thinking: $(printf '%s' "$REASON" | wc -c) byte(s) to the base"
  fi

  if [ "$NTC" = "0" ]; then
    NO_TOOL=$((NO_TOOL + 1))
log_to_stderr "$(ts)  turn $TURN  no tool ($NO_TOOL) - model text: $(printf '%s' "$CONTENT" | tr '\n\t' '  ' | cut -c1-"$(conf_req_num loop error_chars)")"
    hist_apply --arg m "$(msg free_text)" '. + [{role:"system",content:$m}]'
    continue
  fi

  TCS=$(printf '%s' "$MSG" | jq -c --arg turn "$TURN" \
    '[.tool_calls | to_entries[] | .value + {id: (.value.id // ("call_la_" + $turn + "_" + (.key | tostring)))}]')
  if [ "${ECHO_REASON:-0}" = 1 ]; then
    AM=$(jq -cn --argjson tcs "$TCS" --arg c "$CONTENT" --arg r "$REASON" \
      --arg k "${REASON_FIELD:-reasoning}" \
      '{role:"assistant", content:$c, tool_calls:$tcs} + {($k):$r}')
  else
    AM=$(jq -cn --argjson tcs "$TCS" --arg c "$CONTENT" '{role:"assistant", content:$c, tool_calls:$tcs}')
  fi
  hist_apply --argjson m "$AM" '. + [$m]'

  I=0
  while [ "$I" -lt "$NTC" ]; do
    TC=$(printf '%s' "$TCS" | jq -c ".[$I]")
    ID=$(printf '%s' "$TC" | jq -r '.id')
    RAW=$(printf '%s' "$TC" | jq -r '.function.arguments // ""')
    I=$((I + 1))
    CALLS_TOTAL=$((CALLS_TOTAL + 1))
    if [ "$TRACE" = 1 ]; then
      log_to_stderr "$(ts)  turn $TURN  tool_call BRUT : $(printf '%s' "$TC" | jq -c '{id,function}')"
    fi

    G=$(printf '%s' "$RAW" | jq -r '.g // empty' 2>/dev/null || true)
    AJ=$(printf '%s' "$RAW" | jq -c 'if (.a|type)=="array" then [.a[]|tostring] elif (.a|type)=="string" then [.a] elif .a==null then [] else [] end' 2>/dev/null || true)
    if [ -z "$G" ] || [ -z "$AJ" ]; then
      LINE_=$(jq -cn --arg t "$(ts)" --arg m "$(msg json_args)" --arg r "$(msg json_shape)" '{status:"refused",tool:"la",
        line:($t+"  la  ->  "+$m),
        result:$r,
        ts:$t}')
log_to_stderr "$(ts)  turn $TURN  la  ->  unreadable arguments (sent back to the model)"
      RESULT_TEXT=$(result_of "$LINE_")
      hist_apply --arg id "$ID" --arg c "$RESULT_TEXT" '. + [{role:"tool",tool_call_id:$id,content:$c}]'
      continue
    fi
    case "$G" in *[!0-9]*) G='' ;; esac
    if [ -z "$G" ]; then
LINE_=$(refuse_loop "g must be a NUMBER of the table (got: something else)")
log_to_stderr "$(ts)  turn $TURN  la  ->  g is not a number (sent back to the model)"
      RESULT_TEXT=$(result_of "$LINE_")
      hist_apply --arg id "$ID" --arg c "$RESULT_TEXT" '. + [{role:"tool",tool_call_id:$id,content:$c}]'
      continue
    fi

    printf '%s\n' "$AJ" > "$T/a.json"
    NA=$(jq 'length' "$T/a.json" 2>/dev/null || true)
    case "${NA:-}" in ''|*[!0-9]*) NA=0 ;; esac
    BLOCK=$(block_of_id "$G" 2>/dev/null || true)
    TN=$(printf '%s\n' "$BLOCK" | sed -n 's/^    tool:[[:space:]]*//p' | head -n 1)
    FA=$(printf '%s\n' "$BLOCK" | sed -n 's/^    family:[[:space:]]*//p' | head -n 1)
    ACT=$(printf '%s' "$AJ" | jq -r '.[0] // ""')
    MODE=''
    [ "$TN" = reply ] && MODE=$(printf '%s' "$AJ" | jq -r '.[0] // empty' 2>/dev/null || true)

    if [ -n "$BLOCK" ] && ! scope_has "$G"; then
      _why="is not in the scope of THIS turn: the scope is built BEFORE your calls, so a gesture
 that opens it is worth for the NEXT turn. Name a tool of the list, or finish the turn (answer)"
      if in_plan_family "$TN" && [ "$DOC_READ" != 1 ]; then
        _why="belongs to the PLAN family, still CLOSED: read the doc first with load_doc"
      elif [ "$TN" = toolset ] && [ "$PLAN_DONE" != 1 ]; then
        _why="opens AFTER the plan: do the plan first (todo), the toolset follows"
      elif [ "$TN" = toolset ] && [ "$ARMED_THIS" = 1 ]; then
        _why="is already open this turn: name the tools of the skill directly"
      fi
      LINE_=$(refuse_loop "$TN ($G) $_why")
    else
      if is_gated "$TN" "$ACT" && ! approval_gate "$TN" "$ACT"; then
        approval_ask "$TN" "$ACT"
        if [ "$APPROVAL" != true ]; then
          LINE_=$(refuse_loop "$TN $ACT changes the harness: the active skill does not carry APPROVAL: true, so no green light can pass through it")
        else
          LINE_=$(refuse_loop "$TN $ACT waits for a human green light: approve that very gesture (work/approve), it is worth for it only and only once")
        fi
      else
        if [ -n "$BLOCK" ]; then
          ARGC=$(count_non_stdin_of_tool "$TN")
          if [ "$NA" -gt 0 ] && [ "$ARGC" -ge "$NA" ] && [ -n "$(stdin_tail_of_tool "$TN" 2>/dev/null || true)" ]; then
            ARGC=$((NA - 1))
          fi
          [ "$ARGC" -gt "$NA" ] && ARGC=$NA
        else
          ARGC=0
        fi
        case "$TN" in table_manage|skill_manage) LA_APPROVED=1 ; export LA_APPROVED ;; esac
        exec_engine "$G" "$ARGC" "$T/a.json"
        LINE_=$(cat "$T/engine.out")
        [ -n "$LINE_" ] || LINE_=$(refuse_loop "the engine rendered nothing")
        unset LA_APPROVED
      fi
    fi

    MSG_TS=$(printf '%s' "$LINE_" | jq -r '.ts // empty' 2>/dev/null || true)
    TOOL_NAME=$(printf '%s' "$LINE_" | jq -r '.tool // "?"' 2>/dev/null || true)
    MSG_STATUS=$(printf '%s' "$LINE_" | jq -r '.status // "?"' 2>/dev/null || true)
    step_record "$TOOL_NAME" "$MSG_STATUS"   # le tunnel avance sur le FAIT (tous ses outils ok)
    case "$TOOL_NAME" in
      load_doc) [ "$MSG_STATUS" = ok ] &&                                  DOC_READ=1 ;;
      toolset)                                                             TOOLSET_ARMED=1 ;;
      todo)                                                                PLAN_DONE=1 ;;
      update_todo)
        PLAN_DONE=1; PLAN_DUE=0
        if [ "$MSG_STATUS" = ok ] && "${PROCS}/plan.sh" status 2>/dev/null | grep -qi 'no open plan'; then
          PLAN_DONE=0 ; DOC_READ=0 ; TOOLSET_ARMED=0
          SKF=$(_abs "$(conf_str paths skill_active 'skills/.active')")
          if [ -f "$SKF" ] && [ ! -L "$SKF" ]; then
            SKE=$(sed -n '1p' "$SKF" | tr -d '\r')
            rm -f "$SKF"
            log_to_stderr "$(ts)  turn $TURN  la(g=$G, a=$AJ)  ->  $(msg plan_done "${SKE:-?}")"
          fi
        fi ;;
      load_project) [ "$MSG_STATUS" = ok ] && { BIG_DUE=1 ; BIG_ACT=$(big_act) ; } ;;
      big_todo|update_big_todo)
        BIG_DUE=0
        [ "$UPDATE_DUE" = 1 ] && UPDATE_DUE=2 ;;
      update_spec) [ "$UPDATE_DUE" = 2 ] && UPDATE_DUE=0 ;;
    esac
    MSG_LINE=$(printf '%s' "$LINE_" | jq -r '.line // .result // ""' 2>/dev/null || true)
    trace tool "$(jq -cn --arg t "${TURN:-0}" --arg ts "${MSG_TS:-$(ts)}" --arg n "${TOOL_NAME:-?}" \
      --arg s "${MSG_STATUS:-?}" --arg g "${G:-}" --arg a "${AJ:-}" --arg l "$MSG_LINE" \
      '{turn:($t|tonumber),ts:$ts,kind:"tool",tool:$n,status:$s,g:$g,args:$a,line:$l}')"
    log_to_stderr "${MSG_TS:-$(ts)}  turn $TURN  la(g=$G, a=$AJ)  ->  $MSG_LINE"

    case "$TOOL_NAME" in
      read_file|list_dir) P0=$(printf '%s' "$AJ" | jq -r '.[0] // empty'); [ -n "$P0" ] && printf '%s\n' "$P0" >> "$T/read_log" ;;
      write_file)         P0=$(printf '%s' "$AJ" | jq -r '.[0] // empty'); [ -n "$P0" ] && printf '%s\n' "$P0" >> "$T/written" ;;
    esac
    case "$TOOL_NAME" in
      reply|todo|update_todo|big_todo|update_big_todo|change_big_todo|toolset) : ;;
      *) printf '%s %s\n' "$TOOL_NAME" "$(printf '%s' "$AJ" | jq -r '.[0] // ""')" >> "$T/counter" ;;
    esac

    RESULT_TEXT=$(result_of "$LINE_")
    if [ "$MSG_STATUS" = "ok" ] && [ "$MODE" = "talk" ]; then
      _said=$(take_say)
      if [ -n "$_said" ]; then
        _suffix=""
        if [ "$I" -lt "$NTC" ]; then
          _ng=$(printf '%s' "$TCS" | jq -r ".[$I].function.arguments | (fromjson? // {}) | .g // empty" 2>/dev/null || true)
          _nb=$(block_of_id "$_ng" 2>/dev/null || true)
          _nn=$(printf '%s\n' "$_nb" | sed -n 's/^    tool:[[:space:]]*//p' | head -n 1)
          [ -n "$_nn" ] && _suffix="  (the result of $_nn follows just after, in this same turn)"
        fi
        RESULT_TEXT="the human said: $_said$_suffix"
        log_to_stderr "$(ts)  turn $TURN  talk: the human word comes in ($(printf '%s' "$_said" | wc -c) byte(s))"
      else
        RESULT_TEXT=""
      fi
    fi
    [ -n "$RESULT_TEXT" ] || [ "$MODE" = talk ] || RESULT_TEXT="the tool rendered nothing: $TOOL_NAME"
    RID_=
    [ "$MODE" = talk ] || RID_=$(printf '%s' "$LINE_" | jq -r '.return // empty' 2>/dev/null || true)
    hist_apply --arg id "$ID" --arg c "$RESULT_TEXT" --arg rid "${RID_:-}" \
      '. + [{role:"tool",tool_call_id:$id,
             content:($c + (if $rid == "" then "" else "\n[return " + $rid + "]\n" end))}]'

    if [ "$MSG_STATUS" = "ok" ] && [ "$MODE" = "talk" ]; then
      if ! say_once "$(result_of "$LINE_")"; then
        hist_apply --arg m "$(msg turn_same_words)" '. + [{role:"system",content:$m}]'
      fi
      log_to_stderr "$(ts)  turn $TURN  talk: the word was passed to the human channel, the turn goes on"
    fi
    if [ "$MSG_STATUS" = "ok" ] && [ "$MODE" = "answer" ]; then
      REPLY=$(result_of "$LINE_")
      if open_plan; then
        say_once "$REPLY" || true
        log_to_stderr "$(ts)  turn $TURN  answer PASSED and the plan is not finished: the reply goes to the human channel, the turn continues"
        SAID=$(printf '%s' "$REPLY" | tr '\n\t' '  ' | cut -c1-"$(conf_req_num loop error_chars)")
        hist_apply --arg m "$(msg turn_open "$SAID")" '. + [{role:"system",content:$m}]'
      else
        ANSWERED=1
        close_remaining
        break
      fi
    fi
    if [ "$MSG_STATUS" = "ok" ] && [ "$MODE" = "ask" ]; then
      REPLY=$(result_of "$LINE_")
      ANSWERED=1
      close_remaining
      log_to_stderr "$(ts)  turn $TURN  ask: the turn stops and waits for the human"
      break
    fi
    if [ -n "$MODE" ] && [ "$MODE" != "talk" ]; then
      log_to_stderr "$(ts)  turn $TURN  reply/$MODE was REFUSED: sent back to the model, the turn does not close"
    fi
    db_insert
  done
  [ "$ANSWERED" = 1 ] && break

  DUPLICATE=$(sort "$T/counter" | uniq -d | head -n 1)
  if [ -n "$DUPLICATE" ] && [ "$DUPLICATE" != "$CAP_LAST" ]; then
    CAP_LAST=$DUPLICATE
log_to_stderr "$(ts)  turn $TURN  anti-loop CAP: the same tool on the same target came back ($DUPLICATE)"
    hist_apply --arg m "$(msg bound_duplicate "$DUPLICATE")" '. + [{role:"system",content:$m}]'
  elif [ -n "$DUPLICATE" ]; then
    log_to_stderr "$(ts)  turn $TURN  anti-loop CAP: $DUPLICATE comes back again, I do not repeat it, I close"
    hist_apply --arg m "$(msg bound_removed "$DUPLICATE")" '. + [{role:"system",content:$m}]'
  fi

  if [ "$TOKENS_MAX" -gt 0 ] && [ "$TOKENS_TOTAL" -ge "$TOKENS_MAX" ]; then
    if [ "$TOKENS_SPOKE" = 0 ]; then
      TOKENS_SPOKE=1
      log_to_stderr "$(ts)  turn $TURN  token CAP: $TOKENS_TOTAL/$TOKENS_MAX - the model is warned to conclude"
      hist_apply --arg m "$(msg bound_tokens "$TOKENS_TOTAL" "$TOKENS_MAX")" '. + [{role:"system",content:$m}]'
    else
      log_to_stderr "$(ts)  turn $TURN  token CAP reached: $TOKENS_TOTAL/$TOKENS_MAX - the task stops"
      break
    fi
  fi

  if [ "$CALLS_MAX" -gt 0 ] && [ "$CALLS_TOTAL" -ge "$CALLS_MAX" ]; then
    if [ "$CALLS_SPOKE" = 0 ]; then
      CALLS_SPOKE=1
      log_to_stderr "$(ts)  turn $TURN  call CAP: $CALLS_TOTAL/$CALLS_MAX - the model is warned to conclude"
      hist_apply --arg m "$(msg bound_calls "$CALLS_TOTAL" "$CALLS_MAX")" '. + [{role:"system",content:$m}]'
    else
      log_to_stderr "$(ts)  turn $TURN  call CAP reached: $CALLS_TOTAL/$CALLS_MAX - the task stops"
      break
    fi
  fi

  ELAPSED=$(( $(date +%s) - T0 ))
  if [ "$SECONDS_MAX" -gt 0 ] && [ "$ELAPSED" -ge "$SECONDS_MAX" ]; then
    if [ "$SECONDS_SPOKE" = 0 ]; then
      SECONDS_SPOKE=1
      log_to_stderr "$(ts)  turn $TURN  time CAP: ${ELAPSED}s/$SECONDS_MAX - the model is warned to conclude"
      hist_apply --arg m "$(msg bound_time "$ELAPSED" "$SECONDS_MAX")" '. + [{role:"system",content:$m}]'
    else
      log_to_stderr "$(ts)  turn $TURN  time CAP reached: ${ELAPSED}s/$SECONDS_MAX - the task stops"
      break
    fi
  fi
done

db_insert

if [ -n "${CHAT_SEEN:-}" ]; then
  WF=$(tpn "$(conf_str paths seen 'config/%s.seen')" "$LA_FROM")
  case "$WF" in /*) ;; *) WF="$ROOT/$WF" ;; esac
  printf '%s\n' "$CHAT_SEEN" > "$WF" 2>/dev/null \
    || printf 'loop: the chat watermark could not be written (%s)\n' "$WF" >&2
fi

signal_task() {
  [ -x "$PROCS/signal_task.sh" ] || return 0
  ( printf '{}' | nohup "$PROCS/signal_task.sh" >>"/dev/null" 2>&1 & ) >/dev/null 2>&1
}

if [ "$ANSWERED" != 1 ]; then
  signal_task
  log_to_stderr "$(ts)  CAP of safety: a bound reached without reply (turns $TURN/$TURNS_MAX, tokens $TOKENS_TOTAL/$TOKENS_MAX, calls $CALLS_TOTAL/$CALLS_MAX, $(( $(date +%s) - T0 ))s/$SECONDS_MAX)"
  printf '(the task stopped without a reply : a safety bound is reached)\n'
  exit 0
fi

if [ -n "$REPLY" ] && [ -x "$PROCS/session_note.sh" ]; then
  ( nohup "$PROCS/session_note.sh" "$REQUEST" "$REPLY" >>"/dev/null" 2>&1 & ) >/dev/null 2>&1
fi
signal_task

printf '%s\n' "$REPLY"
