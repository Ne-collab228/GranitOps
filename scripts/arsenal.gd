class_name Arsenal
extends RefCounted
## Каталог оружия и обвесов, расчёт итоговых характеристик, хранение снаряжения игрока.

const LONG := ["ar", "akm", "smg", "lmg", "dmr", "sg", "sr"]
const SIDE := ["pistol"]
const SLOT_TITLES := ["ОСНОВНОЕ", "ВТОРОЕ", "ПИСТОЛЕТ"]

const WEAPONS := {
	"ar": {"id": "ar", "name": "ШВ-5", "cal": "5,56 мм", "cls": "Штурмовая винтовка", "mag": 30, "reserve": 150, "rpm": 720.0, "dmg": 34.0,
		"speed": 880.0, "auto": true, "recoil": Vector2(0.95, 0.4), "hip": 2.4, "ads": 0.07, "ads_time": 0.2, "reload": 2.3,
		"sound": "shot_rifle", "pitch": 1.0, "zero": 100.0, "drag": 0.28, "kick": 0.03, "tracer": 3, "noise": 120.0,
		"slots": ["optic", "muzzle", "barrel", "grip", "mag", "stock", "laser", "camo"], "optics": ["iron", "rds", "holo", "x3", "x6", "thermal"],
		"defaults": {"optic": "rds", "camo": "sand"}},
	"akm": {"id": "akm", "name": "АКМ-7", "cal": "7,62 мм", "cls": "Штурмовая винтовка", "mag": 30, "reserve": 120, "rpm": 600.0, "dmg": 43.0,
		"speed": 715.0, "auto": true, "recoil": Vector2(1.35, 0.62), "hip": 2.7, "ads": 0.1, "ads_time": 0.23, "reload": 2.5,
		"sound": "shot_rifle", "pitch": 0.86, "zero": 100.0, "drag": 0.36, "kick": 0.038, "tracer": 3, "noise": 130.0,
		"slots": ["optic", "muzzle", "barrel", "grip", "mag", "stock", "laser", "camo"], "optics": ["iron", "rds", "holo", "x3", "thermal"],
		"defaults": {"optic": "iron", "camo": "wood"}},
	"smg": {"id": "smg", "name": "ПП-9 «Шершень»", "cal": "9 мм", "cls": "Пистолет-пулемёт", "mag": 30, "reserve": 180, "rpm": 900.0, "dmg": 25.0,
		"speed": 400.0, "auto": true, "recoil": Vector2(0.62, 0.34), "hip": 1.7, "ads": 0.14, "ads_time": 0.15, "reload": 1.9,
		"sound": "shot_pistol", "pitch": 1.12, "zero": 50.0, "drag": 0.62, "kick": 0.02, "tracer": 0, "noise": 85.0,
		"slots": ["optic", "muzzle", "grip", "mag", "stock", "laser", "camo"], "optics": ["iron", "rds", "holo"],
		"defaults": {"optic": "rds", "camo": "black"}},
	"lmg": {"id": "lmg", "name": "РПЛ-7", "cal": "7,62 мм", "cls": "Ручной пулемёт", "mag": 100, "reserve": 200, "rpm": 660.0, "dmg": 40.0,
		"speed": 800.0, "auto": true, "recoil": Vector2(1.05, 0.55), "hip": 3.6, "ads": 0.11, "ads_time": 0.34, "reload": 5.2,
		"sound": "shot_rifle", "pitch": 0.78, "zero": 100.0, "drag": 0.3, "kick": 0.034, "tracer": 2, "noise": 135.0, "move": 0.9,
		"slots": ["optic", "muzzle", "barrel", "grip", "mag", "stock", "laser", "camo"], "optics": ["iron", "rds", "holo", "x3", "thermal"],
		"defaults": {"optic": "holo", "camo": "olive"}},
	"dmr": {"id": "dmr", "name": "СВМ-76", "cal": "7,62 мм", "cls": "Марксманская винтовка", "mag": 10, "reserve": 60, "rpm": 280.0, "dmg": 76.0,
		"speed": 830.0, "auto": false, "recoil": Vector2(2.3, 0.55), "hip": 3.8, "ads": 0.03, "ads_time": 0.26, "reload": 2.7,
		"sound": "shot_sniper", "pitch": 1.12, "zero": 150.0, "drag": 0.22, "kick": 0.055, "tracer": 0, "noise": 145.0,
		"slots": ["optic", "muzzle", "barrel", "grip", "mag", "stock", "laser", "camo"], "optics": ["iron", "rds", "x3", "x6", "thermal"],
		"defaults": {"optic": "x3", "camo": "black"}},
	"sg": {"id": "sg", "name": "КС-12", "cal": "12 калибр", "cls": "Дробовик", "mag": 7, "reserve": 42, "rpm": 75.0, "dmg": 17.0, "pellets": 9,
		"speed": 400.0, "auto": false, "recoil": Vector2(3.6, 0.9), "hip": 3.4, "ads": 2.3, "ads_time": 0.2, "reload": 3.4,
		"sound": "shot_sniper", "pitch": 0.72, "zero": 25.0, "drag": 1.3, "kick": 0.08, "tracer": 0, "noise": 120.0, "pump": true,
		"slots": ["optic", "muzzle", "mag", "stock", "laser", "camo"], "optics": ["iron", "rds", "holo"],
		"defaults": {"optic": "iron", "camo": "black"}},
	"sr": {"id": "sr", "name": "СВ-7", "cal": "7,62 мм", "cls": "Снайперская винтовка", "mag": 5, "reserve": 35, "rpm": 50.0, "dmg": 115.0,
		"speed": 820.0, "auto": false, "recoil": Vector2(3.4, 0.6), "hip": 4.5, "ads": 0.012, "ads_time": 0.3, "reload": 3.2,
		"sound": "shot_sniper", "pitch": 1.0, "zero": 200.0, "drag": 0.2, "kick": 0.075, "tracer": 0, "noise": 160.0, "bolt": true,
		"slots": ["optic", "muzzle", "mag"], "optics": ["x6", "x10", "thermal"], "defaults": {"optic": "x6"}},
	"pistol": {"id": "pistol", "name": "П-9", "cal": "9 мм", "cls": "Пистолет", "mag": 15, "reserve": 60, "rpm": 420.0, "dmg": 27.0,
		"speed": 375.0, "auto": false, "recoil": Vector2(1.7, 0.5), "hip": 1.7, "ads": 0.22, "ads_time": 0.14, "reload": 1.7,
		"sound": "shot_pistol", "pitch": 1.0, "zero": 25.0, "drag": 0.6, "kick": 0.028, "tracer": 0, "noise": 70.0, "slide": true,
		"slots": ["muzzle", "mag", "laser"], "optics": ["iron"], "defaults": {}},
}

