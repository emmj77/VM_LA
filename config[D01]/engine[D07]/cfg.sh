# id: E06
# role: the only reader of the master file. every value the code uses comes from here.

# _flat_raw <fichier> : la table aplatie, telle que le maitre l ecrit
_flat_raw() {
  _f=${1:-$LA_CONF}
  awk '
    /^[ \t]*#/ { next }
    /^[ \t]*$/ { next }
    {
      match($0, /^ */); ind = RLENGTH
      if (skip >= 0 && ind > skip) { next }
      skip = -1
      d = int(ind / 2) + 1
      line = substr($0, ind + 1)
      if (line ~ /^- /) {
        v = substr(line, 3)
        sub(/[ \t]+$/, "", v)
        if (path[d-1] != "") { list[path[d-1]] = (list[path[d-1]] == "" ? v : list[path[d-1]] " " v) }
        next
      }
      i = index(line, ":")
      if (i == 0) { next }
      k = substr(line, 1, i - 1)
      v = substr(line, i + 1)
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]+$/, "", v)
      path[d] = k
      for (j = d + 1; j < 40; j++) { path[j] = "" }
      if (v == "|" || v == ">") { skip = ind; next }
      if (v != "") {
        if (v ~ /^".*"$/ && length(v) > 1) { v = substr(v, 2, length(v) - 2) }
        else if (v ~ /^\047.*\047$/ && length(v) > 1) { v = substr(v, 2, length(v) - 2) }
        print join(d) "\t" v
      }
    }
    function join(n,   s, j) {
      s = path[1]
      for (j = 2; j <= n; j++) { s = s "." path[j] }
      return s
    }
    END { for (k in list) { print k "\t[" list[k] "]" } }
  ' "$_f"
}

# LE MAITRE EST LU UNE FOIS PAR PROCESSUS : trente-cinq lectures d un fichier de quarante
# kilo, c etait une seconde a chaque commande. La signature (taille.date) dit si le maitre a
# bouge ; sinon la table deja aplatie est resservie, sous-shells compris.
_flat() {
  _f=${1:-$LA_CONF}
  if [ "$_f" = "$LA_CONF" ] && [ -n "${LA_FLAT_SIG:-}" ]; then
    _sg=$(stat -c '%s.%Y' "$_f" 2>/dev/null)
    [ "$_sg" = "$LA_FLAT_SIG" ] && { printf '%s\n' "$LA_FLAT"; return 0; }
  fi
  _t=$(_flat_raw "$_f")
  if [ "$_f" = "$LA_CONF" ]; then
    LA_FLAT=$_t
    LA_FLAT_SIG=$(stat -c '%s.%Y' "$_f" 2>/dev/null)
    export LA_FLAT LA_FLAT_SIG
  fi
  printf '%s\n' "$_t"
}

# conf_str <dotted.key> : the value, empty if absent
conf_str() {
  _v=$(_flat | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }')
  if [ -n "$_v" ]; then printf '%s\n' "$_v"; return 0; fi
  if [ $# -gt 1 ]; then printf '%s\n' "$2"; return 0; fi
  return 1
}

# conf_num <dotted.key> : the value if it is a number
conf_num() {
  _v=$(conf_str "$1")
  case $_v in
    ''|*[!0-9]*) [ $# -gt 1 ] && { printf '%s\n' "$2"; return 0; }
                 return 1 ;;
    *) printf '%s\n' "$_v" ;;
  esac
}

# conf_list <dotted.key> : the items, one space between them
conf_list() {
  _v=$(conf_str "$1")
  _v=${_v#\[}
  _v=${_v%\]}
  printf '%s\n' "$_v" | tr ',' ' ' | tr -s ' ' | sed 's/^ *//; s/ *$//'
}

# conf_has <dotted.key> : true when the key carries something
conf_has() {
  _flat | awk -F'\t' -v k="$1" '$1 == k || index($1, k ".") == 1 { f = 1 } END { exit(f ? 0 : 1) }'
}

# _cfg_exts : les extensions que l index connait, lues une fois et gardees
_cfg_exts() {
  if [ -n "${LA_EXTS:-}" ]; then printf '%s\n' "$LA_EXTS"; return 0; fi
  LA_EXTS=$(conf_list extensions 2>/dev/null | tr '\n' ' ')
  export LA_EXTS
  printf '%s\n' "$LA_EXTS"
}

