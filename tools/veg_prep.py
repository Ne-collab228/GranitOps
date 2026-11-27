"""Подготовка исходников растительности к запеканию (только чтение staging как данных).

python -I tools/veg_prep.py <staging> <проект>

Копирует нужные glTF Poly Haven в tools/_veg_src/<имя>/ (там .gdignore — редактор их не импортирует,
в APK не попадают): альбедо + альфа склеиваются в один RGBA PNG (≤1024), карты нормалей/ORM из glTF
убираются (запекание использует только цвет и геометрию). Альфа: отдельный файл *_alpha_*.png, иначе —
ключ по чёрному фону для материалов BLEND/MASK. Атласы травинок ambientCG — RGBA PNG + прямоугольники
отдельных травинок (blades.json) для процедурных пучков.
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

STAGING = sys.argv[1]
PROJECT = sys.argv[2]
OUT = os.path.join(PROJECT, "tools", "_veg_src")

MODELS = [
    "jacaranda_tree", "searsia_burchellii", "searsia_lucida", "fir_sapling_medium",
    "shrub_02", "shrub_03", "wild_rooibos_bush", "fern_02", "grass_medium_02",
    "flower_ursinia", "flower_gazania", "dry_branches_medium_01",
]
BLADES = ["Foliage001", "Foliage002", "Foliage003", "Foliage004", "Foliage006", "Foliage007"]


def load_alpha(path):
    im = Image.open(path)
    a = np.array(im)
    if a.ndim == 3:
        a = a[..., 0]
    a = a.astype(np.float32)
    if a.max() > 255:
        a /= 257.0
    return a


def prep_model(name):
    src = os.path.join(STAGING, name)
    gl = [f for f in os.listdir(src) if f.endswith(".gltf")][0]
    g = json.load(open(os.path.join(src, gl), encoding="utf-8"))
    dst = os.path.join(OUT, name)
    os.makedirs(os.path.join(dst, "textures"), exist_ok=True)
    # какие изображения — цвет, и нужен ли им ключ по чёрному
    color_imgs = {}
    for m in g.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        if "baseColorTexture" not in pbr:
            continue
        src_img = g["textures"][pbr["baseColorTexture"]["index"]]["source"]
        cut = m.get("alphaMode", "OPAQUE") in ("BLEND", "MASK")
        color_imgs[src_img] = color_imgs.get(src_img, False) or cut
        # убрать лишние карты: запекание их не использует
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(k, None)
        pbr.pop("metallicRoughnessTexture", None)
        m.pop("extensions", None)
    new_uri = {}
    for idx, cut in color_imgs.items():
        uri = g["images"][idx]["uri"]
        p = os.path.join(src, uri.replace("%20", " "))
        im = Image.open(p).convert("RGB")
        rgb = np.array(im).astype(np.float32)
        ap = p.replace("_diff_", "_alpha_").rsplit(".", 1)[0] + ".png"
        if os.path.exists(ap):
            a = load_alpha(ap)
            kind = "файл альфы"
        elif cut:
            mx = rgb.max(axis=2)
            a = np.clip((mx - 6.0) / 14.0, 0, 1) * 255.0
            kind = "ключ по чёрному"
        else:
            a = np.full(rgb.shape[:2], 255.0, np.float32)
            kind = "непрозрачный"
        rgba = np.dstack([rgb, a]).clip(0, 255).astype(np.uint8)
        out = Image.fromarray(rgba, "RGBA")
        if out.width > 1024:
            out = out.resize((1024, 1024), Image.LANCZOS)
        fn = "textures/%s_col%d.png" % (name, idx)
        out.save(os.path.join(dst, fn))
        new_uri[idx] = fn
        print("  ", name, uri, "->", fn, kind)
    used = set()
    for t in g.get("textures", []):
        used.add(t["source"])
    for i, img in enumerate(g["images"]):
        img["mimeType"] = "image/png"
        if i in new_uri:
            img["uri"] = new_uri[i]
        else:
            img["uri"] = new_uri[next(iter(new_uri))]  # заглушка вместо удалённых карт
    for b in g["buffers"]:
        bsrc = os.path.join(src, b["uri"])
        bdst = os.path.join(dst, b["uri"])
        if not os.path.exists(bdst) or os.path.getsize(bdst) != os.path.getsize(bsrc):
            shutil.copyfile(bsrc, bdst)
    with open(os.path.join(dst, name + ".gltf"), "w", encoding="utf-8") as f:
        json.dump(g, f)
    shutil.copyfile(os.path.join(src, "SOURCE.txt"), os.path.join(dst, "SOURCE.txt"))


def prep_blades(name):
    src = os.path.join(STAGING, "acg_" + name)
    col = [f for f in os.listdir(src) if f.endswith("_Color.png")][0]
    rgb = np.array(Image.open(os.path.join(src, col)).convert("RGB"))
    a = load_alpha(os.path.join(src, col.replace("_Color", "_Opacity")))
    h, w = a.shape
    lab, n = ndimage.label(a > 40, structure=np.ones((3, 3)))
    rects = []
    for sl in ndimage.find_objects(lab):
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        if (y1 - y0) * (x1 - x0) < 400:
            continue
        rects.append([x0, y0, x1, y1])
    # склеить перекрывающиеся прямоугольники (травинка из нескольких кусков)
    merged = True
    while merged:
        merged = False
        for i in range(len(rects)):
            for j in range(i + 1, len(rects)):
                r, q = rects[i], rects[j]
                if r[0] <= q[2] and q[0] <= r[2] and r[1] <= q[3] and q[1] <= r[3]:
                    rects[i] = [min(r[0], q[0]), min(r[1], q[1]), max(r[2], q[2]), max(r[3], q[3])]
                    rects.pop(j)
                    merged = True
                    break
            if merged:
                break
    # дилатация цвета под прозрачные места, чтобы край травинки не темнел
    mask = a > 128
    _, (iy, ix) = ndimage.distance_transform_edt(~mask, return_indices=True)
    rgb = rgb[iy, ix]
    out = Image.fromarray(np.dstack([rgb, a.clip(0, 255).astype(np.uint8)]), "RGBA")
    out = out.resize((1024, 1024), Image.LANCZOS)
    dst = os.path.join(OUT, "acg")
    os.makedirs(dst, exist_ok=True)
    out.save(os.path.join(dst, name + ".png"))
    shutil.copyfile(os.path.join(src, "SOURCE.txt"), os.path.join(dst, name + "_SOURCE.txt"))
    # прямоугольники в долях; ориентация: вертикальная/горизонтальная травинка
    res = []
    for r in rects:
        res.append([r[0] / w, r[1] / h, r[2] / w, r[3] / h])
    print("  ", name, "травинок:", len(res))
    return res


def main():
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    for m in MODELS:
        prep_model(m)
    blades = {}
    for b in BLADES:
        blades[b] = prep_blades(b)
    with open(os.path.join(OUT, "acg", "blades.json"), "w") as f:
        json.dump(blades, f)


main()
