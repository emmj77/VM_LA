#!/usr/bin/dash
# french in code is forbidden
set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

TABLE=${LA_CONFIG:-$ROOT/config/la_tools.yaml}
SKILLS=$ROOT/skills
PROGS=$ROOT/config/programs
BODIES=
for _f in "$ROOT"/config/tools/*/tool_*.yaml "$ROOT"/config/tools/tool_*.yaml ; do
  [ -f "$_f" ] && BODIES="$BODIES $_f"
done

LIM_HEALTH=$(conf_num limits health_timeout 3)
LIM_PING=$(conf_num limits ping_timeout 2)
LIM_BENCH=$(conf_num limits bench_timeout 120)
LIM_TUNNEL=$(conf_num limits tunnel_steps 12)

PY=/usr/bin/python3
[ -x "$PY" ] || PY=python3

SHORT=0 ; LIGHT=0
for _a in "$@"; do
  case "$_a" in
    --short) SHORT=1 ;;
    --light) LIGHT=1 ;;
  esac
done

FAULTS=0 ; NOTES=0
ok()    { [ "$SHORT" = 1 ] || printf '  ok     %s\n' "$1" ; }
note()  { NOTES=$((NOTES+1)) ; [ "$SHORT" = 1 ] || printf '  note   %s\n' "$1" ; }
fail()  { FAULTS=$((FAULTS+1)) ; printf '  FAULT  %s\n' "$1" ; }
title() { [ "$SHORT" = 1 ] || printf '\n%s\n' "$1" ; }
quiet() { [ "$FAULTS" = "$1" ] && ok "$2" ; return 0 ; }

title "LA RACINE ET LA CONFIG"
if [ ! -d "$ROOT" ] || [ ! -f "$TABLE" ] || [ ! -f "$CONF" ]; then
  fail "racine, table ou la_config introuvable ($ROOT / $TABLE / $CONF)"
  printf '\n  --     %d fault(s)\n' "$FAULTS"
  exit 1
fi
ok "racine $ROOT"

if command -v "$PY" >/dev/null 2>&1 ; then
  if _y=$("$PY" -B -c 'import sys,yaml;yaml.safe_load(open(sys.argv[1]))' "$CONF" 2>&1) ; then
    ok "la_config se lit (YAML, $(wc -l <"$CONF") lignes)"
  else
    fail "la_config ne se lit pas en YAML : $(printf '%s' "$_y" | tail -n 1)"
  fi
else
  note "pas d interprete python3 : la_config n est pas verifiee en YAML (dash, board et tui tomberaient)"
fi

_b=$FAULTS ; NR=0
while read -r _sec _keys ; do
  [ -n "${_sec:-}" ] || continue
  for _k in $_keys ; do
    NR=$((NR+1))
    conf_has "$_sec" "$_k" || \
      fail "la_config : $_sec.$_k est exige par le moteur et MANQUE (il refusera de demarrer, exit 78)"
  done
done <<EOF
$(grep -h '^conf_require ' "$ROOT"/config/engine/*.sh 2>/dev/null | sed 's/^conf_require //')
EOF
quiet "$_b" "$NR cle(s) exigees par le moteur, toutes ecrites"

title "LES SCRIPTS ET LES BRIQUES"
_b=$FAULTS ; N=0
for _f in "$ROOT"/config/engine/*.sh ; do
  [ -f "$_f" ] || continue
  N=$((N+1))
  dash -n "$_f" 2>/dev/null || fail "syntaxe dash : ${_f##*/}"
done
for _b2 in lib.sh engine.sh loop.sh second.sh ; do
  [ -f "$ROOT/config/engine/$_b2" ] || fail "brique du coeur absente : $_b2"
done
quiet "$_b" "$N script(s), syntaxe tenue"

