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
# (permanent_section) et la lecture de la TABLE (table_ids, table_block).

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
