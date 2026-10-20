# STATE FILES OF THE PIPELINE

One turn writes the same thing in five places. This page says where, and what each file is worth.
Measured on 2026-10-20 (`config/state`, 21 files).

## THE TURN : WHAT IS WRITTEN AND WHERE IT IS READ

| file | written by | read by | holds | verdict |
|---|---|---|---|---|
| `config/sessions.db` | `loop.sh` (`db_insert`) | `/history`, `/usage`, `board.py` | `messages(id, exchange, ts, role, content, tool_calls, reasoning)` + `usage` | KEEP : the only conversation store |
| `config/state/reasoning.jsonl` | `loop.sh` | `dash.py` `recent_think()` | the reasoning of each model message, per exchange | FOLD into `messages.reasoning` (column exists, empty today) |
| `config/state/journal.jsonl` | `loop.sh` (`journal_entry`) | `/journal` | `{turn, ts, role, message, reasoning}` | FOLD : duplicate of the conversation |
| `config/state/thinking.jsonl` | `loop.sh` | `/thinking` | one reasoning line per turn | FOLD : duplicate of `reasoning.jsonl` |
| `config/state/trace.jsonl` | `loop.sh` | nobody | every tool call of the turn | DEAD until a reader exists |
| `config/state/spoken.jsonl` | `dash.py` | `/spoken` | the phrases already said aloud | KEEP (voice echo) |

So today: the reasoning goes to `reasoning.jsonl`, the reply goes into `sessions.db` (as the tool
result) plus `journal.jsonl`. The thread reads two of them, `/journal` and `/thinking` read the
others : that is why the app, the dashboard and the CLI can disagree.

## THE LOOP SCRATCH (one writer, no reader)

| file | written by | verdict |
|---|---|---|
| `last_spoken` | `loop.sh` `say_once` | keep : the 300 s window is read back by the same function |
| `next.md` | `loop.sh` | DEAD |
| `scope.cand` | `loop.sh` | DEAD |
| `session_note.log` | `loop.sh` | DEAD |
| `signal_task.log` | `loop.sh` | DEAD |
| `reply.stream` | `board.py` | DEAD (the panel streams, nobody replays it) |
| `cli_history` | `board.py` | DEAD |
| `board.log` | `la.sh` | keep : the panel's only trail |

## THE OBSERVABILITY FILES

| file | written by | read by | verdict |
|---|---|---|---|
| `bridge.log` | `dash.py` (one line per request, with the code) | nobody, read by hand | KEEP, needs rotation : 1.8 MB today |
| `watch.jsonl` | `watcher.sh` | nobody, read by hand | KEEP : the judge's verdicts |
| `doctor.cache`, `doctor.light.cache`, `doctor.short.cache` | `dash.js` | `board.py` | KEEP, three caches for three question shapes |
| `vocab_cache.json` | `audit_vocab.py` | `audit_vocab.py` | KEEP : the audit costs 0.35 s instead of 7 s |
| `tts.log`, `blender.log` | `tts.sh`, `engine.sh` | by hand | KEEP |

## THE TARGET

    one conversation : config/sessions.db   demand, reasoning, reply, tool_calls, tokens
    one access log   : config/state/bridge.log
    one judge trail  : config/state/watch.jsonl

Everything else folds into `sessions.db` or leaves. Nothing reads a file the human surface cannot see.
