# id: P03
# french in code is forbidden
import glob
import json
import os
import threading
import time
import wave
from array import array
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import sherpa_onnx

ROOT = os.environ["LA_ROOT"]
AUDIO_DIR = os.environ["LA_AUDIO"]
PORT = int(os.environ.get("LA_PORT_TTS") or 8090)
SID = int(os.environ.get("LA_TTS_SID") or 1)
THREADS = int(os.environ.get("LA_TTS_THREADS") or 8)
MODEL_DIR = os.path.expanduser(os.environ.get("LA_TTS_MODEL")
                              or "~/Applications/sherpa-onnx/voix/vits-piper-fr_FR-upmc-medium")

LOCK = threading.Lock()


def load():
    onnx = sorted(glob.glob(os.path.join(MODEL_DIR, "*.onnx")))
    if not onnx:
        raise SystemExit("voice: no model in %s" % MODEL_DIR)
    start = time.monotonic()
    config = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            vits=sherpa_onnx.OfflineTtsVitsModelConfig(
                model=onnx[0],
                tokens=os.path.join(MODEL_DIR, "tokens.txt"),
                data_dir=os.path.join(MODEL_DIR, "espeak-ng-data"),
            ),
            num_threads=THREADS,
            provider="cpu",
            debug=False,
        ),
        max_num_sentences=1,
    )
    if not config.validate():
        raise SystemExit("voice: invalid configuration (model paths?)")
    tts = sherpa_onnx.OfflineTts(config)
    return tts, int((time.monotonic() - start) * 1000)


TTS, LOAD_MS = load()
MODEL = os.path.basename(MODEL_DIR)


PEAK_TARGET = 0.84
GAIN_MAX = 4.0


def say(text):
    start = time.monotonic()
    with LOCK:
        audio = TTS.generate(text, sid=SID, speed=1.0)
    if not audio.samples:
        raise RuntimeError("voice: no sound produced")
    name = "speech-%s-%06d.wav" % (
        time.strftime("%Y%m%d-%H%M%S"),
        time.time_ns() // 1000 % 1000000,
    )
    path = os.path.join(AUDIO_DIR, name)
    pcm = array("h", [int(max(-1.0, min(1.0, s)) * 32767.0) for s in audio.samples])
    peak = 0
    for v in pcm:
        if v < 0:
            v = -v
        if v > peak:
            peak = v
    if peak > 0:
        gain = (PEAK_TARGET * 32767.0) / peak
        if gain > GAIN_MAX:
            gain = GAIN_MAX
        if gain > 1.0:
            pcm = array("h", [int(max(-32768, min(32767, round(v * gain)))) for v in pcm])
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(audio.sample_rate)
        f.writeframes(pcm.tobytes())
    duration = len(pcm) / float(audio.sample_rate)
    return os.path.relpath(path, ROOT), os.path.getsize(path), duration, int((time.monotonic() - start) * 1000)


class Service(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def answer(self, code, payload, content_type="application/json; charset=utf-8"):
        data = payload.encode("utf-8") if isinstance(payload, str) else payload
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.split("?")[0] == "/health":
            self.answer(200, json.dumps(
                {"ok": True, "load_ms": LOAD_MS, "voice_sid": SID, "model": MODEL}))
        else:
            self.answer(404, json.dumps({"error": "route inconnue"}))

    def do_POST(self):
        if self.path.split("?")[0] != "/say":
            self.answer(404, json.dumps({"error": "route inconnue"}))
            return
        try:
            size = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(size) or b"{}")
            text = (payload.get("text") or "").strip()
        except Exception as e:
            self.answer(400, json.dumps({"error": "corps illisible : %s" % e}))
            return
        if not text:
            self.answer(400, json.dumps({"error": "texte vide"}))
            return
        try:
            rel_path, size_bytes, duration, ms = say(text)
        except Exception as e:
            self.answer(500, json.dumps({"error": "synthese : %s" % e}))
            return
        line = "speech : %s (%d Ko, %f s)" % (rel_path, size_bytes // 1024, duration)
        print(line, flush=True)
        self.answer(200, line, "text/plain; charset=utf-8")


if __name__ == "__main__":
    os.makedirs(AUDIO_DIR, exist_ok=True)
    try:
        SERVER = ThreadingHTTPServer(("127.0.0.1", PORT), Service)
    except OSError as e:
        raise SystemExit("voice: port %d is already taken (%s) - no voice was announced"
                         % (PORT, e))
    print("voix prete : %s, voix %d, sur 127.0.0.1:%d, chargee en %d ms"
          % (MODEL, SID, PORT, LOAD_MS), flush=True)
    SERVER.serve_forever()
