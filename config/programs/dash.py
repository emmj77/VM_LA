# french in code is forbidden
import json
import os
import re
import sqlite3
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import laconf
import model
CONF_DIR = laconf.CONFD
ROOT = laconf.ROOT
CONF = laconf.CONF




TABLE = os.environ.get("LA_CONFIG", os.path.join(CONF_DIR, "la_tools.yaml"))
ENGINE = os.path.join(CONF_DIR, "engine", "engine.sh")
SWITCH = os.path.join(CONF_DIR, "engine", "engine_switch.sh")
SH = os.environ.get("LA_SH") or "/bin/dash"
WEB = os.path.join(CONF_DIR, "dashboard")
W = laconf.state_dir()


def _lines():
    try:
        with open(CONF, "r", encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except OSError:
        return []


def _section_bounds(lines, section):
    start = None
    for i, ln in enumerate(lines):
        if ln.rstrip() == section + ":" or re.match(r"^" + re.escape(section) + r":\s*(#.*)?$", ln):
            start = i + 1
            continue
        if start is not None:
            if ln and not ln[0].isspace() and not ln.lstrip().startswith("#"):
                return start, i
    return (start, len(lines)) if start is not None else (None, None)






BRICK_UPDATE = os.path.join(ROOT, "config", "engine", "update.sh")


def update_version():
    return model.git_state()["describe"] or "?"


def update_state():
    try:
        r = subprocess.run(["sh", BRICK_UPDATE, "--json"], capture_output=True, text=True, timeout=90)
    except (OSError, subprocess.SubprocessError) as e:
        return {"error": str(e)}
    for raw_line in reversed((r.stdout or "").strip().splitlines()):
        try:
            return json.loads(raw_line)
        except ValueError:
            continue
    return {"error": (r.stderr or "aucune sortie").strip()[:300]}


def launch_update():
    log = os.path.join(W, "update.log")
    try:
        with open(log, "ab") as f:
            subprocess.Popen(["sh", BRICK_UPDATE], stdout=f, stderr=f, start_new_session=True)
    except OSError as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "log": log}



def tool_id(name):
    for r in laconf.table():
        if r.get("tool") == name:
            return r.get("id")
    return None


def run_tool(name, *args, stdin_data=None):
    tid = tool_id(name)
    if not tid:
        return False, "la table ne porte pas %s" % name
    env = dict(os.environ, LA_ROOT=ROOT, LA_CONF=CONF, LA_CONFIG=TABLE)
    try:
        p = subprocess.run([SH, ENGINE, tid, *args], input=(stdin_data or ""), env=env,
                           capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, "le tool %s n a pas repondu (%s)" % (name, e)
    try:
        d = json.loads(p.stdout or "{}")
    except ValueError:
        return p.returncode == 0, (p.stdout or p.stderr or "").strip()[:400]
    ok = d.get("status") == "ok"
    return ok, (d.get("result") or d.get("line") or p.stderr or "").strip()


def engines():
    try:
        p = subprocess.run([SH, SWITCH, "list"], capture_output=True, text=True, timeout=20)
        data = json.loads(p.stdout or "[]")
        return data if isinstance(data, list) else []
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []


def tts_wav(text):
    port = int(laconf.num("tts", "port", 8090))
    body = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:%d/say" % port, data=body,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=180) as r:
        line = r.read().decode("utf-8", "replace")
    m = re.search(r"speech\s*:\s*(\S+\.wav)", line or "")
    if not m:
        raise RuntimeError((line or "la voix n a rien rendu").strip())
    p = m.group(1)
    if not os.path.isabs(p):
        p = os.path.join(ROOT, p)
    with open(p, "rb") as f:
        return p, f.read()


def agents():
    names = (laconf.text("agents", "names", "agent_one human voice") or "").split()
    run_tpl = laconf.text("agents", "run", "config/%s.run") or "config/%s.run"
    main = laconf.text("agents", "main", "agent_one")
    out = []
    for n in names:
        f = run_tpl % n
        f = f if os.path.isabs(f) else os.path.join(ROOT, f)
        pid, ts, task, status = None, "", "", "idle"
        try:
            with open(f, "r", encoding="utf-8", errors="replace") as h:
                parts = (h.readline() or "").split(" ", 2)
            pid = int(parts[0])
            ts = parts[1] if len(parts) > 1 else ""
            task = parts[2].strip() if len(parts) > 2 else ""
            alive = False
            if pid:
                try:
                    os.kill(pid, 0)
                    alive = True
                except OSError:
                    alive = False
            status = "active" if alive else "ended"
        except (OSError, ValueError):
            pass
        out.append({"name": n, "pid": pid, "since": ts, "task": task,
                    "status": status, "main": n == main})
    return out


def board():
    f = laconf.path("chat", "config/agent_chat.jsonl")
    msgs = []
    try:
        with open(f, "r", encoding="utf-8", errors="replace") as h:
            for ln in h:
                ln = ln.strip()
                if not ln:
                    continue
                try:
                    d = json.loads(ln)
                except ValueError:
                    continue
                if isinstance(d, dict) and d.get("body"):
                    msgs.append(d)
    except OSError:
        pass
    return msgs[-40:]


def turn_state():
    mark = os.path.join(W, "turn.pid")
    try:
        with open(mark, "r", encoding="utf-8") as h:
            pid = int((h.read() or "0").strip() or 0)
    except (OSError, ValueError):
        return {"running": False, "pid": None}
    try:
        os.kill(pid, 0)
        return {"running": True, "pid": pid}
    except OSError:
        return {"running": False, "pid": None}


def jsonl(path):
    out = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as h:
            for ln in h:
                ln = ln.strip()
                if not ln:
                    continue
                try:
                    out.append(json.loads(ln))
                except ValueError:
                    out.append({"raw": ln})
    except OSError:
        pass
    return out


def doctor():
    d = model.doctor("short")
    return {"rc": d["rc"], "text": (d["raw"] or "").strip()[-800:]}


def state():
    eng = engines()
    cur = next((e for e in eng if e.get("active")), None)
    tk = model.tokens()
    sess, tok_sess, tok_last = tk["session"], tk["session_tokens"], tk["last_turn"]
    skill = (open(os.path.join(ROOT, "skills", ".active")).read().strip()
             if os.path.exists(os.path.join(ROOT, "skills", ".active")) else "")
    proj = (open(os.path.join(ROOT, "projects", ".active")).read().strip()
            if os.path.exists(os.path.join(ROOT, "projects", ".active")) else "")
    return {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": {"alias": (cur or {}).get("alias"), "provider": (cur or {}).get("provider"),
                  "model": (cur or {}).get("model")},
        "engines": eng,
        "tokens": {"session": sess, "session_tokens": tok_sess, "last_turn": tok_last,
                   "calls": tk["calls"]},
        "agents": agents(),
        "names": {"main": laconf.text("agents", "main", "agent_one"),
                  "user": laconf.text("agents", "name_human", "user"),
                  "voice": laconf.text("agents", "name_voice", "voice"),
                  "list": (laconf.text("agents", "names", "") or "").split()},
        "turn": turn_state(),
        "skill": skill or None,
        "project": proj or None,
        "board": len(board()),
        "head": head_stamp(),
        "poll_ms": laconf.num("dashboard", "poll_ms", 1500),
        "bridge": {"host": laconf.text("bridge", "host", "127.0.0.1"),
                   "port": laconf.num("bridge", "port", 8765)},
    }


