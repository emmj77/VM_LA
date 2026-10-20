#!/usr/bin/dash
# french in code is forbidden

set -u

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

W="$STATE"   # l etat du harnais, resolu par lib.sh depuis la_config (paths.state)
PLAN="$HERE/plan.sh"
JOURNAL="$W/watch.jsonl"
RHOST=${LA_RERANK_HOST:-$(conf_str models host 127.0.0.1)}
RPORT=${LA_RERANK_PORT:-$(conf_num models port 8091)}
URL="http://$RHOST:$RPORT/v1/rerank"
LIMIT=${LA_VEILLEUR_LIMIT:-$(conf_num watcher limit 40)}

EVENTS="say voice image"

OUT_WAKE="wake: a human request waits for an answer now"
OUT_SLEEP="sleep: nothing waits for an answer now, the event can wait for the next turn"

refuse() { printf 'watcher : %s\n' "$1" >&2 ; exit 1 ; }

usage() { sed -n '2,37p' "$0" ; }

events_list() { for e in $EVENTS; do printf '%s\n' "$e"; done ; }

last_verdicts() {
  [ -f "$JOURNAL" ] || { printf '%s\n' "$(msg watcher_no_verdict "$JOURNAL")" ; exit 0 ; }
  N=${1:-10}
  case "$N" in ''|*[!0-9]*) refuse "the number of verdicts is not a number ($N)" ;; esac
  tail -n "$N" "$JOURNAL" \
    | jq -r '[.ts, .event, ("proposition=" + (.proposal // "?")), ("decision=" + (.decision // "attente")),
              ("scores " + (.score_reveiller // "?") + " / " + (.score_dormir // "?"))] | join("  ")' 2>/dev/null \
    || refuse "the verdict journal is unreadable ($JOURNAL)"
}

case "${1:-}" in
  ''|-h|--help|help) usage ; exit 0 ;;
  --events|-e)       events_list ; exit 0 ;;
  --last)            shift ; last_verdicts "${1:-10}" ; exit 0 ;;
esac

EV=$1 ; shift
case " $EVENTS " in
  *" $EV "*) ;;
  *) printf '%s\n' "$(msg watch_event "$EV")" >&2
     printf '%s\n' "$(msg watcher_full_list "$(events_list | tr '\n' ' ')")" >&2
     refuse "an event is NAMED, it is not guessed" ;;
esac

DETAIL= ; DECIDE=
while [ $# -gt 0 ]; do
  case "$1" in
    --decide) DECIDE=${2:-} ; [ $# -gt 1 ] && shift ;;
    *) [ -n "$DETAIL" ] || DETAIL=$1 ;;
  esac
  shift
done
case "$DECIDE" in
  ''|reveiller|dormir) ;;
  *) refuse "the decision ($DECIDE) is not one of the two agreed outputs: wake, sleep" ;;
esac
[ -n "$DETAIL" ] || DETAIL="(l evenement n a pas de corps)"

PLAN_TXT=$("$PLAN" status 2>/dev/null || true)
case "$PLAN_TXT" in
  *"no open plan"*|'') PLAN_TXT="no open plan" ;;
esac

Q="the bridge saw $EV while the session sleeps: $DETAIL"
BODY=$(jq -cn --arg q "$Q" --arg a "$OUT_WAKE" --arg b "$OUT_SLEEP" \
       --arg m "${LA_RERANK_MODEL:-$(conf_str models rerank bge-reranker-v2-m3-Q4_K_M)}" \
       '{model:$m, query:$q, documents:[$a,$b], top_n:2}') \
  || refuse "the judge question was not written (jq missing?)"
REP=$(curl -s -m "$LIMIT" -X POST "$URL" -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null || true)
S1=$(printf '%s' "$REP" | jq -r '[.results[] | select(.index==0) | .relevance_score][0] // empty' 2>/dev/null || true)
S2=$(printf '%s' "$REP" | jq -r '[.results[] | select(.index==1) | .relevance_score][0] // empty' 2>/dev/null || true)
case "${S1}${S2}" in
  ''|*[!0-9.eE+-]*) refuse "le juge ne peut pas NOTER les deux sorties : le classement ne repond pas ($URL). Je n invente pas de verdict (loi 1547)" ;;
esac

if awk -v a="$S1" -v b="$S2" 'BEGIN { exit !(a >= b) }'; then PROP=reveiller ; else PROP=dormir ; fi

DEC=${DECIDE:-attente}
LINE=$(jq -cn --arg ts "$(ts)" --arg e "$EV" --arg d "$DETAIL" --arg p "$PROP" --arg dec "$DEC" \
             --arg s1 "$S1" --arg s2 "$S2" --arg plan "$PLAN_TXT" \
             '{ts:$ts,event:$e,detail:$d,proposal:$p,decision:$dec,
               score_reveiller:$s1,score_dormir:$s2,plan:$plan}')
printf '%s\n' "$LINE" >> "$JOURNAL" \
  || refuse "the verdict journal cannot be touched ($JOURNAL)"
printf '%s\n' "$PROP"
