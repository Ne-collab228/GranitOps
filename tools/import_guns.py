"""Импорт моделей оружия (CC0) из папки staging в проект и генерация текстур детализации.

    python -I tools/import_guns.py <staging> <project>

staging — C:\\Users\\user\\Downloads\\granit_models_staging (собрано агентом, лицензии в CLAUDE.md).
Что делает:
  * копирует нужные стилизованные модели Pichuliru (CC0) в assets/guns/flat/;
  * АКМ (LonesomeDucky, CC0): вынимает текстуры из glb, ужимает 4K -> 1K, пишет glb без картинок;
  * M4A1 (nisu, CC0): glb + текстуры 2K -> 1K, Metallic/Roughness собираются в ORM;
  * генерирует бесшовные текстуры детализации (царапины, зерно, пятна) для стилизованных моделей;
  * пишет .import для всех текстур (VRAM-сжатие + мипмапы; карты нормалей помечены).
"""
import io
import json
import os
import shutil
import struct
import sys

import numpy as np
from PIL import Image

STAGING = sys.argv[1]
PROJECT = sys.argv[2]
OGA = os.path.join(STAGING, "opengameart")
DST = os.path.join(PROJECT, "assets", "guns")
os.makedirs(os.path.join(DST, "flat"), exist_ok=True)

FLAT = {
    os.path.join(OGA, "flat_guns_west_Pichuliru_CC0", "x_flat_guns_west", "Flat Guns West", "GLB"):
        ["SMG_Full_West", "Rifle_Battle_West", "Sniper_Material_West", "Shotgun_Auto_West"],
    os.path.join(OGA, "flat_guns_east_Pichuliru_CC0", "x_flat_guns_east", "Flat Guns East", "GLB"):
        ["Shotgun_Pump_East", "Rifle_Battle_East"],
    os.path.join(OGA, "flat_attachments_Pichuliru_CC0", "x_flat_attachments", "Flat_Attachments", "GLB"):
        ["Suppressor_West", "Foregrip_West", "Foregrip_East", "Laser_West", "RedDot_West", "Reflex_West",
         "Holographic_West", "Magnified_West", "Magnified_East", "Scope_East", "Scope_West"],
}
for folder, names in FLAT.items():
    for n in names:
        shutil.copyfile(os.path.join(folder, n + ".glb"), os.path.join(DST, "flat", n + ".glb"))


def read_glb(path):
    b = open(path, "rb").read()
    assert b[:4] == b"glTF"
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", b[off:off + 4])[0]
    return j, b[off + 8:off + 8 + bl]


def view_bytes(j, binc, vi):
    v = j["bufferViews"][vi]
    o = v.get("byteOffset", 0)
    return binc[o:o + v["byteLength"]]


def write_glb_without_images(j, binc, path):
    """glb без картинок/текстур: в буфере остаются только bufferView, на которые ссылаются accessors."""
    for k in ("images", "textures", "samplers"):
        j.pop(k, None)
    for m in j.get("materials", []):
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(k, None)
        pbr = m.get("pbrMetallicRoughness", {})
        pbr.pop("baseColorTexture", None)
        pbr.pop("metallicRoughnessTexture", None)
    used = sorted({a["bufferView"] for a in j["accessors"] if "bufferView" in a})
    remap = {}
    out = bytearray()
    views = []
    for old in used:
        v = dict(j["bufferViews"][old])
        data = view_bytes(j, binc, old)
        while len(out) % 4:
            out.append(0)
        v["byteOffset"] = len(out)
        v["byteLength"] = len(data)
        v["buffer"] = 0
        out += data
        remap[old] = len(views)
        views.append(v)
    for a in j["accessors"]:
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
    j["bufferViews"] = views
    while len(out) % 4:
        out.append(0)
    j["buffers"] = [{"byteLength": len(out)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, total))
        f.write(struct.pack("<I", len(js)) + b"JSON" + js)
        f.write(struct.pack("<I", len(out)) + b"BIN\x00" + bytes(out))


def save_tex(img, path, size=1024):
    img = img.resize((size, size), Image.LANCZOS)
    if path.endswith(".jpg"):
        img.convert("RGB").save(path, quality=90)
    else:
        img.save(path, optimize=True)


# ---- АКМ
akm_dir = os.path.join(DST, "akm")
os.makedirs(akm_dir, exist_ok=True)
j, binc = read_glb(os.path.join(STAGING, "converted", "akm_LonesomeDucky.glb"))
for im in j["images"]:
    pic = Image.open(io.BytesIO(view_bytes(j, binc, im["bufferView"])))
    name = im["name"]
    if "Normal" in name:
        save_tex(pic.convert("RGB"), os.path.join(akm_dir, "akm_nor.png"))
    elif "Roughness" in name:
        save_tex(pic.convert("RGB"), os.path.join(akm_dir, "akm_orm.png"))
    else:
        save_tex(pic, os.path.join(akm_dir, "akm_alb.jpg"))
