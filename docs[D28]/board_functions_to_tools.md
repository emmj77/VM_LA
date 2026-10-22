# LA — le plan final du moteur (fichier unique)

Un seul fichier. Il décrit en français : la mécanique réelle, où se branchent les
trois sorties, où vivent les fonctions, et le **catalogue FINAL** — chaque outil du
moteur, déjà découpé au niveau **famille** (choix A : un outil = une famille, ses
`op` choisissent la cible/le verbe de cette même fonction). Plus rien n'est « à
découper ».

Rien n'est exécuté ici.

---

## 1. La mécanique réelle

- **`la.sh` (E08) — l'ENTRÉE.** La commande `la`. Trouve la racine, source
  `boot.sh`, puis **aiguille** seulement : `la engine …` → `run_call` ; `la` seul
  sur un terminal → `cmd_run cli` ; `la` en pipe → `run_call engine.turn` ; autre
  → `cmd_run`. **Elle n'exécute aucun corps.**
- **`boot.sh` (E03) — le LIANT.** La seule ligne sourcée : trouve la racine, charge
  `cfg.sh` + les briques (`msg fs tab skl canon shape args cap run shell approval
  step`), exporte les chemins (`LA_ROOT`, `LA_CONFIG`, `LA_SESSIONS_DB`, ports…).