def projects_list():
    d = os.path.join(ROOT, "projects")
    active_path = ""
    try:
        with open(os.path.join(d, ".active"), "r", encoding="utf-8") as h:
            active_path = h.read().strip()
    except OSError:
        pass
    out = []
    for n in sorted(os.listdir(d)):
        f = os.path.join(d, n, "project.yml")
        if os.path.isfile(f):
            out.append({"name": n, "active": n == active_path, "path": os.path.relpath(f, ROOT)})
    return out


def idmap():
    return {r["id"]: r["tool"] for r in laconf.table() if r.get("tool")}


def _speech_of(tool_calls, content):
    said = []
    try:
        calls = json.loads(tool_calls) if tool_calls else []
    except ValueError:
        calls = []
    names = idmap()
    for c in calls if isinstance(calls, list) else []:
        fn = (c or {}).get("function") or {}
        nm = fn.get("name") or ""
        args = fn.get("arguments") or ""
        try:
            a = json.loads(args) if isinstance(args, str) else (args or {})
        except ValueError:
            a = {}
        real, text, mode = nm, "", ""
        if nm == "la" and isinstance(a, dict):
            real = names.get(str(a.get("g")), "la")
            argv = a.get("a") or []
            if isinstance(argv, list) and argv:
                mode = str(argv[0])
                strs = [str(x) for x in argv[1:] if isinstance(x, str) and x.strip()]
                text = strs[-1] if strs else ""
        if real in ("reply", "talk"):
            said.append({"tool": real, "mode": mode, "text": text})
        else:
            brief = ""
            path = ""
            if isinstance(a, dict):
                argv = a.get("a")
                if isinstance(argv, list):
                    brief = " ".join(str(x) for x in argv[1:4] if isinstance(x, (str, int)) and str(x) != "")
                    path = str(argv[0]) if argv and isinstance(argv[0], (str, int)) else ""
                else:
                    brief = str(a.get("path") or a.get("query") or a.get("name") or "")[:80]
                    path = brief
            said.append({"tool": real, "text": brief, "path": path})
    if not said and (content or "").strip():
        said.append({"tool": "", "text": content.strip()})
    return said


def _epoch(ts):
    if ts is None:
        return 0.0
    if isinstance(ts, (int, float)):
        return float(ts)
    s = str(ts).strip()
    if s.isdigit():
        return float(s)
    try:
        import datetime as _d
        return _d.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0.0


def recent_think(maxsec=86400):
    import time as _t
    out = []
    now = _t.time()
    try:
        with open(os.path.join(W, "reasoning.jsonl"), "r", encoding="utf-8") as h:
            for ln in h:
                try:
                    o = json.loads(ln)
                except ValueError:
                    continue
                txt = (o.get("text") or "").strip()
                if o.get("exchange") is None or not txt:
                    continue
                ep = _epoch(o.get("ts"))
                if ep and (now - ep) > maxsec:
                    continue
                out.append({"exchange": int(o["exchange"]), "ts": o.get("ts") or "", "text": txt})
    except OSError:
        return out
    return out


def history(turns=12):
    start = 0
    sf = laconf.path("session_start", "config/session.start")
    try:
        with open(sf, "r", encoding="utf-8") as h:
            start = int((h.readline() or "0").strip() or 0)
    except (OSError, ValueError):
        start = 0
    try:
        cx = sqlite3.connect("file:%s?mode=ro" % laconf.path("sessions", ""), uri=True, timeout=5)
        cx.row_factory = sqlite3.Row
        ex = [r[0] for r in cx.execute(
            "SELECT DISTINCT exchange FROM messages WHERE id > ? ORDER BY exchange DESC LIMIT ?",
            (start, int(turns)))]
        if not ex:
            return {"session_start": start, "turns": []}
        q = ("SELECT id, exchange, ts, role, content, tool_calls, name, reasoning FROM messages "
             "WHERE exchange >= ? AND id > ? ORDER BY id")
        rows = [dict(r) for r in cx.execute(q, (min(ex), start))]
        cx.close()
    except sqlite3.Error as e:
        return {"session_start": start, "turns": [], "error": str(e)}
    per = {}
    usg = {}
    for u in model.usage():
        usg[int(u.get("session") or 0)] = usg.get(int(u.get("session") or 0), 0) + int(u.get("tokens") or 0)
    for r in rows:
        e = r["exchange"]
        t = per.setdefault(e, {"exchange": e, "ts": r["ts"], "demand": "", "speech": [],
                               "think": [], "tools": [], "tool_calls": [], "refused": [], "steps": [],
                               "tokens": usg.get(e, 0)})
        if r["role"] == "user":
            t["demand"] = (r["content"] or "").strip()
        elif r["role"] == "system":
            t["refused"].append((r["content"] or "").strip()[:300])
        elif r["role"] == "assistant":
            if (r["reasoning"] or "").strip():
                txt = r["reasoning"].strip()
                t["think"].append(txt)
                t["steps"].append({"ts": r["ts"], "kind": "think", "text": txt})
            for s in _speech_of(r["tool_calls"], r["content"]):
                if s["tool"] in ("reply", "talk"):
                    txt = (s["text"] or "").strip()
                    if txt and txt not in t["speech"]:
                        t["speech"].append(txt)
                        t["steps"].append({"ts": r["ts"], "kind": "say", "text": txt})
                elif s["tool"]:
                    if s["tool"] not in t["tools"]:
                        t["tools"].append(s["tool"])
                    t["tool_calls"].append({"name": s["tool"], "path": (s.get("path") or "").strip()})
                    t["steps"].append({"ts": r["ts"], "kind": "tool", "name": s["tool"],
                                       "path": (s.get("path") or "").strip()})
        elif r["role"] == "tool":
            pass
    for x in recent_think():
        t = per.get(x["exchange"])
        if not t:
            continue
        if x["text"] not in t["think"]:
            t["think"].append(x["text"])
        pas = t["steps"]
        i = len(pas)
        for j, y in enumerate(pas):
            if y["ts"] and y["ts"] >= x["ts"]:
                i = j
                break
        pas.insert(i, {"ts": x["ts"], "kind": "think", "text": x["text"]})
    return {"session_start": start, "turns": [per[k] for k in sorted(per)]}


def speak_stream():
    f = os.path.join(laconf.state_dir().rstrip("/"), "reply.stream")
    turn_no, chunks, last = 0, [], ""
    try:
        with open(f, encoding="utf-8", errors="replace") as fh:
            for raw_line in fh:
                try:
                    o = json.loads(raw_line)
                except ValueError:
                    continue
                turn_no = o.get("turn") or turn_no
                last = o.get("ts") or last
                if o.get("kind") == "reply" and o.get("text"):
                    chunks = [o["text"]]
    except OSError:
        return {"turn": 0, "ts": "", "text": ""}
    return {"turn": turn_no, "ts": last, "text": "".join(chunks)}


def live():
    return {
        "turn": turn_state(),
        "thinking": jsonl(os.path.join(W, "thinking.jsonl"))[-40:],
        "journal": jsonl(os.path.join(W, "journal.jsonl"))[-60:],
        "spoken": jsonl(os.path.join(W, "spoken.jsonl"))[-20:],
        "say_queue": jsonl(os.path.join(W, "say.queue"))[:20],
        "reply": speak_stream(),
    }




