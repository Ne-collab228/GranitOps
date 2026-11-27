class_name MapPass
extends Level
## Карта 3: горный перевал «Седло» (1,26 x 1,26 км, север = −Z, восток = +X).
##
## Игрок выходит с юга: горная деревня в южной котловине, затем серпантин в пять колен вверх к перевалу.
## У вершины дорогу рвёт ущелье с мостом, за мостом — застава на седловине (штаб с разведданными).
## К северу дорога спускается в северную котловину: хутор, лесопилка со складом боеприпасов, поляна эвакуации.
## Рельеф: седловина (вдоль z) и два хребта по бокам (вдоль x), горные тропы-дороги к ретранслятору на
## восточной вершине и к горному посту на западном склоне. Ельники — рощами на склонах ниже границы леса.

const PASS_H := 73.0              # высота седловины над нулём (дно котловины ~8 м)
const SPAWN := Vector2(0.0, 548.0)
const VILLAGE := Vector2(-10.0, 335.0)
const FARMS := Vector2(190.0, 405.0)
const RUINS_SW := Vector2(-235.0, 445.0)
const BR_X := 33.0
const FORT := Vector2(30.0, -100.0)
const RELAY := Vector2(250.0, -170.0)
const LODGE := Vector2(-255.0, -30.0)
const HAMLET := Vector2(205.0, -428.0)
const MILL := Vector2(-250.0, -400.0)
const LZ := Vector2(400.0, -450.0)
## Крайние точки шпилек серпантина: [z центра, x вершины дуги, сторона наружу (+1 восток / −1 запад)].
const HAIRPINS := [[182.0, 106.0, 1.0], [123.0, -56.0, -1.0], [66.0, 103.0, 1.0], [10.0, -46.0, -1.0]]

var noise_c := FastNoiseLite.new()
var noise_f := FastNoiseLite.new()
var relay_dish: Node3D
var relay_alive := true
var relay_node: MeshInstance3D
var relay_lamp: MeshInstance3D
var bridge_node: MeshInstance3D
var bridge_y := Vector2.ZERO
var _gr := RandomNumberGenerator.new()
## Точки ИИ зданий Bld (для проверки).
var bld_log: Array = []
var _n_posts := 0
## Доля сохранённых одиночных постов и стрелков гарнизонов (остальных пропускаем детерминированно): ~60 врагов на карту.
var _thin := RandomNumberGenerator.new()
var post_keep := 0.38
var garrison_keep := 0.42


func _configure() -> void:
	map_key = "pass"
	title = "Перевал «Седло»"
	size = 1260.0
	cell = 3.0
	chunk = 105
	lod_dist = 260.0
	play_half = 570.0
	outer_half = 2430.0
	outer_cell = 30.0
	map_seed = 20261127
	spawn_max_h = 45.0
	sky_file = "res://assets/sky/sky2_2k.hdr"
	sun_dir = Vector3(-0.55, 0.42, 0.72).normalized()
	orbit_center = Vector3(0, 40, 0)
	orbit_radius = 200.0
	orbit_height = 70.0
	backdrop_color = Color(0.45, 0.47, 0.5)
	nav_aabb = AABB(Vector3(-575, -40, -575), Vector3(1150, 330, 1150))
	tree_mix = {"fir": 0.82, "dead": 0.06, "searsia": 0.07, "broadleaf": 0.05}
	grove_share = 0.55
	tree_density = 1.15
	veg_cell_grass = 32.0
	tree_max_h = 80.0
	veg_cell_tree = 80.0
	site_points = [Vector3(SPAWN.x, SPAWN.y, 0), Vector3(VILLAGE.x, VILLAGE.y, 95), Vector3(FARMS.x, FARMS.y, 50), Vector3(RUINS_SW.x, RUINS_SW.y, 30),
		Vector3(BR_X, -38, 40), Vector3(FORT.x, FORT.y, 80), Vector3(RELAY.x, RELAY.y, 40), Vector3(LODGE.x, LODGE.y, 40),
		Vector3(HAMLET.x, HAMLET.y, 50), Vector3(MILL.x, MILL.y, 70), Vector3(LZ.x, LZ.y, 30)]
	for hp in HAIRPINS:
		site_points.append(Vector3(float(hp[1]), float(hp[0]), 22))


func _setup_noise() -> void:
	noise_a.seed = 41
	noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_a.frequency = 0.0058
	noise_a.fractal_octaves = 3
	noise_b.seed = 59
	noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_b.frequency = 0.03
	noise_b.fractal_octaves = 2
	noise_c.seed = 17
	noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_c.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_c.frequency = 0.0017
	noise_c.fractal_octaves = 5
	noise_f.seed = 73
	noise_f.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_f.frequency = 0.0075
	noise_f.fractal_octaves = 2


func _terrain_tex() -> Dictionary:
	return {"a": "aerial_grass_rock", "b": "forrest_ground_01", "r": "rock_boulder_dry", "tint": Vector3(0.84, 0.9, 0.86)}


## Холодный горный воздух: синеватая дымка, заметная перспектива, низкое солнце.
func _tune_environment() -> void:
	env.tonemap_exposure = 1.06
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 1.04
	env.ambient_light_color = Color(0.58, 0.64, 0.76)
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_energy = 1.0
	env.fog_light_color = Color(0.62, 0.7, 0.82)
	env.fog_density = 0.0007
	env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter = 0.2
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.3


# ------------------------------------------------------------------ рельеф
## Ось ущелья: z центра при данном x.
func _gz(x: float) -> float:
	return -38.0 + 3.0 * sin(x / 45.0)


func base_height(x: float, z: float) -> float:
	var h := 8.0 + noise_a.get_noise_2d(x, z) * 3.0 + noise_b.get_noise_2d(x, z) * 0.8
	# седловина вдоль z: подъём по южному склону, площадка у заставы, спуск к северной котловине
	var rise := smoothstep(235.0, -20.0, z)
	var fall := smoothstep(-135.0, -350.0, z)
	var lift := (PASS_H - 8.0) * rise * (1.0 - 0.8 * fall)
	# хребты по бокам седловины
	var w := smoothstep(40.0, 280.0, absf(x - 25.0))
	var belt := smoothstep(265.0, 120.0, z) * smoothstep(-420.0, -270.0, z)
	h += lift * (1.0 - w * belt)
	h += w * belt * (95.0 + 55.0 * noise_c.get_noise_2d(x, z) + 14.0 * noise_a.get_noise_2d(x * 2.0, z * 2.0))
	# ущелье с мостом
	var gd := absf(z - _gz(x))
	var ge := 1.0 - smoothstep(150.0, 260.0, absf(x - 40.0))
	h -= 20.0 * ge * (1.0 - smoothstep(9.0, 17.0, gd))
	# вершины над ретранслятором и горным постом
	h += 16.0 * exp(-Vector2(x - RELAY.x, z - RELAY.y).length_squared() / (2.0 * 40.0 * 40.0))
	h += 10.0 * exp(-Vector2(x - LODGE.x, z - LODGE.y).length_squared() / (2.0 * 36.0 * 36.0))
	# горы по краю и за границей игровой зоны
	var e := maxf(absf(x), absf(z))
	var b := smoothstep(470.0, 640.0, e)
	h += b * b * 70.0 + b * noise_b.get_noise_2d(x * 0.6, z * 0.6) * 6.0
	var far := maxf(e - 600.0, 0.0)
	if far > 0.0:
		var ridge := 1.0 - absf(noise_a.get_noise_2d(x * 0.3 + 900.0, z * 0.3))
		h += far * 0.1 + ridge * ridge * minf(far, 1100.0) * 0.3
	return h


