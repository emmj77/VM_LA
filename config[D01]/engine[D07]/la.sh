#!/bin/sh
# id: E08
# role: the door of the engine. it finds the root, loads the engine, reads the command table of the master file, and hands over.
# the commands are data (commands: in la_config.yaml): the cli, the dashboard and the app read the same list, nobody doubles it.

_la_here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
LA_DIR=$_la_here
export LA_DIR
unset _la_here
. "$LA_DIR/boot.sh" || exit 1

la_usage() {
  printf '%s\n' \
    "la <tool> [key=value ...]     call a tool through the door" \
    "la engine <tool> [k=v ...]    the same, as the engine" \
    "" \
    "the commands (master file, commands:):"
  for _id in $(table_ids "$LA_CONF"); do
    _nm=$(table_field "$LA_CONF" "$_id" name) || continue
    [ -n "$_nm" ] || continue
    _ag=$(table_field "$LA_CONF" "$_id" arg)
    _tc=$(table_field "$LA_CONF" "$_id" tool)
    printf '  %-18s %s%s\n' "$_nm" "${_ag:+<$_ag> }" "${_tc:+(tool $_tc)}"
  done
}

_la_new() {
  _s=$(cfg path state) || exit 1
  _t=$(date +%s)
  for _f in note.txt request.txt reply.stream board.tmp; do
    [ -f "$_s/$_f" ] || continue
    mv "$_s/$_f" "$_s/new.$_t.$_f" || exit 1
  done
  printf 'new turn : the state of the last one is put aside (%s)\n' "$_t"
}

_la_stop() {
  _s=$(cfg path state) || exit 1
  _t=$(date +%s)
  for _f in request.txt say.queue say.done; do
    [ -f "$_s/$_f" ] || continue
    mv "$_s/$_f" "$_s/stop.$_t.$_f" || exit 1
  done
  printf 'stop : the queued request and say are put aside (%s)\n' "$_t"
}

# la_dispatch <word ...> : the longest command name wins, the rest is its argument
la_dispatch() {
  _line="$*"
  _best=""; _bw=0
  for _id in $(table_ids "$LA_CONF"); do
    _nm=$(table_field "$LA_CONF" "$_id" name) || continue
    case $_line in
      "$_nm"|"$_nm "*) ;;
      *) continue ;;
    esac
    _w=$(printf '%s' "$_nm" | wc -w)
    [ "$_w" -gt "$_bw" ] && { _bw=$_w; _best=$_id; }
  done
  if [ -z "$_best" ]; then
    run_call "$@"
    return $?
  fi
  _act=$(table_field "$LA_CONF" "$_best" act)
  _tool=$(table_field "$LA_CONF" "$_best" tool)
  _argn=$(table_field "$LA_CONF" "$_best" arg)
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
  case $_act in
    usage)        la_usage ;;
    version)      printf 'LA %s, master %s\n' "$(cfg str date)" "$LA_CONF" ;;
    map)          LA_FROM=engine; export LA_FROM
                  run_call engine.map op=rebuild | jq -r '.result // .' 2>/dev/null || : ;;
    new)          _la_new ;;
    stop)         _la_stop ;;
    skill_unload) skl_disarm && printf 'no skill loaded\n' ;;
    service)      LA_FROM=engine; export LA_FROM
                  run_call engine.service "name=${1:-}" ;;
    tool_call)    run_call "$@" ;;
    *)            printf 'no act: %s\n' "$_act" >&2; exit 1 ;;
  esac
}

case ${1:-} in
  -h|--help)  la_usage ;;
  engine)     LA_FROM=engine; export LA_FROM; shift; run_call "$@" ;;
  "")         LA_FROM=engine; export LA_FROM; run_call engine.turn "text=$(cat)" ;;
  *)          la_dispatch "$@" ;;
esac
