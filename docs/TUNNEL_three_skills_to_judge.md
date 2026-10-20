# LE TUNNEL DU TELEPHONE — trois skills à juger

Rapport du 19 octobre 2026. Tout ce qui suit a été **lu ou mesuré sur ce poste**, pas supposé.
Aucune modification n'a été faite : ni au dépôt, ni au réseau, ni à `/etc`.

---

## 1. OÙ EN EST LE TUNNEL, MESURÉ À L'INSTANT

| ce qu'on regarde | état mesuré | ce que ça veut dire |
|---|---|---|
| interface `wg0` | **10.10.0.1/24, levée** | le tunnel existe côté poste |
| port `51820/UDP` | **ouvert** (IPv4 et IPv6) | le pair peut frapper à la porte |
| `/etc/wireguard/wg0.conf` | **présent** | la configuration est posée |
| profil du téléphone `work/LA-phone.conf` | **ABSENT** | la clé privée du téléphone n'existe plus |
| pont sur `8765` / `8766` | **0 écouteur** | le pont est mort (`socat ... signal 15`) |
| lignes citant `10.10.0.2` dans `work/bridge.log` | **0** | aucun tour n'est jamais venu du téléphone |
| outils `tunnel*` au registre | **0 sur 3317** | l'agent ne peut ni lever, ni lire, ni couper |
| paquets | wireguard-tools, qrencode **présents** | la matière première est là |

**Le diagnostic du BACKLOG est incomplet.** Il accusait le service Android 13+. Il y a une
**seconde porte fermée, écrite noir sur blanc dans la configuration** :

    bridge:
      host: 127.0.0.1      <-- le pont n'écoute QUE sur la boucle locale
      port: 8765

Même avec un téléphone parfait, un tunnel parfait et une redirection de box correcte, le
téléphone arriverait sur le poste et **n'entrerait nulle part**. `la.sh` le dit lui-même :
« pour que le téléphone l'atteigne, il faut élargir ADRESSE — et ce jour-là c'est une décision ».

**Et un état sans retour :** l'interface est levée, mais le profil du téléphone a disparu. Le pair
existe dans `wg0.conf`, la clé privée qui lui correspond n'existe plus. Ce téléphone ne se
reconnectera pas « en rescanant » : il faut retirer le pair et en créer un neuf. Or la brique
actuelle **n'a pas de `down`** — elle sait lever, jamais défaire, et elle **régénère les deux
paires à chaque passage** (donc relancer pour « redonner le QR » rend le téléphone muet en silence).

---

## 2. LES TROIS SKILLS PROPOSÉES

### 2.1 `tunnel-status` — LIRE (indispensable)

**Ce qu'elle fait.** Une seule chose : dire ce que le tunnel EST maintenant. Interface et son
adresse (attendue 10.10.0.1/24), port UDP, pair et âge de la poignée de main, présence et droits du
profil du téléphone, les deux portes du pont (8765 et 8766), et le nombre de lignes du journal qui
citent le téléphone. Elle finit par « faute(s) : N ».

**Ce qu'elle refuse.** Rien — elle ne fait que lire. Mais elle **ne confond jamais** « je n'ai pas pu
lire » avec « zéro » : `sudo -n` refusé s'écrit « non lu », pas « aucune poignée de main ». C'est la
leçon de la brique : un zéro muet déclare mort un tunnel vivant.

**Ce qu'elle ne fait pas.** Elle ne lève rien, ne coupe rien, ne touche à aucune règle. Elle ne
sonde pas avec `port_busy()` : cette fonction ne teste qu'en **TCP** et ne verrait jamais 51820/UDP.

**Pourquoi elle est indispensable.** C'est la seule qui puisse **contredire le BACKLOG** avec des
faits. Sans elle, un agent qui « répare le tunnel » travaille à l'aveugle, et l'humain aussi.

---

### 2.2 `tunnel-raise` — LEVER (indispensable, mais c'est un acte système)

**Ce qu'elle fait.** Lève `wg0` en appelant la brique du dépôt (`engine/tunnel.sh` — une seule
vérité sur la façon d'écrire `/etc/wireguard`), puis **prouve** son geste en relisant l'adresse et
le port. Un `exit 0` ne prouve rien : elle relit.

**Ce qu'elle refuse, et chaque refus est nommé :**
- une adresse qui n'est pas une adresse (caractères hors `[A-Za-z0-9.-]`, `-` ou `.` en tête, `..`) ;
- une adresse **privée** (10.*, 127.*, 192.168.*, 172.16-31.*) : le téléphone en 4G ne l'atteindra pas ;
- une adresse sans point ;
- un outil manquant (`wg`, `wg-quick`, `ip`, `ss`, `qrencode`) — refus **avec le nom du paquet Debian** ;
- `sudo -n` qui demanderait un mot de passe : « un tool qui attend un mot de passe est un tool qui pend » ;
- le port 51820/UDP déjà pris par autre chose ;
- **un pair déjà connu** : là elle ne régénère RIEN. Si `wg0.conf` existe et que le profil a
  disparu, elle refuse et nomme le seul chemin (retirer, puis lever). C'est le trou le plus grave
  de la brique actuelle : elle écrase la config sans regarder.

