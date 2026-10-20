#!/usr/bin/dash
# french in code is forbidden
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

[ -n "$HERE" ] || HERE=$(dirname "$0")
CONF_DIR=$(dirname "$HERE")
active_skill
active_project
TABLE=${LA_CONFIG:-$CONF_DIR/la_tools.yaml}
CONF=${LA_CONF:-$CONF_DIR/la_config.yaml}

CAP_TASK_L=$(conf_num second task_lines 1);     CAP_TASK_C=$(conf_num second task_chars 160)
CAP_PLAN_L=$(conf_num second plan_lines 16)
CAP_PLAN_C=$(conf_num second plan_chars 900)
CAP_STAMP_L=$(conf_num second stamp_lines 1);   CAP_STAMP_C=$(conf_num second stamp_chars 120)
CAP_RESUME_L=$(conf_num second resume_lines 12); CAP_RESUME_C=$(conf_num second resume_chars 800)
CAP_TOOLS_L=$(conf_num second tools_lines 4);   CAP_TOOLS_C=$(conf_num second tools_chars 200)
CAP_SKILL_L=$(conf_num second skill_lines 12);  CAP_SKILL_C=$(conf_num second skill_chars 800)
CAP_NEXT_L=$(conf_num second next_lines 3);     CAP_NEXT_C=$(conf_num second next_chars 240)
CAP_READS_L=$(conf_num second reads_lines 3);   CAP_READS_C=$(conf_num second reads_chars 240)
CAP_AG_L=$(conf_num second agents_lines 8);     CAP_AG_C=$(conf_num second agents_chars 600)
CAP_MSG_L=$(conf_num second msg_lines 14);      CAP_MSG_C=$(conf_num second msg_chars 1200)
T_project_label='== THE ACTIVE PROJECT =='
T_project_state='active project (state file) : %s'
T_project_loaded='loaded project : %s'
T_project_path='path : %s'
T_project_opens='opens skills : %s'
T_project_opens_none='opens skills : none declared ; the perimeter is wide (load a skill to reach its tools)'
T_summary_label='summary :'
T_project_summary_none='summary : none ; the project summary section is empty'
T_no_project='no project loaded : the perimeter is WIDE, but you do NOT hold every tool. A tool lives in a skill : load the skill that owns it (load_skill) to reach its tools. toolset lists the perimeter of THIS turn, never the whole registry.'
T_skill_label='== THE ACTIVE SKILL =='
T_skill_state='active skill (state file) : %s'
T_skill_loaded='loaded skill : %s'
T_no_skill='no skill loaded : the active skill is missing or nameless (%s)'
T_skill_summary_none='summary : none ; the active skill summary section is empty'
T_model_label='== THE LOCAL MODEL SUMMARY =='
T_model_written='exchanges %s ; written %s'
T_model_none='# no summary : %s is missing or empty. The model writes it, never here.'
T_plan_label='== THE LOADED SKILL PLAN =='
T_plan_missing='the plan could not be obtained : the plan brick is missing (%s)'
T_plan_empty='the plan could not be obtained : the plan brick returned nothing'
T_tools_label='== THE TOOLS STATE =='
T_tools_family='family open : %s'
T_tools_no_family='no family open : the perimeter is wide (tools live in skills ; load_skill to reach one)'
T_tools_visible='always visible : %s'
T_tools_none='always visible : none declared (%s, permanent section)'
T_reads_label='== HOW THE DEMAND READS =='
T_reads_judged='judged_family : %s'
T_reads_unjudged='judged_family : non juge -- le filtre n a pas appris (%s)'
T_next_label='== THE NEXT INSTRUCTION =='
T_task_label='== THE TASK =='
T_stamp_label='== THE TIMESTAMP =='
T_stamp_line='date %s  time %s  locale UTC'
T_agents_label='== THE AGENTS =='
T_agents_line='%s  pid %s  %s  task : %s'
T_agents_on='active'
T_agents_off='ended'
T_agents_idle='%s  idle : no turn runs'
T_agents_none='no agent is declared (agents: names, la_config)'
T_msg_label='== THE MESSAGES =='
T_msg_count='%s message(s) for me'
T_msg_none='no message for me'
T_msg_nobody='no board is readable (%s)'
T_msg_from='%s wrote to me at %s :'
T_msg_wait='%s and the following wait for the next call (the declared bound is reached)'
T_msg_lost='MESSAGES WERE LOST before I read them : my watermark fell outside the board'
T_who_label='== THE HUMAN =='
T_who_line='you are talking with %s (%s) ; the agent answering is %s'

