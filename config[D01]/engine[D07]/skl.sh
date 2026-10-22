# id: E14
# role: the loaded set. One file for what is loaded and what it opens: the active skill, the
# active project, its plan, the toolset and the skillset built from the register, and THE GATE.
# skl_gate is the ONE place that decides what a turn may carry: the doc lock, the plan lock,
# the step of a route, the recall of a journal, the finish. The door (run.sh), the toolset
# (tool_toolset, tool_turn_scope) and the end of turn all ASK it; none of them decide.

# skl_skill : the name of the armed skill, empty when none
skl_skill() {
  _f=$(cfg abs skill_active) || return 1
  [ -r "$_f" ] || return 1
  head -n 1 -- "$_f"
}

# skl_project : the name of the armed project, empty when none
skl_project() {
  _f=$(cfg abs project_active) || return 1
  [ -r "$_f" ] || return 1
  head -n 1 -- "$_f"
}

# skl_step_file [name] : the skill.yaml of a skill, the armed one when no name is given
skl_step_file() {
  _n=${1:-$(skl_skill)}
  [ -n "$_n" ] || return 1
  _d=$(cfg path skills) || return 1
  _f="$_d/$_n/skill.yaml"
  [ -r "$_f" ] || return 1
  printf '%s\n' "$_f"
}