title "LES PROGRAMMES"
_b0=$FAULTS ; N=0
if command -v "$PY" >/dev/null 2>&1 ; then
  for _f in "$PROGS"/*.py ; do
    [ -f "$_f" ] || continue
    N=$((N+1))
    "$PY" -B -c 'import ast,sys;ast.parse(open(sys.argv[1],encoding="utf-8").read())' "$_f" 2>/dev/null \
      || fail "syntaxe python : ${_f##*/}"
    case "${_f##*/}" in
      dash.py|board.py)
        grep -q 'laconf' "$_f" || fail "${_f##*/} : ne passe pas par laconf (deuxieme lecteur de la_config)" ;;
    esac
  done
  _b1=$FAULTS
  if [ "$LIGHT" = 1 ] ; then
    note "l import des programmes : NON VERIFIE (--light)"
  else
    for _m in dash board ; do
      [ -f "$PROGS/$_m.py" ] || continue
      "$PY" -B -c "import sys;sys.path.insert(0,'$PROGS');import $_m" 2>/dev/null \
        || fail "programme $_m : l import leve une erreur -- il ne demarre pas"
    done
    quiet "$_b1" "les deux programmes s importent"
  fi
  quiet "$_b0" "$N programme(s), syntaxe tenue"

  _b2=$FAULTS ; NJ=0
  if command -v node >/dev/null 2>&1 ; then
    for _f in "$ROOT"/config/dashboard/*.js "$ROOT"/config/widget-sw.js "$ROOT"/config/applets/*/applet.js ; do
      [ -f "$_f" ] || continue
      NJ=$((NJ+1))
      node --check "$_f" 2>/dev/null || fail "javascript : ${_f##*/} ne se lit pas"
    done
    quiet "$_b2" "$NJ fichier(s) javascript, tous lisibles"
  else
    note "pas de node : le javascript n est pas verifie"
  fi
else
  fail "pas d interprete python3 : dash, board et tui ne tournent pas"
fi

title "LE PROMPT (la loi donnee au modele)"
if [ -f "$ROOT/config/head.yaml" ] ; then
  if [ -s "$ROOT/config/head.yaml" ] ; then
    ok "head.yaml present ($(wc -l <"$ROOT/config/head.yaml") lignes, $(wc -c <"$ROOT/config/head.yaml") octets)"
  else
    fail "head.yaml est VIDE : le modele partirait sans consigne"
  fi
  grep -q 'head.yaml' "$ROOT/config/engine/loop.sh" || fail "la boucle ne lit pas head.yaml"
else
  fail "pas de head.yaml : le modele recevrait un prompt sans loi"
fi

title "LA TABLE (registre, familles, corps)"
_b=$FAULTS
IDS=$(grep -c '^  - id: ' "$TABLE")
TOOLS=$(grep -c '^    tool: ' "$TABLE")
FAM=$(grep -c '^    family: ' "$TABLE")
[ "$IDS" -gt 0 ] || fail "la table ne declare aucun tool"
[ "$IDS" = "$TOOLS" ] || fail "$IDS id(s) pour $TOOLS tool(s)"
[ "$IDS" = "$FAM" ] || fail "$IDS id(s) pour $FAM famille(s)"

FAM_OK=" $(grep -oE '^  [A-Z]+(\|[A-Z]+)+\)' "$ROOT/config/engine/engine.sh" 2>/dev/null \
          | head -n 1 | tr -d ' )' | tr '|' ' ') "
[ "$FAM_OK" != "  " ] || note "les familles du moteur : introuvables dans engine.sh (le case a bouge ?)"
OUT=
for _F in $(sed -n 's/^    family:[[:space:]]*//p' "$TABLE" | sort -u) ; do
  case "$FAM_OK" in *" $_F "*) ;; *) OUT="$OUT $_F" ;; esac
done
[ -z "$OUT" ] || fail "famille(s) que le moteur refuse a l execution :$OUT"

DUP=$(grep -oE '^  - id: [0-9]+' "$TABLE" | sort | uniq -d | tr '\n' ' ')
[ -z "$DUP" ] || fail "id(s) en double : $DUP"

