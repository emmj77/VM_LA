#!/bin/sh
# engine.sh - LE ENGINE DE LA (config/engine/engine.sh). Le SEUL proc : ce qui remplace les
# procs disparus, c'est une TABLE et un engine.
#
# CE QU'IL FAIT, DANS CET ORDRE, POUR UN TOOL DEMANDE
#   1 il LIT LA TABLE   config/la_tools.yaml, la ligne qui porte l'ID demande
#   2 il VALIDE         l'arite, le type de chaque argument, la liste fermee
#   3 il RESOUT         le chemin RELATIF selon la FAMILLE de la ligne. READ -> sous le
#                       ROOT - WRITE -> sous $W. MANAGE ne valide que la FORME, sa
#                       COMMANDE nomme son registre - REPLY ne porte aucun chemin.
#   4 il EXECUTE        la commande de la ligne, dans dash -c
#   5 il REND           LA FORME UNIQUE, et c'est LUI qui l'ecrit, jamais la commande
#
# L'INTERFACE
#   engine.sh <id> [argument...]
#   les arguments dans l'ORDRE DECLARE par la ligne. Ceux qui portent stdin: true
#   (LE TEXTE LIBRE) ne sont PAS sur la ligne de commande : ils arrivent sur l'ENTREE
#   STANDARD du engine, et le engine les tend a l'entree standard de la commande.
#
# LA TABLE - une cle racine tools:, une entree par tool, et rien d'autre dans le fichier :
#   id - tool - family - description - args - command
#     args     name - type (path | enum | int | bool | text) - values (enum) - stdin
#     command  nue (cat) - entre quotes simples ('...') - ou un BLOC (|) dont le corps
#              est indente de six espaces
#   L'ID N'EST PAS UNE POSITION : un tool porte son id, l'ajouter ne renumerote rien.
#
# CE QUE LE ENGINE POSE, POUR LA COMMANDE (les lignes de la table s'en servent deja) :
#   ROOT       la racine du projet                      LA_CONFIG  le chemin de la TABLE
#   SKROOT     le dossier du SKILL ACTIF                W          l'espace de travail du skill
#   (le plan vit dans la section PLAN: du SKILL ACTIF, plus dans un dossier)
# LE SKILL ACTIF se lit a UN SEUL endroit : <projet>/skills/la/skill.yaml, section
# PERIMETER:. C'EST LA, et jamais ailleurs, que le engine lit OU un fichier s'ecrit. Le
# modele ne donne JAMAIS un chemin absolu : il donne un chemin RELATIF, et le engine
# le resout. Le trou substitue dans la commande porte ce RELATIF, deja valide.
#
# LA VALIDATION PASSE AVANT TOUT EFFET : rien n'est execute si une seule chose cloche.
#   ARITE   c'est un PLAFOND. Plus d'arguments que la ligne n'en declare : refus nomme.
#           Moins : ce qui manque en queue prend la VALEUR VIDE, et c'est la VALIDATION
#           qui tranche - un enum qui n'admet pas la valeur vide est refuse ; un int, un
#           path, un text vide passent, et c'est la COMMANDE qui juge (la table porte ses
#           defauts). C'est ce qui laisse `engine.sh 126 remove_skill <name>` atteindre
#           sa commande sans nommer les six arguments qui ne la regardent pas.
#   TYPE    enum  la valeur est dans values, sinon refus EN LA NOMMANT avec la liste
#           int   des chiffres, ou vide       bool  true ou false
#           path  voir CHEMIN               text  toute valeur
#           un argument marque stdin: true ne passe JAMAIS en argument.
#   CHEMIN  RELATIF (l'absolu et le ~ sont refuses), sans .., sans caractere de coquille
#           (guillemet, dollar, accent grave, antislash, motif * ? [ ]) et sans caractere
#           de controle. Puis RESOLU : ce qui sort du registre est refuse.
#   FAMILLE elle dit la NATURE, et donc ou un chemin a le droit d'etre. Le registre vient
#           du SKILL ACTIF (paths.root, paths.work) et JAMAIS d'une colonne de la table :
#           READ    le chemin se resout sous le ROOT, et n'en sort pas ;
#           WRITE   sous $W, le registre de travail du skill actif ;
#           MANAGE  la FORME seule (relatif, sans .., sans coquille) : la COMMANDE
#                   nomme son registre ($ROOT/memory, skills/, config/) ;
#           REPLY   aucun chemin du tout. Une famille hors de ces quatre : refus nomme.
#
# LA COMMANDE porte des trous {{nom}}. Le engine remplace les trous qui portent le NOM d'un
# argument declare hors stdin par sa valeur DEJA VALIDEE ; tout autre {{...}} RESTE TEL QUEL,
# et la table s'en sert (108 y garde les trous du moule memory-entry.md : {{date}}, {{text}}).
# Le TEXTE LIBRE (stdin: true) ne monte JAMAIS dans la commande : il entre par l'entree
# standard. Et un text qui entre dans la commande est REFUSE s'il porte de quoi casser le
# guillemet de la table (guillemet, dollar, accent grave, antislash, caractere de controle) :
# aucun argument n'est du texte interprete. Puis la commande part dans dash -c.
#
# LES CODES DE LA COMMANDE, ET C'EST LA LOI DU RETOUR
#   0      status ok            result = sa sortie standard
#   3      status approval   ce qu'elle demande est sur sa SORTIE STANDARD, et ce
#                               texte part vers l'humain
#   autre  status refused         ce qu'elle a dit sur sa SORTIE D'ERREUR est ce que l'humain
#                               lira ; un refus n'est JAMAIS muet
#
# LA FORME DU RETOUR, une seule, ecrite par le engine sur SA SORTIE STANDARD, en JSON sur
# une ligne - et RIEN d'autre sur ce canal :
#   {"status":"ok|refused|approval","tool":"<nom>","line":"<pour l'humain>",
#    "result":"<pour le LLM>","ts":"<date -u +%Y-%m-%dT%H:%M:%SZ>"}
# Sur un refus le engine sort en 0 : c'est le status qui juge, pas le code.
#
# sh (dash) + jq + coreutils : rien d'autre. Ni bash, ni python3. AUCUN accent grave dans
# ce fichier, meme dans un commentaire : dash ouvre la ou on ne l'attend pas.

