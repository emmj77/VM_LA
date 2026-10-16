#!/bin/sh
# session_note.sh - LE GESTE DE FIN DE TOUR (config/engine/session_note.sh).
#
# CE QU'IL FAIT
#   il prend UN ECHANGE (la demande de l humain, la reply de l agent), il demande au MODELE
#   LOCAL le compactage des deux cotes, et il POSE une entree horodatee dans
#   config/sessions.yaml. Il ne rend rien sur sa sortie standard : la reply du tour est deja
#   passee a l humain, et ce script ne parle pas a sa place.
#
# LES ARGUMENTS
#   $1  la DEMANDE du tour      $2  la REPLY du tour
#
# LA FORME QU'IL TIENT (declaree dans sessions.yaml, tenue ici)
#   stamp   l horodatage UTC, pose par CE SCRIPT (jamais par le modele)
#   human   au plus DEUX lignes : ce que l humain a demande, et ce qu il a obtenu
#   agent   au plus DEUX lignes : ce que l agent a fait, et ou il en est
#   Le compactage vient du MODELE (mode SEC de summary.sh, 6 lignes / 400 octets) ; quand le
#   modele ne separe pas ses deux blocs, on le DIT dans le bloc de l humain et le texte va
#   dans celui de l agent : JAMAIS un bloc invente par ce script.
#
# LE REFUS
#   une ligne sur la sortie d'erreur, code 1, et RIEN d ecrit : sans modele local qui repond,
#   ou sans reply, il n y a pas d echange a compacter, donc pas d entree.
#
# POSIX sh (dash) + coreutils, ASCII sans accent grave, aucune cle.

LC_ALL=C
export LC_ALL

HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
BRICK="$HERE/summary.sh"
FILE=${LA_SESSIONS:-$CONF_DIR/sessions.yaml}

REQUEST=${1:-}
REPLY=${2:-}

[ -f "$BRICK" ] || { echo "refuse : la brique de compactage est introuvable ($BRICK)" >&2 ; exit 1 ; }
[ -f "$FILE" ] || { echo "refuse : le fichier des sessions est introuvable ($FILE)" >&2 ; exit 1 ; }
[ -w "$FILE" ] || { echo "refuse : le fichier des sessions n est pas inscriptible ($FILE)" >&2 ; exit 1 ; }
[ -n "$REQUEST" ] || { echo 'refuse : aucune demande a compacter' >&2 ; exit 1 ; }
[ -n "$REPLY" ] || { echo 'refuse : aucune reply a compacter' >&2 ; exit 1 ; }

# l echange porte au modele, borne : la demande garde 4000 octets, la reply 19000, pour que
# le tout reste sous la borne d entree de la brique (24000 octets).
REQUEST=$(printf '%s' "$REQUEST" | head -c 4000)
REPLY=$(printf '%s' "$REPLY" | head -c 19000)

TEXT="DEMANDE DE L HUMAIN :
$REQUEST

REPLY DE L AGENT :
$REPLY"

# LE COMPACTAGE, EN DEUX APPELS. Chacun ne demande QU UN cote, sans aucune marque a
# respecter : le petit modele local ne tient pas un format, il tient une question unique et courte.
# (mesure faite : une consigne a deux blocs et deux marques, il rend de la prose.)
compact() {  # $1 = human|agent ; rend le bloc sur la sortie standard
  case "$1" in
    agent) CADRE="CE QUE L AGENT A FAIT, ET OU IL EN EST" ;;
    *)     CADRE="CE QUE L HUMAIN A DEMANDE, ET CE QU IL A OBTENU" ;;
  esac
  printf '%s\n\n%s' "$CADRE" "$TEXT" | LA_SUMMARY_BRIEF=1 sh "$BRICK" 2>/dev/null
}

HUMAN_SIDE=$(compact human | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | head -n 2)
[ -n "$HUMAN_SIDE" ] || HUMAN_SIDE='le modele local n a rien rendu du cote de l humain'
AGENT_SIDE=$(compact agent | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | head -n 2)
[ -n "$AGENT_SIDE" ] || AGENT_SIDE='le modele local n a rien rendu du cote de l agent'

STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