## Цвет вершины: r — подстилка леса, g — скала (крутизна и высота), b — дорога/двор.
func _vertex_color(x: float, z: float, nrm: Vector3, rd: float) -> Color:
	var hh := base_height(x, z)
	var rock := maxf(smoothstep(0.84, 0.62, nrm.y), smoothstep(88.0, 140.0, hh) * 0.9)
	var band := smoothstep(9.0, 20.0, hh) * (1.0 - smoothstep(60.0, 82.0, hh))
	var alt := clampf(band * (0.35 + 0.8 * smoothstep(-0.1, 0.3, noise_f.get_noise_2d(x, z))), 0.0, 1.0)
	var road := 1.0 - smoothstep(2.2, 5.0, rd)
	return Color(alt, rock, maxf(road, _yard_weight(x, z)), 0.0)


func _yard_weight(x: float, z: float) -> float:
	var w := (1.0 - smoothstep(0.0, 12.0, maxf(maxf(absf(x - VILLAGE.x) - 40.0, absf(z - VILLAGE.y) - 66.0), 0.0))) * 0.3
	w = maxf(w, (1.0 - smoothstep(0.0, 12.0, maxf(maxf(absf(x - FORT.x) - 56.0, absf(z - FORT.y) - 28.0), 0.0))) * 0.4)
	w = maxf(w, (1.0 - smoothstep(0.0, 14.0, maxf(maxf(absf(x - MILL.x) - 38.0, absf(z - MILL.y) - 26.0), 0.0))) * 0.45)
	w = maxf(w, (1.0 - smoothstep(0.0, 10.0, Vector2(x - RELAY.x, z - RELAY.y).length() - 10.0)) * 0.35)
	return w


func _setup_pads() -> void:
	var gz := _gz(BR_X)
	roads = [
		# 0: главная — с юга через деревню, серпантин из пяти колен, к южному берегу ущелья
		PackedVector2Array([Vector2(0, 575), Vector2(14, 520), Vector2(2, 455), Vector2(-8, 400), Vector2(-10, 335), Vector2(-9, 270), Vector2(0, 232),
			Vector2(40, 214), Vector2(80, 203), Vector2(100, 193), Vector2(106, 182), Vector2(98, 172),
			Vector2(60, 163), Vector2(10, 152), Vector2(-35, 143), Vector2(-54, 133), Vector2(-56, 122), Vector2(-46, 114),
			Vector2(0, 104), Vector2(50, 93), Vector2(88, 84), Vector2(103, 73), Vector2(100, 62), Vector2(90, 55),
			Vector2(50, 45), Vector2(0, 32), Vector2(-30, 25), Vector2(-46, 15), Vector2(-46, 3), Vector2(-36, -3),
			Vector2(-10, -8), Vector2(18, -12), Vector2(BR_X, gz + 19.0)]),
		# 1: северная — от моста через заставу, спуск, хутор и к поляне эвакуации
		PackedVector2Array([Vector2(BR_X, gz - 19.0), Vector2(33, -70), Vector2(33, -135), Vector2(36, -190), Vector2(20, -250), Vector2(50, -310),
			Vector2(95, -360), Vector2(140, -405), Vector2(190, -430), Vector2(260, -440), Vector2(330, -446), Vector2(388, -450)]),
		# 2: тропа-дорога на восточную вершину к ретранслятору
		PackedVector2Array([Vector2(-5, 300), Vector2(70, 305), Vector2(140, 290), Vector2(200, 250), Vector2(240, 190), Vector2(250, 120), Vector2(232, 50),
			Vector2(250, -30), Vector2(262, -100), Vector2(256, -150)]),
		# 3: к лесопилке
		PackedVector2Array([Vector2(50, -310), Vector2(-20, -370), Vector2(-110, -402), Vector2(-200, -406), Vector2(-240, -400)]),
		# 4: на западный склон к горному посту
		PackedVector2Array([Vector2(-12, 290), Vector2(-90, 285), Vector2(-160, 262), Vector2(-215, 205), Vector2(-250, 130), Vector2(-262, 60), Vector2(-258, -10)]),
	]
	pads = [
		{"c": VILLAGE, "half": Vector2(46, 70), "m": 30.0, "h": base_height(VILLAGE.x, VILLAGE.y)},
		{"c": SPAWN, "half": Vector2(5, 5), "m": 12.0, "h": base_height(SPAWN.x, SPAWN.y)},
		{"c": FARMS, "half": Vector2(46, 26), "m": 24.0, "h": base_height(FARMS.x, FARMS.y)},
		{"c": RUINS_SW, "half": Vector2(26, 20), "m": 18.0, "h": base_height(RUINS_SW.x, RUINS_SW.y)},
		{"c": Vector2(BR_X, gz + 19.0), "half": Vector2(5, 3), "m": 7.0, "h": PASS_H},
		{"c": Vector2(BR_X, gz - 19.0), "half": Vector2(5, 3), "m": 7.0, "h": PASS_H},
		{"c": FORT, "half": Vector2(62, 28), "m": 10.0, "h": PASS_H},
		{"c": RELAY, "half": Vector2(13, 12), "m": 18.0, "h": base_height(RELAY.x, RELAY.y)},
		{"c": LODGE, "half": Vector2(14, 12), "m": 22.0, "h": base_height(LODGE.x, LODGE.y)},
		{"c": HAMLET, "half": Vector2(46, 22), "m": 20.0, "h": base_height(HAMLET.x, HAMLET.y)},
		{"c": MILL, "half": Vector2(40, 28), "m": 24.0, "h": base_height(MILL.x, MILL.y)},
		{"c": LZ, "half": Vector2(10, 10), "m": 16.0, "h": base_height(LZ.x, LZ.y)},
	]


# ------------------------------------------------------------------ растительность
## Ельники рощами: только между 9 и tree_max_h м по высоте, по шумовым пятнам, не у построек.
func _free_spot(x: float, z: float, margin := 2.0) -> bool:
	if not super._free_spot(x, z, margin):
		return false
	if margin < 2.4:
		return true
	for sp in site_points:
		if absf(x - sp.x) < sp.z * 0.8 and absf(z - sp.y) < sp.z * 0.8:
			return false
	var hh := base_height(x, z)
	var band := smoothstep(9.0, 18.0, hh) * (1.0 - smoothstep(tree_max_h - 14.0, tree_max_h, hh))
	var f := band * smoothstep(0.0, 0.3, noise_f.get_noise_2d(x * 1.0 + 40.0, z * 1.0))
	var hv := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return (hv - floorf(hv)) < f * 1.7


# ------------------------------------------------------------------ здания и гарнизоны
func _bld(g: Geo, kind: String, x: float, z: float, yaw: float, opt := {}, out := {}) -> Dictionary:
	var y := _ground_min(x, z, 6.0) - 0.15
	var p := Vector3(x, y, z)
	var info: Dictionary
	match kind:
		"house":
			info = Bld.house(g, rng, p, yaw, out, opt)
		"house_fence":
			info = Bld.house(g, rng, p, yaw, out, {"fence": true})
		"house_east":
			info = Bld.house(g, rng, p, yaw, out, {"east": true})
		"house2":
			info = Bld.house2(g, rng, p, yaw, out, opt)
		"block":
			info = Bld.block(g, rng, p, yaw, out, opt)
		"shop":
			info = Bld.shop(g, rng, p, yaw, out, {"cafe": false})
		"cafe":
			info = Bld.shop(g, rng, p, yaw, out, {"cafe": true})
		"warehouse":
			info = Bld.warehouse(g, rng, p, yaw, out, opt)
		"garages":
			info = Bld.garages(g, rng, p, yaw, out, opt)
		"shed":
			info = Bld.shed(g, rng, p, yaw, out, opt)
		"booth":
			info = Bld.booth(g, rng, p, yaw, out, opt)
		"hq":
			info = Bld.hq(g, rng, p, yaw, out, opt)
		"ruin":
			info = Bld.ruin(g, rng, p, yaw, out, opt)
		_:
			push_warning("_bld: неизвестный тип " + kind)
			return {}
	for c in out.get("cover", []):
		cover_points.append(c)
	bld_log.append({"kind": kind, "info": info, "out": out})
	return info


