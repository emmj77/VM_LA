#!/bin/sh
# bridge.sh - LE BRIDGE. Le lien direct entre le telephone et le harness.
#
# POURQUOI CE NOM. Le gateway, c'est l'EXPOSITION : le tunnel prive qui fait entrer une requete
# de l'exterieur (le 24/7 de LA.md). Ici il n'y a rien de tel -- deux bords, le telephone et le
# harness, et un proc qui porte la demande d'un bord a l'autre et rapporte la reply. C'est un
# PONT. Le gateway viendra se poser DEVANT, et ce sera un autre proc.
#
# MODES : start | stop_bridge | status | request | help
#
# LES ROUTES
#   GET  /ping           il est vivant, et il dit ce qu'il sert.
#   GET  /plan           l'etat du plan, par le tool `load_plan` de la table. AUCUN modele.
#   GET  /audio/<nom>    rend un wav de config/audio/.
#   GET  /        ET /widget   LE WIDGET : une seule vue (l'ecoute, la photo, le texte, le
#                        plan, l'adresse active). Une PAGE, pas un canal : elle n'appelle que
#                        les routes d'ici, et elle ne connait aucun tool.
#   GET  /engine         les adresses DECLAREES (alias, provider, model, active), lues par
#                        engine_switch.sh. Aucune valeur de secret ne sort.
#   POST /engine         {"alias":"..."} : PREND cette adresse ; le manager change le mot
#                        `active` dans la config, et rien d'autre.
#   POST /say            le corps EST la demande en texte (ou {"text":"..."}) ; le loop la joue.
#   POST /voice          le corps EST un audio (wav, webm, mp4, m4a ou ogg) : pose sous
#                        config/audio/, le tool `transcribe` le transcrit, et le texte obtenu
#                        DEVIENT la demande.
#   POST /image          le corps EST une image (png, jpg ou webp) : posee sous work/, le tool
#                        `see_image` la lit, et ce qu'il en dit DEVIENT la demande. Meme forme
#                        que la voix : l'image est une ENTREE, pas un canal de plus.
#
# LA REPLY PORTE TOUJOURS TROIS CHAMPS : la reponse du loop, le wav du tour s'il y en a un, et le
# code de sortie du loop.
#
# CE QUE LE BRIDGE NE FAIT PAS. Il ne decide rien, il ne parle pas au modele, il ne connait aucun
# tool par coeur : il lit la TABLE pour trouver un id, et il lance le loop. Le loop reste la seule
# tete ; le bridge n'est qu'une porte.
#
# ENTREE (env)
#   LA_BRIDGE_ADDRESS   defaut 127.0.0.1
#   LA_BRIDGE_PORT      defaut 8765
#   LA_LOOP             defaut le loop du projet ; pour un essai, n'importe quelle commande
#
# SORTIE : son journal vit sous work/ (bridge.log), sa marque aussi (bridge.pid).

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# la bibliotheque commune (ts, active_skill) : UNE definition, pas une copie par brique.
[ -f "$HERE/lib.sh" ] || { printf 'bridge: the common library is missing (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"
TABLE="$ROOT/config/la_tools.yaml"
W="$ROOT/work"
# TOUT L AUDIO VIT ICI, ET NULLE PART AILLEURS : ce qui SORT (la voix du tour) comme ce qui ENTRE
# (l audio du telephone). Un dossier a part, purge par audio_purge.sh, pour que le disque ne se
# remplisse pas en silence. Le NOM des fichiers ne change pas : seul leur dossier a change.
AUDIO="$ROOT/config/audio"
LOOP=${LA_LOOP:-"$HERE/loop.sh"}
ENGINE="$HERE/engine.sh"
SWITCH="$HERE/engine_switch.sh"
WIDGET="$ROOT/config/widget.html"
SH=$(command -v dash 2>/dev/null) || SH=$(command -v sh)
ADDRESS=${LA_BRIDGE_ADDRESS:-127.0.0.1}
PORT=${LA_BRIDGE_PORT:-8765}
TLSPORT=${LA_BRIDGE_TLS_PORT:-8766}
MANIFEST="$ROOT/config/widget.webmanifest"
ICON="$ROOT/config/widget-icon.svg"
SWF="$ROOT/config/widget-sw.js"
CERT="$ROOT/config/certs/bridge-cert.pem"
KEY="$ROOT/config/certs/bridge-key.pem"
PID_FILE="$W/bridge.pid"
PID_TLS="$W/bridge-tls.pid"
# L APK DU TELEPHONE. Le poste le SERT, le telephone le prend : pas de cable, pas d adb.
APKFILE=${LA_APK:-/home/moussa/Applications/LA-widget/app/build/outputs/apk/debug/app-debug.apk}
LOGF="$W/bridge.log"

log_to_file() { printf '%s  %s\n' "$(ts)" "$1" >> "$LOGF" 2>/dev/null || true; }

# L'ID D'UN TOOL SE LIT PAR SON NOM. L'id n'est pas une position : la table porte la
# correspondance, et personne d'autre.
id_of() {
  awk -v n="$1" '
    /^  - id: /   { id = $3 }
    /^    tool: / { if ($2 == n) { print id; exit } }' "$TABLE" 2>/dev/null
}

# LE TYPE ANNONCE DONNE L EXTENSION. Un corps binaire ne dit pas ce qu'il est : on ne le
# devine pas, on lit l'en-tete de la requete, et on refuse ce qu'on ne sait pas nommer.
ext_of() {  # $1 = le Content-Type
  case "$1" in
    *webm*) printf 'webm' ;;
    *mp4*|*m4a*|*aac*) printf 'm4a' ;;
    *ogg*|*opus*) printf 'ogg' ;;
    *wav*|*wave*) printf 'wav' ;;
    *png*) printf 'png' ;;
    *webp*) printf 'webp' ;;
    *jpeg*|*jpg*) printf 'jpg' ;;
    *) printf '' ;;
  esac
}

