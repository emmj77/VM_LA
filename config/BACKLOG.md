# BACKLOG — les mecaniques PRETES, mais NON ACTIVES

**Ce fichier n'est pas une fiche** : rien de ce qui est ici n'entre dans une decision de LA. Il
existe pour que le corpus reste tendu sur ce qui est VRAI aujourd'hui (canon, §5 : une passe qui
ajoute doit retirer).

Pour activer une entree : elle entre dans la MATIERE qui la porte (`skills/la/spec.yaml`), avec son
cas d'usage NOMME.

## LE MICRO-MODELE — les deux resumes

    ce qui est en place    une PLACE bornee dans second.sh (12 lignes, 800 octets) et la brique
      aujourd'hui         summary.sh — appelee par RIEN
    ce qu'il doit ecrire   les resumes pour sessions.yaml, ET le resume du head secondaire
    la condition           le modele est CHOISI et MESURE : RAM au repos et pendant un resume, et le
      d'activation         temps d'un resume ; puis la brique est branchee sur la fin de tour, EN
                           ASYNCHRONE (posee DEVANT le tour, elle ajouterait sa latence a chaque tour)
    pourquoi ce n'est      le modele n'est pas encore defini proprement : deux taches de fond, deux
      pas actif            FORMES de modele — le FILTRE choisit (un encodeur gele et une tete), le
                           RESUME ecrit (un modele de langue)
    ce que ca changerait   le contexte du tour cesse de porter l'historique entier : il porte la
                           FENETRE, et le resume au-dessus

## Le schema impose au DECODAGE

    ce qui tient le format     le PROC, apres coup (matiere LES_PROCS)
      aujourd'hui
    la condition d'activation  le jour ou le moteur tourne DANS la VM
    ce que ca changerait       la grammaire du schema contraint la generation : une valeur hors bornes
                               devient IMPOSSIBLE a produire, et une classe entiere d'erreurs disparait
    pourquoi ce n'est pas      une adresse distante ne donne pas la main sur le decodage — c'est ce qui
      actif                    justifie la validation par le proc, et rien n'en depend aujourd'hui

## LE DRAPEAU `overwrite` SUR `write_file`

    ce que c'etait   un booleen qui autorisait le remplacement d'un fichier existant
    la condition     aucune : ecarte definitivement
    pourquoi         le modele l'aurait appris a le mettre SYSTEMATIQUEMENT des la deuxieme ecriture,
                     et la protection serait devenue une formalite recitee. Le remplacement se declare
                     par le MODE de write_file (matiere LA_LOI_D_ECRITURE)

## LE DECLENCHEUR DE CRON

    ce qui existe deja     les DEUX TOOLS (add_cron, remove_cron : 130 et 131) : ils tiennent la
                           section (matiere LES_MANAGERS)
    ce qui manque          LE DECLENCHEUR : QUI les fait tourner
    la condition           une tache doit vraiment s'eveiller a date fixe
    pourquoi ce n'est pas  la boucle est un tour de PAROLE, et rien dans le projet ne s'eveille tout
      actif                seul. Le declencheur est un PROC de la VM, jamais un cron de la station : la
                           station ne decide rien, et un crond cote station ferait entrer une decision
                           dans la machine qui n'en prend aucune
    le jour ou il entre    il entre ENTIER — les deux tools ET le declencheur, le meme jour — NOMME
                           dans la matiere LES_MANAGERS, sa ligne sur le canal de l'humain

## L'APPROBATION SCOPEE

    ce que c'est                un objet SCOPE : acteur, tool, arguments, duree UNE FOIS, issue
                                (approuve / refuse / EXPIRE). Quand elle expire, elle TERMINE.
    la condition d'activation   le jour ou un tool SORT du strict lire / ecrire dans le travail
    pourquoi ce n'est pas actif l'approbation existe par la variable LA_APPROVED, et le confinement par
                                ABSENCE DE MOYEN fait deja le travail. Une section qui prepare un futur
                                non advenu se paie a chaque relecture

## LE ROUTAGE PAR FAMILLE — le troisieme chemin du perimetre

    ce qui tient le perimetre  le verbe (T0), l'etape du plan (T1), le filtre (T2) — AUCUN des trois
      aujourd'hui              n'est dans loop.sh : le perimetre REEL vient du champ `tools` du SKILL
                               ACTIF plus la categorie permanente (matiere LE_FILTRE)
    ce qui manque              le chemin qui tranche quand NI un verbe NI un plan n'est la, et que le
                               catalogue n'est plus une liste courte : la FAMILLE du tool, lue sur la
                               MEME ligne que son nom
    la condition d'activation  le perimetre doit rester rendu en 3 a 5 tools quand le catalogue
                               s'allonge
    pourquoi ce n'est pas      une mecanique que rien n'appelle est du poids paye a chaque relecture
      actif                    (canon, §5)
    ce que ca changerait       le catalogue peut croitre sans rendre de liberte — le modele NOMME
                               toujours un tool, il n'en compose aucun

## LE MOTEUR DE SYNTHESE — quel TTS parle

    ce qui est en place      Piper, voix fr_FR-tom-medium, compile en glibc (matiere LA_VOIX)
      aujourd'hui
    les candidats releves    Kokoro-82M par kokoro-onnx (Apache-2.0, UNE voix francaise, et il tourne
                             sur le python3-onnxruntime de Debian) ; Supertonic (licence OpenRAIL-M,
                             depot archive) ; KittenTTS ; et Piper lui-meme (GPL-3.0-or-later, SEPT
                             voix francaises)
    la condition             DEUX MESURES, sur CPU et DANS la VM : la RAM (au repos et pendant une
      d'activation           synthese) et le temps du premier mot. Aucune des deux n'est prise — les
                             seules valeurs publiees viennent d'un autre materiel
    pourquoi ce n'est pas    changer de moteur change la MEMOIRE de la VM, et la memoire n'est pas
      actif                  encore fixee : le plancher se mesure d'abord (matiere LA_MACHINE)
    ce que ca changerait     le poids de l'image et le plancher de RAM. Le reste — le format de sortie,
                             la place du TTS dans la boucle, les deux bouts du tour de parole — ne
                             bouge pas.

## LE TRANSPORT DU PONT (le widget, le poste, le telephone)

    ce qui est en place      le tunnel WireGuard (poste 10.10.0.1, port 51820), la face TLS du pont,
                             l'appli native installee sur le telephone, le widget pose. Le
                             telephone ATTEINT la machine : poignee de main vue, APK pris par
                             le tunnel.
    ce qui manque            LE TOUR N'A PAS PASSE. Le journal du pont ne porte AUCUNE requete du
                             telephone ; la seule ligne POST /say est un essai fait depuis le
                             poste. Le moteur, lui, repond : un tour local rend « OK » en 15 s.
    la cause probable        le bouton PARLER du widget lance une diffusion d'arriere-plan qui
                             demarre un service d'ecoute au premier plan ; Android 13+ refuse ce
                             demarrage, et le refus est SILENCIEUX. Rien ne sort du telephone.
    la suite                 refaire le widget entierement : un design qui tienne (les standards
                             graphiques 2026, pas les boutons systeme), et PARLER qui OUVRE
                             l'appli — une activite est toujours permise — laquelle lance
                             l'ecoute elle-meme.
    la condition             le premier tour complet telephone -> poste, LU dans le journal du pont.
