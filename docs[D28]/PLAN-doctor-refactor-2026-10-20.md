# PLAN — refactorisation complète du moteur

**Ouvert le** : 2026-10-20
**Horizon** : long. Ce document est LE plan de référence. Le docteur (phase 0) y est inclus.
**Règle** : aucun code n'est écrit avant que sa ligne soit cochée ici. Une phase ne commence
pas avant que la précédente ait franchi sa porte de sortie.

---

## 0. Les contraintes

| contrainte | portée |
|---|---|
| un métier par fichier | un `.sh` = une responsabilité. Le nom dit ce qu'il fait |
| aucun fichier > 200 lignes | au-delà, il porte deux métiers et se coupe |
| aucun fichier ne fait rien quand on le source | pas de code au niveau du fichier, sauf le maître |
| pas de bricolage | pas de heredoc, pas de python emballé, pas de fait recopié, pas de chemin en dur |
| une seule source par fait | une liste, un chemin, une clé : un seul endroit qui le déclare |
| anglais absolu dans le code | messages, commentaires, variables |
| rien ne casse en route | chaque extraction est un déplacement pur, prouvé avant/après |

---

## 1. L'état mesuré

### 1.1 Les scripts — 24 fichiers, 4 438 lignes

    1447  loop.sh          <-- 50 fonctions : dix metiers dans un fichier
     597  engine.sh
     430  second.sh        <-- 1 fonction, le reste est un corps de script
     418  doctor.sh
     396  lib.sh           <-- 30 fonctions, six metiers
     151  update.sh
     147  plan.sh
     125  trim_forms.sh    <-- 0 fonction
     120  session_note.sh
     117  la.sh
     113  summary.sh
     107  watcher.sh
      82  engine_switch.sh
      78  backup.sh
      76  approval.sh
      64  audio_purge.sh
      60  tunnel.sh
      40  models.sh
      28  signal_task.sh
      27  spec.sh
      26  tts.sh
      23  pick.sh
      22  asr.sh
       6  board.sh

23 scripts sourcent `lib.sh`. C'est déjà une bibliothèque, mais elle porte **six métiers**.
Les trois gros n'ont aucune frontière interne.

### 1.2 Les programmes — 11 fichiers Python, 4 487 lignes

    1538  dash.py               HTTP : dashboard, bridge, TLS
    1355  board.py              TUI Textual : le tableau, le CLI
     311  audit_vocab.py        vocabulaire
     214  sse.py                evenements server-sent
     190  laconf.py             lecteur de la_config
     185  model.py              appels au modele
     173  watch.py              onnxruntime + numpy
     168  micro_vision.py       cv2 + onnxruntime
     145  tts_daemon.py         HTTP + sherpa-onnx
     121  build_tool_vectors.py embeddings
      87  vector_pick.py        cosinus sur sqlite

### 1.3 Ce que le moteur appelle

    board.sh:6             exec board.py
    la.sh:33,64,99,109,115 exec board.py (cli, say, board, once)
    loop.sh:965,971        pipe vers sse.py
    pick.sh:12             vector_pick.py
    tts.sh:26              sherpa-onnx via uv
    doctor.sh:19,52,118,410 python pour le YAML, ast, imports, audit_vocab

### 1.4 Les points d'entrée installés

    la-asr.service      -> engine/asr.sh run
    la-models.service   -> engine/models.sh run
    la-tts.service      -> engine/tts.sh run
    la-dash.service     -> /usr/bin/python3 programs/dash.py
    la-audio-purge      -> engine/audio_purge.sh once

---

## 2. Diagnostic — pourquoi c'est ingérable

**D1 `lib.sh` porte six métiers.** Config, messages, chemins, table, skills[D33], services :
396 lignes, 30 fonctions, un fichier. Toute modification touche les 23 scripts à la fois.

**D2 `loop.sh` porte dix métiers.** Base (`db_init`, `db_add`, `db_insert`), fenêtre
(`hist_window`), agents (`declare_agents`), journal (`trace`, `say_once`), prompt
(`active_block`, `head_schema`, `read_prompt`), arguments d'outil (`args_block_of_tool`,
`args_text`, `count_non_stdin_of_tool`), skills[D33] (`read_skill_tools`, `read_guardrails`),
approbation (`approval_gate`, `approval_ask`), plan (`step_record`, `in_plan_family`,
`open_plan`, `big_act`), sélection (`rank_share`, `scope_build`), appel (`call`), exécution
(`exec_engine`), signaux. 1 447 lignes, 50 fonctions.