def head_file():
    return laconf.path("head_file", "config/second.head")


def head_stamp():
    f = head_file()
    try:
        st = os.stat(f)
    except OSError:
        return {"file": f, "present": False, "mtime": 0, "bytes": 0, "written": None, "age_s": None}
    return {"file": f, "present": True, "mtime": st.st_mtime_ns, "bytes": st.st_size,
            "written": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(st.st_mtime)),
            "age_s": int(time.time() - st.st_mtime)}


def head_snapshot():
    f = head_file()
    try:
        st = os.stat(f)
    except OSError:
        return {"file": f, "present": False, "sections": [], "raw_bytes": 0, "written": None,
                "why": "aucun head depose : la boucle n ecrit pas encore %s" % f}
    return {"file": f, "present": True, "sections": laconf.head(f), "raw_bytes": st.st_size,
            "written": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(st.st_mtime)),
            "age_s": int(time.time() - st.st_mtime), "why": ""}


SKILL_SECTIONS = {
    "SUMMARY": {"lo": 100, "hi": 199, "max": 100},
    "TOOLS": {"lo": 200, "hi": 299, "max": 100},
    "DOCS": {"lo": 300, "hi": 399, "max": 100},
    "PLAN": {"lo": 400, "hi": 419, "max": 20},
    "ERROR": {"lo": 600, "hi": 699, "max": 100},
}
SKILL_PLAIN = {"RULES": {"max": 40}, "PERIMETER": {"max": 10}}

def parse_sections(lines):
    out = {}
    cur = None
    for i, ln in enumerate(lines):
        if not ln or ln[0].isspace() or ln.lstrip().startswith("#"):
            if cur and re.match(r"^\s+", ln) and not ln.lstrip().startswith("#"):
                m = re.match(r"^\s+([A-Za-z0-9_]+):\s*(.*)$", ln)
                if m:
                    out[cur].append((i, m.group(1), m.group(2)))
            continue
        m = re.match(r"^([A-Za-z_]+):\s*(#.*)?$", ln)
        cur = m.group(1) if m else None
        if cur:
            out.setdefault(cur, [])
    return out


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except OSError:
        return None


def lines_bytes(t):
    return len(t.encode("utf-8"))


def skill_path(name):
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,60}", name or ""):
        return None
    p = os.path.join(ROOT, "skills", name, "skill.yaml")
    return p if os.path.isfile(p) else None


def skills_list():
    d = os.path.join(ROOT, "skills")
    is_active = ""
    try:
        with open(os.path.join(d, ".active"), "r", encoding="utf-8") as h:
            is_active = h.read().strip()
    except OSError:
        pass
    out = []
    try:
        for n in sorted(os.listdir(d)):
            p = skill_path(n)
            if not p:
                continue
            lines = read_text(p) or []
            secs = parse_sections(lines)
            tools = len(secs.get("TOOLS", []))
            plan_text = len(secs.get("PLAN", []))
            bad = sum(1 for ln in lines if lines_bytes(ln) > 100 and ln.strip() and not ln.lstrip().startswith("#"))
            out.append({"name": n, "active": n == is_active, "tools": tools, "plan": plan_text,
                        "long_lines": bad, "lines": len(lines),
                        "sections": sorted([k for k in secs if secs[k] is not None])})
    except OSError:
        pass
    return out


def skill_detail(name):
    p = skill_path(name)
    if not p:
        return None
    lines = read_text(p) or []
    secs = parse_sections(lines)
    data = {"name": name, "path": os.path.relpath(p, ROOT), "raw_lines": len(lines),
            "sections": {}, "rules": {}}
    for s, meta in SKILL_SECTIONS.items():
        rows = []
        for (i, k, v) in secs.get(s, []):
            txt = v.strip()
            if len(txt) >= 2 and txt[0] == '"' and txt[-1] == '"':
                txt = txt[1:-1]
            rows.append({"id": k, "text": txt, "bytes": lines_bytes(txt)})
        data["sections"][s] = {"rows": rows, "max": meta["max"], "range": [meta["lo"], meta["hi"]]}
    for s in ("RULES", "PERIMETER"):
        rows = []
        for (i, k, v) in secs.get(s, []):
            t = v.strip()
            if len(t) >= 2 and t[0] == '"' and t[-1] == '"':
                t = t[1:-1]
            rows.append({"id": k, "text": t})
        data["sections"][s] = {"rows": rows, "max": SKILL_PLAIN[s]["max"], "range": None}
    data["tools_known"] = tool_names()
    return data


def tool_names():
    return sorted(r["tool"] for r in laconf.table() if r.get("tool"))


def _section_span(lines, section, spec=False):
    if spec:
        head = re.compile(r"^SECTION\s*:\s*" + re.escape(section) + r"\s*$")
        nxt = re.compile(r"^SECTION\s*:")
    else:
        head = re.compile(r"^" + re.escape(section) + r":\s*(#.*)?$")
        nxt = re.compile(r"^[A-Za-z_]+\s*:")
    start = None
    for i, ln in enumerate(lines):
        if head.match(ln):
            start = i
            break
    if start is None:
        return None, None
    for j in range(start + 1, len(lines)):
        if nxt.match(lines[j]):
            return start, j
    return start, len(lines)


def set_section_lines(path, section, rows, meta=None, spec=False):
    lines = read_text(path)
    if lines is None:
        return False, "le fichier est illisible"
    a, b = _section_span(lines, section, spec)
    if a is None:
        return False, "la section %s n existe pas dans ce fichier" % section
    meta = meta or {}
    raw = section == "RULES"
    keys_are_ids = spec or section not in ("RULES", "PERIMETER")
    cap = meta.get("max") or (100 if spec else 0)
    keep = [r for r in rows if (r.get("text") or "").strip()]
    if cap and len(keep) > cap:
        return False, "%s : %d lignes pour un plafond de %d" % (section, len(keep), cap)
    seen = set()
    for r in keep:
        rid = str(r.get("id") or "").strip()
        txt = (r.get("text") or "").strip()
        if keys_are_ids and not re.fullmatch(r"\d+", rid):
            return False, "id non numerique : %r" % rid
        if not keys_are_ids and not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,40}", rid):
            return False, "cle off-form : %r" % rid
        if rid in seen:
            return False, "id en double : %s" % rid
        seen.add(rid)
        lo, hi = meta.get("lo"), meta.get("hi")
        if keys_are_ids and lo is not None and hi is not None:
            if not (lo <= int(rid) <= hi):
                return False, "l id %s sort de la centaine %d-%d" % (rid, lo, hi)
        if lines_bytes(txt) > 100:
            return False, "la ligne %s fait %d octets (100 au plus)" % (rid, lines_bytes(txt))
        if raw:
            if not re.fullmatch(r"[A-Za-z0-9_.:/ -]{1,100}", txt):
                return False, "la ligne %s porte des signes refuses dans RULES" % rid
        elif '"' in txt or "\n" in txt:
            return False, "la ligne %s porte un guillemet ou un retour a la ligne" % rid
    idx = {}
    for i in range(a + 1, b):
        m = re.match(r"^\s+([A-Za-z0-9_]+):", lines[i])
        if m:
            idx[m.group(1)] = i
    out = list(lines)
    last = max(idx.values()) if idx else _section_last(out, a, b)
    for r in rows:
        rid = str(r.get("id") or "").strip()
        txt = (r.get("text") or "").strip()
        new = None if not txt else ("  %s: %s" % (rid, txt) if raw else '  %s: "%s"' % (rid, txt))
        if rid in idx:
            out[idx[rid]] = new
            last = max(last, idx[rid])
        elif new is not None:
            last += 1
            out.insert(last, new)
            idx[rid] = last
    out = [l for l in out if l is not None]
    err = laconf.write_atomic(path, out)
    if err:
        return False, "l ecriture a echoue (%s)" % err
    return True, "ecrit (%d ligne(s))" % len(rows)


