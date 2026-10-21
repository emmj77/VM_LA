# Break-Glass : free terminal & skill debug — spec (harness RMS)

Source : conversation Gemini du 21/10/2026, tours 53 et 55. Décision de Moussa : ajouter une skill « debug » qui donne accès à un **free terminal**.
Objectif réel : quand la machine elle-même est bloquée (pas le projet), avoir accès à **l'ensemble du PC**, sans repasser par un agent sur l'hôte.

---

## 1. Problème constaté

- Un agent RMS tourne en sandbox : dès qu'il a besoin d'une action hors périmètre, il ne peut pas la faire.
- Contournement actuel : Moussa ouvre manuellement son RMS sur l'hôte. Ça casse le flux et c'est pénible.
- Le harness Default Deny est hermétique par construction : sans trappe, un cas non anticipé = deadlock ou travail à la main.

## 2. Principe : le `sudo` du harness

- La skill debug n'est **jamais** chargée par défaut. Elle s'ouvre uniquement **sur action explicite de Moussa** (double verrou : Default Deny maintenu au quotidien, escalade seulement à la demande).
- Une fois chargée, elle expose un outil terminal **sans entrave** : n'importe quelle commande, sur l'hôte, pas seulement dans le workspace du projet.
- Elle doit pouvoir être **déchargée** immédiatement pour revenir au toolset normal.

## 3. Déclenchement

| Voie | Forme | État |
|---|---|---|
| Slash | `/debug` → charge la skill debug | à implémenter |
| Slash | `/unload` ou `/unload skill` → décharge la skill courante | à implémenter |
| Vocal (mode Jarvis) | le Ring Inner repère le mot dans la phrase (« debug », « unload skill ») et traduit en ordre système | cible |

Le SLM sert de détecteur de mot-clé : il capte le déclencheur au vol, bascule la skill sans manipulation de menu.

## 4. Ce que la skill doit contenir

- **Outil free terminal** : exécution de commande arbitraire, sur l'hôte.
- **Point d'entrée unique** : une seule porte, pas un jeu d'outils d'administration éparpillés.
- **Retour d'exécution** : stdout/stderr + code de sortie, sans filtre qui masquerait l'échec.
- **Cohabitation avec `reply`** : `reply` reste accessible (pas de deadlock même en mode debug).

## 5. Garde-fous minimaux (à valider par Moussa)

- Chargement **toujours** initié par l'humain, jamais décidé par le modèle.
- Le toolset debug **remplace** le toolset métier pendant la session debug ; on ne cumule pas les deux périmètres.
- Sortie de mode : `/unload` remet le toolset de la skill précédente ou du projet.
- Différence avec le reste du harness : ici la vérification par delta d'octets ne s'applique pas (commandes arbitraires) → le seul contrôle est humain.
- La suppression est refusée par le noyau, pas par une liste de binaires : voir §5bis.

## 5bis. Le mécanisme en place (21/10/2026)

Décision de Moussa : un lanceur dont la configuration porte **directement** la restriction, et cette configuration vit dans `la_config` — une seule source, rien en dur dans le corps.

- L'outil `G077 free_terminal` lance : `systemd-run --user --pipe --wait --collect -p RuntimeMaxSec=… puis un -p SystemCallFilter=~<appel> par appel refusé -p SystemCallErrorNumber=… -- bwrap --bind / / --dev /dev --proc /proc -- /bin/sh -c "<commande>"`.
- Le refus est **dans le noyau**, au nom de l'appel système (filtre seccomp) : `machine.free_terminal.deny: [unlink, unlinkat, rmdir]`, `machine.free_terminal.error: EPERM`.
- Conséquence mesurée le 21/10 : `rm` → « Opération non permise » (code 1) ; `python3 os.unlink` → `PermissionError: [Errno 1]` ; l'écriture reste libre (`touch`, `id -un` = moussa).
- `bwrap --dev /dev` garde son rôle : les disques réels ne sont pas visibles (fdisk, parted, mkfs, dd sur un disque n'ont rien à mordre). La liste de noms de binaires (ex-C10) a disparu : elle se contournait par python.
- Le journal reste : chaque commande s'ajoute à `state/free_terminal.log` (horodatage + texte).

## 6. Question ouverte restée sans réponse

**Journalisation systématique ?** Faut-il enregistrer toutes les commandes passées en free terminal dans un fichier (quoi, où, rétention, relecture par l'agent ou par Moussa seulement) ? Gemini a posé la question, Moussa n'a pas répondu dans la conversation. C'est une décision de sécurité, pas un détail.

## 7. À implémenter (ordre)

1. Outil free terminal branché sur l'hôte.
2. Commande slash `/debug` / `/unload`.
3. Politique de journalisation (§6) une fois tranchée.
4. Déclenchement vocal via le Ring Inner.
