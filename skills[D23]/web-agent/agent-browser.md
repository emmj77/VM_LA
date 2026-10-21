id: "M02"
# agent-browser : la doc de l'app installee

Source : la version posee sur le disque (0.26.0), doc servie par le CLI lui-meme.
Le texte complet se prend a la source, il ne se recopie pas ici :

    agent-browser skills get core --full     # reference complete des commandes
    agent-browser skills list                # skills specialisees de cette version

## La boucle

    agent-browser open <url>        # 1. ouvrir
    agent-browser snapshot -i       # 2. voir les elements interactifs
    agent-browser click @e3         # 3. agir sur une ref du snapshot
    agent-browser snapshot -i       # 4. re-snapshot apres tout changement

Les refs `@eN` sont valables entre snapshots, mais une navigation les perime :
une lecture, puis une action, jamais deux.

## Session nommee : obligatoire des la premiere commande

    export AGENT_BROWSER_SESSION="$(agent-browser session id --scope worktree --prefix task)"

La session sans nom est PARTAGEE par tous les agents de la machine et survit aux
conversations : y travailler peut voler la page d'un autre. `--session <nom>` fait
la meme chose commande par commande.

## Lire

    snapshot                 arbre complet (bavard)
    snapshot -i              interactifs seuls (le choix par defaut)
    snapshot -i -u           avec les href des liens
    snapshot -i -c           compact, sans noeuds vides
    snapshot -i -d 3         profondeur limitee a 3
    snapshot -s "#main"      restreint a un selecteur CSS
    snapshot -i --json       sortie lisible par une machine
    snapshot -i --delta      l'etat complet une fois, puis les changements

## Agir

    click @e1 | --new-tab | --human      dblclick | hover | focus
    fill @e2 "texte"                     vide puis tape
    type @e2 " suite"                    tape sans vider
    press Enter | press Control+a
    check @e3 | uncheck @e3
    select @e4 "valeur"                  par valeur ou libelle
    upload @e5 fichier.pdf
    scroll down 500 | scrollintoview @e1
    drag @e1 @e2

## Attendre (c'est la que les agents echouent)

    wait @e1                      un element apparait
    wait --text "Succes"          un texte apparait
    wait --url "**/dashboard"     l'URL correspond (glob)
    wait --fn "window.app.ready === true"
    wait --load domcontentloaded | load | networkidle
    wait 2000                     delai fixe, en dernier recours

## Onglets

    tab | tab new <url> | tab t2 | tab close t2

Apres un changement d'onglet, les refs de l'ancien ne valent plus : re-snapshot.

## Drapeaux globaux utiles

    --session <nom>    navigateur isole        --json        sortie machine
    --headed           fenetre visible         --cdp <port>  se raccrocher a un Chrome
    --profile <nom>    profil Chrome (session)  --state <f>   etat d'auth sauve
    --engine <nom>     chrome | lightpanda      --headers <json>

## Sur cette machine

Le navigateur integre annonce `HeadlessChrome` et `webdriver=true` : un captcha y
echoue toujours. On lance /usr/bin/chromium --remote-debugging-port=9222 sur le
profil persistant, puis `--cdp 9222`.

## Installation (une fois)

    npm i -g agent-browser && agent-browser install
    agent-browser install --with-deps      # bibliotheques du navigateur sous Linux
