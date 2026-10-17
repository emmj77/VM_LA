#!/usr/bin/env python3
"""board.py — LE TABLEAU DE LA. Une colonne. La liste de controle, puis l'etat des morceaux.

    board.py            LA LISTE DE CONTROLE, ligne a ligne, PUIS le tableau vivant (Ctrl-C sort)
    board.py --once     la meme chose en une passe et il sort : code de retour = NB DE DEFAUTS
    board.py --watch 5  le tableau, redessine toutes les 5 secondes (defaut : 3)

CE QU'IL EST : un LECTEUR. Il ne repare rien, il n'ouvre rien, il n'ecrit nulle part. Chaque ligne
est une VERIFICATION NOMMEE avec son verdict. Un tableau qui dirait « tout va bien » sans dire ce
qu'il a regarde ne vaudrait rien.

CE QU'IL MONTRE : LE CONTROLE (une ligne par epreuve : engine, table, canon, git, doctor, erreurs,
residents, ram DE LA, api, api status, last_activity, journal, pont) ; LES RESIDENTS ; LES MODELES
DE LA -- ceux que NOS morceaux nomment, avec leur etat (charge ou a la demande) ; LA MACHINE.

CE QU'IL NE MONTRE PAS : les gros processus de la machine, et les modeles du disque qui ne servent a
aucun de nos outils. Ce n'est pas l'inventaire de la machine, c'est l'etat de LA.
"""
import argparse
import glob
import os
import re
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
# LE JOURNAL DU TOUR : LA_LOG_FILE quand une session le pose ; sinon celui que LE PONT tient et que
# sa route /journal rend au widget. Ne pas lire le bon fichier, c'est dire « pas de journal » alors
# qu'il y en a un : le tableau nomme donc TOUJOURS le fichier qu'il a lu.
JOURNAL = os.environ.get("LA_LOG_FILE", "") or os.path.join(ROOT, "work", "journal.jsonl")
FILTRE = os.path.join(CONF_DIR, "filtre", "famille.bin")
SPECS = [os.path.join(ROOT, "projects", "la", "spec.yaml"),
         os.path.join(ROOT, "skills", "la", "spec.yaml")]
VISION = os.path.join(ROOT, "work", "voir.log")

# LES RESIDENTS : l'unite systemd, son port, le chemin de sante. Le nom de la brique porte le meme
# radical que l'unite (embed.sh -> la-embed). La liste est un CONTRAT : un resident qui nait entre ici.
RESIDENTS = [("embed", "la-embed.service", 8096, "health"),
             ("rerank", "la-rerank.service", 8095, "health"),
             ("local", "la-local.service", 8088, "health"),
             ("asr", "la-asr.service", 8080, "ready"),
             ("tts", "la-tts.service", 8090, "health")]
# CE QUI N'EST PAS UN RESIDENT : regarde sans etre compte comme une faute (il nait a la demande).
APPOINT = [("pont", 8765, "ping", "l'app est eteinte"),
           ("vision", 8091, "health", "il nait a la demande")]
# LES EXTENSIONS QUI FONT UN MODELE. Un fichier de ces formes, nomme par un de NOS morceaux, est un
# modele de LA ; le meme nom ailleurs sur le disque n'interesse personne.
FORMES = r"[A-Za-z0-9_.\-]+\.(?:gguf|onnx|pb|ftz)"
# LES BRIQUES QUI PORTENT UN MODELE (les residents), et le port sur lequel elles repondent.
BRIQUES = {"embed": 8096, "rerank": 8095, "local": 8088, "asr": 8080, "tts": 8090}
# LES PORTEURS QUI PORTENT UN MODELE. board.py est EXCLU : il PARLE des modeles, il n'en charge aucun
# (le nommer ferait entrer ses propres commentaires dans la liste).
PORTEURS = ["micro_vision.py", "see_image.py"]


