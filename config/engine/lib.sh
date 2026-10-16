#!/bin/sh
# lib.sh — LA BIBLIOTHEQUE COMMUNE DES BRIQUES (config/engine/).
#
# CONVENTION ANGLAISE OBLIGATOIRE : tout IDENTIFIANT et tout NOM de ressource (cle, champ,
# fichier) s'ecrit en ANGLAIS. La PROSE (commentaires, messages pour l'humain) reste en francais.
#
# Chaque brique la charge en tete, APRES avoir pose $ROOT :
#   . "$HERE/lib.sh"
# Elle porte ce que les briques partagent, UNE fois : l horodatage (ts), la resolution
# unique du SKILL ACTIF (active_skill), la lecture de la categorie PERMANENTE
# (permanent_section), la lecture de la TABLE (table_ids, table_block) et le tronc
# commun des services detaches (service_ctl).

# --- L HORODATAGE --------------------------------------------------------------
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- LA SKILL ACTIVE : resolution UNIQUE ---------------------------------------
# Lit $ROOT/skills/.active (premiere ligne = nom du dossier de la skill active), verifie
# qu un dossier REEL le porte sous skills/ (avec un skill.yaml), sinon retombe sur `la` et
# le DIT sur stderr. Un nom ne sort jamais de skills/ (refuse / et ..). Jamais un lien.
# Pose : NAME (le nom) et SKILL (le chemin de son skill.yaml).
active_skill() {
  SKILLS_DIR="$ROOT/skills"
  ACTIVE_FILE="$SKILLS_DIR/.active"
  NAME=
  if [ -L "$ACTIVE_FILE" ]; then
    printf 'skills: the state file is a LINK (%s) ; links are forbidden ; falling back to la\n' "$ACTIVE_FILE" >&2
  elif [ ! -f "$ACTIVE_FILE" ]; then
    printf 'skills: the state file is MISSING (%s) ; falling back to la\n' "$ACTIVE_FILE" >&2
  else
    NAME=$(sed -n '1p' "$ACTIVE_FILE" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$NAME" in
      '') printf 'skills: the state file is EMPTY (%s) ; falling back to la\n' "$ACTIVE_FILE" >&2 ; NAME= ;;
      */*|*..*) printf 'skills: skill NAME REFUSED (%s) ; a name carries no / nor .. and never leaves skills/ ; falling back to la\n' "$NAME" >&2 ; NAME= ;;
      *) [ -d "$SKILLS_DIR/$NAME" ] && [ -f "$SKILLS_DIR/$NAME/skill.yaml" ] || { printf 'skills: skill %s has NO DIR under skills/ ; falling back to la\n' "$NAME" >&2 ; NAME= ; } ;;
    esac
  fi
  [ -n "$NAME" ] || NAME=la
  SKILL="$SKILLS_DIR/$NAME/skill.yaml"
}

# --- LA CATEGORIE PERMANENTE ---------------------------------------------------
# Lit la section `permanent:` de la CONFIG ($1), une entree par ligne, l indentation et
# les guillemets retires.
permanent_section() {
  CONF=${1:-}
  [ -n "$CONF" ] && [ -f "$CONF" ] || return 0
  sed -n '/^permanent:/,/^[^[:space:]]/p' "$CONF" \
    | sed -n 's/^[[:space:]]*-[[:space:]]*//p' \
    | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' | grep -v '^$'
}

# --- LA TABLE ------------------------------------------------------------------
# table_ids — tous les ids de la table ($1), dans l ordre.
table_ids() {
  grep -n '^  - id: ' "$1" | sed 's/^[0-9]*:  - id:[[:space:]]*//' | tr -d ' '
}
# table_block — le bloc de l id ($2) dans la table ($1) ; vide + rc=1 si absent.
table_block() {
  TB_TABLE=${1:-}
  TB_ID=${2:-}
  [ -f "$TB_TABLE" ] || return 1
  TB_START=$(grep -n "^  - id: $TB_ID[[:space:]]*\$" "$TB_TABLE" 2>/dev/null | head -n 1 | cut -d: -f1)
  [ -n "$TB_START" ] || return 1
  TB_END=$(grep -n '^  - id: ' "$TB_TABLE" | cut -d: -f1 | while IFS= read -r n; do
        [ "$n" -gt "$TB_START" ] && { printf '%s\n' "$n"; break; }
      done)
  [ -n "$TB_END" ] || TB_END=$(( $(wc -l < "$TB_TABLE") + 1 ))
  sed -n "${TB_START},$((TB_END - 1))p" "$TB_TABLE"
}

# --- LES SERVICES DETACHES : le tronc commun -----------------------------------
# start | stop | status | run | help, partages par les services qui restent DEBOUT.
# L appelant pose LABEL, PID_FILE, LOGF, PORT, HEALTH et WD (le dossier de lancement),
# puis : service_ctl "${1:-help}" <la commande de fond...>
#   run    au premier plan (systemd), depuis WD. Ne rend jamais la main.
#   start  detache la commande, ecrit sa marque (PID_FILE).
#   stop   arrete le pid de sa marque. JAMAIS par motif : on ne tue que ce qu'on a pose.
#   status interroge HEALTH sur le port.
service_ctl() {
  SC_MODE=$1 ; shift
  case "$SC_MODE" in
    run) cd "$WD" || exit 1 ; exec "$@" ;;
    start)
      if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "$LABEL tourne deja (pid $(cat "$PID_FILE"), port $PORT)" ; exit 0
      fi
      ( cd "$WD" && nohup "$@" >> "$LOGF" 2>&1 & echo $! > "$PID_FILE" )
      echo "$LABEL lance (pid $(cat "$PID_FILE"), port $PORT, journal $LOGF)"
      ;;
    stop)
      if [ ! -f "$PID_FILE" ]; then echo "$LABEL ne tourne pas : aucune marque" ; exit 0 ; fi
      SC_P=$(cat "$PID_FILE")
      if kill "$SC_P" 2>/dev/null; then echo "$LABEL arrete (pid $SC_P)" ; else echo "$LABEL ne repondait plus (pid $SC_P)" ; fi
      rm -f "$PID_FILE"
      ;;
    status)
      SC_R=$(curl -s --max-time 3 "http://127.0.0.1:$PORT/$HEALTH" 2>/dev/null)
      if [ -n "$SC_R" ]; then echo "$LABEL debout sur 127.0.0.1:$PORT : $SC_R" ; else echo "$LABEL muet sur 127.0.0.1:$PORT" ; exit 1 ; fi
      ;;
    *) echo "modes : start | stop | status | run | help" ;;
  esac
}
