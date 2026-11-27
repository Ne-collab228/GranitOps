"""Generate procedural textures and sound effects for the game, plus Godot .import files."""
import math
import os
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.signal import butter, lfilter

PROJECT = sys.argv[1]
GEN = os.path.join(PROJECT, "assets", "gen")
SFX = os.path.join(PROJECT, "assets", "sfx")
os.makedirs(GEN, exist_ok=True)
os.makedirs(SFX, exist_ok=True)
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- textures
def fnoise(n, beta=2.0, seed=0):
    """Tileable fractal noise in 0..1 (spectral synthesis)."""
    r = np.random.default_rng(seed)
    white = r.normal(size=(n, n))
    f = np.fft.fft2(white)
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    rad = np.sqrt(fx * fx + fy * fy)
    rad[0, 0] = 1.0
    f = f / (rad ** (beta / 2.0))
    f[0, 0] = 0
    out = np.real(np.fft.ifft2(f))
    out = (out - out.min()) / (out.max() - out.min())
    return out


def save_rgba(arr, name):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(GEN, name))


def save_rgb(arr, name):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(os.path.join(GEN, name))


def camo_tile(n, palette, seed):
    a = fnoise(n, 2.6, seed)
    b = fnoise(n, 2.6, seed + 1)
    c = fnoise(n, 2.2, seed + 2)
    img = np.zeros((n, n, 3), np.float32)
    img[:] = palette[0]
    img[a > 0.56] = palette[1]
    img[b > 0.60] = palette[2]
    img[(c > 0.66) & (a < 0.5)] = palette[3]
    weave = fnoise(n, 0.4, seed + 5)
    img *= (0.86 + 0.28 * weave)[..., None]
    return img


def flat_tile(n, color, seed, amount=0.2, stripes=False):
    img = np.zeros((n, n, 3), np.float32)
    img[:] = color
    img *= (1.0 - amount / 2 + amount * fnoise(n, 1.2, seed))[..., None]
    if stripes:
        for y in range(0, n, 26):
            img[y:y + 5] *= 0.72
            img[y + 5:y + 7] *= 1.12
        for x in range(0, n, 40):
            img[:, x:x + 2] *= 0.8
    return img


def soldier_atlas(name, palette, gear, seed):
    n = 256
    tiles = [
        camo_tile(n, palette, seed),
        flat_tile(n, gear, seed + 10, 0.25, True),
        flat_tile(n, (178, 134, 104), seed + 20, 0.12),
        flat_tile(n, (30, 29, 27), seed + 30, 0.3),
    ]
    save_rgb(np.concatenate(tiles, axis=1), name)


soldier_atlas("soldier_a.png", [(84, 90, 58), (58, 46, 34), (126, 114, 82), (38, 48, 32)], (66, 62, 46), 11)
soldier_atlas("soldier_b.png", [(70, 70, 66), (40, 40, 40), (104, 100, 92), (28, 30, 30)], (36, 36, 34), 51)
# first-person sleeves/gloves for the player (desert tan uniform)
soldier_atlas("soldier_p.png", [(150, 132, 100), (112, 94, 68), (176, 160, 126), (90, 82, 60)], (60, 56, 44), 91)


