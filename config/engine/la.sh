#!/bin/sh
# la.sh — OUVRIR LA (le corps). La porte est ~/.local/bin/la : un VRAI fichier qui exec celui-ci.
#
#   la.sh              reveille les cinq residents, dit l'etat du pont, ouvre LE PANNEAU et le laisse
#   la.sh --board      seulement le panneau, dans sa fenetre (aucun resident n'est touche)
#   la.sh --once       le panneau UNE fois, ici, en texte (audit ou script) : code = nb de defauts
#   la.sh --help       ce qu'il fait
#
# POURQUOI UNE PORTE ET UN CORPS : `la` doit se taper d'un mot depuis n'importe quel terminal, mais
# ce qui vit dans ~/.local/bin n'est suivi par AUCUN depot. Le travail seme hors de son dossier n'est
# pas fini : le corps vit donc ici, dans le projet, et l'entree n'est qu'un chemin qui s'execute.
# JAMAIS UN LIEN, ni d'un cote ni de l'autre (regle de Moussa).
#
# IL N'INSTALLE RIEN, IL NE SUPPRIME RIEN, IL N'OUVRE AUCUN PORT : il DEMARRE des unites declarees,
# il MONTRE, et il sort. Le pont vers l'app est un SERVICE RESEAU : `la` dit qu'il est muet et donne
# la commande exacte -- il ne le branche pas tout seul.
LC_ALL=C
export LC_ALL

# LA RACINE : la.sh vit dans <racine>/config/engine/ , donc TROIS remontees (engine -> config -> racine).
LA_ROOT=${LA_ROOT:-$(dirname "$(dirname "$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")")")}
PANNEAU="$LA_ROOT/config/py/board.py"
BRIDGE="$LA_ROOT/config/engine/bridge.sh"
RESIDENTS="la-embed la-rerank la-local la-asr la-tts"

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
  # 2. LE PONT VERS L'APP : c'est lui que l'app interroge. la NE LE DEMARRE PAS : c'est un service
  #    reseau, et l'ouvrir engage la machine. Il le DIT, avec la commande exacte a taper.
  PONT=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:8765/ping 2>/dev/null || true)
  case "$PONT" in
    ''|000)
      if [ -f "$BRIDGE" ]; then
        printf '  le pont vers l app est muet. Pour le brancher : sh %s start\n' "$BRIDGE"
        [ -x "$BRIDGE" ] || printf '    (la brique n est PAS executable -- droits %s -- donc aucune unite ne peut la demarrer telle quelle)\n' "$(stat -c %a "$BRIDGE" 2>/dev/null)"
      else
        printf '  le pont est muet et sa brique est absente (%s)\n' "$BRIDGE"
      fi ;;
    *) printf '  le pont vers l app repond deja (%s)\n' "$PONT" ;;
  esac
fi

# 3. LE PANNEAU, DANS SA PROPRE FENETRE, ET IL Y RESTE. Une fenetre de 140 colonnes : c'est la
# largeur a laquelle le panneau se met sur deux colonnes au lieu de s'empiler.
if command -v kitty >/dev/null 2>&1; then
  setsid kitty --title "LA — le panneau" -o initial_window_width=140c -o initial_window_height=48c \
    -e /usr/bin/python3 "$PANNEAU" >/dev/null 2>&1 &
  printf '  le panneau s ouvre dans sa fenetre et y reste (Ctrl-C dans cette fenetre pour le fermer)\n'
else
  printf '  kitty est absent : le panneau reste ici\n'
  exec /usr/bin/python3 "$PANNEAU"
fi
