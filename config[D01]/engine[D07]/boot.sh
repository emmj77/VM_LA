# id: E03
# role: the only sourced line. it finds the master file, loads cfg, then every brick by its key.
# two names are written here and nowhere else: the master file, and cfg.sh, the reader of it.
# a directory name carries [Dxx], and brackets are a glob class: no glob is used on a path.
HERE=${LA_DIR:?boot: LA_DIR is not set, boot is only sourced by la.sh}
LA_HOME=$(dirname -- "$HERE")
ROOT=$(dirname -- "$LA_HOME")
LA_CONF=$(find "$LA_HOME" -maxdepth 2 -name la_config.yaml -print 2>/dev/null | head -n 1)
[ -n "$LA_CONF" ] && [ -r "$LA_CONF" ] || { echo "boot: no master file in $LA_HOME" >&2; return 1 2>/dev/null || exit 1; }
# the INDEX: the only list of folders and files. the document checks it, cfg reads it.
LA_INDEX=$(find "$LA_HOME" -maxdepth 3 -name index_la.yaml -print 2>/dev/null | head -n 1)
[ -n "$LA_INDEX" ] && [ -r "$LA_INDEX" ] || { echo "boot: no index in $LA_HOME" >&2; return 1 2>/dev/null || exit 1; }
export LA_INDEX
# THE STATE DIRECTORY IS FOUND BEFORE ANY BRICK NEEDS IT (MOUSSA, 21/10): the map of the tree
# lives there, and without it every lookup walked the whole disk again.
LA_STATE_BOOT=$(find "$LA_HOME" -maxdepth 2 -type d -name 'state\[D*\]' -print 2>/dev/null | head -n 1)
[ -n "$LA_STATE_BOOT" ] && { LA_STATE="$LA_STATE_BOOT"; export LA_STATE; }
LC_ALL=C
export LC_ALL
. "$HERE/cfg.sh" || { echo "boot: cfg failed" >&2; return 1 2>/dev/null || exit 1; }
# le maitre est lu et aplati UNE fois : les trente-cinq lectures qui suivaient etaient une seconde
_flat >/dev/null 2>&1 || :
for b in msg fs tab skl canon shape args cap run shell approval step; do
  p=$(cfg abs "$b" 2>/dev/null)
  [ -n "$p" ] && [ -f "$p" ] || p="$HERE/$b.sh"
  [ -f "$p" ] || { echo "boot: no such brick: $b" >&2; return 1 2>/dev/null || exit 1; }
  . "$p" || { echo "boot: cannot load $b" >&2; return 1 2>/dev/null || exit 1; }
done
# the names a program reads: one origin, one moment, never a path built by hand
export LA_ROOT="$ROOT"
export LA_CONFIG="$LA_CONF"
export LA_STATE="$(cfg path state)"
export LA_DATA="$(cfg path data)"
export LA_RETURNS="$(cfg path returns)"
export LA_AUDIO="$(cfg path audio)"
export LA_PAGE="$(cfg path page)"
export LA_BOARD="$(cfg abs board)"
export LA_TOOL="$(cfg abs la)"
export LA_SESSIONS_DB="$(cfg abs sessions)"
export LA_MEMORY_DB="$(cfg abs memory)"
export LA_TRACE="$(cfg abs trace)"
export LA_REPLY_STREAM="$(cfg abs reply_stream)"
export LA_ENV="$(cfg abs env)"
export LA_HOST="$(cfg str models.host 127.0.0.1)"
export LA_BRIDGE_HOST="$(cfg str bridge.host 0.0.0.0)"
export LA_PORT_BRIDGE="$(cfg num ports.bridge)"
export LA_PORT_DASH="$(cfg num ports.dash)"
export LA_PORT_TLS="$(cfg num ports.tls)"
export LA_CERT="$(cfg abs bridge_cert 2>/dev/null)"
export LA_KEY="$(cfg abs bridge_key 2>/dev/null)"
export LA_PORT_TTS="$(cfg num units.tts.port)"
export LA_TTS_SID="$(cfg num machine.tts.sid 1)"
export LA_TTS_THREADS="$(cfg num machine.tts.threads 8)"
export LA_TTS_MODEL="$(cfg str machine.tts.model)"
export LA_GGUF="$(cfg str machine.llama.gguf)"
export LA_APK_FILE="$(cfg str machine.app.apk)"
export LA_PORT_MODELS="$(cfg num units.models.port)"
export LA_PORT_ASR="$(cfg num units.asr.port)"
export LA_CAP_BYTES="$(cfg num limits.return_bytes)"
export LA_CAP_LINES="$(cfg num limits.engine_lines)"
unset b p
# ROOT is the tree root and never moves. W is where an armed project writes.
W=$(canon_root 2>/dev/null)
[ -n "$W" ] || W=$ROOT
_s=$(skl_workspace 2>/dev/null) && [ -n "$_s" ] && W="$W/${_s%/}"
unset _s
export LA_WRITEABLE_WORKSPACE="$W"
