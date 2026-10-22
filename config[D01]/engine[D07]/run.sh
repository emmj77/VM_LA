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
        q = "1"
        if ($0 ~ /required:[ \t]*false/) { q = "0" }
        if (v != "") print n ":" t ":" v ":" f ":" q
        else print n ":" t "::" f ":" q
      }
    }' "$1"
}

# _door_usage <body> : the shape of the call, taken from the body, nothing added
_door_usage() {
  awk '
    BEGIN { tool = "" ; n = 0 }
    /^[ \t]*tool:[ \t]*/ {
      v = $0; sub(/^[ \t]*tool:[ \t]*/, "", v); gsub(/"/, "", v); tool = v; next
    }
    /^[ \t]*ARGS:/ { ina = 1; next }
    ina {
      if ($0 !~ /^[ \t]/) { ina = 0; next }
      line = $0
      if (!match(line, /name:[ \t]*[A-Za-z_0-9]+/)) next
      nm = substr(line, RSTART, RLENGTH); sub(/.*name:[ \t]*/, "", nm)
      tp = "text"
      if (match(line, /type:[ \t]*[a-z]+/)) { tp = substr(line, RSTART, RLENGTH); sub(/.*type:[ \t]*/, "", tp) }
      ex = ""
      if (tp == "enum" && match(line, /values:[ \t]*\[[^]]*\]/)) {
        ex = substr(line, RSTART, RLENGTH); sub(/.*values:[ \t]*\[/, "", ex)
        gsub(/[ \t]/, "", ex); gsub(/\]/, "", ex); ex = "[" ex "]"
      }
      s = ""
      if (line ~ /stdin:[ \t]*true/) s = " or on standard input"
      o = ""
      if (line ~ /required:[ \t]*false/) o = " (optional)"
      n++; a[n] = nm "=<" tp ">" ex s o
    }
    END {
      printf "usage: %s", (tool == "" ? "tool" : tool)
      for (i = 1; i <= n; i++) printf "%s %s", (i > 1 ? " |" : ""), a[i]
      printf "\n"
    }' "$1"
}

# _door_fill <pattern> <value> : the text on stdin, every pattern replaced, newlines kept
# sed cannot carry a value with a newline in its replacement: the body came out empty
# and the call answered ok with nothing in it. awk moves the bytes, no escaping.
_door_fill() {
  _f_pat=${1:-}
  _f_val=${2-}
  [ -n "$_f_pat" ] || cat
  [ -n "$_f_pat" ] || return 0
  _F_PAT="$_f_pat" _F_VAL="$_f_val" awk '
    { line = $0
      while ((i = index(line, ENVIRON["_F_PAT"])) > 0)
        line = substr(line, 1, i - 1) ENVIRON["_F_VAL"] substr(line, i + length(ENVIRON["_F_PAT"]))
      print line }'
}

# _door_arity_fail <name> <body> <phrase key> [arg ...] : the refusal, then the usage
# the same six fields; the phrase and, under it, the shape of the call taken from the body
_door_arity_fail() {
  _u_n=${1:-}
  _u_b=${2:-}
  _u_k=${3:-}
  [ $# -gt 2 ] && shift 3
  _u_p=$(msg "$_u_k" "$@")
  [ -n "$_u_p" ] || printf 'shape: no text for %s\n' "$_u_k" >&2
  _u_u=$(_door_usage "$_u_b")
  shape refused "$_u_n" "" "$_u_p
$_u_u" ""
  return 1
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
_door_register() { [ "$LA_SELF" = yes ] && cfg abs registry-engine || cfg abs registry; }

# run_call <name> [key=value ...] : the whole door, one shape out
# 0 ok, 3 a human must sign, 124 the bound was reached, 1 refused
run_call() {
  _name=${1:-}
  [ $# -gt 0 ] && shift
  channel_set "$(channel_label)"

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
  _bfam=$(lower "$_bfam")
  _rfam=$(lower "$_rfam")
  if [ -n "$_bfam" ] && [ -n "$_rfam" ] && [ "$_bfam" != "$_rfam" ]; then
    shape_fail "$_name" "" refusals.arity
    return 1
  fi

  # 5 the tools the active skill allows: the model alone is held to it
  # a permanent tool passes anywhere, the others need the toolset of the active skill
  if [ "$LA_GATE" != no ]; then skl_gate_ask "$_name" || return 1 ; fi

  # 6 arity and 7 types
  _decl=$(_door_decl "$_body")
  _args=""
  for _d in $_decl; do
    _n=${_d%%:*}
    _rest=${_d#*:}
    _t=${_rest%%:*}
    _rest=${_rest#*:}
    _vals=$(printf '%s' "${_rest%%:*}" | tr ',' ' ')
    _rest=${_rest#*:}
    _sin=${_rest%%:*}
    _req=${_rest#*:}
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
      fi
      # nothing named, nothing piped, and the body asks for it: the refusal says the shape
      if [ -z "$_v" ] && [ "$_req" != 0 ]; then
        _door_arity_fail "$_name" "$_body" refusals.arity
        return 1
      fi
    fi
    if [ -z "$_v" ] && [ "$_t" != bool ]; then
      _w=''                             # declared optional: the body decides
    else
      _w=$(args_line "$_t" "$_v" $_vals) || { _door_arity_fail "$_name" "$_body" refusals.arity; return 1; }
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

  # 9 approval : a gated body waits for a signed go; only a label whose row lifts it is exempt
  if [ "$LA_APPROVAL" != no ] && is_gated "$_body"; then
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
    _prov=0
    for _pair in "$@"; do
      case $_pair in
        "$_n"=*)
          _prov=1
          _cmd=$(printf '%s' "$_cmd" | _door_fill "{{$_n}}" "${_pair#*=}") ;;
      esac
    done
    # declared optional and not given: the hole is closed with nothing, the body decides
    if [ "$_prov" = 0 ]; then
      _r5=${_d#*:}; _r5=${_r5#*:}; _r5=${_r5#*:}
      if [ "${_r5#*:}" = 0 ]; then
        _cmd=$(printf '%s' "$_cmd" | _door_fill "{{$_n}}" "")
      fi
    fi
  done
  case $_cmd in
    *"{{"*) _door_arity_fail "$_name" "$_body" refusals.arity; return 1 ;;
  esac
  # a body that came out empty is a call that would answer ok with nothing in it
  [ -n "$_cmd" ] || { _door_arity_fail "$_name" "$_body" refusals.arity; return 1 ; }

  # 11 run: the door launches nothing. it hands the text and the arguments to the runner
  # one road for the engine, shell_exec (shell.sh): one way in, one timeout, one form.
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