func _far(mi: MeshInstance3D, d: float) -> void:
	mi.visibility_range_end = d
	mi.visibility_range_end_margin = 20.0
	veg_ranges.append([mi, d])


func _garrison(out: Dictionary, info: Dictionary, fire_n: int, inside_n := 0, roof_n := 0, door_n := 0) -> void:
	if info.is_empty():
		return
	_in_garrison = true
	_garrison_inner(out, info, fire_n, inside_n, roof_n, door_n)
	_in_garrison = false


func _garrison_inner(out: Dictionary, info: Dictionary, fire_n: int, inside_n: int, roof_n: int, door_n: int) -> void:
	var ctr: Vector3 = info.pos
	var fire: Array = (out.get("fire", []) as Array).duplicate()
	for i in range(fire.size() - 1, 0, -1):
		var j := _gr.randi() % (i + 1)
		var tmp = fire[i]
		fire[i] = fire[j]
		fire[j] = tmp
	for i in mini(fire_n, fire.size()):
		var p: Vector3 = fire[i]
		if _gr.randf() > garrison_keep:
			continue
		_e_face(p, p - ctr, 1 if i % 3 == 2 else 0, true)
	var ins: Array = out.get("inside", [])
	for i in mini(inside_n, ins.size()):
		var p2: Vector3 = ins[i]
		if _gr.randf() > garrison_keep:
			continue
		_e(p2.x, p2.z, _gr.randf() * 360.0, 0, [], p2.y, false)
	var roof: Array = out.get("roof", [])
	for i in mini(roof_n, roof.size()):
		var p3: Vector3 = roof[_gr.randi() % roof.size()]
		_e_face(p3, p3 - ctr, 2, true)
	var doors: Array = out.get("doors", [])
	for i in mini(door_n, doors.size()):
		var p4: Vector3 = doors[i]
		if _gr.randf() > garrison_keep:
			continue
		_e_face(p4, p4 - ctr, 0, false)


func _e_face(p: Vector3, dir: Vector3, kind: int, hold: bool) -> void:
	_e(p.x, p.z, rad_to_deg(atan2(-dir.x, -dir.z)), kind, [], p.y, hold)


func _set_palette(on: bool) -> void:
	if on:
		Bld.walls_house = ["plaster_tan", "stucco_yellow", "wood_dark", "concrete"]
		Bld.walls_block = ["concrete", "plaster_tan"]
		Bld.roofs = ["slate", "roof_red"]
	else:
		Bld.walls_house = ["plaster_tan", "stucco_blue", "stucco_yellow", "concrete"]
		Bld.walls_block = ["concrete", "plaster_tan", "stucco_yellow"]
		Bld.roofs = ["slate", "roof_red", "iron"]


func _build_sites() -> void:
	_n_posts = enemy_spawns.size()
	_set_palette(true)
	_build_spawn()
	_build_village()
	await get_tree().process_frame
	_build_south_farms()
	_build_serpentine()
	_build_bridge()
	await get_tree().process_frame
	_build_fort()
	_build_relay()
	_build_lodge()
	await get_tree().process_frame
	_build_hamlet()
	_build_mill()
	_build_lz()
	_build_field_cover()
	_set_palette(false)
	print("ПЕРЕВАЛ: врагов %d (посты и патрули до построек %d), укрытий в поле %d" % [enemy_spawns.size(), _n_posts, field_cover_count])
	_define_vehicles()
	blast_fx["bridge"] = {"fires": [[Vector3(-1.5, 0.3, 0), 1.6], [Vector3(1.5, 0.3, 2), 1.4]], "blasts": [[0.4, Vector3(0, 1, 0)], [1.0, Vector3(0, 1, 6)], [1.6, Vector3(0, 1, -6)]]}
	blast_fx["relay"] = {"fires": [[Vector3(0, 0.4, 0), 1.6], [Vector3(1.5, 0.3, -1), 1.2]], "blasts": [[0.5, Vector3(0, 2, 0)], [1.2, Vector3(-1, 3, 1)]]}
	blast_fx["depot"] = {"fires": [[Vector3(-3, 0.5, 0), 1.4], [Vector3(3, 0.5, 1), 1.2]], "blasts": [[0.4, Vector3(-3, 1, 0)], [0.9, Vector3(4, 1, -2)], [1.6, Vector3(0, 1, 3)]]}


# ------------------------------------------------------------------ точка появления
func _build_spawn() -> void:
	var y: float = pads[1].h
	spawn_point = Vector3(SPAWN.x, y + 0.2, SPAWN.y)
	var g := Geo.new()
	_barrier(g, SPAWN.x - 9.0, SPAWN.y - 14.0, 0.2, ground(SPAWN.x - 9.0, SPAWN.y - 14.0) - 0.05)
	_sandbags(g, Vector2(SPAWN.x + 6.0, SPAWN.y - 22.0), Vector2(SPAWN.x + 11.0, SPAWN.y - 22.0), ground(SPAWN.x + 8.0, SPAWN.y - 22.0) - 0.1, 3)
	_ammo_crate(SPAWN.x + 4.0, SPAWN.y - 8.0, y, 0.4)
	_far(g.finish(self, "spawn"), 200.0)


# ------------------------------------------------------------------ горная деревня (улица с севера на юг)
func _build_village() -> void:
	var g := Geo.new()
	var c := VILLAGE
	var saved := rng.state
	rng.seed = 7311
	_gr.seed = 7312
	# западная сторона смотрит на восток (yaw +90), восточная — на запад (−90); сдвиги вдоль улицы (z)
	var west := [[-60.0, "house_fence"], [-38.0, "house2"], [-14.0, "cafe"], [10.0, "shop"], [34.0, "house"], [58.0, "house_fence"]]
	var east := [[-60.0, "house"], [-38.0, "house_east"], [-12.0, "block"], [16.0, "house2"], [40.0, "garages"], [60.0, "ruin"]]
	var garr := {"house_fence": [1, 0, 0, 0], "house": [1, 0, 0, 0], "house2": [2, 0, 1, 0], "ruin": [1, 0, 0, 0], "cafe": [2, 0, 0, 0],
		"shop": [1, 0, 0, 1], "block": [3, 0, 1, 0], "house_east": [1, 0, 0, 0], "garages": [1, 0, 0, 0]}
	for side in 2:
		var lst: Array = west if side == 0 else east
		var xx := c.x - 17.0 if side == 0 else c.x + 17.0
		var yaw := PI * 0.5 if side == 0 else -PI * 0.5
		for it in lst:
			var kind: String = it[1]
			var out := {}
			var opt := {}
			if kind == "block":
				opt = {"floors": 2}
			var info := _bld(g, kind, xx, c.y + float(it[0]), yaw, opt, out)
			var gp: Array = garr.get(kind, [0, 0, 0, 0])
			_garrison(out, info, gp[0], gp[1], gp[2], gp[3])
	_bld(g, "shed", c.x - 34.0, c.y - 30.0, PI * 0.5, {"iron": true})
	_bld(g, "shed", c.x + 36.0, c.y + 28.0, -PI * 0.5)
	_truck(g, c.x + 3.0, c.y - 46.0, 0.1, ground(c.x + 3.0, c.y - 46.0) - 0.05)
	_wreck(g, c.x - 4.0, c.y + 50.0, 1.6)
	for b in [[c.x + 2.0, c.y - 24.0, 0.4], [c.x - 3.0, c.y + 22.0, -0.3], [c.x + 3.0, c.y + 66.0, 0.2]]:
		_barrier(g, b[0], b[1], b[2], ground(b[0], b[1]) - 0.05)
	_barrels(c.x + 8.0, c.y + 4.0, 3, ground(c.x + 8.0, c.y + 4.0))
	_ammo_crate(c.x - 26.0, c.y + 22.0, ground(c.x - 26.0, c.y + 22.0), 0.3)
	_far(g.finish(self, "village"), 380.0)
	rng.state = saved


