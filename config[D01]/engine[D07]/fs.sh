# id: E07
# role: paths, atomic writes, temp files. nothing here knows a name of the tree: cfg answers.
# the four names of the document are abs_path, state_paths, tmpfile, write_atomic.

# abs_path <path> : the path made whole against ROOT, an absolute one is left alone
abs_path() {
  case ${1:-} in
    '') return 1 ;;
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s/%s\n' "$ROOT" "$1" ;;
  esac
}

# state_paths [key] : the state directory, or one of its files when a key is given
state_paths() {
  _d=$(cfg path state) || return 1
  if [ $# -eq 0 ] || [ -z "$1" ]; then
    printf '%s\n' "$_d"
    return 0
  fi
  _f=$(cfg abs "$1") || return 1
  case $_f in
    "$_d"/*) printf '%s\n' "$_f" ;;
    *) return 1 ;;
  esac
}

# tmpfile [prefix] : a fresh file in the state directory, its name already made
tmpfile() {
  _d=$(cfg path state) || return 1
  [ -d "$_d" ] || mkdir -p -- "$_d" || return 1
  mktemp "$_d/${1:-tmp}.XXXXXX"
}

# write_atomic <path> : the text arrives on stdin, the file appears in one move
write_atomic() {
  _p=$(abs_path "${1:-}") || return 1
  _d=$(dirname -- "$_p")
  [ -d "$_d" ] || mkdir -p -- "$_d" || return 1
  _t="$_p.$$.tmp"
  cat > "$_t" || { rm -f -- "$_t"; return 1; }
  mv -f -- "$_t" "$_p" || { rm -f -- "$_t"; return 1; }
}

# fs_json <text> : the text escaped for one JSON string, newlines kept as \n
fs_json() {
  printf '%s' "$*" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r//g' -e 's/\t/\\t/g' |
    awk 'BEGIN { ORS = "" } { if (NR > 1) printf "\\n"; printf "%s", $0 }'
}

# fs_age <path> : seconds since the file was last written, fails when absent
fs_age() {
  [ -e "${1:-}" ] || return 1
  _n=$(date +%s)
  _m=$(stat -c %Y -- "$1") || return 1
  printf '%s\n' $((_n - _m))
}

# env_get <NAME> : one value of the key file, empty when it is not there
env_get() {
  _f=$(cfg abs env) || return 1
  [ -r "$_f" ] || return 1
  awk -F= -v k="${1:-}" '$1 == k { sub("^" k "=", ""); gsub(/^["\047]|["\047]$/, ""); print; exit }' "$_f"
}
