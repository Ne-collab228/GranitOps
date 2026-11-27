"""Extra CC0 assets from Poly Haven for the second map (textures + evening sky)."""
import json
import os
import sys
import urllib.request

UA = "generic-client"
PROJECT = sys.argv[1]
API = "https://api.polyhaven.com/files/"
TEXTURES = ["forrest_ground_01", "brown_mud_leaves_01", "aerial_grass_rock", "bark_brown_02"]
SKIES = sys.argv[2:] or ["kloppenheim_06_puresky"]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def save(url, dst):
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
        return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(get(url))
    print("saved", os.path.basename(dst), os.path.getsize(dst) // 1024, "KB")


for t in TEXTURES:
    try:
        info = json.loads(get(API + t))
    except Exception as e:
        print("!! no texture", t, e)
        continue
    for key, short in (("Diffuse", "diff"), ("nor_gl", "nor"), ("arm", "arm")):
        if key in info:
            save(info[key]["1k"]["jpg"]["url"], os.path.join(PROJECT, "assets", "tex", "%s_%s.jpg" % (t, short)))
        else:
            print("!!", t, "has no", key, list(info.keys()))
for i, s in enumerate(SKIES):
    try:
        info = json.loads(get(API + s))
        save(info["hdri"]["2k"]["hdr"]["url"], os.path.join(PROJECT, "assets", "sky", "sky2_2k.hdr" if i == 0 else "sky2_alt%d.hdr" % i))
    except Exception as e:
        print("!! no sky", s, e)
