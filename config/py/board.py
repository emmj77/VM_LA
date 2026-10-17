#!/usr/bin/env python3
"""board.py — LE TABLEAU DE LA. Etroit, vivant, et il ne casse pas.

    board.py            LE CONTROLE ligne a ligne (le chargeur), PUIS le tableau vivant (Ctrl-C)
    board.py --once     une passe, puis il sort : code de retour = LE NOMBRE DE DEFAUTS
    board.py --line     UNE ligne pour un bouton de panneau (c'est ce qu'un widget lira)
    board.py --watch 5  redessine toutes les 5 secondes (defaut : 3)

IL EST FAIT POUR UNE FENETRE ETROITE (un tiers d'ecran, ~78 colonnes). Chaque ligne est BATIE pour
la largeur du moment et COUPEE si elle ne rentre pas : rien ne se replie, rien ne casse. rich relit
la taille du terminal a chaque dessin, et un redimensionnement (SIGWINCH) fait redessiner TOUT DE
SUITE -- le tableau est refait, jamais etire.

IL EST VIVANT : chaque tour il relit tout -- les unites systemd, les ports, la table, le canon, les
journaux, la RAM, et LES DERNIERS APPELS DU JOURNAL DU TOUR. Ce n'est pas une photo : c'est ce qui
se passe.

IL EST UN LECTEUR : il ne repare rien, il n'ouvre rien, il n'ecrit rien. Il ne meurt pas non plus :
une sonde qui echoue devient une ligne, jamais une trace de pile -- un tableau qui disparait ne vaut
rien.
"""
import argparse
import glob
import json
import os
import re
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
CONF_DIR = os.path.dirname(HERE)
ROOT = os.environ.get("LA_ROOT") or os.path.dirname(CONF_DIR)
TABLE = os.environ.get("LA_CONFIG", os.path.join(CONF_DIR, "la_tools.yaml"))
CONF = os.environ.get("LA_CONF", os.path.join(CONF_DIR, "la_config.yaml"))
DOCTOR = os.path.join(CONF_DIR, "engine", "doctor.sh")
ENGINE = os.path.join(CONF_DIR, "engine", "engine.sh")
GGUF = os.environ.get("LA_GGUF_DIR", os.path.expanduser("~/LLM_GGUF"))
DB = os.environ.get("LA_DB", os.path.join(CONF_DIR, "sessions.db"))
JOURNAL = os.environ.get("LA_LOG_FILE", "") or os.path.join(ROOT, "work", "journal.jsonl")
FILTRE = os.path.join(CONF_DIR, "filtre", "famille.bin")
SPECS = [os.path.join(ROOT, "projects", "la", "spec.yaml"),
         os.path.join(ROOT, "skills", "la", "spec.yaml")]
VISION = os.path.join(ROOT, "work", "voir.log")
LARGEUR_DEFAUT = 78

RESIDENTS = [("embed", "la-embed.service", 8096, "health"),
             ("rerank", "la-rerank.service", 8095, "health"),
             ("local", "la-local.service", 8088, "health"),
             ("asr", "la-asr.service", 8080, "ready"),
             ("tts", "la-tts.service", 8090, "health")]
APPOINT = [("pont", 8765, "ping", "l'app est eteinte"),
           ("vision", 8091, "health", "il nait a la demande")]
FORMES = r"[A-Za-z0-9_.\-]+\.(?:gguf|onnx|pb|ftz)"
BRIQUES = {"embed": 8096, "rerank": 8095, "local": 8088, "asr": 8080, "tts": 8090}
PORTEURS = ["micro_vision.py", "see_image.py"]


# ----------------------------------------------------------------------------- LES OUTILS DE BASE
def run(cmd, timeout=8):
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           timeout=timeout, text=True)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return -1, ""


def sonde(port, chemin):
    code, out = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "2",
                     "http://127.0.0.1:%d/%s" % (port, chemin)], timeout=6)
    out = out.strip()[:3]
    return out if out.isdigit() and out != "000" else "000"


