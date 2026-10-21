# id: E05
# role: the bounds. what comes back is cut here and nowhere else, and a big return becomes a handle.

# cap_bytes <max> : stdin, at most max bytes, the cut is said
cap_bytes() {
  _m=${1:-0}
  [ "$_m" -gt 0 ] 2>/dev/null || { cat; return 0; }
  awk -v m="$_m" 'BEGIN { n = 0; cut = 0 }
    {
      line = $0 "\n"
      if (!cut && n + length(line) > m) {
        keep = m - n
        if (keep > 0) { printf "%s", substr(line, 1, keep) }
        printf "\n[cut at %d bytes]", m
        cut = 1
      }
      if (!cut) { printf "%s", line; n += length(line) }
    }'
}

# cap_head <lines> : the first lines, the rest is said
cap_head() {
  _m=${1:-0}
  [ "$_m" -gt 0 ] 2>/dev/null || { cat; return 0; }
  awk -v m="$_m" 'NR <= m { print; next }
    NR == m + 1 { printf "[cut at %d lines]\n", m }'
}

# cap_tail <lines> : the last lines, the start is said
cap_tail() {
  _m=${1:-0}
  [ "$_m" -gt 0 ] 2>/dev/null || { cat; return 0; }
  awk -v m="$_m" '{ b[NR % m] = $0; n = NR }
    END {
      if (n <= m) { for (i = 1; i <= n; i++) print b[i % m]; exit }
      printf "[cut at %d lines]\n", m
      for (i = n - m + 1; i <= n; i++) print b[i % m]
    }'
}

# cap_lines <max> : stdin cut to max lines, the middle goes first
cap_lines() {
  _m=${1:-0}
  _all=$(cat)
  _n=$(printf '%s\n' "$_all" | wc -l)
  if [ "$_m" -le 0 ] 2>/dev/null || [ "$_n" -le "$_m" ]; then
    printf '%s\n' "$_all"
    return 0
  fi
  _head=$(( _m * 2 / 3 ))
  _tail=$(( _m - _head ))
  printf '%s\n' "$_all" | head -n "$_head"
  printf '[cut: %s lines in the middle]\n' "$(( _n - _m ))"
  printf '%s\n' "$_all" | tail -n "$_tail"
}

# cap_return <label> : stdin, short stays as it is, long becomes a file and its path
# the bound is read, never written here: a missing key is a refusal, not a default.
cap_return() {
  _l=${1:-return}
  _max=$(conf_num limits.return_bytes) || { printf '[return refused: limits.return_bytes is not set]\n'; return 1; }
  _t=$(tmpfile "$_l") || return 1
  cat > "$_t" || { rm -f -- "$_t"; return 1; }
  _n=$(wc -c < "$_t" | tr -d ' ')
  if [ "$_n" -le "$_max" ]; then
    cat -- "$_t"
    rm -f -- "$_t"
    return 0
  fi
  _d=$(cfg path returns) || return 1
  [ -d "$_d" ] || mkdir -p -- "$_d" || return 1
  _p="$_d/$_l.$(date +%s).txt"
  mv -f -- "$_t" "$_p" || return 1
  case $_p in
    "$ROOT"/*) _p=${_p#"$ROOT"/} ;;
  esac
  printf '[return of %s bytes: %s]\n' "$_n" "$_p"
}
