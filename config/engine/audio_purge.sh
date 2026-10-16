#!/bin/sh
# audio_purge.sh - THE AUDIO PURGE. The disk does not fill up in silence.
#
# WHY THIS NAME. All the audio lives in config/audio/ : what GOES OUT (the turn's voice) and what
# COMES IN (the phone's audio). Without a purge, dozens of files pile up every day : the disk
# fills up and nobody sees it. Here we BOUND it : we keep the most recent, throw the rest, and
# never a file younger than LA_PURGE_MIN minutes -- we do not yank a wav from under the phone
# while it is listening to it.
#
# MODES : status | once | help
#   status  what is there, what would leave, and the total used. TOUCHES NOTHING.
#   once    runs the purge. This is what the timer calls.
#
# SETTINGS (env)
#   LA_PURGE_KEEP    default 20    the number of files KEPT (the most recent)
#   LA_PURGE_MIN     default 10    never younger than this, in minutes
#   LA_PURGE_MAX_MO  default 200   the tolerated total, in MB : beyond it, the oldest are thrown
#   LA_PURGE_TYPES   default "speech-*.wav voice-*"   what is purged (glob, space-separated)
#
# THE TRASH, NOT THE AXE. The house rule: `gio trash`, never `rm -rf`. What leaves stays
# recoverable ; the trash empties later by its own rules.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
AUDIO="$ROOT/config/audio"

KEEP=${LA_PURGE_KEEP:-20}
MIN=${LA_PURGE_MIN:-10}
MAXMO=${LA_PURGE_MAX_MO:-200}
TYPES=${LA_PURGE_TYPES:-"speech-*.wav voice-*"}

[ -d "$AUDIO" ] || { echo "refused: the audio folder is missing ($AUDIO)" >&2 ; exit 1 ; }

# THE LIST, FROM NEWEST TO OLDEST, over only the house's files (never a neighbour's).
list() {
  for T in $TYPES; do
    find "$AUDIO" -maxdepth 1 -type f -name "$T" -printf '%T@ %p\n' 2>/dev/null
  done | sort -rn | awk '{ $1=""; sub(/^ /,""); print }'
}

total_mb() { du -sm "$AUDIO" 2>/dev/null | cut -f1; }

# WHAT LEAVES : everything beyond the KEEP most recent, provided it has the minimum age.
# $1 = 1 to act, 0 to only say.
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
    # THE SIZE CEILING. Even under KEEP files, one file can be huge : if the total exceeds
    # MAXMO, we keep throwing, from oldest to newest, never below MIN minutes.
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