def radial(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2.0
    dx, dy = (x - c) / c, (y - c) / c
    return np.sqrt(dx * dx + dy * dy), np.arctan2(dy, dx)


def bullet_hole(name, rim_color, hole=0.22, rim=0.62, seed=0):
    n = 128
    r, th = radial(n)
    nz = fnoise(n, 1.6, seed)
    rr = r * (0.8 + 0.5 * nz)
    img = np.zeros((n, n, 4), np.float32)
    rim_a = np.clip((rim - rr) / 0.25, 0, 1) * (0.55 + 0.45 * fnoise(n, 1.0, seed + 3))
    img[..., 0:3] = np.array(rim_color, np.float32) * (0.75 + 0.5 * nz)[..., None]
    img[..., 3] = rim_a * 235
    core = np.clip((hole - rr) / 0.07, 0, 1)
    img[..., 0:3] = img[..., 0:3] * (1 - core[..., None]) + np.array((8, 7, 6), np.float32) * core[..., None]
    img[..., 3] = np.maximum(img[..., 3], core * 255)
    save_rgba(img, name)


bullet_hole("hole_concrete.png", (176, 170, 160), seed=1)
bullet_hole("hole_metal.png", (150, 152, 156), hole=0.2, rim=0.36, seed=2)
bullet_hole("hole_wood.png", (186, 160, 118), hole=0.16, rim=0.48, seed=3)


def muzzle_sheet():
    n = 256
    sheet = np.zeros((n * 2, n * 2, 3), np.float32)
    for k in range(4):
        r, th = radial(n)
        rr = np.random.default_rng(100 + k)
        spikes = np.zeros_like(r)
        for _ in range(7):
            ang = rr.uniform(-math.pi, math.pi)
            width = rr.uniform(0.10, 0.28)
            length = rr.uniform(0.45, 1.0)
            d = np.abs(np.angle(np.exp(1j * (th - ang))))
            spikes = np.maximum(spikes, np.exp(-(d / width) ** 2) * length)
        reach = 0.22 + 0.7 * spikes
        inten = np.clip(1.0 - r / reach, 0, 1) ** 1.6
        inten *= 0.75 + 0.5 * fnoise(n, 1.5, 200 + k)
        core = np.clip(1.0 - r / 0.2, 0, 1) ** 1.2
        col = np.stack([inten * 255 + core * 120, inten * 190 + core * 150, inten * 90 + core * 190], -1)
        edge = np.clip(1.0 - r, 0, 1) ** 0.5
        col *= edge[..., None]
        oy, ox = (k // 2) * n, (k % 2) * n
        sheet[oy:oy + n, ox:ox + n] = col
    save_rgb(sheet, "muzzle.png")


muzzle_sheet()


def puff(name, seed, n=128, hard=1.0):
    r, _ = radial(n)
    nz = fnoise(n, 2.2, seed)
    a = np.clip(1.0 - r * (0.85 + 0.5 * nz), 0, 1) ** hard
    a *= 0.55 + 0.6 * fnoise(n, 1.4, seed + 1)
    img = np.zeros((n, n, 4), np.float32)
    img[..., 0:3] = 255 * (0.82 + 0.18 * nz)[..., None]
    img[..., 3] = np.clip(a, 0, 1) * 255
    save_rgba(img, name)


puff("smoke.png", 31)
puff("smoke2.png", 41, hard=1.6)

r, _ = radial(64)
g = np.clip(1.0 - r, 0, 1) ** 2.2
spark = np.zeros((64, 64, 4), np.float32)
spark[..., 0:3] = 255
spark[..., 3] = g * 255
save_rgba(spark, "spark.png")

save_rgb(np.repeat((fnoise(256, 2.4, 77) * 255)[..., None], 3, -1), "macro_noise.png")


def plant(name, kind, seed, n=256):
    s = 4
    img = Image.new("RGBA", (n * s, n * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(seed)
    W = n * s
    if kind == "grass":
        for _ in range(70):
            x0 = W / 2 + r.normal(0, W * 0.10)
            lean = r.normal(0, 0.45)
            h = r.uniform(0.35, 0.95) * W
            w = r.uniform(5, 11) * s / 4 * 2.2
            shade = r.uniform(0.7, 1.15)
            base = np.array(r.choice([[168, 150, 92], [146, 136, 84], [122, 124, 72], [186, 166, 108]]))
            col = tuple(int(c) for c in np.clip(base * shade, 0, 255)) + (255,)
            pts = []
            for t in np.linspace(0, 1, 9):
                x = x0 + lean * h * t * t
                y = W - 2 - h * t
                pts.append((x, y, w * (1 - t) + 1))
            poly = [(x - ww / 2, y) for x, y, ww in pts] + [(x + ww / 2, y) for x, y, ww in reversed(pts)]
            d.polygon(poly, fill=col)
    elif kind == "shrub":
        def branch(x, y, ang, length, width, depth):
            x2 = x + math.cos(ang) * length
            y2 = y - math.sin(ang) * length
            c = int(r.uniform(58, 84))
            d.line([(x, y), (x2, y2)], fill=(c + 26, c + 6, c - 18, 255), width=max(2, int(width)))
            if depth <= 0:
                for _ in range(5):
                    lx, ly = x2 + r.normal(0, 26), y2 + r.normal(0, 26)
                    rad = r.uniform(9, 20)
                    g2 = r.uniform(0.75, 1.15)
                    d.ellipse([lx - rad, ly - rad * 0.6, lx + rad, ly + rad * 0.6],
                              fill=(int(104 * g2), int(112 * g2), int(62 * g2), 255))
                return
            for _ in range(int(r.integers(2, 4))):
                branch(x2, y2, ang + r.normal(0, 0.55), length * r.uniform(0.6, 0.82), width * 0.68, depth - 1)
        for _ in range(4):
            branch(W / 2 + r.normal(0, 30), W - 4, math.pi / 2 + r.normal(0, 0.5), W * 0.24, 16, 4)
    else:  # foliage cluster for tree crowns
        for _ in range(900):
            ang = r.uniform(0, 2 * math.pi)
            rad0 = abs(r.normal(0, 0.27)) * W
            lx, ly = W / 2 + math.cos(ang) * rad0, W / 2 + math.sin(ang) * rad0 * 0.72
            rad = r.uniform(10, 24)
            g2 = r.uniform(0.6, 1.2)
            rot = r.uniform(0, math.pi)
            pts = [(lx + math.cos(rot + a) * rad * (1.0 if i % 2 == 0 else 0.45),
                    ly + math.sin(rot + a) * rad * (1.0 if i % 2 == 0 else 0.45))
                   for i, a in enumerate(np.linspace(0, 2 * math.pi, 8, endpoint=False))]
            d.polygon(pts, fill=(int(74 * g2), int(92 * g2), int(46 * g2), 255))
    img = img.resize((n, n), Image.LANCZOS)
    arr = np.array(img).astype(np.float32)
    arr[..., 3] = np.where(arr[..., 3] > 96, 255, 0)
    save_rgba(arr, name)


plant("grass.png", "grass", 5)
plant("shrub.png", "shrub", 9)
plant("foliage.png", "foliage", 13, 512)

# app icon
ic = Image.new("RGBA", (512, 512), (24, 28, 24, 255))
d = ImageDraw.Draw(ic)
d.ellipse([56, 56, 456, 456], outline=(214, 196, 150, 255), width=14)
d.ellipse([150, 150, 362, 362], outline=(214, 196, 150, 255), width=8)
for box in ([248, 20, 264, 190], [248, 322, 264, 492], [20, 248, 190, 264], [322, 248, 492, 264]):
    d.rectangle(box, fill=(214, 196, 150, 255))
d.polygon([(256, 214), (300, 290), (256, 270), (212, 290)], fill=(196, 70, 44, 255))
ic.save(os.path.join(PROJECT, "icon.png"))

# ---------------------------------------------------------------- sounds
SR = 44100


def N(sec):
    return int(sec * SR)


def noise(n):
    return rng.uniform(-1, 1, n)


def filt(x, kind, fc, order=2):
    if isinstance(fc, (tuple, list)):
        wn = [f / (SR / 2) for f in fc]
    else:
        wn = fc / (SR / 2)
    b, a = butter(order, wn, kind)
    return lfilter(b, a, x)


def decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def place(buf, sig, at, gain=1.0):
    i = N(at)
    j = min(len(buf), i + len(sig))
    if j > i:
        buf[i:j] += sig[:j - i] * gain


def write(name, x, peak=0.95, drive=1.0):
    x = np.tanh(x * drive)
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * peak
    fade = min(len(x), N(0.004))
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(SFX, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def sweep(n, f0, f1, tau):
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / tau)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def gunshot(name, length, crack_hp, crack_tau, thump_f, thump_gain, body_lp, body_tau, tail_tau, tail_gain, mech=0.3, drive=2.2):
    n = N(length)
    x = np.zeros(n)
    c = filt(noise(N(0.08)), "high", crack_hp) * decay(N(0.08), crack_tau)
    place(x, c, 0.0, 1.0)
    b = filt(noise(N(0.3)), "low", body_lp) * decay(N(0.3), body_tau)
    place(x, b, 0.0, 1.1)
    th = sweep(N(0.25), thump_f[0], thump_f[1], 0.03) * decay(N(0.25), 0.055)
    place(x, th, 0.0, thump_gain)
    if mech > 0:
        m = filt(noise(N(0.03)), "band", (2200, 6000)) * decay(N(0.03), 0.006)
        place(x, m, 0.045, mech)
        place(x, m[::-1] * 0.6, 0.085, mech * 0.7)
    tl = filt(noise(n), "band", (220, 3200)) * decay(n, tail_tau)
    mod = 1.0 + 0.45 * filt(noise(n), "low", 14) * 6
    place(x, tl * np.clip(mod, 0.2, 2.0), 0.012, tail_gain)
    for dly, g2, fc in ((0.11, 0.30, 2400), (0.23, 0.18, 1500), (0.41, 0.10, 900)):
        e = filt(c * 0.6 + b[:len(c)] * 0.8, "low", fc)
        place(x, e, dly, g2)
    write(name, x, drive=drive)


gunshot("shot_rifle", 1.1, 1400, 0.011, (190, 62), 1.2, 1100, 0.045, 0.24, 0.30)
gunshot("shot_sniper", 1.7, 900, 0.018, (150, 46), 1.9, 800, 0.075, 0.42, 0.42, mech=0.0, drive=2.6)
gunshot("shot_pistol", 0.8, 1800, 0.008, (260, 95), 0.9, 1500, 0.03, 0.16, 0.22, mech=0.35, drive=2.0)
gunshot("shot_enemy", 1.2, 1100, 0.014, (170, 55), 1.5, 950, 0.055, 0.30, 0.36, mech=0.2, drive=2.4)


def click(freqs, tau=0.012, nz=0.6, length=0.06, hp=1500):
    n = N(length)
    t = np.arange(n) / SR
    x = filt(noise(n), "high", hp) * decay(n, tau * 0.5) * nz
    for f in freqs:
        x += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * decay(n, tau) * 0.5
    return x


def seq(name, length, events, drive=1.4, peak=0.8):
    x = np.zeros(N(length))
    for at, sig, g2 in events:
        place(x, sig, at, g2)
    write(name, x, peak=peak, drive=drive)


def slide(length, lo, hi, gain=1.0):
    n = N(length)
    return filt(noise(n), "band", (lo, hi)) * np.hanning(n) * gain


seq("mag_out", 0.5, [(0.02, click([2100, 3900]), 0.9), (0.06, slide(0.22, 900, 3800), 0.5), (0.30, click([900, 1700], 0.02, 0.4, hp=600), 0.5)])
seq("mag_in", 0.5, [(0.02, slide(0.16, 1200, 4200), 0.45), (0.19, click([1500, 2800, 5200], 0.016), 1.0), (0.24, click([700], 0.03, 0.3, hp=300), 0.6)])
seq("bolt", 0.6, [(0.02, click([1800, 3300], 0.014), 0.9), (0.05, slide(0.14, 1500, 5000), 0.5), (0.24, click([2400, 4100, 6200], 0.012), 1.0), (0.26, click([600], 0.03, 0.3, hp=300), 0.7)])
seq("bolt_action", 1.0, [(0.02, click([2600, 4800], 0.01), 0.7), (0.10, slide(0.16, 1400, 5200), 0.55), (0.27, click([1700, 3000], 0.016), 0.9), (0.42, slide(0.16, 1600, 5600), 0.55), (0.60, click([2300, 3900, 6100], 0.012), 1.0), (0.70, click([2900, 5200], 0.01), 0.7)])
seq("dry", 0.15, [(0.01, click([3200, 5400], 0.006, 0.8, 0.05), 1.0)], peak=0.5)
seq("pistol_slide", 0.4, [(0.02, slide(0.09, 1800, 6000), 0.6), (0.12, click([2600, 4700], 0.01), 1.0)])
seq("cloth", 0.3, [(0.0, slide(0.26, 500, 2600), 1.0)], peak=0.35)
seq("pin", 0.35, [(0.02, click([4200, 6800, 9100], 0.03, 0.3), 1.0), (0.12, click([5200], 0.05, 0.1), 0.5)], peak=0.5)
seq("bounce", 0.25, [(0.0, click([1300, 2900, 4300], 0.02, 0.5, hp=500), 1.0)], peak=0.6)


def footstep(name, kind, seed):
    r = np.random.default_rng(seed)
    n = N(0.28)
    x = np.zeros(n)
    if kind == "gravel":
        for _ in range(16):
            g = N(r.uniform(0.004, 0.018))
            grain = filt(r.uniform(-1, 1, g), "band", (r.uniform(700, 1800), r.uniform(3000, 7000))) * np.hanning(g)
            place(x, grain, r.uniform(0.0, 0.16), r.uniform(0.3, 1.0))
        th = filt(noise(N(0.08)), "low", 160) * decay(N(0.08), 0.02)
        place(x, th, 0.0, 2.2)
    else:
        th = filt(noise(N(0.1)), "low", 300) * decay(N(0.1), 0.018)
        place(x, th, 0.0, 2.5)
        tk = filt(noise(N(0.03)), "band", (1500, 5000)) * decay(N(0.03), 0.004)
        place(x, tk, 0.004, 0.7)
        place(x, tk * 0.5, 0.07, 0.4)
    write(name, x, peak=0.6, drive=1.2)


for i in range(4):
    footstep("step_gravel%d" % i, "gravel", 300 + i)
for i in range(3):
    footstep("step_hard%d" % i, "hard", 400 + i)


def impact(name, kind):
    n = N(0.5)
    x = np.zeros(n)
    t = np.arange(n) / SR
    if kind == "dirt":
        place(x, filt(noise(N(0.12)), "low", 500) * decay(N(0.12), 0.025), 0, 2.0)
        place(x, filt(noise(N(0.25)), "band", (900, 5000)) * decay(N(0.25), 0.06), 0.01, 0.5)
    elif kind == "concrete":
        place(x, filt(noise(N(0.06)), "high", 1800) * decay(N(0.06), 0.008), 0, 1.0)
        place(x, filt(noise(N(0.12)), "low", 700) * decay(N(0.12), 0.02), 0, 1.3)
        for _ in range(7):
            place(x, click([rng.uniform(2500, 6000)], 0.006, 0.6, 0.03), rng.uniform(0.04, 0.32), rng.uniform(0.1, 0.35))
    elif kind == "metal":
        for f, g2, tau in ((1840, 1.0, 0.09), (3170, 0.7, 0.07), (4730, 0.5, 0.05), (6890, 0.3, 0.035)):
            x += np.sin(2 * np.pi * f * (1 + rng.uniform(-0.03, 0.03)) * t) * decay(n, tau) * g2
        place(x, filt(noise(N(0.03)), "high", 2500) * decay(N(0.03), 0.004), 0, 1.5)
    elif kind == "wood":
        place(x, filt(noise(N(0.1)), "band", (300, 1800)) * decay(N(0.1), 0.02), 0, 1.6)
        place(x, np.sin(2 * np.pi * 420 * t[:N(0.1)]) * decay(N(0.1), 0.02), 0, 0.7)
    else:  # body
        place(x, filt(noise(N(0.14)), "low", 420) * decay(N(0.14), 0.03), 0, 2.0)
        place(x, filt(noise(N(0.07)), "band", (800, 2600)) * decay(N(0.07), 0.015), 0.004, 0.5)
    write(name, x, peak=0.75, drive=1.5)


for k in ("dirt", "concrete", "metal", "wood", "body"):
    impact("hit_" + k, k)

for i in range(2):
    n = N(0.4)
    x = np.zeros(n)
    place(x, filt(noise(N(0.012)), "high", 3000) * decay(N(0.012), 0.002), 0.0, 1.6)
    wn = noise(n)
    t = np.arange(n) / SR
    fc = 3400 * np.exp(-t / 0.12) + 900
    ph = np.cumsum(fc) / SR * 2 * np.pi
    whine = np.sin(ph) * filt(wn, "low", 60) * 14 + filt(wn, "band", (1200, 4200)) * 0.5
    place(x, whine * decay(n, 0.09 + 0.03 * i), 0.004, 0.7)
    write("whizz%d" % i, x, peak=0.7, drive=1.3)

# explosion
n = N(3.0)
x = np.zeros(n)
place(x, filt(noise(N(0.1)), "high", 900) * decay(N(0.1), 0.012), 0, 1.4)
place(x, sweep(N(0.9), 120, 28, 0.12) * decay(N(0.9), 0.25), 0, 2.6)
place(x, filt(noise(N(1.5)), "low", 380) * decay(N(1.5), 0.32), 0, 2.2)
tail = filt(noise(n), "band", (70, 1400)) * decay(n, 0.8) * np.clip(1 + filt(noise(n), "low", 9) * 9, 0.2, 2.2)
place(x, tail, 0.03, 0.8)
for _ in range(26):
    place(x, click([rng.uniform(900, 4200)], 0.01, 0.8, 0.04, hp=700), rng.uniform(0.25, 1.9), rng.uniform(0.05, 0.22))
write("explosion", x, drive=2.6)

t = np.arange(N(0.07)) / SR
write("hitmark", np.sin(2 * np.pi * 2300 * t) * decay(len(t), 0.012) + filt(noise(len(t)), "high", 4000) * decay(len(t), 0.003), peak=0.45)
t = np.arange(N(0.16)) / SR
k = np.sin(2 * np.pi * 1500 * t) * decay(len(t), 0.02)
k[N(0.07):] += (np.sin(2 * np.pi * 980 * t) * decay(len(t), 0.03))[:len(t) - N(0.07)]
write("killmark", k, peak=0.5)
t = np.arange(N(0.05)) / SR
write("ui_click", np.sin(2 * np.pi * 1250 * t) * decay(len(t), 0.01), peak=0.35)
t = np.arange(N(0.07)) / SR
write("beep", np.sin(2 * np.pi * 2050 * t) * np.hanning(len(t)), peak=0.45)

# radio squelch + two tones
n = N(0.55)
x = np.zeros(n)
place(x, filt(noise(N(0.08)), "band", (1200, 3600)) * np.hanning(N(0.08)), 0.0, 0.5)
t = np.arange(N(0.12)) / SR
place(x, np.sin(2 * np.pi * 880 * t) * np.hanning(len(t)), 0.09, 0.8)
place(x, np.sin(2 * np.pi * 1320 * t) * np.hanning(len(t)), 0.24, 0.8)
place(x, filt(noise(N(0.07)), "band", (1200, 3600)) * np.hanning(N(0.07)), 0.42, 0.4)
write("radio", x, peak=0.4)

# heartbeat loop (1.0 s)
n = N(1.0)
x = np.zeros(n)
for at, g2 in ((0.0, 1.0), (0.26, 0.7)):
    t = np.arange(N(0.16)) / SR
    place(x, np.sin(2 * np.pi * 52 * t) * np.hanning(len(t)), at, g2)
write("heartbeat", x, peak=0.8)

# tinnitus
t = np.arange(N(3.0)) / SR
write("ring", (np.sin(2 * np.pi * 4100 * t) + 0.5 * np.sin(2 * np.pi * 6230 * t)) * decay(len(t), 0.9) * np.minimum(1, t / 0.05), peak=0.3)

# wind loop (8 s, crossfaded so it loops seamlessly)
n = N(8.0)
xf = N(1.0)
raw = filt(noise(n + xf), "band", (90, 900), 1) * (1 + 0.6 * filt(noise(n + xf), "low", 0.5) * 40)
raw += filt(noise(n + xf), "band", (400, 2400), 1) * 0.25 * (1 + filt(noise(n + xf), "low", 0.8) * 30)
loop = raw[:n].copy()
ramp = np.linspace(0, 1, xf)
loop[:xf] = raw[:xf] * ramp + raw[n:n + xf] * (1 - ramp)
m = np.max(np.abs(loop))
data = (loop / m * 0.5 * 32767).astype(np.int16)
with wave.open(os.path.join(SFX, "wind.wav"), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data.tobytes())

# fire loop (3 s)
n = N(3.0)
xf = N(0.4)
raw = filt(noise(n + xf), "band", (150, 1800), 1) * (0.6 + np.clip(filt(noise(n + xf), "low", 6) * 14, -0.5, 1.5))
for _ in range(60):
    place(raw, click([rng.uniform(1500, 5000)], 0.004, 0.9, 0.02), rng.uniform(0, 3.3), rng.uniform(0.2, 0.9))
loop = raw[:n].copy()
ramp = np.linspace(0, 1, xf)
loop[:xf] = raw[:xf] * ramp + raw[n:n + xf] * (1 - ramp)
data = (loop / np.max(np.abs(loop)) * 0.6 * 32767).astype(np.int16)
with wave.open(os.path.join(SFX, "fire.wav"), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data.tobytes())

# ---------------------------------------------------------------- .import files
TEX_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=%d
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=%d
compress/channel_pack=0
mipmaps/generate=%s
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

count = 0
for root, _, files in os.walk(os.path.join(PROJECT, "assets")):
    for fn in files:
        low = fn.lower()
        if not low.endswith((".jpg", ".png")):
            continue
        is_normal = "_nor" in low
        mode = 2
        mips = "true"
        path = os.path.join(root, fn) + ".import"
        with open(path, "w", newline="\n") as f:
            f.write(TEX_IMPORT % (mode, 1 if is_normal else 2, mips))
        count += 1
print("textures:", len(os.listdir(GEN)), "sounds:", len(os.listdir(SFX)), "import files:", count)
