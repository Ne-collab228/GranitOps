class_name MapValley
extends Level
## Карта 1: долина «Гранит» (1,26 x 1,26 км). В центре — опорная база, вокруг: блокпост, РЛС на холме,
## деревня Каменка (восток), колхоз с элеватором у сухого русла (юго-запад), карьер со складом
## взрывчатки (север), укреплённая высота (юго-восток), точка эвакуации в северо-восточном углу.

const RADAR := Vector2(-118.0, -92.0)
const LZ := Vector2(430.0, -420.0)
const CHECKPOINT := Vector2(8.0, 92.0)
const SPAWN := Vector2(10.0, 178.0)
const VILLAGE := Vector2(335.0, 40.0)
const FARM := Vector2(-320.0, 290.0)
const QUARRY := Vector2(-40.0, -410.0)
const HILLFORT := Vector2(330.0, 350.0)
## Сухое русло: с севера на юг западнее базы.
const RIVER := [Vector2(-470, -640), Vector2(-390, -320), Vector2(-260, -130), Vector2(-232, 60), Vector2(-250, 240), Vector2(-190, 440), Vector2(-160, 640)]

var radar_dish: Node3D
var radar_alive := true
var fuel_node: MeshInstance3D
var radar_node: MeshInstance3D
var noise_c := FastNoiseLite.new()


func _configure() -> void:
	map_key = "valley"
	title = "Долина «Гранит»"
	size = 1260.0
	# куски по 315 м: 16 штук (меньше вызовов отрисовки), дальний LOD — ячейка 9 м
	chunk = 105
	lod_dist = 260.0
	play_half = 570.0
	outer_half = 2430.0
	outer_cell = 30.0
	spawn_max_h = 45.0
	nav_aabb = AABB(Vector3(-575, -40, -575), Vector3(1150, 200, 1150))
	orbit_center = Vector3(0, 5, -9)
	orbit_radius = 140.0
	orbit_height = 40.0
	site_points = [Vector3(CHECKPOINT.x, CHECKPOINT.y, 0), Vector3(RADAR.x, RADAR.y, 0), Vector3(LZ.x, LZ.y, 0), Vector3(SPAWN.x, SPAWN.y, 0),
		Vector3(VILLAGE.x, VILLAGE.y, 90), Vector3(FARM.x, FARM.y, 60), Vector3(QUARRY.x, QUARRY.y, 60), Vector3(HILLFORT.x, HILLFORT.y, 20)]


func _setup_noise() -> void:
	super._setup_noise()
	noise_c.seed = 21
	noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_c.frequency = 0.0021
	noise_c.fractal_octaves = 3


func _build_sites() -> void:
	_build_compound()
	_build_checkpoint()
	_build_radar()
	_build_lz()
	_build_field_cover()
	await get_tree().process_frame
	_build_village()
	_build_farm()
	await get_tree().process_frame
	_build_quarry()
	_build_hillfort()
	blast_fx["fuel"] = {"fires": [[Vector3(-5, 0.5, -4), 1.5], [Vector3(5, 0.5, -4), 1.5], [Vector3(0, 0.5, -6), 1.5]],
		"blasts": [[0.5, Vector3(-5, 1, -4)], [1.1, Vector3(5, 1, -5)]]}
	_define_vehicles()
	blast_fx["depot"] = {"fires": [[Vector3(-3, 0.5, 0), 1.4], [Vector3(3, 0.5, 1), 1.2]],
		"blasts": [[0.4, Vector3(-3, 1, 0)], [0.9, Vector3(4, 1, -2)], [1.6, Vector3(0, 1, 3)]]}


## Задачи операции для этой карты.
func mission_objectives() -> Array:
	return [
		{"id": "radar", "title": "Уничтожить РЛС на холме", "pos": objectives.radar, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "fuel", "title": "Подорвать топливный склад", "pos": objectives.fuel, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "intel", "title": "Забрать разведданные в штабе", "pos": objectives.intel, "done": false, "prompt": "Забрать разведданные", "hold": 1.2, "armed": false},
		{"id": "depot", "title": "Взорвать склад взрывчатки в карьере", "pos": objectives.depot, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "lz", "title": "Выйти к точке эвакуации", "pos": objectives.lz, "done": false, "locked": true, "prompt": "", "hold": 0.0, "armed": false},
	]


func briefing() -> String:
	return "Противник развернул в долине опорную базу и держит окрестные посёлки. Вы высаживаетесь на краю долины.\n\n" \
		+ "• Уничтожить РЛС на холме северо-западнее базы\n• Подорвать топливный склад на базе\n" \
		+ "• Забрать разведданные на втором этаже штаба\n• Взорвать склад взрывчатки в карьере на севере\n" \
		+ "• Выйти к точке эвакуации в северо-восточном углу долины\n\nВ деревне на востоке, в колхозе и на высоте — гарнизоны противника."


func bench_views() -> Array:
	return [["снаружи, вид на базу", Vector3(95, 0, 95), Vector3(0, 3, 0)],
		["двор, на север", Vector3(0, 0, -5), Vector3(0, 3, -60)],
		["у штаба, на восток", Vector3(-18, 0, -30), Vector3(40, 3, -30)],
		["у ангара, на запад", Vector3(50, 0, 30), Vector3(-30, 3, 20)],
		["с юга издалека", Vector3(0, 0, 150), Vector3(0, 3, 0)],
		["деревня, улица", Vector3(250, 0, 44), Vector3(380, 3, 40)],
		["колхоз", Vector3(-250, 0, 230), Vector3(-320, 6, 290)],
		["карьер сверху", Vector3(-40, 0, -300), Vector3(-40, -8, -410)],
		["высота", Vector3(260, 0, 290), Vector3(330, 4, 350)],
		["горизонт с холма", Vector3(-118, 0, -70), Vector3(300, 20, 300)]]


## Доля «утоптанной земли» в точке (двор базы, улица деревни, двор колхоза, дно карьера).
func _yard_weight(x: float, z: float) -> float:
	var w := (1.0 - smoothstep(0.0, 8.0, maxf(maxf(absf(x) - 70.0, absf(z + 9.0) - 59.0), 0.0))) * 0.3
	w = maxf(w, (1.0 - smoothstep(0.0, 10.0, maxf(maxf(absf(x - FARM.x) - 45.0, absf(z - FARM.y) - 32.0), 0.0))) * 0.35)
	w = maxf(w, (1.0 - smoothstep(0.0, 14.0, maxf(maxf(absf(x - QUARRY.x) - 40.0, absf(z - QUARRY.y) - 28.0), 0.0))) * 0.45)
	return w


func _terrain_tex() -> Dictionary:
	return {"a": "sandy_gravel_02", "b": "dry_ground_rocks", "r": "rock_boulder_dry"}


## Цветокоррекция и свет (бесплатно для GPU): тёплое солнце, холодные тени, воздушная перспектива,
## чуть больше контраста — картинка объёмнее без новых проходов рендера.
func _tune_environment() -> void:
	env.tonemap_exposure = 1.04
	env.adjustment_contrast = 1.13
	env.adjustment_saturation = 1.1
	env.ambient_light_color = Color(0.6, 0.65, 0.74)
	env.ambient_light_sky_contribution = 0.5
	env.fog_light_color = Color(0.66, 0.72, 0.82)
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.3
	env.fog_sun_scatter = 0.18
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.25


