#!/bin/sh
# second.sh - THE SECONDARY HEAD (config/engine/second.sh).
# It returns on its STANDARD OUTPUT FIXED, bounded SECTIONS, in THIS ORDER :
#   == THE TASK ==                    the turn's request, short
#   == THE LOADED SKILL PLAN ==       the OPEN plan, read by config/engine/plan.sh status
#   == THE LOCAL MODEL SUMMARY ==     a marked PLACE, AND ITS BOUND ; nothing inside
#   == THE TOOLS STATE ==             which family is open (the ACTIVE SKILL), and the
#                                     ALWAYS-visible tools (the permanent category read in
#                                     config/la_config.yaml, section `permanent:`)
#   == THE ACTIVE SKILL ==            the name of the loaded skill, and its SUMMARY
#   == THE ACTIVE PROJECT ==          the name of the loaded project, its path and its SUMMARY
# The TASK comes from the arguments ; without an argument, one line of the STANDARD INPUT.
# It NEVER returns free text to the human : it is a preamble, not a reply.
# POSIX sh (dash) + coreutils, no backtick. jq to read the engine's shape.
LC_ALL=C
export LC_ALL

HERE=$(dirname "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")
[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
ROOT=${LA_ROOT:-$(dirname "$CONF_DIR")}
ENGINE="$HERE/engine.sh"
# THE ACTIVE SKILL — the resolution lives in the common library (config/engine/lib.sh).
[ -f "$HERE/lib.sh" ] || { printf 'second: the common library is missing (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"
active_skill
active_project
TABLE=${LA_CONFIG:-$CONF_DIR/la_tools.yaml}
CONF=${LA_CONF:-$CONF_DIR/la_config.yaml}

# THE SECTION BOUNDS - DECLARED numbers, not a guess.
CAP_TASK_L=1;   CAP_TASK_C=160
CAP_PLAN_L=16;   CAP_PLAN_C=900
CAP_STAMP_L=1;   CAP_STAMP_C=120
CAP_RESUME_L=12; CAP_RESUME_C=800
CAP_TOOLS_L=4;   CAP_TOOLS_C=200
CAP_SKILL_L=12;  CAP_SKILL_C=800

bound() {   # $1 = lines at most ; $2 = bytes at most : bounds a section on its input
  head -n "$1" | head -c "$2"
}

# ---- THE TASK (short) --------------------------------------------------------
if [ "$#" -gt 0 ]; then
  TASK="$*"
else
  IFS= read -r TASK || TASK=
fi
printf '== THE TASK ==\n'
printf '%s\n' "$TASK" | bound "$CAP_TASK_L" "$CAP_TASK_C"

# ---- OFFSET 2 : COMMENT LA DEMANDE SE LIT -----------------------------------------------
# LE PREMIER ETAGE (loi 1505), pose ICI, sur la demande, une fois par tour, et declare : deux faits
# BORNES, chacun sur UNE ligne, qui ne bougent pas d'un tour a l'autre.
#   1. `user_emotional_status` : l'humeur de la demande, par config/py/read_emotion.py (GoEmotions
#      int8, 28 etiquettes, trois plus fortes). L'INSTRUMENT N A APPRIS QUE L ANGLAIS : sur une
#      demande francaise il se TAIT au lieu de deviner (lois 1557-1558 ; mesure du 17/10 : reproche francais ->
#      `neutral` 0,90-0,96, le meme reproche en anglais -> `annoyance` 0,79). La porte s'appelle
#      AVANT de charger le modele : une demande francaise coute la mesure de langue (18 ms), pas
#      les 340 ms et 307 Mo du chargement.
#   2. `judged_family` : la famille du perimetre jugee par le filtre fastText (0,4 Mo, 5 ms) que
#      `train_family_filter` a pose. Le moteur ne s'en sert pas encore comme d'un VERROU : il le
#      dit. Un verrou demande une justesse MESUREE et declaree (loi 709).
# LE MODELE N ECRIT RIEN ICI : ce sont des faits, pas un texte. Un fait qui manque se DIT.
CAP_READS_L=3; CAP_READS_C=240
printf '== HOW THE DEMAND READS ==\n'
{
  EMO_PY="$CONF_DIR/py/read_emotion.py"
  if [ -f "$EMO_PY" ] && [ -r "$EMO_PY" ]; then
    EMO=$(printf '%s\n' "$TASK" | /usr/bin/python3 "$EMO_PY" 2>&1)
    case "$EMO" in
      refuse*)
        printf 'user_emotional_status : non lu -- %s\n' \
          "$(printf '%s' "$EMO" | sed -e 's/^refuse : //' | head -n 1 | head -c 100)" ;;
      '')
        printf 'user_emotional_status : non lu -- le porteur n a rien rendu (%s)\n' "$EMO_PY" ;;
      *)
        printf 'user_emotional_status : %s\n' \
          "$(printf '%s' "$EMO" | head -n 1 | head -c 60)" ;;
    esac
  else
    printf 'user_emotional_status : non lu -- le porteur de l humeur est absent (%s)\n' "$EMO_PY"
  fi
  FAMF=${LA_FILTER_MODEL:-$CONF_DIR/filtre/famille.bin}
  FAM=
  if [ -f "$FAMF" ] && command -v fasttext >/dev/null 2>&1; then
    FAM=$(printf '%s\n' "$TASK" | fasttext predict-prob "$FAMF" - 1 2>/dev/null \
            | sed -e 's/^__label__//' -e 's/\([0-9]\.[0-9][0-9]\).*/\1/')
  fi
  if [ -n "$FAM" ]; then
    printf 'judged_family : %s\n' "$FAM"
  else
    printf 'judged_family : non juge -- le filtre n a pas appris (%s ; lance train_family_filter)\n' "$FAMF"
  fi
} | bound "$CAP_READS_L" "$CAP_READS_C"