TEXTS=$(
  [ -n "${CONF:-}" ] && [ -f "${CONF:-}" ] || exit 0
  awk '
    /^second:[[:space:]]*$/ { on = 1 ; next }
    on && /^[^[:space:]]/   { exit }
    on && /^[[:space:]]*#/  { next }
    on && /^[[:space:]]*t_[A-Za-z0-9_]+:/ {
      l = $0
      sub(/^[[:space:]]+/, "", l)
      k = l ; sub(/:.*/, "", k)
      v = l ; sub(/^[^:]+:[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2) }
      else { sub(/[[:space:]]+#.*$/, "", v) }
      print k ; print v
    }
  ' "$CONF"
)
while IFS= read -r _tk; do
  IFS= read -r _tv || break
  case $_tk in
    t_project_label)        T_project_label=$_tv ;;
    t_who_label)            T_who_label=$_tv ;;
    t_who_line)             T_who_line=$_tv ;;
    t_project_state)        T_project_state=$_tv ;;
    t_project_loaded)       T_project_loaded=$_tv ;;
    t_project_path)         T_project_path=$_tv ;;
    t_project_opens)        T_project_opens=$_tv ;;
    t_project_opens_none)   T_project_opens_none=$_tv ;;
    t_summary_label)        T_summary_label=$_tv ;;
    t_project_summary_none) T_project_summary_none=$_tv ;;
    t_no_project)           T_no_project=$_tv ;;
    t_skill_label)          T_skill_label=$_tv ;;
    t_skill_state)          T_skill_state=$_tv ;;
    t_skill_loaded)         T_skill_loaded=$_tv ;;
    t_no_skill)             T_no_skill=$_tv ;;
    t_skill_summary_none)   T_skill_summary_none=$_tv ;;
    t_model_label)          T_model_label=$_tv ;;
    t_model_written)        T_model_written=$_tv ;;
    t_model_none)           T_model_none=$_tv ;;
    t_plan_label)           T_plan_label=$_tv ;;
    t_plan_missing)         T_plan_missing=$_tv ;;
    t_plan_empty)           T_plan_empty=$_tv ;;
    t_tools_label)          T_tools_label=$_tv ;;
    t_tools_family)         T_tools_family=$_tv ;;
    t_tools_no_family)      T_tools_no_family=$_tv ;;
    t_tools_visible)        T_tools_visible=$_tv ;;
    t_tools_none)           T_tools_none=$_tv ;;
    t_reads_label)          T_reads_label=$_tv ;;
    t_reads_judged)         T_reads_judged=$_tv ;;
    t_reads_unjudged)       T_reads_unjudged=$_tv ;;
    t_next_label)           T_next_label=$_tv ;;
    t_task_label)           T_task_label=$_tv ;;
    t_stamp_label)          T_stamp_label=$_tv ;;
    t_stamp_line)           T_stamp_line=$_tv ;;
    t_agents_label)         T_agents_label=$_tv ;;
    t_agents_line)          T_agents_line=$_tv ;;
    t_agents_on)            T_agents_on=$_tv ;;
    t_agents_off)           T_agents_off=$_tv ;;
    t_agents_idle)          T_agents_idle=$_tv ;;
    t_agents_none)          T_agents_none=$_tv ;;
    t_msg_label)            T_msg_label=$_tv ;;
    t_msg_count)            T_msg_count=$_tv ;;
    t_msg_none)             T_msg_none=$_tv ;;
    t_msg_nobody)           T_msg_nobody=$_tv ;;
    t_msg_from)             T_msg_from=$_tv ;;
    t_msg_wait)             T_msg_wait=$_tv ;;
    t_msg_lost)             T_msg_lost=$_tv ;;
    *) printf '%s\n' "$(msg second_key_unused "$_tk")" >&2 ;;
  esac
done <<EOF
$TEXTS
EOF

if [ "$#" -gt 0 ]; then
  TASK="$*"
else
  IFS= read -r TASK || TASK=
fi

