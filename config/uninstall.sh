#!/bin/sh
# french in code is forbidden
# uninstall.sh - LA QUITTE LE POSTE : ce qu'il a pose, il le reprend.
#
#   ./config/uninstall.sh            arrete, desactive, retire les unites, la porte `la` et l'applet
#   ./config/uninstall.sh --check    dit ce qui partirait ; ne touche a RIEN
#   ./config/uninstall.sh --help
#
# CE QU'IL NE TOUCHE PAS, ET POURQUOI :
#   le depot (lui-meme)         c'est la sauvegarde ; git s'en occupe
#   config/state, config/*.db   journaux, pid, memoire : des DONNEES, pas une installation
#   ~/LLM_GGUF                  les modeles ne sont pas a LA ; les retirer demanderait un mot
#
# LA REGLE D'APPARTENANCE, la meme que install.sh : une unite de ~/.config/systemd/user est a LA
# si son modele vit dans config/units/, ou si elle NOMME cette racine. Rien d'autre ne part : ni
# une unite d'un autre projet, ni une unite ecrite a la main.
#
# POSIX sh (dash). gio met a la corbeille ; systemctl gere les unites.

set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
UNITS_SRC="$ROOT/config/units"
UNITS_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
APPLET_DST="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets/LA_Info@moussa"
BIN_DST="$HOME/.local/bin"
APPS_DST="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DST="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/la-app.svg"

MODE=remove
case "${1:-}" in
  --check)   MODE=check ;;
  --help|-h) sed -n '2,19p' "$0" | sed -e 's/^# \{0,1\}//' ; exit 0 ;;
  "") ;;
  *) printf 'uninstall: argument inconnu : %s (--check, --help)\n' "$1" >&2 ; exit 2 ;;
esac

titre() { printf '\n%s\n' "$1" ; }

# jeter : corbeille d'abord (rm -rf est interdit ici), effacement d'un FICHIER en secours.
jeter() {
  gio trash "$1" 2>/dev/null && return 0
  [ -f "$1" ] || return 1
  rm -f "$1"
}

# les unites qui appartiennent a cette racine
units_de_la() {
  for U in "$UNITS_DST"/la-*.service "$UNITS_DST"/la-*.timer; do
    [ -f "$U" ] || continue
    B=$(basename "$U")
    if [ -f "$UNITS_SRC/$B.in" ] || grep -qF -- "$ROOT" "$U"; then
      printf '%s\n' "$U"
    fi
  done
}

# ------------------------------------------------------------------ 1. L'INVENTAIRE
titre "CE QUI APPARTIENT A CETTE RACINE ($ROOT)"
LISTE=$(units_de_la)
N=0
while IFS= read -r U; do
  [ -n "$U" ] || continue
  N=$((N + 1))
  ET=$(systemctl --user is-active "$U" 2>/dev/null || true)
  EN=$(systemctl --user is-enabled "$U" 2>/dev/null || true)
  printf '  unite    %-24s %s / %s\n' "$(basename "$U")" "${ET:-inconnu}" "${EN:-inconnu}"
done <<EOF
$LISTE
EOF
[ "$N" -eq 0 ] && printf '  (aucune : rien a retirer de ce cote)\n'

APPLET=non ; [ -d "$APPLET_DST" ] && APPLET=oui
ENTREE=non ; [ -f "$APPS_DST/la.desktop" ] && ENTREE=oui
ICONE=non ; [ -f "$ICON_DST" ] && ICONE=oui
PORTE=non
if [ -f "$BIN_DST/la" ] && grep -q '^LA_ROOT=' "$BIN_DST/la" 2>/dev/null \
   && grep -qF -- "$ROOT" "$BIN_DST/la" 2>/dev/null; then PORTE=oui ; fi
printf '  porte    %-24s %s\n' "$BIN_DST/la" "$PORTE"
printf '  entree   %-24s %s\n' "la.desktop" "$ENTREE"
printf '  icone    %-24s %s\n' "la-app.svg" "$ICONE"
printf '  applet   %-24s %s\n' "LA_Info@moussa" "$APPLET"

