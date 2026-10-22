# LA — le moteur, ses fonctions, ses trois sorties (fichier unique)

Ce fichier remplace les deux documents précédents. Il décrit, en français, comment
le moteur marche vraiment, où vivent ses fonctions, où se branchent les trois
sorties, et il liste TOUTES les fonctions de l'engine.

Rien n'est exécuté ici. On définit, on ne branche encore rien.

---

## 1. La mécanique réelle (corrigée)

J'avais tort d'appeler `la.sh` « la porte ». La chaîne réelle, dans l'ordre :

- **`la.sh` (E08) — l'ENTRÉE.** C'est la commande `la`. Elle trouve la racine,
  source `boot.sh`, puis **aiguille** seulement :
  - `la engine …` → `run_call …`
  - `la` seul sur un vrai terminal → `cmd_run cli`
  - `la` seul dans un pipe → `run_call engine.turn text=…`
  - toute autre commande → `cmd_run …`
  **Elle n'exécute aucun corps.**

- **`boot.sh` (E03) — le LIANT.** La seule ligne sourcée. Elle trouve la racine,
  charge `cfg.sh` (le lecteur du fichier maître `la_config.yaml`), puis charge
  chaque brique (`msg fs tab skl canon shape args cap run shell approval step`),
  et exporte les chemins (`LA_ROOT`, `LA_CONFIG`, `LA_SESSIONS_DB`, les ports…).

