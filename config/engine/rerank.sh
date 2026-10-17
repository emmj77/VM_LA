#!/bin/sh
# rerank.sh - THE TOOL SELECTOR'S ENGINE. The reranker that RANKS, loaded once.
#
# WHY. The tool selector (rank_share, in loop.sh) must choose among the tools the ACTIVE SKILL
# already preselected -- never the whole table. It hands the request and the candidate list to a
# CROSS-ENCODER (a reranker), which scores each candidate on its own. A bi-encoder
# (e5-small) put the right tool first only 11 times out of 20, in the first 30% of the list
# 11 times out of 20 either. The reranker puts it in the first 30% 20 times out of 20.
# The model: bge-reranker-v2-m3, named by llama.cpp's OWN server documentation
# (tools/server/README.md, POST /reranking : "Requires a reranker model (such as
# bge-reranker-v2-m3) and the --embedding --pooling rank options").
#
# CPU BY DESIGN (MOUSSA): a hard CORE CAP (taskset), never the whole machine, so a tool
# selection starves nothing else. Target: 200 ms per answer -- measured 75 ms median here.
# The GPU belongs to the heavy one : here NEVER -ngl.
#
# MODES : start | stop | status | run | help
#   run     in the foreground, for systemd. Never returns.
#   start   detached, writes its mark (work/rerank.pid) and its log (work/rerank.log).
#   stop    kills the pid of its mark. NEVER by pattern: only what we placed is killed.
#   status  probes /health and says whether the reranker answers, and on which port.
#
# INPUT (env)
#   LA_RERANK_PORT     default 8095
#   LA_RERANK_MODEL    default bge-reranker-v2-m3-Q8_0.gguf
#   LA_RERANK_GGUF     default /home/moussa/LLM_GGUF   the models folder
#   LA_RERANK_THREADS  default 6
#   LA_RERANK_CORES    default 0-5   THE CPU CAP
#   LA_RERANK_CTX      default 1024
#
# OUTPUT : work/rerank.log, work/rerank.pid

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
W="$ROOT/work"
BIN=${LA_LLAMA_BIN:-/home/moussa/Applications/llama.cpp/build_cuda/bin/llama-server}
GGUF=${LA_RERANK_GGUF:-/home/moussa/LLM_GGUF}
MODEL=${LA_RERANK_MODEL:-bge-reranker-v2-m3-Q8_0.gguf}
HOST=${LA_RERANK_HOST:-127.0.0.1}
PORT=${LA_RERANK_PORT:-8095}
THREADS=${LA_RERANK_THREADS:-6}
CORES=${LA_RERANK_CORES:-0-5}
CTX=${LA_RERANK_CTX:-1024}
PID_FILE="$W/rerank.pid"
LOGF="$W/rerank.log"
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-$(dirname -- "$BIN")}

[ -x "$BIN" ] || { echo "refused: llama-server is missing ($BIN)" >&2 ; exit 1 ; }
[ -f "$GGUF/$MODEL" ] || { echo "refused: the reranker model is missing ($GGUF/$MODEL)" >&2 ; exit 1 ; }

. "$HERE/lib.sh"
LABEL="rerank" ; HEALTH=health ; WD=.
service_ctl "${1:-help}" taskset -c "$CORES" "$BIN" -m "$GGUF/$MODEL" --embedding --pooling rank --reranking --host "$HOST" --port "$PORT" -t "$THREADS" --no-warmup -c "$CTX"