func _setup_pads() -> void:
	roads = [
		# главная дорога с юга через блокпост к южным воротам базы
		PackedVector2Array([Vector2(12, 600), Vector2(14, 470), Vector2(10, 400), Vector2(10, 300), Vector2(10, 208), Vector2(10, 150), Vector2(9, 120), Vector2(8, 92), Vector2(4, 70), Vector2(0, 52), Vector2(0, 18)]),
		# восточные ворота — деревня — восточный край
		PackedVector2Array([Vector2(70, -12), Vector2(110, -14), Vector2(170, 2), Vector2(240, 38), Vector2(330, 40), Vector2(430, 42), Vector2(600, 70)]),
		# к РЛС
		PackedVector2Array([Vector2(-70, 9.7), Vector2(-94, -18), Vector2(-108, -58), Vector2(-116, -82)]),
		# на северо-восток к точке эвакуации
		PackedVector2Array([Vector2(70, -12), Vector2(88, -70), Vector2(112, -138), Vector2(190, -220), Vector2(300, -320), Vector2(415, -410)]),
		# на запад через брод к колхозу
		PackedVector2Array([Vector2(-70, 9.7), Vector2(-150, 22), Vector2(-232, 48), Vector2(-275, 140), Vector2(-305, 250)]),
		# к карьеру
		PackedVector2Array([Vector2(-108, -58), Vector2(-112, -160), Vector2(-84, -280), Vector2(-50, -370)]),
		# из деревни на юг к высоте и на главную дорогу
		PackedVector2Array([Vector2(330, 40), Vector2(342, 170), Vector2(330, 300), Vector2(326, 338)]),
		PackedVector2Array([Vector2(14, 470), Vector2(150, 420), Vector2(250, 360), Vector2(318, 350)]),
	]
	pads = [
		{"c": Vector2(0, -9), "half": Vector2(77, 66), "m": 30.0, "h": H0},
		{"c": CHECKPOINT, "half": Vector2(14, 13), "m": 14.0, "h": base_height(CHECKPOINT.x, CHECKPOINT.y)},
		{"c": RADAR, "half": Vector2(11, 10), "m": 18.0, "h": base_height(RADAR.x, RADAR.y) - 0.6},
		{"c": LZ, "half": Vector2(10, 10), "m": 16.0, "h": base_height(LZ.x, LZ.y)},
		{"c": SPAWN, "half": Vector2(5, 5), "m": 12.0, "h": base_height(SPAWN.x, SPAWN.y)},
		{"c": VILLAGE, "half": Vector2(98, 24), "m": 40.0, "h": base_height(VILLAGE.x, VILLAGE.y)},
		{"c": FARM, "half": Vector2(55, 42), "m": 32.0, "h": base_height(FARM.x, FARM.y)},
		{"c": QUARRY, "half": Vector2(42, 30), "m": 28.0, "h": base_height(QUARRY.x, QUARRY.y) - 13.0},
		{"c": HILLFORT, "half": Vector2(16, 14), "m": 22.0, "h": base_height(HILLFORT.x, HILLFORT.y)},
	]


func base_height(x: float, z: float) -> float:
	var h := noise_a.get_noise_2d(x, z) * 9.0 + noise_b.get_noise_2d(x, z) * 1.4 + 4.0
	# крупные холмы — дальше от базы (рядом с ней рельеф как раньше)
	var db := Vector2(x, z + 9.0).length()
	h += noise_c.get_noise_2d(x, z) * 16.0 * smoothstep(130.0, 300.0, db)
	var d2 := Vector2(x - RADAR.x, z - RADAR.y).length_squared()
	h += 13.0 * exp(-d2 / (2.0 * 30.0 * 30.0))
	# гребень на юге, с которого раньше высаживались
	h += 5.0 * exp(-pow((z - 172.0) / 20.0, 2.0)) * exp(-pow((x - 10.0) / 70.0, 2.0))
	# высота на юго-востоке
	h += 24.0 * exp(-Vector2(x - HILLFORT.x, z - HILLFORT.y).length_squared() / (2.0 * 60.0 * 60.0))
	# отвалы вокруг карьера
	var dq := Vector2(x - QUARRY.x, z - QUARRY.y).length()
	h += 9.0 * exp(-pow((dq - 80.0) / 26.0, 2.0))
	# сухое русло
	var p := Vector2(x, z)
	var dr := 999.0
	for i in RIVER.size() - 1:
		dr = minf(dr, p.distance_to(Geometry2D.get_closest_point_to_segment(p, RIVER[i], RIVER[i + 1])))
	h -= 6.5 * (1.0 - smoothstep(5.0, 30.0, dr))
	# горы по краю и за границей игровой зоны
	var e := maxf(absf(x), absf(z))
	var b := smoothstep(500.0, 650.0, e)
	h += b * b * 60.0 + b * noise_b.get_noise_2d(x * 0.6, z * 0.6) * 5.0
	var far := maxf(e - 600.0, 0.0)
	if far > 0.0:
		var ridge := 1.0 - absf(noise_a.get_noise_2d(x * 0.35 + 900.0, z * 0.35))
		h += far * 0.06 + ridge * ridge * minf(far, 900.0) * 0.16
	return h


## Дом-заглушка: коробка с проёмами и двускатной крышей (позже — Bld).
func _house(g: Geo, cx: float, cz: float, w: float, d: float, floors: int, mat: String, door_side: String) -> void:
	var y := _ground_min(cx, cz, maxf(w, d) * 0.5) - 0.05
	var h := 2.9
	var ops := {"s": [win(1.0), win(w - 2.3)], "n": [win(1.0), win(w - 2.3)], "e": [win(d * 0.5 - 0.65)], "w": [win(d * 0.5 - 0.65)]}
	var dl: Array = ops[door_side]
	if door_side == "s" or door_side == "n":
		dl.append(door(w * 0.5 - 0.6, 1.2))
	else:
		ops[door_side] = [door(d * 0.5 - 0.6, 1.2)]
	_building(g, cx, cz, w, d, h, mat, ops, y, "floor", 0.3, true, floors == 1)
	if floors > 1:
		g.box("floor", Vector3(cx + 0.9, y + h, cz), Vector3(w - 2.4, 0.2, d - 0.6))
		g.stairs("floor", Vector3(cx - w * 0.5 + 0.95, y, cz + d * 0.5 - 0.6), 0.0, 1.0, h, minf(d - 1.4, 4.6))
		_building(g, cx, cz, w, d, h, mat, {"s": [win(1.0), win(w - 2.3)], "n": [win(1.0), win(w - 2.3)]}, y + h, "concrete", 0.3, false, true)
		return
	# двускатная крыша из двух наклонных плит
	var rh := 1.6
	var ang := atan2(rh, d * 0.5 + 0.4)
	var slab := Vector3(w + 0.6, 0.12, (d * 0.5 + 0.5) / cos(ang))
	for s in [-1.0, 1.0]:
		g.box("rust", Vector3(cx, y + h + 0.2 + rh * 0.5, cz + s * (d * 0.25 + 0.12)), slab, 0.0, false, -s * ang)
	# фронтоны
	for sx in [-1.0, 1.0]:
		for k in 3:
			var hh := rh * (1.0 - k / 3.0)
			g.box(mat, Vector3(cx + sx * (w * 0.5 - 0.15), y + h + 0.2 + rh * k / 3.0 + rh / 6.0, cz), Vector3(0.3, rh / 3.0, (d - 0.3) * hh / rh), 0.0, false)


