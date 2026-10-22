# LA — le plan final (fichier unique)

Un seul fichier. La mécanique réelle, la porte et les trois sorties, où vivent les
fonctions, et le **catalogue en trois zones** — MOTEUR (E), AGENT/CŒUR (G), DOCTEUR (D).
Correction dite franchement : le docteur a **22 outils** (pas 7), et ce que j'avais
appelé « catalogue » n'est **pas dans le moteur** — ce sont les outils de l'agent/cœur,
et ils **existent déjà**.

Rien n'est exécuté ici.

---

## 1. La mécanique réelle

- **`la.sh` (E08) — l'ENTRÉE.** La commande `la`. Trouve la racine, source
  `boot.sh`, puis **aiguille** seulement : `la engine …` → `run_call` ; `la` seul
  sur un terminal → `cmd_run cli` ; `la` en pipe → `run_call engine.turn` ; autre
  → `cmd_run`. **Elle n'exécute aucun corps.**
- **`boot.sh` (E03) — le LIANT.** La seule ligne sourcée : trouve la racine, charge
  `cfg.sh` + les briques, exporte les chemins (`LA_ROOT`, `LA_SESSIONS_DB`, ports…).
- **`run.sh` (E11) — LA PORTE.** `run_call <nom> [clé=valeur …]` : lit le registre
  (l'`id`), trouve le corps `tool_<nom>.yaml`, vérifie, construit la commande,
  remplit les `{{arg}}`, puis appelle `shell_exec`.
- **`shell.sh` (E13) — LE SEUL ENDROIT QUI LANCE UN CORPS.** `shell_exec` lance le
  texte en `dash -c`, applique le timeout et **shape** la réponse (le JSON).

Chaîne : **`la.sh` aiguille → `run.sh` porte (`run_call`) → `shell.sh` lance et shape.**

## 2. La porte unique et les trois sorties

Une porte : `run_call` (run.sh) → `shell_exec` (shell.sh). Les trois sorties s'y
branchent :
- **CLI** — `la` seul sur un terminal → `cmd_run cli` → board `--cli`.
- **Dashboard** — `dash_server.py` → `sh la.sh …` → `run_call`.
- **App Android** — HTTP → `bridge.py` → `la engine engine.commands …` → `run_call`.

Une porte, trois sorties, les mêmes outils ; aucune sortie ne lit le disque elle-même.

## 3. Où vivent les fonctions

Un corps par fonction : `tools[D14]/<zone>/tool_<nom>.yaml` — `id`, `tool`,
`DESCRIPTION`, `COMMAND` (shell), `ARGS`. Trois zones de corps :

- **`engine[D16]`** = le **MOTEUR** (ids **E**).
- **`core[D35]`** = l'**AGENT / CŒUR** (ids **G**) — les outils que le modèle appelle
  et que les sorties lisent.
- **`doctor[D15]`** = le **DOCTEUR** (ids **D**) — la santé et l'inventaire.

---

## 4. Les trois zones (ce qui existe vraiment)

Les trois sorties ne lisent pas « le moteur » : elles lisent les **trois zones**. Et
**presque tout ce dont elles ont besoin existe déjà**. Je n'invente plus de « catalogue ».

### 4.1 MOTEUR (engine / E) — 26 outils

Le moteur a 25 outils existants (E001..E027, **E018 absent**, `engine.doctor` **déplacé au docteur**) **+ `engine.config` (E028, nouveau) = 26**. **Aucun à découper** :
chaque famille reste un outil, ses `op` choisissent la cible/le verbe. Seul `board`
devient mince (il compose, §5).

| id | outil | fonction | op |
|---|---|---|---|
| E001 | engine.approve | la porte humaine | request·allow·grant·deny·status |
| E002 | engine.asr | l'oreille | start·stop·status |
| E003 | engine.backup | le filet hors du disque | now·verify·restore |
| E004 | engine.commands | la porte/dispatch des surfaces (zéro logique) | board·once·app·cli·say·turn·doctor·tool·new·update·help·line |
| E006 | engine.hist | la base des sessions | init·add·window·turns·apply·result |
| E007 | engine.install | ce qui est posé | units·command·desktop·applet·certs |
| E008 | engine.models | le routeur des modèles | load·unload·status |
| E009 | engine.retention | les bornes, par catégorie | audio·returns·logs·bases |
| E010 | engine.spec | le canon | add·list |
| E011 | engine.stat | sessions.db comptée | exchanges·tools·cost |
| E012 | engine.switch | le provider actif | list·take |
| E013 | engine.trace | le canal vivant | line·json·tail |
| E014 | engine.tts | la voix | start·stop·status |
| E015 | engine.tunnel | wireguard | up·down·status·qr |
| E016 | engine.update | le projet par git | check·apply·rollback |
| E017 | engine.reload | le registre reconstruit | build |
| E019 | engine.signal | signaux de tâche | raise·take·list |
| E020 | engine.board | **mince** : compose + rend | line·once·json·menu |
| E021 | engine.residents | les résidents | status·up·down·toggle·listen·listen-on·listen-off |
| E022 | engine.service | un service au premier plan | models·asr·tts·kws·bridge·dashboard |
| E023 | engine.turn | un tour | — |
| E024 | engine.map | la carte des noms | rebuild |
| E025 | engine.uninstall | ce que l'install a posé, retiré | units·command·desktop·applet·certs |
| E026 | engine.wake | un réveil | — |
| E027 | engine.purge | rendre le cache froid | all·list·la-asr·la-tts·la-models·la-bridge |
| E028 | engine.config | lit une clé pointée de config/état (créé ✓) | str·num·list·has |

**Total moteur = 26 outils** (dont `engine.config` E028 ; `engine.doctor` E005 parti au docteur).

### 4.2 AGENT / CŒUR (core / G) — 71 outils (TOUS existants)

C'est **ici** que vivent les « listes » que j'avais mal rangées : elles ne sont **pas
dans le moteur**, ce sont les outils de l'agent/cœur, déjà écrits. Extrait représentatif :

- **Skills** : `skill_list` G051 · `skill_view` G052 · `skill_manage` G017 · `load_skill` G053
- **Projets** : `project_list` G033 · `project_view` G054 · `load_project` G034 · `unload_project` G042
- **Config / table / outils** : `config_list` G080 · `config_set` G081 · `table_manage` G018 · `tools_list` G007 (le toolmap) · `tool_show` G057 · `toolset` G026
- **Voix / oreille** : `voice_text` G025 · `transcribe` G021
- **Réponse / agents** : `reply` G001 · `delegate_task` G008 · `send_agent_chat` G063
- **Lire / écrire / chercher** : `read_file` G002 · `write_file` G004 · `search` G005 · `list_dir` G003 · `search_sessions` G029 · `recall` G056 · `search_memory` G019 · `read_return` G058 · `load_doc` G022 · `load_memory` G030
- **Plan** : `todo` G015 · `update_todo` G016 · `big_todo` G048
- **Tunnel** : `tunnel_up` G065 · `tunnel_down` G066 · `tunnel_status` G064 · `tunnel_provision` G072
- **Web / modèles locaux** : `web_search` G031 · `web_extract` G032 · `web_read` G069 · `models_ask` G009 · `models_status` G010
- … et le reste → **71 au total**.

(À nettoyer plus tard : le tunnel et les modèles existent dans **deux** zones —
`engine.tunnel` E015 **et** `tunnel_*` G064-72 ; `engine.models` E008 **et**
`models_status` G010. La doctrine « une seule source » veut en garder un.)

### 4.3 DOCTEUR (doctor / D) — 23 outils (22 existants + `doctor.run`)

La santé et l'inventaire. Voici **tous** les outils du docteur, avec leurs `op` :

| id | outil | fonction | op |
|---|---|---|---|
| D018 | doctor.arguments | un texte qui attend un nom n'est jamais imprimé | arguments |
| D001 | doctor.data | les bases et la mémoire, un écrivain chacune | bases·memory |
| D013 | doctor.duplicates | les copies : le même bloc deux fois (jscpd) | clones·shapes |
| D002 | doctor.forms | les formes d'un retour : leurs bornes | forms |
| D011 | doctor.index | le disque contre l'index | tree·apk·roles |
| D003 | doctor.keys | la_config contre les corps : un seul propriétaire par clé | keys·used |
| D004 | doctor.knowledge | les skills, la skill/projet armé, le canon | skills·active·canon |
| D005 | doctor.language | aucun mot français dans la machine, rien de mort | vocab |
| D006 | doctor.machine | ce qui écoute, ce qui est appelé, les bancs | residents·instruments·benches·tunnel·declared |
| D007 | doctor.manifest | le document contre le disque, dans les deux sens | manifest |
| D012 | doctor.models | les modèles et le llama.cpp qui les porte | router·files·binary·residents |
| D019 | doctor.pages | les scripts des deux pages compilent | pages |
| D022 | doctor.perms | les clés lues par le seul propriétaire | keys |
| D023 | doctor.skills | les skills et ce qu'elles ouvrent | orphans·dangling·docs·empty·workspace·paths |
| D020 | doctor.state | aucun orphelin dans le dossier d'état | orphans·writers |
| D008 | doctor.structure | la racine, la syntaxe des briques | root·scripts·programs·channels |
| D015 | doctor.tags | chaque corps porte quatre tags, un par famille | all |
| D009 | doctor.texts | la tête du modèle, les refus de la porte | prompt |
| D010 | doctor.tools | le registre contre les corps par id | table·paths |
| D021 | doctor.turn | le verrou de tour dit la vérité | lock |
| D016 | doctor.vision | la famille vision : chaque outil enregistré | all |
| D017 | doctor.voice | la chaîne de voix entière | chain |
| D024 | doctor.run | l'entrée de la famille : lance tous les contrôles docteur et compte les fautes (ex-`engine.doctor` E005) | short·light·json·all·badge |

**Total docteur = 23 outils.**

---

## 5. Le board ne recalcule plus — chaque fonction de board.py part dans son outil

`engine.board` (E020) perd tout son Python. Voici **chaque fonction de `board.py`**
(102 entrées) et sa destination. **La 1ʳᵉ colonne = le fichier d'origine** (où la fonction
vit aujourd'hui) ; **la dernière colonne = la zone de l'outil cible — une seule
règle, pas de catégorie « base » :**
- **`engine.*`** (Engine) — c'est du moteur → l'outil doit être `engine.*` ;
- **`doctor.*`** (Doctor) — c'est un contrôle de santé → l'outil doit être `doctor.*` ;
- **`G…`** (Agent) — sinon, c'est un outil de l'agent ;
- **—** — reste dans board : **le TUI seul** (le rendu part en SH dans `engine.board`).

On ne transfère **jamais** une fonction moteur dans un outil qui n'est pas du moteur.

| fichier | fonction board.py (l.) | rôle | état | outil cible (zone) |
|---|---|---|---|---|
| `board.py` | `state_dir` (35) | chemins d'état | part | `engine.config` (Engine — chemins) |
| `board.py` | `num` (40) | lit un nombre de la config | part | `engine.config` (Engine) |
| `board.py` | `_cfg` (53) | la config | part | `engine.config` (Engine) |
| `board.py` | `bridge` (62) · `bridge_ping` (81) · `bridge_state` (86) | appels au pont HTTP | sh | `engine.board` (sh — via `curl`) |
| `board.py` | `read_head` (90) | snapshot de tête | part | `head_state` (à vérifier) |
| `board.py` | `_units` (94) · `alive` (284) | units / vivant résidents | part | `engine.residents` |
| `board.py` | `_git_state` (119, +`one`) · `read_git` (638) | état git | part | `engine.update` (`op=check`) |
| `board.py` | `_engine` (129) · `read_engine` (625) | endpoint / provider | part | `engine.board` / `engine.switch` |
| `board.py` | `_db_counts` (145) · `_db_query` (151) · `class model` (216) | comptes / sql / tokens sur sessions.db | part | `engine.stat` (`op=exchanges·tools·cost`) |
| `board.py` | `_table` (161, = `laconf.table()`) | lit les lignes du registre (`registry-*.yaml`) | part | `engine.map` (Engine) |
| `board.py` | `read_table` (570) | intégrité : registre contre les corps → manquants, doublons | part | `doctor.tools` D010 (`op=table`) |
| `board.py` | `read_registry` (495) | lit la table `id`↔`outil` depuis `la_config` | part | `engine.map` (Engine) |
| `board.py` | `class laconf` (189) · `dotted` (206) | accès config | part | `engine.config` (Engine) |
| `board.py` | `_port` (239) · `run` (268) | parse port / lance cmd | sh | `engine.board` (sh — util) |
| `board.py` | `probe` (277) · `_rss_port` (379) · `size_of` (526) · `read_instruments` (478) · `read_machine_name` (690) | ports / mémoire / instruments / machine | part | `doctor.machine` |
| `board.py` | `weight` (292) · `line` (302, +`build`) · `ago` (717) · `short` (960) · `tint` (1027) · `_footer` (1048) · `human_count` (1169) · `shorten` (1183) | mise en forme | sh | `engine.board` (sh — mise en forme `awk`/`printf`) |
| `board.py` | `_router_models` (330) | routeur modèles | part | `engine.models` |
| `board.py` | `read_residents` (340) | résidents | part | `engine.residents` |
| `board.py` | `_appoint_rows` (368) · `read_appoints` (394) · `read_approval` (410) · `_approval_gesture` (903) | approbations / geste | part | `engine.approve` (`op=view`) |
| `board.py` | `_models_in` (510) · `read_modeles` (543, +`place`) | fichiers modèles | part | `doctor.models` (`op=files`) |
| `board.py` | `read_canon` (598) | canon | part | `doctor.knowledge` (`op=canon`) |
| `board.py` | `read_doctor` (621) | cache docteur | part | `doctor.run` (Doctor) |
| `board.py` | `read_traffic` (645) | trafic sessions / journal | part | `engine.stat` / `engine.trace` |
| `board.py` | `read_turn` (668) · `_tool_line` (1242) · `class Tailer` (1208) | le canal vivant | part | `engine.trace` |
| `board.py` | `read_state` (1188) | lit la 1ʳᵉ ligne d'un chemin de config (`skill_active`, `project_active`) | part | `engine.config` (Engine) |
| `board.py` | `_read_history` (1499, dans Cli) | historique | part | `engine.hist` |
| `board.py` | `one_turn` (1258, +`stream`) | un tour | part | `engine.turn` |
| `board.py` | `control` (734) · `_expand` (866) · `_ratio_of` (879) · `board_object` (915, +`row`) · `sections` (976) · `one_line` (1013) · `snapshot` (1196) | composition du board | sh | `engine.board` (sh — composition, appels parallèles) |
| `board.py` | `_sigwinch` (1023) · `_keys` (1037) · `tui` (1054) · `class Cli` (1297, +24 méthodes) · `cli` (1700) · `main` (1705) | interface terminal | reste | — (TUI — **Python seul, sh impossible**) |
| `board.py` | `base` (1146) · `http` (1150) · `door_line` (1162) | serveur HTTP du board | à retirer | — (le dashboard `dash_server.py` possède déjà l'HTTP) |

**Les zones cibles existent** (`engine.*` / `doctor.*` / `G…`). La config et l'état iront
dans un petit **`engine.config`** (lire une clé — Engine), le registre dans
**`engine.map`**. Là où un outil ne rend pas la donnée exacte d'une ligne (ex.
`engine.stat op=exchanges` disait « 28 messages » au lieu des échanges distincts), on
**ajuste son `op` de quelques lignes** — jamais un lecteur parallèle.

**Règle unique de la dernière colonne, sans « base » :** du moteur → **`engine.*`** (Engine) ;
un contrôle → **`doctor.*`** (Doctor) ; sinon → **`G…`** (Agent) ; **—** → reste dans
board. Aucune donnée du moteur ne finit dans un outil d'agent. Ainsi `_cfg`, `laconf`,
`dotted`, `num`, `read_state` → **`engine.config`** ; `_table`, `read_registry` →
**`engine.map`** ; `read_table` (registre contre corps) → **`doctor.tools`** ; et
`_db_query` (SQL brut) → `engine.stat`, pas `search_sessions`.

`read_state` lit la 1ʳᵉ ligne d'un chemin de config (`skill_active`, `project_active`) :
c'est une lecture de **config de la machine** → **`engine.config`** (Engine), comme
`_cfg`, `class laconf`, `dotted` et `num`. Ni `skill_list`/`project_list`, ni
`config_list` — du moteur, jamais l'agent.

Les trois du registre : `_table` lit la table (`registry-*.yaml`) → **`engine.map`**
(Engine) ; `read_table` vérifie le registre **contre les corps** → **`doctor.tools`**
(Doctor) ; `read_registry` lit `id`↔`outil` → **`engine.map`** (Engine). Donnée du
moteur → Engine, contrôle → Doctor. Jamais l'agent pour du moteur.

## 6. Route par route — les trois sorties, et l'outil existant qui y répond

- `/api/skills` → `skill_list` G051 · `/api/skill/<nom>` → `skill_view` G052
- `/api/projects` → `project_list` G033 · `/api/agents` → `send_agent_chat` G063 (+ `agent_list` à vérifier)
- `/api/toolmap` → `tools_list` G007 · `/api/commands` → `config_list` G080 (à vérifier)
- `/api/config` GET → `config_list` G080 · POST → `config_set` G081
- `/voice_text` → `voice_text` G025 · `/transcribe` → `transcribe` G021
- `/api/state` → `engine.board` · `/api/live` → `engine.trace` · `/api/history` → `engine.hist`
- `/api/doctor` → `doctor.run` (Doctor) · `/api/residents` → `engine.residents` · `/api/update` → `engine.update`
- `/api/approval`·`/approve`·`/deny` → `engine.approve` · `/api/version` → version (à vérifier)
- `/api/head` → snapshot de tête (à vérifier : sans outil dédié peut-être)

**Tout existe sauf peut-être 4 petits** : `agent_list`, `list_commands`, `head_state`,
`version` — à vérifier, souvent déjà couverts (`tools_list`, `config_list`).

## 6 ter. Les deux surfaces Python — fonction par fonction

Même mécanique : rôle · état (`part`/`sh`/`reste`/`à retirer`) · cible. Ces deux fichiers
sont des **surfaces** (elles appellent la porte), pas le moteur : ce qui **lit une donnée**
part dans un outil ; ce qui est **HTTP/plomberie** reste.

**`bridge.py` — le pont (surface « app »), ~60 fonctions**

| fichier | fonction (l.) | rôle | état | cible (langue) |
|---|---|---|---|---|
| `bridge.py` | `env`·`die`·`now`·`state_file`·`kind_of`·`cached`·`first_name` (36–56,168,483) | utilitaires | reste | — (Python — glue) |
| `bridge.py` | `door`·`ask`·`delegate` (60/67/87) | appellent la porte `run_call` | reste | — (Python — l'unique entrée est la porte) |
| `bridge.py` | `conf`·`conf_section`·`root_file`·`active_name`·`_fields` (97–212) | lisent la config en direct (yaml) | part | `engine.config` (Engine) |
| `bridge.py` | `board_json` (265) | assemble l'état du board | part | `engine.board` (`op=json`) |
| `bridge.py` | `_trace_events` (447) | lit les événements d'appels | part | `engine.trace` |
| `bridge.py` | `head_snapshot` (530) | assemble la tête | part | `head_state` (Engine — à vérifier) |
| `bridge.py` | `_machine_return` (323) | mémoire / ports | part | `doctor.machine` |
| `bridge.py` | `approval_window`·`approval_view`·`feed_of` (189–238) | état d'approbation | part | `engine.approve` (`op=view`) |
| `bridge.py` | `_watch_armed`·`_watch_once`·`watch_loop`·`warm` (351–470) | veille / chauffe | part | `engine.watch` (Engine — à vérifier) |
| `bridge.py` | `_thinking_keep`·`_keep_turn`·`summary_text`·`short_agent_line` (288–520) | forme du tour / résumé | part | `engine.turn` (mise en forme) |
| `bridge.py` | `config_page` (579) | la page de config | part | `engine.commands` + `config_list` |
| `bridge.py` | `voice` (601) | la parole | part | `engine.tts` |
| `bridge.py` | `run_turn` (616) · `_turn_file` (443) | un tour | part | `engine.turn` |
| `bridge.py` | `agents_list` (146) | liste des agents | part | `send_agent_chat` G063 / `agent_list` (à vérifier) |
| `bridge.py` | `class Handler` + 20 méthodes (639–1090) | serveur HTTP du pont | reste | — (Python — HTTP) |
| `bridge.py` | `main` (1091) | démarrage | reste | — (Python) |

**`dash_server.py` — le dashboard (surface « dashboard »), ~14 fonctions**

| fichier | fonction (l.) | rôle | état | cible (langue) |
|---|---|---|---|---|
| `dash_server.py` | `commands`·`commands_html`·`commands_legend` (31/57/62) | la liste des commandes | part | `engine.commands` E004 (Engine) |
| `dash_server.py` | `run_command` (67) | lance une commande par la porte | reste | — (appelle `run_call`, Python) |
| `dash_server.py` | `class Handler` + `relay` (91–190) | serveur HTTP + relais `/api/*`, `/doctor` | reste | — (Python — HTTP relais) |
| `dash_server.py` | `watch_idle`·`serve` (196/203) | boucle serveur | reste | — (Python) |

## 6 quater. Les fonctions du MOTEUR lui-même (.sh) — « tout dans le moteur »

C'est le cœur de ta demande : **chaque brique du moteur**, fonction par fonction. Règle :
**moteur-core = `reste` (jamais un outil)** ; ce qui **externalise une donnée** = outil.

| fichier | fonction (l.) | rôle | état | cible (langue) |
|---|---|---|---|---|
| `la.sh` | (24 l., 0 fonction) | aiguillage / point d'entrée | moteur | — (reste : le moteur) |
| `boot.sh` | (71 l., 0 fonction) | le liant : trouve maître, charge cfg + chaque brique | moteur | — (reste : le moteur) |
| `run.sh` | `_door_field`·`_door_decl`·`_door_usage`·`_door_fill`·`_door_arity_fail`·`_door_cmd`·`_door_register`·`run_call`·`say_err`·`die` (5–289) | **la porte** (`run_call`) | moteur | — (reste : la porte) |
| `shell.sh` | `shell_addr`·`shell_bin`·`shell_cmd`·`shell_exec`·`shell_run`·`krita_url` (5–129) | **l'exécutant** (`dash -c`, timeout, shape JSON) | moteur | — (reste : l'exécutant) |
| `cfg.sh` | `conf_str`·`conf_num`·`conf_list`·`conf_has` (65–91) | lecture d'une valeur de config | part | `engine.config` E028 (Engine) |
| `cfg.sh` | `cfg_dir`·`cfg_file`·`cfg_path`·`cfg_abs`·`cfg_here`·`cfg_table`·`cfg_root` (162–226) | chemins / localisation | part | `engine.config` (Engine) |
| `cfg.sh` | `_flat_raw`·`_flat`·`_cfg_exts`·`_cfg_tree`·`_cfg_map_build`·`_cfg_locate`·`_cfg_world`·`_cfg_tree_list`·`_cfg_family`·`_cfg_place`·`cfg`·`channel_label`·`channel_set`·`project_dir`·`skill_rule` (5–279) | machinerie interne du config-engine | moteur | — (reste : interne) |
| `tab.sh` | `table_block`·`table_entry`·`table_field`·`table_field_list`·`table_keys`·`table_ids`·`table_index`·`block_by_id`·`body_of`·`count` (25–122) | lecture du registre / de la table | part | `engine.map` E024 (Engine) |
| `tab.sh` | `cmd_ids`·`cmd_get`·`cmd_usage`·`cmd_slash`·`cmd_has`·`cmd_new_turn`·`cmd_run` (134–186) | les **commandes** | part | `engine.commands` E004 (DOOR) |
| `tab.sh` | `_block` (7) | interne d'accès bloc | moteur | — (reste) |
| `head_second.sh` | `_sec_channel`·`_sec_human`·`_sec_project`·`_sec_skill`·`_sec_summary`·`_sec_plan`·`_sec_project_plan`·`_sec_note`·`_sec_agents`·`_sec_chat`·`_sec_toolset` (6–133) | construit la « seconde tête » (contexte) | part | `head_state` (Engine — à créer/vérifier) |

**Bilan moteur** : `la.sh`/`boot.sh`/`run.sh`/`shell.sh` + l'interne de `cfg.sh`/`tab.sh`
= **le moteur, jamais des outils**. Ce qui rend une **donnée** (`cfg` → `engine.config`,
table → `engine.map`, commandes → `engine.commands`, tête → `head_state`) = **outil**.
Aucune fonction de surface n'entre ici.

## 6 quinquies. La surface natale (Android)

| fichier | rôle | état | cible (langue) |
|---|---|---|---|
| `Bridge.kt` | appels HTTP fins vers le pont | reste | — (Kotlin — surface) |
| `ChatActivity.kt` (16 appels `Bridge.*`) | la vue / le chat | reste | — (Kotlin — surface) |

La surface Android **ne contient aucune logique** : elle appelle le pont, qui appelle la
porte. Rien à y externaliser.

## 6 bis. SH ou Python ? — la mesure (ce que j'avais dit de faux)

J'avais dit « le rendu reste du code, pas du shell ». **Faux, et voici la preuve chiffrée :**
- `sh -c true` = **2 ms**/process ; `python3 -c pass` = **26 ms**/process → les deux langages démarrent en ms. **La lenteur n'est pas le langage.**
- 1 `run_call` complet = **~1,4 s** : c'est `boot.sh` qui **re-parse les 801 lignes de la config** à chaque appel, pas le shell.
- **Séquentiel** = N × 1,4 s = le « 34 s » de `engine.doctor` (~24 contrôles). **Parallèle** = ~1 démarrage : 4 séq = 6 775 ms → 4 par = 778 ms (**×8,7**).
- Donc **tout le rendu/agrégation de board est faisable en sh** (compose par `run_call`, formate par `awk`/`printf`, JSON par `printf`/`jq`). Seule exception réelle : le **TUI interactif**. Le coût de démarrage se règle par la **résidence** (moteur chaud en RAM) ou l'appel **in-process** (sourcer une fois).

## 7. Ce qui reste dans board.py — **le TUI, et lui seul**

Correction (après mesure) : ce n'est PAS « le rendu reste en Python ». **Tout le rendu et
l'agrégation deviennent SH** → l'outil `engine.board` (composition : `control`,
`board_object`, `sections`, `one_line`, `snapshot`, `_expand`, `_ratio_of` ; mise en forme :
`line`, `weight`, `ago`, `short`, `tint`, `_footer`, `human_count`, `shorten` ; utils :
`_port`, `run`, `bridge*`).
Seule l'**interface terminal interactive** ne peut pas être du sh : `tui`, `class Cli`
(402 l., clavier/resize/curseur, mode brut `termios`/`select`/`SIGWINCH`), `_keys`,
`_sigwinch`, `cli`, `main`. Le sh POSIX n'a aucune de ces primitives → **TUI = Python**.
Après migration, `board.py` ≈ **le TUI**.

## 8. Comptes et ordre (on ne l'exécute PAS maintenant)

- **MOTEUR (E) = 26** (25 + `engine.config` E028) · **AGENT/CŒUR (G) = 71** · **DOCTEUR (D) = 23**.
- Ce que j'avais compté « 50 » était faux : il n'y a pas 34+9+7. Ce sont trois zones
  réelles, existantes, et les sorties lisent les trois.
- **À créer au plus : 5 petits** (`engine.config` E028, `agent_list`, `list_commands`, `head_state`, `version`),
  et seulement s'ils ne sont pas déjà couverts. Le reste = **router** les trois sorties
  par la porte sur ces outils (le pont lit en direct aujourd'hui) + **décomposer board**
  pour qu'il compose.
- **Ordre validé (4 phases, un commit par tranche, moteur jamais touché = apothéose) :**
  1. **Finir les outils** — `engine.config` (E028 ✓ créé) + corriger les `op` qui n'émettent pas la donnée exacte du board (`engine.stat op=exchanges`, `engine.approve op=view`, `engine.trace`, `doctor.machine` MB). Chacun testé par la porte.
  2. **Rebrancher les lecteurs de board** sur ces outils (parité prouvée, ligne par ligne).
  3. **Sortir le rendu** (`control/sections/one_line/footer/board_object/mise en forme`) → données LAConfig + outil `engine.board` en sh.
  4. **`board.py` = TUI seule.**
