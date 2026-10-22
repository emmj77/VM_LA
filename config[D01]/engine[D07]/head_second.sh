# id: E08
# role: the producers of the secondary head, one function per section id. turn.prompt
# carries no section logic of its own: it sources this file and calls the function named
# by each id in head.second_order. to add a section, add a function here and its id there.

_sec_channel() {
  printf '== THE CHANNEL ==\n'
  printf 'channel : %s ; input : %s\n' "$(_turn_get '.channel // "cli"')" "$(_turn_get '.input // "text"')"
}
_sec_human() {
  printf '== THE HUMAN ==\n'
  printf 'you are talking with the human (%s) ; the agent answering is %s\n' \
    "$(cfg str agents.human user)" "$(cfg str agents.main jarvis)"
}
_sec_project() {
  printf '== THE ACTIVE PROJECT ==\n'
  _pr=$(skl_project 2>/dev/null)
  if [ -n "$_pr" ]; then printf 'project : %s\n' "$_pr"; else printf 'no project loaded : every skill is reachable\n'; fi
  # the project's rules, a minima : what its manifest declares, stack included
  if [ -n "$_pr" ]; then
    _pf=$(skl_big_file 2>/dev/null)
    if [ -n "$_pf" ]; then
      awk '/^RULES:/ { f = 1 ; next } f && /^[^ \t]/ { f = 0 } !f { next } /^  skillset:/ { sk = 1 ; next } sk && /^  [^ ]/ { sk = 0 } sk { next } /[a-z]/ && !/^[ \t]*#/ && !/: *""? *$/ { sub(/^[ \t]+/, "") ; print "rule : " $0 }' "$_pf" | head -n 6
    fi
  fi
}
_sec_skill() {
  printf '== THE ACTIVE SKILL ==\n'
  _sk=$(skl_skill 2>/dev/null)
  if [ -n "$_sk" ]; then printf 'skill : %s\n' "$_sk"; else printf 'no skill loaded : no skill is active\n'; fi
  # nothing loaded: three likely skills, one bounded line, that is all
  if [ -z "$_sk" ] && [ -n "$_req" ]; then
    _fd=$(find "$(dirname "$(dirname "$LA_CONFIG")")" -maxdepth 1 -type d -name 'filter\[D*\]' -print 2>/dev/null | head -n 1)
    _fm="$_fd/skills.bin"
    if [ -r "$_fm" ]; then
      _pp=$(printf '%s\n' "$_req" | tr 'A-Z' 'a-z' | fasttext predict-prob "$_fm" - 3 2>/dev/null \
        | sed 's/__label__//g' \
        | awk '{ o = ""; for (i = 1; i <= NF; i += 2) o = o (i > 1 ? " · " : "") $i " " sprintf("%.2f", $(i+1)); print o }')
      [ -n "$_pp" ] && printf 'skills probables : %s\n' "$_pp"
    fi
  fi
  # the skill's doc, in short : the agent keeps it in view ; it never grows long
  if [ -n "$_sk" ]; then
    _sd=$(cfg path skills) ; case $_sd in /*) ;; *) _sd="$ROOT/$_sd" ;; esac
    _td=$(cfg path tools) ; case $_td in /*) ;; *) _td="$ROOT/$_td" ;; esac
    _dl=$(cfg num limits.doc_lines 8) || _dl=8
    _dn=0
    for _dname in $(sed -n '/^DOCS:/,/^[^[:space:]]/p' "$_sd/$_sk/skill.yaml" 2>/dev/null \
                    | sed -n 's/^[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
                    | sed -e 's/^"//' -e 's/"[[:space:]]*$//' | grep -v '^$'); do
      _dn=$((_dn+1)) ; [ "$_dn" -le 2 ] || break
      case $_dname in
        web_search|web|none) printf 'doc %s : on the web, take the official source\n' "$_dname" ; continue ;;
      esac
      _df=""
      for _c in "$_td/$_dname" "$ROOT/$_dname" "$_sd/$_sk/$_dname" "$_sd/$_dname"; do
        [ -f "$_c" ] && { _df=$_c ; break ; }
      done
      if [ -n "$_df" ]; then printf 'doc %s :\n' "$_dname" ; head -n "$_dl" -- "$_df" ; else printf 'doc %s\n' "$_dname" ; fi
    done
  fi
}
_sec_summary() {
  printf '== THE LOCAL MODEL SUMMARY ==\n'
  _sf=$(cfg abs second 2>/dev/null)
  _sm=""; _ex=none; _sy=none
  if [ -n "$_sf" ] && [ -f "$_sf" ]; then
    _sm=$(_flat "$_sf" | awk -F'\t' '$1 ~ /^summary\./ { print $2; exit }')
    _ex=$(_flat "$_sf" | awk -F'\t' '$1 == "exchanges" { print $2; exit }')
    _sy=$(_flat "$_sf" | awk -F'\t' '$1 == "stamp" { print $2; exit }')
  fi
  if [ -n "$_sm" ]; then
    printf 'exchanges %s ; written %s\n%s\n' "${_ex:-none}" "${_sy:-none}" "$_sm"
  else
    printf 'no summary yet\n'
  fi
}
_sec_plan() {
  printf '== THE LOADED SKILL PLAN ==\n'
  _pll=$(cfg num head.second_plan_lines 8) || _pll=8
  _pl=$(plan_status 2>/dev/null | head -n "$_pll")
  if [ -n "$_pl" ]; then printf '%s\n' "$_pl"; else printf 'no open plan\n'; fi
}
_sec_project_plan() {
  _bpf=$(skl_big_file 2>/dev/null)
  [ -n "$_bpf" ] || return 0
  printf '== THE PROJECT PLAN ==\n'
  _bpt=$(_skl_big_body "$_bpf" 2>/dev/null)
  if [ -z "$_bpt" ]; then printf 'the big plan is not written\n' ; else
    printf '%s\n' "$_bpt" | awk '
      { l = $0 ; sub(/^[ \t]*[0-9]+:[ \t]*"?/, "", l) ; sub(/"?[ \t]*$/, "", l)
        if (l ~ /^\[in_progress\]/) { sub(/^\[in_progress\][ \t]*/, "", l) ; ip = l }
        else if (l ~ /^\[completed\]/) { sub(/^\[completed\][ \t]*/, "", l) ; lc = l }
        else if (l ~ /^\[todo\]/) { sub(/^\[todo\][ \t]*/, "", l) ; if (nx == "") nx = l } }
      END {
        if (lc != "") printf "done : %s\n", lc
        printf "now  : %s\n", (ip != "" ? ip : "nothing in progress")
        printf "next : %s\n", (nx != "" ? nx : "nothing left")
      }'
  fi
}
_sec_note() {
  printf '== THE STICKY NOTE ==\n'
  _sn=$(cfg abs note 2>/dev/null)
  if [ -n "$_sn" ] && [ -s "$_sn" ]; then head -c 1200 "$_sn"; printf '\n'; else printf 'the note is empty\n'; fi
}
_sec_agents() {
  printf '== THE AGENTS ==\n'
  _main=$(cfg str agents.main jarvis)
  _st=$(_turn_get '.status // "idle"')
  _al=$(cfg num head.second_agents_lines 30) || _al=30
  _ac=$(cfg num head.second_agents_chars 2000) || _ac=2000
  for _a in $(cfg str agents.names "$_main"); do
    if [ "$_a" = "$_main" ] && [ "$_st" = running ]; then
      printf '%s  active : a turn runs\n' "$_a"
    else
      printf '%s  idle : no turn runs\n' "$_a"
    fi
  done | head -n "$_al" | awk -v c="$_ac" '{ print substr($0,1,c) }'
}
_sec_chat() {
  printf '== THE CHAT ==\n'
  _cf=$(cfg str agents.chat 2>/dev/null)
  case $_cf in ""|/*) ;; *) _cf="$LA_ROOT/$_cf" ;; esac
  _ml=$(cfg num head.second_msg_lines 6) || _ml=6
  _mc=$(cfg num head.second_msg_chars 120) || _mc=120
  if [ -n "$_cf" ] && [ -s "$_cf" ]; then
    grep '^{' "$_cf" | tail -n "$_ml" | jq -r --argjson mc "$_mc" '(.from // "?") + " -> " + (.to // "?") + " : " + ((.body // "") | .[0:$mc])' 2>/dev/null
  else
    printf 'the chat is empty\n'
  fi
}
_sec_toolset() {
  printf '== THE TOOLSET ==\n'
  _tln=$(cfg num head.second_tools_lines 40) || _tln=40
  _tl=$(printf '%s' "$(_turn_get '.tools')" | jq -r '.[]? | select(.function.name != "reply" and .function.name != "kill_proc" and .function.name != "toolset") | "- " + .function.name + " : " + (.function.description // "")' 2>/dev/null)
  [ -n "$_tl" ] && printf '%s\n' "$_tl" | head -n "$_tln" || printf 'no tool\n'
}
