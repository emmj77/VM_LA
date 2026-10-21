# LES MICRO-MODÈLES DE VM_LA — CE QUI EST SUR LA MACHINE, CE QUI RESTE À ESSAYER

Relevé du 16/10/2026, **banc du 17/10/2026** sur le Z4 G4 (CPU seul ; les cartes restent au grand
modèle). Tout chiffre de ce document est une MESURE faite ici, sur NOS images (les planches et les
croquis de DESTIN), jamais un chiffre recopié d'une fiche.

Règle de lecture : une ligne du **tableau 1** est un geste qui marche et qui a passé le banc ; une
ligne du **tableau 2** est une piste que tu as annotée et que le banc n'a PAS validée — rien n'a été
posé, et tout y reste à essayer dans un second temps.


## 1. CE QUI EST SUR LA MACHINE — ET CE QUE LE BANC EN A DIT

| Ce qui est posé | Le geste | Taille | Mesuré ici | Verdict |
| --- | --- | --- | --- | --- |
| tesseract-ocr 5.5.0 + tesseract-ocr-fra (paquet Debian) | lire le TEXTE d'une image | paquet système | 174 à 285 ms par planche ; le texte FRANÇAIS exact sur 3 planches sur 4 ; 0 octet sur une capture sans texte (et il le dit) | **OUTIL 214 `read_text_in_img`** |
| tokei 12.1.2 (paquet Debian) | compter un projet : code, commentaires, blancs | 4,5 Mo | 11 ms ; VM_LA = **8 791 lignes de code, 1 789 commentaires, 939 blancs** (YAML 5 476, Shell 2 834, Python 404, HTML 69, SVG 5, JS 3) | **OUTIL 215 `count_lines_of_code`** |
| python3-onnxruntime 1.21 (paquet Debian) | le moteur des modèles ONNX sur le CPU | paquet système | charge un ONNX et l'exécute en mémoire basse ; c'est le porteur COMMUN des quatre gestes ci-dessous | la plomberie des 216 à 219 |
| `yolo11n.onnx` | les **BOÎTES** des objets d'une image | 10,4 Mo | 60 à 71 ms ; **5 personnages** trouvés sur la planche de cohérence (0,76 à 0,93) ; 2 faux positifs (« tennis racket ») ; 2/2 sur une bande, 1/1 sur Ibo. Il ne rend PAS les cases : 80 classes d'objets, aucune notion de mise en page | **OUTIL 216 `find_objects_in_img`** |
| `u2netp.onnx` | le **MASQUE DOUX** du sujet (détourage) | 4,4 Mo | 220 à 241 ms ; 20,9 % de premier plan sur Ibo (sujet clair) ; **0 % sur une planche de 224 teintes** — sur une image sans sujet, il n'invente rien | **OUTIL 217 `cut_subject_from_img`** |
| `depth-anything-v2-small.onnx` | la **CARTE DE RELIEF** (devant / derrière) | 94,5 Mo | 519 à 588 ms ; relief rendu (étendue 3,3 à 7,4) sur deux planches | **OUTIL 218 `read_depth_of_img`** |
| `lama-inpaint.onnx` | **RÉPARER UNE ZONE** (tache, texte, objet) | 88,3 Mo | 2 846 ms ; une zone de 15 000 px remplie ; sortie fixe 512×512 | **OUTIL 219 `repair_zone_in_img`** |
| `lid.176.ftz` (fastText, 176 langues) | la **LANGUE** d'un texte | 0,9 Mo | 18 ms par appel ; fr 0,80 / en 0,97 / es 0,997 / de 0,999 ; le wolof part en cebuano 0,85 : les langues hors liste sont MAL classées, et le tool le dit | **OUTIL 220 `read_language_of_text`** |
| `mobilenetv3_small_100.onnx` | classer une image (1 000 objets) | 9,7 Mo | 3 à 4 ms, mais les étiquettes sont **FAUSSES sur notre matière** : « swab » sur le portrait d'Ibo, « nail » 16 % sur une photo de lame, « water tower » sur une planche | pas d'outil — voir tableau 2 |
| `goemotions-int8.onnx` + son vocabulaire | le **TON** d'un texte (28 nuances) | 119,6 Mo | **DÉBRANCHÉ ET AU REBUT le 17/10** : il lit l'anglais (annoyance 0,79, gratitude 0,99) et **meurt en français** (`neutral` 0,90 à 0,96 — il n'a appris que l'anglais) ; une traduction pour lui parler serait du poids pour rien | **plus d'outil** : le porteur, le tool 225 et les 119,6 Mo sont partis au rebut ; l'**offset 2** de la tête secondaire reste **réservé** à un instrument qui lit le français (lois 1555-1559) |
| `FSRCNN_x2/x3/x4.pb` | agrandir un sprite ou une texture | 39 à 41 Ko | le cv2 5.0 de la machine **REFUSE** l'import TensorFlow (`DepthSpaceLayer: blocksize is required`) ; aucun .onnx publié | pas d'outil — voir tableau 2 |

