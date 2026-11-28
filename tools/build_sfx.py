"""Сборка звуков игры из настоящих записей (CC0).

python -I tools/build_sfx.py <staging> <проект> [sources.json]

staging — папка со скачанными архивами (oga_a/.., ffsl/..., см. assets/sfx/LICENSES.md).
Пишет assets/sfx/*.ogg (моно для 3D-звуков, стерео для окружения) и assets/sfx/LICENSES.md.
Сами записи в репозиторий не кладутся — только результат.
"""
import sys, os, re, json, glob, subprocess, tempfile, csv
import numpy as np
from scipy import signal
from scipy.io import wavfile

STAGE = sys.argv[1]
PROJECT = sys.argv[2]
SRC_JSON = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "sfx_sources.json")
OUT = os.path.join(PROJECT, "assets", "sfx")
SR = 44100
RNG = np.random.default_rng(228)
SOURCES = json.load(open(SRC_JSON, encoding="utf-8"))
FFSL = os.path.join(STAGE, "ffsl", "Prepared SFX Library")

_used = set()
LICENSE_ROWS = []   # (name, [источники])


# ---------------------------------------------------------------- ввод-вывод

def P(*parts):
    return os.path.join(STAGE, *parts)


def G(pattern):
    r = sorted(glob.glob(os.path.join(STAGE, pattern), recursive=True))
    if not r:
        raise SystemExit("нет файла: " + pattern)
    return r


def load(path, ch=1, sr=SR):
    _used.add(path)
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", str(ch), "-ar", str(sr), "-f", "f32le", "-"],
                         capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    if ch == 2:
        x = x.reshape(-1, 2)
    if len(x) == 0:
        raise SystemExit("пусто: " + path)
    return x


def db(v):
    return 10.0 ** (v / 20.0)


def peak(x):
    return float(np.abs(x).max()) + 1e-12


def norm(x, target_db):
    return x * (db(target_db) / peak(x))


def rms_norm(x, target_db):
    r = float(np.sqrt((x ** 2).mean())) + 1e-12
    return x * (db(target_db) / r)


def seg(x, a, b):
    return x[int(a * SR):int(b * SR)]


def trim(x, head_db=-42.0, tail_db=-46.0, pad_head=0.004):
    e = np.abs(x if x.ndim == 1 else x.max(axis=1))
    pk = e.max()
    k = int(SR * 0.003)
    env = np.convolve(e, np.ones(k) / k, "same")
    idx = np.where(env > pk * db(head_db))[0]
    a = max(0, idx[0] - int(pad_head * SR)) if len(idx) else 0
    idt = np.where(env > pk * db(tail_db))[0]
    b = idt[-1] + 1 if len(idt) else len(x)
    return x[a:b]


def fade(x, a_ms=2.0, b_ms=30.0):
    x = x.copy()
    na, nb = int(SR * a_ms / 1000), int(SR * b_ms / 1000)
    if na > 0:
        w = np.linspace(0, 1, na)
        x[:na] *= w if x.ndim == 1 else w[:, None]
    if nb > 0:
        w = np.linspace(1, 0, min(nb, len(x))) ** 1.5
        x[-len(w):] *= w if x.ndim == 1 else w[:, None]
    return x


def cap(x, sec, fade_ms=60.0):
    n = int(sec * SR)
    if len(x) > n:
        x = fade(x[:n], 0, fade_ms)
    return x


def punch(x, drive=2.5):
    """Мягкий ограничитель: поднимает хвост относительно острого пика (выстрелы иначе звучат тихо)."""
    pk = peak(x)
    return np.tanh(x / pk * drive) / np.tanh(drive) * pk


def pitch(x, r):
    """Смена скорости (высоты) в r раз."""
    n = int((len(x) - 1) / r)
    t = np.arange(n) * r
    if x.ndim == 1:
        return np.interp(t, np.arange(len(x)), x)
    return np.stack([np.interp(t, np.arange(len(x)), x[:, c]) for c in range(x.shape[1])], 1)


def sweep_pitch(x, r0, r1):
    """Скорость воспроизведения плавно от r0 до r1 (допплер, рикошет)."""
    n_out = int(len(x) / ((r0 + r1) * 0.5))
    r = np.linspace(r0, r1, n_out)
    t = np.cumsum(r)
    t = t[t < len(x) - 1]
    return np.interp(t, np.arange(len(x)), x)