set -- "$TABLE"
for _f in $BODIES ; do set -- "$@" "$_f" ; done
BODY_SCAN=$(awk '
  FILENAME == ARGV[1] {
    if ($1 == "-") id = $3
    else if ($1 == "tool:" && NF >= 2) { K++ ; T[K] = $2 ; REG[$2] = 1 }
    next
  }
  FNR == 1 { n = split(FILENAME, a, "/") ; f = a[n] ; sub(/^tool_/, "", f) ; sub(/\.yaml$/, "", f) ; cur = f }
  /^COMMAND:/ { HAS[cur] = 1 }
  /^machine:/ { HAS[cur] = 1 }
  END {
    for (i = 1 ; i <= K ; i++) if (T[i] in HAS) NK++ ; else NOB = NOB " " T[i]
    for (t in HAS) if (!(t in REG)) ORP = ORP " " t
    printf "%d|%s|%s\n", NK, NOB, ORP
  }' "$@" 2>/dev/null)
NFILE=$(printf '%s' "$BODY_SCAN" | cut -d'|' -f1)
NOBODY=$(printf '%s' "$BODY_SCAN" | cut -d'|' -f2)
ORPH=$(printf '%s' "$BODY_SCAN" | cut -d'|' -f3 | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ')
[ -z "$NOBODY" ] || fail "id(s) sans corps dans config/tools/ :$NOBODY"
[ -z "$ORPH" ] || note "corps sans ligne au registre (inatteignable, il dort) :$ORPH"

NSF=$(grep -c '^    sub_family: ' "$TABLE" 2>/dev/null || printf 0)
[ "${NSF:-0}" -gt 0 ] || note "aucune sous-famille : les ateliers annonceront leurs 2 500 noms d un bloc"
quiet "$_b" "$IDS tools, $NFILE corps, familles tenues"

title "LES CHEMINS CITES PAR LA TABLE"
_b=$FAULTS ; N=0
for _p in $(grep -ohE '(/home/[A-Za-z0-9_./+-]+|\$HOME/[A-Za-z0-9_./+-]*)' \
             "$TABLE" $BODIES 2>/dev/null | sed "s|^\\\$HOME|$HOME|" | sort -u) ; do
  N=$((N+1))
  [ -e "$_p" ] || fail "cite et ABSENT : $_p"
done
quiet "$_b" "$N chemin(s) cite(s), present(s)"

title "LES BASES"
for _db in "$ROOT/config/sessions.db" "$ROOT/config/memory.db" "$ROOT/config/terminal_return.db" ; do
  if [ ! -f "$_db" ] ; then
    note "pas de base ${_db##*/} (elle nait au premier usage)"
    continue
  fi
  if ! command -v sqlite3 >/dev/null 2>&1 ; then
    note "pas de sqlite3 : ${_db##*/} n est pas verifiee"
    continue
  fi
  _v=$(sqlite3 "$_db" 'pragma quick_check;' 2>&1 | head -n 1)
  if [ "$_v" = ok ] ; then
    ok "la base ${_db##*/} tient ($(du -h "$_db" | cut -f1))"
  else
    fail "la base ${_db##*/} est MALFORMEE : $_v"
  fi
done
if [ -f "$ROOT/config/sessions.db" ] && command -v sqlite3 >/dev/null 2>&1 ; then
  _m=$(sqlite3 "$ROOT/config/sessions.db" 'pragma journal_mode;' 2>/dev/null)
  [ "$_m" = wal ] || note "sessions.db en ${_m:-?} : le WAL est ce qui laisse un lecteur vivre a cote de l ecrivain"
fi

title "LA MEMOIRE"
if [ -f "$ROOT/config/memory.db" ] && command -v sqlite3 >/dev/null 2>&1 ; then
  NT=$(sqlite3 "$ROOT/config/memory.db" 'SELECT count(*) FROM memory;' 2>/dev/null || printf '')
  NV=$(sqlite3 "$ROOT/config/memory.db" 'SELECT count(vec) FROM memory;' 2>/dev/null || printf '')
  ok "la table porte ${NT:-0} entree(s), ${NV:-0} avec un vecteur"
  case "${NT:-0}" in
    0) note "la table est vide : la premiere entree vient du compacteur, a la fin d un tour" ;;
    *) [ "${NT:-0}" = "${NV:-0}" ] || note "$((NT - NV)) entree(s) sans vecteur (lisibles par mots seulement)" ;;
  esac
fi

