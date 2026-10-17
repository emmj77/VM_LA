#!/bin/sh
# engine.sh - THE LA ENGINE (config/engine/engine.sh). The ONLY proc : what replaces the gone
# procs is a TABLE and an engine.
#
# WHAT IT DOES, IN THIS ORDER, FOR A REQUESTED TOOL
#   1 it READS THE TABLE   config/la_tools.yaml, the line that carries the requested ID
#   2 it VALIDATES         the arity, the type of each argument, the closed list
#   3 it RESOLVES          the RELATIVE path according to the FAMILY of the line. READ -> under the
#                       ROOT - WRITE -> under $W. MANAGE validates only the SHAPE, its
#                       COMMAND names its register - REPLY carries no path.
#   4 it EXECUTES        the command of the line, in dash -c
#   5 it RETURNS         THE SINGLE SHAPE, and it is IT that writes it, never the command
#
# THE INTERFACE
#   engine.sh <id> [argument...]
#   the arguments in the ORDER DECLARED by the line. Those that carry stdin: true
#   (THE FREE TEXT) are NOT on the command line : they arrive on the STANDARD INPUT of the
#   engine, and the engine hands them to the command's standard input.
#
# THE TABLE - a root key tools:, one entry per tool, and nothing else in the file :
#   id - tool - family - description - args - command
#     args     name - type (path | enum | int | bool | text) - values (enum) - stdin
#     command  bare (cat) - in single quotes ('...') - or a BLOCK (|) whose body is indented by
#              six spaces
#   THE ID IS NOT A POSITION : a tool carries its id, adding it renumbers nothing.
#
# WHAT THE ENGINE SETS, FOR THE COMMAND (the table lines already use it) :
#   ROOT       the project root                      LA_CONFIG  the path of the TABLE
#   SKROOT     the folder of the ACTIVE SKILL        W          the skill's workspace
#   (the plan lives in the PLAN: section of the ACTIVE SKILL, no longer in a folder)
# THE ACTIVE SKILL is read at a SINGLE place : <project>/skills/la/skill.yaml, section
# PERIMETER:. IT IS THERE, and never elsewhere, that the engine reads WHERE a file is written. The
# model NEVER gives an absolute path : it gives a RELATIVE path, and the engine resolves it. The
# hole substituted in the command carries that RELATIVE, already validated.
#
# VALIDATION COMES BEFORE ANY EFFECT : nothing is executed if a single thing is off.
#   ARITY   it is a CEILING. More arguments than the line declares : named refusal.
#           Fewer : what is missing at the tail takes the EMPTY VALUE, and it is the VALIDATION
#           that decides - an enum that does not accept the empty value is refused ; an int, a
#           path, an empty text pass, and it is the COMMAND that judges (the table carries its
#           defaults). That is what lets `engine.sh 126 remove_skill <name>` reach its command
#           without naming the six arguments that do not concern it.
#   TYPE    enum  the value is in values, otherwise refusal NAMING IT with the list
#           int   digits, or empty         bool  true or false
#           path  see PATH                 text  any value
#           an argument marked stdin: true NEVER passes as an argument.
#   PATH   RELATIVE (absolute and ~ are refused), no .., no shell character (quote, dollar,
#           backtick, backslash, pattern * ? [ ]) and no control character. Then RESOLVED : what
#           leaves the register is refused.
#   FAMILY it says the NATURE, and therefore where a path is allowed to be. The register comes
#           from the ACTIVE SKILL (paths.root, paths.work) and NEVER from a table column :
#           READ    the path resolves under the ROOT, and does not leave it ;
#           WRITE   under $W, the working register of the active skill ;
#           MANAGE  the SHAPE alone (relative, no .., no shell) : the COMMAND names its register
#                   ($ROOT/memory, skills/, config/) ;
#           REPLY   no path at all. A family outside these four : named refusal.
#
# THE COMMAND carries holes {{name}}. The engine replaces the holes that carry the NAME of an
# argument declared outside stdin by its ALREADY VALIDATED value ; any other {{...}} STAYS AS IS,
# and the table uses it (108 keeps the holes of the memory-entry.md template there : {{date}},
# {{text}}). The FREE TEXT (stdin: true) NEVER mounts into the command : it enters by the standard
# input. And a text that enters the command is REFUSED if it carries what would break the table's
# quote (quote, dollar, backtick, backslash, control character) : no argument is interpreted text.
# Then the command goes off into dash -c.
#
# THE COMMAND CODES, AND IT IS THE LAW OF THE RETURN
#   0      status ok        result = its standard output
#   3      status approval  what it asks is on its STANDARD OUTPUT, and that text goes to the human
#   other  status refused   what it said on its ERROR OUTPUT is what the human will read ; a
#                           refusal is NEVER silent
#
# THE SHAPE OF THE RETURN, a single one, written by the engine on ITS STANDARD OUTPUT, as JSON on
# one line - and NOTHING else on that channel :
#   {"status":"ok|refused|approval","tool":"<name>","line":"<for the human>",
#    "result":"<for the LLM>","ts":"<date -u +%Y-%m-%dT%H:%M:%SZ>"}
# On a refusal the engine exits at 0 : it is the status that judges, not the code.
#
# sh (dash) + jq + coreutils : nothing else. No bash, no python3. NO backtick in this file, even
# in a comment : dash opens it where you least expect.