write_glb_without_images(j, binc, os.path.join(akm_dir, "akm.glb"))

# ---- M4A1
m4_dir = os.path.join(DST, "m4")
os.makedirs(m4_dir, exist_ok=True)
shutil.copyfile(os.path.join(STAGING, "converted", "m4a1_nisu.glb"), os.path.join(m4_dir, "m4.glb"))
src = os.path.join(OGA, "m4a1_nisu_CC0", "x", "M4A1")
save_tex(Image.open(os.path.join(src, "M4A1_Base_Color.png")), os.path.join(m4_dir, "m4_alb.jpg"))
save_tex(Image.open(os.path.join(src, "M4A1_Normal.png")).convert("RGB"), os.path.join(m4_dir, "m4_nor.png"))
rough = Image.open(os.path.join(src, "M4A1_Roughness.png")).convert("L").resize((1024, 1024), Image.LANCZOS)
metal = Image.open(os.path.join(src, "M4A1_Metallic.png")).convert("L").resize((1024, 1024), Image.LANCZOS)
ao = Image.new("L", (1024, 1024), 255)
Image.merge("RGB", (ao, rough, metal)).save(os.path.join(m4_dir, "m4_orm.png"), optimize=True)

# ---- текстуры детализации для стилизованных моделей (бесшовные 512x512)
rng = np.random.default_rng(7)
S = 512


def tile_noise(scale, octaves=4):
    out = np.zeros((S, S))
    amp = 1.0
    for o in range(octaves):
        n = int(scale * 2 ** o)
        g = rng.standard_normal((n, n))
        img = Image.fromarray(((g - g.min()) / (g.max() - g.min()) * 255).astype(np.uint8))
        # повторяем решётку 3x3 и вырезаем центр — интерполяция без шва
        big = Image.new("L", (n * 3, n * 3))
        for yy in range(3):
            for xx in range(3):
                big.paste(img, (xx * n, yy * n))
        big = big.resize((S * 3, S * 3), Image.BICUBIC).crop((S, S, S * 2, S * 2))
        out += (np.asarray(big, np.float64) / 255.0 - 0.5) * amp
        amp *= 0.5
    return out


def scratches(count, length, width):
    img = np.zeros((S, S))
    for _ in range(count):
        x, y = rng.uniform(0, S, 2)
        a = rng.uniform(0, np.pi) if rng.random() < 0.4 else rng.normal(0.15, 0.25)
        ln = rng.uniform(length * 0.3, length)
        steps = int(ln)
        for t in range(steps):
            px = int(x + np.cos(a) * t) % S
            py = int(y + np.sin(a) * t) % S
            img[py, px] = max(img[py, px], rng.uniform(0.4, 1.0))
            if width > 1:
                img[(py + 1) % S, px] = max(img[(py + 1) % S, px], 0.4)
    return img


blot = tile_noise(4, 4)
grain = tile_noise(64, 2)
scr = scratches(260, 90, 1)
fine = scratches(900, 18, 1)
# альбедо-множитель: пятна потёртости и светлые царапины
alb = 0.92 + blot * 0.14 + grain * 0.04 + scr * 0.1 + fine * 0.05
alb = np.clip(alb, 0.7, 1.08) / 1.08
Image.fromarray((alb * 255).astype(np.uint8)).convert("RGB").save(os.path.join(DST, "detail_alb.png"))
# шероховатость: царапины и стёртые места глаже (блестят)
rgh = 0.66 + blot * 0.22 + grain * 0.1 - scr * 0.28 - fine * 0.12
rgh = np.clip(rgh, 0.12, 1.0)
Image.fromarray((rgh * 255).astype(np.uint8)).convert("RGB").save(os.path.join(DST, "detail_rough.png"))
# нормали: мелкое зерно (дробеструй/пластик) + канавки царапин
h = grain * 0.5 + tile_noise(128, 1) * 0.4 - scr * 0.35 - fine * 0.15
dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 1.1
dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 1.1
nz = np.ones_like(h)
ln = np.sqrt(dx * dx + dy * dy + nz)
nor = np.stack([-dx / ln, -dy / ln, nz / ln], -1) * 0.5 + 0.5
Image.fromarray((nor * 255).astype(np.uint8)).save(os.path.join(DST, "detail_nor.png"))

# ---- .import для текстур
TEX_IMPORT = """[remap]

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
n = 0
for root, _, files in os.walk(DST):
    for fn in files:
        if fn.lower().endswith((".png", ".jpg")):
            with open(os.path.join(root, fn) + ".import", "w", newline="\n") as f:
                f.write(TEX_IMPORT % (1 if "_nor" in fn else 2))
            n += 1
total = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(DST) for f in fs)
print("ok, textures:", n, "size MB: %.1f" % (total / 1048576))