# ---- THE LOADED SKILL PLAN : there is ALWAYS a plan in progress ---------------
printf '== THE LOADED SKILL PLAN ==\n'
# THE PLAN comes from the plan BRICK, read DIRECTLY (config/engine/plan.sh status) : the plan lives
# in the PLAN: section of the ACTIVE skill, not behind a tool of the table. `status` WRITES NOTHING.
# No jq here : the brick returns the plan as TEXT, or the words `no open plan` when there is none.
PLAN=
PLAN_SH="$HERE/plan.sh"
if [ ! -x "$PLAN_SH" ]; then
  PLAN="the plan could not be obtained : the plan brick is missing ($PLAN_SH)"
else
  # THE ACTIVE SKILL is the one the STATE FILE names (active_skill, above) : we hand its path to the
  # brick through PLAN_FILE, so the brick never has to GUESS where the plan lives.
  PLAN=$(PLAN_FILE="$SKILL" "$PLAN_SH" status 2>/dev/null) || PLAN=
  [ -n "$PLAN" ] || PLAN="the plan could not be obtained : the plan brick returned nothing"
fi
printf '%s\n' "$PLAN" | bound "$CAP_PLAN_L" "$CAP_PLAN_C"

# ---- THE TIMESTAMP : the date, the time, the locale --------------------------
# LAW 1904 : the dynamic block carries FOUR sections, and the timestamp is one of them.
# LAW 337 : facts go LAST in the messages ; the state layer carries them TOO, so the model
# has them before its eyes without having to ask.
# LAW 1908 : FIXED size - a single line, bounded, which REPLACES itself and never grows.
printf '== THE TIMESTAMP ==\n'
printf 'date %s  time %s  locale UTC\n' "$(date -u +%Y-%m-%d)" "$(date -u +%H:%M:%S)" \
  | bound "$CAP_STAMP_L" "$CAP_STAMP_C"

# ---- THE LOCAL MODEL SUMMARY : written by the local model, in config/second.yaml ------------
# LAW 110 : summary.sh WRITES THE SUMMARY ; LAW 1716 : the micro-model writes BOTH summaries
# (memory.db AND the secondary head). LAW 1915 : the exchanges that LEFT the window go to
# the summary. LAW 813 : a summary comes from the MODEL, or there is NO summary - here, we
# fabricate nothing, we return what the model placed. LAW 808/812 : the place is bounded, and
# the bound is the one declared above (CAP_RESUME_L / CAP_RESUME_C).
printf '== THE LOCAL MODEL SUMMARY ==\n'
RESF=${LA_SUMMARY_FILE:-$CONF_DIR/second.yaml}
LINES=
if [ -f "$RESF" ]; then
  LINES=$(sed -n '/^summary:/,/^[^[:space:]]/p' "$RESF" \
           | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
           | sed -e 's/^"//' -e 's/"$//' | grep -v '^$')
