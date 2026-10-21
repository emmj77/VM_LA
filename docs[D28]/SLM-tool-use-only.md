# LE SLM TOOL-USE ONLY

## Un modèle de 1 à 2 B qui ne fait qu'un seul geste : émettre un appel d'outil

    Source          conversation « Création d'un agent GUI autonome »
                    share.gemini.google/FQ6pM3woQzpj — 31 échanges
    Règle de lecture [Qn] = ce que MOUSSA a dit au tour n : cela engage le projet.
                    (Rn) = ce que l'assistant a répondu : une proposition, jamais une mesure.
                    Sans marque = proposition d'ingénierie de ce document, à trancher.
    Statut           document de conception. Rien n'est entraîné.
    Note             le format d'appel de la section 1 bis a été vérifié sur un serveur
                     llama.cpp réel le 18/10/2026 (mesures M 21 à M 23).

---

## 0. La thèse

Un modèle de langage généraliste porte dans ses poids la poésie, le code, la conversation et
trente langues. On lui demande ici un seul geste : **lire un état, rendre un appel d'outil**.

L'idée n'est pas de brider un gros modèle par un prompt, mais de **prendre un modèle de base de
1 à 2 milliards de paramètres et de l'entraîner sur ce seul geste** [Q26][Q27][Q28]. Toute sa
capacité passe dans une chose : comprendre la demande (français, anglais) et la traduire en
`id d'outil + arguments`, au format OpenAI, pour que le moteur local n'ait pas à se battre avec
le protocole [Q29].

Trois conséquences, et ce sont elles qui tiennent le document :

1. **Le schéma est unique et ne change jamais** [Q23] : il tient dans le prompt système et vit
   dans le cache. Le modèle ne réapprend rien d'un tour à l'autre.
2. **La réponse est un outil elle aussi** [Q26][Q28] : parler, c'est appeler l'outil `talk`.
   Il n'existe qu'une seule primitive de sortie dans tout le système.
3. **Le modèle ne connaît pas le code** [Q31] : il ne touche jamais une chaîne de shell. Le
   code reste dans les fiches YAML, que le moteur exécute.

---

## 1. Le contrat : un schéma unique, immuable

### 1.1 Ce que le modèle voit, choisit, ignore

| | contenu |
|---|---|
| **voit** | le schéma unique (une fois, en tête, donc en cache) [Q23] |
| **voit** | l'état du tour : le retour du dernier outil + le message de l'humain |
| **choisit** | l'**identifiant numérique** de l'outil [Q21][Q22] |
| **choisit** | les **arguments**, pris dans la liste que l'outil déclare [Q24] |
| **ignore** | la commande shell, ses options, son ordre d'assemblage [Q22] |
| **ignore** | toute coordonnée d'écran (c'est l'objet du second document) |

### 1.2 La forme, formalisée

Forme proposée, à figer une fois pour toutes. `id` est le numéro de l'outil ; `args` est plat.

    {"name": "tool",
     "arguments": {"id": 301, "args": {"x1": 100, "y1": 50, "x2": 200, "y2": 80}}}

    {"name": "tool",
     "arguments": {"id": 1, "args": {"text": "Le carré est tracé, je vérifie la fermeture."}}}

`id: 1` réservé à `talk` est une proposition : la conversation parle d'un « outil de réponse »
sans lui donner de numéro [Q28]. Le numéro est libre ; il doit être **figé avant l'entraînement**,
puisque le modèle l'apprend par cœur.

### 1.3 Ce que le moteur fait du numéro

    appel du modèle ──▶ moteur ──▶ table des outils (YAML) ──▶ fiche de l'outil 301
                                                             │
                                                             ├─ description
                                                             ├─ arguments valides
                                                             └─ commande + placeholders
                                                                        │
                                                            arguments injectés
                                                                        │
                                                                   shell (sh)