def vive(unite):
    _, etat = run(["systemctl", "--user", "is-active", unite], timeout=5)
    _, pid = run(["systemctl", "--user", "show", "-p", "MainPID", "--value", unite], timeout=5)
    pid = pid.strip()
    mo = None
    if pid.isdigit() and pid != "0" and os.path.isfile("/proc/%s/status" % pid):
        try:
            with open("/proc/%s/status" % pid, "r") as f:
                for l in f:
                    if l.startswith("VmRSS:"):
                        mo = int(l.split()[1]) // 1024
                        break
        except OSError:
            mo = None
    return etat.strip() or "?", mo, pid


def poids(o):
    if o is None or o < 0:
        return "introuvable"
    if o >= 1073741824:
        return "%.1f Go" % (o / 1073741824.0)
    if o >= 1048576:
        return "%d Mo" % (o // 1048576)
    return "%d Ko" % (o // 1024)


# ------------------------------------------------------------------- LA MISE EN PAGE : UNE LIGNE
def ligne(etiquette, verdict, note="", largeur=LARGEUR_DEFAUT):
    """UNE LIGNE QUI NE DEPASSE JAMAIS `largeur`. Elle ne se replie pas : ce qui ne rentre pas est
    retire dans l'ordre du moins utile -- la queue de la note, puis la note, puis l'etiquette. Le
    VERDICT, lui, reste toujours entier : c'est ce qu'on est venu lire."""
    def batir(et, ve, no, points=True):
        if points:
            reste = ve if not no else "%s   %s" % (ve, no)
            tete = "  %s " % et
            n = largeur - len(tete) - len(reste) - 1
            if n >= 1:
                return tete + "." * n + " " + reste
        return "  %s %s%s" % (et, ve, ("   " + no) if no else "")

    l = batir(etiquette, verdict, note)
    if len(l) <= largeur:
        return l
    if note:                                    # 1. la note perd sa queue
        place = largeur - len("  %s " % etiquette) - len(verdict) - 4
        if place >= 6:
            l = batir(etiquette, verdict, note[:place].rstrip() + "~")
            if len(l) <= largeur:
                return l
        l = batir(etiquette, verdict, "", points=False)
        if len(l) <= largeur:
            return l
    place = largeur - len(verdict) - 4          # 2. l'etiquette se coupe, le verdict reste entier
    if place > 8:
        return "  %s %s" % (etiquette[:place - 1].rstrip() + "~", verdict)
    return ("%s %s" % (etiquette, verdict))[:largeur]


# ---------------------------------------------------------------------------------- LES SONDES
def lire_residents():
    out = []
    for nom, unite, port, chemin in RESIDENTS:
        etat, mo, _ = vive(unite)
        code = sonde(port, chemin) if etat == "active" else "000"
        faute = etat != "active" or code == "000"
        motif = ("eteint (%s)" % etat) if etat != "active" else ("muet" if code == "000" else "")
        out.append((nom, port, etat, code, mo, faute, motif))
    return out


def lire_appoints():
    out = []
    for nom, port, chemin, mot in APPOINT:
        code = sonde(port, chemin)
        out.append((nom, port, code, mot, code == "000"))
    return out


def lire_registre():
    m = {}
    if not os.path.isfile(TABLE):
        return m
    ident = None
    with open(TABLE, "r", errors="replace") as f:
        for l in f:
            s = l.strip()
            if s.startswith("- id:"):
                ident = s[5:].strip()
            elif s.startswith("tool:") and ident:
                m[s[5:].strip()] = ident
    return m


def _modeles_dans(chemin):
    try:
        with open(chemin, "r", errors="replace") as f:
            trouves = re.findall(FORMES, f.read())
    except OSError:
        return []
    noms, vus = [], set()
    for n in trouves:
        n = n.lstrip("-._")
        if len(n) < 4 or n in vus:
            continue
        vus.add(n)
        noms.append(n)
    return noms


def taille_de(nom, pid=None):
    pistes = []
    if pid and pid.isdigit() and os.path.isdir("/proc/%s" % pid):
        try:
            cwd = os.readlink("/proc/%s/cwd" % pid)
            pistes += [os.path.join(cwd, nom), os.path.join(cwd, "models", nom)]
        except OSError:
            pass
    pistes.append(os.path.join(GGUF, nom))
    for p in pistes:
        if os.path.isfile(p):
            return os.path.getsize(p)
    if os.path.isfile(FILTRE) and nom == os.path.basename(FILTRE):
        return os.path.getsize(FILTRE)
    return None


def lire_modeles():
    trouve = {}

    def poser(nom, qui, charge, pid=None):
        if nom not in trouve or charge:
            trouve[nom] = (qui, charge, pid)

    for radical, port in sorted(BRIQUES.items()):
        etat, _, pid = vive("la-%s.service" % radical)
        for nom in _modeles_dans(os.path.join(CONF_DIR, "engine", "%s.sh" % radical)):
            poser(nom, "%s %s" % (radical, port), etat == "active", pid)
    ids = lire_registre()
    for f in sorted(glob.glob(os.path.join(ROOT, "config", "tools", "*", "tool_*.yaml"))):
        nom_tool = os.path.basename(f)[len("tool_"):-len(".yaml")]
        for nom in _modeles_dans(f):
            poser(nom, "%s %s" % (nom_tool, ids.get(nom_tool, "?")), False)
    for f in PORTEURS:
        for nom in _modeles_dans(os.path.join(ROOT, "config", "py", f)):
            poser(nom, f, False)
    if os.path.isfile(FILTRE):
        poser("famille.bin", "filtre 223/224", False)
    lignes = [(nom, taille_de(nom, pid), qui, charge)
              for nom, (qui, charge, pid) in trouve.items()]
    lignes.sort(key=lambda x: (not x[3], x[2]))
    return lignes


def lire_table():
    ids, manquants, doublons = [], [], []
    if not os.path.isfile(TABLE):
        return None
    vus = set()
    with open(TABLE, "r", errors="replace") as f:
        for l in f:
            s = l.strip()
            if s.startswith("- id:"):
                i = s[5:].strip()
                if i in vus:
                    doublons.append(i)
                vus.add(i)
                ids.append(i)
            elif s.startswith("tool:"):
                nom = s[5:].strip()
                if not glob.glob(os.path.join(ROOT, "config", "tools", "*", "tool_%s.yaml" % nom)):
                    manquants.append(nom)
    return len(ids), len(ids) - len(manquants), manquants, doublons


def lire_canon():
    chemin = next((c for c in SPECS if os.path.isfile(c)), None)
    if not chemin:
        return {"chemin": None}
    lois, sections, longs, numeros, doublons = 0, 0, 0, [], []
    with open(chemin, "r", errors="replace") as f:
        for l in f:
            if l.startswith("SECTION : "):
                sections += 1
            elif l.startswith("  ") and ":" in l:
                tete = l.split(":")[0].strip()
                if tete.isdigit():
                    lois += 1
                    if tete in numeros:
                        doublons.append(tete)
                    numeros.append(tete)
            if len(l.rstrip("\n")) > 100:
                longs += 1
    suivi = run(["git", "-C", ROOT, "ls-files", "--error-unmatch", chemin], timeout=6)[0] == 0
    return {"chemin": chemin, "lois": lois, "sections": sections, "longs": longs,
            "doublons": doublons, "suivi": suivi}


def lire_doctor():
    if not os.path.isfile(DOCTOR):
        return None
    code, out = run(["sh", DOCTOR], timeout=60)
    verd = []
    for brut in out.splitlines():
        s = brut.strip()
        if s:
            mot = s.split()[0]
            if mot in ("ok", "fail", "FAULT", "FAUTE", "note"):
                verd.append((mot, s[len(mot):].strip()))
    return verd


def lire_engine():
    """TOUJOURS DEUX VALEURS : un booleen nu ferait tomber l'appelant."""
    if not os.path.isfile(ENGINE):
        return False, -1
    code, out = run(["sh", ENGINE, "104", "config"], timeout=30)
    return ('"status":"ok"' in out or '"status": "ok"' in out), code


def lire_git():
    code, out = run(["git", "-C", ROOT, "status", "--short"], timeout=8)
    if code != 0:
        return None, None
    n = len([l for l in out.splitlines() if l.strip()])
    _, rev = run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], timeout=6)
    return n, rev.strip()


