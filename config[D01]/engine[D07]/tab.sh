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

# table_ids <table> : every id of the table, one per line, block style
table_ids() {
  [ -f "${1:-}" ] || return 1
  awk '/^[ \t]*- id:[ \t]*/ { v = $0; sub(/^[ \t]*- id:[ \t]*/, "", v); gsub(/["\047]/, "", v); sub(/[ \t].*$/, "", v); print v }' "$1"
}

# table_index : the whole table as id|tool|family|guardrail|description|permanent|with_skill|with_project
table_index() {
  [ -n "${TABLE_INDEX+x}" ] && return 0
  TABLE_INDEX=
  # the register is found here when TABLE is not carried: one source, no caller has to pose it
  _tix=${TABLE:-$(cfg abs registry 2>/dev/null)}
  [ -f "${_tix:-}" ] || return 1
  TABLE_INDEX=$(awk '
    function emit() {
      if (id == "") return
      printf "%s|%s|%s|%s|%s|%s|%s|%s\n", id, tool, fam, gu, d, pm, ws, wp
    }
    /^[ \t]*- id:[ \t]*/ { emit() ; id = $0 ; sub(/^[ \t]*- id:[ \t]*/, "", id) ; gsub(/["\047]/, "", id) ; sub(/[ \t].*$/, "", id) ; tool = "" ; fam = "" ; gu = "" ; d = "" ; pm = "" ; ws = "" ; wp = "" ; next }
    /^[ \t]*(name|tool):[ \t]*/      { tool = $0 ; sub(/^[ \t]*(name|tool):[ \t]*/, "", tool) ; gsub(/"/, "", tool) ; next }
    /^[ \t]*family:[ \t]*/    { fam = $0 ; sub(/^[ \t]*family:[ \t]*/, "", fam) ; gsub(/"/, "", fam) ; next }
    /^[ \t]*guardrail:[ \t]*/ { gu = $0 ; sub(/^[ \t]*guardrail:[ \t]*/, "", gu) ; gsub(/"/, "", gu) ; next }
    /^[ \t]*permanent:[ \t]*/ { pm = $0 ; sub(/^[ \t]*permanent:[ \t]*/, "", pm) ; gsub(/"/, "", pm) ; next }
    /^[ \t]*with_skill:[ \t]*/ { ws = $0 ; sub(/^[ \t]*with_skill:[ \t]*/, "", ws) ; gsub(/"/, "", ws) ; next }
    /^[ \t]*with_project:[ \t]*/ { wp = $0 ; sub(/^[ \t]*with_project:[ \t]*/, "", wp) ; gsub(/"/, "", wp) ; next }
    /^[ \t]*(description|desc):[ \t]*/ { d = $0 ; sub(/^[ \t]*(description|desc):[ \t]*/, "", d) ; sub(/^"/, "", d) ; sub(/"$/, "", d) ; next }
    END { emit() }
  ' "$_tix" 2>/dev/null)
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

# ----- the command table: one list in the master file, one dispatcher for every door -----

cmd_ids() {
  table_ids "${1:-$LA_CONF}"
}

cmd_get() {
  table_field "${3:-$LA_CONF}" "$1" "$2" 2>/dev/null
}

# cmd_usage : the list as it is written in the master file
cmd_usage() {
  printf '%s\n' \
    "la <tool> [key=value ...]     call a tool through the door" \
    "la engine <tool> [k=v ...]    the same, as the engine" \
    "" \
    "the commands (master file, commands:):"
  for _id in $(cmd_ids); do
    _n=$(cmd_get "$_id" name); [ -n "$_n" ] || continue
    _ag=$(cmd_get "$_id" arg)
    _tc=$(cmd_get "$_id" tool)
    printf '  %-18s %s%s\n' "$_n" "${_ag:+<$_ag> }" "${_tc:+(tool $_tc)}"
  done
}

# cmd_slash : the first word of every command, once, in order: the page legend
cmd_slash() {
  for _id in $(cmd_ids); do
    _n=$(cmd_get "$_id" name); [ -n "$_n" ] || continue
    printf '/%s\n' "${_n%% *}"
  done | awk '!seen[$0]++'
}

# cmd_has <first word> : is it the first word of a command?
cmd_has() {
  _h="$1"
  for _id in $(cmd_ids); do
    _n=$(cmd_get "$_id" name); [ -n "$_n" ] || continue
    [ "${_n%% *}" = "$_h" ] && return 0
  done
  return 1
}

cmd_new_turn() {
  _s=$(cfg path state) || return 1
  _t=$(date +%s)
  for _f in note.txt request.txt reply.stream board.tmp; do
    [ -f "$_s/$_f" ] || continue
    mv "$_s/$_f" "$_s/new.$_t.$_f" || return 1
  done
  printf 'new turn : the state of the last one is put aside (%s)\n' "$_t"
}

# cmd_run <word ...> : the longest command name wins, the rest is its argument; an unknown word is a tool
cmd_run() {
  _line="$*"
  _best=""; _bw=0
  for _id in $(cmd_ids); do
    _n=$(cmd_get "$_id" name); [ -n "$_n" ] || continue
    case $_line in
      "$_n"|"$_n "*) ;;
      *) continue ;;
    esac
    _w=$(printf '%s' "$_n" | wc -w)
    [ "$_w" -gt "$_bw" ] && { _bw=$_w; _best=$_id; }
  done
  if [ -z "$_best" ]; then
    run_call "$@"
    return $?
  fi
  _act=$(cmd_get "$_best" act)
  _tool=$(cmd_get "$_best" tool)
  _argn=$(cmd_get "$_best" arg)
  [ "$_bw" -gt 0 ] && shift "$_bw"
  if [ -n "$_tool" ]; then
    LA_FROM=human; export LA_FROM
    if [ -n "$_argn" ]; then
      run_call "$_tool" "$_argn=${1:-}"
    else
      run_call "$_tool"
    fi
    return $?
  fi
  LA_FROM=engine; export LA_FROM
  case $_act in
    usage)        cmd_usage ;;
    version)      printf 'LA %s, master %s\n' "$(cfg str date)" "$LA_CONF" ;;
    map)          run_call engine.map op=rebuild | jq -r '.result // .' 2>/dev/null || : ;;
    new)          cmd_new_turn ;;
    stop)         printf 'stop\n' | write_atomic "$(cfg abs stop)" && printf 'ok the turn is asked to stop\n' ;;
    listen_on)    run_call engine.residents op=listen-on | jq -r '.result // .' 2>/dev/null ;;
    listen_off)   run_call engine.residents op=listen-off | jq -r '.result // .' 2>/dev/null ;;
    start)        gio trash -- "$(cfg abs stop)" 2>/dev/null; printf 'ok the stop is lifted\n' ;;
    skill_unload) skl_disarm && printf 'no skill loaded\n' ;;
    service)      run_call engine.service "name=${1:-}" ;;
    model)        if [ -n "${1:-}" ]; then
                    printf '%s' "$1" | run_call engine.switch op=take | jq -r '.result // .' 2>/dev/null
                  else
                    run_call engine.switch op=list | jq -r '.result // .' 2>/dev/null
                  fi ;;
    doctor)       run_call engine.doctor "op=${1:-short}" ;;
    app)          run_call engine.commands op=app ;;
    cmds)
      # le panneau, dans le terminal : whiptail le parcourt aux fleches, Entree l execute
      if [ ! -t 0 ] || [ ! -t 1 ]; then printf 'note cmds wants a terminal\n'; exit 0; fi
      set -- --title "LA - les commandes" --menu "fleches pour choisir, Entree pour lancer" \
             26 84 18 --output-fd 1
      for _i in $(cmd_ids); do
        _n=$(cmd_get "$_i" name)
        [ -n "$_n" ] || continue
        _w=$(cmd_get "$_i" act)
        [ -n "$_w" ] || _w=$(cmd_get "$_i" tool)
        set -- "$@" "$_n" "${_w:-commande}"
      done
      _sel=$(whiptail "$@" 3>&1 1>&2 2>&3) || exit 0
      [ -n "$_sel" ] && cmd_run "$_sel"
      ;;
    tool_call)    LA_FROM=human; export LA_FROM; run_call "$@" ;;
    *)            printf 'no act: %s\n' "$_act" >&2; return 1 ;;
  esac
}
