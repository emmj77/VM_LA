# french in code is forbidden
import argparse
import json
import os
import sys
import urllib.request

import laconf

ROOT = laconf.ROOT


def port_embed():
    return str(laconf.num("models", "port", 8091))


def question_vector(port, text):
    name = os.environ.get("LA_EMBED_MODEL") or "local"
    body = json.dumps({"input": [text], "model": name}).encode()
    req = urllib.request.Request("http://127.0.0.1:%s/v1/embeddings" % port, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())["data"][0]["embedding"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--request", default="")
    ap.add_argument("--k", type=int, default=60)
    ap.add_argument("--db", default=os.path.join(ROOT, "config", "tool_vec.db"))
    a = ap.parse_args()

    with open(a.candidates, encoding="utf-8") as f:
        lines = [l for l in f.read().split("\n") if l.strip()]
    if len(lines) <= a.k:
        return 0

    try:
        import numpy as np
    except Exception:
        sys.stderr.write("note: numpy missing, no preselection by meaning took place "
                         "(%d candidates sent to the reranker)\n" % len(lines))
        return 0
    try:
        import sqlite3
        con = sqlite3.connect(a.db)
        ids = [int(l.split("|", 1)[0]) for l in lines]
        marks = ",".join("?" * len(ids))
        vecs = {}
        for i, blob in con.execute("SELECT id, vec FROM tool_vec WHERE id IN (%s)" % marks, ids):
            if blob:
                vecs[i] = np.frombuffer(blob, dtype="<f4")
        if not vecs:
            raise RuntimeError("no vector for these candidates")
        q = np.asarray(question_vector(port_embed(), a.request), dtype="f4")
        size = min(len(v) for v in vecs.values())
        if len(q) != size:
            raise RuntimeError("the question vector is %d wide, tools are %d"
                               % (len(q), size))
        guards = [i for i in ids if i in vecs]
        M = np.vstack([vecs[i] for i in guards])
        qn = q / (np.linalg.norm(q) + 1e-9)
        Mn = M / (np.linalg.norm(M, axis=1, keepdims=True) + 1e-9)
        scores = Mn @ qn
        order = np.argsort(-scores)[:a.k]
        kept = []
        for pos in order:
            i = guards[int(pos)]
            kept.append(i)
        par_id = {int(l.split("|", 1)[0]): l for l in lines}
        output = [par_id[i] for i in kept]
        no_vec = [l for l in lines if int(l.split("|", 1)[0]) not in vecs]
        output += no_vec[:max(0, a.k - len(output))]
        sys.stdout.write("\n".join(output) + "\n")
        sys.stderr.write("preselection: %d candidate(s) of %d kept by meaning\n"
                         % (len(output), len(lines)))
        return 0
    except Exception as e:
        sys.stderr.write("note: preselection impossible (%s); %d candidate(s) go to the "
                         "reranker\n" % (e, len(lines)))
        sys.stdout.write("\n".join(lines) + "\n")
        return 0


if __name__ == "__main__":
    sys.exit(main())
