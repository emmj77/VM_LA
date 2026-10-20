#!/usr/bin/dash
# french in code is forbidden
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

F=${1:-} ; Q=${2:-} ; K=${3:-0}
[ -n "$F" ] && [ -f "$F" ] || { printf '%s\n' "$(msg pick_none "$F")" >&2; exit 1; }
[ "$K" -gt 0 ] 2>/dev/null || exit 0
N=$(wc -l < "$F" | tr -d ' ')
[ "$N" -gt "$K" ] || exit 0

TMP="$F.pick"
if python3 "$ROOT/config/programs/vector_pick.py" --candidates "$F" --request "$Q" --k "$K" \
     > "$TMP" 2>"$TMP.err"; then
  if [ -s "$TMP" ]; then
    cat "$TMP.err" >&2
    mv -f "$TMP" "$F"
  fi
else
  cat "$TMP.err" >&2
fi
mkdir -p "$STATE/pick" 2>/dev/null ; mv -f "$TMP.err" "$STATE/pick/" 2>/dev/null
[ -f "$TMP" ] && mv -f "$TMP" "$STATE/pick/" 2>/dev/null
exit 0
