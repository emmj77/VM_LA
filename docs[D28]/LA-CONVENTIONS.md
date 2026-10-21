# LA — every name in the engine

Two columns: the name as the code writes it, and one sentence. Shell bricks, then the python programs, the shell programs, the applet, the bodies, the families, the services, the state files, the registers, and the addresses the page asks against the ones the bridge serves.

| Name | What it is |
|---|---|
| `approval.sh` · `_ap_key` | the human door: a signed go, checked here, never asked by a tool |
| `approval.sh` · `_ap_digest` | the 32-character digest of a request, the thing the signature covers |
| `approval.sh` · `_ap_sig` | the hmac of a digest, with the key read from conf/.env |
| `approval.sh` · `approval_request` | writes the pending request (tool, digest, ts) and answers 3 |
| `approval.sh` · `approval_ok` | true when a signed grant exists, matches the digest, and still sits inside the window |
| `approval.sh` · `approval_grant` | turns the pending request into a signed grant; the signature is made here |
| `approval.sh` · `approval_deny` | sends the pending request to the trash |
| `approval.sh` · `approval_status` | the tool named in the grant, or the word none |
| `approval.sh` · `run_approval` | the entry of engine.approve: allow, deny, or status |
| `args.sh` · `args_word` | args_word <value> : the value as one shell word, quoted for the command |
| `args.sh` · `args_ok` | args_ok <type> <value> [enum1 enum2 ...] : true when the value fits the type |
| `args.sh` · `args_bool` | args_bool <value> : the value as 0 or 1 |
| `args.sh` · `args_path` | args_path <value> : the value as a full path, no symlink taken, no way above the root |
| `args.sh` · `args_line` | args_line <type> <value> [enum ...] : the word a command receives, refused if it does not fit |
| `args.sh` · `args_env` | args_env <name> <value> : one assignment line for the command environment |
| `args.sh` · `args_split` | args_split <decl> : one item per line, name:type or name:type:a,b,c |
| `args.sh` · `args_decl` | args_decl <decl> <name> : the type of one declared argument, empty when it is not declared |
| `args.sh` · `args_enum` | args_enum <decl> <name> : the allowed values of one declared argument |
| `canon.sh` · `canon_file` | canon_file [project] : the canon of the project, spec.yaml when it exists, project.yml otherwise |
| `canon.sh` · `canon_decl` | canon_decl [project] : the declaration of the project, always project.yml |
| `canon.sh` · `canon_root` | canon_root [project] : the root the project declares, relative to the home of the machine |
| `canon.sh` · `canon_get` | canon_get <key> [project] : one field of the declaration |
| `canon.sh` · `canon_rule` | canon_rule <name> [project] : one value under RULES |
| `canon.sh` · `canon_law` | canon_law [project] : what the project wants said when a call is refused, one line per entry |
| `canon.sh` · `canon_summary` | canon_summary [project] : the lines of the project, in the order of their rank |
| `canon.sh` · `canon_skills` | canon_skills [project] : the skills the project carries, in the order of their rank |
| `canon.sh` · `canon_path` | the name the document gives this brick |
| `cap.sh` · `cap_bytes` | cap_bytes <max> : stdin, at most max bytes, the cut is said |
| `cap.sh` · `cap_head` | cap_head <lines> : the first lines, the rest is said |
| `cap.sh` · `cap_tail` | cap_tail <lines> : the last lines, the start is said |
| `cap.sh` · `cap_lines` | cap_lines <max> : stdin cut to max lines, the middle goes first |
| `cap.sh` · `cap_return` | the bound is read, never written here: a missing key is a refusal, not a default. |
| `cfg.sh` · `_flat` | flatten the master file into "dotted.key<TAB>value" lines |
| `cfg.sh` · `conf_str` | conf_str <dotted.key> : the value, empty if absent |
| `cfg.sh` · `conf_num` | conf_num <dotted.key> : the value if it is a number |
| `cfg.sh` · `conf_list` | conf_list <dotted.key> : the items, one space between them |
| `cfg.sh` · `conf_has` | conf_has <dotted.key> : true when the key carries something |
| `cfg.sh` · `_cfg_tree` | the path is rebuilt from the indentation, so the reader never needs the box drawing. |
| `cfg.sh` · `cfg_dir` | the path of a directory, read from the tree, then from the world section |
| `cfg.sh` · `cfg_file` | the path of a file, read from the tree, then from the world section |
| `cfg.sh` · `_cfg_world` | the world section answers for the dirs outside this one |
| `cfg.sh` · `_cfg_tree_list` | the id is the third column; the population (a tool body) carries none until the build names it. |
| `cfg.sh` · `_cfg_here` | one resolver: the tree is written by the document, the root is where it stands. |
| `cfg.sh` · `cfg_path` | cfg_path <key> : a directory key resolved against the root |
| `cfg.sh` · `cfg_abs` | cfg_abs <file key> : a file key resolved against the root |
| `cfg.sh` · `cfg` | cfg <verb> <arg> : the one word the rest of the engine uses |
| `fs.sh` · `abs_path` | abs_path <path> : the path made whole against ROOT, an absolute one is left alone |
| `fs.sh` · `state_paths` | state_paths [key] : the state directory, or one of its files when a key is given |
| `fs.sh` · `tmpfile` | tmpfile [prefix] : a fresh file in the state directory, its name already made |
| `fs.sh` · `write_atomic` | write_atomic <path> : the text arrives on stdin, the file appears in one move |
| `fs.sh` · `fs_json` | fs_json <text> : the text escaped for one JSON string, newlines kept as \n |
| `fs.sh` · `fs_age` | fs_age <path> : seconds since the file was last written, fails when absent |
| `fs.sh` · `env_get` | env_get <NAME> : one value of the key file, empty when it is not there |
| `loop.sh` · `_ltr` | the trace belongs to its body: the loop calls it, it never writes the channel |
| `loop.sh` · `loop_before` | loop_steps : the pipeline split where it repeats: before call, the cycle, after tools |
| `loop.sh` · `loop_cycle` | the steps from call to tools, the half that talks to the model |
| `loop.sh` · `loop_after` | the steps after tools, the half that writes and replies |
| `loop.sh` · `loop_busy` | loop_busy : true when another turn holds the mark |
| `loop.sh` · `loop_mark` | loop_mark : this shell owns the turn |
| `loop.sh` · `loop_release` | loop_release : the turn is over, the mark goes |
| `loop.sh` · `loop_turn` | loop_turn <prompt> : the whole turn |
| `msg.sh` · `msg` | msg <dotted.key> [arg ...] : the phrase, arguments filled in order |
| `msg.sh` · `msg_str` | msg_str <dotted.key> : the raw text, no substitution |
| `msg.sh` · `msg_has` | msg_has <dotted.key> : true when the phrase exists |
| `run.sh` · `_door_field` | _door_field <body> <KEY> : one scalar of a body, top level or under a section |
| `run.sh` · `_door_decl` | _door_decl <body> : the declared arguments, "name:type" in their order |
| `run.sh` · `_door_cmd` | _door_cmd <body> : the command text, unfolded |
| `run.sh` · `_door_register` | _door_register : the register the caller is allowed to read |
| `run.sh` · `run_call` | 0 ok, 3 a human must sign, 124 the bound was reached, 1 refused |
| `run.sh` · `say_err` | say <word ...> : the same line, on stderr, when there is no channel |
| `run.sh` · `die` | die <phrase key> [arg ...] : the phrase, then stop this shell |
| `shape.sh` · `shape` | shape <status> <tool> <line> <result> <return> : one line, one object |
| `shape.sh` · `shape_ok` | shape_ok <tool> <line> <result> [return] : the call went through |
| `shape.sh` · `shape_fail` | shape_fail <tool> <line> <phrase key> [arg ...] : a named refusal, in the same form |
| `shape.sh` · `shape_get` | shape_get <line> <field> : one field back, empty when absent |
| `shape.sh` · `shape_short` | shape_short <line> : the same object, cut for a narrow screen |
| `shell.sh` · `shell_addr` | shell_addr <machine> <field> : one address of a machine, from the master file |
| `shell.sh` · `shell_bin` | shell_bin <machine> : the binary of that machine, root+cli when it is split |
| `shell.sh` · `shell_cmd` | shell_cmd <machine> <operation> [arg ...] : the command line, built from the master file only |
| `shell.sh` · `shell_run` | shell_run <machine> <operation> [arg ...] : the same line, run, bounded, shaped |
| `shell.sh` · `krita_url` | krita_url : the krita service, checked before anything is asked of it |
| `skl.sh` · `skl_skill` | skl_skill : the name of the armed skill, empty when none |
| `skl.sh` · `skl_project` | skl_project : the name of the armed project, empty when none |
| `skl.sh` · `skl_arm` | skl_arm <name> : a skill exists before it is armed |
| `skl.sh` · `skl_disarm` | skl_disarm : no skill, no tool is allowed any more |
| `skl.sh` · `skl_project_arm` | skl_project_arm <name> : a project exists before it is armed |
| `skl.sh` · `skl_project_disarm` | skl_project_disarm |
| `skl.sh` · `skl_toolset` | skl_toolset [name] : the tool ids the skill carries, one per line (the TOOLS map of its skill.yaml) |
| `skl.sh` · `skl_workspace` | skl_workspace [name] : where the armed skill writes, relative to the project root |
| `skl.sh` · `skl_in_toolset` | skl_in_toolset <id> : true when the armed skill carries that tool id |
| `skl.sh` · `skl_permanent` | skl_permanent <name> : allowed whatever the skill, because the master file says so |
| `skl.sh` · `tool_allowed` | tool_allowed <name> <id> : the two doors at once, the name for the master file, the id for the skill |
| `skl.sh` · `approval_of` | approval_of <body> : what the body says a human must carry, empty when nothing |
| `skl.sh` · `is_gated` | is_gated <body> : true when the call waits for a human signature |
| `step.sh` · `_turn_file` | the path of state/turn.json |
| `step.sh` · `_turn_get` | one field of turn.json, as a jq expression |
| `step.sh` · `_turn_set` | rewrites turn.json with a jq filter, atomically |
| `step.sh` · `_turn_set_json` | the same, with a JSON value handed as an argument |
| `step.sh` · `step_list` | step_list : the order, from the pipeline file. no name is written here. |
| `step.sh` · `prompt_text` | prompt_text : what the human asked, as one string |
| `step.sh` · `step_run` | step_run <name> : a step is a body of the family turn, and the door is the only way in |
| `tab.sh` · `table_block` | the indent of the table does not matter: the anchor is "- id:" wherever it sits. |
| `tab.sh` · `table_entry` | table_entry <table> <id\|name> : the entry, whether it is given by its id or by its name |
| `tab.sh` · `table_field` | table_field <table> <id\|name> <key> : one value of one entry, empty when it is not there |
| `tab.sh` · `table_ids` | table_ids <table> : every id of the table, one per line, block style |
| `tab.sh` · `cmd_ids` | cmd_ids [file] : the ids of the commands block, one per line |
| `tab.sh` · `cmd_get` | cmd_get <id> <key> : one field of one command |
| `tab.sh` · `cmd_has` | cmd_has <name> : true when the name prefixes a declared command |
| `tab.sh` · `cmd_usage` | cmd_usage : the usage lines the door prints, read from the commands block |
| `tab.sh` · `cmd_slash` | cmd_slash : the legend of the chat, the first word of every command, once |
| `tab.sh` · `cmd_new_turn` | cmd_new_turn : archives the turn file, the next turn is born |
| `tab.sh` · `cmd_run` | cmd_run <word ...> : the longest declared name wins and the rest is its argument; a tool goes through the human door, an act runs inside the engine |
| `tab.sh` · `table_field_list` | table_field_list <table> <id\|name> <key> : a bracketed list, one word per line |
| `tab.sh` · `table_keys` | table_keys <table> <id\|name> : the keys of one entry, one per line |
| `tab.sh` · `table_index` | table_index : the whole table as id\|tool\|family\|guardrail\|description, kept once in TABLE_INDEX |
| `tab.sh` · `block_by_id` | block_by_id <id> : the block of an id in the table carried by TABLE, one pass, no temp file |
| `tab.sh` · `body_of` | body_of <id> : what the document calls the block of an id |
| `tab.sh` · `count` | count <file> : how big it is, "bytes lines" on the standard output |
| `dash_server.py` · `commands` | the commands block of the master file, in order, read at render |
| `dash_server.py` · `commands_html` | the bar of buttons, one form per declared command |
| `dash_server.py` · `commands_legend` | the legend of the chat: first word of every command, once |
| `dash_server.py` · `run_command` | runs one command through the door, allowlist only |
| `board.py` · `_port` | an argument read as a port number |
| `board.py` · `run` | runs a command, returns its exit code and its output |
| `board.py` · `probe` | the http code of one address |
| `board.py` · `alive` | true when the unit of a model answers |
| `board.py` · `weight` | a value kept inside its bounds |
| `board.py` · `line` | one line of the board, drawn by its nested build |
| `board.py` · `build (l.89)` | builds the coloured segments of that line |
| `board.py` · `read_residents` | the units that listen, with their port |
| `board.py` · `_rss_port` | the port of one resident, read from its state file |
| `board.py` · `read_appoints` | what waits for a human |
| `board.py` · `read_approval` | the signed grant and its age |
| `board.py` · `read_instruments` | the instruments the bodies may call |
| `board.py` · `read_registry` | the register, as one map of tools |
| `board.py` · `_models_in` | the models one family declares |
| `board.py` · `size_of` | the size of a file, in a readable unit |
| `board.py` · `read_modeles` | the loaded models, and where each one sits |
| `board.py` · `place (l.260)` | places one model in the table of the two gpus |
| `board.py` · `read_table` | the table of a family, from la_config |
| `board.py` · `read_canon` | the canon of the active project |
| `board.py` · `read_doctor` | the verdicts of the doctor |
| `board.py` · `read_engine` | which engine is active |
| `board.py` · `read_git` | the git state of the tree |
| `board.py` · `read_traffic` | the traffic of the bridge |
| `board.py` · `read_turn` | the turn in progress, from the trace |
| `board.py` · `read_machine_name` | the name of the machine |
| `board.py` · `ago` | a timestamp, as an age in words |
| `board.py` · `control` | calls every reader and returns the data of the board |
| `board.py` · `sections` | the data of the board, cut into sections |
| `board.py` · `one_line` | the board on one line, for the applet |
| `board.py` · `_sigwinch` | marks that the window changed size |
| `board.py` · `tint` | colours a section title |
| `board.py` · `frame` | the frame of the board, section by section |
| `board.py` · `_keys` | reads one key without blocking |
| `board.py` · `_footer` | the footer of the board |
| `board.py` · `tui` | the loop of the tui: keys, refresh, quit |
| `board.py` · `base` | the address of the bridge |
| `board.py` · `http` | one http call to the bridge |
| `board.py` · `human_count` | the number of humans the bridge saw |
| `board.py` · `shorten` | a text cut to the width it gets |
| `board.py` · `read_state` | the state of the engine, read from the bridge |
| `board.py` · `snapshot` | the data of the board, on one line |
| `board.py` · `Tailer.__init__` | opens the trace at its end |
| `board.py` · `Tailer.size` | the size of the trace |
| `board.py` · `Tailer.new_lines` | the lines added since the last read |
| `board.py` · `_tool_line` | the trace line of one tool call |
| `board.py` · `one_turn` | follows one turn through the trace |
| `board.py` · `Tailer.stream` | the live lines of the trace |
| `board.py` · `Cli.__init__` | sets up the interface |
| `board.py` · `Cli.compose` | draws the skeleton of the interface |
| `board.py` · `Cli.on_mount` | wires the stream widget |
| `board.py` · `Cli.banner` | prints the banner |
| `board.py` · `Cli.echo` | writes a line in the stream |
| `board.py` · `Cli.request` | prints what was asked |
| `board.py` · `Cli.answer` | prints an answer |
| `board.py` · `Cli.error` | prints an error |
| `board.py` · `Cli.state` | refreshes the state panel |
| `board.py` · `Cli._probe` | asks the bridge for the state |
| `board.py` · `Cli._show` | keeps the last state |
| `board.py` · `Cli._render` | paints the state panel |
| `board.py` · `title (l.966)` | the title of the state panel |
| `board.py` · `Cli.pump` | moves the trace lines into the stream |
| `board.py` · `Cli.on_input_submitted` | sends what was typed |
| `board.py` · `Cli._remember` | keeps the line in the history |
| `board.py` · `Cli._read_history` | loads the history from disk |
| `board.py` · `Cli.on_key` | handles tab completion and the shortcuts |
| `board.py` · `Cli.completer` | the completion of one command |
| `board.py` · `Cli.command` | runs one command of the cli |
| `board.py` · `Cli.start_turn` | starts a turn from the cli |
| `board.py` · `Cli._queue` | queues the text of the turn |
| `board.py` · `Cli._turn` | follows the turn it started |
| `board.py` · `Cli._done` | marks the turn finished |
| `board.py` · `Cli.action_post` | the action: post the input |
| `board.py` · `Cli.action_last` | the action: show the last turn |
| `board.py` · `Cli.action_quit` | the action: quit |
| `board.py` · `cli` | the entry of the tui |
| `board.py` · `main` | the entry of the program: one line, one pass, or the tui |
| `board.py` · `title (l.1300)` | the title of a model line |
| `board.py` · `short (l.1318)` | the short name of a model at the given width |
| `bridge.py` · `env` | one environment variable, stripped |
| `bridge.py` · `die` | prints a message and stops |
| `bridge.py` · `state_file` | the path of one file under the state dir |
| `bridge.py` · `kind_of` | the content type of a file, from its extension |
| `bridge.py` · `now` | the time, in iso seconds |
| `bridge.py` · `delegate` | sends a tool call to the door and returns its answer |
| `bridge.py` · `Handler.log_message` | writes the http log to stderr |
| `bridge.py` · `Handler.do_GET` | answers a GET |
| `bridge.py` · `Handler.do_POST` | answers a POST |
| `bridge.py` · `Handler.route` | reads the path, then dispatches |
| `bridge.py` · `Handler.work` | the dispatch itself, path by path |
| `bridge.py` · `Handler.inside` | true when a name stays inside its root |
| `bridge.py` · `Handler.extension` | the dispatch of the extra endpoints |
| `bridge.py` · `Handler.body` | reads the request body |
| `bridge.py` · `Handler.object` | the body as json |
| `bridge.py` · `Handler.lines` | the last lines of a file |
| `bridge.py` · `Handler.json` | answers with json |
| `bridge.py` · `Handler.file` | answers with a file |
| `bridge.py` · `Handler.send` | sends the response |
| `bridge.py` · `main` | checks the environment, then serves |
| `tts_daemon.py` · `load` | loads the onnx voice once |
| `tts_daemon.py` · `say` | writes one text as a wav |
| `tts_daemon.py` · `Service.log_message` | silences the http log |
| `tts_daemon.py` · `Service.answer` | answers with a payload and its type |
| `tts_daemon.py` · `Service.do_GET` | answers /health |
| `tts_daemon.py` · `Service.do_POST` | answers /say |
| `watch.py` · `STATE_DIR` | the state directory, from the environment |
| `watch.py` · `_silent` | runs with stderr closed |
| `watch.py` · `open_sessions` | opens the three onnx sessions |
| `watch.py` · `melspec` | the mel spectrogram of one buffer |
| `watch.py` · `embeddings` | the embeddings of one spectrogram |
| `watch.py` · `scores` | the score of a new sample against the known ones |
| `watch.py` · `listen` | listens, and signs what passes the threshold |
| `watch.py` · `signer` | signs the pending approval request |
| `watch.py` · `main` | the entry: listen, or sign once |
| `install.sh` · `conf` | reads one value from la_config for the script |
| `install.sh` · `value` | prints one value, or its default |
| `uninstall.sh` | no function: the script runs straight through, it removes what install put |
| `applet.js` · `ratioOf` | the share of one value in the total |
| `applet.js` · `parseRows` | reads the short output of the doctor |
| `applet.js` · `iconOf` | the icon of a verdict |
| `applet.js` · `main` | paints the applet |
| `doctor.data` (D001) | the bases and the memory, one writer each |
| `doctor.forms` (D002) | the forms of a return: their bounds are written and read |
| `doctor.keys` (D003) | la_config against the bodies: one owner per fact |
| `doctor.knowledge` (D004) | the skills, the armed skill and project, the canon |
| `doctor.language` (D005) | no french word in the machinery, and no dead skill name |
| `doctor.machine` (D006) | what listens, what is called, and the benches |
| `doctor.manifest` (D007) | the document against the disk, both ways |
| `doctor.structure` (D008) | the root, the syntax of the bricks, the syntax and the import of the programs |
| `doctor.texts` (D009) | the head of the model, the refusals the door needs, and the french left |
| `doctor.tools` (D010) | the register against the bodies by id, and every path they cite |
| `engine.approve` (E001) | the human door: request, grant, deny, status |
| `engine.asr` (E002) | the ear: start, stop, status |
| `engine.backup` (E003) | the net outside the disk: now, verify, restore |
| `engine.commands` (E004) | the surfaces of la: board, once, app, cli, say, turn, doctor, tool, new, update, help, line |
| `engine.doctor` (E005) | runs every control of the doctor family and counts: one fault makes it red |
| `engine.hist` (E006) | sessions.db: init, add, window, apply, result |
| `engine.install` (E007) | what is placed on the machine: units, command, desktop, applet, certs |
| `engine.models` (E008) | the router of the models: load, unload, status |
| `engine.retention` (E009) | the bounds applied: audio, returns, logs, bases |
| `engine.spec` (E010) | the canon: add one law, or read it |
| `engine.stat` (E011) | sessions.db, counted: exchanges, tools |
| `engine.switch` (E012) | the active provider: list, take |
| `engine.trace` (E013) | one line in the living channel |
| `engine.tts` (E014) | the voice: start, stop, status |
| `engine.tunnel` (E015) | wireguard between the desktop and the phone: up, down, status, qr |
| `engine.update` (E016) | the project by git: check, apply, rollback |
| `engine.reload` (E017) | the register rebuilt from the bodies: the body carries its id, the line repeats it |
| `turn.call` (T001) | one exchange with the provider, bounded |
| `turn.facts` (T002) | the turn object, born before anything touches it |
| `turn.note` (T003) | the turn kept: memory, compaction, the cut |
| `turn.prompt` (T004) | the messages: the head first, then what the human asked |
| `turn.reply` (T005) | the words of the answer, on the stream and on the board |
| `turn.scope` (T006) | the tools of this turn and nothing more, as the provider wants them |
| `turn.second` (T007) | the small head says who speaks |
| `turn.tools` (T008) | every call the answer named, run through the door, then told back |
| `watch.judge` (W001) | asks the reranker whether an event of the bridge wakes the session or waits |
| `family` · `READ` | base root, register model |
| `family` · `WRITE` | base work, register model |
| `family` · `MANAGE` | base none, register model |
| `family` · `REPLY` | base none, register model |
| `family` · `PLAN` | base none, register model |
| `family` · `VISION` | base root, register model |
| `family` · `BLENDER` | base work, register model |
| `family` · `UNITY` | base work, register model |
| `family` · `KRITA` | base work, register model |
| `family` · `IMAGE` | base work, register model |
| `family` · `ENGINE` | base none, register engine |
| `family` · `DOCTOR` | base none, register engine |
| `family` · `WATCH` | base none, register engine |
| `family` · `TURN` | base none, register engine |
| `service` · `models` | the unit service: runs llama serve with the local model la_config names |
| `service` · `asr` | the unit service: runs asr serve |
| `service` · `tts` | the unit service: runs the tts program |
| `service` · `dashboard` | the unit service: runs the dashboard program |
| `state/approve` | the signed go, kept until it expires |
| `state/approve.request` | the pending request, waiting for a human signature |
| `state/doctor.cache` | the last doctor output, read by the applet and the page |
| `state/free_terminal.log` | every command of the free terminal, its time and its text |
| `state/reply.stream` | the answer as it is being written |
| `state/say.queue` | what waits to be said |
| `state/second_head.yaml` | the product of the second head |
| `state/stop` | the stop mark of a turn |
| `state/trace.jsonl` | the live channel, one line per event |
| `state/turn.json` | the object of the turn, passed from step to step |
| `state/turn.pid` | the pid of the turn in progress |
| `tools/registry.yaml` | the register the model reads, one line per tool it may ask |
| `tools/engine/registry-engine.yaml` | the register the engine reads, one line per body it calls by name |
| `dashboard` · `/cmd` | the dashboard runs one command of the master file, name and arg, through the door |
| `page` · `<!-- the commands -->` | where the dashboard writes the command bar, at render |
| `page` · `<!-- the commands legend -->` | where the dashboard writes the chat legend, at render |
| `page` · `/api/agents` | the page asks this address |
| `page` · `/api/cmd` | the page asks this address |
| `page` · `/api/config` | the page asks this address |
| `page` · `/api/head` | the page asks this address |
| `page` · `/api/history` | the page asks this address |
| `page` · `/api/live` | the page asks this address |
| `page` · `/api/say` | the page asks this address |
| `page` · `/api/skill` | the page asks this address |
| `page` · `/api/skills` | the page asks this address |
| `page` · `/api/state` | the page asks this address |
| `page` · `/api/tts` | the page asks this address |
| `page` · `/api/update/apply` | the page asks this address |
| `page` · `/api/update/check` | the page asks this address |
| `page` · `/api/version` | the page asks this address |
| `bridge` · `/apk` | the bridge serves this address |
| `bridge` · `/audio/` | the bridge serves this address |
| `bridge` · `/command` | the bridge serves this address |
| `bridge` · `/delegate` | the bridge serves this address |
| `bridge` · `/image` | the bridge serves this address |
| `bridge` · `/m` | the bridge serves this address |
| `bridge` · `/ping` | the bridge serves this address |
| `bridge` · `/say` | the bridge serves this address |
| `bridge` · `/spoken` | the bridge serves this address |
| `bridge` · `/static/` | the bridge serves this address |
| `bridge` · `/stop` | the bridge serves this address |
| `bridge` · `/voice` | the bridge serves this address |
| `bridge` · `/widget` | the bridge serves this address |