def lire_trafic():
    t = {}
    if os.path.isfile(CONF):
        prov = None
        with open(CONF, "r", errors="replace") as f:
            for l in f:
                s = l.strip()
                if s.startswith("- provider:"):
                    prov = s.split(":", 1)[1].strip()
                elif s.startswith("alias:"):
                    t["alias_tmp"] = s.split(":", 1)[1].strip()
                elif s.startswith("post:"):
                    t["post_tmp"] = s.split(":", 1)[1].strip()
                elif s.startswith("model:"):
                    t["model_tmp"] = s.split(":", 1)[1].strip()
                elif s.startswith("active:") and "true" in s and prov:
                    t["adresse"] = (prov, t.get("alias_tmp", "-"), t.get("model_tmp", "?"),
                                    t.get("post_tmp", "?"))
                    break
    if "adresse" in t:
        code, _ = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "8",
                       "-X", "HEAD", t["adresse"][3]], timeout=12)
        t["joignable"] = str(code) if str(code).isdigit() else "000"
    if os.path.isfile(DB):
        _, a = run(["sqlite3", DB, "SELECT COUNT(*) FROM messages;"], timeout=6)
        _, b = run(["sqlite3", DB, "SELECT COALESCE(MAX(exchange),0) FROM messages;"], timeout=6)
        _, c = run(["sqlite3", DB, "SELECT ts FROM messages ORDER BY id DESC LIMIT 1;"], timeout=6)
        t["sessions"] = (a.strip() or "?", b.strip() or "?")
        t["quand"] = c.strip()
    if os.path.isfile(JOURNAL):
        _, echecs = run(["grep", "-c", "echec de transport", JOURNAL], timeout=6)
        t["journal"] = (os.path.getsize(JOURNAL), echecs.strip() or "0")
    elif JOURNAL:
        t["journal_absent"] = JOURNAL
    if os.path.isfile(VISION):
        t["vision_log"] = os.path.getsize(VISION)
    return t