### Les sept outils, posés et PROUVÉS

Chacun a été appelé par **le moteur de LA lui-même** (`config/engine/engine.sh`), pas par un banc à
côté. La preuve, telle que le moteur l'a rendue :

    $ config/engine/engine.sh 214 essai_lecture.png
    {"status":"ok","tool":"read_text","line":"read_text   path=essai_lecture.png  ->  56 bytes, 11 line(s)",
     "result":"seed 202\na\n©\n...\nREF IBO AKOROMO\nseed 404\nseed 303\n", ...}

    $ config/engine/engine.sh 215
    {"status":"ok","tool":"code_stats","line":"code_stats   path=  ->  121 bytes, 2 line(s)",
     "result":"8791 lignes de code ; 1789 commentaires ; 939 blancs
                HTML 69 | JavaScript 3 | Python 404 | SVG 5 | Shell 2834 | YAML 5476", ...}

    $ config/engine/engine.sh 219 essai_lecture.png essai_repare.png 200 300 120 90
    {"status":"ok","tool":"repair_zone","line":"... -> /home/moussa/Documents/VM_LA/work/essai_repare.png 512 512", ...}

Les sept lignes du registre (214 à 220), leurs corps et leurs refus nommés :

| id | outil | famille | ce qu'il refuse, en le nommant |
| --- | --- | --- | --- |
| 214 | read_text_in_img | READ | image absente ou d'un type non lu ; tesseract absent ; texte vide (il le DIT, ce n'est pas une panne) |
| 215 | count_lines_of_code | READ | chemin absent ; tokei ou jq absent |
| 216 | find_objects_in_img | READ | image absente ; porteur absent ; modèle absent de la machine |
| 217 | cut_subject_from_img | WRITE | source absente ; porteur absent ; modèle absent |
| 218 | read_depth_of_img | WRITE | source absente ; porteur absent ; modèle absent |
| 219 | repair_zone_in_img | WRITE | bornes qui ne sont pas quatre entiers positifs ; zone hors de l'image ; modèle absent |
| 220 | read_language_of_text | READ | texte vide ; fastText absent ; modèle de langue absent |

Deux points de plomberie, appris au banc :

- **Un porteur, quatre gestes.** Les gestes 216 à 219 partagent un seul fichier,
  `config/programs/micro_vision.py` (modes `boxes`, `matte`, `depth`, `inpaint`). Ce qui sépare deux
  gestes, c'est la LIGNE DU REGISTRE — jamais le fichier. Un mode ajoute de la mécanique sans
  ajouter de nom.
- **Le bavardage de l'ONNX est coupé.** Le build Debian d'onnxruntime recopie le registre des
  schémas sur la sortie d'erreur (100 Ko par appel). Cette sortie est le canal du REFUS : elle est
  fermée pendant le chargement du modèle, et rendue telle quelle pour nos refus.

**À VALIDER (placement dans les palettes)** — un outil hors palette n'est jamais envoyé :
`read_text`, `find_objects`, `cut_out`, `see_depth`, `repair_zone` ont été ouverts dans le skill
**analyze-image** ; `count_lines_of_code` dans **search-code** ; `read_language_of_text` dans **translate-document**.
Les deux derniers sont des placements de commodité : dis-moi si tu veux `count_lines_of_code` ailleurs
(disk-report ?) et si `read_language_of_text` doit rester là.