# skl_plan_is_closed [name] : true when the plan of the skill is a closed route (PERMANENT_TODO: true)
# a skill that says nothing is a journal, not a route : the key opens the door, it never closes it.
skl_plan_is_closed() {
  _f=$(skl_step_file "${1:-}") || return 1
  awk '
    /^PERMANENT_TODO:[ \t]*/ {
      v = $0
      sub(/^PERMANENT_TODO:[ \t]*/, "", v)
      gsub(/[ \t"]/, "", v)
      perm = (v == "true")
    }
    END { exit (perm ? 0 : 1) }' "$_f"
}

# skl_agent : the name of the agent whose plan is live, a bare token
skl_agent() {
  _a=${LA_AGENT:-}
  [ -n "$_a" ] || _a=$(cfg str agents.main jarvis 2>/dev/null)
  [ -n "$_a" ] || _a=la
  printf '%s\n' "$_a" | tr -cd 'A-Za-z0-9_-'
}

# skl_plan_file [agent] : the journal plan of an agent : ONE file, named <agent>_todo.md (all
# lowercase), in the
# state folder. a parallel session writes its own, so two plans never meet.
skl_plan_file() {
  _a=${1:-$(skl_agent)}
  [ -n "$_a" ] || return 1
  _a=$(lower "$_a")
  _t=$(cfg abs turn) || return 1
  printf '%s/%s_todo.md\n' "$(dirname "$_t")" "$_a"
}

# skl_plan_src [name] : the file the plan is READ from : the skill.yaml for a route (the human
# wrote it), the agent's file for a journal (the model writes it)
skl_plan_src() {
  _n=${1:-$(skl_skill)}
  [ -n "$_n" ] || return 1
  if skl_plan_is_closed "$_n" 2>/dev/null; then skl_step_file "$_n"; return 0; fi
  skl_plan_file
}

# skl_plan_step [name] : the step the plan holds open, four fields, TAB between them.
# a ROUTE (the plan is in the skill.yaml, the step is a mapping):
#   id<TAB>tools (csv)<TAB>close (csv)<TAB>text
# a JOURNAL (the agent's file, the step is a marked line):
#   id<TAB>tool<TAB>bytes<TAB>max
# 0 an open step, 2 no plan at all, 3 the plan is finished.
skl_plan_step() {
  _n=${1:-$(skl_skill)}
  if skl_plan_is_closed "$_n" 2>/dev/null; then _skl_step_route "$_n"; return $?; fi
  _src=$(skl_plan_src "$_n" 2>/dev/null) || return 2
  [ -r "$_src" ] || return 2
  _route=0
  awk -v route="$_route" '
    /^PLAN:[ \t]*$/ { inplan = 1; next }
    route && inplan && /^[^ \t]/ { inplan = 0 }
    (!route || inplan) && /^[ \t]*[0-9]+:/ {
      idp = $0; sub(/^[ \t]*/, "", idp); id = idp; sub(/:.*/, "", id)
      v = $0; sub(/^[ \t]*[0-9]+:[ \t]*/, "", v); gsub(/"?[ \t]*$/, "", v); sub(/^"/, "", v)
      any = 1
      if (v ~ /^\[in_progress\]/) { if (step == "") { step = id; line = v } }
      else if (v ~ /^\[todo\]/ && step == "" && todo == "") todo = id
    }
    END {
      if (step == "" && todo != "") { step = todo; line = "" }
      if (step == "") exit (any ? 3 : 2)
      tool = ""; bytes = ""; mx = ""
      if (match(line, /--[ \t]*tools:[ \t]*[A-Za-z0-9_.]+/)) {
        tool = substr(line, RSTART, RLENGTH); sub(/.*tools:[ \t]*/, "", tool)
      }
      if (match(line, /--[ \t]*bytes:[ \t]*[^ ]+/)) {
        bytes = substr(line, RSTART, RLENGTH); sub(/.*bytes:[ \t]*/, "", bytes)
      }
      if (match(line, /--[ \t]*max:[ \t]*[0-9]+/)) {
        mx = substr(line, RSTART, RLENGTH); sub(/.*max:[ \t]*/, "", mx)
      }
      printf "%s\t%s\t%s\t%s\n", step, tool, bytes, mx
    }' "$_src"
}

# _skl_step_route [name] : the open step of a route. the plan is a mapping : PLAN.at names the
# step, the step carries text, tools, close. nothing here knows a skill by its name.
_skl_step_route() {
  _f=$(skl_step_file "${1:-}") || return 2
  _flat "$_f" | awk -F'\t' '
    $1 == "PLAN.at" { at = $2 ; next }
    $1 ~ /^PLAN\.[0-9]+\./ {
      k = $1 ; sub(/^PLAN\./, "", k)
      fld = k ; sub(/^[0-9]+\./, "", fld)
      sub(/\..*$/, "", k)
      if (fld == "text") text[k] = $2
      else if (fld == "tools") tools[k] = $2
      else if (fld == "close") cls[k] = $2
    }
    END {
      n = 0 ; for (k in text) n++
      if (!n) exit 2
      if (at == "done") exit 3
      if (at == "") { for (k in text) if (at == "" || k + 0 < at + 0) at = k }
      if (!(at in text)) exit 2
      t = tools[at] ; if (t ~ /^\[/) t = substr(t, 2)
      if (t ~ /\] *$/) t = substr(t, 1, length(t) - 1)
      c = cls[at] ; if (c ~ /^\[/) c = substr(c, 2)
      if (c ~ /\] *$/) c = substr(c, 1, length(c) - 1)
      printf "%s\t%s\t%s\t%s\n", at, t, c, text[at]
    }'
}

# skl_step_tools [name] : the tools of the open step, one per line. a route names a SET, a
# journal names one tool. an empty answer means the step holds no tool of its own.
skl_step_tools() {
  _n=${1:-$(skl_skill)}
  _st=$(skl_plan_step "$_n" 2>/dev/null) || return 1
  if skl_plan_is_closed "$_n" 2>/dev/null; then
    printf '%s' "$_st" | awk -F'\t' '{ print $2 }' | tr ',' '\n' \
      | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' | grep -v '^$'
    return 0
  fi
  printf '%s' "$_st" | awk -F'\t' '$2 != "" { print $2 }'
}

# _skl_step_at <file> <id|empty> : the PLAN.at key takes that value, in the skill.yaml itself.
# inserted right under PLAN: when absent, removed when the value is empty.
_skl_step_at() {
  _f=${1:?} ; _v=${2:-}
  _t=$(tmpfile at) || return 1
  if grep -q '^[ \t][ \t]*at:' "$_f"; then
    awk -v v="$_v" '/^[ \t]+at:/ { if (v != "") printf "  at: %s\n", v ; next } { print }' "$_f" > "$_t"
  else
    [ -n "$_v" ] || return 0
    awk -v v="$_v" '/^PLAN:[ \t]*$/ && !d { print ; printf "  at: %s\n", v ; d = 1 ; next } { print }' "$_f" > "$_t"
  fi
  python3 -c 'import sys,yaml;yaml.safe_load(open(sys.argv[1],encoding="utf-8"))' "$_t" 2>/dev/null \
    || { rm -f -- "$_t" ; return 1 ; }
  write_atomic "$_f" < "$_t" || { rm -f -- "$_t" ; return 1 ; }
  rm -f -- "$_t"
}

# skl_step_close <tool> <return text> : THE engine closes the open step of a route, on the fact.
# the tool must be one the step names. the fact: status ok (the caller holds it), and either the
# step's close literals are all in the return, or the step names none and the return begins with
# "ok ". reply is the voice: its word is the fact, it closes on ok alone.
# 0 closed, and the line leaves ; 1 not this step, or not met, and the line says what is missing.
skl_step_close() {
  _t=${1:-} ; _r=${2:-}
  [ -n "$_t" ] || return 1
  [ "$LA_SELF" = yes ] && return 1
  _n=$(skl_skill 2>/dev/null) || return 1
  [ -n "$_n" ] || return 1
  skl_plan_is_closed "$_n" 2>/dev/null || return 1
  _st=$(skl_plan_step "$_n" 2>/dev/null) || return 1
  _id=$(printf '%s' "$_st" | awk -F'\t' '{ print $1 }')
  _tools=$(printf '%s' "$_st" | awk -F'\t' '{ print $2 }')
  _close=$(printf '%s' "$_st" | awk -F'\t' '{ print $3 }')
  printf '%s\n' "$_tools" | tr ',' '\n' \
    | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' | grep -qxF -- "$_t" || return 1
  if [ "$_t" != reply ]; then
    if [ -z "$_close" ]; then
      case "$_r" in
        "ok "*) ;;
        *) printf 'the step %s stays open: the return of %s does not begin with ok\n' "$_id" "$_t"
           return 1 ;;
      esac
    else
      _miss=$(printf '%s\n' "$_close" | tr ',' '\n' \
        | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' -e 's/^"//' -e 's/"$//' | grep -v '^$' \
        | while IFS= read -r _l; do
            printf '%s' "$_r" | grep -qF -- "$_l" || { printf '%s' "$_l" ; break ; }
          done)
      [ -z "$_miss" ] || { printf 'the step %s stays open: %s is not in the return of %s\n' \
                             "$_id" "$_miss" "$_t" ; return 1 ; }
    fi
  fi
  _f=$(skl_step_file "$_n") || return 1
  _next=$(_flat "$_f" | awk -F'\t' -v a="$_id" '
    $1 ~ /^PLAN\.[0-9]+\.text$/ {
      k = $1 ; sub(/^PLAN\./, "", k) ; sub(/\.text$/, "", k)
      if (k + 0 > a + 0 && (nx == "" || k + 0 < nx + 0)) nx = k
    }
    END { if (nx != "") print nx }')
  _skl_step_at "$_f" "${_next:-done}" || return 1
  if [ -n "$_next" ]; then
    printf 'ok the step %s of %s is closed: the step now open is %s\n' "$_id" "$_n" "$_next"
  else
    printf 'ok the step %s of %s is closed: the route is complete, at is done\n' "$_id" "$_n"
  fi
  return 0
}

# skl_plan_stamp : the turn number a journal plan was last touched at, empty when the header
# carries none ("400: ... -- turn N")
skl_plan_stamp() {
  _p=$(skl_plan_file 2>/dev/null) || return 1
  [ -r "$_p" ] || return 1
  sed -n 's/^400:.*--[ \t]*turn[ \t]*\([0-9][0-9]*\).*/\1/p' "$_p" | head -n 1
}

# skl_turn_no : how many turns this machine has started, read in its own trace
skl_turn_no() {
  _f=$(cfg abs trace) || { printf '0\n'; return 0; }
  [ -r "$_f" ] || { printf '0\n'; return 0; }
  _c=$(grep -c '"kind":"turn"' "$_f" 2>/dev/null)
  case $_c in ''|*[!0-9]*) _c=0 ;; esac
  printf '%s\n' "$_c"
}