fi
if [ -n "$LINES" ]; then
  # WHAT IT SPEAKS OF : the rewrite time, and the covered range of exchanges
  _h=$(sed -n 's/^stamp:[[:space:]]*//p' "$RESF" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
  _e=$(sed -n 's/^exchanges:[[:space:]]*//p' "$RESF" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
  printf 'exchanges %s ; written %s\n' "${_e:-?}" "${_h:-without time}" \
    | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
  printf '%s\n' "$LINES" | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
else
  printf '# no summary : %s is missing or empty. The summary comes from the local model, never from here.\n' "$RESF" \
    | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
fi

# ---- THE TOOLS STATE : which family is open ---------------------------------
printf '== THE TOOLS STATE ==\n'
FAMS=
if [ -f "$SKILL" ] && [ -f "$TABLE" ]; then
  TOOLS_NAMES=$(sed -n '/^TOOLS:/,/^[^[:space:]]/p' "$SKILL" \
           | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
           | sed -e 's/^"//' -e 's/"$//' | tr '\n' ' ')
  FAMS=$(awk -v names="$TOOLS_NAMES" '
    BEGIN { n=split(names, a, " "); for (i=1;i<=n;i++) if (a[i] != "") want[a[i]]=1 }
    /^    tool:/   { t=$2 }
    /^    family:/ { f=$2; if (t in want) seen[f]=1 }
    END { s=""; for (k in seen) s = (s=="" ? k : s ", " k); print s }
  ' "$TABLE")
fi
if [ -n "$FAMS" ]; then
  printf 'family open : %s\n' "$FAMS" | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C"
else
  printf 'no family open : the perimeter is wide\n' \
    | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C"
fi

# THE ALWAYS-VISIBLE TOOL NAMES : the PERMANENT CATEGORY, read in the config. Whatever the
# palette of the ACTIVE SKILL, those tools are ALWAYS in the turn's perimeter.
# A `tool:action` entry counts only for that action.
PERM=
if [ -f "$CONF" ]; then
  PERM=$(permanent_section "$CONF" | tr '\n' ' ')
fi
if [ -n "$PERM" ]; then
  printf 'always visible : %s\n' "$PERM" | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C"
else
  printf 'always visible : none declared (%s, permanent section)\n' "$CONF" \
    | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C"
fi

# ---- THE ACTIVE SKILL : the loaded skill, and its SUMMARY --------------------
# The NAME comes from the STATE FILE ($ROOT/skills/.active), resolved by active_skill :
# the SAME pointer as the palette and the paths. The summary below stays in the secondary
# head AS LONG AS this skill is loaded : loading ANOTHER skill TAKES ITS PLACE, because
# load_skill writes the name into the state file.
printf '== THE ACTIVE SKILL ==\n'
SKILL_NAME=
RES=
if [ -f "$SKILL" ]; then
  SKILL_NAME=$(sed -n 's/^skill:[[:space:]]*//p' "$SKILL" | head -n 1)
  RES=$(sed -n '/^SUMMARY:/,/^[^[:space:]]/p' "$SKILL" | sed -e '1d' | sed -e '/^[^[:space:]]/d')
fi
{
  printf 'active skill (state file) : %s\n' "${NAME:-la}"
  if [ -n "$SKILL_NAME" ]; then
    printf 'loaded skill : %s\n' "$SKILL_NAME"
  else
    printf 'no skill loaded : the active skill is missing or nameless (%s)\n' "$SKILL"
  fi
  if [ -n "$RES" ]; then
    printf 'summary :\n'
    printf '%s\n' "$RES"
  else
    printf 'summary : none ; the active skill summary section is empty\n'
  fi
} | bound "$CAP_SKILL_L" "$CAP_SKILL_C"

# ---- THE ACTIVE PROJECT : the loaded project, its path and its SUMMARY ---------
# The NAME comes from the STATE FILE ($ROOT/projects/.active), resolved by active_project.
# A project ENVELOPES the skills: its SKILLS list is the set the model may LOAD. With no
# project loaded, the perimeter stays WIDE (every skill is reachable). The path is the
# folder where the project lives — it may move without disturbing anything.
printf '== THE ACTIVE PROJECT ==\n'
PNAME_L= ; PROJECT_L= ; PRES=
if [ -n "$PROJECT" ] && [ -f "$PROJECT" ]; then
  PNAME_L=$(sed -n 's/^project:[[:space:]]*//p' "$PROJECT" | head -n 1 | tr -d '"')
  PROJECT_L=$(sed -n 's/^path:[[:space:]]*//p' "$PROJECT" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
  PRES=$(sed -n '/^SUMMARY:/,/^[^[:space:]]/p' "$PROJECT" | sed -e '1d' | sed -e '/^[^[:space:]]/d')
fi
{
  if [ -n "$PROJECT" ]; then
    printf 'active project (state file) : %s\n' "$PNAME"
    printf 'loaded project : %s\n' "${PNAME_L:-$PNAME}"
    printf 'path : %s\n' "${PROJECT_L:-?}"
    PSK=$(project_skills "$PROJECT" | tr '\n' ' ')
    if [ -n "$PSK" ]; then printf 'opens skills : %s\n' "$PSK"
    else printf 'opens skills : none declared ; the perimeter is wide\n' ; fi
    if [ -n "$PRES" ]; then printf 'summary :\n' ; printf '%s\n' "$PRES"
    else printf 'summary : none ; the project summary section is empty\n' ; fi
  else
    printf 'no project loaded : the perimeter is wide (every skill is reachable)\n'
  fi
} | bound "$CAP_SKILL_L" "$CAP_SKILL_C"
