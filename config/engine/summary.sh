#!/bin/sh
# summary.sh - LE RESUMEUR DE LA (config/engine/summary.sh).
#
# CE QU'IL FAIT
#   il LIT un TEXTE BRUYANT sur son ENTREE STANDARD (une sortie de tool, un tour),
#   il DEMANDE le resume au MODELE LOCAL qui tourne sur le CPU (llama.cpp serveur
#   local), et il REND ce resume sur sa SORTIE STANDARD, et RIEN d'autre sur ce canal.
#
# LE MODELE LOCAL
#   LE MEME modele, un PETIT modele quantifie, sur le CPU : jamais le GPU, jamais -ngl.
#   Les GGUF vivent sous $LA_GGUF_DIR (par defaut /home/moussa/LLM_GGUF). L'adresse du
#   service local est 127.0.0.1:8088 (l'adresse du projet), surchargeable pour un banc
#   par LA_LOCAL_URL. Le champ model envoye est "local" : llama.cpp sert le modele
#   charge, quel que soit l'identifiant demande.
#   Ce script NE LANCE RIEN et N'ARRETE RIEN : si rien ne repond, il refuse (voir plus bas).
#
# LA BORNE, declaree ICI et TENUE par le script (elle est dite au modele, puis tenue de force)
#   SORTIE   au plus 12 LIGNES, et au plus 1200 OCTETS (le saut de ligne compte).
#            La coupe tombe TOUJOURS sur un caractere entier : jamais un octet orphelin.
#   ENTREE   au plus 24000 OCTETS. Au-dela : refus nomme, le texte n'est JAMAIS tronque
#            en silence.
#
# LE REFUS
#   UNE SEULE ligne, sur la SORTIE D'ERREUR, code 1, et RIEN sur la sortie standard.
#   Aucun modele local qui existe, aucun service qui repond, entree vide ou trop longue,
#   reponse HTTP non 200, reponse sans texte : refus NOMME. Jamais un silence, et JAMAIS
#   un resume fabrique par le script lui-meme : un resume vient du modele, ou il n'y a
#   pas de resume.
#
# CE QU'IL NE FAIT JAMAIS
#   il n'imprime AUCUNE cle : il n'en lit aucune, il n'en ecrit aucune, il n'en connait
#   aucune. Il ne dit rien de lui-meme sur la sortie standard (pas de titre, pas de
#   compte, pas d'adresse) : sur stdout il y a le resume, ou il n'y a rien.
#
# sh (dash) + coreutils + jq : rien d'autre. ASCII pur, AUCUN accent grave, meme en
# commentaire (dash ouvre la ou on ne l'attend pas).

LC_ALL=C
export LC_ALL

LINES_MAX=12
BYTES_MAX=1200
INPUT_MAX=24000
TOKENS_MAX=400
TIMEOUT=300
GGUF_DIR=${LA_GGUF_DIR:-/home/moussa/LLM_GGUF}
ADDRESS=${LA_LOCAL_URL:-http://127.0.0.1:8088}

# --- LE MODE SEC : quand LA_SUMMARY_BRIEF vaut 1, la brique ne rend pas un resume ordinaire
#     mais DEUX BLOCS de deux lignes - l un pour l humain, l autre pour l agent. C est ce que
#     config/sessions.yaml porte. Les bornes de ce mode sont DECLAREES ICI, comme les autres :
#     six lignes (les deux marques, plus deux lignes de chaque cote) et quatre cents octets.
BRIEF=${LA_SUMMARY_BRIEF:-0}
case "$BRIEF" in
  1) LINES_MAX=2 ; BYTES_MAX=200 ;;
esac

# --- ce qu'il faut avoir sous la main
command -v curl >/dev/null 2>&1 || { echo 'refuse : curl est introuvable sur la machine' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'refuse : jq est introuvable sur la machine' >&2; exit 1; }

# --- l'adresse du service local
case "$ADDRESS" in
  http://*|https://*) ;;
  *) echo "refuse : l'adresse du modele local est invalide ($ADDRESS)" >&2; exit 1 ;;
esac

