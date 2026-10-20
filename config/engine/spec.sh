#!/usr/bin/dash
# french in code is forbidden
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

law_write() {   # $1 fichier  $2 numero  $3 la loi montee : UNE loi, dans SA section
  F="$1"; ID="$2"; R="$3"
  T="$F.$$.tmp"
  awk -v id="$ID" -v new="$R" -v msg="$(msg spec_band "$((ID / 100 * 100))")" '
    function num(s,  a) { if (match(s, /[0-9]+/)) return substr(s, RSTART, RLENGTH) + 0; return -1 }
    BEGIN { placed = 0 ; band = int(id / 100) * 100 ; inband = 0 ; seen = 0 }
    /^SECTION : / { if (inband && !placed) { print new ; placed = 1 } inband = 0 ; print ; next }
    /^  [0-9]+:/ {
      cur = num($0)
      if (int(cur / 100) * 100 == band) {
        if (!inband) { inband = 1 ; seen = 1 }
        if (cur == id) { print new ; placed = 1 ; next }
        if (!placed && cur > id) { print new ; placed = 1 }
      } else if (inband && !placed) { print new ; placed = 1 ; inband = 0 }
      print ; next
    }
    { print }
    END { if (!placed && !seen) { print msg > "/dev/stderr" ; exit 9 } if (!placed) print new }
  ' "$F" > "$T" || { rm -f "$T" ; return 1 ; }
  [ -s "$T" ] || { rm -f "$T" ; return 1 ; }
  mv -f "$T" "$F" || { rm -f "$T" ; return 1 ; }
  return 0
}