# skl_doc_seen : true when the doc of the armed skill has been read this turn
skl_doc_seen() {
  _n=$(skl_skill 2>/dev/null) || return 1
  [ -n "$_n" ] || return 1
  _d=$(jq -r --arg a "$(skl_agent)" 'if (.doc|type)=="object" then (.doc[$a]//"") elif (.doc|type)=="string" then .doc else "" end' "$(cfg abs turn)" 2>/dev/null)
  [ "$_d" = "$_n" ]
}

# skl_lock : THE one tool the turn is held to, empty when the set is open.
# the order is the law : the doc, then the plan, then the step (a route), then the recall.
skl_lock() {
  _n=$(skl_skill 2>/dev/null) || return 0
  [ -n "$_n" ] || return 0
  if ! skl_doc_seen; then printf 'load_doc\n'; return 0; fi
  _st=$(skl_plan_step "$_n" 2>/dev/null)
  _rc=$?
  case $_rc in
    2) printf 'todo\n'; return 0 ;;
    3) return 0 ;;
  esac
  if skl_plan_is_closed "$_n" 2>/dev/null; then
    _set=$(skl_step_tools "$_n" 2>/dev/null)
    if [ -n "$_set" ]; then printf '%s\n' "$_set"; return 0; fi
    printf 'reply\n'
    return 0
  fi
  _pe=$(cfg num loop.todo_every 5) || _pe=5
  _at=$(skl_plan_stamp 2>/dev/null)
  _now=$(skl_turn_no)
  if [ -n "$_at" ] && [ "$_now" -gt 0 ] && [ $((_now - _at)) -ge "$_pe" ]; then
    printf 'update_todo\n'
  fi
  return 0
}

