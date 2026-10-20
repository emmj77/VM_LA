#!/bin/sh
# french in code is forbidden
# install.sh - LA DEVIENT UN POSTE, EN UNE COMMANDE.
#
#   ./config/install.sh            verifie, pose les unites et l'applet, demarre, passe le docteur
#   ./config/install.sh --check    verifie seulement : ne touche a RIEN, rend le compte
#   ./config/install.sh --no-start pose et lie, mais ne demarre aucun service
#   ./config/install.sh --help
#
# CE QU'IL NE FAIT PAS : il n'installe aucun paquet (pas de sudo, pas d'apt), il ne telecharge
# aucun modele. Il DIT ce qui manque, avec le chemin exact, et il refuse tant que le socle manque.
# Un installateur qui devine est un installateur qui ment.
#
# CE QU'IL POSE, ET RIEN DE PLUS :
#   ~/.config/systemd/user/la-*.service|timer   depuis config/units/*.in (@ROOT@ substitue)
#   ~/.local/bin/la                             la porte (un fichier, jamais un lien)
#   ~/.local/share/applications/la.desktop      l'ENTREE DU MENU : le tableau de bord en appli
#   ~/.local/share/icons/hicolor/scalable/apps/la-app.svg    son icone (une copie)
#   ~/.local/share/cinnamon/applets/LA_Info@moussa   une COPIE (jamais un lien)
#
# POSIX sh (dash) ; aucune dependance hors du socle qu'il verifie lui-meme.

set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONF="$ROOT/config/la_config.yaml"
UNITS_SRC="$ROOT/config/units"
UNITS_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
APPLET_SRC="$ROOT/config/applets/LA_Info@moussa"
APPLET_DST="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets/LA_Info@moussa"
BIN_DST="$HOME/.local/bin"
APPS_DST="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_SRC="$ROOT/config/dashboard/la.svg"
ICON_DST="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/la-app.svg"

MODE=install
case "${1:-}" in
  --check)    MODE=check ;;
  --no-start) MODE=nostart ;;
  --help|-h)  awk 'NR > 1 && /^#/ { sub(/^# ?/, "") ; print ; next } NR > 1 { exit }' "$0" ; exit 0 ;;
  "") ;;
  *) printf 'install: argument inconnu : %s (--check, --no-start, --help)\n' "$1" >&2 ; exit 2 ;;
esac

OK=0 ; WARN=0 ; MISS=0
ok()   { printf '  ok       %s\n' "$1" ; OK=$((OK + 1)) ; }
warn() { printf '  manque   %s\n           %s\n' "$1" "${2:-}" ; WARN=$((WARN + 1)) ; }
hard() { printf '  REFUS    %s\n           %s\n' "$1" "${2:-}" ; MISS=$((MISS + 1)) ; }
titre() { printf '\n%s\n' "$1" ; }
# jeter : corbeille d'abord (rm -rf reste interdit), effacement d'un FICHIER en secours.
jeter() { gio trash "$1" 2>/dev/null && return 0 ; [ -f "$1" ] && rm -f "$1" ; }

# ------------------------------------------------------------------ 1. LE SOCLE
titre "LE SOCLE (sans lui, rien ne tourne)"
for c in dash jq sqlite3 socat curl python3 systemctl; do
  P=$(command -v "$c" 2>/dev/null || true)
  [ -n "$P" ] && ok "$c ($P)" || hard "$c" "il est le socle du moteur ; installez-le (apt install $c)"
done

# ------------------------------------------------------------------ 2. LES INSTRUMENTS
titre "LES INSTRUMENTS (des binaires que des tools appellent)"
for c in tesseract ffmpeg chromium; do
  P=$(command -v "$c" 2>/dev/null || true)
  [ -n "$P" ] && ok "$c ($P)" \
    || warn "$c" "tesseract/ffmpeg : ces tools refuseront ; chromium : l entree du menu retombe sur le navigateur"
done

