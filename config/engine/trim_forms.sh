#!/usr/bin/dash
# french in code is forbidden
set -u
HIST=${1:-}
DEMAND=${2:-}
FREE=${3:-}
[ -n "$HIST" ] && [ -f "$HIST" ] || { printf '%s\n' "$(msg trim_none)" >&2 ; exit 1 ; }
case "${FREE:-}" in
  ''|*[!0-9]*) printf 'trim_forms: no MARGIN given (argument 3, bytes free for the old returns) : the forms are left as they are\n' >&2
               cat "$HIST" ; exit 0 ;;
esac
HERE_TF=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
CONF=${LA_CONF:-$(dirname "$HERE_TF")/la_config.yaml}
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
PORT=${LA_RERANK_PORT:-$(conf_num models port 8091)}
HEAD_CAP=${LA_FORM_TETE:-$(conf_num forms head_bytes 1000)}    # bytes kept at the head of a SUMMARY form
TAIL_CAP=${LA_FORM_QUEUE:-$(conf_num limits form_queue_bytes 1000)}  # tail of a SUMMARY form
JUDGE_MAX=${LA_FORM_JUDGE_MAX:-$(conf_num limits form_judge_bytes 400)}       # what the judge READS
DEMAND_CHARS=$(conf_num limits form_demand_chars 600)                       # the question sent to the judge
JUDGE_TIMEOUT=$(conf_num limits form_rerank_timeout 5)                 # seconds waited for the judge

