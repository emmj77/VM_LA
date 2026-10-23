# LA — le plan cumulatif (fichier unique)

Plan de LA : **bâtir les outils de la famille ENGINE**, extraits des `.py` et des `.sh`.
Pour chaque fonction : l'outil engine qu'elle nourrit (existant → on le remplit ; nouveau →
il s'inscrit). Rien d'autre — ni « brique-outil », ni « recette ».

## 0. Le modèle

Deux niveaux, deux seulement (canon l.29-30) :
- **brique** = « runs during a turn, without the model asking → brick, **sourced** ». Une lib
  shell **sourcée**, toujours chargée : `cfg, msg, fs, tab, skl, canon, trace, shape, loop,
  step, approval`. **Ce n'est pas un outil** : pas de YAML, pas de porte, pas de famille.
  `config` = la brique `cfg`, `map` = la brique `tab` — des briques, pas des outils.
- **outil** = « action asked, parameters, verdict → **YAML tool** ». Une action YAML, appelée
  **par la porte**, rangée dans une **famille** : `engine`, `doctor`, `agent`, `turn`.

L'argument (units, chemins, bornes…) vit dans `la_config` ; le corps YAML ne porte que
l'opération.

---

## 1. Les 27 outils engine (la cible)

Ils existent déjà (un fichier `tool_engine_*.yaml` chacun). La colonne id = leur identité.

| id | outil engine | rôle | fait |
|---|---|---|---|
| E001 | engine.approve | the human door: request, grant, deny, status |  |
| E002 | engine.asr | the ear: start, stop, status |  |
| E003 | engine.backup | the net outside the disk: now, verify, restore |  |
| E004 | engine.commands | the surfaces of la: board, once, app, cli, doctor, tool, new, update… |  |
| E005 | engine.doctor | runs every control of the doctor family and counts |  |
| E006 | engine.hist | sessions.db: init, add, window, apply, result |  |
| E007 | engine.install | what is placed: units, command, desktop, applet, certs |  |
| E008 | engine.models | the router of the models: load, unload, status |  |
| E009 | engine.retention | the bounds applied: audio, returns, logs, bases |  |
| E010 | engine.spec | the canon: add one law, or read it |  |
| E011 | engine.stat | sessions.db, counted: exchanges, tools, cost |  |
| E012 | engine.switch | the active provider: list, take |  |
| E013 | engine.trace | the living channel: write a line, read the tail |  |
| E014 | engine.tts | the voice: start, stop, status |  |
| E015 | engine.tunnel | wireguard desktop↔phone: up, down, status, qr |  |
| E016 | engine.update | the project by git: check, apply, rollback |  |
| E017 | engine.reload | the register rebuilt from the bodies |  |
| E019 | engine.signal | task signals: raise one, take one, list them |  |
| E020 | engine.board | the state of the machine: one line, sections, object |  |
| E021 | engine.residents | the residents: state, start, stop |  |
| E022 | engine.service | one of the four services, in the foreground |  |
| E023 | engine.turn | one turn of the loop: text in, answer out |  |
| E024 | engine.map | the map of the names: rebuilt from the disk |  |
| E025 | engine.uninstall | what install posed, removed |  |
| E026 | engine.wake | a wake opens a request |  |
| E027 | engine.purge | gives the cold page cache back to the kernel |  |
| E028 | engine.config | reads the config: one dotted key (str/num/list/has) |  |

---

## 3. L'extraction — chaque fonction a UN sort (fichier par fichier)

Chaque fonction (`.py` et `.sh`) reçoit **un** sort, et un seul :
1. **entre dans un outil engine qui existe** (le corps va dans `engine.*`) ;
2. **exige un NEW outil engine** → il s'inscrit alors dans §1 ;
3. **reste dans le Py** (serveur HTTP, TUI, glue Python) ;
4. **reste dans le Sh** (porte, exécutant, briques sourcées).
On avance **un fichier à la fois**. Ni « brique cible », ni « recette ».

### 3.1 `board.py` (1782 l., 103 def/class)

| fichier | fonction (l.) | rôle | sort | fait |
|---|---|---|---|---|
| board.py | state_dir 35 · num 40 · _cfg 53 · laconf 189 · dotted 206 · read_state 1197 | lit la_config (Python) | **reste Py** |  |
| board.py | bridge 62 · bridge_ping 81 · bridge_state 86 | appels au pont | **reste Py** |  |
| board.py | read_head 90 | snapshot de tête | **reste Py** |  |
| board.py | _units 94 · alive 294 · read_residents 350 | résidents | → engine.residents (E021) |  |
| board.py | _git_state 119 · one 120 · read_git 648 | état git | → engine.update (E016) |  |
| board.py | _engine 129 · read_engine 635 | provider actif | → engine.switch (E012) |  |
| board.py | _db_counts 145 · _db_query 151 · class model 216 | sessions.db | → engine.hist (E006) · engine.stat (E011) |  |
| board.py | _table 161 · read_registry 505 · read_table 580 | registre | → engine.map (E024) |  |
| board.py | _port 239 · run 278 · probe 287 | port / probe | → engine.board (E020) |  |
| board.py | _router_models 340 · _models_in 520 · read_modeles 553 · place 556 · size_of 536 | fichiers modèles | → engine.models (E008) |  |
| board.py | _appoint_rows 378 · read_appoints 404 · read_approval 420 · _approval_gesture 913 | approbation | → engine.approve (E001) |  |
| board.py | _rss_port 389 · read_instruments 488 · read_machine_name 700 (**nvidia-smi 712**) | état machine : RSS / ports / GPU | → engine.board (E020) |  |
| board.py | read_canon 608 | canon | → engine.spec (E010) |  |
| board.py | read_doctor 631 | docteur | → engine.doctor (E005) |  |
| board.py | read_traffic 655 | trafic / journal | → engine.stat (E011) · engine.trace (E013) |  |
| board.py | read_turn 678 · _tool_line 1251 · Tailer 1217 | canal vivant | → engine.trace (E013) |  |
| board.py | control 744 · _expand 876 · _ratio_of 889 · board_object 925 · row 939 · sections 986 · one_line 1023 · snapshot 1205 | forme du board | → engine.board (E020) |  |
| board.py | one_turn 1267 · stream 1272 | un tour | → engine.turn (E023) |  |
| board.py | weight 302 · line 312 · build 313 · ago 727 · short 970 · tint 1037 · _footer 1058 · human_count 1178 · shorten 1192 | mise en forme (TUI) | **reste Py** |  |
| board.py | _sigwinch 1033 · _keys 1047 · tui 1063 · class Cli 1306+ · cli 1709 · main 1714 | interface terminal | **reste Py** (TUI) |  |
| board.py | base 1155 · http 1159 · door_line 1171 | serveur HTTP du board | **à retirer** (dash_server sert l'HTTP) |  |

**0 outil nouveau dans `board.py`.** Chaque fonction **entre dans un outil engine existant** ou **reste dans le Py**. Rien ne « fait tout » : les faits machine (RSS/ports/GPU) vont dans `engine.board`, qui EST « the state of the machine ». Config lue en Python → reste Py (`engine.config` E028 à confirmer).

### 3.2 `bridge.py` (1122 l., 57 def/class)

Bridge = surface HTTP mince : elle sert des pages et **appelle la porte**. Elle **ne crée aucun outil** — chaque fonction entre dans un outil engine existant, ou reste le serveur Py.

| fichier | fonction (l.) | rôle | sort | fait |
|---|---|---|---|---|
| bridge.py | env 36 · die 43 · state_file 48 · kind_of 52 · now 56 · cached 168 · work 178 · warm 470 · flush 545 · first_name 483 | util / cache | **reste Py** |  |
| bridge.py | door 60 · ask 67 · delegate 87 | appelle la porte (client) | **reste Py** |  |
| bridge.py | conf 97 · conf_section 119 · root_file 133 · active_name 137 · _fields 198 | lit la_config (Python) | **reste Py** |  |
| bridge.py | agents_list 146 · registry 954 | liste des agents | → engine.map (E024) |  |
| bridge.py | approval_window 189 · feed_of 212 · approval_view 238 | vue d'approbation | → engine.approve (E001) |  |
| bridge.py | board_json 265 · panels 927 | état du board | → engine.board (E020) |  |
| bridge.py | _thinking_keep 288 · _keep_turn 296 · summary_text 489 · short_agent_line 520 | forme du tour | **reste Py** |  |
| bridge.py | _machine_return 323 → **systemctl 327** | units / mémoire | → engine.residents (E021) — **ne refait pas `systemctl`** |  |
| bridge.py | _watch_armed 351 · _watch_once 355 · watch_loop 425 | veille des tours | **reste Py** |  |
| bridge.py | _turn_file 443 · run_turn 616 | un tour | → engine.turn (E023) |  |
| bridge.py | _trace_events 447 | événements d'appels | → engine.trace (E013) |  |
| bridge.py | head_snapshot 530 | snapshot de tête | **reste Py** |  |
| bridge.py | config_page 579 | page config | → engine.commands (E004) |  |
| bridge.py | voice 601 | la parole | → engine.tts (E014) |  |
| bridge.py | class Handler 639 (do_GET/do_POST/route/api/as_json/inner/work/inside/extension/body/object/lines/json/redirect/file/send) · main 1091 | serveur HTTP | **reste Py** |  |

**0 outil nouveau dans `bridge.py`.** Soit elle appelle un outil engine existant, soit elle reste le serveur Py. Défaut : `_machine_return` refait `systemctl` → doit appeler `engine.residents`.

### 3.3 `dash_server.py` (228 l., 18 def/class)

| fichier | fonction (l.) | rôle | sort | fait |
|---|---|---|---|---|
| dash_server.py | commands 31 · commands_html 57 · commands_legend 62 | liste des commandes | → engine.commands (E004) |  |
| dash_server.py | run_command 67 | lance une commande par la porte | **reste Py** |  |
| dash_server.py | class Handler 91 (log_message/body/send_page/reply/relay/do_GET/do_POST/do_HEAD) · watch_idle 196 · serve 203 · class Woken 208 (server_bind/server_activate) | serveur HTTP + relais | **reste Py** |  |

**0 outil nouveau dans `dash_server.py`.** Surface HTTP, comme le bridge.

### 3.4 les `.sh` du moteur — un tableau par fichier

**Une ligne par fonction.** Colonne `sort` : **reste Sh** = le code reste dans la brique sourcée ; **→ engine tool** = c'est une action, elle sort dans l'outil.

#### approval.sh (64 l. + 3 ex skl.sh = 11 fns)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| approval.sh | _ap_key 5 | → `_approval_key` | lit la clé HMAC (env) | **reste Sh** |  |
| approval.sh | _ap_digest 11 | → `_approval_digest` | sha256 tronqué d'un geste | **reste Sh** |  |
| approval.sh | _ap_sig 13 | → `_approval_sig` | signature HMAC d'un digest | **reste Sh** |  |
| approval.sh | approval_request 20 | → `approval_request` | écrit la demande de go | **→ engine.approve (E001)** |  |
| approval.sh | approval_ok 30 | → `approval_ok` | vérifie un go signé (fenêtre + HMAC) — la porte l'appelle | **reste Sh** |  |
| approval.sh | approval_grant 42 | → `approval_grant` | accorde (signe) + efface la demande | **→ engine.approve (E001)** |  |
| approval.sh | approval_deny 58 | → `approval_deny` | refuse + efface | **→ engine.approve (E001)** |  |
| approval.sh | approval_status 64 | → `approval_status` | tool approuvé, ou none | **→ engine.approve (E001)** |  |
| approval.sh | approval_of (ex skl.sh 687) | → `approval_of` | ce qu'un corps dit qu'un humain doit signer | **reste Sh** |  |
| approval.sh | skill_approval (ex skl.sh 701) | → `approval_skill` | le skill doit-il être signé ? | **reste Sh** |  |
| approval.sh | is_gated (ex skl.sh 709) | → `approval_gated` | l'appel attend-il une signature ? | **reste Sh** |  |

> reçoit de `skl.sh` : `approval_of`, `skill_approval`, `is_gated` (l'approbation appartient ici). 4 verbes → `engine.approve (E001)` ; la vérif + crypto reste Sh.

#### args.sh (82 l., 9 fns)

| fichier | fonction (l.) | rôle | sort | fait |
|---|---|---|---|---|
| args.sh | args_word 5 | une valeur en un mot shell | **reste Sh** |  |
| args.sh | args_ok 10 | la valeur respecte le type | **reste Sh** |  |
| args.sh | args_bool 27 | la valeur en 0/1 | **reste Sh** |  |
| args.sh | args_path 35 | la valeur en chemin plein, sous ROOT | **reste Sh** |  |
| args.sh | args_line 50 | le mot qu'une commande reçoit | **reste Sh** |  |
| args.sh | args_env 64 | une ligne d'assignation d'environnement | **reste Sh** |  |
| args.sh | args_split 70 | un item par ligne d'une déclaration | **reste Sh** |  |
| args.sh | args_decl 75 | le type d'un argument déclaré | **reste Sh** |  |
| args.sh | args_enum 80 | les valeurs permises d'un argument | **reste Sh** |  |

> 9 / 9 **reste Sh** : préfixe `args_` déjà conforme — **aucun renommage**.

#### boot.sh (71 l., 0 fonction)

Le liant : source `cfg.sh` + les briques, exporte les chemins. Aucune fonction ⇒ rien à extraire.

#### manifest.sh (63 l., 9 fns) — ex `canon.sh`, le manifeste projet (levée de l'ambiguïté avec LE canon / `ARCHITECTURE_LA.txt`)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| manifest.sh | canon_file 5 | → `manifest_file` | le manifeste du projet (zone SPEC) | **reste Sh** |  |
| manifest.sh | canon_decl 10 | → `manifest_decl` | la déclaration du projet (project.yml) | **reste Sh** |  |
| manifest.sh | canon_root 19 | → `manifest_root` | la racine déclarée par le projet | **reste Sh** |  |
| manifest.sh | canon_get 30 | → `manifest_get` | un champ de la déclaration | **reste Sh** |  |
| manifest.sh | canon_rule 38 | → `manifest_rule` | une valeur sous RULES | **reste Sh** |  |
| manifest.sh | canon_law 43 | → `manifest_law` | les phrases de refus déclarées | **reste Sh** |  |
| manifest.sh | canon_summary 49 | → `manifest_summary` | les lignes du projet, par rang | **reste Sh** |  |
| manifest.sh | canon_skills 56 | → `manifest_skills` | les skills du projet, par rang | **reste Sh** |  |
| manifest.sh | canon_path 63 | → `manifest_path` | le nom que le doc donne à cette brique | **reste Sh** |  |

#### cap.sh (78 l., 5 fns)

| fichier | fonction (l.) | rôle | sort | fait |
|---|---|---|---|---|
| cap.sh | cap_bytes 5 | stdin, au plus N octets, le coupé est dit | **reste Sh** |  |
| cap.sh | cap_head 22 | les premières lignes, le reste est dit | **reste Sh** |  |
| cap.sh | cap_tail 30 | les dernières lignes, le début est dit | **reste Sh** |  |
| cap.sh | cap_lines 42 | stdin coupé à N lignes, le milieu d'abord | **reste Sh** |  |
| cap.sh | cap_return 59 | court tel quel, long → fichier + son chemin | **reste Sh** |  |

> 5 / 5 **reste Sh** : préfixe `cap_` déjà conforme — **aucun renommage**.

#### Réorganisation de `cfg.sh` (287 l., 24 fns) → 3 fichiers + 1 fn vers skill.sh

Convention : **préfixe = nom du fichier**, `_préfixe_x` = privé, chaque fichier expose son propre verbe. Le méga-verbe `cfg` se **scinde** en `config` (valeurs) et `tree` (chemins).

##### config.sh — lire une valeur du maître (7 fns) — verbe `config`

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| config.sh | _flat_raw 5 | → `_config_flat_raw` | aplatit le maître en table | **reste Sh** |  |
| config.sh | _flat 49 | → `config_flat` | la table, en cache *(15 fichiers l'appellent)* | **reste Sh** |  |
| config.sh | conf_str 65 | → `config_str` | une valeur (chaîne) | **reste Sh** |  |
| config.sh | conf_num 73 | → `config_num` | une valeur (nombre) | **reste Sh** |  |
| config.sh | conf_list 83 | → `config_list` | une valeur (liste) | **reste Sh** |  |
| config.sh | conf_has 91 | → `config_has` | la clé existe ? | **reste Sh** |  |
| config.sh | cfg 229 | → `config` | le verbe (str/num/list/has) | **reste Sh** |  |

##### tree.sh — l'index → une place (14 fns) — verbe `tree`

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| tree.sh | _cfg_exts 96 | → `_tree_exts` | extensions connues | **reste Sh** |  |
| tree.sh | _cfg_tree 106 | → `_tree_find` | cherche une entrée dans l'index | **reste Sh** |  |
| tree.sh | _cfg_map_build 138 | → `tree_build` | (re)construit tree.map (find) | **reste Sh** |  |
| tree.sh | _cfg_locate 147 | → `tree_locate` | nom → chemin via la map | **reste Sh** |  |
| tree.sh | cfg_dir 162 | → `tree_dir` | chemin d'un dossier | **reste Sh** |  |
| tree.sh | cfg_file 163 | → `tree_file` | chemin d'un fichier | **reste Sh** |  |
| tree.sh | _cfg_world 166 | → `_tree_world` | section world (hors arbre) | **reste Sh** |  |
| tree.sh | _cfg_tree_list 181 | → `tree_list` | liste kind → chemin → id | **reste Sh** |  |
| tree.sh | _cfg_here 194 | → `tree_here` | chemin absolu contre ROOT | **reste Sh** |  |
| tree.sh | _cfg_family 206 | → `tree_family` | id d'un nom (zone + N) | **reste Sh** |  |
| tree.sh | _cfg_place 216 | → `tree_place` | nom → place (state, sinon arbre) | **reste Sh** |  |
| tree.sh | cfg_path 225 | → `tree_path` | dossier absolu | **reste Sh** |  |
| tree.sh | cfg_abs 226 | → `tree_abs` | fichier absolu | **reste Sh** |  |
| tree.sh | project_dir 266 | → `tree_project` | dossier d'un projet *(114 fichiers l'appellent)* | **reste Sh** |  |

> Le verbe `cfg` perd ses branches `dir/file/path/abs/tree/map/here/where` : elles deviennent le verbe **`tree`** (`tree path tools`, `tree abs turn`…).

##### channel.sh — le canal (2 fns)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| channel.sh | channel_label 254 | → `channel_label` | le label de l'appelant | **reste Sh** |  |
| channel.sh | channel_set 256 | → `channel_set` | les drapeaux du canal | **reste Sh** |  |

##### skill.sh ← +1 (le canal et le projet ne sont pas du config)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| skill.sh | skill_rule 279 | → `skill_rule` | `RULES.<k>` de la skill armée | **reste Sh** |  |

> **24 réparties** : `config 7 · tree 14 · channel 2 · skill 1`. Renommages : `config_*`, `tree_*` ; `channel_*` et `skill_rule` étaient déjà conformes.
> ⚠️ **Churn d'appelants (assumé — « on renomme tout »)** : le verbe `cfg X` devient `config X` (valeurs) ou `tree X` (chemins) dans **tous les corps d'outils** ; `project_dir` → `tree_project` touche **114 fichiers** (les upipe) ; `_flat` → `config_flat` touche **15 fichiers**.

#### fs.sh (65 l., 7 fns)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| fs.sh | abs_path 6 | → `fs_abs_path` | chemin rendu absolu contre ROOT | **reste Sh** |  |
| fs.sh | state_paths 15 | → `fs_state_paths` | le dossier d'état, ou un de ses fichiers | **reste Sh** |  |
| fs.sh | tmpfile 29 | → `fs_tmpfile` | un fichier temporaire frais | **reste Sh** |  |
| fs.sh | write_atomic 37 | → `fs_write_atomic` | le texte arrive sur stdin, le fichier apparaît d'un coup | **reste Sh** |  |
| fs.sh | fs_json 47 | → `fs_json` | le texte échappé pour une chaîne JSON | **reste Sh** |  |
| fs.sh | fs_age 53 | → `fs_age` | secondes depuis la dernière écriture | **reste Sh** |  |
| fs.sh | env_get 61 | → `fs_env_get` | une valeur du fichier de clés | **reste Sh** |  |

#### la.sh (24 l., 0 fonction)

Aiguillage (`la cli` / `la <cmd>` → `run_call`). Aucune fonction ⇒ rien à extraire.

#### msg.sh (26 l., 3 fns)

| fichier | fonction (l.) | rôle | sort | fait |
|---|---|---|---|---|
| msg.sh | msg 5 | la phrase, arguments remplis | **reste Sh** |  |
| msg.sh | msg_str 17 | le texte brut, sans substitution | **reste Sh** |  |
| msg.sh | msg_has 24 | la phrase existe ? | **reste Sh** |  |

> 3 / 3 **reste Sh** : préfixe `msg_` déjà conforme — **aucun renommage**.

#### run.sh (308 l., 10 fns)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| run.sh | _door_field 5 | → `run_field` | un scalaire d'un corps | **reste Sh** |  |
| run.sh | _door_decl 20 | → `run_decl` | les arguments déclarés du corps | **reste Sh** |  |
| run.sh | _door_usage 45 | → `run_usage` | la forme de l'appel | **reste Sh** |  |
| run.sh | _door_fill 80 | → `run_fill` | remplit les `{{patterns}}` | **reste Sh** |  |
| run.sh | _door_arity_fail 94 | → `run_arity_fail` | le refus, puis l'usage | **reste Sh** |  |
| run.sh | _door_cmd 108 | → `run_cmd` | le texte de la commande | **reste Sh** |  |
| run.sh | _door_register 120 | → `run_register` | le registre que l'appelant peut lire | **reste Sh** |  |
| run.sh | run_call 124 | → `run_call` | **la porte** : id → corps → contrôles → exécution | **reste Sh** |  |
| run.sh | say_err 284 | → `run_say_err` *(ou `msg_say_err` ?)* | la ligne sur stderr | **reste Sh** |  |
| run.sh | die 289 | → `run_die` *(ou `msg_die` ?)* | la phrase, puis sortir | **reste Sh** |  |

> 10 / 10 **reste Sh** : `run.sh` **est** la porte — elle *appelle* les outils engine ; elle n'est pas un outil. ⚠️ `say_err`/`die` sont sortie/arrêt, **pas** la porte : à arbitrer — restent `run_*` ou rejoignent `msg.sh` (`msg_say_err`/`msg_die`).

#### Réorganisation de `shell.sh` (137 l., 6 fns) → 2 fichiers : `machine.sh` + `exec.sh`

Deux métiers dans un fichier : **construire** une ligne de commande pour un service, et **lancer** un corps. On sépare.

##### machine.sh — la couche machine : `(machine, op, args)` → une ligne (5 fns)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| machine.sh | shell_addr 5 | → `machine_addr` | une adresse d'une machine (via `config`) | **reste Sh** |  |
| machine.sh | shell_bin 10 | → `machine_bin` | le binaire d'une machine | **reste Sh** |  |
| machine.sh | shell_cmd 24 | → `machine_cmd` | la ligne d'une `machine.opération` (llama / asr / tts / blender) | **reste Sh** |  |
| machine.sh | shell_run 120 | → `machine_run` | `machine_cmd` + `exec_body` | **reste Sh** |  |
| machine.sh | krita_url 129 | → `machine_url` | le service krita, vérifié avant usage | **reste Sh** |  |

##### exec.sh — l'exécutant : lancer un corps (1 fn) — le cœur du moteur

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| exec.sh | shell_exec 84 | → `exec_body` | **la seule voie qui lance un corps** : borne, code retour, `shape`, ferme le step | **reste Sh** |  |

> **6 réparties** : `machine 5 · exec 1`. `shell.sh` n'existe plus. `exec_body` est le gosier du moteur — jamais un outil ; la porte (`run.sh`) décide *quoi* lancer, `exec_body` le lance.

#### tab.sh (257 l., 18 fns)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| tab.sh | _block 7 | → `_tab_block` | les lignes d'une entrée | **reste Sh** |  |
| tab.sh | table_block 25 | → `tab_block` | l'entrée, dans la table nommée | **reste Sh** |  |
| tab.sh | table_entry 28 | → `tab_entry` | l'entrée, par id ou par nom | **reste Sh** |  |
| tab.sh | table_field 49 | → `tab_field` | une valeur d'une entrée | **reste Sh** |  |
| tab.sh | table_field_list 68 | → `tab_field_list` | une liste entre crochets | **reste Sh** |  |
| tab.sh | table_keys 74 | → `tab_keys` | les clés d'une entrée | **reste Sh** |  |
| tab.sh | table_ids 85 | → `tab_ids` | tous les id de la table | **reste Sh** |  |
| tab.sh | table_index 91 | → `tab_index` | la table entière, aplatie | **reste Sh** |  |
| tab.sh | block_by_id 116 | → `tab_block_by_id` | le bloc d'un id dans TABLE | **reste Sh** |  |
| tab.sh | body_of 119 | → `tab_body_of` | le bloc d'un id (alias) | **reste Sh** |  |
| tab.sh | count 122 | → `tab_count` | sa taille, « octets lignes » | **reste Sh** |  |
| tab.sh | cmd_ids 134 | → `command_ids` | les id de la table de commandes | **→ engine.commands (E004)** |  |
| tab.sh | cmd_get 138 | → `command_get` | un champ d'une commande | **→ engine.commands (E004)** |  |
| tab.sh | cmd_usage 143 | → `command_usage` | la liste des commandes | **→ engine.commands (E004)** |  |
| tab.sh | cmd_slash 158 | → `command_slash` | le premier mot de chaque commande | **→ engine.commands (E004)** |  |
| tab.sh | cmd_has 166 | → `command_has` | est-ce le premier mot d'une commande ? | **→ engine.commands (E004)** |  |
| tab.sh | cmd_new_turn 175 | → `command_new_turn` | met de côté l'état du tour précédent | **→ engine.commands (E004)** |  |
| tab.sh | cmd_run 186 | → `command_run` | le routeur de `la` (mot → acte / outil) | **→ engine.commands (E004)** |  |

> 11 **reste Sh** (brique `tab`) · 7 **→ engine.commands (E004)**, qui **EST** le routeur de `la`. Son corps inline duplique ces fonctions → il doit les **appeler** (une seule source).

#### head_second.sh (138 l., 11 fns)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| head_second.sh | _sec_channel 6 | → `head_second_channel` | section canal | **reste Sh** |  |
| head_second.sh | _sec_human 10 | → `head_second_human` | section humain | **reste Sh** |  |
| head_second.sh | _sec_project 15 | → `head_second_project` | section projet actif | **reste Sh** |  |
| head_second.sh | _sec_skill 27 | → `head_second_skill` | section skill actif | **reste Sh** |  |
| head_second.sh | _sec_summary 63 | → `head_second_summary` | section résumé du modèle local | **reste Sh** |  |
| head_second.sh | _sec_plan 78 | → `head_second_todo` | section plan du skill | **reste Sh** |  |
| head_second.sh | _sec_project_plan 84 | → `head_second_bigtodo` | section grand plan du projet | **reste Sh** |  |
| head_second.sh | _sec_note 102 | → `head_second_note` | section note collante | **reste Sh** |  |
| head_second.sh | _sec_agents 107 | → `head_second_agents` | section agents | **reste Sh** |  |
| head_second.sh | _sec_chat 121 | → `head_second_chat` | section chat | **reste Sh** |  |
| head_second.sh | _sec_toolset 133 | → `head_second_toolset` | section toolset | **reste Sh** |  |

> 11 / 11 **reste Sh** : producteurs de la tête secondaire ; `turn.prompt` les source et appelle la fonction nommée par chaque id.

#### loop.sh (150 l., 8 fns)

| fichier | fonction (l.) | rôle | sort | fait |
|---|---|---|---|---|
| loop.sh | _step_end 8 | la dernière étape du cycle | **reste Sh** |  |
| loop.sh | loop_before 15 | les étapes avant l'appel | **reste Sh** |  |
| loop.sh | loop_cycle 22 | les étapes du cycle | **reste Sh** |  |
| loop.sh | loop_after 32 | les étapes après la fin | **reste Sh** |  |
| loop.sh | loop_busy 42 | un autre tour tient-il la marque ? | **reste Sh** |  |
| loop.sh | loop_mark 51 | ce shell possède le tour | **reste Sh** |  |
| loop.sh | loop_release 60 | le tour est fini, la marque part | **reste Sh** |  |
| loop.sh | loop_turn 67 | **le tour** : étapes en ordre, appels répétés, bornes | **reste Sh** |  |

> 7 / 8 **reste Sh** conformes. **1 renommage** : `_step_end` → `_loop_step_end`. C'est la brique `loop` (le tour) ; `engine.turn` l'appelle.

#### shape.sh (60 l., 5 fns)

| fichier | fonction (l.) | rôle | sort | fait |
|---|---|---|---|---|
| shape.sh | shape 5 | une ligne, un objet (6 champs, toujours) | **reste Sh** |  |
| shape.sh | shape_ok 16 | l'appel a marché | **reste Sh** |  |
| shape.sh | shape_fail 21 | un refus nommé, dans la même forme | **reste Sh** |  |
| shape.sh | shape_get 33 | un champ relu | **reste Sh** |  |
| shape.sh | shape_short 56 | le même objet, coupé pour un écran étroit | **reste Sh** |  |

> 5 / 5 **reste Sh** : préfixe `shape` déjà conforme — c'est la brique `shape`, la forme que tout appel renvoie. **Aucun renommage.**

#### step.sh (39 l., 8 fns)

| fichier | ancien (l.) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| step.sh | _turn_file 4 | → `step_file` | le fichier d'état du tour — lu par **tous** les outils `turn.*` | **reste Sh** |  |
| step.sh | _turn_get 5 | → `step_get` | lit une valeur du tour — **l'accesseur unique** des `turn.*` + `load_doc/load_spec/app_spec` + `head_second` + `loop` | **reste Sh** |  |
| step.sh | _turn_set 6 | → `step_set` | écrit une valeur du tour — le même accesseur unique | **reste Sh** |  |
| step.sh | _turn_set_json 7 | → `step_set_json` | écrit une valeur JSON du tour | **reste Sh** |  |
| step.sh | trace_line 11 | → `step_trace` | la seule façon d'écrire une ligne du journal (appelle `engine.trace`) | **reste Sh** |  |
| step.sh | step_list 14 | → `step_list` | l'ordre (pipeline) | **reste Sh** |  |
| step.sh | prompt_text 21 | → `step_prompt` | ce que l'human a demandé | **reste Sh** |  |
| step.sh | step_run 28 | → `step_run` | lance une étape (par la porte) | **reste Sh** |  |

> 8 / 8 **reste Sh** — **un seul fichier** `step.sh`, pas de split : un tour et son étape sont le même cycle de vie, et un fichier de 39 lignes ne se fragmente pas. Préfixe `step_` partout. Les outils `turn.*` (YAML dans `turn[D19]`) *appellent* `step_get` / `step_set` / `step_set_json` / `step_trace` ; ces fonctions restent Sh car elles sont **le seul point** de lecture/écriture de `state/turn.json`.

#### Réorganisation de `skl.sh` (715 l., 51 fns) → 8 fichiers d'un métier

`skl.sh` se scinde en 8 fichiers distincts ; il est réparti ci-dessous, **aucune fonction coupée ni perdue** (les n° de ligne renvoient à l'ancien `skl.sh`). Chaque fichier = **un** métier ; ses 3 fonctions d'approbation remontent dans `approval.sh`. Les fichiers s'appellent entre eux (tous sourcés par `boot.sh`) → **zéro duplication : chaque fonction a un seul domicile.**

##### active.sh — l'état armé : qui est actif (8 fns)

Ce n'est pas « skill » : le fichier lit/écrit **les trois noms actifs** (skill, projet, agent) et les arme/désarme.

| fichier | ancien (l. skl) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| active.sh | skl_skill 9 | → `active_skill` | le nom du skill armé | **reste Sh** |  |
| active.sh | skl_project 16 | → `active_project` | le nom du projet armé | **reste Sh** |  |
| active.sh | skl_agent 47 | → `active_agent` | l'agent au plan vivant | **reste Sh** |  |
| active.sh | skl_arm 559 | → `active_arm` | armer un skill | **reste Sh** |  |
| active.sh | skl_disarm 567 | → `active_disarm` | désarmer (skill + plan partent) | **reste Sh** |  |
| active.sh | skl_turn_end 578 | → `active_turn_end` | fin de tour (plan ouvert garde le skill) | **reste Sh** |  |
| active.sh | skl_project_arm 589 | → `active_project_arm` | armer un projet | **reste Sh** |  |
| active.sh | skl_project_disarm 597 | → `active_project_disarm` | désarmer un projet | **reste Sh** |  |

> 8 / 8 **reste Sh** — « qui est actif » : `active_skill` (21 appels), `active_project` (11), `active_agent` (8) sont des **accesseurs publics** appelés par `head_second`, `loop`, `canon` et les corps `turn.facts` / `doctor.knowledge`.

##### skill.sh — la déclaration du skill (2 fns + `skill_rule` venue de `cfg.sh` → 3)

| fichier | ancien (l. skl) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| skill.sh | skl_step_file 23 | → `skill_file` | le `skill.yaml` d'un skill | **reste Sh** |  |
| skill.sh | skl_workspace 615 | → `skill_workspace` | où le skill armé a le droit d'écrire | **reste Sh** |  |

> 2 / 2 **reste Sh** — ce que le skill **déclare** de lui-même : son fichier et son workspace (pas sa palette — voir `toolset.sh`). Rejoint ici `skill_rule` (venue de `cfg.sh`), qui lit aussi le `skill.yaml` → **3 fns** au total.

##### todo.sh — le plan-journal du skill (route), écrit par les outils `todo` / `update_todo` — 16 fns, non coupé

| fichier | ancien (l. skl) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| todo.sh | skl_plan_is_closed 34 | → `todo_closed` | le plan est-il une route fermée ? | **reste Sh** |  |
| todo.sh | skl_plan_file 57 | → `todo_file` | le fichier plan-journal d'un agent | **reste Sh** |  |
| todo.sh | skl_plan_src 67 | → `todo_src` | le fichier d'où le plan est lu | **reste Sh** |  |
| todo.sh | skl_plan_step 80 | → `todo_step` | l'étape ouverte du plan | **reste Sh** |  |
| todo.sh | _skl_step_route 115 | → `_todo_route` | l'étape ouverte d'une route | **reste Sh** |  |
| todo.sh | skl_step_tools 143 | → `todo_step_tools` | les outils de l'étape ouverte | **reste Sh** |  |
| todo.sh | _skl_step_at 156 | → `_todo_at` | la clé PLAN.at d'une route | **reste Sh** |  |
| todo.sh | skl_step_close 176 | → `todo_step_close` | ferme l'étape ouverte d'une route | **reste Sh** |  |
| todo.sh | skl_plan_stamp 224 | → `todo_stamp` | le n° de tour où le plan fut touché | **reste Sh** |  |
| todo.sh | skl_turn_no 231 | → `todo_turn_no` | combien de tours la machine a lancés | **reste Sh** |  |
| todo.sh | skl_doc_seen 240 | → `todo_doc_seen` | le doc du skill lu ce tour ? | **reste Sh** |  |
| todo.sh | plan_status 356 | → `todo_status` | ce que la tête montre : doc, plan, étape | **reste Sh** |  |
| todo.sh | _skl_plan_render 389 | → `_todo_render` | rend les lignes numérotées d'un plan | **reste Sh** |  |
| todo.sh | _skl_plan_move 409 | → `_todo_move` | déplace le corps d'un plan | **reste Sh** |  |
| todo.sh | skl_plan_write 436 | → `todo_write` | `todo` écrit le plan-journal | **reste Sh** |  |
| todo.sh | skl_plan_advance 456 | → `todo_advance` | `update_todo` avance le plan-journal | **reste Sh** |  |

> 16 / 16 **reste Sh**. C'est **un** métier (le plan du skill) : même à ~250 lignes on ne le coupe pas. (`lower`/`slug` sortent vers `str.sh` — dessous.)

##### str.sh — helpers de chaîne, génériques (2 fns)

| fichier | ancien (l. skl) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| str.sh | lower 379 | → `str_lower` | le mot en minuscules | **reste Sh** |  |
| str.sh | slug 382 | → `str_slug` | le nom canonique (≤40) | **reste Sh** |  |

> 2 / 2 **reste Sh** — helpers de chaîne **génériques** (appelés par `run`, `board.py`, `bridge.py`, tools blender/comfyui, `texts.yaml`…) : ils n'avaient rien à faire dans `todo.sh`.

##### bigtodo.sh — le grand plan du projet, écrit par `big_todo` / `update_big_todo` / `change_big_todo` (6 fns)

| fichier | ancien (l. skl) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| bigtodo.sh | skl_big_recall 337 | → `bigtodo_recall` | une ligne de tête pour le grand plan | **reste Sh** |  |
| bigtodo.sh | skl_big_file 483 | → `bigtodo_file` | le project.yml du projet armé | **reste Sh** |  |
| bigtodo.sh | _skl_big_body 493 | → `_bigtodo_body` | les lignes du PROJECT_BIGTODO | **reste Sh** |  |
| bigtodo.sh | _skl_big_put 499 | → `_bigtodo_put` | le corps du PROJECT_BIGTODO devient fichier | **reste Sh** |  |
| bigtodo.sh | skl_big_write 518 | → `bigtodo_write` | `big_todo` écrit / `change_big_todo` remplace | **reste Sh** |  |
| bigtodo.sh | skl_big_advance 537 | → `bigtodo_advance` | `update_big_todo` avance le grand plan | **reste Sh** |  |

> 6 / 6 **reste Sh** — le grand plan **du projet** (distinct du plan-journal du skill).

##### gate.sh — la porte + le verrou (5 fns)

| fichier | ancien (l. skl) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| gate.sh | skl_lock 249 | → `gate_lock` | ce qui bloque en premier (doc/todo/étape) | **reste Sh** |  |
| gate.sh | skl_gate 276 | → `gate` *(le verbe)* | **LA PORTE** : sans arg la palette permise, avec arg « autorisé ? » | **reste Sh** |  |
| gate.sh | _skl_gate_check 288 | → `_gate_check` | la question de la porte (codes 0/2/3/4/5) | **reste Sh** |  |
| gate.sh | skl_gate_ask 316 | → `gate_ask` | le mot de la porte, le refus inclus | **reste Sh** |  |
| gate.sh | tool_allowed 329 | → `gate_allowed` | le mot de la porte, d'elle seule | **reste Sh** |  |

> 5 / 5 **reste Sh** — la porte qui décide ce qu'un tour peut porter.

##### toolset.sh — la palette du skill (2 fns)

| fichier | ancien (l. skl) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| toolset.sh | skl_tools_map 605 | → `toolset_map` | la carte `SKILL_TOOL_SET` du skill | **reste Sh** |  |
| toolset.sh | skl_in_toolset 627 | → `toolset_has` | le skill porte-t-il cet outil ? | **reste Sh** |  |

> 2 / 2 **reste Sh** — juste la palette : quels outils le skill ouvre, et *X* y est-il. (`skl_workspace` est parti dans `skill.sh` ; `skl_toolset`, alias de `skl_gate`, **supprimé**.)

##### permission.sh — permissions du registre (6 fns)

| fichier | ancien (l. skl) | → nouveau | rôle | sort | fait |
|---|---|---|---|---|---|
| permission.sh | skl_permanent 641 | → `permission_permanent` | permis quel que soit le skill (le TOOL le dit) | **reste Sh** |  |
| permission.sh | table_perm 651 | → `permission_perm` | le TOOL dit « chaque tour » | **reste Sh** |  |
| permission.sh | table_with_skill 657 | → `permission_with_skill` | permis dès qu'un skill est armé | **reste Sh** |  |
| permission.sh | table_with_project 663 | → `permission_with_project` | permis dès qu'un projet est chargé | **reste Sh** |  |
| permission.sh | table_permanents 669 | → `permission_permanents` | les noms de chaque tour | **reste Sh** |  |
| permission.sh | skl_carries 675 | → `permission_carries` | le skill porte cet outil (nom ou clé) | **reste Sh** |  |

> 6 / 6 **reste Sh** — les requêtes du registre (permanent / with_skill / with_project).

> **51 réparties** : `active 8 · skill 2 · todo 16 · str 2 · bigtodo 6 · gate 5 · toolset 2 · permission 6` + `3 → approval.sh` = 50 placées, **1 supprimée** (`skl_toolset`, alias de `skl_gate`). Chaque fonction a **un seul domicile** ; les fichiers s'appellent (sourcés par `boot.sh`), donc **zéro duplication**.

> ✅ **27 fichiers, un métier chacun.** 17 `.sh` lus ; `cfg.sh` → `config · tree · channel`, `skl.sh` → `active · skill · todo · str · bigtodo · gate · toolset · permission` (+3 fns vers `approval.sh`), `shell.sh` → `machine · exec`. Extraits vers un engine tool : `approval.sh` (4 → `engine.approve`) et `tab.sh` (7 → `engine.commands`). **Tout le reste reste Sh**, une ligne par fonction. ⚠️ 27 > 16 : le canon l.896 (« seize fichiers ») doit être amendé — geste explicite de Moussa.

---

## 6. La surface Android

| fichier | rôle | cible | fait |
|---|---|---|---|
| Bridge.kt | appels HTTP fins vers le pont | reste (surface Kotlin) |  |
| ChatActivity.kt | la vue / le chat | reste (surface Kotlin) |  |

Aucune logique : elle appelle le pont, qui appelle la porte.

---

## 7. Ce qui vit dans `la_config` (les arguments)

Le YAML d'un outil ne porte **que l'opération**. Toutes les valeurs sont lues en config :

- **units** : `units.<k>.unit`, `.port`, `.probe` (models, asr, tts, kws, bridge, dashboard)
- **modèles / moteur** : `models.host`, `models.local`, `engines.<nom>.model`, `active_engine`
- **chemins** : `paths.state`, `.audio`, `.returns`, `.certs`, `.user_units`, `.user_bin`, `.user_apps`, `.applet`
- **bornes** : `limits.db_busy_ms`, `boot_tries`, `health_timeout`, `audio_keep`, `audio_mb`, `audio_min_minutes`, `return_keep`, `trace_bytes`, `trace_keep`, `live_lines`, `tunnel_steps`, `purge_margin`, `loop.window`, `loop.feed_turns`
- **listes** : `lists.audio_patterns`, `doctor.badge`, `backup.supports`, `backup.support`
- **tunnel** : `tunnel.file`, `.interface`, `.port`, `.host`, `.peer`, `.dns`, `.keepalive`, `.phone`, `.public`
- **divers** : `update.return_tag`, `ports.dash`, `board.*`

---

## 8. Le moteur (inchangé) et l'ordre

`la.sh` aiguille → `boot.sh` lie → `run.sh` **la porte** (`run_call`) → `shell.sh` **exécute**.
Les trois sorties (CLI, dashboard, app Android) se branchent sur la même porte.

**Ordre** (un commit par tranche, le moteur jamais touché) :
1. **Écrire/remplir les outils engine** — un `tool_engine_<nom>.yaml` par outil ; `engine.reload op=build`.
2. **Faire appeler** par `board`/`bridge`/`dash` les outils engine existants au lieu de refaire
   le travail (voir §3 : `board.menu` relisait `nvidia-smi`/`ss`/`systemctl` ; `bridge._machine_return` refaisait `systemctl`).
3. **Sortir `app`/`new` de `engine.commands`** ; brancher les trois sorties sur la porte.
4. `board.py` = **TUI seule** ; `engine.board` fournit l'état.
