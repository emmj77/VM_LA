# ENGINE AUDIT — 2026-10-20

Method : codegraph index (`codegraph init --yes .`, 2553 files / 560 nodes), then a
line-by-line read of every `.sh` (24 files, 3069 lines) and every `.py` (13 files,
6057 lines) of `config/engine` and `config/programs`, compared with the canon
(`projects/la/spec.yaml`, 899 lines) and with `docs/state-registry.md`.
Every finding below was reproduced on the live harness (CLI `la`, dashboard :8770,
engine.sh, plan.sh) — no finding is inferred from reading alone.

Vocabulary rule applied : identifiers, keys, file names, function names and every
string the AGENT reads are in English. Strings the HUMAN reads (panel, doctor,
messages.yaml, service logs) stay French : that is his language.

---

## AUDIT 1 — THE SHELL ENGINE (`config/engine/*.sh`)

    file                lines   verdict
    loop.sh              1429   the turn : 6 real bugs
    engine.sh             597   1 data-loss risk, French identifiers
    second.sh             424   1 dead path (wrong file name)
    doctor.sh             416   2 false checks
    lib.sh                396   ok (2 minor)
    update.sh             151   ok
    summary.sh            113   ok
    trim_forms.sh         125   French markers written into agent text
    plan.sh               146   SEVERE : data loss on `change`
    la.sh                 117   ok
    watcher.sh             91   usage() prints code
    session_note.sh       120   ok
    approval.sh            76   ok
    tunnel.sh              60   ok
    pick.sh / asr / tts / models / board / spec / signal_task / audio_purge / backup   ok

### S1 (SEVERE) `plan.sh` destroys every section that follows PLAN

`change` runs `clear` (which removes the section) and then `rewrite` (which cuts the
file again on the OLD `END_POS`). After `clear` the file is shorter, so the tail from
the old offset is silently dropped. Reproduced on a copy of a skill :

    PLAN:, followed by PERIMETER: workspace + type-file
    $ plan.sh change probe "goal"   ->   PERIMETER: and workspace: are GONE

Reachable from the agent through `change_big_todo` (project plans) and from any
skill file whose PLAN section is not the last one. `rewrite` already replaces the
whole section, so `clear` is pure loss : it must not be called.

### S2 (SEVERE) the live channel has a reader and no writer

The previous refactor moved the reasoning into `messages.reasoning` and stopped
writing `thinking.jsonl` / `journal.jsonl`. But `dash.live()` (`/api/live`) and the
`board.py` tailers still read those files, and `board.read_turn()` now parses
`bridge.log` as JSON. Result : "WHAT GOES THROUGH" is always empty in the panel, the
live panel of the dashboard never shows a tool call, and `one_turn()` (`la --say`)
never prints a step. Worse, `read_traffic()` greps the French `echec de transport`,
a wording the loop no longer uses, so the failure counter is stuck at 0.

Fix : one live file, `config/state/trace.jsonl`, written by `loop.sh` only
(`kind: think | tool | end`), read by `dash.live()`, `board.read_turn()`,
`board.Tailer` and `dash.js` unchanged. `docs/state-registry.md` is updated : the
file moves from DEAD to KEEP.

### S3 `second.sh` points at a file that does not exist

`FAMF=$CONF_DIR/filtre/family.bin` while the shipped path is `config/filter/family.bin`
(`paths.filter`). The "unjudged reads" warning can never fire : a silent false
negative on the 180-law family check. The French directory name is the same bug seen
from the vocabulary side.

### S4 `doctor.sh` cries fault on a normal state

- no `skills/.active` is reported as a FAULT, but that is the normal state after a
  plan is completed (`loop.sh` removes the file on purpose, law 921). Measured : the
  doctor exits 1 on a healthy harness.
- the tunnel check looks for `-- outils:` in project specs, the loop looks for
  `tools:` : the step-tool check has never matched anything.
- the "required keys" check only harvests `conf_require`, never `conf_req_num`.

### S5 `trim_prog` (loop.sh) can nest two truncation markers

`coupe($cap)` clips, then the budget pass clips the already-clipped text and writes a
second `[... TRUNCATED ...]` inside the first. Harmless content-wise, unreadable for
the model. The same function is named `coupe` — French in code.

### S6 French in agent-facing strings and identifiers

