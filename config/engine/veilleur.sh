#!/bin/sh
# veilleur.sh - LE JUGE DU REVEIL (lois 1543 a 1553). La brique de l'AUTOMATIQUE.
#
# CE QU'IL EST. Une entree : l'EVENEMENT que le pont vient de voir. DEUX SORTIES CONVENUES, jamais
# une troisieme : `reveiller` ou `dormir` (loi 1546). Il les NOTE, il ne les INVENTE pas : son etage
# est le RERANKER (bge-reranker-v2-m3, :8095), qui rend un score par sortie (loi 1547). Il PROPOSE ;
# le ENGINE DECIDE (lois 1533, 1549). Ce script n'arme rien, n'ouvre rien, n'elargit rien (1550) :
# un reveil n'elargit jamais le perimetre du reveille.
#
# IL JUGE LE REVEIL, JAMAIS L'ARRET (loi 1548) : la route /stop n'est pas un evenement ici. L'arret
# reste un COMPTE d'etapes (lois 382, 393).
#
# LES EVENEMENTS ADMIS SONT NOMMES (loi 1553) : une liste FERMEE, celle des routes du pont qui
# portent une DEMANDE de l'humain. Rien d'autre n'entre, et un nom hors liste rend LA LISTE ENTIERE.
#   say    POST /say      le corps est le texte demande
#   voice  POST /voice    le corps est un audio : une demande PARLEE
#   image  POST /image    le corps est une image : une demande MONTREE
#
# LA BORNE (loi 1551) : un seul systeme automatique est arme par session, et le plan est sa borne.
# Le veilleur ne DECIDE pas cela : il lit l'etat du plan (plan.sh status) et il l'ECRIT dans son
# verdict. C'est l'engine qui decide, en le lisant.
#
# USAGE
#   veilleur.sh <evenement> [<detail>] [--decide reveiller|dormir]
#   veilleur.sh --events           la liste fermee des evenements admis, une par ligne
#   veilleur.sh --last [n]         les n derniers verdicts, en clair (defaut : 10)
#
# SORTIE : la PROPOSITION seule, sur la sortie standard (`reveiller` ou `dormir`) -- c'est ce que le
# engine lit. Et UNE LIGNE au journal des verdicts ($W/veille.jsonl) : l'HEURE, l'EVENEMENT, la
# PROPOSITION, la DECISION (loi 1552), avec les deux scores et l'etat du plan.
#
# SORTIE D'ERREUR : un refus NOMME, code 1. Aucun verdict n'est rendu sans les deux scores : un
# juge qui ne peut pas noter n'invente pas (loi 1547).
#
# LE CLIENT. Le service est appele en curl + jq, l'outillage de la maison. Le SELECTEUR de tools
# (la fonction rank_share de loop.sh) garde une PART d'une longue liste : ce n'est pas le geste du
# juge, qui note DEUX sorties fixes. Un seul service, deux gestes.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${LA_ROOT:-$(CDPATH= cd -- "$HERE/../.." && pwd)}
[ -f "$HERE/lib.sh" ] || { printf 'veilleur: la bibliotheque commune est absente (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"

W="$ROOT/work"
PLAN="$HERE/plan.sh"
JOURNAL="$W/veille.jsonl"
URL="http://${LA_RERANK_HOST:-127.0.0.1}:${LA_RERANK_PORT:-8095}/v1/rerank"
LIMIT=${LA_VEILLEUR_LIMIT:-40}

# LA LISTE FERMEE DES EVENEMENTS ADMIS (loi 1553). Elle est ecrite ICI, une fois : l'ajouter ailleurs
# serait la deuxieme copie. /image entre par la meme porte que /say : une image est une demande.
EVENTS="say voice image"

# LES DEUX SORTIES CONVENUES, ecrites une fois (loi 1547). Le reranker les NOTE : leur formulation
# EST la mesure. Ne pas les rallonger sans refaire la mesure.
OUT_REVEILLER="reveiller : une demande de l humain attend une reponse maintenant"
OUT_DORMIR="dormir : rien n attend de reponse maintenant, l evenement peut attendre le prochain tour"

refuse() { printf 'veilleur : %s\n' "$1" >&2 ; exit 1 ; }

usage() { sed -n '2,42p' "$0" ; }

events_list() { for e in $EVENTS; do printf '%s\n' "$e"; done ; }

last_verdicts() {
  [ -f "$JOURNAL" ] || { printf 'veilleur : aucun verdict n a encore ete rendu (%s)\n' "$JOURNAL" ; exit 0 ; }
  N=${1:-10}
  case "$N" in ''|*[!0-9]*) refuse "le nombre de verdicts n est pas un nombre ($N)" ;; esac
  tail -n "$N" "$JOURNAL" \
    | jq -r '[.ts, .event, ("proposition=" + (.proposal // "?")), ("decision=" + (.decision // "attente")),
              ("scores " + (.score_reveiller // "?") + " / " + (.score_dormir // "?"))] | join("  ")' 2>/dev/null \
    || refuse "le journal des verdicts est illisible ($JOURNAL)"
}

# --- [1] LES SOUS-COMMANDES DE LECTURE ----------------------------------------
case "${1:-}" in
  ''|-h|--help|help) usage ; exit 0 ;;
  --events|-e)       events_list ; exit 0 ;;
  --last)            shift ; last_verdicts "${1:-10}" ; exit 0 ;;
