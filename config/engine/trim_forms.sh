#!/bin/sh
# trim_forms.sh - QUELLE FORME POUR CHAQUE VIEUX RETOUR D OUTIL (lois 604-606).
#
# CE QUI DECIDAIT AVANT : la TAILLE seule. La boucle repartissait la MEME allocation a tous les
# vieux retours -- ($bud - le reste) / $nt -- utile ou perime, sans distinction. Mesure du 16/10 :
# huit vieux retours a 1 891 octets CHACUN, identiques, pendant que le plus recent gardait 6 022.
#
# CE QUI DECIDE MAINTENANT, ET DANS CET ORDRE :
#   LA MARGE DU TOUR decida la COUPE (loi 606) : rien de ce qui suit ne la depasse, et la marge est
#   recue en argument -- jamais devinee. Le tool, lui, ne decide rien.
#   LE SENS ordonna la REPARTITION dans cette marge (loi 605) : le resident rerank (127.0.0.1:8095),
#   le MEME 0,64 Go qui choisit les tools (loi 827 : un resident sert plusieurs fois par tour), note
#   chaque vieux retour contre la demande du tour. Les plus utiles gardent tout ; quand la marge
#   s epuise, le reste passe au resume, puis au chemin seul.
#
# LES TROIS FORMES (loi 605)
#   [1] ENTIER        : le retour qui sert, tel quel.
#   [2] RESUME+CHEMIN : tete ET queue (LA_FORM_TETE / LA_FORM_QUEUE) + ou vit le texte entier.
#   [3] RIEN+CHEMIN   : le marqueur seul, nommant LE TOOL et L ID : « le resultat n est plus
#                       utile », et « s il en veut plus, il a le tool pour le lire » (loi 612).
# LE PLUS RECENT N EST JAMAIS TOUCHE : il porte le travail de l etape en cours. C est le temoin.
#
# ENTREE   $1 = l historique (un tableau JSON, la forme de hist.json)
#          $2 = la demande du tour (vide : le dernier message humain de l historique sert)
#          $3 = LA MARGE en octets, disponible pour les VIEUX retours. VIDE OU NON NUMERIQUE :
#               la brique REFUSE en le nommant (loi 512) et rend l historique inchange.
# SORTIE   l historique reforme. Toujours 0 : c est le JSON qui juge (loi 520).
#
# SI LE RESIDENT NE REPOND PAS : l historique est rendu INCHANGE et la ligne le DIT (loi 502).
# Le plafond mecanique de la boucle reste en place : il n est pas double, il est PRECEDE.
#
# PAYE LE 16/10, trois fois, et les trois sont ecrits ici :
#   - un fichier .classes en TEXTE lu par --slurpfile (qui attend du JSON) faisait echouer le jq,
#     et le garde-fou rendait l historique inchange EN SILENCE : tout vit dans UN SEUL jq.
#   - `jq -c` rend UNE ligne : compter les candidats avec `wc -l` en annoncait 1 sur 8.
#   - le serveur de rerank rend la POSITION du document envoye, PAS l etage de l historique : les
#     confondre attribuait chaque forme a l etage VOISIN. L index voyage donc avec le candidat.
set -u
HIST=${1:-}
DEMANDE=${2:-}
DISPO=${3:-}
[ -n "$HIST" ] && [ -f "$HIST" ] || { echo 'refuse : il faut le chemin de l historique' >&2 ; exit 1 ; }
case "${DISPO:-}" in
  ''|*[!0-9]*) printf 'trim_forms: la MARGE n est pas donnee (argument 3, octets disponibles pour les vieux retours) : les formes ne sont pas reformees\n' >&2
               cat "$HIST" ; exit 0 ;;
esac
PORT=${LA_RERANK_PORT:-8095}
CAP_TETE=${LA_FORM_TETE:-1000}    # octets gardes en tete de la forme RESUME
CAP_QUEUE=${LA_FORM_QUEUE:-1000}  # octets gardes en queue de la forme RESUME
JUGES=${LA_FORM_JUGES:-400}       # ce que le reranker lit de chaque retour pour juger

