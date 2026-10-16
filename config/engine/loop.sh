#!/bin/sh
# loop.sh - LA BOUCLE (09), refondue sur l architecture TABLE + ENGINE.
# Elle ne fait AUCUN tool elle-meme : elle lit le head, assemble un appel, appelle le
# engine, et lui rend ce qu il a fait. La PAROLE est un tool : talk DIT sans fermer,
# answer FERME quand le PLAN EST TERMINE, ask ARRETE le tour et attend l humain.
#
# LE TOUR, ET RIEN D AUTRE :
#   [1] elle LIT LE HEAD (le projet, config/head.yaml) et LE HEAD SECONDAIRE
#       (le plan, pose par config/engine/second.sh)
#   [2] elle OUVRE LE PERIMETRE : le champ tools du SKILL ACTIF. Vide, le doute ouvre.
#   [3] elle ENVOIE LA DEMANDE avec LE SEUL SCHEMA la(g, a) et le perimetre du skill
#   [4] elle LIT {g, a} : g nomme la ligne de la table, a porte ses arguments
#   [5] elle DECOUPE a : autant d arguments que la ligne en declare HORS stdin, le SURPLUS
#       sur l ENTREE STANDARD du engine
#   [6] elle APPELLE le engine, et lit UNE ligne JSON {status,tool,line,result,ts}
#   [7] elle HORODATE le tour sur UNE ligne, et rend LE REFUS AU MODELE tel quel - un tour
#       lui est laisse pour se corriger
#   [8] elle FERME le tour quand answer PASSE le plan termine, ou quand ask PASSE
#
# AUCUN texte du modele n est accepte comme reponse : tout passe par un tool. TALK est le
# tool de la PAROLE : il la pose sur le CANAL HUMAIN, et le tour CONTINUE.
#
# LE HEAD - config/head.yaml. GELE : lu SUR PLACE, jamais reecrit -- donc le prefixe de
#   l appel se met en cache. Ce que la boucle y LIT :
#   Sa forme : des SECTIONS en MAJUSCULES (une cle nue, ex. COMPORTEMENT:) et des LIGNES
#   NUMEROTEES (101: "texte"). La boucle en tire un PREAMBULE PLAT : les lignes numerotees
#   rendent leur texte, les cles restent des titres. Les commentaires et les lignes vides sortent.
#   Absent, la boucle S ARRETE EN LE NOMMANT : le head est la piece unique du tour.
#
# LE HEAD SECONDAIRE - config/engine/second.sh : REBATI A CHAQUE TOUR, la demande passee.
#   Sa sortie est la couche du plan (l etape courante). S il rend un objet JSON portant
#   result/content/texte/text, ce champ est pris ; sinon la sortie est prise telle quelle.
#   Absent, la boucle pose la couche vide et le DIT.
#
# LE PERIMETRE - la palette du SKILL ACTIF (skills/la/skill.yaml, champ tools:), par NOM
#   de tool, PLUS LA CATEGORIE PERMANENTE. Vide, la palette ouvre toute la table.
#   LA CATEGORIE PERMANENTE (config/la_config.yaml, section `permanent:`) liste, par NOM,
#   les tools TOUJOURS apparents : la boucle l AJOUTE a la palette de chaque tour normal.
#   Une entree `tool:action` (ex. skill_manage:view_skill) ne rend permanent QUE cette action.
#   UN VERROU (preconditions: requires_tool: dans le SKILL ACTIF) REDUIT le perimetre au SEUL
#   tool impose, PLUS quatre garde-fous qui ne tombent JAMAIS : answer, ask, kill, talk (une
#   variable nommee). Sans eux un verrou ne se leve plus, et un agent parti en boucle n a pas de bouton
#   d arret. Un g hors perimetre ferme est refuse PAR LA BOUCLE, dans la MEME forme, et le
#   modele a un tour pour se corriger. LA_SCOPE_TRACE=1 MONTRE le calcul (verrou, permanents, ids).
#
# L ENTREE    la demande de l humain, sur l entree standard.
# LA SORTIE   la reply (le result du dernier answer/ask), sur la sortie standard.
#             le journal du tour, horodate, sur la sortie d erreur (et dans $LA_LOG_FILE si pose).
#
# VARIABLES
#   LA_ROOT    la racine du projet                    (defaut : le parent de config/)
#   LA_TABLE     la table des tools                     (defaut : config/la_tools.yaml)
#   LA_CONF      les adresses des engines               (defaut : config/la_config.yaml)
#   LA_PROCS     les briques                            (defaut : config/engine)
#   LA_ENGINE    le engine                              (defaut : <briques>/engine.sh)
#   LA_ALIAS     l alias du engine a utiliser           (defaut : celui qui porte active: true)
#   LA_MAX_TURNS la borne de SECURITE du tour           (defaut 400 : une borne LARGE, jamais un
#                frein ; le tour s arrete AVANT tout sur le COMPTE DES ETAPES DU PLAN, sur
#                answer le plan termine, ou sur ask. 0 = aucune borne.)
#   LA_MAX_TOKENS la borne de JETONS d une task         (defaut 0 = aucune : elle se DIT d abord,
#                le modele est averti de conclure, puis elle coupe au tour suivant)
#   LA_MAX_CALLS  la borne d APPELS d outil de la task  (defaut 0 = aucune : meme style, elle se
#                DIT d abord puis coupe ; elle borne le TOUR ENTIER, talk compris)
#   LA_MAX_SECONDS la borne de TEMPS MURAL de la task (defaut 0 = aucune : elle se DIT d abord
#                puis coupe ; c est la duree de la TASK, pas celle d un seul appel)
#   LA_LOG_FILE   un fichier ou le journal s AJOUTE en JSONL (une ligne par tool)
#   LA_TRACE     1 : le tool_call BRUT du modele part aussi sur la sortie d erreur
#   LA_SCOPE_TRACE 1 : le CALCUL du perimetre se MONTRE sur la sortie d erreur
#   LA_DEPTH     la profondeur (un agent en dessous ne descend jamais plus bas que 1)
#
# IL FAUT : sh (dash), coreutils, jq, curl. Ni bash, ni python3.
# PIEGE : JAMAIS d accent grave dans ce fichier, meme dans un commentaire - dash ouvre une
# substitution de commande et le fichier ne se lit plus.
# PIEGE : JAMAIS d apostrophe francaise DANS une chaine entre quotes simples : elle FERME la
# chaine. On ecrit l humain, n est, s arrete, sans apostrophe.
# PIEGE : la VALEUR d une cle ne s imprime JAMAIS, meme tronquee. On dit posee ou absente.

set -u
LC_ALL=C
export LC_ALL

# --- [0] QUI JE SUIS, OU SONT LES PIECES --------------------------------------
HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")

# CONFD = config/ ; MOI = config/engine (les BRIQUES) ; le ROOT est le parent de config.
CONFD=$(dirname "$HERE")
ROOT=${LA_ROOT:-$(dirname "$CONFD")}
TABLE=${LA_TABLE:-$CONFD/la_tools.yaml}
CONF=${LA_CONF:-$CONFD/la_config.yaml}
PROCS=${LA_PROCS:-$HERE}
ENGINE=${LA_ENGINE:-$PROCS/engine.sh}
# LA SKILL ACTIVE — la resolution vit dans la bibliotheque commune (config/engine/lib.sh).
[ -f "$HERE/lib.sh" ] || { printf 'loop: the common library is missing (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"
active_skill
HEADF="$CONFD/head.yaml"   # LE HEAD GELE : lu sur place, jamais reecrit, donc le prefixe se met en cache
SECOND_HEAD="$PROCS/second.sh"

# --- LE CORPS DE LA SESSION, ET LA FENETRE (lois 1712, 1715, 1910, 1915, 809) -----
# sessions.db EST LE CORPS : chaque tour y laisse ses lignes, brutes, horodatees. La TABLE
# (config/sessions.yaml) reste tenue par le micro-modele, pour la recherche rapide et a bas prix.
DB=${LA_SESSIONS_DB:-$CONFD/sessions.db}
WINDOW=${LA_WINDOW:-20}          # LA FENETRE GARDE VINGT ECHANGES
MSG_MAX=${LA_MSG_MAX:-8000}      # AUCUN message plus gros que ca : tete ET queue gardees
MSG_BUDGET=${LA_MSG_BUDGET:-32000}   # LE BUDGET de tout ce que le modele LIT (les tetes systeme a part)

db_init() {   # pose le schema si la base est neuve ; rend 1 si sqlite3 manque
  command -v sqlite3 >/dev/null 2>&1 || return 1
  sqlite3 "$DB" 'CREATE TABLE IF NOT EXISTS messages(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      exchange INTEGER NOT NULL,
      ts TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT,
      tool_calls TEXT,
      tool_call_id TEXT,
      name TEXT);' 2>/dev/null || return 1
  sqlite3 "$DB" 'CREATE INDEX IF NOT EXISTS messages_exchange ON messages(exchange, id);' 2>/dev/null || :
  return 0
}

