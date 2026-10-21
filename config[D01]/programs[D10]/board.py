# french in code is forbidden
import argparse
import glob
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

from rich.markdown import Markdown
from rich.panel import Panel
from rich.text import Text
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Footer, Header, Input, RichLog, Static

# --- le panneau lit le pont, et rien d'autre : aucune donnee en double ---
ROOT = os.environ.get("LA_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# lance a la main, sans la porte, board.py doit trouver sa config : elle est dans l arbre, pas dans l environnement
os.environ.setdefault("LA_CONFIG", os.path.join(ROOT, "config[D01]", "conf[D05]", "la_config.yaml"))
os.environ.setdefault("LA_STATE", os.path.join(ROOT, "config[D01]", "state[D12]"))
CONFD = os.path.dirname(os.environ.get("LA_CONFIG", ""))
# la racine du projet a change de nom (config -> config[D01]) : elle se deduit du fichier, jamais d un litteral
CONF_DIR = CONFD or os.path.join(ROOT, "config[D01]")
BRIDGE = "http://%s:%s" % (os.environ.get("LA_HOST") or "127.0.0.1",
                           os.environ.get("LA_PORT_BRIDGE") or "8770")
_SEEN = {}


def state_dir(*part):
    base = os.environ.get("LA_STATE") or os.path.join(ROOT, "config[D01]", "state[D12]")
    return os.path.join(base, *part)


def num(section, key, default=0):
    v = (_cfg().get(section) or {}).get(key)
    if isinstance(v, list) and v:
        v = v[0]
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return float(v)
        except (TypeError, ValueError):
            return default


def _cfg():
    import yaml
    try:
        with open(os.environ.get("LA_CONFIG", ""), encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def bridge(path, body=None, ttl=0.0):
    """the only door to the data: the same answer the page and the phone read"""
    hit = _SEEN.get(path)
    if ttl and hit and (time.time() - hit[0]) < ttl:
        return hit[1]
    opts = {}
    if body is not None:
        opts = {"method": "POST", "headers": {"Content-Type": "application/json"},
                "body": json.dumps(body).encode("utf-8")}
    try:
        req = urllib.request.Request(BRIDGE + path, **opts)
        with urllib.request.urlopen(req, timeout=20) as r:
            d = json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        d = {"error": "%s: %s" % (type(e).__name__, e)}
    _SEEN[path] = (time.time(), d)
    return d


def bridge_ping():
    d = bridge("/ping", ttl=2.0)
    return bool(d) and "error" not in d


def bridge_state():
    return bridge("/api/state", ttl=1.0)


def read_head():
    return bridge("/api/head", ttl=2.0)


def read_hist(turns=12):
    return bridge("/api/history?turns=%d" % turns, ttl=2.0)


def read_live():
    return bridge("/api/live", ttl=1.0)


def _units(names):
    """l etat d une unite, tel que read_residents l attend : state, pid, memoire"""
    out = {}
    for u in names or []:
        state, pid, mb = "?", "", None
        try:
            r = subprocess.run(["systemctl", "--user", "show", "-p", "ActiveState",
                                "-p", "MainPID", "-p", "MemoryCurrent", u],
                               capture_output=True, text=True, timeout=4)
            d = {}
            for l in (r.stdout or "").strip().splitlines():
                if "=" in l:
                    k, v = l.split("=", 1)
                    d[k] = v
            state = d.get("ActiveState") or "?"
            pid = d.get("MainPID") or ""
            mem = d.get("MemoryCurrent") or ""
            mb = int(mem) // 1048576 if mem.isdigit() else None
        except (OSError, subprocess.TimeoutExpired):
            pass
        out[u] = {"state": state, "active": state == "active", "pid": pid,
                  "cg_mb": mb, "rss_mb": mb, "anon_mb": mb}
    return out


def _git_state():
    def one(*a):
        r = subprocess.run(["git", "-C", ROOT] + list(a), capture_output=True, text=True)
        return (r.stdout or "").strip()
    dirty = one("status", "--short")
    return {"dirty": bool(dirty), "rev": one("rev-parse", "--short", "HEAD") or "?",
            "branch": one("rev-parse", "--abbrev-ref", "HEAD") or "?",
            "describe": one("describe", "--tags", "--always") or "?"}


def _engine():
    """l ancien contrat : alias, model, provider, post, context"""
    m = bridge_state().get("model") or {}
    e = {"alias": m.get("alias") or "?", "model": m.get("model") or "?",
         "provider": m.get("provider") or "?", "post": "", "context": 0}
    eng = _cfg().get("engines") or {}
    cur = eng.get(e["alias"]) if isinstance(eng, dict) else None
    if isinstance(cur, dict):
        e["post"] = str(cur.get("post") or "")
        try:
            e["context"] = int(str(cur.get("context") or 0).replace("_", ""))
        except ValueError:
            e["context"] = 0
    return e


def _db_counts():
    st = bridge_state()
    n = st.get("exchanges") or 0
    return {"n": n, "ex": n, "ts": st.get("ts") or ""}


def _db_query(sql, args=()):
    import sqlite3
    f = state_dir("sessions.db")
    try:
        with sqlite3.connect(f) as c:
            return c.execute(sql, args).fetchall()
    except Exception:
        return []


def _table():
    """the tool registries of the current tree: rows {id, tool, ...}"""
    import yaml
    rows = []
    base = os.path.join(ROOT, "config[D01]", "tools[D14]")
    try:
        subs = sorted(os.listdir(base))
    except OSError:
        subs = []
    files = []
    for d in subs:
        here = os.path.join(base, d)
        if os.path.isdir(here):
            files += [os.path.join(here, f) for f in sorted(os.listdir(here))
                      if f.startswith("registry-") and f.endswith(".yaml")]
    for f in files:
        try:
            with open(f, encoding="utf-8") as fh:
                d = yaml.safe_load(fh) or {}
        except Exception:
            continue
        lst = d if isinstance(d, list) else (d.get("tools") or d.get("entries") or [])
        for r in lst if isinstance(lst, list) else []:
            if isinstance(r, dict):
                rows.append(r)
    return rows


class laconf(object):
    ROOT = ROOT
    CONFD = CONFD
    path = staticmethod(lambda name, default="": {
        "config": os.environ.get("LA_CONFIG", ""),
        "engine": os.path.join(ROOT, "config[D01]", "engine[D07]"),
        "trace": state_dir("trace.jsonl"),
        "reply_stream": state_dir("reply.stream"),
        "bridge_log": state_dir("bridge.log"),
        "table": os.environ.get("LA_CONFIG", ""),
        "gguf": os.environ.get("LA_GGUF_DIR") or os.path.expanduser("~/LLM_GGUF"),
    }.get(name) or default)
    get = staticmethod(lambda section, key, default=None: (_cfg().get(section) or {}).get(key, default))
    text = staticmethod(lambda section, key, default="": str((_cfg().get(section) or {}).get(key, default)))
    table = staticmethod(_table)


class model(object):
    engine = staticmethod(_engine)
    tokens = staticmethod(lambda: bridge_state().get("tokens") or {})
    db_counts = staticmethod(_db_counts)
    units = staticmethod(_units)
    doctor = staticmethod(lambda op="light": {"verdicts": bridge_state().get("doctor") or {}})
    git_state = staticmethod(_git_state)
    query = staticmethod(_db_query)

TABLE = os.environ.get("LA_CONFIG") or laconf.path("table", "")
CONF = os.environ.get("LA_CONF") or laconf.path("config", "")
ENGINE = os.path.join(laconf.path("engine", ""), "engine.sh")
GGUF = os.environ.get("LA_GGUF_DIR") or laconf.path("gguf", "")
JOURNALS = laconf.path("bridge_log", "config/state/bridge.log")
FILTER = laconf.path("filter", "")
SPECS = [s if os.path.isabs(s) else os.path.join(ROOT, s) for s in laconf.get("paths", "specs", [])]
if not SPECS:      # le canon de l arbre actuel
    SPECS = [os.path.join(ROOT, "ARCHITECTURE_LA.txt")]
VISION = laconf.path("vision_log", "")
TRACE = laconf.path("trace", "config/state/trace.jsonl")
DEFAULT_WIDTH = num("board", "columns", 82)


def _port(v):
    v = str(v).strip()
    return int(v) if v.isdigit() else num(v, "port", 0)


RESIDENTS = [(r["name"], r["unit"], _port(r.get("port")), r.get("probe", "health"))
             for r in laconf.get("board", "residents", [])]
RESIDENT_NAMES = tuple(r[0] for r in RESIDENTS)
APPOINT = [(a["name"], _port(a.get("port")), a.get("probe", "health"), a.get("word", ""),
            a.get("unit", ""))
           for a in laconf.get("board", "appoints", [])]
INSTRUMENTS = [(i["name"], i.get("label") or i["name"], i.get("why", ""))
               for i in laconf.get("board", "instruments", [])]
FORMS = laconf.text("board", "forms", r"[A-Za-z0-9_.\-]+\.(?:gguf|onnx|pb|ftz)")
BRICKS = {r[0]: r[2] for r in RESIDENTS}
CARRIERS = laconf.get("board", "porteurs", [])


def run(cmd, timeout=8):
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           timeout=timeout, text=True)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return -1, ""


def probe(port, path):
    code, out = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "2",
                     "http://127.0.0.1:%d/%s" % (port, path)], timeout=6)
    out = out.strip()[:3]
    return out if out.isdigit() and out != "000" else "000"


