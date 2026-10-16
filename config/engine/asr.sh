#!/bin/sh
# asr.sh - L OREILLE. Le moteur qui ENTEND, charge une seule fois.
#
# POURQUOI CE NOM. Le tool `transcribe` transcrivait un fichier avec le binaire one-shot : chaque
# appel relisait 681 Mo de modele. Ici le modele reste DEBOUT derriere la route HTTP du projet
# nemo-speech (`serve`), et une transcription coute le seul calcul : mesure faite, 809 ms au lieu
# de 1 254 a 1 567 ms, et le modele n'est plus jamais relu.
#
# CE QUE CA CHANGE POUR LES AUTRES : rien. Le service expose la route du PROJET, pas une route a
# nous (`POST /v1/audio/transcriptions`, sous-ensemble OpenAI documente) : le tool y va par curl,
# et c'est tout. Le pont et l'appli ne connaissent que le tool.
#
# MODES : start | stop | status | run | help
#   run     au premier plan, pour systemd. Ne rend jamais la main.
#   start   detache, ecrit sa marque (work/asr.pid) et son journal (work/asr.log).
#   stop    arrete le pid de sa marque. JAMAIS par motif : on ne tue que ce qu'on a pose.
#   status  interroge /ready et dit si l'oreille repond, et sur quel port.
#
# ENTREE (env)
#   LA_ASR_PORT     defaut 8080
#   LA_ASR_THREADS  defaut 4      le pool de requetes du serveur
#   LA_ASR_MODEL    defaut le parakeet du projet
#
# SORTIE : work/asr.log, work/asr.pid

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

[ -x "$CLI" ] || { echo "refuse : le moteur nemo-speech est introuvable ($CLI)" >&2 ; exit 1 ; }
[ -f "$ROOT_MODELS/$MODEL" ] || { echo "refuse : le modele de l oreille est introuvable ($MODEL)" >&2 ; exit 1 ; }

. "$HERE/lib.sh"
LABEL="asr" ; HEALTH=ready ; WD="$ROOT_MODELS"
service_ctl "${1:-help}" "$CLI" serve --asr-model "$MODEL" --host "$HOST" --port "$PORT" --no-ui --threads "$THREADS"
