# LA — LE CHAT ENTRE AGENTS : TA VISION, CONFRONTEE AU CODE ET AUX MESURES

Date : 16/10/2026 — auteur : Hermes (session hote) — etat : **ETUDE, a annoter**.
Relevé du code : **16/10 a 20h35** ; mesures : **20h40 UTC**. Le projet a bouge pendant l'ecriture :
une autre passe a commite deux fois ce soir (le plan reduit a deux tools, la chaine de l'entree) et
laisse neuf fichiers modifies non commites. Les references citees sont celles de ce releve-la.

---

## 0. TA VISION (16/10/2026, tes mots)

> « un fichier qui sert de blackboard avec une limite de taille de message, le nom de l'auteur et
> son destinataire purgé a l'arret de ce message est injecté dans une fenetre du head secondaire de
> l'agent. on ajoute un outil send_agent_chat qui permet aux agents de se parler entre eux. tous les
> agents sont nommés, ces noms sont stables et gravés en dur. lancer un sous agent c'est appeler
> jarvis, ou paul ; lui ecrire c'est envoyer un message a paul. dans cette fenetre a un offset
> precis est indiqué le nom de tous les agents en cours de travail et son PID de session et si
> possible ce qu'il fait, et se met a jour a chaque tour. c'est là que session.db doit devenir un
> livre avec des pages et non un fichier plat car une session = une page avec le nom de l'agent et
> le titre de la session. toute session meme celle d'un sous agent cree une nouvelle page dans
> cette table. ainsi recevoir un msg est automatisé et c'est comme un chat ou les messages
> défilent ; en plus l'agent principal ou tout autre agent sait ce que font les autres et qui est
> actif, pour bénéficier du prompt catching les noms sont a des offsets fixes ce qui change le pid.
> donc on aurait une fenetre qui affiche les tools de tous les agents, une fenetre pour les
> messages, une fenetre pour les noms le pid et le statut actif ou non actif. il faut aussi que
> chaque agent ait son propre log de tools. l'agent n'ecrit plus sa mémoire (je travaille avec un
> autre agent sur cette question). delegate_task devient aussi une skill cible avec une mission
> donc l'agent délégué charge la skill, fait sa recherche de doc, ecrit son todo et fait son
> travail, puis sleep comme les autres. en gros un agent démarré est en sommeil jusqu'a ce que le
> juge le reveille s'il n'a pas de tache. »

**Les pieces qu'elle nomme**, numerotees — c'est par ces numeros que j'ai repondu section 3 :

1. **un fichier unique** qui sert de blackboard ; 2. une **limite de taille** par message ;
3. le **nom de l'auteur** et son **destinataire** ; 4. la **purge** du message ;
5. l'injection dans une **fenetre du head secondaire** de l'agent ; 6. un outil **send_agent_chat** ;
7. les agents **nommes**, noms **stables et graves en dur** ; 8. lancer = **appeler un nom**,
   ecrire = **un message a ce nom** ; 9. une **fenetre des agents** : nom, PID, statut, ce qu'il
   fait, a offsets fixes, remise a jour a chaque tour ; 10. **sessions.db en pages** (une session =
   une page : nom de l'agent + titre) ; 11. une **fenetre des messages**, une **fenetre des tools de
   tous les agents**, et **un log de tools par agent** ; 12. **delegate_task** = une **skill cible +
   une mission**, puis **sleep** ; 13. un agent demarre **dort jusqu'a ce que le juge le reveille** ;
   14. la **memoire** : hors chantier (l'autre agent).

---

## 1. Ce que le code dit AUJOURD'HUI (releve du 16/10, 20h35)

| # | Fait | Ou je l'ai lu | Ce que ca decide |
|---|---|---|---|
| 1 | **LA PORTE EST UNIQUE.** La demande entre **une fois**, sur l'entree standard ; vide, le tour meurt en le nommant. Le pont est le seul lanceur. | `loop.sh`, `REQUEST=$(cat)` (l.771) ; `bridge.sh`, `turn()` | Tout message doit entrer par la, ou n'entre pas. Loi 469 : un tool, un canal. |
| 2 | **LE HEAD SECONDAIRE EST FRAIS A CHAQUE APPEL MODELE.** Il est rebati **dans** la boucle du tour, pas une fois par tour. | `loop.sh:877` (la boucle) et `:884` (`PLAN_TXT=$(read_second)`) | **Ta fenetre des messages peut defiler en cours de tour**, entre deux tools. C'est le fait qui rend ta vision faisable telle que tu la decris. |
| 3 | Mesure : **1 192 octets**, six sections, **chacune bornee par un plafond declare**. | `second.sh` (CAP_TASK, CAP_PLAN, CAP_STAMP, CAP_RESUME, CAP_TOOLS, CAP_SKILL) ; mesure du 20h37 | Une fenetre de plus = **une section de plus avec son plafond**, pas un fichier de plus. |
| 4 | **LA FENETRE D'HISTORIQUE EST GLOBALE.** Les vingt derniers echanges, **sans filtre d'auteur**. La base n'a **aucune colonne de session** ; l'echange vaut `MAX+1`, global. | `hist_window()` (`loop.sh:203`) ; schema reel de `sessions.db` ; `loop.sh:763` | Deux sessions se LISENT deja l'une l'autre. La page que tu demandes est ce qui manque pour **savoir qui parle**. |
| 5 | **LE TOUR N'EST PAS SERIALISE.** Le pont est un `socat … fork` : un processus par connexion. Le journal des tools et la liste des mots sont des fichiers **globaux tronques au depart de chaque tour** ; le mot d'arret est global. | `bridge.sh` (`fork`, `JOURNAL="…/work/journal.jsonl"`, `: > "$JOURNAL"`) | « Chaque agent a son propre log » **corrige ce fait** — et c'est le meme geste que la fenetre des tools. |
| 6 | **L'ECRITURE DU CORPS ECHOUE EN SILENCE.** | `db_add()` : `2>/dev/null \|\| :` | A corriger AVANT d'empiler des ecrivains (loi 502 : un silence n'existe pas). |
| 7 | **Les familles et les chemins.** `READ` sous la racine, `WRITE` sous l'espace du skill (`work/`), **`MANAGE` ne subit aucun controle de chemin** : la commande nomme son registre, le moteur ne juge que la forme. | `engine.sh`, `case "$FAMILY"` | `send_agent_chat` en MANAGE ecrit son blackboard ou sa commande le dit — pas de plomberie neuve. |
| 8 | **Le precedent d'un registre rendu en UNE ligne** : `signal_task.sh` lit le registre deja ecrit et rend une ligne. | `signal_task.sh` | Ta fenetre des agents est **le meme geste**, borne par section. |
| 9 | **Les outils permanents (courant)** : answer, ask, talk, kill, tools_list, **todo, progress**, skill_manage:view_skill/load_skill, **sleep** (loi 474 : un tour qui ne peut pas s'endormir ne peut pas attendre). | `la_config.yaml`, section `permanent:` | Ton point 13 (le sommeil) est **deja ouvert** ; les points 6 et 9 ne doivent PAS devenir permanents (le permanent se paie sur chaque palette). |
| 10 | **La table** : 69 lignes, ids **101 → 179**. Le prochain id libre est **180**. `178 = search_sessions`, `179 = load_memory`. | `la_tools.yaml` | Poser = **ajouter des lignes**, jamais renumeroter (loi 1019). |
| 11 | **La memoire a change de forme ce soir** : `sessions.yaml` ne vit plus (loi 1716) ; la memoire est une TABLE, le corps est `sessions.db` ; **le modele ne l'ecrit jamais** (lois 1700-1717). | `spec.yaml`, `SECTION : LA_MEMOIRE` | Tes pages vivent dans `sessions.db` — **le meme fichier que la passe memoire**. A coordonner, jamais a doubler. |
| 12 | **Le banc porte deja B1 a B22** (24 verdicts nommes). | `work/scripts/banc_tour.sh` | Tes verdicts commencent a **B23**. |

---

## 2. CE QUE J'AI MESURE (16/10, 20h40) — hors du projet, dans mon brouillon

Quatre mesures, des chiffres. Les scripts vivent dans mon brouillon
(`~/.hermes/cache/scratch/bb_worker.sh`, `bb_mesure.py`, `bb_mesure2.py`) : ils entreront dans
`work/scripts/` **le jour ou une de ces regles sera posee** (loi 1806 : une regle tenue par un
script s'ecrit dans le script).

### M1 — le blackboard : plusieurs ecrivains sur UN fichier

Geste mesure = celui de la maison : la ligne est construite dans une variable, puis ecrite par
**un seul `printf >> fichier`** (ce que la boucle fait deja pour ses registres). **8 ecrivains** en
parallele, 60 messages chacun, 3 essais, on garde le **pire** :

| Taille de la ligne | Lignes relues | Lignes **illisibles** |
|---|---|---|
| 1 000 o | 480/480 | 0 |
| 3 900 o | 480/480 | 0 |
| **4 096 o** (la borne de la maison) | **480/480** | **0** |
| 6 000 o | 480/480 | 0 |
| 8 192 o | 480/480 | **258** |
| 10 000 o | 480/480 | 261 |
| 16 384 o | 480/480 | 310 |

**Verdict : ton blackboard tient, a une condition qui a une valeur chiffree.** Sous 6 000 octets,
huit ecrivains qui ecrivent en meme temps ne se coupent **jamais** ; a 8 192 octets, **plus de la
moitie des lignes sont coupees** — au-dela de son tampon, le `printf` d'un shell ne part plus en un
seul `write()`. La borne de la maison (**4096**) passe avec une marge d'environ 1,5x : ce n'est pas
un hasard, c'est le meme chiffre que la porte du moteur.

### M2 — la purge par reecriture : la fenetre de perte

Le purgeur lit le blackboard, garde les dernieres lignes non lues, ecrit un temporaire et le met en
place (remplacement atomique). L'ecrivain, lui, ne prend **aucune** pause — le pire cas.

| Purge | Messages ecrits | **Perdus** |
|---|---|---|
| toutes les 5 ms | 4 000 | **154 (3,9 %)** |
| toutes les 50 ms | 4 000 | **37 (0,9 %)** |

**Verdict : la perte est reelle, elle a une taille, et elle ne peut pas se cacher.** Un message
ecrit entre la lecture du purgeur et la mise en place atterrit dans l'ancien fichier et **personne
ne le voit** — sauf que : un agent dont le filigrane est plus vieux que la premiere ligne gardee
**sait** qu'une tranche lui a echappe, et il le dit (loi 502). Et la perte **tombe a zero** si la
purge se fait quand **aucun ecrivain n'est eveille** — c'est **exactement** ce que ta fenetre des
agents donne a voir : **nom, PID, statut actif ou non actif**. Les deux pieces se tiennent l'une
l'autre.

### M3 — le head secondaire : ce qui bouge entre deux appels

Trois appels espaces de 1,2 s, mesures a 20h37 :

    == THE TASK ==                    20 o    1 ligne
    == THE LOADED SKILL PLAN ==       68 o    1 ligne
    == THE TIMESTAMP ==               43 o    1 ligne
    == THE LOCAL MODEL SUMMARY ==    141 o    1 ligne
    == THE TOOLS STATE ==            159 o    2 lignes
    == THE ACTIVE SKILL ==           623 o   11 lignes
    total                           1192 o

Le `diff` entre deux appels ne montre **qu'une seule ligne** : l'horodatage.

**Verdict : ton instinct est bon — le head secondaire est deja stable, et il ne coute qu'une ligne
a deplacer** (l'horodatage, section 3 sur 6, qui casse tout ce qui le suit).

### M4 — mais le cache casse PLUS HAUT, et c'est la que tout se decide

L'ordre exact de ce que le modele recoit (releve dans la boucle) :

    [head gele] [protocole] [portee] [etat] + head secondaire + fenetre + voix + demande
    + historique du tour + faits

- `head.yaml` (3 448 o) est **gele** — et c'est **pour le cache** qu'il l'est (lois 802-804) ;
- le **protocole** est un texte fixe ;
- la **portee** change des que le skill ou l'etape du plan change ;
- **l'etat change a chaque tool** (« lus / ecrits / outils : N »).

**Verdict — et il corrige mon propre conseil de la veille** : un bloc de noms place **dans le head
secondaire** est **deja** hors du prefixe cachable, parce que `etat` l'a casse avant lui. Ton
argument des « offsets fixes » demande donc autre chose que ce que tu decris : un **bloc gele de
noms au TOUT DEBUT** (la ou vit `head.yaml`, et pour la meme raison que lui), et **le vivant
apres** — pid, statut, ce qu'il fait. Le head secondaire, lui, est la place des **messages**, parce
qu'ils bougent.

---

## 3. Ta vision, piece par piece

### 1 et 2 — le blackboard unique, avec une limite par message

**Ce que le code dit** : rien n'interdit un fichier a plusieurs ecrivains ; le moteur ne juge que la
forme d'une ligne MANAGE (fait 7).

**Ce qui manque** : rien, **si la borne est tenue et si l'ecriture est UN seul geste**. La mesure M1
le chiffre : **4096 octets est sû r**, 6 000 passe encore, 8 192 casse. La borne de la maison est
donc **exactement** la bonne, et la ligne s'ecrit d'**un seul `printf`** — deux `echo` bout a bout
ne sont plus atomiques.

### 3 — le nom de l'auteur et son destinataire dans le message

**Ce que le code dit** : les deux champs se posent **par la commande**, horodates par le proc (lois
1214-1215).

**Ce qui manque** : rien de neuf. `from` **ne vient jamais du modele** : c'est le nom du tour, pose
par le lanceur (piece 7) ; `to` est l'argument, et la commande refuse un destinataire **inconnu en
nommant la liste des noms graves**.

### 4 — la purge

**Tes mots sont ambigus et c'est le seul endroit ou je ne peux pas deviner.** « purge a l'arret de
ce message » peut vouloir dire deux choses tres differentes :

- **(A) purge a la consommation** : le message disparait quand son destinataire l'a lu ;
- **(B) purge a la fin du tour de l'auteur** : le message ne survit pas au tour qui l'a ecrit.

(A) est un chat. (B) est un appel. Je recommande **(A)** — et la mesure M2 dit **comment** la faire
sans rien perdre : **quand personne n'est eveille**. Aucune purge ne peut etre un `rm` (lois
1200-1201) : purger, c'est **reecrire le blackboard sans les lignes lues**, d'un coup, par **un
seul** ecrivain.

### 5 — la fenetre des messages dans le head secondaire

**Ce que le code dit** : c'est **exactement** la bonne place — le head secondaire est rebati a
chaque appel modele (fait 2). Une section de plus, avec son plafond : **recevoir devient
automatique**, et l'agent n'a **aucun tool de lecture a nommer**. Les messages defilent entre deux
tools, dans le meme tour.

**Ce qui manque** : (a) le **filigrane** — `second.sh` **ne doit rien ecrire** (il est appele des
dizaines de fois par tour) ; c'est **la boucle** qui avance le filigrane du tour **une fois, a la
fin**, et qui le dit ; (b) le **nom de l'auteur en premiere ligne**, pour qu'un pair ne soit jamais
pris pour MOUSSA ; (c) **l'horodatage du head secondaire descend a la fin de sa section** — une
ligne, et tout ce qui suit devient stable (mesure M3).

### 6 — l'outil send_agent_chat

**Ce que le code dit** : MANAGE, le corps sur l'entree standard, le **destinataire en `enum`** —
l'engine refuse hors liste **en rendant la liste entiere**. Les noms sont donc une **declaration**
qui s'ajoute par MOUSSA (lois 206-208).

**Ce qui manque** : poser la ligne, et **la ou elle vit** : la palette du skill `agent` (qui porte
deja `delegate_task`), jamais dans les permanents (fait 9). Et **surtout pas** `mail_*` :
`skills/mail/` existe et veut dire **courriel** (imap/smtp). Ton nom, `send_agent_chat`, evite la
collision.

### 7 et 8 — les noms graves en dur, appeler par son nom

**Ce que le code dit** : `delegate_task` (id 110) ouvre deja un `loop.sh` avec `LA_DEPTH=1`, un
nombre de tours borne (1..6), `timeout 120`, et **ne lit que sa sortie standard**. Un enfant qui a
une question meurt avec elle.

**Ce qui manque** : (a) **le lanceur pose le nom** du tour (le geste de `LA_VOICE`, `LA_LOG_FILE`,
`LA_STOP_FILE`) — sans lui, aucun message ne se signe ni ne s'adresse ; (b) `delegate_task` doit
porter **le nom de l'appelant et le nom de l'enfant** ; (c) un enfant doit pouvoir **ecrire** au
blackboard : c'est **la skill cible** qui ouvre `send_agent_chat`, exactement ce que tu decris au
point 12.

**Ou vivent les noms** : trois endroits possibles — l'`enum` de la ligne du tool (le moins cher :
un nom s'ajoute en editant **une** ligne), une section `agents:` de `la_config.yaml` (mais son
en-tete dit « les adresses des engines, et les noms des secrets, **rien d'autre** »), ou un fichier
de declaration neuf (`config/agents.yaml`). **A trancher.**

### 9 — la fenetre des agents (nom, PID, statut, ce qu'il fait)

**Ce que le code dit** : `signal_task.sh` est le precedent (un proc qui lit et rend **une** ligne).
Les sources existent : `/proc` dit **vivant ou mort** (le PID est un fait de la machine) ; la page
(piece 10) dit **quel agent** ; le plan dit **ou il en est**.

**Ce qui manque** : un **collecteur borne** (une ligne par agent : nom, pid, statut, le dernier
tool, l'etape du plan), avec son plafond de section. Et cette fenetre rend **deux services de
plus**, tous deux mesures : elle rend la purge **sans perte** (M2), et elle dit **qui peut ecrire a
cet instant**.

**Sur ton argument de cache** : il est juste, mais sa place n'est pas dans le head secondaire —
mesure M4 en main. Le **bloc gele des noms** va au **tout debut** du prompt, et le **vivant** (pid,
statut, ce qu'il fait) vient apres.

### 10 — sessions.db : un livre avec des pages

**Ce que le code dit** : `sessions.db` a **une** table (`messages`) et **aucune** colonne de
session ; `exchange` est un compteur global (fait 4). La loi dit deja qu'une session est **un
registre** (1606-1607) et que le tour **se transcrit** (1712).

**Ce qui manque** : une **table des pages** — `id`, `agent` (le nom), `title`, `started_at`,
`ended_at`, `pid` — et le **lien** depuis chaque message. Une page s'ouvre a l'ouverture du tour
(donc **toute** session, sous-agent compris, ouvre la sienne : ton point), et **le titre vient de la
demande**, jamais du modele (lois 1214-1215).

**Ce qui n'est pas tranche et qui compte** : la **fenetre** (fait 4) devient-elle « les vingt
derniers echanges de MA page », ou reste-t-elle globale ? Mon avis : la page sert a **savoir qui
parle et qui fait quoi**, la fenetre **reste globale** — c'est le salon, et il est deja la. Dans les
deux cas, il faut **le dire** dans le head, sinon le modele ne sait pas qui il lit.

**Attention de chantier** : `sessions.db` est **le corps de la memoire** depuis ce soir (fait 11).
Cette piece se pose **avec** la passe memoire, pas a cote.

### 11 — les trois fenetres, et un log par agent

**Ce que le code dit** : le journal des tools est **global et tronque a chaque depart de tour**
(fait 5) ; les routes `/journal` et `/spoken` lisent ce fichier global.

**Ce qui manque** : le journal **par agent** (`work/journal-<nom>.jsonl`) et une **agregation
bornee** pour la fenetre des tools de tous les agents — une ligne par agent (dernier tool, heure,
compte), jamais le journal entier.

### 12 et 13 — le sous-agent par mission, et le sommeil jusqu'au reveil

**Ce que le code dit** : `delegate_task` **borne l'enfant a 120 s** et l'enfant **meurt a sa
reponse**. Le sommeil (id 177) existe, il est **permanent**, et il borne l'attente d'un tour
(15..180 s par pas de 15, refus en rendant la liste).

**Ce qui manque** : ce sont **deux dessins**, et je ne les confonds pas :

- **Dessin A — l'agent resident.** Le tour, au lieu de fermer sur `answer` quand il n'a rien a
  faire, **nomme `sleep`**, se reveille, **relit sa fenetre de messages** (fraiche a chaque appel :
  fait 2) et reprend ou se rendort. Le reveil **est** la fenetre : aucun canal neuf, aucune demande
  neuve. Les bornes existantes bornent l'agent resident ; l'anti-boucle juge sur (tool, cible) et
  attrape le « je verifie, rien de neuf ». **Le PID ne change pas** tant que le tour vit.
- **Dessin B — la page sans processus.** L'agent n'est qu'une **page** ; le processus nait a chaque
  reveil et meurt a `answer`. Le PID **change** a chaque reveil — c'est **ta propre phrase** (« les
  noms sont a des offsets fixes, ce qui change c'est le pid »), et elle pointe le dessin B.

**Le juge n'a pas le meme role dans les deux** : en **A**, le sommeil suffit presque (il ne reste
que le cas « l'agent est mort ») ; en **B**, le juge est **le** declencheur, et un reveil est une
**demande** — ce que le canon dit deja (lois 1542-1553 : le veilleur propose, le engine decide ; un
reveil n'elargit jamais le perimetre). **A trancher.**

### 14 — la memoire

Hors chantier : elle est travaillee par une autre passe (lois 1700-1717, posees ce soir). Rien dans
cette etude n'y touche. Point a surveiller : le tool `note` (id 108) ecrit dans `memory/`, un
vestige — si la passe memoire le retire, ce n'est **pas** a moi de le faire.

---

## 4. Les points durs

### a. LE BLACKBOARD A PLUSIEURS ECRIVAINS, ET SA PURGE

La loi 1213 dit : « **un seul ecrivain a la fois** : la boucle tient le tour, le manager sa
section. » Un blackboard unique **viole la lettre** de cette loi et **respecte son esprit** : la
mesure M1 le prouve sous 6 000 octets, avec un seul `write()` par message. Trois formes de purge, et
il faut **en choisir une, par toi** :

| Forme | Ce qu'elle donne | Ce qu'elle coute |
|---|---|---|
| (i) append-only, **jamais purge** | le plus simple ; aucun ecrivain ne touche ce qu'un autre a ecrit | le fichier grossit sans fin (loi 1604 : « un fichier qui grossit tout seul finit illisible ») |
| (ii) purge par **le dernier lecteur**, **quand aucun agent n'est eveille** | la perte mesuree **tombe a zero** (M2 : 3,9 % sinon) | il faut la fenetre des agents pour savoir qui est eveille — les deux pieces se tiennent |
| (iii) purge par **le dernier ecrivain** | pas de collecteur separe | meme fenetre de perte, et le dernier ecrivain n'est pas forcement celui qui sait |

**Mon avis** : (ii). Le filigrane de chaque agent vit dans **son** fichier (un ecrivain par
filigrane), et si une tranche a echappe a un agent, **il le dit** — c'est la loi 502, et c'est la
seule chose qui rend la perte tolerable.

### b. LE CACHE : LE BLOC GELE VA AU DEBUT, PAS DANS LE HEAD SECONDAIRE

C'est la mesure M4, et elle est plus severe que mon premier conseil : le prefixe cachable
s'arrete **avant** le head secondaire, parce que `etat` change a chaque tool. Donc :

    [head gele] [bloc gele des NOMS] [protocole] [portee] [etat]
    [head secondaire : messages] [fenetre] [demande] [historique] [faits]

Le stable **devant**, le vivant **derriere** — et l'horodatage du head secondaire descend a la fin
de sa section (M3). Sans ca, un bloc de noms « a offsets fixes » ne fait gagner **rien**.

### c. LE POIDS : TROIS FENETRES DE PLUS, A CHAQUE APPEL MODELE

Le head secondaire est rebati **a chaque appel modele** (fait 2). Mesure : 1 192 octets aujourd'hui.
La fenetre d'historique, elle, porte **vingt echanges bruts** — c'est de loin le poste le plus
lourd. Regle proposee : **une fenetre = une section = un plafond declare**, et **rien n'entre sans
son plafond** (loi 826 : la RAM se rembourse en jetons, et l'inverse est vrai aussi).

### d. L'ECRITURE MUETTE DU CORPS (fait 6)

`db_add()` avale ses erreurs. Empiler des ecrivains sur une base dont l'echec est muet, c'est
construire sur du sable. **A corriger avant le reste** — et c'est un verdict de banc, pas une
opinion.

---

## 5. L'ordre que je propose (rien ne se pose sans ta validation)

1. **Le nom du tour** (`LA_FROM`, pose par le lanceur) + **ou vivent les noms**.
2. **Le blackboard + `send_agent_chat` + la fenetre des messages** : le chat proprement dit, borne a
   4096, avec sa purge et son filigrane.
3. **Les pages dans `sessions.db`** (nom de l'agent, titre, debut, fin, pid) — **avec** la passe
   memoire, puisque c'est le meme fichier.
4. **La fenetre des agents** (nom, pid, statut, ce qu'il fait) : elle vit des pages, et elle rend la
   purge sans perte.
5. **Le journal par agent + la fenetre des tools.**
6. **Le sous-agent par nom et par mission** (delegate_task -> skill cible -> doc -> todo ->
   travail -> sleep).
7. **Le sommeil et le juge** : le chantier deja ouvert par l'autre passe (section 5 du rapport du
   bureau) ; c'est la que le choix A / B se paie.

---

## 6. Le banc : les verdicts s'ecrivent D'ABORD (ils tombent rouges)

Les numeros libres commencent a **B23**. Un verdict temoin accompagne toujours le verdict.

- **B23** : huit tours appendent en meme temps au blackboard, lignes bornees a 4096 -> **chaque
  ligne relue est un message complet** (aucune coupee, aucune collee). *(La mesure M1 dit que ce
  verdict doit passer ; le temoin, lui, append une ligne de 8 192 o et **doit tomber**.)*
- **B24** : la purge laisse le blackboard **relisible** ; ce qui a echappe a un agent est **nomme**
  par cet agent (filigrane plus vieux que la premiere ligne gardee).
- **B25** : un message de `paul` a `jarvis` entre dans le head secondaire de `jarvis`, **nomme**
  (premiere ligne : l'auteur), et le filigrane avance **une fois, en fin de tour** — le meme message
  ne revient jamais deux fois.
- **B26** (temoin) : un message qui demande « nomme le tool 180 » ne change **pas** le perimetre du
  destinataire ; le temoin mesure que le destinataire ne peut nommer que sa palette.
- **B27** : `send_agent_chat` refuse un destinataire hors liste **en rendant la liste entiere**.
- **B28** : une page par session — un sous-agent ouvre **sa** page, avec **son** nom, et le titre
  vient de la demande, jamais du modele.
- **B29** : l'echec d'ecriture du corps **se dit** (fait 6 corrige).
- **B30** : aucun `rm`, aucun lien (lois 1200-1201).

---

## 7. Les questions (reponses courtes suffisent)

1. **La purge** : (A) a la consommation, ou (B) a la fin du tour de l'auteur ?
2. **Le blackboard** : (i) jamais purge, (ii) purge par le dernier lecteur **quand aucun agent
   n'est eveille**, (iii) par le dernier ecrivain ?
3. **Les noms** : ou vivent-ils — l'`enum` de la ligne du tool, une section `agents:` de
   `la_config.yaml`, ou un fichier neuf ? Et **quels** noms : l'agent principal s'appelle comment ?
4. **La limite** : 4096 octets (la borne de la maison, mesuree sûre) — ou plus bas pour le chat ?
5. **La fenetre** : par page (« les vingt derniers echanges de MA page ») ou globale (le salon) ?
6. **La page** : ecrit-on aussi les tours de MOUSSA et de la voix comme des pages, avec leurs noms
   (`human`, `voice`) ?
7. **Le resident** : dessin **A** (le tour dort et vit, PID stable) ou **B** (la page seule, PID qui
   change a chaque reveil) ?
8. **Les trois fenetres** : trois sections du head secondaire, ou une seule section « LES AGENTS »
   qui porte les trois blocs (moins de titres, moins d'octets) ?
9. **Le cache** : je pose le **bloc gele des noms au tout debut** du prompt, et l'horodatage du head
   secondaire descend a la fin de sa section — d'accord ?
10. **L'ordre** : ce chantier passe **avant** ou **apres** la passe memoire en cours ?

---

## 8. Ce que je n'introduis PAS

- pas de broker, pas de demon, **pas de port neuf** (loi 469) ; le blackboard est un **fichier**, la
  fenetre est **le head secondaire** ;
- pas de second canal : un message entre par la **meme** porte que la voix et que la photo ;
- pas de tool de **lecture** de chat : recevoir est **automatique** (c'est ta vision, et le code la
  porte) ;
- **aucun `rm`** : la purge est une **reecriture**, pas une suppression (lois 1200-1201) ;
- rien dans **la memoire** : autre passe, autre chantier.
