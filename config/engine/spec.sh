#!/bin/sh
# spec.sh - LA LOI SE MONTE ICI, EN UN SEUL ENDROIT (config/engine/spec.sh).
#
# write_spec REMPLIT le canon (une loi par son numero, ou une section entiere) ; update_spec MET A
# JOUR une loi QUI EXISTE DEJA. Les deux ecrivent la MEME ligne, au MEME endroit : law_write().
# Deux gestes, une mecanique -- et c est ici qu elle vit.
#
# LC_ALL=C ; POSIX sh (dash) ; ecriture atomique (un temporaire, puis mv) ; une Loi fait au plus
# 100 octets (le cap vit dans le skill, pas ici).
LC_ALL=C
export LC_ALL

law_write() {   # $1 fichier  $2 numero  $3 la loi montee : UNE loi, dans SA section
  F="$1"; ID="$2"; R="$3"
  T="$F.$$.tmp"
  awk -v id="$ID" -v new="$R" '
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
    END { if (!placed && !seen) { print "refuse : aucune section du spec ne porte la centaine " band > "/dev/stderr" ; exit 9 } if (!placed) print new }
  ' "$F" > "$T" || { rm -f "$T" ; return 1 ; }
  [ -s "$T" ] || { rm -f "$T" ; return 1 ; }
  # LE CAP JUGE LA LOI QU ON ECRIT, PAS L HERITAGE : le spec porte des lignes trop
  # longues d avant cette regle, et set_law n a pas a refuser d ecrire a cause d elles.
  mv -f "$T" "$F" || { rm -f "$T" ; return 1 ; }
  return 0
}
