# SKILL TUNNEL — le mecanisme reel, et le plan de create_spec

Un seul document. Il absorbe et remplace quatre fichiers, retires du corpus le 21/10 :
  SKILL_TUNNEL_SPEC.md, SPEC_RETOUR_ERREUR_SCHEMA.md (Bureau),
  docs/skills-tunnel-nouveau-format.md, docs/TUNNEL_three_skills_to_judge.md.
Ecrit le 2026-10-21. Corpus sans accent. Prose francaise, identifiants anglais (loi 108).

---

## 0. LES DECISIONS DU 21/10 (Moussa)

| N | Decision |
|---|---|
| 1 | La route d'un tunnel est le PLAN PERMANENT (4xx + PERMANENT_TODO: true). Le bloc STEPS (5xx) reste mort : on ne l'exhume pas. |
| 2 | Le curseur d'etape vit DANS LA SKILL, pas dans un fichier d'etat a cote. |
| 3 | Un seul outil par etape, hors toolset permanent. Le modele recoit les permanents + cet outil, et le moteur REFUSE tout autre outil, sauf reply et ask. |
| 4 | phone-tunnel est le banc d'essai. Sa derniere etape portera answer. |
| 5 | Le meta-schema la(g,a) et le schema complet sur erreur : chantier separe, apres le tunnel. |
| 6 | La pose des touches appartient a l'assistant, une touche par message, teste apres chacune. |

---

## 1. DEFINITION

Un tunnel est une skill dont la route est ecrite par l'humain, et dont chaque etape
n'ouvre au modele QU'UN outil. Le modele remplit un moule ; il ne choisit ni l'ordre,
ni le plan, ni l'outil suivant. L'etape suivante s'ouvre sur un FAIT lu dans la machine,
jamais sur la parole du modele. Le tunnel est la ROUTE ; le plan est son journal.

Trois piliers (lois 1020, 705, 1512, 1123-1125) :
  - le RANG est l'ORDRE : une ligne de plan, un rang, pas une prose « l'ordre recommande » ;
  - l'OMISSION est la PROHIBITION : l'outil des autres etapes n'est pas envoye ;
  - l'AVANCEE est un FAIT : le moteur lit, le modele ne juge pas.

---

## 2. LE MECANISME REEL, CODE EN MAIN

### 2.1 La boucle — engine/loop.sh, conf/pipeline.yaml

`pipeline.yaml` liste l'ordre, et rien d'autre ne le decide :

    steps: facts, second, effort, scope, prompt, call, tools, reply, note

`loop.sh` coupe cette liste en trois : `loop_before` (avant `call`), `loop_cycle`
(`call` .. `tools`), `loop_after` (apres `tools`). Le cycle se repete tant que
`turn.json` gagne des appels (`.calls | length`) ; une reply ferme le tour.

Consequence pour le tunnel : l'avance doit etre lue APRES `tools` et AVANT le `scope`
du tour suivant. C'est exactement l'emplacement d'une etape de pipeline a ajouter.

### 2.2 La palette — trois constructeurs, dont un mort

(a) `turn.scope` (tools/turn/tool_turn_scope.yaml) : c'est LUI qui produit le tableau
    `tools` envoye a l'API.

    _perm=$(cfg list permanent)
    _ids=$( { for _n in $_perm; do table_field "$_reg" "$_n" id; done
              skl_toolset 2>/dev/null; } | sort -u )

    Puis : pour chaque id, une fonction {name, description, parameters} avec les
    arguments declares dans le corps. Puis le reranker note chaque outil contre la
    demande et coupe a `loop.share` (30 %), jamais moins de trois, `reply` force.

    PIEGE MESURE, a traiter dans la touche : avec la liste permanente (19 noms) plus
    UN outil d'etape, la coupe s'active (_top = 6) et peut RETIRER l'outil de l'etape.
    Dans un tunnel, la coupe est donc court-circuitee : l'outil de l'etape reste, toujours.

