# id: E15
# role: one step of the turn. the order is conf/pipeline.yaml, the work is a body.

_turn_file() { cfg abs turn; }
_turn_get() { jq -r "${1:-.}" "$(_turn_file)" 2>/dev/null; }
_turn_set() { jq "$1" "$(_turn_file)" | write_atomic "$(_turn_file)"; }
_turn_set_json() { jq --argjson v "$2" "$1" "$(_turn_file)" | write_atomic "$(_turn_file)"; }

# trace_line <kind> <text> : the ONE way to write a line of the journal. the tools call it
# instead of carrying their own copy of the pipe.
trace_line() { printf '%s %s\n' "${1:-step}" "${2:-}" | run_call engine.trace op=line >/dev/null; }

# step_list : the order, from the pipeline file. no name is written here.
step_list() {
  _f=$(cfg abs pipeline) || return 1
  [ -r "$_f" ] || return 1
  _flat "$_f" | awk -F'\t' '$1 == "steps" { print $2; exit }' | tr -d '[]' | tr ',' ' '
}

# prompt_text : what the human asked, as one string
prompt_text() {
  _p=$(_turn_get '.prompt')
  [ -n "$_p" ] || _p=${PROMPT:-}
  printf '%s' "$_p"
}

# step_run <name> : a step is a body of the family turn, and the door is the only way in
step_run() {
  _n=${1:-}
  [ -n "$_n" ] || { shape_fail "" "" refusals.arity; return 1; }
  _line=$(run_call "turn.$_n")
  _st=$(shape_get "$_line" status)
  printf '%s\n' "$_line"
  case $_st in
    ok)      return 0 ;;
    timeout) return 124 ;;
    *)       return 1 ;;
  esac
}
