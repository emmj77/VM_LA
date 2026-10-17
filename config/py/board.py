#!/usr/bin/env python3
"""board.py — LE PANNEAU DE LA. Ce qui est charge, ce qui repond, ce qui ne va pas.

    board.py            le panneau VIVANT : il se redessine, il reste visible (Ctrl-C pour sortir)
    board.py --once     UNE passe et il sort : le code de retour est le NOMBRE DE DEFAUTS
    board.py --watch 5  le panneau, redessine toutes les 5 secondes (defaut : 3)

CE QU'IL EST : un LECTEUR. Il ne repare rien, il n'ouvre rien, il n'ecrit nulle part. Chaque ligne
est une VERIFICATION NOMMEE avec son verdict : [ok] elle tient, [!!] elle ne tient pas, [--] elle ne
s'occupe pas de nous ici. Un panneau qui dirait « tout va bien » sans dire ce qu'il a regarde ne
vaudrait rien (c'est la regle du doctor, loi 1800).

IL PARTAGE SES VERIFICATIONS AVEC LE DOCTOR : les lignes de doctor.sh sont relues TELLES QUELLES,
et le panneau ajoute ce que le doctor ne regarde pas -- les residents, les modeles sur le disque, la
table a deux fichiers, le trafic, la RAM. Une meme verite ne s'ecrit qu'une fois : le jour ou le
doctor couvre une ligne, elle se retire d'ici.

LA MISE EN PAGE EST RICH (13.9, le paquet du systeme). Sans rich, le panneau rend le MEME contenu en
texte plat et le dit : il ne disparait pas parce qu'une bibliotheque manque.
"""
import argparse
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
GGUF = os.environ.get("LA_GGUF_DIR", os.path.expanduser("~/LLM_GGUF"))
DB = os.environ.get("LA_DB", os.path.join(CONF_DIR, "sessions.db"))
JOURNAL = os.environ.get("LA_LOG_FILE", "")
FILTRE = os.path.join(CONF_DIR, "filtre", "famille.bin")
SPECS = [os.path.join(ROOT, "projects", "la", "spec.yaml"),
         os.path.join(ROOT, "skills", "la", "spec.yaml")]

# LES RESIDENTS : l'unite systemd, son port, le chemin de sante. La liste est un CONTRAT : le jour
# ou un resident nait, il entre ici, et le panneau le regarde.
RESIDENTS = [("embed", "la-embed.service", 8096, "health"),
             ("rerank", "la-rerank.service", 8095, "health"),
             ("local", "la-local.service", 8088, "health"),
             ("asr", "la-asr.service", 8080, "ready"),
             ("tts", "la-tts.service", 8090, "health")]
