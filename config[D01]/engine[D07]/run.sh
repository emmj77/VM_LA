# id: E11
# role: the door. it reads the register, reads the body, checks the call, runs it, and shapes what comes back.

# _door_field <body> <KEY> : one scalar of a body, top level or under a section
_door_field() {
  awk -v k="${2:-}" '
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (index(line, k ":") == 1) {
        v = substr(line, length(k) + 2)
        sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
        if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2) }
        print v; exit
      }
    }' "$1"
}

# _door_decl <body> : the declared arguments, "name:type" in their order
_door_decl() {
  awk '
    /^[ \t]*ARGS:/ { ina = 1; next }
    ina {
      if ($0 !~ /^[ \t]/) { exit }
      if (match($0, /\{name:[ \t]*[A-Za-z_0-9]+/)) {
        n = substr($0, RSTART, RLENGTH); sub(/.*name:[ \t]*/, "", n)
        t = "text"
        if (match($0, /type:[ \t]*[a-z]+/)) { t = substr($0, RSTART, RLENGTH); sub(/.*type:[ \t]*/, "", t) }
        v = ""
        if (match($0, /values:[ \t]*[^}]+/)) {
          v = substr($0, RSTART, RLENGTH); sub(/.*values:[ \t]*/, "", v)
          gsub(/[ \t]/, "", v); gsub(/[\[\]]/, "", v)
        }
        f = "0"
        if ($0 ~ /stdin:[ \t]*true/) { f = "1" }
        if (v != "") print n ":" t ":" v ":" f
        else print n ":" t "::" f
      }
    }' "$1"
}

# _door_cmd <body> : the command text, unfolded
_door_cmd() {
  awk '
    /^[ \t]*COMMAND:[ \t]*\|/ { inb = 1; next }
    inb {
      if ($0 ~ /^[ \t]*$/) { print ""; next }
      if ($0 !~ /^[ \t]/) { exit }
      if (ind == 0) { match($0, /^[ \t]*/); ind = RLENGTH }
      print substr($0, ind + 1)
    }' "$1"
}

# _door_register : the register the caller is allowed to read
_door_register() {
  if [ "${LA_FROM:-model}" = engine ]; then
    cfg abs registry-engine
  else
    cfg abs registry
  fi
}

