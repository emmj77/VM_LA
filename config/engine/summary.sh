#!/usr/bin/dash
# french in code is forbidden

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

GGUF_DIR=${LA_GGUF_DIR:-$(conf_str llama gguf)}
ADDRESS=${LA_LOCAL_URL:-http://$(conf_str models host 127.0.0.1):$(conf_num models port 8091)}

LINES_MAX=$(conf_num summary lines_max 12)
BYTES_MAX=$(conf_num summary bytes_max 1200)
BRIEF_LINES=$(conf_num summary brief_lines 2)
BRIEF_BYTES=$(conf_num summary brief_bytes 200)
INPUT_MAX=$(conf_num summary input_max 24000)
TOKENS_MAX=$(conf_num summary tokens_max 400)
TIMEOUT=$(conf_num summary timeout 300)
TEMPERATURE=$(conf_str summary temperature 0.2)
TOP_P=$(conf_str summary top_p 0.9)
REPEAT_PENALTY=$(conf_str summary repeat_penalty 1.15)

BRIEF=${LA_SUMMARY_BRIEF:-0}
case "$BRIEF" in
  1) LINES_MAX=$BRIEF_LINES ; BYTES_MAX=$BRIEF_BYTES ;;
esac

need curl "the summary, to reach the local model" || exit 1
need jq   "the summary, to read and write JSON" || exit 1

case "$ADDRESS" in
  http://*|https://*) ;;
  *) echo "refused: the local model address is invalid ($ADDRESS)" >&2; exit 1 ;;
esac

[ -d "$GGUF_DIR" ] || { echo "refused: no local model exists (the models folder is missing : $GGUF_DIR)" >&2; exit 1; }
ls "$GGUF_DIR"/*.gguf >/dev/null 2>&1 || { echo "refused: no local model exists (no .gguf under $GGUF_DIR)" >&2; exit 1; }

TEXT=$(cat)
[ -n "$TEXT" ] || { echo "refused: the input is empty ; there is nothing to summarize" >&2; exit 1; }
N=$(printf '%s' "$TEXT" | wc -c | tr -d ' ')
[ "$N" -le "$INPUT_MAX" ] || { echo "refused: the input is $N bytes, the input bound is $INPUT_MAX" >&2; exit 1; }

K=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$ADDRESS/v1/models" 2>/dev/null || true)
case "$K" in
  ''|000) echo "refused: no local model answers on $ADDRESS (is the local llama.cpp server started ?)" >&2; exit 1 ;;
esac

DEF_OUT="You will summarize the tool output placed between the lines [[[ and ]]]. It may be JSON, a list of files or prose: summarize its CONTENT in French, do not copy it. At most %s lines and at most %s bytes. Write only the summary, without an introductory sentence."
DEF_EXC="You will summarize an EXCHANGE between a human (ME) and an agent (AGENT), placed between the lines [[[ and ]]. Keep what MOVED FORWARD, the DECISIONS taken and the FILES modified. Invent nothing: what is not in the exchange is not written. At most %s lines and at most %s bytes. Write only the summary, without an introductory sentence."
case "${LA_SUMMARY_KIND:-output}" in
  exchange) USR=$(conf_str summary t_exchange "$DEF_EXC") ;;
  *)        USR=$(conf_str summary t_output "$DEF_OUT") ;;
esac
USR=$(tpn "$USR" "$LINES_MAX" "$BYTES_MAX")

FO=$(conf_str summary t_frame_open '[[[')
FC=$(conf_str summary t_frame_close ']]]')
PRIME=$(conf_str summary t_prime 'Summary :')
MDL=${LA_LOCAL_MODEL:-local}
C=$(printf '%s' "$TEXT" | jq -Rs --arg u "$USR" --argjson m "$TOKENS_MAX" --arg mdl "$MDL" \
      --argjson t "$TEMPERATURE" --argjson p "$TOP_P" --argjson r "$REPEAT_PENALTY" \
      --arg fo "$FO" --arg fc "$FC" --arg pr "$PRIME" \
      '{model:$mdl,stream:false,temperature:$t,top_p:$p,repeat_penalty:$r,max_tokens:$m,
        messages:[{role:"user",content:($u + "\n\n" + $fo + "\n" + . + "\n" + $fc + "\n\n" + $pr + "\n")}]}') \
  || { echo "refused: the request could not be built (jq)" >&2; exit 1; }

R=$(curl -s -m "$TIMEOUT" -H 'Content-Type: application/json' -d "$C" -w '\n%{http_code}' "$ADDRESS/v1/chat/completions" 2>/dev/null || true)
K=$(printf '%s' "$R" | tail -n 1)
B=$(printf '%s' "$R" | sed '$d')
case "$K" in
  ''|000) echo "refused: no local model answers on $ADDRESS (is the local llama.cpp server started ?)" >&2; exit 1 ;;
esac
[ "$K" = 200 ] || { echo "refused: the local model returned HTTP $K on $ADDRESS/v1/chat/completions" >&2; exit 1; }
T=$(printf '%s' "$B" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
[ -n "$T" ] || { echo "refused: the local model returned no text" >&2; exit 1; }

strip_orphan_byte() {
  s=$(cat)
  while [ -n "$s" ]; do
    d=$(printf '%s' "$s" | tail -c 1 | od -An -tu1 | tr -d ' \n')
    case "$d" in ''|*[!0-9]*) break ;; esac
    [ "$d" -lt 128 ] && break
    if [ "${#s}" -le 1 ]; then
      s=
    else
      s=$(printf '%s' "$s" | cut -b "1-$(( ${#s} - 1 ))")
    fi
  done
  printf '%s' "$s"
}

bound_stream() {
  ml=$1
  mo=$2
  n=0
  b=0
  while IFS= read -r l || [ -n "$l" ]; do
    [ "$n" -lt "$ml" ] || break
    t=$(( ${#l} + 1 ))
    if [ $(( b + t )) -le "$mo" ]; then
      printf '%s\n' "$l"
      n=$(( n + 1 ))
      b=$(( b + t ))
    else
      r=$(( mo - b - 1 ))
      if [ "$r" -ge 1 ]; then
        u=$(printf '%s' "$l" | cut -b "1-$r" | strip_orphan_byte)
        [ -n "$u" ] && printf '%s\n' "$u"
      fi
      break
    fi
  done
}

printf '%s\n' "$T" | sed -e '/[^[:blank:]]/,$!d' -e ':a' -e '/^[[:blank:]]*$/{$d;N;ba' -e '}' | bound_stream "$LINES_MAX" "$BYTES_MAX"