## 2. CE QUE TU AS NOTÉ PERTINENT ET QUE JE N'AI PAS VALIDÉ (à essayer plus tard)

| Ce que tu as annoté | Ta note | Ce que le banc a mesuré | Pourquoi ce n'est pas un outil aujourd'hui | Ce qu'il faudrait pour l'essayer |
| --- | --- | --- | --- | --- |
| PP-OCRv4 (mobile) | « 6 très pertinent » | non posé : **aucun porteur prêt** (ONNX + post-traitement des boîtes à écrire) | le GESTE, lui, est tenu : tesseract lit nos planches, mesuré au tableau 1 | écrire le post-traitement le jour où tesseract bute sur une police |
| U²-Net-P | « 3 à tester très pertinent » | 220 à 241 ms, 4,4 Mo ; détoure un sujet clair, ne trouve rien sur une planche | — (validé : c'est l'outil `cut_subject_from_img`) | posé |
| U-Net Patch Inpainter | « 2 très pertinent » | le geste est rendu par LaMa : une zone de 15 000 px remplie en 2,8 s | — (validé : c'est l'outil `repair_zone_in_img`) | posé |
| Depth Anything V2 (Small) | « 2 pertinent » | 519 à 588 ms, carte de relief rendue | — (validé : c'est l'outil `read_depth_of_img`) | posé |
| MobileNetV3-Small | « 3 très pertinent » | il tourne (3-4 ms) mais ses étiquettes sont **fausses sur nos images** : ImageNet est un monde de photographies, LA travaille sur des dessins | un outil qui rend un fait FAUX coûte plus qu'il ne rend | un entraînement sur NOS images (fine-tuning), sinon rien |
| Fast-SCNN | « 3 très pertinent » | **aucun .onnx publié** : rien à poser, rien à mesurer | pas de porteur ; et le geste (détourage) est déjà tenu par `cut_out` | un build ONNX publié, ou rien |
| FSRCNN | « 2 très pertinent » | les poids sont posés (39 à 41 Ko seulement — c'est sa vraie taille) mais le cv2 5.0 installé refuse l'import TensorFlow | le geste de l'agrandissement est déjà tenu côté cartes (comfyui) | une conversion `.pb` → `.onnx` (tf2onnx ≈ 600 Mo) ou un build ONNX |
| Tiny Colorizer | « 1 pertinent » | **aucun artefact identifiable** sur les dépôts publics | pas de porteur ; le geste est tenu par comfyui (colorisation) | un dépôt nommé, et on l'essaie |
| GoEmotions (DistilRoBERTa) | « 4 pertinent » | l'anglais : `annoyance` 0,79, `gratitude` 0,99 ; le français : `neutral` 0,90 et plus | **REBUTÉ le 17/10** (loi 1558 : un instrument d'anglais meurt en français) | **reste ouvert** : l'instrument FRANÇAIS — (a) fastText appris sur un corpus d'humeurs françaises, 0,4 Mo, 5 ms ; (b) un CamemBERT d'émotion converti en ONNX, ~2 Go de torch ; (c) **un k-NN d'humeurs sur l'embedder harrier déjà résident** : 0 installation, 0 RAM ajoutée |


## 3. FASTTEXT — COMMENT ON L'INTÈGRE (le chantier, mesuré)

La loi 1532 du canon nomme **fastText LE CLASSIFIEUR**, et la loi 1505 pose trois étages
(classifieur, modèle de structure, principal). Le binaire est sur la machine (`/usr/bin/fasttext`)
et il n'est cité **nulle part** dans le code : le premier barreau manque.

### Ce que le banc a mesuré (32 exemples écrits à la main, 8 gestes, 4 phrases par geste)

| Ce qu'on fait varier | Poids du modèle | Chargement + 8 prédictions | Justes |
| --- | --- | --- | --- |
| défaut (seau 2 000 000, dim 50) | **381,5 Mo** | 158 ms | 7/8 |
| seau 200 000 | 38,2 Mo | 28 ms | 7/8 |
| seau 50 000 | 9,6 Mo | 12 ms | 7/8 |
| seau 50 000, dim 25 | 4,8 Mo | 11 ms | 7/8 |
| **seau 10 000, dim 10** | **0,4 Mo** | **5 ms** | 7/8 |