(b) La porte — engine/run.sh etape 5, via `tool_allowed` (skl.sh) :

    tool_allowed() { skl_permanent "$1" && return 0 ; skl_carries "$1" "$2" ; }

    C'est le refus reel : un outil hors palette est refuse AVANT execution.

(c) `tools_list` (core/tool_toolset.yaml) : reconstruit la palette a la main. Il est
    MORT aujourd'hui : il lit `$ROOT/config/la_config.yaml` et `$ROOT/config/la_tools.yaml`,
    deux chemins qui n'existent pas (le maitre est `config[D01]/conf[D05]/la_config.yaml`).
    Il devra passer par le meme constructeur, pas par une troisieme lecture.

Regle de pose : un seul constructeur (`skl_palette`), trois lecteurs. Deux lectures
qui divergent font un modele qui appelle un outil que la porte refuse.

### 2.3 La porte — run.sh, dans l'ordre

    1 registre lu (registry.yaml pour le modele, registry-engine.yaml pour le moteur)
    2 l'id, puis le nom (l'id est l'identite)
    3 le corps, par le nom : tools/<famille>/tool_<nom>.yaml
    4 coherence registre / corps (id et famille)
    5 tool_allowed   <- LE REFUS DU PERIMETRE
    6 arite et types (path, enum, int, bool, text)
    7 chemins : un argument path ne sort pas du canon
    8 approval (quatre corps attendent un humain)
    9 commande montee, aucun {{...}} restant
   10 shell_exec : une seule voie de lancement, un timeout, une forme

### 2.4 Ce que « ok » veut dire — et pourquoi ca change tout

`shell_exec` : code de retour 0 -> `shape ok`, quoi que le corps ait imprime.
Un corps imprime `ok ...`, `note ...` ou `FAULT ...` et sort TOUJOURS 0 (loi 609).

Donc `status: ok` ne dit RIEN de l'ouvrage : un `FAULT tunnel file cannot be installed`
sort en `status: ok`. La verite est dans le TEXTE du retour.

La condition d'avance se lit donc sur les deux champs :

    status == "ok"   ET   result commence par "ok "

C'est le point le plus important du document : aujourd'hui rien ne distingue un outil
qui a fait le travail d'un outil qui a refuse. `note` et `FAULT` ne ferment pas une etape.

### 2.5 Le plan — tools/plan/*.yaml

Cinq gestes : `plan.read`, `plan.add`, `plan.change`, `plan.progress`, `plan.done`.
Deux lignes par tache (400..419), 100 octets par ligne, 20 lignes au plus (lois 1012/1013).
`plan.progress` ecrit dans `skills/<skill>/skill.yaml` avec un `awk` puis `mv -f` :
le plan d'une skill humaine est deja ecrit par un corps. C'est le precedent qui autorise
le moteur a tenir le curseur dans la skill (decision 2).

### 2.6 Le gabarit — conf/templates/skill_template.yaml

`PERMANENT_TODO: true` y est documente (le plan est une route, la palette se ferme sur
l'etape courante, c'est la boucle qui ferme). Le bloc `STEPS` y a ete RETIRE le 19/10 :
« une route qu'on ne peut pas appliquer est une suggestion de plus ». `set_steps` repond
`steps_gone` (texts.yaml). Rien dans le code ne lit `PERMANENT_TODO`.

---

## 3. L'ETAT PRESENT, MESURE

| ce qu'on regarde | commande | resultat |
|---|---|---|
| qui lit PERMANENT_TODO | `grep -rn PERMANENT_TODO engine/ programs/ tools/` | 0 |
| qui lit le suffixe `-- tools:` d'une ligne de plan | `grep -rn -- "tools:" engine/ programs/` | 0 |
| qui lit STEPS | `grep -rln STEPS engine/ tools/` | 0 |
| la palette est-elle coupee par etape | `tool_turn_scope.yaml` | non : permanent + toute la skill |
| les 4 outils tunnel sont-ils au registre | `grep -n 'tool: "tunnel' registry.yaml` | 4 (status, up, down, provision) |
| `tools_list` est-il vivant | `ls $ROOT/config/la_config.yaml` | non : chemin inexistant |
| `plan_status` appele par turn.prompt | `grep -rn plan_status` | 1 hit : l'appel seul, la fonction n'existe pas |