# --- un modele local EXISTE-t-il sur la machine ?
#     (un fichier .gguf dans le dossier des modeles : le modele lui-meme)
[ -d "$GGUF_DIR" ] || { echo "refuse : aucun modele local n'existe (le dossier des modeles est introuvable : $GGUF_DIR)" >&2; exit 1; }
ls "$GGUF_DIR"/*.gguf >/dev/null 2>&1 || { echo "refuse : aucun modele local n'existe (aucun .gguf sous $GGUF_DIR)" >&2; exit 1; }

# --- l'entree : tout ce qui arrive sur l'entree standard
TEXT=$(cat)
[ -n "$TEXT" ] || { echo "refuse : l'entree est vide ; il n'y a rien a resumer" >&2; exit 1; }
N=$(printf '%s' "$TEXT" | wc -c | tr -d ' ')
[ "$N" -le "$INPUT_MAX" ] || { echo "refuse : l'entree fait $N octets, la bound d'entree est $INPUT_MAX" >&2; exit 1; }

# --- le service local repond-il ?
K=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$ADDRESS/v1/models" 2>/dev/null || true)
case "$K" in
  ''|000) echo "refuse : aucun modele local ne repond sur $ADDRESS (le serveur llama.cpp local est-il demarre ?)" >&2; exit 1 ;;
esac

# --- la consigne demandee au modele : BORNEE comme le script la tiendra.
#     Le modele local (LFM2.5-1.2B) tourne sur le CPU : il ne faut pas lui demander "resume" en lui tendant
#     du JSON nu, il repond alors qu'il n'a rien recu. On lui DONNE le cadre (les deux
#     lignes [[[ et ]]), on lui dit que c'est une sortie d'outil, et on amorce la fin
#     ("Resume :") pour qu'il commence sur le resume. UN SEUL message user : aucune ligne
#     systeme (mesure faite : avec un systeme, le modele recopie le canon au lieu de le
#     resumer). temperature 0.2 + repeat_penalty 1.15 : a temperature 0 il recrache la
#     meme ligne (mesure : 44 s de boucle sur la sortie de engine.sh 109).
if [ "$BRIEF" = 1 ]; then
  USR="Tu vas resumer la sortie d'outil placee entre les lignes [[[ et ]]]. Elle peut etre du JSON, une liste de fichiers ou de la prose : resume son CONTENT en francais, ne le recopie pas. Au plus $LINES_MAX lignes et au plus $BYTES_MAX octets. N'ecris que le resume, sans phrase d'introduction."
else
  # LA MATIERE CHANGE LA CONSIGNE, PAS LES BORNES (loi 1806 : la regle est tenue par le script).
  # `output` : le defaut, inchange. `exchange` : ce que le head secondaire porte (loi 1905) -
  # l'avancement, les decisions prises, les fichiers modifies - pour un DIALOGUE (MOI/AGENT) et
  # non pour une sortie d'outil ; sans ce cadre, un petit modele DECRIT la sortie au lieu de la
  # resumer, et le resume ne dit rien de ce qui s'est passe.
  case "${LA_SUMMARY_KIND:-output}" in
    exchange) USR="Tu vas resumer un ECHANGE entre un humain (MOI) et un agent (AGENT), place entre les lignes [[[ et ]]]. Retiens ce qui a AVANCE, les DECISIONS prises et les FICHIERS modifies. N'invente rien : ce qui n'est pas dans l'echange ne s'ecrit pas. Au plus $LINES_MAX lignes et au plus $BYTES_MAX octets. N'ecris que le resume, sans phrase d'introduction." ;;
    *)       USR="Tu vas resumer la sortie d'outil placee entre les lignes [[[ et ]]]. Elle peut etre du JSON, une liste de fichiers ou de la prose : resume son CONTENT en francais, ne le recopie pas. Au plus $LINES_MAX lignes et au plus $BYTES_MAX octets. N'ecris que le resume, sans phrase d'introduction." ;;
  esac
fi

# --- la demande montee en JSON (jamais une cle : il n'y en a aucune ici)
C=$(printf '%s' "$TEXT" | jq -Rs --arg u "$USR" --argjson m "$TOKENS_MAX" \
      '{model:"local",stream:false,temperature:0.2,top_p:0.9,repeat_penalty:1.15,max_tokens:$m,
        messages:[{role:"user",content:($u + "\n\n[[[\n" + . + "\n]]]\n\nResume :\n")}]}') \
  || { echo "refuse : la demande n'a pas pu etre montee (jq)" >&2; exit 1; }

# --- l'appel au modele local
R=$(curl -s -m "$TIMEOUT" -H 'Content-Type: application/json' -d "$C" -w '\n%{http_code}' "$ADDRESS/v1/chat/completions" 2>/dev/null || true)
K=$(printf '%s' "$R" | tail -n 1)
B=$(printf '%s' "$R" | sed '$d')
case "$K" in
  ''|000) echo "refuse : aucun modele local ne repond sur $ADDRESS (le serveur llama.cpp local est-il demarre ?)" >&2; exit 1 ;;
esac
[ "$K" = 200 ] || { echo "refuse : le modele local a render HTTP $K sur $ADDRESS/v1/chat/completions" >&2; exit 1; }
T=$(printf '%s' "$B" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
[ -n "$T" ] || { echo "refuse : le modele local n'a render aucun texte" >&2; exit 1; }

# --- retirer un caractere UTF-8 incomplet de la queue (jamais un octet orphelin)
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

# --- la borne TENUE : $1 lignes max, $2 octets max (saut de ligne compris)
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

# --- la forme : des lignes nettoyees (pas de blancs en tete ni en queue), bornees, et rien d'autre
printf '%s\n' "$T" | sed -e '/[^[:blank:]]/,$!d' -e ':a' -e '/^[[:blank:]]*$/{$d;N;ba' -e '}' | bound_stream "$LINES_MAX" "$BYTES_MAX"
