# LA — LE CHAT ENTRE AGENTS : CE QUE JE POSERAIS (proposition, rien n'est pose)

Date : 16/10/2026 — auteur : Hermes (session hote) — releve du code : 20h55 UTC.
Ce document n'est pas une etude de plus : c'est **le patch**, ligne par ligne, de la **premiere
pose** — celle qui fait parler deux agents. Il attend ton oui, piece par piece. Rien n'est pose.

**Ce que cette pose achete** : un agent ecrit a un autre (`send_agent_chat`), le message entre
**tout seul** dans le head secondaire du destinataire, une seule fois, borne, signe — et **rien
n'est jamais perdu en silence**.

**Ce qu'elle n'achete pas** (les pieces suivantes, dans l'ordre du §5 de l'etude) : les pages dans
`sessions.db`, la fenetre des agents (nom / pid / statut), le journal par agent, la fenetre des
tools, le sous-agent nomme par mission, le sommeil et le juge. **Rien de la memoire.**

**Cinq fichiers toucheraient, pas un de plus** :
`config/engine/loop.sh`, `config/engine/bridge.sh`, `config/engine/second.sh`,
`config/la_tools.yaml`, `skills/agent/skill.yaml`.
Et deux fichiers qui naitraient d'eux-memes : `work/agent_chat.jsonl` (le tableau, a la premiere
ecriture) et `work/chat.<nom>.seen` (les filigranes, a la fin du premier tour). Le registre de
travail existe deja — **aucun dossier n'est cree**.

---

## EPROUVE, PAS SUPPOSE

Le coeur de ce patch **a tourne**, en `dash`, hors du projet, sur un faux tableau (mon brouillon :
`~/.hermes/cache/scratch/pose1_test.sh`). Ce que la sortie a montre : la ligne compacte (une ligne
par message), le filigrane qui joue (deuxieme regard : « 0 message »), la fenetre qui **refuse** un
message trop long au lieu de le couper (« borne atteinte : ... attend le prochain appel »), le
drapeau « des messages ont disparu » qui **se repare tout seul**, la purge qui passe de 38 a 24
lignes **sans rien laisser derriere elle**, et un corps piege (`$(rm -rf /)`, backticks,
guillemets, antislash) qui reste un **texte** de 165 octets sur une seule ligne.