- **`run.sh` (E11) — LA PORTE.** `run_call <nom> [clé=valeur …]`. Elle lit le
  registre (l'`id`), trouve le corps `tool_<nom>.yaml`, vérifie famille/id, le
  gate de la skill active, l'arité et les types, les chemins, l'approbation,
  construit la commande depuis le bloc `COMMAND` (ou `machine --op`), remplit les
  trous `{{arg}}`, puis appelle `shell_exec`.

- **`shell.sh` (E13) — LE SEUL ENDROIT QUI LANCE UN CORPS.** `shell_exec <nom>
  <commande> [args]`. Elle lance le texte du corps en `dash -c`, applique le
  timeout, la limite de retour, et **shape** la réponse (`shape_ok` /
  `shape refused` / `shape timeout` → le JSON).

Résumé : **`la.sh` aiguille → `run.sh` est la porte (`run_call`) → `shell.sh`
lance et shape (`shell_exec`).**

---

## 2. La porte unique et le branchement des trois sorties

Il y a **une** porte : `run_call` (run.sh) → `shell_exec` (shell.sh). Tout y passe.
Les trois sorties s'y branchent :

- **CLI** — `la` sans argument sur un terminal → `cmd_run cli` → board.py `--cli`.
  (Aujourd'hui le CLI lit encore en direct. La cible : il passe par la porte.)
- **Dashboard** — `dash_server.py` → `sh la.sh <commande>` → aiguillage → `run_call`.
- **App Android** — HTTP → `bridge.py` → `la engine engine.commands …` → `run_call`.

Une seule porte, trois sorties, les **mêmes petits outils**. Aucune sortie ne lit
le disque elle-même.

---

## 3. Où vivent les fonctions

Chaque fonction = **un corps de fichier** :
`tools[D14]/<famille>/tool_<nom>.yaml` — avec `id`, `tool`, `DESCRIPTION`,
`COMMAND` (du shell), `ARGS`.

Le moteur ne recopie pas la logique : il trouve le corps et le porte à la porte
(`run_call`), qui le lance (`shell_exec`). Ajouter une fonction = ajouter un petit
corps + son `id` au registre. Rien d'autre.

---

## 4. Le grand tableau — toutes les fonctions de l'engine (E001..E027)

Légende : **PETIT** = une fonction cohérente, on garde. **À DÉCOUPER** = monolithe,
à séparer en plusieurs petites fonctions. **PORTE** = aiguilleur, reste mince.

| id | outil | ce qu'il fait | lignes | ops | verdict |
|---|---|---|---|---|---|
| E001 | engine.approve | la porte humaine : demander, accorder, refuser, statut | 50 | 5 | PETIT |
| E002 | engine.asr | l'oreille : démarrer, arrêter, statut | 51 | 3 | PETIT |
| E003 | engine.backup | le filet hors du disque : maintenant, vérifier, restaurer | 84 | 3 | À DÉCOUPER → backup_now / backup_verify / backup_restore |
| E004 | engine.commands | les sorties de la : board, once, app, cli, user… | 148 | 12 | PORTE (dispatch seulement) |
| E005 | engine.doctor | lance chaque contrôle de la famille docteur | 93 | 5 | MINCE (délègue au docteur) |
| E006 | engine.hist | sessions.db : init, ajouter, fenêtre | 72 | 6 | À DÉCOUPER → hist_init / hist_add / hist_window |
| E007 | engine.install | ce qui est posé sur la machine | 117 | 5 | À DÉCOUPER → install_units / install_command / install_desktop / install_applet / install_certs |
| E008 | engine.models | le routeur des modèles : charger, décharger, statut | 51 | 3 | PETIT |
| E009 | engine.retention | les bornes appliquées : audio, retours, logs, base | 83 | 4 | À DÉCOUPER → retention_audio / retention_returns / retention_logs / retention_base |
| E010 | engine.spec | le canon : ajouter une loi, ou le lire | 50 | 2 | PETIT |
| E011 | engine.stat | sessions.db comptée : échanges, outils, coût | 43 | 3 | PETIT |
| E012 | engine.switch | le provider actif : lister, prendre | 51 | 2 | PETIT |
| E013 | engine.trace | le canal vivant : écrire une ligne, ou lire | 49 | 3 | PETIT |
| E014 | engine.tts | la voix : démarrer, arrêter, statut | 51 | 3 | PETIT |
| E015 | engine.tunnel | wireguard desktop↔téléphone : up, down, statut, qr | 87 | 4 | À DÉCOUPER → tunnel_up / tunnel_down / tunnel_status / tunnel_qr |
| E016 | engine.update | le projet par git : vérifier, appliquer, restaurer | 92 | 3 | À DÉCOUPER → update_check / update_apply |
| E017 | engine.reload | le registre reconstruit depuis les corps | 50 | 1 | PETIT |
| E019 | engine.signal | signaux de tâche entre processus | 49 | 3 | PETIT |
| E020 | engine.board | l'état de la machine : une ligne, chaque section | 184 | 4 | À DÉCOUPER (monolithe) — priorité |
| E021 | engine.residents | les résidents : état, démarrer, arrêter, écouter | 72 | 6 | À DÉCOUPER → resident_state / resident_start / resident_stop / resident_listen |
| E022 | engine.service | un des quatre services, au premier plan | 35 | 6 | PETIT |
| E023 | engine.turn | un tour de la boucle : le texte entre, la réponse sort | 30 | 1 | PETIT |
| E024 | engine.map | la carte des noms, reconstruite depuis le disque | 22 | 1 | PETIT |
| E025 | engine.uninstall | ce que l'install a posé, retiré | 48 | 5 | PETIT |
| E026 | engine.wake | un réveil ouvre une requête | 25 | 1 | PETIT |
| E027 | engine.purge | rend le cache de pages froid au noyau | 77 | 3 | PETIT |

Compte : **16 PETITS**, **1 PORTE**, **1 MINCE**, **8 À DÉCOUPER**. Le seul vrai
monolithe à découper en premier : **E020 engine.board**.

---

## 5. Gros outils → les petites fonctions qu'ils deviennent

### E020 engine.board (184 lignes, 9,9 Ko) — LA priorité
Aujourd'hui il recopie en Python ce que ces petits outils doivent porter. Après
découpage, board ne fait plus que composer et afficher :

- `resident_state` (état des units + mémoire) … `engine.residents op=status` (+ mémoire)
- `router_models` … `engine.models op=status`
- `model_files` … `doctor.models op=files`
- `instrument_state` … `doctor.machine op=instruments`
- `machine_state` (ram/swap/gpu/disque) … `doctor.machine`
- `approval_state` … `engine.approve op=status`
- `trace_tail` … `engine.trace op=tail`
- `session_count` … `engine.stat op=exchanges` (compter les échanges, pas les messages)
- `table_state` / `registry_map` … `table_manage`
- `canon_state` … **docteur** `doctor.knowledge op=canon` (pas un outil du moteur)
- `git_state` … NOUVEAU (`git -C $LA_ROOT status --short` + `rev-parse`)
- `api_endpoint` … NOUVEAU (`engines.<actif>.{provider,model,post}` + `curl -I`)
- `active_state` … NOUVEAU (`skill_active` / `project_active`)
- `usage_tokens` … NOUVEAU ou `engine.stat op=cost`

### Les autres monolithes (découpables plus tard, un op = une petite fonction)
`engine.commands` = la porte (garde zéro logique). `engine.install`,
`engine.update`, `engine.backup`, `engine.retention`, `engine.hist`,
`engine.tunnel`, `engine.residents` sont de grosses familles cohérentes : chaque op
peut devenir son petit outil quand on y arrive. Ils ne bloquent pas le board.

---

## 6. Les fonctions de board.py → leur outil (nouveau / existant)

| fonction Python (board.py) | outil | route |
|---|---|---|
| `read_residents` (+ `alive`, `_units`) | `resident_state` | EXISTANT `engine.residents op=status` |
| `_router_models` | `router_models` | EXISTANT `engine.models op=status` |
| `read_approval` | `approval_state` | EXISTANT `engine.approve op=status` |
| `read_instruments` (+ `dotted`) | `instrument_state` | EXISTANT `doctor.machine op=instruments` |
| `read_modeles` | `model_files` | EXISTANT `doctor.models op=files` |
| `read_table` / `read_registry` | `table_state` / `registry_map` | EXISTANT `table_manage` |
| `read_turn` | `trace_tail` | EXISTANT `engine.trace op=tail` |
| `read_machine_name` | `machine_state` | EXISTANT `doctor.machine` |
| `read_traffic` (sessions) | `session_count` | EXISTANT `engine.stat op=exchanges` |
| `read_canon` | `doctor.knowledge op=canon` | EXISTANT — **docteur** |
| `_db_query` / `model.query` | `session_query` | `sqlite3 "$LA_SESSIONS_DB"` (lecture) |
| `laconf.get/text/path` | `config_read` | EXISTANT `cfg str <clé>` |
| `read_git` | `git_state` | NOUVEAU petit outil |
| `read_engine` | `api_endpoint` | NOUVEAU petit outil |
| `read_state` | `active_state` | NOUVEAU petit outil |
| `read_traffic` (journal) | `journal_state` | NOUVEAU (tail du log du pont) |
| `model.tokens` | `usage_tokens` | NOUVEAU ou `engine.stat op=cost` |
| `bridge` / `bridge_state` | — (la porte HTTP) | PAS un outil |

---

## 7. Ce qui reste dans board.py (pas un outil)

Composition et rendu seulement — il appelle les petits outils :

- `control()`, `board_object()`, `sections()`, `one_line()` — assemblent les lignes
- `line()`, `tint()`, `_footer()`, `short()` — formatent
- `weight()`, `ago()`, `human_count()`, `shorten()` — mise en forme
- `tui()`, `Cli`, `Tailer`, `snapshot()`, `main` — l'interface terminal
- `run()`, `probe()`, `_port()`, `num()`, `state_dir()` — petits utilitaires

---

## 8. L'ordre (on ne l'exécute PAS maintenant)

1. **Définir** (ce fichier) — fait.
2. Plus tard, quand tu le diras : découper `E020 board` — chaque `read_*` devient un
   appel au petit outil par la porte ; le Python du lecteur est supprimé ; sortie
   prouvée identique ; un commit par lecteur.
3. Puis créer les petits outils manquants, docteur vert à chaque étape.
4. Encore plus tard : découper les autres grosses familles, même discipline.