# LES CANDIDATS : tous les retours d outil SAUF le dernier, chacun portant SON INDEX D HISTORIQUE.
# On n envoie que la TETE de chacun : le reranker juge le sens, pas la longueur, et la charge reste
# minuscule (huit candidats de 400 octets, c est moins cher qu un seul retour entier).
CANDS=$(jq -c --argjson n "$JUGES" '
  [ . | to_entries[]
    | select(.value.role == "tool")
    | { h: .key, t: ((.value.content // "")[0:$n]) } ]
  | .[0:(length - 1)]' "$HIST" 2>/dev/null || true)
[ -n "$CANDS" ] || { cat "$HIST" ; exit 0 ; }
N=$(printf '%s' "$CANDS" | jq 'length' 2>/dev/null || printf '0')
case "${N:-}" in ''|*[!0-9]*) N=0 ;; esac
[ "$N" -ge 1 ] || { cat "$HIST" ; exit 0 ; }

# LA MARGE SUFFIT-ELLE DEJA ? Alors on ne reveille pas le resident pour rien : une question dont la
# reponse est deja connue ne se pose pas, et la RAM se rembourse en tokens (loi 826).
BESOIN=$(jq -r '[ . | to_entries[]
                  | select(.value.role == "tool")
                  | ((.value.content // "") | if type == "string" then utf8bytelength else 0 end) ]
                | (.[0:(length - 1)] | add // 0)' "$HIST" 2>/dev/null || printf '0')
case "${BESOIN:-}" in ''|*[!0-9]*) BESOIN=0 ;; esac
[ "$BESOIN" -le "$DISPO" ] && { cat "$HIST" ; exit 0 ; }

DOCS=$(printf '%s' "$CANDS" | jq -c 'map(.t | gsub("[\\r\\n\\t]+"; " "))')
IDX=$(printf '%s' "$CANDS" | jq -c 'map(.h)')

Q=$(printf '%s' "$DEMANDE" | head -c 600)
[ -n "$Q" ] || Q=$(jq -r '[.[] | select(.role == "user") | .content] | last // ""' "$HIST" 2>/dev/null | head -c 600)
[ -n "$Q" ] || { printf 'trim_forms: aucune demande pour juger (ni argument 2, ni message humain dans l historique) : les formes ne sont PAS reformees\n' >&2
               cat "$HIST" ; exit 0 ; }

# L APPEL AU RESIDENT. top_n = le nombre de candidats : on veut TOUS les scores.
REQ=$(jq -cn --arg q "$Q" --argjson docs "$DOCS" --argjson n "$N" \
  '{query: $q, documents: $docs, top_n: $n}')
REP=$(curl -s --max-time 5 -H 'Content-Type: application/json' -d "$REQ" \
  "http://127.0.0.1:$PORT/v1/rerank" 2>/dev/null || true)
RANG=$(printf '%s' "$REP" | jq -c --argjson ids "$IDX" '
  [(.results // [])[] | { h: ($ids[.index] // null), s: .relevance_score }]
  | map(select(.h != null)) | sort_by(-.s)' 2>/dev/null || true)
case "${RANG:-}" in ''|'[]'|'null')
  printf 'trim_forms: le resident rerank ne repond pas sur 127.0.0.1:%s - les formes ne sont pas reformees, le plafond mecanique tient\n' "$PORT" >&2
  cat "$HIST" ; exit 0 ;;
esac
[ "${LA_FORM_TRACE:-0}" = 1 ] && printf 'trim_forms: marge %s o, %s candidat(s), besoin %s o, rang : %s\n' "$DISPO" "$N" "$BESOIN" "$RANG" >&2

# LA REPARTITION ET LA REEKRITURE, EN UN SEUL jq.
jq -c --argjson rang "$RANG" --argjson dispo "$DISPO" --argjson ct "$CAP_TETE" --argjson cq "$CAP_QUEUE" '
  def marque($nom; $id; $taille):
    "[retour range (" + $nom + ", " + $id + ") : " + ($taille | tostring)
    + " octets, le texte entier est dans config/sessions.db et dans le journal du tour]";
  def raccourci($nom; $id; $taille):
    ((.content[0:$ct]) + "\n[... RACCOURCI (resume+chemin) : " + ($taille | tostring)
     + " octets au total (" + $nom + ", " + $id
     + ") ; le texte entier est dans config/sessions.db et dans le journal du tour ...]\n"
     + (.content[-$cq:]));
  . as $hist
  | ( reduce $rang[] as $r
        ( { reste: $dispo, forme: {} };
          . as $a
          | ($r.h) as $h
          | ($hist[$h]) as $m
          | (if (($m.content // "") | type) == "string" then ($m.content | utf8bytelength) else 0 end) as $taille
          | ($m.name // "tool") as $nom
          | ($m.tool_call_id // "-") as $id
          | ($m | marque($nom; $id; $taille) | utf8bytelength) as $cout_chemin
          | ($m | raccourci($nom; $id; $taille) | utf8bytelength) as $cout_resume
          # UN RETOUR PLUS COURT QUE SON PROPRE MARQUEUR N EST PAS COUPE : le chemin serait plus
          # gros que la chose, et la marge n y gagnerait rien.
          | if $taille == 0 or $taille <= $cout_chemin
            then { reste: $a.reste, forme: ($a.forme + { ($h | tostring): "entier" }) }
            elif $taille <= $a.reste
            then { reste: ($a.reste - $taille), forme: ($a.forme + { ($h | tostring): "entier" }) }
            elif $cout_resume <= $a.reste
            then { reste: ($a.reste - $cout_resume), forme: ($a.forme + { ($h | tostring): "resume" }) }
            else { reste: ($a.reste - $cout_chemin), forme: ($a.forme + { ($h | tostring): "chemin" }) }
            end ) ) as $alloc
  | to_entries
  | map( .key as $k
         | .value as $m
         | ($alloc.forme[($k | tostring)]) as $f
         | if ($m.role == "tool") and ($f != null) then
             ($m.name // "tool") as $nom
             | ($m.tool_call_id // "-") as $id
             | ($m
                 | if $f == "entier" then .
                   elif $f == "chemin" then
                     .content = marque($nom; $id; ((.content // "") | utf8bytelength))
                   else
                     (.content | utf8bytelength) as $L
                     | .content = raccourci($nom; $id; $L)
                   end)
           else $m end )
' "$HIST" 2>/dev/null || cat "$HIST"
exit 0
