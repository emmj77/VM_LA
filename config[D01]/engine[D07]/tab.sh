# id: E16
# role: the register. the five names of the document, the bodies proven in the old engine:
# table_block, table_index, block_by_id, body_of, count. one file in, lines out, TABLE carries it.

# table_block <table> <id> : the lines of one entry, from "id:" to the line before the next entry
# the indent of the table does not matter: the anchor is "- id:" wherever it sits.
table_block() {
  _t=${1:-}
  _id=${2:-}
  [ -f "$_t" ] || return 1
  awk -v id="$_id" '
    /^[ \t]*- id:[ \t]*/ {
      if (on) { exit }
      v = $0
      sub(/^[ \t]*- id:[ \t]*/, "", v)
      gsub(/["\047]/, "", v)
      sub(/[ \t].*$/, "", v)
      if (v == id) on = 1
    }
    on { print }
    END { if (!on) exit 1 }
  ' "$_t"
}

# table_entry <table> <id|name> : the entry, whether it is given by its id or by its name
table_entry() {
  _t=${1:-}
  _w=${2:-}
  [ -f "$_t" ] || return 1
  _id=$(awk -v w="$_w" '
    /^[ \t]*- id:[ \t]*/ {
      v = $0 ; sub(/^[ \t]*- id:[ \t]*/, "", v) ; gsub(/["\047]/, "", v) ; sub(/[ \t].*$/, "", v)
      id = v
      if (v == w && byid == "") byid = v
      next
    }
    /^[ \t]*(name|tool):[ \t]*/ {
      v = $0 ; sub(/^[ \t]*(name|tool):[ \t]*/, "", v) ; gsub(/"/, "", v) ; sub(/[ \t]+$/, "", v)
      if (v == w && byname == "") byname = id
    }
    END { if (byid != "") print byid ; else if (byname != "") print byname }' "$_t")
  [ -n "$_id" ] || return 1
  table_block "$_t" "$_id"
}

# table_field <table> <id|name> <key> : one value of one entry, empty when it is not there
table_field() {
  table_entry "${1:-}" "${2:-}" | awk -v k="${3:-}" '
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      sub(/^-[ \t]+/, "", line)
      if (length(line) > 0 && index(line, k ":") == 1) {
        v = substr(line, length(k) + 2)
        sub(/^[ \t]+/, "", v)
        sub(/[ \t]+$/, "", v)
        if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2) }
        else if (v ~ /^\047.*\047$/) { v = substr(v, 2, length(v) - 2) }
        print v
        exit
      }
    }'
}

# table_field_list <table> <id|name> <key> : a bracketed list, one word per line
table_field_list() {
  table_field "${1:-}" "${2:-}" "${3:-}" | tr -d '[]{}' | tr ',' '\n' |
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
}

# table_keys <table> <id|name> : the keys of one entry, one per line
table_keys() {
  table_entry "${1:-}" "${2:-}" | awk '
    /^[ \t]*(name|tool):[ \t]*/ { next }
    {
      line = $0 ; sub(/^[ \t]+/, "", line)
      i = index(line, ":")
      if (i > 0) { print substr(line, 1, i - 1) }
    }'
}

# table_index : the whole table as id|tool|family|guardrail|description, kept once in TABLE_INDEX
table_index() {
  [ -n "${TABLE_INDEX+x}" ] && return 0
  TABLE_INDEX=
  [ -f "${TABLE:-}" ] || return 1
  TABLE_INDEX=$(awk '
    function emit() {
      if (id == "") return
      printf "%s|%s|%s|%s|%s\n", id, tool, fam, gu, d
    }
    /^[ \t]*- id:[ \t]*/ { emit() ; id = $0 ; sub(/^[ \t]*- id:[ \t]*/, "", id) ; gsub(/["\047]/, "", id) ; sub(/[ \t].*$/, "", id) ; tool = "" ; fam = "" ; gu = "" ; d = "" ; next }
    /^[ \t]*(name|tool):[ \t]*/      { tool = $0 ; sub(/^[ \t]*(name|tool):[ \t]*/, "", tool) ; gsub(/"/, "", tool) ; next }
    /^[ \t]*family:[ \t]*/    { fam = $0 ; sub(/^[ \t]*family:[ \t]*/, "", fam) ; gsub(/"/, "", fam) ; next }
    /^[ \t]*guardrail:[ \t]*/ { gu = $0 ; sub(/^[ \t]*guardrail:[ \t]*/, "", gu) ; gsub(/"/, "", gu) ; next }
    /^[ \t]*(description|desc):[ \t]*/ { d = $0 ; sub(/^[ \t]*(description|desc):[ \t]*/, "", d) ; sub(/^"/, "", d) ; sub(/"$/, "", d) ; next }
    END { emit() }
  ' "$TABLE" 2>/dev/null)
  return 0
}

# block_by_id <id> : the block of an id in the table carried by TABLE, one pass, no temp file
block_by_id() {
  awk -v id="${1:-}" '
    /^[ \t]*- id:[ \t]*/ {
      if (on) exit
      v = $0
      sub(/^[ \t]*- id:[ \t]*/, "", v)
      gsub(/["\047]/, "", v)
      sub(/[ \t].*$/, "", v)
      if (v == id) on = 1
    }
    on { print }
    END { if (!on) exit 1 }
  ' "$TABLE"
}

# body_of <id> : what the document calls the block of an id
body_of() { block_by_id "$@"; }

# count <file> : how big it is, "bytes lines" on the standard output
count() {
  _f=${1:-}
  _o=$(wc -c < "$_f" 2>/dev/null | tr -d ' ')
  _l=$(wc -l < "$_f" 2>/dev/null | tr -d ' ')
  case $_o in ''|*[!0-9]*) _o=0 ;; esac
  case $_l in ''|*[!0-9]*) _l=0 ;; esac
  if [ -s "$_f" ] && [ -n "$(tail -c 1 "$_f" 2>/dev/null)" ]; then _l=$((_l + 1)); fi
  printf '%s %s' "$_o" "$_l"
}
