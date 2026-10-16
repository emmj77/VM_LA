#!/bin/sh
# audio_purge.sh - LA PURGE DE L AUDIO. Le disque ne se remplit pas en silence.
#
# POURQUOI CE NOM. Tout l audio vit dans config/audio/ : ce qui SORT (la voix du tour) et ce qui
# ENTRE (l audio du telephone). Sans purge, des dizaines de fichiers par jour s entassent : le
# disque se remplit et personne ne le voit. Ici on BORNE : on garde les plus recents, on jette
# au-dela, et jamais un fichier plus jeune que LA_PURGE_MIN minutes -- on n arrache pas un wav
# sous le nez du telephone pendant qu il l ecoute.
#
# MODES : status | once | help
#   status  ce qui est la, ce qui partirait, et le total occupe. NE TOUCHE A RIEN.
#   once    fait la purge. C est ce que le minuteur appelle.
#
# REGLAGES (env)
#   LA_PURGE_KEEP    defaut 20    le nombre de fichiers GARDES (les plus recents)
#   LA_PURGE_MIN     defaut 10    jamais moins vieux que ca, en minutes
#   LA_PURGE_MAX_MO  defaut 200   le total tolere, en Mo : au-dela, on jette les plus vieux
#   LA_PURGE_TYPES   defaut "speech-*.wav voice-*"   ce qui est purge (glob, separe par des espaces)
#
# LA CORBEILLE, PAS LA HACHE. La regle de la maison : `gio trash`, jamais `rm -rf`. Ce qui part
# reste rattrapable ; la corbeille se vide ensuite selon ses propres regles.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
AUDIO="$ROOT/config/audio"

KEEP=${LA_PURGE_KEEP:-20}
MIN=${LA_PURGE_MIN:-10}
MAXMO=${LA_PURGE_MAX_MO:-200}
TYPES=${LA_PURGE_TYPES:-"speech-*.wav voice-*"}

[ -d "$AUDIO" ] || { echo "refuse : le dossier de l audio est introuvable ($AUDIO)" >&2 ; exit 1 ; }

# LA LISTE, DU PLUS RECENT AU PLUS VIEUX, sur les seuls fichiers de la maison (jamais un voisin).
list() {
  for T in $TYPES; do
    find "$AUDIO" -maxdepth 1 -type f -name "$T" -printf '%T@ %p\n' 2>/dev/null
  done | sort -rn | awk '{ $1=""; sub(/^ /,""); print }'
}

total_mb() { du -sm "$AUDIO" 2>/dev/null | cut -f1; }

# CE QUI PART : tout ce qui depasse les KEEP plus recents, a condition d avoir l age minimum.
# $1 = 1 pour agir, 0 pour seulement dire.
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
    echo "audio : $N fichier(s), $(total_mb) Mo sous $AUDIO"
    echo "garde : les $KEEP plus recents, et rien de plus jeune que $MIN min (total tolere $MAXMO Mo)"
    echo "partiraient a la prochaine purge : $P"
    leaving | sed 's|^.*/|    |'
    ;;
  once)
    N=$(list | wc -l)
    if [ "$N" -eq 0 ]; then echo "audio : rien a purger" ; exit 0 ; fi
    J=0 ; E=0
    leaving > "${TMPDIR:-/tmp}/purge.$$" || true
    while IFS= read -r F; do
      [ -n "$F" ] || continue
      if gio trash "$F" 2>/dev/null; then J=$((J+1)) ; else E=$((E+1)) ; fi
    done < "${TMPDIR:-/tmp}/purge.$$"
    rm -f "${TMPDIR:-/tmp}/purge.$$"
    # LE PLAFOND DE TAILLE. Meme sous KEEP fichiers, un fichier peut etre enorme : si le total
    # depasse MAXMO, on continue de jeter, du plus vieux au plus recent, jamais sous MIN minutes.
    while [ "$(total_mb)" -gt "$MAXMO" ]; do
      V=$(list | tail -n 1)
      [ -n "$V" ] || break
      find "$V" -maxdepth 0 -mmin +"$MIN" >/dev/null 2>&1 || break
      gio trash "$V" 2>/dev/null && J=$((J+1)) || { E=$((E+1)) ; break ; }
    done
    echo "purge : $J a la corbeille, $E en echec ; reste $(list | wc -l) fichier(s), $(total_mb) Mo"
    ;;
  *)
    echo "modes : status | once | help"
    ;;
esac
