"""Текстура грязи для зданий (assets/gen/grime.png) + .import.
Атлас 256x256: левая половина — подтёки (тёмный верх, полосы вниз), правая — мягкое пятно.
Запуск: python -I tools/gen_bld_tex.py <путь к проекту>"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

PROJECT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = np.random.default_rng(7)
S = 256
H = S // 2

alpha = np.zeros((S, S), np.float32)

# --- подтёки: x 0..127
xs = np.arange(H)
ys = np.arange(S)[:, None] / (S - 1)
cols = np.zeros(H, np.float32)
# сумма узких полос разной длины
length = np.full(H, 0.25, np.float32)
for _ in range(26):
    c = rng.uniform(4, H - 4)
    wdt = rng.uniform(1.5, 6.0)
    ln = rng.uniform(0.3, 1.0)
    prof = np.exp(-((xs - c) / wdt) ** 2)
    length = np.maximum(length, prof * ln)
    cols += prof * rng.uniform(0.25, 0.7)
cols = np.clip(cols, 0, 1)
fade = np.clip(1.0 - ys / np.maximum(length[None, :], 0.05), 0, 1) ** 1.4
top = np.clip(1.0 - ys / 0.18, 0, 1) ** 2 * 0.55
edge = np.clip(np.minimum(xs, H - 1 - xs) / 14.0, 0, 1)[None, :]
streak = np.clip(fade * (0.35 + 0.65 * cols[None, :]) + top, 0, 1) * edge
alpha[:, :H] = streak

# --- пятно: x 128..255
yy, xx = np.mgrid[0:S, 0:H]
cx, cy = H / 2, S / 2
r = np.sqrt(((xx - cx) / (H * 0.48)) ** 2 + ((yy - cy) / (S * 0.48)) ** 2)
noise = rng.random((S // 16, H // 16)).astype(np.float32)
noise = np.array(Image.fromarray((noise * 255).astype(np.uint8)).resize((H, S), Image.BICUBIC), np.float32) / 255
blot = np.clip(1.0 - r + (noise - 0.5) * 0.7, 0, 1) ** 1.5
blot *= np.clip(1.0 - r, 0, 1) * 1.6
alpha[:, H:] = np.clip(blot, 0, 1) * 0.85

a8 = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
a_img = Image.fromarray(a8).filter(ImageFilter.GaussianBlur(0.8))
grain = (rng.random((S, S)) * 40 + 200).astype(np.uint8)
rgb = Image.fromarray(grain).filter(ImageFilter.GaussianBlur(0.6))
img = Image.merge("RGBA", (rgb, rgb, rgb, a_img))
out = os.path.join(PROJECT, "assets", "gen", "grime.png")
img.save(out)

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
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
if not os.path.exists(out + ".import"):
    with open(out + ".import", "w", newline="\n") as f:
        f.write(IMPORT)
print("ok", out)