# LA BORNE DE LA CHARGE (B14) ---- le noyau refuse tout argument au-dela de MAX_ARG_STRLEN
# (131 072 octets) et l appel ne PART MEME PAS : c est la panne de 00:04, et elle ne se voit
# qu au moment ou elle tue. Le remede n est pas de raccourcir la boucle : ce que le modele LIT
# est borne (les gros dumps d outil sont tronques, tete ET queue gardees, et le plus RECENT
# garde le plus de place), pendant que le poste GARDE tout (le registre, le journal du tour).
trim_prog() {
  cat <<'JQ'
def coupe($n):
  if (.content|type) != "string" then .
  elif (.content|utf8bytelength) <= $n then .
  else (.content|utf8bytelength) as $L
       | .content = ((.content[0:(($n/4)|floor)])
           + "\n[... TRONQUE : " + ($L|tostring) + " octets au total ; le texte entier est dans config/sessions.db et dans le journal du tour ...]\n"
           + (.content[-(($n/4)|floor):]))
  end;
map(coupe($cap))
| . as $m
| ($m | length) as $nl
| ($m | map(.content|length) | add // 0) as $tot
| ($m | map(select(.role == "tool") | (.content|length)) | add // 0) as $tl
| ($m | map(select(.role == "tool")) | length) as $nt
| if $tot <= $bud or $nt == 0 then $m
  else ((($bud - ($tot - $tl)) / $nt) | floor | if . < 60 then 60 else . end) as $al
       | ($m | to_entries
              | map(.value = (if (.value.role == "tool" and .key != ($nl - 1))
                              then (.value | coupe($al)) else .value end))
              | map(.value))
  end
JQ
}

# LA MARGE DU TOUR (loi 606) : ce qui RESTE du budget une fois pose tout ce qui ne se coupe pas --
# les tetes systeme, les echanges, et le travail en cours (le PLUS RECENT retour d outil). C est
# elle qui decide la coupe ; le sens ne fait que la repartir. Elle est calculee ICI, une fois.
marge_vieux() {   # $1 = un fichier d historique -> octets disponibles pour les VIEUX retours
  jq -r --argjson bud "$MSG_BUDGET" '
    (map((.content // "") | if type == "string" then utf8bytelength else 0 end) | add // 0) as $tot
    | ([ .[] | select(.role == "tool")
         | ((.content // "") | if type == "string" then utf8bytelength else 0 end) ]
       | (.[0:(length - 1)] | add // 0)) as $vieux
    | ($bud - ($tot - $vieux)) | if . < 0 then 0 else . end' "$1" 2>/dev/null || printf '0'
}

# LES FORMES AVANT LE PLAFOND (lois 604-606) : la marge d abord, le sens ensuite, et le plafond
# mecanique de trim_prog reste en garde -- il n est pas double, il est PRECEDE. La brique REFUSE en
# nommant si la marge manque, et rend l historique inchange : ici, on le dit sur la sortie d erreur.
trim_formes() {   # $1 = un fichier d historique -> le meme, formes choisies par le resident
  _m=$(marge_vieux "$1")
  case "${_m:-}" in ''|*[!0-9]*) cat "$1" ; return 0 ;; esac
  "$PROCS/trim_forms.sh" "$1" "${REQUEST:-}" "$_m" || cat "$1"
}

db_add() {    # $1 role, $2 content, $3 tool_calls, $4 tool_call_id, $5 name
  [ -f "$DB" ] || return 0
  _r=$(printf '%s' "$1" | sed "s/'/''/g"); _c=$(printf '%s' "$2" | sed "s/'/''/g")
  _t=$(printf '%s' "$3" | sed "s/'/''/g"); _i=$(printf '%s' "$4" | sed "s/'/''/g")
  _n=$(printf '%s' "$5" | sed "s/'/''/g")
  if [ -n "$_t" ]; then _tr="'$_t'"; else _tr=NULL; fi
  if [ -n "$_i" ]; then _ir="'$_i'"; else _ir=NULL; fi
  if [ -n "$_n" ]; then _nr="'$_n'"; else _nr=NULL; fi
  sqlite3 "$DB" "INSERT INTO messages(exchange, ts, role, content, tool_calls, tool_call_id, name) VALUES($EXCHANGE, '$(ts)', '$_r', '$_c', $_tr, $_ir, $_nr);" 2>/dev/null || :
}

db_insert() {  # verse dans la base les messages NOUVEAUX de l historique du tour
  [ -f "$DB" ] || return 0
  _n=$(jq 'length' "$T/hist.json" 2>/dev/null || printf '0')
  case "${_n:-}" in ''|*[!0-9]*) return 0 ;; esac
  [ "$_n" -gt "$SENT" ] || return 0
  jq -c --argjson n "$SENT" '.[$n:][]' "$T/hist.json" 2>/dev/null | while IFS= read -r _m; do
    [ -n "$_m" ] || continue
    db_add "$(printf '%s' "$_m" | jq -r '.role // ""')" \
           "$(printf '%s' "$_m" | jq -r '.content // ""')" \
           "$(printf '%s' "$_m" | jq -c '.tool_calls // empty')" \
           "$(printf '%s' "$_m" | jq -r '.tool_call_id // ""')" \
           "$(printf '%s' "$_m" | jq -r '.name // ""')"
  done
  SENT=$_n
}

hist_window() {  # LA ZONE 3 : les vingt derniers echanges, BRUTS, identifiants compris
  [ "$EXCHANGE" -gt 1 ] 2>/dev/null || { printf '[]'; return 0 ; }
  _b=$(sqlite3 "$DB" "SELECT MAX(0, COALESCE(MAX(exchange),0) - $WINDOW) FROM messages;" 2>/dev/null || printf '')
  case "${_b:-}" in ''|*[!0-9]*) printf '[]'; return 0 ;; esac
  sqlite3 -json "$DB" "SELECT role, content, tool_calls, tool_call_id, name FROM messages WHERE exchange > $_b ORDER BY id;" 2>/dev/null \
   | jq -c '[.[] | {role, content}
             + (if (.tool_calls // "") == "" then {} else {tool_calls: (.tool_calls | fromjson)} end)
             + (if (.tool_call_id // "") == "" then {} else {tool_call_id: .tool_call_id} end)
             + (if (.name // "") == "" then {} else {name: .name} end)]' 2>/dev/null || printf '[]'
}

TURNS_MAX=${LA_MAX_TURNS:-400}  # une BORNE de securite, jamais un frein : le PLAN, answer
                                # et ask arretent le tour bien avant. 0 = aucune borne.
TOKENS_MAX=${LA_MAX_TOKENS:-0}  # la BORNE de JETONS d une task (0 = aucune). Elle se DIT d abord
                                # (le modele est averti de conclure), puis elle coupe au tour suivant.
CALLS_MAX=${LA_MAX_CALLS:-0}    # la BORNE du nombre TOTAL d APPELS d outil d une task (0 = aucune).
                                # Meme logique : elle se DIT d abord, puis elle coupe au tour suivant.
SECONDS_MAX=${LA_MAX_SECONDS:-0}  # la BORNE de TEMPS MURAL de la task, en SECONDES (0 = aucune).
                                # Meme logique : elle se DIT d abord, puis elle coupe au tour suivant.
TRACE=${LA_TRACE:-0}
TIMEOUT=${LA_TIMEOUT:-600}          # le delai de l APPEL AU MODELE. Un long run doit pouvoir
                                # raisonner, sans laisser une panne pendre une heure
JOURNAL=${LA_LOG_FILE:-}
ENV1=${LA_ENV:-$CONF_DIR/.env}
LA_DEPTH=${LA_DEPTH:-0}
# LA VOIX DU TOUR. Le pont pose LA_VOICE=1 quand la demande est VENUE PAR LA VOIX : le tour
# s ouvre alors par UN MOT, pas par du travail. Sans ce mot, l humain attend tout le travail en
# silence, et le telephone n entend rien avant la toute fin.
LA_VOICE=${LA_VOICE:-0}
export LA_DEPTH LA_ROOT="$ROOT" LA_CONFIG="$TABLE"

die() {
  printf 'loop: %s\n' "$1" >&2
  # LA MORT PARLE AUSSI A L'HUMAIN (B8) : le journal de la boucle va sur la sortie d'erreur, que
  # le pont SAUTE ; mais UNE phrase courte part sur la sortie standard. C'est elle que le pont
  # prononce quand le tour vient par la voix (bridge.sh, 'reply said'), et c'est elle que l'appli
  # affiche. Sans elle, un tour mort rendait une reply VIDE : le travail fait, puis le silence.
  printf 'Le tour s est arrete sans reponse : %s\n' "$(printf '%s' "$1" | cut -c1-160)"
  exit 2
}

# le journal : UNE ligne, horodatee, vers l humain (stderr). Le FICHIER $LA_LOG_FILE, lui,
# ne recoit QUE du JSONL (une entree par tool) : les deux canaux ne se melangent jamais.
log_to_stderr() {  # $1 = une ligne deja plate
  printf '%s\n' "$1" >&2
}

# L HISTORIQUE DU TOUR S ECRIT TOUJOURS PAREIL : un filtre jq rend le nouveau tableau, on le
# pose, et le remplacement est ATOMIQUE (jamais un hist.json tronque). $@ = options + filtre jq.
hist_apply() {
  jq -c "$@" "$T/hist.json" > "$T/hist.next" || return 1
  _src="$T/hist.next"
  # LES FORMES SEULEMENT QUAND LA BORNE PEUT MORDRE. Un fichier plus PETIT que le budget ne sera pas
  # coupe (le JSON pese plus lourd que ses contenus), et reveiller le resident a chaque mutation
  # d historique couterait cher pour rien : hist_apply est appele des dizaines de fois par tour.
  # C est la loi 826 : la RAM se rembourse en tokens, et une question deja repondue ne se repose pas.
  _o=$(wc -c < "$T/hist.next" 2>/dev/null || printf '0')
  case "${_o:-}" in ''|*[!0-9]*) _o=0 ;; esac
  if [ "$_o" -gt "$MSG_BUDGET" ]; then
    trim_formes "$T/hist.next" > "$T/hist.forms" && _src="$T/hist.forms"
  fi
  jq -c --argjson cap "$MSG_MAX" --argjson bud "$MSG_BUDGET" "$(trim_prog)" "$_src" > "$T/hist.trim" \
    && mv "$T/hist.trim" "$T/hist.json"
}

# LA LIGNE DU MOTEUR PORTE SON RESULTAT SOUS .result ; $1 = la ligne, $2 = le defaut (vide).
result_of() { printf '%s' "$1" | jq -r --arg d "${2:-}" '.result // $d' 2>/dev/null || printf '%s' "${2:-}"; }

# --- [1] LES OUTILS DE LA MACHINE ---------------------------------------------
[ -n "${ROOT:-}" ] || die "LA_ROOT is not set : the loop does not know where the project is."
[ -d "$ROOT" ]     || die "the project is not there : $ROOT"
[ -f "$TABLE" ]      || die "the table is missing : $TABLE"
[ -f "$CONF" ]       || die "the engine config is missing : $CONF"
[ -f "$ENGINE" ]     || die "the engine is missing : $ENGINE"
command -v jq   >/dev/null 2>&1 || die "jq is missing"
command -v curl >/dev/null 2>&1 || die "curl is missing"
SH=$(command -v dash 2>/dev/null) || SH=$(command -v sh 2>/dev/null)
[ -n "$SH" ] || die "no sh (dash) on the machine"

# --- [2] LES CLES. Le .env du projet, une variable deja posee GAGNE -----------
# La valeur ne sort JAMAIS d ici : on ne dit que le NOM et posee ou absente.
load_env() {  # $1 = un fichier KEY=VALUE
  [ -f "$1" ] || return 0
  while IFS= read -r L || [ -n "$L" ]; do
    case "$L" in ''|\#*) continue ;; esac
    case "$L" in *=*) ;; *) continue ;; esac
    K=${L%%=*}
    V=${L#*=}
    case "$K" in ''|*[!A-Za-z0-9_]*) continue ;; esac
    case "$K" in [0-9]*) continue ;; esac
    case "$V" in
      \"*\") V=$(printf '%s' "$V" | sed -e 's/^"//' -e 's/"$//') ;;
      \'*\') V=$(printf '%s' "$V" | sed -e "s/^'//" -e "s/'$//") ;;
    esac
    ALREADY=$(printenv "$K" 2>/dev/null || true)
    [ -n "$ALREADY" ] && continue
    export "$K=$V" 2>/dev/null || :
  done < "$1"
}
load_env "$ENV1"

# --- [3] LE ENGINE ACTIF : la seule adresse qui porte active: "true" ----------
# La config est un YAML : on la parcourt comme la table, au grep et au sed.
active_block() {
  DEBS=$(grep -n '^  - provider:' "$CONF" | cut -d: -f1)
  [ -n "$DEBS" ] || return 1
  TOTAL=$(wc -l < "$CONF")
  N=$(printf '%s\n' "$DEBS" | grep -c .)
  i=0
  while [ "$i" -lt "$N" ]; do
    i=$((i + 1))
    D=$(printf '%s\n' "$DEBS" | sed -n "${i}p")
    F=$(printf '%s\n' "$DEBS" | sed -n "$((i + 1))p")
    F=${F:-$((TOTAL + 1))}
    B=$(sed -n "${D},$((F - 1))p" "$CONF")
    case "$B" in
      *'active: "true"'*|*'active: true'*)
        if [ -n "${LA_ALIAS:-}" ]; then
          case "$B" in *"alias: $LA_ALIAS"*) printf '%s' "$B"; return 0 ;; esac
        else
          printf '%s' "$B"; return 0
        fi
        ;;
    esac
  done
  return 1
}
FIELD() { printf '%s\n' "$1" | sed -n "s/^[[:space:]]*-\{0,1\}[[:space:]]*$2:[[:space:]]*//p" | head -n 1 | sed -e 's/^"//' -e 's/"$//' ; }

MB=$(active_block) || die "no engine is active in $CONF"
POST=$(FIELD "$MB" post)
MODEL=$(FIELD "$MB" model)
HEADER=$(FIELD "$MB" header)
VARIABLE=$(FIELD "$MB" variable)
MAX_TOKENS=$(FIELD "$MB" max_tokens)
TOOL_CHOICE=$(FIELD "$MB" tool_choice)
PROVIDER=$(FIELD "$MB" provider)
[ -n "$POST" ] || die "the active engine carries no address (post)"
[ -n "$MODEL" ] || die "the active engine carries no model (model)"
case "${TOOL_CHOICE:-}" in required|auto|none) ;; *) TOOL_CHOICE=auto ;; esac
case "${MAX_TOKENS:-}" in ''|*[!0-9]*) MAX_TOKENS=2048 ;; esac

# L ADRESSE : un entete d autorisation. Un engine sans variable est local : aucun entete.
KEY=""
AUTH=""
if [ -n "$VARIABLE" ]; then
  KEY=$(printenv "$VARIABLE" 2>/dev/null || true)
  if [ -n "$KEY" ]; then STATE_KEY=set; else STATE_KEY=ABSENT; fi
  printf 'loop: variable %s is %s (value never printed) ; engine %s / %s\n' \
    "$VARIABLE" "$STATE_KEY" "$PROVIDER" "$MODEL" >&2
  [ -n "$KEY" ] || die "variable $VARIABLE is empty : the engine cannot answer"
  case "$HEADER" in
    ""|Authorization) AUTH="Authorization: Bearer $KEY" ;;
    *) AUTH="$HEADER: $KEY" ;;
  esac
fi

# --- [4] LE SCHEMA UNIQUE, ET LE PROTOCOLE -----------------------------------
# La demande, elle, est lue sur l entree standard JUSTE avant le tour (section [9]) : le head
# est lu d abord, et le refus d une entree vide tombe APRES, une fois le projet annonce.

# LE SEUL SCHEMA : il est ECRIT DANS LE HEAD, en UN SEUL EXEMPLAIRE, AU FORMAT OPENAI
# (config/head.yaml, section TOOLS_SCHEMA), et le engine le LIT. Le code ne le fabrique plus.
head_schema() {  # $1 = le head ; rend la ligne de la section TOOLS_SCHEMA
  sed -n '/^TOOLS_SCHEMA:[[:space:]]*$/,/^[^[:space:]]/p' "$1" \
    | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' | head -n 1
}
TOOLS=$(head_schema "$HEADF")
[ -n "$TOOLS" ] || die "the head carries no TOOLS_SCHEMA section : $HEADF"
printf '%s' "$TOOLS" | jq -e 'type == "array" and length == 1 and .[0].type == "function" and .[0].function.name == "la"' >/dev/null 2>&1 \
  || die "the head schema is not an OpenAI tool : a one-element list, type:function, function.name:la"
printf 'loop: the single schema is read (%s, %s byte(s))\n' "$HEADF" "$(printf '%s' "$TOOLS" | wc -c)" >&2

PROTOCOL='LA REGLE DU TOUR : tu ne reponds JAMAIS par du texte. Tu CHOISIS un tool de la table, et le engine de ce tool l execute. Tu n as qu UN SEUL outil, la : g nomme le NUMERO du tool, a porte ses arguments DANS L ORDRE DECLARE par sa ligne. Le SURPLUS de a - le texte libre - part sur l INPUT STANDARD du tool : il n est pas un argument nomme.
LE TOOL QUI REPOND : son PREMIER argument est la FORME (text, list, table, code) et TOUT LE RESTE de a EST ta reponse, mot pour mot. Exemple : a = ["list", "voici l inventaire ..."]. Un tool sans texte ne dit RIEN a l humain : ton texte EST ta reponse.
Ce que tu fais se passe TOUJOURS par un tool : un texte sans tool n est pas une reponse.'

# --- [5] LA TABLE : lire une ligne, compter ses arguments hors stdin ----------
all_ids() { table_ids "$TABLE"; }

block_of_id() {  # $1 = l id ; rend le bloc, ou echoue
  table_block "$TABLE" "$1"
}

args_section() {  # $1 = bloc
  printf '%s\n' "$1" | sed -n '/^    args:/,/^    [a-z]/p' | sed '$d'
}

# LA LOI DU DECOUPAGE : le nombre d arguments declares HORS stdin.
count_non_stdin() {  # $1 = bloc
  A=$(args_section "$1")
  NA=$(printf '%s\n' "$A" | grep -c '^      - {')
  NS=$(printf '%s\n' "$A" | sed -n 's/^      - {\(.*\)}[[:space:]]*$/\1/p' | grep -c 'stdin:[[:space:]]*true')
  printf '%s' "$((NA - NS))"
}

args_text() {  # $1 = bloc ; rend les noms, leur FORME, et ce que la ligne FERME
  # LA LOI : le modele recoit ce que la ligne FERME, pas un nom nu. Un enum rend sa liste
  # ENTIERE, dans le MEME rendu que le refus du engine (join " | ", engine.sh:359) ; un
  # argument ouvert rend son TYPE. La borne n'a plus a s'apprendre par un refus.
  args_section "$1" | sed -n 's/^      - {\(.*\)}[[:space:]]*$/\1/p' | while IFS= read -r SPEC; do
    NM=$(printf '%s' "$SPEC" | sed -n 's/.*name:[[:space:]]*\([A-Za-z0-9_]*\).*/\1/p')
    [ -n "$NM" ] || continue
    TY=$(printf '%s' "$SPEC" | sed -n 's/.*type:[[:space:]]*\([a-z]*\).*/\1/p')
    FO="$TY"
    case "$SPEC" in
      *'values:'*)
        LIST=$(printf '%s' "$SPEC" | sed -n 's/.*values:[[:space:]]*\[\([^]]*\)\].*/\1/p' \
          | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' \
          | jq -R . | jq -cs . | jq -r 'join(" | ")')
        [ -n "$LIST" ] && FO="$TY : $LIST"
        ;;
    esac
    case "$SPEC" in
      *'stdin: true'*) FO="$FO,stdin" ;;
    esac
    printf '%s(%s) ' "$NM" "$FO"
  done
}

# --- [6] LE SKILL ACTIF : la portee -------------------------------------------
[ -f "$SKILL" ] || die "the ACTIVE SKILL is not found ($SKILL) : the scope is unknown"

# --- [6bis] L ETAT DE L ENTREE : les verrous en cascade ----------------------
# LE SKILL, LA DOC ET LE PLAN OUVRENT LE TOOLSET DANS CET ORDRE (lois 1000, 1002) :
#   load_skill -> load_doc (LA DOC) -> manage_plan (LE PLAN) -> LES TOOLS DU SKILL.
# Trois drapeaux, tenus par la BOUCLE (aucun fichier d etat), armes au tour ou le modele
# APPELLE le tool (le perimetre garantit deja qu il etait atteignable) :
#   DOC_READ      : load_doc a ete appele -> la famille PLAN s ouvre.
#   PLAN_DONE     : un outil de plan a ete appele -> le TOOLSET du skill s ouvre.
#   TOOLSET_ARMED : `toolset` a ete appele -> 100% pour le tour SUIVANT, puis retour a 30%.
DOC_READ=0
PLAN_DONE=0
TOOLSET_ARMED=0
PLAN_FAMILY='start_plan load_plan advance_plan revise_plan close_plan abort_plan'
SHARE_NAMES=''

# LE SKILL ACTIF, RELU A CHAQUE TOUR (load_skill reecrit skills/.active) : le champ TOOLS: du
# skill, une liste sous la cle, ou une liste en ligne. Un skill SANS tool (SK_TOOLS vide) est
# un etat VALIDE : le perimetre large, comme la boucle le faisait deja.
SK_TOOLS_EMPTY=1
SK_TOOLS=''
read_skill_tools() {
  SK_TOOLS_EMPTY=1; SK_TOOLS=''
  LINE_TOOLS=$(sed -n 's/^TOOLS:[[:space:]]*//p' "$SKILL" | head -n 1)
  if [ -n "$LINE_TOOLS" ]; then
    case "$LINE_TOOLS" in
      \[*\])
        SK_TOOLS=$(printf '%s' "$LINE_TOOLS" | sed -e 's/^\[//' -e 's/\]$//' | tr ',' '\n' \
          | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' | grep -v '^$')
        ;;
    esac
  fi
  if [ -z "$SK_TOOLS" ]; then
    # Deux formes sous la cle TOOLS: - la forme `- name`, ET la forme `ID: name` (l ID n est
    # pas une position : chaque ligne de la section porte son ID). Dans les deux cas, on ne
    # retient que le NOM du tool.
    SK_TOOLS=$(sed -n '/^TOOLS:/,/^[^[:space:]]/p' "$SKILL" \
      | sed -n 's/^[[:space:]]*-[[:space:]]*//p; s/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
      | sed -e 's/^"//' -e 's/"$//' | grep -v '^$')
  fi
  [ -n "$SK_TOOLS" ] && SK_TOOLS_EMPTY=0
}

# LES GARDE-FOUS : les tools qui ne tombent JAMAIS, meme sous un verrou. Sans eux, un
# verrou ne se leve plus (answer, ask), un agent parti en boucle n a aucun bouton d arret
# (kill), et le modele ne peut plus PARLER (talk). La PROPRIETE vit dans la TABLE
# (config/la_tools.yaml, champ `guardrail: true`) : le code ne NOMME plus ces tools.
read_guardrails() {  # les tools `guardrail: true` de la table, separes par un espace
  for ID in $(all_ids); do
    B=$(block_of_id "$ID") || continue
    [ "$(FIELD "$B" guardrail)" = true ] && FIELD "$B" tool
  done | tr '\n' ' ' | sed -e 's/[[:space:]]*$//'
}
GUARDRAILS=$(read_guardrails)
[ -n "$GUARDRAILS" ] || die "the table declares no guardrail (guardrail: true) : the harness cannot arm a lock"

# LA CATEGORIE PERMANENTE : les tools TOUJOURS apparents, par NOM, lus dans la CONFIG
# (config/la_config.yaml, section `permanent:`). C est son SEUL endroit de declaration.
# Une entree `tool:action` (ex. skill_manage:view_skill) ne vaut QUE pour cette action-la :
# la LIGNE skill_manage porte treize actions, et la marquer rendrait create_skill et
# remove_skill permanents du meme coup, ce qu on refuse.
read_permanent() {  # la section permanente, une entree par ligne
  permanent_section "$CONF"
}
PERMANENTS=$(read_permanent)
if [ -z "$PERMANENTS" ]; then
  printf 'loop: the PERMANENT section is EMPTY or MISSING (%s) : only the guardrails are kept (answer, ask, kill, talk).\n' "$CONF" >&2
  PERMANENTS="$GUARDRAILS"
fi

# le tool TOUT ENTIER est-il permanent ? (une entree sans action)
tool_is_permanent() {  # $1 = nom
  printf '%s\n' "$PERMANENTS" | grep -qxF -- "$1"
}
# les ACTIONS permanentes d un tool (entrees `nom:action`) ; vide si le tool entier l est
permanent_actions() {  # $1 = nom
  printf '%s\n' "$PERMANENTS" | sed -n "s/^$1://p" | tr '\n' ' '
}
# le tool est-il permanent pour CETTE action-la ? ($2 = l action, peut etre vide)
is_permanent() {  # $1 = nom, $2 = l action (ou vide)
  printf '%s\n' "$PERMANENTS" | while IFS= read -r P; do
    [ -n "$P" ] || continue
    case "$P" in
      *:*)
        [ "${P%%:*}" = "$1" ] && [ "${P#*:}" = "$2" ] && { printf 'yes\n'; break; } ;;
      *)
        [ "$P" = "$1" ] && { printf 'yes\n'; break; } ;;
    esac
  done | grep -q yes
}

