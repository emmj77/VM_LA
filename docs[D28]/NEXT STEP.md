# NEXT STEP

## Ce qui est fait

- **manage-spec** (K36), deux outils, deux actes : `load_spec` (tout le canon, une section, ou une
  plage de lignes, numerotees d un bout a l autre) et `app_spec` (une ou deux lignes, a l offset dit,
  dans une section qui existe). `app_spec` ne passe qu apres un `load_spec` du meme tour, et le load
  se ferme apres une ecriture : une ecriture par load. Aucun outil ne nomme une section.
- **La route** : le pas est une donnée (`text`, `tools`, `close`) ; le moteur ferme le pas sur le fait
  (`skl_step_close`, au retour de l'outil) ; `at:` dans le `skill.yaml` dit où l'on en est.
- **Le doc** : la section `DOCS` est le doc, jamais vide, et les trois formes se mêlent.

## Le pas suivant : la skill `create-spec`

Route tunnel (`PERMANENT_TODO: true`), plan dans son `skill.yaml`, chaque pas ouvre un JEU d'outils et
se ferme sur un fait évalué par le moteur. Elle ne travaille que sur une section **absente** ; la
présence de la section à la fin est la preuve du dernier pas.

    400: "a section of the canon that was not there, and holds"
    at: 401
    401 read    [load_spec, read_file]     close: ["scaffolding"]   lire ce qui tient
    402 name    [open_spec, load_spec]     close: ["<section>"]     nommer la section, vide
    403 write   [load_spec, app_spec]       close: ["<section>"]     poser les enonces, deux par deux
    404 prove   [load_spec, read_file]      close: ["<section>"]     la section est la, et tient
    405 report  [reply]                     close: []                dire ce qui a ete nomme

Deux décisions à prendre avant de l'écrire :

1. L'outil qui **nomme** la section vide — son nom, et son unique argument : `open_spec <section>` ?
   Il exige une section absente, et pose la clé vide dans le `SPEC`.
2. `create-spec` écrit-elle aussi ses premiers énoncés (`load_spec` + `app_spec` dans la route), ou
   ouvre-t-elle la section et passe-t-elle la main à `manage-spec` ?

## Demain — imposer `manage-spec`

Quand un projet est charge, le modele doit travailler le canon de ce projet. Deux formes, retenues :

1. **a l'unload du projet** : au moment ou le projet se decharge, la porte impose `manage-spec`. Le canon
   se travaille quand le chantier se ferme, jamais au chargement.
2. **a cadence** : `manage-spec` revient tous les N tours tant qu'un projet est charge — la cadence en
   `la_config`, comme `loop.todo_every` et `loop.big_todo_every`.

## Demain — le dispatcher unity

    le docteur le dit maintenant : 211 corps de la famille unity n'ont ni skill ni dispatcher
    (note 211 body(ies) of unity: no skill opens them and no dispatcher enters the family).
    upipe_command n'en entre que 44 ; les 167 autres n'ont aucune porte nommée.

Ce qu'il faut : un `unity_command` sur le dessin de `upipe_command` et de `krita_cli_tools` —
l'opération en enum, la connaissance des fiches dans la DESCRIPTION, un seul fichier.

  1. lister les ops et ne garder que les corps dont ARGS est vide et dont le seul mot qui
     change est l'opération (le même scan que pour les 44 upipe) ;
  2. prouver le même argv avant et après avec un faux CLI, op par op ;
  3. les corps qui portent des arguments réels restent des tools : une fusion ne vaut que
     pour ce qui ne diffère que par un mot.

## Reste ouvert (ancienne liste, à trancher)

5. **Reranker, autres missions** : au-delà de l'effort, la palette et le réveil.
6. **Simplifier** : encore moins de lignes.
13. **Outils et skills manquants** : à recenser.
15. **Section de spec à afficher dans la tête secondaire.**
7. **Délégation + chat inter-agent** : à tester.
8. **Boucle longue** : test de tenue (plusieurs heures).
9. **Tests de chargement** : skill load/unload, projets, todos, app Android.
11. **Compacteur** : chercher plus léger et meilleur parmi les modèles récents.
12. corriger le flux sonore ne marche plus
14. corriger le streaming
RENFORCER LA SOLIDITE L'APP BUG TROP SOUVENT

