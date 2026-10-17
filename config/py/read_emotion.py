#!/usr/bin/env python3
"""read_emotion.py - L'HUMEUR DE LA DEMANDE. Un texte sur l'entree standard, l'etat du demandeur
en sortie : les trois etiquettes les plus fortes, avec leur confiance.

CE QUE C'EST. GoEmotions (DistilRoBERTa, 28 etiquettes) quantifie en int8 : 119,6 Mo de modele,
307 Mo de memoire vive au pic, 340 ms de chargement, 50 a 70 ms par texte. Le modele est
MULTI-ETIQUETTE (une sigmoide par etiquette, pas un softmax) : plusieurs etats peuvent tenir
ensemble, donc on rend les TROIS plus forts et pas seulement le premier -- sur un compliment
francais, la premiere est souvent `neutral` et la deuxieme porte le vrai signal.

CE QU'IL NE DIT PAS. L'INTENSITE et LA SINCERITE : `annoyance 0.62` ne dit pas si l'agacement est
leger ou noir, et un modele anglophone lit le francais sans accent -- c'est une BORNE de
l'instrument, jamais un fait sur la personne. Le tool la rend comme telle : une impression.

USAGE
  read_emotion.py < texte          (le texte par l'entree standard)
SORTIE
  une seule ligne : label confiance | label confiance | label confiance
"""
import os
import subprocess
import sys

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

GGUF = os.environ.get("LA_GGUF_DIR", os.path.expanduser("~/LLM_GGUF"))
# L'ORDRE DES ETIQUETTES est celui du modele (id2label de roberta-base-go_emotions, alphabetique) :
# le changer, c'est nommer un etat par un autre. Il vient du depot du modele, jamais d'ici.
LABELS = ["admiration", "amusement", "anger", "annoyance", "approval", "caring", "confusion",
          "curiosity", "desire", "disappointment", "disapproval", "disgust", "embarrassment",
          "excitement", "fear", "gratitude", "grief", "joy", "love", "nervousness", "optimism",
          "pride", "realization", "relief", "remorse", "sadness", "surprise", "neutral"]


def refuse(msg):
    sys.stderr.write("refuse : " + msg + "\n")
    raise SystemExit(1)


def charger():
    """Le vocabulaire et le modele. Le bruit du ONNX sur la sortie d'erreur est coupe : elle sert
    au refus, et le build Debian y recopie tout son registre de schemas."""
    import contextlib

    vocab = os.path.join(GGUF, "goemotions-tokenizer.json")
    modele = os.path.join(GGUF, "goemotions-int8.onnx")
    for p in (vocab, modele):
        if not os.path.isfile(p):
            refuse("le modele de l humeur est absent de la machine (%s)" % p)
    with open(os.devnull, "w") as vide, contextlib.redirect_stderr(vide):
        sauve = os.dup(2)
        os.dup2(vide.fileno(), 2)
        try:
            return Tokenizer.from_file(vocab), ort.InferenceSession(modele, providers=["CPUExecutionProvider"])
        finally:
            os.dup2(sauve, 2)
            os.close(sauve)


def langue(texte):
    """LA PORTE DE LANGUE. Mesure AVANT de charger le modele, et pas apres : sur un texte francais
    le chargement (340 ms, 307 Mo) ne servirait a rien. GoEmotions a appris l'ANGLAIS ; mesure du
    17/10 : reproche francais -> `neutral` 0,90-0,96 ; le meme reproche en anglais -> `annoyance`
    0,79. Un instrument qui ne lit pas la langue SE TAIT (loi 1557) : il devine, ou il refuse."""
    lid = os.path.join(GGUF, "lid.176.ftz")
    if not os.path.isfile(lid):
        refuse("je ne peux pas mesurer la langue du texte (modele absent : %s)" % lid)
    try:
        r = subprocess.run(["fasttext", "predict", lid, "-", "1"], input=texte, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
    except (OSError, subprocess.SubprocessError):
        refuse("je ne peux pas mesurer la langue du texte (fasttext introuvable)")
    vu = r.stdout.strip().splitlines()
    vu = vu[0].replace("__label__", "") if vu else ""
    if vu != "en":
        refuse("je ne lis pas cette langue (fastText voit `%s`) -- mon modele a appris l anglais"
               % (vu or "?"))
    return vu


def main():
    texte = sys.stdin.read().strip()
    if not texte:
        refuse("il n y a pas de texte a lire")
    langue(texte)
    tok, session = charger()
    enc = tok.encode(texte)
    v = session.run(None, {"input_ids": [enc.ids], "attention_mask": [enc.attention_mask]})[0][0]
    p = 1.0 / (1.0 + np.exp(-v))                     # multi-etiquettes : une sigmoide par etiquette
    ordre = np.argsort(p)[::-1][:3]
    print(" | ".join("%s %.2f" % (LABELS[i], float(p[i])) for i in ordre))


main()
