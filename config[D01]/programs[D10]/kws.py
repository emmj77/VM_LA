#!/usr/bin/env python3
# id: P08
# L'OREILLE : un seul processus, le petit zipformer KWS, le micro. Il ne sert aucun port :
# il ecoute, il reconnait un mot des commandes, et il ouvre la porte.
#
# Usage : kws.py --root <modele> --keywords <fichier> --log <fichier> --gate <la.sh> [--mic default]

import argparse
import re
import subprocess
import sys
import time
from array import array


def log(path, line):
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), line))
    except OSError:
        pass


def load_keywords(path):
    """le fichier des mots : le texte entendu -> le nom de la commande (@nom)"""
    out = {}
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return out
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.search(r"@([A-Za-z0-9_\-]+)\s*$", line)
        if not m:
            continue
        out[heard(line.split(":")[0])] = m.group(1).replace("_", " ")
    return out


def heard(text):
    """le mot ramene a la forme du fichier : un seul espace, pas de symbole de debut"""
    text = re.sub(r"[▁_]+", " ", text or "")
    return re.sub(r"\s+", " ", text).strip().upper()


def samples(raw):
    """PCM 16 bits little endian -> flottants -1..1, sans numpy"""
    pcm = array("h")
    pcm.frombytes(raw)
    if sys.byteorder == "big":
        pcm.byteswap()
    return array("f", [v / 32768.0 for v in pcm])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--keywords", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--gate", required=True)
    ap.add_argument("--mic", default="default")
    ap.add_argument("--threads", type=int, default=2)
    a = ap.parse_args()

    import sherpa_onnx

    root = a.root.rstrip("/")
    words = load_keywords(a.keywords)
    if not words:
        log(a.log, "FAULT no keyword in %s" % a.keywords)
        return 2
    log(a.log, "ready, %d word(s): %s" % (len(words), ", ".join(sorted(words))))

    kws = sherpa_onnx.KeywordSpotter(
        tokens=root + "/tokens.txt",
        encoder=root + "/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
        decoder=root + "/decoder-epoch-12-avg-2-chunk-16-left-64.onnx",
        joiner=root + "/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
        keywords_file=a.keywords,
        num_threads=a.threads,
        provider="cpu",
    )
    stream = kws.create_stream()

    block = 3200          # 0.1 s : le decodeur veut de petits morceaux, le micro n attend jamais
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
                    if time.time() - last < 2.0:      # un mot ne se repete pas dans la meme seconde
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
