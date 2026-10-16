#!/bin/sh
# bridge.sh - THE BRIDGE. The direct link between the phone and the harness.
#
# WHY THIS NAME. The gateway is the EXPOSITION : the private tunnel that lets a request in from
# the outside (the 24/7 of LA.md). Here there is nothing of the sort -- two shores, the phone and
# the harness, and a proc that carries the demand from one shore to the other and brings back the
# reply. It is a BRIDGE. The gateway will come to sit IN FRONT, and that will be another proc.
#
# MODES : start | stop_bridge | status | request | help
#
# THE ROUTES
#   GET  /ping           it is alive, and it says what it serves.
#   GET  /plan           the plan state, through the `load_plan` tool of the table. NO model.
#   GET  /audio/<name>   returns a wav of config/audio/.
#   GET  /        AND /widget   THE WIDGET : a single view (the listening, the photo, the text,
#                        the plan, the active address). A PAGE, not a channel : it calls only the
#                        routes from here, and it knows no tool.
#   GET  /engine         the DECLARED addresses (alias, provider, model, active), read by
#                        engine_switch.sh. No secret value leaves.
#   POST /engine         {"alias":"..."} : TAKES that address ; the manager changes the word
#                        `active` in the config, and nothing else.
#   POST /say            the body IS the text demand (or {"text":"..."}) ; the loop plays it.
#   POST /voice          the body IS an audio (wav, webm, mp4, m4a or ogg) : placed under
#                        config/audio/, the `transcribe` tool transcribes it, and the text obtained
#                        BECOMES the demand.
#   POST /image          the body IS an image (png, jpg or webp) : placed under work/, the
#                        `see_image` tool reads it, and what it says BECOMES the demand. Same shape
#                        as the voice : the image is an INPUT, not one more channel.
#
# THE REPLY ALWAYS CARRIES THREE FIELDS : the loop's response, the turn's wav if there is one, and
# the loop's exit code.
#
# WHAT THE BRIDGE DOES NOT DO. It decides nothing, it does not talk to the model, it knows no tool
# by heart : it reads the TABLE to find an id, and it launches the loop. The loop stays the single
# head ; the bridge is only a door.
#
# INPUT (env)
#   LA_BRIDGE_ADDRESS   default 127.0.0.1
#   LA_BRIDGE_PORT      default 8765
#   LA_LOOP             default the project's loop ; for a test, any command
#
# OUTPUT : its journal lives under work/ (bridge.log), its mark too (bridge.pid).

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# the common library (ts, active_skill) : ONE definition, not one copy per brick.
[ -f "$HERE/lib.sh" ] || { printf 'bridge: the common library is missing (%s)\n' "$HERE/lib.sh" >&2 ; exit 2 ; }
. "$HERE/lib.sh"
TABLE="$ROOT/config/la_tools.yaml"
W="$ROOT/work"
# LE MOT DE L'ARRET (loi 476). Le pont ARME le sommeil du tour : ce fichier n'existe pas tant que
# l'humain n'a rien dit. La route /stop le TOUCHE ; le tool `sleep` le voit a la seconde suivante
# et rend un fait NOMME (jamais une mort muette). Un seul fichier pour la machine : deux tours
# paralleles s'arretent ensemble -- c'est la marque par tour qui viendra avec le veilleur.
STOP="$W/stop"
# ALL THE AUDIO LIVES HERE, AND NOWHERE ELSE : what GOES OUT (the turn's voice) as what COMES IN
# (the phone's audio). A separate folder, purged by audio_purge.sh, so the disk does not fill up in
# silence. The NAME of the files does not change : only their folder changed.
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
# THE PHONE'S APK. The desktop SERVES it, the phone takes it : no cable, no adb.
APKFILE=${LA_APK:-/home/moussa/Applications/LA-widget/app/build/outputs/apk/debug/LA-app.apk}
LOGF="$W/bridge.log"

log_to_file() { printf '%s  %s\n' "$(ts)" "$1" >> "$LOGF" 2>/dev/null || true; }