# skl_gate [tool] : the one place. no argument : the NAMES the turn may carry, one per line.
# with a name : 0 allowed, 2 the doc first, 3 the plan first, 4 not this step, 5 the recall, 1 no.
skl_gate() {
  if [ "$#" -gt 0 ]; then _skl_gate_check "$1"; return $?; fi
  _l=$(skl_lock)
  if [ -n "$_l" ]; then printf '%s\n' "$_l" reply; return 0; fi
  _n=$(skl_skill 2>/dev/null)
  [ -n "$_n" ] || { table_permanents; return 0; }
  # a loaded skill carries ITS OWN palette, and nothing of the out-of-skill set
  skl_tools_map "$_n" | awk -F'\t' '{ print $2 }' | awk 'NF && !seen[$0]++'
  return 0
}

# _skl_gate_check <tool> : the door's question, answered from the same place
_skl_gate_check() {
  _t=${1:-}
  [ -n "$_t" ] || return 1
  # these three are never refused: they live in the primary head, every turn, closed plan or not
  case "$_t" in reply|kill_proc|toolset) return 0 ;; esac
  _l=$(skl_lock)
  if [ -n "$_l" ]; then
    printf '%s\n' "$_l" | grep -qxF -- "$_t" && return 0
    [ "$_t" = reply ] && return 0
    printf '%s\n' "$_l" | grep -qxF -- load_doc && return 2
    printf '%s\n' "$_l" | grep -qxF -- todo && return 3
    printf '%s\n' "$_l" | grep -qxF -- update_todo && return 5
    return 4
  fi
  _n=$(skl_skill 2>/dev/null)
  if [ -z "$_n" ]; then
    # out of skill: the permanent basics are the toolset
    skl_permanent "$_t" && return 0
    return 1
  fi
  # a loaded skill carries its own palette; only the explicitly flagged tools ride along
  skl_carries "$_t" "" && return 0
  table_with_skill "$_t" && return 0
  [ -n "$(skl_project)" ] && table_with_project "$_t" && return 0
  return 1
}

# skl_gate_ask <tool> : the gate's word, its refusal included: the door obeys, it never translates
skl_gate_ask() {
  _skl_gate_check "${1:-}" ; case $? in
    0) return 0 ;;
    2) shape_fail "$1" "" refusals.doc_first "$(skl_skill)" ;;
    3) shape_fail "$1" "" refusals.plan_first ;;
    5) shape_fail "$1" "" refusals.overdue "$(cfg num loop.todo_every 5)" ;;
    4) shape_fail "$1" "" refusals.not_on_step ;;
    *) shape_fail "$1" "" refusals.tool_not_allowed ;;
  esac
  return 1
}

# tool_allowed <name> <id> : the door's word, from skl_gate alone
tool_allowed() {
  skl_gate "${1:-}"
  return $?
}

# skl_big_recall : one line of the head for the big plan. the three conditions hold together:
# a project is loaded, its plan carries an open step, and no journal plan is open for this agent.
# the cadence is loop.big_todo_every. it reminds, it never closes the toolset.
skl_big_recall() {
  _f=$(skl_big_file) || return 1
  _b=$(_skl_big_body "$_f")
  [ -n "$_b" ] || return 1
  printf '%s\n' "$_b" | grep -q '\[in_progress\]' || return 1
  _p=$(skl_plan_file 2>/dev/null)
  [ -n "$_p" ] || return 1
  if [ -s "$_p" ] && grep -q '\[in_progress\]\|\[todo\]' "$_p" 2>/dev/null; then return 1; fi
  _at=$(printf '%s\n' "$_b" | sed -n 's/.*-- turn \([0-9][0-9]*\).*/\1/p' | head -n 1)
  [ -n "$_at" ] || return 1
  _now=$(skl_turn_no)
  [ "$_now" -gt 0 ] 2>/dev/null || return 1
  _be=$(cfg num loop.big_todo_every 15) || _be=15
  [ $((_now - _at)) -ge "$_be" ] || return 1
  _step=$(printf '%s\n' "$_b" | grep '\[in_progress\]' | head -n 1 | sed -e 's/^ *[0-9][0-9]*: "//' -e 's/"$//' -e 's/^\[in_progress\][[:space:]]*//')
  printf 'the big plan of %s has not moved for %s turns -- its open step: %s\n' "$(skl_project)" "$((_now - _at))" "$_step"
}

