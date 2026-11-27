"""Собирает текстуры склеенных мешей (Geo) в массивы текстур: assets/tex_arr/geo_{diff,arm,nor}.jpg
(слои друг под другом) + .import для импорта как Texture2DArray (VRAM-сжатие, мипмапы).

Один материал-массив вместо материала на текстуру: район (база, деревня) рисуется 2–4 вызовами вместо 12–25.
Порядок слоёв = Mats.ARR_LAYERS (последний — белый: плоские цвета «#rrggbb» берут оттенок из цвета вершин).
Запуск: python -I tools/gen_tex_array.py <путь к проекту>
"""
import os
import sys

from PIL import Image

LAYERS = [
    "concrete_wall_003", "concrete_floor_worn_001", "worn_cracked_plaster", "corrugated_iron_02",
    "rusty_metal_02", "container_side", "metal_plate", "wood_planks_grey", "asphalt_02", "hessian_230",
    "green_metal_rust", "rock_boulder_dry", "bark_brown_02", "white",
]
SIZE = 1024
# белый слой: альбедо белое, ORM = (AO 1, шероховатость 0.9, металл 0), нормаль плоская
WHITE = {"diff": (255, 255, 255), "arm": (255, 230, 0), "nor": (128, 128, 255)}

IMPORT = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical={n}
"""


def main() -> None:
    root = sys.argv[1]
    out_dir = os.path.join(root, "assets", "tex_arr")
    os.makedirs(out_dir, exist_ok=True)
    for kind in ("diff", "arm", "nor"):
        img = Image.new("RGB", (SIZE, SIZE * len(LAYERS)))
        for i, name in enumerate(LAYERS):
            if name == "white":
                layer = Image.new("RGB", (SIZE, SIZE), WHITE[kind])
            else:
                layer = Image.open(os.path.join(root, "assets", "tex", f"{name}_{kind}.jpg")).convert("RGB")
                if layer.size != (SIZE, SIZE):
                    layer = layer.resize((SIZE, SIZE), Image.LANCZOS)
            img.paste(layer, (0, i * SIZE))
        path = os.path.join(out_dir, f"geo_{kind}.jpg")
        img.save(path, quality=93)
        imp = path + ".import"
        # .import пишем только если его нет: Godot дописывает в него uid и пути, перезапись сбила бы их
        if not os.path.exists(imp):
            with open(imp, "w", encoding="utf-8") as f:
                f.write(IMPORT.format(n=len(LAYERS)))
        print(path, img.size)


if __name__ == "__main__":
    main()
