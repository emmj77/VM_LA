#!/bin/sh
# id: S01 - the installation. it checks the machine, then asks the engine to pose each piece:
# the la command, the units, the desktop entry, the applet, the certificates.
# it poses, it says what it posed, and it starts nothing.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LA="$(CDPATH= cd -- "$HERE/../engine[D07]" && pwd -P)/la.sh"
START=0
CERTS=0
CHECK=0
for a in "$@"; do
  case $a in
    --start) START=1 ;;
    --certs) CERTS=1 ;;
    --check) CHECK=1 ;;
    -h|--help) printf 'install.sh [--check] [--certs] [--start]\n  --check  verify, pose nothing\n  --certs  create the bridge certificate when it is missing\n  --start  enable and start the four units\n' ; exit 0 ;;
    *) printf 'install.sh: unknown argument %s\n' "$a" >&2 ; exit 2 ;;
  esac
done

pose() {   # $1 op
  _o=$(dash "$LA" engine engine.install "op=$1" 2>&1 | jq -r '.result // .' 2>/dev/null) || true
  [ -n "${_o:-}" ] || _o="nothing said by op $1"
  printf '%s\n' "$_o"
}

printf 'home   %s\n' "$LA"
_miss=""
for c in dash python3 jq systemctl; do command -v "$c" >/dev/null 2>&1 || _miss="$_miss $c"; done
[ -x "$LA" ] || _miss="$_miss la.sh"
systemctl --user show-environment >/dev/null 2>&1 || _miss="$_miss user-manager"
[ -z "$_miss" ] || { printf 'FAULT missing on this machine:%s\n' "$_miss" ; exit 1 ; }
printf 'checks ok: dash python3 jq systemctl user-manager la.sh\n'

if [ "$CHECK" = 1 ]; then
  for f in "$HOME/.local/bin/la" "$HOME/.config/systemd/user/la-models.service" \
           "$HOME/.local/share/applications/la.desktop" \
           "$HOME/.local/share/cinnamon/applets/LA_Info@moussa"; do
    [ -e "$f" ] && printf 'posed    %s\n' "$f" || printf 'missing  %s\n' "$f"
  done
  exit 0
fi

pose command
pose units
pose desktop
pose applet
[ "$CERTS" = 1 ] && pose certs

if [ "$START" = 1 ]; then
  systemctl --user enable --now la-models la-asr la-tts la-dash 2>&1 | sed 's/^/unit    /' || true
fi

printf 'done. the panel shows the applet after: cinnamon --replace &\n'
