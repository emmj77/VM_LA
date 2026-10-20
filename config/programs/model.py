# french in code is forbidden
import json
import os
import re
import sqlite3
import subprocess
import time

import laconf


def _run(args, timeout=6):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout or ""


def git_state():
    lines = _run(["git", "-C", laconf.ROOT, "status", "--porcelain=v1", "-b"], 8).splitlines()
    header = lines[0][3:] if lines and lines[0].startswith("## ") else ""
    branch, _, rest = header.partition("...")
    m = re.search(r"\[([^\]]*)\]", rest)
    delta = {}
    for p in (m.group(1).split(",") if m else []):
        k, _, v = p.strip().partition(" ")
        delta[k] = int(v) if v.isdigit() else 0
    return {
        "branch": (branch or header).strip(),
        "upstream": rest.split("[")[0].strip(),
        "ahead": delta.get("ahead", 0),
        "behind": delta.get("behind", 0),
        "dirty": len([l for l in lines[1:] if l.strip()]),
        "rev": _run(["git", "-C", laconf.ROOT, "rev-parse", "--short", "HEAD"], 8).strip(),
        "describe": _run(["git", "-C", laconf.ROOT, "describe", "--always", "--tags", "--dirty"], 8).strip(),
    }


def _tree(pid):
    if not (pid and pid.isdigit() and pid != "0"):
        return None, None
    seen, stack = [], [pid]
    while stack:
        q = stack.pop()
        if q in seen:
            continue
        seen.append(q)
        try:
            for tid in os.listdir("/proc/%s/task" % q):
                with open("/proc/%s/task/%s/children" % (q, tid), "r") as f:
                    stack.extend(f.read().split())
        except OSError:
            pass
    anon = rss = counted = 0
    for q in seen:
        try:
            with open("/proc/%s/status" % q, "r") as f:
                for l in f:
                    if l.startswith("RssAnon:"):
                        anon += int(l.split()[1])
                    elif l.startswith("VmRSS:"):
                        rss += int(l.split()[1])
            counted += 1
        except OSError:
            pass
    return (anon // 1024, rss // 1024) if counted else (None, None)


def units(names):
    wanted = [n for n in names if n]
    if not wanted:
        return {}
    full_names = [n if "." in n.rsplit("/", 1)[-1] else n + ".service" for n in wanted]
    txt = _run(["systemctl", "--user", "show", "-p", "Id", "-p", "ActiveState", "-p", "MainPID",
                "-p", "MemoryCurrent"] + full_names)
    by_id, block = {}, {}

    def _close(b):
        if not b.get("Id"):
            return
        cg = b.get("MemoryCurrent", "")
        by_id[b["Id"]] = {"state": b.get("ActiveState") or "?", "pid": b.get("MainPID") or None,
                           "cg_mb": int(cg) // 1048576 if cg.isdigit() and int(cg) != 2 ** 64 - 1 else None}

    for ln in txt.splitlines() + [""]:
        if ln.strip():
            k, _, v = ln.partition("=")
            block[k] = v.strip()
            continue
        _close(block)
        block = {}
    empty = {"state": "?", "pid": None, "cg_mb": None, "anon_mb": None, "rss_mb": None}
    for d, p in zip(wanted, full_names):
        st = by_id.get(p) or dict(empty)
        st["anon_mb"], st["rss_mb"] = _tree(st["pid"])
        by_id[d] = st
    return by_id


def usage():
    f = laconf.path("usage", "")
    rows = []
    if not f:
        return rows
    try:
        with open(f, "r", encoding="utf-8", errors="replace") as h:
            for ln in h:
                try:
                    rows.append(json.loads(ln))
                except ValueError:
                    continue
    except OSError:
        pass
    return rows


def tokens():
    rows = usage()
    sess = max([int(r.get("session") or 0) for r in rows] or [0])
    return {"session": sess, "calls": len(rows),
            "session_tokens": sum(int(r.get("tokens") or 0) for r in rows
                                  if int(r.get("session") or 0) == sess),
            "last_turn": int(rows[-1].get("tokens") or 0) if rows else 0}


def query(sql, params=()):
    f = laconf.path("sessions", "")
    if not f or not os.path.isfile(f):
        return []
    try:
        cx = sqlite3.connect("file:%s?mode=ro" % f, uri=True, timeout=3)
        cx.row_factory = sqlite3.Row
        try:
            return [dict(r) for r in cx.execute(sql, params)]
        finally:
            cx.close()
    except sqlite3.Error:
        return []


def db_counts():
    r = query("select count(*) as n, coalesce(max(exchange),0) as ex, "
              "(select ts from messages order by id desc limit 1) as ts from messages")
    return r[0] if r else {"n": 0, "ex": 0, "ts": ""}


def doctor(mode="short", grace=60):
    cache = os.path.join(laconf.state_dir(), "doctor.%s.cache" % mode)
    try:
        age = time.time() - os.path.getmtime(cache)
    except OSError:
        age = None
    raw = ""
    if age is not None and age < grace:
        try:
            with open(cache, "r", errors="replace") as f:
                raw = f.read()
        except OSError:
            raw = ""
    if not raw:
        raw = _run(["sh", os.path.join(laconf.CONFD, "engine", "doctor.sh"), "--%s" % mode], 120)
        try:
            with open(cache, "w") as f:
                f.write(raw)
        except OSError:
            pass
        age = 0.0
    verdicts = []
    for ln in raw.splitlines():
        word = ln.strip().split()[0] if ln.strip() else ""
        if word in ("ok", "fail", "FAULT", "FAUTE", "note"):
            verdicts.append((word, ln.strip()[len(word):].strip()))
    return {"age": age, "raw": raw, "verdicts": verdicts,
            "rc": 1 if any(v[0] in ("fail", "FAULT", "FAUTE") for v in verdicts) else 0}


def engine():
    for e in (laconf.raw().get("engines") or []):
        if isinstance(e, dict) and str(e.get("active", "")).lower() in ("true", "1", "oui"):
            return {"alias": e.get("alias") or e.get("provider") or "?",
                    "model": e.get("model") or "?", "provider": e.get("provider") or "?",
                    "post": e.get("post") or "",
                    "context": int(str(e.get("context") or 0).replace("_", "") or 0)}
    return {"alias": "?", "model": "?", "provider": "?", "post": "", "context": 0}
