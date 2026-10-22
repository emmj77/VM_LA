# SKILL TUNNEL — le mecanisme en une page

Ecrit le 2026-10-22. Remplace le document du 21/10 (432 lignes) : meme sujet, verifie
contre le code du jour. Corpus sans accent, prose francaise, identifiants anglais.

## 1. Une phrase

Une skill tunnel est une ROUTE FERMEE : son plan est ecrit dans son propre `skill.yaml`, et
le moteur n ouvre au modele, tour apres tour, que l outil du pas courant. Le modele ne
choisit ni le plan, ni l ordre, ni l outil : il remplit un moule et rend compte.

## 2. La marque

    PERMANENT_TODO: true        # dans skills/<nom>/skill.yaml

C est elle, et rien d autre, qui fait basculer le moteur (`engine/skl.sh`) :
  - `skl_plan_is_closed` lit ce drapeau ;
  - `skl_plan_src` lit alors le plan DANS `skills/<nom>/skill.yaml`, section `PLAN` ;
  - une skill ordinaire lit son plan dans `state/<agent>_todo.md`.

## 3. Le pas

    400: "PLAN <nom> : <le but>"
    401: "[in_progress] <le pas en cours> -- tools: <un seul outil>"
    402: "[todo] <le pas suivant> -- tools: <un seul outil>"

  - marques : `[in_progress]` (une seule), `[todo]`, `[completed]` ;
  - une ligne : 100 octets au plus ; une route : 12 pas au plus ;
  - champs facultatifs : `-- bytes: <chemin>@<taille>` et `-- max: <n>` ;
  - `skl_plan_step` rend quatre colonnes : id, outil, bytes, max.

## 4. Qui impose quoi

`skl_lock` (`engine/skl.sh`) est LE verrou du tour : elle nomme l unique outil tenu.

    1  doc du skill pas lu         -> load_doc
    2  pas de plan                 -> todo
    3  route, un pas ouvert        -> l outil du pas (le champ -- tools:)
    4  route, plus de pas ouvert   -> rien : le jeu s ouvre
    5  skill ordinaire             -> update_todo, quand le plan n a pas bouge depuis
                                      loop.todo_every tours

`skl_gate`, meme fichier, en est la seule porte, avec trois lecteurs : `turn.toolset` (le
tableau envoye au modele), la porte `run.sh` (le refus avant execution), `loop.sh`
(l echeance).

    verrou ouvert -> verrou + reply, et rien d autre
    aucun verrou  -> les permanents + les outils de la skill (+ update_todo)

`reply` est toujours ouvert : c est la voix, jamais une action.

## 5. Ce qui ferme un pas

Le FAIT, jamais la parole. Deux conditions ensemble :

    status == "ok"   ET   le texte du retour commence par "ok "

Un corps qui imprime `FAULT` sort aussi en `status: ok` : le texte seul distingue l ouvrage
du refus. Un pas qui refuse (wg absent, conf illisible) ne se ferme pas : le modele dit ce
qui manque, il ne raconte pas que c est fait.

## 6. La fin

Le dernier pas passe `[completed]` -> `skl_turn_end` decharge la skill (`engine/loop.sh`).
La route ne s efface pas : elle reste dans son `skill.yaml`, prete a repartir.

## 7. Ou ca se branche

| maillon | fichier | ce qu il fait |
|---|---|---|
| la marque | `skills/<nom>/skill.yaml` | `PERMANENT_TODO: true` |
| le plan lu | `engine/skl.sh` | `skl_plan_src`, `skl_plan_is_closed` |
| le pas courant | `engine/skl.sh` | `skl_plan_step` : `-- tools` `-- bytes` `-- max` |
| le verrou | `engine/skl.sh` | `skl_lock` : l unique outil du tour |
| la porte | `engine/skl.sh` | `skl_gate`, `_skl_gate_check` |
| les outils ouverts | `tools/turn/tool_toolset.yaml` | lit `skl_gate`, mappe les noms |
| le refus avant execution | `engine/run.sh` | `run_call`, meme `skl_gate` |
| l avancee du pas | `tools/core/tool_update_todo.yaml` | `update_todo` -> `skl_plan_advance` |
| la fin | `engine/loop.sh` | `skl_turn_end` decharge la skill |
| la trace | `engine/step.sh` | `trace_line`, seul ecrivain du journal |

Un seul endroit decide du perimetre : `skl_gate`. Le tableau envoye au modele et le refus de
la porte lisent la meme fonction : ils ne peuvent pas diverger.

## 8. Prerequis — une route qui en manque un est morte

    1  skills/<nom>/skill.yaml : PERMANENT_TODO: true, PLAN (400 + pas), TOOLS, DOCS,
       WRITABLE_WORKSPACE, ERROR
    2  chaque -- tools: nomme un outil du registre (registry.yaml)
    3  le doc nomme dans DOCS existe sur le disque : tools/, la racine, skills/<nom>/,
       skills/ — sinon la porte ne lache que load_doc et la route ne demarre jamais
    4  APPROVAL: false justifie : les outils de la route vivent hors GATED
    5  un agent arme : la skill load <nom> (l humain), ou la charge par la porte
    6  les pas : 12 au plus, 100 octets par ligne, un seul outil par pas

## 9. Les deux skills du canon

    create-spec    une route (la forme ci-dessus) : pose une section qui n existe pas,
                   un pas par section, chaque pas prouve.
    manage-spec    une skill ordinaire : lit, corrige, verifie un canon existant ;
                   elle ne cree rien.

Aucune autre skill n ecrit dans `SPEC`. La creation est une route ; l entretien est un geste.
