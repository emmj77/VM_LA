#!/bin/sh
# board.sh — LA PORTE DU PANNEAU. Le panneau lui-meme est config/py/board.py (rich).
# Ici il n'y a que la porte : une seule chose a retenir, le chemin. Le panneau se lance par cette
# brique comme les residents se lancent par les leurs (embed.sh, asr.sh...).
#
#   board.sh              le panneau vivant (Ctrl-C pour sortir)
#   board.sh --once       une passe, puis il sort ; le code de retour est le nombre de defauts
#   board.sh --watch 5    redessine toutes les 5 secondes
LC_ALL=C
export LC_ALL
HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
PANNEAU="$HERE/../py/board.py"
[ -f "$PANNEAU" ] || { printf 'board: le panneau est absent (%s)\n' "$PANNEAU" >&2 ; exit 2 ; }
exec /usr/bin/python3 "$PANNEAU" "$@"