# ------------------------------------------------------------------ 3. LES BINAIRES RESIDENTS
titre "LES BINAIRES DES RESIDENTS (adresses lues dans $CONF)"
conf() {   # $1 section  $2 cle : la valeur, ou vide (pas de defaut ici : c'est l'installateur)
  sed -n "/^$1:/,/^[^[:space:]]/p" "$CONF" 2>/dev/null \
    | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | head -n 1 \
    | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//'
}
LLAMA_BIN=$(conf llama bin) ; LLAMA_GGUF=$(conf llama gguf)
UV=$(conf tts uv)
ASR_ROOT=$(conf asr root) ; ASR_CLI=$(conf asr cli)

[ -n "$LLAMA_BIN" ] || hard "llama.bin" "la_config ne porte pas llama.bin"
[ -x "$LLAMA_BIN" ] 2>/dev/null && ok "llama-server ($LLAMA_BIN)" \
  || warn "llama-server" "il sert embed, local et rerank ; la_config dit : $LLAMA_BIN"
[ -n "$LLAMA_GGUF" ] && [ -d "$LLAMA_GGUF" ] && ok "le dossier des modeles ($LLAMA_GGUF)" \
  || warn "le dossier des modeles" "la_config dit : ${LLAMA_GGUF:-<vide>}"
[ -n "$UV" ] && [ -x "$UV" ] && ok "uv ($UV)" || warn "uv" "la voix (sherpa-onnx) se lance par uv ; la_config dit : ${UV:-<vide>}"
if [ -n "$ASR_ROOT" ] && [ -x "$ASR_ROOT/$ASR_CLI" ]; then
  ok "l'oreille ($ASR_ROOT/$ASR_CLI)"
else
  warn "l'oreille (NeMo-Speech.cpp)" "la_config dit root=${ASR_ROOT:-<vide>} cli=${ASR_CLI:-<vide>}"
fi

# ------------------------------------------------------------------ 4. LES MODELES
# UN SEUL ROUTEUR (19/10) : les trois noms vivent dans la section `models:`, les fichiers sous
# `models.dir`, et leurs reglages dans le PRESET. Chercher une section `embed:` est une vieille
# lecture -- elle ne trouvait rien et l'installateur annoncait trois modeles absents.
titre "LES MODELES (noms dans la section models:, fichiers sous models.dir)"
MDIR=$(conf models dir) ; [ -n "$MDIR" ] || MDIR="$LLAMA_GGUF"
PRESET=$(conf models preset)
for s in embed rerank local; do
  M=$(conf models "$s")
  if [ -z "$M" ]; then
    warn "$s" "la_config ne nomme aucun modele pour $s (section models)"
  elif [ -n "$MDIR" ] && [ -f "$MDIR/$M.gguf" ]; then
    ok "$s : $M.gguf"
  else
    warn "$s : $M.gguf" "attendu sous ${MDIR:-<dossier inconnu>}"
  fi
  if [ -n "$M" ] && [ -n "$PRESET" ] && [ -f "$ROOT/$PRESET" ] \
     && ! grep -qx "\[$M\]" "$ROOT/$PRESET" 2>/dev/null; then
    warn "$s : $M" "aucune section [$M] dans $PRESET"
  fi
done
AM=$(conf asr model)
if [ -n "$AM" ] && [ -n "$ASR_ROOT" ] && [ -f "$ASR_ROOT/$AM" ]; then
  ok "asr : $AM"
else
  warn "asr : ${AM:-<aucun modele declare>}" "attendu sous ${ASR_ROOT:-<racine inconnue>}"
fi
for f in oww-melspectrogram.onnx oww-embedding_model.onnx oww-hey_jarvis_v0.1.onnx; do
  [ -n "$LLAMA_GGUF" ] && [ -f "$LLAMA_GGUF/$f" ] && ok "veilleur : $f" \
    || warn "veilleur : $f" "sans lui, veille.py ne signe aucune approbation"
done

# ------------------------------------------------------------------ 5. LE COMPTE
printf '\n%s\n' "----------------------------------------------------------"
printf '  %s present(s), %s manquant(s) non bloquant(s), %s refus\n' "$OK" "$WARN" "$MISS"
if [ "$MISS" -gt 0 ]; then
  printf '  INSTALLATION ARRETEE : le socle manque. Rien n a ete pose.\n'
  exit 2
