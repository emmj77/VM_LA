# SKILL TUNNEL — le mecanisme en une page

Ecrit le 2026-10-22, version 2 : le pas devient une donnee, et c est le moteur qui valide.
Corpus sans accent, prose francaise, identifiants anglais.

## 1. Une phrase

Une skill tunnel est une ROUTE FERMEE : son plan est ecrit dans son propre `skill.yaml`, et
le moteur n ouvre au modele, tour apres tour, que le JEU d outils du pas courant. Le modele
ne choisit ni le plan, ni l ordre, ni l etape : il travaille dans le jeu qu on lui ouvre.

## 2. La marque

    PERMANENT_TODO: true        # dans skills/<nom>/skill.yaml

C est elle, et rien d autre, qui fait basculer le moteur (`engine/skl.sh`) :
  - `skl_plan_is_closed` lit ce drapeau ;
  - `skl_plan_src` lit alors le plan DANS `skills/<nom>/skill.yaml`, section `PLAN` ;
  - une skill ordinaire lit son plan dans `state/<agent>_todo.md`.

## 3. Le pas — tout dans le YAML

    PLAN:
      400: "phone on the bridge, proven"
  at: 401            # ecrit par le moteur : l id du pas courant, puis done
      401:
        text:  "read what stands"
        tools: [tunnel_status, read_file]
        close: ["10.10.0.1", "@"]
      402:
        text:  "raise wg0, or lower it first if the profile is lost"
        tools: [tunnel_up, tunnel_down, tunnel_status]
        close: ["10.10.0.1"]
      403:
        text:  "prove it by the fact"
        tools: [tunnel_status]
        close: ["10.10.0.1", "@", "peer"]
      404:
        text:  "report four lines"
        tools: [reply]
        close: []

  - `text`  : une ligne, 100 octets au plus ;
  - `tools` : le JEU des outils que ce pas ouvre (`reply` vient en plus, toujours) ;
  - `close` : les preuves. Chaque litteral doit apparaitre dans le retour de l outil que le
              pas a servi. Liste vide : la seule preuve est `status ok` plus le texte qui
              commence par `ok `.

**Un pas ouvre un jeu, jamais un seul outil.** C est ce qui justifie un modele : si chaque
pas n ouvrait qu un outil, avec une suite connue d avance, la route entiere serait un script
python et le modele n aurait rien a y faire. Ce que le modele apporte, c est la latitude
DANS l etape : plusieurs outils ouverts, il choisit lequel, avec quels arguments, il lit le
retour, il insiste ou il change de voie — `tunnel_down` avant `tunnel_up` quand le profil est
perdu, par exemple. Le moteur, lui, ne connait du pas que le jeu qu il ouvre et sa porte de
sortie (`close`). Un pas dont le jeu tient en un seul outil est le signe d un pas qui devrait
etre un script, pas une etape.

Tout ce qui est propre a une skill vit ici, dans la donnee. Le moteur ne connait le nom
d aucun outil d aucune skill : il lit trois champs et il applique.

## 4. Qui impose, et qui ferme le pas

`skl_lock` (`engine/skl.sh`) nomme ce que le tour peut porter :

    1  doc du skill pas lu         -> load_doc
    2  pas de plan                 -> todo
    3  route, un pas ouvert        -> les `tools` du pas, et eux seuls
    4  route, plus de pas ouvert   -> rien : le jeu s ouvre
    5  skill ordinaire             -> update_todo, quand le plan n a pas bouge depuis
                                      loop.todo_every tours

`skl_gate`, meme fichier, en est la seule porte, avec trois lecteurs : `turn.toolset` (le
tableau envoye au modele), la porte `run.sh` (le refus avant execution), et `loop.sh`.

**C est le moteur qui ferme le pas, pas le modele.** A chaque retour d un outil nomme par
`tools`, le moteur evalue `close` :

    status ok   ET   le texte commence par "ok "   ET   chaque litteral de close est present
    vrai  ->  le pas passe [completed], le suivant [in_progress], la cle at du plan prend son id
    faux  ->  rien ne bouge, et le refus nomme ce qui manque :
              "the step stays open: 10.10.0.1 is not in the return of tunnel_status"

Le modele ne declare donc plus rien sur une route : il appelle l outil du pas et il lit le
retour. `update_todo` n a plus de role sur une route ; il reste le geste du journal.

