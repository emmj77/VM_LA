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

Le moteur a aujourd'hui 26 outils (E001..E027, **E018 absent**). **Aucun à découper** :
chaque famille reste un outil, ses `op` choisissent la cible/le verbe. Seul `board`
devient mince (il compose, §5).

| id | outil | fonction | op |
|---|---|---|---|
| E001 | engine.approve | la porte humaine | request·allow·grant·deny·status |
| E002 | engine.asr | l'oreille | start·stop·status |
| E003 | engine.backup | le filet hors du disque | now·verify·restore |
| E004 | engine.commands | la porte/dispatch des surfaces (zéro logique) | board·once·app·cli·say·turn·doctor·tool·new·update·help·line |
| E005 | engine.doctor | le médecin de l'engine (mince) | short·light·json·all·badge |
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

**Total moteur = 26 outils.**

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

### 4.3 DOCTEUR (doctor / D) — 22 outils (TOUS existants)

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

**Total docteur = 22 outils.**

---

## 5. Le board ne recalcule plus — chaque fonction de board.py part dans son outil

`engine.board` (E020) perd tout son Python. Voici **chaque fonction de `board.py`**
(102 entrées) et sa destination. **La 4ᵉ colonne = l'outil où la fonction part** ;
« — » = reste dans board (rendu, TUI, HTTP, utilitaire). On sait exactement ce qu'on
met où.

| fonction board.py (l.) | rôle | état | outil cible (4ᵉ) |
|---|---|---|---|
| `state_dir` (35) | chemins d'état | reste | — (util) |
| `num` (40) | un nombre de section | reste | — (util) |
| `_cfg` (53) | la config | part | `config_list` G080 |
| `bridge` (62) · `bridge_ping` (81) · `bridge_state` (86) | appels au pont HTTP | reste | — (porte HTTP) |
| `read_head` (90) | snapshot de tête | part | `head_state` (à vérifier) |
| `_units` (94) · `alive` (284) | units / vivant résidents | part | `engine.residents` |
| `_git_state` (119, +`one`) · `read_git` (638) | état git | part | `engine.update` (`op=check`) |
| `_engine` (129) · `read_engine` (625) | endpoint / provider | part | `engine.board` / `engine.switch` |
| `_db_counts` (145) | comptes sessions | part | `engine.stat` |
| `_db_query` (151) · `class model` (216) | sql / tokens | part | `recall` G056 / `search_sessions` G029 |
| `_table` (161) · `read_table` (570) · `read_registry` (495) | registre / table | part | `table_manage` G018 |
| `class laconf` (189) · `dotted` (206) | accès config | part | `config_list` G080 |
| `_port` (239) · `run` (268) | parse port / lance cmd | reste | — (util) |
| `probe` (277) · `_rss_port` (379) · `size_of` (526) · `read_instruments` (478) · `read_machine_name` (690) | ports / mémoire / instruments / machine | part | `doctor.machine` |
| `weight` (292) · `line` (302, +`build`) · `ago` (717) · `short` (960) · `tint` (1027) · `_footer` (1048) · `human_count` (1169) · `shorten` (1183) | mise en forme | reste | — (rendu) |
| `_router_models` (330) | routeur modèles | part | `engine.models` |
| `read_residents` (340) | résidents | part | `engine.residents` |
| `_appoint_rows` (368) · `read_appoints` (394) · `read_approval` (410) · `_approval_gesture` (903) | approbations / geste | part | `engine.approve` (`op=view`) |
| `_models_in` (510) · `read_modeles` (543, +`place`) | fichiers modèles | part | `doctor.models` (`op=files`) |
| `read_canon` (598) | canon | part | `doctor.knowledge` (`op=canon`) |
| `read_doctor` (621) | cache docteur | part | `engine.doctor` |
| `read_traffic` (645) | trafic sessions / journal | part | `engine.stat` / `engine.trace` |
| `read_turn` (668) · `_tool_line` (1242) · `class Tailer` (1208) | le canal vivant | part | `engine.trace` |
| `read_state` (1188) | skill / projet armé | part | `skill_list` G051 / `project_list` G033 |
| `_read_history` (1499, dans Cli) | historique | part | `engine.hist` / `recall` G056 |
| `one_turn` (1258, +`stream`) | un tour | part | `engine.turn` |
| `control` (734) · `_expand` (866) · `_ratio_of` (879) · `board_object` (915, +`row`) · `sections` (976) · `one_line` (1013) · `snapshot` (1196) | composition du board | reste | — (rendu board) |
| `_sigwinch` (1023) · `_keys` (1037) · `tui` (1054) · `class Cli` (1297, +24 méthodes) · `cli` (1700) · `main` (1705) | interface terminal | reste | — (TUI) |
| `base` (1146) · `http` (1150) · `door_line` (1162) | appels HTTP | reste | — (HTTP) |

