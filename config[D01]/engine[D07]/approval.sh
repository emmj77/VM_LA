# id: E01
# role: the human door. a signed go is checked here, never asked by a tool. window, HMAC, one file.

# --- the human door: a signed go, checked here, never asked by a tool
_ap_key() {
  _k=$(env_get LA_APPROVE_KEY)
  [ -n "$_k" ] || { say_err "$(msg refusals.approval_required)"; return 3; }
  printf '%s' "$_k"
}

_ap_digest() { printf '%s' "$1" | sha256sum | cut -c1-32; }

_ap_sig() {
  _k=$(_ap_key) || return 3
  printf '%s' "$1" | openssl dgst -sha256 -hmac "$_k" -r | cut -d' ' -f1
}

# _ap_trace <word> <line>: one trace line, through the body that owns it
_ap_trace() { printf '%s %s\n' "${1:-approve}" "${2:-}" | run_call engine.trace op=line >/dev/null; }

approval_request() {
  _d=$(_ap_digest "$*")
  { printf 'tool: %s\n' "$1"; printf 'digest: %s\n' "$_d"; printf 'ts: %s\n' "$(date +%s)"; } |
    write_atomic "$(cfg abs approve_request)" || return 1
  _ap_trace approve "requested: $1"
  return 3
}

approval_ok() {
  _f=$(cfg abs approve) || return 3
  [ -s "$_f" ] || return 3
  _d=$(_door_field "$_f" digest)
  [ "$_d" = "$(_ap_digest "$*")" ] || return 3
  _w=$(conf_num limits.approval_window) || return 3
  _ts=$(_door_field "$_f" ts)
  [ $(($(date +%s) - _ts)) -le "$_w" ] || return 3
  [ "$(_door_field "$_f" sig)" = "$(_ap_sig "$_d")" ] || return 3
  return 0
}

approval_grant() {
  _f=$(cfg abs approve_request) || return 1
  [ -s "$_f" ] || { say_err "$(msg refusals.approval_required)"; return 1; }
  _d=$(_door_field "$_f" digest)
  _s=$(_ap_sig "$_d") || return 3
  _n=$(_door_field "$_f" tool)
  { printf 'tool: %s\n' "$_n"; printf 'digest: %s\n' "$_d"
    printf 'ts: %s\n' "$(_door_field "$_f" ts)"; printf 'sig: %s\n' "$_s"; } |
    write_atomic "$(cfg abs approve)"
  _ap_trace approve "granted: $_n"
  return 0
}

approval_deny() {
  gio trash -- "$(cfg abs approve_request)" 2>/dev/null
  _ap_trace approve "denied"
  return 0
}

approval_status() { _f=$(cfg abs approve); [ -s "$_f" ] && _door_field "$_f" tool || printf 'none\n'; }