LC_ALL=C
export LC_ALL

# --- what is not guessed : the project, the table, the skill
SEVERE=$(printf '\140')
HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
ROOT=${LA_ROOT:-$(dirname "$CONF_DIR")}
TABLE=${LA_CONFIG:-$CONF_DIR/la_tools.yaml}
# THE ACTIVE SKILL — the resolution lives in the common library (config/engine/lib.sh).
[ -f "$HERE/lib.sh" ] || { printf 'engine: the common library is missing (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"
active_skill

TS=$(ts)
TOOL=unknown
ARGS_LINE=
NAMES_STDIN=' '
NAMES_TEXT=' '
BASE=
STDIN_FREE=no
TMPD=

# --- THE BOUND AND THE DELAY : the caps of the result, and the TIME cap --------
# EVERY result that enters the JSON reply is bounded here. A result that fits under BOTH caps
# passes AS IS, and creates NO file. Beyond it : a HEAD and a TAIL (the end of an output often
# carries the answer), cut on a WHOLE CHARACTER (never an orphan byte : the cut goes through
# iconv, which discards the incomplete sequence), and the COMPLETE output goes under $W,
# timestamped and speaking ; the bounded result NAMES that file, its bytes and its lines, and says
# it is truncated.
# LA_CAP_BYTES / LA_CAP_LINES / LA_TIMEOUT are set by the environment ; the RETAINED VALUES :
# 4000 bytes, 200 lines, 600 s. The engine's delay is a MARGIN over the longest internal timeout
# of the table (300 s, comfyui) : it is IT that cuts a tool that hangs. A tool that asks for
# longer declares it in ITS line, not here.
CAP_BYTES=${LA_CAP_BYTES:-4000}
CAP_LINES=${LA_CAP_LINES:-200}
TIMEOUT=${LA_TIMEOUT:-600}

command -v jq >/dev/null 2>&1 || {
  printf '{"status":"refused","tool":"unknown","line":"jq is missing from the machine","result":"refused: jq is missing, the engine could not write the single shape","ts":"%s"}\n' "$(ts)"
  exit 0
}

# --- THE SINGLE SHAPE : the engine is the ONLY one to write on the standard output.
one_line() {   # $1 = a multi-line message -> ONE line for the human
  printf '%s' "$1" | tr '\n\t' '  ' | jq -Rr 'if length > 400 then .[0:400] + " ..." else . end' 2>/dev/null
}
shape() {       # $1 status - $2 tool - $3 line - $4 result
  jq -cn --arg st "$1" --arg t "$2" --arg l "$3" --arg r "$4" --arg ts "$TS" \
    '{status:$st,tool:$t,line:$l,result:$r,ts:$ts}' 2>/dev/null \
  || printf '{"status":"refused","tool":"engine","line":"the single shape could not be built","result":"refused: the engine could not write the single shape","ts":"%s"}\n' "$TS"
  exit 0
}
file_shape() {   # the same shape, the result read AS IS from a file (exact bytes)
  if jq -cn --arg st "$1" --arg t "$2" --arg l "$3" --arg ts "$TS" --rawfile r "$4" \
       '{status:$st,tool:$t,line:$l,result:$r,ts:$ts}' 2>/dev/null; then
    exit 0
  fi
  shape "$1" "$2" "$3" ""
}
refuse_tool() {       # $1 = the detail ; the refusal is NAMED, it is never silent
  shape refused "$TOOL" "$(one_line "refused: $1")" "refused: $1"
}
refuse_preformed() {   # $1 = the already-formed message (the command's, as is)
  shape refused "$TOOL" "$(one_line "$1")" "$1"
}

# --- THE BOUND : the only place where a result is sized ------------------------
# count : the number of BYTES and real LINES of a file (a last line without a newline counts as
#         one line, as wc -l forgets it).
# bound_file : returns 1 if the file fits under BOTH caps (it is then neither modified nor copied) ;
#         returns 0 while WRITING on its standard output the bounded result - head, tail, path of
#         the complete file, bytes, lines.
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
  # the room taken by the markers of the bounded result, kept out of the head/tail
  FRAME=400
  CONTENT=$((CAP_BYTES - FRAME))
  [ "$CONTENT" -gt 200 ] || CONTENT=200
  HT=$((CONTENT * 3 / 5))
  QT=$((CONTENT - HT))
  # THE CUT ON A WHOLE CHARACTER : iconv reads the chunk, discards the incomplete sequence at the
  # head or tail, and leaves only valid UTF-8. If the file is not UTF-8, the cut stays on the byte
  # (there is no character to respect), and we say so by the file name.
  if iconv -f UTF-8 -t UTF-8 "$F" >/dev/null 2>&1; then
    HEAD_PART=$(head -c "$HT" "$F" 2>/dev/null | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
    TAIL_PART=$(tail -c "$QT" "$F" 2>/dev/null | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
  else
    HEAD_PART=$(head -c "$HT" "$F" 2>/dev/null)
    TAIL_PART=$(tail -c "$QT" "$F" 2>/dev/null)
  fi
  # THE COMPLETE OUTPUT under $W, timestamped and speaking ; the path is said RELATIVE to the
  # project, so the READ tool (read_file) takes it back as is.
  FILE_NAME="truncated-output-$(date -u +%Y%m%dT%H%M%SZ)-${TOOL}.txt"
  PATH="$W/$FILE_NAME"
  if ! cp "$F" "$PATH" 2>/dev/null; then PATH=; fi
  printf '[TRUNCATED] the raw output is %s byte(s) and %s line(s) ; the caps are %s byte(s) and %s line(s).\n' "$O" "$L" "$CAP_BYTES" "$CAP_LINES"
  if [ -n "$PATH" ]; then
    REL=${PATH#"$ROOT"/}
    printf 'complete output (as is) : %s (%s byte(s), %s line(s))\n' "$REL" "$O" "$L"
  else
    printf 'the complete output could not be written under $W (%s)\n' "$W"
  fi
  printf -- '--- HEAD_PART (start) ---\n%s\n--- TAIL_PART (end) ---\n%s\n' "$HEAD_PART" "$TAIL_PART"
  printf '[TRUNCATED] head and tail only ; the rest is in the file above.\n'
  return 0
}

# --- [1] THE ID, AND THE LINE --------------------------------------------------
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
  READ|WRITE|MANAGE|REPLY) ;;
  *) refuse_tool "the line $ID ($TOOL) carries an off-form family (${FAMILY:-absent}) ; the families are READ, WRITE, MANAGE, REPLY" ;;
esac
# --- LE FICHIER DU TOOL : le corps, les arguments et le plafond de temps y vivent -------------
# Le REGISTRE (config/la_tools.yaml) ne porte plus que l'id, le nom, la famille et les garde-fous.
# Le corps vit dans config/tools/<machine>/tool_<nom>.yaml, sous la cle COMMAND ; les arguments sous
# ARGS ; le plafond de temps du tool sous RULES.timeout. Une ligne qui porte encore son
# command: est l'ANCIENNE FORME : elle est lue comme avant, le temps de la migration.
TOOLFILE=
for TDIR in "$ROOT"/config/tools/*/ "$ROOT"/config/tools/; do
  [ -f "$TDIR/tool_$TOOL.yaml" ] && { TOOLFILE="$TDIR/tool_$TOOL.yaml"; break; }
done
FABLOC=
FTMO=
FENB=
if [ -n "$TOOLFILE" ]; then
  [ -r "$TOOLFILE" ] || refuse_tool "the file of the tool $TOOL is unreadable ($TOOLFILE)"
  # LE BLOC D'UNE CLE : les lignes indentees qui suivent la cle, jusqu'a la PREMIERE ligne qui ne
  # l'est pas (la cle suivante), et rien apres. Les lignes vides du corps sont GARDEES telles
  # quelles : un corps est repris mot pour mot, jamais reflowe.
  FCMD=$(awk '/^COMMAND: \|$/{f=1;next} f&&/^[^ ]/{exit} f{sub(/^  /,"");print}' "$TOOLFILE")
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
fi

# --- THE enabled FIELD : a tool WITHOUT enabled is ACTIVE ----------------------
# Le champ vit dans le fichier du tool (RULES) ; une ligne du registre peut encore le porter
# (ancienne forme). C'est ICI, et seulement ici, que ce champ devient un effet.
if [ -n "$TOOLFILE" ]; then
  EBL=$FENB
else
  EBL=$(printf '%s\n' "$BLOCK" | sed -n 's/^    enabled:[[:space:]]*//p' | head -n 1)
fi
case "$EBL" in
  ''|true) ;;
  false) refuse_tool "the tool $TOOL is disabled : its file carries enabled: false, and the engine does not execute it ; reactivate it before calling it (${TOOLFILE:-line $ID})" ;;
  *)     refuse_tool "the enabled field of the tool $ID ($TOOL) is off-form (${EBL}) ; it carries true or false" ;;