# plan_status : what the head shows : the doc, the plan, and its open step
plan_status() {
  _n=$(skl_skill 2>/dev/null)
  [ -n "$_n" ] || { printf 'no skill armed\n'; skl_big_recall 2>/dev/null; return 0; }
  if skl_doc_seen; then printf 'doc: read\n'; else printf 'doc: TO READ -- load_doc first, it is the only tool of this turn\n'; fi
  _st=$(skl_plan_step "$_n" 2>/dev/null)
  case $? in
    2) printf 'plan: NONE -- todo writes %s_todo.md\n' "$(lower "$(skl_agent)")"; skl_big_recall 2>/dev/null; return 0 ;;
    3) printf 'plan: FINISHED -- the skill closes\n'; skl_big_recall 2>/dev/null; return 0 ;;
  esac
  printf '%s\n' "$(printf '%s' "$_st" | awk -F'\t' '{ printf "plan: step %s OPEN", $1; if ($2 != "") printf " -- tools: %s", $2; printf "\n" }')"
  _src=$(skl_plan_src "$_n" 2>/dev/null) || return 0
  [ -r "$_src" ] || return 0
  awk '/^[ \t]*4[0-1][0-9]:/ { print }' "$_src" | head -n 12
  skl_big_recall 2>/dev/null
  return 0
}

# --- the plan, ONE machinery for the two layers. the journal plan is the agent's file
# (state/<agent>_todo.md); the big plan is the PROJECT_PLAN section of the project's
# manifest. same line shape, same two names (in_progress, completed), same bounds, same
# move. the header carries its turn, so both recalls have their reference in the file.

# lower <text> : the lowercase word the plan file name is built from
lower() { printf '%s' "${1:-}" | tr 'A-Z' 'a-z'; }

# slug <text> : the canonical name : lowercase, digits and dashes, 40 characters at most
slug() {
  printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' \
    | sed -e 's/^-*//' -e 's/-*$//' | cut -c1-40 | sed -e 's/-*$//'
}

# _skl_plan_render <indent> <name> <goal> : the steps arrive on stdin, the numbered lines
# leave, the first step in_progress. 0 written, 10 too many steps, 11 a step too long.
_skl_plan_render() {
  _in=${1:-} ; _nm=${2:-} ; _g=${3:-}
  _ps=$(cat)
  _mx=$(cfg num loop.plan_steps 12) || _mx=12
  _mc=$(cfg num loop.plan_chars 100) || _mc=100
  _k=$(printf '%s\n' "$_ps" | grep -c '[^[:space:]]')
  [ "$_k" -le "$_mx" ] || return 10
  [ -z "$(printf '%s\n' "$_ps" | awk -v mc="$_mc" 'length($0) > mc { print ; exit }')" ] || return 11
  printf '%s400: "PLAN %s: %s -- turn %s"\n' "$_in" "${_nm:-$(skl_agent)}" "$_g" "$(skl_turn_no)"
  _j=0 ; _i=400
  printf '%s\n' "$_ps" | while IFS= read -r _l; do
    [ -n "$(printf '%s' "$_l" | tr -d '[:space:]')" ] || continue
    _j=$((_j+1)) ; _i=$((_i+1))
    if [ "$_j" -eq 1 ]; then _m=in_progress ; else _m=todo ; fi
    printf '%s%s: "[%s] %s"\n' "$_in" "$_i" "$_m" "$_l"
  done
}

# _skl_plan_move <in_progress|completed> : the plan body arrives on stdin, the moved body
# leaves, its header restamped with the turn. 0 moved, 2 the state, 9 the last step closed.
_skl_plan_move() {
  case ${1:-completed} in in_progress|completed) ;; *) return 2 ;; esac
  awk -v st="${1:-completed}" -v tn="$(skl_turn_no)" '
    function restamp(s) { if (match(s, /--[ \t]*turn[ \t]*[0-9]+/)) return substr(s, 1, RSTART - 1) "-- turn " tn substr(s, RSTART + RLENGTH) ; return s }
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        l = lines[i]
        if (l ~ /^[ \t]*400:/) { lines[i] = restamp(l) ; continue }
        if (l ~ /\[in_progress\]/ && ip == 0) ip = i
        if (l ~ /\[todo\]/ && td == 0) td = i
      }
      if (st == "completed") {
        if (ip) { sub(/\[in_progress\]/, "[completed]", lines[ip])
                  if (td) sub(/\[todo\]/, "[in_progress]", lines[td]) ; else fin = 1 }
        else if (td) sub(/\[todo\]/, "[in_progress]", lines[td])
        else fin = 1
      } else {
        if (td && !ip) sub(/\[todo\]/, "[in_progress]", lines[td])
      }
      for (i = 1; i <= NR; i++) print lines[i]
      if (fin) exit 9
    }'
}