## Слоты обвеса: заголовок и варианты. Первый вариант — «пусто/штатный».
const SLOTS := {
	"optic": {"title": "Прицел", "items": [
		["iron", "Штатный (механика)"], ["rds", "Коллиматор «Точка»"], ["holo", "Голограф «Кольцо»"],
		["x3", "Оптика ×3"], ["x6", "Оптика ×6"], ["x10", "Оптика ×10"], ["thermal", "Тепловизор ×4"]]},
	"muzzle": {"title": "Дульное устройство", "items": [
		["none", "Штатное"], ["supp", "Глушитель"], ["comp", "Компенсатор"], ["flash", "Пламегаситель"]]},
	"barrel": {"title": "Ствол", "items": [["std", "Штатный"], ["long", "Длинный"], ["short", "Укороченный"]]},
	"grip": {"title": "Цевьё", "items": [["none", "Без рукоятки"], ["vert", "Вертикальная рукоятка"], ["angled", "Угловая рукоятка"]]},
	"mag": {"title": "Магазин", "items": [["std", "Штатный"], ["ext", "Увеличенный"], ["fast", "Быстросменный"]]},
	"stock": {"title": "Приклад", "items": [["std", "Штатный"], ["light", "Облегчённый"], ["heavy", "Усиленный"]]},
	"laser": {"title": "Тактический блок", "items": [["none", "Нет"], ["laser", "Лазерный целеуказатель"]]},
	"camo": {"title": "Окраска", "items": [
		["black", "Чёрный"], ["sand", "Песок"], ["olive", "Олива"], ["grey", "Городской серый"], ["arctic", "Арктика"], ["wood", "Дерево"]]},
}