esac

# --- THE COMMAND : in the tool's file, or on the line (ancienne forme) ---------
CMD=
if [ -n "$TOOLFILE" ]; then
  CMD=$FCMD
  [ -n "$CMD" ] || refuse_tool "the file of the tool $TOOL carries no command ($TOOLFILE)"
  CMD_COUNT=$(printf '%s\n' "$BLOCK" | grep -c '^    command:')
  [ "$CMD_COUNT" = 0 ] || refuse_tool "the line $ID ($TOOL) carries a command AND the tool's file carries one : a tool has ONE body, not two ($TOOLFILE)"
else
  CMD_COUNT=$(printf '%s\n' "$BLOCK" | grep -c '^    command:')
  [ "$CMD_COUNT" = 1 ] || refuse_tool "the tool $TOOL has no body : the line $ID of the register carries no command, and no tool's file carries one ($ROOT/config/tools/*/tool_$TOOL.yaml)"
  CMD_LINE=$(printf '%s\n' "$BLOCK" | grep '^    command:' | head -n 1)
  case "$CMD_LINE" in
    '    command: |')
      CMD=$(printf '%s\n' "$BLOCK" | sed -n '/^    command: |$/,$p' | sed '1d' | sed -e 's/^      //')
      ;;
    '    command:'*)
      CMD=$(printf '%s\n' "$CMD_LINE" | sed -e 's/^    command:[[:space:]]*//')
      case "$CMD" in
        \'*\') CMD=$(printf '%s' "$CMD" | sed -e "s/^'//" -e "s/'\$//") ;;
      esac
      ;;
    *)
      refuse_tool "the line $ID ($TOOL) is unreadable : the command field could not be read" ;;
  esac
