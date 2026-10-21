# id: P07
# the dashboard's own door. the page only; the bridge is elsewhere and stays there.
# it exits when nobody looks at it, and systemd wakes it on the next connection.

import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PAGE = os.environ.get("LA_PAGE") or os.path.join(ROOT, "page[D09]")
BRIDGE = os.environ.get("LA_BRIDGE_URL") or "http://127.0.0.1:8770"
IDLE = int(os.environ.get("LA_DASH_IDLE") or 120)
PAGE_ROUTES = ("/", "/m", "/chat", "/doctor", "/plan", "/models")
MASTER = os.environ.get("LA_CONF") or os.path.join(ROOT, "conf[D05]", "la_config.yaml")
ENGINE = os.environ.get("LA_ENGINE") or os.path.join(ROOT, "engine[D07]", "la.sh")
MARK = "<!-- les commandes -->"
TOUCH = [time.time()]


def commands():
    # the commands of the master file, block style, in order: one reader, no copy
    try:
        with open(MASTER, encoding="utf-8") as f:
            txt = f.read()
    except OSError:
        return []
    parts = txt.split("\ncommands:\n", 1)
    if len(parts) < 2:
        return []
    blk = parts[1].split("\n#", 1)[0]
    out, cur = [], None
    for line in blk.splitlines():
        s = line.strip()
        if s.startswith("- id:"):
            if cur:
                out.append(cur)
            cur = {}
        elif cur is not None and ":" in s:
            k, v = s.split(":", 1)
            cur[k.strip()] = v.strip().strip('"')
    if cur:
        out.append(cur)
    return [c for c in out if c.get("name")]


def commands_html():
    cs = commands()
    if not cs:
        return ""
    h = ['<div id="cmds"><style>'
         '#cmds{display:flex;flex-wrap:wrap;gap:8px;padding:10px 14px;background:#0d0d0d;'
         'border-bottom:1px solid #222;align-items:center}'
         '#cmds form{display:flex;gap:6px;margin:0}'
         '#cmds button{background:#1c1c1c;color:#e8e8e8;border:1px solid #333;'
         'border-radius:8px;padding:7px 11px;font:13px/1.2 system-ui,sans-serif;cursor:pointer}'
         '#cmds button:hover{border-color:#555;background:#242424}'
         '#cmds input{background:#141414;color:#e8e8e8;border:1px solid #333;border-radius:8px;'
         'padding:6px 8px;font:13px/1.2 system-ui,sans-serif;width:7em}'
         '</style>']
    for c in cs:
        name = escape(c["name"])
        what = escape(c.get("tool") or c.get("act") or "")
        if c.get("arg"):
            h.append('<form method="get" action="/cmd">'
                     '<input type="hidden" name="name" value="%s">'
                     '<input name="arg" placeholder="%s" autocomplete="off">'
                     '<button title="%s">%s</button></form>' % (name, escape(c["arg"]), what, name))
        else:
            h.append('<form method="get" action="/cmd">'
                     '<input type="hidden" name="name" value="%s">'
                     '<button title="%s">%s</button></form>' % (name, what, name))
    h.append("</div>")
    return "".join(h)


def run_command(name, arg):
    # the door does the work: one path, whatever the surface
    cmd = ["sh", ENGINE] + name.split()
    if arg:
        cmd.append(arg)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return "timeout", "the command did not answer in 600 s"
    out = (p.stdout or "") + (p.stderr or "")
    status = "ok" if p.returncode == 0 else "refused"
    result = out.strip()
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            status = d.get("status") or status
            result = (d.get("result") or d.get("message") or "").strip()
    return status, result