# the tree, read as the document writes it: a name, its id, then the comment.
# a directory carries [Dxx] in its name; a file carries its id in the third column.
# the path is rebuilt from the indentation, so the reader never needs the box drawing.
_cfg_tree() {
  # the INDEX is the only list: folders and files, each with its id.
  _exts=$(_cfg_exts)

  awk -v want="$1" -v kind="$2" -v exts="$_exts" '
    BEGIN { gsub(/-/, "_", want) }
    function k_of(n,   k, ext) {
      k = n
      sub(/\[D[0-9][0-9]\]$/, "", k)
      if (kind == "dir") return k
      if (k ~ /^\./) k = substr(k, 2)
      if (match(k, /\.[A-Za-z0-9]+$/)) {
        ext = substr(k, RSTART + 1)
        if (index(" " exts " ", " " ext " ") > 0) k = substr(k, 1, RSTART - 1)
      }
      gsub(/\./, "_", k)
      gsub(/-/, "_", k)
      return k
    }
    /^dirs:/  { s = "dir";  next }
    /^files:/ { s = "file"; next }
    /^  - \{id: "/ {
      if (s != kind) next
      n = $0
      sub(/^.*name: "/, "", n)
      sub(/".*$/, "", n)
      if (k_of(n) == want) { print n; exit }
    }' "$LA_INDEX"
}

# the name becomes a place: the tree is walked once and the map is kept, so the engine looks a
# place up instead of walking the disk on every call. THE INDEX CARRIES NO PATH (MOUSSA, 21/10).
_cfg_map_build() {
  _m=$LA_STATE/tree.map
  { find "$ROOT" \( -name .git -o -name node_modules \) -prune -o \( -type f -print -o -type d -print \) ; } 2>/dev/null \
    | while IFS= read -r _x; do
        printf '%s\t%s\n' "$(basename -- "$_x")" "${_x#$ROOT/}"
      done | sort -u > "$_m.new" 2>/dev/null
  [ -s "$_m.new" ] && mv "$_m.new" "$_m"
}

_cfg_locate() {
  # AT STARTUP, LA_STATE IS NOT KNOWN YET: the search is direct, once.
  if [ -z "${LA_STATE:-}" ]; then
    _pat=$(printf '%s' "$1" | sed 's/[][*?\\]/\\&/g')
    find "$LA_HOME" \( -name .git -o -name node_modules \) -prune -o -name "$_pat" -print -quit 2>/dev/null \
      | sed "s|^$(printf '%s' "$ROOT" | sed 's/[][*.^$\\/]/\\&/g')/||"
    return 0
  fi
  _m=$LA_STATE/tree.map
  [ -s "$_m" ] || _cfg_map_build
  # a name absent from the map triggers NO rebuild: the map is made at
  # startup and remade by the map command, otherwise every unknown key cost a walk.
  awk -F'\t' -v n="$1" '$1 == n { print $2; exit }' "$_m"
}

cfg_dir()  { _p=$(_cfg_tree "$1" dir);  [ -n "$_p" ] || _p=$(_cfg_world "$1"); printf "%s\n" "$_p"; }
cfg_file() { _p=$(_cfg_tree "$1" file); [ -n "$_p" ] || _p=$(_cfg_world "$1"); printf "%s\n" "$_p"; }

# the world section answers for the dirs outside this one
_cfg_world() {
  awk -v want="$1" '
    /^world:/ { inw = 1; next }
    inw && /^  - / {
      line = $0
      if (match(line, /key: [a-z_]+/)) {
        k = substr(line, RSTART + 5, RLENGTH - 5)
        if (k == want && match(line, /path: "[^"]*"/)) { print substr(line, RSTART + 7, RLENGTH - 8); exit }
      }
    }
  ' "$LA_CONF"
}

# _cfg_tree_list : every entry of the tree, "kind<TAB>path<TAB>id", in the order of the document.
# the id is the third column; the population (a tool body) carries none until the build names it.
_cfg_tree_list() {
  awk '
    /^dirs:/  { s = "dir";  next }
    /^files:/ { s = "file"; next }
    /^  - \{id: "/ {
      id = $0; sub(/^  - \{id: "/, "", id); sub(/".*$/, "", id)
      n  = $0; sub(/^.*name: "/, "", n);   sub(/".*$/, "", n)
      if (s != "" && n != "") print s "\t" n "\t" id
    }' "$LA_INDEX"
}

# _cfg_here <path of the tree> : the path made whole against the root, absolute left alone.
# one resolver: the tree is written by the document, the root is where it stands.
_cfg_here() {
  _p=${1:-}
  [ -n "$_p" ] || return 1
  case $_p in
    /*) printf '%s\n' "$_p" ;;
    *)  printf '%s/%s\n' "$ROOT" "$_p" ;;
  esac
}

# cfg_path <key> : a directory key resolved against the root
# _cfg_family <name>: the id the index gives that name. the letter says the zone,
# and a state file (N) lives in state, even before it exists on disk.
_cfg_family() {
  awk -v n="$1" '
    /^  - \{id: "/ {
      id = $0; sub(/^  - \{id: "/, "", id); sub(/".*/, "", id)
      nm = $0; sub(/^.*name: "/, "", nm); sub(/".*$/, "", nm)
      if (nm == n) { print id; exit }
    }' "$LA_INDEX" 2>/dev/null
}

# _cfg_place <resolver> <key> : one name in, one place out, in the state or in the tree
_cfg_place() {
  _n=$("$1" "${2:-}") || return 1
  [ -n "$_n" ] || return 1
  case $(_cfg_family "$_n") in N[0-9]*) printf '%s/%s\n' "$LA_STATE" "$_n" ; return 0 ;; esac
  _p=$(_cfg_locate "$_n") ; [ -n "$_p" ] || _p=$_n
  realpath -m -- "$(_cfg_here "$_p")"
}

# cfg_path <folder key> : a folder of the tree. cfg_abs <file key> : a file, against the root
cfg_path() { _cfg_place cfg_dir "${1:-}" ; }
cfg_abs() { _cfg_place cfg_file "${1:-}" ; }

# cfg <verb> <arg> : the one word the rest of the engine uses
cfg() {
  _v=${1:-}
  [ $# -gt 0 ] && shift
  case $_v in
    str)  conf_str "$@" ;;
    num)  conf_num "$@" ;;
    list) conf_list "$@" ;;
    has)  conf_has "$@" ;;
    dir)  cfg_dir "$@" ;;
    file) cfg_file "$@" ;;
    path) cfg_path "$@" ;;
    abs)  cfg_abs "$@" ;;
    tree) _cfg_tree_list "$@" ;;
    map)  _cfg_map_build ;;
    here) _cfg_here "$@" ;;
    # where <name>: the name becomes a place. the index carries no path any more.
    where) _q=$(_cfg_locate "$1"); [ -n "$_q" ] && _cfg_here "$_q" ;;
    *)    return 2 ;;
  esac
}