def alive(unit):
    st = model.units([unit]).get(unit) or {}
    busy = st.get("cg_mb")
    if busy is None:
        busy = st.get("rss_mb")
    return st.get("state", "?"), st.get("anon_mb"), st.get("pid") or "", busy


def weight(o):
    if o is None or o < 0:
        return "introuvable"
    if o >= 1073741824:
        return "%.1f GB" % (o / 1073741824.0)
    if o >= 1048576:
        return "%d MB" % (o // 1048576)
    return "%d KB" % (o // 1024)


def line(label, verdict, note="", width=DEFAULT_WIDTH):
    def build(et, ve, no, points=True):
        if points:
            rest = ve if not no else "%s   %s" % (ve, no)
            head = "  %s " % et
            n = width - len(head) - len(rest) - 1
            if n >= 1:
                return head + "." * n + " " + rest
        return "  %s %s%s" % (et, ve, ("   " + no) if no else "")

    l = build(label, verdict, note)
    if len(l) <= width:
        return l
    if note:
        place = width - len("  %s " % label) - len(verdict) - 4
        if place >= 6:
            l = build(label, verdict, note[:place].rstrip() + "~")
            if len(l) <= width:
                return l
        l = build(label, verdict, "", points=False)
        if len(l) <= width:
            return l
    place = width - len(verdict) - 4
    if place > 8:
        return "  %s %s" % (label[:place - 1].rstrip() + "~", verdict)
    return ("%s %s" % (label, verdict))[:width]


def read_residents():
    out = []
    for name, unit, port, path in RESIDENTS:
        state, mo, _, busy = alive(unit)
        code = probe(port, path) if state == "active" else "000"
        fault = state != "active" or code == "000"
        pattern = ("eteint (%s)" % state) if state != "active" else ("silent" if code == "000" else "")
        out.append((name, port, state, code, mo, fault, pattern, busy))
    return out



def _rss_port(port):
    try:
        p = subprocess.run(["ss", "-ltnp", "sport = :%d" % port], capture_output=True, text=True, timeout=4).stdout
        m = re.search(r"pid=(\d+)", p)
        if not m:
            return 0
        with open("/proc/%s/status" % m.group(1)) as f:
            for l in f:
                if l.startswith("VmRSS:"):
                    return int(l.split()[1]) // 1024
    except (OSError, subprocess.TimeoutExpired):
        pass
    return 0


def read_appoints():
    out = []
    for name, port, path, word, unit in APPOINT:
        # une ligne qui porte une unite lit son etat, elle ne sonde pas son port :
        # le port d une page est un socket, le sonder la reveille et elle ne dort plus jamais
        if unit:
            st = (_units([unit]).get(unit) or {}).get("state") or "?"
            # la page de LA a deux etats utiles : ouverte ou fermee. Vert veut dire ouverte.
            mot = {"active": "open", "inactive": "closed"}.get(st, st)
            out.append((name, port, mot, word, st != "active", unit))
            continue
        code = probe(port, path)
        out.append((name, port, code, word, code == "000", ""))
    return out


def read_approval():
    import time as _t
    import pathlib
    w = pathlib.Path(state_dir())
    try:
        win = num("approval", "window", 300) or 300
    except Exception:
        win = 300
    request = None
    f = w / "approve.request"
    if f.is_file():
        try:
            t = f.read_text(errors="replace").splitlines()
            words = (t[0].strip() if t else "").split()
            if words and words[-1].isdigit():
                words = words[:-1]
            request = (words[0] if words else "illisible",
                   words[1] if len(words) > 1 else "",
                   int(_t.time() - f.stat().st_mtime))
        except Exception:
            request = ("illisible", "", 0)
    # une demande signee n est plus une demande : la signature prime
    if request is not None:
        sig = w / "approve"
        try:
            if sig.is_file() and sig.stat().st_mtime >= f.stat().st_mtime:
                request = None
        except OSError:
            pass
    signal = None
    g = w / "approve"
    if g.is_file():
        try:
            t = g.read_text(errors="replace").splitlines()
            left = int(win - (_t.time() - g.stat().st_mtime))
            signal = ((t[0].strip() if t else "illisible"), max(0, left))
        except Exception:
            signal = ("illisible", 0)
    rights = []
    # les skills vivent a la racine du projet, sous un nom qui porte son numero : on les cherche par leur forme
    for p in sorted(pathlib.Path(ROOT).glob("skills*/*/skill.yaml")):
        try:
            for ln in p.read_text(errors="replace").splitlines():
                if ln.startswith("APPROVAL:") and ln.split(":", 1)[1].strip().lower() == "true":
                    rights.append(p.parent.name)
                    break
        except Exception:
            pass
    return request, signal, rights, win


def read_instruments():
    out = []
    for name, label, what in INSTRUMENTS:
        code, output = run([name, "--version"], timeout=5)
        v = ""
        if code == 0:
            for l in output.splitlines():
                l = l.strip()
                if l:
                    t = l.split()
                    v = t[1] if len(t) > 1 and t[0] == name else t[0]
                    break
        out.append((label, v, code == 0, what))
    return out


def read_registry():
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


def _models_in(path):
    try:
        with open(path, "r", errors="replace") as f:
            found_rev = re.findall(FORMS, f.read())
    except OSError:
        return []
    names, seen = [], set()
    for n in found_rev:
        n = n.lstrip("-._")
        if len(n) < 4 or n in seen:
            continue
        seen.add(n)
        names.append(n)
    return names


def size_of(name, pid=None):
    hints = []
    if pid and pid.isdigit() and os.path.isdir("/proc/%s" % pid):
        try:
            cwd = os.readlink("/proc/%s/cwd" % pid)
            hints += [os.path.join(cwd, name), os.path.join(cwd, "models", name)]
        except OSError:
            pass
    hints.append(os.path.join(GGUF, name))
    for p in hints:
        if os.path.isfile(p):
            return os.path.getsize(p)
    if os.path.isfile(FILTER) and name == os.path.basename(FILTER):
        return os.path.getsize(FILTER)
    return None


def read_modeles():
    found = {}

    def place(name, who, load, pid=None):
        if name not in found or load:
            found[name] = (who, load, pid)

    for stem, port in sorted(BRICKS.items()):
        state, _, pid, _ = alive("la-%s.service" % stem)
        for name in _models_in(os.path.join(CONF_DIR, "engine", "%s.sh" % stem)):
            place(name, "%s %s" % (stem, port), state == "active", pid)
    ids = read_registry()
    for f in sorted(glob.glob(os.path.join(CONF_DIR, "tools", "*", "tool_*.yaml"))):
        tool_name = os.path.basename(f)[len("tool_"):-len(".yaml")]
        for name in _models_in(f):
            place(name, "%s %s" % (tool_name, ids.get(tool_name, "?")), False)
    for f in CARRIERS:
        for name in _models_in(os.path.join(CONF_DIR, "programs", f)):
            place(name, f, False)
    if os.path.isfile(FILTER):
        place("family.bin", "filter 223/224", False)
    lines = [(name, size_of(name, pid), who, load)
              for name, (who, load, pid) in found.items()]
    lines.sort(key=lambda x: (not x[3], x[2]))
    return lines


def read_table():
    rows = laconf.table()
    if not rows:
        return None
    bodies = set()
    base = os.path.join(ROOT, "config[D01]", "tools[D14]")
    try:
        dirs = [base] + [os.path.join(base, d) for d in os.listdir(base)
                             if os.path.isdir(os.path.join(base, d))]
    except OSError:
        dirs = [base]
    for d in dirs:
        try:
            bodies.update(f[5:-5] for f in os.listdir(d)
                          if f.startswith("tool_") and f.endswith(".yaml"))
        except OSError:
            pass
    ids = [r["id"] for r in rows]
    missing = [r["tool"] for r in rows
               if r.get("tool") and str(r["tool"]).replace(".", "_") not in bodies]
    seen, dups = set(), []
    for i in ids:
        if i in seen:
            dups.append(i)
        seen.add(i)
    return len(ids), len(ids) - len(missing), missing, dups


def read_canon():
    path = next((c for c in SPECS if os.path.isfile(c)), None)
    if not path:
        return {"path": None}
    laws, sections, longs, numbers, duplicates = 0, 0, 0, [], []
    with open(path, "r", errors="replace") as f:
        for l in f:
            if l.startswith("SECTION : "):
                sections += 1
            elif l.startswith("  ") and ":" in l:
                head = l.split(":")[0].strip()
                if head.isdigit():
                    laws += 1
                    if head in numbers:
                        duplicates.append(head)
                    numbers.append(head)
            if len(l.rstrip("\n")) > 100:
                longs += 1
    tracked = run(["git", "-C", ROOT, "ls-files", "--error-unmatch", path], timeout=6)[0] == 0
    return {"path": path, "laws": laws, "sections": sections, "longest": longs,
            "duplicates": duplicates, "tracked": tracked}


def read_doctor():
    return model.doctor("light")["verdicts"]


def read_engine():
    """the engine that actually answers: the active one, read from the bridge"""
    e = _engine()
    if e.get("alias") in ("", "?", None):
        return False, -1
    post = str(e.get("post") or "")
    if not post:
        return True, 0
    code, _ = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "8",
                   "-X", "HEAD", post], timeout=12)
    return (str(code).strip() in ("200", "401", "403", "405")), 0