**Ce qu'elle ne fait pas.** Ouvrir le port sur la box (c'est écrit dans la brique : c'est à la
main). Élargir l'adresse du pont (`127.0.0.1` → tunnel) : ce n'est pas un effet de bord d'un
« lève le tunnel », c'est une décision qui expose le poste.

**Le coût.** Elle écrit dans `/etc/wireguard` et fait `wg-quick up`. C'est un acte système, pas un
acte de fichier.

---

### 2.3 `tunnel-lower` — RETIRER (utile, c'est le pendant)

**Ce qu'elle fait.** Défait ce que `raise` a fait : `wg-quick down wg0`, la config, le profil, le
QR. C'est **l'acte destructif** du projet (le téléphone devra rescanner un code neuf).

**Ce qu'elle refuse :**
- `name` et `confirm` absents, différents, ou nommant autre chose que `wg0` ;
- un `wg0` présent sans `/etc/wireguard/wg0.conf` : « ce n'est pas notre tunnel, je ne le coupe pas » ;
- une config qui n'a pas été posée par `tunnel.sh` (elle en vérifie la première ligne) :
  « je ne défais pas le tunnel de quelqu'un d'autre » ;
- `sudo -n` qui demanderait un mot de passe.

**Pourquoi elle est nécessaire.** Sans elle, un agent qui a levé ne peut plus jamais défaire : il
n'a que `wg-quick down` à la main, ce qui est interdit au modèle. Et le cas d'aujourd'hui
(pair connu + profil perdu) n'a **aucune** sortie propre sans elle.

---

## 3. CE QUE ÇA CHANGE, CONCRÈTEMENT

| geste | aujourd'hui | avec les trois skills |
|---|---|---|
| savoir où en est le tunnel | `ip`/`ss`/`wg` à la main | une commande, un verdict par ligne |
| lever | brique non nommable par l'agent | `tunnel_up <adresse publique>` |
| **redonner un QR sans casser le pair** | impossible (la brique régénère les clés) | refusé **et expliqué** : down puis up |
| retirer proprement | impossible (pas de `down`) | `tunnel_down wg0, wg0` |
| se rendre compte que le pont n'écoute pas | jamais | `tunnel_status` le dit, avec l'adresse |

---

## 4. LES TROIS TROUS QUI RESTENT, MÊME AVEC LES SKILLS

1. **`bridge: host: 127.0.0.1`** — tant que ça n'est pas élargi à l'adresse du tunnel, le
   téléphone n'entre nulle part. `tunnel_status` le **dit**, il ne le corrige pas : c'est une
   décision (exposer le pont).
2. **Le profil du téléphone a disparu** — il faut un `tunnel_down` puis un `tunnel_up` pour
   redonner un code neuf. C'est le premier vrai geste à faire.
3. **Le DNS du profil contredit son `AllowedIPs`** : `DNS = 1.1.1.1` alors que le tunnel ne porte
   que `10.10.0.0/24`. Le téléphone enverra ses requêtes DNS dans un tunnel qui ne les transporte
   pas. À corriger dans la brique, pas dans les skills.

---

## 5. CE QUE JE RECOMMANDE

**Poser `tunnel-status` tout de suite** : lecture pure, aucune écriture système, aucun risque, et
elle transforme le diagnostic du BACKLOG en faits.

**Poser `tunnel-raise` et `tunnel-lower` ensemble, jamais l'une sans l'autre.** Une porte qui lève
sans porte qui défait est exactement le défaut de la brique actuelle. C'est aussi un acte système :
il se place sous l'approbation (la skill déclarera `APPROVAL: true`).

**Ne pas élargir l'adresse du pont dans la foulée.** Un geste à la fois : d'abord un tour complet
du téléphone LU dans le journal, avec le pont élargi à la main, pour savoir si Android suit. On
saura alors si le second problème est réel ou si le premier masquait tout.

Ordre proposé : `status` → (à la main : élargir le pont) → `down` → `up` → un tour réel → on lit.

---

## 6. CE QU'IL ME FAUT POUR POSER

1. Les **trois** ? Ou seulement `tunnel-status` d'abord ?
2. Les ids sont libres : **3486, 3487, 3488** (3485 vient d'être pris par `send_agent_chat`, l'autre
   session). Je confirme au moment de poser.
3. `tunnel-raise` déclarera `APPROVAL: true` : c'est la première skill qui utilisera le mécanisme
   d'approbation. Si l'approbation n'est pas encore en place, je la pose **sans** (et le geste reste
   protégé par ses refus), ou j'attends.
4. Les corps complets (les trois fichiers `tool_tunnel_*.yaml`, commentés ligne à ligne, avec leurs
   refus nommés) sont écrits et prêts : ils ne sont pas dans ce rapport pour qu'il reste lisible.
   Dis « pose », et ils arrivent avec les trois fiches `skill.yaml`.

---

*Mesures faites en lecture seule : `ip`, `ss`, `ls`, `grep`, `sudo -n ls`. Aucun service touché,
aucun réseau modifié, aucun fichier du dépôt écrit.*
