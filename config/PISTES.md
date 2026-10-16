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
