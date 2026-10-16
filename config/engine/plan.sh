#!/bin/sh
# plan.sh - LE PLAN VIT DANS LE SKILL (config/engine/plan.sh).
#
# OU VIT LE PLAN : dans la section PLAN: du skill ACTIF, c est-a-dire $SKROOT/skill.yaml.
# Il n y a plus de dossier de plans, plus de fichier par plan : le plan est une SUITE DE
# LIGNES INDEXEES du skill, comme le reste de sa matiere. Les lignes d un plan portent les
# numeros 4xx (401 pour le premier point, et ainsi de suite) : c est la centaine du PLAN.
#
# LA FORME D UNE LIGNE DE PLAN (la meme que toute ligne de skill : au plus 100 octets)
#   401: "[todo] ouvrir le fichier"
#   402: "[doing] le relire"
#   403: "[complete] poser la ligne"
# et la PREMIERE ligne du plan, 400, porte le but :
#   400: "PLAN <nom> : <but>"
#
# LES ETATS, et rien d autre : todo, doing, complete. advance ne bouge QUE le premier point
# qui n est pas complete, et d UN SEUL etat a la fois (jamais todo -> complete d un coup).
#
# LE POINT DE NETTOYAGE : le plan l AJOUTE LUI-MEME en dernier a l ouverture, et close_plan
# REFUSE de fermer un plan dont le dernier point n est pas celui-la.
#
# LES SOUS-COMMANDES (une par outil de la table)
#   start <nom> <but>   ouvre un plan ; les points arrivent un par ligne sur l entree standard
#   load                rend le plan ouvert, ou dit qu il n y en a pas
#   advance             avance le premier point non complete, d un seul etat
#   revise <motif>      reecrit les points NON FRANCHIS ; les points complete ne bougent pas
#   close <motif>       ferme le plan (sa section redevient vide) ; refuse si le dernier
#                       point n est pas le point de nettoyage
#   abort <motif>       ferme le plan en l interrompant
#
# LE REFUS : une seule ligne, code 1, RIEN d ecrit dans le skill. POSIX sh (dash), ASCII,
# sans accent grave. Les ecritures sont atomiques (fichier temporaire puis mv).

LC_ALL=C
export LC_ALL

TARGET=${PLAN_FILE:-${SKROOT:+$SKROOT/skill.yaml}}
[ -n "$TARGET" ] || { echo 'refuse : le skill actif est inconnu (SKROOT est vide) ; le plan ne sait pas ou vivre' >&2 ; exit 1 ; }
[ -f "$TARGET" ] || { echo "refuse : le skill actif est introuvable ($TARGET)" >&2 ; exit 1 ; }
[ -w "$TARGET" ] || { echo "refuse : le skill actif n est pas inscriptible ($TARGET)" >&2 ; exit 1 ; }

START=$(grep -n '^PLAN:[[:space:]]*$' "$TARGET" | head -n 1 | cut -d: -f1)
[ -n "$START" ] || START=$(grep -n '^PLAN:' "$TARGET" | head -n 1 | cut -d: -f1)
[ -n "$START" ] || { echo 'refuse : le skill actif ne porte pas de section PLAN:' >&2 ; exit 1 ; }
END_POS=$(awk -v d="$START" 'NR > d && /^[^[:space:]]/ { print NR; exit }' "$TARGET")
TOTAL=$(wc -l < "$TARGET")
END_POS=${END_POS:-$((TOTAL + 1))}

# les lignes du plan, telles qu elles sont (2 espaces, un numero, deux points, le texte entre guillemets)
lines() { sed -n "$((START + 1)),$((END_POS - 1))p" "$TARGET" | grep -E '^  [0-9]{3}: "' ; }
text()  { printf '%s' "$1" | sed -e 's/^  [0-9][0-9][0-9]: "//' -e 's/"$//' ; }
state()   { printf '%s' "$1" | sed -n 's/^\[\([a-z]*\)\].*/\1/p' ; }