def run(cmd, timeout=8):
    """Rend (code, texte). Un appel qui n'aboutit pas rend (-1, '')."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           timeout=timeout, text=True)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return -1, ""


def sonde(port, chemin):
    """Le code HTTP du resident, ou 000 s'il ne repond pas."""
    code, out = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "2",
                     "http://127.0.0.1:%d/%s" % (port, chemin)], timeout=6)
    out = out.strip()[:3]
    return out if out.isdigit() and out != "000" else "000"


def vive(unite):
    """(etat, Mo, pid) d'une unite systemd --user."""
    _, etat = run(["systemctl", "--user", "is-active", unite], timeout=5)
    _, pid = run(["systemctl", "--user", "show", "-p", "MainPID", "--value", unite], timeout=5)
    pid = pid.strip()
    mo = None
    if pid.isdigit() and pid != "0" and os.path.isfile("/proc/%s/status" % pid):
        try:
            with open("/proc/%s/status" % pid, "r") as f:
                for ligne in f:
                    if ligne.startswith("VmRSS:"):
                        mo = int(ligne.split()[1]) // 1024
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


# ---------------------------------------------------------------- LES VERIFICATIONS (lecture seule)
def lire_residents():
    out = []
    for nom, unite, port, chemin in RESIDENTS:
        etat, mo, _ = vive(unite)
        code = sonde(port, chemin) if etat == "active" else "000"
        faute = etat != "active" or code == "000"
        motif = ("il ne tourne pas (%s)" % etat) if etat != "active" else (
            "il tourne mais ne repond pas" if code == "000" else "")
        out.append((nom, port, etat, code, mo, faute, motif))
    return out


def lire_appoints():
    out = []
    for nom, port, chemin, mot in APPOINT:
        code = sonde(port, chemin)
        out.append((nom, port, code, mot, code == "000"))
    return out


def lire_registre():
    """{nom du tool: id} -- lu a la seule source, le registre."""
    m = {}
    if not os.path.isfile(TABLE):
        return m
    ident = None
    with open(TABLE, "r", errors="replace") as f:
        for ligne in f:
            s = ligne.strip()
            if s.startswith("- id:"):
                ident = s[5:].strip()
            elif s.startswith("tool:") and ident:
                m[s[5:].strip()] = ident
    return m


def _modeles_dans(chemin):
    """Les noms de modeles nommes dans un fichier, NORMALISES : sans le tiret de l'option, sans
    les points de tete, et SANS DOUBLON (la brique ecrit « MODEL=-X.gguf » et « -m X.gguf »)."""
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
    """La taille du modele, cherchee dans l'ordre : le dossier de travail du resident qui le porte
    (son cwd + le nom, puis son cwd + models/), le dossier des modeles, le filtre du projet. Rien
    d'autre : un modele qu'on ne trouve pas se DIT introuvable, il ne se devine pas."""
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
    """Les modeles LIES A NOS MORCEAUX : (nom, taille, qui, charge). Rien d'autre du disque."""
    trouve = {}   # nom -> (qui, charge, pid) -- le pid sert a retrouver le fichier par son cwd

    def poser(nom, qui, charge, pid=None):
        if nom not in trouve or charge:
            trouve[nom] = (qui, charge, pid)

    # 1. LES BRIQUES DES RESIDENTS : le modele est CHARGE tant que l'unite tourne (mesure, pas
    #    declaration : c'est l'etat du service qui le dit).
    for radical, port in sorted(BRIQUES.items()):
        etat, _, pid = vive("la-%s.service" % radical)
        for nom in _modeles_dans(os.path.join(CONF_DIR, "engine", "%s.sh" % radical)):
            poser(nom, "%s (%s)" % (radical, port), etat == "active", pid)
    # 2. LES CORPS DES OUTILS : ils nomment le modele qu'ils chargent a l'appel.
    ids = lire_registre()
    for f in sorted(glob.glob(os.path.join(ROOT, "config", "tools", "*", "tool_*.yaml"))):
        nom_tool = os.path.basename(f)[len("tool_"):-len(".yaml")]
        for nom in _modeles_dans(f):
            poser(nom, "%s (%s)" % (nom_tool, ids.get(nom_tool, "?")), False)
    # 3. LES PORTEURS : le modele vit dans le python qui le sert.
    for f in PORTEURS:
        for nom in _modeles_dans(os.path.join(ROOT, "config", "py", f)):
            poser(nom, f, False)
    # 4. LE FILTRE DE FAMILLE : le modele qu'ON a appris, et qui se refait en 60 ms.
    if os.path.isfile(FILTRE):
        poser("famille.bin", "filtre de famille (223/224)", False)

    lignes = [(nom, taille_de(nom, pid), qui, charge) for nom, (qui, charge, pid) in trouve.items()]
    # CE QUI EST CHARGE D'ABORD : c'est ce qui coute, et c'est ce qu'on vient regarder.
    lignes.sort(key=lambda x: (not x[3], x[2], x[0]))
    return lignes


