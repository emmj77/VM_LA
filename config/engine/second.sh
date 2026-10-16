#!/bin/sh
# second.sh - LE HEAD SECONDAIRE (config/engine/second.sh).
# Il rend sur sa SORTIE STANDARD des SECTIONS FIXES, bornees, dans CET ORDRE :
#   == LA TACHE ==                    la demande du tour, courte
#   == LE PLAN DE LA SKILL CHARGEE == le plan OUVERT, obtenu par config/engine/engine.sh 122
#   == LE RESUME DU MODELE LOCAL ==   une PLACE marquee, ET SA BORNE ; rien dedans
#   == L'ETAT DES TOOLS ==            quelle famille est ouverte (le SKILL ACTIF), et
#                                     les tools TOUJOURS apparents (la categorie permanente
#                                     lue dans config/la_config.yaml, section `permanent:`)
#   == LA SKILL ACTIVE ==             le nom de la skill chargee, et son RESUME
# La TACHE vient des arguments ; sans argument, une ligne de l'ENTREE STANDARD.
# Il ne rend JAMAIS de texte libre a l'humain : c'est un preambule, pas une reply.
# POSIX sh (dash) + coreutils, sans accent grave. jq pour lire la forme du engine.
LC_ALL=C
export LC_ALL

HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
ROOT=${LA_ROOT:-$(dirname "$CONF_DIR")}
ENGINE="$HERE/engine.sh"
# LA SKILL ACTIVE — la resolution vit dans la bibliotheque commune (config/engine/lib.sh).
[ -f "$HERE/lib.sh" ] || { printf 'second: the common library is missing (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"
active_skill
TABLE=${LA_CONFIG:-$CONF_DIR/la_tools.yaml}
CONF=${LA_CONF:-$CONF_DIR/la_config.yaml}

# LES BORNES DES SECTIONS - des chiffres DECLARES, pas une impression.
CAP_TASK_L=1;   CAP_TASK_C=160
CAP_PLAN_L=16;   CAP_PLAN_C=900
CAP_STAMP_L=1;   CAP_STAMP_C=120
CAP_RESUME_L=12; CAP_RESUME_C=800
CAP_TOOLS_L=4;   CAP_TOOLS_C=200
CAP_SKILL_L=12;  CAP_SKILL_C=800

bound() {   # $1 = lignes au plus ; $2 = octets au plus : borne une section sur son entree
  head -n "$1" | head -c "$2"
}

# ---- LA TACHE (courte) -------------------------------------------------------
if [ "$#" -gt 0 ]; then
  TASK="$*"
else
  IFS= read -r TASK || TASK=
fi
printf '== THE TASK ==\n'
printf '%s\n' "$TASK" | bound "$CAP_TASK_L" "$CAP_TASK_C"

# ---- LE PLAN DE LA SKILL CHARGEE : il y a TOUJOURS un plan en cours ----------
printf '== THE LOADED SKILL PLAN ==\n'
PLAN=
if ! command -v jq >/dev/null 2>&1; then
  PLAN="le plan n'a pas pu etre obtenu : jq est absent"
elif [ ! -x "$ENGINE" ]; then
  PLAN="le plan n'a pas pu etre obtenu : le engine est introuvable ($ENGINE)"
else
  PJ=$(printf '' | "$ENGINE" 122 2>/dev/null)
  case "$(printf '%s' "$PJ" | jq -r '.status // ""' 2>/dev/null)" in
    ok)    PLAN=$(printf '%s' "$PJ" | jq -r '.result // ""' 2>/dev/null) ;;
    refused) PLAN=$(printf '%s' "$PJ" | jq -r '.line // ""' 2>/dev/null) ;;
    *)     PLAN="le plan n'a pas pu etre obtenu : le engine 122 n'a rien render" ;;
  esac
fi
[ -n "$PLAN" ] || PLAN="aucun plan ouvert : le skill actif ne porte aucun plan dans sa section PLAN:"
printf '%s\n' "$PLAN" | bound "$CAP_PLAN_L" "$CAP_PLAN_C"

# ---- L'HORODATAGE : la date, l'heure, la locale -------------------------------
# LOI 1904 : le bloc dynamique porte QUATRE sections, et l'horodatage est l'une d'elles.
# LOI 337 : les faits partent EN DERNIER dans les messages ; la couche de l'etat les porte
# AUSSI, pour que le modele les ait sous les yeux sans avoir a les demander.
# LOI 1908 : taille FIXE - une seule ligne, bornee, qui se REMPLACE et ne s'allonge jamais.
printf '== THE TIMESTAMP ==\n'
printf 'date %s  heure %s  locale UTC\n' "$(date -u +%Y-%m-%d)" "$(date -u +%H:%M:%S)" \
  | bound "$CAP_STAMP_L" "$CAP_STAMP_C"