def read_git():
    st = model.git_state()
    if not st["rev"]:
        return None, None
    return st["dirty"], st["rev"]


def read_traffic():
    t = {}
    e = model.engine()
    if e["post"]:
        t["adresse"] = (e["provider"], e["alias"], e["model"], e["post"])
    if "adresse" in t:
        code, _ = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "8",
                       "-X", "HEAD", t["adresse"][3]], timeout=12)
        t["joignable"] = str(code) if str(code).isdigit() else "000"
    c = model.db_counts()
    if c["n"]:
        t["sessions"] = (str(c["n"]), str(c["ex"]))
        t["quand"] = c["ts"] or ""
    if os.path.isfile(JOURNALS):
        _, failures = run(["grep", "-c", "transport failure", JOURNALS], timeout=6)
        t["journal"] = (os.path.getsize(JOURNALS), failures.strip() or "0")
    elif JOURNALS:
        t["journal_absent"] = JOURNALS
    if os.path.isfile(VISION):
        t["vision_log"] = os.path.getsize(VISION)
    return t


def read_turn():
    if not os.path.isfile(TRACE):
        return []
    rows = []
    try:
        with open(TRACE, "r", errors="replace") as f:
            for l in f:
                l = l.strip()
                if not l.startswith("{"):
                    continue
                try:
                    o = json.loads(l)
                except ValueError:
                    continue
                if isinstance(o, dict) and o.get("kind") == "tool":
                    rows.append(o)
    except OSError:
        return []
    return [(str(o.get("ts", ""))[11:19], "n°%s" % str(o.get("turn", "?")),
             str(o.get("tool") or "?"), str(o.get("line") or "")[:80]) for o in rows[-4:]]


def read_machine_name():
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
                m["swap"] = int(p[2])
    _, gpu = run(["nvidia-smi", "--query-gpu=name,memory.used,memory.total,utilization.gpu",
                  "--format=csv,noheader"], timeout=8)
    m["cards"] = []
    for l in gpu.splitlines():
        p = [x.strip() for x in l.split(",")]
        if len(p) == 4:
            m["cards"].append((" ".join(p[0].split()[-2:]), p[1], p[2], p[3]))
    _, df = run(["df", "-h", ROOT], timeout=6)
    for l in df.splitlines()[1:2]:
        p = l.split()
        if len(p) >= 5:
            m["disk"] = (p[5], p[2], p[1], p[3])
    return m