## Стоянки машин и патрули на дорогах (сами машины ставит Level.spawn_vehicles при старте миссии).
func _define_vehicles() -> void:
	var c := CHECKPOINT
	var v := VILLAGE
	var f := FARM
	var q := QUARRY
	vehicle_spots = [
		# база: двор и у ворот
		[Vector3(-8, 0, 4), 0.0, "mil"], [Vector3(-30, 0, 18), 1.57, "mil"], [Vector3(22, 0, 12), 3.0, "mil"],
		[Vector3(-44, 0, -42), 0.0, "mil"], [Vector3(84, 0, -4), 1.57, "mil"],
		# блокпост
		[Vector3(c.x - 8.0, 0, c.y + 12.0), 0.2, "mil"],
		# деревня: на улице и во дворах
		[Vector3(v.x - 70.0, 0, v.y + 5.0), 1.57, "civ"], [Vector3(v.x - 8.0, 0, v.y - 5.0), -1.57, "civ"],
		[Vector3(v.x + 30.0, 0, v.y + 5.0), 1.6, "civ"], [Vector3(v.x + 75.0, 0, v.y - 6.0), -1.5, "civ"],
		[Vector3(v.x - 30.0, 0, v.y + 8.0), 1.57, "mil"],
		# колхоз
		[Vector3(f.x + 12.0, 0, f.y + 24.0), 0.4, "any"], [Vector3(f.x - 2.0, 0, f.y - 14.0), 1.2, "civ"], [Vector3(f.x + 38.0, 0, f.y - 10.0), 0.0, "civ"],
		# карьер и высота
		[Vector3(q.x + 14.0, 0, q.y + 20.0), 2.4, "mil"], [Vector3(q.x - 4.0, 0, q.y + 26.0), 0.3, "mil"],
		[Vector3(HILLFORT.x - 6.0, 0, HILLFORT.y + 22.0), 0.0, "mil"],
		# брошенные у дорог
		[Vector3(18, 0, 300), 0.1, "civ"], [Vector3(205, 0, 26), 2.0, "civ"], [Vector3(-190, 0, 40), 1.4, "civ"],
		[Vector3(250, 0, -275), 0.8, "any"], [Vector3(-104, 0, -200), 3.0, "any"], [Vector3(160, 0, 430), 1.2, "civ"],
	]
	vehicle_patrols = [[1, 2], [3, 3], [4, 2], [0, 2]]


# ------------------------------------------------------------------ деревня Каменка (восток)
func _build_village() -> void:
	var g := Geo.new()
	var c := VILLAGE
	var saved := rng.state
	rng.seed = 7301
	var mats := ["plaster", "plaster_tan", "plaster", "wood"]
	for side: float in [-1.0, 1.0]:
		for i in 6:
			var x := c.x - 82.0 + i * 31.0 + rng.randf_range(-3.0, 3.0)
			if side > 0.0 and i == 2:
				continue
			var z := c.y + side * 15.0
			var w := rng.randf_range(7.0, 9.5)
			var d := rng.randf_range(6.5, 8.0)
			var floors := 2 if rng.randf() < 0.25 else 1
			_house(g, x, z, w, d, floors, mats[rng.randi() % mats.size()], "s" if side < 0.0 else "n")
			# сарай во дворе и забор
			var by := _ground_min(x + 5.0, z + side * 12.0, 2.0)
			_building(g, x + 5.0, z + side * 12.0, 3.4, 3.0, 2.3, "wood", {"w": [door(0.8, 1.2)]}, by, "iron", 0.12)
			for k in [-1.0, 1.0]:
				_fence(g, Vector2(x + k * 7.5, z - side * 5.5), Vector2(x + k * 7.5, z + side * 17.0), ground(x + k * 7.5, z) - 0.05, 1.6)
			for k in 4:
				cover(x + rng.randf_range(-5, 5), z - side * 6.5)
	# сельсовет — 2 этажа, укреплён (гарнизон)
	var sx := c.x - 20.0
	var sz := c.y + 15.0
	var sy := _ground_min(sx, sz, 8.0)
	_building(g, sx, sz, 14, 10, 3.2, "plaster_tan", {"n": [win(1.5), door(6.2), win(10.5)], "s": [win(2.0), win(7.0), win(11.0)], "e": [win(4.0)], "w": [win(4.0)]}, sy, "floor", 0.3, true, false)
	g.box("floor", Vector3(sx + 1.0, sy + 3.1, sz), Vector3(11.8, 0.2, 10))
	g.stairs("floor", Vector3(sx - 6.2, sy, sz + 4.2), 0.0, 1.2, 3.2, 4.6)
	_building(g, sx, sz, 14, 10, 3.0, "plaster_tan", {"n": [win(1.5), win(6.2), win(10.5)], "s": [win(2.0), win(7.0), win(11.0)], "e": [win(4.0)], "w": [win(4.0)]}, sy + 3.2, "concrete", 0.3, false, true)
	_sandbags(g, Vector2(sx - 4.0, sz - 7.5), Vector2(sx + 4.0, sz - 7.5), sy)
	_ammo_crate(sx + 4.5, sz + 2.5, sy + 0.08, 0.3)
	# магазин у дороги
	var mx := c.x + 40.0
	var mz := c.y - 15.0
	_building(g, mx, mz, 10, 7, 3.2, "plaster", {"s": [[1.0, 4.0, 0.6, 2.6], door(5.0, 1.4), [7.0, 9.2, 0.6, 2.6]], "n": [door(4.4, 1.2)]}, _ground_min(mx, mz, 5.0), "concrete")
	# брошенная техника и баррикады на улице
	_truck(g, c.x - 50.0, c.y + 2.0, 1.45, ground(c.x - 50.0, c.y + 2.0) - 0.05)
	_wreck(g, c.x + 70.0, c.y - 3.0, 1.2)
	for b in [[c.x - 35.0, c.y - 2.0, 1.3], [c.x + 12.0, c.y + 3.0, 1.7], [c.x + 58.0, c.y + 1.0, 1.5]]:
		_barrier(g, b[0], b[1], b[2], ground(b[0], b[1]) - 0.05)
	_barrels(c.x + 25.0, c.y + 6.0, 3, ground(c.x + 25.0, c.y + 6.0))
	g.finish(self, "village")
	rng.state = saved


