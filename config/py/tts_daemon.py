#!/usr/bin/env python3
"""LA - voix permanente : Piper (upmc) charge UNE fois, puis repond a la demande.

LE MODELE RETENU : vits-piper-fr_FR-upmc-medium, le seul modele francais a deux
voix (sid 0 = jessica, sid 1 = pierre). Les deux sont validees par l'humain.

Contrat identique a l'appel one-shot qu'il remplace, donc rien a changer ailleurs :
  - ecrit  <RACINE>/config/audio/speech-AAAAMMJJ-HHMMSS-mmmmmm.wav
  - imprime sur la sortie standard :  speech : config/audio/speech-....wav (123 Ko, 4.735828 s)

Ecoute sur 127.0.0.1:<LA_TTS_PORT> (defaut 8090).
  GET  /health          -> {"ok":true,"load_ms":N,"voice_sid":N,"model":"..."}
  POST /say  {"text": "..."}  -> la ligne "speech : ..." en clair (200) ou une erreur (4xx/5xx)

Lancement (l'environnement vit dans le cache uv, rien n'est installe chez l'utilisateur) :
  uv run --no-project --with sherpa-onnx python3 <ce fichier>
"""
import glob
import json
import os
import threading
import time
import wave
from array import array
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import sherpa_onnx

ROOT = os.environ.get("LA_ROOT", os.path.expanduser("~/Documents/VM_LA"))
# TOUT L AUDIO VIT DANS config/audio/ : ce dossier est purge par audio_purge.sh. La voix ecrit la,
# comme le pont y pose l audio du telephone -- le disque ne se remplit plus en silence.
AUDIO_DIR = os.path.join(ROOT, "config", "audio")
PORT = int(os.environ.get("LA_TTS_PORT", "8090"))
# LA VOIX DANS LE MODELE : 0 = jessica (8/10), 1 = pierre (9/10). Defaut : pierre.
SID = int(os.environ.get("LA_TTS_SID", "1"))
THREADS = int(os.environ.get("LA_TTS_THREADS", "8"))
MODEL_DIR = os.environ.get(
    "LA_TTS_MODEL",
    os.path.expanduser("~/Applications/sherpa-onnx/voix/vits-piper-fr_FR-upmc-medium"),
)

LOCK = threading.Lock()  # une synthese a la fois : le modele n'est pas partageable


def load():
    """Charge la voix en memoire. Renvoie (tts, load_ms)."""
    # LE .onnx SE CHERCHE, IL NE SE DEVINE PAS : changer de voix = changer MODEL_DIR, rien d'autre.
    onnx = sorted(glob.glob(os.path.join(MODEL_DIR, "*.onnx")))
    if not onnx:
        raise SystemExit("voix : aucun modele dans %s" % MODEL_DIR)
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
        raise SystemExit("voix : configuration invalide (chemins du modele ?)")
    tts = sherpa_onnx.OfflineTts(config)
    return tts, int((time.monotonic() - start) * 1000)


TTS, LOAD_MS = load()
MODEL = os.path.basename(MODEL_DIR)


# REGLAGES DE NIVEAU. Mesure a l'origine sur ce moteur : la voix sortait a mean -26 dB / crete
# -10 dB, la ou une voix humaine donne -18,6 / -4,9. Sur un haut-parleur de telephone, elle etait
# presque inaudible. On MONTE donc chaque sortie jusqu a une CRETE CIBLE, avec un gain BORNE.
PEAK_TARGET = 0.84   # crete visee : -1,5 dB sous le maximum, fort mais sans saturation
GAIN_MAX = 4.0       # +12 dB au plus : un murmure ne devient pas du bruit


def say(text):
    """Fabrique le wav, renvoie (chemin relatif, octets, duree_s, ms)."""
    start = time.monotonic()
    with LOCK:
        audio = TTS.generate(text, sid=SID, speed=1.0)
    if not audio.samples:
        raise RuntimeError("voix : aucun son produit")
    name = "speech-%s-%06d.wav" % (
        time.strftime("%Y%m%d-%H%M%S"),
        time.time_ns() // 1000 % 1000000,
    )
    path = os.path.join(AUDIO_DIR, name)
    pcm = array("h", [int(max(-1.0, min(1.0, s)) * 32767.0) for s in audio.samples])
    # LE NIVEAU SE REGLE ICI, AU DERNIER MOMENT : on cherche la crete, et on monte le son
    # jusqu a la crete visee. La dynamique de la phrase est gardee, et rien ne sature puisque
    # la cible reste sous le maximum. Le gain est borne : une sortie deja forte ne bouge pas.
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
    return "config/audio/" + name, os.path.getsize(path), duration, int((time.monotonic() - start) * 1000)


class Service(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass  # silencieux : la sortie standard porte le contrat "speech : ..."

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
    print("voix prete : %s, voix %d, sur 127.0.0.1:%d, chargee en %d ms"
          % (MODEL, SID, PORT, LOAD_MS), flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Service).serve_forever()