# CE QUI N'EST PAS UN RESIDENT : on le regarde sans en faire une faute (il se demarre a la demande).
# (nom, port, chemin, ce qu'on dit quand il est a l'arret)
APPOINT = [("bridge", 8765, "ping", "l'app est-elle lancee ?"),
           ("vision", 8091, "health", "il se demarre a la demande")]


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
        return "?"
    return "%d Mo" % (o // 1048576) if o >= 1048576 else "%d Ko" % (o // 1024)


# ---------------------------------------------------------------- LES VERIFICATIONS (lecture seule)
def lire_residents():
    """[(nom, port, etat, repond, Mo, faute, motif)]"""
    out = []
    for nom, unite, port, chemin in RESIDENTS:
        etat, mo, _ = vive(unite)
        code = sonde(port, chemin) if etat == "active" else "000"
        if etat != "active":
            out.append((nom, port, etat, None, mo, True, "il ne tourne pas (etat : %s)" % etat))
        elif code == "000":
            out.append((nom, port, etat, None, mo, True, "il tourne mais ne repond pas"))
        else:
            out.append((nom, port, etat, code, mo, False, ""))
    return out


def lire_appoints():
    out = []
    for nom, port, chemin, mot in APPOINT:
        code = sonde(port, chemin)
        out.append((nom, port, code, mot, code == "000"))
    return out


def lire_modeles():
    """Les modeles que la TABLE reclame : le nom est lu dans le corps du tool, jamais d'une liste."""
    out, vus = [], set()
    d = os.path.join(ROOT, "config", "tools")
    if os.path.isdir(d):
        for machine in sorted(os.listdir(d)):
            m = os.path.join(d, machine)
            if not os.path.isdir(m):
                continue
            for f in sorted(os.listdir(m)):
                if not (f.startswith("tool_") and f.endswith(".yaml")):
                    continue
                try:
                    with open(os.path.join(m, f), "r", errors="replace") as fh:
                        txt = fh.read()
                except OSError:
                    continue
                # le corps ecrit « $LA_GGUF_DIR/yolo11n.onnx » : le NOM est ce qui suit le dernier
                # « / », et c'est LUI qu'on cherche sous le dossier des modeles.
                trouves = re.findall(r"[A-Za-z0-9_.\-]+\.(?:gguf|onnx|pb|ftz)", txt)
                if trouves and trouves[0] not in vus:
                    vus.add(trouves[0])
    for nom in sorted(vus):
        p = os.path.join(GGUF, nom)
        out.append((nom, os.path.getsize(p) if os.path.isfile(p) else None))
    return out


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
                trouve = False
                base = os.path.join(ROOT, "config", "tools")
                if os.path.isdir(base):
                    for machine in os.listdir(base):
                        if os.path.isfile(os.path.join(base, machine, "tool_%s.yaml" % nom)):
                            trouve = True
                            break
                if not trouve:
                    manquants.append(nom)
    return len(ids), len(ids) - len(manquants), manquants, doublons


def lire_canon():
    chemin = next((c for c in SPECS if os.path.isfile(c)), None)
    if not chemin:
        return {"chemin": None, "faute": [("le canon est introuvable", None)]}
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
        return None, []
    code, out = run(["sh", DOCTOR], timeout=40)
    lignes, verd = [], []
    for brut in out.splitlines():
        s = brut.strip()
        if not s:
            continue
        mot = s.split()[0]
        if mot in ("ok", "fail", "FAULT", "FAUTE", "note"):
            reste = s[len(mot):].strip()
            verd.append((mot, reste))
    return out, verd


def lire_trafic():
    t = {}
    if os.path.isfile(CONF):
        prov = url = mod = None
        actif = False
        with open(CONF, "r", errors="replace") as f:
            for ligne in f:
                s = ligne.strip()
                if s.startswith("- provider:"):
                    prov, actif = s.split(":", 1)[1].strip(), False
                elif s.startswith("post:"):
                    url = s.split(":", 1)[1].strip()
                elif s.startswith("model:"):
                    mod = s.split(":", 1)[1].strip()
                elif s.startswith("active:") and "true" in s:
                    actif = True
                if actif and prov and url and mod:
                    t["adresse"] = (prov, mod, url)
                    break
    if "adresse" in t:
        code, _ = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "6",
                       "-X", "HEAD", t["adresse"][2]], timeout=9)
        t["joignable"] = str(code) if str(code).isdigit() else "000"
    if os.path.isfile(DB):
        _, a = run(["sqlite3", DB, "SELECT COUNT(*) FROM messages;"], timeout=6)
        _, b = run(["sqlite3", DB, "SELECT COALESCE(MAX(exchange),0) FROM messages;"], timeout=6)
        _, c = run(["sqlite3", DB,
                    "SELECT role || ' : ' || substr(content,1,80) FROM messages "
                    "WHERE content <> '' ORDER BY id DESC LIMIT 1;"], timeout=6)
        t["sessions"] = (a.strip() or "?", b.strip() or "?")
        t["dernier"] = " ".join(c.split())
    if JOURNAL and os.path.isfile(JOURNAL):
        t["journal"] = (os.path.getsize(JOURNAL),
                        sum(1 for _ in open(JOURNAL, errors="replace")) if os.path.getsize(JOURNAL) else 0)
        _, echecs = run(["grep", "-c", "echec de transport", JOURNAL], timeout=6)
        t["echecs"] = echecs.strip() or "0"
    return t