# skl_plan_write <name> <goal> <points> : todo writes the journal plan of the agent.
# returns 0 written, 1 the arguments, 10 too many steps, 11 a step too long, 12 one is open.
skl_plan_write() {
  _nm=${1:-} ; _g=${2:-} ; _ps=${3:-}
  [ -n "$_g" ] || return 1
  [ -n "$(printf '%s' "$_ps" | tr -d '[:space:]')" ] || return 1
  _p=$(skl_plan_file) || return 1
  if [ -s "$_p" ] && grep -q '\[in_progress\]\|\[todo\]' "$_p" 2>/dev/null; then return 12 ; fi
  _b=$(tmpfile todo) || return 1
  printf '%s\n' "$_ps" | _skl_plan_render "" "$_nm" "$_g" > "$_b"
  _rc=$?
  [ "$_rc" = 0 ] || { rm -f "$_b" ; return "$_rc" ; }
  [ -s "$_b" ] || { rm -f "$_b" ; return 1 ; }
  write_atomic "$_p" < "$_b" || { rm -f "$_b" ; return 1 ; }
  rm -f "$_b"
  printf 'ok the plan of %s is open: %s steps -- %s\n' "$(skl_agent)" "$(grep -c '\[in_progress\]\|\[todo\]' "$_p")" "$_p"
}

# skl_plan_advance <in_progress|completed> : update_todo moves the journal plan.
# completed : the open step closes, the next one opens ; the last one closes the plan, the
# file goes, the skill unloads. in_progress : the step stays, the header is restamped.
# returns 0 moved, 2 the state, 4 a route (the machine advances it), 5 no plan, 9 finished.
skl_plan_advance() {
  _st=${1:-completed}
  case $_st in in_progress|completed) ;; *) return 2 ;; esac
  _n=$(skl_skill 2>/dev/null) || return 5
  [ -n "$_n" ] || return 5
  skl_plan_is_closed "$_n" 2>/dev/null && return 4
  _p=$(skl_plan_file) || return 5
  [ -s "$_p" ] || return 5
  _new=$(_skl_plan_move "$_st" < "$_p")
  _rc=$?
  case $_rc in
    9) gio trash -- "$_p" 2>/dev/null || rm -f -- "$_p"
       skl_disarm
       printf '%s\n' "$(msg plan_done "$_n")"
       return 9 ;;
    0) ;; *) return 5 ;;
  esac
  [ -n "$_new" ] || return 5
  printf '%s\n' "$_new" | write_atomic "$_p" || return 5
  printf 'ok the plan moved: %s -- %s steps in progress\n' "$_st" "$(grep -c '\[in_progress\]' "$_p" 2>/dev/null)"
}

# --- the BIG plan : the project's chantier, in its manifest, under PROJECT_PLAN.
# it is the second layer. it is CHANGED, and it erases itself at its last step.
# it never holds the project: the project unloads whenever the human says so.

# skl_big_file : the project.yml of the armed project, empty when no project is loaded
skl_big_file() {
  _p=$(skl_project) || return 1
  [ -n "$_p" ] || return 1
  _d=$(project_dir "$_p") || return 1
  _f="$_d/project.yml"
  [ -r "$_f" ] || return 1
  printf '%s\n' "$_f"
}

# _skl_big_body <file> : the body lines of the PROJECT_PLAN section
_skl_big_body() {
  awk '/^PROJECT_PLAN:/ { inb = 1 ; next } inb && /^[^ \t]/ { inb = 0 } inb { print }' "${1:?}"
}

# _skl_big_put <file> <bodyfile> : the PROJECT_PLAN body becomes that file, the section
# appears if absent. an empty body file empties the section.
_skl_big_put() {
  _f=${1:?} ; _b=${2:?}
  _t=$(tmpfile big) || return 1
  awk -v B="$_b" '
    BEGIN { while ((getline l < B) > 0) body[++nb] = l }
    /^PROJECT_PLAN:/ { print ; seen = 1 ; for (i = 1 ; i <= nb ; i++) print body[i] ; next }
    seen && /^[^ \t]/ { seen = 0 }
    seen { next }
    { print }
  ' "$_f" > "$_t"
  if ! grep -q '^PROJECT_PLAN:' "$_t"; then
    { printf 'PROJECT_PLAN:\n' ; cat "$_b" ; } >> "$_t"
  fi
  [ -s "$_t" ] || { rm -f "$_t" ; return 1 ; }
  mv -f "$_t" "$_f"
}