LC_ALL=C
export LC_ALL

# --- ce qui ne se devine pas : le projet, la table, le skill
SEVERE=$(printf '\140')
HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
ROOT=${LA_ROOT:-$(dirname "$CONF_DIR")}
TABLE=${LA_CONFIG:-$CONF_DIR/la_tools.yaml}
# LA SKILL ACTIVE — la resolution vit dans la bibliotheque commune (config/engine/lib.sh).
[ -f "$HERE/lib.sh" ] || { printf 'engine: the common library is missing (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"
active_skill

TS=$(ts)
TOOL=unknown
ARGS_LINE=
NAMES_STDIN=' '
NAMES_TEXT=' '
BASE=
STDIN_FREE=no
TMPD=

# --- LA BORNE ET LE DELAI : les plafonds du resultat, et le plafond de TEMPS ----
# TOUT resultat qui entre dans la reponse JSON est borne ici. Un resultat qui tient
# sous les DEUX plafonds passe TEL QUEL, et ne cree AUCUN fichier. Au-dela : une TETE
# et une QUEUE (la fin d'une sortie porte souvent la reponse), coupees sur un
# CARACTERE ENTIER (jamais un octet orphelin : la coupe passe par iconv, qui ecarte
# la sequence incomplete), et la sortie COMPLETE part sous $W, horodatee et parlante ;
# le resultat borne NOMME ce fichier, ses octets et ses lignes, et dit qu'il est tronque.
# LA_CAP_BYTES / LA_CAP_LINES / LA_TIMEOUT se posent par l'environnement ; les
# VALEURS RETENUES : 4000 octets, 200 lignes, 600 s. Le delai du engine est une MARGE
# sur le plus long timeout interne de la table (300 s, comfyui) : c'est LUI qui coupe
# un tool qui pend. Un tool qui demande plus long se declare dans SA ligne, pas ici.
CAP_BYTES=${LA_CAP_BYTES:-4000}
CAP_LINES=${LA_CAP_LINES:-200}
TIMEOUT=${LA_TIMEOUT:-600}

command -v jq >/dev/null 2>&1 || {
  printf '{"status":"refused","tool":"unknown","line":"jq est absent de la machine","result":"refus : jq est absent, le engine n a pas pu ecrire la shape unique","ts":"%s"}\n' "$(ts)"
  exit 0
}

# --- LA FORME UNIQUE : le engine est le SEUL a ecrire sur la sortie standard.
one_line() {   # $1 = un message sur plusieurs lignes -> UNE ligne pour l'humain
  printf '%s' "$1" | tr '\n\t' '  ' | jq -Rr 'if length > 400 then .[0:400] + " ..." else . end' 2>/dev/null
}
shape() {       # $1 status - $2 tool - $3 line - $4 result
  jq -cn --arg st "$1" --arg t "$2" --arg l "$3" --arg r "$4" --arg ts "$TS" \
    '{status:$st,tool:$t,line:$l,result:$r,ts:$ts}' 2>/dev/null \
  || printf '{"status":"refused","tool":"engine","line":"la shape unique n a pas pu etre montee","result":"refus : le engine n a pas pu ecrire la shape unique","ts":"%s"}\n' "$TS"
  exit 0
}
file_shape() {   # la meme forme, le result lu TEL QUEL dans un fichier (octets exacts)
  if jq -cn --arg st "$1" --arg t "$2" --arg l "$3" --arg ts "$TS" --rawfile r "$4" \
       '{status:$st,tool:$t,line:$l,result:$r,ts:$ts}' 2>/dev/null; then
    exit 0
  fi
  shape "$1" "$2" "$3" ""
}
refuse_tool() {       # $1 = le detail ; le refus est NOMME, il n'est jamais muet
  shape refused "$TOOL" "$(one_line "refus : $1")" "refus : $1"
}
refuse_preformed() {   # $1 = le message deja forme (celui de la commande, tel quel)
  shape refused "$TOOL" "$(one_line "$1")" "$1"
}

# --- LA BORNE : le seul endroit ou un resultat est taille ----------------------
# compte : le nombre d'OCTETS et de LIGNES reelles d'un fichier (une derniere ligne
#          sans saut compte pour une ligne, comme wc -l l'oublie).
# borner : rend 1 si le fichier tient sous les DEUX plafonds (il n'est alors NI
#          modifie NI recopie) ; rend 0 en ECRIVANT sur sa sortie standard le
#          resultat borne - tete, queue, chemin du fichier complet, octets, lignes.
count() {   # $1 = fichier ; ecrit "<octets> <lignes>" sur la sortie standard
  O=$(wc -c < "$1" 2>/dev/null | tr -d ' ')
  L=$(wc -l < "$1" 2>/dev/null | tr -d ' ')
  case "$O" in ''|*[!0-9]*) O=0 ;; esac
  case "$L" in ''|*[!0-9]*) L=0 ;; esac
  if [ -s "$1" ] && [ -n "$(tail -c 1 "$1" 2>/dev/null)" ]; then L=$((L + 1)); fi
  printf '%s %s' "$O" "$L"
}
bound_file() {   # $1 = fichier brut ; la coupe passe TOUJOURS par iconv
  F=$1
  set -- $(count "$F")
  O=$1
  L=$2
  if [ "$O" -le "$CAP_BYTES" ] && [ "$L" -le "$CAP_LINES" ]; then
    return 1
  fi
  # la place prise par les marqueurs du resultat borne, gardee hors des tete/queue
  FRAME=400
  CONTENT=$((CAP_BYTES - FRAME))
  [ "$CONTENT" -gt 200 ] || CONTENT=200
  HT=$((CONTENT * 3 / 5))
  QT=$((CONTENT - HT))
  # LA COUPE SUR UN CARACTERE ENTIER : iconv lit le morceau, ecarte la sequence
  # incomplete de tete ou de queue, et ne laisse que de l'UTF-8 valide. Si le
  # fichier n'est pas de l'UTF-8, la coupe reste sur l'octet (il n'y a pas de
  # caractere a respecter), et on le dit par le nom du fichier.
  if iconv -f UTF-8 -t UTF-8 "$F" >/dev/null 2>&1; then
    HEAD_PART=$(head -c "$HT" "$F" 2>/dev/null | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
    TAIL_PART=$(tail -c "$QT" "$F" 2>/dev/null | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
  else
    HEAD_PART=$(head -c "$HT" "$F" 2>/dev/null)
    TAIL_PART=$(tail -c "$QT" "$F" 2>/dev/null)
  fi
  # LA SORTIE COMPLETE sous $W, horodatee et parlante ; le chemin est dit RELATIF
  # au projet, pour que le tool de LECTURE (read_file) le reprenne tel quel.
  FILE_NAME="truncated-output-$(date -u +%Y%m%dT%H%M%SZ)-${TOOL}.txt"
  PATH="$W/$FILE_NAME"
  if ! cp "$F" "$PATH" 2>/dev/null; then PATH=; fi
  printf '[TRONQUE] la sortie brute fait %s octet(s) et %s ligne(s) ; les plafonds sont %s octet(s) et %s ligne(s).\n' "$O" "$L" "$CAP_BYTES" "$CAP_LINES"
  if [ -n "$PATH" ]; then
    REL=${PATH#"$ROOT"/}
    printf 'sortie complete (telle quelle) : %s (%s octet(s), %s ligne(s))\n' "$REL" "$O" "$L"
  else
    printf 'la sortie complete n a pas pu etre ecrite sous $W (%s)\n' "$W"
  fi
  printf -- '--- HEAD_PART (debut) ---\n%s\n--- TAIL_PART (fin) ---\n%s\n' "$HEAD_PART" "$TAIL_PART"
  printf '[TRONQUE] tete et queue seulement ; le reste est dans le fichier ci-dessus.\n'
  return 0
}

# --- [1] L'ID, ET LA LIGNE -----------------------------------------------------
ID=${1:-}
case "$ID" in
  ''|*[!0-9]*)
    refuse_tool "l'id est absent ou hors form (${1:-rien}) ; un id est un nombre, et c'est celui de la ligne de la table" ;;
esac
shift

[ -e "$TABLE" ] || refuse_tool "la table est introuvable ($TABLE)"
[ -f "$TABLE" ] || refuse_tool "la table n'est pas un fichier ($TABLE)"
[ -r "$TABLE" ] || refuse_tool "la table est illisible ($TABLE)"

BLOCK=$(table_block "$TABLE" "$ID")
[ -n "$BLOCK" ] || refuse_tool "l'id $ID n'est pas dans la table : aucune ligne ne porte cet id ($TABLE)"

TOOL=$(printf '%s\n' "$BLOCK" | sed -n 's/^    tool:[[:space:]]*//p' | head -n 1)
FAMILY=$(printf '%s\n' "$BLOCK" | sed -n 's/^    family:[[:space:]]*//p' | head -n 1)
[ -n "$TOOL" ] || refuse_tool "la ligne $ID est illisible : elle ne porte pas de champ tool"
case "$TOOL" in *[!a-z0-9_]*) refuse_tool "la ligne $ID porte un tool hors form ($TOOL)" ;; esac
case "$FAMILY" in
  READ|WRITE|MANAGE|REPLY) ;;
  *) refuse_tool "la ligne $ID ($TOOL) porte une family hors form (${FAMILY:-absente}) ; les familles sont READ, WRITE, MANAGE, REPLY" ;;
