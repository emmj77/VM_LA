#!/usr/bin/dash
# french in code is forbidden
set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

ROOT=${LA_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
TAG=la-avant-update
INSTALL="$ROOT/config/install.sh"
BRIDGE_UNIT=la-dash.service

git_() { git -C "$ROOT" "$@" 2>/dev/null ; }

version() { git_ describe --always --tags --dirty || printf '?' ; }

sale() { [ -n "$(git_ status --porcelain)" ] ; }

turn_running() {
  M="$STATE/turn.pid"
  [ -f "$M" ] || return 1
  P=$(sed -n '1p' "$M" 2>/dev/null | tr -d '[:space:]')
  [ -n "$P" ] && kill -0 "$P" 2>/dev/null
}

upstream() { git_ rev-parse --abbrev-ref --symbolic-full-name '@{u}'; }

check_json() {
  V=$(version)
  if ! git_ fetch --quiet origin; then
    printf '{"version":"%s","behind":null,"dirty":null,"error":"the network (git fetch) failed"}\n' "$V"
    exit 3
  fi
  U=$(upstream)
  SALE=0 ; sale && SALE=1
  N=$(git_ rev-list --count "HEAD..$U" 2>/dev/null || printf '0')
  LIST=$(git_ log --oneline "HEAD..$U" 2>/dev/null | head -n "$(conf_num update log_lines 20)" | jq -R -s 'split("\n") | map(select(length > 0))')
  printf '{"version":"%s","upstream":"%s","behind":%s,"dirty":%s,"commits":%s}\n' \
    "$V" "$U" "${N:-0}" "$([ "$SALE" = 1 ] && echo true || echo false)" "${LIST:-[]}"
  [ "$SALE" = 1 ] && exit 2
  [ "${N:-0}" -gt 0 ] && exit 1
  exit 0
}

check_human() {
  V=$(version)
  printf '  version : %s\n' "$V"
  if ! git_ fetch --quiet origin; then
    printf '%s\n' "$(msg update_net_failed)" >&2
    exit 3
  fi
  U=$(upstream)
  printf '  branche : %s\n' "${U:-?}"
  if sale ; then
    printf '%s\n' "$(msg update_dirty)" >&2
    exit 2
  fi
  N=$(git_ rev-list --count "HEAD..$U" 2>/dev/null || printf '0')
  AHEAD=$(git_ rev-list --count "$U..HEAD" 2>/dev/null || printf '0')
  [ "${AHEAD:-0}" -gt 0 ] && printf '%s\n' "$(msg update_local_commits "$AHEAD")"
  if [ "${N:-0}" = 0 ]; then
    printf '  a jour.\n'
    exit 0
  fi
  printf '  %s commit(s) attendent :\n' "$N"
  git_ log --oneline "HEAD..$U" | head -n "$(conf_num update log_lines 20)" | sed -e 's/^/    /'
  exit 1
}

apply() {
  V0=$(version)
  if sale ; then
    printf '%s\n' "$(msg upd_dirty)" >&2
    exit 2
  fi
  if turn_running ; then
    printf '%s\n' "$(msg upd_turn "$(sed -n '1p' "$STATE/turn.pid")")" >&2
    exit 3
  fi
  printf '%s\n' "$(msg update_version_before "$V0")"
  git_ tag -f "$TAG" >/dev/null || { printf '%s\n' "$(msg upd_tag "$TAG")" >&2 ; exit 4 ; }
  printf '%s\n' "$(msg update_tag "$TAG")"
  MARK=$(mktemp) || exit 4
  sleep 0.01
  if ! git_ pull --ff-only ; then
    printf '%s\n' "$(msg upd_pull)" >&2
    rm -f "$MARK"
    exit 4
  fi
  printf '  code a jour : %s\n' "$(version)"
  if [ -x "$INSTALL" ] || [ -f "$INSTALL" ]; then
    printf '  install.sh --no-start :\n'
    sh "$INSTALL" --no-start 2>&1 | sed -e 's/^/    /'
  else
    printf '%s\n' "$(msg update_no_install)" >&2
  fi
  CHANGES=$(find "$ROOT/config/units" -maxdepth 1 -name '*.service.in' -newer "$MARK" 2>/dev/null \
            | sed -e 's|.*/||' -e 's|\.in$||')
  rm -f "$MARK"
  command -v systemctl >/dev/null 2>&1 || { printf '%s\n' "$(msg update_no_systemctl)" ; exit 0 ; }
  systemctl --user daemon-reload 2>/dev/null || true
  for U in $CHANGES ; do
    [ "$U" = "$BRIDGE_UNIT" ] && continue
    printf '  redemarrage : %s\n' "$U"
    systemctl --user restart "$U" 2>/dev/null || printf '%s\n' "$(msg update_restart_failed "$U" "$U")"
  done
  printf '%s\n' "$(msg update_bridge_restart "$BRIDGE_UNIT")"
  bridge_detached
  exit 0
}

bridge_detached() {
  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --user --collect --quiet --on-active=1 --unit="la-update-bridge-$$" \
      systemctl --user restart "$BRIDGE_UNIT" >/dev/null 2>&1 && return 0
  fi
  setsid sh -c "sleep 1; systemctl --user restart $BRIDGE_UNIT" >/dev/null 2>&1 &
  return 0
}

rollback() {
  if ! git_ rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    printf '%s\n' "$(msg upd_notag "$TAG")" >&2
    exit 5
  fi
  TARGET=$(git_ rev-parse --short "$TAG")
  printf '  retour a %s (%s)\n' "$TAG" "$TARGET"
  if ! git_ reset --hard "$TAG" >/dev/null ; then
    printf '%s\n' "$(msg upd_reset "$TAG")" >&2
    exit 5
  fi
  if [ -f "$INSTALL" ]; then
    sh "$INSTALL" --no-start 2>&1 | sed -e 's/^/    /'
  fi
  command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload 2>/dev/null || true
  for U in la-models.service la-asr.service la-tts.service ; do
    command -v systemctl >/dev/null 2>&1 && systemctl --user restart "$U" 2>/dev/null || true
  done
  printf '  version : %s\n' "$(version)"
  printf '%s\n' "$(msg update_bridge_restart_bare)"
  bridge_detached
  exit 0
}

case "${1:-apply}" in
  --version)  version ; printf '\n' ; exit 0 ;;
  --check)    check_human ;;
  --json)     check_json ;;
  apply|'')   apply ;;
  --rollback) rollback ;;
  -h|--help)  awk 'NR > 1 && /^#/ { sub(/^# ?/, "") ; print ; next } NR > 1 { exit }' "$0" ; exit 0 ;;
  *)          printf 'update: argument inconnu : %s (--check, --json, --rollback, --version)\n' "$1" >&2 ; exit 2 ;;
esac