def lire_table():
    """(ids, corps, manquants, doublons)"""
    ids, manquants, doublons = [], [], []
    if not os.path.isfile(TABLE):
        return None
    vus = set()
    with open(TABLE, "r", errors="replace") as f:
        for ligne in f:
            s = ligne.strip()
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
        for ligne in f:
            if ligne.startswith("SECTION : "):
                sections += 1
            elif ligne.startswith("  ") and ":" in ligne:
                tete = ligne.split(":")[0].strip()
                if tete.isdigit():
                    lois += 1
                    if tete in numeros:
                        doublons.append(tete)
                    numeros.append(tete)
            if len(ligne.rstrip("\n")) > 100:
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
        if not s:
            continue
        mot = s.split()[0]
        if mot in ("ok", "fail", "FAULT", "FAUTE", "note"):
            verd.append((mot, s[len(mot):].strip()))
    return verd


def lire_engine():
    """LE MOTEUR REPOND-IL ? On lui demande une chose vraie et pas chere : lire un dossier."""
    if not os.path.isfile(ENGINE):
        return False, "engine.sh est absent"
    code, out = run(["sh", ENGINE, "104", "config"], timeout=30)
    if '"status":"ok"' in out or '"status": "ok"' in out:
        return True, "un tool a rendu sa forme (104 list_dir config)"
    return False, " ".join(out.split())[:120] or "aucune forme rendue"


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
        actif = False
        with open(CONF, "r", errors="replace") as f:
            for ligne in f:
                s = ligne.strip()
                if s.startswith("- provider:"):
                    prov, actif = s.split(":", 1)[1].strip(), False
                elif s.startswith("alias:"):
                    t["alias" if False else "alias_tmp"] = s.split(":", 1)[1].strip()
                elif s.startswith("post:"):
                    t["post_tmp"] = s.split(":", 1)[1].strip()
                elif s.startswith("model:"):
                    t["model_tmp"] = s.split(":", 1)[1].strip()
                elif s.startswith("active:") and "true" in s and prov:
                    t["adresse"] = (prov, t.pop("alias_tmp", "-"), t.get("model_tmp", "?"),
                                    t.get("post_tmp", "?"))
    if "adresse" in t:
        code, _ = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "8",
                       "-X", "HEAD", t["adresse"][3]], timeout=12)
        t["joignable"] = str(code) if str(code).isdigit() else "000"
    if os.path.isfile(DB):
        _, a = run(["sqlite3", DB, "SELECT COUNT(*) FROM messages;"], timeout=6)
        _, b = run(["sqlite3", DB, "SELECT COALESCE(MAX(exchange),0) FROM messages;"], timeout=6)
        _, c = run(["sqlite3", DB, "SELECT ts FROM messages ORDER BY id DESC LIMIT 1;"], timeout=6)
        _, d = run(["sqlite3", DB, "SELECT role || ' : ' || substr(content,1,70) FROM messages "
                                   "WHERE content <> '' ORDER BY id DESC LIMIT 1;"], timeout=6)
        t["sessions"] = (a.strip() or "?", b.strip() or "?")
        t["quand"] = c.strip()
        t["dernier"] = " ".join(d.split())
    if JOURNAL:
        if os.path.isfile(JOURNAL):
            _, echecs = run(["grep", "-c", "echec de transport", JOURNAL], timeout=6)
            t["journal"] = (os.path.getsize(JOURNAL), echecs.strip() or "0")
        else:
            t["journal_absent"] = JOURNAL
    if os.path.isfile(VISION):
        _, n = run(["grep", "-c", "", VISION], timeout=6)
        t["vision_log"] = (os.path.getsize(VISION), n.strip() or "0")
    return t


