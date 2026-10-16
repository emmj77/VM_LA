#!/bin/sh
# engine_switch.sh - LE MANAGER DES ADRESSES (config/engine/engine_switch.sh).
#
# POURQUOI IL EXISTE. config/la_config.yaml porte les ADRESSES des engines, et UNE SEULE
# d'entre elles porte `active: "true"`. Le canon dit qu'une declaration se change "par un
# outil de la station, JAMAIS a la main, JAMAIS par le modele" : ce script EST cet outil.
# Il tient la section `engines` : il la LIT (list) et il en change le mot `active`
# (take <alias>) - rien d'autre, et aucune autre section.
#
# CE QU'IL NE FAIT PAS. Il n'ecrit aucune valeur de secret (le fichier ne porte que des
# NOMS de variables), il n'affiche aucune adresse de provider, il ne cree rien.
#
# L'ECRITURE EST ATOMIQUE ET VERIFIEE. Un temporaire, puis un renommage. Avant le
# renommage : le nombre de lignes n'a pas bouge, et il reste EXACTEMENT une adresse active.
# Sinon rien n'est ecrit et la raison est nommee.
#
# MODES : list | take <alias> | help

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
CFG=${LA_CONFIG_FILE:-"$ROOT/config/la_config.yaml"}

refuse_cli() { printf '%s\n' "$1" >&2 ; exit 1 ; }
# la bibliotheque commune (ts, active_skill) : UNE definition, pas une copie par brique.
[ -f "$HERE/lib.sh" ] || refuse_cli "the common library is missing ($HERE/lib.sh)"
. "$HERE/lib.sh"

# les adresses declarees, en TSV : provider, alias, model, active
read_engines() {
  awk '
    /^engines:[[:space:]]*$/ { dans = 1 ; next }
    dans && /^[^[:space:]#]/ { dans = 0 }
    dans && /^  - provider:/ {
      if (vu) { print f "\t" a "\t" m "\t" act }
      vu = 1 ; f = $3 ; a = "" ; m = "" ; act = "false" ; next
    }
    dans && /^    alias:/     { a = $2 ; next }
    dans && /^    model:/     { m = $2 ; next }
    dans && /^    active:/    { act = $2 ; gsub(/"/, "", act) ; next }
    END { if (vu) { print f "\t" a "\t" m "\t" act } }
  ' "$CFG"
}

[ -f "$CFG" ] || refuse_cli "refuse : la config des adresses est introuvable ($CFG)"
[ -r "$CFG" ] || refuse_cli "refuse : la config des adresses est illisible ($CFG)"

MODE=${1:-help}

case "$MODE" in
  list)
    read_engines | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t"))
      | map({provider: .[0], alias: .[1], model: .[2], active: (.[3] == "true")})' \
      || refuse_cli 'refuse : les adresses n ont pas pu etre lues'
    exit 0
    ;;

  take)
    ALIAS=${2:-}
    [ -n "$ALIAS" ] || refuse_cli 'refuse : take veut un alias (take <alias>) ; list les donne'
    case "$ALIAS" in *[!a-zA-Z0-9_-]*) refuse_cli "refuse : alias hors form ($ALIAS) ; lettres, chiffres, tiret et souligne" ;; esac
    [ -w "$CFG" ] || refuse_cli "refuse : la config des adresses n est pas inscriptible ($CFG)"
    if ! read_engines | cut -f2 | grep -qx -- "$ALIAS"; then
      refuse_cli "refuse : aucune adresse declaree ne porte l alias $ALIAS ; la config en porte : $(read_engines | cut -f2 | tr '\n' ' ')"
    fi

    TD=$(mktemp -d "${TMPDIR:-/tmp}/engine_switch.XXXXXX") || refuse_cli 'refuse : aucun espace temporaire'
    trap 'rm -f "$TD/neuf"; rmdir "$TD" 2>/dev/null' EXIT INT TERM HUP

    BEFORE=$(wc -l < "$CFG" | tr -d ' ')
    awk -v cible="$ALIAS" '
      /^engines:[[:space:]]*$/ { dans = 1 ; print ; next }
      dans && /^[^[:space:]#]/  { dans = 0 }
      dans && /^    alias:/    { a = $2 }
      dans && /^    active:/   {
        if (a == cible) { print "    active: \"true\"" } else { print "    active: \"false\"" }
        next
      }
      { print }
    ' "$CFG" > "$TD/neuf" || refuse_cli "refuse : le montage des adresses a echoue"
    [ -s "$TD/neuf" ] || refuse_cli 'refuse : le montage des adresses n a rien ecrit'

    AFTER=$(wc -l < "$TD/neuf" | tr -d ' ')
    [ "$BEFORE" = "$AFTER" ] || refuse_cli "refuse : le montage a change le nombre de lignes ($BEFORE -> $AFTER) ; rien n est ecrit"

    NACT=$(grep -c '^    active: "true"$' "$TD/neuf" | tr -d ' ')
    [ "$NACT" = 1 ] || refuse_cli "refuse : il resterait $NACT adresse(s) active(s) ; il en faut exactement une ; rien n est ecrit"

    OTHER=$(grep -vcE '^    active: ' "$TD/neuf" | tr -d ' ')
    EXPECTED=$(grep -vcE '^    active: ' "$CFG" | tr -d ' ')
    [ "$OTHER" = "$EXPECTED" ] || refuse_cli 'refuse : une ligne hors active a bouge ; rien n est ecrit'

    mv -f "$TD/neuf" "$CFG" || refuse_cli "refuse : ecriture impossible ($CFG)"
    printf 'l adresse active est %s (%s)\n' "$ALIAS" "$(ts)"
    exit 0
    ;;

  help|*)
    sed -n '2,24p' "$0"
    ;;
esac