# LE VERROU : le tool IMPOSE, lu dans le SKILL ACTIF (preconditions: requires_tool: ...).
# Arme, il REDUIT le perimetre a ce seul tool, plus les garde-fous.
read_lock() {
  [ -f "$SKILL" ] || return 0
  sed -n '/^preconditions:/,/^[^[:space:]]/p' "$SKILL" 2>/dev/null \
    | sed -n 's/^[[:space:]]*requires_tool:[[:space:]]*//p' | head -n 1 \
    | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//'
}
LOCK=$(read_lock)

# le NOM du skill ouvre-t-il ce tool ?
in_skill() {  # $1 = nom
  printf '%s\n' "$SK_TOOLS" | while IFS= read -r N; do
    [ "$N" = "$1" ] && { printf 'yes\n'; break; }
  done | grep -q yes
}

# LES PALIERS DE LA CH AINE DE L ENTREE : trois verrous en cascade (lois 1000, 1002-1003).
#   palier 1 : la doc n est pas lue      -> la famille PLAN est FERMEE (load_doc reste ouvert).
#   palier 2 : la doc est lue, plan non fait -> les tools du SKILL sont FERMES.
#   palier 3 : le plan est fait          -> le TOOLSET du skill (les 30% de tete) + les permanents.
#   palier 3bis : `toolset` vient d etre appele -> le TOOLSET EN ENTIER (100%), sans `toolset`.
in_share() {  # $1 = nom : est-il dans la part de tete (le 30%) ?
  printf '%s\n' "$SHARE_NAMES" | grep -qxF -- "$1"
}
in_plan_family() { case " $PLAN_FAMILY " in *" $1 "*) return 0 ;; esac; return 1; }