**D3 `second.sh` est un corps, pas un module.** 430 lignes, une seule fonction (`section_of`,
l.394). On ne peut ni le tester, ni l'appeler partiellement.

**D4 deux lecteurs pour la même config.** `lib.sh` lit `la_config` par `sed`, `laconf.py` par
`yaml`. Deux vérités pour un fichier — la racine de `client.py` et des relectures de `board.py`.

**D5 les listes recopiées.** `la.sh:9` `RESIDENTS="la-models la-asr la-tts"` en dur alors que
`board.residents` les déclare ; `doctor.sh:339` en recopie quatre autres. Chaque copie diverge
en silence.

**D6 le python fait de la plomberie.** 987 lignes ne servent qu'à lire un YAML, appeler un
modèle, comparer des vecteurs, écrire des événements, compter des mots. Ce n'est pas du
calcul, c'est du collage — et la loi 517 l'interdit dans un proc.

**D7 l'interface et l'inférence sont du Python légitime.** 3 500 lignes servent un serveur
HTTP, une TUI, des modèles ONNX. Ce n'est pas du bricolage : c'est du runtime.

---

## 3. La règle

Un fichier = un verbe. Il expose des fonctions et **ne fait rien en le sourçant**.
Le seul code exécuté au chargement est celui du fichier maître.

---

## 4. L'arbre cible

### 4.1 Fondations

    cfg.sh        la_config : conf_num, conf_str, conf_has, conf_prime, conf_require
    msg.sh        les messages : msg, msg_str, tpn
    fs.sh         chemins et fichiers : state_paths, tmpfile, abs_path, cleanup
    verdict.sh    les trois verdicts : section, ok, note, fail, close

### 4.2 Données

    tab.sh        la table : table_index, table_block, tool_file_of, guardrails
    skl.sh        skills[D33] et projets : active_skill, active_project, project_skills,
                  permanent_section, read_permanent
    canon.sh      le canon : canon_path, et la raison qu'il donne

### 4.3 Le tour

    hist.sh        la base : db_init, db_add, db_insert, hist_window, hist_apply
    agents.sh      la liste fermée des agents
    trace.sh       le journal vivant : trace, say_once, log
    prompt.sh      le prompt : active_block, head_schema, read_prompt
    args.sh        les arguments : args_block_of_tool, args_text, tool_args_text,
                   stdin_tail_of_tool, count_non_stdin_of_tool
    rank.sh        la présélection : rank_share, scope_build, scope_has, in_dirs
    plan_layer.sh  la couche du plan : step_record, step_text, in_plan_family,
                   open_plan, big_plan_txt, big_act
    approval.sh    la porte : approval_gate, approval_ask
    call.sh        l'appel : build_messages, call
    run.sh         l'exécution : exec_engine, result_of, close_remaining
    turn.sh        UN tour, qui enchaîne les modules ci-dessus
    loop.sh        la boucle : signal, repos, reprise. Cible : < 120 lignes

### 4.4 Le carrier — une règle, pas un annuaire

**Correction d'une erreur du plan précédent.** Il prévoyait `carrier_blender.sh`,
`carrier_blender_cli.sh`, `carrier_krita.sh` : un fichier par machine. C'est faux, et c'est
l'architecture qui le dit.

Mesure : `engine.sh:305-314` lit `machine:` **dans le corps du tool**, puis **construit une
chaîne** :

    FCMD="$FMACH --op $FOP"
    FCMD="$FCMD --arg \"$_an={{$_an}}\""     # pour chaque argument declare

Le moteur ne connaît aucune machine. « Carrier » n'est pas un fichier ni un annuaire : c'est
**un mode d'exécution** — un corps sans `COMMAND:` mais avec `machine:` et `op:`.

Mesures : **1 694 corps** portent un `machine:` et **aucun** n'a de `COMMAND:` ; 787 corps
n'ont pas de machine et portent une vraie commande. Les machines se réduisent à **deux** noms
(`blender` 1 692, `blender-cli` 2), ce qui est précisément la raison de ne pas en faire des
fichiers.

Donc :

    carrier.sh      la REGLE : machine + op + args -> une commande. Une fonction courte.