# ------------------------------------------------------------------ колхоз с элеватором (юго-запад)
func _build_farm() -> void:
	var g := Geo.new()
	var c := FARM
	var y: float = pads[6].h
	# элеватор: 4 силоса и башня
	for i in 4:
		var sx := c.x - 30.0 + i * 7.6
		g.cyl("concrete", Transform3D(Basis(), Vector3(sx, y + 9.0, c.y - 28.0)), 3.6, 18.0, 16)
		g.cyl("plate_dark", Transform3D(Basis(), Vector3(sx, y + 18.3, c.y - 28.0)), 3.7, 0.6, 16, false)
	g.box("concrete", Vector3(c.x + 3.0, y + 12.0, c.y - 28.0), Vector3(7.0, 24.0, 7.0))
	g.box("iron", Vector3(c.x + 3.0, y + 25.0, c.y - 28.0), Vector3(7.6, 2.0, 7.6))
	g.box("rust", Vector3(c.x - 11.0, y + 19.5, c.y - 28.0), Vector3(30.0, 1.2, 1.4), 0.0, false)
	# коровники/склады из профлиста
	_building(g, c.x - 22.0, c.y + 4.0, 30, 11, 4.2, "iron", {"e": [[2.5, 8.5, 0.0, 3.6]], "w": [[2.5, 8.5, 0.0, 3.6]], "n": [win(5.0, 2.0), win(13.0, 2.0), win(21.0, 2.0)], "s": [door(14.0, 1.6)]}, y, "iron", 0.14)
	_building(g, c.x + 24.0, c.y + 6.0, 22, 12, 5.0, "iron", {"w": [[3.0, 9.0, 0.0, 4.2]], "n": [door(10.0, 1.6)]}, y, "iron", 0.14)
	# контора
	_building(g, c.x + 28.0, c.y - 18.0, 9, 7, 3.0, "plaster", {"s": [win(1.0), door(4.0, 1.2), win(6.5)], "n": [win(1.5), win(6.0)]}, y, "concrete")
	_ammo_crate(c.x + 30.0, c.y - 19.0, y + 0.08, 1.0)
	# техника, стога, укрытия
	_truck(g, c.x + 5.0, c.y + 22.0, 0.3, y)
	_truck(g, c.x - 40.0, c.y - 12.0, 1.8, y)
	_wreck(g, c.x + 8.0, c.y - 10.0, 0.6)
	for k in 5:
		g.cyl("canvas", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(c.x - 45.0 + k * 3.0, y + 0.9, c.y + 30.0)), 0.9, 1.6, 10)
	for b in [[c.x - 5.0, c.y - 5.0, 0.2], [c.x + 14.0, c.y + 14.0, 1.4], [c.x - 38.0, c.y + 20.0, 0.0]]:
		_barrier(g, b[0], b[1], b[2], y)
	_sandbags(g, Vector2(c.x + 40.0, c.y - 30.0), Vector2(c.x + 46.0, c.y - 24.0), y)
	_barrels(c.x + 16.0, c.y - 22.0, 4, y)
	_crate(g, c.x - 6.0, c.y + 12.0, 1.2, 0.3, y)
	_crate(g, c.x - 4.6, c.y + 12.3, 1.1, -0.2, y)
	g.finish(self, "farm")


# ------------------------------------------------------------------ карьер со складом взрывчатки (север)
func _build_quarry() -> void:
	var g := Geo.new()
	var c := QUARRY
	var y: float = pads[7].h
	# дробилка на опорах и конвейер к отвалу
	for sx in [-3.0, 3.0]:
		for sz in [-3.0, 3.0]:
			g.box("rust", Vector3(c.x + 18.0 + sx, y + 3.0, c.y - 12.0 + sz), Vector3(0.4, 6.0, 0.4))
	g.box("iron", Vector3(c.x + 18.0, y + 8.0, c.y - 12.0), Vector3(8.0, 4.0, 8.0))
	g.box("rust", Vector3(c.x + 30.0, y + 7.0, c.y - 12.0), Vector3(20.0, 0.5, 1.4), 0.0, false, 0.0, 0.42)
	# бытовки
	_building(g, c.x - 22.0, c.y + 14.0, 6.0, 2.6, 2.6, "container_grey", {"s": [door(1.0, 1.0), win(3.4, 1.4)]}, y, "plate_dark", 0.12)
	_building(g, c.x - 22.0, c.y + 20.0, 6.0, 2.6, 2.6, "container_blue", {"s": [door(1.0, 1.0)]}, y, "plate_dark", 0.12)
	# склад взрывчатки (цель): обвалованная площадка с контейнерами и ящиками
	var dx := c.x - 8.0
	var dz := c.y - 16.0
	_container(g, dx - 4.0, dz, 0.0, "container_green", y)
	_container(g, dx + 4.0, dz + 3.5, 0.05, "container_grey", y)
	_sandbags(g, Vector2(dx - 9.0, dz - 5.0), Vector2(dx + 9.0, dz - 5.0), y, 5)
	_sandbags(g, Vector2(dx - 9.0, dz - 5.0), Vector2(dx - 9.0, dz + 7.0), y, 5)
	_sandbags(g, Vector2(dx + 9.0, dz - 5.0), Vector2(dx + 9.0, dz + 7.0), y, 5)
	for k in 6:
		_crate(g, dx - 3.0 + (k % 3) * 1.3, dz + 4.5 + int(k / 3) * 1.3, 1.1, rng.randf_range(-0.2, 0.2), y)
	objectives["depot"] = Vector3(dx, y + 1.0, dz + 3.0)
	_ammo_crate(c.x - 18.0, c.y + 10.0, y + 0.08, 0.4)
	_truck(g, c.x + 4.0, c.y + 18.0, 0.9, y)
	_truck(g, c.x - 30.0, c.y - 6.0, 0.1, y)
	_barrels(c.x - 26.0, c.y + 4.0, 4, y)
	for b in [[c.x + 6.0, c.y + 4.0, 0.3], [c.x - 10.0, c.y + 22.0, 1.2], [c.x + 26.0, c.y + 10.0, 0.8]]:
		_barrier(g, b[0], b[1], b[2], y)
	var dep := g.finish(self, "quarry")
	_burn["depot"] = [dep]


# ------------------------------------------------------------------ укреплённая высота (юго-восток)
func _build_hillfort() -> void:
	var g := Geo.new()
	var c := HILLFORT
	var y: float = pads[8].h
	# бетонный дот с амбразурой (вход сзади, с юга)
	_building(g, c.x, c.y - 4.0, 6.0, 5.0, 2.4, "concrete", {"n": [[1.5, 4.5, 1.2, 1.6]], "s": [door(2.4, 1.2)], "w": [[1.8, 3.2, 1.2, 1.6]], "e": [[1.8, 3.2, 1.2, 1.6]]}, y, "concrete", 0.5)
	# окопы-брустверы по кругу
	for k in 8:
		var a := TAU * k / 8.0 + 0.3
		var p0 := c + Vector2(cos(a), sin(a)) * 13.0
		var p1 := c + Vector2(cos(a + 0.5), sin(a + 0.5)) * 13.0
		_sandbags(g, p0, p1, ground(p0.x, p0.y) - 0.1, 3)
	_tower(g, c.x + 8.0, c.y + 6.0, false, y)
	_ammo_crate(c.x - 4.0, c.y + 3.0, y + 0.08, 0.8)
	_crate(g, c.x + 3.0, c.y + 4.0, 1.2, 0.4, y)
	g.finish(self, "hillfort")


## Опорные точки на подходах к базе (90–130 м от центра): мешки с песком, бетонные блоки, руины стен
## с проломом-окном, сгоревшие машины, ящики. Всё — один меш из 4 материалов (4 вызова отрисовки),
## тени — кусками (Geo.shadow_proxies). Свой ГСЧ: расстановка остальной карты не меняется.
func _build_field_cover() -> void:
	var saved := rng.state
	rng.seed = 51125
	var g := Geo.new()
	var n := 0
	for i in 18:
		# в секторе перебираем места на 88–135 м и берём первое ровное: местность холмистая
		var x := 0.0
		var z := 0.0
		var found := false
		for t in 12:
			var a := TAU * (i + rng.randf_range(-0.35, 0.35)) / 18.0
			var r := rng.randf_range(88.0, 135.0)
			x = cos(a) * r
			z = sin(a) * r - 9.0
			if road_dist(x, z) < 9.0 or not _cover_ok(x, z, 32.0, 6.0):
				continue
			# гнездо/руины/машина стоят на одной высоте — перепад по всей ширине (±3.5 м), иначе край висит
			var span := maxf(absf(ground(x + 3.5, z) - ground(x - 3.5, z)), absf(ground(x, z + 3.5) - ground(x, z - 3.5)))
			if span <= 0.7:
				found = true
				break
		if not found:
			continue
		# «лицом» к базе: локальная −Z смотрит на центр
		var yaw := atan2(x, z + 9.0)
		match (i + int(rng.randi() % 2)) % 4:
			0:
				_nest(g, x, z, yaw)
			1:
				for k in 3:
					var p := _lw(x, z, yaw, -3.2 + k * 3.2 + rng.randf_range(-0.4, 0.4), rng.randf_range(-0.8, 0.8))
					_barrier(g, p.x, p.y, yaw + rng.randf_range(-0.25, 0.25), ground(p.x, p.y) - 0.05)
			2:
				_ruin(g, x, z, yaw)
			3:
				_wreck(g, x, z, yaw + rng.randf_range(-0.9, 0.9))
		# второе укрытие сбоку — перебежки от одного к другому
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var q := _lw(x, z, yaw, side * rng.randf_range(7.0, 10.0), rng.randf_range(2.0, 5.0))
		if _cover_ok(q.x, q.y, 26.0, 4.0):
			_cover_spots.append(Vector3(q.x, q.y, 3.0))
			if rng.randf() < 0.5:
				_field_crates(g, q.x, q.y, yaw)
			else:
				var b2 := _lw(q.x, q.y, yaw, 1.3, 0.0)
				_barrier(g, q.x, q.y, yaw + 0.2, ground(q.x, q.y) - 0.05)
				_barrier(g, b2.x + 1.2, b2.y, yaw - 0.3, ground(b2.x, b2.y) - 0.05)
		_cover_spots.append(Vector3(x, z, 7.5))
		n += 1
	g.finish(self, "field_cover")
	field_cover_count = n
	rng.state = saved