# LE RERANKER : le resident sur 127.0.0.1:$LA_RERANK_PORT. Il NOTE chaque candidat du skill.
# IL POSE $SHARE_NAMES, ET REND 1 S'IL MANQUE. Il ne die PAS ici : appele dans un $(...), un die
# n'y tuerait que le SOUS-SHELL, et la boucle continuerait avec un perimetre VIDE, en silence --
# c'est le bug que le verdict B19 a attrape. C'est l'APPELANT (scope_build, hors subshell) qui die.
rank_share() {   # $1 = fichier candidats (id|nom|description) ; $2 = la demande ; pose SHARE_NAMES
  _cand=$1; _q=$2
  SHARE_NAMES=''
  [ -s "$_cand" ] || return 0
  [ -n "$_q" ] || _q=' '
  _port=${LA_RERANK_PORT:-8095}
  _k=$(wc -l < "$_cand" | tr -d ' ')
  _part=$(( (_k * 30 + 99) / 100 )); [ "$_part" -ge 1 ] || _part=1
  _req=$(jq -cn --arg q "$_q" --rawfile docs "$_cand" --argjson n "$_k" \
    '{query:$q, documents:($docs|split("\n")|map(select(length>0))), top_n:$n}')
  _rep=$(printf '%s' "$_req" | curl -sS --max-time 15 -X POST \
    "http://127.0.0.1:$_port/v1/rerank" -H 'Content-Type: application/json' -d @- 2>/dev/null) || _rep=''
  [ -n "$_rep" ] || return 1
  _names=$(jq -R 'split("|")[1]' "$_cand" | jq -s '.')
  SHARE_NAMES=$(printf '%s' "$_rep" | jq -r --argjson names "$_names" --argjson k "$_part" \
    '(.results // .) | sort_by(-.relevance_score) | .[0:$k] | .[] | $names[.index]' 2>/dev/null)
  [ -n "$SHARE_NAMES" ]
}

# CE TOOL EST-IL DANS LE PERIMETRE DU TOUR ? (pour BATIR la liste ; l action viendra apres)
reachable() {  # $1 = nom
  if [ -n "$LOCK" ]; then
    case " $GUARDRAILS $LOCK " in *" $1 "*) return 0 ;; esac
    return 1
  fi
  # load_doc : le lecteur de doc, TOUJOURS la (sans lui, la chaine ne demarre jamais)
  [ "$1" = load_doc ] && return 0
  # la famille PLAN : fermee tant que la doc n est pas lue
  if in_plan_family "$1"; then [ "$DOC_READ" = 1 ] && return 0 || return 1; fi
  # toolset : ferme avant le plan ; ABSENT au tour arme (100%) ; ouvert sinon
  if [ "$1" = toolset ]; then
    if [ "$PLAN_DONE" = 1 ] && [ "$TOOLSET_ARMED" != 1 ]; then return 0; else return 1; fi
  fi
  # les permanents (hors plan/toolset, deja traites)
  tool_is_permanent "$1" && return 0
  [ -n "$(permanent_actions "$1")" ] && return 0
  # les tools du SKILL : fermes tant que le plan n est pas fait
  [ "$PLAN_DONE" = 1 ] || return 1
  [ "$SK_TOOLS_EMPTY" = 1 ] && return 0
  in_skill "$1" || return 1
  # in_skill : le tour arme ouvre TOUT ; sinon, la part de tete (le 30%)
  [ "$TOOLSET_ARMED" = 1 ] && return 0
  in_share "$1"
}