func _build_south_farms() -> void:
	var g := Geo.new()
	var saved := rng.state
	rng.seed = 7411
	_gr.seed = 7412
	var f := FARMS
	var o1 := {}
	_garrison(o1, _bld(g, "warehouse", f.x - 12.0, f.y - 4.0, 0.0, {"w": 22.0, "d": 11.0}, o1), 2, 0, 0, 0)
	var o2 := {}
	_garrison(o2, _bld(g, "house", f.x + 24.0, f.y + 4.0, PI * 0.5, {}, o2), 2, 0, 0, 0)
	_bld(g, "shed", f.x + 10.0, f.y - 16.0, 0.0, {"iron": true})
	for k in 4:
		g.cyl("canvas", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(f.x - 30.0 + k * 3.0, ground(f.x - 30.0, f.y + 14.0) + 0.9, f.y + 14.0)), 0.9, 1.6, 10)
	_barrier(g, f.x + 4.0, f.y + 12.0, 0.3, ground(f.x + 4.0, f.y + 12.0) - 0.05)
	_ammo_crate(f.x + 18.0, f.y - 12.0, ground(f.x + 18.0, f.y - 12.0), 0.8)
	var r := RUINS_SW
	_ruin(g, r.x, r.y, 0.4)
	_ruin(g, r.x + 12.0, r.y + 6.0, 2.4)
	_wreck(g, r.x - 8.0, r.y - 8.0, 1.0)
	_far(g.finish(self, "south_farms"), 270.0)
	rng.state = saved


# ------------------------------------------------------------------ серпантин
func _build_serpentine() -> void:
	var g := Geo.new()
	var saved := rng.state
	rng.seed = 7511
	for hp in HAIRPINS:
		var hz: float = hp[0]
		var hx: float = hp[1]
		var sgn: float = hp[2]
		# каменный парапет по внешнему краю дуги
		var px := hx + sgn * 5.6
		for k in range(-4, 5):
			var zz := hz + k * 3.1 - 4.0
			var y := _ground_min(px, zz, 1.5) - 0.2
			g.box("rock", Vector3(px, y + 0.45, zz), Vector3(0.8, 0.95, 3.1), 0.0, true)
		# пост на внутренней стороне: мешки и блоки
		var ix := hx - sgn * 18.0
		_sandbags(g, Vector2(ix, hz - 8.0), Vector2(ix, hz - 3.0), ground(ix, hz - 5.0) - 0.1, 4)
		_barrier(g, hx - sgn * 10.0, hz + 7.0, 0.2, ground(hx - sgn * 10.0, hz + 7.0) - 0.05)
		_barrier(g, hx - sgn * 14.0, hz - 9.0, 1.4, ground(hx - sgn * 14.0, hz - 9.0) - 0.05)
		_cover_spots.append(Vector3(ix, hz - 5.0, 6.0))
	# разбитый грузовик на третьем колене и ящики боеприпасов у второй шпильки
	_wreck(g, 52.0, 94.0, 0.15)
	_ammo_crate(-40.0, 118.0, ground(-40.0, 118.0), 0.3)
	_wreck(g, 62.0, 36.0, 1.9)
	_far(g.finish(self, "serpentine"), 250.0)
	rng.state = saved


# ------------------------------------------------------------------ мост через ущелье
func _build_bridge() -> void:
	var g := Geo.new()
	var gz := _gz(BR_X)
	var zs := gz + 18.5
	var zn := gz - 18.5
	var ys := ground(BR_X, zs)
	var yn := ground(BR_X, zn)
	bridge_y = Vector2(ys, yn)
	var len := zs - zn
	var ang := atan2(yn - ys, len)
	var midy := (ys + yn) * 0.5
	g.box("asphalt", Vector3(BR_X, midy - 0.3, gz), Vector3(7.2, 0.6, len + 0.6), 0.0, true, ang)
	# фермы по бортам, перила, стойки
	for sx in [-3.45, 3.45]:
		g.box("rust", Vector3(BR_X + sx, midy + 0.45, gz), Vector3(0.28, 1.35, len), 0.0, true, ang)
		g.box("plate_dark", Vector3(BR_X + sx, midy + 1.2, gz), Vector3(0.36, 0.14, len), 0.0, false, ang)
		var nb := 8
		for k in nb:
			var t0 := float(k) / nb
			var t1 := float(k + 1) / nb
			var za := zs - len * t0
			var zb := zs - len * t1
			var ya := lerpf(ys, yn, t0)
			var yb := lerpf(ys, yn, t1)
			var d := Vector3(0, (yb - ya) + (1.0 if k % 2 == 0 else -1.0) * 1.1, zb - za)
			var cen := Vector3(BR_X + sx, (ya + yb) * 0.5 + 0.45, (za + zb) * 0.5)
			g.box("rust", cen, Vector3(0.14, 0.14, d.length()), 0.0, false, atan2(d.y, absf(d.z)) * (1.0 if d.z < 0.0 else -1.0))
	# опоры: устои у берегов и столб посередине до дна ущелья
	var floor_y := ground(BR_X, gz)
	for zz in [zs - 1.2, zn + 1.2]:
		var yy := ground(BR_X, zz)
		g.box("concrete", Vector3(BR_X, (yy - 0.6 + floor_y) * 0.5, zz), Vector3(7.8, yy - 0.6 - floor_y + 1.0, 2.4), 0.0, true)
	g.box("concrete", Vector3(BR_X, (midy - 0.6 + floor_y) * 0.5, gz), Vector3(3.6, midy - 0.6 - floor_y + 0.5, 3.0), 0.0, true)
	for sx in [-2.8, 2.8]:
		g.box("concrete", Vector3(BR_X + sx, midy - 1.1, gz), Vector3(0.5, 1.0, len * 0.9), 0.0, false, ang)
	# заграждения на съездах с моста: северный — укреплённый
	_sandbags(g, Vector2(BR_X - 9.0, zn - 6.0), Vector2(BR_X - 4.5, zn - 6.0), yn - 0.1, 4)
	_sandbags(g, Vector2(BR_X + 4.5, zn - 6.0), Vector2(BR_X + 9.0, zn - 6.0), yn - 0.1, 4)
	_sandbags(g, Vector2(BR_X - 9.0, zs + 6.0), Vector2(BR_X - 4.5, zs + 6.0), ys - 0.1, 4)
	_sandbags(g, Vector2(BR_X + 5.0, zs + 8.0), Vector2(BR_X + 9.5, zs + 8.0), ys - 0.1, 4)
	_barrier(g, BR_X + 1.5, zs + 3.0, 0.1, ys - 0.05)
	bridge_node = g.finish(self, "bridge")
	_far(bridge_node, 420.0)
	objectives["bridge"] = Vector3(BR_X, midy + 0.15, gz + 1.0)


