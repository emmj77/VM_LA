# id: E13
# role: the machine layer. a machine, an operation, arguments: one command line. no address is written here.

# machine_addr <machine> <field> : one address of a machine, from the master file
machine_addr() {
  config str "machine.${1:-}.${2:-}"
}

# machine_bin <machine> : the binary of that machine, root+cli when it is split
machine_bin() {
  _m=${1:-}
  _b=$(machine_addr "$_m" bin)
  if [ -n "$_b" ]; then
    printf '%s\n' "$_b"
    return 0
  fi
  _r=$(machine_addr "$_m" root) || return 1
  _c=$(machine_addr "$_m" cli) || return 1
  [ -n "$_r" ] && [ -n "$_c" ] || return 1
  printf '%s/%s\n' "$_r" "$_c"
}

# machine_cmd <machine> <operation> [arg ...] : the command line, built from the master file only
machine_cmd() {
  _m=${1:-}
  _o=${2:-}
  [ $# -gt 1 ] && shift 2
  case "$_m.$_o" in
    llama.serve)
      _b=$(machine_bin llama) || return 1
      _p=$(config num models.port) || return 1
      _h=$(config str models.host) || _h=127.0.0.1
      # ONE server for every model: router mode. Every model setting lives in the preset
      # (ctx, threads, gpu layers, cache, sleep): a global -c/-t/--n-gpu-layers would
      # overwrite it for every child.
      _d=$(config str models.dir) || return 1
      _pre=$(config str models.preset) || _pre="$_d/models.ini"
      _pre=$(tree here "$_pre")
      _mx=$(config num models.max 1) || _mx=1
      printf '%s --models-preset %s --models-max %s --reranking --embeddings --port %s --host %s' \
        "$(args_word "$_b")" "$(args_word "$_pre")" "$_mx" "$_p" "$_h"
      ;;
    llama.health)
      _p=$(config num models.port) || return 1
      _h=$(config str models.host) || _h=127.0.0.1
      _ht=$(config num limits.health_timeout) || _ht=3
      printf 'curl -fsS -m %s http://%s:%s/health' "$_ht" "$_h" "$_p"
      ;;
    blender.script)
      _b=$(machine_bin blender) || return 1
      [ $# -ge 2 ] || return 1
      printf '%s -b %s -P %s' "$(args_word "$_b")" "$(args_word "$1")" "$(args_word "$2")"
      ;;
    asr.serve)
      _b=$(machine_bin asr) || return 1
      _r=$(machine_addr asr root) || return 1
      _mod=$(machine_addr asr model) || return 1
      _p=$(config num units.asr.port) || return 1
      _h=$(config str models.host) || _h=127.0.0.1
      printf '%s serve --asr-model %s --host %s --port %s' \
        "$(args_word "$_b")" "$(args_word "$_r/$_mod")" "$_h" "$_p"
      ;;
    asr.file)
      _b=$(machine_bin asr) || return 1
      _r=$(machine_addr asr root) || return 1
      _mod=$(machine_addr asr model) || return 1
      [ $# -ge 1 ] || return 1
      printf '%s -m %s -f %s' "$(args_word "$_b")" "$(args_word "$_r/$_mod")" "$(args_word "$1")"
      ;;
    tts.say)
      _u=$(machine_addr tts uv) || return 1
      _mod=$(machine_addr tts model) || return 1
      [ $# -ge 2 ] || return 1
      printf '%s run --directory %s sherpa-onnx-offline-tts --vits-model=%s/model.onnx --output-filename=%s %s' \
        "$(args_word "$_u")" "$(args_word "$_mod")" "$(args_word "$_mod")" "$(args_word "$2")" "$(args_word "$1")"
      ;;
    *) return 2 ;;
  esac
}

# machine_run <machine> <operation> [arg ...] : the same line, run, bounded, shaped
machine_run() {
  _m=${1:-}
  _o=${2:-}
  [ $# -gt 1 ] && shift 2
  _c=$(machine_cmd "$_m" "$_o" "$@") || { shape_fail "machine.$_m.$_o" "" refusals.tool_unknown "$_m.$_o"; return 1; }
  exec_body "machine.$_m.$_o" "$_c"
}

# machine_url : the krita service, checked before anything is asked of it
machine_url() {
  _h=$(config str machine.krita.host) || return 1
  _p=$(config num machine.krita.port) || return 1
  if [ -z "$_h" ] || [ -z "$_p" ]; then printf '%s\n' "$(msg krita_noport)" >&2; return 1; fi
  _s="http://$_h:$_p"
  curl -sf --max-time 10 "$_s/health" >/dev/null 2>&1 \
    || { printf '%s\n' "$(msg krita_down "$_s")" >&2; return 1; }
  printf '%s\n' "$_s"
}
