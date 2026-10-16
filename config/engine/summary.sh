#!/bin/sh
# summary.sh - THE LA SUMMARIZER (config/engine/summary.sh).
#
# WHAT IT DOES
#   it READS a NOISY TEXT on its STANDARD INPUT (a tool output, a turn),
#   it ASKS the summary from the LOCAL MODEL running on the CPU (llama.cpp local
#   server), and it RETURNS that summary on its STANDARD OUTPUT, and NOTHING else on that
#   channel.
#
# THE LOCAL MODEL
#   THE SAME model, a SMALL quantized model, on the CPU : never the GPU, never -ngl.
#   The GGUF live under $LA_GGUF_DIR (default /home/moussa/LLM_GGUF). The local service
#   address is 127.0.0.1:8088 (the project's address), overridable for a bench by
#   LA_LOCAL_URL. The model field sent is "local" : llama.cpp serves the loaded model,
#   whatever identifier is asked.
#   This script STARTS NOTHING and STOPS NOTHING : if nothing answers, it refuses (see below).
#
# THE BOUND, declared HERE and HELD by the script (it is told to the model, then enforced)
#   OUTPUT  at most 12 LINES, and at most 1200 BYTES (the newline counts).
#           The cut always falls on a whole character : never an orphan byte.
#   INPUT   at most 24000 BYTES. Beyond it : named refusal, the text is NEVER truncated in
#           silence.
#
# THE REFUSAL
#   A SINGLE line, on the ERROR OUTPUT, code 1, and NOTHING on the standard output.
#   No local model that exists, no service that answers, empty or too long input, non-200
#   HTTP response, response without text : NAMED refusal. Never a silence, and NEVER a
#   summary fabricated by the script itself : a summary comes from the model, or there is
#   no summary.
#
# WHAT IT NEVER DOES
#   it prints NO key : it reads none, it writes none, it knows none. It says nothing of
#   itself on the standard output (no title, no count, no address) : on stdout there is the
#   summary, or there is nothing.
#
# sh (dash) + coreutils + jq : nothing else. Pure ASCII, NO backtick, even in a comment
# (dash opens it where you least expect).

LC_ALL=C
export LC_ALL

LINES_MAX=12
BYTES_MAX=1200
INPUT_MAX=24000
TOKENS_MAX=400
TIMEOUT=300
GGUF_DIR=${LA_GGUF_DIR:-/home/moussa/LLM_GGUF}
ADDRESS=${LA_LOCAL_URL:-http://127.0.0.1:8088}

# --- THE BRIEF MODE : when LA_SUMMARY_BRIEF is 1, the brick does not return an ordinary
#     summary but TWO BLOCKS of two lines - one for the human, the other for the agent. This
#     is what config/sessions.yaml carries. The bounds of this mode are DECLARED HERE, like the
#     others : six lines (the two marks, plus two lines on each side) and four hundred bytes.
BRIEF=${LA_SUMMARY_BRIEF:-0}
case "$BRIEF" in
  1) LINES_MAX=2 ; BYTES_MAX=200 ;;
esac

# --- what must be at hand
command -v curl >/dev/null 2>&1 || { echo 'refused: curl is missing on the machine' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'refused: jq is missing on the machine' >&2; exit 1; }

# --- the local service address
case "$ADDRESS" in
  http://*|https://*) ;;
  *) echo "refused: the local model address is invalid ($ADDRESS)" >&2; exit 1 ;;
esac

