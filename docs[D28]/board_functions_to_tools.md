# board.py functions -> tools

Every reader that board.py still owns, mapped to ONE small tool.
Rule: a tool = one responsibility, one input, one output, its COMMAND is shell
and it is reached through the door (la.sh). No python in a tool, no big tool.

The motor stays minimal. Its tools are unified. The three surfaces — the CLI, the
Android app, the dashboard — all read the SAME tools. Anything that checks health
(the canon, duplicates, tags, index...) is a doctor function, never a motor tool.

Column 2 names are evocative: reading the name tells you what it does.
Column 3 states the route: EXISTING tool to reuse (with its op), or NEW small
shell tool to create (with its source command).

| Python function (board.py) | Tool name (evocative) | Route / technical precision |
|---|---|---|
| `read_residents()` (+ `alive`, `_units`) | `resident_state` | EXISTING `engine.residents` (E021) `op=status` -> per-unit active/memory (embed, rerank, local, asr, tts, kws) |
| `_router_models()` | `router_models` | EXISTING `engine.models` (E008) `op=status` -> `/models` loaded/sleeping per model id |
| `read_appoints()` (+ `_appoint_rows`) | `appoint_state` | EXISTING `engine.residents` (E021) if dash/bridge are units; else NEW shell: `systemctl --user is-active la-dash la-bridge` |
| `read_approval()` | `approval_state` | EXISTING `engine.approve` (E001) `op=status` (request + signal window) + `skill_list` for the count to sign |
| `read_instruments()` (+ `dotted`) | `instrument_state` | EXISTING `doctor.machine` (D006) `op=instruments` -> `<bin> --version` |
| `read_registry()` | `registry_map` | EXISTING `table_manage` (G018) -> id/tool from `registry-*.yaml` |
| `read_modeles()` (+ `_models_in`, `size_of`) | `model_files` | EXISTING `doctor.models` (D012) `op=files` (+ `models_status` G010) |
| `read_table()` (+ `_table`) | `tool_table_state` | EXISTING `table_manage` (G018) -> bodies missing + duplicate ids |
| `read_canon()` | `doctor.knowledge` `op=canon` | EXISTING doctor function (D004) — the canon is NOT a motor tool; the doctor checks it (SPEC zone, statements, empty canon) |
| `read_doctor()` | (doctor cache) | NOT a new tool — board reads the head of `$(cfg abs doctor_cache)`, the doctor writes it; `doctor_state` name is already taken (op=orphans,writers) |
| `read_engine()` (+ `_engine`) | `api_endpoint` | NEW shell: `cfg str engines.<active>.{provider,model,post}` + `curl -I` -> code |
| `read_git()` (+ `_git_state`) | `git_state` | NEW shell: `git -C $LA_ROOT status --short` + `rev-parse --short HEAD` |
| `read_traffic()` | `session_count` + `journal_state` | split: sessions -> EXISTING `engine.stat` (E011) `op=exchanges`; journal -> NEW `journal_state` (tail `$LA_STATE/bridge.log`) |
| `read_turn()` | `trace_tail` | EXISTING `engine.trace` (E013) `op=tail` -> last tool calls from `trace.jsonl` |
| `read_machine_name()` | `machine_state` | EXISTING `doctor.machine` (D006) -> ram/swap/gpu/disk (`free`, `nvidia-smi`, `df`) |
| `read_head()` | `head_state` | bridge `/api/head`; EXISTING via `engine.board op=json` if it exposes head, else NEW `head_state` |
| `read_state()` | `active_state` | NEW shell: `cat $LA_STATE/skill_active $LA_STATE/project_active` |
| `model.tokens()` | `usage_tokens` | check EXISTING `engine.stat op=cost`; else NEW (last session tokens from `$(cfg abs usage)`) |
| `_db_query()` / `model.query()` | `session_query` | read-only browsing: EXISTING `search_sessions` / `recall`; free SQL for CLI `/last` -> NEW `session_query` (`sqlite3 "$LA_SESSIONS_DB"`) |
| `laconf.get/text/path` (+ `_cfg`, `num`) | `config_read` | EXISTING `cfg` CLI / `config_list` (G080): readers call `cfg str <key>` directly |
| `bridge` / `bridge_state` / `bridge_ping` | — (the door) | NOT a tool: the HTTP door itself (`/api/state`, `/api/head`); tools are reached through it |

## What stays in board.py (not a tool)

These are composition and rendering, not reads. They keep calling the small tools above:

- `control()`, `board_object()`, `sections()`, `one_line()` — assemble the rows
- `_expand()`, `_ratio_of()`, `_approval_gesture()`, `short()`, `line()`, `tint()`, `_footer()`
- `weight()`, `ago()`, `human_count()`, `shorten()` — formatting
- `tui()`, `Cli`, `Tailer`, `snapshot()`, `main` — the terminal interface
- `run()`, `probe()`, `_port()`, `num()`, `state_dir()` — tiny helpers

## Order of work (one at a time, each proved against the current board output)

1. EXISTING routes first (cheapest, proven tools): `resident_state`, `router_models`, `approval_state`, `instrument_state`, `trace_tail`, `machine_state`, `session_count`, `tool_table_state`, `model_files`, `registry_map`, `config_read`, and the canon via `doctor.knowledge op=canon`.
2. NEW small shell tools for the gaps: `git_state`, `api_endpoint`, `journal_state`, `active_state`, `usage_tokens`, `session_query`. (The canon is NOT here — it is `doctor.knowledge op=canon`, an existing doctor function.)
3. Rewire board.py: each `read_*` becomes a call to its tool through the door. Delete the python body of that reader. One function, one commit, output identical.
