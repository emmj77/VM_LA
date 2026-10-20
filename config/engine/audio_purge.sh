#!/usr/bin/dash
# french in code is forbidden

set -u

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
AUDIO="$ROOT/config/audio"

KEEP=${LA_PURGE_KEEP:-$(conf_num purge keep 20)}
MIN=${LA_PURGE_MIN:-$(conf_num purge min_minutes 10)}
MAXMO=${LA_PURGE_MAX_MO:-$(conf_num purge max_mb 200)}
TYPES=${LA_PURGE_TYPES:-"speech-*.wav voice-*"}

[ -d "$AUDIO" ] || { echo "refused: the audio folder is missing ($AUDIO)" >&2 ; exit 1 ; }

list() {
  for T in $TYPES; do
    find "$AUDIO" -maxdepth 1 -type f -name "$T" -printf '%T@ %p\n' 2>/dev/null
  done | sort -rn | awk '{ $1=""; sub(/^ /,""); print }'
}

total_mb() { du -sm "$AUDIO" 2>/dev/null | cut -f1; }

leaving() {
  i=0
  list | while IFS= read -r F; do
    i=$((i+1))
    [ "$i" -le "$KEEP" ] && continue
    find "$F" -maxdepth 0 -mmin +"$MIN" >/dev/null 2>&1 || continue
    printf '%s\n' "$F"
  done
}

case "${1:-help}" in
  status)
    N=$(list | wc -l)
    P=$(leaving | wc -l)
    echo "audio : $N file(s), $(total_mb) MB under $AUDIO"
    echo "keep : the $KEEP most recent, and nothing younger than $MIN min (tolerated total $MAXMO MB)"
    echo "would leave at the next purge : $P"
    leaving | sed 's|^.*/|    |'
    ;;
  once)
    N=$(list | wc -l)
    if [ "$N" -eq 0 ]; then echo "audio : nothing to purge" ; exit 0 ; fi
    T=0 ; F=0
    leaving > "${TMPDIR:-/tmp}/purge.$$" || true
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if gio trash "$f" 2>/dev/null; then T=$((T+1)) ; else F=$((F+1)) ; fi
    done < "${TMPDIR:-/tmp}/purge.$$"
    rm -f "${TMPDIR:-/tmp}/purge.$$"
    while [ "$(total_mb)" -gt "$MAXMO" ]; do
      V=$(list | tail -n 1)
      [ -n "$V" ] || break
      find "$V" -maxdepth 0 -mmin +"$MIN" >/dev/null 2>&1 || break
      gio trash "$V" 2>/dev/null && T=$((T+1)) || { F=$((F+1)) ; break ; }
    done
    echo "purge : $T to the trash, $F failed ; $(list | wc -l) file(s) left, $(total_mb) MB"
    ;;
  *)
    echo "modes : status | once | help"
    ;;
esac
