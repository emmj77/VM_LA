# id: P02
# role: the bridge. page, API, audio, delegate. transport only: it decides nothing,
# it holds no address, and it reads the environment instead of a file or a path.
import json
import os
import re
import subprocess
import tempfile
import sys
import ssl
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NEEDED = ("LA_HOST", "LA_PORT_BRIDGE", "LA_PAGE", "LA_STATE", "LA_AUDIO", "LA_TOOL")

TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".json": "application/json",
    ".webmanifest": "application/manifest+json",
    ".wav": "audio/wav",
    ".webm": "audio/webm",
    ".ogg": "audio/ogg",
    ".mp4": "audio/mp4",
    ".apk": "application/vnd.android.package-archive",
}


def env(name):
    v = os.environ.get(name, "").strip()
    if not v:
        die("%s is not set" % name)
    return v


def die(message):
    sys.stderr.write("bridge: %s\n" % message)
    raise SystemExit(1)


def state_file(name):
    return os.path.join(os.environ["LA_STATE"], name)


def kind_of(path):
    return TYPES.get(os.path.splitext(path)[1].lower(), "application/octet-stream")


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def ask(kind, tool, args, feed=None, secs=240):
    """one round trip to the door, unwrapped: the bridge never decides anything itself"""
    run = subprocess.run(["dash", os.environ["LA_TOOL"], kind, tool] + args,
                         input=feed, capture_output=True, text=True, timeout=secs)
    txt = (run.stdout or "").strip()
    try:
        d = json.loads(txt)
    except Exception:
        return {"error": txt or (run.stderr or "").strip()}
    v = d.get("result", d) if isinstance(d, dict) else d
    if isinstance(v, str):
        try:
            v = json.loads(v)
        except Exception:
            pass
    return v


def delegate(tool, args):
    """the only thing this file does besides transport: it hands the work to the door"""
    cmd = ["dash", os.environ["LA_TOOL"], "tool", tool] + args
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return {"tool": tool, "rc": p.returncode, "out": (p.stdout or "").strip(),
            "err": (p.stderr or "").strip()}


CONF = {"mt": None, "raw": {}}


def conf(section=None):
    """the master file as a dict, reread when it moves. never written here."""
    path = os.environ.get("LA_CONFIG", "")
    try:
        mt = os.stat(path).st_mtime_ns
    except OSError:
        return {}
    if CONF["mt"] != mt:
        try:
            import yaml
            with open(path, encoding="utf-8") as f:
                CONF["raw"] = yaml.safe_load(f) or {}
        except Exception:
            CONF["raw"] = {}
        CONF["mt"] = mt
    raw = CONF["raw"] or {}
    if section:
        node = raw.get(section)
        return node if isinstance(node, dict) else {}
    return raw


def conf_section(name):
    """a section that moved to its own file sits beside the master: conf/<name>.yaml"""
    node = conf(name)
    if isinstance(node, dict) and node:
        return node
    path = os.path.join(os.path.dirname(os.environ.get("LA_CONFIG", "")), "%s.yaml" % name)
    try:
        import yaml
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def root_file(rel):
    return os.path.join(os.environ.get("LA_ROOT", "."), rel)


