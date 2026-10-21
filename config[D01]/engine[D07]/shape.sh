# id: E12
# role: the single form every call returns. six fields, always in this order, always present.

# shape <status> <tool> <line> <result> <return> : one line, one object
shape() {
  printf '{"status":"%s","tool":"%s","line":"%s","result":"%s","ts":%s,"return":"%s"}\n' \
    "$(fs_json "${1:-}")" \
    "$(fs_json "${2:-}")" \
    "$(fs_json "${3:-}")" \
    "$(fs_json "${4:-}")" \
    "$(date +%s)" \
    "$(fs_json "${5:-}")"
}

# shape_ok <tool> <line> <result> [return] : the call went through
shape_ok() {
  shape ok "${1:-}" "${2:-}" "${3:-}" "${4:-}"
}

# shape_fail <tool> <line> <phrase key> [arg ...] : a named refusal, in the same form
shape_fail() {
  _t=${1:-}
  _l=${2:-}
  _k=${3:?shape_fail: a key of texts is required, never a default phrase}
  shift 3
  _ph=$(msg "$_k" "$@")
  # a refusal nobody can read is worse than no refusal: the key goes to stderr
  [ -n "$_ph" ] || printf 'shape: no text for %s\n' "$_k" >&2
  shape refused "$_t" "$_l" "$_ph" ""
}

# shape_get <line> <field> : one field back, empty when absent
shape_get() {
  printf '%s' "${1:-}" | awk -v f="${2:-}" '{
    p = index($0, "\"" f "\":")
    if (p == 0) { exit }
    s = substr($0, p + length(f) + 3)
    if (substr(s, 1, 1) == "\"") {
      s = substr(s, 2)
      out = ""
      while (length(s) > 0) {
        c = substr(s, 1, 1); s = substr(s, 2)
        if (c == "\\") { n = substr(s, 1, 1); s = substr(s, 2)
          if (n == "n") out = out "\n"; else out = out n; continue }
        if (c == "\"") { break }
        out = out c
      }
      print out
    } else {
      sub(/[,}].*$/, "", s); print s
    }
  }'
}

# shape_short <line> : the same object, cut for a narrow screen
shape_short() {
  _m=$(conf_num agents.run_chars) || return 1
  printf '%s' "${1:-}" | cut -c "1-$_m"
  printf '\n'
}
