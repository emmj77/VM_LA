# id: P07
# the dashboard's own door. the page only; the bridge is elsewhere and stays there.
# it exits when nobody looks at it, and systemd wakes it on the next connection.

import os
import socket
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PAGE = os.environ.get("LA_PAGE") or os.path.join(ROOT, "page[D09]")
BRIDGE = os.environ.get("LA_BRIDGE_URL") or "http://127.0.0.1:8770"
IDLE = int(os.environ.get("LA_DASH_IDLE") or 120)
PAGE_ROUTES = ("/", "/m", "/chat", "/doctor", "/plan", "/models")
TOUCH = [time.time()]


class Handler(BaseHTTPRequestHandler):
    server_version = "LA-dash"
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n > 0 else b""

    def send_page(self):
        try:
            with open(os.path.join(PAGE, "page.html"), "rb") as f:
                data = f.read()
        except OSError:
            return self.reply(500, b"the page is not in the tree", "text/plain; charset=utf-8")
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
        TOUCH[0] = time.time()
        p = urlsplit(self.path).path
        if p == "/ping":
            return self.reply(200, b'{"state": "alive", "door": "dashboard"}', "application/json")
        if p in PAGE_ROUTES:
            return self.send_page()
        if p.startswith("/static/"):
            name = p[len("/static/"):]
            if "/" in name or name.startswith("."):
                return self.reply(404, b"no", "text/plain")
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