Et les trois fonctions `blender()`, `blender_cli()`, `krita_url()` d'`engine.sh` (l.30-155) ne
sont **pas** des porteurs : ce sont des commandes de corps qui n'ont rien à faire dans le
moteur. `blender()` porte en outre **92 lignes de Python emballé** (l.36-128) pour parler à
`bpy` : c'est un programme déguisé en fonction shell, et il viole la loi 517 comme les autres.
Elles sortent du moteur en phase 5 (§8), et le docteur doit alors leur trouver un domicile
hors de `config[D02]/engine[D09]/`.

### 4.5 Les entrées

    la.sh          LE FICHIER MAITRE (§5)
    second.sh      la couche du plan en mode script (devient mince)
    update.sh      la mise à jour
    doctor.sh      l'orchestrateur du docteur (§4.6)
    … les autres entrées restent, une par métier

### 4.6 Le docteur — un fichier par famille de contrôles

    doctor.sh           orchestre, appelle, compte le total
    check_root.sh       racine, config[D02], 22 cles exigees, cles declarees deux fois
    check_scripts.sh    syntaxe des .sh, briques du coeur, aucun .py dans engine/
    check_programs.sh   presence et taille des programmes, node --check
    check_table.sh      registre : colonnes, doublons, familles acceptees
    check_bodies.sh     chaque tool a son corps
    check_bases.sh      bases : quick_check, journal_mode, qui les nomme
    check_skills.sh     perimetre, porte, tools, summary, approval, todo
    check_canon.sh      lois en double, sections, lignes longues
    check_services.sh   residents, appointees, pont, tailnet
    check_machines.sh   machines declarees, carriers declares

Chaque `check_*.sh` rend des lignes de verdict ; `doctor.sh` les compte. Aucun ne décide du
total : c'est `close` qui compte ce qui est sorti.

**Le défaut P1 est la loi de ce découpage** : `quiet()` disait `ok` sur du vide. `close` compte
les lignes émises entre l'ouverture et lui, donc un contrôle muet ne peut plus passer pour vert.

---

## 5. Le fichier maître

`config[D02]/engine[D09]/la.sh` existe et dispatche déjà. Il devient **le seul point d'entrée**.

    la <metier> [arguments]

    la board | app | say <texte> | cli     l'interface
    la doctor [--short|--light]           le diagnostic
    la tool <family> <tool> [args]        un outil
    la turn                               un tour
    la loop                               la boucle (service)
    la plan | second                      la couche du plan
    la update | backup | session          l'entretien
    la tts | asr | pick                   les residents
    la help

Règles du maître :

- il résout la racine **une fois** et l'exporte ;
- il source les fondations (cfg, msg, fs, verdict), puis **le seul module du métier** ;
- il ne contient **aucune logique métier** : un `case`, des `exec` ;
- les unités `config[D02]/units[D25]/*.in` pointent sur lui : `la loop`, `la doctor --short`, `la tts`.
  Les unités changent **dans la même phase**, sinon on casse le service en croyant ranger.

---

## 6. Ce que devient chaque programme Python

### 6.1 La plomberie — 987 lignes, réductibles en sh

    laconf.py          190  ->  cfg.sh    lib.sh lit deja la_config par sed
    model.py           185  ->  call.sh   curl + jq
    audit_vocab.py     311  ->  vocab.sh  grep sur des mots declares
    sse.py             214  ->  live.sh   printf vers le flux
    vector_pick.py      87  ->  rank.sh   sqlite3 + embedder + awk

Ils ne calculent rien : ils relisent, comparent, recopient. Ils partent.

### 6.2 Le runtime — 3 500 lignes, pas du shell

    dash.py      1538   serveur HTTP + TLS : dashboard et pont du telephone
    board.py     1355   interface terminal Textual
    watch.py      173   onnxruntime
    micro_vision.py 168 cv2 + onnxruntime
    tts_daemon.py 145   sherpa-onnx
    build_tool_vectors.py 121  embeddings

Un shell ne sert pas une page web, n'affiche pas une TUI, ne lance pas un modèle ONNX.
Trois voies :

- **A** — ils restent, **hors du moteur** : ce sont des services. Le moteur les joint par
  leur porte (HTTP, socket, CLI) et reste en sh pur.
- **B** — ils sont remplacés par des binaires non-Python (llama-server, sherpa-onnx binaire,
  serveur HTTP du système). Le Python du projet tombe à zéro, la dette devient binaire.
- **C** — les fonctions disparaissent : plus de tableau, plus de dashboard, plus de voix,
  plus de vision.

Le plan est écrit pour **A**. B est un chantier à part. C est une décision de produit.