# ---- LE RESUME DU MODELE LOCAL : ecrit par le modele local, dans config/second.yaml --------
# LOI 110 : summary.sh ECRIT LE RESUME ; LOI 1716 : le micro-modele ecrit les DEUX resumes
# (sessions.yaml ET le head secondaire). LOI 1915 : les echanges SORTIS de la fenetre passent
# au resume. LOI 813 : un resume vient du MODELE, ou il n y a PAS de resume - ici, on ne
# fabrique rien, on rend ce que le modele a pose. LOI 808/812 : la place est bornee, et la
# borne est celle declaree plus haut (CAP_RESUME_L / CAP_RESUME_C).
printf '== THE LOCAL MODEL SUMMARY ==\n'
RESF=${LA_SUMMARY_FILE:-$CONF_DIR/second.yaml}
LINES=
if [ -f "$RESF" ]; then
  LINES=$(sed -n '/^summary:/,/^[^[:space:]]/p' "$RESF" \
           | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
           | sed -e 's/^"//' -e 's/"$//' | grep -v '^$')
fi
if [ -n "$LINES" ]; then
  # DE QUOI IL PARLE : l heure de la reecriture, et la plage d echanges couverte
  _h=$(sed -n 's/^stamp:[[:space:]]*//p' "$RESF" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
  _e=$(sed -n 's/^exchanges:[[:space:]]*//p' "$RESF" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
  printf 'exchanges %s ; ecrit %s\n' "${_e:-?}" "${_h:-sans heure}" \
    | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
  printf '%s\n' "$LINES" | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
else
  printf '# aucun resume : %s est absent ou vide. Le resume vient du modele local, jamais d ici.\n' "$RESF" \
    | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
fi

# ---- L'ETAT DES TOOLS : quelle famille est ouverte ---------------------------
printf '== THE TOOLS STATE ==\n'
FAMS=
if [ -f "$SKILL" ] && [ -f "$TABLE" ]; then
  TOOLS_NAMES=$(sed -n '/^TOOLS:/,/^[^[:space:]]/p' "$SKILL" \
           | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
           | sed -e 's/^"//' -e 's/"$//' | tr '\n' ' ')
  FAMS=$(awk -v noms="$TOOLS_NAMES" '
    BEGIN { n=split(noms, a, " "); for (i=1;i<=n;i++) if (a[i] != "") want[a[i]]=1 }
    /^    tool:/   { t=$2 }
    /^    family:/ { f=$2; if (t in want) vu[f]=1 }
    END { s=""; for (k in vu) s = (s=="" ? k : s ", " k); print s }
  ' "$TABLE")
fi
if [ -n "$FAMS" ]; then
  printf 'famille ouverte : %s\n' "$FAMS" | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C"
else
  printf 'aucune famille ouverte : le perimetre est large\n' \
    | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C"
fi

# LES TOOLS_NOMS TOUJOURS APPARENTS : la CATEGORIE PERMANENTE, lue dans la config. Quelle que
# soit la palette du SKILL ACTIF, ces tools-la sont TOUJOURS dans le perimetre du tour.
# Une entree `tool:action` ne vaut que pour cette action-la.
PERM=
if [ -f "$CONF" ]; then
  PERM=$(permanent_section "$CONF" | tr '\n' ' ')
fi
if [ -n "$PERM" ]; then
  printf 'toujours apparents : %s\n' "$PERM" | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C"
else
  printf 'toujours apparents : aucuns declares (%s, section permanent)\n' "$CONF" \
    | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C"
fi

# ---- LA SKILL ACTIVE : la skill chargee, et son RESUME -----------------------
# Le NOM vient du FICHIER D ETAT ($ROOT/skills/.active), resolu par skill_actif :
# le MEME pointeur que la palette et les paths. Le resume ci-dessous reste dans le
# head secondaire TANT QUE cette skill est chargee : le chargement d une AUTRE skill
# PREND SA PLACE, car load_skill ecrit le nom dans le fichier d etat.
printf '== THE ACTIVE SKILL ==\n'
SKILL_NAME=
RES=
if [ -f "$SKILL" ]; then
  SKILL_NAME=$(sed -n 's/^skill:[[:space:]]*//p' "$SKILL" | head -n 1)
  RES=$(sed -n '/^SUMMARY:/,/^[^[:space:]]/p' "$SKILL" | sed -e '1d' | sed -e '/^[^[:space:]]/d')
fi
{
  printf 'skill active (fichier d etat) : %s\n' "${NAME:-la}"
  if [ -n "$SKILL_NAME" ]; then
    printf 'skill chargee : %s\n' "$SKILL_NAME"
  else
    printf 'aucune skill chargee : le skill actif est introuvable ou sans nom (%s)\n' "$SKILL"
  fi
  if [ -n "$RES" ]; then
    printf 'resume :\n'
    printf '%s\n' "$RES"
  else
    printf 'resume : aucun ; la section resume du skill actif est vide\n'
  fi
} | bound "$CAP_SKILL_L" "$CAP_SKILL_C"