**Le poids est le SEAU, pas la donnée.** La matrice d'entrée d'un modèle fastText fait
`seau × dimension × 4 octets` : au réglage par défaut, 2 000 000 de seaux sur 50 dimensions = 400 Mo
de matrice, pour trente-deux phrases apprises. Le banc l'a payé (381,5 Mo, 130 ms à chaque appel) ;
avec `-bucket 10000 -dim 10` le même classeur tient dans **0,4 Mo** et répond en **5 ms** — et il
classe AUSSI BIEN (7/8 aux deux bouts de l'échelle). L'entraînement complet prend 5 secondes.

Ce que cela décide, et c'est la réponse à ta question :

1. **Le classifieur de LA est un CLI, pas un service résident.** Un modèle de 0,4 à 10 Mo se charge
   en 5 à 12 ms à chaque appel ; un résident coûterait de la RAM à chaque tour pour rien. La loi
   825-827 (la RAM du tour se paie) est satisfaite par la forme CLI — zéro RAM au repos.
2. **La langue coûte 18 ms et 0,9 Mo** : c'est le tout premier barreau, et il est déjà posé en outil
   (`read_language_of_text`, 220).
3. **Ce que dit la machine d'elle-même est trop mince.** `config/sessions.db` ne porte que
   **15 échanges** (5 lignes du registre touchées, dominées par les essais de voix). Le corpus ne
   peut donc pas venir du vécu : il s'écrit à la main (le résumé de chaque skill + deux ou trois
   demandes-exemples par skill), et il **grandit avec les sessions**. Un compte se périme, une
   borne se tient.
**CE QUI EST FAIT (17/10, validé).** Les classes sont les **QUATRE FAMILLES du périmètre** — READ,
WRITE, MANAGE, REPLY : quatre étiquettes stables, qu'aucune table ne peut périmer. Deux outils sont
posés, le corpus vit DANS le projet, et le tout est prouvé par le moteur lui-même :

| id | outil | ce qu'il fait |
| --- | --- | --- |
| 223 | `train_family_filter` | apprend sur `config/filtre/familles.txt`, met UN TOUR SUR QUATRE de côté, juge dessus, puis réapprend sur tout et pose `config/filtre/famille.bin` |
| 224 | `guess_family_of_text` | la demande sur l'entrée standard → la famille et sa confiance (`READ 0.85`) |

La première mesure, telle que l'outil la rend :

    corpus 55 lignes utiles ; 13 mises de cote ; 6 justes sur 13 ; apprentissage 60 ms ;
    modele 410123 octets ; MANAGE 14 | READ 14 | REPLY 13 | WRITE 14

Quatre classes, quatorze exemples chacune, **6 justes sur 13** (le hasard en donnerait 3), 400 Ko,
60 ms pour apprendre, 5 ms pour juger. Les six jugements faux disent tous la même chose : la
demande porte un verbe qui n'apparaît qu'UNE fois dans le corpus (« ou est defini le perimetre »,
« remplace la ligne 12 »). **C'est le corpus qui est mince, pas la mécanique** : à 200 lignes de TES
demandes, ce filtre devient un vrai premier étage — et c'est toi qui l'écris, une ligne par demande.

Deux pièges payés en le posant, ils valent d'être dits :

- **fastText avale les commentaires** : un `#` dans le corpus est appris comme un exemple et fausse
  la mesure (premier essai : 4 justes sur 15, sept commentaires comptés comme des demandes). Le
  corpus est de la DONNÉE, pure ; ce qui l'explique vit dans l'en-tête de l'outil.
- **Une mesure se prend sur la DEMANDE SEULE**, sans son étiquette : lui laisser `__label__READ`
  dans l'entrée gonfle le compte (7/13 annoncés au lieu de 6/13).
