#!/bin/sh
# local.sh - LE MODELE LOCAL. Le petit modele qui RESUME (la compaction), charge une seule fois.
#
# POURQUOI CE NOM. summary.sh et session_note.sh demandent un RESUME a un modele local, sur le
# CPU. Sans lui, pas de resume de session. Ici le modele du projet reste DEBOUT sur
# 127.0.0.1:8088 -- un service, pas un appel.
#
# LE MODELE : UN SEUL endroit le nomme -- LA_LOCAL_MODEL (defaut le LFM2.5-1.2B, pose dans
# ~/LLM_GGUF). Changer de modele = un mot. Le GPU appartient au lourd : ici JAMAIS de -ngl.
#
# MODES : start | stop | status | run | help
#   run     au premier plan, pour systemd. Ne rend jamais la main.
#   start   detache, ecrit sa marque (work/local.pid) et son journal (work/local.log).
#   stop    arrete le pid de sa marque. JAMAIS par motif : on ne tue que ce qu'on a pose.
#   status  interroge /health et dit si le modele repond, et sur quel port.
#
# ENTREE (env)
#   LA_LOCAL_PORT     defaut 8088
#   LA_LOCAL_MODEL    defaut LFM2.5-1.2B-Instruct-Q4_K_M.gguf
#   LA_LOCAL_GGUF     defaut /home/moussa/LLM_GGUF   le dossier des modeles
#   LA_LOCAL_THREADS  defaut 8
#   LA_LOCAL_CTX      defaut 12288
#   LA_LOCAL_NGL      defaut 0    le petit modele tourne sur le CPU
#
# SORTIE : work/local.log, work/local.pid

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

[ -x "$BIN" ] || { echo "refuse : llama-server est introuvable ($BIN)" >&2 ; exit 1 ; }
[ -f "$GGUF/$MODEL" ] || { echo "refuse : le modele local est introuvable ($GGUF/$MODEL)" >&2 ; exit 1 ; }

case "${1:-help}" in
  run)
    exec "$BIN" -m "$GGUF/$MODEL" --host "$HOST" --port "$PORT" -ngl "$NGL" -t "$THREADS" --no-warmup -c "$CTX" --parallel 1
    ;;
  start)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "le modele local tourne deja (pid $(cat "$PID_FILE"), port $PORT)"
      exit 0
    fi
    nohup "$BIN" -m "$GGUF/$MODEL" --host "$HOST" --port "$PORT" -ngl "$NGL" -t "$THREADS" --no-warmup -c "$CTX" --parallel 1 >> "$LOGF" 2>&1 &
    echo $! > "$PID_FILE"
    echo "modele local lance (pid $!, port $PORT, modele $MODEL, journal $LOGF)"
    ;;
  stop)
    if [ ! -f "$PID_FILE" ]; then echo "le modele local ne tourne pas : aucune marque" ; exit 0 ; fi
    P=$(cat "$PID_FILE")
    if kill "$P" 2>/dev/null; then echo "modele local arrete (pid $P)" ; else echo "le modele local ne repondait plus (pid $P)" ; fi
    rm -f "$PID_FILE"
    ;;
  status)
    R=$(curl -s --max-time 3 "http://127.0.0.1:$PORT/health" 2>/dev/null)
    if [ -n "$R" ]; then echo "modele local debout sur 127.0.0.1:$PORT : $R" ; else echo "modele local muet sur 127.0.0.1:$PORT" ; exit 1 ; fi
    ;;
  *)
    echo "modes : start | stop | status | run | help"
    ;;
esac