# reecrire la section : les nouvelles lignes arrivent sur l entree standard
rewrite() {
  T=$(mktemp "${TMPDIR:-/tmp}/plan.XXXXXX") || { echo 'refuse : aucun espace temporaire' >&2 ; exit 1 ; }
  trap 'rm -f "$T"' EXIT INT TERM HUP
  # ce qui PRECEDE la section (l en-tete PLAN: compris), PUIS les nouvelles lignes, PUIS le
  # reste du skill. Le plan doit atterrir DANS sa section, jamais a la fin du fichier.
  {
    awk -v d="$START" 'NR <= d { print }' "$TARGET"
    cat
    awk -v f="$END_POS" 'NR >= f { print }' "$TARGET"
  } > "$T" || { echo 'refuse : la lecture du skill a echoue' >&2 ; exit 1 ; }
  [ -s "$T" ] || { echo 'refuse : la reecriture a rendu un fichier vide ; rien n a ete touche' >&2 ; exit 1 ; }
  mv -f "$T" "$TARGET" || { echo 'refuse : l ecriture dans le skill a echoue' >&2 ; exit 1 ; }
}

# poser une section PLAN: vide (les cas close et abort)
clear() {
  T=$(mktemp "${TMPDIR:-/tmp}/plan.XXXXXX") || { echo 'refuse : aucun espace temporaire' >&2 ; exit 1 ; }
  trap 'rm -f "$T"' EXIT INT TERM HUP
  awk -v d="$START" -v f="$END_POS" 'NR <= d || NR >= f { print }' "$TARGET" > "$T" || { echo 'refuse : la lecture du skill a echoue' >&2 ; exit 1 ; }
  mv -f "$T" "$TARGET" || { echo 'refuse : l ecriture dans le skill a echoue' >&2 ; exit 1 ; }
}

# combien de lignes de plan, et combien de points non complete
N_LINES=$(lines | wc -l | tr -d ' ')
N_OPEN=$(lines | grep -c '\[todo\]\|\[doing\]' | tr -d ' ')
PLAN_OPEN=0
[ "$N_OPEN" -gt 0 ] && PLAN_OPEN=1

point_status() { printf '%s' "$1" | sed -e 's/^\[[a-z]*\][[:space:]]*//'; }

