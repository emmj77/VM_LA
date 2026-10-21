# id: E04
# role: the canon. the project says where its root is, what it forbids, and what it wants said instead.

# canon_file [project] : the canon of the project, spec.yaml when it exists, project.yml otherwise
canon_file() {
  _n=${1:-$(skl_project)}
  [ -n "$_n" ] || return 1
  _d=$(cfg path projects) || return 1
  if [ -f "$_d/$_n/spec.yaml" ]; then
    printf '%s\n' "$_d/$_n/spec.yaml"
  else
    [ -f "$_d/$_n/project.yml" ] || return 1
    printf '%s\n' "$_d/$_n/project.yml"
  fi
}

# canon_decl [project] : the declaration of the project, always project.yml
canon_decl() {
  _n=${1:-$(skl_project)}
  [ -n "$_n" ] || return 1
  _d=$(cfg path projects) || return 1
  [ -f "$_d/$_n/project.yml" ] || return 1
  printf '%s\n' "$_d/$_n/project.yml"
}

# canon_root [project] : the root the project declares, relative to the home of the machine
canon_root() {
  _f=$(canon_decl "$1") || return 1
  _p=$(_flat "$_f" | awk -F'\t' '$1 == "path" { print $2; exit }')
  [ -n "$_p" ] || return 1
  case $_p in
    /*) realpath -m -- "$_p" ;;
    *)  realpath -m -- "$HOME/$_p" ;;
  esac
}

# canon_get <key> [project] : one field of the declaration
canon_get() {
  _k=${1:-}
  [ -n "$_k" ] || return 1
  _f=$(canon_decl "$2") || return 1
  _flat "$_f" | awk -F'\t' -v k="$_k" '$1 == k { print $2; exit }'
}

# canon_rule <name> [project] : one value under RULES
canon_rule() {
  canon_get "RULES.${1:-}" "${2:-}"
}

# canon_law [project] : what the project wants said when a call is refused, one line per entry
canon_law() {
  _f=$(canon_decl "$1") || return 1
  _flat "$_f" | awk -F'\t' '$1 ~ /^ERROR\./ { print $2 }'
}

# canon_summary [project] : the lines of the project, in the order of their rank
canon_summary() {
  _f=$(canon_decl "$1") || return 1
  _flat "$_f" | awk -F'\t' '$1 ~ /^SUMMARY\./ { n = $1; sub(/^SUMMARY\./, "", n); print n "\t" $2 }' |
    sort -n | cut -f2-
}

# canon_skills [project] : the skills the project carries, in the order of their rank
canon_skills() {
  _f=$(canon_decl "$1") || return 1
  _flat "$_f" | awk -F'\t' '$1 ~ /^SKILLS\./ { n = $1; sub(/^SKILLS\./, "", n); print n "\t" $2 }' |
    sort -n | cut -f2-
}

# the name the document gives this brick
canon_path() { canon_file "$@"; }