**Toutes les fonctions qui « partent » existent déjà comme outils** — aucune à
réinventer. Là où un outil ne rend pas la donnée exacte d'une ligne (ex.
`engine.stat op=exchanges` disait « 28 messages » au lieu des échanges distincts), on
**ajuste son `op` de quelques lignes** — jamais un lecteur parallèle.

## 6. Route par route — les trois sorties, et l'outil existant qui y répond

- `/api/skills` → `skill_list` G051 · `/api/skill/<nom>` → `skill_view` G052
- `/api/projects` → `project_list` G033 · `/api/agents` → `send_agent_chat` G063 (+ `agent_list` à vérifier)
- `/api/toolmap` → `tools_list` G007 · `/api/commands` → `config_list` G080 (à vérifier)
- `/api/config` GET → `config_list` G080 · POST → `config_set` G081
- `/voice_text` → `voice_text` G025 · `/transcribe` → `transcribe` G021
- `/api/state` → `engine.board` · `/api/live` → `engine.trace` · `/api/history` → `engine.hist`
- `/api/doctor` → `engine.doctor` · `/api/residents` → `engine.residents` · `/api/update` → `engine.update`
- `/api/approval`·`/approve`·`/deny` → `engine.approve` · `/api/version` → version (à vérifier)
- `/api/head` → snapshot de tête (à vérifier : sans outil dédié peut-être)

**Tout existe sauf peut-être 4 petits** : `agent_list`, `list_commands`, `head_state`,
`version` — à vérifier, souvent déjà couverts (`tools_list`, `config_list`).

## 7. Ce qui reste dans board.py (pas un outil)

Composition et rendu seulement : `control()`, `board_object()`, `sections()`,
`one_line()` (assemblent), `line()`, `tint()`, `_footer()`, `short()`, `weight()`,
`ago()` (formatent), `tui()`, `Cli`, `Tailer`, `snapshot()`, `main` (le terminal),
`run()`, `probe()`, `_port()`, `num()`, `state_dir()` (petits utilitaires).

## 8. Comptes et ordre (on ne l'exécute PAS maintenant)

- **MOTEUR (E) = 26** · **AGENT/CŒUR (G) = 71** · **DOCTEUR (D) = 22** — **tous existent déjà**.
- Ce que j'avais compté « 50 » était faux : il n'y a pas 34+9+7. Ce sont trois zones
  réelles, existantes, et les sorties lisent les trois.
- **À créer au plus : 4 petits** (`agent_list`, `list_commands`, `head_state`, `version`),
  et seulement s'ils ne sont pas déjà couverts. Le reste = **router** les trois sorties
  par la porte sur ces outils (le pont lit en direct aujourd'hui) + **décomposer board**
  pour qu'il compose.
- Ordre, sur ton feu vert : décomposer `board` (chaque `read_*` → son outil existant,
  un commit par lecteur, sortie prouvée), puis router le pont. On ne branche rien tant
  que tu n'as pas validé.