# A TOOL'S ID IS READ BY ITS NAME. The id is not a position : the table carries the correspondence,
# and no one else.
id_of() {
  awk -v n="$1" '
    /^  - id: /   { id = $3 }
    /^    tool: / { if ($2 == n) { print id; exit } }' "$TABLE" 2>/dev/null
}

# THE ANNOUNCED TYPE GIVES THE EXTENSION. A binary body does not say what it is : we do not guess
# it, we read the request header, and we refuse what we cannot name.
ext_of() {  # $1 = the Content-Type
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

# AN HTTP REPLY, THE BODY IN A FILE (the wav is returned as is, without going through text).
answer() {  # $1 = code, $2 = type, $3 = body file, $4 = download name (optional)
  printf 'HTTP/1.0 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\n' \
    "$1" "$2" "$(wc -c < "$3" | tr -d ' ')"
  # A FILE NAME IS SAID, IT IS NOT GUESSED. Without this header, the browser names the download
  # after the ROUTE : /apk returned a file called apk.apk. The $4 names it.
  [ -z "${4:-}" ] || printf 'Content-Disposition: attachment; filename="%s"\r\n' "$4"
  printf 'Connection: close\r\n\r\n'
  cat "$3"
}

# SAY A WORD : the `speak` tool pronounces a text, and the wav enters the turn's list.
# The bridge composes NOTHING : it makes heard what the loop said, and nothing more.
speak_word() {  # $1 = the word to say ; $2 = the turn folder
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
      printf '%s\n' "$N" >> "$ROOT/work/spoken.jsonl" 2>/dev/null || true
      printf '%s' "$W" > "$2/last"
      log_to_file "voice  said ($(printf '%s' "$W" | wc -c) bytes) -> $N"
    fi
  fi
}

# A TURN : the demand enters through the loop's standard input, the reply comes out, and the turn's
# voice is located at the timestamp (the `speak` tool writes its wav under config/audio/).
turn() {  # $1 = the demand ; $2 = the file where to place the JSON body ; $3 = "voice" if the demand
          # came BY VOICE : the reply then leaves by voice
  # local : these names MUST NOT overflow onto the caller's variables (T carries the request
  # folder ; overwrite it here, and the reply is written into a deleted folder).
  local T RC AV IDS R L N LPID LIST ALREADY FIFO JOURNAL
  T=$(mktemp -d) || { printf '{"response":"","audio":"","code":70}\n' > "$2"; return 1; }
  touch "$T/mark"
  : > "$T/said"       # the wavs said DURING the turn, in order
  : > "$T/last"    # the last word pronounced, so as not to say it again at the end
  # THE TOOLS JOURNAL OF THIS TURN : the loop writes it as JSONL (one line per tool) as soon as
  # LA_LOG_FILE is set. The /journal route returns it to the widget (laws 610/1712/1432). We start
  # from an empty file at each turn : the widget sees only the current turn.
  JOURNAL="$W/journal.jsonl"
  : > "$JOURNAL" 2>/dev/null || true
  # THE LIST OF THE TURN'S WAVS, ALSO SHARED : the same work/ file as the journal, reset at each
  # turn. The app re-reads it AS IT GOES : it hears each word as soon as it is ready, instead of
  # waiting for the turn to finish and receiving the last wav in one go.
  : > "$ROOT/work/spoken.jsonl" 2>/dev/null || true
  # LE TOUR PART SANS MOT D'ARRET : on retire celui du tour precedent, sinon la premiere seconde
  # du sommeil tomberait sur le mot d'hier. Le fichier est CREE par /stop, jamais par le tour.
  rm -f "$STOP" 2>/dev/null || true

  # THE TURN IS SHORT, AND ITS VOICE IS WATCHED. The loop runs in the background : its standard
  # output carries the reply, its error output carries the JOURNAL and THE HUMAN CHANNEL - that is
  # where talk, answer and ask place their word. We read that channel AS IT GOES, and each said word
  # is PRONOUNCED RIGHT AWAY, instead of waiting for all the work to be done.
  #   A turn come from VOICE receives LA_VOICE=1 : the loop then demands a short talk from the model
  # at the opening, and the human hears something within the first seconds instead of waiting for
  # the end. A turn come from TEXT stays mute, and does not pay one more model call.
  FIFO="$T/pipe"
  if mkfifo "$FIFO" 2>/dev/null; then
    if [ "${3:-}" = voice ]; then
      printf '%s\n' "$1" | LA_VOICE=1 LA_LOG_FILE="$JOURNAL" LA_STOP_FILE="$STOP" "$SH" "$LOOP" > "$T/reply" 2> "$FIFO" &
    else
      printf '%s\n' "$1" | LA_LOG_FILE="$JOURNAL" LA_STOP_FILE="$STOP" "$SH" "$LOOP" > "$T/reply" 2> "$FIFO" &
    fi
    LPID=$!
    while IFS= read -r L; do
      printf '%s\n' "$L" >> "$LOGF" 2>/dev/null || true   # the journal keeps everything, as before
      case "$L" in
        # the loop's JOURNAL (timestamped, or prefixed) is NOT speech : we do not say it.
        ''|loop:*|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) continue ;;
      esac
      # A WORD FOR THE HUMAN : pronounced NOW, while the turn continues.
      [ "${3:-}" = voice ] && speak_word "$L" "$T"
    done < "$FIFO"
    wait "$LPID"
    RC=$?
  else
    # FALLBACK : without a fifo (exotic filesystem), we fall back on the old path -
    # the whole turn, then the reply, once.
    printf '%s\n' "$1" | LA_LOG_FILE="$JOURNAL" LA_STOP_FILE="$STOP" "$SH" "$LOOP" > "$T/reply" 2>>"$LOGF"
    RC=$?
  fi
  # THE LAST WAV IS READ IN THE TURN'S LIST, NOT IN THE FOLDER : `find`'s order is not time's
  # order, and as soon as a turn says several words, it pointed to the wrong file.
  AV=$(tail -n 1 "$T/said" 2>/dev/null || true)
  # THE REPLY BECOMES AUDIBLE. A turn come by VOICE leaves by voice : the bridge names the `speak`
  # tool (the same one the model would name) on the reply TEXT, and its wav falls into config/audio/
  # - it is that one the reply takes. The bridge decides NOTHING of the reply : it makes heard what
  # the loop returned, and nothing more.
  #   THE SAID TEXT IS BOUNDED TO 600 BYTES, AND CUT AT THE LAST FINISHED SENTENCE : the permanent
  # voice costs ~0.17 s per second of sound plus ~1 s fixed, and the app waits only 180 s for a
  # WHOLE turn (transcription + model + voice). A longer reply is heard by its complete beginning,
  # and read in full on the screen. The turn come by TEXT stays text : no synthesis is launched.
  ALREADY=$(cat "$T/last" 2>/dev/null || true)
  if [ "${3:-}" = voice ]; then
    IDS=$(id_of speak)
    R=$(head -c 600 "$T/reply" 2>/dev/null)
    if [ "$(head -c 601 "$T/reply" 2>/dev/null | wc -c)" -gt 600 ]; then
      R=$(printf '%s' "$R" | tr '\n' ' ' | awk '{ i=0; for (k=1; k<=length($0); k++) { c=substr($0,k,1); if (c=="." || c=="!" || c=="?") i=k } if (i>60) print substr($0,1,i); else print }')
    fi
    if [ -n "$IDS" ] && [ -n "$R" ] && [ "$R" != "$ALREADY" ]; then
      printf '%s' "$R" | LA_APPROVED=1 "$SH" "$ENGINE" "$IDS" > "$T/spoken" 2>>"$LOGF"
      log_to_file "voice  reply said ($(printf '%s' "$R" | wc -c) bytes) -> $(cat "$T/spoken" 2>/dev/null | tr '\n\t' '  ' | cut -c1-140)"
      N=$(sed -n 's/.*speech : config\/audio\/\([^ ]*\).*/\1/p' "$T/spoken" 2>/dev/null | head -n 1)
      if [ -n "$N" ]; then
        printf '%s\n' "$N" >> "$T/said"
        printf '%s\n' "$N" >> "$W/spoken.jsonl" 2>/dev/null || true
        AV=$N
      else
        AV=$(find "$AUDIO" -maxdepth 1 -name 'speech-*.wav' -newer "$T/mark" 2>/dev/null | sort | tail -n 1)
      fi
    fi
  fi
  [ -n "$AV" ] && AV=${AV##*/}
  # THE LIST OF THE TURN'S WAVS, IN THE ORDER THEY WERE SAID : the phone can pull them one by one
  # (field `audios`). The field `audio` stays what it was - the LAST - so the app of today sees no
  # difference.
  LIST=$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$T/said" 2>/dev/null) || LIST='[]'
  case "${LIST:-}" in '['*) ;; *) LIST='[]' ;; esac
  if jq -cn --rawfile r "$T/reply" --arg a "${AV:-}" --argjson l "$LIST" --argjson c "$RC" \
       '{response:$r, audio:$a, audios:$l, code:$c}' > "$2" 2>/dev/null; then
    :
  else
    printf '{"response":"the reply could not be shaped","audio":"","code":%s}\n' "$RC" > "$2"
  fi
  rm -f "$T/reply" "$T/mark" "$T/spoken" 2>/dev/null
  rmdir "$T" 2>/dev/null
}