# skl_big_write <name> <goal> <points> [change] : big_todo writes, change_big_todo replaces.
# same bounds, same renderer. returns 0, 10/11 the bounds, 14 no project, 15 one is open.
skl_big_write() {
  _nm=${1:-} ; _g=${2:-} ; _ps=${3:-} ; _chg=${4:-}
  [ -n "$_g" ] || return 1
  [ -n "$(printf '%s' "$_ps" | tr -d '[:space:]')" ] || return 1
  _f=$(skl_big_file) || return 14
  if [ -z "$_chg" ] && _skl_big_body "$_f" | grep -q '\[in_progress\]' 2>/dev/null; then return 15 ; fi
  _b=$(tmpfile bigb) || return 1
  printf '%s\n' "$_ps" | _skl_plan_render "  " "$_nm" "$_g" > "$_b"
  _rc=$?
  [ "$_rc" = 0 ] || { rm -f "$_b" ; return "$_rc" ; }
  _n=$(grep -c '\[in_progress\]\|\[todo\]' "$_b")
  _skl_big_put "$_f" "$_b" || { rm -f "$_b" ; return 1 ; }
  rm -f "$_b"
  if [ -n "$_chg" ]; then _w=changed ; else _w=open ; fi
  printf 'ok the big plan of %s is %s: %s steps -- %s\n' "$(skl_project)" "$_w" "$_n" "$_f"
}

# skl_big_advance <in_progress|completed> : update_big_todo moves the project's plan.
# the last completed erases it. returns 0 moved, 2 the state, 5 no plan, 9 erased, 14 no project.
skl_big_advance() {
  _st=${1:-completed}
  case $_st in in_progress|completed) ;; *) return 2 ;; esac
  _f=$(skl_big_file) || return 14
  _b0=$(_skl_big_body "$_f")
  [ -n "$_b0" ] || return 5
  _new=$(printf '%s\n' "$_b0" | _skl_plan_move "$_st")
  _rc=$?
  case $_rc in
    9) _skl_big_put "$_f" /dev/null || return 5
       printf 'ok the big plan of %s is finished and erased: its last step closed, the section stays empty\n' "$(skl_project)"
       return 9 ;;
    0) ;; *) return 5 ;;
  esac
  _b=$(tmpfile biga) || return 5
  printf '%s\n' "$_new" > "$_b"
  _skl_big_put "$_f" "$_b" || { rm -f "$_b" ; return 5 ; }
  rm -f "$_b"
  printf 'ok the big plan moved: %s\n' "$_st"
}

# skl_arm <name> : a skill exists before it is armed
skl_arm() {
  _n=${1:-}
  _d=$(cfg path skills) || return 1
  [ -n "$_n" ] && [ -f "$_d/$_n/skill.yaml" ] || return 1
  printf '%s\n' "$_n" | write_atomic "$(cfg abs skill_active)"
}

# skl_disarm : no skill, no tool is allowed any more, and the plan file of the agent goes with it
skl_disarm() {
  _f=$(cfg abs skill_active) || return 1
  [ -e "$_f" ] && { gio trash -- "$_f" 2>/dev/null || rm -f -- "$_f"; }
  _p=$(skl_plan_file 2>/dev/null)
  [ -n "$_p" ] && [ -e "$_p" ] && { gio trash -- "$_p" 2>/dev/null || rm -f -- "$_p"; }
  return 0
}

# skl_turn_end : the turn is over. an open plan keeps its skill armed (the plan resumes next
# turn: nobody quits a skill with the plan unfinished); a finished plan or none, the skill goes.
# The MODEL never unloads: no unload_skill tool exists. The human keeps `skill unload`.
skl_turn_end() {
  _n=$(skl_skill 2>/dev/null) || return 0
  [ -n "$_n" ] || return 0
  skl_plan_step "$_n" >/dev/null 2>&1
  case $? in
    0) return 0 ;;
  esac
  skl_disarm
}

# skl_project_arm <name> : a project exists before it is armed
skl_project_arm() {
  _n=${1:-}
  _p=$(project_dir "$_n") || return 1
  [ -n "$_n" ] && [ -f "$_p/project.yml" ] || return 1
  printf '%s\n' "$_n" | write_atomic "$(cfg abs project_active)"
}

# skl_project_disarm
skl_project_disarm() {
  _f=$(cfg abs project_active) || return 1
  [ -e "$_f" ] && gio trash -- "$_f" 2>/dev/null
  return 0
}

# skl_tools_map [name] : the SKILL_TOOL_SET map of the skill.yaml, one "key<TAB>name" per line,
# kept as it is written : the key is a local rank, it names nothing in the register.
skl_tools_map() {
  _n=${1:-$(skl_skill)}
  [ -n "$_n" ] || return 1
  _d=$(cfg path skills) || return 1
  _f="$_d/$_n/skill.yaml"
  [ -r "$_f" ] || return 1
  _flat "$_f" | awk -F'\t' '$1 ~ /^SKILL_TOOL_SET\./ { sub(/^SKILL_TOOL_SET\./, "", $1); printf "%s\t%s\n", $1, $2 }'
}

