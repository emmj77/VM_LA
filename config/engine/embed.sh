#!/bin/sh
# embed.sh - THE EMBEDDER. The bi-encoder that turns a text into a vector, loaded once.
#
# WHY. The memory table (config/memory.db) carries two lines per exchange, and the LAW says the
# TABLE IS READ UNDER A QUESTION, never under a word (1713) : a grep does not replace a question
# (1714 promised the model that would do it). This brick is that promise kept. It is the OPPOSITE
# object to the reranker, and the two must not be confused :
#   the RERANKER (bge-reranker-v2-m3, port 8095) reads the QUESTION AND THE CANDIDATE TOGETHER and
#     scores the pair ; it ranks a SHORT list (the tour's tools). A bi-encoder failed there.
#   the EMBEDDER reads ONE text at a time and returns a VECTOR ; it is what makes a whole base
#     searchable, because the vectors are computed ONCE and kept (the `vec` column of the table).
#
# THE MODEL : harrier-oss-v1-270M (Microsoft, MIT), 640 dimensions, 32768 tokens of context, Q8_0.
# DECIDED BY MEASURE, never by taste (1517/1518 : quality is measured, with its date).
#   17/10/2026, this machine (Xeon W-2123, 4 cores / 8 threads), 18 distinct documents and 19
#   French questions, one server at a time, each candidate under ITS OWN contract :
#     harrier-oss-v1-270M    Q8 last  292 Mo  top-1 12/19  top-3 17/19  RR 0.756  51 ms/doc  RSS 621 Mo
#     embeddinggemma-300m    Q8 mean  329 Mo  top-1 12/19  top-3 16/19  RR 0.762  31 ms/doc  RSS 598 Mo
#     granite-embedding-107m Q8 cls   121 Mo  top-1 10/19  top-3 16/19  RR 0.697  22 ms/doc  RSS 574 Mo
#     granite-embedding-97M-r2 Q8 cls 115 Mo  top-1 10/19  top-3 13/19  RR 0.653  24 ms/doc  RSS 509 Mo
#     multilingual-e5-small  Q8 mean  132 Mo  top-1  3/19  top-3  4/19  RR 0.293  19 ms/doc  RSS 493 Mo
#   Locally the two first are TIED, and 19 questions cannot separate them. What separates them is
#   the PUBLISHED multilingual suite, which is our exact task (French, two-line summaries) :
#   MTEB (Multilingual, v2) mean, harrier 0.6655 (15th of 86) against gemma 0.6115 (29th of 86).
#   Add the licence (MIT against the Gemma terms) and the context (32768 against 2048) : harrier.
#   The four others left ~/LLM_GGUF on 17/10/2026, on MOUSSA's word : they are in the trash,
#   recoverable, and nothing here needs them.
#
# THE CONTRACT (the model's, not a preference). The QUERY side carries ONE instruction ; the
# DOCUMENT side carries NOTHING :
#     query    : "Instruct: Given a web search query, retrieve relevant passages that answer the
#                 query" then a newline, "Query: ", then the question.
#     document : the bare text.
# That asymmetry is what the model was trained on. The DOCUMENT side is written by the COMPACTEUR
# (session_note.sh), which carries NO prefix. The QUERY side is written by the CALLER -- the tool
# line in config/la_tools.yaml : THE MODEL NEVER FILLS WHAT THE HARNESS KNOWS FILL (1513). This
# resident applies no prefix of its own : it reads ONE text as it comes, and that is all it does.
# The pooling is the model's own (LAST token), and the vectors come out L2-normalised.
#
# CPU BY DESIGN (MOUSSA): a hard CORE CAP (taskset), never the whole machine. The reranker holds
# 0-5 and sits on the critical path of tool selection ; the embedder takes 6-7, because its calls
# are short bursts that follow the reply (the compacting writer) or a search. The GPU belongs to
# the heavy one : here NEVER -ngl.
#
# MODES : start | stop | status | run | help
#   run     in the foreground, for systemd. Never returns.
#   start   detached, writes its mark (work/embed.pid) and its log (work/embed.log).
#   stop    kills the pid of its mark. NEVER by pattern: only what we placed is killed.
#   status  probes /health and says whether the embedder answers, and on which port.
#
# INPUT (env)
#   LA_EMBED_PORT      default 8096
#   LA_EMBED_MODEL     default harrier-oss-v1-270M-Q8_0.gguf
#   LA_EMBED_GGUF      default /home/moussa/LLM_GGUF   the models folder
#   LA_EMBED_THREADS   default 2
#   LA_EMBED_CORES     default 6-7   THE CPU CAP
#   LA_EMBED_CTX       default 512   a summary is two lines : 512 tokens is already roomy
#   LA_EMBED_POOLING   default last  the model's OWN pooling, never a guess
#
# OUTPUT : work/embed.log, work/embed.pid

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
W="$ROOT/work"
BIN=${LA_LLAMA_BIN:-/home/moussa/Applications/llama.cpp/build_cuda/bin/llama-server}
GGUF=${LA_EMBED_GGUF:-/home/moussa/LLM_GGUF}
MODEL=${LA_EMBED_MODEL:-harrier-oss-v1-270M-Q8_0.gguf}
HOST=${LA_EMBED_HOST:-127.0.0.1}
PORT=${LA_EMBED_PORT:-8096}
THREADS=${LA_EMBED_THREADS:-2}
CORES=${LA_EMBED_CORES:-6-7}
CTX=${LA_EMBED_CTX:-512}
POOLING=${LA_EMBED_POOLING:-last}
PID_FILE="$W/embed.pid"
LOGF="$W/embed.log"
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-$(dirname -- "$BIN")}
# 100 % CPU, et PAS SEULEMENT pour le calcul : aucune carte ne doit meme etre VISIBLE.
# Sans cette ligne, ce binaire (compile CUDA) ouvre un contexte de calcul sur les DEUX cartes
# et y retient de la VRAM pour un modele qui calcule sur le processeur. Mesure du 17/10 :
# 788 Mo sur la P2200 par le seul embedder, 912 Mo au total sur la P2200 et 856 Mo sur la 3060
# -- pour les trois residents reunis. Un contexte de calcul vide ne sert a rien ici.
export CUDA_VISIBLE_DEVICES=""

[ -x "$BIN" ] || { echo "refused: llama-server is missing ($BIN)" >&2 ; exit 1 ; }
[ -f "$GGUF/$MODEL" ] || { echo "refused: the embedding model is missing ($GGUF/$MODEL)" >&2 ; exit 1 ; }

. "$HERE/lib.sh"
LABEL="embed" ; HEALTH=health ; WD=.
service_ctl "${1:-help}" taskset -c "$CORES" "$BIN" -m "$GGUF/$MODEL" --embedding --pooling "$POOLING" --embd-normalize 2 --host "$HOST" --port "$PORT" -t "$THREADS" --no-warmup -c "$CTX"