---

## 7. Les dépendances autorisées

    dash, coreutils, awk, sed, grep, find, xargs
    jq                JSON
    sqlite3           les bases
    curl              HTTP
    systemctl --user  les services
    tailscale         le tailnet
    node              --check seulement
    tesseract         l'OCR
    git               la mise a jour

Interdits : `python3` dans le moteur, `yq` (absent du PATH de service, et second lecteur de
YAML), tout heredoc, tout outil non installable par la voie officielle.

---

## 8. Les phases, avec leur porte de sortie

**Phase 0 — le docteur** *(spécifiée en §4.6, prête à écrire)*
Réécrit en 11 fichiers de contrôle. C'est l'instrument de mesure de tout le reste.
Porte : le docteur tourne, 0 fault, et il compte par section.

**Phase 1 — les fondations**
`lib.sh` éclate en `cfg.sh`, `msg.sh`, `fs.sh`, `verdict.sh`. Les 23 scripts changent une
ligne chacun (leur source). Aucune logique ne bouge.
Porte : 24 `dash -n` verts, docteur vert, un tour complet joué.

**Phase 2 — les données**
`tab.sh`, `skl.sh`, `canon.sh` sortent de `lib.sh`.
Porte : docteur S05, S06, S09, S10, S11 verts ; la table rend les mêmes 2 487 lignes.

**Phase 3 — la plomberie Python**
`laconf.py` meurt, `model.py` → `call.sh`, `audit_vocab.py` → `vocab.sh`, `sse.py` → `live.sh`,
`vector_pick.py` → `rank.sh`.
Porte : `grep -r python3 config[D02]/engine[D09]` vide ; dashboard, board et TTS démarrent encore.

**Phase 4 — le tour**
`loop.sh` se coupe en dix modules (§4.3). Une fonction déplacée à la fois, un tour joué
entre chaque.
Porte : trois tours identiques en sortie ; `loop.sh` < 120 lignes.

**Phase 5 — les porteurs**
`engine.sh` se coupe en `carrier.sh`, trois `carrier_*.sh`, `shape.sh`.
Porte : les 1 694 corps passent par le routeur ; un `blender` et un `blender-cli` réels passent.

**Phase 6 — les entrées**
`la.sh` devient le maître unique ; `second.sh` cesse d'être un corps ; les unités pointent
sur `la`.
Porte : cinq units vertes, `la doctor` et `la turn` marchent.

**Phase 7 — le ménage**
Fonctions mortes supprimées, listes recopiées remplacées par leur source, chemins en dur
sortis. Un commit par phase.

---

## 9. Le budget

    aujourd'hui       4 438 lignes de sh dans 24 fichiers
                      4 487 lignes de py dans 11 fichiers

    apres 1-2         ~4 400 de sh, ~30 fichiers, aucun > 200
    apres 3           -987 de py
    apres 4           loop.sh 1 447 -> 120 + 10 modules de 80 a 150
    apres 5           engine.sh 597 -> 60 + 5 modules

Projection : **~48 fichiers sh, ~4 300 lignes, aucun au-dessus de 200**. Le total baisse peu ;
c'est la taille de chaque fichier qui change tout.

La règle des 200 lignes n'a pas d'exception : un module qui dépasse est coupé.

---

## 10. Risques

    R1  casser un service en changeant les unites    -> unites dans la meme phase
    R2  perdre un comportement en deplacant du code  -> sortie comparee, phase par phase
    R3  deux lecteurs de config[D02] qui divergent         -> cfg.sh seul lecteur, laconf.py meurt
    R4  une liste recopiee qui revient               -> le docteur la signale
    R5  la dette python deplacee, pas reduite        -> T1 tranche A, B ou C
    R6  refactorisation infinie                      -> chaque phase a une porte mesurable ;
                                                        pas de porte, pas de phase suivante

---

## 11. Ce qui reste à trancher

**T1 — le runtime Python** : A (services hors moteur), B (binaires), C (on supprime tableau,
dashboard, voix, vision). Le plan est écrit pour A.

**T2 — le nom du maître** : `la.sh` devient le maître unique. Si le canon impose un autre nom,
il faut le dire maintenant, pas en phase 6.

---

## 12. Journal

    | date | phase | fait | porte |
    |---|---|---|---|
    | 2026-10-20 | 0 | plan de refactorisation ecrit ; inventaire mesure : 24 sh / 4 438 l, 11 py / 4 487 l | non franchie |