func _build_compound() -> void:
	var g := Geo.new()
	var y := H0
	# периметр
	g.wall("concrete", Vector3(-70, y, 50), Vector3(70, y, 50), 3.0, 0.35, [[65.5, 74.5, 0.0, 3.0]])
	g.wall("concrete", Vector3(-70, y, -68), Vector3(70, y, -68), 3.0, 0.35)
	g.wall("concrete", Vector3(-70, y, -68), Vector3(-70, y, 50), 3.0, 0.35, [[76.0, 79.5, 0.0, 3.0]])
	g.wall("concrete", Vector3(70, y, -68), Vector3(70, y, 50), 3.0, 0.35, [[52.0, 60.0, 0.0, 3.0]])
	# обломки пролома в западной стене
	for i in 7:
		g.box("concrete", Vector3(-70.0 + rng.randf_range(-1.6, 1.6), y + rng.randf_range(0.1, 0.35), 9.8 + rng.randf_range(-1.8, 1.8)),
			Vector3(rng.randf_range(0.5, 1.2), rng.randf_range(0.25, 0.6), rng.randf_range(0.4, 0.9)), rng.randf() * TAU, false, rng.randf_range(-0.3, 0.3))
	# столбы ворот
	for p in [Vector3(-4.7, y + 1.7, 50), Vector3(4.7, y + 1.7, 50), Vector3(70, y + 1.7, -16.2), Vector3(70, y + 1.7, -7.8)]:
		g.box("concrete", p, Vector3(0.6, 3.4, 0.6))
	_tower(g, -64.0, 44.0, true)
	_tower(g, 64.0, -62.0, false)

	# --- штаб (2 этажа)
	_building(g, -30, -42, 16, 11, 3.2, "plaster_tan",
		{"s": [win(3.0), door(9.0), win(12.5)], "n": [win(3.0), win(8.0), win(12.5)], "e": [door(4.8)], "w": [win(6.5)]},
		y, "floor", 0.3, true, false)
	g.box("floor", Vector3(-28.9, y + 3.1, -42), Vector3(13.8, 0.2, 11))
	g.box("floor", Vector3(-36.9, y + 3.1, -45.35), Vector3(2.2, 0.2, 4.3))
	g.box("floor", Vector3(-36.9, y + 3.1, -37.25), Vector3(2.2, 0.2, 1.5))
	g.stairs("floor", Vector3(-36.8, y, -38.2), 0.0, 1.8, 3.2, 4.8)
	g.box("wood_dark", Vector3(-35.75, y + 3.7, -40.6), Vector3(0.08, 1.0, 5.2))
	_building(g, -30, -42, 16, 11, 3.0, "plaster_tan",
		{"s": [win(2.0), win(7.3), win(12.5)], "n": [win(2.0), win(7.3), win(12.5)], "e": [win(2.0), win(7.0)], "w": [win(1.5), win(7.5)]},
		y + 3.2, "concrete", 0.3, false, true)
	for s in [[-30.0, -47.6, 16.5, 0.2], [-30.0, -36.4, 16.5, 0.2], [-38.1, -42.0, 0.2, 11.4], [-21.9, -42.0, 0.2, 11.4]]:
		g.box("concrete", Vector3(s[0], y + 6.65, s[1]), Vector3(s[2], 0.5, s[3]))
	# стол с разведданными (2 этаж)
	g.box("wood_dark", Vector3(-24.2, y + 3.95, -44.5), Vector3(1.8, 0.08, 0.9))
	for lx in [-0.8, 0.8]:
		for lz in [-0.35, 0.35]:
			g.box("wood_dark", Vector3(-24.2 + lx, y + 3.57, -44.5 + lz), Vector3(0.07, 0.75, 0.07), 0.0, false)
	g.box("wood_dark", Vector3(-32.0, y + 0.76, -45.8), Vector3(2.2, 0.08, 1.0))
	g.box("wood_dark", Vector3(-32.0, y + 0.38, -45.8), Vector3(2.0, 0.72, 0.8), 0.0, false)
	_prop("plastic_monobloc_chair_01", Vector3(-24.4, y + 3.2, -43.5), 0.3, "", "wood")
	_prop("plastic_monobloc_chair_01", Vector3(-31.6, y + 0.08, -44.6), 2.8, "", "wood")
	_prop("steel_frame_shelves_01", Vector3(-23.0, y + 0.08, -40.0), -PI * 0.5, "box", "metal", 0.1)
	_prop("steel_frame_shelves_01", Vector3(-27.0, y + 3.2, -47.0), 0.0, "box", "metal", 0.1)
	_make_intel(Vector3(-24.2, y + 3.99, -44.5))
	# дополнительные ящики с боеприпасами: штаб, казармы, двор
	_ammo_crate(-25.0, -38.2, y + 0.08, 0.2)
	_ammo_crate(33.0, -50.5, y + 0.08, 1.6)
	_ammo_crate(-43.5, 11.5, y + 0.08, 0.0)
	for lp in [[-8.0, 44.0, 0.0], [20.0, -30.0, 1.57], [-40.0, -30.0, -1.57], [52.0, 10.0, 3.14], [-20.0, 16.0, 0.0], [34.0, 46.0, 3.14]]:
		_lamp(g, lp[0], lp[1], y, lp[2])

	# --- казармы, склад, гараж, караулка
	_building(g, 26, -48, 18, 8, 3.0, "plaster", {"s": [door(3.0), win(6.5), win(9.5), door(13.0), win(15.5)], "n": [win(3.0), win(8.0), win(13.0)]})
	_building(g, -46, 6, 8, 16, 3.0, "plaster", {"e": [win(2.5), door(7.0), win(11.5)], "w": [win(3.0), win(11.0)]})
	_building(g, 38, 22, 20, 14, 5.5, "iron", {"w": [[4.5, 9.5, 0.0, 4.0]], "n": [door(15.0)], "s": [[3.0, 5.0, 3.0, 4.2], [14.0, 16.0, 3.0, 4.2]]}, y, "iron", 0.14)
	_building(g, 11, 44, 4, 4, 2.7, "plaster_tan", {"w": [door(1.3, 1.4)], "s": [win(1.3)], "n": [win(1.3)]})
	g.box("floor", Vector3(-18, y + 0.04, 28), Vector3(12, 0.08, 8))
	g.wall("iron", Vector3(-24, y, 24), Vector3(-12, y, 24), 3.5, 0.14)
	g.wall("iron", Vector3(-24, y, 24), Vector3(-24, y, 32), 3.5, 0.14)
	g.wall("iron", Vector3(-12, y, 24), Vector3(-12, y, 32), 3.5, 0.14)
	g.box("iron", Vector3(-18, y + 3.6, 28.2), Vector3(12.6, 0.1, 8.8), 0.0, true, -0.05)
	for px in [-24.0, -18.0, -12.0]:
		g.box("rust", Vector3(px, y + 1.75, 32), Vector3(0.16, 3.5, 0.16))
	for sp in [[-56.0, 20.0], [58.0, 6.0]]:
		_building(g, sp[0], sp[1], 2.2, 2.2, 2.4, "iron", {"s": [door(0.5, 1.0)]}, y, "iron", 0.1)

	# --- склад внутри
	for i in 4:
		_prop("steel_frame_shelves_01", Vector3(47.3, y + 0.08, 17.0 + i * 3.0), -PI * 0.5, "box", "metal", 0.1)
	_crate(g, 31.0, 17.5, 1.2, 0.1, y + 0.08)
	_crate(g, 32.4, 17.4, 1.2, -0.05, y + 0.08)
	_crate(g, 31.6, 17.5, 1.0, 0.3, y + 1.28)
	_crate(g, 40.0, 26.5, 1.3, 0.2, y + 0.08)
	_crate(g, 41.6, 26.8, 1.1, -0.15, y + 0.08)
	_crate(g, 36.0, 21.0, 1.2, 0.5, y + 0.08)
	_prop("old_military_crate", Vector3(36.5, y + 0.08, 27.5), 0.2, "box", "wood")
	_prop("ammo_box", Vector3(36.4, y + 0.4, 27.4), 0.6, "", "metal", 1.4)
	ammo_points.append(Vector3(36.5, y + 0.5, 27.5))

	# --- топливный склад (цель)
	g.box("floor", Vector3(46, y + 0.1, -18), Vector3(18, 0.2, 14))
	for s in [[46.0, -25.2, 18.4, 0.3], [46.0, -10.8, 6.0, 0.3], [37.0, -18.0, 0.3, 14.4], [55.0, -18.0, 0.3, 14.4]]:
		g.box("concrete", Vector3(s[0], y + 0.4, s[1]), Vector3(s[2], 0.8, s[3]))
	var fg := Geo.new()
	for tx in [41.0, 46.0, 51.0]:
		fg.cyl("green", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(tx, y + 2.0, -18.5)), 1.4, 7.0, 16)
		for sz in [-21.0, -16.0]:
			g.box("concrete", Vector3(tx, y + 0.5, sz), Vector3(2.2, 0.7, 0.5))
		fg.cyl("rust", Transform3D(Basis(), Vector3(tx, y + 3.6, -18.5)), 0.25, 0.5, 8, false)
	fg.cyl("rust", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(46, y + 3.7, -18.5)), 0.07, 10.5, 6, false)
	fuel_node = fg.finish(self, "fuel")
	objectives["fuel"] = Vector3(46.0, y + 1.2, -14.2)
	_barrels(39.0, -12.5, 4, y + 0.2)
	_barrels(53.5, -23.0, 3, y + 0.2)
	_prop("propane_tank", Vector3(52.0, y + 0.2, -12.3), 0.4, "cyl", "metal")
	_prop("propane_tank", Vector3(52.6, y + 0.2, -12.6), 1.4, "cyl", "metal")

	# --- мачта связи
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			g.box("rust", Vector3(-17.0 + sx, y + 8.0, -53.0 + sz), Vector3(0.1, 16.0, 0.1), 0.0, false)
	for i in 8:
		var by := y + 1.0 + i * 2.0
		g.box("rust", Vector3(-17.0, by, -53.5), Vector3(1.5, 0.06, 0.06), 0.0, false, 0.0, 0.9 if i % 2 == 0 else -0.9)
		g.box("rust", Vector3(-17.0, by, -52.5), Vector3(1.5, 0.06, 0.06), 0.0, false, 0.0, -0.9 if i % 2 == 0 else 0.9)
		g.box("rust", Vector3(-17.5, by, -53.0), Vector3(0.06, 0.06, 1.5), 0.0, false, 0.9 if i % 2 == 0 else -0.9)
		g.box("rust", Vector3(-16.5, by, -53.0), Vector3(0.06, 0.06, 1.5), 0.0, false, -0.9 if i % 2 == 0 else 0.9)
	g.collider("metal", Transform3D(Basis(), Vector3(-17.0, y + 8.0, -53.0)), Vector3(1.1, 16.0, 1.1))
	g.box("floor", Vector3(-17.0, y + 0.1, -53.0), Vector3(2.2, 0.2, 2.2))
	var lamp := MeshInstance3D.new()
	var ls := SphereMesh.new()
	ls.radius = 0.12
	ls.height = 0.24
	lamp.mesh = ls
	lamp.material_override = Mats.emissive(Color(1, 0.1, 0.05), 3.0)
	lamp.position = Vector3(-17.0, y + 16.2, -53.0)
	add_child(lamp)

	# --- контейнеры, техника, укрытия
	_container(g, 10.0, -20.0, 0.2, "container", y)
	_container(g, 11.0, -23.2, 0.22, "container_blue", y)
	_container(g, -4.0, -6.0, PI * 0.5, "container_green", y)
	_container(g, -56.0, -30.0, 0.05, "container_grey", y)
	_container(g, 56.0, 38.0, 1.4, "container", y)
	_container(g, 22.0, 4.0, 0.15, "container_blue", y)
	_container(g, -27.0, 41.0, 0.0, "container_green", y)
	g.box("container_grey", Vector3(10.4, y + 3.9, -21.4), Vector3(6.06, 2.6, 2.44), 0.26)
	_truck(g, 4.0, 12.0, 0.25, y)
	_truck(g, -58.0, -55.0, 1.5, y)
	_truck(g, -20.5, 28.5, 0.0, y + 0.08)
	_prop("covered_car", Vector3(-15.0, y + 0.08, 28.0), PI, "box", "metal")
	_prop("covered_car", Vector3(30.0, y, -36.0), 1.2, "box", "metal")
	_prop("portable_generator", Vector3(-20.5, y, -37.5), 0.4, "box", "metal")
	_prop("utility_box_01", Vector3(-21.4, y, -41.0), -PI * 0.5, "box", "metal")
	_prop("utility_box_01", Vector3(16.7, y, -46.0), PI * 0.5, "box", "metal")

	_sandbags(g, Vector2(-9.5, 46.0), Vector2(-5.0, 46.0), y)
	_sandbags(g, Vector2(5.0, 39.0), Vector2(9.5, 39.0), y)
	_sandbags(g, Vector2(64.0, -5.5), Vector2(64.0, -1.5), y)
	_sandbags(g, Vector2(63.0, -22.5), Vector2(63.0, -18.5), y)
	_sandbags(g, Vector2(-33.0, -33.0), Vector2(-29.5, -33.0), y, 3)
	_sandbags(g, Vector2(-26.0, -33.0), Vector2(-22.5, -33.0), y, 3)
	_sandbags(g, Vector2(-2.0, -32.0), Vector2(3.0, -32.0), y)
	_sandbags(g, Vector2(3.0, -32.0), Vector2(3.0, -28.5), y)
	_sandbags(g, Vector2(20.0, 30.0), Vector2(24.5, 30.0), y)
	_sandbags(g, Vector2(-45.0, -18.0), Vector2(-45.0, -13.5), y)
	_sandbags(g, Vector2(34.0, -3.0), Vector2(38.5, -3.0), y)
	for b in [[-12.0, 20.0, 0.0], [14.0, 26.0, 1.2], [-40.0, -22.0, 0.4], [30.0, -30.0, 1.57], [50.0, 0.0, 0.2], [-8.0, -50.0, 0.0],
			[2.0, 34.0, 1.57], [-2.5, 30.0, 1.57], [46.0, -40.0, 0.5], [-58.0, 0.0, 1.3], [16.0, -60.0, 0.0], [0.0, -14.0, 0.8]]:
		_barrier(g, b[0], b[1], b[2], y)
	for c in [[-10.0, 6.0, 1.3], [-11.5, 6.4, 1.1], [18.0, -34.0, 1.2], [44.0, 6.0, 1.3], [45.4, 5.6, 1.0], [-48.0, 36.0, 1.3],
			[-50.0, -48.0, 1.2], [60.0, -40.0, 1.3], [-34.0, 18.0, 1.1], [26.0, 44.0, 1.3], [8.0, -44.0, 1.2], [-62.0, -12.0, 1.3]]:
		_crate(g, c[0], c[1], c[2], rng.randf_range(-0.4, 0.4), y)
	for b in [[-14.0, -30.0, 4], [24.0, -14.0, 3], [-36.0, 30.0, 5], [58.0, 20.0, 3], [-60.0, 30.0, 4], [6.0, -58.0, 3], [-5.0, 24.0, 2], [48.0, -52.0, 4], [-52.0, -62.0, 3]]:
		_barrels(b[0], b[1], b[2], y)
	for t in [[-22.0, 34.5], [-13.0, 33.5], [3.5, 16.5], [-60.5, -52.0], [31.5, 30.5]]:
		var tyre := _prop("old_tyre", Vector3(t[0], y + 0.09, t[1]), rng.randf() * TAU, "", "dirt")
		tyre.rotation.x = PI * 0.5
	for j in [[-19.0, 33.0], [-18.6, 33.3], [36.0, -11.6], [35.6, -11.9], [12.5, 42.6]]:
		_prop("metal_jerrycan_green", Vector3(j[0], y, j[1]), rng.randf() * TAU, "", "metal")
	_prop("wooden_crate_02", Vector3(12.0, y, 46.6), 0.3, "box", "wood")
	_prop("wooden_crate_01", Vector3(12.1, y + 0.46, 46.6), 0.9, "", "wood")
	g.finish(self, "compound")


