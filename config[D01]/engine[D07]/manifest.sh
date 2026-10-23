# id: E04
# role: the manifest of the project. the project says where its root is, what it forbids, and what it wants said instead.

# manifest_file [project] : the manifest of the project, in its declaration, zone SPEC
manifest_file() {
  manifest_decl "${1:-}"
}

# manifest_decl [project] : the declaration of the project, always project.yml
manifest_decl() {
  _n=${1:-$(active_project)}
  [ -n "$_n" ] || return 1
  _p=$(tree_project "$_n") || return 1
  [ -f "$_p/project.yml" ] || return 1
  printf '%s\n' "$_p/project.yml"
}

# manifest_root [project] : the root the project declares, relative to the home of the machine
manifest_root() {
  _f=$(manifest_decl "$1") || return 1
  _p=$(config_flat "$_f" | awk -F'\t' '$1 == "path" { print $2; exit }')
  [ -n "$_p" ] || return 1
  case $_p in
    /*) realpath -m -- "$_p" ;;
    *)  realpath -m -- "$HOME/$_p" ;;
  esac
}

# manifest_get <key> [project] : one field of the declaration
manifest_get() {
  _k=${1:-}
  [ -n "$_k" ] || return 1
  _f=$(manifest_decl "$2") || return 1
  config_flat "$_f" | awk -F'\t' -v k="$_k" '$1 == k { print $2; exit }'
}

# manifest_rule <name> [project] : one value under RULES
manifest_rule() {
  manifest_get "RULES.${1:-}" "${2:-}"
}

# manifest_law [project] : what the project wants said when a call is refused, one line per entry
manifest_law() {
  _f=$(manifest_decl "$1") || return 1
  config_flat "$_f" | awk -F'\t' '$1 ~ /^ERROR\./ { print $2 }'
}

# manifest_summary [project] : the lines of the project, in the order of their rank
manifest_summary() {
  _f=$(manifest_decl "$1") || return 1
  config_flat "$_f" | awk -F'\t' '$1 ~ /^SUMMARY\./ { n = $1; sub(/^SUMMARY\./, "", n); print n "\t" $2 }' |
    sort -n | cut -f2-
}

# manifest_skills [project] : the skills the project carries, in the order of their rank
manifest_skills() {
  _f=$(manifest_decl "$1") || return 1
  config_flat "$_f" | awk -F'\t' '$1 ~ /^RULES\.skillset\./ { n = $1; sub(/^RULES\.skillset\./, "", n); print n "\t" $2 }' |
    sort -n | cut -f2-
}

# the name the document gives this brick
manifest_path() { manifest_file "$@"; }
