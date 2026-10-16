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