# ------------------------------------------------------------------ застава на седловине
func _build_fort() -> void:
	var g := Geo.new()
	var y := PASS_H
	var saved := rng.state
	rng.seed = 7611
	_gr.seed = 7612
	var f := FORT
	var oh := {}
	var ih := _bld(g, "hq", f.x - 44.0, f.y - 24.0, 0.0, {}, oh)
	_garrison(oh, ih, 3, 1, 1, 1)
	# разведданные: стол на втором этаже
	var best := Vector3(f.x - 44.0, y + 3.7, f.y - 26.0)
	for p in oh.get("inside", []):
		if (p as Vector3).y > best.y - 0.5:
			best = p
	g.box("wood_dark", Vector3(best.x, best.y + 0.4, best.z), Vector3(1.3, 0.8, 0.8), 0.0, true)
	_make_intel(Vector3(best.x, best.y + 0.84, best.z))
	var ob := {}
	var ib := _bld(g, "block", f.x + 40.0, f.y - 24.0, 0.0, {"floors": 3}, ob)
	_garrison(ob, ib, 3, 0, 1, 0)
	var og := {}
	_garrison(og, _bld(g, "garages", f.x - 40.0, f.y + 22.0, PI, {"count": 3}, og), 1, 0, 0, 0)
	var ow := {}
	_garrison(ow, _bld(g, "warehouse", f.x + 38.0, f.y + 22.0, PI, {"w": 20.0, "d": 11.0}, ow), 2, 0, 0, 0)
	var obo := {}
	_garrison(obo, _bld(g, "booth", f.x + 11.0, f.y + 26.0, PI * 0.5, {"boom": true}, obo), 1, 0, 0, 0)
	_bld(g, "shed", f.x - 8.0, f.y - 30.0, 0.0, {"iron": true})
	_bld(g, "shed", f.x + 70.0, f.y - 2.0, -PI * 0.5)
	_tower(g, f.x - 62.0, f.y + 24.0, false, y)
	_tower(g, f.x + 70.0, f.y + 24.0, false, y)
	# двор: техника, контейнеры, мешки, блоки
	_wreck(g, f.x - 20.0, f.y - 4.0, 0.2)
	_container(g, f.x + 18.0, f.y - 8.0, 0.1, "container_green", y)
	_container(g, f.x - 56.0, f.y - 6.0, 1.5, "container_green", y)
	_prop("portable_generator", Vector3(f.x - 30.0, y, f.y - 18.0), 0.4, "box", "metal")
	for sb in [[f.x - 12.0, f.y + 14.0, f.x - 7.0, f.y + 14.0], [f.x + 6.0, f.y + 22.0, f.x + 10.5, f.y + 22.0], [f.x + 16.0, f.y - 2.0, f.x + 20.5, f.y - 2.0],
			[f.x - 24.0, f.y + 10.0, f.x - 24.0, f.y + 5.0], [f.x + 54.0, f.y + 10.0, f.x + 54.0, f.y + 5.0]]:
		_sandbags(g, Vector2(sb[0], sb[1]), Vector2(sb[2], sb[3]), y, 4)
	for b in [[f.x - 2.0, f.y + 6.0, 1.57], [f.x + 22.0, f.y + 12.0, 0.3], [f.x - 36.0, f.y + 4.0, 0.6], [f.x + 50.0, f.y - 8.0, 1.2], [f.x + 4.0, f.y - 16.0, 0.0]]:
		_barrier(g, b[0], b[1], b[2], y)
	for c in [[f.x - 14.0, f.y - 8.0, 1.2], [f.x + 30.0, f.y - 6.0, 1.3], [f.x + 31.4, f.y - 6.2, 1.0], [f.x - 28.0, f.y + 16.0, 1.2]]:
		_crate(g, c[0], c[1], c[2], rng.randf_range(-0.4, 0.4), y)
	_barrels(f.x + 24.0, f.y + 16.0, 4, y)
	_ammo_crate(f.x + 26.0, f.y - 4.0, y, 0.2)
	_ammo_crate(f.x - 36.0, f.y - 14.0, y, 1.2)
	_far(g.finish(self, "fort"), 360.0)
	rng.state = saved


# ------------------------------------------------------------------ ретранслятор на восточной вершине (цель)
func _build_relay() -> void:
	var g := Geo.new()
	var c := RELAY
	var y: float = pads[7].h
	var saved := rng.state
	rng.seed = 7711
	_gr.seed = 7712
	g.box("floor", Vector3(c.x, y + 0.1, c.y), Vector3(16, 0.2, 14))
	_container(g, c.x + 9.0, c.y + 3.0, 1.5, "container_green", y)
	_container(g, c.x - 9.0, c.y - 5.0, 0.2, "container_grey", y)
	_sandbags(g, Vector2(c.x - 8.0, c.y + 11.0), Vector2(c.x - 2.0, c.y + 11.0), y, 4)
	_sandbags(g, Vector2(c.x + 4.0, c.y + 11.0), Vector2(c.x + 10.0, c.y + 11.0), y, 4)
	_sandbags(g, Vector2(c.x - 13.0, c.y), Vector2(c.x - 13.0, c.y + 6.0), y, 4)
	_prop("portable_generator", Vector3(c.x + 5.0, y + 0.2, c.y - 5.0), 0.8, "box", "metal")
	_barrels(c.x - 5.0, c.y - 8.0, 3, y)
	_crate(g, c.x + 8.0, c.y - 8.0, 1.2, 0.2, y)
	_ammo_crate(c.x + 12.0, c.y + 9.0, y, 0.4)
	_barrier(g, c.x + 1.0, c.y + 14.0, 0.2, y)
	_barrier(g, c.x - 14.0, c.y + 14.0, -0.3, y)
	var o := {}
	_garrison(o, _bld(g, "booth", c.x + 20.0, c.y + 8.0, -PI * 0.5, {"boom": false}, o), 1, 0, 0, 0)
	_far(g.finish(self, "relay_site"), 280.0)
	# решётчатая мачта 26 м, антенны, тарелка
	var mg := Geo.new()
	for sx in [-0.7, 0.7]:
		for sz in [-0.7, 0.7]:
			mg.box("rust", Vector3(c.x + sx, y + 13.0, c.y + sz), Vector3(0.12, 26.0, 0.12), 0.0, false)
	for i in 13:
		var by := y + 1.0 + i * 2.0
		mg.box("rust", Vector3(c.x, by, c.y - 0.7), Vector3(1.9, 0.06, 0.06), 0.0, false, 0.0, 0.8 if i % 2 == 0 else -0.8)
		mg.box("rust", Vector3(c.x, by, c.y + 0.7), Vector3(1.9, 0.06, 0.06), 0.0, false, 0.0, -0.8 if i % 2 == 0 else 0.8)
		mg.box("rust", Vector3(c.x - 0.7, by, c.y), Vector3(0.06, 0.06, 1.9), 0.0, false, 0.8 if i % 2 == 0 else -0.8)
		mg.box("rust", Vector3(c.x + 0.7, by, c.y), Vector3(0.06, 0.06, 1.9), 0.0, false, -0.8 if i % 2 == 0 else 0.8)
	mg.collider("metal", Transform3D(Basis(), Vector3(c.x, y + 13.0, c.y)), Vector3(1.6, 26.0, 1.6))
	mg.box("floor", Vector3(c.x, y + 0.3, c.y), Vector3(3.2, 0.2, 3.2))
	mg.box("plate_dark", Vector3(c.x + 1.6, y + 22.0, c.y), Vector3(0.1, 0.1, 1.8), 0.0, false)
	mg.box("plate", Vector3(c.x - 1.0, y + 25.0, c.y + 0.8), Vector3(0.8, 0.5, 0.3), 0.0, false)
	relay_node = mg.finish(self, "relay_mast")
	_far(relay_node, 700.0)
	relay_dish = Node3D.new()
	relay_dish.position = Vector3(c.x + 1.2, y + 18.0, c.y + 0.9)
	add_child(relay_dish)
	var dish := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.4
	sm.height = 0.7
	sm.is_hemisphere = true
	sm.radial_segments = 16
	sm.rings = 4
	dish.mesh = sm
	var dm := (Mats.get_mat("plate") as BaseMaterial3D).duplicate() as BaseMaterial3D
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dish.material_override = dm
	dish.rotation.x = PI * 0.5
	relay_dish.add_child(dish)
	var lamp := MeshInstance3D.new()
	var ls := SphereMesh.new()
	ls.radius = 0.14
	ls.height = 0.28
	lamp.mesh = ls
	lamp.material_override = Mats.emissive(Color(1, 0.1, 0.05), 3.0)
	lamp.position = Vector3(c.x, y + 26.2, c.y)
	add_child(lamp)
	relay_lamp = lamp
	objectives["relay"] = Vector3(c.x, y + 1.0, c.y + 2.4)
	rng.state = saved