mode=${1:-}
case "$mode" in
  start)
    NAME=${2:-}
    GOAL=${3:-}
    [ -n "$NAME" ] || { echo 'refuse : start veut un nom de plan' >&2 ; exit 1 ; }
    [ -n "$GOAL" ] || { echo 'refuse : start veut un but (ce que la tache doit produire)' >&2 ; exit 1 ; }
    SLUG=$(printf '%s' "$NAME" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//')
    [ -n "$SLUG" ] || { echo 'refuse : le nom ne donne aucun slug (minuscules, chiffres, tirets)' >&2 ; exit 1 ; }
    [ "$PLAN_OPEN" = 0 ] || { echo "refuse : un plan est deja ouvert dans $TARGET ; un seul plan est actif a la fois" >&2 ; exit 1 ; }
    N=400
    TMPL=$(mktemp "${TMPDIR:-/tmp}/planl.XXXXXX") || { echo 'refuse : aucun espace temporaire' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL"' EXIT INT TERM HUP
    HEAD=$(printf 'PLAN %s : %s' "$SLUG" "$GOAL")
    [ $(( ${#HEAD} + 12 )) -le 100 ] || { echo "refuse : le but est trop long pour une ligne de skill ($(( ${#HEAD} + 12 )) octets, 100 au plus)" >&2 ; exit 1 ; }
    printf '  %s: "%s"\n' "$N" "$HEAD" > "$TMPL"
    while IFS= read -r L || [ -n "$L" ]; do
      [ -n "$L" ] || continue
      N=$((N + 1))
      [ $(( ${#L} + 20 )) -le 100 ] || { echo "refuse : un point depasse la ligne de skill ($(( ${#L} + 20 )) octets, 100 au plus) : $L" >&2 ; exit 1 ; }
      printf '  %s: "[todo] %s"\n' "$N" "$L" >> "$TMPL"
    done
    [ "$N" -gt 400 ] || { echo 'refuse : start veut au moins un point, un par ligne sur l entree standard' >&2 ; exit 1 ; }
    # LE POINT DE NETTOYAGE, ajoute par le plan lui-meme, en dernier
    N=$((N + 1))
    printf '  %s: "[todo] NETTOYAGE : ranger le travail, rien ne reste seme"\n' "$N" >> "$TMPL"
    rewrite < "$TMPL"
    echo "plan ouvert dans $TARGET ($((N - 400)) points)"
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  load)
    if [ "$N_LINES" = 0 ]; then
      echo 'aucun plan ouvert : le skill actif ne porte aucun plan dans sa section PLAN:'
      exit 0
    fi
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  advance)
    [ "$PLAN_OPEN" = 1 ] || { echo 'refuse : aucun plan ouvert a avancer' >&2 ; exit 1 ; }
    TMPL=$(mktemp "${TMPDIR:-/tmp}/plana.XXXXXX") || { echo 'refuse : aucun espace temporaire' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL"' EXIT INT TERM HUP
    VU=0
    lines | while IFS= read -r L; do
      T=$(text "$L")
      E=$(state "$T")
      if [ "$VU" = 0 ] && [ "$E" = todo ]; then
        VU=1; E=doing
      elif [ "$VU" = 0 ] && [ "$E" = doing ]; then
        VU=1; E=complete
      fi
      NUM=$(printf '%s' "$L" | sed -n 's/^  \([0-9][0-9][0-9]\):.*/\1/p')
      printf '  %s: "[%s] %s"\n' "$NUM" "$E" "$(point_status "$T")"
    done > "$TMPL"
    rewrite < "$TMPL"
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  revise)
    PATTERN=${2:-}
    [ -n "$PATTERN" ] || { echo 'refuse : revise veut un motif' >&2 ; exit 1 ; }
    [ "$PLAN_OPEN" = 1 ] || { echo 'refuse : aucun plan ouvert a reviser' >&2 ; exit 1 ; }
    TMPL=$(mktemp "${TMPDIR:-/tmp}/planr.XXXXXX") || { echo 'refuse : aucun espace temporaire' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL"' EXIT INT TERM HUP
    NEW=$(mktemp "${TMPDIR:-/tmp}/planrn.XXXXXX") || { echo 'refuse : aucun espace temporaire' >&2 ; exit 1 ; }
    trap 'rm -f "$TMPL" "$NEW"' EXIT INT TERM HUP
    cat > "$NEW"
    # les points DEJA FRANCHIS (complete) ne bougent pas ; les autres sont remplaces
    lines | grep '\[complete\]' > "$TMPL"
    N=400
    while IFS= read -r L || [ -n "$L" ]; do
      [ -n "$L" ] || continue
      N=$((N + 1))
      [ $(( ${#L} + 20 )) -le 100 ] || { echo "refuse : un point depasse la ligne de skill : $L" >&2 ; exit 1 ; }
      printf '  %s: "[todo] %s"\n' "$N" "$L" >> "$NEW.out"
    done < "$NEW"
    [ -s "$NEW.out" ] || { rm -f "$NEW.out" ; echo 'refuse : revise veut au moins un point sur l entree standard' >&2 ; exit 1 ; }
    N=$((N + 1))
    printf '  %s: "[todo] NETTOYAGE : ranger le travail, rien ne reste seme"\n' "$N" >> "$NEW.out"
    cat "$NEW.out" >> "$TMPL"
    rm -f "$NEW.out" "$NEW"
    rewrite < "$TMPL"
    echo "plan revise ($PATTERN)"
    lines | while IFS= read -r L; do printf '  %s\n' "$(text "$L")"; done
    ;;
  close)
    PATTERN=${2:-}
    [ "$N_LINES" -gt 0 ] || { echo 'refuse : aucun plan ouvert a fermer' >&2 ; exit 1 ; }
    LAST=$(lines | tail -n 1 | sed -e 's/^  [0-9][0-9][0-9]: "//' -e 's/"$//')
    case "$(point_status "$LAST")" in
      NETTOYAGE*) ;;
      *) echo "refuse : le dernier point du plan n est pas le point de nettoyage ; close_plan ferme un plan range, pas un plan en cours ($(point_status "$LAST"))" >&2 ; exit 1 ;;
    esac
    clear
    echo "plan ferme${PATTERN:+ ($PATTERN)} ; la section PLAN: du skill est vide"
    ;;
  abort)
    PATTERN=${2:-}
    [ "$N_LINES" -gt 0 ] || { echo 'refuse : aucun plan ouvert a interrompre' >&2 ; exit 1 ; }
    clear
    echo "plan interrompu${PATTERN:+ ($PATTERN)} ; la section PLAN: du skill est vide"
    ;;
  *)
    echo 'refuse : sous-commande inconnue ; start, load, advance, revise, close ou abort' >&2
    exit 1
    ;;
esac