Traduction : le canon §TUNNEL (lois 2400..2409) est une PROMESSE. Le code tient 2402 sur
la skill entiere, et rien de 2401, 2403, 2404, 2409. `phone-tunnel` declare
PERMANENT_TODO: true : sa route ne contraint rien aujourd'hui.

---

## 4. LA FORME D'UNE ROUTE

Section PLAN d'une skill tunnel. La ligne 400 porte le titre, 401..419 les etapes.

    400: "PLAN phone-tunnel : le pont du telephone, prouve par la machine"
    401: "[progress] lire l etat du tunnel -- tools: tunnel_status"
    402: "[todo] lever wg0 -- tools: tunnel_up"
    403: "[todo] constater ce qui est monte -- tools: tunnel_status"
    404: "[todo] rendre compte -- tools: answer"

Regles de forme, refusees a la pose (loi 1014) :
  - exactement UNE ligne `[progress]` ; les autres sont `[todo]` ou `[done]` (loi 2401) ;
  - UN seul outil par etape, hors toolset permanent ;
  - l'outil nomme existe dans `TOOLS` ET dans la table du registre ;
  - 100 octets par ligne, 20 lignes au plus ;
  - la derniere etape porte `answer` : le tunnel ne se ferme pas sur un silence ;
  - `-- bytes: <chemin>@<taille>` : condition de delta (facultative, voir 5.4) ;
  - `-- max: <n>` : plafond de lignes pour l'outil de l'etape (facultatif).

Ce que la route ne porte JAMAIS : ni consigne d'interdiction, ni nom d'un outil qu'elle
ne donne pas. Ce qui n'est pas envoye n'a pas besoin d'etre refuse (lois 705, 1512).

---

## 5. LA MECANIQUE A POSER

### 5.1 Le curseur vit dans la skill (decision 2)

Le curseur n'est pas un fichier de plus : c'est le marqueur de la ligne de plan.
  - l'etape courante est LA ligne `[progress]` ;
  - `done` = faite, `todo` = en attente ;
  - aucune autre copie de l'etat n'existe. Le plan EST l'etat, il est lisible par
    l'humain (`plan.read`) et par la machine (meme section).

L'ecriture de la ligne appartient au moteur, jamais au modele (loi 2404). Le geste est
une reecriture d'UNE ligne par son id, comme `plan.progress` : `awk` puis `mv -f`.

### 5.2 T1 — `skl_palette` : un constructeur, trois lecteurs

Nouvelle fonction dans `engine/skl.sh`, a cote de `skl_toolset` :

    skl_palette   # les noms des outils du tour, un par ligne
                  # tunnel ouvert -> l'outil de la ligne [progress], et lui seul
                  # sinon         -> skl_toolset (toute la skill)
                  # + la liste permanente, toujours

Les trois lecteurs s'y branchent : `turn.scope` (le tableau envoye a l'API),
`tool_allowed` (le refus de la porte), `tools_list` (la vue du modele).
Un seul endroit decide du perimetre ; la palette et le refus ne peuvent plus diverger.

### 5.3 T2 — `turn.scope` : la coupe du reranker saute en tunnel

Si `skl_palette` repond un tunnel ouvert, le classement ne s'applique pas : l'outil de
l'etape reste, meme s'il n'est pas dans le haut du classement. Sans ca, la coupe a 30 %
peut retirer l'outil attendu et le tour est perdu.

### 5.4 T3 — `turn.tunnel` : l'avance, apres `tools`

Un corps neuf, famille TURN (donc dans `registry-engine.yaml`), et UNE ligne dans
`pipeline.yaml` apres `tools` :

    steps: facts, second, effort, scope, prompt, call, tools, tunnel, reply, note