# ------------------------------------------------------------------ горный пост на западном склоне
func _build_lodge() -> void:
	var g := Geo.new()
	var c := LODGE
	var y: float = pads[8].h
	var saved := rng.state
	rng.seed = 7811
	_gr.seed = 7812
	var o := {}
	_garrison(o, _bld(g, "house2", c.x + 2.0, c.y - 4.0, PI * 0.5, {"east": false}, o), 2, 0, 1, 0)
	_bld(g, "shed", c.x - 6.0, c.y + 12.0, 0.0, {"iron": true})
	_tower(g, c.x - 10.0, c.y - 12.0, false, y)
	_sandbags(g, Vector2(c.x + 14.0, c.y + 4.0), Vector2(c.x + 14.0, c.y + 9.0), y, 4)
	_barrier(g, c.x + 12.0, c.y - 12.0, 0.4, y)
	_crate(g, c.x - 4.0, c.y + 6.0, 1.2, 0.3, y)
	_ammo_crate(c.x + 8.0, c.y + 8.0, y, 0.4)
	_far(g.finish(self, "lodge"), 260.0)
	rng.state = saved


# ------------------------------------------------------------------ хутор в северной котловине
func _build_hamlet() -> void:
	var g := Geo.new()
	var c := HAMLET
	var saved := rng.state
	rng.seed = 7911
	_gr.seed = 7912
	var north := [[-30.0, "house_fence"], [-4.0, "ruin"], [24.0, "house2"]]
	var south := [[-26.0, "house"], [0.0, "garages"], [28.0, "house_east"]]
	for side in 2:
		var lst: Array = north if side == 0 else south
		var zz := c.y - 16.0 if side == 0 else c.y + 16.0
		var yaw := 0.0 if side == 0 else PI
		for it in lst:
			var out := {}
			var info := _bld(g, String(it[1]), c.x + float(it[0]), zz, yaw, {}, out)
			_garrison(out, info, 1, 0, 1 if String(it[1]) == "house2" else 0, 0)
	_barrier(g, c.x - 10.0, c.y + 2.0, 0.3, ground(c.x - 10.0, c.y + 2.0) - 0.05)
	_wreck(g, c.x + 40.0, c.y + 3.0, 1.2)
	_ammo_crate(c.x + 14.0, c.y + 25.0, ground(c.x + 14.0, c.y + 25.0), 0.3)
	_far(g.finish(self, "hamlet"), 300.0)
	rng.state = saved


# ------------------------------------------------------------------ лесопилка и склад боеприпасов (цель)
func _build_mill() -> void:
	var g := Geo.new()
	var c := MILL
	var y: float = pads[10].h
	var saved := rng.state
	rng.seed = 8011
	_gr.seed = 8012
	var o1 := {}
	_garrison(o1, _bld(g, "warehouse", c.x - 4.0, c.y - 8.0, PI, {"w": 24.0, "d": 12.0}, o1), 3, 1, 0, 0)
	var o2 := {}
	_garrison(o2, _bld(g, "house", c.x + 30.0, c.y + 6.0, -PI * 0.5, {}, o2), 2, 0, 0, 0)
	_bld(g, "shed", c.x - 30.0, c.y + 14.0, 0.0, {"iron": true})
	# штабеля брёвен
	for k in 4:
		for j in 3 - k % 2:
			g.cyl("bark", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(c.x - 26.0 + j * 0.85 + k % 2 * 0.4, y + 0.45 + k * 0.78, c.y + 22.0)), 0.42, 7.0, 8)
	for k in 3:
		g.cyl("bark", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x + 20.0 + k * 0.9, y + 0.45, c.y - 24.0)), 0.42, 6.0, 8)
	g.box("rust", Vector3(c.x + 12.0, y + 2.0, c.y - 20.0), Vector3(5.0, 4.0, 3.0))
	# склад боеприпасов: обвалованная площадка
	var dx := c.x + 16.0
	var dz := c.y + 14.0
	_container(g, dx - 3.0, dz, 0.0, "container_green", y)
	_container(g, dx + 4.5, dz + 3.0, 0.1, "container_grey", y)
	for s in [[dx - 9.0, dz - 5.0, dx + 9.0, dz - 5.0], [dx - 9.0, dz - 5.0, dx - 9.0, dz + 8.0], [dx + 9.0, dz - 5.0, dx + 9.0, dz + 8.0]]:
		_sandbags(g, Vector2(s[0], s[1]), Vector2(s[2], s[3]), y, 5)
	for k in 6:
		_crate(g, dx - 3.0 + (k % 3) * 1.3, dz + 4.5 + int(k / 3) * 1.3, 1.1, rng.randf_range(-0.2, 0.2), y)
	objectives["depot"] = Vector3(dx, y + 1.0, dz + 3.0)
	_ammo_crate(c.x - 16.0, c.y + 6.0, y, 0.4)
	_truck(g, c.x + 4.0, c.y + 20.0, 0.9, y)
	_barrels(c.x + 30.0, c.y - 14.0, 4, y)
	for b in [[c.x - 14.0, c.y + 2.0, 0.3], [c.x + 22.0, c.y - 6.0, 1.2], [c.x + 3.0, c.y + 30.0, 0.8]]:
		_barrier(g, b[0], b[1], b[2], y)
	var dep := g.finish(self, "mill")
	_far(dep, 300.0)
	_burn["depot"] = [dep]
	rng.state = saved


func _build_lz() -> void:
	var y: float = pads[11].h
	objectives["lz"] = Vector3(LZ.x, y, LZ.y)
	var g := Geo.new()
	for a in 4:
		var ang := a * PI * 0.5 + 0.4
		g.box("#d9d2c0", Vector3(LZ.x + cos(ang) * 6.0, y + 0.03, LZ.y + sin(ang) * 6.0), Vector3(2.4, 0.04, 0.5), -ang, false)
	_crate(g, LZ.x - 8.0, LZ.y + 5.0, 1.2, 0.2, y)
	_crate(g, LZ.x + 7.0, LZ.y - 7.0, 1.3, 0.6, y)
	_ammo_crate(LZ.x - 6.0, LZ.y - 6.0, y, 0.8)
	_far(g.finish(self, "lz"), 220.0)


