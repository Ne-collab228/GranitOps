"""Download CC0 assets from Poly Haven into the game project (1k textures, glTF models, HDRI sky)."""
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

UA = "generic-client"
PROJECT = sys.argv[1]
API = "https://api.polyhaven.com/files/"

TEXTURES = [
    "sandy_gravel_02", "dry_ground_rocks", "rock_boulder_dry",
    "concrete_wall_003", "concrete_floor_worn_001", "worn_cracked_plaster",
    "corrugated_iron_02", "rusty_metal_02", "container_side", "metal_plate",
    "wood_planks_grey", "asphalt_02", "hessian_230", "green_metal_rust",
]
MODELS = [
    "Barrel_01", "Barrel_02", "barrel_03", "wooden_crate_01", "wooden_crate_02",
    "old_tyre", "propane_tank", "utility_box_01", "metal_jerrycan_green",
    "covered_car", "ammo_box", "old_military_crate", "bolt_action_rifle_7_62",
    "service_pistol", "plastic_monobloc_chair_01", "steel_frame_shelves_01",
    "portable_generator",
]
SKY = "kloofendal_48d_partly_cloudy_puresky"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except Exception as e:
            if attempt == 3:
                raise
    return b""


def save(url, dst):
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
        return 0
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    data = get(url)
    with open(dst, "wb") as f:
        f.write(data)
    return len(data)


jobs = []
for t in TEXTURES:
    info = json.loads(get(API + t))
    for key, short in (("Diffuse", "diff"), ("nor_gl", "nor"), ("arm", "arm")):
        if key not in info:
            print("!! texture", t, "has no", key, "- keys:", list(info.keys()))
            continue
        url = info[key]["1k"]["jpg"]["url"]
        jobs.append((url, os.path.join(PROJECT, "assets", "tex", "%s_%s.jpg" % (t, short))))

for m in MODELS:
    info = json.loads(get(API + m))
    g = info["gltf"]["1k"]["gltf"]
    base = os.path.join(PROJECT, "assets", "models", m)
    jobs.append((g["url"], os.path.join(base, m + ".gltf")))
    for rel, inc in g.get("include", {}).items():
        jobs.append((inc["url"], os.path.join(base, rel.replace("/", os.sep))))

info = json.loads(get(API + SKY))
for res in ("2k", "4k"):
    jobs.append((info["hdri"][res]["hdr"]["url"], os.path.join(PROJECT, "assets", "sky", "sky_%s.hdr" % res)))

print("files to fetch:", len(jobs))
total = 0
with ThreadPoolExecutor(max_workers=8) as ex:
    for n in ex.map(lambda j: save(*j), jobs):
        total += n
print("downloaded %.1f MB" % (total / 1048576))
size = 0
for root, _, files in os.walk(os.path.join(PROJECT, "assets")):
    for fn in files:
        size += os.path.getsize(os.path.join(root, fn))
print("assets dir: %.1f MB" % (size / 1048576))
