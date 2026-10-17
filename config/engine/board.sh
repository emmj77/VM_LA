#!/bin/sh
# board.sh — LE PANNEAU DE LA. Ce qui est charge, ce qui repond, ce qui ne va pas.
#
#   board.sh              le panneau VIVANT : il se redessine, il reste visible (Ctrl-C pour sortir)
#   board.sh --once       UNE passe et il sort : c'est la forme dont un agent se sert pour auditer
#   board.sh --watch 5    le panneau, redessine toutes les 5 secondes (defaut : 3)
#
# CE QU'IL EST : un LECTEUR. Il ne repare rien, il n'ouvre rien, il n'ecrit nulle part. Chaque ligne
# est une VERIFICATION NOMMEE avec son verdict : [ok] elle tient, [!!] elle ne tient pas, [--] elle
# ne s'applique pas ici. Un panneau qui dirait « tout va bien » sans dire ce qu'il a regarde ne
# vaudrait rien (c'est la regle du doctor, loi 1800).
#
# IL PARTAGE SES VERIFICATIONS AVEC LE DOCTOR : les lignes de doctor.sh sont relues TELLES QUELLES
# (section THE DOCTOR), et le panneau ajoute ce que le doctor ne regarde pas -- les residents, les
# modeles sur le disque, la table a deux fichiers, le trafic, la RAM. Une meme verite ne s'ecrit
# qu'une fois : le jour ou le doctor couvre une ligne, elle se retire d'ici.
#
# POSIX sh (dash) + coreutils + curl + sqlite3. Pas de backtick. Aucune ecriture.
LC_ALL=C
export LC_ALL

HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
ROOT=${LA_ROOT:-$(dirname "$CONF_DIR")}
TABLE=${LA_CONFIG:-$CONF_DIR/la_tools.yaml}
CONF=${LA_CONF:-$CONF_DIR/la_config.yaml}
GGUF=${LA_GGUF_DIR:-$HOME/LLM_GGUF}
DB=${LA_DB:-$CONF_DIR/sessions.db}
JOURNAL=${LA_LOG_FILE:-}

WATCH=3
ONCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --once) ONCE=1 ;;
    --watch) shift; case "${1:-}" in ''|*[!0-9]*) : ;; *) WATCH=$1 ;; esac ;;
    -h|--help) sed -n '2,9p' "$0" | sed -e 's/^# \{0,1\}//' ; exit 0 ;;
    *) printf 'board: je ne connais pas %s (--once, --watch N)\n' "$1" >&2 ; exit 2 ;;
  esac
  shift
done

FAULTS=0
ok()   { printf '  [ok] %s\n' "$1" ; }
ko()   { FAULTS=$((FAULTS + 1)) ; printf '  [!!] %s\n' "$1" ; }
neut() { printf '  [--] %s\n' "$1" ; }
titre() { printf '\n%s\n' "$1" ; }

# UNE SONDE : $1 = port, $2 = chemin. Rend le code HTTP, ou 000 si rien ne repond.
sonde() {
  _code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$1/$2" 2>/dev/null || true)
  _code=$(printf '%s' "$_code" | cut -c1-3)
  case "$_code" in ''|*[!0-9]*) printf '000' ;; *) printf '%s' "$_code" ;; esac
}
# LA VIVE D'UNE UNITE : $1 = unite systemd --user. Rend « <etat> <Mo> » (Mo vide si pas de processus).
vive() {
  _pid=$(systemctl --user show -p MainPID --value "$1" 2>/dev/null || printf '')
  _etat=$(systemctl --user is-active "$1" 2>/dev/null || printf '?')
  _mo=
  case "$_pid" in ''|0|*[!0-9]*) : ;; *)
    _ko=$(awk '/^VmRSS:/{print $2}' "/proc/$_pid/status" 2>/dev/null)
    case "$_ko" in ''|*[!0-9]*) : ;; *) _mo=$((_ko / 1024)) ;; esac ;;
  esac
  printf '%s %s' "$_etat" "$_mo"
}
# LE MODELE DECLARE PAR UNE BRIQUE : le premier chemin absolu a extension de poids.
modele_de() {
  grep -m1 -oE '/[^ "]{0,120}\.(gguf|onnx|bin|ftz|pb)' "$1" 2>/dev/null | head -n 1
}
octets_lisibles() {   # $1 = un nombre d'octets
  case "${1:-}" in ''|*[!0-9]*) printf '?' ; return ;; esac
  awk -v b="$1" 'BEGIN{ if (b>=1048576) printf "%d Mo", b/1048576; else printf "%d Ko", b/1024 }'
}