## Опорные точки в поле вокруг районов: [центр, мин. радиус, макс. радиус, число секторов].
func _build_field_cover() -> void:
	var saved := rng.state
	rng.seed = 52127
	var g := Geo.new()
	var n_ok := 0
	var anchors := [[VILLAGE, 95.0, 140.0, 8], [FORT, 78.0, 120.0, 6], [Vector2(0, 232), 30.0, 90.0, 5], [MILL, 60.0, 100.0, 5],
		[HAMLET, 55.0, 90.0, 4], [Vector2(60, -310), 20.0, 70.0, 4], [FARMS, 55.0, 90.0, 3]]
	for an in anchors:
		var ac: Vector2 = an[0]
		var cnt: int = an[3]
		for i in cnt:
			var x := 0.0
			var z := 0.0
			var found := false
			for t in 14:
				var a := TAU * (i + rng.randf_range(-0.35, 0.35)) / cnt
				var r := rng.randf_range(float(an[1]), float(an[2]))
				x = ac.x + cos(a) * r
				z = ac.y + sin(a) * r
				if road_dist(x, z) < 9.0 or not _cover_ok(x, z, 28.0, 6.0):
					continue
				var span := maxf(absf(ground(x + 3.5, z) - ground(x - 3.5, z)), absf(ground(x, z + 3.5) - ground(x, z - 3.5)))
				if span <= 0.8:
					found = true
					break
			if not found:
				continue
			var yaw := atan2(ac.x - x, ac.y - z) + PI
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
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var q := _lw(x, z, yaw, side * rng.randf_range(7.0, 10.0), rng.randf_range(2.0, 5.0))
			if _cover_ok(q.x, q.y, 26.0, 4.0):
				_cover_spots.append(Vector3(q.x, q.y, 3.0))
				_field_crates(g, q.x, q.y, yaw)
			_cover_spots.append(Vector3(x, z, 7.5))
			n_ok += 1
	_far(g.finish(self, "field_cover"), 300.0)
	field_cover_count = n_ok
	rng.state = saved


# ------------------------------------------------------------------ задачи
func mission_objectives() -> Array:
	return [
		{"id": "bridge", "title": "Подорвать мост через ущелье", "pos": objectives.bridge, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "intel", "title": "Забрать разведданные в штабе заставы", "pos": objectives.intel, "done": false, "prompt": "Забрать разведданные", "hold": 1.2, "armed": false},
		{"id": "relay", "title": "Уничтожить ретранслятор на восточной вершине", "pos": objectives.relay, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "depot", "title": "Взорвать склад боеприпасов на лесопилке", "pos": objectives.depot, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "lz", "title": "Выйти к точке эвакуации в северной котловине", "pos": objectives.lz, "done": false, "locked": true, "prompt": "", "hold": 0.0, "armed": false},
	]


func briefing() -> String:
	return "Противник держит перевал «Седло» — единственную дорогу через хребет. Вы входите в южную котловину со стороны границы.\n\n" \
		+ "• Пройти горную деревню и серпантин к перевалу\n• Подорвать мост через ущелье\n• Забрать разведданные в штабе заставы на седловине\n" \
		+ "• Уничтожить ретранслятор на восточной вершине (горная дорога от деревни)\n• Взорвать склад боеприпасов на лесопилке в северной котловине\n" \
		+ "• Выйти к точке эвакуации на северо-востоке\n\nСкалы и ельники дают укрытие, но по дороге ходят патрули и машины."


func _process(delta: float) -> void:
	if relay_dish and relay_alive:
		relay_dish.rotate_y(delta * 0.6)


func destroy_objective(key: String) -> void:
	var burnt := Mats.flat(Color(0.05, 0.045, 0.04), 0.95)
	if key == "relay":
		relay_alive = false
		relay_dish.rotation = Vector3(0.9, relay_dish.rotation.y, 0.5)
		relay_dish.position.y -= 3.0
		for c in relay_dish.get_children():
			(c as MeshInstance3D).material_override = burnt
		relay_node.material_override = burnt
		relay_lamp.visible = false
	elif key == "bridge":
		bridge_node.material_override = burnt
	elif key == "intel":
		intel_node.visible = false
	for n in _burn.get(key, []):
		(n as GeometryInstance3D).material_override = burnt


func bench_views() -> Array:
	var gz := _gz(BR_X)
	return [["деревня, улица", Vector3(-10, 0, 440), Vector3(-10, 3, 330)],
		["серпантин снизу", Vector3(-10, 0, 290), Vector3(20, 40, 100)],
		["шпилька, вид сверху", Vector3(60, 0, 150), Vector3(-50, 5, 125)],
		["мост с юга", Vector3(36, 0, gz + 26.0), Vector3(BR_X, 0, gz - 30.0)],
		["мост сбоку, из ущелья", Vector3(-20, 0, gz + 22.0), Vector3(BR_X, -6, gz)],
		["мост с севера", Vector3(40, 0, gz - 30.0), Vector3(BR_X, -3, gz + 20.0)],
		["застава, двор", Vector3(30, 0, FORT.y + 24.0), Vector3(30, 5, FORT.y - 20.0)],
		["застава с севера", Vector3(30, 0, FORT.y - 70.0), Vector3(30, 5, FORT.y + 10.0)],
		["склон к ретранслятору", Vector3(250, 0, -90), Vector3(250, 20, -170)],
		["ретранслятор, вид вниз", Vector3(230, 0, -150), Vector3(160, -30, 20)],
		["северная котловина", Vector3(100, 0, -330), Vector3(220, 6, -430)],
		["лесопилка", Vector3(-170, 0, -380), Vector3(-250, 3, -400)],
		["панорама на перевал с юга", Vector3(0, 0, 500), Vector3(30, 60, -50)],
		["горный пост", Vector3(-230, 0, 60), Vector3(-255, 5, -30)]]


# ------------------------------------------------------------------ машины
## Индексы дорог: 0 главная, 1 северная, 2 к ретранслятору, 3 к лесопилке, 4 к горному посту.
func _define_vehicles() -> void:
	var v := VILLAGE
	var f := FORT
	vehicle_spots = [
		[Vector3(v.x - 6.0, 0, v.y - 30.0), 1.57, "civ"], [Vector3(v.x + 5.0, 0, v.y + 5.0), -1.57, "civ"], [Vector3(v.x - 5.0, 0, v.y + 40.0), 1.5, "civ"],
		[Vector3(v.x + 32.0, 0, v.y + 24.0), 0.0, "mil"], [Vector3(FARMS.x + 6.0, 0, FARMS.y + 14.0), 0.5, "civ"],
		[Vector3(50, 0, 205), 1.57, "mil"], [Vector3(-30, 0, 140), 1.57, "mil"], [Vector3(60, 0, 50), 0.0, "mil"],
		[Vector3(f.x - 20.0, 0, f.y + 8.0), 0.0, "mil"], [Vector3(f.x + 15.0, 0, f.y - 14.0), 1.57, "mil"], [Vector3(f.x + 52.0, 0, f.y + 10.0), 3.0, "mil"],
		[Vector3(RELAY.x - 8.0, 0, RELAY.y + 20.0), 1.2, "mil"], [Vector3(LODGE.x + 10.0, 0, LODGE.y + 18.0), 0.2, "mil"],
		[Vector3(HAMLET.x - 20.0, 0, HAMLET.y + 4.0), 1.6, "civ"], [Vector3(MILL.x + 10.0, 0, MILL.y + 22.0), 0.4, "any"],
		[Vector3(-200, 0, -402), 1.57, "any"], [Vector3(300, 0, -444), 1.5, "any"], [Vector3(14, 0, 500), 0.2, "civ"],
	]
	vehicle_patrols = [[0, 2], [1, 2], [2, 2]]