const OPTICS := {
	"iron": {"fov": 56.0, "t": 1.0, "scope": false},
	"rds": {"fov": 54.0, "t": 1.0, "scope": false},
	"holo": {"fov": 52.0, "t": 1.04, "scope": false},
	"x3": {"fov": 27.0, "t": 1.15, "scope": true},
	"x6": {"fov": 14.0, "t": 1.3, "scope": true},
	"x10": {"fov": 8.8, "t": 1.45, "scope": true},
	"thermal": {"fov": 19.0, "t": 1.3, "scope": true},
}

const HINTS := {
	"rds": "Быстрое прицеливание, без увеличения", "holo": "Большое окно, чуть медленнее", "x3": "Средние дистанции",
	"x6": "Дальние дистанции, долгий вход в прицел", "x10": "Сверхдальние дистанции",
	"thermal": "Видит тепло: противники светятся даже в тени и кустах",
	"supp": "Тихий выстрел без вспышки, ниже скорость пули", "comp": "Меньше подброс ствола, громче",
	"flash": "Меньше увод в стороны", "long": "Выше скорость пули и точность, медленнее прицел",
	"short": "Быстрее прицел, ниже точность и скорость пули", "vert": "Меньше подброс", "angled": "Быстрее прицел, меньше увод",
	"ext": "+50% патронов, дольше перезарядка", "fast": "Быстрая перезарядка", "light": "Быстрее прицел, сильнее отдача",
	"heavy": "Слабее отдача, медленнее прицел", "laser": "Точнее стрельба от бедра",
}


static func default_att(id: String) -> Dictionary:
	var w: Dictionary = WEAPONS[id]
	var out := {}
	for s in w.slots:
		out[s] = SLOTS[s].items[0][0]
	if not (out.get("optic", "iron") in w.optics):
		out["optic"] = w.optics[0]
	for k in w.defaults:
		out[k] = w.defaults[k]
	return out


## Варианты слота, доступные конкретному оружию.
static func items_for(id: String, slot: String) -> Array:
	var all: Array = SLOTS[slot].items
	if slot == "optic":
		return all.filter(func(it): return it[0] in WEAPONS[id].optics)
	if id == "sr" or id == "pistol":
		if slot == "muzzle":
			return all.filter(func(it): return it[0] in ["none", "supp"])
		if slot == "mag":
			return all.filter(func(it): return it[0] in ["std", "ext"])
	if id == "sg" and slot == "mag":
		return all.filter(func(it): return it[0] in ["std", "ext"])
	return all