dessine() {
  printf 'LA -- THE BOARD   %s UTC\n' "$(date -u +%H:%M:%S)"
  printf '  racine %s\n' "$ROOT"
  if command -v git >/dev/null 2>&1 && [ -d "$ROOT/.git" ]; then
    printf '  depot %s   %s\n' "$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf '?')" \
      "$(git -C "$ROOT" log -1 --format=%s 2>/dev/null | cut -c1-60)"
  fi

  # ---- THE RESIDENTS : ceux qui doivent etre LA, et ce qu'ils ont charge --------------------
  titre 'THE RESIDENTS (what is loaded, and what it costs)'
  for u in la-embed la-rerank la-local la-asr la-tts; do
    _v=$(vive "$u.service")
    _etat=${_v%% *} ; _mo=${_v##* }
    _br="$HERE/${u#la-}.sh"
    case "$u" in la-embed) _br="$HERE/embed.sh" ; _p=8096 ;; la-rerank) _br="$HERE/rerank.sh" ; _p=8095 ;;
      la-local) _br="$HERE/local.sh" ; _p=8088 ;; la-asr) _br="$HERE/asr.sh" ; _p=8080 ;;
      la-tts) _br="$HERE/tts.sh" ; _p=8090 ;; esac
    _ligne=$(printf '%-13s :%s' "${u#la-}" "$_p")
    if [ "$_etat" = active ]; then
      _c=$(sonde "$_p" "${LA_HEALTH_PATH:-health}")
      case "$_c" in 000) _ligne="$_ligne  [!!] il tourne mais ne repond pas" ; FAULTS=$((FAULTS + 1)) ;;
        *) _ligne="$_ligne  [ok] il repond ($_c)" ;; esac
      [ -n "$_mo" ] && _ligne="$_ligne  ${_mo} Mo"
    else
      _ligne="$_ligne  [!!] il ne tourne pas (etat : $_etat)" ; FAULTS=$((FAULTS + 1))
    fi
    printf '%s\n' "$_ligne"
  done
  _c=$(sonde 8765 ping)
  case "$_c" in 000) neut 'le pont vers l app (8765) ne repond pas : l app est-elle lancee ?' ;;
    *) ok "le pont vers l app repond (8765, $_c)" ;; esac
  _c=$(sonde 8091 health)
  case "$_c" in 000) neut 'l etage de vision (8091) est a l arret : il se demarre a la demande' ;;
    *) ok "l etage de vision repond (8091, $_c)" ;; esac

  # ---- THE MODELS ON DISK : ceux que la TABLE reclame ---------------------------------------
  titre 'THE MODELS ON DISK (what the tools ask for)'
  _vus= ; _n=0 ; _manque=0
  for f in "$ROOT"/config/tools/*/tool_*.yaml; do
    [ -f "$f" ] || continue
    _m=$(grep -m1 -oE '[A-Za-z0-9_.-]+\.(gguf|onnx|pb|ftz)' "$f" 2>/dev/null | head -n 1)
    [ -n "$_m" ] || continue
    case " $_vus " in *" $_m "*) continue ;; esac
    _vus="$_vus $_m" ; _n=$((_n + 1))
    if [ -f "$GGUF/$_m" ]; then
      printf '  [ok] %-34s %s\n' "$_m" "$(octets_lisibles "$(wc -c < "$GGUF/$_m" 2>/dev/null)")"
    else
      printf '  [!!] %-34s MANQUANT sous %s\n' "$_m" "$GGUF" ; _manque=$((_manque + 1)) ; FAULTS=$((FAULTS + 1))
    fi
  done
  if [ "$_n" -eq 0 ]; then neut 'aucun corps de tool ne nomme de modele'; fi
  _mf="$CONF_DIR/filtre/famille.bin"
  if [ -f "$_mf" ]; then ok "le filtre de famille a appris ($(octets_lisibles "$(wc -c < "$_mf")"))"
  else neut "le filtre de famille n a pas appris ($_mf : lance train_family_filter)"; fi

  # ---- THE TABLE : les ids du registre et les corps qui leur repondent ---------------------
  titre 'THE TABLE (every id has a body)'
  _ids=0 ; _corps=0 ; _perdus=
  if [ -f "$TABLE" ]; then
    _liste=$(sed -n 's/^[[:space:]]*tool:[[:space:]]*//p' "$TABLE")
    for _t in $_liste; do
      _ids=$((_ids + 1))
      if ls "$ROOT"/config/tools/*/"tool_$_t.yaml" >/dev/null 2>&1; then
        _corps=$((_corps + 1))
      else
        _perdus="$_perdus $_t"
      fi
    done
    _nperdus=0
    for _t in $_perdus; do _nperdus=$((_nperdus + 1)); done
    if [ "$_nperdus" -eq 0 ]; then
      ok "$_ids ids, $_corps corps trouves, aucun sans corps"
    else
      ko "$_ids ids, $_corps corps trouves ; $_nperdus sans corps :"
      printf '        %s\n' "$(printf '%s' "$_perdus" | cut -c1-180)"
    fi
    _dups=$(sed -n 's/^[[:space:]]*-[[:space:]]*id:[[:space:]]*//p' "$TABLE" | sort | uniq -d | tr '\n' ' ')
    if [ -z "$_dups" ]; then ok 'aucun id en double'
    else ko "id(s) en double : $_dups -- le moteur prend le PREMIER, en silence" ; fi
  else
    ko "la table est absente ($TABLE)" ; _ids=0
  fi

  # ---- THE CANON : ou il vit, et sa forme ----------------------------------------------------
  titre 'THE CANON (its form, not its content)'
  _spec=
  for c in "$ROOT/projects/la/spec.yaml" "$ROOT/skills/la/spec.yaml"; do
    [ -f "$c" ] && _spec=$c && break
  done
  if [ -z "$_spec" ]; then
    ko 'le canon est introuvable (projects/la/spec.yaml, puis skills/la/spec.yaml)'
  else
    _lois=$(grep -cE '^  [0-9]+:' "$_spec")
    _sec=$(grep -c '^SECTION : ' "$_spec")
    _dup=$(grep -oE '^  [0-9]+:' "$_spec" | sort | uniq -d | tr '\n' ' ')
    _long=$(awk 'length($0) > 100' "$_spec" | wc -l | tr -d ' ')
    printf '  [--] lu dans %s\n' "$_spec"
    ok "$_lois lois, $_sec sections"
    [ -z "$_dup" ] && ok 'aucun numero de loi en double' || ko "numero(s) de loi en double : $_dup"
    [ "$_long" = 0 ] && ok 'aucune ligne de plus de 100 octets' || ko "$_long ligne(s) de plus de 100 octets"
    if command -v git >/dev/null 2>&1 && ! git -C "$ROOT" ls-files --error-unmatch "$_spec" >/dev/null 2>&1; then
      ko "le canon n est PAS suivi par git : aucune histoire de ses editeurs"
    else
      ok 'le canon est suivi par git'
    fi
  fi

  # ---- THE DOCTOR : ses propres lignes, telles quelles --------------------------------------
  titre 'THE DOCTOR (the same checks, read here)'
  _doc=$(sh "$HERE/doctor.sh" 2>/dev/null) || _doc=''
  if [ -z "$_doc" ]; then
    ko "doctor.sh n a rien rendu ($HERE/doctor.sh)"
  else
    printf '%s\n' "$_doc" | grep -E '^  *(ok|fail|FAULT|FAUTE|note)|^[A-Z][A-Z ]{3,}' \
      | sed -E -e 's/^  *(ok|fail|FAULT|FAUTE|note) +/  [\1] /' \
               -e 's/^  \[(fail|FAULT|FAUTE)\] /  [!!] /' -e 's/^  \[note\] /  [--] /' \
      | head -n 30
    _df=$(printf '%s\n' "$_doc" | grep -cE '^  *(fail|FAULT|FAUTE)' | tr -d ' ')
    case "$_df" in ''|*[!0-9]*) _df=0 ;; esac
    FAULTS=$((FAULTS + _df))
  fi

  # ---- THE TRAFFIC : ce qui transite ---------------------------------------------------------
  titre 'THE TRAFFIC (what goes in and out)'
  _addr=$(awk '/^  - provider:/{p=$3} /^    post:/{u=$2} /^    model:/{m=$2} /^    active:[[:space:]]*"true"/{print p" "u" "m; exit}' "$CONF" 2>/dev/null)
  if [ -n "$_addr" ]; then
    _prov=${_addr%% *} ; _reste=${_addr#* } ; _url=${_reste%% *} ; _mod=${_reste#* }
    printf '  [--] adresse en service : %s (%s)\n' "$_prov" "$_mod"
    _code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 -X HEAD "$_url" 2>/dev/null || true)
    _code=$(printf '%s' "$_code" | cut -c1-3)
    case "$_code" in 000) ko "l adresse ne repond pas ($_url)" ;;
      *) ok "l adresse repond ($_code) : $_url" ;; esac
  else
    neut 'aucune adresse active dans la config'
  fi
  if [ -f "$DB" ]; then
    _ech=$(sqlite3 "$DB" 'SELECT COALESCE(MAX(exchange),0) FROM messages;' 2>/dev/null || printf '?')
    _msg=$(sqlite3 "$DB" 'SELECT COUNT(*) FROM messages;' 2>/dev/null || printf '?')
    ok "sessions : $_msg messages, dernier echange n° $_ech"
    sqlite3 "$DB" "SELECT role || ' : ' || substr(content,1,70) FROM messages WHERE content <> '' ORDER BY id DESC LIMIT 1;" 2>/dev/null \
      | tr '\n\t' '  ' | sed -e 's/^/        dernier mot : /'
  else
    neut "pas de base de sessions ($DB)"
  fi
  if [ -n "$JOURNAL" ] && [ -f "$JOURNAL" ]; then
    ok "journal : $JOURNAL ($(octets_lisibles "$(wc -c < "$JOURNAL" 2>/dev/null)"), $(wc -l < "$JOURNAL" | tr -d ' ') lignes)"
    tail -n 1 "$JOURNAL" 2>/dev/null | tr '\n\t' '  ' | cut -c1-110 | sed -e 's/^/        /'
    _echecs=$(grep -c 'echec de transport' "$JOURNAL" 2>/dev/null | tr -d ' ')
    case "$_echecs" in ''|0) ok 'aucun echec de transport au journal' ;;
      *) ko "$_echecs echec(s) de transport au journal" ;; esac
  else
    neut 'pas de journal de tour : pose LA_LOG_FILE pour que le panneau lise ce qui transite'
  fi

  # ---- THE MACHINE : la ram, les cartes, le disque -------------------------------------------
  titre 'THE MACHINE (RAM, cards, disk)'
  if command -v free >/dev/null 2>&1; then
    free -m | awk '/^Mem:/{printf "  [--] RAM %s Mo utilises sur %s (%s libres) ; echange %s Mo\n", $3, $2, $7, $5}'
  fi
  printf '  [--] les plus gros : %s\n' "$(ps -eo rss=,comm= --sort=-rss 2>/dev/null | head -n 4 | awk '{printf "%s %d Mo  ", $2, $1/1024}')"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null \
      | sed -e 's/^/  [--] carte : /' | head -n 2
  fi
  df -h "$ROOT" 2>/dev/null | awk 'NR==2{printf "  [--] disque %s : %s utilises sur %s (%s libres)\n", $6, $3, $2, $4}'

  printf '\n%s : %d defaut(s).\n' "$(date -u +%H:%M:%S)" "$FAULTS"
}

if [ "$ONCE" = 1 ]; then
  dessine
  [ "$FAULTS" -eq 0 ] && exit 0
  exit 1
fi

trap 'printf '\''\nboard: le panneau s arrete.\n'\'' ; exit 0' INT TERM HUP
printf 'board: le panneau de LA, toutes les %s s. Ctrl-C pour sortir.\n' "$WATCH"
while :; do
  clear 2>/dev/null || printf '\033[H\033[J'
  FAULTS=0
  dessine
  sleep "$WATCH" || exit 0
done