# channel_set <label> : the row of the table, read in one pass and kept for the process. an
# undeclared label takes the model row, and an empty cell counts as yes: the door stays shut.
# channel_label : the label of the caller, read once, right here. an empty label is the model, so
# a caller that says nothing is held to the strict row; no other file spells LA_FROM.
channel_label() { printf '%s' "${LA_FROM:-model}" ; }

channel_set() {
  _l=${1:-model}
  set -- $(awk -v l="$_l" '/^channels:/{c=1;next} c&&/^[^ #]/{c=0} c&&/^  [a-z]/{r=$1;sub(/:.*/,"",r);next} c&&r&&/^    /{k=$1;sub(/:.*/,"",k);v=$2;sub(/#.*/,"",v);gsub(/[ \t]/,"",v);if(r==l)g[k]=v;else if(r=="model")m[k]=v} END{n=split("self gate capture approval",K," ");for(i=1;i<=n;i++){v=(K[i] in g)?g[K[i]]:((K[i] in m)?m[K[i]]:(K[i]=="self"?"no":"yes"));printf "%s ",(v=="no"||v=="off"||v=="false"||v=="0")?"no":"yes"}}' "${LA_CONF:?}")
  LA_SELF=${1:-yes} ; LA_GATE=${2:-yes} ; LA_CAPTURE=${3:-yes} ; LA_APPROVAL=${4:-yes}
  LA_CHANNEL=$_l
  # no export: a decision belongs to the process of the door that took it; a child that changes
  # label calls channel_set itself, an inherited flag would answer for the parent label
}

# project_dir <name> : the folder of a project, even when its name carries an id (la[D22])
project_dir() {
  _n=${1:-}
  [ -n "$_n" ] || return 1
  _base=$(cfg path projects) || return 1
  [ -d "$_base/$_n" ] && { printf '%s\n' "$_base/$_n"; return 0; }
  for _c in "$_base"/*/; do
    _b=$(basename -- "$_c") ; _b=${_b%%[*}
    [ "$_b" = "$_n" ] && { printf '%s\n' "${_c%/}"; return 0; }
  done
  return 1
}

# skill_rule <key> [skill] : RULES.<key> of the armed skill, empty when no skill is armed
skill_rule() {
  _k=${1:-}
  _n=${2:-}
  [ -n "$_n" ] || _n=$(head -n 1 -- "$(cfg abs skill_active)" 2>/dev/null)
  [ -n "$_n" ] || return 0
  _f="$(cfg path skills)/$_n/skill.yaml"
  [ -r "$_f" ] || return 0
  _flat "$_f" 2>/dev/null | awk -F'\t' -v k="RULES.$_k" '$1 == k { print $2 ; exit }'
}
