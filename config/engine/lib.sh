#!/bin/sh
# lib.sh — THE SHARED LIBRARY OF THE BRICKS (config/engine/).
#
# CONVENTION: the whole machinery is in ENGLISH — identifiers, resource names, comments
# and messages.
#
# Every brick sources it first, AFTER $ROOT is set:
#   . "$HERE/lib.sh"
# It carries what the bricks share, ONCE: the timestamp (ts), the single resolution of
# the ACTIVE SKILL (active_skill), the reading of the PERMANENT category
# (permanent_section), the reading of the TABLE (table_ids, table_block) and the shared
# trunk of the detached services (service_ctl).

# --- THE TIMESTAMP -------------------------------------------------------------
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- THE ACTIVE SKILL : SINGLE resolution --------------------------------------
# Reads $ROOT/skills/.active (first line = the active skill's folder name), checks that a
# REAL folder carries it under skills/ (with a skill.yaml), otherwise falls back to `la`
# and SAYS so on stderr. A name never leaves skills/ (refuses / and ..). Never a link.
# Sets: NAME (the name) and SKILL (the path of its skill.yaml).
active_skill() {
  SKILLS_DIR="$ROOT/skills"
  ACTIVE_FILE="$SKILLS_DIR/.active"
  NAME=
  if [ -L "$ACTIVE_FILE" ]; then
    printf 'skills: the state file is a LINK (%s) ; links are forbidden ; NO skill is active\n' "$ACTIVE_FILE" >&2
  elif [ ! -f "$ACTIVE_FILE" ]; then
    printf 'skills: the state file is MISSING (%s) ; NO skill is active\n' "$ACTIVE_FILE" >&2
  else
    NAME=$(sed -n '1p' "$ACTIVE_FILE" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$NAME" in
      '') printf 'skills: the state file is EMPTY (%s) ; NO skill is active\n' "$ACTIVE_FILE" >&2 ; NAME= ;;
      */*|*..*) printf 'skills: skill NAME REFUSED (%s) ; a name carries no / nor .. and never leaves skills/ ; NO skill is active\n' "$NAME" >&2 ; NAME= ;;
      *) [ -d "$SKILLS_DIR/$NAME" ] && [ -f "$SKILLS_DIR/$NAME/skill.yaml" ] || { printf 'skills: skill %s has NO DIR under skills/ ; NO skill is active\n' "$NAME" >&2 ; NAME= ; } ;;
    esac
  fi
  # NO PHANTOM FALLBACK : the old fallback named `la`, a skill that no longer exists (the canon
  # moved under projects/, 17/10) : it made every brick read a skill that is not there, and the
  # doctor then hunted a spec under a folder that does not exist. A missing .active is SAID, NAME
  # stays EMPTY, and the CALLER refuses by naming it (engine.sh, loop.sh scope_build, doctor.sh).
  SKILL=
  [ -n "$NAME" ] && SKILL="$SKILLS_DIR/$NAME/skill.yaml"
}

# --- THE CANON : SINGLE resolution ---------------------------------------------
# THE CANON IS THE SPEC OF THE ACTIVE PROJECT (the law : `LE CANON EST spec.yaml`). ONE place
# resolves it, and the engine, the doctor and write_spec all go through it : two resolutions of
# the same thing diverge in silence.
#   1. the ACTIVE PROJECT carries a spec.yaml        -> projects/<name>/spec.yaml
#   2. no project, the ACTIVE SKILL carries one      -> skills/<name>/spec.yaml
#   3. otherwise                                    -> projects/la/spec.yaml, LA itself
# Sets: SPEC (the path, EMPTY when nothing carries a canon) and CANON_WHY (which of the three, so
# a refusal NAMES the reason). Call it AFTER active_skill : it reads $SKILL.
canon_path() {
  SPEC=
  CANON_WHY=
  active_project
  PD="$ROOT/projects"
  if [ -n "$PNAME" ]; then
    # A LOADED PROJECT CARRIES ITS OWN CANON : we never lend it the canon of LA (a project that
    # reads another project's architecture is a project without law). Missing -> NAMED.
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

# --- THE ACTIVE PROJECT : SINGLE resolution ------------------------------------
# Reads $ROOT/projects/.active (first line = the active project's folder name),
# checks that a REAL folder carries it under projects/ (with a project.yml),
# otherwise falls back to NO project and stays quiet: a project is OPTIONAL
# (unlike the skill, which always resolves to one). A name never leaves
# projects/ (refuses / and ..). Never a link.
# Sets: PNAME (the name, empty when none) and PROJECT (the path of its project.yml).
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
      */*|*..*) printf 'projects: project NAME REFUSED (%s) ; a name carries no / nor .. and never leaves projects/\n' "$PNAME" >&2 ; PNAME= ;;
      *) [ -d "$PROJECTS_DIR/$PNAME" ] && [ -f "$PROJECTS_DIR/$PNAME/project.yml" ] || { printf 'projects: project %s has NO DIR under projects/ ; ignored\n' "$PNAME" >&2 ; PNAME= ; } ;;
    esac
  fi
  PROJECT=
  [ -n "$PNAME" ] && PROJECT="$PROJECTS_DIR/$PNAME/project.yml"
}

