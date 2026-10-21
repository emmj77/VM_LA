# id: E13
# role: the machine layer. a machine, an operation, arguments: one command line. no address is written here.

# shell_addr <machine> <field> : one address of a machine, from the master file
shell_addr() {
  cfg str "machine.${1:-}.${2:-}"
}

# shell_bin <machine> : the binary of that machine, root+cli when it is split
shell_bin() {
  _m=${1:-}
  _b=$(shell_addr "$_m" bin)
  if [ -n "$_b" ]; then
    printf '%s\n' "$_b"
    return 0
  fi
  _r=$(shell_addr "$_m" root) || return 1
  _c=$(shell_addr "$_m" cli) || return 1
  [ -n "$_r" ] && [ -n "$_c" ] || return 1
  printf '%s/%s\n' "$_r" "$_c"
}

# shell_cmd <machine> <operation> [arg ...] : the command line, built from the master file only
shell_cmd() {
  _m=${1:-}
  _o=${2:-}
  [ $# -gt 1 ] && shift 2
  case "$_m.$_o" in
    llama.serve)
      _b=$(shell_bin llama) || return 1
      _p=$(cfg num models.port) || return 1
      _h=$(cfg str models.host) || _h=127.0.0.1
      # ONE server for every model: router mode. Every model setting lives in the preset
      # (ctx, threads, gpu layers, cache, sleep): a global -c/-t/--n-gpu-layers would
      # overwrite it for every child.
      _d=$(cfg str models.dir) || return 1
      _pre=$(cfg str models.preset) || _pre="$_d/models.ini"
      _pre=$(cfg here "$_pre")
      _mx=$(cfg num models.max 1) || _mx=1
      printf '%s --models-preset %s --models-max %s --reranking --embeddings --port %s --host %s' \
        "$(args_word "$_b")" "$(args_word "$_pre")" "$_mx" "$_p" "$_h"
      ;;
    llama.health)
      _p=$(cfg num models.port) || return 1
      _h=$(cfg str models.host) || _h=127.0.0.1
      _ht=$(cfg num limits.health_timeout) || _ht=3
      printf 'curl -fsS -m %s http://%s:%s/health' "$_ht" "$_h" "$_p"
      ;;
    blender.script)
      _b=$(shell_bin blender) || return 1
      [ $# -ge 2 ] || return 1
      printf '%s -b %s -P %s' "$(args_word "$_b")" "$(args_word "$1")" "$(args_word "$2")"
      ;;
    asr.serve)
      _b=$(shell_bin asr) || return 1
      _r=$(shell_addr asr root) || return 1
      _mod=$(shell_addr asr model) || return 1
      _p=$(cfg num units.asr.port) || return 1
      _h=$(cfg str models.host) || _h=127.0.0.1
      printf '%s serve --asr-model %s --host %s --port %s' \
        "$(args_word "$_b")" "$(args_word "$_r/$_mod")" "$_h" "$_p"
      ;;
    asr.file)
      _b=$(shell_bin asr) || return 1
      _r=$(shell_addr asr root) || return 1
      _mod=$(shell_addr asr model) || return 1
      [ $# -ge 1 ] || return 1
      printf '%s -m %s -f %s' "$(args_word "$_b")" "$(args_word "$_r/$_mod")" "$(args_word "$1")"
      ;;
    tts.say)
      _u=$(shell_addr tts uv) || return 1
      _mod=$(shell_addr tts model) || return 1
      [ $# -ge 2 ] || return 1
      printf '%s run --directory %s sherpa-onnx-offline-tts --vits-model=%s/model.onnx --output-filename=%s %s' \
        "$(args_word "$_u")" "$(args_word "$_mod")" "$(args_word "$_mod")" "$(args_word "$2")" "$(args_word "$1")"
      ;;
    *) return 2 ;;
  esac
}

# shell_run <machine> <operation> [arg ...] : the same line, run, bounded, shaped
# shell_exec <name> <command text> [arg ...] : THE ONLY PLACE THAT LAUNCHES A BODY.
# the door hands the text and the arguments; here it gets a limit, a return code, one shape.
shell_exec() {
  _x=${1:?shell_exec: a name is required}
  _c=${2:-}
  [ $# -gt 1 ] && shift 2
  # a body may set its own bound (timeout: in its header), otherwise the master's
  _to=${LA_TIMEOUT:-$(cfg num limits.engine_timeout)} || _to=600
  [ -n "$_to" ] || _to=600
  _eng=$(cfg path engine) || return 1
  _pre=". '$_eng/boot.sh'"
  # a bound of 0: no bound at all. the call keeps the hand and holds it (a service).
  _lim="timeout $_to"
  [ "$_to" = 0 ] && _lim=""
  _out=$(LA_FROM="${LA_FROM:-model}" LA_DIR="$_eng" ROOT="$ROOT" W="$W" LA_HOME="$LA_HOME" LA_CONF="$LA_CONF" \
    $_lim dash -c "$_pre
$_c" dash "$@" 2>&1)
  _rc=$?
  if [ "$_rc" -eq 124 ]; then
    shape timeout "$_x" "$_c" "$(msg refusals.timeout "$_to")" ""
    return 124
  fi
  # an engine call feeds the turn, not the model: no cap, no returns entry
  case ${LA_FROM:-model} in
    engine|human) _res=$_out ;;
    *) _res=$(printf '%s' "$_out" | cap_return "$_x") ;;
  esac
  [ "$_rc" -eq 0 ] && { shape_ok "$_x" "$_c" "$_res" ""; return 0; }
  shape refused "$_x" "$_c" "$_res" ""
  return "$_rc"
}

shell_run() {
  _m=${1:-}
  _o=${2:-}
  [ $# -gt 1 ] && shift 2
  _c=$(shell_cmd "$_m" "$_o" "$@") || { shape_fail "shell.$_m.$_o" "" refusals.tool_unknown "$_m.$_o"; return 1; }
  shell_exec "shell.$_m.$_o" "$_c"
}

# krita_url : the krita service, checked before anything is asked of it
krita_url() {
  _h=$(cfg str machine.krita.host) || return 1
  _p=$(cfg num machine.krita.port) || return 1
  [ -n "$_h" ] && [ -n "$_p" ] || { printf '%s\n' "$(msg krita_noport)" >&2; return 1; }
  _s="http://$_h:$_p"
  curl -sf --max-time 10 "$_s/health" >/dev/null 2>&1 \
    || { printf '%s\n' "$(msg krita_down "$_s")" >&2; return 1; }
  printf '%s\n' "$_s"
}
