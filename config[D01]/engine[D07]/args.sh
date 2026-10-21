# id: E02
# role: declared arguments to a command line. five types, one rule each, no eval anywhere.

# args_word <value> : the value as one shell word, quoted for the command
args_word() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# args_ok <type> <value> [enum1 enum2 ...] : true when the value fits the type
args_ok() {
  _t=${1:-}
  _v=${2:-}
  [ $# -gt 1 ] && shift 2
  case $_t in
    text) [ -n "$_v" ] ;;
    path) [ -n "$_v" ] && [ "${_v#-}" = "$_v" ] ;;
    int)  case $_v in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac ;;
    bool) case $_v in 0|1|true|false|yes|no) return 0 ;; *) return 1 ;; esac ;;
    enum) [ $# -gt 0 ] || return 1
          for _e in "$@"; do [ "$_v" = "$_e" ] && return 0; done
          return 1 ;;
    *) return 1 ;;
  esac
}

# args_bool <value> : the value as 0 or 1
args_bool() {
  case ${1:-} in
    1|true|yes) printf '1\n' ;;
    *)          printf '0\n' ;;
  esac
}

# args_path <value> : the value as a full path, no symlink taken, no way above the root
args_path() {
  _v=${1:-}
  [ -n "$_v" ] || return 1
  case $_v in
    /*) _a=$_v ;;
    *)  _a="$ROOT/$_v" ;;
  esac
  _a=$(realpath -m -- "$_a" 2>/dev/null) || return 1
  case $_a in
    "$ROOT"|"$ROOT"/*) printf '%s\n' "$_a" ;;
    *) return 1 ;;
  esac
}

# args_line <type> <value> [enum ...] : the word a command receives, refused if it does not fit
args_line() {
  _t=${1:-}
  _v=${2:-}
  [ $# -gt 1 ] && shift 2
  args_ok "$_t" "$_v" "$@" || return 1
  case $_t in
    path) _p=$(args_path "$_v") || return 1
          printf '%s\n' "$_p" ;;
    bool) [ "$(args_bool "$_v")" = 1 ] && printf '1\n' || printf '0\n' ;;
    *)    printf '%s\n' "$_v" ;;
  esac
}

# args_env <name> <value> : one assignment line for the command environment
args_env() {
  [ -n "${1:-}" ] || return 1
  printf '%s=%s\n' "$1" "$(args_word "${2:-}")"
}

# args_split <decl> : one item per line, name:type or name:type:a,b,c
args_split() {
  printf '%s\n' "${1:-}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
}

# args_decl <decl> <name> : the type of one declared argument, empty when it is not declared
args_decl() {
  args_split "$1" | awk -F: -v n="$2" '$1 == n { print $2; exit }'
}

# args_enum <decl> <name> : the allowed values of one declared argument
args_enum() {
  args_split "$1" | awk -F: -v n="$2" '$1 == n { print $3; exit }' | tr '|' ' '
}