# THE REQUEST : a single one per connection, then we close.
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
        printf '{"error":"the table does not carry load_plan"}\n' > "$T/out"
        answer 500 application/json "$T/out"
      else
        "$SH" "$ENGINE" "$ID" < /dev/null > "$T/out" 2>>"$LOGF"
        answer 200 application/json "$T/out"
      fi
      ;;

    /stop*)
      # LE MOT DE L'HUMAIN (loi 476). On ne tue RIEN ici : on POSE le mot. Le sommeil du tour en
      # cours le voit a la seconde suivante et rend un fait nomme (« sommeil : interrompu a N s
      # sur M, mot de l humain »). Un tour qui ne dort pas n'est pas touche : il finit son travail
      # (couper un tour reste un INT/TERM, un autre geste, loi 339).
      if printf '%s\n' "$(ts)" > "$STOP" 2>/dev/null; then
        printf '{"state":"word placed","file":"%s","ts":"%s"}\n' "$STOP" "$(ts)" > "$T/out"
        answer 200 application/json "$T/out"
      else
        printf '{"error":"the word could not be placed","file":"%s"}\n' "$STOP" > "$T/out"
        answer 500 application/json "$T/out"
      fi
      ;;

    /journal*)
      # THE TOOLS JOURNAL OF THE CURRENT TURN (laws 610/1712/1432) : the loop wrote it as JSONL
      # under work/journal.jsonl ; here we return it as is, as a JSON array.
      if [ -f "$W/journal.jsonl" ]; then
        jq -R -s -c 'split("\n") | map(select(length>0)) | map(try fromjson catch empty)' \
          "$W/journal.jsonl" > "$T/out" 2>/dev/null || printf '[]\n' > "$T/out"
        case "$(head -c 1 "$T/out" 2>/dev/null)" in '[') ;; *) printf '[]\n' > "$T/out" ;; esac
      else
        printf '[]\n' > "$T/out"
      fi
      answer 200 application/json "$T/out"
      ;;

    /spoken*)
      # THE WAVS OF THE CURRENT TURN, IN THE ORDER THEY WERE SAID : the journal's mechanics
      # (law 610) -- a work/ file, reset at each turn, that the app re-reads as it goes to HEAR
      # during the turn, instead of waiting for the end for a single wav.
      if [ -f "$W/spoken.jsonl" ]; then
        jq -R -s -c 'split("\n") | map(select(length>0))' "$W/spoken.jsonl" > "$T/out" 2>/dev/null || printf '[]\n' > "$T/out"
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
        printf '{"error":"wav not found"}\n' > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /say|/say/*)
      if [ "$M" != POST ]; then
        printf '{"error":"POST expected for /say"}\n' > "$T/out"
        answer 405 application/json "$T/out"
      else
        D=$(cat "$T/body" 2>/dev/null)
        case "$D" in
          '{'*) X=$(printf '%s' "$D" | jq -r '.text // empty' 2>/dev/null); [ -n "$X" ] && D=$X ;;
        esac
        if [ -z "$D" ]; then
          printf '{"error":"empty demand"}\n' > "$T/out"
          answer 400 application/json "$T/out"
        else
          log_to_file "say  $(printf '%s' "$D" | tr '\n\t' '  ' | cut -c1-120)"
          turn "$D" "$T/out"
          answer 200 application/json "$T/out"
        fi
      fi
      ;;

    /voice|/voice/*)
      if [ "$M" != POST ]; then
        printf '{"error":"POST expected for /voice"}\n' > "$T/out"
        answer 405 application/json "$T/out"
      elif [ ! -s "$T/body" ]; then
        printf '{"error":"no audio in the body"}\n' > "$T/out"
        answer 400 application/json "$T/out"
      elif [ -z "$(ext_of "$CT")" ]; then
        printf '{"error":"unknown audio type (%s) ; wav, webm, mp4 or ogg"}\n' "${CT:-absent}" > "$T/out"
        answer 415 application/json "$T/out"
      else
        N="voice-$(date -u +%Y%m%d-%H%M%S)-$$.$(ext_of "$CT")"
        if ! cp "$T/body" "$AUDIO/$N" 2>/dev/null; then
          printf '{"error":"the audio could not be placed in config/audio"}\n' > "$T/out"
          answer 500 application/json "$T/out"
        else
          IDT=$(id_of transcribe)
          if [ -z "$IDT" ]; then
            printf '{"error":"the table does not carry transcribe"}\n' > "$T/out"
            answer 500 application/json "$T/out"
          else
            "$SH" "$ENGINE" "$IDT" "$N" < /dev/null > "$T/tr" 2>>"$LOGF"
            D=$(jq -r '.result // empty' "$T/tr" 2>/dev/null | tr -d '\r' | sed -e 's/[[:space:]]*$//')
            if [ -z "$D" ]; then
              printf '{"error":"the transcription returned nothing","audio":"%s"}\n' "$N" > "$T/out"
              answer 500 application/json "$T/out"
            else
              log_to_file "voice  $N -> $(printf '%s' "$D" | tr '\n\t' '  ' | cut -c1-120)"
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
        printf '{"error":"the widget is not found (%s)"}\n' "$WIDGET" > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /engine|/engine/*)
      if [ "$M" = POST ]; then
        A=$(jq -r '.alias // empty' "$T/body" 2>/dev/null)
        if [ -z "$A" ]; then
          printf '{"error":"POST /engine expects a JSON body with an alias"}\n' > "$T/out"
          answer 400 application/json "$T/out"
        elif L=$("$SH" "$SWITCH" take "$A" 2>&1); then
          log_to_file "address $A"
          if jq -cn --arg l "$L" --arg a "$A" '{line:$l, alias:$a}' > "$T/out" 2>/dev/null; then :; else
            printf '{"line":"%s"}\n' "$L" > "$T/out"
          fi
          answer 200 application/json "$T/out"
        else
          if jq -cn --arg e "$L" '{error:$e}' > "$T/out" 2>/dev/null; then :; else
            printf '{"error":"the address change failed"}\n' > "$T/out"
          fi
          answer 500 application/json "$T/out"
        fi
      else
        if L=$("$SH" "$SWITCH" list 2>&1); then
          printf '{"engines":%s}\n' "$L" > "$T/out"
          answer 200 application/json "$T/out"
        else
          printf '{"error":"the addresses could not be read"}\n' > "$T/out"
          answer 500 application/json "$T/out"
        fi
      fi
      ;;

    /image|/image/*)
      if [ "$M" != POST ]; then
        printf '{"error":"POST expected for /image"}\n' > "$T/out"
        answer 405 application/json "$T/out"
      elif [ ! -s "$T/body" ]; then
        printf '{"error":"no image in the body"}\n' > "$T/out"
        answer 400 application/json "$T/out"
      else
        EXT=$(ext_of "$CT")
        case "$EXT" in png|jpg|webp) ;; *) EXT=jpg ;; esac
        N="image-$(date -u +%Y%m%d-%H%M%S)-$$.$EXT"
        if ! cp "$T/body" "$W/$N" 2>/dev/null; then
          printf '{"error":"the image could not be placed in the workspace"}\n' > "$T/out"
          answer 500 application/json "$T/out"
        else
          IDV=$(id_of see_image)
          if [ -z "$IDV" ]; then
            printf '{"error":"the table does not carry see_image"}\n' > "$T/out"
            answer 500 application/json "$T/out"
          else
            "$SH" "$ENGINE" "$IDV" "$N" < /dev/null > "$T/vi" 2>>"$LOGF"
            D=$(jq -r '.result // empty' "$T/vi" 2>/dev/null | tr -d '\r' | sed -e 's/[[:space:]]*$//')
            if [ -z "$D" ]; then
              printf '{"error":"the vision returned nothing","image":"%s"}\n' "$N" > "$T/out"
              answer 500 application/json "$T/out"
            else
              log_to_file "image $N -> $(printf '%s' "$D" | tr '\n\t' '  ' | cut -c1-120)"
              # THE DEMAND DOES NOT REDUCE TO THE READING. The vision says what it sees ; the demand
              # must say WHERE IT COMES FROM and WHAT IS EXPECTED : otherwise the main model, which
              # does not see the image, answers that no image reached it. (The request is the HUMAN'S
              # VOICE : it stays in French.)
              REQUEST="Je viens de te donner une photo a voir, celle que je viens de prendre. Ce que la vision en dit : $D
Reponds a ce que j en attends : dis-moi ce que cette image montre, et ce qu il y a d utile a en retenir."
              log_to_file "demand placed to the model : $(printf '%s' "$REQUEST" | tr '\n\t' '  ' | cut -c1-120)"
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

    /apk|/LA-app.apk)
      if [ -f "$APKFILE" ]; then
        answer 200 "application/vnd.android.package-archive" "$APKFILE" "LA-app.apk"
      else
        printf '{"error":"the APK is not built on the station (%s)"}\n' "$APKFILE" > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /manifest.webmanifest)
      if [ -f "$MANIFEST" ]; then
        answer 200 "application/manifest+json" "$MANIFEST"
      else
        printf '{"error":"the manifest is not found"}\n' > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /icon.svg)
      if [ -f "$ICON" ]; then
        answer 200 "image/svg+xml" "$ICON"
      else
        printf '{"error":"the icon is not found"}\n' > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    /sw.js)
      if [ -f "$SWF" ]; then
        answer 200 "text/javascript; charset=utf-8" "$SWF"
      else
        printf '{"error":"the widget file is not found"}\n' > "$T/out"
        answer 404 application/json "$T/out"
      fi
      ;;

    *)
      printf '{"error":"unknown route","routes":["GET /","GET /widget","GET /LA-app.apk","GET /manifest.webmanifest","GET /icon.svg","GET /sw.js","GET /ping","GET /plan","GET /journal","GET /spoken","GET /engine","POST /engine","GET /audio/<name>","POST /say","POST /voice","POST /image","POST /stop"]}\n' > "$T/out"
      answer 404 application/json "$T/out"
      ;;
  esac
  exit 0
}

# --- THE MODES -----------------------------------------------------------------
start() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    printf 'bridge: it is already running (pid %s)\n' "$(cat "$PID_FILE")"
    return 0
  fi
  command -v socat >/dev/null 2>&1 || { printf 'bridge: socat is absent from the station\n' >&2; return 1; }
  socat TCP-LISTEN:"$PORT",bind="$ADDRESS",reuseaddr,fork EXEC:"$SH $0 request" \
    >/dev/null 2>>"$LOGF" &
  printf '%s\n' "$!" > "$PID_FILE"
  printf 'bridge: the door is open on %s:%s (pid %s)\n' "$ADDRESS" "$PORT" "$!"
  log_to_file "start  $ADDRESS:$PORT"
}

stop_bridge() {
  [ -f "$PID_FILE" ] || { printf 'bridge: nothing to stop\n'; return 0; }
  P=$(cat "$PID_FILE")
  case "$P" in
    ''|*[!0-9]*) printf 'bridge: the mark is unreadable, I drop it\n' ;;
    *) if kill "$P" 2>/dev/null; then printf 'bridge: stopped (pid %s)\n' "$P"
       else printf 'bridge: pid %s no longer answered\n' "$P"; fi ;;
  esac
  rm -f "$PID_FILE"
  log_to_file "stop"
}

# THE ENCRYPTED DOOR. Android refuses getUserMedia (the voice) and the home-screen install on a
# page served in clear : it demands a SECURE CONTEXT. This mode opens the same bridge over TLS, with
# a SELF-SIGNED certificate placed on the desktop. The phone refuses it the first time, one accepts
# it once, and the voice opens.
# This is NOT the canon's private tunnel (an address coming from the outside) : it is the same
# bridge, encrypted, on the local network. The tunnel will come to sit IN FRONT.
start_tls() {
  if [ -f "$PID_TLS" ] && kill -0 "$(cat "$PID_TLS")" 2>/dev/null; then
    printf 'bridge: the encrypted door is already running (pid %s)\n' "$(cat "$PID_TLS")"
    return 0
  fi
  [ -f "$CERT" ] && [ -f "$KEY" ] || { printf 'bridge: the certificate is missing (%s / %s) : generate it first\n' "$CERT" "$KEY" >&2; return 1; }
  command -v socat >/dev/null 2>&1 || { printf 'bridge: socat is absent from the station\n' >&2; return 1; }
  socat OPENSSL-LISTEN:"$TLSPORT",bind="$ADDRESS",cert="$CERT",key="$KEY",verify=0,reuseaddr,fork \
    EXEC:"$SH $0 request" >/dev/null 2>>"$LOGF" &
  printf '%s\n' "$!" > "$PID_TLS"
  printf 'bridge: the encrypted door is open on https://%s:%s (pid %s)\n' "$ADDRESS" "$TLSPORT" "$!"
  log_to_file "start-tls $ADDRESS:$TLSPORT"
}

stop_tls() {
  [ -f "$PID_TLS" ] || { printf 'bridge: the encrypted door is not running\n'; return 0; }
  P=$(cat "$PID_TLS")
  case "$P" in
    ''|*[!0-9]*) printf 'bridge: the encrypted door mark is unreadable, I drop it\n' ;;
    *) if kill "$P" 2>/dev/null; then printf 'bridge: encrypted door stopped (pid %s)\n' "$P"
       else printf 'bridge: pid %s no longer answered\n' "$P"; fi ;;
  esac
  rm -f "$PID_TLS"
  log_to_file "stop-tls"
}

status() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    printf 'bridge: it runs (pid %s) on %s:%s\n' "$(cat "$PID_FILE")" "$ADDRESS" "$PORT"
  else
    printf 'bridge: it does not run\n'
  fi
  printf 'bridge: loop served = %s\n' "$LOOP"
  printf 'bridge: log_line = %s line(s)\n' "$(wc -l < "$LOGF" 2>/dev/null | tr -d ' ' || printf 0)"
  printf 'bridge: the ids read in the table : load_plan=%s transcribe=%s\n' \
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