# LE TOOL PASSE-T-IL, ICI ET MAINTENANT ? ($3 = l action demandee, pour `nom:action`)
in_scope() {  # $1 = nom, $2 = family, $3 = l action (ou vide)
  if [ -n "$LOCK" ]; then
    case " $GUARDRAILS $LOCK " in *" $1 "*) return 0 ;; esac
    return 1
  fi
  [ "$1" = load_doc ] && return 0
  if in_plan_family "$1"; then [ "$DOC_READ" = 1 ] && return 0 || return 1; fi
  if [ "$1" = toolset ]; then
    if [ "$PLAN_DONE" = 1 ] && [ "$TOOLSET_ARMED" != 1 ]; then return 0; else return 1; fi
  fi
  is_permanent "$1" "$3" && return 0
  [ "$PLAN_DONE" = 1 ] || return 1
  [ "$SK_TOOLS_EMPTY" = 1 ] && return 0
  in_skill "$1" || return 1
  [ "$TOOLSET_ARMED" = 1 ] && return 0
  in_share "$1"
}

# ---- LA PORTEE, REBATIE A CHAQUE TOUR : le skill peut changer, et les paliers bougent --------
# Elle relit le skill ACTIF frais, ses TOOLS:, le verrou, puis BATIT la liste. Appelee UNE FOIS
# PAR TOUR, en tete de boucle (apres la demande et le plan), JAMAIS une fois pour toutes.
scope_build() {
  active_skill
  SKILL="$SKILLS_DIR/$NAME/skill.yaml"
  [ -f "$SKILL" ] || die "the ACTIVE SKILL is not found ($SKILL) : the scope is unknown"
  read_skill_tools
  LOCK=$(read_lock)
  SHARE_NAMES=''
  # la part de tete : seulement quand la chaine est OUVERTE (doc lue + plan fait) et NON armee
  if [ -z "$LOCK" ] && [ "$DOC_READ" = 1 ] && [ "$PLAN_DONE" = 1 ] && [ "$TOOLSET_ARMED" != 1 ]; then
    _cand="$T/share.cand"; : > "$_cand"
    for ID in $(all_ids); do
      B=$(block_of_id "$ID") || continue
      TN=$(FIELD "$B" tool)
      in_skill "$TN" || continue
      # on ne CLASSE pas ce qui est TOUJOURS la (les permanents, load_doc, toolset) : classer un
      # tool deja present gaspille un rang de la part. Le reranker ne choisit QUE parmi les tools
      # MOUVANTS du skill ceux qui entrent dans la part ; les permanents sont ajoutes APRÈS.
      tool_is_permanent "$TN" && continue
      [ -n "$(permanent_actions "$TN")" ] && continue
      [ "$TN" = load_doc ] && continue
      [ "$TN" = toolset ] && continue
      printf '%s|%s|%s\n' "$ID" "$TN" "$(FIELD "$B" description)" >> "$_cand"
    done
    rank_share "$_cand" "${REQUEST:-} ${PLAN_TXT:-}" \
      || die "the reranker is silent on 127.0.0.1:${LA_RERANK_PORT:-8095} : the resident must be in RAM (rerank.sh start). This is an ENGINE bug, not a turn."
  fi
  # LA TETE DE LA PORTEE : elle DIT le palier de la chaine de l entree (lois 1000, 1002)
  SCOPE_IDS=' '
  if [ -n "$LOCK" ]; then
    SCOPE_TXT="LES TOOLS ATTEIGNABLES CE TOUR - UN LOCK EST ARME (tool impose : $LOCK) : le perimetre est REDUIT a ce seul tool, EXTRA les garde-fous answer, ask, kill, talk. Par leur NUMERO :
"
  elif [ "$DOC_READ" != 1 ]; then
    SCOPE_TXT="LES TOOLS ATTEIGNABLES CE TOUR - LA DOC N EST PAS ENCORE LUE : la famille PLAN est FERMEE. Lis la doc (load_doc) pour ouvrir le plan. Les permanents, par leur NUMERO :
"
  elif [ "$PLAN_DONE" != 1 ]; then
    SCOPE_TXT="LES TOOLS ATTEIGNABLES CE TOUR - LA DOC EST LUE, LE PLAN N EST PAS FAIT : les tools du SKILL sont FERMES. Fais le plan (start_plan / load_plan / advance_plan) pour ouvrir le toolset. Par leur NUMERO :
"
  elif [ "$TOOLSET_ARMED" = 1 ]; then
    SCOPE_TXT="LES TOOLS ATTEIGNABLES CE TOUR - LE TOOLSET EST OUVERT EN ENTIER (toolset vient d etre nomme) : le tour COMPLET du skill actif, EXTRA les permanents. toolset est ABSENT de ce tour. Par leur NUMERO :
"
  else
    SCOPE_TXT="LES TOOLS ATTEIGNABLES CE TOUR - LE TOOLSET DU SKILL (les 30% les plus probables pour cette tache), EXTRA les permanents. Si un tool te manque, nomme toolset : la liste complete t est rendue. Par leur NUMERO :
"
  fi
  for ID in $(all_ids); do
    B=$(block_of_id "$ID") || continue
    TN=$(FIELD "$B" tool)
    FA=$(FIELD "$B" family)
    DE=$(FIELD "$B" description)
    if reachable "$TN"; then
      ARGS=$(args_text "$B")
      AP=$(permanent_actions "$TN")
      SCOPE_IDS="$SCOPE_IDS$ID "
      SCOPE_TXT="$SCOPE_TXT  $ID  $TN  [$FA]  $DE
         args : ${ARGS:-aucun}
"
      [ -z "$AP" ] || SCOPE_TXT="$SCOPE_TXT         PERMANENT SEULEMENT pour ces actions : $AP
"
    fi
  done
  [ "$SCOPE_IDS" != ' ' ] || die "the scope is empty : no reachable tool"
  SCOPE_TXT="$SCOPE_TXT Un numero HORS de cette liste est refuse par le harnais : il te le dira, et tu auras un turn pour te corriger."
  # LA TRACE DU CALCUL : avec LA_SCOPE_TRACE=1, le perimetre se MONTRE (palier, verrou, ids).
  if [ "${LA_SCOPE_TRACE:-0}" = 1 ]; then
    printf 'loop: SCOPE  lock=[%s]  doc_read=%s  plan_done=%s  toolset_armed=%s\n' \
      "${LOCK:-aucun}" "$DOC_READ" "$PLAN_DONE" "$TOOLSET_ARMED" >&2
    printf 'loop: SCOPE  ids kept=%s\n' "$SCOPE_IDS" >&2
  fi
  # TOOLSET ARME : consomme ICI, APRES le calcul (le 100% vaut pour CE tour ; retour a 30% ensuite)
  [ "$TOOLSET_ARMED" = 1 ] && TOOLSET_ARMED=0
}

# --- [7] LE HEAD, ET LE HEAD SECONDAIRE ---------------------------------------
# config/head.yaml, GELE : il porte des SECTIONS en MAJUSCULES (cle:) et des LIGNES numerotees
# (101: "texte"). On en tire un PREAMBULE PLAT : les lignes numerotees rendent leur texte,
# les cles restent des titres. Les commentaires et les lignes vides sortent.
clean_head() {  # $1 = le fichier ; rend le preambule plat sur la sortie standard
  # LA SECTION TOOLS_SCHEMA NE PART PAS DANS LA TETE : elle porte le JSON du tool unique, et
  # ce JSON est DEJA dans `tools` de l appel. L'envoyer deux fois paie deux fois.
  sed -e '/^TOOLS_SCHEMA:[[:space:]]*$/,/^[^[:space:]]/{/^TOOLS_SCHEMA:[[:space:]]*$/d;/^[^[:space:]]/!d;}' \
      -e 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/' \
      -e 's/^[[:space:]]*\([a-z_][a-z_0-9]*\):[[:space:]]*\(.*\)$/\1: \2/' \
      -e '/^[[:space:]]*# /d' -e '/^[[:space:]]*#$/d' -e '/^[[:space:]]*$/d' "$1"
}

HEAD_TXT=''
if [ -f "$HEADF" ] && [ -r "$HEADF" ]; then
  HEAD_TXT=$(clean_head "$HEADF")
  printf 'loop: the head is read (%s, %s byte(s))\n' "$HEADF" "$(printf '%s' "$HEAD_TXT" | wc -c)" >&2
else
  die "the head is missing : $HEADF (the loop does not run without a head)"
fi
[ -n "$HEAD_TXT" ] || die "the head is empty : $HEADF"

# LE HEAD SECONDAIRE : config/engine/second.sh, REBATI A CHAQUE TOUR (le plan bouge, et peu).
SECOND_OK=0
[ -x "$SECOND_HEAD" ] && SECOND_OK=1
if [ "$SECOND_OK" = 1 ]; then
  printf 'loop: the secondary head is read (%s), rebuilt at every turn\n' "$SECOND_HEAD" >&2
else
  printf 'loop: second.sh is MISSING (%s) : the plan layer is empty. It is read as soon as it exists.\n' "$SECOND_HEAD" >&2
fi
read_second() {
  if [ "$SECOND_OK" = 1 ]; then
    S2=$("$SECOND_HEAD" "$REQUEST" 2>/dev/null) || S2=''
    PJ=$(printf '%s' "$S2" | jq -r '.result // .content // .text // empty' 2>/dev/null || true)
    [ -n "$PJ" ] && S2=$PJ
    printf '%s' "$S2"
  else
    printf '%s' 'AUCUN PLAN OUVERT : second.sh est absent, et la couche du plan est vide.'
  fi
}