if [ "$MODE" = check ]; then
  printf '\n%s\n' "----------------------------------------------------------"
  printf '  --check : %s unite(s), porte=%s, entree=%s, icone=%s, applet=%s. Rien n a ete touche.\n' \
    "$N" "$PORTE" "$ENTREE" "$ICONE" "$APPLET"
  printf '  LAISSE (donnees, pas installation) : config/state, config/*.db, ~/LLM_GGUF\n'
  exit 0
fi

# ------------------------------------------------------------------ 2. L'ARRET
titre "L'ARRET (stop, puis disable : une unite desactivee ne revient pas au login)"
while IFS= read -r U; do
  [ -n "$U" ] || continue
  systemctl --user stop "$U"    >/dev/null 2>&1 || true
  systemctl --user disable "$U" >/dev/null 2>&1 || true
  if systemctl --user is-active "$U" >/dev/null 2>&1; then
    printf '  ECHEC    %s tient encore (journalctl --user -u %s -n 20)\n' "$(basename "$U")" "$(basename "$U" .service)"
  else
    printf '  arretee  %s\n' "$(basename "$U")"
  fi
done <<EOF
$LISTE
EOF

# ------------------------------------------------------------------ 3. LES FICHIERS
titre "LES FICHIERS (corbeille : ce qui a ete pose se reprend)"
while IFS= read -r U; do
  [ -n "$U" ] || continue
  if jeter "$U"; then
    printf '  retire   %s\n' "$(basename "$U")"
  else
    printf '  REFUS    %s (retirez-le a la main : gio trash %s)\n' "$(basename "$U")" "$U"
  fi
  systemctl --user reset-failed "$(basename "$U")" >/dev/null 2>&1 || true
done <<EOF
$LISTE
EOF

if [ "$PORTE" = oui ]; then
  jeter "$BIN_DST/la" && printf '  retire   %s\n' "$BIN_DST/la" \
    || printf '  REFUS    %s (gio trash %s)\n' "$BIN_DST/la" "$BIN_DST/la"
elif [ -f "$BIN_DST/la" ]; then
  printf '  laissee  %s (elle ne vient pas de cette racine)\n' "$BIN_DST/la"
fi

if [ "$ENTREE" = oui ]; then
  jeter "$APPS_DST/la.desktop" && printf '  retiree  %s\n' "$APPS_DST/la.desktop" \
    || printf '  REFUS    %s (gio trash %s)\n' "$APPS_DST/la.desktop" "$APPS_DST/la.desktop"
fi
if [ "$ICONE" = oui ]; then
  jeter "$ICON_DST" && printf '  retiree  %s\n' "$ICON_DST" \
    || printf '  REFUS    %s (gio trash %s)\n' "$ICON_DST" "$ICON_DST"
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DST" >/dev/null 2>&1
# le menu relit ses icones : sans ce cache refait, l entree garde son point d interrogation
HICOLOR_UN=$(dirname "$(dirname "$(dirname "$ICON_DST")")")
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$HICOLOR_UN" >/dev/null 2>&1
true

if [ "$APPLET" = oui ]; then
  if gio trash "$APPLET_DST" 2>/dev/null; then
    printf '  retiree  %s\n' "$APPLET_DST"
  else
    printf '  REFUS    %s (retirez-la a la main : gio trash %s)\n' "$APPLET_DST" "$APPLET_DST"
  fi
else
  printf '  passee   applet absente\n'
fi

command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1 || true

# ------------------------------------------------------------------ 4. LE COMPTE
printf '\n%s\n' "----------------------------------------------------------"
printf '  %s unite(s) reprise(s), porte=%s, applet=%s\n' "$N" "$PORTE" "$APPLET"
printf '  Reste, et c est voulu : le depot, config/state, config/*.db, ~/LLM_GGUF\n'
printf '  Pour revenir : %s/config/install.sh\n' "$ROOT"