S_PROJECT=
PNAME_L= ; PROJECT_L= ; PRES=
if [ -n "$PROJECT" ] && [ -f "$PROJECT" ]; then
  PNAME_L=$(sed -n 's/^project:[[:space:]]*//p' "$PROJECT" | head -n 1 | tr -d '"')
  PROJECT_L=$(sed -n 's/^path:[[:space:]]*//p' "$PROJECT" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
  PRES=$(sed -n '/^SUMMARY:/,/^[^[:space:]]/p' "$PROJECT" | sed -e '1d' | sed -e '/^[^[:space:]]/d')
fi
S_PROJECT=$({
  printf '%s\n' "$T_project_label"
  if [ -n "$PROJECT" ]; then
    tpn "$T_project_state" "$PNAME"
    tpn "$T_project_loaded" "${PNAME_L:-$PNAME}"
    tpn "$T_project_path" "${PROJECT_L:-?}"
    PSK=$(project_skills "$PROJECT" | tr '\n' ' ')
    if [ -n "$PSK" ]; then tpn "$T_project_opens" "$PSK"
    else printf '%s\n' "$T_project_opens_none" ; fi
    if [ -n "$PRES" ]; then printf '%s\n' "$T_summary_label" ; printf '%s\n' "$PRES"
    else printf '%s\n' "$T_project_summary_none" ; fi
  else
    printf '%s\n' "$T_no_project"
  fi
} | bound "$CAP_SKILL_L" "$CAP_SKILL_C")

S_SKILL=
SKILL_NAME= ; SKRES=
if [ -f "$SKILL" ]; then
  SKILL_NAME=$(sed -n 's/^skill:[[:space:]]*//p' "$SKILL" | head -n 1)
  SKRES=$(sed -n '/^SUMMARY:/,/^[^[:space:]]/p' "$SKILL" | sed -e '1d' | sed -e '/^[^[:space:]]/d')
fi
S_SKILL=$({
  printf '%s\n' "$T_skill_label"
  tpn "$T_skill_state" "${NAME:-la}"
  if [ -n "$SKILL_NAME" ]; then
    tpn "$T_skill_loaded" "$SKILL_NAME"
  else
    tpn "$T_no_skill" "$SKILL"
  fi
  if [ -n "$SKRES" ]; then
    printf '%s\n' "$T_summary_label"
    printf '%s\n' "$SKRES"
  else
    printf '%s\n' "$T_skill_summary_none"
  fi
} | bound "$CAP_SKILL_L" "$CAP_SKILL_C")

RESF=${LA_SUMMARY_FILE:-$CONF_DIR/second.yaml}
LINES=
if [ -f "$RESF" ]; then
  LINES=$(sed -n '/^summary:/,/^[^[:space:]]/p' "$RESF" \
           | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
           | sed -e 's/^"//' -e 's/"$//' | grep -v '^$')
fi
S_SUMMARY=$({
  printf '%s\n' "$T_model_label"
  if [ -n "$LINES" ]; then
    _h=$(sed -n 's/^stamp:[[:space:]]*//p' "$RESF" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
    _e=$(sed -n 's/^exchanges:[[:space:]]*//p' "$RESF" | head -n 1 | sed -e 's/^"//' -e 's/"$//')
    tpn "$T_model_written" "${_e:-?}" "${_h:-without time}" \
      | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
    printf '%s\n' "$LINES" | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
  else
    tpn "$T_model_none" "$RESF" \
      | bound "$CAP_RESUME_L" "$CAP_RESUME_C"
  fi
} | bound "$CAP_RESUME_L" "$CAP_RESUME_C")

S_PLAN=
PLAN=
PLAN_SH="$HERE/plan.sh"
if [ ! -x "$PLAN_SH" ]; then
  PLAN=$(tpn "$T_plan_missing" "$PLAN_SH")
else
  PLAN=$(PLAN_FILE="$SKILL" "$PLAN_SH" status 2>/dev/null) || PLAN=
  [ -n "$PLAN" ] || PLAN=$T_plan_empty
fi
S_PLAN=$({
  printf '%s\n' "$T_plan_label"
  printf '%s\n' "$PLAN"
} | bound "$CAP_PLAN_L" "$CAP_PLAN_C")

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
PERM=
if [ -f "$CONF" ]; then
  PERM=$(read_permanent | tr '\n' ' ')
fi
S_TOOLS=$({
  printf '%s\n' "$T_tools_label"
  if [ -n "$FAMS" ]; then
    tpn "$T_tools_family" "$FAMS"
  else
    printf '%s\n' "$T_tools_no_family"
  fi
  if [ -n "$PERM" ]; then
    tpn "$T_tools_visible" "$PERM"
  else
    tpn "$T_tools_none" "$CONF"
  fi
} | bound "$CAP_TOOLS_L" "$CAP_TOOLS_C")

S_READS=$({
  printf '%s\n' "$T_reads_label"
  FAMF=${LA_FILTER_MODEL:-$CONF_DIR/filtre/family.bin}
  FAM=
  if [ -f "$FAMF" ] && command -v fasttext >/dev/null 2>&1; then
    FAM=$(printf '%s\n' "$TASK" | fasttext predict-prob "$FAMF" - 1 2>/dev/null \
            | sed -e 's/^__label__//' -e 's/\([0-9]\.[0-9][0-9]\).*/\1/')
  fi
  if [ -n "$FAM" ]; then
    tpn "$T_reads_judged" "$FAM"
  else
    tpn "$T_reads_unjudged" "$FAMF"
  fi
} | bound "$CAP_READS_L" "$CAP_READS_C")

AG_NAMES=$(conf_str agents names "")
AG_RUN=$(conf_str paths run 'config/%s.run')
S_AGENTS=$( {
  printf '%s\n' "$T_agents_label"
  if [ -z "$AG_NAMES" ]; then
    printf '%s\n' "$T_agents_none"
  else
    for _a in $AG_NAMES; do
      _f=$(tpn "$AG_RUN" "$_a")
      case "$_f" in /*) ;; *) _f="$ROOT/$_f" ;; esac
      if [ -f "$_f" ]; then
        _p= ; _h= ; _k=
        { read -r _p _h _k < "$_f" ; } 2>/dev/null || :
        if kill -0 "${_p:-0}" 2>/dev/null; then _st=$T_agents_on ; else _st=$T_agents_off ; fi
        tpn "$T_agents_line" "$_a" "${_p:-?}" "$_st" "${_k:-?}"
      else
        tpn "$T_agents_idle" "$_a"
      fi
    done
  fi
} | bound "$CAP_AG_L" "$CAP_AG_C")

ME=${LA_FROM:-$(conf_str agents main agent_one)}
AG_CHAT=$(conf_str paths chat 'config/agent_chat.jsonl')
case "$AG_CHAT" in /*) ;; *) AG_CHAT="$ROOT/$AG_CHAT" ;; esac
AG_SEEN=$(tpn "$(conf_str paths seen 'config/%s.seen')" "$ME")
case "$AG_SEEN" in /*) ;; *) AG_SEEN="$ROOT/$AG_SEEN" ;; esac
TAB=$(printf '\t')
MSG_RES_C=$(conf_num second msg_reserve_bytes 260)
MSG_RES_L=$(conf_num second msg_reserve_lines 3)
MSG_HEAD_C=$(conf_num second msg_head_bytes 90)
MSG_FIT=$(( CAP_MSG_C - MSG_RES_C )); [ "$MSG_FIT" -ge 200 ] || MSG_FIT=$CAP_MSG_C
MSG_LFIT=$(( CAP_MSG_L - MSG_RES_L )); [ "$MSG_LFIT" -ge 3 ]  || MSG_LFIT=$CAP_MSG_L
S_MESSAGES=$( {
  printf '%s\n' "$T_msg_label"
  if [ ! -r "$AG_CHAT" ]; then
    tpn "$T_msg_nobody" "$AG_CHAT"
  else
    LAST=${LA_CHAT_SEEN:-}
    if [ -z "$LAST" ] && [ -f "$AG_SEEN" ]; then
      LAST=$(head -n 1 "$AG_SEEN" 2>/dev/null | tr -d '\r')
    fi
    ESC=$(jq -r -s --arg last "$LAST" '
          if $last == "" then 0
          else (if ([.[].id] | index($last)) == null then 1 else 0 end) end' \
          "$AG_CHAT" 2>/dev/null) || ESC=
    LIST=$(jq -r -s --arg me "$ME" --arg last "$LAST" '
          . as $all
          | ($all | map(.id) | index($last)) as $i
          | (if $last == "" then 0 elif $i == null then 0 else $i + 1 end) as $start
          | $all[$start:][] | select(.to == $me and .from != $me)
          | "\(.id)\t\(.from)\t\(.ts)\t\(.body | gsub("\n"; " "))"' "$AG_CHAT" 2>/dev/null) || LIST=
    NMSG=$(printf '%s\n' "$LIST" | grep -c . 2>/dev/null) || NMSG=0
    case "${NMSG:-0}" in ''|*[!0-9]*) NMSG=0 ;; esac
    if [ "$NMSG" -eq 0 ]; then
      printf '%s\n' "$T_msg_none"
    else
      case "${ESC:-}" in 1) printf '%s\n' "$T_msg_lost" ;; *) : ;; esac
      tpn "$T_msg_count" "$NMSG"
      USED=0 ; SHOWN=0 ; IDLAST=
      while IFS=$TAB read -r _id _src _ts _body; do
        [ -n "$_id" ] || continue
        NEED=$(printf '%s\n' "$_body" | wc -c)
        NEEDL=$(printf '%s\n' "$_body" | wc -l)
        if [ $((USED + NEED + MSG_HEAD_C)) -gt "$MSG_FIT" ] \
        || [ $((SHOWN + NEEDL + 2)) -gt "$MSG_LFIT" ]; then
          tpn "$T_msg_wait" "$_src"
          break
        fi
        USED=$((USED + NEED + MSG_HEAD_C))
        SHOWN=$((SHOWN + NEEDL + 2))
        tpn "$T_msg_from" "$_src" "$_ts"
        printf '%s\n' "$_body"
        IDLAST="$_id"
      done <<EOF
$LIST
EOF
      [ -n "$IDLAST" ] && printf '[chat-seen:%s]\n' "$IDLAST"
    fi
  fi
} | bound "$CAP_MSG_L" "$CAP_MSG_C")

S_NEXT=
if [ -s "$STATE/next.md" ]; then
  S_NEXT=$({
    printf '%s\n' "$T_next_label"
    bound "$CAP_NEXT_L" "$CAP_NEXT_C" < "$STATE/next.md"
  })
fi

S_TASK=$({
  printf '%s\n' "$T_task_label"
  printf '%s\n' "$TASK" | bound "$CAP_TASK_L" "$CAP_TASK_C"
})

S_STAMP=$({
  printf '%s\n' "$T_stamp_label"
  tpn "$T_stamp_line" "$(date -u +%Y-%m-%d)" "$(date -u +%H:%M:%S)"
} | bound "$CAP_STAMP_L" "$CAP_STAMP_C")

NAME_H=$(conf_str agents name_human user)
case "$NAME_H" in ''|*[!a-z0-9_-]*) NAME_H=user ;; esac
NAME_H_CAP=$(printf '%s' "$NAME_H" | sed 's/^./\U&/')
S_WHO=$( {
  printf '%s\n' "$T_who_label"
  tpn "$T_who_line" "$NAME_H_CAP" "$NAME_H" "${LA_FROM:-$(conf_str agents main agent_one)}"
} )

ORDER_DEFAULT="who project skill summary plan agents messages tools reads next task stamp"
ORDER=$(conf_str second order "")
[ -n "$ORDER" ] || ORDER=$ORDER_DEFAULT

section_of() {   # $1 = the DECLARED name : prints that section
  case "$1" in
    who)     printf '%s' "$S_WHO" ;;
    project) printf '%s' "$S_PROJECT" ;;
    skill)   printf '%s' "$S_SKILL" ;;
    summary) printf '%s' "$S_SUMMARY" ;;
    plan)    printf '%s' "$S_PLAN" ;;
    agents)  printf '%s' "$S_AGENTS" ;;
    messages) printf '%s' "$S_MESSAGES" ;;
    tools)   printf '%s' "$S_TOOLS" ;;
    reads)   printf '%s' "$S_READS" ;;
    next)    printf '%s' "$S_NEXT" ;;
    task)    printf '%s' "$S_TASK" ;;
    stamp)   printf '%s' "$S_STAMP" ;;
    *) return 1 ;;
  esac
}

NAMED=
for SEC in $ORDER; do
  S=$(section_of "$SEC") || {
    printf '%s\n' "$(msg second_section_unknown "$SEC")" >&2
    printf '%s\n' "$(msg second_order_hint)" >&2
    continue
  }
  NAMED="$NAMED $SEC"
  [ -n "$S" ] || continue
  printf '%s\036' "$S"
done

for SEC in $ORDER_DEFAULT; do
  case " $NAMED " in *" $SEC "*) continue ;; esac
  S=$(section_of "$SEC")
  [ -n "$S" ] || continue
  printf '%s\n' "$(msg second_section_absent "$SEC")" >&2
  printf '%s\036' "$S"
done
