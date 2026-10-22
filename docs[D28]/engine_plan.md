# The engine plan — one motor, small tools, three surfaces

## How it works (the short version)

- The **engine is the motor**. It runs a turn, and it owns the single door `la.sh`.
- It has **many small functions — the tools** listed below. Each tool does one thing,
  its body is shell, and it is reached through the door.
- **No surface touches the disk.** The CLI, the Android app and the dashboard all call
  the SAME small tools through the door. One source of truth, three surfaces, same
  commands everywhere.
- Anything that **checks health** (canon, duplicates, tags, index) is the **doctor's**
  job — never a reader's, never the motor's.
- The **board is not a source**: it is a surface. It only COMPOSES small-tool answers
  and renders them. Today it re-implements the reads in Python; the split below removes
  that Python and makes it compose the small tools.

## The big tableau — every tool of the engine (E001..E027)

Legend: **SMALL** = one cohesive function, keep. **SPLIT** = monolith, break into
several small functions. **DOOR** = dispatcher, keep thin, holds no logic.

| id | tool | what it does | lines | ops | verdict |
|---|---|---|---|---|---|
| E001 | engine.approve | the human door: request, grant, deny, status | 50 | 5 | SMALL |
| E002 | engine.asr | the ear: start, stop, status | 51 | 3 | SMALL |
| E003 | engine.backup | the net outside the disk: now, verify, restore | 84 | 3 | SPLIT -> backup_now / backup_verify / backup_restore |
| E004 | engine.commands | the surfaces of la: board, once, app, cli, user... | 148 | 12 | DOOR (dispatch only) |
| E005 | engine.doctor | runs every control of the doctor family | 93 | 5 | THIN (delegates to doctor.*) |
| E006 | engine.hist | sessions.db: init, add, window | 72 | 6 | SPLIT -> hist_init / hist_add / hist_window |
| E007 | engine.install | what is placed on the machine | 117 | 5 | SPLIT -> install_units / install_command / install_desktop / install_applet / install_certs |
| E008 | engine.models | the router of the models: load, unload, status | 51 | 3 | SMALL |
| E009 | engine.retention | the bounds applied: audio, returns, logs, base | 83 | 4 | SPLIT -> retention_audio / retention_returns / retention_logs / retention_base |
| E010 | engine.spec | the canon: add one law, or read it | 50 | 2 | SMALL |
| E011 | engine.stat | sessions.db counted: exchanges, tools, cost | 43 | 3 | SMALL |
| E012 | engine.switch | the active provider: list, take | 51 | 2 | SMALL |
| E013 | engine.trace | the living channel: write one line, or read it | 49 | 3 | SMALL |
| E014 | engine.tts | the voice: start, stop, status | 51 | 3 | SMALL |
| E015 | engine.tunnel | wireguard desktop<->phone: up, down, status, qr | 87 | 4 | SPLIT -> tunnel_up / tunnel_down / tunnel_status / tunnel_qr |
| E016 | engine.update | the project by git: check, apply, restore | 92 | 3 | SPLIT -> update_check / update_apply |
| E017 | engine.reload | the register rebuilt from the bodies | 50 | 1 | SMALL |
| E019 | engine.signal | task signals between processes | 49 | 3 | SMALL |
| E020 | engine.board | the state of the machine: one line, every section | 184 | 4 | SPLIT (monolith) — the priority |
| E021 | engine.residents | the residents: state, start, stop, listen | 72 | 6 | SPLIT -> resident_state / resident_start / resident_stop / resident_listen |
| E022 | engine.service | one of the four services, in the foreground | 35 | 6 | SMALL |
| E023 | engine.turn | one turn of the loop: text in, answer out | 30 | 1 | SMALL |
| E024 | engine.map | the map of the names, rebuilt from disk | 22 | 1 | SMALL |
| E025 | engine.uninstall | what the install posed, removed | 48 | 5 | SMALL |
| E026 | engine.wake | a wake opens a request | 25 | 1 | SMALL |
| E027 | engine.purge | gives the cold page cache back to the kernel | 77 | 3 | SMALL |

Count: **16 SMALL**, **1 DOOR**, **1 THIN**, **~8 SPLIT**. The one true monolith to
decompose now is **E020 engine.board**.

## Big tools -> the small functions they become

### E020 engine.board (184 lines, 9.9 KB) — THE priority
It re-implements, in Python-in-shell, what these small tools must own. After the split,
board only composes and renders:

- `resident_state` (units state + memory)  … existing `engine.residents op=status`, +memory
- `router_models` … existing `engine.models op=status`
- `model_files` … existing `doctor.models op=files`
- `instrument_state` … existing `doctor.machine op=instruments`
- `machine_state` (ram/swap/gpu/disk) … existing `doctor.machine`
- `approval_state` … existing `engine.approve op=status`
- `trace_tail` … existing `engine.trace op=tail`
- `session_count` … existing `engine.stat op=exchanges` (make it count exchanges, not messages)
- `table_state` … existing `table_manage`
- `registry_map` … existing `table_manage`
- `canon_state` … **doctor** `doctor.knowledge op=canon` (not a motor tool)
- `git_state` … NEW small tool (`git -C $LA_ROOT status --short` + `rev-parse`)
- `api_endpoint` … NEW small tool (`engines.<active>.{provider,model,post}` + `curl -I`)
- `active_state` … NEW small tool (`skill_active` / `project_active`)
- `usage_tokens` … NEW or `engine.stat op=cost`

### Other monoliths (splittable later, each op already a small function)
`engine.commands` = the door (keeps no logic). `engine.install`, `engine.update`,
`engine.backup`, `engine.retention`, `engine.hist`, `engine.tunnel`, `engine.residents`
are large families: each op can become its own small tool when we get there. They are
cohesive today, so they are not blocking the board work.

## board.py functions -> their tool (new / existing)

Full per-function mapping: `docs[D28]/board_functions_to_tools.md`.
Summary: ~13 functions route to an EXISTING small tool; ~6 need a NEW small tool
(`git_state`, `api_endpoint`, `journal_state`, `active_state`, `usage_tokens`,
`session_query`); the canon routes to the doctor.

## Order of execution (one function, one proof, one commit)

1. **E020 board first.** Each `read_*` in board.py becomes a call to its small tool
   through the door; the Python body of that reader is deleted. Output proven against
   the current board before the commit. One reader per commit.
2. **Create the missing small tools** as the readers need them (each ~10-15 lines).
3. **Doctor stays green** after each step (tools / tags / index / duplicates).
4. Later: split the other large families op-by-op, same discipline.