# UNE REPLY HTTP, LE CORPS DANS UN FICHIER (le wav est rendu tel quel, sans passer par du texte).
answer() {  # $1 = code, $2 = type, $3 = fichier du corps, $4 = nom du telechargement (facultatif)
  printf 'HTTP/1.0 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\n' \
    "$1" "$2" "$(wc -c < "$3" | tr -d ' ')"
  # UN NOM DE FICHIER SE DIT, IL NE SE DEVINE PAS. Sans cet en-tete, le navigateur nomme le
  # telechargement d apres la ROUTE : /apk rendait un fichier appele apk.apk. Le $4 le nomme.
  [ -z "${4:-}" ] || printf 'Content-Disposition: attachment; filename="%s"\r\n' "$4"
  printf 'Connection: close\r\n\r\n'
  cat "$3"
}

# DIRE UN MOT : le tool `speak` prononce un texte, et le wav entre dans la liste du tour.
# Le pont ne compose RIEN : il fait dire ce que la boucle a dit, et rien de plus.
speak_word() {  # $1 = le mot a dire ; $2 = le dossier du tour
  local G W N
  G=$(id_of speak)
  [ -n "$G" ] || return 0
  W=$(printf '%s' "$1" | head -c 600)
  [ -n "$W" ] || return 0
  [ -n "$(printf '%s' "$W" | tr -d '[:space:]')" ] || return 0
  if printf '%s' "$W" | LA_APPROVED=1 "$SH" "$ENGINE" "$G" > "$2/spoken" 2>>"$LOGF"; then
    N=$(sed -n 's/.*speech : config\/audio\/\([^ ]*\).*/\1/p' "$2/spoken" 2>/dev/null | head -n 1)
    if [ -n "$N" ]; then
      printf '%s\n' "$N" >> "$2/said"
      printf '%s\n' "$N" >> "$ROOT/work/dits.jsonl" 2>/dev/null || true
      printf '%s' "$W" > "$2/last"
      log_to_file "voix  dit ($(printf '%s' "$W" | wc -c) octets) -> $N"
    fi
  fi
}

