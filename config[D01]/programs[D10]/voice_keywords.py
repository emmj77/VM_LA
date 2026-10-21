# id: P08
# the keyword list of the microphone, written from the master file's commands (voice: true).
# the spotter reads no comment: the file is bare, one line per command, in order.

import re
import sys

import sentencepiece as spm

master, bpe, out = sys.argv[1], sys.argv[2], sys.argv[3]

txt = open(master, encoding="utf-8").read()
parts = txt.split("\ncommands:\n", 1)
if len(parts) < 2:
    print("refused: no commands: section in the master file")
    sys.exit(1)
blk = parts[1].split("\n#", 1)[0]

sp = spm.SentencePieceProcessor(model_file=bpe)
lines, voiced = [], []
for chunk in blk.split("- id:")[1:]:
    d = dict(re.findall(r"^\s{4}([a-z]+):\s*(.*)$", chunk, re.M))
    if d.get("voice", "").strip() != "true":
        continue
    name = d["name"].strip().strip('"')
    if not name:
        continue
    th = "0.1" if len(name.split()) == 1 else "0.2"
    lines.append(" ".join(sp.encode(name.upper(), out_type=str)) + " :1.0 #" + th + " @" + name.replace(" ", "_"))
    voiced.append(name)

open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("keywords: %d (%s)" % (len(lines), ", ".join(voiced)))