- **Un id en double dans le registre ne fait AUCUN bruit** : le moteur prend le PREMIER et exécute
  le mauvais outil (payé : un autre chantier a pris 221 pendant l'écriture ; le 221 du filtre est
  devenu `unload_project`, et c'est `unload_project` qui a répondu).

## 4. POUR REFAIRE LE BANC (les scripts vivent hors du projet)

- `~/.hermes/cache/scratch/banc_micro.py` — les cinq modèles ONNX, un par un, latences et poids.
- `~/.hermes/cache/scratch/banc_micro2.py` — MobileNetV3 en probabilités, GoEmotions sur du FRANÇAIS.
- `~/.hermes/cache/scratch/banc_fasttext.py` — la langue, puis la mécanique du classeur.
- `~/.hermes/cache/scratch/etude_fasttext.py` — ce que coûte le seau : le tableau du point 3.
- Les mesures brutes : `micro_resultats.json`, `micro_resultats2.json`, `micro_resultats3.json`,
  `ft_etude.json` (même dossier).
- Le porteur des gestes, lui, est DANS le projet : `config/programs/micro_vision.py`.

## 5. POSÉ AUTOUR DES MODÈLES, LE 17/10 (ce ne sont pas des modèles)

Ce qui suit n'est pas un micro-modèle : c'est la machinerie qui les entoure, posée le même jour et
éprouvée par son appel.

| ce qui | où | ce qu'il fait |
|---|---|---|
| **LE TABLEAU** | `config/programs/board.py`, porte `config/engine/board.sh` | **une seule colonne** : la **liste de contrôle d'abord** — engine, table, canon, git, doctor, erreurs, résidents, **RAM de LA**, api, endpoint, **api status**, sessions, **last_activity**, journal, pont — puis les résidents, puis **les modèles DE LA avec leur état** (CHARGE / à la demande : ceux que nos briques, nos corps et nos porteurs nomment, pas les modèles du disque), puis la machine. `--once` = une passe, code de retour = **le nombre de défauts** (la forme dont l'agent se sert pour auditer) ; vivant, la liste s'imprime ligne à ligne — c'est le chargeur — puis le tableau se redessine sur place et reste. En rich : cadres et couleurs. |
| **OUVRIR LA** | porte `~/.local/bin/la`, corps `config/engine/la.sh` | réveille les cinq résidents, **branche** le pont s'il est muet (il n'écoute que sur 127.0.0.1 : l'ouvrir n'expose rien hors de la machine) et dit l'état. `la --board` : le tableau dans sa fenêtre, **à la demande**. `la --once` : une passe ici. |
| **LE BOUTON DE PANNEAU** | applet Cinnamon `la-status@moussa` — source `config/applets/la-status@moussa/`, **copie** dans `~/.local/share/cinnamon/applets/` | l'étiquette « LA clear » (vert) ou le nombre de défauts (rouge) dans la barre, rafraîchie toutes les 30 s ; un clic : la liste de contrôle et trois actions. **Bâti sur `temperature@fevimu`**, un applet déjà installé et en service : rien des idiomes n'est inventé. Tout part **en asynchrone** (`Util.spawn_async`), jamais dans la boucle de Cinnamon, jamais deux fois de front — un bouton ne peut donc pas geler le panneau. Banc : `work/scripts/banc_applet.py`, cinq verdicts. |
| **LES PROGRAMMES** | skill `program-manage` ; ids **225** `install_program`, **226** `uninstall_program`, **227** `open_program` | un seul dépôt (apt) : ce qui n'y est pas ne s'installe pas par ici. Le nom est jugé **comme un nom** (`x; touch INJECTE` est refusé et ne crée rien) ; un retrait se nomme **deux fois** (`name` et `confirm`) et dit ce qui partirait AVANT l'acte ; `open_program` ouvre ce qui est déjà là et dit où il a cherché quand il ne trouve pas. |

Ce qui reste ouvert, et qui n'attend qu'un corpus : **l'instrument d'humeur en français**. Le k-NN
sur l'embedder déjà résident a été mesuré et **ne tient pas** : il lit le français (0,963 sur deux
paraphrases, 0,57 sans rapport) et coûte 13 ms, mais les humeurs ne se séparent pas — humeur
**opposée** 0,659 contre humeur **différente** 0,535. Le vecteur attrape le sujet et le style, pas
l'affect. Il faut 15-20 phrases par humeur **écrites par toi** ; alors fastText (5 ms, 0,4 Mo) ou une
régression sur les vecteurs feront le travail — et ils nommeront TES états, ce que GoEmotions ne
savait pas faire.