# UN TOUR : la demande entre par l'entree standard du loop, la reply sort, et la voix du tour est
# repereE a l'horodatage (le tool `speak` ecrit son wav sous config/audio/).
turn() {  # $1 = la demande ; $2 = le fichier ou poser le corps JSON ; $3 = "voice" si la demande
          # est venue PAR LA VOIX : la reply repart alors par la voix
  # local : ces noms NE DOIVENT PAS deborder sur les variables de l'appelant (T porte le
  # dossier de la requete ; l'ecraser ici, et la reply s'ecrit dans un dossier efface).
  local T RC AV IDS R L N LPID LIST ALREADY FIFO JOURNAL
  T=$(mktemp -d) || { printf '{"response":"","audio":"","code":70}\n' > "$2"; return 1; }
  touch "$T/mark"
  : > "$T/said"       # les wav dits PENDANT le tour, dans l ordre
  : > "$T/last"    # le dernier mot prononce, pour ne pas le redire a la fin
  # LE JOURNAL DES TOOLS DE CE TOUR : la boucle l ecrit en JSONL (une ligne par tool) des que
  # LA_LOG_FILE est pose. La route /journal le rend au widget (lois 610/1712/1432). On repart
  # d un fichier vide a chaque tour : le widget ne voit que le tour courant.
  JOURNAL="$W/journal.jsonl"
  : > "$JOURNAL" 2>/dev/null || true
  # LA LISTE DES WAV DU TOUR, ELLE AUSSI PARTAGEE : meme fichier de work/ que le journal, remis a
  # zero a chaque tour. L'appli la relit AU FIL DE L EAU : elle entend chaque mot des qu il est
  # pret, au lieu d attendre que le tour soit fini et de recevoir le dernier wav en une fois.
  : > "$ROOT/work/dits.jsonl" 2>/dev/null || true

  # LE TOUR COURT, ET SA VOIX EST SURVEILLEE. Le loop tourne en arriere-plan : sa sortie
  # standard porte la reply, sa sortie d erreur porte le JOURNAL et LE CANAL HUMAIN - c est la
  # que talk, answer et ask posent leur mot. On lit ce canal AU FIL DE L EAU, et chaque mot
  # dit est PRONONCE TOUT DE SUITE, au lieu d attendre que tout le travail soit fini.
  #   Un tour venu de la VOIX recoit LA_VOICE=1 : la loop exige alors du modele un talk court
  # en ouverture, et l humain entend quelque chose des les premieres secondes au lieu d attendre
  # la fin. Un tour venu du TEXTE reste muet, et ne paie pas un appel de modele de plus.
  FIFO="$T/pipe"
  if mkfifo "$FIFO" 2>/dev/null; then
    if [ "${3:-}" = voice ]; then
      printf '%s\n' "$1" | LA_VOICE=1 LA_LOG_FILE="$JOURNAL" "$SH" "$LOOP" > "$T/reply" 2> "$FIFO" &
    else
      printf '%s\n' "$1" | LA_LOG_FILE="$JOURNAL" "$SH" "$LOOP" > "$T/reply" 2> "$FIFO" &
    fi
    LPID=$!
    while IFS= read -r L; do
      printf '%s\n' "$L" >> "$LOGF" 2>/dev/null || true   # le journal garde tout, comme avant
      case "$L" in
        # le JOURNAL du loop (horodate, ou prefixe) n est PAS de la parole : on ne le dit pas.
        ''|loop:*|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) continue ;;
      esac
      # UN MOT POUR L HUMAIN : prononce MAINTENANT, pendant que le tour continue.
      [ "${3:-}" = voice ] && speak_word "$L" "$T"
    done < "$FIFO"
    wait "$LPID"
    RC=$?
  else
    # REPLI : sans fifo (systeme de fichiers exotique), on retombe sur l ancien chemin -
    # tout le tour, puis la reply, une seule fois.
    printf '%s\n' "$1" | LA_LOG_FILE="$JOURNAL" "$SH" "$LOOP" > "$T/reply" 2>>"$LOGF"
    RC=$?
  fi
  # LE DERNIER WAV SE LIT DANS LA LISTE DU TOUR, PAS DANS LE DOSSIER : l ordre de `find` n est
  # pas l ordre du temps, et des qu un tour dit plusieurs mots, il designait le mauvais fichier.
  AV=$(tail -n 1 "$T/said" 2>/dev/null || true)
  # LA REPLY DEVIENT AUDIBLE. Un tour venu par la VOIX repart par la voix : le pont nomme le
  # tool `speak` (le meme que le modele nommerait) sur le TEXTE de la reply, et son wav tombe
  # dans config/audio/ - c'est lui que la reply reprend. Le pont ne decide RIEN de la
  # reply : il fait entendre ce que la boucle a rendu, et rien de plus.
  #   LE TEXTE DIT EST BORNE A 600 OCTETS, ET COUPE A LA DERNIERE PHRASE FINIE : la voix
  # permanente coute ~0,17 s par seconde de son plus ~1 s fixe, et l'appli n'attend que 180 s
  # pour un tour ENTIER (transcription + modele + voix). Une reply plus longue s'entend par
  # son debut complet, et se lit en entier a l'ecran. Le tour venu par le TEXTE reste du
  # texte : aucune synthese n'est lancee.
  ALREADY=$(cat "$T/last" 2>/dev/null || true)
  if [ "${3:-}" = voice ]; then
    IDS=$(id_of speak)
    R=$(head -c 600 "$T/reply" 2>/dev/null)
    if [ "$(head -c 601 "$T/reply" 2>/dev/null | wc -c)" -gt 600 ]; then
      R=$(printf '%s' "$R" | tr '\n' ' ' | awk '{ i=0; for (k=1; k<=length($0); k++) { c=substr($0,k,1); if (c=="." || c=="!" || c=="?") i=k } if (i>60) print substr($0,1,i); else print }')
    fi
    if [ -n "$IDS" ] && [ -n "$R" ] && [ "$R" != "$ALREADY" ]; then
      printf '%s' "$R" | LA_APPROVED=1 "$SH" "$ENGINE" "$IDS" > "$T/spoken" 2>>"$LOGF"
      log_to_file "voix  reply dite ($(printf '%s' "$R" | wc -c) octets) -> $(cat "$T/spoken" 2>/dev/null | tr '\n\t' '  ' | cut -c1-140)"
      N=$(sed -n 's/.*speech : config\/audio\/\([^ ]*\).*/\1/p' "$T/spoken" 2>/dev/null | head -n 1)
      if [ -n "$N" ]; then
        printf '%s\n' "$N" >> "$T/said"
        printf '%s\n' "$N" >> "$W/dits.jsonl" 2>/dev/null || true
        AV=$N
      else
        AV=$(find "$AUDIO" -maxdepth 1 -name 'speech-*.wav' -newer "$T/mark" 2>/dev/null | sort | tail -n 1)
      fi
    fi
  fi
  [ -n "$AV" ] && AV=${AV##*/}
  # LA LISTE DES WAV DU TOUR, DANS L ORDRE OU ILS ONT ETE DITS : le telephone peut les tirer un
  # par un (champ `audios`). Le champ `audio` reste ce qu'il etait - le DERNIER - pour que
  # l'appli d'aujourd'hui ne voie aucune difference.
  LIST=$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$T/said" 2>/dev/null) || LIST='[]'
  case "${LIST:-}" in '['*) ;; *) LIST='[]' ;; esac
  if jq -cn --rawfile r "$T/reply" --arg a "${AV:-}" --argjson l "$LIST" --argjson c "$RC" \
       '{response:$r, audio:$a, audios:$l, code:$c}' > "$2" 2>/dev/null; then
    :
  else
    printf '{"response":"la reply n a pas pu etre mise en shape","audio":"","code":%s}\n' "$RC" > "$2"
  fi
  rm -f "$T/reply" "$T/mark" "$T/spoken" 2>/dev/null
  rmdir "$T" 2>/dev/null
}