title "LES SKILLS"
NSK=0
for _d in "$SKILLS"/*/ ; do
  [ -f "$_d/skill.yaml" ] || continue
  NSK=$((NSK+1))
  S="$_d/skill.yaml"
  NM=$(basename "$_d")
  grep -q '^PERIMETER:' "$S" || fail "skill $NM : pas de PERIMETER"
  grep -q '^  workspace:' "$S" || fail "skill $NM : PERIMETER sans workspace"
  _dr=$(sed -n '/^PERIMETER:/,/^[^[:space:]]/p' "$S" | sed -n 's/^[[:space:]]*tools:[[:space:]]*//p' | head -1 | sed "s/[\"']//g")
  if [ -n "$_dr" ]; then
    table_index
    printf '%s\n' "$TABLE_INDEX" \
      | awk -F'|' -v f="$(printf '%s' "$_dr" | tr 'a-z' 'A-Z')" '$3 == f { n++ } END { exit (n > 0) ? 0 : 1 }' \
      || fail "skill $NM : la porte '$_dr' n ouvre rien -- famille absente du registre"
  fi
  for _T in $(sed -n '/^TOOLS:/,/^[A-Z][A-Z]*:/p' "$S" \
               | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*"\([a-z_][a-z_0-9]*\)".*/\1/p') ; do
    grep -q "^    tool: $_T\$" "$TABLE" || fail "skill $NM : ouvre un tool qui n existe pas ($_T)"
  done
  L=$(awk '/^SUMMARY:/,/^[A-Z][A-Z]*:/' "$S" | awk 'length($0) > 100' | wc -l)
  [ "$L" = 0 ] || fail "skill $NM : $L ligne(s) de SUMMARY au-dela de 100 octets"
  grep -q '^STEPS:' "$S" && fail "skill $NM : porte encore un bloc STEPS -- la route, c est le plan permanent"
  grep -q '^DOCS:' "$S" || note "skill $NM : pas de DOCS -- load_doc repondra \"names no resource\""
  A=$(sed -n 's/^APPROVAL:[[:space:]]*//p' "$S" | head -n 1 | sed -e 's/#.*//' | tr -d "[:space:]\"'")
  case "$A" in
    true|false) ;;
    '') note "skill $NM : pas de ligne APPROVAL -- la boucle lit false (elle n ecrit pas dans le harnais)" ;;
    *) fail "skill $NM : APPROVAL hors forme (\"$A\") -- elle porte true ou false, en minuscules" ;;
  esac
  PT=$(sed -n 's/^PERMANENT_TODO:[[:space:]]*//p' "$S" | head -n 1 | sed -e 's/#.*//' | tr -d "[:space:]\"'")
  case "$PT" in
    true)
      NP=$(grep -c '^  [0-9][0-9][0-9]:[[:space:]]*"\[progress\]' "$S")
      NT=$(grep -c '^  [0-9][0-9][0-9]:[[:space:]]*"\[todo\]' "$S")
      NC=$(grep -c '^  [0-9][0-9][0-9]:[[:space:]]*"\[complete\]' "$S")
      NS=$((NP + NT + NC))
      [ "$NP" = 1 ] || fail "skill $NM : PERMANENT_TODO true mais $NP etape(s) en cours -- il en faut UNE (le tunnel ne saurait pas ou il en est)"
      [ "$NS" -le "$LIM_TUNNEL" ] || fail "skill $NM : $NS etapes dans le tunnel -- $LIM_TUNNEL au plus"
      for _W in $(sed -n 's/.*--[[:space:]]*outils:[[:space:]]*\(.*\)"$/\1/p' "$S" | tr ',' ' ') ; do
        grep -qE "^    tool: $_W\$" "$TABLE" || \
          fail "skill $NM : une etape nomme l outil \"$_W\", absent de la table -- elle ne se fermerait jamais"
        grep -qE "^  [0-9]+: \"$_W\"" "$S" || \
          fail "skill $NM : une etape nomme \"$_W\", absent de TOOLS: -- la palette d une etape est un sous-ensemble de la sienne"
      done
      ok "skill $NM : todo permanent, $NS etapes, $NP en cours"
      ;;
    false|'') ;;
    *) fail "skill $NM : PERMANENT_TODO hors forme (\"$PT\") -- true ou false, en minuscules" ;;
  esac
done
[ "$NSK" -gt 0 ] && ok "$NSK skill(s) examine(s)" || fail "aucune skill dans $SKILLS"

