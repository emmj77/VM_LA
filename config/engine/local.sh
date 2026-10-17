#!/bin/sh
# local.sh - THE LOCAL MODEL. The small model that SUMMARIZES (compaction), loaded once.
#
# WHY THIS NAME. summary.sh and session_note.sh ask a local model for a SUMMARY, on the CPU.
# Without it, no session summary. Here the project's model stays UP on 127.0.0.1:8088 -- a
# service, not a call.
#
# THE MODEL : a SINGLE place names it -- LA_LOCAL_MODEL (default the LFM2.5-1.2B, kept in
# ~/LLM_GGUF). Changing model = one word. The GPU belongs to the heavy one : here NEVER -ngl.
#
# MODES : start | stop | status | run | help
#   run     in the foreground, for systemd. Never returns.
#   start   detached, writes its mark (work/local.pid) and its log (work/local.log).
#   stop    kills the pid of its mark. NEVER by pattern: only what we placed is killed.
#   status  probes /health and says whether the model answers, and on which port.
#
# INPUT (env)
#   LA_LOCAL_PORT     default 8088
#   LA_LOCAL_MODEL    default LFM2.5-1.2B-Instruct-Q4_K_M.gguf
#   LA_LOCAL_GGUF     default /home/moussa/LLM_GGUF   the models folder
#   LA_LOCAL_THREADS  default 8
#   LA_LOCAL_CTX      default 12288
#   LA_LOCAL_NGL      default 0    the small model runs on the CPU
#
# OUTPUT : work/local.log, work/local.pid

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
W="$ROOT/work"
BIN=${LA_LLAMA_BIN:-/home/moussa/Applications/llama.cpp/build_cuda/bin/llama-server}
GGUF=${LA_LOCAL_GGUF:-/home/moussa/LLM_GGUF}
MODEL=${LA_LOCAL_MODEL:-LFM2.5-1.2B-Instruct-Q4_K_M.gguf}
HOST=${LA_LOCAL_HOST:-127.0.0.1}
PORT=${LA_LOCAL_PORT:-8088}
THREADS=${LA_LOCAL_THREADS:-8}
CTX=${LA_LOCAL_CTX:-12288}
NGL=${LA_LOCAL_NGL:-0}
PID_FILE="$W/local.pid"
LOGF="$W/local.log"
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-$(dirname -- "$BIN")}
# 100 % CPU, et PAS SEULEMENT pour le calcul : aucune carte ne doit meme etre VISIBLE.
# Sans cette ligne, ce binaire (compile CUDA) ouvre un contexte de calcul sur les DEUX cartes
# et y retient de la VRAM pour un modele qui calcule sur le processeur. Mesure du 17/10 :
# 788 Mo sur la P2200 par le seul embedder, 912 Mo au total sur la P2200 et 856 Mo sur la 3060
# -- pour les trois residents reunis. Un contexte de calcul vide ne sert a rien ici.
export CUDA_VISIBLE_DEVICES=""

[ -x "$BIN" ] || { echo "refused: llama-server is missing ($BIN)" >&2 ; exit 1 ; }
[ -f "$GGUF/$MODEL" ] || { echo "refused: the local model is missing ($GGUF/$MODEL)" >&2 ; exit 1 ; }

. "$HERE/lib.sh"
LABEL="local" ; HEALTH=health ; WD=.
service_ctl "${1:-help}" "$BIN" -m "$GGUF/$MODEL" --host "$HOST" --port "$PORT" -ngl "$NGL" -t "$THREADS" --no-warmup -c "$CTX" --parallel 1
