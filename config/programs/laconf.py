# french in code is forbidden
import os
import re
import tempfile

ROOT = os.environ.get("LA_ROOT") or os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
CONFD = os.path.join(ROOT, "config")
CONF = os.environ.get("LA_CONF") or os.path.join(CONFD, "la_config.yaml")
TABLE = os.environ.get("LA_CONFIG") or os.path.join(CONFD, "la_tools.yaml")
MESSAGES = os.environ.get("LA_MESSAGES") or os.path.join(CONFD, "messages.yaml")

_cache = {"mtime": None, "data": {}}
_msgs = {"mtime": None, "data": {}}


def raw():
    try:
        mt = os.stat(CONF).st_mtime_ns
    except OSError:
        return {}
    if _cache["mtime"] != mt:
        try:
            import yaml
            with open(CONF, encoding="utf-8") as f:
                _cache["data"] = yaml.safe_load(f) or {}
        except Exception:
            _cache["data"] = {}
        _cache["mtime"] = mt
    return _cache["data"]


def messages():
    try:
        mt = os.stat(MESSAGES).st_mtime_ns
    except OSError:
        return {}
    if _msgs["mtime"] != mt:
        try:
            import yaml
            with open(MESSAGES, encoding="utf-8") as f:
                _msgs["data"] = yaml.safe_load(f) or {}
        except Exception:
            _msgs["data"] = {}
        _msgs["mtime"] = mt
    return _msgs["data"]


def get(section, key, default=""):
    d = raw().get(section)
    v = d.get(key) if isinstance(d, dict) else None
    return default if v is None or v == "" else v


def text(section, key, default=""):
    d = raw().get(section)
    v = d.get(key) if isinstance(d, dict) else None
    return default if v is None or v == "" else str(v)


def num(section, key, default):
    try:
        return int(str(get(section, key, "")).strip())
    except (TypeError, ValueError):
        return default


def path(key, default):
    v = os.path.expanduser(text("paths", key, default))
    return v if os.path.isabs(v) else os.path.join(ROOT, v)


def state_dir():
    return path("state", "config/state/")


def write_atomic(p, lines):
    txt = lines if isinstance(lines, str) else "".join(lines)
    d = os.path.dirname(p) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(txt)
        try:
            os.chmod(tmp, os.stat(p).st_mode & 0o777)
        except OSError:
            pass
        os.replace(tmp, p)
        return ""
    except Exception as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return str(e)


def set(section, key, value):
    try:
        with open(CONF, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError as e:
        return False, "la_config illisible (%s)" % e
    sec = None
    pat = re.compile(r"^(\s+" + re.escape(key) + r":\s*)(\"[^\"]*\"|[^#\n]*?)(\s+#.*)?(\n?)$")
    for i, l in enumerate(lines):
        if not l.strip() or l.lstrip().startswith("#"):
            continue
        if not l[0].isspace():
            sec = l.split(":", 1)[0].strip()
            continue
        if sec != section:
            continue
        m = pat.match(l)
        if not m:
            continue
        lines[i] = m.group(1) + str(value) + (m.group(3) or "") + (m.group(4) or "\n")
        err = write_atomic(CONF, lines)
        if err:
            return False, "l ecriture a echoue (%s)" % err
        _cache["mtime"] = None
        if text(section, key, "") != str(value).strip('"'):
            return False, "la valeur relue ne correspond pas : rien n est garanti"
        return True, "ecrit"
    if section not in raw():
        return False, "la section %s n existe pas dans la_config" % section
    return False, "la cle %s n est pas ecrite dans la section %s" % (key, section)


_tbl = {"mt": None, "rows": []}


def table():
    try:
        mt = os.stat(TABLE).st_mtime_ns
    except OSError:
        return []
    if _tbl["mt"] != mt:
        rows, cur = [], None
        try:
            with open(TABLE, encoding="utf-8", errors="replace") as f:
                for ln in f:
                    m = re.match(r"^\s+-\s+id:\s*(\d+)\s*$", ln)
                    if m:
                        if cur:
                            rows.append(cur)
                        cur = {"id": m.group(1)}
                        continue
                    m = re.match(r"^\s+(tool|family):\s*(\S+)\s*$", ln)
                    if m and cur is not None:
                        cur[m.group(1)] = m.group(2).strip('"')
            if cur:
                rows.append(cur)
        except OSError:
            return []
        _tbl.update({"mt": mt, "rows": rows})
    return _tbl["rows"]


_head = {"mt": None, "s": []}


def head(path=None):
    f = path or os.path.join(ROOT, "config/second.head")
    try:
        mt = os.stat(f).st_mtime_ns
    except OSError:
        return []
    if _head["mt"] == mt:
        return _head["s"]
    try:
        with open(f, encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
    except OSError:
        return []
    out = []
    for part in raw.split("\x1e"):
        if not part.strip():
            continue
        ls = part.splitlines()
        t = ls[0].strip() if ls and ls[0].lstrip().startswith("==") else ""
        body = ("\n".join(ls[1:]) if t else part).strip("\n")
        out.append({"label": (t.strip("= ").strip() if t else "(sans titre)"), "body": body,
                    "bytes": len(body.encode()), "lines": len([x for x in body.splitlines() if x.strip()])})
    _head.update({"mt": mt, "s": out})
    return out

def message(key, default=""):
    v = messages().get(key)
    return default if v is None or v == "" else str(v)