def lire_machine():
    m = {}
    _, mo = run(["free", "-m"], timeout=6)
    # LES CHAMPS DE free : total, used, free, shared, buff/cache, available. LE TOTAL EST p[1] :
    # lire p[3] (libre) en croyant lire le total annonce une machine huit fois plus petite qu'elle
    # n'est -- l'erreur est muette, le chiffre reste plausible, et c'est tout ce qui la rend grave.
    for ligne in mo.splitlines():
        if ligne.startswith("Mem:"):
            p = ligne.split()
            if len(p) >= 7:
                m["ram"] = (int(p[2]), int(p[1]), int(p[6]))
        elif ligne.startswith(("Swap:", "Echange:")):
            p = ligne.split()
            if len(p) >= 3:
                m["echange"] = int(p[2])
    _, tops = run(["ps", "-eo", "rss=,comm="], timeout=8)
    total = {}
    for ligne in tops.splitlines()[1:]:
        p = ligne.split()
        if len(p) == 2 and p[0].isdigit():
            total[p[1]] = total.get(p[1], 0) + int(p[0]) // 1024
    m["gros"] = sorted(total.items(), key=lambda x: -x[1])[:4]
    _, gpu = run(["nvidia-smi", "--query-gpu=name,memory.used,memory.total,utilization.gpu",
                  "--format=csv,noheader"], timeout=8)
    m["cartes"] = [l.strip() for l in gpu.splitlines() if l.strip()]
    _, df = run(["df", "-h", ROOT], timeout=6)
    for ligne in df.splitlines()[1:2]:
        p = ligne.split()
        if len(p) >= 5:
            m["disque"] = (p[5], p[2], p[1], p[3])
    return m