def _section_last(lines, a, b):
    j = b - 1
    while j > a and not lines[j].strip():
        j -= 1
    return j




def command(line):
    parts = (line or "").strip().split(None, 1)
    cmd = (parts[0] or "").lower()
    arg = (parts[1] if len(parts) > 1 else "").strip()
    if cmd == "/stop":
        ok, txt = stop_word()
        return {"kind": "note", "ok": ok, "text": txt}
    if cmd == "/model":
        al = [e.get("alias") for e in engines()]
        if not arg:
            return {"kind": "note", "ok": True, "text": "alias : " + " ".join(
                ["%s(%s)" % (e.get("alias"), e.get("model")) for e in engines()])}
        if arg not in al:
            return {"kind": "note", "ok": False, "text": "alias inconnu : %s ; les alias sont : %s" % (arg, " ".join(al))}
        ok, line = engine_take(arg)
        return {"kind": "note", "ok": ok, "text": line, "model": arg}
    if cmd == "/skill":
        if not arg:
            return {"kind": "note", "ok": True, "text": "skills : " + " ".join(s["name"] for s in skills_list())}
        if not skill_path(arg):
            return {"kind": "note", "ok": False, "text": "skill inconnue : %s" % arg}
        ok, t = run_tool("load_skill", arg, stdin_data=arg)
        return {"kind": "note", "ok": ok, "text": t, "skill": arg if ok else None}
    if cmd == "/project":
        project_names = [x["name"] for x in projects_list()]
        if not arg:
            return {"kind": "note", "ok": True, "text": "projets : " + " ".join(project_names)}
        if arg not in project_names:
            return {"kind": "note", "ok": False, "text": "projet inconnu : %s ; les projets sont : %s" % (arg, " ".join(project_names))}
        ok, t = run_tool("load_project", arg, stdin_data=arg)
        return {"kind": "note", "ok": ok, "text": t, "project": arg if ok else None}
    if cmd == "/ps":
        return {"kind": "note", "ok": True, "text": "les unites de LA et les jetons",
                "ps": {u: v.get("state", "?") for u, v in model.units(laconf.get("dashboard", "units", [])).items() if "." in u},
                "tokens": model.tokens()}
    if cmd == "/agents":
        ags = agents()
        return {"kind": "note", "ok": True, "text": "%d agent(s)" % len(ags), "agents": ags}
    if cmd == "/head":
        hs = head_snapshot()
        return {"kind": "note", "ok": hs["present"], "text": "le head secondaire : %d section(s)" % len(hs["sections"]),
                "head": hs["sections"]}
    if cmd == "/plan":
        return {"kind": "note", "ok": True, "text": plan_text()}
    if cmd == "/engine":
        if not arg:
            return {"kind": "note", "ok": True, "text": "les adresses declarees", "engines": engines()}
        ok, line = engine_take(arg)
        return {"kind": "note", "ok": ok, "text": line}
    if cmd == "/update":
        if arg == "apply":
            return dict(launch_update(), ok=True, kind="note")
        u = update_state()
        return {"kind": "note", "ok": True, "update": u,
                "text": "%s · retard %s · %s" % (u.get("version") or "?", u.get("behind"), "sale" if u.get("dirty") else "propre")}
    if cmd == "/doctor":
        d = doctor()
        return {"kind": "doctor", "ok": d["rc"] == 0, "text": d["text"], "rc": d["rc"]}
    if cmd == "/new":
        r = model.query("SELECT COALESCE(MAX(id),0) AS id FROM messages")
        sid = int(r[0]["id"]) if r else 0
        sf = laconf.path("session_start", "config/session.start")
        try:
            with open(sf, "w", encoding="utf-8") as h:
                h.write("%d\n" % sid)
        except OSError as e:
            return {"kind": "note", "ok": False, "text": "la borne de session n a pas pu etre ecrite (%s)" % e}
        return {"kind": "boundary", "ok": True,
                "text": "nouvelle session : la fenetre part apres le message %d" % sid}
    if cmd == "/to":
        who, _, txt = arg.partition(" ")
        if not who or not txt.strip():
            return {"kind": "note", "ok": False, "text": "usage : /to <agent> <message>"}
        ok, t = run_tool("send_agent_chat", who, stdin_data=txt.strip())
        return {"kind": "agent", "ok": ok, "text": t, "to": who}
    if cmd == "/tools":
        rows = [r for r in laconf.table() if not arg or arg.lower() in (r.get("tool") or "").lower()]
        return {"kind": "note", "ok": True,
                "text": "%d tools dans la table ; %d pour « %s »" % (len(laconf.table()), len(rows), arg),
                "tools": rows[:20]}
    if cmd == "/delegate":
        if not arg:
            return {"kind": "note", "ok": False, "text": "usage : /delegate <ce que je dois deleguer>"}
        brief = ("Delegue cette demande au sous-agent le plus adapte parmi ceux disponibles : choisis TOI la cible "
               "via delegate_task, puis rends-moi la reponse de cet agent. Demande a deleguer : " + arg)
        d, _ = say(brief)
        rep = (d.get("response") or d.get("speech") or d.get("error") or "").strip()
        return {"kind": "reply", "ok": bool(ok) and bool(rep), "text": rep or "(pas de reponse de l agent)", "delegated": arg}
    if cmd in ("/help", "/?"):
        return {"kind": "help", "ok": True, "text":
                "/stop  /model <alias>  /skill <nom>  /doctor  /new  /to <agent> <message>  /tools <mot>"}
    return {"kind": "note", "ok": False, "text": "commande inconnue : %s (essaye /help)" % cmd}


def config_schema():
    return laconf.get("schema", "fields", [])


def engine_choices():
    return laconf.get("schema", "engine_choices", {})


def config_page():
    eng = engines()
    return {
        "schema": config_schema(),
        "values": {("%s.%s" % (s["section"], s["key"])): laconf.text(s["section"], s["key"], "")
                   for s in config_schema()},
        "engines": [{"alias": e.get("alias"), "provider": e.get("provider"),
                     "model": e.get("model"), "active": bool(e.get("active")),
                     "thinking": engine_config(e.get("alias"), "thinking", ""),
                     "reasoning_effort": engine_config(e.get("alias"), "reasoning_effort", ""),
                     "reasoning_field": engine_config(e.get("alias"), "reasoning_field", ""),
                     "stream": engine_config(e.get("alias"), "stream", "false"),
                     "reasoning_echo": engine_config(e.get("alias"), "reasoning_echo", "false"),
                     "tool_choice": engine_config(e.get("alias"), "tool_choice", "auto"),
                     "max_tokens": engine_config(e.get("alias"), "max_tokens", "4096")}
                    for e in eng],
        "engine_choices": engine_choices(),
    }