Le moteur reconnaît le numéro parce qu'il tient la table [Q22]. Il va chercher la fiche, place
les arguments là où ils doivent aller, et envoie la commande au shell [Q22]. **Le modèle n'a
jamais vu cette fiche.**

### 1.4 Pourquoi l'immuabilité est le cœur du dispositif

Un schéma qui ne bouge pas est un schéma que le `prompt caching` garde indéfiniment [Q23].
Ajouter un outil, c'est **ajouter un YAML** : le prompt ne change pas d'un octet, le modèle
invoque le nouvel identifiant immédiatement [Q23]. Le catalogue peut grandir sans coût de
contexte, et c'est ce qui rend le second document (des milliers d'éléments d'écran) viable.

---

## 1 bis. Le format : standard sur le fil, nôtre au fond

C'est le point que Moussa a corrigé : **on ne réinvente pas un format, on détourne le format
OpenAI**. Le fil reste strictement standard (sinon `llama.cpp` refuse ou se tait) ; c'est le
**sens** qu'on met derrière qui nous appartient, et ce sens vit dans le harnais.

### 1 bis.1 Ce que le standard prévoit, et ce qu'on en fait

| le standard OpenAI | notre usage | où ça se décide |
|---|---|---|
| `tools[]` : N fonctions, chacune avec un nom et un schéma | **une seule** fonction, nommée `tool` | la requête |
| `arguments` : les propriétés déclarées de la fonction | `{id: entier, args: objet}` | le schéma, figé |
| `message.content` : la réponse en texte | **toujours vide** | la réponse |
| `tool_calls[]` : zéro, un ou plusieurs appels | un ou deux : **action**, puis **parole** | la réponse |
| le catalogue change à chaque requête | **jamais** : il vit dans le moteur | le harnais |
| l'exécution, c'est l'affaire du client | résolution `id → YAML → sh` | le harnais |