def lire_machine():
    """La machine, en trois lignes : la RAM, les cartes, le disque. PAS la liste des processus."""
    m = {}
    _, mo = run(["free", "-m"], timeout=6)
    for ligne in mo.splitlines():
        if ligne.startswith("Mem:"):
            p = ligne.split()
            if len(p) >= 7:
                m["ram"] = (int(p[2]), int(p[1]), int(p[6]))
        elif ligne.startswith(("Swap:", "Echange:")):
            p = ligne.split()
            if len(p) >= 3:
                m["echange"] = int(p[2])
    _, gpu = run(["nvidia-smi", "--query-gpu=name,memory.used,memory.total,utilization.gpu",
                  "--format=csv,noheader"], timeout=8)
    m["cartes"] = [l.strip() for l in gpu.splitlines() if l.strip()]
    _, df = run(["df", "-h", ROOT], timeout=6)
    for ligne in df.splitlines()[1:2]:
        p = ligne.split()
        if len(p) >= 5:
            m["disque"] = (p[5], p[2], p[1], p[3])
    return m


def depuis(ts):
    """« il y a 6 min » a partir d'un horodatage de la base."""
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
        return "il y a %d s" % d
    if d < 5400:
        return "il y a %d min" % (d // 60)
    return "il y a %d h" % (d // 3600)


# ------------------------------------------------------------------------------------ LA MISE EN PAGE
def ligne_vue(x, largeur=22):
    """UNE LIGNE DE CONTROLE : « etiquette ...... verdict »."""
    etiquette, verdict, faute = x
    return "  %s %s %s" % (etiquette, "." * max(2, largeur - len(etiquette)), verdict)


def ligne_corps(label, verdict, largeur=22, note=""):
    return "  %s %s %s%s" % (label, "." * max(2, largeur - len(label)), verdict,
                             ("   " + note) if note else "")


def controle():
    """LA LISTE DE CONTROLE : la premiere chose qu'on lit. Rend tout ce dont la suite a besoin."""
    res = lire_residents()
    appoints = lire_appoints()
    table = lire_table()
    canon = lire_canon()
    docteur = lire_doctor()
    trafic = lire_trafic()
    ok_engine, dit_engine = lire_engine()
    non_commite, rev = lire_git()

    L = []
    L.append(("engine", "ok" if ok_engine else "il ne repond pas", not ok_engine))
    if table is None:
        L.append(("table", "ABSENTE", True))
    else:
        L.append(("table", "%d ids / %d corps" % (table[0], table[1]), bool(table[2] or table[3])))
    if canon.get("chemin") is None:
        L.append(("canon", "INTROUVABLE", True))
    else:
        L.append(("canon", "%d lois / %d sections" % (canon["lois"], canon["sections"]),
                  bool(canon["doublons"] or canon["longs"])))
    etat_git = ("suivi" if canon.get("suivi") else "HORS DEPOT")
    if non_commite is not None:
        etat_git += " / %d non commite(s)" % non_commite
    if rev:
        etat_git += " @%s" % rev
    L.append(("git", etat_git, canon.get("chemin") is not None and not canon["suivi"]))
    if docteur is None:
        L.append(("doctor", "absent", True))
        nko = 0
    else:
        nko = len([x for x in docteur if x[0] in ("fail", "FAULT", "FAUTE")])
        nok = len([x for x in docteur if x[0] == "ok"])
        nno = len([x for x in docteur if x[0] == "note"])
        L.append(("doctor", "%d ok / %d defaut / %d note" % (nok, nko, nno), nko > 0))
    fautes = [r[6] for r in res if r[5]]
    if table is not None:
        fautes += ["corps manquant : " + n for n in table[2]]
        fautes += ["id en double : " + n for n in table[3]]
    if docteur:
        fautes += [x[1] for x in docteur if x[0] in ("fail", "FAULT", "FAUTE")]
    L.append(("erreurs", str(len(fautes)), bool(fautes)))
    actifs = len([r for r in res if not r[5]])
    L.append(("residents", "%d / %d actifs" % (actifs, len(res)), actifs != len(res)))
    mo_la = sum(r[4] for r in res if r[4])
    L.append(("ram de LA", "%d Mo" % mo_la, False))
    if "adresse" in trafic:
        prov, alias, mod, post = trafic["adresse"]
        L.append(("api", "%s (%s) : %s" % (prov, alias or "-", mod), False))
        L.append(("endpoint", post, False))
        muet = trafic.get("joignable") == "000"
        L.append(("api status", "PAS DE REPONSE" if muet else "connected", muet))
    else:
        L.append(("api", "aucune adresse active dans la_config", True))
    if trafic.get("sessions"):
        L.append(("sessions", "%s messages / dernier echange n° %s" % trafic["sessions"], False))
    if trafic.get("quand"):
        L.append(("last_activity", "%s (%s)" % (trafic["quand"], depuis(trafic["quand"])), False))
    if "journal" in trafic:
        taille, echecs = trafic["journal"]
        L.append(("journal", "%s / %s echec(s) de transport" % (poids(taille), echecs),
                  echecs not in ("0", "")))
    elif "journal_absent" in trafic:
        L.append(("journal", "annonce mais absent (%s)" % trafic["journal_absent"], True))
    else:
        L.append(("journal", "LA_LOG_FILE n'est pas pose", False))
    if "vision_log" in trafic:
        L.append(("vision (journal)", "%s / %s ligne(s)" % (poids(trafic["vision_log"][0]),
                                                            trafic["vision_log"][1]), False))
    for nom, port, code, mot, muet in appoints:
        L.append((nom, ("muet (%s)" % mot) if muet else ("repond " + code), False))
    return L, fautes, res, appoints, table, canon, docteur, trafic, lire_modeles(), lire_machine()


def sections(res, appoints, table, canon, docteur, trafic, modeles, machine):
    """Le tableau d'apres : les residents, les modeles DE LA, la machine. UNE COLONNE."""
    out = ["LES RESIDENTS"]
    for nom, port, etat, code, mo, faute, motif in res:
        out.append(ligne_corps("%s :%d" % (nom, port), "!!" if faute else "ok", 20,
                               ("%d Mo" % mo) if mo else ("- " + motif if motif else "-")))
    for nom, port, code, mot, muet in appoints:
        out.append(ligne_corps("%s :%d" % (nom, port), "--" if muet else "ok", 20,
                               mot if muet else code))
    out.append("")
    out.append("LES MODELES DE LA")
    if not modeles:
        out.append("  aucun : aucun de nos morceaux ne nomme de modele")
    for nom, taille, qui, charge in modeles:
        out.append(ligne_corps(qui, "CHARGE" if charge else "a la demande", 34,
                               "%s   %s" % (poids(taille), nom)))
    out.append("")
    out.append("LA MACHINE")
    if "ram" in machine:
        u, tot, lib = machine["ram"]
        out.append(ligne_corps("ram", "%d / %d Mo" % (u, tot), 20,
                               "(%d disponibles, echange %d Mo)" % (lib, machine.get("echange", 0))))
    for c in machine.get("cartes", []):
        p = [x.strip() for x in c.split(",")]
        if len(p) == 4:
            out.append(ligne_corps("carte", "%s : %s / %s (%s)" % (p[0], p[1], p[2], p[3]), 20))
    if "disque" in machine:
        d = machine["disque"]
        out.append(ligne_corps("disque", "%s : %s / %s" % (d[0], d[1], d[2]), 20,
                               "(%s libres)" % d[3]))
    return out


def batir():
    """Le tableau vivant. Rend (renderable, nombre de defauts)."""
    L, fautes, res, appoints, table, canon, docteur, trafic, modeles, machine = controle()
    corps = [ligne_vue(x) for x in L] + [""] + sections(res, appoints, table, canon, docteur,
                                                       trafic, modeles, machine)
    try:
        from rich import box
        from rich.console import Console, Group
        from rich.panel import Panel
        from rich.text import Text
        Console()
        riche = True
    except ImportError:
        riche = False

    if not riche:
        from types import SimpleNamespace
        return SimpleNamespace(texte="\n".join(corps)), len(fautes)

    tete = Text("LA — LE TABLEAU", style="bold white")
    sous = Text("%s UTC   ·   %s" % (time.strftime("%H:%M:%S", time.gmtime()), ROOT), style="dim")
    verd = Text("TOUT EST EN PLACE" if not fautes else "%d DEFAUT%s" %
                (len(fautes), "S" if len(fautes) > 1 else ""),
                style="bold white on dark_green" if not fautes else "bold white on dark_red")
    rendu = []
    for l in corps:
        if l.startswith("LES ") or l.startswith("LA MACHINE"):
            rendu.append(Text(l, style="bold cyan"))
        elif " !! " in l or l.rstrip().endswith("!!"):
            rendu.append(Text(l, style="red"))
        elif not l.strip():
            rendu.append(Text(""))
        else:
            rendu.append(Text(l, style=""))
    pied = []
    if fautes:
        pied.append(Text("ce qu'il faut regarder :", style="bold red"))
        for f in fautes:
            pied.append(Text("  - " + str(f)[:110], style="red"))
    return Group(Panel(Group(tete, sous, Text(""), verd), border_style="cyan", box=box.ROUNDED),
                 Panel(Group(*rendu), border_style="blue", box=box.ROUNDED),
                 Panel(Group(*pied), border_style="red", box=box.ROUNDED)
                 if fautes else Text("")), len(fautes)


def main():
    ap = argparse.ArgumentParser(description="le tableau de LA : ce qui est charge, et ce qui ne va pas")
    ap.add_argument("--once", action="store_true", help="une passe, puis il sort (code = defauts)")
    ap.add_argument("--watch", type=float, default=3.0, help="secondes entre deux dessins")
    a = ap.parse_args()

    if a.once:
        L, fautes, res, appoints, table, canon, docteur, trafic, modeles, machine = controle()
        for x in L:
            print(ligne_vue(x))
        print("")
        for l in sections(res, appoints, table, canon, docteur, trafic, modeles, machine):
            print(l)
        return 1 if fautes else 0

    try:
        from rich.console import Console
        from rich.live import Live
    except ImportError:
        print("board: rich est absent : le tableau ne peut pas s'animer (--once rend encore le texte).")
        return 2
    console = Console()
    # LA LISTE DE CONTROLE D'ABORD, LIGNE A LIGNE : c'est le chargeur qu'on regarde ouvrir. Puis le
    # tableau prend la place et se redessine tout seul. screen=False : il se redessine SUR PLACE et
    # n'efface RIEN -- la liste de controle reste lisible dans le defile au-dessus.
    L, fautes, *_ = controle()
    for x in L:
        console.print(ligne_vue(x)[:110], style="bold red" if x[2] else None)
    console.print("")
    with Live(console=console, refresh_per_second=4, screen=False) as vivant:
        while True:
            try:
                panneau, _ = batir()
                if hasattr(panneau, "texte"):
                    console.print(panneau.texte)
                else:
                    vivant.update(panneau)
                time.sleep(a.watch)
            except KeyboardInterrupt:
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
