# french in code is forbidden

import argparse
import contextlib
import os
import subprocess
import sys
import time

import numpy as np
import onnxruntime as ort

import laconf

GGUF = os.path.expanduser(laconf.text("llama", "gguf", "~/LLM_GGUF"))


def STATE_DIR():
    return laconf.path("state", "config/state/")


MEL = os.path.join(GGUF, "oww-melspectrogram.onnx")
EMB = os.path.join(GGUF, "oww-embedding_model.onnx")

RATE = 16000
FRAME = 1280
WINDOW = 76
STEP = 8
NEMB = 16
NEED = (WINDOW + 8) * 160


@contextlib.contextmanager
def _silent():
    saved = os.dup(2)
    hole = os.open(os.devholel, os.O_WRONLY)
    os.dup2(hole, 2)
    try:
        yield
    finally:
        os.dup2(saved, 2)
        os.close(saved)
        os.close(hole)


def open_sessions(model_path):
    for f in (MEL, EMB, model_path):
        if not os.path.exists(f):
            sys.exit("refused: the model is missing: %s" % f)
    so = ort.SessionOptions()
    so.intra_op_num_threads = 1
    so.inter_op_num_threads = 1
    so.log_severity_level = 3
    with _silent():
        return (ort.InferenceSession(MEL, so), ort.InferenceSession(EMB, so), ort.InferenceSession(model_path, so))


def melspec(sess, pcm):
    x = np.asarray(pcm, dtype=np.float32).reshape(1, -1)
    raw = sess.run(None, {sess.get_inputs()[0].name: x})[0].squeeze(axis=(0, 1))
    return raw / 10.0 + 2.0


def embeddings(sess, mel):
    if mel.shape[0] < WINDOW:
        return np.zeros((0, 96), dtype=np.float32)
    out = []
    for i in range(0, mel.shape[0] - WINDOW + 1, STEP):
        w = mel[i:i + WINDOW].reshape(1, WINDOW, 32, 1).astype(np.float32)
        out.append(sess.run(None, {sess.get_inputs()[0].name: w})[0].reshape(-1))
    return np.array(out) if out else np.zeros((0, 96), dtype=np.float32)


def scores(sess, emb):
    if len(emb) < NEMB:
        return []
    out = []
    name = sess.get_inputs()[0].name
    for i in range(0, max(0, len(emb) - NEMB) + 1):
        w = emb[i:i + NEMB].reshape(1, NEMB, 96).astype(np.float32)
        out.append(float(sess.run(None, {name: w})[0].reshape(-1)[0]))
    return out


def listen(pcm, sessions, threshold):
    mel, emb, model_path = sessions
    s = scores(model_path, embeddings(emb, melspec(mel, pcm)))
    hits = [i for i, v in enumerate(s) if v >= threshold]
    return (bool(hits) and (len(hits) > 1 and hits[-1] - hits[-2] == 1 or len(hits) == 1)), (max(s) if s else 0.0)


def signer():
    req = os.path.join(STATE_DIR(), "approve.request")
    if not os.path.exists(req):
        return "no pending request: the word signs nothing"
    with open(req, encoding="utf-8", errors="replace") as f:
        words = f.read().split()
    if not words or words[-1].isdigit():
        words = words[:-1]
    if not words:
        return "the pending request is unreadable"
    args = ["dash", laconf.path("approval_brick", "config/engine/approval.sh"), "allow"] + words
    r = subprocess.run(args, capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()[:200] or "green light written"


def main():
    ap = argparse.ArgumentParser(description="the one-word watcher: listen, and sign what waits")
    ap.add_argument("--model", default=os.path.join(GGUF, "oww-hey_jarvis_v0.1.onnx"),
                    help="the keyword model to listen for")
    ap.add_argument("--threshold", type=float, default=0.5, help="the score to clear (0.5 by default)")
    ap.add_argument("--wav", help="instead of the mic: a 16 kHz mono file, to test the chain")
    ap.add_argument("--once", action="store_true", help="stop after one signature")
    ap.add_argument("--quiet", action="store_true", help="say nothing when the word does not pass")
    a = ap.parse_args()
    sessions = open_sessions(a.model)

    if a.wav:
        import wave
        with wave.open(a.wav) as w:
            if w.getframerate() != RATE or w.getnchannels() != 1:
                sys.exit("refused: a 16 kHz mono wav is required (got %d Hz, %d channel(s))"
                         % (w.getframerate(), w.getnchannels()))
            pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
            if len(pcm) < NEED:
                pcm = np.concatenate([np.zeros(NEED - len(pcm), dtype=np.int16), pcm])
        t0 = time.time()
        hit, pic = listen(pcm, sessions, a.threshold)
        sys.stderr.write("peak %.3f  threshold %.2f  ->  %s  (%.0f ms for %.1f s of audio)\n"
                         % (pic, a.threshold, "WORD" if hit else "nothing", (time.time() - t0) * 1000,
                            len(pcm) / RATE))
        if hit:
            print(signer())
        return 0 if hit else 1

    buf = np.zeros(0, dtype=np.int16)
    last = 0.0
    last_tick = 0.0
    proc = subprocess.Popen(["arecord", "-q", "-f", "S16_LE", "-r", str(RATE), "-c", "1", "-t", "raw"],
                            stdout=subprocess.PIPE)
    sys.stderr.write("the watcher listens (16 kHz mono); word = %s; threshold = %.2f\n"
                     % (os.path.basename(a.model), a.threshold))
    try:
        while True:
            block = proc.stdout.read(FRAME * 2)
            if not block:
                break
            buf = np.concatenate([buf, np.frombuffer(block, dtype=np.int16)])
            if len(buf) < NEED:
                continue
            pcm, buf = buf, buf[-NEED:]
            hit, pic = listen(pcm, sessions, a.threshold)
            if pic > last:
                last = pic
            if hit and time.time() - last_tick > 3:
                last_tick = time.time()
                print("%s  %s" % (time.strftime("%H:%M:%S"), signer()), flush=True)
                subprocess.run(["dash", "-c", '. "$1/config/engine/lib.sh" && bip ok', "bip", laconf.ROOT],
                               check=False)
                if a.once:
                    return 0
            elif not a.quiet:
                sys.stderr.write("\rscore %.3f " % pic)
                sys.stderr.flush()
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
