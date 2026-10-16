#!/bin/sh
# tts.sh - LA VOIX. Le moteur qui DIT, charge une seule fois.
#
# POURQUOI CE NOM. Le tool `speak` disait une phrase et rendait un fichier : c'etait un APPEL,
# et il rechargeait magpie a chaque phrase -- huit secondes pour trois secondes de son, et trois
# minutes pour une reply longue. Ici c'est l'inverse : un moteur qui reste DEBOUT, garde sa voix
# en memoire, et repond en quelques dixiemes de seconde quand le modele est charge. Un service,
# pas un appel.
#
# CE QUE CA CHANGE POUR LES AUTRES : rien, volontairement. Le service imprime EXACTEMENT la ligne
# que l'appel rendait avant (`speech : work/....wav (N Ko, T s)`) et ecrit dans work/ : le pont,
# l'appli et la table des tools n'ont pas a savoir que la voix est devenue permanente.
#
# MODES : start | stop | status | run | help
#   run     au premier plan, pour systemd. Ne rend jamais la main.
#   start   detache, ecrit sa marque (work/tts.pid) et son journal (work/tts.log).
#   stop    arrete le pid de sa marque. JAMAIS par motif : on ne tue que ce qu'on a pose.
#   status  interroge /health et dit si la voix repond, et sur quel port.
#
# ENTREE (env)
#   LA_TTS_PORT     defaut 8090
#   LA_TTS_SID      defaut 1      la voix dans le modele (0 = jessica, 1 = pierre)
#   LA_TTS_THREADS  defaut 8
#
# SORTIE : work/tts.log, work/tts.pid

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

[ -f "$PROG" ] || { echo "refuse : la voix est introuvable ($PROG)" >&2 ; exit 1 ; }
[ -x "$UV" ] || { echo "refuse : uv est introuvable ($UV) ; la voix ne peut pas charger son module" >&2 ; exit 1 ; }

. "$HERE/lib.sh"
LABEL="la voix" ; HEALTH=health ; WD=.
service_ctl "${1:-help}" "$UV" run --no-project --with sherpa-onnx python3 "$PROG"
