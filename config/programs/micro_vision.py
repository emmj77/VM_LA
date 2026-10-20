# french in code is forbidden
import os
import sys

import cv2
import numpy as np
import onnxruntime as ort

import laconf

GGUF = os.path.expanduser(laconf.text("llama", "gguf", "~/LLM_GGUF"))
COCO = ("person bicycle car motorcycle airplane bus train truck boat traffic_light fire_hydrant "
        "stop_sign parking_meter bench bird cat dog horse sheep cow elephant bear zebra giraffe "
        "backpack umbrella handbag tie suitcase frisbee skis snowboard sports_ball kite "
        "baseball_bat baseball_glove skateboard surfboard tennis_racket bottle wine_glass cup fork "
        "knife spoon bowl banana apple sandwich orange broccoli carrot hot_dog pizza donut cake "
        "chair couch potted_plant bed dining_table toilet tv laptop mouse remote keyboard "
        "cell_phone microwave oven toaster sink refrigerator book clock vase scissors teddy_bear "
        "hair_drier toothbrush").split()


def t(key, default):
    return laconf.message(key, default)


def reject(msg):
    sys.stderr.write(msg + "\n")
    raise SystemExit(1)


def model(name):
    import contextlib

    p = os.path.join(GGUF, name)
    if not os.path.isfile(p):
        reject(t("vision_model", "refused: the vision model is missing from the machine (%s)") % p)
    with open(os.devnull, "w") as empty, contextlib.redirect_stderr(empty):
        save = os.dup(2)
        os.dup2(empty.fileno(), 2)
        try:
            return ort.InferenceSession(p, providers=["CPUExecutionProvider"])
        finally:
            os.dup2(save, 2)
            os.close(save)


def image(path):
    im = cv2.imread(path)
    if im is None:
        reject(t("vision_image", "refused: the image could not be read (%s)") % path)
    return im


def tensor(im, hw):
    x = cv2.resize(im, hw, interpolation=cv2.INTER_AREA)
    x = cv2.cvtColor(x, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    x = (x - np.array([0.485, 0.456, 0.406], np.float32)) / np.array([0.229, 0.224, 0.225], np.float32)
    return np.ascontiguousarray(x.transpose(2, 0, 1)[None])


def output_path(request, prefix, source):
    path = request or os.path.join(os.path.dirname(source), prefix + os.path.basename(source))
    folder = os.path.dirname(path)
    if not os.path.isdir(folder):
        reject(t("vision_out", "refused: the output folder does not exist (%s)") % folder)
    return path


def boxes(path, threshold=0.25):
    s = model("yolo11n.onnx")
    im = image(path)
    h0, w0 = im.shape[:2]
    r = min(640.0 / w0, 640.0 / h0)
    thumb = cv2.resize(im, (int(w0 * r), int(h0 * r)))
    canvas = np.full((640, 640, 3), 114, np.uint8)
    canvas[: thumb.shape[0], : thumb.shape[1]] = thumb
    blob = cv2.dnn.blobFromImage(canvas, 1 / 255.0, (640, 640), swapRB=True)
    o = s.run(None, {s.get_inputs()[0].name: blob})[0][0].T
    conf = o[:, 4:].max(1)
    kept = o[conf > threshold]
    if not len(kept):
        print(t("vision_empty", "no object found (threshold %.2f ; 80 COCO classes)") % threshold)
        return
    idx = cv2.dnn.NMSBoxes([[b[0] - b[2] / 2, b[1] - b[3] / 2, b[2], b[3]] for b in kept],
                           [float(b[4:].max()) for b in kept], threshold, 0.45)
    for i in np.array(idx).flatten():
        b = kept[i]
        c = int(b[4:].argmax())
        print("%s %.2f %d %d %d %d" % (COCO[c] if c < len(COCO) else str(c), float(b[4:].max()),
                                      round(b[0] - b[2] / 2), round(b[1] - b[3] / 2),
                                      round(b[2]), round(b[3])))


def matte(path, destination):
    s = model("u2netp.onnx")
    im = image(path)
    o = s.run(None, {s.get_inputs()[0].name: tensor(im, (320, 320))})[0][0][0]
    o = (o - o.min()) / (o.max() - o.min() + 1e-8)
    alpha = cv2.resize(o, (im.shape[1], im.shape[0]))
    path = output_path(destination, "matte_", path)
    cv2.imwrite(path, (alpha * 255).astype(np.uint8))
    print("%s %.1f" % (path, float((alpha > 0.5).mean() * 100)))


def depth(path, destination):
    s = model("depth-anything-v2-small.onnx")
    im = image(path)
    o = s.run(None, {s.get_inputs()[0].name: tensor(im, (518, 518))})[0][0]
    spread = float(o.max() - o.min())
    o = (o - o.min()) / (o.max() - o.min() + 1e-8)
    path = output_path(destination, "depth_", path)
    cv2.imwrite(path, (o * 255).astype(np.uint8))
    print("%s %.3f" % (path, spread))


def inpaint(path, args, destination):
    if len(args) < 4:
        reject(t("vision_bounds", "refused: inpaint wants four bounds: x y width height"))
    try:
        x, y, w, h = [int(v) for v in args[:4]]
    except ValueError:
        reject(t("vision_int", "refused: the bounds of inpaint are integers (x y width height)"))
    if w <= 0 or h <= 0:
        reject(t("vision_positive", "refused: a zone to repair needs a positive width and height"))
    s = model("lama-inpaint.onnx")
    im = image(path)
    h0, w0 = im.shape[:2]
    thumb = cv2.resize(im, (512, 512))
    kx, ky = 512.0 / w0, 512.0 / h0
    mask = np.zeros((512, 512), np.float32)
    mask[max(0, int(y * ky)):min(512, int((y + h) * ky)), max(0, int(x * kx)):min(512, int((x + w) * kx))] = 1.0
    if mask.sum() == 0:
        reject(t("vision_zone", "refused: the zone to repair falls outside the image (%d %d %d %d)") % (x, y, w, h))
    plane = (thumb[:, :, ::-1].astype(np.float32) / 255.0).transpose(2, 0, 1)[None]
    o = s.run(None, {"image": plane, "mask": mask[None, None]})[0][0]
    zone = (np.clip(o.transpose(1, 2, 0), 0, 1) * 255).astype(np.uint8)[:, :, ::-1]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(w0, x + w), min(h0, y + h)
    repaired = im.copy()
    repaired[y0:y1, x0:x1] = cv2.resize(zone, (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA)
    path = output_path(destination, "repaired_", path)
    cv2.imwrite(path, repaired)
    print("%s %d %d" % (path, repaired.shape[1], repaired.shape[0]))


def main():
    if len(sys.argv) < 3:
        reject(t("vision_usage", "usage: micro_vision.py boxes|matte|depth|inpaint <image> [bounds] [out]"))
    mode, path = sys.argv[1], sys.argv[2]
    left = sys.argv[3:]
    if mode == "boxes":
        try:
            threshold = float(left[0])
        except (IndexError, ValueError):
            threshold = 0.25
        boxes(path, threshold)
    elif mode == "matte":
        matte(path, left[0] if left else "")
    elif mode == "depth":
        depth(path, left[0] if left else "")
    elif mode == "inpaint":
        inpaint(path, left, left[4] if len(left) > 4 else "")
    else:
        reject(t("vision_mode", "refused: unknown mode (%s) ; boxes, matte, depth or inpaint") % mode)


if __name__ == "__main__":
    main()