fi
[ -n "$CMD" ] || refuse_tool "the line $ID ($TOOL) is unreadable : its command is empty"

# --- THE ACTIVE SKILL : it is there, and nowhere else, that a file is written ---
[ -f "$SKILL" ] || refuse_tool "the ACTIVE SKILL is missing ($SKILL) : the engine has nowhere to read the registers of the active skill"
# PERIMETER carries TWO things : workspace (the working folders) and type-file (the accepted
# types). SPECS is derived from the ACTIVE SKILL itself ; ROOT is the PROJECT root.
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
SPEC="$SKROOT/spec.yaml"
# SPEC serves as a working variable for reading the arguments : the spec PATH travels under another
# name, otherwise the first argument of write_spec overwrites it.
SPEC_FILE="$SPEC"
# PROCS : the BRICKS folder (the engine scripts). A tool whose body lives in a brick names it
# through it : the table line carries ONLY the command (law 506).
PROCS=$HERE
# THE PLAN NO LONGER LIVES IN A FOLDER : it lives in the PLAN: section of the ACTIVE SKILL, held by
# the plan.sh brick. P is therefore no longer a file scope, and it is no longer exported.
export ROOT SKROOT W PROCS SKILL SPEC_FILE
LA_CONFIG=$TABLE
export LA_CONFIG