# ------------------------------------------------------------------ противники
## Одиночные посты (без маршрута, не снайперы) прореживаются: см. post_keep.
func _e(x: float, z: float, yaw_deg: float, kind := 0, route := [], y := -1000.0, hold := false) -> void:
	if route.is_empty() and kind != 2 and not _in_garrison and _thin.randf() > post_keep:
		return
	super._e(x, z, yaw_deg, kind, route, y, hold)


var _in_garrison := false


func _define_enemies() -> void:
	_thin.seed = 4711
	var v := VILLAGE
	# въезд в деревню с юга и севера, патрули по улице
	_e(v.x - 4.0, v.y + 74.0, 0, 0)
	_e(v.x + 5.0, v.y + 72.0, 0, 1)
	_e(v.x + 3.0, v.y - 72.0, 180, 0)
	_e(v.x - 4.0, v.y - 70.0, 180, 1)
	_e(v.x, v.y + 50.0, 0, 0, [[v.x, v.y + 50.0], [v.x - 2.0, v.y - 45.0]])
	_e(v.x + 4.0, v.y - 40.0, 180, 0, [[v.x + 4.0, v.y - 40.0], [v.x, v.y + 30.0]])
	_e(v.x - 36.0, v.y + 38.0, 90)
	_e(v.x + 38.0, v.y - 18.0, -90)
	# южные хозяйства и руины, патрули по котловине
	_e(FARMS.x - 4.0, FARMS.y + 14.0, 200, 0, [[FARMS.x - 40.0, FARMS.y + 14.0], [FARMS.x + 40.0, FARMS.y + 14.0]])
	_e(FARMS.x + 20.0, FARMS.y - 10.0, 120)
	_e(RUINS_SW.x + 4.0, RUINS_SW.y + 6.0, 20)
	_e(RUINS_SW.x - 10.0, RUINS_SW.y - 4.0, 60, 1)
	_e(120.0, 330.0, 0, 0, [[110.0, 300.0], [180.0, 340.0], [150.0, 380.0]])
	_e(-120.0, 380.0, 0, 0, [[-110.0, 330.0], [-160.0, 400.0], [-60.0, 420.0]])
	_e(10.0, 470.0, 0, 0, [[12.0, 500.0], [0.0, 430.0]])
	# шпильки серпантина: пост на каждой, снайпер на склоне над вторым и четвёртым коленом
	for hp in HAIRPINS:
		var hz: float = hp[0]
		var hx: float = hp[1]
		var sgn: float = hp[2]
		_e(hx - sgn * 18.0, hz - 3.0, 90.0 * sgn)
		_e(hx - sgn * 17.0, hz - 8.0, 90.0 * sgn, 1)
	_e(-60.0, 126.0, 80, 2, [], -1000.0, true)
	_e(100.0, 60.0, 260, 2, [], -1000.0, true)
	_e(20.0, 120.0, 0, 0, [[-30.0, 143.0], [60.0, 163.0], [95.0, 175.0]])
	_e(10.0, 38.0, 0, 0, [[-30.0, 25.0], [50.0, 45.0]])
	# мост и южный берег
	var gz := _gz(BR_X)
	_e(BR_X - 7.0, gz + 26.0, 180)
	_e(BR_X + 8.0, gz + 24.0, 180, 1)
	_e(BR_X, gz + 3.0, 0, 0, [[BR_X, gz + 14.0], [BR_X, gz - 14.0]])
	_e(BR_X - 6.0, gz - 24.0, 0)
	_e(BR_X + 7.0, gz - 24.0, 0, 1)
	# застава (внутри зданий — гарнизоны Bld)
	var f := FORT
	_e(f.x + 3.0, f.y + 22.0, 180)
	_e(f.x + 18.0, f.y + 24.0, 180)
	_e(f.x - 20.0, f.y + 8.0, 180, 1)
	_e(f.x + 10.0, f.y - 6.0, 180)
	_e(f.x - 62.0, f.y + 24.0, 180, 2, [], PASS_H + 5.0, true)
	_e(f.x + 70.0, f.y + 24.0, 180, 2, [], PASS_H + 5.0, true)
	_e(f.x - 48.0, f.y - 4.0, 180, 0, [[f.x - 55.0, f.y + 6.0], [f.x - 10.0, f.y + 12.0], [f.x + 55.0, f.y + 6.0], [f.x + 10.0, f.y - 14.0]])
	_e(f.x + 30.0, f.y - 32.0, 0, 0)
	# ретранслятор и тропа к нему
	var r := RELAY
	_e(r.x + 6.0, r.y + 10.0, 180)
	_e(r.x - 9.0, r.y + 6.0, 180, 1)
	_e(r.x + 2.0, r.y - 10.0, 0)
	_e(r.x - 3.0, r.y + 2.0, 90, 2, [], -1000.0, true)
	_e(r.x, r.y + 16.0, 180, 0, [[r.x - 14.0, r.y + 16.0], [r.x + 14.0, r.y + 14.0], [r.x + 14.0, r.y - 12.0], [r.x - 14.0, r.y - 12.0]])
	_e(236.0, 60.0, 180, 0, [[232.0, 50.0], [248.0, -20.0]])
	_e(245.0, 160.0, 180, 1)
	# горный пост
	var l := LODGE
	_e(l.x + 12.0, l.y + 6.0, 90)
	_e(l.x - 4.0, l.y + 8.0, 180, 1)
	_e(l.x - 10.0, l.y - 12.0, 270, 2, [], float(pads[8].h) + 5.0, true)
	_e(-262.0, 60.0, 0, 0, [[-260.0, 80.0], [-256.0, 0.0]])
	# северный спуск
	_e(36.0, -190.0, 0, 0, [[36.0, -170.0], [22.0, -250.0]])
	_e(40.0, -280.0, 0, 0, [[20.0, -250.0], [50.0, -310.0], [90.0, -355.0]])
	_e(15.0, -200.0, 90, 1)
	_e(60.0, -330.0, 0, 0)
	# хутор у дороги
	_e(HAMLET.x - 14.0, HAMLET.y + 2.0, 0, 0, [[HAMLET.x - 40.0, HAMLET.y], [HAMLET.x + 40.0, HAMLET.y + 4.0]])
	_e(HAMLET.x + 26.0, HAMLET.y - 2.0, 180)
	# лесопилка
	var m := MILL
	_e(m.x + 14.0, m.y + 8.0, 200)
	_e(m.x + 22.0, m.y + 18.0, 150, 1)
	_e(m.x + 6.0, m.y + 4.0, 160)
	_e(m.x - 22.0, m.y + 8.0, 150)
	_e(m.x + 8.0, m.y - 20.0, 0, 0, [[m.x + 8.0, m.y - 20.0], [m.x - 30.0, m.y - 18.0], [m.x - 34.0, m.y + 22.0], [m.x + 38.0, m.y + 22.0]])
	_e(m.x + 50.0, m.y + 26.0, 200, 2, [], -1000.0, true)
	_e(m.x - 90.0, m.y + 8.0, 90, 0, [[m.x - 120.0, m.y + 6.0], [m.x - 50.0, m.y + 6.0]])
	# эвакуация и подходы
	_e(LZ.x - 9.0, LZ.y + 7.0, 160)
	_e(LZ.x + 8.0, LZ.y - 8.0, 200, 1)
	_e(330.0, -440.0, 90, 0, [[290.0, -440.0], [370.0, -446.0]])
	_e(260.0, -420.0, 0, 0)