# --- does a local model EXIST on the machine ?
#     (a .gguf file in the models folder : the model itself)
[ -d "$GGUF_DIR" ] || { echo "refused: no local model exists (the models folder is missing : $GGUF_DIR)" >&2; exit 1; }
ls "$GGUF_DIR"/*.gguf >/dev/null 2>&1 || { echo "refused: no local model exists (no .gguf under $GGUF_DIR)" >&2; exit 1; }

# --- the input : everything that arrives on the standard input
TEXT=$(cat)
[ -n "$TEXT" ] || { echo "refused: the input is empty ; there is nothing to summarize" >&2; exit 1; }
N=$(printf '%s' "$TEXT" | wc -c | tr -d ' ')
[ "$N" -le "$INPUT_MAX" ] || { echo "refused: the input is $N bytes, the input bound is $INPUT_MAX" >&2; exit 1; }

# --- does the local service answer ?
K=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$ADDRESS/v1/models" 2>/dev/null || true)
case "$K" in
  ''|000) echo "refused: no local model answers on $ADDRESS (is the local llama.cpp server started ?)" >&2; exit 1 ;;
esac

# --- the instruction asked to the model : BOUNDED as the script will hold it.
#     The local model (LFM2.5-1.2B) runs on the CPU : one must not ask it to "summarize" by
#     handing it bare JSON, it then answers that it received nothing. We GIVE it the frame (the
#     two lines [[[ and ]]), we tell it it is an interface output, and we prime the end so it
#     starts on the summary. A SINGLE user message : no system line (measured : with a system,
#     the model copies the canon instead of summarizing it). temperature 0.2 + repeat_penalty
#     1.15 : at temperature 0 it spits out the same line (measured : 44 s of loop on the output
#     of engine.sh 109).
if [ "$BRIEF" = 1 ]; then
  USR="You will summarize the tool output placed between the lines [[[ and ]]]. It may be JSON, a list of files or prose: summarize its CONTENT in French, do not copy it. At most $LINES_MAX lines and at most $BYTES_MAX bytes. Write only the summary, without an introductory sentence."
else
  # THE MATERIAL CHANGES THE INSTRUCTION, NOT THE BOUNDS (law 1806 : the rule is held by the script).
  # `output` : the default, unchanged. `exchange` : what the secondary head carries (law 1905) -
  # the progress, the decisions taken, the files modified - for a DIALOGUE (ME/AGENT) and not
  # for a tool output ; without this frame, a small model DESCRIBES the output instead of
  # summarizing it, and the summary says nothing of what happened.
  case "${LA_SUMMARY_KIND:-output}" in
    exchange) USR="You will summarize an EXCHANGE between a human (ME) and an agent (AGENT), placed between the lines [[[ and ]]. Keep what MOVED FORWARD, the DECISIONS taken and the FILES modified. Invent nothing: what is not in the exchange is not written. At most $LINES_MAX lines and at most $BYTES_MAX bytes. Write only the summary, without an introductory sentence." ;;
    *)       USR="You will summarize the tool output placed between the lines [[[ and ]]]. It may be JSON, a list of files or prose: summarize its CONTENT in French, do not copy it. At most $LINES_MAX lines and at most $BYTES_MAX bytes. Write only the summary, without an introductory sentence." ;;
  esac
fi

# --- the request built as JSON (never a key : there is none here)
C=$(printf '%s' "$TEXT" | jq -Rs --arg u "$USR" --argjson m "$TOKENS_MAX" \
      '{model:"local",stream:false,temperature:0.2,top_p:0.9,repeat_penalty:1.15,max_tokens:$m,
        messages:[{role:"user",content:($u + "\n\n[[[\n" + . + "\n]]]\n\nSummary :\n")}]}') \
  || { echo "refused: the request could not be built (jq)" >&2; exit 1; }

# --- the call to the local model
R=$(curl -s -m "$TIMEOUT" -H 'Content-Type: application/json' -d "$C" -w '\n%{http_code}' "$ADDRESS/v1/chat/completions" 2>/dev/null || true)
K=$(printf '%s' "$R" | tail -n 1)
B=$(printf '%s' "$R" | sed '$d')
case "$K" in
  ''|000) echo "refused: no local model answers on $ADDRESS (is the local llama.cpp server started ?)" >&2; exit 1 ;;
esac
[ "$K" = 200 ] || { echo "refused: the local model returned HTTP $K on $ADDRESS/v1/chat/completions" >&2; exit 1; }
T=$(printf '%s' "$B" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
[ -n "$T" ] || { echo "refused: the local model returned no text" >&2; exit 1; }

# --- remove an incomplete UTF-8 character from the tail (never an orphan byte)
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

# --- the bound HELD : $1 lines max, $2 bytes max (newline included)
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

# --- the shape : cleaned lines (no leading or trailing blanks), bounded, and nothing else
printf '%s\n' "$T" | sed -e '/[^[:blank:]]/,$!d' -e ':a' -e '/^[[:blank:]]*$/{$d;N;ba' -e '}' | bound_stream "$LINES_MAX" "$BYTES_MAX"