- `loop.sh` : `SCOPE_TXT` blocks (5), `"l humain a dit :"`, `"le resultat de ... arrive juste
  apres"`, `def coupe`, plus a comment block.
- `trim_forms.sh` : jq identifiers `marque / raccourci / dernier / reste / forme` and the
  markers `[retour range ...]`, `[... RACCOURCI ...]` written INTO the tool result the
  model reads.
- `engine.sh` : embedded Blender python (`--fichier`, `convertir`, `_appeler`, `manque`).
- `second.sh` : `T_reads_unjudged`.

### S7 minors
`lib.sh` trap expands `$CLEAN` unquoted ; `plan.sh` `T=$TMPFILE || ...` never fires on an
empty `TMPFILE` ; `watcher.sh` `usage()` prints lines 2-37 of the script (code, not help) ;
`engine.sh` repeats its `CONF_DIR/TABLE` prelude twice ; `vector_pick.py` has an early
return that prints nothing (dead path, `pick.sh` filters it out).

---

## AUDIT 2 — THE PYTHON PROGRAMS (`config/programs/*.py`)

    file                 lines   verdict
    dash.py               1448   bridge + dashboard : 4 bugs, 1 crash
    board.py              1357   6 stale bindings
    audit_vocab.py         304   ok (identifiers only, by design)
    watch.py               173   1 crash (`os.devholel`)
    micro_vision.py        168   ok
    sse.py                 214   ok
    model.py               187   ok
    tts_daemon.py          145   ok (French log strings)
    laconf.py              163   ok
    summary/second/programs glue         ok

### P1 (crash) `watch.py` : `os.devholel`

Line 36 reads `os.devholel` instead of `os.devnull`. `_silent()` runs at every start
(`open_sessions`), so the keyword watcher dies with `AttributeError` before it opens
the microphone. No unit ships it today, so it is invisible — one typo away from a
dead feature.

### P2 (500) `dash.py` : `/delegate` uses an unbound name

In `command()`, the `/delegate` branch reads `ok` although `ok` is only assigned in
the other branches. First command of a session = `UnboundLocalError` = HTTP 500.

### P3 `dash.py` : `/doctor` is called by the dashboard and not served

`dash.js` fetches `/doctor` ; on :8770 it answers `404 no such route`. Measured on the
live dashboard.

### P4 `dash.py` : the live panel reads files nobody writes (see S2), and
`history()` leaks file handles (`open(...).read()` without `with`).

### P5 `board.py` : six bindings left over from the refactor
- `JOURNALS = bridge.log` then `read_turn()` parses it as JSON : always empty.
- `grep -c "echec de transport"` : the loop says `transport failure`, counter stuck at 0.
- `tint()` colours the headers `CE QUI / LES / LA` — the headers are now English, no
  header is ever coloured.
- menu bucket tests `"ram de la"`, the row is `ram of LA` (falls in LA by luck).
- label `filtre 223/224` for the family filter.
- `read_engine()` hardcodes table id `104`.

---

## AUDIT 3 — THE CONTRACT (canon vs code, measured on the live harness)

| what | measurement | verdict |
|---|---|---|
| `la --line` | `active / 4/4 up / table 2487/2487 / api connected` | ok |
| `board --menu` | 31 rows, 3 buckets | ok, one dead test |
| `:8770 /api/*` | 12 routes 200 | ok, `/doctor` 404 |
| `:8765` | bridge, `/say` streaming | ok |
| `doctor.sh --short` | 1 FAULT : "no active skill" | false |
| `memory.db` | 48 entries, 48 vectors | ok |
| `config/sessions.db` | 75 exchanges, 847 messages | ok |
| `bridge.log` | 1.8 MB, 32 NUL bytes mid-file, no rotation | needs rotation |
| `audit_vocab.py` | `total: 0` | ok (it only audits identifiers, not prose) |

Canon laws verified in code : 164 (English for the agent) → violated (S6) ;
921 (a finished plan discharges the skill) → implemented, but the doctor calls it a
fault (S4) ; 1200 (no tool deletes) → holds ; 2205 (state files) → the list is stale,
it names three files that no longer exist.

---

## FIX LOG

Each line below was re-tested on the live harness after the change.

1. `plan.sh` : `clear` removed from the `change` path (S1). `clear` is still defined and
   still called on one legitimate path : the last point of a `PLAN:` section empties it
   (law 921). It never follows a `rewrite` there, so the double cut of S1 cannot occur.