# skl_workspace [name] : where the armed skill writes, relative to the project root
skl_workspace() {
  _n=${1:-$(skl_skill)}
  [ -n "$_n" ] || return 1
  _d=$(cfg path skills) || return 1
  _f="$_d/$_n/skill.yaml"
  [ -r "$_f" ] || return 1
  _w=$(_flat "$_f" | awk -F'\t' '$1 == "WRITABLE_WORKSPACE.workspace" { print $2; exit }')
  [ -n "$_w" ] || return 1
  printf '%s\n' "$_w"
}

# skl_in_toolset <id|name> : true when the armed skill carries that tool
skl_in_toolset() {
  _id=${1:-}
  [ -n "$_id" ] || return 1
  skl_tools_map | while IFS="$(printf '\t')" read -r _k _t; do
    { [ "$_k" = "$_id" ] || [ "$_t" = "$_id" ]; } && { echo yes; break; }
  done | grep -q yes
}

# skl_toolset [name] : kept for its callers : the gate's names, one per line
skl_toolset() {
  skl_gate
}

# skl_permanent <name> : allowed whatever the skill, because the TOOL says so in the register
skl_permanent() {
  _n=${1:-}
  [ -n "$_n" ] || return 1
  table_perm "$_n" && return 0
  if [ -n "$(skl_skill)" ] && table_with_skill "$_n"; then return 0; fi
  if [ -n "$(skl_project)" ] && table_with_project "$_n"; then return 0; fi
  return 1
}

# table_perm <name> : the TOOL says it rides every turn, in the register - the one source
table_perm() {
  table_index || return 1
  printf '%s\n' "$TABLE_INDEX" | awk -F'|' -v n="${1:-}" '$2 == n && $6 == "true" { f = 1 } END { exit !f }'
}

# table_with_skill <name> : allowed as soon as ANY skill is armed
table_with_skill() {
  table_index || return 1
  printf '%s\n' "$TABLE_INDEX" | awk -F'|' -v n="${1:-}" '$2 == n && $7 == "true" { f = 1 } END { exit !f }'
}

# table_with_project <name> : allowed as soon as a project is loaded
table_with_project() {
  table_index || return 1
  printf '%s\n' "$TABLE_INDEX" | awk -F'|' -v n="${1:-}" '$2 == n && $8 == "true" { f = 1 } END { exit !f }'
}

# table_permanents : the names that ride every turn, one per line, in the register's order
table_permanents() {
  table_index || return 1
  printf '%s\n' "$TABLE_INDEX" | awk -F'|' '$6 == "true" { print $2 }'
}

# skl_carries <name> <id> : the armed skill carries that tool, by name (the value) or by key (200..)
skl_carries() {
  _n=${1:-}; _i=${2:-}
  _d=$(cfg path skills) || return 1
  _s=$(skl_skill) || return 1
  _f="$_d/$_s/skill.yaml"
  [ -r "$_f" ] || return 1
  _flat "$_f" | awk -F'\t' -v n="$_n" -v i="$_i" '
    $1 ~ /^SKILL_TOOL_SET\./ { k = $1; sub(/^SKILL_TOOL_SET\./, "", k); if (k == i || $2 == n) f = 1 }
    END { exit(f ? 0 : 1) }'
}

# approval_of <body> : what the body says a human must carry, empty when nothing
approval_of() {
  [ -r "${1:-}" ] || return 1
  awk '
    /^[ \t]*approval:[ \t]*/ {
      v = $0
      sub(/^[ \t]*approval:[ \t]*/, "", v)
      sub(/[ \t]+$/, "", v)
      gsub(/["\047]/, "", v)
      print v
      exit
    }' "$1"
}

# skill_approval <skill.yaml> : true when the skill must be signed before it loads, false otherwise
skill_approval() {
  [ -r "${1:-}" ] || { printf 'false\n' ; return 0 ; }
  _v=$(sed -n 's/^[[:space:]]*APPROVAL:[[:space:]]*//p' "$1" | head -n 1 \
       | sed -e 's/#.*$//' -e 's/["'\'']//g' | tr -d '[:space:]' | tr 'A-Z' 'a-z')
  [ "$_v" = true ] && printf 'true\n' || printf 'false\n'
}

# is_gated <body> : true when the call waits for a human signature
is_gated() {
  _a=$(approval_of "${1:-}") || return 1
  case $_a in
    ""|none) return 1 ;;
  esac
  return 0
}
