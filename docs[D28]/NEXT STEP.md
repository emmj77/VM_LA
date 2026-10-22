# NEXT STEP

## Ce qui est fait

- **manage-spec** (K36), quatre outils, un par acte : `spec_read` (lire une section ou tout le canon,
  énoncés numérotés), `spec_set` (écrire un énoncé nouveau, ou remplacer celui d'un numéro),
  `spec_drop` (ôter l'énoncé d'un numéro), `spec_check` (audit : les trois clés, chaque section, chaque
  énoncé contre le plafond, chaque répétition). Aucun ne **nomme** une section : nommer est l'acte de
  `create-spec`.
- **La route** : le pas est une donnée (`text`, `tools`, `close`) ; le moteur ferme le pas sur le fait
  (`skl_step_close`, au retour de l'outil) ; `at:` dans le `skill.yaml` dit où l'on en est.
- **Le doc** : la section `DOCS` est le doc, jamais vide, et les trois formes se mêlent.

## Le pas suivant : la skill `create-spec`

Route tunnel (`PERMANENT_TODO: true`), plan dans son `skill.yaml`, chaque pas ouvre un JEU d'outils et
se ferme sur un fait évalué par le moteur. Elle ne travaille que sur une section **absente** ; la
présence de la section à la fin est la preuve du dernier pas.

    400: "a section of the canon that was not there, and holds"
    at: 401
    401 read    [spec_read, read_file]      close: ["scaffolding"]   lire ce qui tient
    402 name    [spec_open, spec_read]      close: ["<section>"]     nommer la section, vide
    403 write   [spec_set, spec_read]       close: ["<section>"]     poser les énoncés, un par un
    404 audit   [spec_check, spec_read]     close: ["ok spec"]       l'audit passe sans faute
    405 report  [reply]                     close: []                dire ce qui a été nommé

Deux décisions à prendre avant de l'écrire :

1. `spec_open <section>` — l'outil qui pose la section vide : `spec_open` ou `spec_begin` ?
2. La preuve du pas 404 : le littéral `ok spec` suffit-il, ou faut-il exiger le compte
   (`7 section(s)`) pour prouver que la section est bien entrée ?

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
