#!/usr/bin/dash
# french in code is forbidden
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

LA_ROOT=${LA_ROOT:-$(dirname "$(dirname "$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")")")}
PANEL="$LA_ROOT/config/programs/board.py"
CLI="$LA_ROOT/config/programs/board.py"
BPORT=$(conf_num bridge port 8765)
RESIDENTS="la-models la-asr la-tts"
WIDTH=${LA_BOARD_COLS:-$(conf_num board columns 82)}
HEIGHT=${LA_BOARD_LINES:-$(conf_num board lines 50)}

MODE=cli
case "${1:-}" in
  --board) MODE=board ;;
  --app)   MODE=app ;;
  --once)  MODE=once ;;
  update)  MODE=update ; shift ;;
  --say)   MODE=say ; shift ; TEXT="${1:-}" ;;
  --cli)   MODE=cli ;;
  -h|--help) sed -n '2,13p' "$0" | sed -e 's/^# \{0,1\}//' ; exit 0 ;;
  '') : ;;
  *) printf '%s\n' "$(msg la_unknown_option "$1")" >&2 ; exit 2 ;;
esac

[ -f "$PANEL" ] || { printf '%s\n' "$(msg la_panel_absent "$PANEL")" >&2 ; exit 2 ; }

if [ "$MODE" = update ]; then
  exec sh "$(dirname -- "$0")/update.sh" "$@"
fi

if [ "$MODE" = once ]; then
  exec /usr/bin/python3 "$PANEL" --once
fi

if [ "$MODE" = app ]; then
  BASE="http://$(conf_str dashboard host 127.0.0.1):$(conf_num dashboard port 8770)"
  alive() { [ "$(curl -s -m 1 -o /dev/null -w '%{http_code}' "$BASE/health" 2>/dev/null)" = 200 ]; }
  if ! alive; then
    systemctl --user start la-dash 2>/dev/null || true
    i=0 ; while [ "$i" -lt "$(conf_num limits boot_tries 40)" ]; do alive && break ; sleep 0.25 ; i=$((i + 1)) ; done
  fi
  if ! alive; then
    LOG="${XDG_CACHE_HOME:-$HOME/.cache}/la-dashboard.log"
    command -v xdg-open >/dev/null 2>&1 && xdg-open "$LOG" >/dev/null 2>&1 || true
    printf '%s\n' "$(msg la_page_silent "$BASE")" >&2
    exit 1
  fi
  PROFILE="${XDG_DATA_HOME:-$HOME/.local/share}/la-dashboard/profil"
  mkdir -p "$PROFILE" 2>/dev/null || true
  for B in chromium chromium-browser google-chrome-stable google-chrome; do
    if command -v "$B" >/dev/null 2>&1; then
      exec "$B" --app="$BASE/" --user-data-dir="$PROFILE" --class=LA-Dashboard \
        --no-first-run --no-default-browser-check --window-size=1500,950
    fi
  done
  exec xdg-open "$BASE/"
fi

if [ "$MODE" = say ]; then
  [ -n "${TEXT:-}" ] || { printf '%s\n' "$(msg la_say_needs_text)" >&2 ; exit 2 ; }
  [ -f "$CLI" ] || { printf '%s\n' "$(msg la_cli_absent "$CLI")" >&2 ; exit 2 ; }
  command -v systemctl >/dev/null 2>&1 && systemctl --user start la-models la-asr la-tts >/dev/null 2>&1
  exec /usr/bin/python3 "$CLI" --say "$TEXT"
fi

if [ "$MODE" = cli ]; then
  printf '%s\n' "$(msg la_opening)"
  if command -v systemctl >/dev/null 2>&1; then
    SLEEPING=
    for u in $RESIDENTS; do
      E=$(systemctl --user is-active "$u.service" 2>/dev/null)
      [ "$E" = active ] || SLEEPING="$SLEEPING $u"
    done
    if [ -n "$SLEEPING" ]; then
      printf '  je reveille :%s\n' "$SLEEPING"
      systemctl --user start $SLEEPING 2>/dev/null
    else
      printf '%s\n' "$(msg la_residents_already)"
    fi
    A=0
    for u in $RESIDENTS; do
      E=$(systemctl --user is-active "$u.service" 2>/dev/null)
      [ "$E" = active ] && A=$((A + 1))
    done
    printf '%s\n' "$(msg la_residents_count "$A")"
    [ "$A" = 3 ] || printf '%s\n' "$(msg la_resident_stuck)"
  else
    printf '%s\n' "$(msg la_no_systemctl)"
  fi
  BRIDGE_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$(conf_num limits ping_timeout 2)" \
          "http://127.0.0.1:$BPORT/ping" 2>/dev/null || true)
  case "${BRIDGE_CODE:-000}" in
    000) printf '%s\n' "$(msg la_app_silent "$BPORT")"
         command -v systemctl >/dev/null 2>&1 && systemctl --user restart la-dash 2>/dev/null ;;
    *)   printf '%s\n' "$(msg la_app_answers "$BRIDGE_CODE")" ;;
  esac
  if [ -t 0 ] && [ -t 1 ]; then
    exec /usr/bin/python3 "$CLI" --cli
  fi
  printf '%s\n' "$(msg la_no_terminal)" >&2
  exit 2
fi

if [ "$MODE" = board ]; then
  if command -v kitty >/dev/null 2>&1; then
    setsid kitty --title "LA — le tableau" -o remember_window_size=no \
      -o initial_window_width=${WIDTH}c \
      -o initial_window_height=${HEIGHT}c -e /usr/bin/python3 "$PANEL" \
      >>"$STATE/board.log" 2>&1 &
    printf '%s\n' "$(msg la_board_window "$WIDTH" "$HEIGHT")"
    printf '%s\n' "$(msg la_board_trace "$STATE/board.log")"
  else
    printf '%s\n' "$(msg la_no_kitty)"
    exec /usr/bin/python3 "$PANEL" --once
  fi
fi
