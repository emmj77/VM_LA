#!/bin/sh
# signal_task : tool appele par LA BOUCLE, EN FIN DE TACHE (apres answer, ou apres une borne
# d'arret) ; JAMAIS par le LLM ('04 - LE FILTRE'). Famille READ : il ne fait que READ ce qui est
# deja ecrit, et il rend UNE LIGNE - un signal a l'humain ('11 - LE RETOUR DES OUTILS').
# Le registre qui tient est LA BASE DES SESSIONS (sessions.db) : c'est la que le tour est
# transcrit (loi 1607 : une session est un REGISTRE). Il n'ecrit AUCUN fichier : 'un signal
# n'a qu'un lecteur' ('04 - LE FILTRE'), donc aucun moule ne porte sa forme - sa line JSON est
# montee par jq -cn ('13 - LES PROCS').
# Entree : un objet JSON sur stdin (ce tool ne prend aucun argument). Sortie : une line JSON
# {status,line,result,ts}. Un refus est un RESULTAT : meme text dans line et result, rc=0, rien
# sur stderr.
# PIEGE : aucun accent grave dans ce fichier - dash ouvrirait une substitution de commande.
refuse_signal() {
  jq -cn --arg r "refus: $1" --arg ts "$TS" \
    '{status:"refused",line:$r,result:$r,ts:$ts}'
  exit 0
}

INPUT=$(cat)
exec 2>/dev/null

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STAMP=$(date -u +'%Y-%m-%d %H:%M')

# --- [1] la base des sessions : le registre qui tient, pose par la boucle (config/sessions.db).
#     Le proc ne devine aucun chemin : la base vit a cote du engine, LA_SESSIONS_DB la surcharge.
HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
CONF_DIR=$(dirname "$HERE")
DB=${LA_SESSIONS_DB:-$CONF_DIR/sessions.db}
[ -f "$DB" ] || refuse_signal "sessions.db introuvable ($DB)"
command -v sqlite3 >/dev/null 2>&1 || refuse_signal "sqlite3 introuvable sur la machine"

# --- [2] ce qui est deja ecrit : les echanges, puis les appels de tools de la base.
N=$(sqlite3 "$DB" 'SELECT COUNT(DISTINCT exchange) FROM messages;' 2>/dev/null)
case "${N:-}" in ''|*[!0-9]*) N=0 ;; esac
M=$(sqlite3 "$DB" "SELECT COUNT(*) FROM messages WHERE COALESCE(tool_calls,'') <> '';" 2>/dev/null)
case "${M:-}" in ''|*[!0-9]*) M=0 ;; esac

LINE="$STAMP  signal_task  sessions.db  ->  $N echanges, $M appels de tools"
jq -cn --arg l "$LINE" --arg ts "$TS" '{status:"ok",line:$l,result:$l,ts:$ts}'
exit 0