Algorithme, a chaque tour :
  1 la skill armee a-t-elle `PERMANENT_TODO: true` ? sinon, ne rien faire, sortir 0.
  2 lire la ligne `[progress]` : son id, sa consigne, son outil, ses options.
  3 dans `turn.json .calls`, chercher au moins un appel de CET outil dont
     `status == "ok"` ET dont le texte de retour commence par `ok `.
     Aucun -> ne rien faire (l'etape reste ouverte, le tour continue).
  4 si la ligne porte `-- bytes: <chemin>@<taille>` : comparer la taille reelle du
     fichier a la taille notee a l'ouverture. Egale -> etape NON fermee, ecrire la
     trace `tunnel: no effect on <chemin>`, sortir 0. C'est la loi 1212 appliquee :
     on verifie avant l'effet, et un delta nul n'est pas un progres.
  5 fait complet : la ligne courante passe `[done]` ; la ligne suivante, si elle existe,
     passe `[progress]` et recoit sa marque `@<taille>` si elle porte `-- bytes:`.
  6 plus de ligne suivante : le plan est fini -> `ok done <skill>`, la boucle decharge
     la skill (loi 1009). La derniere etape porte `answer`, donc c'est deja dit.
  7 chaque avance laisse UNE ligne dans `state/trace.jsonl` via `engine.trace` :
     l'etape fermee, l'outil, la preuve (taille avant / apres). Sans trace, la
     validation n'est qu'une parole de modele.

### 5.5 T4 — `plan.*` fermes dans un tunnel

`plan.add`, `plan.change`, `plan.progress`, `plan.done` refusent quand la skill armee
porte `PERMANENT_TODO: true` et qu'une ligne `[progress]` existe : « la route avance par
la machine, pas par le plan » (loi 2404). La lecture reste ouverte.

### 5.6 T5 — les refus nommes (texts.yaml, section refusals)

    tunnel_route_open:  'REFUSED: the route advances by the machine, not the plan.'
    tunnel_one_tool:    'REFUSED: one tool per step, and that one is on the route line.'
    tunnel_no_effect:   'BOUND: the file did not move (bytes %s -> %s). The step stays open.'
    tunnel_step_shape:  'REFUSED: a route line is [mark] text -- tools: <one> [-- bytes: p@s] [-- max: n].'

Tout refus nomme la ligne fautive (loi 1309) : un refus muet est un bug deguise.

### 5.7 T6 — la pose validée

  - `skill_manage set_plan` : valide chaque ligne d'un plan permanent (les six regles
    du §4) et refuse en NOMMANT l'id et la regle. Aujourd'hui ces lignes sont du texte
    libre a 100 octets : rien n'y est verifie.
  - `doctor` : un controle de plus (loi 2409) — skill permanente : une seule
    `[progress]`, ≤ 12 etapes, chaque outil nomme declare ET porte, et pour un tunnel
    ouvert, la ligne designee existe encore.
  - `phone-tunnel` : sa derniere etape ne nomme aucun outil ; elle portera `answer`.

---

## 6. LE PLAN DE LA SKILL `create_spec`

Le tunnel de creation de spec. Il ne s'ouvre qu'apres §5 (le moteur) : sans avance sur
fait, cette route serait une liste de souhaits.

### 6.1 Le principe

Le modele ne choisit ni les sections, ni leur ordre, ni la position dans le fichier.
Il remplit des moules : une cible, un fait, une condition. Le moteur decide OU ca
s'ecrit ; le modele decide CE QUE ca dit.

L'outil d'etape rend `ok ` seulement quand SON etape est finie : tant qu'il reste du
travail, il rend `note ...` (ou `FAULT ...`), et l'etape reste ouverte. Le moteur ne
juge pas le contenu, il lit le fait. C'est ce qui permet une condition de couverture
(100 % des entrees documentees) sans aucun modele juge (loi 383).

### 6.2 Les neuf outils a ecrire (un corps, un geste, arguments fermes)

