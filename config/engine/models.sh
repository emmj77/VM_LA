#!/usr/bin/dash
# french in code is forbidden

set -u

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
W="$STATE"   # l etat du harnais, resolu par lib.sh depuis la_config (paths.state)

BIN=$(conf_str llama bin)
DIR=$(conf_str models dir)
PRESET=$(conf_str models preset)
HOST=${LA_MODELS_HOST:-$(conf_str models host 127.0.0.1)}
PORT=${LA_MODELS_PORT:-$(conf_num models port 8091)}
MAX=${LA_MODELS_MAX:-$(conf_num models max 3)}
SLEEP=${LA_MODELS_SLEEP:-$(conf_num models sleep 600)}
THREADS=${LA_MODELS_THREADS:-$(conf_num llama threads 8)}

[ -n "$BIN" ] || { printf '%s\n' "$(msg config_field_empty llama.bin)" >&2 ; exit 1 ; }
[ -x "$BIN" ] || { printf '%s\n' "$(msg binary_missing_bin "$BIN")" >&2 ; exit 1 ; }
[ -n "$DIR" ] || { printf '%s\n' "$(msg config_field_empty models.dir)" >&2 ; exit 1 ; }
[ -d "$DIR" ] || { printf '%s\n' "$(msg dir_missing "$DIR")" >&2 ; exit 1 ; }
[ -n "$PRESET" ] || { printf '%s\n' "$(msg config_field_empty models.preset)" >&2 ; exit 1 ; }
case "$PRESET" in /*) P="$PRESET" ;; *) P="$ROOT/$PRESET" ;; esac
[ -f "$P" ] || { printf '%s\n' "$(msg preset_missing "$P")" >&2 ; exit 1 ; }
case "$MAX" in ''|*[!0-9]*) printf '%s\n' "$(msg not_a_number models.max "$MAX")" >&2 ; exit 1 ;; esac
case "$SLEEP" in ''|*[!0-9]*) printf '%s\n' "$(msg not_a_number models.sleep "$SLEEP")" >&2 ; exit 1 ;; esac

PID_FILE="$W/models.pid"
LOGF="$W/models.log"
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-$(dirname -- "$BIN")}

LABEL="models" ; HEALTH=health ; WD=.
service_ctl "${1:-help}" "$BIN" \
  --models-dir "$DIR" \
  --models-preset "$P" \
  --models-max "$MAX" \
  --sleep-idle-seconds "$SLEEP" \
  --threads "$THREADS" \
  --host "$HOST" --port "$PORT" \
  --no-warmup
