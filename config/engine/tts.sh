#!/bin/sh
# tts.sh - THE VOICE. The engine that SAYS, loaded once.
#
# WHY THIS NAME. The `speak` tool said a sentence and returned a file: it was a CALL, and it
# reloaded magpie on every sentence -- eight seconds for three seconds of sound, and three
# minutes for a long reply. Here it is the reverse: an engine that stays UP, keeps its voice in
# memory, and answers in a few tenths of a second once the model is loaded. A service, not a call.
#
# WHAT IT CHANGES FOR OTHERS : nothing, on purpose. The service prints EXACTLY the line the call
# used to return (`speech : work/....wav (N Ko, T s)`) and writes into work/ : the bridge, the
# app and the tool table do not have to know the voice became permanent.
#
# MODES : start | stop | status | run | help
#   run     in the foreground, for systemd. Never returns.
#   start   detached, writes its mark (work/tts.pid) and its log (work/tts.log).
#   stop    kills the pid of its mark. NEVER by pattern: only what we placed is killed.
#   status  probes /health and says whether the voice answers, and on which port.
#
# INPUT (env)
#   LA_TTS_PORT     default 8090
#   LA_TTS_SID      default 1      the voice in the model (0 = jessica, 1 = pierre)
#   LA_TTS_THREADS  default 8
#
# OUTPUT : work/tts.log, work/tts.pid

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
W="$ROOT/work"
PROG="$ROOT/config/py/tts_daemon.py"
UV=${LA_UV:-/home/moussa/.local/bin/uv}

export UV_CACHE_DIR=${UV_CACHE_DIR:-/home/moussa/.cache/uv}
export LA_ROOT=${LA_ROOT:-$ROOT}
export LA_TTS_PORT=${LA_TTS_PORT:-8090}
export LA_TTS_SID=${LA_TTS_SID:-1}
export LA_TTS_THREADS=${LA_TTS_THREADS:-8}

PORT="$LA_TTS_PORT"
PID_FILE="$W/tts.pid"
LOGF="$W/tts.log"

[ -f "$PROG" ] || { echo "refused: the voice is missing ($PROG)" >&2 ; exit 1 ; }
[ -x "$UV" ] || { echo "refused: uv is missing ($UV) ; the voice cannot load its module" >&2 ; exit 1 ; }

. "$HERE/lib.sh"
LABEL="tts" ; HEALTH=health ; WD=.
service_ctl "${1:-help}" "$UV" run --no-project --with sherpa-onnx python3 "$PROG"