func _build_checkpoint() -> void:
	var g := Geo.new()
	var y: float = pads[1].h
	var c := CHECKPOINT
	_barrier(g, c.x - 2.2, c.y + 5.0, 0.15, y)
	_barrier(g, c.x + 2.4, c.y - 1.0, -0.1, y)
	_barrier(g, c.x - 2.0, c.y - 7.0, 0.1, y)
	_sandbags(g, Vector2(c.x + 5.0, c.y + 6.0), Vector2(c.x + 9.5, c.y + 6.0), y)
	_sandbags(g, Vector2(c.x + 9.5, c.y + 6.0), Vector2(c.x + 9.5, c.y + 2.5), y)
	_sandbags(g, Vector2(c.x - 9.0, c.y + 3.0), Vector2(c.x - 5.0, c.y + 4.5), y)
	_building(g, c.x + 8.0, c.y - 5.0, 3.6, 3.6, 2.5, "wood", {"w": [door(1.1, 1.4)], "s": [win(1.1)], "n": [win(1.1)]}, y, "iron", 0.12)
	_barrels(c.x - 7.0, c.y - 3.0, 3, y)
	_crate(g, c.x + 4.6, c.y - 8.5, 1.2, 0.3, y)
	_prop("old_military_crate", Vector3(c.x + 8.6, y + 0.08, c.y - 4.4), 0.1, "box", "wood")
	ammo_points.append(Vector3(c.x + 8.6, y + 0.5, c.y - 4.4))
	# шлагбаум
	g.box("rust", Vector3(c.x - 4.2, y + 0.6, c.y + 1.5), Vector3(0.2, 1.2, 0.2))
	g.box("#c8c2b4", Vector3(c.x - 0.6, y + 1.9, c.y + 1.5), Vector3(7.5, 0.1, 0.1), 0.0, false, 0.0, 0.38)
	g.finish(self, "checkpoint")