fi
if [ "$MODE" = check ]; then
  printf '  --check : rien n a ete pose, rien n a ete demarre.\n'
  [ "$WARN" -eq 0 ] && exit 0 || exit 1
fi

# ------------------------------------------------------------------ 6. LES UNITES
titre "LES UNITES (config/units/*.in -> $UNITS_DST)"
command -v systemctl >/dev/null 2>&1 || { printf '  REFUS : systemctl absent\n' ; exit 2 ; }
if ! systemctl --user show-environment >/dev/null 2>&1; then
  printf '  REFUS : la session systemd --user ne repond pas (XDG_RUNTIME_DIR absent ?)\n' ; exit 2
fi
mkdir -p "$UNITS_DST" || { printf '  REFUS : %s ne se cree pas\n' "$UNITS_DST" ; exit 2 ; }
N=0
for F in "$UNITS_SRC"/la-*.in; do
  [ -f "$F" ] || continue
  T="$UNITS_DST/$(basename "$F" .in)"
  sed "s|@ROOT@|$ROOT|g" "$F" > "$T" && N=$((N + 1))
done
printf '  %s unite(s) posee(s)\n' "$N"

# LES UNITES MORTES : un la-*.service qui nomme cette racine et dont le modele a quitte le depot
# est un residu d'une version precedente. Il est retire, jamais laisse a tourner.
for U in "$UNITS_DST"/la-*.service "$UNITS_DST"/la-*.timer; do
  [ -f "$U" ] || continue
  B=$(basename "$U")
  [ -f "$UNITS_SRC/$B.in" ] && continue
  grep -qF -- "$ROOT" "$U" || continue
  systemctl --user disable --now "$U" >/dev/null 2>&1 || true
  jeter "$U" 2>/dev/null && printf '  retire   %s (plus dans le depot)\n' "$B"
done
systemctl --user daemon-reload || { printf '  REFUS : daemon-reload a echoue\n' ; exit 2 ; }

if [ "$MODE" = install ]; then
  for U in la-models la-tts la-asr la-dash; do
    systemctl --user enable --now "$U" >/dev/null 2>&1 \
      && printf '  demarre  %s\n' "$U" \
      || printf '  ECHEC    %s (journalctl --user -u %s -n 20)\n' "$U" "$U"
  done
  systemctl --user enable --now la-audio-purge.timer >/dev/null 2>&1 \
    && printf '  demarre  la-audio-purge.timer\n' \
    || printf '  ECHEC    la-audio-purge.timer\n'
fi

# ------------------------------------------------------------------ 7. LA PORTE
titre "LA PORTE ($BIN_DST/la, un fichier)"
mkdir -p "$BIN_DST" 2>/dev/null
cat > "$BIN_DST/la" <<EOF
#!/bin/sh
# la — LE POINT D'ENTREE DE LA. Une porte : elle resout le chemin et execute le corps, qui vit
# DANS le projet (config/engine/la.sh) et que git suit.
# CE FICHIER EST POSE PAR install.sh : le modifier ici, c'est le perdre au prochain install.
#
#   la            les residents, l'etat du pont, et le panneau
#   la --app      LA EN APPLICATION : la page du poste dans sa fenetre
#   la --board    le panneau dans sa fenetre
#   la --once     le panneau une fois, ici (code de retour = nombre de defauts)
LA_ROOT=\${LA_ROOT:-$ROOT}
CORPS="\$LA_ROOT/config/engine/la.sh"
[ -f "\$CORPS" ] || { printf 'la: le corps est absent (%s)\n' "\$CORPS" >&2 ; exit 2 ; }
exec /bin/sh "\$CORPS" "\$@"
EOF
if chmod +x "$BIN_DST/la" 2>/dev/null; then printf '  posee    %s\n' "$BIN_DST/la" ; else printf '  ECHEC    %s\n' "$BIN_DST/la" ; fi
case ":$PATH:" in
  *":$BIN_DST:"*) ;;
  *) printf '  attention %s n est pas dans le PATH\n' "$BIN_DST" ;;
esac

