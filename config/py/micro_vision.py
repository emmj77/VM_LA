#!/usr/bin/env python3
"""micro_vision.py - LES YEUX DU CPU. Un porteur, quatre gestes : boxes, matte, depth, inpaint.

POURQUOI UN SEUL FICHIER POUR QUATRE GESTES. La loi 454 du canon dit ceci : un MODE ajoute de la
mecanique SANS ajouter de name. Les quatre gestes partagent la meme plomberie (charger une image,
monter un tenseur, ecrire un PNG) et le meme moteur (onnxruntime, CPU) ; les separer en quatre
fichiers recopierait quatre fois la meme chose. Ce qui separe les gestes, c'est la LIGNE DE LA TABLE,
jamais le porteur : chacun garde son nom, sa famille et sa description.

CE QU'IL NE FAIT PAS. Il ne joint rien (aucun reseau : les modeles sont sur le disque), il n'ecrit
que ce qu'on lui nomme, et sur un modele absent il REFUSE en le nommant (loi 502 : un tool silencieux
n'existe pas).

LES MODELES (mesures du 17/10/2026, cette machine) :
  boxes   yolo11n.onnx                  10,7 Mo   60-71 ms   COCO 80 classes, 640x640
  matte   u2netp.onnx                    4,5 Mo   220-241 ms premier plan, 320x320
  depth   depth-anything-v2-small.onnx  96,7 Mo  519-588 ms relief relatif, 518x518
  inpaint lama-inpaint.onnx             90,4 Mo  2 846 ms   zone a reparer, 512x512 fixe, LaMa

USAGE
  micro_vision.py boxes   <image>
  micro_vision.py matte   <image> [sortie.png]
  micro_vision.py depth   <image> [sortie.png]
  micro_vision.py inpaint <image> <x> <y> <largeur> <hauteur> [sortie.png]

SORTIE
  boxes    une ligne par objet : classe confiance x y largeur hauteur
  matte    le CHEMIN du PNG ecrit (loi 603 : un tool qui ecrit un fichier rend le chemin)
  depth    le CHEMIN du PNG ecrit
  inpaint  le CHEMIN du PNG ecrit
"""
import os
import sys

import cv2
import numpy as np
import onnxruntime as ort

GGUF = os.environ.get("LA_GGUF_DIR", os.path.expanduser("~/LLM_GGUF"))
COCO = ("person bicycle car motorcycle airplane bus train truck boat traffic_light fire_hydrant "
        "stop_sign parking_meter bench bird cat dog horse sheep cow elephant bear zebra giraffe "
        "backpack umbrella handbag tie suitcase frisbee skis snowboard sports_ball kite "
        "baseball_bat baseball_glove skateboard surfboard tennis_racket bottle wine_glass cup fork "
        "knife spoon bowl banana apple sandwich orange broccoli carrot hot_dog pizza donut cake "
        "chair couch potted_plant bed dining_table toilet tv laptop mouse remote keyboard "
        "cell_phone microwave oven toaster sink refrigerator book clock vase scissors teddy_bear "
        "hair_drier toothbrush").split()


def refuse(msg):
    """Un refus SE NOMME et sort en 1 : c'est le engine qui forme le JSON."""
    sys.stderr.write("refuse : " + msg + "\n")
    raise SystemExit(1)


def modele(nom):
    """Le bruit du ONNX sur la sortie d'erreur est COUPE : elle sert au refus, pas au bavardage.
    Le build Debian d'onnxruntime recopie le registre des schemas sur fd 2 (100 Ko par appel) ;
    la sortie d'erreur d'un tool est le canal du REFUS (loi 502), elle reste pour nous."""
    import contextlib

    p = os.path.join(GGUF, nom)
    if not os.path.isfile(p):
        refuse("le modele est absent de la machine (%s)" % p)
    with open(os.devnull, "w") as vide, contextlib.redirect_stderr(vide):
        sauve = os.dup(2)
        os.dup2(vide.fileno(), 2)
        try:
            return ort.InferenceSession(p, providers=["CPUExecutionProvider"])
        finally:
            os.dup2(sauve, 2)
            os.close(sauve)


def image(chemin):
    im = cv2.imread(chemin)
    if im is None:
        refuse("l image n a pas pu etre lue (%s)" % chemin)
    return im