- **`run.sh` (E11) — LA PORTE.** `run_call <nom> [clé=valeur …]` : lit le registre
  (l'`id`), trouve le corps `tool_<nom>.yaml`, vérifie famille/id, le gate de la
  skill, l'arité/les types, les chemins, l'approbation, construit la commande
  depuis le bloc `COMMAND` (ou `machine --op`), remplit les `{{arg}}`, puis appelle
  `shell_exec`.
- **`shell.sh` (E13) — LE SEUL ENDROIT QUI LANCE UN CORPS.** `shell_exec` lance le
  texte en `dash -c`, applique le timeout, la limite de retour, et **shape** la
  réponse (`shape_ok` / `shape refused` / `shape timeout` → le JSON).

Chaîne : **`la.sh` aiguille → `run.sh` porte (`run_call`) → `shell.sh` lance et
shape (`shell_exec`).**

## 2. La porte unique et les trois sorties

Une porte : `run_call` (run.sh) → `shell_exec` (shell.sh). Les trois sorties s'y
branchent :
- **CLI** — `la` seul sur un terminal → `cmd_run cli` → board `--cli`.
- **Dashboard** — `dash_server.py` → `sh la.sh …` → aiguillage → `run_call`.
- **App Android** — HTTP → `bridge.py` → `la engine engine.commands …` → `run_call`.

Une porte, trois sorties, les mêmes petits outils ; aucune sortie ne lit le disque.

## 3. Où vivent les fonctions

Un corps par fonction : `tools[D14]/<famille>/tool_<nom>.yaml` — `id`, `tool`,
`DESCRIPTION`, `COMMAND` (shell), `ARGS`. Le moteur porte le corps à la porte
(`run_call`) qui le lance (`shell_exec`). Ajouter une fonction = un petit corps +
son `id` au registre.

---

## 4. Catalogue FINAL — chaque outil du moteur (niveau famille)

Le moteur a aujourd'hui 26 outils (E001..E027, **E018 absent**). Voici leur forme
finale. **Aucun n'est « à découper »** : chaque famille reste un outil, ses `op`
choisissent la cible/le verbe de la même fonction. Seul `board` change de nature
(il devient mince, cf. §5). Puis 6 petits outils de lecture sont ajoutés.

| # | outil (final) | fonction | op |
|---|---|---|---|
| 1 | engine.approve | la porte humaine : demander, accorder, refuser, statut | request·allow·grant·deny·status |
| 2 | engine.asr | l'oreille : démarrer, arrêter, statut | start·stop·status |
| 3 | engine.backup | le filet hors du disque : maintenant, vérifier, restaurer | now·verify·restore |
| 4 | engine.hist | la base des sessions : init, ajouter, fenêtre, tours, appliquer, résultat | init·add·window·turns·apply·result |
| 5 | engine.install | ce qui est posé : units, commande, desktop, applet, certs | units·command·desktop·applet·certs |
| 6 | engine.models | le routeur des modèles : charger, décharger, statut | load·unload·status |
| 7 | engine.purge | rendre le cache de pages froid, par service | all·list·la-asr·la-tts·la-models·la-bridge |
| 8 | engine.reload | le registre reconstruit depuis les corps | build |
| 9 | engine.residents | les résidents : état, up, down, toggle, écouter | status·up·down·toggle·listen·listen-on·listen-off |
| 10 | engine.retention | les bornes appliquées, par catégorie | audio·returns·logs·bases |
| 11 | engine.service | un service au premier plan, par nom | models·asr·tts·kws·bridge·dashboard |
| 12 | engine.signal | signaux de tâche entre processus | raise·take·list |
| 13 | engine.spec | le canon : ajouter une loi, lister | add·list |
| 14 | engine.stat | sessions.db comptée : échanges, outils, coût | exchanges·tools·cost |
| 15 | engine.switch | le provider actif : lister, prendre | list·take |
| 16 | engine.trace | le canal vivant : écrire une ligne, json, queue | line·json·tail |
| 17 | engine.tts | la voix : démarrer, arrêter, statut | start·stop·status |
| 18 | engine.tunnel | wireguard desktop↔téléphone : up, down, statut, qr | up·down·status·qr |
| 19 | engine.turn | un tour de la boucle : le texte entre, la réponse sort | — |
| 20 | engine.uninstall | ce que l'install a posé, retiré | units·command·desktop·applet·certs |
| 21 | engine.update | le projet par git : vérifier, appliquer, revenir | check·apply·rollback |
| 22 | engine.wake | un réveil ouvre une requête | — |
| 23 | engine.map | la carte des noms, reconstruite depuis le disque | rebuild |
| 24 | engine.doctor | le médecin de l'engine (mince, délègue à la famille `doctor.*`) | short·light·json·all·badge |
| 25 | engine.commands | la porte/dispatch des surfaces (aucune logique) | board·once·app·cli·say·turn·doctor·tool·new·update·help·line |
| 26 | engine.board | **devient mince** : compose les lecteurs (§5) et rend | line·once·json·menu (rendu seul) |
| 27 | engine.git_state | l'état git : fichiers modifiés + rev HEAD (NOUVEAU) | — |
| 28 | engine.api_endpoint | provider·modèle·post + code HTTP du endpoint (NOUVEAU) | — |
| 29 | engine.active_state | la skill armée / le projet armé (NOUVEAU) | — |
| 30 | engine.journal_state | la queue du journal du pont (NOUVEAU) | — |
| 31 | engine.usage_tokens | les jetons de la dernière session (NOUVEAU) | — |
| 32 | engine.session_query | lecture libre de sessions.db en sqlite (NOUVEAU) | — |

**Total moteur = 32 outils** : 26 outils existants (24 familles + `commands` la porte + `board` mince) + 6 nouveaux lecteurs.

## 4 bis. Audit des trois sorties — outils AJOUTÉS pour le dashboard et l'app

J'ai lu `dash_server.py`, `bridge.py` (le pont que le dashboard relaie et que l'app
appelle) et `Bridge.kt` / `ChatActivity.kt`. Le pont lit **lui-même** plusieurs
données que rien n'outille (son commentaire : « no tool owns them yet »). Routés
par la porte, il faut donc AJOUTER :

**Moteur (engine) — nouveaux :**
- `engine.head_state` — le snapshot de tête (`/api/head`, `head_snapshot()`)
- `engine.version` — la chaîne de version (`/api/version`)

**Moteur (engine) — étendre une famille existante (pas de nouvel outil) :**
- `engine.approve` `op=view` — l'objet d'approbation pending·tool·gesture·phrase·age (`/api/approval`)
- `engine.tts` `op=say` — lire un texte (`/voice_text`)
- `engine.asr` `op=transcribe` — transcrire un fichier (`/transcribe`)

**Catalogue (cœur) — les listes que l'app et la page affichent, lues en direct par le pont aujourd'hui :**
- `list_skills` — skills[D23] + la skill armée (`/api/skills`)
- `show_skill` — le détail d'une skill (`/api/skill/<nom>`)
- `list_projects` — projects[D21] + le projet armé (`/api/projects`)
- `list_agents` — les agents (`/api/agents`)
- `list_toolmap` — les familles du registre + compte (`/api/toolmap`)
- `list_commands` — les commandes du fichier maître (`/api/commands`)
- `config_view` — la vue config (`/api/config` GET)
- `config_set` — écrire un réglage (`/api/config` POST) — **existe déjà** (G081, cœur)

