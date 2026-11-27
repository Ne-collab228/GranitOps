class_name TerrainData
extends Resource
## Запечённый рельеф карты: сетка высот, расстояние до дорог, меши кусков (2 LOD), коллизии, дальние горы.
## Считается долго (на телефоне — десятки секунд), поэтому печётся на ПК (`-- --bake`) и кладётся в APK.
## Ключ `ver` = Level.terrain_key(): при любой правке параметров рельефа кэш пересчитывается сам.

@export var ver := ""
@export var hgrid := PackedFloat32Array()
## Расстояние до ближайшей дороги в узлах сетки (обрезано сверху ROAD_MAX м).
@export var road := PackedFloat32Array()
@export var meshes: Array[ArrayMesh] = []
@export var meshes_far: Array[ArrayMesh] = []
@export var shapes: Array[ConcavePolygonShape3D] = []
@export var outer: Array[ArrayMesh] = []