def tenseur(im, hw):
    x = cv2.resize(im, hw, interpolation=cv2.INTER_AREA)
    x = cv2.cvtColor(x, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    x = (x - np.array([0.485, 0.456, 0.406], np.float32)) / np.array([0.229, 0.224, 0.225], np.float32)
    return np.ascontiguousarray(x.transpose(2, 0, 1)[None])


def sortie(demande, defaut):
    chemin = demande or defaut
    dossier = os.path.dirname(chemin)
    if not os.path.isdir(dossier):
        refuse("le dossier de sortie n existe pas (%s)" % dossier)
    return chemin


# ------------------------------------------------------------------ boxes
def boxes(chemin, seuil=0.25):
    s = modele("yolo11n.onnx")
    im = image(chemin)
    h0, w0 = im.shape[:2]
    r = min(640.0 / w0, 640.0 / h0)
    petit = cv2.resize(im, (int(w0 * r), int(h0 * r)))
    toile = np.full((640, 640, 3), 114, np.uint8)
    toile[: petit.shape[0], : petit.shape[1]] = petit
    blob = cv2.dnn.blobFromImage(toile, 1 / 255.0, (640, 640), swapRB=True)
    o = s.run(None, {s.get_inputs()[0].name: blob})[0][0].T
    conf = o[:, 4:].max(1)
    garde = o[conf > seuil]
    if not len(garde):
        print("aucun objet trouve (seuil %.2f ; 80 classes COCO, aucun fond ni case)" % seuil)
        return
    idx = cv2.dnn.NMSBoxes([[b[0] - b[2] / 2, b[1] - b[3] / 2, b[2], b[3]] for b in garde],
                           [float(b[4:].max()) for b in garde], seuil, 0.45)
    for i in np.array(idx).flatten():
        b = garde[i]
        c = int(b[4:].argmax())
        print("%s %.2f %d %d %d %d" % (COCO[c] if c < len(COCO) else str(c), float(b[4:].max()),
                                      round(b[0] - b[2] / 2), round(b[1] - b[3] / 2),
                                      round(b[2]), round(b[3])))


# ------------------------------------------------------------------ matte
def matte(chemin, destination):
    s = modele("u2netp.onnx")
    im = image(chemin)
    o = s.run(None, {s.get_inputs()[0].name: tenseur(im, (320, 320))})[0][0][0]
    o = (o - o.min()) / (o.max() - o.min() + 1e-8)
    alpha = cv2.resize(o, (im.shape[1], im.shape[0]))
    chemin = sortie(destination, os.path.join(os.path.dirname(chemin), "matte_" + os.path.basename(chemin)))
    cv2.imwrite(chemin, (alpha * 255).astype(np.uint8))
    print("%s %.1f" % (chemin, float((alpha > 0.5).mean() * 100)))


# ------------------------------------------------------------------ depth
def depth(chemin, destination):
    s = modele("depth-anything-v2-small.onnx")
    im = image(chemin)
    o = s.run(None, {s.get_inputs()[0].name: tenseur(im, (518, 518))})[0][0]
    o = (o - o.min()) / (o.max() - o.min() + 1e-8)
    chemin = sortie(destination, os.path.join(os.path.dirname(chemin), "depth_" + os.path.basename(chemin)))
    cv2.imwrite(chemin, (o * 255).astype(np.uint8))
    print("%s %.1f" % (chemin, float(o.max() * 255 - o.min() * 255)))


# ------------------------------------------------------------------ inpaint
def inpaint(chemin, args, destination):
    if len(args) < 4:
        refuse("inpaint veut quatre bornes : x y largeur hauteur")
    try:
        x, y, w, h = [int(v) for v in args[:4]]
    except ValueError:
        refuse("les bornes d inpaint sont des entiers (x y largeur hauteur)")
    if w <= 0 or h <= 0:
        refuse("une zone a reparer a une largeur et une hauteur positives")
    s = modele("lama-inpaint.onnx")
    im = image(chemin)
    h0, w0 = im.shape[:2]
    petit = cv2.resize(im, (512, 512))
    kx, ky = 512.0 / w0, 512.0 / h0
    masque = np.zeros((512, 512), np.float32)
    masque[max(0, int(y * ky)):min(512, int((y + h) * ky)), max(0, int(x * kx)):min(512, int((x + w) * kx))] = 1.0
    if masque.sum() == 0:
        refuse("la zone a reparer tombe hors de l image (%d %d %d %d)" % (x, y, w, h))
    entree = (petit[:, :, ::-1].astype(np.float32) / 255.0).transpose(2, 0, 1)[None]
    o = s.run(None, {"image": entree, "mask": masque[None, None]})[0][0]
    repare = (np.clip(o.transpose(1, 2, 0), 0, 1) * 255).astype(np.uint8)[:, :, ::-1]
    chemin = sortie(destination, os.path.join(os.path.dirname(chemin), "repare_" + os.path.basename(chemin)))
    cv2.imwrite(chemin, repare)
    print("%s %d %d" % (chemin, repare.shape[1], repare.shape[0]))


def main():
    if len(sys.argv) < 3:
        refuse("usage : micro_vision.py boxes|matte|depth|inpaint <image> [bornes] [sortie]")
    geste, chemin = sys.argv[1], sys.argv[2]
    reste = sys.argv[3:]
    if geste == "boxes":
        try:
            seuil = float(reste[0])
        except (IndexError, ValueError):
            seuil = 0.25
        boxes(chemin, seuil)
    elif geste == "matte":
        matte(chemin, reste[0] if reste else None)
    elif geste == "depth":
        depth(chemin, reste[0] if reste else None)
    elif geste == "inpaint":
        inpaint(chemin, reste, reste[4] if len(reste) > 4 else None)
    else:
        refuse("geste inconnu (%s) ; boxes, matte, depth ou inpaint" % geste)


main()