## 5. Ce qui reste dans le shell

Quatre gestes, et aucun ne connait une skill par son nom :

    - lire le manifeste (la FORME du YAML, jamais le sens d une route) ;
    - ouvrir exactement les `tools` du pas, plus `reply` ;
    - evaluer `close` : status, prefixe, litteraux ;
    - ecrire at: lid du pas suivant (ou le vider : la route est faite).

Une route qui veut une preuve nouvelle n ajoute pas de bash : elle ajoute un litteral dans
`close`. Si une preuve depasse un jour les litteraux (un octet, un port en ecoute), c est
une decision humaine, pas une extension du moteur par la bande.

## 6. La fin

Le dernier pas passe `[completed]` -> `skl_turn_end` decharge la skill (`engine/loop.sh`).
La route ne s efface pas : elle reste dans son `skill.yaml`, prete a repartir.

## 7. Ou ca se branche

| maillon | fichier | ce qu il fait |
|---|---|---|
| la marque | `skills/<nom>/skill.yaml` | `PERMANENT_TODO: true` |
| le plan lu | `engine/skl.sh` | `skl_plan_src`, `skl_plan_is_closed` |
| le pas, en donnee | `engine/skl.sh` | `skl_plan_step` : `text`, `tools`, `close` |
| le verrou | `engine/skl.sh` | `skl_lock` : les `tools` du pas, plus `reply` |
| la porte | `engine/skl.sh` | `skl_gate`, `_skl_gate_check` |
| les outils ouverts | `tools/turn/tool_toolset.yaml` | lit `skl_gate`, mappe les noms |
| le refus avant execution | `engine/run.sh` | `run_call`, meme `skl_gate` |
| la validation du pas | `engine/skl.sh` | `skl_step_close` : status, prefixe, litteraux ; appele par `shell_exec` |
| la fin | `engine/loop.sh` | `skl_turn_end` decharge la skill |
| la trace | `engine/step.sh` | `trace_line`, seul ecrivain du journal |

Un seul endroit decide du perimetre (`skl_gate`), un seul valide le pas (`skl_step_close`,
appele par `shell_exec` au retour de l outil, jamais par le modele).

## 8. Prerequis — une route qui en manque un est morte

    1  skills/<nom>/skill.yaml : PERMANENT_TODO: true, PLAN (400 + pas), SKILL_TOOL_SET,
       DOCS, WRITABLE_WORKSPACE, ERROR
    2  chaque nom de `tools` existe au registre (registry.yaml)
    3  DOCS n est JAMAIS vide : une phrase au moins, dans chaque skill. trois formes, et
       elles se melangent : "web_search" (la source officielle), le NOM d un fichier du
       disque (tools/, la racine, skills/<nom>/, skills/), ou la phrase elle-meme, que
       load_doc rend telle quelle. le docteur nomme une skill sans doc.
    4  APPROVAL: false justifie : les outils de la route vivent hors GATED
    5  un agent arme : la skill load <nom> (l humain), ou la charge par la porte
    6  les pas : 12 au plus, `text` 100 octets, et chaque pas porte `text`, `tools`, `close`

## 9. Ce que la version 2 change, a valider avant de coder

    - le pas : une ligne de texte -> un mapping a trois cles ;
    - `-- tools:` disparait ; `tools:` le remplace, et c est un JEU : plusieurs outils par
      pas, jamais un seul — un pas a un seul outil est un pas de script ;
    - sur une route, `update_todo` disparait : le moteur ferme le pas sur la preuve ;
    - `skl_plan_step` sort le pas entier ; un validateur neuf, `skl_step_close`, rend vrai
      ou faux et nomme le litteral manquant ;
    - le docteur refuse une route dont un pas n a pas de `close` ;
    - les routes existantes sont reecrites au nouveau pas (phone-tunnel d abord).

## 10. Les deux skills du canon

    create-spec    une route (la forme ci-dessus) : pose une section qui n existe pas,
                   un pas par section, chaque pas prouve par ses litteraux.
    manage-spec    une skill ordinaire : lit, corrige, verifie un canon existant ;
                   elle ne cree rien.

Aucune autre skill n ecrit dans `SPEC`. La creation est une route ; l entretien est un geste.
