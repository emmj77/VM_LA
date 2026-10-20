# french in code is forbidden
import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time
import urllib.request

import laconf

ROOT = laconf.ROOT



def descriptions(table):
    names = {}
    with open(table, encoding="utf-8") as f:
        current = None
        for line in f:
            s = line.strip()
            if s.startswith("- id:"):
                current = int(s.split(":")[1])
            elif s.startswith("tool:") and current is not None:
                names[current] = s.split(":", 1)[1].strip().strip('"')
                current = None
    fiches = {}
    base = os.path.join(ROOT, "config", "tools")
    for folder in sorted(os.listdir(base)):
        d = os.path.join(base, folder)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if not (f.startswith("tool_") and f.endswith(".yaml")):
                continue
            path = os.path.join(d, f)
            name, desc = None, ""
            with open(path, encoding="utf-8", errors="replace") as g:
                for line in g:
                    if line.startswith("tool:"):
                        name = line.split(":", 1)[1].strip().strip('"')
                    elif line.startswith("DESCRIPTION:"):
                        desc = line.split(":", 1)[1].strip().strip('"')
                        break
            if name:
                fiches[name] = desc
    out = {}
    for i, name in sorted(names.items()):
        words = name.replace("_", " ").replace("-", " ").strip()
        desc = fiches.get(name, "")
        out[i] = (name, (words + " : " + desc).strip()[:400] if desc else words)
    return out


def vectors(port, texts, modele):
    body = json.dumps({"input": texts, "model": modele}).encode()
    req = urllib.request.Request("http://127.0.0.1:%s/v1/embeddings" % port, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        rep = json.loads(r.read())
    return [d["embedding"] for d in rep["data"]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(ROOT, "config", "tool_vec.db"))
    ap.add_argument("--table", default=os.path.join(ROOT, "config", "la_tools.yaml"))
    ap.add_argument("--only-missing", action="store_true",
                    help="only compute what is missing or changed (the current mode)")
    ap.add_argument("--limit", type=int, default=0, help="stop after N tools (a try)")
    ap.add_argument("--batch", type=int, default=32)
    a = ap.parse_args()

    port = str(laconf.num("models", "port", 8091))
    con = sqlite3.connect(a.db)
    con.execute("CREATE TABLE IF NOT EXISTS tool_vec (id INTEGER PRIMARY KEY, name TEXT, "
                "empreinte TEXT, texte TEXT, vec BLOB)")
    con.execute("CREATE TABLE IF NOT EXISTS meta (cle TEXT PRIMARY KEY, valeur TEXT)")
    con.commit()

    tools = descriptions(a.table)
    modele = laconf.text("models", "embed", "local")
    already = {i: e for i, e in con.execute("SELECT id, empreinte FROM tool_vec")}
    todo = []
    for i, (name, text) in tools.items():
        e = hashlib.sha1(text.encode("utf-8")).hexdigest()[:16]
        if a.only_missing and already.get(i) == e:
            continue
        todo.append((i, name, text, e))
    if a.limit:
        todo = todo[:a.limit]
    sys.stderr.write("%d tool(s) a vectoriser sur %d\n" % (len(todo), len(tools)))
    if not todo:
        print("rien a faire : la table de vectors est a jour (%d tools)" % len(tools))
        return 0

    start = time.time()
    import struct
    for k in range(0, len(todo), a.batch):
        batch = todo[k:k + a.batch]
        vecs = vectors(port, [t for _, _, t, _ in batch], modele)
        con.executemany("INSERT OR REPLACE INTO tool_vec(id, name, empreinte, texte, vec) "
                        "VALUES (?,?,?,?,?)",
                        [(i, n, e, t, struct.pack("<%df" % len(v), *v))
                         for (i, n, t, e), v in zip(batch, vecs)])
        con.commit()
        done = k + len(batch)
        sys.stderr.write("\r%d/%d  (%.0f s)" % (done, len(todo), time.time() - start))
        sys.stderr.flush()
    dim = len(vecs[0])
    con.execute("INSERT OR REPLACE INTO meta VALUES ('dim', ?)", (str(dim),))
    con.execute("INSERT OR REPLACE INTO meta VALUES ('modele', ?)", (modele,))
    con.commit()
    sys.stderr.write("\ntermine : %d vectors de %d dimensions en %.0f s\n"
                     % (len(todo), dim, time.time() - start))
    return 0


if __name__ == "__main__":
    sys.exit(main())
