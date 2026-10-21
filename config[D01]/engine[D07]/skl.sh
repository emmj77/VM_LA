# id: E14
# role: the active skill, the active project, the tools a skill allows, and what is always allowed.

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

# skl_plan_step [name] : the step the plan holds open, four fields, TAB between them :
#   id<TAB>tool<TAB>bytes<TAB>max
# 0 an open step, 3 the plan is finished (no [progress] left), 1 a journal plan, not a route.
skl_plan_step() {
  _f=$(skl_step_file "${1:-}") || return 1
  awk '
    /^PERMANENT_TODO:[ \t]*/ {
      v = $0; sub(/^PERMANENT_TODO:[ \t]*/, "", v); gsub(/[ \t"]/, "", v)
      perm = (v == "true")
    }
    /^PLAN:[ \t]*$/ { inplan = 1; next }
    inplan && /^[^ \t]/ { inplan = 0 }
    inplan && /^[ \t]*[0-9]+:/ {
      idp = $0; sub(/^[ \t]*/, "", idp); id = idp; sub(/:.*/, "", id)
      v = $0; sub(/^[ \t]*[0-9]+:[ \t]*/, "", v); gsub(/"?[ \t]*$/, "", v); sub(/^"/, "", v)
      if (v ~ /^\[progress\]/) { step = id; line = v }
    }
    END {
      if (!perm) exit 1
      if (step == "") exit 3
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
    }' "$_f"
}

# skl_arm <name> : a skill exists before it is armed
skl_arm() {
  _n=${1:-}
  _d=$(cfg path skills) || return 1
  [ -n "$_n" ] && [ -f "$_d/$_n/skill.yaml" ] || return 1
  printf '%s\n' "$_n" | write_atomic "$(cfg abs skill_active)"
}

# skl_disarm : no skill, no tool is allowed any more
skl_disarm() {
  _f=$(cfg abs skill_active) || return 1
  [ -e "$_f" ] && gio trash -- "$_f" 2>/dev/null
  return 0
}

# skl_project_arm <name> : a project exists before it is armed
skl_project_arm() {
  _n=${1:-}
  _d=$(cfg path projects) || return 1
  [ -n "$_n" ] && [ -f "$_d/$_n/project.yml" ] || return 1
  printf '%s\n' "$_n" | write_atomic "$(cfg abs project_active)"
}

# skl_project_disarm
skl_project_disarm() {
  _f=$(cfg abs project_active) || return 1
  [ -e "$_f" ] && gio trash -- "$_f" 2>/dev/null
  return 0
}

# skl_tools_map [name] : the TOOLS map of the skill.yaml, one "key<TAB>name" per line,
# kept as it is written : the key is a local rank, it names nothing in the register.
skl_tools_map() {
  _n=${1:-$(skl_skill)}
  [ -n "$_n" ] || return 1
  _d=$(cfg path skills) || return 1
  _f="$_d/$_n/skill.yaml"
  [ -r "$_f" ] || return 1
  _flat "$_f" | awk -F'\t' '$1 ~ /^TOOLS\./ { sub(/^TOOLS\./, "", $1); printf "%s\t%s\n", $1, $2 }'
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

# skl_toolset [name] : the tool NAMES this turn may carry, one per line, and it is the ONE
# place that decides : an open step gives its single tool, a finished plan gives nothing
# (the skill is closed, only the permanent tools remain), a journal plan gives the TOOLS map.
# a name, never the key of the map : the register is read by name, and a key 200 names nothing.
skl_toolset() {
  _n=${1:-$(skl_skill)}
  [ -n "$_n" ] || return 1
  _st=$(skl_plan_step "$_n" 2>/dev/null)
  case $? in
    0)  printf '%s\n' "$(printf '%s' "$_st" | awk -F'\t' '{ print $2 }')"
        return 0 ;;
    3)  return 0 ;;   # the plan is finished: the skill opens nothing any more
  esac
  skl_tools_map "$_n" | awk -F'\t' '{ print $2 }'
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

# skl_carries <name> <id> : the armed skill carries that tool, by name (the value) or by key (200..)
skl_carries() {
  _n=${1:-}; _i=${2:-}
  _d=$(cfg path skills) || return 1
  _s=$(skl_skill) || return 1
  _f="$_d/$_s/skill.yaml"
  [ -r "$_f" ] || return 1
  _flat "$_f" | awk -F'\t' -v n="$_n" -v i="$_i" '
    $1 ~ /^TOOLS\./ { k = $1; sub(/^TOOLS\./, "", k); if (k == i || $2 == n) f = 1 }
    END { exit(f ? 0 : 1) }'
}

# tool_allowed <name> <id> : the two doors at once, the name for the master file, the id for the skill
# an open step closes the second door to its single tool : what is not named on the step's
# line is not reachable, and the door and the toolset cannot disagree (law 2402).
tool_allowed() {
  skl_permanent "$1" && return 0
  if skl_plan_is_closed 2>/dev/null; then
    _st=$(skl_plan_step 2>/dev/null) || return 1
    _t=$(printf '%s' "$_st" | awk -F'\t' '{ print $2 }')
    [ -n "$_t" ] || return 1
    [ "$_t" = "$1" ] && return 0
    return 1
  fi
  skl_carries "$1" "$2"
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

# is_gated <body> : true when the call waits for a human signature
is_gated() {
  _a=$(approval_of "${1:-}") || return 1
  case $_a in
    ""|none) return 1 ;;
  esac
  return 0
}
