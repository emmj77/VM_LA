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
    printf 'skills: the state file is a LINK (%s) ; links are forbidden ; falling back to la\n' "$ACTIVE_FILE" >&2
  elif [ ! -f "$ACTIVE_FILE" ]; then
    printf 'skills: the state file is MISSING (%s) ; falling back to la\n' "$ACTIVE_FILE" >&2
  else
    NAME=$(sed -n '1p' "$ACTIVE_FILE" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$NAME" in
      '') printf 'skills: the state file is EMPTY (%s) ; falling back to la\n' "$ACTIVE_FILE" >&2 ; NAME= ;;
      */*|*..*) printf 'skills: skill NAME REFUSED (%s) ; a name carries no / nor .. and never leaves skills/ ; falling back to la\n' "$NAME" >&2 ; NAME= ;;
      *) [ -d "$SKILLS_DIR/$NAME" ] && [ -f "$SKILLS_DIR/$NAME/skill.yaml" ] || { printf 'skills: skill %s has NO DIR under skills/ ; falling back to la\n' "$NAME" >&2 ; NAME= ; } ;;
    esac
  fi
  [ -n "$NAME" ] || NAME=la
  SKILL="$SKILLS_DIR/$NAME/skill.yaml"
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
      ( cd "$WD" && nohup "$@" >> "$LOGF" 2>&1 & echo $! > "$PID_FILE" )
      echo "$LABEL started (pid $(cat "$PID_FILE"), port $PORT, log $LOGF)"
      ;;
    stop)
      if [ ! -f "$PID_FILE" ]; then echo "$LABEL is not running: no mark" ; exit 0 ; fi
      SC_P=$(cat "$PID_FILE")
      if kill "$SC_P" 2>/dev/null; then echo "$LABEL stopped (pid $SC_P)" ; else echo "$LABEL no longer answered (pid $SC_P)" ; fi
      rm -f "$PID_FILE"
      ;;
    status)
      SC_R=$(curl -s --max-time 3 "http://127.0.0.1:$PORT/$HEALTH" 2>/dev/null)
      if [ -n "$SC_R" ]; then echo "$LABEL up on 127.0.0.1:$PORT : $SC_R" ; else echo "$LABEL silent on 127.0.0.1:$PORT" ; exit 1 ; fi
      ;;
    *) echo "modes: start | stop | status | run | help" ;;
  esac
}
