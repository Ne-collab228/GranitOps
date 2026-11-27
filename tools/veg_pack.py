"""Сборка атласов растительности из снимков tools/_veg_bake (после tools/bake_veg.gd).

python -I tools/veg_pack.py <проект>

Делает: уменьшение с суперсэмплинга (в premultiplied-альфе), обрезку видов по альфе, раскладку в атласы,
полосу коры (assets/tex/bark_brown_02, оттенок подогнан под запечённый ствол), дилатацию цвета/нормалей
под прозрачными местами (нет каймы на мипмапах), .import (VRAM-сжатие + мипмапы, *_nor — как карта нормалей),
и scripts/veg_data.gd с размерами карточек в метрах и UV.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

PROJECT = sys.argv[1]
BAKE = os.path.join(PROJECT, "tools", "_veg_bake")
OUT = os.path.join(PROJECT, "assets", "veg")
TEX = os.path.join(PROJECT, "assets", "tex")

# раскладка атласов деревьев: размер и ячейки [x, y, w, h] в пикселях
TREES = {
    "broadleaf": {"atlas": [2048, 2048], "v0": [0, 0, 1024, 1024], "v60": [1024, 0, 1024, 1024],
                  "v120": [0, 1024, 1024, 1024], "top": [1024, 1024, 896, 1024], "bark": [1920, 1024, 128, 1024]},
    "dead": {"atlas": [2048, 1536], "v0": [0, 0, 1024, 768], "v60": [1024, 0, 1024, 768],
             "v120": [0, 768, 1024, 768], "bark": [1024, 768, 128, 768]},
    "searsia": {"atlas": [1024, 1024], "v0": [0, 0, 512, 512], "v60": [512, 0, 512, 512],
                "v120": [0, 512, 512, 512], "top": [512, 512, 512, 512]},
    "fir": {"atlas": [2048, 1024], "v0": [0, 0, 640, 1024], "v60": [640, 0, 640, 1024],
            "v120": [1280, 0, 640, 1024], "bark": [1920, 0, 128, 1024]},
}
SHRUBS = ["shrub_02", "shrub_03", "rooibos", "fern", "lucida"]
SHRUB_W = 2048
SHRUB_MAX = 512
SHRUB_PPM = 400.0

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=%d
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0


def reduce(img, k):
    """Уменьшение в k раз с усреднением в premultiplied-альфе."""
    h, w = img.shape[:2]
    h2, w2 = h // k, w // k
    img = img[:h2 * k, :w2 * k]
    a = img[..., 3:4]
    pm = np.concatenate([img[..., :3] * a, a], axis=2)
    pm = pm.reshape(h2, k, w2, k, 4).mean(axis=(1, 3))
    return unpremult(pm)


def unpremult(pm):
    a = pm[..., 3:4]
    rgb = np.where(a > 1e-4, pm[..., :3] / np.maximum(a, 1e-4), 0.0)
    return np.concatenate([np.clip(rgb, 0, 1), a], axis=2)


def resize(img, w, h):
    """Масштаб с LANCZOS в premultiplied-альфе (каналы по отдельности, float)."""
    a = img[..., 3:4]
    pm = np.concatenate([img[..., :3] * a, a], axis=2)
    out = np.zeros((h, w, 4), np.float32)
    for c in range(4):
        ch = Image.fromarray(pm[..., c].astype(np.float32), "F").resize((w, h), Image.LANCZOS)
        out[..., c] = np.asarray(ch)
    out = np.clip(out, 0, 1)
    return unpremult(out)


def crop_box(a, pad=3):
    ys, xs = np.nonzero(a > 0.02)
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad + 1, a.shape[0])
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad + 1, a.shape[1])
    return x0, y0, x1, y1


def view_img(meta, v):
    """Снимок вида: уменьшение, обрезка; возвращает (col, nor, метры кадра обрезки)."""
    k = meta["ss"]
    col = reduce(load(os.path.join(BAKE, v["file"] + "_col.png")), k)
    nor = load(os.path.join(BAKE, v["file"] + "_nor.png"))
    nor[..., 3] = load(os.path.join(BAKE, v["file"] + "_col.png"))[..., 3]
    nor = reduce(nor, k)
    h, w = col.shape[:2]
    x0, y0, x1, y1 = crop_box(col[..., 3])
    mpx = v["w"] / w  # метров на пиксель
    m = {"x0": v["x0"] + x0 * mpx, "x1": v["x0"] + x1 * mpx}
    if "z0" in v:  # вид сверху: строки идут с севера (−Z) на юг
        m.update({"z0": v["z0"] + y0 * mpx, "z1": v["z0"] + y1 * mpx})
    else:
        top = v["y0"] + v["h"]
        m.update({"y1": top - y0 * mpx, "y0": top - y1 * mpx})
    return col[y0:y1, x0:x1], nor[y0:y1, x0:x1], m


def place(atlas, img, cell, align_bottom=True):
    """Вписать img в ячейку с сохранением пропорций; вернуть UV-прямоугольник [u0, v0, u1, v1]."""
    cx, cy, cw, ch = cell
    h, w = img.shape[:2]
    s = min(cw / w, ch / h)
    nw, nh = max(1, int(round(w * s))), max(1, int(round(h * s)))
    r = resize(img, nw, nh) if (nw, nh) != (w, h) else img
    ox = cx + (cw - nw) // 2
    oy = cy + (ch - nh) if align_bottom else cy
    atlas[oy:oy + nh, ox:ox + nw] = r
    H, W = atlas.shape[:2]
    return [ox / W, oy / H, (ox + nw) / W, (oy + nh) / H]


def dilate(img, thr=0.35, empty=None):
    """Цвет прозрачных пикселей = цвет ближайшего непрозрачного (против каймы на мипмапах)."""
    mask = img[..., 3] > thr
    if not mask.any():
        return img
    dist, (iy, ix) = ndimage.distance_transform_edt(~mask, return_indices=True)
    out = img.copy()
    out[..., :3] = img[iy, ix, :3]
    if empty is not None:
        far = dist > 48
        out[far, :3] = empty
    return out


def bark_strip(cell_wh, tint_target, trunk_r, trunk_h):
    """Кора bark_brown_02 на полосу [окружность x высота], подкрашенная под ствол вида."""
    diff = np.asarray(Image.open(os.path.join(TEX, "bark_brown_02_diff.jpg")).convert("RGB")).astype(np.float32) / 255
    nor = np.asarray(Image.open(os.path.join(TEX, "bark_brown_02_nor.jpg")).convert("RGB")).astype(np.float32) / 255
    tile = 1.2  # метров на текстуру (как в Mats.DEFS["bark"])
    circ = 2 * np.pi * trunk_r
    th, tw = diff.shape[:2]
    pw = max(8, int(circ / tile * tw))
    ph = max(8, int(trunk_h / tile * th))
    ys = np.arange(ph) % th
    xs = np.arange(pw) % tw
    d = diff[ys][:, xs]
    n = nor[ys][:, xs]
    w, h = cell_wh
    d = np.asarray(Image.fromarray((d * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)).astype(np.float32) / 255
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)).astype(np.float32) / 255
    if tint_target is not None:
        k = np.clip(tint_target / np.maximum(d.reshape(-1, 3).mean(0), 1e-3), 0.4, 2.2)
        d = np.clip(d * k, 0, 1)
    one = np.ones((h, w, 1), np.float32)
    return np.concatenate([d, one], 2), np.concatenate([n, one], 2)


def save(name, col, nor):
    col = dilate(col)
    nor = dilate(nor, empty=np.array([0.5, 0.5, 1.0]))
    Image.fromarray((col * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_col.png"), optimize=True)
    h, w = nor.shape[:2]
    nimg = Image.fromarray((nor[..., :3] * 255 + 0.5).astype(np.uint8), "RGB").resize((w // 2, h // 2), Image.LANCZOS)
    nimg.save(os.path.join(OUT, name + "_nor.png"), optimize=True)
    for fn, is_nor in ((name + "_col.png", 0), (name + "_nor.png", 1)):
        with open(os.path.join(OUT, fn + ".import"), "w", newline="\n") as f:
            f.write(IMPORT % (1 if is_nor else 2))


def tree(name, lay):
    meta = json.load(open(os.path.join(BAKE, name + ".json"), encoding="utf-8"))
    W, H = lay["atlas"]
    col = np.zeros((H, W, 4), np.float32)
    nor = np.zeros((H, W, 4), np.float32)
    d = {"kind": "tree", "atlas": [W, H], "height": meta["height"], "radius": meta["radius"],
         "crown_y0": meta["crown_y0"], "crown_y1": meta["crown_y1"], "views": []}
    trunk_col = None
    for v in meta["views"]:
        key = "v%d" % int(v["yaw"])
        c, n, m = view_img(meta, v)
        uv = place(col, c, lay[key])
        place(nor, n, lay[key])
        m.update({"yaw": v["yaw"], "uv": uv})
        d["views"].append(m)
        if key == "v0":
            # цвет ствола: нижние 6% высоты, середина по ширине
            hh, ww = c.shape[:2]
            cx = int((-m["x0"]) / (m["x1"] - m["x0"]) * ww)
            band = c[int(hh * 0.94):, max(cx - ww // 40, 0):cx + ww // 40]
            sel = band[band[..., 3] > 0.8][:, :3]
            if len(sel):
                trunk_col = sel.mean(0)
    if "top" in meta and "top" in lay:
        c, n, m = view_img(meta, meta["top"])
        m.update({"y": meta["top"]["y"], "uv": place(col, c, lay["top"], False)})
        place(nor, n, lay["top"], False)
        d["top"] = m
    if "bark" in lay:
        bx, by, bw, bh = lay["bark"]
        tr = TRUNK.get(name, [0.3, 3.0])
        bc, bn = bark_strip((bw, bh), trunk_col, tr[0], tr[1])
        col[by:by + bh, bx:bx + bw] = bc
        nor[by:by + bh, bx:bx + bw] = bn
        d["bark"] = [bx / W, by / H, (bx + bw) / W, (by + bh) / H]
        d["trunk"] = tr
    save(name, col, nor)
    return d


# ствол-цилиндр: [радиус у земли, высота до развилки], м (по снимкам вида спереди)
TRUNK = {"broadleaf": [0.3, 3.2], "dead": [0.27, 2.8], "fir": [0.2, 4.0]}


def shrubs():
    items = []
    for name in SHRUBS:
        meta = json.load(open(os.path.join(BAKE, name + ".json"), encoding="utf-8"))
        views = [view_img(meta, v) + (v["yaw"],) for v in meta["views"]]
        big = max(max(m["x1"] - m["x0"], m["y1"] - m["y0"]) for _, _, m, _ in views)
        ppm = min(SHRUB_MAX / big, SHRUB_PPM)
        for c, n, m, yaw in views:
            w = max(4, int(round((m["x1"] - m["x0"]) * ppm)))
            h = max(4, int(round((m["y1"] - m["y0"]) * ppm)))
            items.append((name, yaw, resize(c, w, h), resize(n, w, h), m, meta))
    # полочная укладка по убыванию высоты
    order = sorted(range(len(items)), key=lambda i: -items[i][2].shape[0])
    x = y = shelf = 0
    pos = {}
    for i in order:
        h, w = items[i][2].shape[:2]
        if x + w > SHRUB_W:
            x, y, shelf = 0, y + shelf + 2, 0
        pos[i] = (x, y)
        x += w + 2
        shelf = max(shelf, h)
    H = y + shelf
    H = (H + 63) // 64 * 64
    col = np.zeros((H, SHRUB_W, 4), np.float32)
    nor = np.zeros((H, SHRUB_W, 4), np.float32)
    out = {}
    for i, (name, yaw, c, n, m, meta) in enumerate(items):
        px, py = pos[i]
        h, w = c.shape[:2]
        col[py:py + h, px:px + w] = c
        nor[py:py + h, px:px + w] = n
        m = dict(m)
        m.update({"yaw": yaw, "uv": [px / SHRUB_W, py / H, (px + w) / SHRUB_W, (py + h) / H]})
        o = out.setdefault(name, {"kind": "shrub", "atlas": [SHRUB_W, H], "height": meta["height"],
                                  "radius": meta["radius"], "views": []})
        o["views"].append(m)
    save("shrubs", col, nor)
    return out


def grass():
    meta = json.load(open(os.path.join(BAKE, "grass.json"), encoding="utf-8"))
    cw, ch = meta["cell"]
    W, H = cw * 2, ch * 4
    col = np.zeros((H, W, 4), np.float32)
    nor = np.zeros((H, W, 4), np.float32)
    for fr in meta["frames"]:
        c = reduce(load(os.path.join(BAKE, fr["file"] + "_col.png")), meta["ss"])
        n = load(os.path.join(BAKE, fr["file"] + "_nor.png"))
        n[..., 3] = load(os.path.join(BAKE, fr["file"] + "_col.png"))[..., 3]
        n = reduce(n, meta["ss"])
        x, y = fr["col"] * cw, fr["row"] * ch
        # отступ 2 px сверху и по бокам, чтобы соседние кадры не просвечивали на мипмапах
        c[:2] = 0
        c[:, :2] = 0
        c[:, -2:] = 0
        col[y:y + ch, x:x + cw] = c
        nor[y:y + ch, x:x + cw] = n
    save("grass", col, nor)
    return {"kind": "grass", "atlas": [W, H], "w": meta["w"], "h": meta["h"], "cols": 2, "rows": 4,
            "frames": {fr["file"][6:]: [fr["col"], fr["row"]] for fr in meta["frames"]}}


def to_gd(v, ind=0):
    p = "\t" * ind
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = ",\n".join(p + "\t" + json.dumps(k) + ": " + to_gd(x, ind + 1) for k, x in v.items())
        return "{\n" + items + ",\n" + p + "}"
    if isinstance(v, list):
        return "[" + ", ".join(to_gd(x, ind) for x in v) + "]"
    if isinstance(v, float):
        return "%.4f" % v
    return json.dumps(v)


def main():
    os.makedirs(OUT, exist_ok=True)
    data = {}
    for name, lay in TREES.items():
        if os.path.exists(os.path.join(BAKE, name + ".json")):
            data[name] = tree(name, lay)
            print("дерево", name)
    data.update(shrubs())
    data["grass"] = grass()
    with open(os.path.join(PROJECT, "scripts", "veg_data.gd"), "w", encoding="utf-8", newline="\n") as f:
        f.write("extends RefCounted\n## Сгенерировано tools/veg_pack.py — не править руками.\n"
                "## Размеры карточек в метрах (x — вправо от оси, y — вверх от земли), UV в атласах assets/veg.\n\n")
        f.write("const DATA := " + to_gd(data) + "\n")
    tot = 0
    for fn in sorted(os.listdir(OUT)):
        if fn.endswith(".png"):
            sz = os.path.getsize(os.path.join(OUT, fn))
            tot += sz
            print("  %-22s %s %6.2f МБ" % (fn, Image.open(os.path.join(OUT, fn)).size, sz / 1e6))
    print("итого %.1f МБ" % (tot / 1e6))


main()
