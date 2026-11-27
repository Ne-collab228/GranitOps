class_name VehDefs
extends RefCounted
## Машины: исходные модели (CC0, assets/vehicles/src/*/SOURCE.txt) и ходовые характеристики.
## Модели склеиваются tools/flatten_vehicles.gd в assets/vehicles/<id>.res (VehicleModel): кузов — один меш
## с цветами вершин (плоские материалы исходника → цвет вершины), колесо — отдельный меш.
## После правки DEFS — перезапустить: G --headless --path . --script res://tools/flatten_vehicles.gd
##
## src — путь от assets/vehicles/src; flip — у исходника перёд смотрит в +Z (в игре перёд = −Z);
## ws — масштаб колёс и высоты кузова, sx/sz — доп. множители ширины/длины кузова (у набора rgs кузова
## мультяшно широкие); paint — имена материалов окраски (перекрашиваются в colors); glass — стёкла.
const DEFS := {
	"uaz469": {"name": "УАЗ-469", "src": "uaz469/uaz469.fbx", "flip": true, "ws": 0.65, "sx": 0.93, "sz": 1.0,
		"paint": ["soviet military vehicle paint"], "glass": ["fake glass", "mirror"],
		"colors": [Color(0.31, 0.34, 0.22), Color(0.4, 0.38, 0.28), Color(0.24, 0.27, 0.21)],
		"mass": 1650.0, "power": 4200.0, "vmax": 25.0, "brake": 60.0, "hp": 900.0, "mil": true, "offroad": 1.0},
	"uaz452": {"name": "УАЗ-452", "src": "uaz452/uaz_452.fbx", "flip": false, "ws": 1.0, "sx": 0.86, "sz": 1.0,
		"paint": [], "glass": [], "colors": [Color.WHITE], "skip": ["LicensePlate", "LicensePlateBack"],
		"mass": 1900.0, "power": 4000.0, "vmax": 23.0, "brake": 60.0, "hp": 1000.0, "mil": false, "offroad": 0.9},
	"pickup": {"name": "Пикап", "src": "rgs/Pickup.fbx", "flip": true, "ws": 0.86, "sx": 0.8, "sz": 1.12,
		"paint": ["body dark green"], "glass": ["windows"],
		"colors": [Color(0.36, 0.37, 0.27), Color(0.6, 0.53, 0.4), Color(0.85, 0.84, 0.8), Color(0.45, 0.16, 0.12)],
		"mass": 1700.0, "power": 4600.0, "vmax": 30.0, "brake": 60.0, "hp": 800.0, "mil": true, "offroad": 0.9},
	"suv": {"name": "Внедорожник", "src": "rgs/SUV.fbx", "flip": true, "ws": 0.86, "sx": 0.8, "sz": 1.1,
		"paint": ["body dark purple"], "glass": ["windows"],
		"colors": [Color(0.08, 0.08, 0.09), Color(0.32, 0.33, 0.35), Color(0.82, 0.82, 0.8), Color(0.3, 0.08, 0.09)],
		"mass": 1900.0, "power": 4800.0, "vmax": 32.0, "brake": 65.0, "hp": 800.0, "mil": false, "offroad": 0.85},
	"sedan": {"name": "Седан", "src": "rgs/Sedan.fbx", "flip": true, "ws": 0.78, "sx": 0.86, "sz": 1.12,
		"paint": ["body grey"], "glass": ["windows"],
		"colors": [Color(0.86, 0.85, 0.8), Color(0.7, 0.62, 0.48), Color(0.12, 0.17, 0.3), Color(0.5, 0.5, 0.5)],
		"mass": 1100.0, "power": 3000.0, "vmax": 33.0, "brake": 45.0, "hp": 600.0, "mil": false, "offroad": 0.6},
	"hatch": {"name": "Хэтчбек", "src": "rgs/Hatchback.fbx", "flip": true, "ws": 0.76, "sx": 0.86, "sz": 1.0,
		"paint": ["body dark yellow"], "glass": ["windows"],
		"colors": [Color(0.55, 0.1, 0.08), Color(0.85, 0.85, 0.82), Color(0.2, 0.35, 0.22), Color(0.8, 0.45, 0.12)],
		"mass": 950.0, "power": 2600.0, "vmax": 31.0, "brake": 40.0, "hp": 550.0, "mil": false, "offroad": 0.55},
	"van": {"name": "Фургон", "src": "rgs/Van.fbx", "flip": true, "ws": 0.86, "sx": 0.8, "sz": 1.0,
		"paint": ["body dark blue"], "glass": ["windows"],
		"colors": [Color(0.86, 0.86, 0.84), Color(0.45, 0.47, 0.48), Color(0.14, 0.18, 0.34)],
		"mass": 2100.0, "power": 4200.0, "vmax": 27.0, "brake": 60.0, "hp": 900.0, "mil": false, "offroad": 0.6},
}

## Сгоревший остов (статичный проп): assets/vehicles/wreck_uaz452.res
const WRECKS := {"wreck_uaz452": {"src": "uaz452/uaz_destroyed.fbx", "len": 4.36}}


static func ids() -> Array:
	return DEFS.keys()


static func military() -> Array:
	return DEFS.keys().filter(func(k): return bool(DEFS[k].mil))


static func civil() -> Array:
	return DEFS.keys().filter(func(k): return not bool(DEFS[k].mil))
