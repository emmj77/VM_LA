#!/usr/bin/env python3
# id: P08
# THE EAR: one process, the small zipformer keyword spotter, the microphone. It serves no port:
# it hears one word of the commands, and it opens the door.
#
# The keyword list is built HERE, from the master file, and written to a file only for the
# second the spotter needs to read it: sherpa-onnx takes a path, never a string. The file is
# thrown away as soon as the spotter holds the words, so nothing stale lives on the disk.
#
# Usage: ear.py --root <model> --master <la_config> --log <file> --gate <la.sh>
#               [--mic default] [--threads 2] [--once]

import argparse
import os
import re
import subprocess
import sys
import tempfile
import time
from array import array


def log(path, line):
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), line))
    except OSError:
        pass


def commands(master):
    """the commands of the master file that the voice may open: name, in order"""
    txt = open(master, encoding="utf-8").read()
    parts = txt.split("\ncommands:\n", 1)
    if len(parts) < 2:
        return []
    blk = parts[1].split("\n#", 1)[0]
    out = []
    for chunk in blk.split("- id:")[1:]:
        d = dict(re.findall(r"^\s{4}([a-z]+):\s*(.*)$", chunk, re.M))
        if d.get("voice", "").strip() != "true":
            continue
        name = d.get("name", "").strip().strip('"')
        if name:
            out.append(name)
    return out


def keyword_lines(names, bpe):
    """one line per command: the tokens, the score, the threshold, the name for the map"""
    import sentencepiece as spm

    sp = spm.SentencePieceProcessor(model_file=bpe)
    lines = []
    for name in names:
        boost = "0.1" if len(name.split()) == 1 else "0.2"
        toks = " ".join(sp.encode(name.upper(), out_type=str))
        lines.append((toks, boost, name))
    return lines


def heard(text):
    """what the spotter says, back to the shape of the master file: one space, no start mark"""
    text = re.sub(r"[\u2581_]+", " ", text or "")
    return re.sub(r"\s+", " ", text).strip().upper()


def samples(raw):
    """16 bit little endian PCM -> floats -1..1, without numpy"""
    pcm = array("h")
    pcm.frombytes(raw)
    if sys.byteorder == "big":
        pcm.byteswap()
    return array("f", [v / 32768.0 for v in pcm])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--master", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--gate", required=True)
    ap.add_argument("--mic", default="default")
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--once", action="store_true", help="build the list, show it, stop")
    a = ap.parse_args()

    root = a.root.rstrip("/")
    bpe = root + "/bpe.model"
    names = commands(a.master)
    if not names:
        log(a.log, "FAULT no command with voice: true in %s" % a.master)
        return 2
    if not os.path.exists(bpe):
        log(a.log, "FAULT the bpe model is missing: %s" % bpe)
        return 2

    lines = keyword_lines(names, bpe)
    if a.once:
        for toks, boost, name in lines:
            print("%s :1.0 #%s @%s" % (toks, boost, name.replace(" ", "_")))
        return 0

    # the spotter reads the file once, at construction: write it, build, throw it away
    where = os.environ.get("LA_STATE") or tempfile.gettempdir()
    fd, path = tempfile.mkstemp(prefix="keywords.", suffix=".txt", dir=where)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        for toks, boost, name in lines:
            f.write("%s :1.0 #%s @%s\n" % (toks, boost, name.replace(" ", "_")))

    import sherpa_onnx

    try:
        kws = sherpa_onnx.KeywordSpotter(
            tokens=root + "/tokens.txt",
            encoder=root + "/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
            decoder=root + "/decoder-epoch-12-avg-2-chunk-16-left-64.onnx",
            joiner=root + "/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
            keywords_file=path,
            num_threads=a.threads,
            provider="cpu",
        )
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass

    words = {}
    for toks, boost, name in lines:
        words[heard(toks)] = name
    log(a.log, "ready, %d word(s): %s" % (len(words), ", ".join(sorted(words))))
    stream = kws.create_stream()

    block = 3200          # 0.1 s: the decoder wants small pieces, the microphone never waits
    last = 0.0
    while True:
        rec = subprocess.Popen(
            ["arecord", "-q", "-D", a.mic, "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "raw", "-"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        log(a.log, "listening on %s" % a.mic)
        try:
            while True:
                raw = rec.stdout.read(block)
                if not raw:
                    break
                stream.accept_waveform(16000, samples(raw))
                while kws.is_ready(stream):
                    kws.decode_stream(stream)
                    result = kws.get_result(stream)
                    if not result:
                        continue
                    kws.reset_stream(stream)
                    word = heard(result)
                    cmd = words.get(word)
                    if not cmd:
                        log(a.log, "heard %s (no command)" % word)
                        continue
                    if time.time() - last < 2.0:      # a word never repeats within the same second
                        continue
                    last = time.time()
                    log(a.log, "heard %s -> %s" % (word, cmd))
                    subprocess.Popen(["dash", a.gate, cmd], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, start_new_session=True)
        except KeyboardInterrupt:
            rec.terminate()
            return 0
        finally:
            try:
                rec.terminate()
            except OSError:
                pass
        log(a.log, "the microphone stopped, retrying")
        time.sleep(5)


if __name__ == "__main__":
    sys.exit(main() or 0)