# run_call <name> [key=value ...] : the whole door, one shape out
# 0 ok, 3 a human must sign, 124 the bound was reached, 1 refused
run_call() {
  _name=${1:-}
  [ $# -gt 0 ] && shift

  # 1 an id : the register names it
  _reg=$(_door_register) || { shape_fail "$_name" "" refusals.tool_unknown; return 1; }
  [ -r "$_reg" ] || { shape_fail "$_name" "" refusals.tool_unknown; return 1; }
  # the caller may name the tool or give its id: the register holds both, the id is the identity
  _id=$(table_field "$_reg" "$_name" id)
  [ -n "$_id" ] || { shape_fail "$_name" "" refusals.tool_unknown; return 1; }
  # the id names the tool: from here on we hold its name, whatever the caller gave
  _nm=$(table_field "$_reg" "$_id" tool)
  [ -n "$_nm" ] && _name=$_nm
  # the body is found by its name: the family says the folder, the name says the file.
  _body=""
  _fn=$(printf '%s' "$_name" | tr '.' '_')
  for _x in "$(cfg path tools)"/*/tool_"$_fn".yaml; do
    [ -f "$_x" ] && { _body=$_x; break; }
  done
  [ -n "$_body" ] || { shape_fail "$_name" "" refusals.tool_unknown; return 1; }

  # 2 its family
  _rfam=$(table_field "$_reg" "$_id" family)

  # 3 its body : a path in the register is written against the config root
  [ -r "$_body" ] || { shape_fail "$_name" "" refusals.tool_unknown; return 1; }

  # 4 coherence : the register and the body speak of the same tool
  _nm=$(table_field "$_reg" "$_id" tool)
  [ -n "$_nm" ] && _name=$_nm
  _bid=$(_door_field "$_body" id)
  if [ -n "$_bid" ] && [ "$_bid" != "$_id" ]; then
    shape_fail "$_name" "" refusals.arity
    return 1
  fi
  _bfam=$(_door_field "$_body" family)
  _bfam=$(printf '%s' "$_bfam" | tr 'A-Z' 'a-z')
  _rfam=$(printf '%s' "$_rfam" | tr 'A-Z' 'a-z')
  if [ -n "$_bfam" ] && [ -n "$_rfam" ] && [ "$_bfam" != "$_rfam" ]; then
    shape_fail "$_name" "" refusals.arity
    return 1
  fi

  # 5 the tools the active skill allows ; an engine call answers to nobody
  # a permanent tool passes anywhere, the others need the toolset of the active skill
  if [ "${LA_FROM:-model}" != engine ]; then
    tool_allowed "$_name" "$_id" || { shape_fail "$_name" "" refusals.tool_not_allowed; return 1; }
  fi

  # 6 arity and 7 types
  _decl=$(_door_decl "$_body")
  _args=""
  for _d in $_decl; do
    _n=${_d%%:*}
    _rest=${_d#*:}
    _t=${_rest%%:*}
    _rest2=${_rest#*:}
    _vals=$(printf '%s' "${_rest2%:*}" | tr ',' ' ')
    _sin=${_rest2##*:}
    _v=""
    for _pair in "$@"; do
      case $_pair in
        "$_n"=*) _v=${_pair#*=} ;;
      esac
    done
    if [ -z "$_v" ] && [ "$_t" != bool ]; then
      if [ "$_sin" = 1 ]; then
        if [ -t 0 ]; then _v="" ; else _v=$(cat) ; fi   # nothing piped, nothing to read
        [ -n "$_v" ] && set -- "$@" "$_n=$_v"
      else
        shape_fail "$_name" "" refusals.arity
        return 1
      fi
    fi
    if [ "$_sin" = 1 ] && [ -z "$_v" ]; then
      _w=''                             # nothing was piped: the body decides
    else
      _w=$(args_line "$_t" "$_v" $_vals) || { shape_fail "$_name" "" refusals.arity; return 1; }
    fi
    _args="$_args $_w"
  done

  # 8 paths : a path argument never leaves the canon
  for _d in $_decl; do
    case $_d in
      *:path)
        _n=${_d%%:*}
        for _pair in "$@"; do
          case $_pair in
            "$_n"=*) args_path "${_pair#*=}" >/dev/null || {
                       shape_fail "$_name" "" refusals.path_outside_canon
                       return 1
                     } ;;
          esac
        done ;;
    esac
  done

  # 9 approval : four bodies wait for a human, never for a tool
  if is_gated "$_body" && [ "${LA_FROM:-model}" != engine ]; then
    if approval_ok "$_name" "$@"; then
      :
    else
      approval_request "$_name" "$@" || { shape_fail "$_name" "" refusals.approval_required; return 3; }
      shape_fail "$_name" "" refusals.approval_required
      return 3
    fi
  fi

  # 10 the command, then no hole left in it
  _cmd=$(_door_cmd "$_body")
  if [ -z "$_cmd" ]; then
    _m=$(_door_field "$_body" machine)
    _o=$(_door_field "$_body" op)
    if [ -z "$_m" ] || [ -z "$_o" ]; then
      shape_fail "$_name" "" refusals.arity
      return 1
    fi
    _cmd="$_m --op $_o"
    for _d in $_decl; do
      _n=${_d%%:*}
      _cmd="$_cmd --arg \"$_n={{$_n}}\""
    done
  fi
  for _d in $_decl; do
    _n=${_d%%:*}
    for _pair in "$@"; do
      case $_pair in
        "$_n"=*)
          _sv=$(printf '%s' "${_pair#*=}" | sed 's/[\\&|]/\\&/g')
          _cmd=$(printf '%s' "$_cmd" | sed "s|{{$_n}}|$_sv|g") ;;
      esac
    done
  done
  case $_cmd in
    *"{{"*) shape_fail "$_name" "" refusals.arity; return 1 ;;
  esac

  # 11 run : la porte ne lance rien. elle confie le texte et les arguments a l executeur
  # unique du moteur, shell_exec (shell.sh) : une seule voie, un seul timeout, une seule forme.
  _to=$(_door_field "$_body" timeout)
  [ -n "$_to" ] || _to=$(conf_num limits.engine_timeout) || { shape_fail "$_name" "" refusals.timeout; return 1; }
  LA_TIMEOUT="$_to" shell_exec "$_name" "$_cmd" $_args
  return $?
}

# say <word ...> : the same line, on stderr, when there is no channel
say_err() {
  printf '%s\n' "$*" >&2
}

# die <phrase key> [arg ...] : the phrase, then stop this shell
die() {
  _k=${1:?die: a key of texts is required}
  [ $# -gt 0 ] && shift
  printf '%s\n' "$(msg "$_k" "$@")" >&2
  exit 1
}

# run as a command, not sourced: the door of the document, run.sh <id|name> [arg ...]
# the guard matters: boot.sh sources this file, so entering twice would be a loop
case ${0##*/} in
  run.sh)
    if [ $# -gt 0 ] && [ "${LA_DOOR_ENTERED:-0}" != 1 ]; then
      LA_DOOR_ENTERED=1
      export LA_DOOR_ENTERED
      LA_DIR=$(cd -- "$(dirname -- "$0")" && pwd) || exit 1
      . "$LA_DIR/boot.sh" || exit 1
      run_call "$@"
      exit $?
    fi ;;
esac
