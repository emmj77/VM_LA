#!/usr/bin/dash
# french in code is forbidden
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

shell_path() { command -v dash 2>/dev/null || command -v sh 2>/dev/null; }

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  printf 'refused: %s is missing from the machine%s\n' "$1" \
    "${2:+ (needed by $2)}" >&2
  return 1
}

bip() {  # $1 = notify (defaut, une approbation attend) | ok (le feu vert est signe)
  case "${1:-notify}" in
    ok) F=/usr/share/sounds/freedesktop/stereo/bell.oga ;;
    *)  F=/usr/share/sounds/freedesktop/stereo/message-new-instant.oga ;;
  esac
  [ -f "$F" ] || return 0
  command -v paplay >/dev/null 2>&1 || return 0
  ( paplay "$F" >/dev/null 2>&1 || true ) &
  return 0
}

CLEAN=
tmpfile() {   # $1 = a prefix (plan, plant, planp...) ; sets TMPFILE and remembers it
  TMPFILE=$(mktemp "${TMPDIR:-/tmp}/$1.XXXXXX") || { TMPFILE= ; return 1 ; }
  # CLEAN garde UN CHEMIN PAR LIGNE : mktemp accepte un TMPDIR avec des espaces,
  # et `rm -f $CLEAN` couperait alors un chemin en deux arguments.
  CLEAN="$CLEAN$TMPFILE
"
  trap 'printf "%s" "$CLEAN" | while IFS= read -r _f ; do [ -n "$_f" ] && rm -f -- "$_f" ; done' EXIT INT TERM HUP
}

HERE=${HERE:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
ROOT=${ROOT:-${LA_ROOT:-$(CDPATH= cd -- "$HERE/../.." && pwd)}}
LC_ALL=C ; export LC_ALL
CONF=${LA_CONF:-$ROOT/config/la_config.yaml}
MSGS=${LA_MESSAGES:-$ROOT/config/messages.yaml}

state_paths() {
  _sp_from=${LA_FROM:-agent_one}
  _sp_main=$(sed -n '/^agents:/,/^[^[:space:]]/p' "$ROOT/config/la_config.yaml" 2>/dev/null \
             | sed -n 's/^[[:space:]]*main:[[:space:]]*//p' | head -n 1 \
             | sed -e 's/[[:space:]]*#.*$//' -e 's/^"//' -e 's/"$//')
  [ -n "$_sp_main" ] || _sp_main=agent_one
  if [ "$_sp_from" = "$_sp_main" ]; then
    LA_STATE_SKILL="$ROOT/skills/.active"
    LA_STATE_PROJECT="$ROOT/projects/.active"
  else
    LA_STATE_SKILL="$ROOT/config/$_sp_from.skill"
    LA_STATE_PROJECT="$ROOT/config/$_sp_from.project"
  fi
  export LA_STATE_SKILL LA_STATE_PROJECT
  return 0
}

active_skill() {
  SKILLS_DIR="$ROOT/skills"
  if [ -n "${LA_STATE_SKILL:-}" ]; then ACTIVE_FILE="$LA_STATE_SKILL"
  else ACTIVE_FILE="$SKILLS_DIR/.active" ; fi
  NAME=
  if [ -L "$ACTIVE_FILE" ]; then
    printf 'skills: the state file is a LINK (%s) ; links are forbidden ; NO skill is active\n' "$ACTIVE_FILE" >&2
  elif [ ! -f "$ACTIVE_FILE" ]; then
    printf 'skills: the state file is MISSING (%s) ; NO skill is active\n' "$ACTIVE_FILE" >&2
  else
    NAME=$(sed -n '1p' "$ACTIVE_FILE" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$NAME" in
      '') printf 'skills: the state file is EMPTY (%s) ; NO skill is active\n' "$ACTIVE_FILE" >&2 ; NAME= ;;
      */*|*..*) printf '%s\n' "$(msg skill_name "$NAME")" >&2 ; NAME= ;;
      *) [ -d "$SKILLS_DIR/$NAME" ] && [ -f "$SKILLS_DIR/$NAME/skill.yaml" ] || { printf 'skills: skill %s has NO DIR under skills/ ; NO skill is active\n' "$NAME" >&2 ; NAME= ; } ;;
    esac
  fi
  SKILL=
  [ -n "$NAME" ] && SKILL="$SKILLS_DIR/$NAME/skill.yaml"
}

canon_path() {
  SPEC=
  CANON_WHY=
  active_project
  PD="$ROOT/projects"
  if [ -n "$PNAME" ]; then
    if [ -f "$PD/$PNAME/spec.yaml" ]; then
      SPEC="$PD/$PNAME/spec.yaml" ; CANON_WHY="the SPEC of the active project ($PNAME)"
    else
      CANON_WHY="the active project ($PNAME) carries NO spec.yaml ($PD/$PNAME/spec.yaml is absent)"
    fi
  else
    SD=
    [ -n "${SKILL:-}" ] && SD=$(dirname "$SKILL")
    if [ -n "$SD" ] && [ -f "$SD/spec.yaml" ]; then
      SPEC="$SD/spec.yaml" ; CANON_WHY="the SPEC of the active skill (${NAME:-?})"
    elif [ -f "$PD/la/spec.yaml" ]; then
      SPEC="$PD/la/spec.yaml" ; CANON_WHY="the SPEC of LA itself (no project, no skill spec)"
    fi
  fi
  [ -n "$CANON_WHY" ] || CANON_WHY="nothing carries a canon : no project, no skill spec, and $PD/la/spec.yaml is absent"
  return 0
}

active_project() {
  PROJECTS_DIR="$ROOT/projects"
  PACTIVE_FILE="$PROJECTS_DIR/.active"
  PNAME=
  if [ -L "$PACTIVE_FILE" ]; then
    printf 'projects: the state file is a LINK (%s) ; links are forbidden\n' "$PACTIVE_FILE" >&2
  elif [ ! -f "$PACTIVE_FILE" ]; then
    :
  else
    PNAME=$(sed -n '1p' "$PACTIVE_FILE" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$PNAME" in
      '') PNAME= ;;
      */*|*..*) printf '%s\n' "$(msg project_name "$PNAME")" >&2 ; PNAME= ;;
      *) [ -d "$PROJECTS_DIR/$PNAME" ] && [ -f "$PROJECTS_DIR/$PNAME/project.yml" ] || { printf 'projects: project %s has NO DIR under projects/ ; ignored\n' "$PNAME" >&2 ; PNAME= ; } ;;
    esac
  fi
  PROJECT=
  [ -n "$PNAME" ] && PROJECT="$PROJECTS_DIR/$PNAME/project.yml"
}

