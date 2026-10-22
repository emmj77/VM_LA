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

## Reste ouvert (ancienne liste, à trancher)

5. **Reranker, autres missions** : au-delà de l'effort, la palette et le réveil.
6. **Simplifier** : encore moins de lignes.
13. **Outils et skills manquants** : à recenser.
15. **Section de spec à afficher dans la tête secondaire.**
7. **Délégation + chat inter-agent** : à tester.
8. **Boucle longue** : test de tenue (plusieurs heures).
9. **Tests de chargement** : skill load/unload, projets, todos, app Android.
11. **Compacteur** : chercher plus léger et meilleur parmi les modèles récents.

Et trois trous connus du moteur :

- `second.order` : schéma mort dans `la_config`, aucun lecteur — à brancher ou à retirer.
- `turn.json` est partagé : le drapeau « doc lue » est global, deux sessions se marchent dessus.
- Le schéma d'erreur : tout tombe encore dans `refusals.arity`.