esac
CMD_COUNT=$(printf '%s\n' "$BLOCK" | grep -c '^    command:')
[ "$CMD_COUNT" = 1 ] || refuse_tool "la ligne $ID ($TOOL) est illisible : elle porte $CMD_COUNT champ(s) command"

# --- LE CHAMP enabled DE LA LIGNE : une ligne SANS enabled est ACTIVE -----------
# disable_tool ecrit `enabled: false` sur la ligne ; c'est ICI, et ici seulement, que
# ce champ devient un effet. Une ligne qui ne porte PAS enabled est active.
EBL=$(printf '%s\n' "$BLOCK" | sed -n 's/^    enabled:[[:space:]]*//p' | head -n 1)
case "$EBL" in
  ''|true) ;;
  false) refuse_tool "le tool $TOOL (ligne $ID) est desactive : sa ligne porte enabled: false, et le engine ne l'execute pas ; reactiver la ligne (table_manage, enable_tool) avant de l'call" ;;
  *)     refuse_tool "le champ enabled de la ligne $ID ($TOOL) est hors form (${EBL}) ; il porte true ou false" ;;
esac

# --- LA COMMANDE DE LA LIGNE : nue, entre quotes simples, ou en bloc | ----------
CMD_LINE=$(printf '%s\n' "$BLOCK" | grep '^    command:' | head -n 1)
case "$CMD_LINE" in
  '    command: |')
    CMD=$(printf '%s\n' "$BLOCK" | sed -n '/^    command: |$/,$p' | sed '1d' | sed -e 's/^      //')
    ;;
  '    command:'*)
    CMD=$(printf '%s\n' "$CMD_LINE" | sed -e 's/^    command:[[:space:]]*//')
    case "$CMD" in
      \'*\') CMD=$(printf '%s' "$CMD" | sed -e "s/^'//" -e "s/'\$//") ;;
    esac
    ;;
  *)
    refuse_tool "la ligne $ID ($TOOL) est illisible : le champ command n'a pas pu etre lu" ;;