project_skills() {
  [ -f "${1:-}" ] || return 0
  sed -n '/^SKILLS:/,/^[^[:space:]]/p' "$1" \
    | sed -n 's/^[[:space:]]*-[[:space:]]*//p; s/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
    | sed -e 's/^"//' -e 's/"$//' | grep -v '^$'
}

config_section() {  # $1 = le fichier ; $2 = le nom de section : une entree par ligne
  [ -n "${1:-}" ] && [ -f "${1:-}" ] || return 0
  sed -n "/^$2:/,/^[^[:space:]]/p" "$1" 2>/dev/null \
    | sed -n 's/^[[:space:]]*-[[:space:]]*//p' \
    | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' | grep -v '^$'
}

permanent_section() {
  CONF=${1:-}
  config_section "$CONF" permanent
}

table_ids() {
  grep -n '^  - id: ' "$1" | sed 's/^[0-9]*:  - id:[[:space:]]*//' | tr -d ' '
}
table_block() {
  TB_TABLE=${1:-}
  TB_ID=${2:-}
  [ -f "$TB_TABLE" ] || return 1
  TB_START=$(grep -n "^  - id: ${TB_ID}[[:space:]]*\$" "$TB_TABLE" 2>/dev/null | head -n 1 | cut -d: -f1)
  [ -n "$TB_START" ] || return 1
  TB_END=$(grep -n '^  - id: ' "$TB_TABLE" | cut -d: -f1 | while IFS= read -r n; do
        [ "$n" -gt "$TB_START" ] && { printf '%s\n' "$n"; break; }
      done)
  [ -n "$TB_END" ] || TB_END=$(( $(wc -l < "$TB_TABLE") + 1 ))
  sed -n "${TB_START},$((TB_END - 1))p" "$TB_TABLE"
}

