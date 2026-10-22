# Jarvis — spécification et état de l'application (LA_android_app)

Application **mobile-first** pour parler au pont LA : une enveloppe native **Kotlin** qui porte une
**WebView** (l'interface), le micro, le haut-parleur, la bulle flottante et le service d'arrière-plan.
Ce n'est pas le dashboard rejoué dans un cadre : c'est une messagerie vocale, pensée pour le pouce.

Le téléphone reste un **client léger** : aucun modèle, aucune clé, aucun outil. Tout se décide sur le poste.

---

## Spécification

- **Nom** : Jarvis · **package** : `fr.la.chat` · **versionName** : 2.0 · **versionCode** : 1
- **minSdk 26** (TYPE_APPLICATION_OVERLAY) · **targetSdk 34** (type de service d'avant-plan obligatoire)
- **Permissions** : INTERNET, RECORD_AUDIO, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE,
  SYSTEM_ALERT_WINDOW, POST_NOTIFICATIONS, VIBRATE
- **Outils** : AGP 8.6.0, Kotlin 2.0.21, Gradle 8.9, JDK 21, build-tools 34.0.0
- **Dépendances** : `androidx.core:core-ktx` seulement
- **Architecture** : la page (`assets/`) ne fait aucune connexion réseau ; tout passe par la passerelle
  native `@JavascriptInterface` (`window.Android`). Le natif pousse les événements vers
  `window.JarvisApply`.
- **Un tour à la fois** : `TurnEngine` refuse un second tour tant que le premier n'est pas revenu.
- **Historique** : `localStorage` de la WebView, 120 messages au plus, effaçable depuis les Réglages.
- **Service** : avant-plan de type `microphone`, notification avec action « Arrêter », battement
  `/ping` toutes les 25 s.
- **Bulle** : fenêtre `TYPE_APPLICATION_OVERLAY` ; toucher ouvre l'app, appui maintenu parle,
  glissement déplace.
- **Confiance TLS** : certificat du pont épinglé, seule autorité acceptée.

---

## Arborescence

```
LA_android_app[D39]/
├── settings.gradle / build.gradle / gradle.properties / local.properties
│     la recette de build de la station (AGP 8.6.0, Kotlin 2.0.21, Gradle 8.9, SDK 34)
├── app/build.gradle
│     module unique : namespace fr.la.chat, minSdk 26, targetSdk 34, core-ktx seulement
├── app/src/main/AndroidManifest.xml
│     permissions, activité, service d'avant-plan (type microphone), FileProvider
├── app/src/main/java/fr/la/chat/
│   ├── Bridge.kt        client du pont : HTTPS + certificat épinglé, /user_say /user_voice /image /ping /stop,
│   │                    /engine /plan /journal /thinking /spoken /audio, repli d'adresse
│   ├── TurnEngine.kt    un tour : envoi, sondage du journal et du raisonnement, événements vers l'UI
│   ├── Speaker.kt       file de lecture des wav du tour (téléchargés par Bridge, joués en local)
│   ├── Recorder.kt      micro natif : AAC mono 16 kHz dans un m4a (audio/mp4 pour le pont)
│   ├── JarvisService.kt service d'avant-plan : bulle flottante, appui long pour parler, battement /ping
│   └── ChatActivity.kt  la WebView, la passerelle @JavascriptInterface, permissions, photos
├── app/src/main/assets/
│   ├── index.html       structure de l'écran (discussion, activité, réglages)
│   ├── app.css          thème sombre, bulles, orbe, barre d'enregistrement, onglets
│   └── app.js           rendu, markdown léger, machine d'état, mode Jarvis, réglages
├── app/src/main/res/
│   ├── raw/bridge_cert.pem            le certificat du pont (copié, jamais lié)
│   ├── xml/network_security_config.xml  une seule autorité : ce certificat
│   ├── xml/file_paths.xml             la photo reste dans notre cache
│   ├── xml/data_extraction_rules.xml  aucune sauvegarde cloud
│   ├── values/                        textes, couleurs, thème sombre
│   ├── drawable/                      icône, micro, pastilles
│   └── mipmap-anydpi-v26/             icône adaptative
└── README.md
```

---

## Build et installation

```bash
cd /home/moussa/Documents/VM_LA/LA_android_app\[D39\]
/home/moussa/Applications/gradle-8.9/bin/gradle assembleDebug
# APK : app/build/outputs/apk/debug/app-debug.apk
```

Installation sur le téléphone (débogage USB activé) :

```bash
/home/moussa/Applications/android-sdk/platform-tools/adb install -r \
  /home/moussa/Documents/VM_LA/LA_android_app\[D39\]/app/build/outputs/apk/debug/app-debug.apk
```

Ou copier `app-debug.apk` sur le téléphone et l'ouvrir (autoriser « sources inconnues »).

Au premier lancement, l'app demande le micro et les notifications. La bulle flottante demande en plus
« affichage par-dessus les autres applis » (Réglages → Capacités → Autoriser la bulle).

---

## Ce que fait l'application

**À l'ouverture** : l'écran de discussion, une orbe au centre (« Appuie pour parler »), trois
suggestions, une barre de saisie et trois onglets (Discussion, Activité, Réglages). L'en-tête montre
l'état du pont (`En ligne · 100.66.81.33:8766`) et le bouton **Jarvis**.

**Parcours Jarvis (voix → voix)**
1. appui sur l'orbe (ou le micro) → enregistrement natif, orbe rouge, chrono, barre rouge ;
2. nouvel appui (ou ✓ dans la barre) → le m4a part en `POST /voice` ;
3. la bulle « en attente » est remplie avec la **transcription** renvoyée par le pont ;
4. pendant le tour, l'app sonde `/journal` et `/thinking` : outils et raisonnement s'affichent en direct ;
5. la réponse arrive, s'écrit dans le fil, et ses wav (`audios`) sont téléchargés puis joués dans l'ordre ;
6. mode **Jarvis** actif : quand la file audio se tait, le micro se rouvre seul → conversation continue.

**Texte** : la barre de saisie envoie `POST /say` ; la réponse s'affiche (markdown léger : gras, listes,
code, liens) avec un bouton « Écouter » quand un wav existe.

**Images** : le `+` ouvre la feuille « Galerie / Photo » ; l'image part en `POST /image` et devient la
demande du tour.

**Bulle flottante** (service d'avant-plan) : toucher ouvre l'app, **appui maintenu parle** (relâcher
envoie), un glissement déplace la bulle. La notification porte « Arrêter ». Un battement `/ping` toutes
les 25 s met l'état du poste dans la notification.

**Réglages** : adresse du pont, repli d'adresse, test de connexion, état des permissions, service,
liste des adresses `/engine` (appui = prendre cette adresse), `/plan`, effacement de l'historique.

L'historique vit dans le `localStorage` de la WebView ; rien ne part ailleurs.

---

## Le pont, tel qu'il est réellement utilisé

| Route | Usage dans l'app |
|---|---|
| `GET /ping` | état de l'en-tête, notification, test |
| `POST /say` | message écrit |
| `POST /voice` | tour vocal (corps audio brut, `audio/mp4`) |
| `POST /image` | tour image |
| `POST /stop` | bouton « Arrêter » (pose le mot, ne tue rien) |
| `GET /engine`, `POST /engine` | liste et choix d'adresse |
| `GET /plan` | onglet Activité |
| `GET /journal`, `GET /thinking` | affichage vivant pendant le tour |
| `GET /spoken` | wav du tour, joués au fil de l'eau |
| `GET /audio/<nom>` | téléchargement du wav par la porte qui épingle |

**Le pont n'a pas de route de flux.** La phrase provisoire n'existe pas côté serveur : l'app ne
l'invente pas et ne la simule pas. Ce qui est vivant vient de trois routes de relecture — `/journal`,
`/thinking`, `/spoken` — reparties à zéro à chaque tour.

---

## Sécurité

- Le certificat auto-signé du pont est **épinglé** : `res/raw/bridge_cert.pem` est la seule autorité de
  confiance (`network_security_config.xml`), et `Bridge` compare en plus le certificat reçu à celui du
  fichier — remplacer la vérification de nom, que `CN=LA` ne peut pas satisfaire face à une IP.
- Si le certificat du pont est réémis : remplacer `res/raw/bridge_cert.pem`, reconstruire l'APK.
- Le clair n'est autorisé que pour `10.10.0.1` et `192.168.8.2` (réglage du réseau de sécurité).
- La WebView ne charge que des fichiers embarqués ; un lien externe s'ouvre dans le navigateur.
- Aucune sauvegarde cloud, aucun export de données.

---

## Vérifié sur la station

- `gradle assembleDebug` : **exit 0**, `BUILD SUCCESSFUL`.
- APK : `app/build/outputs/apk/debug/app-debug.apk` — **2 186 362 octets**, signé debug,
  sha256 `76b00ed01025a2963cdc616af31a51c42c54f95c3fb4dda38503d5eb1de392e0`.
- `aapt dump badging` : package `fr.la.chat`, minSdk **26**, targetSdk **34**, permissions INTERNET,
  RECORD_AUDIO, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE, SYSTEM_ALERT_WINDOW,
  POST_NOTIFICATIONS.
- `unzip -l` : `assets/index.html`, `assets/app.css`, `assets/app.js`, `res/raw/bridge_cert.pem`.
- `gradle lintDebug` : **0 erreur**.
- Interface rendue hors téléphone (Chromium, 390×844) pendant la mise au point.
- `/home/moussa/Applications/LA-widget` n'a **pas** été modifiée.