def active_name(kind):
    rel = "skills[D23]/.active" if kind == "skill" else "projects[D21]/.active"
    try:
        with open(root_file(rel), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def agents_list():
    c = conf_section("agents")
    names = str(c.get("names") or "").split()
    main = str(c.get("main") or "")
    try:
        with open(state_file("turn.pid"), encoding="utf-8") as f:
            pid = int(f.read().strip() or 0)
    except Exception:
        pid = 0
    out = []
    for n in names:
        out.append({"name": n, "main": n == main, "role": "main" if n == main else "sub",
                    "status": "running" if (n == main and pid) else "idle",
                    "pid": pid if n == main else 0})
    return out


_CACHE = {}
_BUSY = set()
CACHE_TTL = 2.0


def cached(key, ttl, fn):
    """the last answer is served at once; a thread refreshes it when it ages.
    the door stays the only source: the bridge just stops making the page wait for it."""
    hit = _CACHE.get(key)
    if hit is None:
        _CACHE[key] = [time.time(), fn()]
        return _CACHE[key][1]
    if (time.time() - hit[0]) > ttl and key not in _BUSY:
        _BUSY.add(key)

        def work():
            try:
                _CACHE[key] = [time.time(), fn()]
            except Exception:
                pass
            finally:
                _BUSY.discard(key)
        threading.Thread(target=work, daemon=True).start()
    return hit[1]


def approval_window():
    """la duree de validite d un feu vert : une seule cle dans la config, jamais deux"""
    try:
        v = (conf("limits") or {}).get("approval_window")
        return int(v) if v else 300
    except Exception:
        return 300


def _fields(path):
    """les lignes « cle: valeur » d un fichier d etat, ou None s il n existe pas"""
    d = {}
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if ":" in line:
                    k, v = line.split(":", 1)
                    d[k.strip()] = v.strip()
    except OSError:
        return None
    return d


def approval_view():
    """LA demande en attente, telle que les trois fronts la dessinent : un objet, jamais une
    phrase a decouper. L app, la page et l applet lisent ceci et rien d autre."""
    st = os.environ.get("LA_STATE", ".")
    out = {"pending": False, "tool": "", "gesture": "", "phrase": "", "age": 0,
           "signed": "", "left": 0, "window": approval_window()}
    sig = _fields(os.path.join(st, "approve"))
    if sig:
        out["signed"] = sig.get("tool", "")
        ts = sig.get("ts", "")
        if ts.isdigit():
            out["left"] = max(0, out["window"] - (int(time.time()) - int(ts)))
    req = _fields(os.path.join(st, "approve.request"))
    if req:
        tool = req.get("tool", "")
        gesture = req.get("gesture") or tool
        ts = req.get("ts", "")
        age = max(0, int(time.time()) - int(ts)) if ts.isdigit() else 0
        # UNE REGLE, LA MEME PARTOUT : une demande est satisfaite quand la signature porte SON
        # digest et qu elle vit encore. L age des fichiers ne dit rien de cela.
        done = (bool(sig) and sig.get("digest") == req.get("digest") and out["left"] > 0)
        if not done:
            out.update({"pending": True, "tool": tool, "gesture": gesture, "age": age,
                        "phrase": "le moteur demande %s" % (gesture or tool)})
    return out


def board_json():
    """le board tel que board.py le mesure : le pont transporte, il ne calcule rien.
    le menu (sections, ordre, icones) vient de la_config, pas d ici."""
    prog = os.environ.get("LA_BOARD") or ""
    if not prog or not os.path.isfile(prog):
        return {"faults": 1, "sections": [], "error": "board.py introuvable (LA_BOARD)"}
    try:
        r = subprocess.run(["python3", prog, "--json"], capture_output=True, text=True, timeout=40)
    except (OSError, subprocess.SubprocessError) as e:
        return {"faults": 1, "sections": [], "error": str(e)[:200]}
    out = (r.stdout or "").strip()
    if not out:
        return {"faults": 1, "sections": [], "error": (r.stderr or "board.py n a rien dit")[:200]}
    try:
        return json.loads(out)
    except ValueError:
        return {"faults": 1, "sections": [], "error": out[:200]}


def _door_read(kind, tool, args, fallback):
    try:
        v = ask(kind, tool, args)
    except Exception:
        return fallback
    if isinstance(v, dict) and "error" in v:
        return fallback
    if isinstance(v, str):
        try:
            v = json.loads(v)
        except ValueError:
            return fallback
    return v if isinstance(v, (dict, list)) else fallback


_NOISE = re.compile(r"^(\d+\s*(tokens?|bytes?|octets?)|turn\s+(start|closed|done\b.*)|"
                    r"stopped\s*:.*|facts\b.*|reply\s+\d+\s*\w+)$", re.I)


def _thinking_keep(text):
    """one line of reasoning, or nothing when the engine only counted itself."""
    t = " ".join(str(text).split())
    if not t or _NOISE.match(t):
        return ""
    return t


def _keep_turn(prompt, reply):
    """one exchange into the base: the user's words and the answer, the thinking beside them."""
    try:
        with open(_turn_file("turn.json"), encoding="utf-8", errors="replace") as f:
            t = json.load(f)
    except (OSError, ValueError):
        t = {}
    ex = "".join(c for c in str(t.get("id") or "") if c.isdigit())
    if not ex:
        return
    msg = t.get("reply_msg") or {}
    said = " ".join(str(prompt or t.get("prompt") or "").split())
    answer = " ".join(str(reply or msg.get("content") or "").split())
    thought = str(msg.get("reasoning") or "").strip()
    for role, content in (("user", said), ("assistant", answer)):
        if not content:
            continue
        body = json.dumps({"exchange": ex, "role": role, "content": content,
                           "reasoning": thought if role == "assistant" else ""})
        try:
            r = subprocess.run(["dash", os.environ["LA_TOOL"], "engine", "engine.hist", "op=add"],
                               input=body, capture_output=True, text=True, timeout=20)
            if r.returncode or '"status":"ok"' not in (r.stdout or ""):
                sys.stderr.write("hist add %s: %s\n" % (role, (r.stdout or r.stderr or "")[:160]))
        except Exception as e:
            sys.stderr.write("hist add %s: %s\n" % (role, e))


def _machine_return():
    """what the machine has to say: a process that ended, a reading of the machine."""
    out = []
    try:
        r = subprocess.run(["systemctl", "--user", "list-units", "--type=service",
                            "--state=failed", "--no-legend", "--plain"],
                           capture_output=True, text=True, timeout=6)
        for line in (r.stdout or "").splitlines():
            unit = (line.split() or [""])[0]
            if unit:
                out.append("process finished: %s failed" % unit)
    except Exception:
        pass
    try:
        with open("/proc/loadavg") as f:
            load = float(f.read().split()[0])
        mem = {}
        with open("/proc/meminfo") as f:
            for ln in f:
                k, _, v = ln.partition(":")
                mem[k] = int(v.split()[0])
        pct = int(100 * (mem["MemTotal"] - mem["MemAvailable"]) / max(1, mem["MemTotal"]))
        out.append("system reading: load %.2f, memory %d%%" % (load, pct))
    except Exception:
        pass
    return out


def _watch_armed():
    return os.path.isfile(_turn_file("watch.armed"))


def _watch_once():
    """one pass: the fresh events go to the judge, its verdict to the channel.

    the automatic rest is armed by an answer (law 1544); its return goes to the judge,
    never to the agent (law 1545). one automatic system per session (law 1551).
    """
    seen_f = _turn_file("watch.seen")
    try:
        with open(seen_f, encoding="utf-8") as f:
            seen = set(json.load(f))
    except Exception:
        seen = set()
    events = []
    # the sleep drops its return here when systemd reaches its deadline
    ev_f = _turn_file("watch.event")
    if os.path.isfile(ev_f):
        try:
            with open(ev_f, encoding="utf-8") as f:
                line = f.read().strip()
        except OSError:
            line = ""
        try:
            os.unlink(ev_f)
        except OSError:
            pass
        if line:
            events.append(line)
    for line in _machine_return():
        if line.startswith("process finished") and line not in seen:
            events.append(line)
            seen.add(line)
    try:
        with open(seen_f, "w", encoding="utf-8") as f:
            json.dump(sorted(seen)[-80:], f)
    except OSError:
        pass
    # a reading only counts when it is out of the ordinary
    for line in _machine_return():
        if line.startswith("system reading"):
            try:
                pct = int(line.rsplit("memory ", 1)[1].rstrip("%"))
            except Exception:
                pct = 0
            if pct >= 92:
                events.append(line)
    for ev in events:
        try:
            said = ask("engine", "watch.judge", ["op=judge"], feed=ev, secs=30)
        except Exception:
            continue
        if isinstance(said, dict):
            said = said.get("result") or ""
        said = str(said)
        if said.startswith("ok wake"):
            # a wake opens a request (law 1549) and never widens the scope (law 1550)
            try:
                ask("engine", "engine.wake", [], feed=ev, secs=30)
            except Exception:
                pass
            try:
                os.unlink(_turn_file("watch.armed"))
            except OSError:
                pass
            try:
                ask("engine", "engine.turn", ["text=reveil: " + ev], secs=600)
            except Exception:
                pass
            break


def watch_loop():
    """the automatic rest, in the bridge: a turn dies, the bridge lives (law 1545)."""
    while True:
        try:
            secs = float(os.environ.get("LA_WATCH_SECONDS") or 15)
        except ValueError:
            secs = 15.0
        time.sleep(secs)
        try:
            if not _watch_armed():
                continue
            if os.path.isfile(_turn_file("turn.pid")):
                continue
            _watch_once()
        except Exception as e:
            sys.stderr.write("watch: %s\n" % e)


def _turn_file(name):
    return os.path.join(os.environ.get("LA_STATE") or ".", name)


def _trace_events():
    """the events of the current turn, in the order they arrived"""
    out = []
    try:
        with open(_turn_file("trace.jsonl"), "r", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass
    except OSError:
        pass
    # the banner shows the current turn only: the last "turn start" opens the window
    for i in range(len(out) - 1, -1, -1):
        e = out[i]
        if e.get("kind") == "turn" and str(e.get("text") or "").startswith("start"):
            return out[i + 1:]
    return out


def warm():
    """the three reads the page asks for at once, warmed at boot so opening is instant"""
    for key, kind, tool, args, fb in (
            ("board", "engine", "engine.board", ["op=json"], {}),
            ("trace", "engine", "engine.trace", ["op=json"],
             {"thinking": [], "journal": [], "reply": {}}),
            ("hist", "engine", "engine.hist", ["op=turns"], {"turns": []})):
        try:
            _CACHE[key] = [time.time(), _door_read(kind, tool, args, fb)]
        except Exception:
            pass


def first_name(name):
    """the name IS the id: paul -> paul"""
    tail = str(name).rsplit("_", 1)[-1]
    return tail or str(name)


def summary_text():
    """C08 second.yaml: the micro-summary the local model rewrites each turn"""
    import yaml
    f = os.path.join(os.path.dirname(os.environ.get("LA_CONFIG", "")), "second.yaml")
    try:
        with open(f, encoding="utf-8") as fh:
            d = yaml.safe_load(fh) or {}
    except (OSError, yaml.YAMLError):
        return ""
    if not isinstance(d, dict):
        return ""
    sm = d.get("summary") or {}
    if isinstance(sm, dict):
        txt = " ".join(str(v) for _, v in sorted(sm.items(), key=lambda kv: str(kv[0])))
    else:
        txt = str(sm or "")
    txt = txt.strip()
    if not txt:
        return "no summary yet"
    st = str(d.get("stamp") or "")
    try:
        import calendar
        when = calendar.timegm(time.strptime(st, "%Y-%m-%dT%H:%M:%SZ"))
        if (time.time() - when) > 86400:      # older than a day: it says nothing any more
            return "no summary yet"
    except (ValueError, TypeError):
        pass
    return "exchanges %s ; written %s\n%s" % (d.get("exchanges") or "none",
                                               d.get("stamp") or "none", txt)


def short_agent_line(line, main=""):
    """THE AGENTS: the first name only, but the main agent keeps its full name"""
    if "  " in line:
        head, rest = line.split("  ", 1)
        if head.strip() == main:
            return line
        return first_name(head) + "  " + rest
    return line


def head_snapshot():
    f = state_file("second_head.yaml")
    try:
        st = os.stat(f)
    except OSError:
        return {"file": f, "present": False, "sections": [], "raw_bytes": 0, "written": None,
                "age_s": None, "why": "no head deposited"}
    try:
        with open(f, encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
    except OSError:
        raw = ""
    out = []
    label, buf, started = None, [], False

    def flush():
        body = "\n".join(buf).strip("\n")
        if label is None and not body.strip():
            return
        out.append({"label": label or "(untitled)", "body": body,
                    "bytes": len(body.encode()),
                    "lines": len([x for x in body.splitlines() if x.strip()])})

    for line in raw.splitlines():
        ln = line.strip()
        if len(ln) > 4 and ln.startswith("==") and ln.endswith("=="):
            flush()
            label, buf, started = ln.strip("=").strip(), [], True
            continue
        if not started:          # the file header before the first section
            continue
        buf.append(line)
    flush()
    out = [x for x in out if x["label"].strip().lower() != "the human"]   # no Human section
    main = str((conf().get("agents") or {}).get("main") or "")
    summ = summary_text()
    for x in out:
        lab = x["label"].strip().lower()
        if lab == "the local model summary" and summ:
            x["body"] = summ
        if lab == "the agents":
            x["body"] = "\n".join(short_agent_line(y, main) for y in x["body"].splitlines())
        x["bytes"] = len(x["body"].encode())
        x["lines"] = len([y for y in x["body"].splitlines() if y.strip()])
    return {"file": f, "present": True, "sections": out, "raw_bytes": st.st_size,
            "written": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(st.st_mtime)),
            "age_s": int(time.time() - st.st_mtime), "why": ""}


def config_page():
    """what the settings page reads: the engines, their choices, the form, the values"""
    c = conf()
    sch = c.get("schema") or {}
    out = {"ok": True, "engines": [], "engine_choices": sch.get("engine_choices") or {},
           "schema": sch.get("fields") or [], "values": {}}
    act = str(c.get("active_engine") or "")
    for alias, e in (c.get("engines") or {}).items():
        d = {"alias": alias, "active": alias == act}
        if isinstance(e, dict):
            d.update(e)
        out["engines"].append(d)
    for f in out["schema"]:
        sec, key = f.get("section"), f.get("key")
        if not sec or not key:
            continue
        node = conf_section(sec)
        if isinstance(node, dict) and key in node:
            out["values"]["%s.%s" % (sec, key)] = node[key]
    return out


def voice(text):
    """the voice resident answers a wav; the bridge only carries it"""
    port = int(os.environ.get("LA_PORT_TTS") or 8090)
    req = urllib.request.Request("http://127.0.0.1:%d/say" % port,
                                 data=json.dumps({"text": text}).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            said = r.read().decode("utf-8", "replace").strip()
    except Exception as e:
        return {"error": "%s: %s" % (type(e).__name__, e), "audio": ""}
    name = said.split("speech : ")[-1].split(" ")[0] if "speech : " in said else ""
    return {"audio": os.path.basename(name), "path": name, "said": said}


class Handler(BaseHTTPRequestHandler):
    server_version = "la-bridge"

    def log_message(self, format, *args):
        sys.stderr.write("%s %s\n" % (now(), format % args))

    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def route(self, method):
        u = urllib.parse.urlparse(self.path)
        p = u.path
        try:
            body = self.body()
            if p.startswith("/api/") or p == "/doctor":
                return self.api(p, u.query, method, body)
            if p in ("/", "/m", "/chat", "/doctor", "/plan", "/models"):
                # the page has its own door: the bridge no longer serves it, it points at it
                return self.redirect(os.environ.get("LA_DASH_URL") or "http://127.0.0.1:8771/")
            if p == "/ping":
                return self.json({"state": "alive", "port": os.environ["LA_PORT_BRIDGE"], "ts": now()})
            if p == "/board":
                # une seule mesure, deux lecteurs : l applet dessine ce que board.py a trouve
                return self.json(cached("menu", 2.0, board_json))
            if p == "/spoken":
                return self.json(self.lines(state_file("spoken.jsonl")))
            if p.startswith("/audio/"):
                return self.file(self.inside(os.environ["LA_AUDIO"], p[len("/audio/"):]))
            if p in ("/apk", "/LA-app.apk"):
                f = os.environ.get("LA_APK_FILE", "")
                if not f or not os.path.isfile(f):
                    return self.json({"error": "the apk is not built here"}, 404)
                return self.file(f, TYPES[".apk"], download="LA-app.apk")
            # THE MODEL, READ IN la_config (MOUSSA, 21/10): the app asks for its list here and
            # changes address here; without these routes it stayed without a model.
            if p == "/engine":
                if method == "POST":
                    alias = ""
                    try:
                        alias = (json.loads(body or b"{}") or {}).get("alias") or ""
                    except Exception:
                        alias = ""
                    if not alias:
                        return self.json({"error": "alias expected"}, 400)
                    # the line arrives on the body input, never as an argument
                    said = ask("engine", "engine.commands", ["op=line"], feed="/model " + alias)
                    if isinstance(said, dict):
                        said = said.get("result") or said.get("line") or said
                    return self.json({"ok": True, "alias": alias, "said": said})
                st = ask("engine", "engine.board", ["op=json"])
                cur = (st.get("model") or {}).get("alias", "") if isinstance(st, dict) else ""
                engines = []
                for e in (st.get("engines") or []) if isinstance(st, dict) else []:
                    engines.append({"alias": e.get("alias", ""), "model": e.get("model", ""),
                                    "provider": e.get("provider", ""),
                                    "active": e.get("alias", "") == cur})
                return self.json({"engines": engines, "model": st.get("model") if isinstance(st, dict) else {}})
            # THE VOICE (MOUSSA, 21/10): the app asks /tts to read a sentence and /transcribe
            # to listen; both routes were missing, hence no sound and no microphone.
            if p == "/tts":
                text = ""
                try:
                    text = (json.loads(body or b"{}") or {}).get("text") or ""
                except Exception:
                    text = ""
                if not text.strip():
                    return self.json({"error": "text expected", "audio": ""}, 400)
                got = voice(text)
                if "error" in got:
                    return self.json(got, 502)
                return self.json(got)
            if p == "/transcribe":
                if method != "POST" or not body:
                    return self.json({"error": "POST with audio expected", "text": ""}, 405)
                tmp = tempfile.mkdtemp()
                try:
                    raw = os.path.join(tmp, "in.raw")
                    with open(raw, "wb") as f:
                        f.write(body)
                    wav = os.path.join(tmp, "in.wav")
                    ff = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw,
                                         "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav],
                                        capture_output=True, text=True)
                    if ff.returncode != 0 or not os.path.isfile(wav):
                        return self.json({"error": "audio unreadable", "text": ""}, 400)
                    port = int(os.environ.get("LA_PORT_ASR") or 8080)
                    out = subprocess.run(["curl", "-s", "--max-time", "90", "-F", "file=@" + wav,
                                          "-F", "response_format=json",
                                          "http://127.0.0.1:%d/v1/audio/transcriptions" % port],
                                         capture_output=True, text=True)
                    try:
                        return self.json(json.loads(out.stdout or "{}"))
                    except Exception:
                        return self.json({"text": ""})
                finally:
                    for f in os.listdir(tmp):
                        try:
                            os.unlink(os.path.join(tmp, f))
                        except OSError:
                            pass
                    try:
                        os.rmdir(tmp)
                    except OSError:
                        pass
            # THE ROUTES THE APP ASKS WITHOUT PREFIX (MOUSSA, 21/10): it reads /state,
            # /agents, /history, /skills, /projects, /toolmap. They return the same JSON as
            # /api/*, never a page: HTML breaks it (JSONObject on a string).
            if p in ("/state", "/agents", "/history", "/skills", "/projects", "/toolmap"):
                return self.api("/api" + p, u.query, method, body)
            if p == "/journal":
                # the tool banner: one entry per act, in order
                return self.json([str(e.get("text") or "") for e in _trace_events()
                                  if e.get("kind") == "tool" and (e.get("text") or "").strip()])
            if p == "/thinking":
                # the expandable thinking: what the model thought, then the steps of the turn
                lines = []
                try:
                    with open(_turn_file("turn.json"), "r", errors="replace") as f:
                        _t = json.load(f)
                    _r = str((_t.get("reply_msg") or {}).get("reasoning") or "").strip()
                    if _r:
                        lines += [x.strip() for x in _r.split("\n\n") if x.strip()]
                except (OSError, ValueError):
                    pass
                lines += [str(e.get("text")) for e in _trace_events()
                          if e.get("kind") in ("step", "call", "reply", "note") and e.get("text")]
                # the engine writes counters next to the model's words: they are not reasoning
                lines = [l for l in (_thinking_keep(x) for x in lines) if l]
                return self.json(lines)
            if p == "/approval":
                # un OBJET, jamais une phrase : l app le passe a JSONObject et casse sinon.
                # pending / tool / gesture / phrase / age : le meme contrat pour les trois fronts.
                return self.json(approval_view())
            if p in ("/approve", "/deny"):
                # the body reads the act on its input: /approve signs the one waiting
                _g = ""
                try:
                    _b = json.loads(body or b"{}")
                    _g = str(_b.get("tool") or _b.get("gesture") or "")
                except Exception:
                    _g = (body or b"").decode("utf-8", "replace").strip()
                if not _g:
                    # sans corps : c est le geste qui attend qui est signe, et seulement s il attend
                    _g = (approval_view().get("gesture") or "").strip()
                _op = "allow" if p == "/approve" else "deny"
                if not _g:
                    return self.json({"ok": False, "text": "rien n attend",
                                      "approval": approval_view()})
                said = ask("engine", "engine.approve", ["op=" + _op], feed=_g)
                return self.json({"ok": True, "op": _op, "said": said,
                                  "approval": approval_view()})
            if p.startswith("/audio/"):
                return self.file(self.inside(os.environ["LA_AUDIO"], p[len("/audio/"):]))
            if p == "/stop":
                open(state_file("stop"), "w").close()
                return self.json({"state": "stopped", "ts": now()})
            if p.startswith("/static/"):
                return self.file(self.inside(os.environ["LA_PAGE"], p[len("/static/"):]))
            # the phone: its app, its icon and the service worker that updates it
            if p in ("/widget", "/widget.html"):
                return self.file(os.path.join(os.environ["LA_PAGE"], "widget.html"), "text/html; charset=utf-8")
            if p == "/manifest.webmanifest":
                return self.file(os.path.join(os.environ["LA_PAGE"], "widget.webmanifest"), "application/manifest+json")
            if p == "/icon.svg":
                return self.file(os.path.join(os.environ["LA_PAGE"], "widget-icon.svg"), "image/svg+xml")
            if p == "/sw.js":
                return self.file(os.path.join(os.environ["LA_PAGE"], "widget-sw.js"), "text/javascript; charset=utf-8")
            # THE PANELS OF THE PAGE: they belong to the page, not to the bridge.
            if p in ("/say", "/command", "/voice", "/image", "/delegate"):
                if method != "POST":
                    return self.json({"error": "POST expected for %s" % p}, 405)
                return self.work(p, body, u.query)
            return self.json({"error": "no such address: %s" % p}, 404)
        except SystemExit:
            raise
        except Exception as e:  # one bad request never takes the server down
            return self.json({"error": "%s: %s" % (type(e).__name__, e)}, 500)

    def api(self, path, query, method, body):
        """the page and the phone ask here; every answer comes from the door, never from here"""
        parts = [x for x in urllib.parse.urlparse(path).path.strip("/").split("/") if x]
        if path.rstrip("/") == "/doctor":
            name = "doctor"
        else:
            name = parts[1] if len(parts) > 1 else ""
        rest = parts[2:]
        payload = {}
        if body:
            try:
                payload = self.object(body)
            except Exception:
                payload = {}

        if name in ("skills", "projects", "toolmap", "agents"):
            return self.json(self.panels(name))

        # ---- l approbation : la meme reponse pour la page, l app et l applet.
        # la page signe par ICI, pas par /command : un feu vert n est pas une commande.
        if name == "approval":
            return self.json(approval_view())
        if name in ("approve", "deny"):
            view = approval_view()
            if not view.get("pending"):
                # rien n attend : on ne signe pas le vide, et on ne fait pas parler la porte
                return self.json({"ok": False, "text": "rien n attend", "approval": view})
            _g = str(payload.get("tool") or payload.get("gesture") or "").strip()
            if not _g:
                _g = (view.get("gesture") or "").strip()
            _op = "allow" if name == "approve" else "deny"
            said = ask("engine", "engine.approve", ["op=" + _op], feed=_g)
            return self.json({"ok": True, "op": _op, "said": said,
                              "approval": approval_view()})

        def door(kind, tool, args, feed=None, secs=200):
            return subprocess.run(["dash", os.environ["LA_TOOL"], kind, tool] + args,
                                  input=feed, capture_output=True, text=True, timeout=secs)

        def as_json(run, fallback=None):
            txt = (run.stdout or "").strip()
            if not txt:
                return fallback if fallback is not None else {"error": (run.stderr or "no answer").strip()}
            try:
                d = json.loads(txt)
            except ValueError:
                return {"text": txt, "ok": run.returncode == 0}
            # the door answers with its own envelope: the body speaks inside "result"
            if isinstance(d, dict) and "status" in d and "result" in d:
                inner = str(d.get("result") or "").strip()
                if inner[:1] in ("{", "["):
                    try:
                        return json.loads(inner)
                    except ValueError:
                        return {"text": inner, "ok": d.get("status") == "ok"}
                return {"text": inner, "ok": d.get("status") == "ok"}
            return d

        if name == "state":
            got = cached("board", 1.5, lambda: as_json(door("engine", "engine.board", ["op=json"]), {}))
            if not isinstance(got, dict):
                got = {}
            got["agents"] = agents_list()
            nm = got.get("names")
            nm = dict(nm) if isinstance(nm, dict) else {}
            nm["list"] = [a["name"] for a in got["agents"]]
            got["names"] = nm
            got["skill"] = got.get("skill") or active_name("skill")
            got["project"] = got.get("project") or active_name("project")
            return self.json(got)
        if name == "live":
            got = cached("trace", 5.0, lambda: as_json(
                door("engine", "engine.trace", ["op=json"]),
                {"thinking": [], "journal": [], "reply": {}}))
            return self.json(got)
        if name == "history":
            # the enum arg goes in positionally: "op=turns" is a word the body never knows
            got = cached("hist", 5.0, lambda: as_json(
                door("engine", "engine.hist", ["op=turns"]), {"turns": []}))
            return self.json(got)
        if name == "cmd":
            line = str(payload.get("line") or urllib.parse.parse_qs(query).get("line", [""])[0]).strip()
            if not line:
                return self.json({"ok": False, "error": "a line is expected"}, 400)
            r = door("engine", "engine.commands", ["op=line"], feed=line, secs=600)
            got = as_json(r, {"ok": r.returncode == 0, "text": (r.stderr or "").strip()})
            # la porte rend une enveloppe : la page veut le RESULTAT et le code, pas l enveloppe
            if isinstance(got, dict) and "result" in got:
                got["text"] = str(got.get("result") or "")
                got["rc"] = int(str(got.get("return") or 0) or 0)
                got["ok"] = got["rc"] == 0
            if "text" not in got:
                got = {"ok": got.get("ok", True), "text": json.dumps(got)[:400]}
            return self.json(got)
        if name == "say":
            text = str(payload.get("text") or "").strip()
            if not text:
                return self.json({"ok": False, "error": "a text is expected"}, 400)
            r = door("engine", "engine.commands", ["op=say"], feed=text, secs=600)
            got = as_json(r, {"text": (r.stdout or r.stderr or "").strip()})
            out = str(got.get("text") or "").strip()
            ok = r.returncode == 0 and not out.startswith("FAULT")
            return self.json({"ok": ok, "bridge": {"queued": False,
                                                   "response": out if ok else "",
                                                   "note": "" if ok else out,
                                                   "error": "" if ok else out}})
        if name == "doctor":
            r = door("engine", "engine.doctor", ["op=json"], secs=300)
            got = as_json(r, {"text": (r.stdout or "").strip()})
            if "rc" not in got:
                got["rc"] = 0 if (r.stdout or "").startswith("ok") else 1
            return self.json(got)
        if name == "residents":
            what = str(payload.get("op") or "status")
            if what not in ("status", "up", "down", "toggle"):
                what = "status"
            r = door("engine", "engine.residents", ["op=" + what], secs=240)
            got = as_json(r, {"text": (r.stdout or r.stderr or "").strip()})
            return self.json({"ok": r.returncode == 0, "op": what,
                              "text": str(got.get("text") or (r.stdout or "").strip())})
        if name == "version":
            r = subprocess.run(["dash", os.environ["LA_TOOL"], "version"],
                               capture_output=True, text=True, timeout=60)
            return self.json({"ok": r.returncode == 0, "version": (r.stdout or "").strip()})
        if name == "update":
            what = rest[0] if rest else "check"
            r = door("engine", "engine.update", ["op=" + what], secs=600)
            got = as_json(r, {})
            txt = got.get("text") if isinstance(got, dict) else ""
            return self.json({"ok": r.returncode == 0,
                              "text": str(txt or (r.stdout or r.stderr or "").strip())})
        if name == "head":
            return self.json(head_snapshot())
        if name == "skills":
            return self.json(self.panels("skills"))
        if name == "skill":
            return self.json({"skill": active_name("skill"), "project": active_name("project")})
        if name == "agents":
            return self.json({"agents": agents_list()})
        if name == "config":
            if method == "POST":
                return self.json({"ok": False,
                                  "text": "the master file has no writer here yet"}, 400)
            return self.json(config_page())
        if name == "tts":
            text = str(payload.get("text") or "").strip()
            if not text:
                return self.json({"ok": False, "error": "a text is expected", "audio": ""}, 400)
            got = voice(text)
            out = dict({"ok": "error" not in got})
            out.update(got)
            return self.json(out)
        return self.json({"error": "no such api: %s" % path}, 404)

    def panels(self, name):
        """the four lists the phone shows, read from the tree: no tool owns them yet"""
        root = os.environ.get("LA_ROOT") or "."
        def inner(rel):
            p = os.path.join(root, rel)
            out = []
            if os.path.isdir(p):
                for d in sorted(os.listdir(p))[:120]:
                    q = os.path.join(p, d)
                    if os.path.isdir(q):
                        out.append({"name": d, "path": os.path.relpath(q, root)})
            return out
        if name == "skills":
            act = active_name("skill")
            items = inner("skills[D23]")
            for it in items:
                it["active"] = it.get("name") == act
            return {"skills": items}
        if name == "projects":
            act = active_name("project")
            items = inner("projects[D21]")
            for it in items:
                it["active"] = it.get("name") == act
            return {"projects": items}
        if name == "agents":
            return {"agents": agents_list()}
        fam, cur = {}, None
        reg = os.path.join(root, "config[D01]", "tools[D14]", "registry.yaml")
        if os.path.isfile(reg):
            for line in open(reg, errors="ignore"):
                m = re.match(r'\s*family:\s*"?([A-Za-z_0-9]+)"?', line)
                if m:
                    cur = m.group(1)
                    fam[cur] = fam.get(cur, 0) + 1
        return {"toolmap": [{"family": k, "count": v} for k, v in sorted(fam.items())]}

    def work(self, p, body, query):
        payload = self.object(body)
        if p == "/say":
            # a sentence from the app runs the turn NOW: the app waits for the answer, not a queue
            text = str(payload.get("text") or body.decode("utf-8", "replace")).strip()
            if not text:
                return self.json({"error": "a text is expected"}, 400)
            ask("engine", "engine.turn", ["text=" + text], secs=600)
            try:
                with open(state_file("reply.stream"), "r", encoding="utf-8", errors="replace") as f:
                    rep = f.read().strip()
            except OSError:
                rep = ""
            _keep_turn(text, rep)
            return self.json({"response": rep, "code": 0, "queued": False})
        if p == "/command":
            line = str(payload.get("line") or query or "").strip()
            if not line:
                return self.json({"error": "a line is expected"}, 400)
            # the line is read on the input, through the engine door: it does not go through
            # the human door, which does not know the engine's gestures (the ear, for one)
            return self.json(ask("engine", "engine.commands", ["op=line"], feed=line, secs=180))
        if p == "/delegate":
            tool = str(payload.get("tool") or "").strip()
            if not tool:
                return self.json({"error": "a tool name is expected"}, 400)
            return self.json(delegate(tool, [str(a) for a in payload.get("args", [])]))
        ext = self.extension(p, body)
        if not ext:
            return self.json({"error": "unknown audio or image type"}, 415)
        name = "%s-%d%s" % (time.strftime("%Y%m%d-%H%M%S", time.gmtime()), os.getpid(), ext)
        path = os.path.join(os.environ["LA_AUDIO"], name)
        with open(path, "wb") as f:
            f.write(body)
        tool = "asr" if p == "/voice" else "vision"
        out = delegate(tool, [os.path.basename(path)])
        out["file"] = name
        return self.json(out)

    def inside(self, root, name):
        n = os.path.basename(urllib.parse.unquote(name))
        if not n or n.startswith("."):
            raise ValueError("refused name")
        return os.path.join(root, n)

    def extension(self, p, body):
        if p == "/voice":
            ctype = (self.headers.get("Content-Type") or "").lower()
            for ext, kind in ((".wav", "wav"), (".webm", "webm"), (".ogg", "ogg"), (".mp4", "mp4")):
                if kind in ctype:
                    return ext
            return ""
        for magic, ext in ((b"\x89PNG", ".png"), (b"\xff\xd8", ".jpg"), (b"RIFF", ".wav")):
            if body.startswith(magic):
                return ext
        return ""

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n > 0 else b""

    def object(self, body):
        try:
            v = json.loads(body.decode("utf-8", "replace") or "{}")
        except ValueError:
            return {}
        return v if isinstance(v, dict) else {}

    def lines(self, path):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                return [ln.strip() for ln in f if ln.strip()]
        except OSError:
            return []

    def json(self, obj, code=200):
        return self.send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"),
                         "application/json; charset=utf-8")

    def redirect(self, url):
        """the page has its own door: the bridge says where, it does not serve it"""
        self.send_response(302)
        self.send_header("Location", url)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def file(self, path, kind=None, download=None):
        if not path or not os.path.isfile(path):
            return self.json({"error": "not there: %s" % os.path.basename(path or "")}, 404)
        with open(path, "rb") as f:
            data = f.read()
        head = {}
        if download:
            head["Content-Disposition"] = 'attachment; filename="%s"' % download
        return self.send(200, data, kind or kind_of(path), head)

    def send(self, code, data, kind, head=None):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (head or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)


def main():
    for name in NEEDED:
        env(name)
    for d in ("LA_STATE", "LA_AUDIO"):
        os.makedirs(os.environ[d], exist_ok=True)
    port = int(os.environ["LA_PORT_BRIDGE"])
    threading.Thread(target=warm, daemon=True).start()   # the page opens without waiting
    threading.Thread(target=watch_loop, daemon=True).start()   # the automatic rest and its judge
    srv = ThreadingHTTPServer((os.environ.get("LA_BRIDGE_HOST") or os.environ["LA_HOST"], port), Handler)
    sys.stderr.write("bridge: listening on %s:%d\n" % (srv.server_address[0], port))
    # THE APP SPEAKS HTTPS ON THE TLS DOOR (MOUSSA, 21/10): the same service, the same page, the
    # the same door, but encrypted, with the certificate of the project.
    tls_port = int(os.environ.get("LA_PORT_TLS") or 0)
    cert, key = os.environ.get("LA_CERT"), os.environ.get("LA_KEY")
    if tls_port and cert and key and os.path.isfile(cert) and os.path.isfile(key):
        try:
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.load_cert_chain(cert, key)
            tsrv = ThreadingHTTPServer((srv.server_address[0], tls_port), Handler)
            tsrv.socket = ctx.wrap_socket(tsrv.socket, server_side=True)
            threading.Thread(target=tsrv.serve_forever, daemon=True).start()
            sys.stderr.write("bridge: tls on %s:%d\n" % (srv.server_address[0], tls_port))
        except Exception as e:
            sys.stderr.write("bridge: no tls (%s)\n" % e)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