def ago(ts):
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
        return "%ds ago" % d
    if d < 5400:
        return "%dmin ago" % (d // 60)
    return "%dh ago" % (d // 3600)


def control(light=False):
    res = read_residents()
    appoints = read_appoints()
    instr = read_instruments()
    table = read_table()
    traffic = read_traffic()
    canon = {"path": None} if light else read_canon()
    doctor = None if light else read_doctor()
    ok_engine = False if light else read_engine()[0]
    uncommitted, rev = (None, None) if light else read_git()

    faults = [r[6] for r in res if r[5]]
    faults += ["instrument absent : " + i[0] for i in instr if not i[2]]
    if table is not None:
        faults += ["sans corps : " + n for n in table[2]] + ["id double : " + n for n in table[3]]
    if doctor:
        faults += [x[1] for x in doctor if x[0] in ("fail", "FAULT", "FAUTE")]
    if not light and canon.get("path") is None:
        faults.append("le canon est introuvable")

    L = []
    L.append(("LA status", "active" if not faults else "disabled", bool(faults)))
    request, signal, rights, _win = read_approval()
    if request:
        L.append(("approbation", "%s %s -- asked %ds ago" % (request[0], request[1], request[2]), True))
    if signal:
        L.append(("feu vert", "%s -- %ds" % (signal[0], signal[1]), False))
    # la ligne dit COMBIEN de skills demandent une signature
    L.append(("approbation", str(len(rights)), False))
    # le cli est un programme qu on OUVRE : vert quand une session tourne, rouge quand personne ne l a ouvert.
    # on lit les arguments exacts dans /proc : un pgrep -f se prendrait pour lui-meme.
    _cli_pid = ""
    for _d in os.listdir("/proc"):
        if not _d.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % _d, "rb") as _f:
                _a = [x.decode("utf-8", "replace") for x in _f.read().split(b"\0") if x]
        except OSError:
            continue
        if len(_a) >= 3 and _a[1].endswith("board.py") and "--cli" in _a[2:]:
            _cli_pid = _d
            break
    _cli_ok = os.access(os.path.abspath(__file__), os.R_OK)
    L.append(("cli", ("open · pid " + _cli_pid) if _cli_pid else ("closed" if _cli_ok else "absent"),
              not _cli_pid))
    if light:
        L.append(("residents", "%d/%d up" % (len([r for r in res if not r[5]]), len(res)),
                  len([r for r in res if not r[5]]) != len(res)))
        L.append(("table", "absente" if table is None else "%d/%d" % (table[0], table[1]),
                  table is None or bool(table[2] or table[3])))
        for name, port, code, word, silent, unit in appoints:
            if unit:
                L.append((name, code + (" · :%d" % port if port else ""), silent))
                continue
            _rss = 0 if silent else _rss_port(port)
            L.append((name, ("silent" if silent else "answers " + code) + " · :%d" % port
                         + ("" if silent else " · %d MB" % _rss),
                      False))
        for name, v, ok, what in instr:
            L.append((name,
                      (v + " · 0 MB · no port") if ok else ("ABSENT (" + what + ") · 0 MB · no port"),
                      not ok))
        if "adresse" in traffic:
            L.append(("api", "%s : %s" % (traffic["adresse"][0], traffic["adresse"][2]), False))
            silent = traffic.get("joignable") == "000"
            L.append(("api status", "pas de reponse" if silent else "connected", silent))
        if "journal" in traffic:
            size, failures = traffic["journal"]
            L.append(("journal", "%s / %s failed" % (weight(size), failures), failures not in ("0", "")))
        return L, faults, res, appoints, table, canon, doctor, traffic
    if table is None:
        L.append(("table", "absente", True))
    else:
        L.append(("table", "%d/%d" % (table[0], table[1]), bool(table[2] or table[3])))
    if canon.get("path"):
        L.append(("canon", "%d laws / %d sections" % (canon["laws"], canon["sections"]),
                  bool(canon["duplicates"] or canon["longest"])))
    git_state = "tracked" if canon.get("tracked") else "outside the repo"
    if uncommitted:
        git_state += " / %d uncommitted" % uncommitted
    if rev:
        git_state += " @%s" % rev
    L.append(("git", git_state, canon.get("path") is not None and not canon["tracked"]))
    if doctor is None:
        L.append(("doctor", "absent", True))
    else:
        nko = len([x for x in doctor if x[0] in ("fail", "FAULT", "FAUTE")])
        L.append(("doctor", "%d ok / %d fault(s)" % (len([x for x in doctor if x[0] == "ok"]), nko),
                  nko > 0))
    L.append(("errors", str(len(faults)), bool(faults)))
    live = len([r for r in res if not r[5]])
    L.append(("residents", "%d/%d up" % (live, len(res)), live != len(res)))
    for name, port, state, code, mo, fault, pattern, busy in res:
        _mo = mo if mo is not None else busy
        verdict = ("%s · :%d" % (pattern, port)) if fault else ("%d MB · :%d" % ((_mo or 0), port))
        L.append((name, verdict, fault))
    for name, v, ok, what in instr:
        L.append((name, (v + " · 0 MB · no port") if ok else ("ABSENT · " + what + " · 0 MB · no port"), not ok))
    _occ = sum(r[4] for r in res if r[4])
    try:
        with open("/proc/meminfo") as f:
            _total = [int(l.split()[1]) for l in f if l.startswith("MemTotal:")][0] // 1048576
    except (OSError, IndexError, ValueError):
        _total = 0
    L.append(("ram of LA", "%d MB / %d GB" % (_occ, _total) if _total else "%d MB" % _occ, False))
    for name, mo, total, pc in read_machine_name().get("cards", []):
        L.append(("gpu " + name,
                  "%s / %s MB" % (mo.replace(" MiB", ""), total.replace(" MiB", "")), False))
    if "adresse" in traffic:
        prov, alias, mod, post = traffic["adresse"]
        L.append(("api", "%s : %s" % (prov, mod), False))
        L.append(("endpoint", post, False))
        silent = traffic.get("joignable") == "000"
        L.append(("api status", "pas de reponse" if silent else "connected", silent))
    if traffic.get("sessions"):
        L.append(("sessions", "%s exchanges / last no. %s" % (traffic["sessions"][1],
                                                                traffic["sessions"][0]), False))
    if traffic.get("quand"):
        L.append(("last_activity", "%s %s" % (traffic["quand"][:19], ago(traffic["quand"])), False))
    if "journal" in traffic:
        size, failures = traffic["journal"]
        L.append(("journal", "%s / %s failed" % (weight(size), failures), failures not in ("0", "")))
    elif "journal_absent" in traffic:
        up = bridge_ping()
        _ena = run(["systemctl", "--user", "is-enabled", "la-bridge"], timeout=4)[1].strip() or "disabled"
        L.append(("bridge", _ena, _ena != "enabled"))
    for name, port, code, word, silent, unit in appoints:
        if unit:
            L.append((name, code + (" · :%d" % port if port else ""), silent))
            continue
        _rss = 0 if silent else _rss_port(port)
        L.append((name, ("silent" if silent else "answers " + code) + " · :%d" % port
                     + ("" if silent else " · %d MB" % _rss), False))
    return L, faults, res, appoints, table, canon, doctor, traffic


def sections(width):
    L, faults, res, appoints, table, canon, doctor, traffic = control()
    out = [line(x[0], x[1], "", width) for x in L]

    out.append("")
    out.append("WHAT GOES THROUGH")
    turn = read_turn()
    if not turn:
        out.append("  the journal is silent (no call recorded)")
    for ts, n, name, detail in turn:
        out.append(line("%s  %s" % (ts or "--:--:--", n), name, detail, width))

    out.append("")
    out.append("THE MODELS OF LA")
    models = read_modeles()
    if not models:
        out.append("  none: our pieces name none")
    for name, size, who, load in models:
        out.append(line(name, "LOADED" if load else "idle", "%s   %s" % (weight(size), who),
                         width))
    nch = len([m for m in models if m[3]])
    out.append("  %d models: %d in memory, %d on call" % (len(models), nch, len(models) - nch))

    machine_name = read_machine_name()
    out.append("")
    out.append("THE MACHINE")
    if "ram" in machine_name:
        u, total, lib = machine_name["ram"]
        out.append(line("ram", "%d/%d MB" % (u, total), "%d free" % lib, width))
    for name, use, total, pc in machine_name.get("cards", []):
        out.append(line("card", "%s %s/%s" % (name, use.split()[0], total.split()[0]), pc, width))
    if "disk" in machine_name:
        d = machine_name["disk"]
        out.append(line("disk", "%s %s/%s" % (d[0], d[1], d[2]), "%s free" % d[3], width))
    return out, faults


def one_line():
    L, faults, *_ = control(light=True)
    d = dict((x[0], x[1]) for x in L)
    return "%s | %s | table %s | api %s" % (d.get("LA status", "?"), d.get("residents", "?"),
                                            d.get("table", "?"), d.get("api status", "?"))


SIGNAL = {"change": False}


def _sigwinch(sig, frame):
    SIGNAL["change"] = True


def tint(l):
    if l.startswith(("WHAT GOES", "THE MODELS", "THE MACHINE")):
        return "\033[36m" + l + "\033[0m"
    if l.rstrip().endswith("!!") or " !! " in l or "fault(s)" in l:
        return "\033[31m" + l + "\033[0m"
    if l.lstrip().startswith("LA status") and "active" in l:
        return "\033[32m" + l + "\033[0m"
    return l


def frame(width, height):
    out, faults = sections(width)
    head = ["LA — LE TABLEAU   %s UTC   %d colonnes" % (time.strftime("%H:%M:%S", time.gmtime()),
                                                        width), ""]
    return [(l if len(l) <= width else l[:width]) for l in head + out][:height], faults


def _keys(fd, delay=0.06):
    import select
    r, _, _ = select.select([fd], [], [], delay)
    if not r:
        return ""
    try:
        return os.read(fd, 8).decode("utf-8", "ignore")
    except OSError:
        return ""


def _footer(width, faults, bottom, total):
    t = "  %d defaut(s)   %d-%d/%d   q sortir  r rafraichir  a appli  j/k defiler  g/G" % (
        faults, (bottom + 1) if total else 0, min(total, bottom + 1), total)
    return t if len(t) <= width else t[:width]


def tui(a, output):
    import termios, tty
    fd = sys.stdin.fileno()
    keyboard = sys.stdin.isatty()
    old = termios.tcgetattr(fd) if keyboard else None
    if keyboard:
        tty.setcbreak(fd)
    output.write("\033[?1049h\033[?25l\033[2J")
    output.flush()
    top = 0
    faults = 0
    try:
        while True:
            try:
                t = os.get_terminal_size(1)
                width, height = t.columns, t.lines
            except OSError:
                width, height = (a.width or DEFAULT_WIDTH), 46
            width = a.width or width
            w = max(24, width - 1)
            h = max(6, height - 1)
            try:
                everything, faults = sections(w)
                everything = ["LA — LE TABLEAU   %s UTC   %d colonnes"
                        % (time.strftime("%H:%M:%S", time.gmtime()), w), ""] + everything
                nf = len(faults) if isinstance(faults, list) else 0
            except Exception as e:
                everything = ["  le tableau a echoue : %s" % e]
                nf = 0
            total = len(everything)
            SIGNAL["change"] = False
            deadline = time.time() + a.watch
            leave = False
            while True:
                top = max(0, min(top, max(0, total - (h - 1))))
                view = [l if len(l) <= w else l[:w] for l in everything[top:top + h - 1]]
                block = "\033[H" + "".join(tint(l) + "\033[K\n" for l in view)
                block += "\033[%d;1H\033[7m%-*s\033[0m\033[K\033[J" % (h, w, _footer(w, nf, top, total))
                output.write(block)
                output.flush()
                if not keyboard:
                    left = deadline - time.time()
                    if left > 0:
                        time.sleep(min(left, 0.25))
                    break
                k = ""
                while time.time() < deadline and not SIGNAL["change"] and not k:
                    k = _keys(fd)
                if k in ("q", "Q", "\x03"):
                    leave = True
                    break
                if not k or SIGNAL["change"]:
                    break
                c = k[0]
                if c == "j" or k == "\x1b[B":
                    top += 1
                elif c == "k" or k == "\x1b[A":
                    top -= 1
                elif c == " " or k == "\x1b[6~":
                    top += h - 2
                elif k == "\x1b[5~":
                    top -= h - 2
                elif c == "g":
                    top = 0
                elif c == "G":
                    top = 10 ** 6
                elif c == "r":
                    break
                elif c == "a":
                    subprocess.Popen(["/bin/sh", os.path.join(CONF_DIR, "engine", "la.sh"), "--app"],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                     start_new_session=True)
                deadline = time.time() + a.watch
            if leave:
                break
    finally:
        if keyboard and old is not None:
            try:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
            except (OSError, termios.error):
                pass
        output.write("\033[?25h\033[?1049l\033[J")
        output.flush()
    return 0


HIST = os.path.join(state_dir(), "cli_history")
STREAM = laconf.path("reply_stream", "config/state/reply.stream")
CMDS = ["/help", "/head", "/resume", "/last", "/engine", "/plan", "/stop", "/ps",
        "/agents", "/board", "/app", "/update", "/clear", "/q"]


def base():
    return BRIDGE      # une seule adresse : celle du pont


def http(route, body=None, timeout=1800.0):
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    req = urllib.request.Request(base() + route, data=data,
                                 headers={"Content-Type": "application/json"} if data else {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
        try:
            return r.status, json.loads(raw.decode("utf-8", "replace"))
        except ValueError:
            return r.status, {"response": raw.decode("utf-8", "replace"), "code": 0}


def human_count(n):
    try:
        n = int(n)
    except (TypeError, ValueError):
        return "?"
    if n >= 1000000:
        v = n / 1000000.0
        return ("%d" % v if abs(v - int(v)) < 0.05 else "%.1f" % v) + "M"
    if n >= 10000:
        v = n / 1000.0
        return ("%d" % v if abs(v - int(v)) < 0.05 else "%.1f" % v) + "k"
    return "{:,}".format(n).replace(",", " ")


def shorten(text, n):
    t = " ".join(str(text or "").split())
    return t if len(t) <= n else t[:n - 1] + "…"


def read_state(key):
    try:
        with open(laconf.path(key, ""), encoding="utf-8") as f:
            return (f.readline() or "").strip()
    except OSError:
        return ""


def snapshot():
    L, faults, *_ = control(light=True)
    tk = model.tokens()
    e = model.engine()
    bridge_up = bridge_ping()
    head = read_head().get("sections") or []
    return {"rows": L, "faults": len(faults), "tokens": tk, "engine": e, "bridge_up": bridge_up,
            "head_sections": head,
            "skill": read_state("skill_active"), "projet": read_state("project_active"),
            "branche": model.git_state()["branch"] or "?", "touches": model.git_state()["dirty"]}


class Tailer:

    def __init__(self, file):
        self.f = file
        self.pos = self.size()

    def size(self):
        try:
            return os.path.getsize(self.f)
        except OSError:
            return 0

    def new_lines(self):
        if self.size() < self.pos:
            self.pos = 0
        try:
            with open(self.f, "r", errors="replace") as f:
                f.seek(self.pos)
                lines = f.readlines()
                self.pos = f.tell()
        except OSError:
            return []
        out = []
        for l in lines:
            l = l.strip()
            if not l:
                continue
            try:
                out.append(json.loads(l))
            except ValueError:
                pass
        return out


def _tool_line(e, width=120):
    if e.get("kind") == "tool":                     # a line of the live trace
        return shorten(str(e.get("line") or e.get("tool") or ""), width), e.get("status") == "ok"
    eng = e.get("engine") or {}
    line = eng.get("line") or ""
    if not line:
        fn = ((e.get("tool_call") or {}).get("function") or {}).get("name") or ""
        if not fn:
            return None, True
        args = ((e.get("tool_call") or {}).get("function") or {}).get("arguments") or ""
        line = "%s %s" % (fn, args)
    if "mode=answer" in line and " -> " in line:
        line = line.split(" -> ")[0]
    return shorten(line, width), (eng.get("status") or "ok") == "ok"


def one_turn(text):
    sj = Tailer(TRACE)
    st = Tailer(TRACE)
    end = {"obj": None, "fault": None}

    def stream():
        try:
            _, end["obj"] = http("/say", {"text": text}, timeout=1800)
        except Exception as e:
            end["fault"] = str(e)

    t = threading.Thread(target=stream, daemon=True)
    t.start()
    while t.is_alive():
        for e in st.new_lines():
            if e.get("kind") != "think":
                continue
            txt = " ".join(str(e.get("text") or "").split())
            if txt:
                sys.stderr.write("· %s\n" % txt[:400])
        for e in sj.new_lines():
            if e.get("kind") != "tool":
                continue
            line, ok = _tool_line(e)
            if line:
                sys.stderr.write(("  ✓ " if ok else "  ✗ ") + line + "\n")
        time.sleep(0.25)
    if end["fault"]:
        sys.stderr.write("la: le tour n'a pas abouti : %s\n" % end["fault"])
        return 2
    obj = end["obj"] or {}
    if obj.get("queued"):
        sys.stderr.write("la: %s\n" % (obj.get("note") or "un tour tourne deja"))
        return 3
    sys.stdout.write((obj.get("response") or "") + "\n")
    return int(obj.get("code") or 0)



class Cli(App):

    CSS = """
    Screen { background: $surface; }
    #stream { width: 1fr; }
    #side { width: 44; padding: 0 1; }
    #draft { display: none; border: round $accent; padding: 0 1; max-height: 14; }
    #draft.on { display: block; }
    #bottom { height: auto; }
    """
    BINDINGS = [("ctrl+c", "post", "post the word"), ("ctrl+q", "quit", "quit"),
                ("ctrl+d", "quit", "quit"), ("ctrl+o", "last", "last output")]

    def __init__(self):
        super().__init__()
        self.ICON = ""
        self.title = "LA"
        self.sub_title = "%s / %s · %s" % (model.engine()["alias"], model.engine()["model"],
                                           model.git_state()["describe"] or "?")
        self.history = self._read_history()
        self.idx_hist = len(self.history)
        self.start = 0.0
        self.tools = 0
        self.draft = ""
        self.running = False
        self._pv = None
        self.pending = ""
        self.sj = Tailer(TRACE)
        self.st = Tailer(TRACE)
        self.sr = Tailer(STREAM)

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="corps"):
            yield RichLog(id="stream", wrap=True, markup=False, highlight=False)
            yield Static("", id="side")
        yield Static("", id="draft")
        with Vertical(id="bottom"):
            yield Input(placeholder="ta demande — /help pour les commandes", id="input")
        yield Footer()

    def on_mount(self):
        self.stream = self.query_one("#stream", RichLog)
        self.side = self.query_one("#side", Static)
        self.input = self.query_one("#input", Input)
        self.draftw = self.query_one("#draft", Static)
        self._lastdraft = ""
        self.input.focus()
        self.banner()
        self.set_interval(0.2, self.pump)
        self.set_interval(5.0, self.state)
        self.state()

    def banner(self):
        self.stream.write(Text("Entree envoie · /help les commandes · Tab complete", style="dim"))
        self.stream.write("")

    def echo(self, text, style=""):
        self.stream.write(text if isinstance(text, Text) else Text(str(text), style=style))

    def request(self, text):
        self.stream.write(Panel(Text(text, style="bold cyan"), title="toi", title_align="left",
                                border_style="cyan", padding=(0, 1)))

    def answer(self, text):
        self.stream.write("")
        if text.strip():
            try:
                body = Markdown(text)
            except Exception:
                body = Text(text)
            self.stream.write(Panel(body, title="hermes", title_align="left",
                                    border_style="grey50", padding=(0, 1)))
        self.stream.write("")

    def error(self, text):
        self.stream.write(Text("✗ " + text, style="bold red"))
        self.bell()

    def state(self):
        self.run_worker(self._probe, thread=True, exclusive=True, group="etat")

    def _probe(self):
        try:
            pv = snapshot()
        except Exception as e:
            pv = {"rows": [("etat", "illisible : %s" % e, True)], "faults": 1,
                  "tokens": {}, "engine": {}, "bridge_up": False, "skill": "", "projet": "",
                  "branche": "?", "touches": -1}
        self.call_from_thread(self._show, pv)

    def _show(self, pv):
        self._pv = pv
        self._render()

    def _render(self):
        pv = self._pv or {}
        L = []
        wide = self.side.size.width or 44

        def title(t):
            if L:
                L.append(Text(""))
            L.append(Text(" %s %s" % (t.upper(), "─" * max(0, wide - len(t) - 6)), style="bold cyan"))

        for sec in pv.get("head_sections") or []:
            title((sec.get("label") or "?").lower())
            for ln in [x for x in (sec.get("body") or "").splitlines() if x.strip()][:3]:
                L.append(Text("  " + shorten(ln, max(10, wide - 4)), style="dim"))
        title("etat")
        for label, verdict, fault in pv.get("rows") or []:
            L.append(Text(line(label, verdict, "", wide), style="red" if fault else ""))
        title("skill")
        L.append(Text("  " + (pv.get("skill") or "aucune"), style="cyan" if pv.get("skill") else "dim"))
        title("projet")
        L.append(Text("  " + (pv.get("projet") or "aucun"), style="cyan" if pv.get("projet") else "dim"))
        title("session")
        f = (pv.get("engine") or {}).get("context") or 0
        tk = pv.get("tokens") or {}
        total = tk.get("session_tokens") or 0
        part = (" (%d%%)" % int(total * 100 / f)) if f and total else ""
        L.append(Text("  %s / %s%s · %s / tour" % (human_count(total), human_count(f) if f else "?",
                                                   part, human_count(tk.get("last_turn") or 0)), style="cyan"))
        keys = pv.get("touches", -1)
        L.append(Text("  %s · %s" % (pv.get("branche") or "?",
                                     "propre" if keys == 0 else "%d modifie(s)" % keys),
                      style="green" if keys == 0 else "yellow"))
        L.append(Text("  bridge " + ("up" if pv.get("bridge_up") else "silent"),
                      style="green" if pv.get("bridge_up") else "red"))
        title("tour")
        if self.running:
            L.append(Text("  %.1f s · %d outil(s)" % (time.time() - self.start, self.tools), style="yellow"))
        else:
            L.append(Text("  au repos", style="dim"))
            L.append(Text(""))
            L.append(Text("  Ctrl-C pose le mot", style="dim"))
        self.side.update(Text("\n").join(L))

    def pump(self):
        for e in self.st.new_lines():
            if e.get("kind") != "think":
                continue
            txt = " ".join(str(e.get("text") or e.get("raw") or "").split())
            if txt:
                self.stream.write(Text("· " + (txt[:400] + ("…" if len(txt) > 400 else "")),
                                    style="dim italic"))
        for e in self.sj.new_lines():
            if e.get("kind") != "tool":
                continue
            l, ok = _tool_line(e, max(40, (self.stream.size.width or 78) - 8))
            if l:
                self.tools += 1
                self.stream.write(Text(("  ✓ " if ok else "  ✗ ") + l, style="green" if ok else "red"))
        for e in self.sr.new_lines():
            k = e.get("kind")
            if k == "reply" and e.get("text"):
                self.draft = e["text"]
            elif k in ("tool", "end"):
                self.draft = ""
        if self.running and self.draft.strip():
            if self.draft != self._lastdraft:
                self.draftw.update(Markdown(self.draft))
                self._lastdraft = self.draft
            self.draftw.add_class("on")
        elif not self.running and self._lastdraft:
            self.draftw.update(Markdown(""))
            self._lastdraft = ""
            self.draftw.remove_class("on")
        if self.running or self.draft:
            self._render()

    def on_input_submitted(self, ev):
        text = (ev.value or "").strip()
        ev.input.value = ""
        if not text:
            return
        if text.endswith("\\"):
            self.pending += text[:-1].rstrip() + "\n"
            self.input.placeholder = "… suite (ligne vide ou Entree seule envoie)"
            return
        if self.pending:
            text = self.pending + text
            self.pending = ""
            self.input.placeholder = "ta demande — /help pour les commandes"
        if not text.strip():
            return
        self._remember(text)
        if text.startswith("/"):
            self.command(text)
            return
        self.request(text)
        self.start_turn(text)

    def _remember(self, text):
        self.history.append(text)
        self.idx_hist = len(self.history)
        try:
            with open(HIST, "w", encoding="utf-8") as f:
                f.write("\n".join(self.history[-500:]) + "\n")
        except OSError:
            pass

    def _read_history(self):
        try:
            with open(HIST, encoding="utf-8", errors="replace") as f:
                return [l.rstrip("\n") for l in f if l.strip()]
        except OSError:
            return []

    def on_key(self, ev):
        if ev.key == "tab":
            ev.stop()
            ev.prevent_default()
            self.input.focus()
            self.completer()
            return
        if self.input.has_focus and ev.key in ("up", "down") and self.history:
            if ev.key == "up":
                self.idx_hist = max(0, self.idx_hist - 1)
            else:
                self.idx_hist = min(len(self.history), self.idx_hist + 1)
            self.input.value = (self.history[self.idx_hist]
                                 if self.idx_hist < len(self.history) else "")
            self.input.cursor_position = len(self.input.value)
            ev.stop()

    def completer(self):
        val = self.input.value
        if not val.startswith("/"):
            return
        matches = [c for c in CMDS if c.startswith(val)]
        if not matches:
            return
        if len(matches) == 1:
            self.input.value = matches[0] + " "
        else:
            common = os.path.commonprefix(matches)
            if len(common) > len(val):
                self.input.value = common
            elif val in matches:
                i = matches.index(val)
                self.input.value = matches[(i + 1) % len(matches)]
            else:
                self.input.value = matches[0]
        self.input.cursor_position = len(self.input.value)

    def command(self, t):
        name, _, arg = t[1:].partition(" ")
        arg = arg.strip()
        if name in ("q", "quit", "exit"):
            self.exit()
            return
        if name == "clear":
            self.stream.clear()
            self.banner()
            return
        if name in ("help", "h", "?"):
            self.echo("  ici : /help /clear /resume [n] /last [n] /board /app /q", "dim")
            self.echo("  au tableau : /engine /plan /head /agents /ps /update /stop /skill /project /doctor /new /to /tools", "dim")
            self.echo("  une ligne sans / est une demande : elle part au bridge, en tour.", "dim")
            return
        if name == "resume":
            passes = model.query(
                "select exchange, role, content from messages where role in ('user','assistant') "
                "and coalesce(content,'') != '' order by id desc limit ?",
                ((int(arg) if arg.isdigit() else 3) * 2,))
            passes.reverse()
            stream, out = None, []
            for r in passes:
                if r["role"] == "user":
                    stream = {"request": r["content"], "reply": ""}
                    out.append(stream)
                elif stream is not None:
                    stream["reply"] = r["content"]
            if not out:
                self.echo("  rien a remontrer : aucun echange dans la base", "dim")
            for e in out:
                self.request(e["request"])
                if e["reply"].strip():
                    self.answer(e["reply"])
            return
        if name == "last":
            res = model.query("select name, content from messages where role = 'tool' "
                              "and coalesce(content,'') != '' order by id desc limit ?",
                              (int(arg) if arg.isdigit() else 2,))
            res.reverse()
            if not res:
                self.echo("  aucun resultat d'outil dans la base", "dim")
            for r in res:
                self.stream.write(Text("── %s" % (r["name"] or "?"), style="bold green"))
                self.stream.write(Text(shorten(r["content"], 3000)))
            return
        if name in ("board", "app"):
            cmd = (["la", "--app"] if name == "app" else
                   ["/usr/bin/python3", os.path.abspath(__file__)])
            try:
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.echo("  %s : fenetre demandee" % name, "dim")
            except OSError as e:
                self.error("impossible d'ouvrir %s (%s)" % (name, e))
            return
        try:
            _, d = http("/command", {"line": t}, timeout=120)
        except (urllib.error.URLError, OSError) as e:
            self.error("le bridge n'a pas pris la commande (%s)" % e)
            return
        if d.get("kind") == "agent":
            self.answer(d.get("text") or "")
            return
        if d.get("agents"):
            for a in d["agents"]:
                alive = a.get("status") != "idle"
                self.echo("  %-18s %-8s %s" % (a.get("name", "?"), a.get("status", "?"),
                                               shorten(a.get("task") or "", 60)),
                          "green" if alive else "dim")
            return
        if d.get("head"):
            for s in d["head"]:
                self.echo("  == %s (%s signes)" % (s.get("label") or "(sans titre)", s.get("bytes") or 0), "cyan")
            return
        if d.get("ps"):
            for u, e in d["ps"].items():
                self.echo("  %-20s %s" % (u, e), "green" if e == "active" else "red")
            tk = d.get("tokens") or {}
            f = model.engine()["context"]
            self.echo("  jetons %s / %s · %s / tour" % (human_count(tk.get("session_tokens", 0)),
                                                       human_count(f) if f else "?",
                                                       human_count(tk.get("last_turn", 0))), "cyan")
            return
        if d.get("engines"):
            for m in d["engines"]:
                active = str(m.get("active", "")).lower() in ("true", "1")
                self.echo("  %s %-12s %-14s %s" % ("*" if active else " ", m.get("alias", "?"),
                                                   m.get("provider", "?"), m.get("model", "?")),
                          "cyan" if active else "dim")
            return
        self.echo("  " + (d.get("text") or ""), "green" if d.get("ok") else "red")

    def start_turn(self, text):
        if self.running:
            self.echo("  un tour tourne deja : ton mot entre dans la file", "yellow")
            self.run_worker(lambda: self._queue(text), thread=True)
            return
        self.running = True
        self.start = time.time()
        self.tools = 0
        self.draft = ""
        self.state()
        self.run_worker(lambda: self._turn(text), thread=True, exclusive=True)

    def _queue(self, text):
        try:
            _, obj = http("/say", {"text": text}, timeout=1800)
        except Exception as e:
            self.call_from_thread(self.error, "le bridge n a pas pris le mot : %s" % e)
            return
        obj = obj or {}
        if obj.get("queued"):
            self.call_from_thread(self.echo,
                                  "  " + str(obj.get("note") or "ton mot est entre dans la file"), "yellow")
        else:
            self.call_from_thread(self.answer, str(obj.get("response") or ""))

    def _turn(self, text):
        try:
            _, obj = http("/say", {"text": text}, timeout=1800)
        except Exception as e:
            self.call_from_thread(self._done, None, str(e))
            return
        self.call_from_thread(self._done, obj, None)

    def _done(self, obj, fault):
        self.running = False
        self.draft = ""
        if fault:
            self.error("le tour n'a pas abouti : %s" % fault)
        elif obj and obj.get("queued"):
            self.echo("  " + str(obj.get("note") or "ton mot est entre dans la file"), "yellow")
        elif obj:
            self.answer(str(obj.get("response") or ""))
        if self.start:
            elapsed = time.time() - self.start
            self.echo("  tour fini en %.1f s · %d outil(s) · %s jetons"
                      % (elapsed, self.tools, human_count(model.tokens()["last_turn"])), "dim")
        self.state()
        self.input.focus()

    def action_post(self):
        if not self.running:
            self.echo("  aucun tour en cours", "dim")
            return
        try:
            http("/stop", {}, timeout=5)
            self.echo("  mot pose : le tour s'arretera a sa prochaine echeance", "yellow")
        except (urllib.error.URLError, OSError):
            self.error("/stop n'a pas pu etre pose")

    def action_last(self):
        self.command("/last")

    def action_quit(self):
        self.exit()

def cli():
    Cli().run()
    return 0


def main():
    ap = argparse.ArgumentParser(description="le tableau de LA : ce qui est charge, et ce qui se passe")
    ap.add_argument("--once", action="store_true", help="one pass, then it exits (code = faults)")
    ap.add_argument("--line", action="store_true", help="one line for a panel button (light)")
    ap.add_argument("--check", action="store_true",
                    help="la liste de controle seule, en colonnes (pour un terminal)")
    ap.add_argument("--menu", action="store_true",
                    help="la liste pour un menu : « etat|etiquette|verdict », une ligne par mesure")
    ap.add_argument("--cli", action="store_true", help="the cli (a stream, a state, an input)")
    ap.add_argument("--say", metavar="TEXT", help="one turn, the reply on stdout")
    ap.add_argument("--watch", type=float, default=3.0, help="seconds between two redraws")
    ap.add_argument("--width", type=int, default=0, help="forced width (default: the terminal)")
    a = ap.parse_args()

    if a.say:
        return one_turn(a.say)

    if a.cli:
        if not (sys.stdin.isatty() and sys.stdout.isatty()):
            sys.stderr.write('la: pas de terminal — un tour : la --say "..." ; le panneau : la --once\n')
            return 2
        return cli()

    if a.line:
        print(one_line())
        return 0

    if a.check:
        width = a.width or int(os.environ.get("COLUMNS") or 0) or 64
        L, faults, *_ = control()
        print("\n".join(line(x[0], x[1], "", width) for x in L))
        return 1 if faults else 0

    if a.menu:
        L, faults, *_ = control()
        def title(name):
            n = name.lower()
            if n in RESIDENT_NAMES or n == "residents":
                return "RESIDENT"
            if n.startswith("gpu ") or n == "ram of la":
                return "GPU/RAM"
            if n == "indra ocr" or n == "vision":
                return "TOOLS"
            if n.startswith("resident "):
                return "LA"
            if n in ("la status", "residents", "ram of la", "sessions", "last_activity"):
                return "LA"
            if n in ("approbation", "feu vert"):
                return "LA"
            if n in ("api", "endpoint", "api status", "bridge_up", "vision"):
                return "RESEAU"
            return "SYSTEME"

        def short(name, value):
            n = name.lower()
            if n == "endpoint":
                return value.replace("https://", "").split("/")[0]
            if n == "last_activity":
                return value.split(" ", 1)[1] if " " in value else value
            if n == "api":
                return value.split(" : ")[-1]
            if n == "sessions":
                return value.replace("exchanges", "exch.").replace(" / last no. ", " / ")
            if n == "git":
                return value.replace("tracked / ", "")
            return value

        rank = {"LA": 0, "RESIDENT": 1, "TOOLS": 2, "GPU/RAM": 3, "SYSTEME": 4, "RESEAU": 5}
        # le cli se range SOUS dash : il ferme la section SYSTEME
        _prio = {"la status": 0, "approbation": 1, "cli": 10}
        print("\n".join("%s|%s|%s|%s" % ("ko" if x[2] else "ok", title(x[0]), x[0],
                                        short(x[0], x[1]))
                        for x in sorted(L, key=lambda x: (rank[title(x[0])],
                                                         _prio.get(x[0].lower(), 9)))))
        return 1 if faults else 0

    if a.once:
        width = a.width or int(os.environ.get("COLUMNS") or 0) or DEFAULT_WIDTH
        out, faults = sections(width)
        print("\n".join(out))
        return 1 if faults else 0

    try:
        signal.signal(signal.SIGWINCH, _sigwinch)
    except (ValueError, AttributeError, OSError):
        pass
    return tui(a, sys.stdout)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
    except BrokenPipeError:
        os._exit(0)