# ------------------------------------------------------------------ 8. L'APPLICATION
titre "L'APPLICATION (le tableau de bord :8770 dans une fenetre, pas une UI de plus)"
mkdir -p "$APPS_DST" "$(dirname "$ICON_DST")" 2>/dev/null
if [ -f "$ICON_SRC" ]; then
  cp -f "$ICON_SRC" "$ICON_DST" && printf '  icone    %s\n' "$ICON_DST" \
    || printf '  ECHEC    la copie de l icone (%s)\n' "$ICON_SRC"
  # UNE ICONE SANS INDEX N EXISTE PAS POUR LE MENU : ~/.local/share/icons n est un theme que s il
  # porte son index.theme. Sans lui (ni cache a jour), le menu affiche un point d interrogation --
  # c est exactement ce qui est arrive le 19/10 avec la-app.svg pourtant pose.
  HICOLOR=$(dirname "$(dirname "$(dirname "$ICON_DST")")")
  mkdir -p "$HICOLOR" 2>/dev/null
  if [ ! -f "$HICOLOR/index.theme" ] && [ -f /usr/share/icons/hicolor/index.theme ]; then
    cp -f /usr/share/icons/hicolor/index.theme "$HICOLOR/index.theme" 2>/dev/null \
      && printf '  index    %s\n' "$HICOLOR/index.theme"
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$HICOLOR" >/dev/null 2>&1 \
      && printf '  cache    %s\n' "$HICOLOR/icon-theme.cache" \
      || printf '  note     le cache d icones n a pas pu etre refait (%s)\n' "$HICOLOR"
  fi
else
  printf '  manque   %s (l entree aura l icone du theme)\n' "$ICON_SRC"
fi
cat > "$APPS_DST/la.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=LA
GenericName=Poste local
Comment=LA — le tableau de bord du poste (:8770), ouvert comme une application
Comment[fr]=LA — le tableau de bord du poste (:8770), ouvert comme une application
Exec=$BIN_DST/la --app
Icon=la-app
Terminal=false
StartupNotify=true
StartupWMClass=LA
Categories=Development;
Keywords=LA;dashboard;tableau;agent;skill;projet;
EOF
chmod 644 "$APPS_DST/la.desktop" 2>/dev/null
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$APPS_DST/la.desktop" && printf '  entree   %s\n' "$APPS_DST/la.desktop" \
    || printf '  ECHEC    desktop-file-validate refuse %s\n' "$APPS_DST/la.desktop"
else
  printf '  entree   %s (desktop-file-validate absent)\n' "$APPS_DST/la.desktop"
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DST" >/dev/null 2>&1

# L'ANCIENNE ENTREE EST MORTE : elle lance config/py/dash-open.sh, absent du depot (le serveur
# vit dans config/programs/dash.py). Une entree qui ne lance rien n'est pas une entree.
if [ -f "$APPS_DST/la-dashboard.desktop" ] && grep -q 'dash-open.sh' "$APPS_DST/la-dashboard.desktop"; then
  jeter "$APPS_DST/la-dashboard.desktop" 2>/dev/null \
    && printf '  retire   la-dashboard.desktop (il lance un script absent)\n'
fi

# ------------------------------------------------------------------ 9. L'APPLET
titre "L'APPLET (une COPIE, jamais un lien)"
if [ -d "$APPLET_SRC" ]; then
  if [ -d "$(dirname "$APPLET_DST")" ]; then
    mkdir -p "$APPLET_DST"
    cp -Rf "$APPLET_SRC"/. "$APPLET_DST"/ 2>/dev/null && printf '  posee    %s\n' "$APPLET_DST" \
      || printf '  ECHEC    la copie vers %s\n' "$APPLET_DST"
    printf '  a faire  clic droit sur le tableau de bord > Applets > recharger LA_Info\n'
  else
    printf '  passee   Cinnamon absent : aucune applet posee\n'
  fi
else
  printf '  passee   %s absent du depot\n' "$APPLET_SRC"
fi

# ------------------------------------------------------------------ 8. LE DOCTEUR
titre "LE DOCTEUR"
if [ "$MODE" != nostart ]; then
  sleep 3
  "$ROOT/config/engine/doctor.sh" --short 2>&1 | tail -n 2
  printf '  (le detail : %s/config/engine/doctor.sh)\n' "$ROOT"
else
  printf '  --no-start : aucun service demarre, le docteur attend son tour\n'
fi