table_index() {
  [ -n "${TABLE_INDEX+x}" ] && return 0
  TABLE_INDEX=
  [ -f "${TABLE:-}" ] || return 1
  TABLE_INDEX=$(awk '
    function emit() {
      if (id == "") return
      printf "%s|%s|%s|%s|%s\n", id, tool, fam, gu, d
    }
    /^  - id: /      { emit() ; id = $0 ; sub(/^  - id:[ \t]*/, "", id) ; sub(/[^0-9].*$/, "", id) ; tool = "" ; fam = "" ; gu = "" ; d = "" ; next }
    /^    tool: /      { tool = $0 ; sub(/^    tool:[ \t]*/, "", tool) ; gsub(/"/, "", tool) ; next }
    /^    family: /    { fam = $0 ; sub(/^    family:[ \t]*/, "", fam) ; gsub(/"/, "", fam) ; next }
    /^    guardrail: / { gu = $0 ; sub(/^    guardrail:[ \t]*/, "", gu) ; gsub(/"/, "", gu) ; next }
    /^    description: / { d = $0 ; sub(/^    description:[ \t]*/, "", d) ; sub(/^"/, "", d) ; sub(/"$/, "", d) ; next }
    END { emit() }
  ' "$TABLE" 2>/dev/null)
  return 0
}

port_busy() {
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$1\$" && return 0
  curl -s --max-time "$(conf_num limits ping_timeout 2)" "http://127.0.0.1:$1/" >/dev/null 2>&1 && return 0
  return 1
}
service_ctl() {
  SC_MODE=$1 ; shift
  case "$SC_MODE" in
    run) cd "$WD" || exit 1 ; exec "$@" ;;
    start)
      if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "$LABEL is already running (pid $(cat "$PID_FILE"), port $PORT)" ; exit 0
      fi
      if port_busy "$PORT"; then
        echo "$LABEL refused: port $PORT is already busy, nothing was started" ; exit 1
      fi
      ( cd "$WD" && exec setsid nohup "$@" >> "$LOGF" 2>&1 & echo $! > "$PID_FILE" )
      echo "$LABEL started (pid $(cat "$PID_FILE"), port $PORT, log $LOGF)"
      ;;
    stop)   # LE GROUPE D ABORD ; et jamais l illusion d avoir arrete ce qu on n a pas place.
      if [ ! -f "$PID_FILE" ]; then
        if port_busy "$PORT"; then
          echo "$LABEL answers on port $PORT but carries NO mark: it was started outside this" >&2
          echo "protocol, and I never kill what I did not place. Stop it by hand or by its service." >&2
          exit 1
        fi
        echo "$LABEL is not running: no mark" ; exit 0
      fi
      SC_P=$(cat "$PID_FILE")
      SC_TUE=0
      [ -x /bin/kill ] && /bin/kill -TERM -- "-$SC_P" 2>/dev/null && SC_TUE=1
      [ "$SC_TUE" = 0 ] && [ -x /usr/bin/kill ] && /usr/bin/kill -TERM -- "-$SC_P" 2>/dev/null && SC_TUE=1
      [ "$SC_TUE" = 0 ] && kill -TERM "$SC_P" 2>/dev/null
      SC_I=0
      while kill -0 "$SC_P" 2>/dev/null && [ "$SC_I" -lt "$(conf_num limits stop_tries 50)" ]; do sleep 0.1; SC_I=$((SC_I + 1)); done
      if kill -0 "$SC_P" 2>/dev/null; then
        [ -x /bin/kill ] && /bin/kill -KILL -- "-$SC_P" 2>/dev/null
        [ -x /usr/bin/kill ] && /usr/bin/kill -KILL -- "-$SC_P" 2>/dev/null
        kill -KILL "$SC_P" 2>/dev/null || :
        rm -f "$PID_FILE"
        echo "$LABEL did not stop on TERM: KILLED (group $SC_P)" ; exit 0
      fi
      echo "$LABEL stopped (group $SC_P, children included)"
      rm -f "$PID_FILE"
      ;;
    status)
      SC_R=$(curl -s --max-time "$(conf_num limits health_timeout 3)" "http://127.0.0.1:$PORT/$HEALTH" 2>/dev/null)
      if [ -n "$SC_R" ]; then
        if [ -f "$PID_FILE" ]; then echo "$LABEL up on 127.0.0.1:$PORT : $SC_R" ;
        else echo "$LABEL up on 127.0.0.1:$PORT WITHOUT a mark: started outside this protocol" ; fi
      else echo "$LABEL silent on 127.0.0.1:$PORT" ; exit 1 ; fi
      ;;
    *) echo "modes: start | stop | status | run | help" ;;
  esac
}

conf_num() {  # $1 = section ; $2 = cle ; $3 = defaut : rend un ENTIER
  if [ "${CONF_PRIMED:-0}" = 1 ]; then
    eval "_v=\${CC_$1_$2:-}"
    case "${_v:-}" in ''|*[!0-9]*) _v='' ;; esac
    [ -n "$_v" ] && { printf '%s' "$_v" ; return 0 ; }
  fi
  _v=''
  if [ -n "${CONF:-}" ] && [ -f "${CONF:-}" ]; then
    _v=$(sed -n "/^$1:/,/^[^[:space:]]/p" "$CONF" 2>/dev/null \
         | sed -n "s/^[[:space:]]*$2:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n 1)
  fi
  case "${_v:-}" in ''|*[!0-9]*) _v=${3:-0} ;; esac
  printf '%s' "$_v"
}

conf_str() {  # $1 = section ; $2 = cle ; $3 = defaut : rend le TEXTE (guillemets et commentaire otés)
  if [ "${CONF_PRIMED:-0}" = 1 ]; then
    eval "_v=\${CC_$1_$2:-}"
    [ -n "$_v" ] && { printf '%s' "$_v" ; return 0 ; }
  fi
  _v=''
  if [ -n "${CONF:-}" ] && [ -f "${CONF:-}" ]; then
    _v=$(sed -n "/^$1:/,/^[^[:space:]]/p" "$CONF" 2>/dev/null \
         | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | head -n 1 \
         | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' \
               -e "s/^'//" -e "s/'$//")
  fi
  [ -n "${_v:-}" ] || _v=${3:-}
  printf '%s' "$_v"
}


conf_prime() {
  _c=${CONF:-}
  [ -f "$_c" ] || return 0
  eval "$(awk '
    /^[a-z_]+:/ { s = $0 ; sub(/:.*/, "", s) ; next }
    /^[[:space:]]+[a-z_]+:/ {
      k = $0 ; sub(/^[[:space:]]+/, "", k)
      v = k ; sub(/^[^:]*:[[:space:]]*/, "", v) ; sub(/[[:space:]]*#.*$/, "", v) ; sub(/[[:space:]]+$/, "", v)
      gsub(/^"|"$/, "", v)
      key = k ; sub(/:.*/, "", key)
      if (v != "" && v !~ /[`$;"'"'"'\\]/) printf "CC_%s_%s=\047%s\047\n", s, key, v
    }' "$_c")"
  CONF_PRIMED=1
}

conf_has() {  # $1 = section ; $2 = cle : la cle est-elle ECRITE dans le fichier ?
  [ -n "${CONF:-}" ] && [ -f "${CONF:-}" ] || return 1
  sed -n "/^$1:/,/^[^[:space:]]/p" "$CONF" 2>/dev/null | grep -qE "^[[:space:]]+$2:"
}

conf_req() {  # $1 = num|str ; $2 = section ; $3 = cle
  conf_has "$2" "$3" || { printf '%s\n' "$(msg conf_missing "$2" "$3")" >&2 ; exit 78 ; }
  "conf_$1" "$2" "$3"
}

conf_require() {  # $1 = section ; le reste = les cles exigees
  _s=$1 ; shift
  if [ "${CONF_PRIMED:-0}" = 1 ]; then
    _bad=0
    for _k in "$@" ; do
      eval "_z=\${CC_${_s}_${_k}+set}"
      [ "${_z:-}" = set ] || { printf 'la_config : %s.%s manque -- le moteur refuse de deviner\n' "$_s" "$_k" >&2 ; _bad=1 ; }
    done
    [ "$_bad" = 0 ] || exit 78
    return 0
  fi
  _miss=$(awk -v sec="$_s" -v keys="$*" '
    BEGIN { n = split(keys, k, " ") ; f = 0 }
    $0 ~ "^"sec":" { f = 1 ; next }
    f && /^[^[:space:]]/ { f = 0 }
    f && /^[[:space:]]+[a-z_]+:/ {
      t = $0 ; sub(/^[[:space:]]+/, "", t) ; sub(/:.*/, "", t) ; seen[t] = 1
    }
    END { for (i = 1 ; i <= n ; i++) if (!(k[i] in seen)) print k[i] }
  ' "${CONF:-}" 2>/dev/null)
  if [ -n "$_miss" ]; then
    for _k in $_miss ; do printf 'la_config : %s.%s manque -- le moteur refuse de deviner\n' "$_s" "$_k" >&2 ; done
    exit 78
  fi
}

conf_req_num() { conf_req num "$1" "$2" ; }
conf_req_str() { conf_req str "$1" "$2" ; }

tpn() {   # $1 = le texte ; $2.. = les valeurs
  _fmt=$1 ; shift
  _need=0 ; _rest=$_fmt
  while : ; do
    case $_rest in *%s*) _need=$((_need + 1)) ; _rest=${_rest#*%s} ;; *) break ;; esac
  done
  if [ "$_need" -eq "$#" ]; then
    printf "$_fmt\n" "$@"
  else
    printf 'config: a declared text carries %s %%s for %s value(s) : written AS IS\n' \
      "$_need" "$#" >&2
    printf '%s\n' "$_fmt"
  fi
}

bound() { head -n "$1" | head -c "$2" ; }

read_permanent() {  # la section permanente, PLUS le scope de ce qui est charge
  permanent_section "$CONF"
  active_skill >/dev/null 2>&1
  [ -n "$SKILL" ] && config_section "$CONF" with_skill
  active_project >/dev/null 2>&1
  [ -n "$PROJECT" ] && config_section "$CONF" with_project
  return 0
}

_abs() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$ROOT" "$1" ;; esac ; }
conf_prime
WORK=$(_abs "$(conf_str paths work "work/")")          ; WORK=${WORK%/}
STATE=$(_abs "$(conf_str paths state "config/state/")") ; STATE=${STATE%/}
RETURNS=$(_abs "$(conf_str paths returns "config/state/returns/")") ; RETURNS=${RETURNS%/}
SCRIPTS=$(_abs "$(conf_str paths programs "config/programs/")") ; SCRIPTS=${SCRIPTS%/}
DOCS=$(_abs "$(conf_str paths docs "config/docs/")") ; DOCS=${DOCS%/}
export WORK STATE RETURNS SCRIPTS DOCS
mkdir -p "$STATE" "$RETURNS" 2>/dev/null || :

tool_file_of() {  # $1 = nom du tool ; ecrit le chemin, echoue s il n existe pas
  for _d in "$ROOT"/config/tools/*/ "$ROOT"/config/tools/; do
    [ -f "$_d/tool_$1.yaml" ] && { printf '%s\n' "$_d/tool_$1.yaml" ; return 0 ; }
  done
  return 1
}

approval_of() {  # $1 = nom du tool ; pose APPROVAL_MODE et APPROVAL_ACTIONS
  APPROVAL_MODE=''
  APPROVAL_ACTIONS=''
  _af=$(tool_file_of "$1") || return 0
  APPROVAL_MODE=$(sed -n '/^RULES:/,/^[A-Z]/p' "$_af" 2>/dev/null \
    | sed -n 's/^[[:space:]]*approval:[[:space:]]*//p' | head -n 1 | tr -d '"'"'"' ' )
  APPROVAL_ACTIONS=$(sed -n '/^RULES:/,/^[A-Z]/p' "$_af" 2>/dev/null \
    | sed -n 's/^[[:space:]]*approval_actions:[[:space:]]*//p' | head -n 1 | tr -d '"[]' | tr ',' ' ')
  return 0
}


is_gated() {  # $1 = tool ; $2 = action : ce geste demande-t-il un feu vert humain ?
  approval_of "$1"
  case "$APPROVAL_MODE" in
    whole) return 0 ;;
    write) case " $APPROVAL_ACTIONS " in *" $2 "*) return 0 ;; esac ;;
  esac
  return 1
}

msg_str() {  # $1 = key : config/messages.yaml carries one line per message
  [ -f "$MSGS" ] || return 0
  awk -v k="$1:" '
    index($0, k) == 1 {
      v = $0 ; sub(/^[^:]*:[[:space:]]*/, "", v)
      if (v ~ /^\047.*\047$/) { v = substr(v, 2, length(v) - 2) ; gsub(/\047\047/, "\047", v) }
      else if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2) }
      print v ; exit
    }' "$MSGS"
}

msg() {
  _t=$(msg_str "$1")
  [ -n "$_t" ] || return 1
  shift
  if [ "$#" -eq 0 ]; then printf '%s' "$_t"; else printf "$_t" "$@"; fi
}