tmpfile histf ; HIST2=$TMPFILE || { cat "$HIST" ; exit 0 ; }
jq -c '
  ([ to_entries[] | select(.value.role == "tool") | .key ] | last) as $last
  | [ to_entries[]
      | .key as $k
      | .value as $m
      | if ($k != $last) and ($m.role == "tool")
           and (($m.content // "") | type) == "string"
           and (($m.content // "") | test("\\[return [0-9]+\\]"))
        then ($m | .content =
               (($m.content | capture("\\[return (?<id>[0-9]+)\\]").id) as $id
                | ($m.content | sub("\\n?\\[return [0-9]+\\]\\n?$"; "") | utf8bytelength) as $t
                | "[return " + $id + "] " + ($m.name // "tool") + " : " + ($t | tostring)
                  + " bytes ; read_return " + $id))
        else $m end ]' "$HIST" > "$HIST2" 2>/dev/null || cp "$HIST" "$HIST2"
[ -s "$HIST2" ] || cp "$HIST" "$HIST2"
HIST=$HIST2     # everything below reads the ALREADY reduced history ; the judge only sees the rest

CANDS=$(jq -c --argjson n "$JUDGE_MAX" '
  [ . | to_entries[]
    | select(.value.role == "tool")
    | select(((.value.content // "") | test("^\\[return [0-9]+\\] ")) | not)
    | { h: .key, t: ((.value.content // "")[0:$n]) } ]
  | .[0:(length - 1)]' "$HIST" 2>/dev/null || true)
[ -n "$CANDS" ] || { cat "$HIST" ; exit 0 ; }
N=$(printf '%s' "$CANDS" | jq 'length' 2>/dev/null || printf '0')
case "${N:-}" in ''|*[!0-9]*) N=0 ;; esac
[ "$N" -ge 1 ] || { cat "$HIST" ; exit 0 ; }

NEED=$(jq -r '[ . | to_entries[]
                  | select(.value.role == "tool")
                  | ((.value.content // "") | if type == "string" then utf8bytelength else 0 end) ]
                | (.[0:(length - 1)] | add // 0)' "$HIST" 2>/dev/null || printf '0')
case "${NEED:-}" in ''|*[!0-9]*) NEED=0 ;; esac
[ "$NEED" -le "$FREE" ] && { cat "$HIST" ; exit 0 ; }

DOCS=$(printf '%s' "$CANDS" | jq -c 'map(.t | gsub("[\\r\\n\\t]+"; " "))')
IDX=$(printf '%s' "$CANDS" | jq -c 'map(.h)')

Q=$(printf '%s' "$DEMAND" | head -c "$DEMAND_CHARS")
[ -n "$Q" ] || Q=$(jq -r '[.[] | select(.role == "user") | .content] | last // ""' "$HIST" 2>/dev/null | head -c "$DEMAND_CHARS")
[ -n "$Q" ] || { printf '%s\n' "$(msg trim_no_request)" >&2
               cat "$HIST" ; exit 0 ; }

RMODEL=${LA_RERANK_MODEL:-$(conf_str models rerank bge-reranker-v2-m3-Q4_K_M)}
REQ=$(jq -cn --arg q "$Q" --argjson docs "$DOCS" --argjson n "$N" --arg m "$RMODEL" \
  '{model: $m, query: $q, documents: $docs, top_n: $n}')
REP=$(curl -s --max-time "$JUDGE_TIMEOUT" -H 'Content-Type: application/json' -d "$REQ" \
  "http://127.0.0.1:$PORT/v1/rerank" 2>/dev/null || true)
RANK=$(printf '%s' "$REP" | jq -c --argjson ids "$IDX" '
  [(.results // [])[] | { h: ($ids[.index] // null), s: .relevance_score }]
  | map(select(.h != null)) | sort_by(-.s)' 2>/dev/null || true)
case "${RANK:-}" in ''|'[]'|'null')
  printf '%s\n' "$(msg trim_rerank_silent "$PORT")" >&2
  cat "$HIST" ; exit 0 ;;
esac
[ "${LA_FORM_TRACE:-0}" = 1 ] && printf 'trim_forms: margin %s B, %s candidate(s), need %s B, rank : %s\n' "$FREE" "$N" "$NEED" "$RANK" >&2

jq -c --argjson rank "$RANK" --argjson free "$FREE" --argjson ct "$HEAD_CAP" --argjson cq "$TAIL_CAP" '
  def stored($name; $id; $size):
    "[stored elsewhere (" + $name + ", " + $id + ") : " + ($size | tostring)
    + " bytes, the whole text is in config/sessions.db and in the turn trace]";
  def shortened($name; $id; $size):
    ((.content[0:$ct]) + "\n[... SHORTENED (summary+path) : " + ($size | tostring)
     + " bytes in total (" + $name + ", " + $id
     + ") ; the whole text is in config/sessions.db and in the turn trace ...]\n"
     + (.content[-$cq:]));
  . as $hist
  | ( reduce $rank[] as $r
        ( { left: $free, form: {} };
          . as $a
          | ($r.h) as $h
          | ($hist[$h]) as $m
          | (if (($m.content // "") | type) == "string" then ($m.content | utf8bytelength) else 0 end) as $size
          | ($m.name // "tool") as $name
          | ($m.tool_call_id // "-") as $id
          | ($m | stored($name; $id; $size) | utf8bytelength) as $path_cost
          | ($m | shortened($name; $id; $size) | utf8bytelength) as $short_cost
          | if $size == 0 or $size <= $path_cost
            then { left: $a.left, form: ($a.form + { ($h | tostring): "whole" }) }
            elif $size <= $a.left
            then { left: ($a.left - $size), form: ($a.form + { ($h | tostring): "whole" }) }
            elif $short_cost <= $a.left
            then { left: ($a.left - $short_cost), form: ($a.form + { ($h | tostring): "short" }) }
            else { left: ($a.left - $path_cost), form: ($a.form + { ($h | tostring): "path" }) }
            end ) ) as $alloc
  | to_entries
  | map( .key as $k
         | .value as $m
         | ($alloc.form[($k | tostring)]) as $f
         | if ($m.role == "tool") and ($f != null) then
             ($m.name // "tool") as $name
             | ($m.tool_call_id // "-") as $id
             | ($m
                 | if $f == "whole" then .
                   elif $f == "path" then
                     .content = stored($name; $id; ((.content // "") | utf8bytelength))
                   else
                     (.content | utf8bytelength) as $L
                     | .content = shortened($name; $id; $L)
                   end)
           else $m end )
' "$HIST" 2>/dev/null || cat "$HIST"
exit 0
