#!/usr/bin/dash
# french in code is forbidden
set -e
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

W="$STATE"   # l etat du harnais, resolu par lib.sh depuis la_config (paths.state)
F="$W/approve"
REQ="$W/approve.request"
WIN=$(conf_num approval window 300)

usage() {
  cat >&2 <<'TXT'
usage: approval.sh [status | allow <tool> <action> | deny]
  status              ce qui attend un feu vert, ce qui est ouvert, et pour combien de temps
  allow <tool> <geste>  ecrit le feu vert pour CE geste (ex. allow table_manage add_tool)
  deny                efface la demande : l humain refuse, le modele le verra au tour suivant
TXT
  exit 1
}


show_status() {
  NOW=$(date +%s)
  if [ -f "$REQ" ]; then
    R=$(sed -n '1p' "$REQ" 2>/dev/null | tr -d '\r')
    AGE=$(( NOW - $(stat -c %Y "$REQ" 2>/dev/null || printf '0') ))
    printf '%s\n' "$(msg approval_request "${R:-unreadable}" "$AGE")"
  else
    printf '%s\n' "$(msg approval_request_none)"
  fi
  if [ -f "$F" ]; then
    A=$(sed -n '1p' "$F" 2>/dev/null | tr -d '\r')
    LEFT=$(( WIN - (NOW - $(stat -c %Y "$F" 2>/dev/null || printf '0')) ))
    [ "$LEFT" -lt 0 ] && LEFT=0
    printf '%s\n' "$(msg approval_green "${A:-unreadable}" "$LEFT")"
  else
    printf '%s\n' "$(msg approval_green_none)"
  fi
  printf '%s\n' "$(msg approval_window "$WIN")"
  active_skill >/dev/null 2>&1 || true
  if [ -n "$SKILL" ] && [ -f "$SKILL" ]; then
    V=$(sed -n 's/^APPROVAL:[[:space:]]*//p' "$SKILL" | head -n 1 | sed -e 's/#.*$//' | tr -d '[:space:]"')
    printf '%s\n' "$(msg approval_skill "${NAME:-?}" "${V:-false}")"
  else
    printf '%s\n' "$(msg approval_skill_none)"
  fi
}

case "${1:-status}" in
  status) show_status ;;
  deny)
    rm -f "$REQ"
    printf '%s\n' "$(msg approval_cleared)"
    ;;
  allow)
    T=${2:-} ; A=${3:-}
    [ -n "$T" ] || usage
    is_gated "$T" "$A" || { printf '%s\n' "$(msg approval_gated "$T${A:+ $A}")" >&2 ; exit 1; }
    [ -z "$A" ] || case "$A" in *[!a-z0-9_:]*) printf '%s\n' "$(msg approval_word "$A")" >&2 ; exit 1 ;; esac
    R=''
    [ -f "$REQ" ] && R=$(awk '{$NF=""; sub(/[[:space:]]+$/, ""); print}' "$REQ" 2>/dev/null)
    WANT=$(printf '%s %s' "$T" "$A" | sed -e 's/[[:space:]]*$//')
    [ "$R" = "$WANT" ] || {
      printf '%s\n' "$(msg approval_none "$T $A")" >&2
      [ -n "$R" ] && printf '%s\n' "$(msg approval_waiting "$R")" >&2
      printf '%s\n' "$(msg approval_law)" >&2
      exit 1
    }
    umask 077
    if [ -n "$A" ]; then printf '%s %s\n' "$T" "$A" > "$F" ; else printf '%s\n' "$T" > "$F" ; fi
    rm -f "$REQ"
    bip ok           # la cloche courte : le feu vert est SIGNE, et il ne servira qu une fois
    printf '%s\n' "$(msg approval_written "$(printf '%s %s' "$T" "$A" | sed -e 's/[[:space:]]*$//')" "$WIN")"
    ;;
  *) usage ;;
esac