Autrement dit : le standard offre **deux canaux** (du texte libre, et des appels d'outils). On les
**fusionne en un seul**. Tout ce que l'agent veut dire ou faire est un appel à `tool`, et le
harnais décide ce que signifie l'identifiant.

Pourquoi garder le standard malgré cela : parce que `llama.cpp` fait le **parsing** à notre place.
Sans lui, il faudrait découper du texte à la main, reconnaître un bloc JSON, gérer les espaces,
les coupures de flux. Avec lui, la réponse arrive déjà structurée.

### 1 bis.2 La forme exacte sur le fil (vérifiée sur la machine)

Requête :

    POST /v1/chat/completions
    {
      "model": "local",
      "tools": [{"type": "function", "function": {
          "name": "tool",
          "description": "Unique outil : identifiant + arguments.",
          "parameters": {"type": "object",
                         "properties": {"id":   {"type": "integer"},
                                        "args": {"type": "object"}},
                         "required": ["id", "args"]}}}],
      "tool_choice": "auto",
      "parallel_tool_calls": true,
      "messages": [ ... ]
    }

Réponse réelle du serveur local [M 21] (LFM2.5-1.2B-Instruct Q4_K_M, 12 288 de contexte) :

    "finish_reason": "tool_calls",
    "message": {"content": "",
                "tool_calls": [{"id": "18pdBQZfpwBwvgyomPRnngWf2BkvC07e",
                                "type": "function",
                                "function": {"name": "tool",
                                  "arguments": "{\"id\":1,\"args\":{\"x1\": 100, ...}}"}}]}

Trois choses à retenir de cette réponse, et aucune n'est dans la conversation :

1. **`arguments` est une chaîne**, pas un objet : le harnais doit la parser (et refuser si elle est
   invalide — c'est le premier point de contrôle).
2. **`id` est fabriqué par le serveur** (chaîne opaque). Le harnais doit le **renvoyer** dans le
   message `role: "tool"` correspondant, sinon le tour suivant est refusé.
3. **`content` est vide** : c'est exactement ce qu'on veut — un modèle qui ne parle pas hors
   schéma.

### 1 bis.3 Ce que `llama.cpp` impose, et qui change le design

| contrainte | conséquence |
|---|---|
| `--jinja` est nécessaire pour les appels d'outils | le serveur doit être lancé avec ; à figer dans l'unité systemd |
| `parallel_tool_calls` est **désactivé par défaut** | sans `true`, **jamais deux appels** dans un tour : la paire action + parole est impossible |
| format *natif* si le template est reconnu (Hermes 2 Pro, Llama 3.x, Qwen 2.5…), sinon *Generic* | un template maison tombe en *Generic* : plus de tokens, moins efficace |
| le template est celui du modèle | le SLM doit être entraîné **exactement** sur le texte que le template produira |
| `-> /props` expose le template | on peut le relire, donc le vérifier, à chaque démarrage |

Mesuré [M 22] : avec `parallel_tool_calls: true`, le serveur accepte la demande, mais le modèle
testé n'a rendu **qu'un** appel. Ce n'est pas un défaut du format : c'est le modèle qui n'a jamais
appris à en rendre deux. Conclusion : **la paire action + parole ne s'obtient pas par
configuration, elle s'obtient par entraînement.** C'est un argument de plus pour le SLM dédié.

### 1 bis.4 La décision qui découle de tout ça, et qu'il faut prendre avant d'écrire une ligne

Le **dialecte du template** fait partie du contrat du modèle. Trois options :

| option | avantage | coût |
|---|---|---|
| **Hermes 2 Pro** (handler natif de llama.cpp) | parsing natif, peu de tokens, déjà éprouvé | il faut entraîner le SLM sur ce dialecte exact |
| template **maison** | liberté totale | tombe en *Generic* : plus de tokens, plus fragile |
| template du modèle de base, non modifié | rien à faire | ne contient pas deux appels d'outils |

Recommandation : **Hermes 2 Pro**, et le corpus est écrit dans ce dialecte. C'est le seul chemin
qui garde le parsing natif *et* permet deux appels.

---

## 2. Pourquoi un modèle de base, et pas un modèle déjà dressé à l'appel d'outil

Ce que la conversation tranche [Q27] : un modèle déjà entraîné au *function calling* a déjà
appris **une autre manière** — répondre en texte libre, couper ses appels, commenter. Ses
réflexes de bavardage reviennent dans les cas limites. Moussa en conclut qu'il faut **partir
d'un modèle de base** et l'entraîner à ne fonctionner que de la façon décrite.

Ce qu'il faut distinguer, et que la conversation laisse implicite :

| lecture de « partir de zéro » | ce que cela implique |
|---|---|
| **pré-entraînement complet** depuis des poids aléatoires | un corpus de dizaines de milliards de tokens ; hors de portée d'une RTX 3060 et sans rapport avec le but |
| **modèle de base publié** (ayant seulement appris à prédire le token suivant), réentraîné sur ce seul geste | la lecture réaliste, et celle qui correspond à « il ne sait faire qu'une seule chose » [Q27] |

La seconde est la seule praticable. Le point à trancher est le **choix du modèle de base** : il
faut un socle qui comprend le français, et c'est là que la taille compte (section 4).

---

## 3. Le périmètre cognitif : français, anglais, et le geste

Décision de Moussa [Q31] : **deux langues seulement** (français, anglais) et **l'appel d'outil**.
Pas de code, pas de multilinguisme, pas de littérature. « Il connaît même pas de code parce que
de toute façon il touche pas aux chaînes » [Q31].

Ce que cela donne dans le corpus d'entraînement :

- toute consigne, tout état, toute réponse textuelle : **français ou anglais** ;
- **aucune** commande shell, aucun extrait de code, aucun JSON hors du schéma ;
- le modèle n'apprend pas à écrire un script : il apprend à **nommer un outil**.

**Une réserve d'ingénierie, à ne pas confondre avec la décision.** Un modèle de base publié a
déjà vu du code et d'autres langues dans son pré-entraînement. Un entraînement sur FR/EN ne
*retire* pas ces connaissances : il les rend improbables, pas impossibles. Si l'interdiction doit
être **certaine**, elle ne peut pas venir des poids — elle vient de l'énumération (le harnais ne
donne que le schéma unique ; il n'y a pas de champ où écrire du code). L'entraînement sert à la
**qualité**, le harnais sert à la **garantie**.

---

## 4. La taille : 1 à 2 B, pas 0,5 B

Arbitrage de Moussa [Q28] : sous 0,5 B, les modèles « sont quand même pas très performants, même
en termes de juste parler » ; il vise **1 B ou 2 B**. Le plancher existe pour une raison précise :
le modèle doit **comprendre la demande** avant de choisir un outil — sans quoi il ne manipule
rien, il devine [Q28].

Ordres de grandeur pour situer (à **mesurer**, ce ne sont pas des mesures) :

| taille | poids en Q4 | ce qu'on attend | verdict |
|---|---|---|---|
| 0,5 B | ~0,3 Go | dérive sur les consignes composées | écarté par Moussa [Q28] |
| 1 B | ~0,7 Go | comprend FR/EN, tient le schéma | plancher |
| 2 B | ~1,3 Go | marge de compréhension, reste rapide | cible |

Sur 12 Go de VRAM, les deux tiennent avec de la place pour le cache KV, et laissent les autres
cartes et modèles tranquilles. La vitesse attendue est de l'ordre de plusieurs centaines de
tokens par seconde (R26) : c'est ce qui fait disparaître la latence de l'agent — mais c'est à
mesurer sur la 3060, pas à croire.

---

## 5. La boucle : deux appels, deux retours

### 5.1 La séquence

    1. le moteur envoie l'état (retour du dernier outil + message humain)
    2. le modèle rend UN OU DEUX appels, dans le même tour :
         ├─ l'appel d'ACTION   id 301  args {…}          (facultatif)
         └─ l'appel de PAROLE  id 1    args {text: …}    (toujours)
    3. le moteur exécute l'action, affiche le texte
    4. le moteur rend un retour pour CHAQUE appel :
         ├─ retour de l'action : le résultat (ou l'identifiant de processus)
         └─ retour de talk     : le message de l'humain, ou vide
    5. on revient en 1.

« Soit il l'envoie vite parce qu'il a rien à dire, soit il l'envoie avec ce qu'il a à dire
dedans » [Q28] : `talk` part **toujours**, quelquefois avec un texte vide.

### 5.2 Pourquoi la parole est un outil (la vraie raison)

Parce que `llama.cpp` — comme tout runtime qui suit le format — attend un contrat strict : **un
appel d'outil appelle un retour d'outil**. En faisant de la réponse finale un outil, on ne casse
jamais ce contrat, et **on n'a plus de boucle complexe à écrire** [Q29] : le moteur lit un
identifiant, exécute ou affiche, rend un retour. Rien d'autre.

Effet de bord, et il est précieux : **le message de l'humain arrive dans le retour de `talk`**
[Q29], pas comme un tour d'utilisateur. La conversation ne contient donc que des appels et des
retours d'outils — l'historique reste homogène, et le cache reste valable.

### 5.3 Le problème que cela règle : le blocage

Si une réponse humaine devait attendre le retour d'un script de trente secondes ou d'une minute,
elle arriverait une minute plus tard — ou il faudrait une machinerie asynchrone compliquée [Q30].
La séparation `talk` / action règle cela : **on parle tout de suite, le travail continue**.

| situation | ce que fait le moteur | ce que voit le modèle |
|---|---|---|
| le modèle a parlé | affiche le texte, retour `talk` = message humain ou vide | son texte, puis la suite |
| le modèle agit (court) | exécute, retour = résultat | le résultat |
| le modèle agit (long) | retour **immédiat** : « lancé, processus X » | il peut parler, puis interroger plus tard |
| rien à dire | retour `talk` vide, aucun affichage | le tour suivant |

---

## 6. Le contrat inverse : ce que le moteur doit garantir

Le modèle est petit : c'est le moteur qui porte la robustesse. Quatre règles que la conversation
nomme déjà :

| cas | ce que le moteur fait | source |
|---|---|---|
| argument **inconnu** de la fiche | refuse, ne corrige pas, renvoie l'erreur | [Q24] |
| argument **trop nombreux** | renvoie **un exemple d'argument valide** | [Q24] |
| identifiant d'outil inconnu | refuse et rappelle que la table est la seule vérité | [Q22] |
| schéma | immuable, en tête de prompt, jamais régénéré | [Q23] |

Ce que cela veut dire en pratique : **le refus est une donnée d'entraînement**. Chaque refus rend
un tour de correction au modèle ; c'est ainsi qu'il apprend à rester dans la liste.

---

## 7. La donnée d'entraînement

**La conversation ne tranche pas ce point** : elle se termine sur la question de la méthode de
génération (R31). Ce qui suit est donc une proposition, pas une décision.

### 7.1 Le principe

Un exemple = *(état du tour)* → *(un ou deux appels)*. Rien d'autre. L'état est exactement ce que
le moteur enverrait : le retour du dernier outil, plus le message de l'humain.

Le point technique qui décide de la réussite : **la perte ne se calcule que sur l'appel produit**
(les tokens de l'appel d'outil), jamais sur l'état reçu. Un modèle entraîné à reproduire l'état
apprend à recopier le contexte, pas à agir.

### 7.2 Les familles d'exemples à couvrir

| # | famille | ce que le modèle apprend |
|---|---|---|
| 1 | `talk` seul | parler sans agir |
| 2 | action seule | agir sans commenter |
| 3 | action + `talk` | faire et dire, dans le même tour |
| 4 | `talk` vide | se taire quand il n'y a rien à dire |
| 5 | argument refusé, puis correction | lire un refus et se corriger |
| 6 | argument trop nombreux, exemple fourni | se conformer à l'exemple |
| 7 | retour de script long | parler d'abord, interroger ensuite |
| 8 | demande ambiguë | demander, **ne pas inventer d'outil** |
| 9 | hors périmètre | refuser par `talk`, sans sortir du schéma |
| 10 | les deux langues, à parts égales | FR et EN, sans préférence |

### 7.3 Ce que le corpus ne contient jamais

du code, du markdown décoratif, des réponses en texte libre hors schéma, d'autres langues, des
appels à des outils inexistants, des arguments hors liste, des identifiants de fantaisie.

### 7.4 La méthode de génération (ouverte)

Trois voies, à trancher : (a) générer les états depuis les fiches YAML réelles et les faire
répondre par un gros modèle, puis filtrer par exécution réelle ; (b) rejouer des traces réelles
d'usage et les re-formater ; (c) hybride — (a) pour le volume, (b) pour la distribution réelle.
Le filtre décisif est le même dans les trois cas : **un exemple n'entre dans le corpus que si son
appel passe le validateur du moteur**.

---

## 8. L'évaluation

Aucune de ces mesures n'existe dans la conversation ; ce sont les seules qui diront si le modèle
est bon.

| mesure | seuil de travail | pourquoi |
|---|---|---|
| JSON valide et conforme au schéma | ~100 % | un seul schéma : aucune excuse |
| identifiant présent dans la table | ~100 % | sinon le moteur refuse |
| arguments tous valides du premier coup | à suivre, > 90 % visé | c'est la qualité du geste |
| bon outil pour l'état donné | mesuré par famille | la compréhension, pas la syntaxe |
| aucune fuite de texte hors schéma | 0 toléré | c'est la définition du modèle |
| stabilité sur 50 tours | pas de dérive | le cache et l'habitude |
| tokens/s sur la 3060 | à mesurer | la latence de l'agent |

---

## 9. Les points ouverts

1. **Le dialecte du template** : Hermes 2 Pro (recommandé) ou maison — c'est la première décision,
   parce que le corpus doit être écrit dans ce dialecte (section 1 bis.4).
2. **Le modèle de base** : lequel, et avec quel tokenizer (un tokenizer qui découpe mal les
   chiffres coûte cher dans un schéma d'identifiants).
3. **Le sens exact de « partir de zéro »** : modèle de base réentraîné (réaliste) ou
   pré-entraînement complet (hors de portée) — section 2.
4. **Le numéro de `talk`** et son placement dans la table.
5. **Un appel ou deux** : `talk` est-il toujours émis, ou seulement quand le modèle a quelque
   chose à dire ? La conversation dit « toujours » [Q28] ; le coût d'un appel vide est nul, mais
   c'est à figer avant l'entraînement — et il faut `parallel_tool_calls: true` [M 22].
6. **La méthode de génération des données** — section 7.4.
7. **La quantification** au service (Q4/Q5/Q8) et son effet sur le respect du schéma.
8. **La longueur de contexte** : un état d'écran peut être gros ; il faut la borner, sinon le
   modèle se noie et le cache se casse.
9. **Le sort des refus** : sont-ils générés par le moteur en production et réinjectés comme
   données (boucle d'apprentissage), ou seulement écrits à la main ?

---

## 10. Fiche de synthèse

| | |
|---|---|
| **nature** | SLM spécialisé, un seul geste : émettre un appel d'outil au format OpenAI |
| **socle** | modèle de base 1–2 B, réentraîné ; pas un instruct, pas un modèle déjà dressé à l'appel d'outil [Q27] |
| **schéma** | unique, immuable, en tête de prompt, en cache [Q23] |
| **format** | OpenAI sur le fil (`tools[]`, `tool_calls[]`, `finish_reason: tool_calls`) ; détourné au fond : un seul outil, `content` toujours vide, catalogue dans le moteur [M 21][M 22] |
| **sortie** | `id` d'outil + arguments plats ; la parole est l'outil `talk` [Q26][Q28] |
| **langues** | français, anglais, et rien d'autre ; aucun code [Q31] |
| **ce qu'il ignore** | la commande shell, les coordonnées d'écran, le catalogue réel |
| **qui exécute** | le moteur : table de YAML, arguments validés, shell [Q22][Q24] |
| **qui garantit** | le moteur, par l'énumération et le refus ; pas les poids |
| **boucle** | un état → un ou deux appels → un retour par appel ; `talk` porte le message humain [Q29] |
| **anti-blocage** | `talk` immédiat + retour « lancé, processus X » pour les scripts longs [Q30] |
| **point non tranché** | la méthode de génération du corpus d'entraînement |

---

## Registre des mesures [M n]

Numérotation commune avec `API-visuelle-de-l-ecran.md`. Faites sur cette machine le 18/10/2026 ;
les autres numéros (M 1 à M 20) y sont définis.

| # | mesure | valeur | moyen |
|---|---|---|---|
| M 21 | réponse réelle d'un serveur llama.cpp sur le schéma unique | `finish_reason: "tool_calls"`, `content: ""`, `tool_calls[0].id` = chaîne opaque générée par le serveur, `function.name` = `tool`, `arguments` = **chaîne** JSON | `POST /v1/chat/completions` sur 127.0.0.1:8088 (LFM2.5-1.2B-Instruct Q4_K_M, n_ctx 12288) |
| M 22 | deux appels dans un tour | `parallel_tool_calls: true` accepté, mais **un seul** appel rendu par ce modèle | même appel |
| M 23 | template exposé | présent, 1 783 caractères, gère `tools` | `GET /props` |