def lire_tour():
    """CE QUI TRANSITE : les derniers appels du journal du tour (JSONL). C'est la partie VIVANTE --
    ce que LA vient de demander, a la seconde."""
    if not os.path.isfile(JOURNAL):
        return []
    code, out = run(["tail", "-n", "120", JOURNAL], timeout=6)
    if code != 0:
        return []
    lus = []
    for l in out.splitlines():
        l = l.strip()
        if not l.startswith("{"):
            continue
        try:
            o = json.loads(l)
        except ValueError:
            continue
        if not isinstance(o, dict):
            continue
        appel = o.get("tool_call") or {}
        fonc = appel.get("function") or {}
        nom = fonc.get("name") or appel.get("type") or "?"
        args = fonc.get("arguments") or o.get("la") or ""
        # « la » est le porteur : ce qui compte, c'est CE QU'IL DEMANDE (g = l'id du tool, a = ses
        # arguments). Un journal qui ne dit que « la » ne dit rien.
        detail = ""
        if isinstance(args, str) and args.strip().startswith("{"):
            try:
                d = json.loads(args)
                if isinstance(d, dict) and ("g" in d or "a" in d):
                    detail = "g=%s a=%s" % (d.get("g", "?"), d.get("a", ""))
            except ValueError:
                detail = ""
        elif isinstance(args, dict):
            detail = "g=%s a=%s" % (args.get("g", "?"), args.get("a", ""))
        lus.append((str(o.get("ts", ""))[11:19], "n°%s" % str(o.get("turn", "?")), str(nom),
                    detail or str(args)[:60]))
    return lus[-4:]