esac
[ -n "$CMD" ] || refuse_tool "la ligne $ID ($TOOL) est illisible : sa commande est vide"

# --- LE SKILL ACTIF : c'est la, et nulle part ailleurs, qu'un fichier s'ecrit ----
[ -f "$SKILL" ] || refuse_tool "le SKILL ACTIF est introuvable ($SKILL) : le engine n'a pas ou lire les registres du skill actif"
# PERIMETER porte DEUX choses : workspace (les dossiers de travail) et type-file (les types
# acceptes). SPECS se derive du SKILL ACTIF lui-meme ; ROOT est la racine du PROJET.
SKW=$(sed -n '/^PERIMETER:/,/^[^[:space:]]/p' "$SKILL" | sed -n 's/^[[:space:]]*workspace:[[:space:]]*//p' | head -n 1)
value() {   # $1 = la valeur du skill ; la nettoie, et refuse ce qui sort du projet
  V=$(printf '%s' "$1" | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" -e 's:/*$::')
  [ -n "$V" ] || refuse_tool "le SKILL ACTIF ne porte pas PERIMETER.$2 ($SKILL)"
  case "$V" in *..*) refuse_tool "PERIMETER.$2 du SKILL ACTIF remonte ($V)" ;; esac
  case "$V" in
    /*) printf '%s' "$V" ;;
    *)  printf '%s' "$ROOT/$V" ;;
  esac
}
SKROOT=$(dirname "$SKILL")
W=$(value "$SKW" workspace)
SPEC="$SKROOT/spec.yaml"
# SPEC sert de variable de travail a la lecture des arguments : le CHEMIN du spec voyage
# sous un autre nom, sinon le premier argument de write_spec l ecrase.
SPEC_FILE="$SPEC"
# PROCS : le dossier DES BRIQUES (les scripts du engine). Un tool dont le corps vit dans une
# brique la nomme par la : la ligne de la table ne porte QUE la commande (loi 506).
PROCS=$HERE
# LE PLAN NE VIT PLUS DANS UN DOSSIER : il vit dans la section PLAN: du SKILL ACTIF, tenue par
# la brique plan.sh. P n est donc plus une portee de fichier, et elle ne s exporte plus.
export ROOT SKROOT W PROCS SKILL SPEC_FILE
LA_CONFIG=$TABLE
export LA_CONFIG

# --- LA FAMILLE : elle dit la NATURE, et donc le registre ou un chemin a le droit d'etre
#   READ   le chemin se resout sous le ROOT   WRITE  sous $W, le registre de travail
#   MANAGE la commande nomme son registre : BASE reste vide, et seul la FORME est jugee
#   REPLY  aucune ligne REPLY ne porte de chemin
BASE=
case "$FAMILY" in
  READ)         BASE=$ROOT ;;
  WRITE)        BASE=$W ;;
  MANAGE|REPLY) BASE= ;;
esac

# --- [2] ET [3] LES ARGUMENTS : l'arite, le type, le chemin --------------------
ABLOC=$(printf '%s\n' "$BLOCK" | sed -n '/^    args:/,/^    [a-z]/p' | sed '$d')
NA=$(printf '%s\n' "$ABLOC" | grep -c '^      - {')
NOT_STDIN=$(printf '%s\n' "$ABLOC" | sed -n 's/^      - {\(.*\)}[[:space:]]*$/\1/p' | grep -c 'stdin:[[:space:]]*true')
DECLARES=$((NA - NOT_STDIN))
GIVEN=$#
[ "$GIVEN" -le "$DECLARES" ] \
  || refuse_tool "l'arite de la ligne $ID ($TOOL) est depassee : $DECLARES argument(s) hors stdin, $GIVEN recu(s)"

MAP='{}'
i=0
while [ "$i" -lt "$NA" ]; do
  i=$((i + 1))
  ARG_LINE=$(printf '%s\n' "$ABLOC" | grep '^      - {' | sed -n "${i}p")
  SPEC=$(printf '%s' "$ARG_LINE" | sed -n 's/^      - {\(.*\)}[[:space:]]*$/\1/p')
  [ -n "$SPEC" ] \
    || refuse_tool "la ligne $ID ($TOOL) est illisible : la $i-e declaration d'argument ne se lit pas"

  VJ='null'
  case "$SPEC" in
    *'values:'*)
      VL=$(printf '%s' "$SPEC" | sed -n 's/.*values:[[:space:]]*\[\([^]]*\)\].*/\1/p')
      SPEC=$(printf '%s' "$SPEC" | sed 's/values:[[:space:]]*\[[^]]*\],\{0,1\}[[:space:]]*//')
      if [ -z "$VL" ]; then
        VJ='[]'
      else
        VJ=$(printf '%s\n' "$VL" | tr ',' '\n' \
             | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' \
             | jq -R . | jq -cs .)
      fi
      ;;
  esac

  ARG_NAME=$(printf '%s' "$SPEC" | sed -n 's/.*name:[[:space:]]*\([^,]*\).*/\1/p' | sed -e 's/[[:space:]]*$//')
  ARG_TYPE=$(printf '%s' "$SPEC" | sed -n 's/.*type:[[:space:]]*\([^,]*\).*/\1/p' | sed -e 's/[[:space:]]*$//')
  ARG_STDIN=$(printf '%s' "$SPEC" | sed -n 's/.*stdin:[[:space:]]*\([^,]*\).*/\1/p' | sed -e 's/[[:space:]]*$//')
  [ -n "$ARG_NAME" ] || refuse_tool "la ligne $ID ($TOOL) est illisible : une declaration d'argument ne porte pas de name"
  case "$ARG_NAME" in *[!A-Za-z0-9_]*) refuse_tool "la ligne $ID ($TOOL) porte un argument hors form ($ARG_NAME)" ;; esac
  case "$ARG_TYPE" in
    path|enum|int|bool|text) ;;
    *) refuse_tool "la ligne $ID ($TOOL) porte un type inconnu pour $ARG_NAME (${ARG_TYPE:-absent}) ; les types sont path, enum, int, bool, text" ;;
  esac
  case "$ARG_STDIN" in
    ''|true|false) ;;
    *) refuse_tool "la ligne $ID ($TOOL) porte un stdin hors form pour $ARG_NAME ($ARG_STDIN)" ;;
  esac

  if [ "$ARG_STDIN" = true ]; then
    case "$ARG_TYPE" in
      text) ;;
      *) refuse_tool "la ligne $ID ($TOOL) marque $ARG_NAME (type $ARG_TYPE) sur l'entree standard ; seul un text y entre" ;;
    esac
    NAMES_STDIN="$NAMES_STDIN$ARG_NAME "
    STDIN_FREE=yes
    continue
  fi

  if [ $# -gt 0 ]; then ARG_VALUE=$1; shift; else ARG_VALUE=; fi
  [ "$ARG_TYPE" = text ] && NAMES_TEXT="$NAMES_TEXT$ARG_NAME "

  case "$ARG_TYPE" in
    enum)
      LIST=$(printf '%s' "$VJ" | jq -r 'join(" | ")')
      [ "$VJ" != 'null' ] \
        || refuse_tool "la ligne $ID ($TOOL) declare $ARG_NAME en enum sans liste fermee (values)"
      printf '%s' "$VJ" | jq -e --arg v "$ARG_VALUE" 'index($v) != null' >/dev/null 2>&1 \
        || refuse_tool "$TOOL : ${ARG_VALUE:-une value vide} n'est pas dans la liste fermee de $ARG_NAME ; values : $LIST"
      ;;
    int)
      case "$ARG_VALUE" in *[!0-9]*) refuse_tool "$TOOL : $ARG_NAME attend des chiffres, ou rien pour prendre le defaut de la table (${ARG_VALUE:-absente})" ;; esac
      ;;
    bool)
      case "$ARG_VALUE" in true|false) ;; *) refuse_tool "$TOOL : $ARG_NAME attend true ou false (${ARG_VALUE:-absent})" ;; esac
      ;;
    text)
      ;;
    path)
      case "$ARG_VALUE" in
        /*) refuse_tool "$TOOL : $ARG_NAME est un chemin ABSOLU ($ARG_VALUE) ; un chemin est relatif, et le engine le resout" ;;
        \~*) refuse_tool "$TOOL : $ARG_NAME commence par ~ ($ARG_VALUE) ; un chemin est relatif, et le engine le resout" ;;
      esac
      case "$ARG_VALUE" in
        *..*) refuse_tool "$TOOL : $ARG_NAME remonte : un chemin ne porte jamais .. ($ARG_VALUE)" ;;
      esac
      case "$ARG_VALUE" in
        *'"'*)       refuse_tool "$TOOL : $ARG_NAME porte un guillemet ($ARG_VALUE)" ;;
        *\$*)        refuse_tool "$TOOL : $ARG_NAME porte un dollar ($ARG_VALUE)" ;;
        *"$SEVERE"*)  refuse_tool "$TOOL : $ARG_NAME porte un accent grave ($ARG_VALUE)" ;;
        *\\*|*'*'*|*'?'*|*'['*|*']'*)
                     refuse_tool "$TOOL : $ARG_NAME porte un motif, et un tool ne parcourt rien ($ARG_VALUE)" ;;
      esac
      if printf '%s' "$ARG_VALUE" | grep -q '[[:cntrl:]]'; then
        refuse_tool "$TOOL : $ARG_NAME porte un caractere de controle"
      fi
      if [ "$FAMILY" = REPLY ]; then
        refuse_tool "$TOOL : la famille REPLY ne porte aucun chemin, et $ARG_NAME en est un ($ARG_VALUE)"
      fi
      if [ -n "$BASE" ] && [ -n "$ARG_VALUE" ]; then
        BCAN=$(readlink -f -- "$BASE" 2>/dev/null)
        TCAN=$(readlink -f -- "$BASE/$ARG_VALUE" 2>/dev/null)
        if [ -n "$BCAN" ] && [ -n "$TCAN" ]; then
          case "$TCAN" in
            "$BCAN"|"$BCAN"/*) ;;
            *) refuse_tool "$TOOL : le chemin resolu sort du registre de la famille $FAMILY ($ARG_VALUE)" ;;
          esac
        fi
      fi
      ;;
  esac

  MAP=$(printf '%s' "$MAP" | jq -c --arg n "$ARG_NAME" --arg v "$ARG_VALUE" '. + {($n):$v}')
  ARGS_LINE="$ARGS_LINE $ARG_NAME=$ARG_VALUE"
done

[ $# -eq 0 ] || refuse_tool "l'arite de la ligne $ID ($TOOL) est depassee : $DECLARES argument(s) hors stdin, et il en reste $#"
ARGS_LINE=$(printf '%s' "$ARGS_LINE" | jq -Rr 'if length > 160 then .[0:160] + " ..." else . end' 2>/dev/null)

# --- [4] LE MONTAGE : les trous qui portent un argument declare, et EUX SEULS --
# Un trou qui porte le nom d'un argument declare hors stdin recoit sa valeur DEJA VALIDEE.
# Tout autre {{...}} RESTE TEL QUEL : la table s'en sert - 108 y garde les trous du moule
# memory-entry.md ({{date}}, {{text}}). Et le TEXTE LIBRE (stdin: true) ne monte JAMAIS
# dans la commande : il entre par l'entree standard.
REMAINING=$CMD
BODY=
while case "$REMAINING" in *'{{'*) true ;; *) false ;; esac; do
  BEFORE=${REMAINING%%'{{'*}
  AFTER=${REMAINING#*'{{'}
  NAME=${AFTER%%[!A-Za-z0-9_]*}
  HOLE='{{'"$NAME"'}}'
  OKAY=hole
  [ -n "$NAME" ] || OKAY=no
  case "$REMAINING" in *"$HOLE"*) ;; *) OKAY=no ;; esac
  if [ "$OKAY" = no ]; then
    BODY="$BODY$BEFORE{{"
    REMAINING=$AFTER
  else
    VALUE=$HOLE
    case "$NAMES_STDIN" in
      *" $NAME "*) ;;                                  # le texte libre : il reste un trou du moule
      *)
        if printf '%s' "$MAP" | jq -e --arg n "$NAME" 'has($n)' >/dev/null 2>&1; then
          VALUE=$(printf '%s' "$MAP" | jq -r --arg n "$NAME" '.[$n]')
          case "$NAMES_TEXT" in
            *" $NAME "*)
              case "$VALUE" in
                *'"'*)      refuse_preformed "refus : $TOOL : l'argument $NAME entre dans la commande et porte un guillemet ; un argument n'est jamais du texte interprete" ;;
                *'$'*)      refuse_preformed "refus : $TOOL : l'argument $NAME entre dans la commande et porte un dollar ; un argument n'est jamais du texte interprete" ;;
                *"$SEVERE"*) refuse_preformed "refus : $TOOL : l'argument $NAME entre dans la commande et porte un accent grave ; un argument n'est jamais du texte interprete" ;;
                *'\'*)      refuse_preformed "refus : $TOOL : l'argument $NAME entre dans la commande et porte un antislash ; un argument n'est jamais du texte interprete" ;;
              esac
              if printf '%s' "$VALUE" | grep -q '[[:cntrl:]]'; then
                refuse_preformed "refus : $TOOL : l'argument $NAME entre dans la commande et porte un caractere de controle"
              fi
              ;;
          esac
        fi
        ;;
    esac
    BODY="$BODY$BEFORE$VALUE"
    REMAINING=${REMAINING#*"$HOLE"}
  fi
done
BODY="$BODY$REMAINING"

# --- [5] L'EXECUTION : la commande, et son entree standard ---------------------
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/engine.XXXXXX" 2>/dev/null)
[ -n "$TMPD" ] && [ -d "$TMPD" ] || refuse_tool "le engine n'a pas pu ouvrir son espace de travail temporaire (${TMPDIR:-/tmp})"
cleanup_tmp_engine() { rm -f "$TMPD/out" "$TMPD/err" 2>/dev/null; rmdir "$TMPD" 2>/dev/null; }
trap 'cleanup_tmp_engine' EXIT INT TERM HUP

SH=$(command -v dash 2>/dev/null)
[ -n "$SH" ] || SH=$(command -v sh 2>/dev/null)
[ -n "$SH" ] || refuse_tool "aucun sh (dash) sur la machine"

# LE DELAI MAXIMAL : aucune ligne de la table ne pend la boucle. timeout couvre la
# commande ENTIERE (son propre timeout interne, s'il en a un, reste plus serre).
TIMEOUT_BIN=$(command -v timeout 2>/dev/null)
[ -n "$TIMEOUT_BIN" ] || refuse_tool "timeout (coreutils) est absent de la machine : le engine ne peut pas poser de delai maximal sur la commande"

if [ "$STDIN_FREE" = yes ]; then
  "$TIMEOUT_BIN" "$TIMEOUT" "$SH" -c "$BODY" > "$TMPD/out" 2> "$TMPD/err"
else
  "$TIMEOUT_BIN" "$TIMEOUT" "$SH" -c "$BODY" > "$TMPD/out" 2> "$TMPD/err" < /dev/null
fi
RC=$?

# --- [6] LA FORME : une seule, et c'est le engine qui l'ecrit ------------------
# TOUT resultat passe par LA BORNE avant d'entrer dans la forme : sous les plafonds
# il est rendu TEL QUEL (aucun fichier n'est cree) ; au-dela il est tronque et la
# sortie complete est ecrite sous $W, avec son chemin dans le resultat.
case "$RC" in
  0)
    LINE=$(jq -rn --rawfile r "$TMPD/out" --arg t "$TOOL" --arg a "$ARGS_LINE" '
      ($r | sub("[\n\t ]+$"; "")) as $x
      | (if ($x | length) == 0 then "fait, 0 octet sur la sortie"
         elif ($x | test("\n")) then (($x | length | tostring) + " octets, " + ((($x | split("\n")) | length) | tostring) + " ligne(s)")
         else $x end) as $res
      | ($t + (if $a == "" then "" else "  " + $a end) + "  ->  "
         + (if ($res | length) > 140 then ($res[0:140] + " ...") else $res end))')
    CAP_TXT=$(bound_file "$TMPD/out"); CAP_RC=$?
    if [ "$CAP_RC" -eq 0 ]; then
      shape ok "$TOOL" "$LINE" "$CAP_TXT"
    fi
    file_shape ok "$TOOL" "$LINE" "$TMPD/out"
    ;;
  3)
    R=$(cat "$TMPD/out" 2>/dev/null)
    [ -n "$R" ] || R="approbation requise par $TOOL, et sa commande n'a rien dit"
    printf '%s' "$R" > "$TMPD/app"
    CAP_TXT=$(bound_file "$TMPD/app"); CAP_RC=$?
    [ "$CAP_RC" -eq 0 ] && [ -n "$CAP_TXT" ] && R=$CAP_TXT
    shape approval "$TOOL" "$(one_line "$R")" "$R"
    ;;
  124)
    refuse_preformed "refus : la commande de $TOOL a depasse le delai maximal (${TIMEOUT} s) et a ete arretee ; aucune ligne ne pend la boucle"
    ;;
  *)
    E=$(cat "$TMPD/err" 2>/dev/null)
    O=$(cat "$TMPD/out" 2>/dev/null)
    M=$E
    [ -n "$M" ] || M=$O
    [ -n "$M" ] || M="refus : la commande de $TOOL a echoue (code $RC) sans rien say"
    printf '%s' "$M" > "$TMPD/ref"
    CAP_TXT=$(bound_file "$TMPD/ref"); CAP_RC=$?
    [ "$CAP_RC" -eq 0 ] && [ -n "$CAP_TXT" ] && M=$CAP_TXT
    refuse_preformed "$M"
    ;;
esac