_ENGINE_CACHE = {"t": 0, "blocks": {}}


def _engine_blocks():
    if time.time() - _ENGINE_CACHE["t"] < 15 and _ENGINE_CACHE["blocks"]:
        return _ENGINE_CACHE["blocks"]
    lines = _lines()
    a, b = _section_bounds(lines, "engines")
    blocks, cur, start = {}, None, None
    if a is not None:
        for i in range(a, b):
            m = re.match(r"^\s+-\s+", lines[i])
            if m:
                if cur:
                    blocks[cur] = (start, i)
                cur, start = None, i
                continue
            m = re.match(r"^\s+alias:\s*\"?([a-z0-9_-]+)\"?", lines[i])
            if m and start is not None and cur is None:
                cur = m.group(1)
        if cur and start is not None:
            blocks[cur] = (start, b)
    _ENGINE_CACHE.update({"t": time.time(), "blocks": blocks})
    return blocks


def engine_config(alias, key, default):
    for e in laconf.raw().get("engines") or []:
        if isinstance(e, dict) and str(e.get("alias")) == str(alias):
            v = e.get(key)
            if v is None or v == "":
                return default
            return ("true" if v else "false") if isinstance(v, bool) else str(v)
    return default


def engine_set(alias, key, value):
    lines = _lines()
    blk = _engine_blocks().get(alias)
    if not blk:
        return False, "l engine %s n existe pas" % alias
    a, b = blk
    for i in range(a, b):
        m = re.match(r"^(\s+" + re.escape(key) + r":\s*)(\"[^\"]*\"|\S+)(\s+#.*$|$)", lines[i])
        if m:
            lines[i] = m.group(1) + value + (m.group(3) or "")
            break
    else:
        anchor = a
        for i in range(a, b):
            if re.match(r"^\s+active:", lines[i]):
                anchor = i
        lines.insert(anchor + 1, "    %s: %s" % (key, value))
    err = laconf.write_atomic(CONF, lines)
    if err:
        return False, "l ecriture a echoue (%s)" % err
    _ENGINE_CACHE["t"] = 0
    if engine_config(alias, key, "") != value.strip('"'):
        return False, "la valeur relue ne correspond pas"
    return True, "ecrit"


def config_write(payload):
    sec = payload.get("section")
    key = payload.get("key")
    val = payload.get("value")
    alias = payload.get("alias")
    if alias is not None and sec == "engines":
        ch = config_page()["engine_choices"]
        if key not in ch:
            return False, "la cle %s ne se regle pas ici" % key
        if str(val) not in ch[key]:
            return False, "%s n est pas dans la liste : %s" % (val, " ".join(ch[key]))
        return engine_set(alias, key, str(val))
    for s in config_schema():
        if s["section"] != sec or s["key"] != key:
            continue
        if s["kind"] == "choice":
            if val not in s["choices"]:
                return False, "%s n est pas dans la liste : %s" % (val, " ".join(s["choices"]))
            return laconf.set(sec, key, val)
        if s["kind"] == "order":
            parts = [p for p in str(val).split() if p]
            unknown = [p for p in parts if p not in s["choices"]]
            if unknown:
                return False, "sections inconnues : %s" % " ".join(unknown)
            if len(set(parts)) != len(parts):
                return False, "une section est nommee deux fois"
            return laconf.set(sec, key, " ".join(parts))
        if s["kind"] == "int":
            try:
                n = int(str(val).strip())
            except ValueError:
                return False, "%s n est pas un entier" % val
            if not (s["min"] <= n <= s["max"]):
                return False, "%s sort des bornes %d..%d" % (n, s["min"], s["max"])
            return laconf.set(sec, key, str(n))
        return False, "cette cle ne se regle pas ici"
    return False, "la cle %s.%s n est pas reglable" % (sec, key)


LOOP = os.environ.get("LA_LOOP") or laconf.path("loop", "config/engine/loop.sh")
PLAN_BRICK = laconf.path("plan_brick", "config/engine/plan.sh")
APPROVAL_BRICK = laconf.path("approval_brick", "config/engine/approval.sh")
STOP_FILE = laconf.path("stop", "config/state/stop")
SAY_QUEUE = laconf.path("say_queue", "config/state/say.queue")
WATCHER = laconf.path("watcher_brick", "config/engine/watcher.sh")
JUDGE_SECONDS = laconf.num("watcher", "judge_seconds", 8)
JOURNAL_FILE = laconf.path("journal", "config/state/journal.jsonl")
SPOKEN_FILE = laconf.path("spoken", "config/state/spoken.jsonl")
THINKING_FILE = laconf.path("thinking", "config/state/thinking.jsonl")
AUDIO_DIR = laconf.path("audio", "config/audio")
BRIDGE_LOG = laconf.path("bridge_log", "config/state/bridge.log")
CERT = laconf.path("bridge_cert", "config/certs/bridge-cert.pem")
KEY = laconf.path("bridge_key", "config/certs/bridge-key.pem")
SKILL_ACTIVE = laconf.path("skill_active", "skills/.active")
BADDR = os.environ.get("LA_BRIDGE_ADDRESS") or laconf.text("bridge", "host", "127.0.0.1")
BPORT = int(os.environ.get("LA_BRIDGE_PORT") or laconf.num("bridge", "port", 8765))
TLSPORT = int(os.environ.get("LA_BRIDGE_TLS_PORT") or laconf.num("bridge", "tls_port", 8766))
AUDIO_MAX = laconf.num("bridge", "audio_bytes", 16000000)
VOICE_BYTES = laconf.num("bridge", "voice_bytes", 600)
STT_TIMEOUT = laconf.num("bridge", "stt_timeout", 25)
LOG_CHARS = laconf.num("bridge", "log_chars", 120)
APK_FILE = os.environ.get("LA_APK") or laconf.text("bridge", "apk", "")
STATIC = {"/": ("widget", "text/html; charset=utf-8"),
          "/widget": ("widget", "text/html; charset=utf-8"),
          "/manifest.webmanifest": ("widget_manifest", "application/manifest+json"),
          "/icon.svg": ("widget_icon", "image/svg+xml"),
          "/sw.js": ("widget_sw", "text/javascript; charset=utf-8")}
HUMAN = {"install_program": "installer un programme", "uninstall_program": "désinstaller un programme",
         "download_file": "télécharger un fichier", "skill_manage": "modifier une compétence"}
TABLE_MANAGE = {"add_tool": "ajouter un outil au tableau", "delete_tool": "supprimer un outil du tableau",
                "install_tool": "installer un nouvel outil"}


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def blog(msg):
    try:
        with open(BRIDGE_LOG, "a", encoding="utf-8") as f:
            f.write("%s  %s\n" % (now(), msg))
    except OSError:
        pass


def ext_of(ct):
    for k, v in (("webm", "webm"), ("mp4", "m4a"), ("m4a", "m4a"), ("aac", "m4a"), ("ogg", "ogg"),
                 ("opus", "ogg"), ("wav", "wav"), ("png", "png"), ("webp", "webp"), ("jpeg", "jpg"),
                 ("jpg", "jpg")):
        if k in (ct or "").lower():
            return v
    return ""


