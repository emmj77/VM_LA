#!/usr/bin/dash
# french in code is forbidden
set -u
HIST=${1:-}
DEMAND=${2:-}
DISPO=${3:-}
[ -n "$HIST" ] && [ -f "$HIST" ] || { printf '%s\n' "$(msg trim_none)" >&2 ; exit 1 ; }
case "${DISPO:-}" in
  ''|*[!0-9]*) printf 'trim_forms: la MARGE n est pas donnee (argument 3, octets disponibles pour les vieux retours) : les formes ne sont pas reformees\n' >&2
               cat "$HIST" ; exit 0 ;;
esac
HERE_TF=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
CONF=${LA_CONF:-$(dirname "$HERE_TF")/la_config.yaml}
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
PORT=${LA_RERANK_PORT:-$(conf_num models port 8091)}
HEAD_CAP=${LA_FORM_TETE:-$(conf_num forms head_bytes 1000)}    # octets gardes en tete de la forme RESUME
TAIL_CAP=${LA_FORM_QUEUE:-$(conf_num limits form_queue_bytes 1000)}  # queue de la forme RESUME
JUDGE_MAX=${LA_FORM_JUDGE_MAX:-$(conf_num limits form_judge_bytes 400)}       # ce que le juge LIT
DEMAND_CHARS=$(conf_num limits form_demand_chars 600)                       # la question envoyee au juge
JUDGE_TIMEOUT=$(conf_num limits form_rerank_timeout 5)                 # secondes d attente du juge

tmpfile histf ; HIST2=$TMPFILE || { cat "$HIST" ; exit 0 ; }
jq -c '
  ([ to_entries[] | select(.value.role == "tool") | .key ] | last) as $dernier
  | [ to_entries[]
      | .key as $k
      | .value as $m
      | if ($k != $dernier) and ($m.role == "tool")
           and (($m.content // "") | type) == "string"
           and (($m.content // "") | test("\\[return [0-9]+\\]"))
        then ($m | .content =
               (($m.content | capture("\\[return (?<id>[0-9]+)\\]").id) as $id
                | ($m.content | sub("\\n?\\[return [0-9]+\\]\\n?$"; "") | utf8bytelength) as $t
                | "[retour " + $id + " de " + ($m.name // "tool") + " : " + ($t | tostring)
                  + " octets ; read_return " + $id + "]"))
        else $m end ]' "$HIST" > "$HIST2" 2>/dev/null || cp "$HIST" "$HIST2"
[ -s "$HIST2" ] || cp "$HIST" "$HIST2"
HIST=$HIST2     # tout ce qui suit lit l historique DEJA reduit ; le juge ne voit que le reste

CANDS=$(jq -c --argjson n "$JUDGE_MAX" '
  [ . | to_entries[]
    | select(.value.role == "tool")
    | select(((.value.content // "") | test("^\\[retour [0-9]+ de ")) | not)
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
[ "$NEED" -le "$DISPO" ] && { cat "$HIST" ; exit 0 ; }

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
[ "${LA_FORM_TRACE:-0}" = 1 ] && printf 'trim_forms: marge %s o, %s candidat(s), besoin %s o, rank : %s\n' "$DISPO" "$N" "$NEED" "$RANK" >&2

jq -c --argjson rank "$RANK" --argjson dispo "$DISPO" --argjson ct "$HEAD_CAP" --argjson cq "$TAIL_CAP" '
  def marque($name; $id; $size):
    "[retour range (" + $name + ", " + $id + ") : " + ($size | tostring)
    + " octets, le texte entier est dans config/sessions.db et dans le journal du tour]";
  def raccourci($name; $id; $size):
    ((.content[0:$ct]) + "\n[... RACCOURCI (resume+chemin) : " + ($size | tostring)
     + " octets au total (" + $name + ", " + $id
     + ") ; le texte entier est dans config/sessions.db et dans le journal du tour ...]\n"
     + (.content[-$cq:]));
  . as $hist
  | ( reduce $rank[] as $r
        ( { reste: $dispo, forme: {} };
          . as $a
          | ($r.h) as $h
          | ($hist[$h]) as $m
          | (if (($m.content // "") | type) == "string" then ($m.content | utf8bytelength) else 0 end) as $size
          | ($m.name // "tool") as $name
          | ($m.tool_call_id // "-") as $id
          | ($m | marque($name; $id; $size) | utf8bytelength) as $cost_path
          | ($m | raccourci($name; $id; $size) | utf8bytelength) as $cout_resume
          | if $size == 0 or $size <= $cost_path
            then { reste: $a.reste, forme: ($a.forme + { ($h | tostring): "entier" }) }
            elif $size <= $a.reste
            then { reste: ($a.reste - $size), forme: ($a.forme + { ($h | tostring): "entier" }) }
            elif $cout_resume <= $a.reste
            then { reste: ($a.reste - $cout_resume), forme: ($a.forme + { ($h | tostring): "resume" }) }
            else { reste: ($a.reste - $cost_path), forme: ($a.forme + { ($h | tostring): "chemin" }) }
            end ) ) as $alloc
  | to_entries
  | map( .key as $k
         | .value as $m
         | ($alloc.forme[($k | tostring)]) as $f
         | if ($m.role == "tool") and ($f != null) then
             ($m.name // "tool") as $name
             | ($m.tool_call_id // "-") as $id
             | ($m
                 | if $f == "entier" then .
                   elif $f == "chemin" then
                     .content = marque($name; $id; ((.content // "") | utf8bytelength))
                   else
                     (.content | utf8bytelength) as $L
                     | .content = raccourci($name; $id; $L)
                   end)
           else $m end )
' "$HIST" 2>/dev/null || cat "$HIST"
exit 0