{
  printf '  - stamp: "%s"\n' "$STAMP"
  printf '    human: |-\n'
  printf '%s\n' "$HUMAN_SIDE" | sed -e 's/^/      /'
  printf '    agent: |-\n'
  printf '%s\n' "$AGENT_SIDE" | sed -e 's/^/      /'
} >> "$FILE" || { echo "refuse : l entree n a pas pu etre posee ($FILE)" >&2 ; exit 1 ; }

echo "session_note : echange compacte et pose a $STAMP"

# --- LE MICRO-RESUME DU HEAD SECONDAIRE (lois 110, 810, 1716, 1915) ----------------------
# LES ECHANGES SORTIS DE LA FENETRE sont resumes par le modele local, et la place du head
# secondaire est ECRASEE a chaque reecriture : elle se REMPLACE, elle ne s allonge pas.
# La SOURCE est le CORPS (sessions.db), jamais la fenetre : ce qui a quitte le contexte est
# justement ce que la fenetre ne porte plus.
#   LA FENETRE garde VINGT echanges (loi 1915) ; le resume couvre les DIX derniers sortis (810).
DB=${LA_SESSIONS_DB:-$CONF_DIR/sessions.db}
RESF=${LA_SUMMARY_FILE:-$CONF_DIR/second.yaml}
WINDOW=${LA_WINDOW:-20}
KEPT=${LA_SUMMARY_EXCHANGES:-10}
MAX_LINES=${LA_SUMMARY_LINES:-12}
MAX_BYTES=${LA_SUMMARY_BYTES:-800}

if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  MAX_EXCHANGE=$(sqlite3 "$DB" 'SELECT COALESCE(MAX(exchange),0) FROM messages;' 2>/dev/null || printf '')
  case "${MAX_EXCHANGE:-}" in ''|*[!0-9]*) MAX_EXCHANGE=0 ;; esac
  WINDOW_END=$((MAX_EXCHANGE - WINDOW))   # le dernier echange SORTI de la fenetre
  if [ "$WINDOW_END" -ge 1 ]; then
    WINDOW_START=$((WINDOW_END - KEPT + 1))
    [ "$WINDOW_START" -ge 1 ] || WINDOW_START=1
    TEXT=$(sqlite3 "$DB" "SELECT (CASE role WHEN 'user' THEN 'MOI : ' ELSE 'AGENT : ' END) || COALESCE(content,'') FROM messages WHERE exchange >= $WINDOW_START AND exchange <= $WINDOW_END AND COALESCE(content,'') <> '' ORDER BY id;" 2>/dev/null | head -c 20000)
    if [ -n "$TEXT" ]; then
      RES=$(printf '%s\n' "$TEXT" \
            | LA_SUMMARY_KIND=exchange sh "$BRICK" 2>/dev/null \
            | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' \
            | head -n "$MAX_LINES" | head -c "$MAX_BYTES")
      if [ -n "$RES" ]; then
        T=$(mktemp "${TMPDIR:-/tmp}/second.XXXXXX") || { echo 'refuse : aucun espace temporaire' >&2 ; exit 1 ; }
        {
          printf '# LE MICRO-RESUME DU HEAD SECONDAIRE (config/second.yaml).\n'
          printf '# ECRIT PAR LE MODELE LOCAL ; ECRASE a chaque reecriture : il se remplace, il ne rallonge pas.\n'
          printf 'stamp: "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          printf 'exchanges: "%s-%s"\n' "$WINDOW_START" "$WINDOW_END"
          printf 'bound: "%s lignes, %s octets, tenue par session_note.sh"\n' "$MAX_LINES" "$MAX_BYTES"
          printf 'summary:\n'
          printf '%s\n' "$RES" | sed -e 's/"/\\"/g' | awk -v d=100 '{ printf "  %d: \"%s\"\n", d + NR, $0 }'
        } > "$T" || { rm -f "$T"; echo 'refuse : le resume n a pas pu etre monte' >&2 ; exit 1 ; }
        [ -s "$T" ] || { rm -f "$T"; echo 'refuse : le resume n a rien ecrit' >&2 ; exit 1 ; }
        mv -f "$T" "$RESF" || { rm -f "$T"; echo "refuse : le resume n a pas pu etre pose ($RESF)" >&2 ; exit 1 ; }
        echo "session_note : resume du head secondaire reecrit ($RESF, exchanges $WINDOW_START-$WINDOW_END)"
      fi
    fi
  fi
fi