esac

# --- [2] L'EVENEMENT : il est NOMME, et la liste est fermee -------------------
EV=$1 ; shift
case " $EVENTS " in
  *" $EV "*) ;;
  *) printf 'refuse : l evenement %s n est pas dans la liste fermee (loi 1553).\n' "$EV" >&2
     printf 'la liste entiere : %s\n' "$(events_list | tr '\n' ' ')" >&2
     refuse "un evenement se NOMME, il ne se devine pas" ;;
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
  *) refuse "la decision ($DECIDE) n est pas une des deux sorties convenues : reveiller, dormir" ;;
esac
[ -n "$DETAIL" ] || DETAIL="(l evenement n a pas de corps)"

# --- [3] LA BORNE : l'etat du plan entre dans le verdict, il ne le decide pas -
PLAN_TXT=$("$PLAN" status 2>/dev/null || true)
case "$PLAN_TXT" in
  *"no open plan"*|'') PLAN_TXT="aucun plan ouvert" ;;
esac

# --- [4] LES DEUX SORTIES, NOTEES PAR LE RERANKER ------------------------------
Q="le pont a vu $EV pendant que la session dort : $DETAIL"
BODY=$(jq -cn --arg q "$Q" --arg a "$OUT_REVEILLER" --arg b "$OUT_DORMIR" \
       '{query:$q, documents:[$a,$b], top_n:2}') \
  || refuse "la question du juge ne s est pas ecrite (jq absent ?)"
REP=$(curl -s -m "$LIMIT" -X POST "$URL" -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null || true)
S1=$(printf '%s' "$REP" | jq -r '[.results[] | select(.index==0) | .relevance_score][0] // empty' 2>/dev/null || true)
S2=$(printf '%s' "$REP" | jq -r '[.results[] | select(.index==1) | .relevance_score][0] // empty' 2>/dev/null || true)
case "${S1}${S2}" in
  ''|*[!0-9.eE+-]*) refuse "le juge ne peut pas NOTER les deux sorties : le classement ne repond pas ($URL). Je n invente pas de verdict (loi 1547)" ;;
esac

if awk -v a="$S1" -v b="$S2" 'BEGIN { exit !(a >= b) }'; then PROP=reveiller ; else PROP=dormir ; fi

# --- [5] LE VERDICT : une ligne, horodatee (loi 1552) --------------------------
DEC=${DECIDE:-attente}
LINE=$(jq -cn --arg ts "$(ts)" --arg e "$EV" --arg d "$DETAIL" --arg p "$PROP" --arg dec "$DEC" \
             --arg s1 "$S1" --arg s2 "$S2" --arg plan "$PLAN_TXT" \
             '{ts:$ts,event:$e,detail:$d,proposal:$p,decision:$dec,
               score_reveiller:$s1,score_dormir:$s2,plan:$plan}')
printf '%s\n' "$LINE" >> "$JOURNAL" \
  || refuse "le journal des verdicts est intouchable ($JOURNAL)"
printf '%s\n' "$PROP"