def speak(word):
    tid = tool_id("speak")
    w = " ".join(str(word or "").split())[:600]
    if not tid or not w:
        return ""
    try:
        p = subprocess.run([SH, ENGINE, str(tid)], input=w, capture_output=True, text=True,
                           env=dict(os.environ, LA_APPROVED="1"), timeout=600)
    except (OSError, subprocess.SubprocessError):
        return ""
    m = re.search(r"speech\s*:\s*config/audio/(\S+)", p.stdout or "")
    if not m:
        return ""
    try:
        with open(SPOKEN_FILE, "a", encoding="utf-8") as f:
            f.write(m.group(1) + "\n")
    except OSError:
        pass
    blog("voice  said (%d o) -> %s" % (len(w.encode("utf-8")), m.group(1)))
    return m.group(1)


def sentence(text, limit):
    cut = text[:limit]
    if len(text) <= limit:
        return cut
    i = max(cut.rfind("."), cut.rfind("!"), cut.rfind("?"))
    return cut[:i + 1] if i > 60 else cut


def judge(event, detail):
    """Le watcher PROPOSE (wake ou sleep) ; il ne bloque jamais : muet = wake (loi 1569)."""
    try:
        p = subprocess.run([SH, WATCHER, event, detail[:400]], capture_output=True, text=True,
                           timeout=JUDGE_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        blog("judge %s -> unreachable, the event is served" % event)
        return "wake"
    word = (p.stdout or "").strip().split("\n")[-1].strip() if p.stdout else ""
    if word not in ("wake", "sleep"):
        blog("judge %s -> no verdict (%s), the event is served" % (event, (p.stderr or "").strip()[:160]))
        return "wake"
    blog("judge %s -> %s" % (event, word))
    return word


def turn(demand, voice=False, who=None):
    who = who or laconf.text("agents", "name_human", "human")
    if not re.match(r"^[a-z0-9_-]+$", who or ""):
        who = "human"
    for f in (JOURNAL_FILE, SPOKEN_FILE, THINKING_FILE):
        try:
            open(f, "w").close()
        except OSError:
            pass
    try:
        os.unlink(STOP_FILE)
    except OSError:
        pass
    env = dict(os.environ, LA_FROM=who, LA_LOG_FILE=JOURNAL_FILE, LA_STOP_FILE=STOP_FILE)
    if voice:
        env["LA_VOICE"] = "1"
    said, last, rc = [], "", 1
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as out:
        try:
            p = subprocess.Popen([SH, LOOP], stdin=subprocess.PIPE, stdout=out,
                                 stderr=subprocess.PIPE, text=True, env=env)
        except OSError as e:
            return {"response": "", "audio": "", "audios": [], "code": 70, "error": str(e)}
        try:
            p.stdin.write(demand.rstrip("\n") + "\n")
            p.stdin.close()
        except OSError:
            pass
        for line in p.stderr:
            blog(line.rstrip("\n"))
            t = line.strip()
            if not t or t.startswith(("loop:", "thinking:")) or re.match(r"^\d{4}-\d\d-\d\dT", t):
                continue
            if voice:
                n = speak(t)
                if n:
                    said.append(n)
                    last = t
        rc = p.wait()
        out.seek(0)
        reply = out.read()
    audio = said[-1] if said else ""
    if voice and reply:
        r = sentence(reply, VOICE_BYTES)
        if r and r != last:
            n = speak(r)
            if n:
                said.append(n)
                audio = n
    return {"response": reply, "audio": audio, "audios": said, "code": rc}


def say(demand):
    demand = (demand or "").strip()
    if not demand:
        return {"error": "empty demand"}, 400
    blog("say  %s" % " ".join(demand.split())[:LOG_CHARS])
    threading.Thread(target=judge, args=("say", demand), daemon=True).start()
    if turn_state()["running"]:
        try:
            with open(SAY_QUEUE, "a", encoding="utf-8") as f:
                f.write(json.dumps({"ts": now(), "text": demand}, ensure_ascii=False) + "\n")
        except OSError:
            return {"error": "the word could not be queued"}, 500
        blog("say  (tour en cours) depose dans la file")
        return {"response": "", "audio": "", "code": 0, "queued": True,
                "note": "un tour tourne : ton mot entre dans la file, le modele le lit a son prochain tour"}, 202
    return turn(demand), 200


def stop_word():
    try:
        with open(STOP_FILE, "w", encoding="utf-8") as f:
            f.write(now() + "\n")
    except OSError:
        return False, "the word could not be placed"
    return True, "word placed"


def plan_text():
    if not os.path.isfile(PLAN_BRICK):
        raise RuntimeError("la brique du plan est absente (%s)" % PLAN_BRICK)
    act = "la"
    try:
        with open(SKILL_ACTIVE, encoding="utf-8") as f:
            act = (f.readline() or "").strip() or "la"
    except OSError:
        pass
    p = subprocess.run([SH, PLAN_BRICK, "status"], capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, PLAN_FILE=os.path.join(os.path.dirname(SKILL_ACTIVE), act, "skill.yaml")))
    return p.stdout or ""


def engine_take(alias):
    try:
        p = subprocess.run([SH, SWITCH, "take", str(alias)], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)
    line = ((p.stdout or p.stderr) or "").strip()
    if p.returncode != 0:
        return False, line or "the address change failed"
    blog("address %s" % alias)
    return True, line


def approval_request():
    try:
        with open(os.path.join(W, "approve.request"), encoding="utf-8", errors="replace") as f:
            words = (f.readline() or "").split()
    except OSError:
        return []
    return words[:-1] if words and words[-1].isdigit() else words


def approval_pending():
    words = approval_request()
    if not words:
        return {"pending": False}
    tool, act = words[0], " ".join(words[1:])
    hum = (TABLE_MANAGE.get(act, "modifier le tableau") if tool == "table_manage"
           else HUMAN.get(tool) or ("%s %s" % (tool, act)).replace("_", " ").strip())
    try:
        age = int(time.time() - os.path.getmtime(os.path.join(W, "approve.request")))
    except OSError:
        age = 0
    return {"pending": True, "gesture": " ".join(words), "tool": tool, "action": act, "human": hum, "age": age,
            "phrase": "Jarvis demande une autorisation : %s. Dis « Valider » ou « Refuser »." % hum}


def approval_act(ok):
    words = approval_request()
    if ok and not words:
        return False, "aucune demande en attente"
    arg = [SH, APPROVAL_BRICK, "allow", words[0], words[1] if len(words) > 1 else ""] if ok else [SH, APPROVAL_BRICK, "deny"]
    try:
        p = subprocess.run(arg, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)
    return p.returncode == 0, " ".join((p.stdout or p.stderr or "").split())[:200]


