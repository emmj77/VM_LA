# Unity : fusion des outils à geste

Même méthode que Blender, appliquée aux 643 fiches de `config/tools/unity/`.

## Règle

Une fusion n'est faite que si deux outils visent **la même chose** et que la
variante est une valeur fermée. Le discriminant s'appelle `geste`.

Trois familles de CLI cohabitent dans ce dossier :

| préfixe | CLI | fiches |
|---|---|---|
| `coplay_` | `unity-mcp`, `set -- <groupe> <action>` | 277 |
| `unity_` | `unity` (cloud, vcs, projets) | 216 |
| `upipe_` | `unity-mcp`, `set -- command <nom> --project-path` | 150 |

Seul `coplay_` a un découpage `groupe + action`, donc seul `coplay_` est
fusionnable sur un axe.

## Forme retenue

Les 198 corps d'origine ne sont **pas** réécrits. Chaque geste garde son corps
mot pour mot dans une branche :

```
  case "{{geste}}" in
  play)   ...corps de coplay_audio_play...   ;;
  stop)   ...corps de coplay_audio_stop...   ;;
  esac
```

Raison : dans cette famille, les corps ne sont pas un gabarit unique. Ils
portent des drapeaux booléens (`[ "{{force}}" = true ] && set -- --force`), des
contrôles de format (`position` doit être deux nombres) et des listes fermées
par argument. Un corps reconstruit à partir des seules lignes `set --` perdait
ces contrôles : la tentative a été mesurée, 24 écarts sur 100 appels, puis
abandonnée au profit de la recopie.

Le gain n'est pas en lignes de shell, il est dans le catalogue : un nom, une
description qui liste les valeurs, le moteur refuse un `geste` inconnu ou vide
en nommant la liste.

## Les 37 fiches fusionnées

| fiche | gestes | fiche | gestes |
|---|---|---|---|
| `coplay_animation_animator` | 7 | `coplay_graphics_skybox_set` | 6 |
| `coplay_animation_clip` | 9 | `coplay_graphics_volume` | 2 |
| `coplay_animation_controller` | 12 | `coplay_graphics_volume_set` | 2 |
| `coplay_asset` | 8 | `coplay_instance` | 3 |
| `coplay_asset_gen` | 7 | `coplay_packages` | 12 |
| `coplay_audio` | 3 | `coplay_physics_configure` | 3 |
| `coplay_blender` | 9 | `coplay_physics_get` | 2 |
| `coplay_build` | 6 | `coplay_prefab` | 6 |
| `coplay_camera_set` | 7 | `coplay_probuilder_create` | 2 |
| `coplay_component` | 4 | `coplay_probuilder_extrude` | 2 |
| `coplay_editor` | 18 | `coplay_probuilder_set` | 3 |
| `coplay_gameobject` | 5 | `coplay_profiler_frame_debugger` | 3 |
| `coplay_graphics_bake` | 5 | `coplay_profiler_memory` | 3 |
| `coplay_graphics_bake_create` | 2 | `coplay_scene` | 12 |
| `coplay_graphics_feature` | 6 | `coplay_shader` | 4 |
| `coplay_graphics_pipeline` | 2 | `coplay_texture` | 5 |
| `coplay_graphics_pipeline_set` | 2 | `coplay_ui_create` | 4 |
| `coplay_vfx_line` | 5 | `coplay_vfx_particle` | 6 |
| `coplay_vfx_trail` | 3 | | |

198 opérateurs couverts, 198 fiches retirées, 37 ajoutées : 643 → 482 fiches
(-25 %), 161 noms en moins.

## Ce qui n'a pas été fusionné

- **`upipe command` (150)** : le nom de la commande est la variante. Fusionner
  reviendrait à mettre 150 commandes sans rapport derrière un seul `geste`.
- **`coplay_material` (6)** : l'ordre des arguments positionnels diffère d'un
  membre à l'autre. Aucun ordre commun ne respecte tous les appels.
- **7 membres écartés** pour conflit de style sur un même argument (positionnel
  chez l'un, `--drapeau` chez l'autre) : `animation controller add-layer`,
  `asset search`, `prefab create`, `gameobject create`, `shader create`,
  `build platform`, `build run`. Ils restent des fiches séparées.
- **`graphics`, `physics`, `profiler`, `probuilder`, `camera`** : la variante
  porte l'objet lui-même (`bake-create-probes` vs `bake-start`). Seuls les
  sous-groupes de même objet ont été fusionnés (`graphics_bake`,
  `profiler_memory`, etc.).

## Le piège corrigé

Un argument `type: enum` de l'union devient obligatoire pour **tous** les
gestes : le moteur refuse une valeur vide. `preset` (utilisé par `create-preset`
seul) rendait `add-curve` incallable. Pour trois arguments dans ce cas
(`preset`, `direction`, `kind`), la déclaration est passée en `text` et la liste
fermée est écrite dans la DESCRIPTION. Les autres enums restent fermés.

## Preuves

Doublure de CLI dans le scratch qui imprime son `argv`, `LA_UNITY_MCP` pointé
dessus, appels réels par `config/engine/engine.sh` :

- 198/198 appels rendent le **même argv** et le **même refus** que l'ancien
  outil (198 comparaisons, 0 écart).
- 37/37 fiches atteignent leur CLI avec des arguments valides.
- `geste` inconnu : `refused: coplay_audio : bidon is not in the closed list of
  geste ; values : play | stop | volume`.
- `unity_tools_find audio` rend 22 lignes, dont les fiches fusionnées.
- `doctor.sh` : 0 faute, 8 notes antérieures.

Le CLI `unity-mcp` n'est pas branché (`unity: mcp: ""` dans `la_config.yaml`) :
en l'état, toute fiche de cette famille refuse en le nommant. C'est aussi ce qui
rend les tests indolores, mais l'équivalence des arguments est prouvée sur la
doublure, pas sur Unity.