# --- [8] L ESPACE DE TRAVAIL, LE NETTOYAGE, L INTERRUPTION --------------------
T=$(mktemp -d "${TMPDIR:-/tmp}/loop.XXXXXX" 2>/dev/null)
[ -n "$T" ] && [ -d "$T" ] || die "the temp dir could not be opened (${TMPDIR:-/tmp})"
cleanup_tmp_loop() { rm -f "$T"/* 2>/dev/null; rmdir "$T" 2>/dev/null; }
trap 'cleanup_tmp_loop' EXIT
trap 'printf "\nloop: INTERRUPTION - le turn s arrete ici, a la main.\n" >&2; exit 130' INT TERM HUP

: > "$T/read_log"; : > "$T/written"; : > "$T/counter"
printf '[]' > "$T/hist.json"; : > "$T/curl.err"

# LA BASE ET L ECHANGE : le numero du tour, puis la fenetre des vingt derniers, lue AVANT
# que ce tour n ecrive ses lignes (sinon il se relirait lui-meme).
EXCHANGE=1; SENT=0; WINDOW_JSON='[]'
if db_init; then
  EXCHANGE=$(sqlite3 "$DB" 'SELECT COALESCE(MAX(exchange),0)+1 FROM messages;' 2>/dev/null || printf '')
  case "${EXCHANGE:-}" in ''|*[!0-9]*) EXCHANGE=1 ;; esac
  WINDOW_JSON=$(hist_window)
else
  log_to_stderr "$(ts)  la base des sessions n a pas pu etre ouverte ($DB) : le contexte part sans la fenetre"
fi

# LA DEMANDE : lue ici, une fois le head annonce. Vide, le tour ne part pas - et il le dit.
REQUEST=$(cat)
[ -n "$REQUEST" ] || die "no request on the input : a turn starts from a request."
db_add "user" "$REQUEST" "" "" ""     # la demande entre dans le corps, horodatee

# LA FENETRE PASSE AUX FORMES ICI, PAS PLUS TOT : la coupe se juge CONTRE LA DEMANDE (lois 604-606),
# et la demande ne se lit que quelques lignes au-dessus -- avant, la fenetre etait rognee sans savoir
# quoi garder. Les formes d abord (la marge decide, le sens repartit), le plafond mecanique ensuite :
# il n est pas double, il est PRECEDE. C est la meme porte que le verdict B14 mesure.
printf '%s' "$WINDOW_JSON" > "$T/window.raw"
if [ -s "$T/window.raw" ]; then
  WINDOW_JSON=$(trim_formes "$T/window.raw" \
    | jq -c --argjson cap "$MSG_MAX" --argjson bud "$MSG_BUDGET" "$(trim_prog)" 2>/dev/null || printf '[]')
fi

# --- [9] LA BOUCLE ------------------------------------------------------------
FACTS() { printf 'FACTS  date %s  time %s  locale UTC' "$(date -u +%Y-%m-%d)" "$(date -u +%H:%M)"; }

build_messages() {  # la demande est dans $REQUEST ; l etat dans $STATE ; les faits dans $FACTS
  jq -cn \
    --arg head "$HEAD_TXT" --arg prot "$PROTOCOL" --arg scope "$SCOPE_TXT" \
    --arg state "$STATE" --arg plan "$PLAN_TXT" --arg request "$REQUEST" --arg facts "$FACTS" \
    --arg voice "$VOICE_TXT" \
    --argjson hist "$(cat "$T/hist.json")" --argjson window "$WINDOW_JSON" \
    '[{role:"system",content:$head},{role:"system",content:$prot},{role:"system",content:$scope},{role:"system",content:$state}]
     + (if $plan == "" then [] else [{role:"system",content:$plan}] end)
     + $window
     + (if $voice == "" then [] else [{role:"system",content:$voice}] end)
     + [{role:"user",content:$request}]
     + $hist
     + [{role:"system",content:$facts}]'
}

call() {  # $1 = le corps JSON ; rend la reply sur la sortie standard
  if [ -n "$AUTH" ]; then
    curl -sS --max-time "$TIMEOUT" -X POST "$POST" \
      -H "$AUTH" -H 'Content-Type: application/json' -d "$1" 2>"$T/curl.err"
  else
    curl -sS --max-time "$TIMEOUT" -X POST "$POST" \
      -H 'Content-Type: application/json' -d "$1" 2>"$T/curl.err"
  fi
}

# le engine, et son decoupage : argc = min(declares hors stdin, taille de a) ; le surplus -> stdin
exec_engine() {  # $1 = g ; $2 = le nombre d arguments hors stdin ; $3 = le chemin de a.json
  # local : ces noms NE DOIVENT PAS deborder sur les compteurs de l appelant (piege du I).
  local G N AF I V
  G=$1; N=$2; AF=$3
  set -- "$SH" "$ENGINE" "$G"
  I=0
  while [ "$I" -lt "$N" ]; do
    V=$(jq -r --argjson i "$I" '.[$i] // ""' "$AF")
    set -- "$@" "$V"
    I=$((I + 1))
  done
  jq -r --argjson n "$N" 'if length > $n then .[$n:] | join("\n") else "" end' "$AF" > "$T/stdin.txt"
  # [10] LE TOOL TRAVAILLE EN ARRIERE-PLAN, ET LA BOUCLE LE SURVEILLE : un long run ne se
  # fait pas en silence. Un mot vers l humain toutes les 15 s, et la boucle reprend la main
  # des que le tool a rendu. Jamais d attente muette, jamais de coupe prematuree.
  "$@" < "$T/stdin.txt" > "$T/engine.out" 2> "$T/engine.err" &
  local PID C
  PID=$!
  C=0
  while kill -0 "$PID" 2>/dev/null; do
    sleep 0.5
    kill -0 "$PID" 2>/dev/null || break
    C=$((C + 1))
    if [ $((C % 30)) -eq 0 ]; then
      printf 'loop: %s has been working for %s s\n' "${TN:-le tool}" "$((C / 2))" >&2
    fi
  done
  wait "$PID"
  return $?
}

# une ligne de refus, DANS LA FORME UNIQUE, pour un tool hors perimetre
refuse_loop() {  # $1 = le texte du refus
  jq -cn --arg t "$(ts)" --arg m "$1" \
    '{status:"refused",tool:"la",line:($t+"  "+$m),result:("refus : "+$m),ts:$t}'
}

plan_open() {   # la COUCHE DE L ETAT rend-il un plan ouvert ? (sinon : termine, ou rien)
  # LES MARQUEURS REELS SONT CEUX QUE LES BRIQUES DISENT : 'no open plan' (celui que la couche du
  # plan rend quand il n'y a pas de plan), 'AUCUN PLAN OUVERT' (celui que la boucle pose quand
  # second.sh est absent) et 'the plan could not be obtained' (ce que second.sh DIT quand la
  # couche casse : jq absent, engine absent, engine 122 muet). Ce dernier etait cherche en
  # francais ('pas pu etre obtenu'), que PERSONNE n'emet : la garde etait morte. Les trois sont
  # exerces par les verdicts B2b/B2c/B2d du banc, sur les mots REELS des briques.
  printf '%s' "$PLAN_TXT" | grep -qi 'aucun plan ouvert' && return 1
  printf '%s' "$PLAN_TXT" | grep -qi 'no open plan' && return 1
  printf '%s' "$PLAN_TXT" | grep -qi 'could not be obtained' && return 1
  printf '%s' "$PLAN_TXT" | grep -q . || return 1
  return 0
}

TURN=0
NO_TOOL=0
ANSWERED=0
REPLY=''
LOADED=0
TOKENS_TOTAL=0
TOKENS_SPOKE=0
CALLS_TOTAL=0
CALLS_SPOKE=0
T0=$(date +%s)
SECONDS_SPOKE=0

while [ "$TURNS_MAX" -eq 0 ] || [ "$TURN" -lt "$TURNS_MAX" ]; do
  TURN=$((TURN + 1))
  STATE="L STATE DE LA TASK - ce que les tools ont fait, rien d autre
  lus    : $(tr '\n' ' ' < "$T/read_log")
  ecrits : $(tr '\n' ' ' < "$T/written")
  tools : $((TURN - 1))"
  FACTS=$(FACTS)
  PLAN_TXT=$(read_second)
  # LA PORTEE DE CE TOUR, REBATIE ICI : le skill actif, ses tools, le verrou, le palier courant,
  # et la part classee (le reranker). Elle est FRAICHE a chaque tour, jamais figee au lancement.
  scope_build
  # LE TOUR VENU DE LA VOIX S OUVRE PAR UN MOT. La consigne n est posee QUE sur ces tours-la :
  # un tour venu du texte reste muet, et ne paie pas un appel de modele de plus.
  VOICE_TXT=''
  if [ "$LA_VOICE" = 1 ]; then
    VOICE_TXT='CE TOUR VIENT DE LA VOIX : L HUMAIN ATTEND DE T ENTENDRE TOUT DE SUITE. Ta PREMIERE action est talk, avec UNE seule phrase courte (moins de 120 signes) qui dit que tu as entendu et que tu y vas. Aucun autre tool avant ce talk. Ensuite tu travailles, et tu nommes talk chaque fois que tu as quelque chose a dire. Aucun texte libre : tout passe par un tool.'
  fi

  MESSAGES=$(build_messages) || die "the messages could not be built"
  PAYLOAD=$(jq -cn --arg model "$MODEL" --argjson tools "$TOOLS" --argjson max "$MAX_TOKENS" \
    --arg choix "$TOOL_CHOICE" --argjson messages "$MESSAGES" \
    '{model:$model, tools:$tools, tool_choice:$choix, max_tokens:$max, stream:false, messages:$messages}') \
    || die "the call could not be built"

  # UN ECHEC DE TRANSPORT N'EST PAS UNE REPONSE (B12) : le meme appel est repose UNE fois, tout
  # de suite. Un refus, lui, EST une reponse : il ne se rejoue pas, et la boucle le dit tel quel.
  REP=$(call "$PAYLOAD")
  CRC=$?
  if [ "$CRC" -ne 0 ]; then
    CURL_WHY=$(head -n 1 "$T/curl.err" 2>/dev/null | tr '\n\t' '  ' | cut -c1-200)
    log_to_stderr "$(ts)  turn $TURN  echec de transport (curl $CRC : $CURL_WHY) : le meme appel est repose UNE fois"
    REP=$(call "$PAYLOAD")
    CRC=$?
  fi
  if [ "$CRC" -ne 0 ]; then
    # LA PANNE DIT POURQUOI, ET ELLE LAISSE SA RAISON (B7, B10) : le code de curl et la
    # premiere ligne de sa raison entrent dans la phrase, et le fichier de curl est
    # RECOPIE dans work/ avant que le dossier temporaire ne parte. Un echec de transport
    # n'est plus interchangeable avec un autre : le journal porte de quoi le prouver.
    CURL_WHY=$(head -n 1 "$T/curl.err" 2>/dev/null | tr '\n\t' '  ' | cut -c1-200)
    cp "$T/curl.err" "$ROOT/work/curl.err" 2>/dev/null || :
    die "the engine did not answer (curl $CRC : $CURL_WHY) : network, or timeout"
  fi

  ERR=$(printf '%s' "$REP" | jq -r '.error.message // empty' 2>/dev/null || true)
  [ -z "$ERR" ] || die "the engine refused : $ERR"
  END=$(printf '%s' "$REP" | jq -r '.choices[0].finish_reason // ""' 2>/dev/null || true)
  MSG=$(printf '%s' "$REP" | jq -c '.choices[0].message // empty' 2>/dev/null || true)
  # ollama-cloud repond load tant que le modele n est pas pret : ce n est PAS un tour.
  if [ "$END" = "load" ]; then
    LOADED=$((LOADED + 1))
    [ "$LOADED" -le 8 ] || die "the engine did not finish loading after 8 attempts : $MODEL"
    printf 'loop: the engine is loading its model - same question asked again (attempt %s)\n' "$LOADED" >&2
    TURN=$((TURN - 1))
    continue
  fi
  [ -n "$MSG" ] && [ "$MSG" != 'null' ] || die "the engine reply carries no message"

  USAGE_TOKENS=$(printf '%s' "$REP" | jq -r '.usage.total_tokens // 0' 2>/dev/null || true)
  case "${USAGE_TOKENS:-}" in ''|*[!0-9]*) USAGE_TOKENS=0 ;; esac
  TOKENS_TOTAL=$((TOKENS_TOTAL + USAGE_TOKENS))

  NTC=$(printf '%s' "$MSG" | jq -r '(.tool_calls // []) | length')
  CONTENT=$(printf '%s' "$MSG" | jq -r '.content // ""')

  # PAS DE TOOL : le texte libre n est pas une reply. La PAROLE a son tool (talk) : on le dit,
  # et le tour continue - la borne de securite, elle, reste au-dessus.
  if [ "$NTC" = "0" ]; then
    NO_TOOL=$((NO_TOOL + 1))
    log_to_stderr "$(ts)  turn $TURN  sans tool ($NO_TOOL) - texte du modele : $(printf '%s' "$CONTENT" | tr '\n\t' '  ' | cut -c1-160)"
    hist_apply '. + [{role:"system",content:"Tu as repondu SANS call de tool : un texte libre n est PAS une reply. Pour PARLER, nomme talk. Pour finir, nomme answer - si le plan est termine. Sinon, nomme le tool qui continue."}]'
    continue
  fi

  # L HISTORIQUE rejoue l appel TEL QUEL, ses identifiants compris. Sans identifiant (Ollama
  # Cloud n en pose pas), la boucle en POSE un, et le message tool porte le meme.
  TCS=$(printf '%s' "$MSG" | jq -c --arg turn "$TURN" \
    '[.tool_calls | to_entries[] | .value + {id: (.value.id // ("call_la_" + $turn + "_" + (.key | tostring)))}]')
  AM=$(jq -cn --argjson tcs "$TCS" --arg c "$CONTENT" '{role:"assistant", content:$c, tool_calls:$tcs}')
  hist_apply --argjson m "$AM" '. + [$m]'

  I=0
  while [ "$I" -lt "$NTC" ]; do
    TC=$(printf '%s' "$TCS" | jq -c ".[$I]")
    ID=$(printf '%s' "$TC" | jq -r '.id')
    RAW=$(printf '%s' "$TC" | jq -r '.function.arguments // ""')
    I=$((I + 1))
    CALLS_TOTAL=$((CALLS_TOTAL + 1))
    if [ "$TRACE" = 1 ]; then
      log_to_stderr "$(ts)  turn $TURN  tool_call BRUT : $(printf '%s' "$TC" | jq -c '{id,function}')"
    fi

    # les arguments : un objet {g, a}. Illisible, le refus voyage comme les autres.
    G=$(printf '%s' "$RAW" | jq -r '.g // empty' 2>/dev/null || true)
    AJ=$(printf '%s' "$RAW" | jq -c 'if (.a|type)=="array" then [.a[]|tostring] elif (.a|type)=="string" then [.a] elif .a==null then [] else [] end' 2>/dev/null || true)
    if [ -z "$G" ] || [ -z "$AJ" ]; then
      LINE_=$(jq -cn --arg t "$(ts)" '{status:"refused",tool:"la",
        line:($t+"  la  ->  refuse : arguments illisibles"),
        result:"refus : ton appel n est pas un objet {g, a} en JSON valide. g est le NUMERO du tool ; a est la liste de ses arguments. Verifie les guillemets et rappelle le tool.",
        ts:$t}')
      log_to_stderr "$(ts)  turn $TURN  la  ->  arguments illisibles (renvoye au modele)"
      RESULT_TEXT=$(result_of "$LINE_")
      hist_apply --arg id "$ID" --arg c "$RESULT_TEXT" '. + [{role:"tool",tool_call_id:$id,content:$c}]'
      continue
    fi
    case "$G" in *[!0-9]*) G='' ;; esac
    if [ -z "$G" ]; then
      LINE_=$(refuse_loop "g doit etre un NUMERO de la table (recu : autre chose)")
      log_to_stderr "$(ts)  turn $TURN  la  ->  g n est pas un numero (renvoye au modele)"
      RESULT_TEXT=$(result_of "$LINE_")
      hist_apply --arg id "$ID" --arg c "$RESULT_TEXT" '. + [{role:"tool",tool_call_id:$id,content:$c}]'
      continue
    fi

    # piEGE : dash echo INTERPRETE \n dans l argument et casserait le JSON. printf, jamais echo.
    printf '%s\n' "$AJ" > "$T/a.json"
    NA=$(jq 'length' "$T/a.json" 2>/dev/null || true)
    case "${NA:-}" in ''|*[!0-9]*) NA=0 ;; esac
    BLOCK=$(block_of_id "$G" 2>/dev/null || true)
    TN=$(printf '%s\n' "$BLOCK" | sed -n 's/^    tool:[[:space:]]*//p' | head -n 1)
    FA=$(printf '%s\n' "$BLOCK" | sed -n 's/^    family:[[:space:]]*//p' | head -n 1)
    # L ACTION demandee : le premier argument. Elle ne compte que pour les tools a
    # categorie permanente par action (skill_manage:view_skill, skill_manage:load_skill).
    ACT=$(printf '%s' "$AJ" | jq -r '.[0] // ""')

    if [ -n "$BLOCK" ] && ! in_scope "$TN" "$FA" "$ACT"; then
      # le perimetre ferme : un tool hors de la liste -> refuse ICI, dans la meme forme
      LINE_=$(refuse_loop "$TN ($G) n est pas dans le perimetre de ce turn : nomme un tool de la liste des tools atteignables")
    else
      # LA LOI DU DECOUPAGE : autant d arguments que la ligne en declare HORS stdin
      if [ -n "$BLOCK" ]; then
        ARGC=$(count_non_stdin "$BLOCK")
        [ "$ARGC" -gt "$NA" ] && ARGC=$NA
      else
        ARGC=0
      fi
      exec_engine "$G" "$ARGC" "$T/a.json"
      LINE_=$(cat "$T/engine.out")
      [ -n "$LINE_" ] || LINE_=$(refuse_loop "le engine n a rien render")
    fi

    # le journal : UNE ligne, horodatee, avec la ligne du engine
    MSG_TS=$(printf '%s' "$LINE_" | jq -r '.ts // empty' 2>/dev/null || true)
    TOOL_NAME=$(printf '%s' "$LINE_" | jq -r '.tool // "?"' 2>/dev/null || true)
    MSG_STATUS=$(printf '%s' "$LINE_" | jq -r '.status // "?"' 2>/dev/null || true)
    # L ETAT DE L ENTREE S ARME ICI, SUR LE TOOL APPELE. Le perimetre a deja garanti qu il etait
    # atteignable : hors perimetre, le nom rendu est `la`, jamais celui du tool. Peu importe le
    # SUCCES : c est le GESTE qui compte (un load_doc qui refuse faute de doc arme quand meme
    # DOC_READ - c est le geste, provisoire, qui fait foi ; on precisera la doc plus tard).
    case "$TOOL_NAME" in
      load_doc)                                                            DOC_READ=1 ;;
      toolset)                                                             TOOLSET_ARMED=1 ;;
      start_plan|load_plan|advance_plan|revise_plan|close_plan|abort_plan) PLAN_DONE=1 ;;
    esac
    MSG_LINE=$(printf '%s' "$LINE_" | jq -r '.line // .result // ""' 2>/dev/null || true)
    log_to_stderr "${MSG_TS:-$(ts)}  turn $TURN  la(g=$G, a=$AJ)  ->  $MSG_LINE"
    if [ -n "$JOURNAL" ]; then
      jq -cn --arg t "$TURN" --arg ts "${MSG_TS:-$(ts)}" --argjson g "$G" --argjson a "$AJ" \
        --argjson tc "$TC" --argjson engine "$LINE_" \
        '{turn:($t|tonumber),ts:$ts,la:{g:$g,a:$a},tool_call:$tc,engine:$engine}' \
        >> "$JOURNAL" 2>/dev/null || :
    fi

    # l etat : des chemins, rien d autre
    case "$TOOL_NAME" in
      read_file|list_dir) P0=$(printf '%s' "$AJ" | jq -r '.[0] // empty'); [ -n "$P0" ] && printf '%s\n' "$P0" >> "$T/read_log" ;;
      write_file)         P0=$(printf '%s' "$AJ" | jq -r '.[0] // empty'); [ -n "$P0" ] && printf '%s\n' "$P0" >> "$T/written" ;;
    esac
    # LE COMPTEUR PORTE LE MOT, QUAND LE TOOL EST LA PAROLE. Deux fois le MEME mot est une
    # boucle ; deux mots DIFFERENTS sont une conversation, et le tour doit pouvoir parler
    # plusieurs fois. La cible du tool talk ne dit rien (elle vaut toujours "text").
    if [ "$TOOL_NAME" = talk ]; then
      printf '%s %s\n' "$TOOL_NAME" "$(result_of "$LINE_" | tr '\n\t' '  ' | cut -c1-60)" >> "$T/counter"
    else
      printf '%s %s\n' "$TOOL_NAME" "$(printf '%s' "$AJ" | jq -r '.[0] // ""')" >> "$T/counter"
    fi

    # [11] LE RETOUR : au modele, LE RESULT (ou le refus nomme), jamais l enveloppe.
    RESULT_TEXT=$(result_of "$LINE_")
    [ -n "$RESULT_TEXT" ] || RESULT_TEXT="le tool n a rien render : $TOOL_NAME"
    hist_apply --arg id "$ID" --arg c "$RESULT_TEXT" '. + [{role:"tool",tool_call_id:$id,content:$c}]'

    # [8] TALK DIT ET NE FERME PAS : la parole passe sur le CANAL HUMAIN (la sortie d erreur),
    # et le tour CONTINUE - c est ce qui permet au modele de PARLER avant la fin de son travail.
    if [ "$MSG_STATUS" = "ok" ] && [ "$TOOL_NAME" = "talk" ]; then
      printf '%s\n' "$(result_of "$LINE_")" >&2
      log_to_stderr "$(ts)  turn $TURN  talk : la parole est passee au canal humain, le turn continue"
    fi
    # ANSWER FERME LE TOUR QUAND LE PLAN EST TERMINE. Plan ouvert : la reponse part au canal
    # humain (l humain la voit), et le tour CONTINUE - sinon le plan resterait a moitie fait.
    if [ "$MSG_STATUS" = "ok" ] && [ "$TOOL_NAME" = "answer" ]; then
      REPLY=$(result_of "$LINE_")
      if plan_open; then
        printf '%s\n' "$REPLY" >&2
        log_to_stderr "$(ts)  turn $TURN  answer PASSE et le plan n est pas termine : la reponse part au canal humain, le turn continue"
        SAID=$(printf '%s' "$REPLY" | tr '\n\t' '  ' | cut -c1-200)
        hist_apply --arg d "$SAID" '. + [{role:"system",content:("Ta reponse est passee a l humain, et le turn CONTINUE : le plan n est pas termine. Nomme le tool qui finit l etape en cours, ou close_plan si les etapes sont faites. (tu as dit : "+$d+")")}]'
      else
        ANSWERED=1
        break
      fi
    fi
    # ASK ARRETE LE TOUR : il rend la main a l humain, et le tour attend sa reponse.
    if [ "$MSG_STATUS" = "ok" ] && [ "$TOOL_NAME" = "ask" ]; then
      REPLY=$(result_of "$LINE_")
      ANSWERED=1
      log_to_stderr "$(ts)  turn $TURN  ask : le turn s arrete et attend l humain"
      break
    fi
    if [ "$TOOL_NAME" = "answer" ] || [ "$TOOL_NAME" = "ask" ]; then
      log_to_stderr "$(ts)  turn $TURN  $TOOL_NAME a ete REFUSE : renvoye au modele, le turn ne se ferme pas"
    fi
    db_insert
  done
  [ "$ANSWERED" = 1 ] && break

  # LES BORNES - elles se DISENT, elles ne coupent pas
  DUPLICATE=$(sort "$T/counter" | uniq -d | head -n 1)
  if [ -n "$DUPLICATE" ]; then
    log_to_stderr "$(ts)  turn $TURN  CAP anti-boucle : le meme tool sur la meme cible est revenu ($DUPLICATE)"
    hist_apply --arg d "$DUPLICATE" '. + [{role:"system",content:("BORNE : tu as deja fait ce tool sur cette cible, sans rien changer : "+$d+". Change de tool, ou nomme answer.")}]'
  fi

  # LA BORNE DE JETONS - elle aussi se DIT d abord, puis coupe au tour suivant. Une task ne paie
  # pas sans fin : le premier depassement AVERTIT le modele, le second ARRETE la task.
  if [ "$TOKENS_MAX" -gt 0 ] && [ "$TOKENS_TOTAL" -ge "$TOKENS_MAX" ]; then
    if [ "$TOKENS_SPOKE" = 0 ]; then
      TOKENS_SPOKE=1
      log_to_stderr "$(ts)  turn $TURN  CAP de jetons : $TOKENS_TOTAL/$TOKENS_MAX - le modele est averti de conclure"
      hist_apply --arg t "$TOKENS_TOTAL" --arg m "$TOKENS_MAX" '. + [{role:"system",content:("BORNE DE JETONS : tu as consomme "+$t+" jetons sur les "+$m+" de cette task. Conclus MAINTENANT par answer (ou ask, si tu attends l humain) : plus aucun autre tool.")}]'
    else
      log_to_stderr "$(ts)  turn $TURN  CAP de jetons atteint : $TOKENS_TOTAL/$TOKENS_MAX - la task s arrete"
      break
    fi
  fi

  # LA BORNE D APPELS - le nombre TOTAL d appels d outil de la task. Meme style : elle se DIT,
  # puis elle coupe. Elle borne le TOUR ENTIER (talk compris), PAS talk en particulier.
  if [ "$CALLS_MAX" -gt 0 ] && [ "$CALLS_TOTAL" -ge "$CALLS_MAX" ]; then
    if [ "$CALLS_SPOKE" = 0 ]; then
      CALLS_SPOKE=1
      log_to_stderr "$(ts)  turn $TURN  CAP d appels : $CALLS_TOTAL/$CALLS_MAX - le modele est averti de conclure"
      hist_apply --arg t "$CALLS_TOTAL" --arg m "$CALLS_MAX" '. + [{role:"system",content:("BORNE D APPELS : tu as fait "+$t+" appels d outil sur les "+$m+" de cette task. Conclus MAINTENANT par answer (ou ask) : plus aucun autre tool.")}]'
    else
      log_to_stderr "$(ts)  turn $TURN  CAP d appels atteint : $CALLS_TOTAL/$CALLS_MAX - la task s arrete"
      break
    fi
  fi

  # LA BORNE DE TEMPS - le temps mural de la TASK, en secondes. Meme style : elle se DIT d abord,
  # puis elle coupe. Elle borne la duree de la task ENTIERE (pas un seul appel, ca c est TIMEOUT).
  SECONDS=$(( $(date +%s) - T0 ))
  if [ "$SECONDS_MAX" -gt 0 ] && [ "$SECONDS" -ge "$SECONDS_MAX" ]; then
    if [ "$SECONDS_SPOKE" = 0 ]; then
      SECONDS_SPOKE=1
      log_to_stderr "$(ts)  turn $TURN  CAP de temps : ${SECONDS}s/$SECONDS_MAX - le modele est averti de conclure"
      hist_apply --arg t "$SECONDS" --arg m "$SECONDS_MAX" '. + [{role:"system",content:("BORNE DE TEMPS : cette task dure depuis "+$t+" secondes sur les "+$m+" allouees. Conclus MAINTENANT par answer (ou ask) : plus aucun autre tool.")}]'
    else
      log_to_stderr "$(ts)  turn $TURN  CAP de temps atteint : ${SECONDS}s/$SECONDS_MAX - la task s arrete"
      break
    fi
  fi