def lire_machine():
    m = {}
    _, mo = run(["free", "-m"], timeout=6)
    for l in mo.splitlines():
        if l.startswith("Mem:"):
            p = l.split()
            if len(p) >= 7:
                m["ram"] = (int(p[2]), int(p[1]), int(p[6]))
        elif l.startswith(("Swap:", "Echange:")):
            p = l.split()
            if len(p) >= 3:
                m["echange"] = int(p[2])
    _, gpu = run(["nvidia-smi", "--query-gpu=name,memory.used,memory.total,utilization.gpu",
                  "--format=csv,noheader"], timeout=8)
    m["cartes"] = []
    for l in gpu.splitlines():
        p = [x.strip() for x in l.split(",")]
        if len(p) == 4:
            m["cartes"].append((" ".join(p[0].split()[-2:]), p[1], p[2], p[3]))
    _, df = run(["df", "-h", ROOT], timeout=6)
    for l in df.splitlines()[1:2]:
        p = l.split()
        if len(p) >= 5:
            m["disque"] = (p[5], p[2], p[1], p[3])
    return m


def depuis(ts):
    if not ts:
        return ""
    try:
        t = time.mktime(time.strptime(ts[:19].replace("T", " "), "%Y-%m-%d %H:%M:%S"))
    except ValueError:
        return ""
    d = int(time.time() - t)
    if d < 0:
        return ""
    if d < 90:
        return "il y a %ds" % d
    if d < 5400:
        return "il y a %dmin" % (d // 60)
    return "il y a %dh" % (d // 3600)


# --------------------------------------------------------------------------------- LE CONTROLE
def controle(leger=False):
    """LE CONTROLE. `leger=True` : les mesures qui repondent en un souffle (les unites, les ports,
    la table, le trafic). C'est ce qu'un BOUTON DE PANNEAU peut se permettre toutes les 30 s ; le
    docteur, lui, coute des secondes, et il n'entre QUE dans la version complete."""
    res = lire_residents()
    appoints = lire_appoints()
    table = lire_table()
    trafic = lire_trafic()
    canon = {"chemin": None} if leger else lire_canon()
    docteur = None if leger else lire_doctor()
    ok_engine = False if leger else lire_engine()[0]
    non_commite, rev = (None, None) if leger else lire_git()

    fautes = [r[6] for r in res if r[5]]
    if table is not None:
        fautes += ["sans corps : " + n for n in table[2]] + ["id double : " + n for n in table[3]]
    if docteur:
        fautes += [x[1] for x in docteur if x[0] in ("fail", "FAULT", "FAUTE")]
    if not leger and canon.get("chemin") is None:
        fautes.append("le canon est introuvable")

    L = []
    L.append(("LA status", "actif" if not fautes else "disabled", bool(fautes)))
    if leger:
        L.append(("residents", "%d/%d actifs" % (len([r for r in res if not r[5]]), len(res)),
                  len([r for r in res if not r[5]]) != len(res)))
        L.append(("table", "absente" if table is None else "%d/%d" % (table[0], table[1]),
                  table is None or bool(table[2] or table[3])))
        for nom, port, code, mot, muet in appoints:
            L.append((nom, "muet" if muet else "repond " + code, False))
        if "adresse" in trafic:
            L.append(("api", "%s : %s" % (trafic["adresse"][0], trafic["adresse"][2]), False))
            muet = trafic.get("joignable") == "000"
            L.append(("api status", "pas de reponse" if muet else "connected", muet))
        if "journal" in trafic:
            taille, echecs = trafic["journal"]
            L.append(("journal", "%s / %s echec" % (poids(taille), echecs), echecs not in ("0", "")))
        return L, fautes, res, appoints, table, canon, docteur, trafic
    L.append(("engine", "ok" if ok_engine else "ne repond pas", not ok_engine))
    if table is None:
        L.append(("table", "absente", True))
    else:
        L.append(("table", "%d/%d" % (table[0], table[1]), bool(table[2] or table[3])))
    if canon.get("chemin"):
        L.append(("canon", "%d lois / %d sections" % (canon["lois"], canon["sections"]),
                  bool(canon["doublons"] or canon["longs"])))
    etat_git = "suivi" if canon.get("suivi") else "hors depot"
    if non_commite:
        etat_git += " / %d non commite" % non_commite
    if rev:
        etat_git += " @%s" % rev
    L.append(("git", etat_git, canon.get("chemin") is not None and not canon["suivi"]))
    if docteur is None:
        L.append(("doctor", "absent", True))
    else:
        nko = len([x for x in docteur if x[0] in ("fail", "FAULT", "FAUTE")])
        L.append(("doctor", "%d ok / %d defaut" % (len([x for x in docteur if x[0] == "ok"]), nko),
                  nko > 0))
    L.append(("erreurs", str(len(fautes)), bool(fautes)))
    actifs = len([r for r in res if not r[5]])
    L.append(("residents", "%d/%d actifs" % (actifs, len(res)), actifs != len(res)))
    L.append(("ram de LA", "%d Mo" % sum(r[4] for r in res if r[4]), False))
    if "adresse" in trafic:
        prov, alias, mod, post = trafic["adresse"]
        L.append(("api", "%s : %s" % (prov, mod), False))
        L.append(("endpoint", post, False))
        muet = trafic.get("joignable") == "000"
        L.append(("api status", "pas de reponse" if muet else "connected", muet))
    if trafic.get("sessions"):
        L.append(("sessions", "%s echanges / derniere n° %s" % (trafic["sessions"][1],
                                                                trafic["sessions"][0]), False))
    if trafic.get("quand"):
        L.append(("last_activity", "%s %s" % (trafic["quand"][:19], depuis(trafic["quand"])), False))
    if "journal" in trafic:
        taille, echecs = trafic["journal"]
        L.append(("journal", "%s / %s echec" % (poids(taille), echecs), echecs not in ("0", "")))
    elif "journal_absent" in trafic:
        L.append(("journal", "annonce mais absent", True))
    for nom, port, code, mot, muet in appoints:
        L.append((nom, "muet" if muet else "repond " + code, False))
    return L, fautes, res, appoints, table, canon, docteur, trafic


# ------------------------------------------------------------------------------------ LE TABLEAU
def sections(largeur):
    L, fautes, res, appoints, table, canon, docteur, trafic = controle()
    out = [ligne(x[0], x[1], "", largeur) for x in L]

    out.append("")
    out.append("CE QUI TRANSITE")
    tour = lire_tour()
    if not tour:
        out.append("  le journal est muet (aucun appel enregistre)")
    for ts, n, nom, detail in tour:
        out.append(ligne("%s  %s" % (ts or "--:--:--", n), nom, detail, largeur))

    out.append("")
    out.append("LES MODELES DE LA")
    modeles = lire_modeles()
    if not modeles:
        out.append("  aucun : nos morceaux n'en nomment aucun")
    for nom, taille, qui, charge in modeles:
        out.append(ligne(nom, "CHARGE" if charge else "repos", "%s   %s" % (poids(taille), qui),
                         largeur))
    nch = len([m for m in modeles if m[3]])
    out.append("  %d modeles : %d en memoire, %d a l'appel" % (len(modeles), nch, len(modeles) - nch))

    machine = lire_machine()
    out.append("")
    out.append("LA MACHINE")
    if "ram" in machine:
        u, tot, lib = machine["ram"]
        out.append(ligne("ram", "%d/%d Mo" % (u, tot), "%d dispo" % lib, largeur))
    for nom, use, tot, pc in machine.get("cartes", []):
        out.append(ligne("carte", "%s %s/%s" % (nom, use.split()[0], tot.split()[0]), pc, largeur))
    if "disque" in machine:
        d = machine["disque"]
        out.append(ligne("disque", "%s %s/%s" % (d[0], d[1], d[2]), "%s libres" % d[3], largeur))
    return out, fautes


def une_ligne():
    """LE BOUTON : une seule ligne courte, pour un panneau ou un widget. MESURES LEGERES : cette
    ligne se demande toutes les trente secondes, elle ne peut pas payer le docteur."""
    L, fautes, *_ = controle(leger=True)
    d = dict((x[0], x[1]) for x in L)
    # LA VALEUR SEULE, SANS PREFIXE : l'applet meteo affiche « 27 °C », pas « meteo 27 °C » -- c'est
    # le dessin a cote qui dit de quoi il parle. Le « LA » en plus faisait 17 pixels de trop dans une
    # barre, et la silhouette de l'applet n'etait plus celle de la meteo.
    return "%s | %s | table %s | api %s" % (d.get("LA status", "?"), d.get("residents", "?"),
                                            d.get("table", "?"), d.get("api status", "?"))


SIGNE = {"change": False}


def _sigwinch(sig, cadre):
    SIGNE["change"] = True


# ------------------------------------------------------------------- LE CADRE : DU TEXTE, RIEN D'AUTRE
# PAS DE BIBLIOTHEQUE POUR DESSINER. Le 17/10 rich a paye une fois : son Live suivait le curseur en
# comptant ses lignes, et des que le contenu demandait plus de lignes que la fenetre n'en avait, le
# compte etait faux -- la fenetre defilait d'une ligne a chaque rafraichissement et le tableau
# s'empilait sur lui-meme. Ce qu'il faut tenir tient en trois regles, et les trois se mesurent :
#   1. CHAQUE LIGNE EST BATIE POUR LA LARGEUR DU MOMENT (`ligne()`) -- jamais de repli.
#   2. ON N'ECRIT JAMAIS LA DERNIERE COLONNE (largeur - 1) : le terminal y declenche un retour.
#   3. ON N'ECRIT JAMAIS LA DERNIERE LIGNE (hauteur - 1) : un retour a la ligne la ferait DEFILER.
# Et l'ecran est un ECRAIN ALTERNATIF : on ne peint pas par-dessus la console de l'utilisateur, on
# lui rend la sienne intacte en sortant.
def teinte(l):
    if l.startswith(("CE QUI", "LES ", "LA ")):
        return "\033[36m" + l + "\033[0m"          # cyan : les titres
    if l.rstrip().endswith("!!") or " !! " in l or "defaut(s)" in l:
        return "\033[31m" + l + "\033[0m"          # rouge : ce qui ne va pas
    if l.lstrip().startswith("LA status") and "actif" in l:
        return "\033[32m" + l + "\033[0m"          # vert : LA tient
    return l


def cadre(largeur, hauteur):
    """LES LIGNES DU TABLEAU, bornees a (largeur, hauteur). Le compte des defauts sort avec."""
    out, fautes = sections(largeur)
    tete = ["LA — LE TABLEAU   %s UTC   %d colonnes" % (time.strftime("%H:%M:%S", time.gmtime()),
                                                        largeur), ""]
    # L'EN-TETE PASSE PAR LA MEME BORNE QUE LE RESTE : une seule ligne hors largeur suffit a faire
    # replier la fenetre, et un repli decale TOUT ce qui suit.
    return [(l if len(l) <= largeur else l[:largeur]) for l in tete + out][:hauteur], fautes


def main():
    ap = argparse.ArgumentParser(description="le tableau de LA : ce qui est charge, et ce qui se passe")
    ap.add_argument("--once", action="store_true", help="une passe, puis il sort (code = defauts)")
    ap.add_argument("--line", action="store_true", help="une ligne pour un bouton de panneau (leger)")
    ap.add_argument("--check", action="store_true",
                    help="la liste de controle seule, en colonnes (pour un terminal)")
    ap.add_argument("--menu", action="store_true",
                    help="la liste pour un menu : « etat|etiquette|verdict », une ligne par mesure")
    ap.add_argument("--watch", type=float, default=3.0, help="secondes entre deux dessins")
    ap.add_argument("--largeur", type=int, default=0, help="largeur forcee (defaut : le terminal)")
    a = ap.parse_args()

    if a.line:
        print(une_ligne())
        return 0

    if a.check:
        largeur = a.largeur or int(os.environ.get("COLUMNS") or 0) or 64
        L, fautes, *_ = controle()
        print("\n".join(ligne(x[0], x[1], "", largeur) for x in L))
        return 1 if fautes else 0

    if a.menu:
        # LA LISTE POUR UN MENU. Un menu n'est pas un terminal : des colonnes de points de conduite
        # y partent en brouillard des que la police n'est pas a chasse fixe, et dix-sept lignes de
        # soixante-douze caracteres font un pave gris. On rend donc des lignes COURTES, une par
        # mesure, precede d'un etat : « ko|table : 115/113 ». Le TABLEAU dit l'etat, l'applet decide
        # comment le montrer (une ligne de menu, et du rouge sur les fautes).
        L, fautes, *_ = controle(leger=True)
        # TROIS CHAMPS SEPARES PAR UNE BARRE : etat, etiquette, verdict. L'applet n'a rien a
        # decouper elle-meme -- un verdict peut contenir « : » (« ollama-cloud : deepseek-v4.1-flash »)
        # et un decoupage devine casserait les deux colonnes.
        print("\n".join("%s|%s|%s" % ("ko" if x[2] else "ok", x[0], x[1]) for x in L))
        return 1 if fautes else 0

    if a.once:
        largeur = a.largeur or int(os.environ.get("COLUMNS") or 0) or LARGEUR_DEFAUT
        out, fautes = sections(largeur)
        print("\n".join(out))
        return 1 if fautes else 0

    try:
        signal.signal(signal.SIGWINCH, _sigwinch)
    except (ValueError, AttributeError, OSError):
        pass
    # LE CADRE VIVANT : effacer, redessiner, rien d'autre. Aucun curseur a suivre, donc rien qui
    # puisse se decaler ou s'empiler.
    sortie = sys.stdout
    alt = "[?1049h" if sortie.isatty() else ""
    sortie.write(alt + "[?25l" + "[2J")
    sortie.flush()
    try:
        while True:
            try:
                t = os.get_terminal_size(1)
                largeur, hauteur = t.columns, t.lines
            except OSError:
                largeur, hauteur = (a.largeur or LARGEUR_DEFAUT), 46
            largeur = a.largeur or largeur
            try:
                lignes, fautes = cadre(max(24, largeur - 1), max(6, hauteur - 1))
                bloc = "\033[H" + "\n".join(teinte(l) + "\033[K" for l in lignes) + "\033[J"
            except Exception as e:
                # UN TABLEAU QUI DISPARAIT NE VAUT RIEN : la faute devient une ligne, pas une mort.
                bloc = "\033[H  le tableau a echoue : %s\033[K\033[J" % e
            sortie.write(bloc)
            sortie.flush()
            SIGNE["change"] = False
            t = 0.0
            while t < a.watch and not SIGNE["change"]:
                time.sleep(0.25)
                t += 0.25
    finally:
        sortie.write("\033[?25h" + ("\033[?1049l" if alt else "") + "\033[J")
        sortie.flush()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
