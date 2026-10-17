#!/bin/sh
# la.sh — OUVRIR LA (le corps). La porte est ~/.local/bin/la : un VRAI fichier qui exec celui-ci.
#
#   la.sh              reveille les cinq residents, BRANCHE le pont s'il est muet, ouvre LE TABLEAU
#   la.sh --board      seulement le panneau, dans sa fenetre (aucun resident n'est touche)
#   la.sh --once       le panneau UNE fois, ici, en texte (audit ou script) : code = nb de defauts
#   la.sh --help       ce qu'il fait
#
# POURQUOI UNE PORTE ET UN CORPS : `la` doit se taper d'un mot depuis n'importe quel terminal, mais
# ce qui vit dans ~/.local/bin n'est suivi par AUCUN depot. Le travail seme hors de son dossier n'est
# pas fini : le corps vit donc ici, dans le projet, et l'entree n'est qu'un chemin qui s'execute.
# JAMAIS UN LIEN, ni d'un cote ni de l'autre (regle de Moussa).
#
# IL N'INSTALLE RIEN, IL NE SUPPRIME RIEN : il DEMARRE des unites declarees, il BRANCHE le pont,
# il MONTRE, et il sort. Le pont n'ecoute que sur 127.0.0.1 (LA_BRIDGE_ADDRESS) : ouvrir cette porte
# n'expose rien hors de la machine. Pour que le telephone l'atteigne, il faut elargir ADRESSE -- et
# ce jour-la, la porte s'ouvre sur le reseau : c'est une decision, pas un effet de bord.
LC_ALL=C
export LC_ALL

# LA RACINE : la.sh vit dans <racine>/config/engine/ , donc TROIS remontees (engine -> config -> racine).
LA_ROOT=${LA_ROOT:-$(dirname "$(dirname "$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")")")}
PANNEAU="$LA_ROOT/config/py/board.py"
BRIDGE="$LA_ROOT/config/engine/bridge.sh"
RESIDENTS="la-embed la-rerank la-local la-asr la-tts"
# LA FENETRE : un tiers d'un ecran de 1920 (82 colonnes, ~720 pixels). Le tableau EST fait pour
# cette largeur : chaque ligne est batie pour la largeur du moment et coupee si elle ne rentre pas.
# Changer ces deux nombres suffit -- il n'y a rien d'autre a regler ailleurs.
LARGESSE=${LA_BOARD_COLS:-82}
HAUTEUR=${LA_BOARD_LINES:-50}

MODE=tout
case "${1:-}" in
  --board) MODE=board ;;
  --once)  MODE=once ;;
  -h|--help) sed -n '2,10p' "$0" | sed -e 's/^# \{0,1\}//' ; exit 0 ;;
  '') : ;;
  *) printf 'la: je ne connais pas %s (--board, --once)\n' "$1" >&2 ; exit 2 ;;
esac

[ -f "$PANNEAU" ] || { printf 'la: le panneau est absent (%s)\n' "$PANNEAU" >&2 ; exit 2 ; }

if [ "$MODE" = once ]; then
  exec /usr/bin/python3 "$PANNEAU" --once
fi

if [ "$MODE" = tout ]; then
  printf 'LA — ouverture\n'
  # 1. LES RESIDENTS : ce qui porte un modele, et qui repond sur son port.
  if command -v systemctl >/dev/null 2>&1; then
    DORMANTS=
    for u in $RESIDENTS; do
      E=$(systemctl --user is-active "$u.service" 2>/dev/null)
      [ "$E" = active ] || DORMANTS="$DORMANTS $u"
    done
    if [ -n "$DORMANTS" ]; then
      printf '  je reveille :%s\n' "$DORMANTS"
      # shellcheck disable=SC2086
      systemctl --user start $DORMANTS 2>/dev/null
    else
      printf '  les cinq residents tournaient deja\n'
    fi
    A=0
    for u in $RESIDENTS; do
      E=$(systemctl --user is-active "$u.service" 2>/dev/null)
      [ "$E" = active ] && A=$((A + 1))
    done
    printf '  residents actifs : %s sur 5\n' "$A"
    [ "$A" = 5 ] || printf '  ATTENTION : un resident ne demarre pas ; le panneau dira lequel\n'
  else
    printf '  systemctl est absent : les residents ne sont pas touches\n'
  fi
  # 2. LE PONT VERS L'APP : c'est lui que l'app interroge. Il se BRANCHE (demande de Moussa, 17/10).
  #    Il n'ecoute que sur 127.0.0.1 par defaut (LA_BRIDGE_ADDRESS) : ouvrir la porte n'expose RIEN
  #    hors de la machine. `start` se detache lui-meme et rend la main.
  PONT=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:8765/ping 2>/dev/null || true)
  case "$PONT" in
    ''|000)
      if [ -x "$BRIDGE" ]; then
        printf '  le pont vers l app est muet : je le branche\n'
        "$BRIDGE" start 2>&1 | sed -e 's/^/    /'
        sleep 1
        PONT2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:8765/ping 2>/dev/null || true)
        case "$PONT2" in
          ''|000) printf '    il ne repond pas encore : le tableau le dira\n' ;;
          *) printf '    il repond (%s)\n' "$PONT2" ;;
        esac
      elif [ -f "$BRIDGE" ]; then
        printf '  la brique du pont n est PAS executable (droits %s) : chmod +x %s\n' "$(stat -c %a "$BRIDGE" 2>/dev/null)" "$BRIDGE"
      else
        printf '  le pont est muet et sa brique est absente (%s)\n' "$BRIDGE"
      fi ;;
    *) printf '  le pont vers l app repond deja (%s)\n' "$PONT" ;;
  esac
fi

# 3. LE PANNEAU, DANS SA PROPRE FENETRE, ET IL Y RESTE. Une fenetre de 140 colonnes : c'est la
# largeur a laquelle le panneau se met sur deux colonnes au lieu de s'empiler.
if command -v kitty >/dev/null 2>&1; then
  # remember_window_size=no : SANS LUI, kitty rouvre la taille de la DERNIERE fenetre et ignore
  # celle qu'on demande -- c'est la faute qui a fait une fenetre de 164 colonnes.
  setsid kitty --title "LA — le tableau" -o remember_window_size=no \
    -o initial_window_width=${LARGESSE}c \
    -o initial_window_height=${HAUTEUR}c -e /usr/bin/python3 "$PANNEAU" \
    >>"$LA_ROOT/work/board.log" 2>&1 &
  printf '  le tableau s ouvre dans sa fenetre, %s x %s (Ctrl-C dedans pour le fermer)\n' "$LARGESSE" "$HAUTEUR"
  printf '  si jamais il tombait, sa trace est dans work/board.log\n'
else
  printf '  kitty est absent : le panneau reste ici\n'
  exec /usr/bin/python3 "$PANNEAU"
fi