def filt(x, kind, fc, order=2):
    sos = signal.butter(order, fc, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def band(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def env_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def mix(parts):
    """parts: [(сигнал, смещение_с, усиление)]"""
    n = max(int(o * SR) + len(s) for s, o, g in parts)
    y = np.zeros(n)
    for s, o, g in parts:
        i = int(o * SR)
        y[i:i + len(s)] += s * g
    return y


def loopify(x, length, xfade=1.5):
    """Бесшовная петля длиной length с: кроссфейд начала с «продолжением» конца (равная мощность)."""
    n, f = int(length * SR), int(xfade * SR)
    if len(x) < n + f:
        raise SystemExit("мало материала для петли: %.1f < %.1f" % (len(x) / SR, length + xfade))
    y = x[:n].copy()
    t = np.linspace(0, np.pi / 2, f)
    fi, fo = np.sin(t), np.cos(t)
    if y.ndim == 2:
        fi, fo = fi[:, None], fo[:, None]
    y[:f] = x[:f] * fi + x[n:n + f] * fo
    return y


def onsets(x, thr=0.2, gap=0.12):
    env = np.abs(x)
    k = int(SR * 0.002)
    env = np.convolve(env, np.ones(k) / k, "same")
    pk = env.max()
    out, last = [], -1e9
    for i in np.where(env > pk * thr)[0]:
        if i - last > gap * SR:
            out.append(i)
        last = i
    return out


def encode(name, x, ch=1, q=4):
    os.makedirs(OUT, exist_ok=True)
    pk = float(np.abs(x).max())
    if pk > 0.93:
        x = x * (0.93 / pk)   # запас под перерегулирование кодека
    pcm = (x * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as td:
        w = os.path.join(td, "t.wav")
        wavfile.write(w, SR, pcm)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", w, "-ac", str(ch), "-c:a", "libvorbis", "-q:a", str(q),
                        os.path.join(OUT, name + ".ogg")], check=True)
    for ext in (".wav", ".wav.import"):
        f = os.path.join(OUT, name + ext)
        if os.path.exists(f):
            os.remove(f)


def done(name, x, ch=1, q=4):
    """Записать звук и запомнить, из каких файлов он собран."""
    global _used
    encode(name, x, ch, q)
    LICENSE_ROWS.append((name, sorted(_used)))
    _used = set()


def variants(base, items, ch=1, q=4):
    """items — список сигналов; первый — base, остальные base_2, base_3…"""
    for i, x in enumerate(items):
        done(base if i == 0 else "%s_%d" % (base, i + 1), x, ch, q)


# ---------------------------------------------------------------- выстрелы

CSV = {}
for r in csv.reader(open(os.path.join(FFSL, "Prepared Master Sheet.csv"), encoding="utf-8-sig", newline=None)):
    if len(r) >= 6:
        CSV[r[0]] = r[5]


def shots(fname, n_max, cap_s, thr=0.2):
    """Одиночные выстрелы из файла библиотеки (между ними 3-4 с тишины и хвоста)."""
    x = load(os.path.join(FFSL, os.path.dirname(fname), os.path.basename(fname)))
    on = onsets(x, thr, 1.2)
    res = []
    for i, s in enumerate(on[:n_max]):
        a = max(0, s - int(0.02 * SR))
        b = on[i + 1] - int(0.15 * SR) if i + 1 < len(on) else len(x)
        b = min(b, a + int(cap_s * SR))
        res.append(fade(trim(x[a:b], -38, -60), 0.5, 150.0))
    return res


# класс: (папка/файл «близко», «вдали», высота, пик близко дБ, макс. число выстрелов)
GUNS = {
    "ar":     ("AR-15/D_32P.wav", "AR-15/D_24P.wav", 1.0, -1.5),
    "akm":    ("AK-47/C_28P.wav", "AK-47/C_31P.wav", 1.0, -0.5),
    "smg":    ("Carl Gustav M45/G_31P.wav", "Carl Gustav M45/G_20P.wav", 1.0, -3.0),
    "lmg":    ("SKS/U_14P.wav", "SKS/U_19P.wav", 0.9, -0.5),
    "dmr":    ("Savage 10 .300 Blackout/T_27P.wav", "Savage 10 .300 Blackout/T_17P.wav", 1.0, 0.0),
    "sr":     ("Mosin Nagant/M_21P.wav", "Mosin Nagant/M_26P.wav", 1.0, 0.0),
    "pistol": ("Walther PPQ/X_39P.wav", "Walther PPQ/X_31P.wav", 1.0, -3.5),
}
SG = [("Mossberg/N_30P.wav", "Mossberg/N_26P.wav"), ("Model 12/K_22P.wav", "Model 12/K_17P.wav"),
      ("Nova/O_21P.wav", "Nova/O_17P.wav")]

SILENCER = None


def silencer_thump():
    global SILENCER
    if SILENCER is None:
        s = load(G("oga_a/hollywood-style-pistol-silencer-sound-effect/silencer.wav")[0])
        SILENCER = fade(trim(s, -35, -42), 1, 80)
    return SILENCER


def make_supp(near, pitch_r):
    """Глушитель: из близкого выстрела — срезанный верх, короткий хвост, плюс «хлопок» глушителя."""
    y = filt(near, "low", 1700, 2)
    y = y[:int(0.5 * SR)] * env_decay(min(len(y), int(0.5 * SR)), 0.16)
    th = pitch(silencer_thump()[:int(0.55 * SR)], pitch_r)
    m = mix([(y / peak(y), 0, 0.7), (th / peak(th), 0, 0.7)])
    return norm(fade(trim(m, -35, -52), 1, 80), -6.0)


def build_guns():
    for gid, (nf, mf, pr, pk) in GUNS.items():
        ns = [pitch(s, pr) if pr != 1.0 else s for s in shots(nf, 3, 1.5)]
        ms = [pitch(s, pr) if pr != 1.0 else s for s in shots(mf, 3, 2.8, 0.15)]
        ns = [norm(punch(s), pk) for s in ns][:3]
        variants("shot_" + gid, ns)
        # «вдали»: запись со среднего расстояния, с естественным эхом
        variants("shot_%s_far" % gid, [norm(punch(s, 1.8), pk - 2.5) for s in ms[:2]])
        variants("shot_%s_supp" % gid, [make_supp(s, pr) for s in ns[:2]])
    # дробовик: три разных ствола как варианты одного звука
    ns, ms = [], []
    for nf, mf in SG:
        ns.append(norm(punch(shots(nf, 1, 1.5)[0]), 0.0))
        ms.append(norm(punch(shots(mf, 1, 2.8, 0.15)[0], 1.8), -2.5))
    variants("shot_sg", ns)
    variants("shot_sg_far", ms[:2])
    variants("shot_sg_supp", [make_supp(s, 0.8) for s in ns[:2]])


# ---------------------------------------------------------------- механика оружия

def build_mech():
    gr1 = load(G("oga_a/gun-reload-sounds/gunreload1.wav")[0])
    ar1 = load(G("oga_a/gun-reload-sounds/assaultriflereload1_0.wav")[0])
    hg = load(G("oga_b/handgun-reload-sound-effect/reload.wav")[0])
    r1 = load(G("oga_b/2-gun-reloads/*/gun_reload.1.ogg")[0])
    r2 = load(G("oga_b/2-gun-reloads/*/gun_reload.2.ogg")[0])
    cl1 = load(G("oga_b/gun-reload-sound-effects/clipload1.wav")[0])
    cl2 = load(G("oga_b/gun-reload-sound-effects/clipload2.wav")[0])
    sb = load(G("oga_b/gun-reload-sound-effects/singlebullet1.wav")[0])
    click = load(G("oga_b/gun-reload-lock-or-click-sound/*.mp3")[0])
    rack = load(G("oga_b/shotgun-reload-sound-effects/*/*/Rack.mp3")[0])
    cock = load(G("oga_a/gun-reload-sounds/shotguncock_0.wav")[0])
    chamber = load(G("oga_b/shotgun-reload-sound-effects/*/*/Shell in Chamber.mp3")[0])

    def cut(x, a, b, g=-6.0):
        return norm(fade(trim(seg(x, a, b), -40, -44), 1, 25), g)

    variants("mag_out", [cut(gr1, 0.1, 0.85), cut(ar1, 0.2, 0.9), cut(r2, 0.1, 0.65)])
    variants("mag_in", [cut(gr1, 1.2, 1.58), cut(ar1, 1.0, 1.5), norm(trim(cl1), -6.0), norm(trim(cl2), -6.0)])
    variants("bolt", [cut(ar1, 1.12, 1.56), cut(r1, 0.45, 0.96), cut(r2, 0.65, 1.3)])
    variants("bolt_action", [cut(rack, 0.5, 1.13, -4.0), norm(trim(cock), -4.0), cut(chamber, 0.4, 1.2, -5.0)])
    variants("pistol_slide", [cut(hg, 0.95, 1.59), cut(hg, 0.5, 1.0), cut(r1, 0.4, 0.96)])
    variants("dry", [norm(trim(click), -7.0), norm(pitch(trim(click), 1.2), -7.0), norm(pitch(trim(click), 0.85), -7.0)])
    # гильзы: мелкий металлический звон о землю
    cl = [load(G("oga_b/metal-impact-sounds/clink%s.wav" % n)[0]) for n in ("1_0", "2", "3")]
    variants("casing", [norm(fade(trim(pitch(c, 1.45), -35, -40), 1, 40)[:int(0.3 * SR)], -9.0) for c in cl]
             + [norm(fade(trim(sb), 1, 40), -9.0)])
    # чека гранаты и пружина
    keys = load(G("oga_b/100-cc0-metal-and-wood-sfx/*/lock_open_01.ogg")[0])
    spr = load(G("oga_b/100-cc0-metal-and-wood-sfx/*/metal_spring_01.ogg")[0])
    spr2 = load(G("oga_b/100-cc0-metal-and-wood-sfx/*/metal_spring_02.ogg")[0])
    variants("pin", [norm(fade(trim(keys), 1, 40), -5.0), norm(fade(trim(spr), 1, 40), -5.0),
                     norm(fade(trim(spr2), 1, 40), -5.0)])
    # шорох экипировки: куски записи ткани
    cloth = load(G("oga_d/fabric-rustling/rustling.ogg")[0])
    on = onsets(cloth, 0.12, 0.5)
    pieces = []
    for i in on[:12]:
        p = fade(seg(cloth, i / SR - 0.03, i / SR + 0.45), 5, 120)
        if peak(p) > 0.1:
            pieces.append(norm(p, -8.0))
    variants("cloth", pieces[:4])
    # граната отскакивает
    t3 = load(G("oga_b/metal-impact-sounds/thud3.wav")[0])
    mh = load(G("oga_b/100-cc0-metal-and-wood-sfx/*/metal_hit_03.ogg")[0])
    cl2b = load(G("oga_b/metal-impact-sounds/clink2.wav")[0])
    variants("bounce", [norm(fade(trim(t3), 1, 50), -6.0), norm(fade(trim(mh), 1, 50), -6.0),
                        norm(fade(trim(pitch(cl2b, 0.8)), 1, 50), -6.0)])


# ---------------------------------------------------------------- попадания, свист, рикошет

def clip(path, g, cap_s=0.45, lo=None, hi=None, r=1.0, head=-40):
    x = load(path)
    if lo:
        x = filt(x, "high", lo)
    if hi:
        x = filt(x, "low", hi)
    if r != 1.0:
        x = pitch(x, r)
    return norm(fade(cap(trim(x, head, -42), cap_s, 60), 0.5, 40), g)


def build_impacts():
    def b(p):
        return G("oga_b/" + p)[0]

    def c(p):
        return G("oga_c/" + p)[0]
    f75 = "75-cc0-breaking-falling-hit-sfx/*/"
    f100 = "100-cc0-metal-and-wood-sfx/*/"
    # земля: глухие удары камешков и грунта
    variants("hit_dirt", [clip(b("metal-impact-sounds/thud3.wav"), -4, 0.4, hi=2600),
                          clip(b(f75 + "bfh1_rock_falling_02.ogg"), -4, 0.4, hi=2800),
                          clip(b(f75 + "bfh1_rock_falling_07.ogg"), -4, 0.4, hi=3200),
                          clip(c("shovel-sound/shovel_0.ogg"), -6, 0.4, hi=3000, r=1.1)])
    variants("hit_concrete", [clip(c("impact/*/*/qubodupImpactStone.ogg"), -3, 0.35),
                              clip(b(f75 + "bfh1_rock_hit_01.ogg"), -3, 0.3),
                              clip(b(f75 + "bfh1_rock_breaking_03.ogg"), -4, 0.4),
                              clip(b(f75 + "bfh1_rock_falling_04.ogg"), -4, 0.3)])
    variants("hit_metal", [clip(b(f100 + "metal_hit_01.ogg"), -3, 0.35), clip(b(f100 + "metal_hit_04.ogg"), -3, 0.35),
                           clip(b(f100 + "metal_hit_05.ogg"), -3, 0.35), clip(c("impact/*/*/qubodupImpactMetal.ogg"), -3, 0.35)])
    variants("hit_sheet", [clip(b(f100 + "metal_sheet_01.ogg"), -3, 0.4), clip(b(f100 + "metal_sheet_02.ogg"), -3, 0.4),
                           clip(b(f100 + "metal_sheet_04.ogg"), -3, 0.4), clip(b(f100 + "metal_sheet_05.ogg"), -3, 0.3)])
    wood = G("oga_b/35-wooden*/*/*/impactwood0*.flac")
    variants("hit_wood", [clip(wood[0], -3, 0.35), clip(wood[3], -3, 0.35), clip(b(f100 + "wood_hit_02.ogg"), -3, 0.35),
                          clip(b(f100 + "wood_hit_04.ogg"), -3, 0.35)])
    variants("hit_body", [clip(c("impact/*/*/qubodupImpactMeat01.ogg"), -3, 0.4), clip(c("impact/*/*/qubodupImpactMeat02.ogg"), -3, 0.4),
                          clip(c("37-hitspunches/*/hits/hit09.mp3.flac"), -3, 0.4, hi=4500),
                          clip(c("37-hitspunches/*/hits/hit06.mp3.flac"), -3, 0.35, hi=4500)])
    # метки попадания и убийства в интерфейсе
    cl = [load(b("metal-impact-sounds/clink%s.wav" % n)) for n in ("1_0", "2", "3")]
    variants("hitmark", [norm(fade(cap(trim(pitch(cl[1], 1.5)), 0.14, 40), 0.5, 30), -7.0)])
    bing = load(b("metal-impact-sounds/bing1.wav"))
    variants("killmark", [norm(fade(cap(trim(pitch(bing, 1.25)), 0.35, 120), 0.5, 80), -6.0)])
    # рикошет: звон с падающей высотой
    rico = []
    for k, (r0, r1) in enumerate([(1.5, 0.8), (1.3, 0.7), (1.7, 0.9)]):
        s = sweep_pitch(bing[:int(0.5 * SR)] if k == 0 else cl[k], r0, r1)
        rico.append(norm(fade(cap(trim(s), 0.55, 200), 0.5, 120), -8.0))
    variants("ricochet", rico)


def build_whizz():
    """Свист и щелчок пули рядом: острый «хлопок» от выстрела + полоса шума с допплером."""
    ak = shots("AK-47/C_28P.wav", 1, 0.3)[0]
    crack = filt(ak[:int(0.012 * SR)], "high", 1800)
    crack = crack / peak(crack)
    items = []
    for k in range(4):
        n = int((0.16 + 0.03 * k) * SR)
        noise = RNG.standard_normal(n)
        # центр полосы падает: пуля пролетает мимо
        y = np.zeros(n)
        f0, f1 = 5200 - 300 * k, 1800 + 150 * k
        blocks = 12
        for i in range(blocks):
            a, bb = i * n // blocks, (i + 1) * n // blocks
            fc = f0 + (f1 - f0) * i / blocks
            y[a:bb] = band(noise, fc * 0.7, min(fc * 1.35, SR / 2 - 100))[a:bb]
        t = np.linspace(0, 1, n)
        amp = np.sin(np.pi * np.clip(t * 1.0, 0, 1)) ** 0.8 * (1 - 0.4 * t)
        y = y * amp
        y = y / peak(y)
        sig = mix([(crack * (0.9 if k % 2 == 0 else 0.5), 0.0, 1.0), (y, 0.0, 0.8)])
        items.append(norm(fade(sig, 0.2, 40), -3.0))
    variants("whizz", items)


# ---------------------------------------------------------------- взрывы, машина

def build_explosions():
    ch = load(G("oga_b/chunky-explosion/*.mp3")[0])
    e1 = load(G("oga_d/explosions-4/explosion1_0.ogg")[0])
    cn = load(G("oga_b/25-cc0-bang-firework-sfx/*/cannon_02.ogg")[0])
    bg = load(G("oga_b/25-cc0-bang-firework-sfx/*/bang_06.ogg")[0])
    me = load(G("oga_d/mechanical-explosion/mechanical_explosion.wav")[0])

    def ex(x, sec, g=-1.0):
        return norm(punch(fade(cap(trim(x, -38, -44), sec, 400), 0.5, 300), 2.0), g)
    variants("explosion", [ex(ch, 4.5), ex(e1, 3.8), ex(mix([(cn, 0, 1.0), (me, 0.02, 0.5)]), 3.0)])
    far1 = load(G("oga_b/muffled-distant-explosion/*.wav")[0])
    far2 = load(G("oga_b/explosion-somewhere-far/*.mp3")[0])
    variants("explosion_far", [norm(filt(ex(far1, 4.8), "low", 3500), -3.0), norm(filt(ex(far2, 2.9), "low", 4000), -3.0),
                               norm(filt(ex(bg, 1.3), "low", 1800, 3), -4.0)])
    # хлопок дымовой/запала: короткий хлопок для зарядов
    variants("explosion_small", [ex(bg, 1.2, -2.0), ex(cn, 1.3, -2.0)])


def build_vehicle():
    p = "oga_b/racing-car-engine-sound-loops/"
    idle = load(G(p + "loop_0.wav")[0])
    run = load(G(p + "loop_4_0.wav")[0])
    hi = load(G(p + "loop_5_0.wav")[0])
    # короткие записи уже зациклены; повторяем до ~2.5 с, чтобы петля не была слишком «ритмичной»
    def rep(x, secs):
        n = max(1, int(round(secs * SR / len(x))))
        return np.tile(x, n)
    # двигатель — тяжёлый: опускаем высоту ~ на кварту
    done("engine_idle", norm(rep(filt(pitch(idle, 0.92), "low", 2400), 2.6), -8.0))
    done("engine_run", norm(rep(filt(pitch(run, 0.9), "low", 3200), 2.6), -8.0))
    done("engine_high", norm(rep(pitch(hi, 0.95), 2.6), -9.0))
    cr = load(G("oga_b/crash-collision/qubodup-crash.ogg")[0])
    sl = load(G("oga_b/100-cc0-metal-and-wood-sfx/*/metal_slam_01.ogg")[0])
    gl = load(G("oga_b/75-cc0-breaking-falling-hit-sfx/*/bfh1_glass_breaking_03.ogg")[0])
    gl2 = load(G("oga_b/75-cc0-breaking-falling-hit-sfx/*/bfh1_glass_breaking_05.ogg")[0])
    mf = load(G("oga_b/100-cc0-metal-and-wood-sfx/*/metal_falling_02.ogg")[0])
    mh = load(G("oga_b/75-cc0-breaking-falling-hit-sfx/*/bfh1_metal_hit_02.ogg")[0])
    t3 = load(G("oga_b/metal-impact-sounds/thud2.wav")[0])
    items = [
        mix([(trim(cr), 0, 1.0), (trim(sl), 0.02, 0.7), (trim(gl), 0.08, 0.5)]),
        mix([(trim(sl), 0, 1.0), (trim(mh), 0.03, 0.8), (trim(gl2), 0.1, 0.45), (trim(t3), 0, 0.8)]),
        mix([(trim(cr), 0, 0.9), (trim(mf), 0.05, 0.6), (trim(t3), 0, 0.9)]),
    ]
    variants("car_crash", [norm(fade(cap(trim(x, -38, -44), 1.4, 300), 0.5, 200), -2.0) for x in items])


# ---------------------------------------------------------------- шаги

def build_steps():
    def steps(name, files, g, cap_s=0.4, lo=None, hi=None, r=1.0):
        items = []
        for f in files:
            x = load(f)
            if lo:
                x = filt(x, "high", lo)
            if hi:
                x = filt(x, "low", hi)
            if r != 1.0:
                x = pitch(x, r)
            items.append(norm(fade(cap(trim(x, -36, -42), cap_s, 80), 0.5, 60), g))
        variants(name, items)
    fz = G("oga_b/fantozzi*/*/*/ogg/")[0]
    own = G("oga_c/sound-effects-pack/**/Footsteps/")[0]
    kdd = G("oga_b/different-steps*/*/")[0]
    steps("step_dirt", [fz + "Fantozzi-Sand%s%d.ogg" % (s, n) for s in "LR" for n in (1, 2, 3)]
          + [own + "grassy-footstep2.wav", own + "grassy-footstep3.wav"], -6.0)
    steps("step_gravel", [kdd + "gravel.ogg", kdd + "stone01.ogg", fz + "Fantozzi-SandL2.ogg", fz + "Fantozzi-SandR3.ogg"],
          -6.0, r=0.95)
    steps("step_concrete", [fz + "Fantozzi-Stone%s%d.ogg" % (s, n) for s in "LR" for n in (1, 2, 3)]
          + [own + "hard-footstep1.wav", own + "hard-footstep3.wav"], -6.0)
    steps("step_metal", G("oga_b/metal-footsteps-on-concrete/*/metal_steps_0[1-8].wav")[:6], -6.0, 0.25)
    steps("step_wood", [kdd + "wood01.ogg", kdd + "wood02.ogg", kdd + "wood03.ogg"], -6.0)
    # ранение игрока / смерть бота без голосов — удары и падение
    # (hit_body используется для ранения; отдельного крика нет)


# ---------------------------------------------------------------- интерфейс, радио, прочее

def build_ui():
    d = G("oga_c/gui-sound-effects/*/*/")[0]

    def u(n, g, cap_s=0.35, r=1.0):
        x = load(d + n)
        if r != 1.0:
            x = pitch(x, r)
        return norm(fade(cap(trim(x, -38, -44), cap_s, 80), 0.5, 40), g)
    cl = load(d + "click.wav")
    cl2 = load(d + "click_2.wav")
    variants("ui_click", [norm(fade(trim(cl, -30, -36), 0.5, 30), -8.0), norm(fade(trim(cl2, -30, -36), 0.5, 30), -8.0),
                          u("misc_menu_3.wav", -9.0, 0.2)])
    variants("beep", [u("positive.wav", -8.0, 0.5), u("misc_menu_4.wav", -9.0, 0.45)])
    # рация: куски статики с огибающей и щелчками
    st = load(G("oga_d/frequency-static-sound-effects/static1.wav")[0])
    items = []
    for k, off in enumerate((3.0, 9.0, 15.0)):
        n = int((0.42 + 0.05 * k) * SR)
        s = band(seg(st, off, off + 1.0)[:n], 350, 3400)
        e = np.ones(n)
        e[:int(0.01 * SR)] = np.linspace(0, 1, int(0.01 * SR))
        e[-int(0.08 * SR):] = np.linspace(1, 0, int(0.08 * SR)) ** 2
        s = s * e
        # лёгкие щелчки открытия/закрытия канала
        tick = np.zeros(n)
        tick[:30] = 1.0
        tick[-int(0.07 * SR):-int(0.07 * SR) + 24] = -1.0
        s = s / peak(s) * 0.6 + tick * 0.5
        items.append(norm(fade(s, 0.1, 20), -6.0))
    variants("radio", items)
    # сердцебиение и огонь — петли
    hb = load(G("oga_c/heartbeat-sounds/heartbeat_slow_0.wav")[0])
    hb = trim(hb, -45, -50)
    hb = np.concatenate([hb, np.zeros(max(0, int(1.8 * SR) - len(hb)))])[:int(1.8 * SR)]
    done("heartbeat", norm(filt(hb, "low", 600), -4.0))
    fire = load(G("oga_d/fireplace-sound-loop/fire.wav")[0])
    done("fire", rms_norm(loopify(seg(fire, 2.0, 15.0), 10.0, 1.5), -22.0), q=3)


# ---------------------------------------------------------------- окружение

def amb(name, x, rms_db=-26.0):
    y = rms_norm(x, rms_db)
    if peak(y) > 0.95:
        y = y * (0.95 / peak(y))
    done(name, y, ch=2, q=3)


def build_ambience():
    def st(path):
        return load(path, 2)
    L = 40.0
    birds = st(G("oga_c/park-ambiences/park_ambience_birds.wav")[0])
    pwind = st(G("oga_c/park-ambiences/park_ambience_wind.wav")[0])
    windy = st(G("oga_c/windy-ambient-noise/windy_ambiance_0.ogg")[0])
    mild = st(G("oga_c/mild-wind-background-noise/*.wav")[0])
    n = int((L + 2) * SR)

    def chunk(x, t):
        a = int(t * SR)
        return x[a:a + n]
    # долина: ветерок и птицы
    v = chunk(pwind, 20) * 0.6 + chunk(birds, 60) * 0.9
    amb("amb_valley", loopify(v, L, 2.0), -27.0)
    # аэродром: открытое место, ровный ветер, редкие птицы вдали и сверчки
    a = chunk(windy, 30) * 0.9 + chunk(birds, 300) * 0.25
    amb("amb_airfield", loopify(a, L, 2.0), -26.0)
    # горы: сильный низкий ветер
    m = filt(chunk(windy, 90), "low", 2200) * 1.2 + chunk(mild, 0)[:n] * 0.5
    amb("amb_pass", loopify(m, L, 2.0), -23.0)
    # порт: волны, чайки, ветер с моря
    waves = [st(f) for f in G("oga_c/beach-ocean-waves/wave_0*.flac")]
    sea = st(G("oga_c/sea-and-river-wave-sounds/VistulaShort_0.mp3")[0])
    gulls = [st(f) for f in G("oga_c/solo-seagull-sound-effects/Seagull Ambient *.wav")]
    base = chunk(sea, 40) * 0.8 + chunk(pwind, 150) * 0.35
    out = base.copy()
    # поверх — волны и чайки в случайных местах (генератор с фиксированным зерном)
    for i in range(10):
        w = waves[i % len(waves)]
        o = int(RNG.uniform(0, L - 3) * SR)
        w = w[:len(out) - o]
        out[o:o + len(w)] += w * 0.5
    for i in range(5):
        gl = gulls[int(RNG.integers(len(gulls)))]
        o = int(RNG.uniform(1, L - 5) * SR)
        gl = pitch(gl, float(RNG.uniform(0.9, 1.1)))
        gl = gl[:len(out) - o]
        out[o:o + len(gl)] += gl * 0.7
    amb("amb_port", loopify(out, L, 2.0), -25.0)


# ---------------------------------------------------------------- лицензии

def write_names():
    """scripts/sfx_names.gd — список звуков и число вариантов (sfx.gd грузит по нему)."""
    cnt = {}
    for name, _ in LICENSE_ROWS:
        m = re.match(r"^(.*)_(\d+)$", name)
        base, n = (m.group(1), int(m.group(2))) if m and m.group(1) in cnt else (name, 1)
        cnt[base] = max(cnt.get(base, 0), n)
    lines = ["## Создаётся tools/build_sfx.py. Имя звука -> число вариантов (name, name_2, name_3…).", "class_name SfxNames", "",
             "const VARIANTS := {"]
    for k in sorted(cnt):
        lines.append('\t"%s": %d,' % (k, cnt[k]))
    lines.append("}")
    open(os.path.join(PROJECT, "scripts", "sfx_names.gd"), "w", encoding="utf-8").write("\n".join(lines) + "\n")


def write_licenses():
    def src_info(path):
        rel = os.path.relpath(path, STAGE)
        top = rel.split(os.sep)
        if top[0] == "ffsl":
            slug = "the-free-firearm-sound-library"
            fname = "/".join(top[2:])
        else:
            slug = top[1]
            fname = "/".join(top[2:])
        return slug, fname
    used_slugs = {}
    lines = []
    for name, paths in LICENSE_ROWS:
        names = []
        for p in paths:
            slug, f = src_info(p)
            used_slugs.setdefault(slug, set()).add(f)
            names.append(slug)
        lines.append("- `%s.ogg` — %s" % (name, ", ".join(sorted(set(names)))))
    out = ["# Источники звуков", "",
           "Все записи — CC0 (общественное достояние), использование в играх без отчислений и без обязательного указания авторства.",
           "Файлы получены с OpenGameArt.org (страницы ниже); обработаны `tools/build_sfx.py` (обрезка, нормализация, моно, OGG Vorbis).",
           "Для рикошета, свиста пуль, глушителя и рации записи дополнительно обработаны (высота, фильтры, наложение).", "",
           "## Паки", ""]
    for slug in sorted(used_slugs):
        s = SOURCES.get(slug, {})
        if slug == "the-free-firearm-sound-library":
            au = "Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (The Free Firearm Sound Library, Still North Media)"
        else:
            au = re.split(r"\s*(?:<div|\(Submitted)", s.get("author", "?"))[0].strip() or "?"
        out.append("- **%s** — автор: %s, лицензия: %s — %s" % (s.get("title", slug).replace("| OpenGameArt.org", "").strip(),
                                                              au, s.get("license", "CC0"), s.get("url", "https://opengameart.org/content/" + slug)))
    out += ["", "## Какой звук из каких паков", ""] + lines + [""]
    out += ["## Не заменено (оставлено сгенерированным, `tools/gen_assets.py`)", "", "- `ring.wav` — звон в ушах после взрыва (синтезированный тон)."]
    open(os.path.join(OUT, "LICENSES.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")


if __name__ == "__main__":
    only = set(a for a in sys.argv[4:])
    steps = [("guns", build_guns), ("mech", build_mech), ("impacts", build_impacts), ("whizz", build_whizz),
             ("expl", build_explosions), ("veh", build_vehicle), ("steps", build_steps), ("ui", build_ui),
             ("amb", build_ambience)]
    for nm, fn in steps:
        if only and nm not in only:
            continue
        print("==", nm, flush=True)
        fn()
    write_licenses()
    write_names()
    print("готово, файлов:", len(LICENSE_ROWS))