done

db_insert

# [11] LE SIGNAL A L'HUMAIN, EN FIN DE TACHE : signal_task.sh ne fait que LIRE ce qui est deja
# ecrit (le registre sessions.db) et rend UNE LIGNE ; il n'ecrit AUCUN fichier. Le tour ne
# l attend JAMAIS : il court en arriere-plan, son journal va dans work/signal_task.log.
signal_task() {
  [ -x "$PROCS/signal_task.sh" ] || return 0
  ( printf '{}' | nohup "$PROCS/signal_task.sh" >>"$ROOT/work/signal_task.log" 2>&1 & ) >/dev/null 2>&1
}

if [ "$ANSWERED" != 1 ]; then
  signal_task
  log_to_stderr "$(ts)  CAP de securite : une borne atteinte sans reply (tours $TURN/$TURNS_MAX, jetons $TOKENS_TOTAL/$TOKENS_MAX, appels $CALLS_TOTAL/$CALLS_MAX, $(( $(date +%s) - T0 ))s/$SECONDS_MAX)"
  printf '(the task stopped without a reply : a safety bound is reached)\n'
  exit 0
fi

# [12] LE COMPACTAGE DE L ECHANGE, EN ARRIERE-PLAN, UNE FOIS LA REPLY RENDUE.
# Pose DEVANT le tour, il ajouterait sa latence a chaque tour : ici il court APRES la reply,
# et il pose l entree horodatee de config/sessions.yaml (le modele local, sur le CPU). Le tour
# ne l attend JAMAIS ; son journal va dans work/session_note.log, jamais dans le JSONL des tools.
if [ -n "$REPLY" ] && [ -x "$PROCS/session_note.sh" ]; then
  ( nohup "$PROCS/session_note.sh" "$REQUEST" "$REPLY" >>"$ROOT/work/session_note.log" 2>&1 & ) >/dev/null 2>&1
fi
signal_task

printf '%s\n' "$REPLY"