## Снаряжение игрока из настроек (с подстановкой значений по умолчанию).
static func loadout() -> Dictionary:
	var raw: Dictionary = Settings.data.get("loadout", {})
	var slots: Array = raw.get("slots", [])
	if slots.size() != 3 or not (slots[0] in LONG) or not (slots[1] in LONG) or not (slots[2] in SIDE) or slots[0] == slots[1]:
		slots = ["ar", "sr", "pistol"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gun=") and arg.get_slice("=", 1) in LONG:
			slots = [arg.get_slice("=", 1), "sr" if arg.get_slice("=", 1) != "sr" else "ar", "pistol"]
	var att := {}
	var saved: Dictionary = raw.get("att", {})
	for id in WEAPONS:
		var a := default_att(id)
		var sv: Dictionary = saved.get(id, {})
		for s in a:
			if sv.has(s) and items_for(id, s).any(func(it): return it[0] == sv[s]):
				a[s] = sv[s]
		att[id] = a
	return {"slots": slots, "att": att}


static func store(lo: Dictionary) -> void:
	Settings.data.loadout = lo
	Settings.save()


## Итоговые характеристики оружия с учётом обвеса.
static func effective(id: String, att: Dictionary) -> Dictionary:
	var d: Dictionary = (WEAPONS[id] as Dictionary).duplicate(true)
	var rec: Vector2 = d.recoil
	var o: Dictionary = OPTICS[att.get("optic", "iron")]
	d["optic"] = att.get("optic", "iron")
	d["ads_fov"] = float(o.fov) + (6.0 if id == "pistol" else 0.0)
	d["scope"] = bool(o.scope)
	d["ads_time"] = float(d.ads_time) * float(o.t)
	d["flash"] = 1.4 if d.get("bolt", false) or d.get("pump", false) else 1.0
	d["vol"] = -3.0
	d["move"] = float(d.get("move", 1.0))
	d["pellets"] = int(d.get("pellets", 1))
	match att.get("muzzle", "none"):
		"supp":
			d.noise = float(d.noise) * 0.22
			d.speed = float(d.speed) * 0.96
			rec *= 0.94
			d.ads_time = float(d.ads_time) * 1.06
			d.flash = 0.0
			d.vol = -13.0
			d.pitch = float(d.pitch) * 1.35
			d.tracer = 0
		"comp":
			rec.x *= 0.8
			d.noise = float(d.noise) * 1.1
		"flash":
			rec.y *= 0.74
			d.flash = float(d.flash) * 0.55
	match att.get("barrel", "std"):
		"long":
			d.speed = float(d.speed) * 1.1
			d.drag = float(d.drag) * 0.9
			d.ads = float(d.ads) * 0.78
			d.ads_time = float(d.ads_time) * 1.1
			d.hip = float(d.hip) * 1.1
		"short":
			d.speed = float(d.speed) * 0.9
			d.ads = float(d.ads) * 1.3
			d.ads_time = float(d.ads_time) * 0.88
			d.hip = float(d.hip) * 0.9
			d.move = float(d.move) * 1.03
	match att.get("grip", "none"):
		"vert":
			rec.x *= 0.86
			d.ads_time = float(d.ads_time) * 1.04
		"angled":
			rec.y *= 0.88
			d.ads_time = float(d.ads_time) * 0.9
	match att.get("mag", "std"):
		"ext":
			d.mag = int(round(float(d.mag) * (1.3 if id == "sg" else 1.5)))
			d.reload = float(d.reload) * 1.12
			d.ads_time = float(d.ads_time) * 1.04
		"fast":
			d.reload = float(d.reload) * 0.78
	match att.get("stock", "std"):
		"light":
			d.ads_time = float(d.ads_time) * 0.86
			rec *= 1.1
			d.move = float(d.move) * 1.04
		"heavy":
			rec *= 0.86
			d.ads_time = float(d.ads_time) * 1.1
	if att.get("laser", "none") == "laser":
		d.hip = float(d.hip) * 0.68
	d.recoil = rec
	return d


## Шкалы для экрана оружейной: [название, значение 0..1].
static func bars(d: Dictionary) -> Array:
	var rec: Vector2 = d.recoil
	return [
		["Урон", clampf(float(d.dmg) * float(d.pellets) / 130.0, 0.05, 1.0)],
		["Темп огня", clampf(float(d.rpm) / 950.0, 0.05, 1.0)],
		["Контроль отдачи", clampf(1.0 - (rec.x + rec.y) / 4.6, 0.05, 1.0)],
		["Точность", clampf(1.0 - float(d.ads) * 2.6 - float(d.hip) / 14.0, 0.05, 1.0)],
		["Скорость прицеливания", clampf(1.0 - (float(d.ads_time) - 0.1) / 0.4, 0.05, 1.0)],
		["Дальность", clampf(float(d.speed) / 950.0 * (1.0 - float(d.drag) * 0.35), 0.05, 1.0)],
		["Скрытность", clampf(1.0 - float(d.noise) / 175.0, 0.03, 1.0)],
	]