# LES IDEES ET LES PISTES DE LA

Depot, pas un canon. Rien ici ne pretend etre vrai : ce sont des idees, des intentions, des choses
vues et NON faites. Ce qui est VRAI vit dans `skills/la/spec.yaml` (dix-huit matieres) ; ce qui doit
attendre sa CONDITION vit dans `BACKLOG.md`.

## LES PISTES, GROUPEES PAR THEME

### Theme A - La VM (Debian, disque, amorce, noyau, memoire, QEMU)   [matiere LA_MACHINE]
- Le coffre DISQUE ext4 (`rootfs.img`, `coffre.img`) ; la loi du disque (non monte, sans root).
- L'amorce /init statique (les cinq etapes) ; les huit pieges mesures (initrd, /dev, -cpu host, HDA,
  udhcpc, crc32c, cpio).
- L'outillage de boot : amorce.sh, vml.sh, probe-b1.txt — les trois ne sont PAS sur le disque, ils se
  reconstruisent ; vml.sh refuse de demarrer sans filet (tar etranger, deroule, compare).
- La memoire : le pic simultane, le dechargement d'une brique, les trois regimes ; la formule RAM ; la
  marge DECIDEE en Mio. RIEN N'EST MESURE : le plancher se mesure par paliers, VML_MEM descendu jusqu'a
  l'echec.
- Le lanceur QEMU (VML_MEM, -smp 4, -cpu host, -audiodev pa) ; le confinement audio partiel, nomme.
- Le partage station/VM ; le vidage de corbeille humain, puis e2fsck.

### Theme B - La voix et le pont   [matiere LA_VOIX]
- Le tour de parole STT/TTS dans la VM ; PUSH-TO-TALK (tranche) ; les quatre etats d'un ask.
- Le moteur de synthese NON TRANCHE : il se tranche par DEUX MESURES (RAM au repos et pendant une
  synthese, temps du premier mot), sur CPU et dans la VM.
- Le STT : parakeet (NeMo-Speech.cpp) ; le tool `transcribe` (id 136) est pose et l'appelle.
- LE PONT : le transport n'est pas tranche. Il transporte un TEXTE et un signal, et il est LOCAL — une
  adresse ou un port se MESURE, il ne s'invente pas. (Le pont Telegram vit, lui, hors de la table.)