**Deux bugs ont ete trouves par l'execution** — et corriges dans ce qui suit : `jq` **imprimait le
JSON sur cinq lignes** (il manquait `-c` : le tableau n'aurait plus ete une ligne par message, et le
filigrane aurait lu `}` au lieu d'un id), et un corps **a plusieurs lignes** cassait la relecture
(il faut `gsub("\n"; " ")`). Rien n'est pose : c'est la proposition, eprouvee.

---

## PIECE 1 — LE NOM DU TOUR (le fait dont tout depend)

Sans lui, aucun message ne se signe et aucun ne s'adresse. Le nom est **pose par le lanceur**,
comme `LA_VOICE` et `LA_STOP_FILE` aujourd'hui : le modele ne le choisit jamais (loi 206).

**1a. `config/engine/loop.sh`** — apres le bloc de `LA_VOICE` (l.226-231), en remplacant la ligne
d'export (l.232) :

```sh
# THE TURN'S NAME. It comes from the LAUNCHER, like LA_VOICE and LA_STOP_FILE : the model
# never chooses it (law 206 : a declaration is changed by the human). It SIGNS what this
# turn writes and it NAMES its mailbox. Without a launcher that poses it, the turn is
# called `agent` - a fact, not a default that hides anything.
LA_FROM=${LA_FROM:-agent}
# The name becomes a FILE NAME (a watermark today, a journal tomorrow) : so it is checked
# ONCE, here. A name that does not fit is REPLACED - and SAID, because a silence is a lie.
case "$LA_FROM" in
  *[!a-z0-9_-]*|"") printf 'loop: nom de tour invalide (%s) : ce tour s appelle agent\n' "$LA_FROM" >&2
                    LA_FROM=agent ;;
esac
export LA_DEPTH LA_FROM LA_ROOT="$ROOT" LA_CONFIG="$TABLE"
```

**1b. `config/engine/bridge.sh`, `turn()`** (l.170-175) — un quatrieme argument, et les trois
appels :

```sh
  # $4 = THE TURN'S NAME : the launcher poses it, the model never does. The human's turn is
  # `human` ; a sub-agent's turn will be the name its parent gave it (a later piece).
  NAME="${4:-human}"
  if mkfifo "$FIFO" 2>/dev/null; then
    if [ "${3:-}" = voice ]; then
      printf '%s\n' "$1" | LA_FROM="$NAME" LA_VOICE=1 LA_LOG_FILE="$JOURNAL" LA_STOP_FILE="$STOP" "$SH" "$LOOP" > "$T/reply" 2> "$FIFO" &
    else
      printf '%s\n' "$1" | LA_FROM="$NAME" LA_LOG_FILE="$JOURNAL" LA_STOP_FILE="$STOP" "$SH" "$LOOP" > "$T/reply" 2> "$FIFO" &
    fi
```

et les trois appels (l.359, l.393, l.478) deviennent :

```sh
          turn "$D" "$T/out"        text  human      # l.359, la demande tapee
              turn "$D" "$T/out1"   voice human      # l.393, la demande venue par la voix
              turn "$REQUEST" "$T/out1" text human   # l.478, la photo
```

**Ce que ca coute** : deux lignes dans le pont, quatre dans la boucle. **Ce que ca donne** : le nom
existe, il est verifie une fois, et il est **exporte** — donc le corps de chaque commande le voit.

---

## PIECE 2 — LE TABLEAU (le fichier)

Un fichier, un chemin, une forme. **Le chemin est unique pour les trois qui le lisent**
(l'outil, la fenetre, la boucle) : `$ROOT/work/agent_chat.jsonl` — le registre de travail ou le
journal du tour s'ecrit deja (`loop.sh`, l.1166). Un seul chemin, pris aux trois endroits : le jour
ou un skill declarera un autre espace de travail, c'est ce chemin qu'il faudra reprendre (le journal
du tour ne le resout pas non plus aujourd'hui).

**Une ligne = un message**, en JSONL, ecrite par **un seul `printf`** (la mesure M1 : sous 6 000
octets, huit ecrivains simultanes ne se coupent jamais) :

```json
{"id":"2026-10-16T21:05:12Z-4711","ts":"2026-10-16T21:05:12Z","from":"paul","to":"jarvis","body":"..."}
```

- `id` = l'horodatage **plus le pid** : unique sans table, sans compteur, sans verrou ;
- `from` = le nom du tour (`LA_FROM`), **jamais** choisi par le modele ;
- `to` = le destinataire, refuse s'il n'est pas **grave** (piece 3) ;
- `body` = le corps, borne a **1024 octets** (ton « limite de taille de message » : c'est elle) ;
  ses retours a la ligne s'affichent comme des espaces dans la fenetre — une ligne de tableau est un
  message, et la fenetre compte des lignes ;
- `ts` = le proc, horodate a la seconde.

**Le tableau est plafonne** : au-dela de **24 lignes**, son **dernier ecrivain** le reecrit avec ses
24 dernieres (loi 1200 : jamais un `rm` — une reecriture). Cette reecriture ouvre la fenetre de
perte que le banc a mesuree (M2 : 3,9 % dans le pire cas) : elle ne tourne que quand le tableau
depasse son plafond, et **ce qui echappe a un lecteur est dit par ce lecteur** (piece 4).

---

## PIECE 3 — `send_agent_chat` (id 180), ET SA PALETTE

**3a. `config/la_tools.yaml`** — le nouveau bloc, **a la fin du fichier** (apres le bloc 179 qui
ferme a la ligne 1499). Jamais au milieu, jamais renumerote (loi 1019) :

```yaml
  - id: 180
    tool: send_agent_chat
    family: MANAGE
    description: "writes ONE message onto an agent's board, and never more than one"
    args:
      - {name: to, type: enum, values: [jarvis, paul, albert, eleonore, claire]}
      - {name: body, type: text, stdin: true}
    command: |
      # THE NAMES ARE ENGRAVED HERE, and nowhere else. The engine refuses a name that is not
      # on this list, NAMING the list : nothing to code. The day delegate_task names a child
      # (a later piece), this list will have to live in ONE place - that day, and not before.
      N=${LA_FROM:-agent}
      D="{{to}}"
      T=$(cat)
      [ -n "$T" ] || { echo "refuse : un message vide ne s ecrit pas" >&2; exit 1; }
      [ "$D" != "$N" ] || { echo "refuse : $N ne s ecrit pas a lui-meme" >&2; exit 1; }
      S=$(printf '%s' "$T" | wc -c)
      [ "$S" -le 1024 ] || { echo "refuse : le corps fait $S octets ; la borne est 1024" >&2; exit 1; }
      BB="$ROOT/work/agent_chat.jsonl"
      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      ID="$TS-$$"
      L=$(printf '%s' "$T" | jq -Rsc --arg i "$ID" --arg t "$TS" --arg f "$N" --arg d "$D" \
            '{id:$i, ts:$t, from:$f, to:$d, body:.}')
      NB=$(printf '%s' "$L" | wc -c)
      [ "$NB" -le 1600 ] || { echo "refuse : la ligne fait $NB octets" >&2; exit 1; }
      printf '%s\n' "$L" >> "$BB" || { echo "refuse : le tableau ne s est pas laisse ecrire ($BB)" >&2; exit 1; }
      # THE BOARD IS CAPPED, AND ITS LAST WRITER PURGES IT. Nothing is deleted : the file is
      # REWRITTEN with its last CAP lines (law 1200 : no rm, no link). The temporary is
      # CONSUMED by the move ; if the move fails it STAYS, and it is named.
      CAP=24
      LN=$(wc -l < "$BB")
      if [ "$LN" -gt "$CAP" ]; then
        TM="$BB.tmp.$$"
        if tail -n "$CAP" "$BB" > "$TM"; then
          mv -f -- "$TM" "$BB" || { echo "refuse : la purge n a pas abouti ; le temporaire est reste en place ($TM)" >&2; exit 1; }
        else
          echo "refuse : la purge n a pas abouti ; le temporaire est reste en place ($TM)" >&2; exit 1
        fi
      fi
      printf 'message ecrit pour %s (id %s) : %s octets\n' "$D" "$ID" "$S"
```

**3b. `skills/agent/skill.yaml`** — la palette qui porte l'outil. `delegate_task` y est deja ; le
chat se pose **a cote de lui**, dans le meme foyer (la skill des agents) :

```yaml
TOOLS:
  200: "delegate_task"
  201: "send_agent_chat"
```

**Les deux lignes se posent ensemble** : une palette qui nomme un outil absent de la table est
une palette cassee. C'est la seule contrainte de cette piece.

**Ce que le code garantit deja, sans une ligne de plus** *(releve dans `engine.sh`, l.58-70)* : le
moteur **refuse** un texte qui porterait ce qui casse les guillemets (guillemet, dollar, backtick,
antislash, caractere de controle), et le corps (**`stdin: true`**) **ne monte jamais dans la
commande** — il entre par l'entree standard. Un `to` hors liste est refuse **en rendant la liste**.
Rien a coder pour la garde : elle est deja dans le moteur.

---

## PIECE 4 — LA FENETRE DES MESSAGES (`second.sh`)

**4a. Les plafonds** — a ajouter apres la ligne des caps (l.31-36) :

```sh
CAP_MSG_L=14;    CAP_MSG_C=1200
```

**4b. La section** — inseree **juste apres le bloc de `THE TASK`** (l.48), avant le commentaire
`# ---- THE LOADED SKILL PLAN` :

```sh
# ---- THE AGENT MESSAGES : what the other sessions wrote to THIS one ----------
# READ here, never WRITTEN here : second.sh is called dozens of times per turn. The LAST line
# carries the watermark - the id of the last message SHOWN ENTIRELY - in a shape the LOOP
# strips before the head ever reaches the model : [chat-seen:<id>]. No message is ever shown
# by halves : what does not fit the declared bound WAITS for the next call, in order.
printf '== THE AGENT MESSAGES ==\n'
ME=${LA_FROM:-agent}
BB="$ROOT/work/agent_chat.jsonl"
SEEN="$ROOT/work/chat.$ME.seen"
if [ ! -r "$BB" ]; then
  printf 'aucun tableau lisible (%s)\n' "$BB" | bound "$CAP_MSG_L" "$CAP_MSG_C"
else
  LAST=
  [ -f "$SEEN" ] && LAST=$(head -n 1 "$SEEN" 2>/dev/null)
  # WHAT ESCAPED : the watermark is older than the first line the purge kept. It is SAID here,
  # by the one it happened to (law 502) - and it heals itself : the board below is shown whole.
  ESC=$(jq -r -s --arg last "$LAST" \
        'if $last == "" then 0 else (if ([.[].id] | index($last)) == null then 1 else 0 end) end' \
        "$BB" 2>/dev/null) || ESC=
  case "$ESC" in
    1) printf 'DES MESSAGES ONT DISPARU avant que je les lise : mon filigrane est tombe hors du tableau\n' ;;
    *) : ;;
  esac
  LIST=$(jq -r -s --arg me "$ME" --arg last "$LAST" '
        . as $all
        | ($all | map(.id) | index($last)) as $i
        | (if $last == "" then 0 elif $i == null then 0 else $i + 1 end) as $start
        | $all[$start:][] | select(.to == $me and .from != $me)
        | "\(.id)\t\(.from)\t\(.ts)\t\(.body | gsub("\n"; " "))"' "$BB" 2>/dev/null) || LIST=
  printf '%s message(s) pour moi\n' "$(printf '%s\n' "$LIST" | grep -c .)"
  USED=0
  SHOWN=0
  IDLAST=
  while IFS='	' read -r id src ts body; do
    [ -n "$id" ] || continue
    NEED=$(printf '%s\n' "$body" | wc -c)
    NEEDL=$(printf '%s\n' "$body" | wc -l)
    if [ $((USED + NEED + 90)) -gt "$CAP_MSG_C" ] || [ $((SHOWN + NEEDL + 1)) -gt "$CAP_MSG_L" ]; then
      printf 'borne atteinte : %s et les suivants attendent le prochain appel\n' "$src"
      break
    fi
    USED=$((USED + NEED + 90))
    SHOWN=$((SHOWN + NEEDL + 1))
    printf '%s ecrit a %s :\n%s\n' "$src" "$ts" "$body"
    IDLAST="$id"
  done <<EOF
$LIST
EOF
  [ -n "$IDLAST" ] && printf '[chat-seen:%s]\n' "$IDLAST"
fi
```

**4c. L'horodatage descend a la fin.** Mesure M3 : entre deux appels, **la seule ligne qui bouge**
dans le head secondaire est `== THE TIMESTAMP ==`. Le bloc (l.70-76) se **deplace a la toute fin du
fichier**, apres la section `THE ACTIVE SKILL` — il reste imprime, il est simplement **le dernier**.
Et le commentaire d'en-tete du fichier (l.4-9) qui liste les sections dans l'ordre se met a jour
d'une ligne, sinon il mentirait sur son propre ordre.

---

## PIECE 5 — LE FILIGRANE (dans la boucle, une fois)

**5a. `read_second()`** (`loop.sh`, l.741) — deux lignes pour prendre le marqueur, et le retirer :

```sh
    S2=$("$SECOND_HEAD" "$REQUEST" 2>/dev/null) || S2=''
    # LE FILIGRANE DU CHAT : la section marque son dernier message MONTRE EN ENTIER. La ligne
    # est RETIREE avant que le head ne parte (le modele ne la voit jamais) et c'est la boucle
    # qui l'ecrit, une seule fois, en fin de tour.
    CHAT_SEEN=$(printf '%s' "$S2" | sed -n 's/^\[chat-seen:\(.*\)\]$/\1/p' | tail -n 1)
    case "$CHAT_SEEN" in
      '') : ;;
      *)  S2=$(printf '%s' "$S2" | sed -e '/^\[chat-seen:[^]]*\]$/d') ;;
    esac
```

**5b. L'ecriture du filigrane** (`loop.sh`) — juste avant `signal_task` (l.1169), apres
`session_note` :

```sh
# LE FILIGRANE S ECRIT UNE FOIS, EN FIN DE TOUR : ce qui m a ete montre est lu. Jamais dans
# second.sh, qui est appele des dizaines de fois. S il ne s ecrit pas, il le DIT.
if [ -n "$CHAT_SEEN" ]; then
  printf '%s\n' "$CHAT_SEEN" > "$ROOT/work/chat.$LA_FROM.seen" \
    || printf 'loop: le filigrane du chat ne s est pas ecrit (%s)\n' "$ROOT/work/chat.$LA_FROM.seen" >&2
fi
```

**La regle, en une phrase** : *ce qui m'a ete montre en entier est lu ; ce qui n'a pas tenu attend
le prochain appel, dans l'ordre ; ce qui a disparu avant que je le lise, je le dis.* Aucune perte
muette, et **au pire une relecture** — jamais un message escamote.

---

## PIECE 6 — LES VERDICTS (B23 a B28)

Le banc tourne **d'abord** : les verdicts s'ecrivent avant, ils tombent rouges, et c'est leur
couleur qui dit que la piece est posee. Ils sont deja nommes au §6 de l'etude. **Je n'ecris pas leur
code maintenant** : le banc a bouge ce soir (18h47) par une autre passe, et j'ecris un verdict
contre son etat du moment, pas contre un etat d'hier. Ils viendront avec la pose, dans le meme
mouvement — B23 (huit tours, lignes de 4096 : chaque ligne relue entiere), B24 (la purge laisse le
tableau relisible, et ce qui a echappe est nomme), B25 (un message de `paul` entre **nomme** dans le
head de `jarvis`, et ne revient jamais), B26 (temoin : un message ne change pas le perimetre du
destinataire), B27 (un nom hors liste est refuse **avec la liste**), B28 (aucun `rm`, aucun lien —
lois 1200-1201).

---

## CE QUI ATTEND TA REPONSE (cinq points, et chacun change des lignes)

1. **LES NOMS.** Les cinq agents sont `jarvis` (l'agent principal), `paul`, `albert`, `eleonore`, `claire`.
   Le chat ne passe qu'entre eux : aucun autre nom n'entre dans `from` ni `to`.
2. **LES NOMBRES.** Corps **1024** octets ; fenetre **1200 octets / 14 lignes** ; tableau plafonne a
   **24 lignes**. Ce sont des plafonds **declares** : ils se lisent, ils se discutent. Moins ? Plus ?
3. **LA PURGE.** Je propose la **forme (iii)** : le dernier ecrivain purge quand le tableau depasse
   son plafond (la fenetre de perte M2 : 3,9 % dans le pire cas, jamais silencieuse). L'alternative
   est **(i) jamais purge** — le plus simple, mais le fichier grossit sans fin (loi 1604). La forme
   **(ii)** — purger quand personne n'est eveille — arrivera **avec la fenetre des agents**, qui dit
   justement qui est eveille.
4. **LE FILIGRANE.** Exact par **marqueur** (la piece 5 : ~15 lignes, aucune perte, au pire une
   relecture) ou approximatif par **queue de tableau** (3 lignes, mais la queue d'un message peut
   etre perdue — je ne le propose pas).
5. **L'HORODATAGE.** Je le descends a la fin du head secondaire (piece 4c) : une ligne deplacee, et
   tout ce qui suit devient stable entre deux appels. D'accord ?

Et la question de chantier, qui n'est pas technique : **cette pose passe avant ou apres la passe
memoire en cours ?** (`sessions.db` est son corps depuis ce soir ; les pages viendront *avec* elle,
pas a cote.)

---

## CE QUE CETTE POSE NE TOUCHE PAS

- **pas de memoire** : ni `sessions.db`, ni `memory/`, ni le tool `note` (id 108) ;
- **pas de pages** : la table des sessions attend la passe memoire ;
- **pas de fenetre des agents**, **pas de journal par agent**, **pas de fenetre des tools** : pieces
  suivantes ;
- **pas de sous-agent nomme**, **pas de sommeil**, **pas de juge** : la piece 6 de l'ordre, et elle
  depend du choix A / B qui est encore ouvert ;
- **aucun `rm`, aucun lien, aucun dossier neuf, aucun port neuf** (lois 1200-1201, 469) ;
- **aucune decision prise** : tout ce qui precede attend ton annotation.
