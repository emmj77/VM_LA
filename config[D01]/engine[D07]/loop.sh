# id: E09
# the trace belongs to its body: the loop calls it, it never writes the channel
_ltr() { printf '%s %s\n' "${1:-step}" "${2:-}" | run_call engine.trace op=line >/dev/null; }
# role: the turn. one at a time, the steps of the pipeline in order, the calls repeated while there are some.

# loop_steps : the pipeline split where it repeats: before call, the cycle, after the end
# _step_end : the last step of the cycle. `advance` when the pipeline carries it (the plan
# moves there), `tools` otherwise : the order of the file alone decides, nothing else.
_step_end() {
  for _s in $(step_list); do
    [ "$_s" = advance ] && { printf 'advance\n'; return 0; }
  done
  printf 'tools\n'
}

loop_before() {
  _seen=0
  for _s in $(step_list); do
    [ "$_s" = call ] && { _seen=1; continue; }
    [ "$_seen" = 0 ] && printf '%s\n' "$_s"
  done
}
loop_cycle() {
  _end=$(_step_end)
  _seen=0
  for _s in $(step_list); do
    if [ "$_s" = call ]; then _seen=1; fi
    if [ "$_seen" = 1 ]; then printf '%s\n' "$_s"; fi
    [ "$_s" = "$_end" ] && break
  done
}
loop_after() {
  _end=$(_step_end)
  _seen=0
  for _s in $(step_list); do
    [ "$_s" = "$_end" ] && { _seen=1; continue; }
    [ "$_seen" = 1 ] && printf '%s\n' "$_s"
  done
}

# loop_busy : true when another turn holds the mark
loop_busy() {
  _f=$(cfg abs turn_pid) || return 1
  [ -r "$_f" ] || return 1
  _p=$(head -n 1 -- "$_f" 2>/dev/null)
  [ -n "$_p" ] || return 1
  kill -0 "$_p" 2>/dev/null
}

# loop_mark : this shell owns the turn
loop_mark() {
  _f=$(cfg abs turn_pid) || return 1
  printf '%s\n' "$$" | write_atomic "$_f"
  _s=$(cfg abs stop) || return 1
  [ -e "$_s" ] && rm -f -- "$_s"
  return 0
}

# loop_release : the turn is over, the mark goes
loop_release() {
  _f=$(cfg abs turn_pid) || return 1
  [ -e "$_f" ] && rm -f -- "$_f"
  return 0
}

# loop_turn <prompt> : the whole turn
loop_turn() {
  PROMPT=${1:-}
  export PROMPT
  [ -n "$PROMPT" ] || { shape_fail "" "" refusals.arity prompt; return 1; }
  loop_busy && { shape_fail "" "" refusals.arity; return 1; }
  loop_mark || return 1
  _tf=$(cfg abs turn)
  [ -s "$_tf" ] && _turn_set '.doc = ""' 2>/dev/null

  _ltr turn "start"
  _t0=$(date +%s)
  _maxc=$(cfg num loop.max_calls) || _maxc=0
  _maxs=$(cfg num loop.max_seconds) || _maxs=0
  _calls=0
  _status=ok

  for _s in $(loop_before); do
    step_run "$_s" || { _status=failed; break; }
  done

  _mt=$(cfg num loop.max_turns 400) || _mt=400
  while [ "$_status" = ok ]; do
    _tn=$(skl_turn_no)
    if [ "$_mt" -gt 0 ] && [ "${_tn:-0}" -ge "$_mt" ]; then
      _ltr step "stopped: turn $_tn, the bound $_mt"
      _status=stopped
      break
    fi
    _before=$(_turn_get '.calls | length')
    for _s in $(loop_cycle); do
      step_run "$_s" || { _status=failed; break; }
    done
    [ "$_status" = ok ] || break
    _rep=$(_turn_get '[.calls[] | select(.tool == "reply")] | length')
    [ "${_rep:-0}" -gt 0 ] 2>/dev/null && { _ltr step "stopped: the answer is said"; break; }
    _after=$(_turn_get '.calls | length')
    if [ "$_after" -le "$_before" ]; then
      # the model called nothing: it is asked again for an answer, even empty,
      # so the human can speak at any time (turn retry)
      _try=$(_turn_get '.retry // 0')
      _rt=$(cfg num loop.retry 1) || _rt=1
      if [ "${_try:-0}" -lt "$_rt" ] 2>/dev/null; then
        _turn_set '.retry = ((.retry // 0) + 1)'
        _ltr step "retry: a reply is asked again"
        continue
      fi
      break
    fi
    _calls=$_after
    if [ "$_maxc" -gt 0 ] && [ "$_calls" -ge "$_maxc" ]; then
      _ltr step "stopped: $_calls calls, the bound"
      break
    fi
    if [ "$_maxs" -gt 0 ] && [ $(( $(date +%s) - _t0 )) -ge "$_maxs" ]; then
      _ltr step "stopped: the time bound"
      break
    fi
    [ -e "$(cfg abs stop)" ] && { _status=stopped; break; }
  done

  [ "$_status" = ok ] && for _s in $(loop_after); do
    step_run "$_s" || {
      [ "$_s" = reply ] || _status=failed
      break
    }
  done

  skl_turn_end
  loop_release
  _ltr step "turn done in $(( $(date +%s) - _t0 ))s, $_calls calls, $_status"
  [ "$_status" = ok ] || return 1
  return 0
}