Route par route, tout le reste est déjà couvert : `state`→board, `live`→`engine.trace`,
`history`→`engine.hist`, `cmd`/`command`→`engine.commands`, `doctor`→`engine.doctor`,
`residents`→`engine.residents`, `update`→`engine.update`, `approval/approve/deny`→`engine.approve`.

**Nouveaux comptes : moteur 34** (32 + `head_state` + `version`), **catalogue/cœur 9**
(`list_skills`, `show_skill`, `list_projects`, `list_agents`, `list_toolmap`,
`list_commands`, `config_view`, `config_set`, `table_manage`), **docteur ~7**. Total
visible par les trois sorties ≈ **50 outils** — et « de plus en plus d'outils YAML, ce
n'est pas un problème ». Là encore, **rien n'est créé ni branché**, c'est le plan.

## 5. Le board ne recalcule plus — il compose

`engine.board` (E020) perd tout son Python de lecture. Chaque `read_*` de
`board.py` appelle désormais l'outil final correspondant, par la porte :

| fonction board.py | outil final | nature |
|---|---|---|
| `read_residents` (+ `alive`, `_units`, appoints) | `engine.residents` | famille existante |
| `_router_models` | `engine.models` | famille existante |
| `read_approval` | `engine.approve` | famille existante |
| `read_turn` | `engine.trace` (`op=tail`) | famille existante |
| `read_traffic` (sessions) | `engine.stat` (`op=exchanges`) | famille existante |
| `read_git` | `engine.git_state` | **nouveau** |
| `read_engine` | `engine.api_endpoint` | **nouveau** |
| `read_state` | `engine.active_state` | **nouveau** |
| `read_traffic` (journal) | `engine.journal_state` | **nouveau** |
| `model.tokens` | `engine.usage_tokens` | **nouveau** |
| `_db_query` / `model.query` | `engine.session_query` | **nouveau** |
| `read_modeles` | `doctor.models` (`op=files`) | docteur |
| `read_instruments` / `read_machine_name` | `doctor.machine` | docteur |
| `read_canon` | `doctor.knowledge` (`op=canon`) | docteur |
| `read_table` / `read_registry` | `table_manage` | cœur |
| `laconf.get/text/path` | `cfg str <clé>` | cfg |
| `bridge` / `bridge_state` | — (la porte HTTP, pas un outil) | — |

## 6. Les outils non-moteur que le board lit à travers (pas le moteur)

Santé et inventaire = **docteur/cœur**, jamais le moteur :
- `doctor.machine` — la machine : units+ports, bancs, instruments, tunnel
- `doctor.models` — les fichiers de modèles (`op=files`)
- `doctor.knowledge` — le canon + les skills armées (`op=canon`)
- `doctor.tools` / `doctor.tags` / `doctor.index` / `doctor.duplicates` — santé de l'inventaire
- `table_manage` — id/tool du registre (cœur, G018)

## 7. Ce qui reste dans board.py (pas un outil)

Composition et rendu seulement :
- `control()`, `board_object()`, `sections()`, `one_line()` — assemblent les lignes
- `line()`, `tint()`, `_footer()`, `short()` — formatent
- `weight()`, `ago()`, `human_count()`, `shorten()` — mise en forme
- `tui()`, `Cli`, `Tailer`, `snapshot()`, `main` — l'interface terminal
- `run()`, `probe()`, `_port()`, `num()`, `state_dir()` — petits utilitaires

## 8. Comptes et ordre (on ne l'exécute PAS maintenant)

- **34 outils moteur** (26 existants + 6 lecteurs + `head_state` + `version`).
- **~9 outils catalogue/cœur** + **~7 docteur** que les sorties lisent à travers.
- Total visible par les trois sorties ≈ **50 outils**. Trois sorties, une porte.
- Ordre, plus tard et sur ton feu vert : découper `board` (chaque `read_*` → son
  outil, un commit par lecteur, sortie prouvée), créer les 6 nouveaux lecteurs,
  docteur vert à chaque étape. On ne branche rien tant que tu n'as pas validé.