# ------------------------------------------------------------------------------------ LA MISE EN PAGE
def batir():
    """Le panneau entier, avec le compte des defauts. Rend (renderable, defauts)."""
    fautes = []
    res = lire_residents()
    appoints = lire_appoints()
    modeles = lire_modeles()
    table = lire_table()
    canon = lire_canon()
    doc_brut, docteur = lire_doctor()
    trafic = lire_trafic()
    machine = lire_machine()

    for nom, port, etat, code, mo, faute, motif in res:
        if faute:
            fautes.append("%s : %s" % (nom, motif))
    if table is None:
        fautes.append("la table est absente (%s)" % TABLE)
    else:
        if table[2]:
            fautes.append("%d corps manquant(s) : %s" % (len(table[2]), " ".join(table[2][:6])))
        if table[3]:
            fautes.append("id(s) en double dans le registre : %s" % " ".join(table[3]))
    for nom, taille in modeles:
        if taille is None:
            fautes.append("modele manquant : %s (sous %s)" % (nom, GGUF))
    if canon.get("chemin") is None:
        fautes.append("le canon est introuvable")
    else:
        if canon["doublons"]:
            fautes.append("loi(s) en double : %s" % " ".join(canon["doublons"]))
        if canon["longs"]:
            fautes.append("%d ligne(s) de plus de 100 octets dans le canon" % canon["longs"])
        if not canon["suivi"]:
            fautes.append("le canon n'est suivi par aucun depot git")
    if docteur is None:
        fautes.append("doctor.sh est absent ou n'a rien rendu")
    else:
        fautes += [x[1] for x in docteur if x[0] in ("fail", "FAULT", "FAUTE")]
    if trafic.get("adresse") and trafic.get("joignable") == "000":
        fautes.append("l'adresse du modele ne repond pas (%s)" % trafic["adresse"][2])
    if trafic.get("echecs") not in (None, "0"):
        fautes.append("%s echec(s) de transport au journal" % trafic["echecs"])

    try:
        import rich  # noqa: F401
        from rich import box
        from rich.console import Console, Group
        from rich.panel import Panel
        from rich.table import Table
        from rich.text import Text
        riche = True
    except ImportError:
        riche = False

    def tete():
        lignes = ["racine %s" % ROOT]
        code, rev = run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], timeout=6)
        if code == 0:
            _, sujet = run(["git", "-C", ROOT, "log", "-1", "--format=%s"], timeout=6)
            lignes.append("depot %s   %s" % (rev.strip(), sujet.strip()[:70]))
        return lignes

    if not riche:
        out = ["LA -- THE BOARD   %s UTC" % time.strftime("%H:%M:%S", time.gmtime())]
        out += ["  " + l for l in tete()]
        out.append("")
        out.append("THE RESIDENTS")
        for nom, port, etat, code, mo, faute, motif in res:
            out.append("  [%s] %-7s :%s  %s" % ("!!" if faute else "ok", nom, port,
                                              motif if faute else "il repond (%s)%s" %
                                              (code, "  %d Mo" % mo if mo else "")))
        for nom, port, code, mot, muet in appoints:
            out.append("  [%s] %-7s :%s  %s" % ("--" if muet else "ok", nom, port,
                                              "muet : %s" % mot if muet else "il repond (%s)" % code))
        out.append("")
        out.append("THE MODELS ON DISK")
        for nom, taille in modeles:
            out.append("  [%s] %-40s %s" % ("ok" if taille else "!!", nom, poids(taille)))
        if table:
            out.append("")
            out.append("THE TABLE   %d ids, %d corps" % (table[0], table[1]))
        out.append("")
        out.append("%d defaut(s) : %s" % (len(fautes), " ; ".join(fautes) if fautes else "aucun"))
        out.append("(rich est absent : le panneau rend le meme contenu en texte plat)")
        from types import SimpleNamespace
        return SimpleNamespace(texte="\n".join(out)), len(fautes)

    console = Console()
    def bandeau():
        t = Text()
        for i, l in enumerate(tete()):
            t.append(l + ("\n" if i < len(tete()) - 1 else ""), style="dim")
        return t

    grille = Table.grid(expand=True)
    grille.add_column(ratio=1)
    grille.add_column(ratio=1)

    # les residents
    t1 = Table(box=box.SIMPLE_HEAD, expand=True, header_style="bold cyan")
    t1.add_column("resident", no_wrap=True)
    t1.add_column("port", justify="right", no_wrap=True)
    t1.add_column("etat", no_wrap=True)
    t1.add_column("Mo", justify="right", no_wrap=True)
    for nom, port, etat, code, mo, faute, motif in res:
        if faute:
            t1.add_row(nom, str(port), Text("NE REPOND PAS", style="bold red"),
                       str(mo) if mo else "-")
        else:
            t1.add_row(nom, str(port), Text("repond " + code, style="green"),
                       str(mo) if mo else "-")
    for nom, port, code, mot, muet in appoints:
        t1.add_row(nom, str(port),
                   Text("muet" if muet else "repond " + code,
                        style="yellow" if muet else "green"), "-")

    t3 = Table(box=box.SIMPLE_HEAD, expand=True, header_style="bold cyan")
    t3.add_column("modele sur le disque")
    t3.add_column("taille", justify="right")
    for nom, taille in modeles:
        t3.add_row(Text(nom, style="red" if taille is None else ""), poids(taille))
    if os.path.isfile(FILTRE):
        t3.add_row("filtre de famille (famille.bin)", poids(os.path.getsize(FILTRE)))
    else:
        t3.add_row(Text("filtre de famille : n'a pas appris", style="yellow"), "-")

    t2 = Table.grid(expand=True)
    t2.add_column(justify="left")
    if table:
        style = "red" if table[2] or table[3] else "green"
        t2.add_row(Text("la table : %d ids, %d corps, %s" %
                        (table[0], table[1],
                         ("%d sans corps" % len(table[2])) if table[2] else "aucun sans corps"),
                        style=style))
    if canon.get("chemin"):
        style = "red" if (canon["doublons"] or canon["longs"] or not canon["suivi"]) else "green"
        t2.add_row(Text("le canon : %d lois, %d sections, %s" %
                        (canon["lois"], canon["sections"],
                         "suivi par git" if canon["suivi"] else "HORS depot git"), style=style))
        t2.add_row(Text(canon["chemin"], style="dim"))
    if doc_brut is None:
        t2.add_row(Text("le doctor : absent", style="red"))
    else:
        nko = len([x for x in docteur if x[0] in ("fail", "FAULT", "FAUTE")])
        nok = len([x for x in docteur if x[0] == "ok"])
        nnote = len([x for x in docteur if x[0] == "note"])
        t2.add_row(Text("le doctor : %d ok, %d defaut, %d note" % (nok, nko, nnote),
                        style="red" if nko else "green"))
        for mot, reste in [x for x in docteur if x[0] != "ok"][:6]:
            t2.add_row(Text("  %s %s" % ("[!!]" if mot != "note" else "[--]", reste[:96]),
                            style="red" if mot != "note" else "yellow"))

    t4 = Table.grid(expand=True)
    t4.add_column(justify="left")
    if trafic.get("adresse"):
        prov, mod, url = trafic["adresse"]
        joignable = trafic.get("joignable")
        t4.add_row(Text("le modele : %s (%s) %s" % (prov, mod, url),
                        style="green" if joignable != "000" else "red"))
    if trafic.get("sessions"):
        t4.add_row(Text("les sessions : %s messages, dernier echange n° %s" %
                        (trafic["sessions"][0], trafic["sessions"][1])))
    if trafic.get("dernier"):
        t4.add_row(Text("dernier mot : " + trafic["dernier"][:90], style="dim"))
    if "journal" in trafic:
        t4.add_row(Text("le journal : %s, %d lignes" % (poids(trafic["journal"][0]), trafic["journal"][1])))
    elif JOURNAL:
        t4.add_row(Text("le journal : %s (annonce, absent)" % JOURNAL, style="yellow"))
    else:
        t4.add_row(Text("le journal : LA_LOG_FILE n'est pas pose, ce qui transite n'est pas lu",
                        style="yellow"))

    t5 = Table.grid(expand=True)
    t5.add_column(justify="left")
    if "ram" in machine:
        u, tot, libre = machine["ram"]
        t5.add_row(Text("RAM %d Mo utilises sur %d (%d disponibles), echange %d Mo"
                        % (u, tot, libre, machine.get("echange", 0))))
        t5.add_row(Text("les plus gros : " + "  ".join("%s %d Mo" % (n, m) for n, m in machine["gros"]),
                        style="dim"))
    for c in machine.get("cartes", []):
        p = [x.strip() for x in c.split(",")]
        t5.add_row(Text("carte %s : %s / %s, %s" % tuple(p) if len(p) == 4 else c))
    if "disque" in machine:
        d = machine["disque"]
        t5.add_row(Text("disque %s : %s utilises sur %s (%s libres)" % (d[0], d[1], d[2], d[3])))

    verdict = Text("TOUT EST EN PLACE" if not fautes else "%d DEFAUT%s" %
                   (len(fautes), "S" if len(fautes) > 1 else ""),
                   style="bold white on dark_green" if not fautes else "bold white on dark_red")
    en_tete = Panel(Group(Text("LA -- THE BOARD", style="bold white"),
                           bandeau(), Text(""),
                           verdict, Text(""),
                           Text("%s UTC   (le panneau se redessine tout seul ; Ctrl-C pour sortir)"
                                % time.strftime("%H:%M:%S", time.gmtime()), style="dim")),
                     border_style="cyan", box=box.ROUNDED)

    # DEUX COLONNES SEULEMENT SI LA PLACE EXISTE : sous 110 colonnes, chaque tableau serait
    # ecrase a quatre caracteres de large, et un panneau illisible ne vaut rien.
    p1 = Panel(t1, title="THE RESIDENTS", border_style="blue", box=box.ROUNDED)
    p3 = Panel(t3, title="THE MODELS ON DISK", border_style="blue", box=box.ROUNDED)
    p2 = Panel(t2, title="THE TABLE, THE CANON, THE DOCTOR", border_style="blue", box=box.ROUNDED)
    p4 = Panel(t4, title="THE TRAFFIC", border_style="blue", box=box.ROUNDED)
    p5 = Panel(t5, title="THE MACHINE", border_style="blue", box=box.ROUNDED)
    corps = Table.grid(expand=True)
    if console.width >= 110:
        corps.add_column(ratio=1)
        corps.add_column(ratio=1)
        corps.add_row(p1, p3)
        corps.add_row(p2, p4)
        corps.add_row(p5, "")
    else:
        corps.add_column(ratio=1)
        for p in (p1, p2, p3, p4, p5):
            corps.add_row(p)

    pied = Text()
    if fautes:
        pied.append("ce qu'il faut regarder :\n", style="bold red")
        for f in fautes:
            pied.append("  - " + f[:110] + "\n", style="red")
    else:
        pied.append("aucun defaut : tout ce qui est charge repond, la table tient, le canon tient.",
                    style="green")
    return Group(en_tete, corps, Panel(pied, border_style="red" if fautes else "green",
                                       box=box.ROUNDED)), len(fautes)


def main():
    ap = argparse.ArgumentParser(description="le panneau de LA : ce qui est charge, et ce qui ne va pas")
    ap.add_argument("--once", action="store_true", help="une passe, puis il sort (code = defauts)")
    ap.add_argument("--watch", type=float, default=3.0, help="secondes entre deux dessins")
    a = ap.parse_args()

    if a.once:
        panneau, fautes = batir()
        if hasattr(panneau, "texte"):
            print(panneau.texte)
        else:
            from rich.console import Console
            Console().print(panneau)
        return 1 if fautes else 0

    try:
        from rich.console import Console
        from rich.live import Live
    except ImportError:
        print("board: rich est absent : le panneau ne peut pas s'animer (--once rend encore le texte).")
        return 2
    console = Console()
    with Live(console=console, refresh_per_second=4, screen=True) as vivant:
        while True:
            try:
                panneau, _ = batir()
                vivant.update(panneau)
                time.sleep(a.watch)
            except KeyboardInterrupt:
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