class Handler(BaseHTTPRequestHandler):
    server_version = "LA-dash"
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n > 0 else b""

    def send_page(self, name="page.html"):
        try:
            with open(os.path.join(PAGE, name), "rb") as f:
                data = f.read()
        except OSError:
            return self.reply(500, b"the page is not in the tree", "text/plain; charset=utf-8")
        if MARK.encode() in data:
            data = data.replace(MARK.encode(), commands_html().encode(), 1)
        return self.reply(200, data, "text/html; charset=utf-8")

    def reply(self, code, data, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def relay(self, method, body):
        """everything that is not the page belongs to the bridge: it is relayed as is"""
        url = BRIDGE + self.path
        req = urllib.request.Request(url, data=body if method in ("POST", "PUT") else None, method=method)
        req.add_header("Content-Type", self.headers.get("Content-Type") or "application/json")
        for h in ("Accept", "Authorization"):
            v = self.headers.get(h)
            if v:
                req.add_header(h, v)
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                data = r.read()
                return self.reply(r.status, data, r.headers.get("Content-Type") or "application/json")
        except urllib.error.HTTPError as e:
            data = e.read()
            return self.reply(e.code, data, e.headers.get("Content-Type") or "application/json")
        except Exception as e:
            return self.reply(502, ('{"error":"the bridge is out of reach: %s"}' % str(e)[:120]).encode(),
                              "application/json")

    def do_GET(self):
        p = urlsplit(self.path).path
        # un ping n est pas une visite : la table sonde la page toutes les quinze secondes,
        # et ce sondage la tenait eveillee pour toujours.
        if p == "/ping":
            return self.reply(200, b'{"state": "alive", "door": "dashboard"}', "application/json")
        TOUCH[0] = time.time()
        if p == "/cmd":
            q = parse_qs(urlsplit(self.path).query)
            name = (q.get("name") or [""])[0].strip()
            arg = (q.get("arg") or [""])[0].strip()
            if name not in [c["name"] for c in commands()]:
                return self.reply(403, b"not a command of the master file", "text/plain; charset=utf-8")
            status, result = run_command(name, arg)
            page = ("<!doctype html><meta charset=utf-8><title>%s</title>"
                    "<style>body{background:#111;color:#e8e8e8;font:15px/1.5 system-ui,sans-serif;margin:24px}"
                    "pre{white-space:pre-wrap;background:#161616;border:1px solid #2a2a2a;border-radius:10px;padding:14px}"
                    "a{color:#8ab4ff}b{color:#9de29d}</style>"
                    "<p><a href='/'>retour</a></p><h3>%s <b>%s</b></h3><pre>%s</pre>") % (
                escape(name), escape(name), escape(status), escape(result or "(rien)"))
            return self.reply(200, page.encode(), "text/html; charset=utf-8")
        if p in PAGE_ROUTES:
            return self.send_page()
        if p.startswith("/static/"):
            name = p[len("/static/"):]
            if "/" in name or name.startswith("."):
                return self.reply(404, b"no", "text/plain")
            if name.endswith(".html"):
                return self.send_page(name)
            try:
                with open(os.path.join(PAGE, name), "rb") as f:
                    data = f.read()
            except OSError:
                return self.reply(404, b"no such file", "text/plain")
            return self.reply(200, data, "application/octet-stream")
        return self.relay("GET", b"")

    def do_POST(self):
        TOUCH[0] = time.time()
        return self.relay("POST", self.body())

    def do_HEAD(self):
        TOUCH[0] = time.time()
        return self.do_GET()


def watch_idle():
    while True:
        time.sleep(5)
        if time.time() - TOUCH[0] > IDLE:
            os._exit(0)


def serve(port):
    fds = int(os.environ.get("LISTEN_FDS") or 0)
    if fds >= 1:
        passed = socket.fromfd(3, socket.AF_INET, socket.SOCK_STREAM)

        class Woken(ThreadingHTTPServer):
            daemon_threads = True

            def server_bind(self):
                self.socket.close()
                self.socket = passed
                self.server_address = self.socket.getsockname()

            def server_activate(self):
                pass

        srv = Woken(("127.0.0.1", port), Handler)
    else:
        srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        srv.daemon_threads = True
    threading.Thread(target=watch_idle, daemon=True).start()
    srv.serve_forever()


if __name__ == "__main__":
    serve(int(os.environ.get("LA_PORT_DASH") or 8771))
