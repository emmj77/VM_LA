# id: E10
# role: the phrases of texts.yaml. one reader, one rule: a missing key says its own name.

# msg <dotted.key> [arg ...] : the phrase, arguments filled in order
msg() {
  _k=${1:-}
  [ $# -gt 0 ] && shift
  [ -n "$_k" ] || return 1
  _t=$(msg_str "$_k") || return 1
  [ $# -gt 0 ] && _t=$(printf "$_t" "$@")
  printf '%s\n' "$_t"
}

# msg_str <dotted.key> : the raw text, no substitution
msg_str() {
  _f=$(cfg abs texts) || return 1
  [ -r "$_f" ] || return 1
  _flat "$_f" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'
}

# msg_has <dotted.key> : true when the phrase exists
msg_has() {
  [ -n "$(msg_str "$1")" ]
}
