#!/usr/bin/dash
# french in code is forbidden

set -u

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
W="$STATE"   # l etat du harnais, resolu par lib.sh depuis la_config (paths.state)
ROOT_MODELS=${LA_MODELS:-$(conf_str asr root)}
[ -n "$ROOT_MODELS" ] || { printf '%s\n' "$(msg config_key_missing asr.root)" >&2; exit 1; }
CLI=${LA_ASR_CLI:-$ROOT_MODELS/$(conf_str asr cli build/cpu-server/bin/nemo-speech)}
MODEL=${LA_ASR_MODEL:-$(conf_str asr model models/parakeet-tdt-0.6b-v3.q8_0.gguf)}
PORT=${LA_ASR_PORT:-$(conf_num asr port 8080)}
THREADS=${LA_ASR_THREADS:-$(conf_num asr threads 4)}
HOST=${LA_ASR_HOST:-$(conf_str asr host 127.0.0.1)}
PID_FILE="$W/asr.pid"
LOGF="$W/asr.log"

[ -x "$CLI" ] || { echo "refused: the nemo-speech engine is missing ($CLI)" >&2 ; exit 1 ; }
[ -f "$ROOT_MODELS/$MODEL" ] || { echo "refused: the ear's model is missing ($MODEL)" >&2 ; exit 1 ; }

LABEL="asr" ; HEALTH=ready ; WD="$ROOT_MODELS"
service_ctl "${1:-help}" "$CLI" serve --asr-model "$MODEL" --host "$HOST" --port "$PORT" --no-ui --threads "$THREADS"
