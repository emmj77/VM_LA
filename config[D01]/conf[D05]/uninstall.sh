#!/bin/sh
# id: S02 - the uninstallation. it removes what the installation posed, and it keeps the data:
# state, audio, data and the master file stay where they are.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LA="$HERE/../engine[D07]/la.sh"

for a in "$@"; do
  case $a in
    -h|--help) printf 'uninstall.sh [units|command|desktop|applet]\n  no argument: everything\n' ; exit 0 ;;
  esac
done

remove() {  # $1 op
  _o=$(dash "$LA" engine engine.uninstall "op=$1" 2>&1 | jq -r '.result // .' 2>/dev/null) || true
  [ -n "${_o:-}" ] || _o="nothing said by op $1"
  printf '%s\n' "$_o"
}

if [ $# -gt 0 ]; then
  for a in "$@"; do remove "$a"; done
else
  remove units
  remove command
  remove desktop
  remove applet
fi
printf 'kept: the master file, state, audio, data, the certificates\n'
