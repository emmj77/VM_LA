#!/bin/sh
# asr.sh - THE EAR. The engine that HEARS, loaded once.
#
# WHY THIS NAME. The `transcribe` tool transcribed a file with the one-shot binary : every call
# re-read 681 MB of model. Here the model stays UP behind the project's HTTP route nemo-speech
# (`serve`), and a transcription costs only the compute : measured, 809 ms instead of 1 254 to
# 1 567 ms, and the model is never re-read.
#
# WHAT IT CHANGES FOR OTHERS : nothing. The service exposes the PROJECT's route, not a route of
# ours (`POST /v1/audio/transcriptions`, documented OpenAI subset) : the tool goes there by curl,
# and that is all. The bridge and the app know only the tool.
#
# MODES : start | stop | status | run | help
#   run     in the foreground, for systemd. Never returns.
#   start   detached, writes its mark (work/asr.pid) and its log (work/asr.log).
#   stop    kills the pid of its mark. NEVER by pattern: only what we placed is killed.
#   status  probes /ready and says whether the ear answers, and on which port.
#
# INPUT (env)
#   LA_ASR_PORT     default 8080
#   LA_ASR_THREADS  default 4      the server's request pool
#   LA_ASR_MODEL    default the project's parakeet
#
# OUTPUT : work/asr.log, work/asr.pid

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
W="$ROOT/work"
ROOT_MODELS=${LA_MODELS:-/home/moussa/Applications/NeMo-Speech.cpp}
CLI=${LA_ASR_CLI:-$ROOT_MODELS/build/cpu-server/bin/nemo-speech}
MODEL=${LA_ASR_MODEL:-models/parakeet-tdt-0.6b-v3.q8_0.gguf}
PORT=${LA_ASR_PORT:-8080}
THREADS=${LA_ASR_THREADS:-4}
HOST=${LA_ASR_HOST:-127.0.0.1}
PID_FILE="$W/asr.pid"
LOGF="$W/asr.log"

[ -x "$CLI" ] || { echo "refused: the nemo-speech engine is missing ($CLI)" >&2 ; exit 1 ; }
[ -f "$ROOT_MODELS/$MODEL" ] || { echo "refused: the ear's model is missing ($MODEL)" >&2 ; exit 1 ; }

. "$HERE/lib.sh"
LABEL="asr" ; HEALTH=ready ; WD="$ROOT_MODELS"
service_ctl "${1:-help}" "$CLI" serve --asr-model "$MODEL" --host "$HOST" --port "$PORT" --no-ui --threads "$THREADS"