func _build_radar() -> void:
	var g := Geo.new()
	var y: float = pads[2].h
	var c := RADAR
	g.box("floor", Vector3(c.x, y + 0.1, c.y), Vector3(9, 0.2, 9))
	_container(g, c.x + 8.0, c.y - 5.0, 0.3, "container_green", y)
	_sandbags(g, Vector2(c.x - 3.0, c.y + 8.5), Vector2(c.x + 3.0, c.y + 8.5), y)
	_sandbags(g, Vector2(c.x + 8.5, c.y + 3.0), Vector2(c.x + 8.5, c.y + 7.0), y)
	_sandbags(g, Vector2(c.x - 9.0, c.y - 2.0), Vector2(c.x - 9.0, c.y + 2.5), y)
	_prop("portable_generator", Vector3(c.x + 4.0, y + 0.2, c.y + 3.0), 0.8, "box", "metal")
	_barrels(c.x - 6.0, c.y - 6.5, 3, y)
	_crate(g, c.x + 3.0, c.y - 8.0, 1.2, 0.2, y)
	_ammo_crate(c.x + 6.5, c.y + 0.5, y, 0.4)
	g.finish(self, "radar_site")

	var rg := Geo.new()
	rg.box("green", Vector3(c.x, y + 1.2, c.y), Vector3(2.6, 2.0, 2.6))
	rg.cyl("plate", Transform3D(Basis(), Vector3(c.x, y + 3.2, c.y)), 0.22, 2.0, 10)
	radar_node = rg.finish(self, "radar_base")
	radar_dish = Node3D.new()
	radar_dish.position = Vector3(c.x, y + 4.3, c.y)
	add_child(radar_dish)
	var dish := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.3
	sm.height = 1.1
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 5
	dish.mesh = sm
	var dm := (Mats.get_mat("plate") as BaseMaterial3D).duplicate() as BaseMaterial3D
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.uv1_scale = Vector3(3, 3, 3)
	dish.material_override = dm
	dish.rotation.x = PI * 0.5
	dish.position = Vector3(0, 0.6, 0.4)
	radar_dish.add_child(dish)
	for a in [0.0, 2.1, 4.2]:
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 2.3)
		arm.mesh = bm
		arm.material_override = Mats.get_mat("rust")
		arm.position = Vector3(cos(a) * 0.9, 0.6 + sin(a) * 0.9, -0.6)
		arm.rotation = Vector3(sin(a) * 0.4, -cos(a) * 0.4, 0)
		radar_dish.add_child(arm)
	objectives["radar"] = Vector3(c.x, y + 1.2, c.y + 1.5)


