"""Second-pass generated textures: 8-tile soldier atlases, chain-link fence, pine needles. Writes .import for new files."""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

PROJECT = sys.argv[1]
GEN = os.path.join(PROJECT, "assets", "gen")


def fnoise(n, beta=2.0, seed=0):
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.normal(size=(n, n)))
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    rad = np.sqrt(fx * fx + fy * fy)
    rad[0, 0] = 1.0
    f = f / (rad ** (beta / 2.0))
    f[0, 0] = 0
    out = np.real(np.fft.ifft2(f))
    return (out - out.min()) / (out.max() - out.min())


def camo(n, pal, seed, weave=0.28):
    a, b, c = fnoise(n, 2.6, seed), fnoise(n, 2.6, seed + 1), fnoise(n, 2.2, seed + 2)
    img = np.zeros((n, n, 3), np.float32)
    img[:] = pal[0]
    img[a > 0.56] = pal[1]
    img[b > 0.60] = pal[2]
    img[(c > 0.66) & (a < 0.5)] = pal[3]
    img *= (1.0 - weave / 2 + weave * fnoise(n, 0.4, seed + 5))[..., None]
    return img


def flat(n, color, seed, amount=0.2, stripes=0, grain=1.2):
    img = np.zeros((n, n, 3), np.float32)
    img[:] = color
    img *= (1.0 - amount / 2 + amount * fnoise(n, grain, seed))[..., None]
    if stripes:
        for y in range(0, n, stripes):
            img[y:y + 4] *= 0.7
            img[y + 4:y + 6] *= 1.14
        for x in range(0, n, 40):
            img[:, x:x + 2] *= 0.8
    return img


def wood(n, color, seed):
    g = fnoise(n, 2.4, seed)
    rings = 0.5 + 0.5 * np.sin((g * 9.0 + np.linspace(0, 1, n)[None, :] * 3.0) * 6.283)
    img = np.zeros((n, n, 3), np.float32)
    img[:] = color
    img *= (0.72 + 0.4 * rings)[..., None]
    return img


def atlas(name, pal, gear, helmet, strap, seed, skin=(176, 134, 106)):
    n = 256
    top = [camo(n, pal, seed), flat(n, gear, seed + 10, 0.25, 26), flat(n, skin, seed + 20, 0.12), flat(n, (26, 25, 24), seed + 30, 0.3)]
    bot = [camo(n, helmet, seed + 40, 0.15), flat(n, (44, 46, 50), seed + 50, 0.22, 0, 0.6), wood(n, (104, 66, 38), seed + 60), flat(n, strap, seed + 70, 0.3, 14)]
    img = np.concatenate([np.concatenate(top, axis=1), np.concatenate(bot, axis=1)], axis=0)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").save(os.path.join(GEN, name))


# enemies: dark, saturated uniforms that read against sand and grass
atlas("soldier_a.png", [(52, 66, 40), (34, 30, 24), (86, 92, 56), (20, 28, 20)], (38, 42, 32), [(44, 54, 36), (30, 34, 26), (60, 66, 44), (22, 26, 20)], (70, 66, 48), 11)
atlas("soldier_b.png", [(40, 42, 46), (22, 22, 24), (66, 66, 70), (14, 15, 16)], (24, 24, 26), [(30, 31, 34), (20, 20, 22), (46, 46, 50), (12, 12, 13)], (52, 50, 46), 51)
atlas("soldier_c.png", [(70, 60, 38), (40, 36, 24), (96, 88, 54), (30, 34, 22)], (50, 44, 30), [(76, 68, 44), (48, 44, 28), (98, 90, 58), (34, 36, 24)], (84, 74, 50), 71)
atlas("soldier_p.png", [(150, 132, 100), (112, 94, 68), (176, 160, 126), (90, 82, 60)], (60, 56, 44), [(140, 124, 94), (104, 90, 64), (160, 146, 114), (84, 76, 56)], (120, 104, 76), 91)

# chain-link fence (alpha)
n = 256
im = Image.new("RGBA", (n * 4, n * 4), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
step = 128
for k in range(-12, 13):
    d.line([(k * step, 0), (k * step + n * 4, n * 4)], fill=(150, 154, 156, 255), width=13)
    d.line([(k * step + n * 4, 0), (k * step, n * 4)], fill=(120, 124, 128, 255), width=13)
im = im.resize((n, n), Image.LANCZOS)
im.save(os.path.join(GEN, "fence.png"))

# pine needles (opaque tile)
g = fnoise(n, 1.0, 5)
h = fnoise(n, 2.4, 6)
img = np.zeros((n, n, 3), np.float32)
img[:] = (34, 58, 30)
img *= (0.55 + 0.9 * g)[..., None]
img[h > 0.62] *= 0.7
streak = np.random.default_rng(3).random((n, n)) > 0.93
img[streak] = img[streak] * 1.5 + 8
Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(0.6)).save(os.path.join(GEN, "pine.png"))

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
made = 0
for root, _, files in os.walk(os.path.join(PROJECT, "assets")):
    for fn in files:
        if fn.lower().endswith((".jpg", ".png")) and not os.path.exists(os.path.join(root, fn) + ".import"):
            with open(os.path.join(root, fn) + ".import", "w", newline="\n") as f:
                f.write(TEX_IMPORT % (1 if "_nor" in fn.lower() else 2))
            made += 1
print("new import files:", made)