def transcribe(raw):
    tmp = tempfile.mkdtemp()
    src, wav = os.path.join(tmp, "src." + (ext_of(raw[0]) or "wav")), os.path.join(tmp, "in.wav")
    try:
        with open(src, "wb") as f:
            f.write(raw[1])
    except OSError:
        return {"text": ""}
    r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-ac", "1", "-ar", "16000",
                        "-c:a", "pcm_s16le", wav], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.isfile(wav) or not os.path.getsize(wav):
        return {"error": "audio illisible", "text": ""}
    url = "http://%s:%d/v1/audio/transcriptions" % (laconf.text("asr", "host", "127.0.0.1"),
                                                    laconf.num("asr", "port", 8080))
    q = subprocess.run(["curl", "-s", "--max-time", str(STT_TIMEOUT), "-F", "file=@" + wav, url],
                       capture_output=True, text=True)
    try:
        return json.loads(q.stdout or "")
    except ValueError:
        return {"text": ""}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8", extra=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    def _raw(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        return self.rfile.read(n) if 0 < n <= AUDIO_MAX else b""

    def _dict(self, raw):
        try:
            d = json.loads(raw.decode("utf-8") or "{}")
        except (ValueError, UnicodeDecodeError):
            return {}
        return d if isinstance(d, dict) else {}


class Bridge(Handler):
    server_version = "LA-bridge/2"
    protocol_version = "HTTP/1.0"

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def _dispatch(self, method):
        p = urlparse(self.path).path
        blog("%s %s" % (method, self.path))
        raw = self._raw()
        try:
            self._route(method, p, raw)
        except Exception as e:
            self._json({"error": "%s: %s" % (type(e).__name__, e)}, 500)

    def _route(self, m, p, raw):
        close = {"Connection": "close", "Content-Disposition": ""}
        if p == "/ping":
            return self._json({"state": "alive", "address": BADDR, "port": BPORT,
                               "loop": os.path.basename(LOOP), "ts": now()})
        if p == "/stop":
            ok, txt = stop_word()
            return self._json({"state": txt, "file": STOP_FILE, "ts": now()} if ok else {"error": txt}, 200 if ok else 500)
        if p == "/plan":
            txt = plan_text()
            return self._json({"status": "ok", "plan": txt, "result": txt})
        if p in ("/journal", "/thinking"):
            return self._json(jsonl(JOURNAL_FILE if p == "/journal" else THINKING_FILE))
        if p == "/spoken":
            try:
                with open(SPOKEN_FILE, encoding="utf-8", errors="replace") as f:
                    return self._json([ln.strip() for ln in f if ln.strip()])
            except OSError:
                return self._json([])
        if p.startswith("/audio/"):
            n = os.path.basename(p[7:])
            f = os.path.join(AUDIO_DIR, n)
            if not n or n.startswith(".") or not os.path.isfile(f):
                return self._json({"error": "wav not found"}, 404)
            with open(f, "rb") as h:
                return self._send(200, h.read(), "audio/wav", close)
        if p in STATIC:
            f = laconf.path(STATIC[p][0], "")
            if not os.path.isfile(f):
                return self._json({"error": "the file is not there (%s)" % f}, 404)
            with open(f, "rb") as h:
                return self._send(200, h.read(), STATIC[p][1], close)
        if p in ("/apk", "/LA-app.apk"):
            if not APK_FILE or not os.path.isfile(APK_FILE):
                return self._json({"error": "the APK is not built on the station (%s)" % APK_FILE}, 404)
            with open(APK_FILE, "rb") as h:
                return self._send(200, h.read(), "application/vnd.android.package-archive",
                                  {"Connection": "close", "Content-Disposition": 'attachment; filename="LA-app.apk"'})
        if p == "/engine":
            if m != "POST":
                return self._json({"engines": engines()})
            alias = str(self._dict(raw).get("alias") or "")
            if not alias:
                return self._json({"error": "POST /engine expects a JSON body with an alias"}, 400)
            ok, line = engine_take(alias)
            return self._json({"line": line, "alias": alias} if ok else {"error": line}, 200 if ok else 500)
        if p == "/state":
            return self._json(state())
        if p == "/agents":
            return self._json(agents())
        if p == "/history":
            tr = (parse_qs(urlparse(self.path).query).get("turns") or ["20"])[0]
            return self._json(history(int(tr) if tr.isdigit() else 20))
        if p == "/toolmap":
            return self._json({"map": idmap()})
        if p == "/skills":
            return self._json({"skills": skills_list()})
        if p == "/projects":
            return self._json({"projects": projects_list()})
        if p in ("/command", "/cmd"):
            line = str(self._dict(raw).get("line") or "").strip()
            if m != "POST" or not line:
                return self._json({"ok": False, "error": "POST with a line expected for /command"}, 405)
            return self._json(command(line))
        if p == "/say":
            if m != "POST":
                return self._json({"error": "POST expected for /say"}, 405)
            text = self._dict(raw).get("text")
            if text is None:
                text = raw.decode("utf-8", "replace")
            d, code = say(text)
            return self._json(d, code)
        if p in ("/voice", "/image"):
            if m != "POST":
                return self._json({"error": "POST expected for %s" % p}, 405)
            if not raw:
                return self._json({"error": "no audio or image in the body"}, 400)
            if p == "/voice":
                ext = ext_of(self.headers.get("Content-Type"))
                if not ext:
                    return self._json({"error": "unknown audio type ; wav, webm, mp4 or ogg"}, 415)
                name = "voice-%s-%d.%s" % (time.strftime("%Y%m%d-%H%M%S", time.gmtime()), os.getpid(), ext)
                tool, voice = "transcribe", True
            else:
                ext = ext_of(self.headers.get("Content-Type"))
                ext = ext if ext in ("png", "jpg", "webp") else "jpg"
                name = "image-%s-%d.%s" % (time.strftime("%Y%m%d-%H%M%S", time.gmtime()), os.getpid(), ext)
                tool, voice = "fast_analyze_img", False
            with open(os.path.join(AUDIO_DIR if voice else W, name), "wb") as f:
                f.write(raw)
            ok, seen = run_tool(tool, name)
            if not ok or not seen.strip():
                return self._json({"error": seen or "the %s returned nothing" % tool,
                                   "audio" if voice else "image": name}, 500)
            blog("%s %s -> %s" % (tool, name, " ".join(seen.split())[:LOG_CHARS]))
            if voice:
                demand = seen.strip()
                threading.Thread(target=judge, args=("voice", demand), daemon=True).start()
                d = turn(demand, voice=True, who=laconf.text("agents", "name_voice", "voice"))
                d["request"] = demand
            else:
                threading.Thread(target=judge, args=("image", seen.strip()), daemon=True).start()
                demand = ("Je viens de te donner une photo a voir, celle que je viens de prendre. Ce que la vision "
                          "en dit : %s\nReponds a ce que j en attends : dis-moi ce que cette image montre, et ce "
                          "qu il y a d utile a en retenir." % seen.strip())
                d = turn(demand)
                d["request"], d["image"] = demand, name
            return self._json(d)
        if p == "/transcribe":
            if m != "POST" or not raw:
                return self._json({"error": "POST with audio expected for /transcribe"}, 405)
            return self._json(transcribe((self.headers.get("Content-Type"), raw)))
        if p == "/tts":
            txt = str(self._dict(raw).get("text") or "").strip()
            if m != "POST" or not txt:
                return self._json({"error": "POST with a text expected for /tts"}, 400)
            path, _ = tts_wav(txt)
            return self._json({"audio": os.path.basename(path), "text": txt})
        if p == "/approval":
            return self._json(approval_pending())
        if p in ("/approve", "/deny"):
            if m != "POST":
                return self._json({"ok": False, "error": "POST expected for %s" % p}, 405)
            ok, txt = approval_act(p == "/approve")
            return self._json({"ok": ok, "text": txt}, 200 if ok else 400)
        return self._json({"error": "unknown route", "path": p}, 404)