# --- THE FAMILY : it says the NATURE, and therefore the register where a path is allowed to be
#   READ   the path resolves under the ROOT   WRITE  under $W, the working register
#   MANAGE the command names its register : BASE stays empty, and only the SHAPE is judged
#   REPLY  no REPLY line carries a path
BASE=
case "$FAMILY" in
  READ)         BASE=$ROOT ;;
  WRITE)        BASE=$W ;;
  MANAGE|REPLY) BASE= ;;
esac

# --- [2] AND [3] THE ARGUMENTS : the arity, the type, the path -----------------
if [ -n "$TOOLFILE" ]; then
  ABLOC=$FABLOC
else
  ABLOC=$(printf '%s\n' "$BLOCK" | sed -n '/^    args:/,/^    [a-z]/p' | sed '$d')
fi
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

# --- [4] THE BUILD : the holes that carry a declared argument, and THEM ALONE --
# A hole that carries the name of an argument declared outside stdin receives its ALREADY VALIDATED
# value. Any other {{...}} STAYS AS IS : the table uses it - 108 keeps the holes of the
# memory-entry.md template there ({{date}}, {{text}}). And the FREE TEXT (stdin: true) NEVER mounts
# into the command : it enters by the standard input.
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

# --- [5] THE EXECUTION : the command, and its standard input -------------------
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/engine.XXXXXX" 2>/dev/null)
[ -n "$TMPD" ] && [ -d "$TMPD" ] || refuse_tool "the engine could not open its temporary workspace (${TMPDIR:-/tmp})"
cleanup_tmp_engine() { rm -f "$TMPD/out" "$TMPD/err" 2>/dev/null; rmdir "$TMPD" 2>/dev/null; }
trap 'cleanup_tmp_engine' EXIT INT TERM HUP

SH=$(command -v dash 2>/dev/null)
[ -n "$SH" ] || SH=$(command -v sh 2>/dev/null)
[ -n "$SH" ] || refuse_tool "no sh (dash) on the machine"

# THE MAXIMAL DELAY : no line of the table hangs the loop. timeout covers the WHOLE command (its
# own internal timeout, if it has one, stays tighter).
TIMEOUT_BIN=$(command -v timeout 2>/dev/null)
[ -n "$TIMEOUT_BIN" ] || refuse_tool "timeout (coreutils) is missing from the machine : the engine cannot set a maximal delay on the command"

if [ "$STDIN_FREE" = yes ]; then
  "$TIMEOUT_BIN" "$TIMEOUT" "$SH" -c "$BODY" > "$TMPD/out" 2> "$TMPD/err"
else
  "$TIMEOUT_BIN" "$TIMEOUT" "$SH" -c "$BODY" > "$TMPD/out" 2> "$TMPD/err" < /dev/null
fi
RC=$?

# --- [6] THE SHAPE : a single one, and it is the engine that writes it ---------
# EVERY result goes through THE BOUND before entering the shape : under the caps it is returned AS
# IS (no file is created) ; beyond it is truncated and the complete output is written under $W,
# with its path in the result.
case "$RC" in
  0)
    LINE=$(jq -rn --rawfile r "$TMPD/out" --arg t "$TOOL" --arg a "$ARGS_LINE" '
      ($r | sub("[\n\t ]+$"; "")) as $x
      | (if ($x | length) == 0 then "done, 0 byte on the output"
         elif ($x | test("\n")) then (($x | length | tostring) + " bytes, " + ((($x | split("\n")) | length) | tostring) + " line(s)")
         else $x end) as $res
      | ($t + (if $a == "" then "" else "  " + $a end) + "  ->  "
         + (if ($res | length) > 140 then ($res[0:140] + " ...") else $res end))')
    CAP_TXT=$(bound_file "$TMPD/out"); CAP_RC=$?
    if [ "$CAP_RC" -eq 0 ]; then
      shape ok "$TOOL" "$LINE" "$CAP_TXT"
    fi
    file_shape ok "$TOOL" "$LINE" "$TMPD/out"
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
