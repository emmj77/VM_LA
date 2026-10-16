#!/bin/sh
# backup.sh — THE NET (B1). The project is tarred, placed on a FOREIGN support, UNROLLED, COMPARED.
# This is not an instruction on a card : it is this script that carries it, and that REFUSES.
#
#   backup.sh put    <support>    the project tar goes onto the support, we imprint it
#   backup.sh unroll <support>    we unroll the tar BESIDE, and compare the du -sb
#   backup.sh verify              the state of the net : placed ? unrolled ? compared ? up to date ?
#
# THE REFUSAL THAT MATTERS : a support on the SAME DEVICE as the project is NOT a foreign
# support. /dev/sda3 carries /home, so a tar in ~/Documents dies with what it protects.
# The script compares the DEVICES (df --output=source), never the paths.
set -u
LC_ALL=C; export LC_ALL
HERE=$(dirname "$(readlink -f "$0")")
ROOT=${LA_ROOT:-$(dirname "$(dirname "$HERE")")}
STAMP=$(date -u +%Y-%m-%d_%H%M%S)

say() { printf 'net: %s\n' "$1"; }
refuse_hard() { printf 'net: REFUSAL — %s\n' "$1" >&2; exit 3; }

[ -d "$ROOT" ] || refuse_hard "the project is not there : $ROOT"
DEV_ROOT=$(df --output=source "$ROOT" 2>/dev/null | tail -1 | tr -d ' ')
[ -n "$DEV_ROOT" ] || refuse_hard "I do not know which device carries the project"

# THE DISK, NOT THE PARTITION. /dev/sda2 and /dev/sda3 are two partitions of the SAME disk : a
# tar that crosses from one to the other dies with what it protects, exactly like a tar in
# ~/Documents. It is lsblk that gives the PARENT disk of a partition. (Measured 14/10 : my first
# check compared partitions and ACCEPTED /media/moussa/SAVE, empty but on sda2.)
disk_of() { lsblk -no PKNAME "$1" 2>/dev/null | head -1 | tr -d ' '; }
foreign_support() {
  [ -d "$1" ] || refuse_hard "the support does not exist : $1"
  D=$(df --output=source "$1" 2>/dev/null | tail -1 | tr -d ' ')
  [ -n "$D" ] || refuse_hard "I do not know which device carries the support : $1"
  [ "$D" != "$DEV_ROOT" ] || refuse_hard "this support is on THE SAME device as the project ($D) : a tar that dies with what it protects is not a net. Plug in the external SSD."
  DC=$(disk_of "$DEV_ROOT"); DS=$(disk_of "$D")
  if [ -n "$DC" ] && [ -n "$DS" ] && [ "$DC" = "$DS" ]; then
    refuse_hard "this support is ANOTHER PARTITION OF THE SAME DISK as the project ($D and $DEV_ROOT are both on $DC) : it dies with it. Plug in the external SSD."
  fi
  FOUND=$(findmnt -rno TARGET,SOURCE | grep -F " $D" | head -1 | cut -d' ' -f1)
  [ -n "$FOUND" ] || refuse_hard "the support $1 is not a MOUNT point : an ordinary folder is not a support"
  printf '%s\n' "$FOUND"
}
size() { du -sb "$1" 2>/dev/null | cut -f1; }

case "${1:-}" in
put)
  [ $# -eq 2 ] || refuse_hard "put takes ONE argument : the support folder"
  MNT=$(foreign_support "$2") || exit 3
  TAR="$2/project-$STAMP.tar.gz"
  say "the project : $ROOT ($(size "$ROOT") bytes) -> the support : $MNT"
  tar czf "$TAR" -C "$(dirname "$ROOT")" "$(basename "$ROOT")" 2>/dev/null \
    || refuse_hard "the tar failed : $TAR"
  [ -s "$TAR" ] || refuse_hard "the tar is empty : $TAR"
  jq -cn --arg project "$ROOT" --arg tar "$TAR" --arg device "$DEV_ROOT" --arg mount "$MNT" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson project_size "$(size "$ROOT")" \
    '{project:$project,tar:$tar,device:$device,mount:$mount,date:$date,project_size:$project_size,unrolled:"",unrolled_size:0,compare:false}' \
    > "$2/.backup.json" || refuse_hard "I could not write the imprint"
  say "placed : $TAR ($(size "$TAR") bytes) — and the imprint is written : $2/.backup.json"
  ;;
unroll)
  [ $# -eq 2 ] || refuse_hard "unroll takes ONE argument : the support folder"
  F="$2/.backup.json"
  [ -f "$F" ] || refuse_hard "no net placed here : $F is missing"
  TAR=$(jq -r '.tar' "$F"); AT=$(jq -r '.project_size' "$F")
  [ -f "$TAR" ] || refuse_hard "the net tar has disappeared : $TAR"
  D="$2/log-$STAMP"
  mkdir -p "$D" || refuse_hard "I could not create the unroll folder : $D"
  tar xzf "$TAR" -C "$D" 2>/dev/null || refuse_hard "the unroll failed : $TAR"
  DR=$(find "$D" -maxdepth 1 -mindepth 1 | head -1)
  [ -n "$DR" ] || refuse_hard "the tar unrolled EMPTY : $TAR"
  N=$(size "$DR")
  jq -c --arg d "$DR" --argjson n "$N" --argjson a "$AT" \
    '.unrolled=$d | .unrolled_size=$n | .compare=($n==$a)' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  if [ "$N" = "$AT" ]; then
    say "unrolled and COMPARED : $N bytes on both sides — the net holds"
  else
    refuse_hard "the sizes DIFFER : project $AT, unrolled $N — the tar does not return what it took"
  fi
  ;;
verify)
  [ $# -eq 1 ] || refuse_hard "verify takes no argument (the support is read in the imprint)"
  N=0; for s in /media/moussa/* ; do [ -f "$s/.backup.json" ] && N=$((N+1)) && F="$s/.backup.json"; done
  [ "$N" -gt 0 ] || refuse_hard "NO net placed on any support : the project is not protected"
  jq -r '"\(.date)  \(.tar)  unrolled=\(.unrolled|if .=="" then "no" else "yes" end)  compare=\(.compare)"' "$F"
  C=$(jq -r '.compare' "$F")
  [ "$C" = "true" ] || refuse_hard "the net is placed but NOT compared : it is not yet a net"
  T=$(size "$ROOT"); A=$(jq -r '.project_size' "$F")
  [ "$T" = "$A" ] || refuse_hard "the project moved since the tar ($A -> $T) : the net is STALE"
  say "the net is placed, unrolled, compared, and up to date — $A bytes"
  ;;
*)
  printf 'usage : backup.sh put <support> | unroll <support> | verify\n' >&2; exit 2 ;;
esac