def bridge_doors():
    try:
        srv = ThreadingHTTPServer((BADDR, BPORT), Bridge)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        blog("start  %s:%d" % (BADDR, BPORT))
    except OSError as e:
        sys.stderr.write("dash: la porte claire %s:%d ne s ouvre pas (%s)\n" % (BADDR, BPORT, e))
    if not (os.path.isfile(CERT) and os.path.isfile(KEY)):
        sys.stderr.write("dash: certificat absent (%s) : la porte chiffree reste fermee\n" % CERT)
        return
    try:
        addr = laconf.text("bridge", "tls_host", "") or subprocess.run(
            ["tailscale", "ip", "-4"], capture_output=True, text=True, timeout=10).stdout.split()[0]
    except (OSError, subprocess.SubprocessError, IndexError):
        addr = ""
    if not addr:
        sys.stderr.write("dash: pas d adresse chiffree (tailnet eteint) : la porte reste fermee\n")
        return
    for _ in range(max(1, laconf.num("bridge", "tls_wait", 30))):
        if re.search(r" %s/" % re.escape(addr), subprocess.run(
                ["ip", "-4", "-o", "addr"], capture_output=True, text=True).stdout or ""):
            break
        time.sleep(1)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    try:
        srv = ThreadingHTTPServer((addr, TLSPORT), Bridge)
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        blog("start-tls %s:%d" % (addr, TLSPORT))
    except OSError as e:
        sys.stderr.write("dash: la porte chiffree %s:%d ne s ouvre pas (%s)\n" % (addr, TLSPORT, e))


class H(Handler):
    server_version = "LA-dash/1"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *a):
        sys.stderr.write("%s  dash  %s\n" % (time.strftime("%H:%M:%S"), fmt % a))

    def _bytes(self, data, ctype="application/octet-stream", code=200):
        self._send(code, data, ctype)

    def _body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if n <= 0:
            return {}
        raw = self.rfile.read(n)
        try:
            return json.loads(raw.decode("utf-8") or "{}")
        except ValueError:
            return {"_raw": raw.decode("utf-8", "replace")}

    def _file(self, name, ctype):
        p = os.path.realpath(os.path.join(WEB, name))
        if not p.startswith(os.path.realpath(WEB)) or not os.path.isfile(p):
            return self._json({"error": "not found", "file": name}, 404)
        with open(p, "rb") as f:
            data = f.read()
        self._send(200, data, ctype)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        p = u.path
        if p == "/health":
            return self._json({"ok": True, "service": "la-dash"})
        if p in ("/", "/index.html"):
            return self._file("index.html", "text/html; charset=utf-8")
        if p == "/dash.js":
            return self._file("dash.js", "application/javascript; charset=utf-8")
        if p == "/dash.css":
            return self._file("dash.css", "text/css; charset=utf-8")
        if p == "/api/state":
            return self._json(state())
        if p == "/api/live":
            return self._json(live())
        if p == "/api/head":
            return self._json(head_snapshot())
        if p == "/api/history":
            return self._json(history(int((q.get("turns") or ["12"])[0] or 12)))
        if p == "/api/agents":
            return self._json({"agents": agents(), "board": board()})
        if p == "/api/toolmap":
            return self._json({"map": idmap()})
        if p == "/api/skills":
            return self._json({"skills": skills_list()})
        if p.startswith("/api/skill/"):
            d = skill_detail(p.rsplit("/", 1)[-1])
            return self._json(d or {"error": "skill inconnue"}, 200 if d else 404)
        if p == "/api/projects":
            return self._json({"projects": projects_list()})
        if p == "/api/config":
            return self._json(config_page())
        if p == "/api/plan":
            return self._json({"status": "ok", "plan": plan_text()})
        if p == "/api/version":
            return self._json({"version": update_version()})
        if p == "/api/update/check":
            return self._json(update_state())
        return self._json({"error": "no such route", "path": p}, 404)

    def do_POST(self):
        u = urlparse(self.path)
        p = u.path
        b = self._body()
        if p == "/api/say":
            text = (b.get("text") or "").strip()
            if not text:
                return self._json({"ok": False, "error": "demande vide"}, 400)
            d, code = say(text)
            return self._json({"ok": code == 200, "bridge": d}, 200 if code == 200 else 502)
        if p == "/api/tts":
            text = (b.get("text") or "").strip()
            if not text:
                return self._json({"ok": False, "error": "rien à dire"}, 400)
            if len(text) > 4000:
                text = text[:4000]
            try:
                path, data = tts_wav(text)
            except Exception as e:
                return self._json({"ok": False, "error": "la voix n'a pas répondu : %s" % e}, 502)
            return self._bytes(data, "audio/wav")
        if p == "/api/cmd":
            line = (b.get("line") or "").strip()
            if not line:
                return self._json({"ok": False, "error": "commande vide"}, 400)
            return self._json(command(line))
        if p == "/api/config":
            ok, msg = config_write(b)
            return self._json({"ok": ok, "text": msg}, 200 if ok else 400)
        if p == "/api/skill":
            name = b.get("name")
            if not skill_path(name):
                return self._json({"ok": False, "text": "skill inconnue"}, 404)
            sec = b.get("section")
            if sec in SKILL_SECTIONS:
                meta = SKILL_SECTIONS[sec]
            elif sec in SKILL_PLAIN:
                meta = dict(SKILL_PLAIN[sec])
            else:
                return self._json({"ok": False, "text": "section non editable : %s" % sec}, 400)
            if sec == "TOOLS":
                known = set(tool_names())
                bad = [r.get("text") for r in (b.get("rows") or [])
                       if (r.get("text") or "").strip() and r.get("text").strip() not in known]
                if bad:
                    return self._json({"ok": False, "text": "ces tools ne sont pas dans la table : %s" % ", ".join(bad)}, 400)
            ok, msg = set_section_lines(skill_path(name), sec, b.get("rows") or [], meta)
            return self._json({"ok": ok, "text": msg}, 200 if ok else 400)
        if p == "/api/update/apply":
            return self._json(launch_update())
        if p == "/api/skill/load":
            ok, t = run_tool("load_skill", b.get("name") or "", stdin_data=b.get("name") or "")
            return self._json({"ok": ok, "text": t}, 200 if ok else 400)
        return self._json({"error": "no such route", "path": p}, 404)


def main():
    port = laconf.num("dashboard", "port", 8770)
    host = laconf.text("dashboard", "host", "127.0.0.1")
    argv = sys.argv[1:]
    if "--port" in argv:
        port = int(argv[argv.index("--port") + 1])
    if "--once" in argv:
        print(json.dumps({"state": state(), "history": history(2), "live": live()},
                         ensure_ascii=False, indent=2))
        return 0
    if not os.path.isdir(WEB):
        print("dash: le dossier des pages est absent : %s" % WEB, file=sys.stderr)
        return 2
    threading.Thread(target=bridge_doors, daemon=True).start()
    srv = ThreadingHTTPServer((host, port), H)
    print("dash: le tableau est ouvert sur http://%s:%d  (racine %s)" % (host, port, ROOT), file=sys.stderr)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\ndash: arret demande", file=sys.stderr)
    finally:
        srv.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
