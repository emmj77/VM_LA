#!/bin/sh
# backup.sh — LE FILET (B1). Le projet est tarre, pose sur un support ETRANGER, DEROULE, COMPARE.
# Ce n est pas une consigne dans une fiche : c est ce script qui la porte, et qui REFUSE.
#
#   backup.sh put    <support>    le tar du projet va sur le support, on l empreinte
#   backup.sh unroll <support>    on deroule le tar A COTE, et on compare les du -sb
#   backup.sh verify              l etat du filet : pose ? deroule ? compare ? a jour ?
#
# LE REFUS QUI COMPTE : un support sur le MEME PERIPHERIQUE que le projet n est PAS un support
# etranger. /dev/sda3 porte /home, donc un tar dans ~/Documents meurt avec ce qu il protege.
# Le script compare les PERIPHERIQUES (df --output=source), jamais les chemins.
set -u
LC_ALL=C; export LC_ALL
HERE=$(dirname "$(readlink -f "$0")")
ROOT=${LA_ROOT:-$(dirname "$(dirname "$HERE")")}
STAMP=$(date -u +%Y-%m-%d_%H%M%S)

say() { printf 'filet: %s\n' "$1"; }
refuse_hard() { printf 'filet: REFUS — %s\n' "$1" >&2; exit 3; }

[ -d "$ROOT" ] || refuse_hard "le projet n est pas la : $ROOT"
DEV_ROOT=$(df --output=source "$ROOT" 2>/dev/null | tail -1 | tr -d ' ')
[ -n "$DEV_ROOT" ] || refuse_hard "je ne sais pas quel peripherique porte le projet"

# LE DISQUE, PAS LA PARTITION. /dev/sda2 et /dev/sda3 sont deux partitions du MEME disque : un
# tar qui passe de l une a l autre meurt avec ce qu il protege, exactement comme un tar dans
# ~/Documents. C est lsblk qui donne le disque PARENT d une partition. (Mesure 14/10 : mon
# premier controle comparait les partitions et a ACCEPTE /media/moussa/SAVE, vide mais sur sda2.)
disk_of() { lsblk -no PKNAME "$1" 2>/dev/null | head -1 | tr -d ' '; }
foreign_support() {
  [ -d "$1" ] || refuse_hard "le support n existe pas : $1"
  D=$(df --output=source "$1" 2>/dev/null | tail -1 | tr -d ' ')
  [ -n "$D" ] || refuse_hard "je ne sais pas quel peripherique porte le support : $1"
  [ "$D" != "$DEV_ROOT" ] || refuse_hard "ce support est sur LE MEME peripherique que le projet ($D) : un tar qui meurt avec ce qu il protege n est pas un filet. Branchez le SSD externe."
  DC=$(disk_of "$DEV_ROOT"); DS=$(disk_of "$D")
  if [ -n "$DC" ] && [ -n "$DS" ] && [ "$DC" = "$DS" ]; then
    refuse_hard "ce support est une AUTRE PARTITION DU MEME DISQUE que le projet ($D et $DEV_ROOT sont tous deux sur $DC) : il meurt avec lui. Branchez le SSD externe."
  fi
  FOUND=$(findmnt -rno TARGET,SOURCE | grep -F " $D" | head -1 | cut -d' ' -f1)
  [ -n "$FOUND" ] || refuse_hard "le support $1 n est pas un point de MONTAGE : un dossier ordinaire n est pas un support"
  printf '%s\n' "$FOUND"
}
size() { du -sb "$1" 2>/dev/null | cut -f1; }

case "${1:-}" in
put)
  [ $# -eq 2 ] || refuse_hard "put prend UN argument : le dossier du support"
  MNT=$(foreign_support "$2") || exit 3
  TAR="$2/project-$STAMP.tar.gz"
  say "le projet : $ROOT ($(size "$ROOT") bytes) -> le support : $MNT"
  tar czf "$TAR" -C "$(dirname "$ROOT")" "$(basename "$ROOT")" 2>/dev/null \
    || refuse_hard "le tar a echoue : $TAR"
  [ -s "$TAR" ] || refuse_hard "le tar est vide : $TAR"
  jq -cn --arg project "$ROOT" --arg tar "$TAR" --arg device "$DEV_ROOT" --arg mount "$MNT" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson project_size "$(size "$ROOT")" \
    '{project:$project,tar:$tar,device:$device,mount:$mount,date:$date,project_size:$project_size,unrolled:"",unrolled_size:0,compare:false}' \
    > "$2/.filet.json" || refuse_hard "je n ai pas pu ecrire l empreinte"
  say "pose : $TAR ($(size "$TAR") bytes) — et l empreinte est ecrite : $2/.filet.json"
  ;;
unroll)
  [ $# -eq 2 ] || refuse_hard "unroll prend UN argument : le dossier du support"
  F="$2/.filet.json"
  [ -f "$F" ] || refuse_hard "aucun filet pose ici : $F est absent"
  TAR=$(jq -r '.tar' "$F"); AT=$(jq -r '.project_size' "$F")
  [ -f "$TAR" ] || refuse_hard "le tar du filet a disparu : $TAR"
  D="$2/log-$STAMP"
  mkdir -p "$D" || refuse_hard "je n ai pas pu creer le dossier de deroulement : $D"
  tar xzf "$TAR" -C "$D" 2>/dev/null || refuse_hard "le deroulement a echoue : $TAR"
  DR=$(find "$D" -maxdepth 1 -mindepth 1 | head -1)
  [ -n "$DR" ] || refuse_hard "le tar s est deroule EMPTY : $TAR"
  N=$(size "$DR")
  jq -c --arg d "$DR" --argjson n "$N" --argjson a "$AT" \
    '.unrolled=$d | .unrolled_size=$n | .compare=($n==$a)' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  if [ "$N" = "$AT" ]; then
    say "deroule et COMPARE : $N bytes des deux cotes — le filet tient"
  else
    refuse_hard "les tailles DIFFERENT : projet $AT, deroule $N — le tar ne rend pas ce qu il a pris"
  fi
  ;;
verify)
  [ $# -eq 1 ] || refuse_hard "verify ne prend aucun argument (le support se lit dans l empreinte)"
  N=0; for s in /media/moussa/* ; do [ -f "$s/.filet.json" ] && N=$((N+1)) && F="$s/.filet.json"; done
  [ "$N" -gt 0 ] || refuse_hard "AUCUN filet pose sur aucun support : le projet n est pas protege"
  jq -r '"\(.date)  \(.tar)  deroule=\(.unrolled|if .=="" then "non" else "oui" end)  compare=\(.compare)"' "$F"
  C=$(jq -r '.compare' "$F")
  [ "$C" = "true" ] || refuse_hard "le filet est pose mais PAS compare : il n est pas encore un filet"
  T=$(size "$ROOT"); A=$(jq -r '.project_size' "$F")
  [ "$T" = "$A" ] || refuse_hard "le projet a bouge depuis le tar ($A -> $T) : le filet est PERIME"
  say "le filet est pose, deroule, compare, et a jour — $A bytes"
  ;;
*)
  printf 'usage : backup.sh put <support> | unroll <support> | verify\n' >&2; exit 2 ;;
esac