# project_skills — the SKILLS of a project file ($1), one name per line ; empty = wide.
# The project ENVELOPES the skills: this list is the set the model may LOAD.
project_skills() {
  [ -f "${1:-}" ] || return 0
  sed -n '/^SKILLS:/,/^[^[:space:]]/p' "$1" \
    | sed -n 's/^[[:space:]]*-[[:space:]]*//p; s/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
    | sed -e 's/^"//' -e 's/"$//' | grep -v '^$'
}

# --- THE PERMANENT CATEGORY ----------------------------------------------------
# Reads the `permanent:` section of the CONFIG ($1), one entry per line, indentation and
# quotes stripped.
permanent_section() {
  CONF=${1:-}
  [ -n "$CONF" ] && [ -f "$CONF" ] || return 0
  sed -n '/^permanent:/,/^[^[:space:]]/p' "$CONF" \
    | sed -n 's/^[[:space:]]*-[[:space:]]*//p' \
    | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' | grep -v '^$'
}

# --- THE TABLE -----------------------------------------------------------------
# table_ids — every id of the table ($1), in order.
table_ids() {
  grep -n '^  - id: ' "$1" | sed 's/^[0-9]*:  - id:[[:space:]]*//' | tr -d ' '
}
# table_block — the block of id ($2) in the table ($1) ; empty + rc=1 when absent.
table_block() {
  TB_TABLE=${1:-}
  TB_ID=${2:-}
  [ -f "$TB_TABLE" ] || return 1
  TB_START=$(grep -n "^  - id: $TB_ID[[:space:]]*\$" "$TB_TABLE" 2>/dev/null | head -n 1 | cut -d: -f1)
  [ -n "$TB_START" ] || return 1
  TB_END=$(grep -n '^  - id: ' "$TB_TABLE" | cut -d: -f1 | while IFS= read -r n; do
        [ "$n" -gt "$TB_START" ] && { printf '%s\n' "$n"; break; }
      done)
  [ -n "$TB_END" ] || TB_END=$(( $(wc -l < "$TB_TABLE") + 1 ))
  sed -n "${TB_START},$((TB_END - 1))p" "$TB_TABLE"
}

# --- THE DETACHED SERVICES : the shared trunk ----------------------------------
# port_busy — $1 = a port : true when it is already bound on the machine.
port_busy() {
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$1\$" && return 0
  curl -s --max-time 2 "http://127.0.0.1:$1/" >/dev/null 2>&1 && return 0
  return 1
}
# The caller sets LABEL, PID_FILE, LOGF, PORT, HEALTH and WD (the launch dir),
# then: service_ctl "${1:-help}" <the background command...>
#   run    in the foreground (systemd), from WD. Never returns.
#   start  detaches the command, writes its mark (PID_FILE).
#   stop   kills the pid of its mark. NEVER by pattern: only what we placed is killed.
#   status probes HEALTH on the port.
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
      # UN RESIDENT EST UN ARBRE (uv -> python3 -> sa voix, ou la CLI -> son moteur), PAS UN
      # PID : setsid en fait UN SEUL GROUPE, et stop tue le groupe. Sans lui, l arret ne tuait
      # que la tete et les enfants s echappaient (banc des residents, verdict R4).
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
      # LE BUILTIN kill DE dash REFUSE `-- -PID` (« Illegal number: - ») : c est le kill
      # EXTERNE qui tue le GROUPE. Sans lui, on ne tuait que la tete, et les enfants du
      # resident restaient vivants (banc des residents, verdict R4 rouge).
      SC_TUE=0
      [ -x /bin/kill ] && /bin/kill -TERM -- "-$SC_P" 2>/dev/null && SC_TUE=1
      [ "$SC_TUE" = 0 ] && [ -x /usr/bin/kill ] && /usr/bin/kill -TERM -- "-$SC_P" 2>/dev/null && SC_TUE=1
      [ "$SC_TUE" = 0 ] && kill -TERM "$SC_P" 2>/dev/null
      SC_I=0
      while kill -0 "$SC_P" 2>/dev/null && [ "$SC_I" -lt 50 ]; do sleep 0.1; SC_I=$((SC_I + 1)); done
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
      SC_R=$(curl -s --max-time 3 "http://127.0.0.1:$PORT/$HEALTH" 2>/dev/null)
      if [ -n "$SC_R" ]; then
        if [ -f "$PID_FILE" ]; then echo "$LABEL up on 127.0.0.1:$PORT : $SC_R" ;
        else echo "$LABEL up on 127.0.0.1:$PORT WITHOUT a mark: started outside this protocol" ; fi
      else echo "$LABEL silent on 127.0.0.1:$PORT" ; exit 1 ; fi
      ;;
    *) echo "modes: start | stop | status | run | help" ;;
  esac
}