## the agents
An agent id is `agent_<NNN>_<name>`: three digits, then the first name, lowercase, one word.
`NNN` starts at `000` for the principal -- the one that carries the head -- and runs `001`, `002`, ...
for the sub-agents, contiguous, no gap. Two digits are not an id: `agent_01_x` does not exist.
`agents.names` in the master file is the ONLY list; `agents.main` names the principal and is one of them.

## the environment

Every `LA_*` name the code carries as a whole word, 99 of them: exported by boot.sh, owned by the door, or read by one body. Two rules: a name is written once, in boot.sh; a program reads the environment and never builds a path.

| Name | What it is |
|---|---|
| `LA_ANIMA_CFG` | a knob of the animate-background body: unet, vae, clip, patch, length, force |
| `LA_ANIMA_CLIP` | a knob of the animate-background body: unet, vae, clip, patch, length, force |
| `LA_ANIMA_SIDE` | a knob of the animate-background body: unet, vae, clip, patch, length, force |
| `LA_ANIMA_STEPS` | a knob of the animate-background body: unet, vae, clip, patch, length, force |
| `LA_ANIMA_FORCE` | a knob of the animate-background body: unet, vae, clip, patch, length, force |
| `LA_ANIMA_PATCH` | a knob of the animate-background body: unet, vae, clip, patch, length, force |
| `LA_ANIMA_UNET` | a knob of the animate-background body: unet, vae, clip, patch, length, force |
| `LA_ANIMA_VAE` | a knob of the animate-background body: unet, vae, clip, patch, length, force |
| `LA_API_MODEL` | the model name a vision body sends to its provider |
| `LA_API_URL` | the provider address a vision body calls |
| `LA_APK_FILE` | the built phone application, served by /apk, empty when nothing was built |
| `LA_FLATTENER_PORT` | a knob read by the body that names it |
| `LA_FLATTENER_THRESHOLD` | a knob of the colouring bodies: the flatting endpoint or its threshold |
| `LA_APPROVED` | set by the door when a human signed: the body may pass the approval gate |
| `LA_APPROVE_KEY` | a knob read by the body that names it |
| `LA_ASR_PORT` | where the ear listens, for a body that calls it |
| `LA_AUDIO` | the folder of the spoken words and the recorded voice |
| `LA_BENCHES` | a knob read by the body that names it |
| `LA_CAP_BYTES` | the byte bound of one return, from limits.return_bytes |
| `LA_CAP_LINES` | the line bound of one return, from limits.engine_lines |
| `LA_COMFY_CFG` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_CKPT` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_CLIP_VISION` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_CONTROLNET` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_CONTROLNET_POSE` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_SAMPLER` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_STEPS` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_FORCE` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_FORCE_CONTROLNET` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_FORCE_LORA` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_FORCE_LORA_CLIP` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_FORCE_POSE` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_HEIGHT` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_IPA` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_IPA_COSTUME` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_IPA_FACE` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_WIDTH` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_LORA` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_SCHEDULER` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_RESOLUTION` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_SIZE` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_UPSCALE` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_WEIGHT` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_WEIGHT_COSTUME` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_COMFY_WEIGHT_FACE` | a knob of the comfyui body that reads it: checkpoint, clip, controlnet, steps, size, weights or a force flag |
| `LA_CONF` | the config folder of the tree, as boot.sh reads it |
| `LA_CONFIG` | the master file itself, la_config.yaml: what a body or a program reads instead of a path |
| `LA_DATA` | the data folder: the bases and the measurement files |
| `LA_DDGR` | the search endpoint a body calls instead of a browser |
| `LA_DEPTH` | how deep a delegate body already is |
| `LA_DIR` | the folder of the bricks, the engine folder, where boot.sh and run.sh stand |
| `LA_DOOR_ENTERED` | 1 once run.sh has entered: boot.sh sources it, so a second entry would be a loop |
| `LA_EMBED_MODEL` | the embedding model the memory bodies ask for |
| `LA_EMBED_PORT` | where the embedding model listens, for the memory bodies |
| `LA_ENV` | the key file, conf/.env: the secrets never travel by argument |
| `LA_FROM` | who called the door: engine, model, bridge, applet. It decides the register read |
| `LA_GGUF_DIR` | where the quantised models sit, for a body that reads one |
| `LA_HOME` | the home of the machine, used only by the installer and the uninstaller |
| `LA_HOST` | the address the bridge listens on, from machine.host |
| `LA_INDEX` | index_la.yaml: the file that says where every other file lives |
| `LA_LANDRUN` | the runner a shell_run body uses |
| `LA_LID_MODEL` | the language-identification model, for the body that names a language |
| `LA_LIGHTPANDA` | the proxy address the extract body goes through |
| `LA_LLAMA_BIN` | the llama.cpp binary a body calls |
| `LA_LOCAL_PORT` | where the local model listens, for a body that asks it |
| `LA_LOOP` | the counter of the turn, for a body that reads how many calls were made |
| `LA_MAX_TURNS` | the turn bound a delegate body hands down |
| `LA_MEMORY_DB` | memory.db, what was learned, kept apart from the conversation |
| `LA_NOTE_BYTES` | the size bound of one note |
| `LA_NOTE_FILE` | where a sticky note body keeps its note |
| `LA_PAGE` | the folder of the page: page.html, the icons, the service worker |
| `LA_PORT_ASR` | the port of the ear, from units.asr.port |
| `LA_PORT_BRIDGE` | the port of the bridge, from ports.bridge |
| `LA_PORT_MODELS` | the port of the model resident, from units.models.port |
| `LA_PORT_DASH` | the port the dashboard unit answers on, from ports.dash: the same server as the bridge |
| `LA_PORT_TLS` | the port the phone reaches over tls, from ports.tls: served only when the certificate exists |
| `LA_PORT_TTS` | the port of the voice resident, from units.tts.port |
| `LA_REPLY_STREAM` | the answer as it is being written, before the turn is closed |
| `LA_RETURNS` | the folder of the returns: what a tool gave, kept out of the conversation |
| `LA_RETURN_DB` | the base of the returns, for the body that reads one back |
| `LA_ROOT` | the root of the tree, exported once by boot.sh: every other path hangs from it |
| `LA_SESSIONS_DB` | sessions.db, the conversation: one row per message |
| `LA_SKILLSET` | the tool ids the armed skill carries, as one string |
| `LA_STATE` | the state folder: marks, queues, the turn object |
| `LA_STATE_PROJECT` | the project armed for this turn, as a state file |
| `LA_STATE_SKILL` | the skill armed for this turn, as a state file |
| `LA_STOP_FILE` | the stop mark, for a body that must not run after a stop |
| `LA_TABLE` | the register a table body reads |
| `LA_TOOL` | the door itself, la.sh: the one way in, for the model and for the bridge |
| `LA_TRACE` | trace.jsonl, the living channel: one line per event of the turn |
| `LA_TTS_MODEL` | the onnx voice of the resident, read by tts_daemon.py |
| `LA_TTS_PORT` | the port the voice resident binds, the same number as LA_PORT_TTS |
| `LA_TTS_SID` | the speaker id of the voice, read by tts_daemon.py |
| `LA_TTS_THREADS` | how many threads the voice resident gives to onnx |
| `LA_UNITY_CLI` | the unity command line, on the machine that owns the editor, for the 482 unity bodies |
| `LA_UNITY_MCP` | the unity mcp endpoint, for the coplay bodies |
| `LA_VISION_MODEL` | the vision model a body loads |
| `LA_WRITEABLE_WORKSPACE` | the workspace of the armed skill or project: where a write lands |