# LA REQUETE : une seule par connexion, puis on ferme.
request() {
  T=$(mktemp -d) || exit 1
  trap 'rm -f "$T"/* 2>/dev/null; rmdir "$T" 2>/dev/null' EXIT

  IFS= read -r L || exit 0
  L=$(printf '%s' "$L" | tr -d '\r')
  M=${L%% *}
  Q=$(printf '%s' "$L" | cut -d' ' -f2)

  CL=0
  CT=
  while IFS= read -r H; do
    H=$(printf '%s' "$H" | tr -d '\r')
    [ -n "$H" ] || break
    case "$H" in
      [Cc]ontent-[Ll]ength:*) CL=$(printf '%s' "$H" | sed 's/^[^:]*:[[:space:]]*//') ;;
      [Cc]ontent-[Tt]ype:*)   CT=$(printf '%s' "$H" | sed 's/^[^:]*:[[:space:]]*//') ;;
    esac
  done
  case "$CL" in ''|*[!0-9]*) CL=0 ;; esac
  [ "$CL" -le 16000000 ] || CL=0
  head -c "$CL" > "$T/body" 2>/dev/null

  log_to_file "$M $Q"

  case "$Q" in
    /ping*)
      printf '{"state":"alive","address":"%s","port":"%s","loop":"%s","ts":"%s"}\n' \
        "$ADDRESS" "$PORT" "${LOOP##*/}" "$(ts)" > "$T/out"
      answer 200 application/json "$T/out"
      ;;

    /plan*)
      ID=$(id_of load_plan)
      if [ -z "$ID" ]; then
        printf '{"error":"la table ne porte pas load_plan"}\n' > "$T/out"
        answer 500 application/json "$T/out"
      else
        "$SH" "$ENGINE" "$ID" < /dev/null > "$T/out" 2>>"$LOGF"
        answer 200 application/json "$T/out"
      fi
      ;;

    /journal*)
      # LE JOURNAL DES TOOLS DU TOUR COURANT (lois 610/1712/1432) : la boucle l a ecrit en
      # JSONL sous work/journal.jsonl ; ici on le rend tel quel, en tableau JSON.
      if [ -f "$W/journal.jsonl" ]; then
        jq -R -s -c 'split("\n") | map(select(length>0)) | map(try fromjson catch empty)' \
          "$W/journal.jsonl" > "$T/out" 2>/dev/null || printf '[]\n' > "$T/out"
        case "$(head -c 1 "$T/out" 2>/dev/null)" in '[') ;; *) printf '[]\n' > "$T/out" ;; esac
      else
        printf '[]\n' > "$T/out"
      fi
      answer 200 application/json "$T/out"
      ;;

    /dits*)
      # LES WAV DU TOUR COURANT, DANS L ORDRE OU ILS ONT ETE DITS : la mecanique du journal
      # (loi 610) -- un fichier de work/, remis a zero a chaque tour, que l'appli relit au fil de
      # l eau pour ENTENDRE pendant le tour, au lieu d attendre la fin pour un seul wav.
      if [ -f "$W/dits.jsonl" ]; then
        jq -R -s -c 'split("\n") | map(select(length>0))' "$W/dits.jsonl" > "$T/out" 2>/dev/null || printf '[]\n' > "$T/out"
        case "$(head -c 1 "$T/out" 2>/dev/null)" in '[') ;; *) printf '[]\n' > "$T/out" ;; esac
      else
        printf '[]\n' > "$T/out"
      fi
      answer 200 application/json "$T/out"
      ;;

    /audio/*)
      N=${Q#/audio/}
      case "$N" in ''|*[!A-Za-z0-9_./-]*|*..*) N= ;; esac
      N=${N##*/}
      case "$N" in ''|*[!A-Za-z0-9_.-]*) N= ;; esac
      if [ -n "$N" ] && [ -f "$AUDIO/$N" ]; then
        answer 200 audio/wav "$AUDIO/$N"
      else
        printf '{"error":"wav introuvable"}\n' > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /say|/say/*)
      if [ "$M" != POST ]; then
        printf '{"error":"POST attendu pour /say"}\n' > "$T/out"
        answer 405 application/json "$T/out"
      else
        D=$(cat "$T/body" 2>/dev/null)
        case "$D" in
          '{'*) X=$(printf '%s' "$D" | jq -r '.text // empty' 2>/dev/null); [ -n "$X" ] && D=$X ;;
        esac
        if [ -z "$D" ]; then
          printf '{"error":"demande vide"}\n' > "$T/out"
          answer 400 application/json "$T/out"
        else
          log_to_file "dire  $(printf '%s' "$D" | tr '\n\t' '  ' | cut -c1-120)"
          turn "$D" "$T/out"
          answer 200 application/json "$T/out"
        fi
      fi
      ;;

    /voice|/voice/*)
      if [ "$M" != POST ]; then
        printf '{"error":"POST attendu pour /voice"}\n' > "$T/out"
        answer 405 application/json "$T/out"
      elif [ ! -s "$T/body" ]; then
        printf '{"error":"aucun audio dans le corps"}\n' > "$T/out"
        answer 400 application/json "$T/out"
      elif [ -z "$(ext_of "$CT")" ]; then
        printf '{"error":"type audio inconnu (%s) ; wav, webm, mp4 ou ogg"}\n' "${CT:-absent}" > "$T/out"
        answer 415 application/json "$T/out"
      else
        N="voice-$(date -u +%Y%m%d-%H%M%S)-$$.$(ext_of "$CT")"
        if ! cp "$T/body" "$AUDIO/$N" 2>/dev/null; then
          printf '{"error":"l audio n a pas pu etre pose dans config/audio"}\n' > "$T/out"
          answer 500 application/json "$T/out"
        else
          IDT=$(id_of transcribe)
          if [ -z "$IDT" ]; then
            printf '{"error":"la table ne porte pas transcribe"}\n' > "$T/out"
            answer 500 application/json "$T/out"
          else
            "$SH" "$ENGINE" "$IDT" "$N" < /dev/null > "$T/tr" 2>>"$LOGF"
            D=$(jq -r '.result // empty' "$T/tr" 2>/dev/null | tr -d '\r' | sed -e 's/[[:space:]]*$//')
            if [ -z "$D" ]; then
              printf '{"error":"la transcription n a rien render","audio":"%s"}\n' "$N" > "$T/out"
              answer 500 application/json "$T/out"
            else
              log_to_file "voix  $N -> $(printf '%s' "$D" | tr '\n\t' '  ' | cut -c1-120)"
              turn "$D" "$T/out1" voice
              if jq -c --arg d "$D" '. + {request:$d}' "$T/out1" > "$T/out" 2>/dev/null; then
                :
              else
                cp "$T/out1" "$T/out"
              fi
              answer 200 application/json "$T/out"
            fi
          fi
        fi
      fi
      ;;

    /|/widget|/widget/*)
      if [ -f "$WIDGET" ]; then
        answer 200 "text/html; charset=utf-8" "$WIDGET"
      else
        printf '{"error":"le widget est introuvable (%s)"}\n' "$WIDGET" > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /engine|/engine/*)
      if [ "$M" = POST ]; then
        A=$(jq -r '.alias // empty' "$T/body" 2>/dev/null)
        if [ -z "$A" ]; then
          printf '{"error":"POST /engine attend un corps JSON avec un alias"}\n' > "$T/out"
          answer 400 application/json "$T/out"
        elif L=$("$SH" "$SWITCH" take "$A" 2>&1); then
          log_to_file "adresse $A"
          if jq -cn --arg l "$L" --arg a "$A" '{line:$l, alias:$a}' > "$T/out" 2>/dev/null; then :; else
            printf '{"line":"%s"}\n' "$L" > "$T/out"
          fi
          answer 200 application/json "$T/out"
        else
          if jq -cn --arg e "$L" '{error:$e}' > "$T/out" 2>/dev/null; then :; else
            printf '{"error":"le changement d adresse a echoue"}\n' > "$T/out"
          fi
          answer 500 application/json "$T/out"
        fi
      else
        if L=$("$SH" "$SWITCH" list 2>&1); then
          printf '{"engines":%s}\n' "$L" > "$T/out"
          answer 200 application/json "$T/out"
        else
          printf '{"error":"les adresses n ont pas pu etre lues"}\n' > "$T/out"
          answer 500 application/json "$T/out"
        fi
      fi
      ;;

    /image|/image/*)
      if [ "$M" != POST ]; then
        printf '{"error":"POST attendu pour /image"}\n' > "$T/out"
        answer 405 application/json "$T/out"
      elif [ ! -s "$T/body" ]; then
        printf '{"error":"aucune image dans le corps"}\n' > "$T/out"
        answer 400 application/json "$T/out"
      else
        EXT=$(ext_of "$CT")
        case "$EXT" in png|jpg|webp) ;; *) EXT=jpg ;; esac
        N="image-$(date -u +%Y%m%d-%H%M%S)-$$.$EXT"
        if ! cp "$T/body" "$W/$N" 2>/dev/null; then
          printf '{"error":"l image n a pas pu etre posee dans l espace de travail"}\n' > "$T/out"
          answer 500 application/json "$T/out"
        else
          IDV=$(id_of see_image)
          if [ -z "$IDV" ]; then
            printf '{"error":"la table ne porte pas see_image"}\n' > "$T/out"
            answer 500 application/json "$T/out"
          else
            "$SH" "$ENGINE" "$IDV" "$N" < /dev/null > "$T/vi" 2>>"$LOGF"
            D=$(jq -r '.result // empty' "$T/vi" 2>/dev/null | tr -d '\r' | sed -e 's/[[:space:]]*$//')
            if [ -z "$D" ]; then
              printf '{"error":"la vision n a rien render","image":"%s"}\n' "$N" > "$T/out"
              answer 500 application/json "$T/out"
            else
              log_to_file "image $N -> $(printf '%s' "$D" | tr '\n\t' '  ' | cut -c1-120)"
              # LA DEMANDE NE SE REDUIT PAS A LA LECTURE. La vision dit ce qu elle voit ; la
              # demande doit dire D OU ELLE VIENT et CE QU ON ATTEND : sinon le modele principal,
              # qui ne voit pas l image, repond qu aucune image ne lui est parvenue.
              REQUEST="Je viens de te donner une photo a voir, celle que je viens de prendre. Ce que la vision en dit : $D
Reponds a ce que j en attends : dis-moi ce que cette image montre, et ce qu il y a d utile a en retenir."
              log_to_file "demande posee au modele : $(printf '%s' "$REQUEST" | tr '\n\t' '  ' | cut -c1-120)"
              turn "$REQUEST" "$T/out1"
              if jq -c --arg d "$REQUEST" --arg i "$N" '. + {request:$d, image:$i}' "$T/out1" > "$T/out" 2>/dev/null; then
                :
              else
                cp "$T/out1" "$T/out"
              fi
              answer 200 application/json "$T/out"
            fi
          fi
        fi
      fi
      ;;

    /apk|/la.apk)
      if [ -f "$APKFILE" ]; then
        answer 200 "application/vnd.android.package-archive" "$APKFILE" "LA.apk"
      else
        printf '{"error":"l APK n est pas bati sur la station (%s)"}\n' "$APKFILE" > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /manifest.webmanifest)
      if [ -f "$MANIFEST" ]; then
        answer 200 "application/manifest+json" "$MANIFEST"
      else
        printf '{"error":"le manifeste est introuvable"}\n' > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /icon.svg)
      if [ -f "$ICON" ]; then
        answer 200 "image/svg+xml" "$ICON"
      else
        printf '{"error":"l icone est introuvable"}\n' > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /sw.js)
      if [ -f "$SWF" ]; then
        answer 200 "text/javascript; charset=utf-8" "$SWF"
      else
        printf '{"error":"le fichier du widget est introuvable"}\n' > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    *)
      printf '{"error":"route inconnue","routes":["GET /","GET /widget","GET /la.apk","GET /manifest.webmanifest","GET /icon.svg","GET /sw.js","GET /ping","GET /plan","GET /journal","GET /dits","GET /engine","POST /engine","GET /audio/<nom>","POST /say","POST /voice","POST /image"]}\n' > "$T/out"
      answer 404 application/json "$T/out"
      ;;
  esac
  exit 0
}

# --- LES MODES -----------------------------------------------------------------
start() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    printf 'bridge: il tourne deja (pid %s)\n' "$(cat "$PID_FILE")"
    return 0
  fi
  command -v socat >/dev/null 2>&1 || { printf 'bridge: socat est absent de la station\n' >&2; return 1; }
  socat TCP-LISTEN:"$PORT",bind="$ADDRESS",reuseaddr,fork EXEC:"$SH $0 request" \
    >/dev/null 2>>"$LOGF" &
  printf '%s\n' "$!" > "$PID_FILE"
  printf 'bridge: la porte est ouverte sur %s:%s (pid %s)\n' "$ADDRESS" "$PORT" "$!"
  log_to_file "start  $ADDRESS:$PORT"
}

stop_bridge() {
  [ -f "$PID_FILE" ] || { printf 'bridge: rien a arreter\n'; return 0; }
  P=$(cat "$PID_FILE")
  case "$P" in
    ''|*[!0-9]*) printf 'bridge: la marque est illisible, je la jette\n' ;;
    *) if kill "$P" 2>/dev/null; then printf 'bridge: arrete (pid %s)\n' "$P"
       else printf 'bridge: le pid %s ne repondait plus\n' "$P"; fi ;;
  esac
  rm -f "$PID_FILE"
  log_to_file "stop"
}

# LA PORTE CHIFFREE. Android refuse getUserMedia (la voix) et l'installation sur l'ecran
# d'accueil a une page servie en clair : il exige un CONTEXTE SECURISE. Ce mode ouvre le
# meme pont sur TLS, avec un certificat AUTO-SIGNE pose sur le poste. Le telephone le refuse
# la premiere fois, on l'accepte une fois, et la voix s'ouvre.
# Ce n'est PAS le tunnel prive du canon (une adresse qui vient de l'exterieur) : c'est le
# meme pont, chiffre, sur le reseau local. Le tunnel viendra se poser DEVANT.
start_tls() {
  if [ -f "$PID_TLS" ] && kill -0 "$(cat "$PID_TLS")" 2>/dev/null; then
    printf 'bridge: la porte chiffree tourne deja (pid %s)\n' "$(cat "$PID_TLS")"
    return 0
  fi
  [ -f "$CERT" ] && [ -f "$KEY" ] || { printf 'bridge: le certificat manque (%s / %s) : genere-le d abord\n' "$CERT" "$KEY" >&2; return 1; }
  command -v socat >/dev/null 2>&1 || { printf 'bridge: socat est absent de la station\n' >&2; return 1; }
  socat OPENSSL-LISTEN:"$TLSPORT",bind="$ADDRESS",cert="$CERT",key="$KEY",verify=0,reuseaddr,fork \
    EXEC:"$SH $0 request" >/dev/null 2>>"$LOGF" &
  printf '%s\n' "$!" > "$PID_TLS"
  printf 'bridge: la porte chiffree est ouverte sur https://%s:%s (pid %s)\n' "$ADDRESS" "$TLSPORT" "$!"
  log_to_file "start-tls $ADDRESS:$TLSPORT"
}

stop_tls() {
  [ -f "$PID_TLS" ] || { printf 'bridge: la porte chiffree ne tourne pas\n'; return 0; }
  P=$(cat "$PID_TLS")
  case "$P" in
    ''|*[!0-9]*) printf 'bridge: la marque de la porte chiffree est illisible, je la jette\n' ;;
    *) if kill "$P" 2>/dev/null; then printf 'bridge: porte chiffree arretee (pid %s)\n' "$P"
       else printf 'bridge: le pid %s ne repondait plus\n' "$P"; fi ;;
  esac
  rm -f "$PID_TLS"
  log_to_file "stop-tls"
}

status() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    printf 'bridge: il tourne (pid %s) sur %s:%s\n' "$(cat "$PID_FILE")" "$ADDRESS" "$PORT"
  else
    printf 'bridge: il ne tourne pas\n'
  fi
  printf 'bridge: loop servi = %s\n' "$LOOP"
  printf 'bridge: log_line = %s ligne(s)\n' "$(wc -l < "$LOGF" 2>/dev/null | tr -d ' ' || printf 0)"
  printf 'bridge: les ids lus dans la table : load_plan=%s transcribe=%s\n' \
    "$(id_of load_plan)" "$(id_of transcribe)"
}

help() {
  sed -n '2,32p' "$0"
}

case "${1:-help}" in
  start)      start ;;
  stop_bridge)       stop_bridge ;;
  start-tls)  start_tls ;;
  stop-tls)   stop_tls ;;
  status)     status ;;
  request)    request ;;
  help|*)     help ;;
esac
