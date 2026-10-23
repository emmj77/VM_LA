# id: E19
# role: the only place that launches a body: one bound, one return code, one shape, and the step closed.

# exec_body <name> <command text> [arg ...] : THE ONLY PLACE THAT LAUNCHES A BODY.
# the door hands the text and the arguments; here it gets a limit, a return code, one shape.
exec_body() {
  _x=${1:?exec_body: a name is required}
  _c=${2:-}
  [ $# -gt 1 ] && shift 2
  # a body may set its own bound (timeout: in its header), otherwise the master's
  _to=${LA_TIMEOUT:-$(config num limits.engine_timeout)} || _to=600
  [ -n "$_to" ] || _to=600
  _eng=$(tree path engine) || return 1
  _pre=". '$_eng/boot.sh'"
  # a bound of 0: no bound at all. the call keeps the hand and holds it (a service).
  _lim="timeout $_to"
  [ "$_to" = 0 ] && _lim=""
  # the label and the four decisions of THIS call travel with the body: one body, one label,
  # nothing inherited from a parent that spoke for another label
  _out=$(LA_FROM="$(channel_label)" LA_DIR="$_eng" ROOT="$ROOT" W="$W" LA_HOME="$LA_HOME" LA_CONF="$LA_CONF" \
    LA_SELF="$LA_SELF" LA_GATE="$LA_GATE" LA_CAPTURE="$LA_CAPTURE" LA_APPROVAL="$LA_APPROVAL" \
    $_lim dash -c "$_pre
$_c" dash "$@" 2>&1)
  _rc=$?
  if [ "$_rc" -eq 124 ]; then
    shape timeout "$_x" "$_c" "$(msg refusals.timeout "$_to")" "124"
    return 124
  fi
  # an engine call feeds the turn, not the model: no cap, no returns entry
  if [ "$LA_CAPTURE" != no ]; then _res=$(printf '%s' "$_out" | cap_return "$_x")
  else _res=$_out ; fi
  # a route closes its step on the fact it has just read: the engine, never the model
  if [ "$_rc" -eq 0 ]; then
    _sc=$(todo_step_close "$_x" "$_res" 2>/dev/null)
    [ -n "$_sc" ] && _res=$(printf '%s\n%s' "$_res" "$_sc")
  fi
  [ "$_rc" -eq 0 ] && { shape_ok "$_x" "$_c" "$_res" "0"; return 0; }
  shape refused "$_x" "$_c" "$_res" "$_rc"
  return "$_rc"
}