RIGHTS=
for _d in "$SKILLS"/*/ ; do
  [ -f "$_d/skill.yaml" ] || continue
  grep -q '^APPROVAL:[[:space:]]*true[[:space:]]*$' "$_d/skill.yaml" && RIGHTS="$RIGHTS $(basename "$_d")"
done
if [ -n "$RIGHTS" ] ; then
  ok "APPROVAL: true --$RIGHTS(et personne d autre)"
else
  note "aucune skill ne porte APPROVAL: true -- la table et les skills sont en lecture seule de l interieur"
fi

if grep -q 'read_return' "$ROOT/config/engine/trim_forms.sh" 2>/dev/null ; then
  grep -qx '  - read_return' "$CONF" \
    && ok "read_return est cite par les formulaires et il est atteignable (permanent)" \
    || fail "trim_forms promet read_return et aucune porte ne l ouvre (permanent dans la_config)"
fi
for _P in $(sed -n '/^permanent:/,/^[a-z_]*:/p' "$CONF" | sed -n 's/^  - \([a-z_][a-z_0-9]*\)$/\1/p') ; do
  N=$(grep -l "^[[:space:]]*[0-9]*:[[:space:]]*\"$_P\"" "$SKILLS"/*/skill.yaml 2>/dev/null | wc -l)
  [ "$N" = 0 ] || note "$_P est permanent et aussi dans $N palette(s) : la palette ne le decide pas"
done

NP=0
for S in "$SKILLS"/*/skill.yaml ; do
  [ -f "$S" ] || continue
  _P=$(sed -n 's/^PORTEUR:[[:space:]]*//p' "$S" 2>/dev/null | head -n 1 | sed -e 's/#.*$//' | tr -d ' "')
  [ -n "$_P" ] || continue
  NP=$((NP+1))
  [ -x "$ROOT/config/engine/$_P" ] || fail "$(basename "$(dirname "$S")") declare $_P, absent de config/engine/"
done
[ "$NP" -gt 0 ] && ok "$NP porteur(s) declare(s), tous presents"

title "LA SKILL ACTIVE ET LE PROJET"
active_skill
active_project
if [ -n "${PNAME:-}" ] ; then
  ok "le projet actif est $PNAME ($PROJECT)"
else
  ok "aucun projet charge : tout le jeu de skills est ouvert (projects/.active absent)"
fi
if [ -n "${NAME:-}" ] && [ -f "$SKILLS/$NAME/skill.yaml" ] ; then
  ok "le .active dit $NAME, et $NAME existe"
else
  fail "le .active ne nomme aucune skill qui existe (skills/.active)"
fi

title "LE CANON"
canon_path
ok "le canon est $CANON_WHY"
if [ -n "${SPEC:-}" ] && [ -f "$SPEC" ] ; then
  D=$(grep -oE '^  [0-9]+:' "$SPEC" | sort | uniq -d | tr '\n' ' ')
  [ -z "$D" ] || fail "lois en double : $D"
  ok "$(grep -c '^SECTION : ' "$SPEC") section(s)"
  L=$(awk 'length($0) > 100' "$SPEC" | wc -l)
  [ "$L" = 0 ] || fail "$L ligne(s) au-dela de 100 octets dans le canon"
  M=$(grep -c 'coffre' "$SPEC" 2>/dev/null || true) ; M=${M:-0}
  [ "$M" = 0 ] || note "$M ligne(s) du canon disent encore \"coffre\""
else
  fail "aucun canon a lire : $CANON_WHY"
fi

title "LES RESIDENTS (ce qui ecoute)"
_b=$FAULTS
for _R in "models:la-models:health" "asr:la-asr:health" "tts:la-tts:health" "dashboard:la-dash:health" ; do
  _SEC=${_R%%:*} ; _REST=${_R#*:} ; _UNIT=${_REST%%:*} ; _H=${_REST#*:}
  _PORT=$(conf_num "$_SEC" port 0)
  if [ "$_PORT" = 0 ] ; then
    note "$_SEC : aucune porte dans la_config"
    continue
  fi
  if ! systemctl --user is-active --quiet "$_UNIT" 2>/dev/null ; then
    note "$_UNIT est arretee ($_PORT) : les tools qui en dependent refuseront"
    continue
  fi
  _REP=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$LIM_HEALTH" "http://127.0.0.1:$_PORT/$_H" 2>/dev/null)
  case "$_REP" in
    200) ok "$_UNIT tient $_PORT/$_H" ;;
    000) fail "$_UNIT est active et $_PORT ne repond pas : ce qui l appelle echouera" ;;
    *)   note "$_UNIT rend $_REP sur $_PORT/$_H" ;;
  esac