func _build_lz() -> void:
	var y: float = pads[3].h
	objectives["lz"] = Vector3(LZ.x, y, LZ.y)
	var g := Geo.new()
	for a in 4:
		var ang := a * PI * 0.5 + 0.4
		g.box("#d9d2c0", Vector3(LZ.x + cos(ang) * 6.0, y + 0.03, LZ.y + sin(ang) * 6.0), Vector3(2.4, 0.04, 0.5), -ang, false)
	_crate(g, LZ.x - 8.0, LZ.y + 5.0, 1.2, 0.2, y)
	_crate(g, LZ.x + 7.0, LZ.y - 7.0, 1.3, 0.6, y)
	_ammo_crate(LZ.x - 6.0, LZ.y - 6.0, y, 0.8)
	g.finish(self, "lz")
	spawn_point = Vector3(SPAWN.x, float(pads[4].h) + 0.2, SPAWN.y)


func _process(delta: float) -> void:
	if radar_dish and radar_alive:
		radar_dish.rotate_y(delta * 0.8)


## Разрушение цели после подрыва.
func destroy_objective(key: String) -> void:
	var burnt := Mats.flat(Color(0.05, 0.045, 0.04), 0.95)
	if key == "radar":
		radar_alive = false
		radar_dish.rotation = Vector3(0.9, radar_dish.rotation.y, 0.5)
		radar_dish.position.y -= 1.6
		for c in radar_dish.get_children():
			(c as MeshInstance3D).material_override = burnt
		radar_node.material_override = burnt
	elif key == "fuel":
		fuel_node.material_override = burnt
	elif key == "intel":
		intel_node.visible = false
	for n in _burn.get(key, []):
		(n as GeometryInstance3D).material_override = burnt


func _define_enemies() -> void:
	var c := CHECKPOINT
	# блокпост
	_e(c.x - 1.0, c.y + 7.0, 180)
	_e(c.x + 7.5, c.y + 4.5, 180)
	_e(c.x + 2.0, c.y - 10.0, 0, 0, [[c.x - 6.0, c.y - 9.0], [c.x + 6.0, c.y - 9.0], [c.x + 6.0, c.y + 9.0], [c.x - 6.0, c.y + 9.0]])
	# ворота
	_e(-7.0, 47.5, 180)
	_e(7.0, 40.5, 180)
	_e(65.5, -3.5, -90)
	_e(64.5, -20.5, -90)
	# вышки (снайперы)
	_e(-64.0, 44.0, 150, 2, [], H0 + 5.0, true)
	_e(64.0, -62.0, -30, 2, [], H0 + 5.0, true)
	# патрули
	var loop := [[-56.0, 38.0], [54.0, 36.0], [56.0, -58.0], [-56.0, -60.0]]
	_e(-56.0, 38.0, 90, 0, loop)
	_e(56.0, -58.0, -90, 0, loop)
	_e(0.0, 28.0, 0, 0, [[0.0, 28.0], [0.0, -26.0], [-20.0, -26.0], [-20.0, 12.0]])
	# штаб
	_e(-27.5, -34.5, 180)
	_e(-31.0, -40.5, 180)
	_e(-25.5, -45.5, -90, 1, [], H0 + 3.25, true)
	# склад, топливо, казармы, двор
	_e(33.5, 22.0, 90)
	_e(43.0, 19.0, 180)
	_e(40.0, -8.5, 180)
	_e(57.0, -20.0, 90, 1)
	_e(21.0, -42.0, 180)
	_e(30.5, -41.5, 180)
	_e(-39.5, 5.0, 90)
	_e(-18.0, 34.0, 180)
	_e(10.0, -6.0, 180, 1)
	# РЛС
	_e(RADAR.x + 5.0, RADAR.y + 6.0, 140)
	_e(RADAR.x - 6.0, RADAR.y - 3.0, 200)
	_e(RADAR.x, RADAR.y + 12.0, 120, 0, [[RADAR.x - 13.0, RADAR.y + 12.0], [RADAR.x + 13.0, RADAR.y + 12.0], [RADAR.x + 14.0, RADAR.y - 12.0], [RADAR.x - 13.0, RADAR.y - 12.0]])
	# внешний патруль и засада у точки эвакуации
	_e(-80.0, 14.0, 0, 0, [[-80.0, 14.0], [-96.0, -24.0], [-104.0, -56.0], [-96.0, -24.0]])
	_e(LZ.x - 9.0, LZ.y + 7.0, 160)
	_e(LZ.x + 8.0, LZ.y - 8.0, 200, 1)
	# деревня: гарнизон в сельсовете, посты на въездах, патруль по улице
	var v := VILLAGE
	_e(v.x - 20.0, v.y + 8.0, 0)
	_e(v.x - 23.0, v.y + 17.0, 180)
	_e(v.x - 18.0, v.y + 14.0, 0, 2, [], _ground_min(v.x - 20.0, v.y + 15.0, 8.0) + 3.3, true)
	_e(v.x - 92.0, v.y + 2.0, -90)
	_e(v.x - 90.0, v.y - 3.0, -90, 1)
	_e(v.x + 88.0, v.y + 3.0, 90)
	_e(v.x + 40.0, v.y - 9.0, 180)
	_e(v.x + 10.0, v.y - 22.0, 160)
	_e(v.x - 60.0, v.y + 22.0, 20)
	_e(v.x - 70.0, v.y, 90, 0, [[v.x - 70.0, v.y], [v.x + 70.0, v.y + 2.0]])
	# колхоз
	var f := FARM
	_e(f.x + 28.0, f.y - 13.0, 0)
	_e(f.x + 3.0, f.y - 22.0, 30)
	_e(f.x - 22.0, f.y - 3.0, 0, 1)
	_e(f.x + 24.0, f.y + 14.0, 160)
	_e(f.x + 43.0, f.y - 22.0, 40)
	_e(f.x - 40.0, f.y + 25.0, 200, 0, [[f.x - 45.0, f.y + 25.0], [f.x + 40.0, f.y + 25.0], [f.x + 40.0, f.y - 35.0], [f.x - 45.0, f.y - 35.0]])
	_e(f.x + 3.0, f.y - 28.0, 120, 2, [], float(pads[6].h) + 26.0, true)
	# карьер
	var q := QUARRY
	_e(q.x - 8.0, q.y - 10.0, 180)
	_e(q.x - 2.0, q.y - 8.0, 150, 1)
	_e(q.x - 18.0, q.y + 6.0, 180)
	_e(q.x + 10.0, q.y + 8.0, 200)
	_e(q.x + 24.0, q.y - 2.0, 230)
	_e(q.x - 30.0, q.y + 30.0, 180, 0, [[q.x - 30.0, q.y + 30.0], [q.x + 30.0, q.y + 30.0]])
	_e(q.x + 50.0, q.y + 60.0, 200, 2, [], -1000.0, true)
	_e(q.x - 60.0, q.y + 55.0, 160, 0, [], -1000.0, true)
	# высота
	var h := HILLFORT
	_e(h.x, h.y - 2.0, 300, 1)
	_e(h.x - 9.0, h.y - 6.0, 270)
	_e(h.x + 8.0, h.y + 6.0, 300, 2, [], float(pads[8].h) + 5.0, true)
	_e(h.x + 10.0, h.y - 9.0, 330)
	_e(h.x - 6.0, h.y + 10.0, 230)
	# патрули на дорогах
	_e(170.0, 2.0, 90, 0, [[150.0, -4.0], [240.0, 38.0]])
	_e(190.0, -220.0, 45, 0, [[140.0, -170.0], [260.0, -290.0]])
	_e(-150.0, 22.0, -90, 0, [[-110.0, 15.0], [-230.0, 48.0]])
	_e(14.0, 420.0, 0, 0, [[12.0, 340.0], [14.0, 470.0], [120.0, 430.0]])
	# брод через русло
	_e(-238.0, 62.0, 90)
	_e(-226.0, 36.0, 90, 1)
