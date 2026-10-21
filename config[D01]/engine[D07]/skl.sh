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

# skl_toolset [name] : the tool ids the skill carries, one per line (the TOOLS map of its skill.yaml)
skl_toolset() {
  _n=${1:-$(skl_skill)}
  [ -n "$_n" ] || return 1
  _d=$(cfg path skills) || return 1
  _f="$_d/$_n/skill.yaml"
  [ -r "$_f" ] || return 1
  _flat "$_f" | awk -F'\t' '$1 ~ /^TOOLS\./ { sub(/^TOOLS\./, "", $1); print $1 }'
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

# skl_in_toolset <id> : true when the armed skill carries that tool id
skl_in_toolset() {
  _id=${1:-}
  [ -n "$_id" ] || return 1
  skl_toolset | while read -r _t; do
    [ "$_t" = "$_id" ] && { echo yes; break; }
  done | grep -q yes
}

# skl_permanent <name> : allowed whatever the skill, because the master file says so
skl_permanent() {
  _n=${1:-}
  [ -n "$_n" ] || return 1
  for _t in $(cfg list permanent); do [ "$_t" = "$_n" ] && return 0; done
  if [ -n "$(skl_skill)" ]; then
    for _t in $(cfg list with_skill); do [ "$_t" = "$_n" ] && return 0; done
  fi
  if [ -n "$(skl_project)" ]; then
    for _t in $(cfg list with_project); do [ "$_t" = "$_n" ] && return 0; done
  fi
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
tool_allowed() {
  skl_permanent "$1" && return 0
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
