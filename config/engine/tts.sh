#!/usr/bin/dash
# french in code is forbidden

set -u

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
W="$STATE"   # l etat du harnais, resolu par lib.sh depuis la_config (paths.state)
PROG="$ROOT/config/programs/tts_daemon.py"
UV=${LA_UV:-$(conf_str tts uv)}
[ -n "$UV" ] || { echo "la_config : tts.uv manque" >&2; exit 1; }

export UV_CACHE_DIR=${UV_CACHE_DIR:-$(conf_str tts cache)}
export LA_ROOT=${LA_ROOT:-$ROOT}
export LA_TTS_PORT=${LA_TTS_PORT:-$(conf_num tts port 8090)}
export LA_TTS_SID=${LA_TTS_SID:-$(conf_num tts sid 1)}
export LA_TTS_THREADS=${LA_TTS_THREADS:-$(conf_num tts threads 8)}

PORT="$LA_TTS_PORT"
PID_FILE="$W/tts.pid"
LOGF="$W/tts.log"

[ -f "$PROG" ] || { echo "refused: the voice is missing ($PROG)" >&2 ; exit 1 ; }
[ -x "$UV" ] || { echo "refused: uv is missing ($UV) ; the voice cannot load its module" >&2 ; exit 1 ; }

LABEL="tts" ; HEALTH=health ; WD=.
service_ctl "${1:-help}" "$UV" run --no-project --with sherpa-onnx python3 "$PROG"