2. `watch.py` : `os.devnull` (P1).
3. `second.sh` : `config/filter/family.bin` (S3).
4. `dash.py` : `/delegate` bound name (P2) ; `/doctor` route (P3) ; `live()` reads
   `trace.jsonl` (S2).
5. `loop.sh` : writes `trace.jsonl` (S2) ; `clip()` instead of `coupe`, no nested
   marker (S5) ; agent strings in English (S6).
6. `trim_forms.sh`, `engine.sh` : identifiers and markers in English (S6).
7. `board.py` : `read_turn()` and the two tailers read `trace.jsonl` ; `transport
   failure` ; headers coloured by their English names ; menu bucket, family label,
   table id from the config (P5).
8. `doctor.sh` : no active skill is a NOTE ; `tools:` token ; `conf_req_num` harvested (S4).
9. `docs/state-registry.md` : `trace.jsonl` is KEEP (the only live channel).

---

## AUDIT 4 — THE GAPS OF THE QUICK PASS

The first pass was fast. This one re-read every fix and looked where the first did not.
Each line below was measured on this machine, not inferred.

### What the first pass got right (re-checked, one by one)

`os.devnull` (watch.py:36) ; `/delegate` binds `ok` (dash.py:748) ; `/doctor` is served
(dash.py:1447) ; `config/filter/family.bin` (second.sh) ; `conf_req_num` + `tools:` + the
"no active skill" NOTE (doctor.sh, diff of 4 lines) ; `clip` replaced `coupe` (loop.sh:54) ;
`trace.jsonl` exists (5.1 KB, one writer, three readers). None of it was bluff.

### G1 — S1 : `clear` is still there, and that is correct

The FIX LOG said "clear removed from the `change` path". True, but `clear` is still defined
(l.50) and still called (l.126) when the last point of a `PLAN:` section closes (law 921).
It never follows a `rewrite` on that path, so the double cut of S1 cannot happen. The
FIX LOG above now says it.

### G2 (fixed) `lib.sh` : `trap 'rm -f $CLEAN'` word-splits

`mktemp` accepts a `TMPDIR` containing a space — measured: `/tmp/a b/x.5KJIoa` is created.
`rm -f $CLEAN` then eats two arguments and leaves the file behind. `CLEAN` now holds one
path per line and the trap reads it with `while IFS= read -r`. Measured after the fix :
file created under a spaced directory, directory empty after `EXIT`.

### G3 (fixed, and overstated by the first pass) the "file-handle leak"

`open(...).read()` does NOT leak a descriptor in CPython — the temporary is collected at
once. Measured : 4 fds before, 4 after 2 000 opens. It is hygiene, not a leak. Six sites in
`audit_vocab.py` (not in `dash.py`), all rewritten with `with` ; the file now runs clean
under `-W error::ResourceWarning` and still prints `total: 0`. `dash.py:history()` was not
in the list the first pass left and is untouched.

### G4 (fixed) `watcher.sh` : `usage()` printed 36 lines of source

`sed -n '2,37p' "$0"` dumped the shebang and the variable block. Replaced with a real usage
in the house form (`cat >&2 <<'TXT'`), in French like `approval.sh` — usage is read by the
human, not the agent.

### G5 (fixed, missed by the first pass) French error, agent side, `watcher.sh`

Line 79 refused in French (`le juge ne peut pas NOTER… Je n invente pas de verdict`) while
every other refusal in the file is English. The whole judge-failure path spoke the wrong
language to the model (law 164). This is the S6 class the first pass believed closed.

### G6 (not a bug) `doctor.sh` does test `projects/.active`

It answers `ok` when the file is absent (l.309-313). Nothing to change.

### G7 (outside the repo, worth knowing) `banc_selecteur.sh` hardcodes its scratch

`SC=/home/moussa/.hermes/cache/scratch` (l.37). The bench dies with `BANC CASSE` the moment
that path is absent or read-only — which is what happened when it ran from the sandbox.
Re-run on a copy with a writable `SC` : `7 verdicts, 0 non conformes`. The bench itself is
sound ; its path is not. `_repo.sh` states the rule ("ce chemin-la s ecrit ICI, une fois")
and `SC` ignores it. Left alone : the benches are work artefacts, outside the repository.