| outil | geste unique | arguments | rend `ok ` quand |
|---|---|---|---|
| `scaffold` | cree l'arborescence du plan | aucune (le plan d'arborescence est dans le corps) | chaque entree existe sur le disque |
| `document_entry` | une entree = une description courte | `path` (doit exister et etre dans l'arbre scanne), `description` (≤ 120 octets) | 100 % des entrees ont leur description |
| `naming_rule` | une regle de nommage, avec son role | `element_pattern`, `naming_rule`, `responsibility_comment` | les quatre portees sont couvertes (fichiers, types, fonctions, constantes) |
| `purpose` | ce que le logiciel fait | `input_fact`, `output_fact`, `problem_fact` | les trois champs sont poses, aucun mot creux |
| `rule_forbidden` | un interdit | `rule_category`, `forbidden_action`, `reason`, `mandatory_alternative` | le minimum de regles de securite est atteint |
| `flow_line` | un echange | `source`, `action_payload`, `target` (une ligne, topologie seule) | le flux est declare clos par l'operateur |
| `dependency` | un paquet tiers autorise | `package`, `version` (exacte), `justification` | chaque paquet de la liste porte sa version |
| `error_case` | un cas d'echec | `error`, `system_behaviour`, `code_or_log` | le minimum de cas est atteint, aucun try/catch vide |
| `section_append` | des assertions dans la section courante | `lines[1..5]` de `{target, action_fact, condition_or_error}` | la section atteint son plafond declare |

`section_append` ne prend NI section, NI chemin, NI offset : la ligne `[progress]` les
porte. Le corps ecrit, puis RELIT la section et rend ses octets reels plus le delta :
un delta nul est un `FAULT`, pas un succes. L'alternance write/read demandee par la
spec du Bureau est ainsi tenue sans second outil ni second tour.

Bornes de redaction : 1..5 assertions par appel, `-- max: 3` sur les sections de fin ;
`action_fact` 20..30 mots, au present ; les mots creux (« securise », « robuste »,
« optimal » sans objet) sont refuses en citant la ligne fautive.

### 6.3 La route

Etapes fixes, dans cet ordre. `read_file`, `skill_view` et `answer` sont permanents :
ils n'ont pas besoin d'etre ouverts par la skill.

    400: "PLAN create_spec : une spec qui decrit l'architecture, sans annotation"
    401: "[progress] lire le canon du projet -- tools: read_file"
    402: "[todo] lire la skill -- tools: skill_view"
    403: "[todo] poser l'arborescence -- tools: scaffold"
    404: "[todo] commenter chaque entree -- tools: document_entry"
    405: "[todo] conventions et roles -- tools: naming_rule"
    406: "[todo] raison d'etre -- tools: purpose"
    407: "[todo] interdits et alternatives -- tools: rule_forbidden"
    408: "[todo] flux de donnees -- tools: flow_line"
    409: "[todo] dependances epinglees -- tools: dependency"
    410: "[todo] cas d'erreur -- tools: error_case"
    411: "[todo] section 3 contrats -- tools: section_append -- bytes: work/spec.md@0"
    412: "[todo] section 4 etats -- tools: section_append -- bytes: work/spec.md@0"
    413: "[todo] section 5 tiers -- tools: section_append -- max: 3 -- bytes: work/spec.md@0"
    414: "[todo] rendre -- tools: answer"

Les sections 3..N et leur ordre sont graves dans la route ; le modele ne peut ni en
ajouter, ni en sauter, ni les renommer. Une section par etape, son titre dans la
consigne : `section_append` refuse un appel si la ligne courante ne porte pas son
numero de section.

### 6.4 Ce que chaque outil refuse (et qui le refuse)

  - `scaffold` : un chemin hors du plan d'arborescence ; un dossier deja present.
  - `document_entry` : un chemin qui n'existe pas ; une description vague ou > 120 octets ;
    une entree deja documentee (l'ecriture remplace, elle ne double pas — loi 1214).
  - `naming_rule` : une regle sans role ; un motif qui ne correspond a aucun fichier reel.
  - `rule_forbidden` : une regle sans alternative obligatoire ; une categorie hors liste.
  - `dependency` : une version non exacte ; une justification absente.
  - `section_append` : plus de 5 assertions (ou plus de `-- max:`) ; un `action_fact`
    hors bornes ; une section hors de la ligne courante ; un delta d'octets nul.

Tous ces refus sont dans le CORPS du corps (un `case ... refuse` qui nomme), pas dans
une consigne textuelle : une phrase ne tient nulle part (lois 383, 1803).

### 6.5 Ordre de pose de create_spec

  1 les neuf corps (un YAML chacun), sans les ouvrir a aucune skill ;
  2 la skill `create_spec` : TOOLS = les neuf, PLAN = la route, PERMANENT_TODO: true ;
  3 `doctor` sur la route (la touche T6) ;
  4 un essai reel sur un projet neuf, et la lecture de la trace.

Hors route, et assume : le WATCHER qui tient la section « arborescence » de la spec.
C'est un service systemd, pas une etape, et il n'a de sens qu'une fois l'arbre reel.

---

## 7. CHANTIER SEPARE : la(g,a) ET LE SCHEMA SUR ERREUR

Loi 304 : « la liste des tools envoyee a l'API porte EXACTEMENT UN element : la(g, a). »
Loi 305 : « g est le numero d'une ligne de la table ; a porte les arguments dans l'ordre
declare. » Le code fait l'inverse : `turn.scope` construit une fonction par outil, avec
son schema. Le canon est donc en faute contre 1807 sur ce point.

  - `la(g,a)` : un seul schema stable, un prefixe immuable (cache chaud), les outils
    disponibles changeant dans la liste des ids et non dans le schema. Touche
    `turn.scope`, `turn.tools`, `bridge.py`, `board.py`, `page.html`, le CLI.
  - Le schema sur erreur : sur un appel rate, le retour porte le code, l'argument fautif
    (`arguments.lines[2].action_fact`), le motif, le schema JSON complet de l'outil
    fautif et un exemple valide. Une fois par erreur, jamais deux tours de suite ; au
    2e echec, le toolset se reduit a l'outil cible plus `reply` (escalade).
    Point d'insertion : `shape_fail` et les refus de `run.sh`, bornes par `limits`.

Ne se fait PAS en meme temps que le tunnel : rayon trop large, et le tunnel n'en depend pas.

---

## 8. LES TROIS TROUS DU TELEPHONE (conserve de l'ancien rapport)

Ces faits ne sont pas du tunnel, mais ils etaient la raison du tunnel ; ils restent
ouverts et ils sont mesures.
  1 `bridge: host: 127.0.0.1` : le pont n'ecoute que la boucle locale. Meme avec un
    telephone parfait, il n'entre nulle part. Elargir l'adresse est une DECISION, pas un
    effet de bord : `tunnel_status` le dit, il ne le corrige pas.
  2 Le profil du telephone a disparu alors que l'interface est levee : pair connu, cle
    privee perdue. La sortie propre est `tunnel_down` puis `tunnel_up` ; la brique actuelle
    regenere les deux paires a chaque `up`, donc un `up` seul rend le telephone muet.
  3 `DNS = 1.1.1.1` dans le profil alors que `AllowedIPs` ne porte que 10.10.0.0/24 :
    le telephone envoie son DNS dans un tunnel qui ne le transporte pas.

---

## 9. OUVERT

  - La forme d'un refus d'etape (au-dela de `note` et `FAULT`) : une troisieme forme
    explicite (`BLOCKED`) ou les deux existantes suffisent ?
  - L'escalade de la spec du Bureau (1 rejet = erreur, 2e = toolset reduit a l'outil
    cible plus reply) : avec UN outil par etape, la reduction n'ajoute presque rien.
    A garder pour le chantier la(g,a), ou le modele peut choisir un mauvais id.
  - Le journal des rejets (erreur, argument fautif, schema injecte) : mesure du taux
    d'erreur par outil et par etape. Il n'existe pas encore.

---

*Fin. Un seul document pour le tunnel. Pour ajouter une idee, on ajoute une ligne avec sa
preuve — jamais un paragraphe.*