done
quiet "$_b" "les cinq residents repondent"

_TA=$(conf_str bridge tls_host "")
[ -n "$_TA" ] || _TA=$(tailscale ip -4 2>/dev/null | head -n 1)
_TP=$(conf_num bridge tls_port 8766)
if [ -n "$_TA" ] ; then
  if curl -sk --max-time "$LIM_PING" "https://$_TA:$_TP/ping" >/dev/null 2>&1 ; then
    ok "la porte chiffree repond sur $_TA:$_TP"
  else
    note "la porte chiffree ne repond pas sur $_TA:$_TP"
  fi
fi

title "LES INSTRUMENTS (appeles par des tools, sans etre des residents)"
if command -v tesseract >/dev/null 2>&1 ; then
  _TV=$(tesseract --version 2>&1 | sed -n '1s/.*tesseract[ ]*//p' | cut -c1-12)
  ok "tesseract ${_TV:-?} repond (see_page, read_text_on_screen, read_text_in_img)"
  for _L in fra eng ; do
    tesseract --list-langs 2>/dev/null | grep -qx "$_L" \
      && ok "la langue $_L est installee" \
      || note "pas de langue $_L pour tesseract : l OCR de ce texte sera pauvre"
  done
else
  fail "pas de tesseract : see_page, read_text_on_screen et read_text_in_img ne lisent rien"
fi

title "LES FORMULAIRES DE RETOUR"
TRF="$ROOT/config/engine/trim_forms.sh"
[ -x "$TRF" ] && ok "le selecteur de formulaires est present et executable" \
              || fail "pas de selecteur de formulaires ($TRF)"
grep -q 'trim_forms' "$ROOT/config/engine/loop.sh" \
  && ok "la boucle passe par les formulaires AVANT le plafond" \
  || fail "la boucle ne passe pas par les formulaires"

title "LES BANCS"
BENCH_DIR=${LA_BENCHES:-$HOME/.cache/la/bancs}
if [ "$LIGHT" = 1 ] ; then
  note "les bancs : NON JOUES (--light)"
elif [ -x "$BENCH_DIR/banc_selecteur.sh" ] ; then
  _B=$(timeout "$LIM_BENCH" sh "$BENCH_DIR/banc_selecteur.sh" 2>&1 | tail -n 1)
  case "$_B" in
    *"0 non conforme"*) ok "les bancs : $_B" ;;
    "")                 note "les bancs : le selecteur n a rien rendu" ;;
    *)                  fail "les bancs : $_B" ;;
  esac
else
  note "les bancs ne sont pas la (LA_BENCHES=$BENCH_DIR) : artefact de travail, pas du depot"
fi

title "LE VOCABULAIRE"
OTHERS=$(printf '%s\n' "$ROOT"/config/engine/*.sh | grep -v '/doctor.sh$' | tr '\n' ' ')
C=$(grep -c 'coffre' $OTHERS "$TABLE" "$ROOT/config/head.yaml" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
[ "$C" = 0 ] && ok "aucun identifiant \"coffre\" dans le code" || fail "$C \"coffre\" restant(s) dans le code"
V=$(/usr/bin/python3 "$ROOT/config/programs/audit_vocab.py" 2>&1 | awk '/^total:/{print $2}')
[ "${V:-0}" = 0 ] && ok "aucun terme francais dans la machinerie" || fail "${V} terme(s) francais dans la machinerie"
for _O in coeur gestion musique rapport reseau systeme veille ; do
  [ -d "$SKILLS/$_O" ] && fail "l ancien nom de skill est revenu : skills/$_O"
done

printf '\n  --     %d fault(s), %d note(s)\n' "$FAULTS" "$NOTES"
[ "$FAULTS" = 0 ] && exit 0
exit 1
