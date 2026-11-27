class_name VehicleModel
extends Resource
## Склеенная модель машины (tools/flatten_vehicles.gd). Перёд — −Z, низ колёс — y = 0, центр по X/Z — 0.
## Материалы уже лежат в поверхностях мешей (по одной поверхности на текстуру; плоские цвета — в вершинах).

## Кузов по вариантам окраски.
@export var bodies: Array[ArrayMesh] = []
## Кузов вдали: со впаянными колёсами (один вызов отрисовки на поверхность).
@export var bodies_far: Array[ArrayMesh] = []
## Колесо правой стороны, центр ступицы в 0, ось вращения — X. Левые колёса — поворот на 180° по Y.
@export var wheel: ArrayMesh
## Центры ступиц, отсортированы спереди назад (перёд — меньший z), в оси — слева направо.
@export var hubs := PackedVector3Array()
@export var wheel_r := 0.35
## Габариты кузова (AABB в координатах модели).
@export var body_aabb := AABB()