### Theme C - Le filtre   [matiere LE_FILTRE]
- T0 (le verbe), T1 (l'etape du plan), T2 (le filtre) : AUCUN des trois n'est dans loop.sh. Le
  perimetre REEL vient du champ `tools` du SKILL ACTIF, PLUS la categorie permanente.
- La brique du filtre (un encodeur gele et une tete entrainee, une passe, moins de 2 ms) ; ses trois
  defauts et leur correctif.
- La couche signal_task "lancee par la boucle" : le proc existe, l'appel n'est pas branche.
- Le doute qui OUVRE le perimetre.

### Theme D - L'economie de tokens   [matiere L_ECONOMIE]
- Les quatre chiffres du budget et la VITESSE : aucun ne s'ecrit, ils se MESURENT.
- LE PLAFOND par NOMBRE DE TOKENS, troncature en tete ; le seuil d'arret a 70 % (la marge de 30 %).
- AUJOURD'HUI : le moteur borne en OCTETS (4000) et en LIGNES (200), et `hist.json` est envoye ENTIER.
  Aucune troncature, aucun plafond de contexte.
- Le cache : ecriture 1,25x, lecture 0,1x, rentable des 1,28 tour.

### Theme E - Le verrou et la doc   [matiere LE_SKILL]
- load_doc EST dans la table : c'est le tool de la doc obligatoire ; le verrou (requires_tool) REDUIT
  le perimetre au SEUL tool impose, plus les garde-fous qui ne tombent jamais (answer, ask, talk,
  kill, et les quatre tools de plan).
- Ce qui manque : un dossier `docs/` SOUS CHAQUE SKILL, et la section `docs:` qui nomme le sujet. Aucun
  skill n'en porte.
- Le message qui NOMME la precondition non remplie, et le demasquage au tour suivant.
- L'enum du perimetre dans le schema de la(tool, arguments).

### Theme F - Le MODE patch de write_file
- Un quatrieme mode qui poserait un bloc entre deux ancres : ECARTE. La table porte `new`, `append`,
  `replace`, et rien de plus. Le mode n'a jamais servi.

### Theme H - L'APPROBATION SCOPEE (objet scope)
- Un objet scope (acteur, tool, arguments, duree, issue) : aujourd'hui l'approbation existe seulement
  par la variable LA_APPROVED.
- Sa condition : un tool qui SORT du strict lire / ecrire dans le travail.

### Theme I - Le DISQUE de la VM (rootfs.img / coffre.img / ext4 sans montage)
- La VM est un disque ext4 dans un seul fichier, lu sans monter (mke2fs, debugfs) : RIEN n'est
  fabrique. Le dossier des disques est VIDE.

### Theme J - LA SESSION TRANSCRITE   [matieres LE_RETOUR_DES_OUTILS, LA_MEMOIRE]
- La boucle doit transcrire chaque tour : le tool, ses arguments, son statut, l'heure.
- Aujourd'hui : loop.sh n'ecrit pas la session ; le tool `session` ouvre seulement un fichier date
  depuis un moule, et rien ne l'appelle.

### Theme K - LE MICRO-MODELE A DEFINIR PROPREMENT   [matieres LA_MEMOIRE, LE_MODELE]
- C'est LUI qui ecrit les RESUMES : le resume pour `sessions.yaml`, ET le resume du HEAD SECONDAIRE.
- Aujourd'hui : la place du resume est marquee ET bornee dans second.sh (12 lignes, 800 octets) et RIEN
  NE LA REMPLIT ; la brique summary.sh existe, ses bornes sont declarees et tenues, et rien ne l'appelle.
- Deux taches de fond, deux FORMES de modele : le FILTRE est un modele de CHOIX (un encodeur gele et
  une tete) ; le RESUME est un modele de LANGUE (il ecrit).
- Sa condition : le modele est choisi, MESURE (RAM, latence), et la brique est branchee sur la fin de
  tour — EN ASYNCHRONE, sinon sa latence se paie a chaque tour.

### Theme L - Le SCHEMA impose au DECODAGE
- Verrouiller le format de sortie au DECODAGE : le moteur valide APRES coup. Une adresse distante ne
  donne pas la main sur le decodage — c'est ce qui justifie la validation par le proc.

### Theme M - Le PLAN toujours ouvert dans le HEAD SECONDAIRE
- second.sh SAIT rendre le plan (le moteur, tool 122) et il le DIT quand il n'y en a aucun ; le
  dossier des plans ne porte rien.

### Theme N - L'ECHELLE DE RECUPERATION et la MESURE DE PROGRES
- Quatre barreaux (DIRE / ELARGIR / REVISER / DEMANDER), trois detecteurs, un seuil de trois tours sans
  progres, une mesure qui coche des etapes.
- Non implemente : un seul detecteur existe dans loop.sh, l'anti-boucle — qui SE DIT et ne coupe pas.

### Theme O - Le WIDGET, le poste, le telephone
- Le widget montre ce que la machine dit DEJA : la ligne du tool, l'etape du plan, le texte de la
  reponse. Il n'ajoute aucun canal.
- Le modele RESTE sur la machine : un poste qui le porterait porterait la memoire, les cles et le coffre.
- Rien n'est pose : ni le poste, ni le transport, ni le mode.

### Theme P - Divers (illustrations, doctrine non executable, citations externes)
- Ce qui ne se lit nulle part dans le code ne s'ecrit pas dans la spec.
- Les citations externes de l'economie (Anthropic 150 000 -> 2 000 ; Cursor ; Writer -40 % / +82 %) ne
  sont pas des mesures d'ici.

