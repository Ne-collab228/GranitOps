class_name MapAirfield
extends Level
## Карта 2: военный аэродром «Северный» в широкой долине (север = −Z, восток = +X).
##
## Схема (м):
##   ВПП 960x42 — z = 62, x −480…480 (бетонные плиты со швами, разметка, номера 09/27)
##   рулёжка z = −8, x −450…450; соединения с ВПП при x = −450, −180, 150, 450
##   перрон x −170…230, z −120…−16: три штурмовика (ЦЕЛЬ) x 22/40/58, транспортник (150, −68), вертолёт (−120, −62)
##   капониры (земляные валы) x −400/−350/−300/−250, z −87…−46; автопарк (−250, −175), водонапорная башня (−300, −190)
##   ангары (арочные) x −130/−80/−30, z −170…−120; КДП — башня (83, −140), кабина на 12.5 м с документами (ЦЕЛЬ)
##   штаб (150, −170), плац, казармы (215, −150/−185), столовая (265, −168); склад ГСМ в обваловании (380, −160)
##   забор x ±560, z −232…132 (север — бетонный), КПП (150, −232), ворота (300, 132) и (−440, 132), проломы
##   за забором: русло (z ≈ 215), зенитная позиция с РЛС на плато (330, 322) — ЦЕЛЬ, деревня (−360, 330),
##   лесистый кряж на севере (гребень z ≈ −590, седловина у x = −75 с лесной дорогой), овраг с кряжа у x ≈ 300,
##   эвакуация — поляна в лесу (−420, −440). За игровой зоной — горы (дальний рельеф до 2600 м).

const RWY_Z := 62.0
const RWY_L := 480.0
const RWY_W := 21.0
const TWY_Z := -8.0
const TWY_L := 450.0
const TWY_W := 8.0
const CONN_XS := [-450.0, -180.0, 150.0, 450.0]
const APRON := Rect2(-170, -120, 400, 104)
const REV_XS := [-400.0, -350.0, -300.0, -250.0]
const HANGAR_XS := [-130.0, -80.0, -30.0]
const JET_XS := [22.0, 40.0, 58.0]
const JET_Z := -52.0
const TRANSPORT := Vector2(150, -68)
const HELI := Vector2(-120, -62)
const TOWER := Vector2(83, -140)
const HQ := Vector2(150, -170)
const FUEL := Vector2(380, -160)
const KPP := Vector2(150, -232)
const FENCE_X := 560.0
const FENCE_N := -232.0
const FENCE_S := 132.0
const RADAR := Vector2(330, 322)
const VILLAGE := Vector2(-360, 330)
const LZ := Vector2(-420, -440)
const SPAWN := Vector2(40, 560)
## Версия «добавок» к рельефу (валы, профиль дорог) — поднять при правке _build_mods.
const MODS_VER := "3"

const C_JET := "#6b757b"
const C_OLIVE := "#59604a"
const C_DARK := "#25292c"
const C_GLASS := "#1b2730"
const C_WHITE := "#d6d5cc"
const C_SEAM := "#3b3a37"
const C_YELLOW := "#c9a23a"

var noise_c := FastNoiseLite.new()
## Земляные валы (капониры, обвалование): [a: Vector2, b: Vector2, высота, полуширина гребня, полуширина основания].
var _berms: Array = []
var _mod_ready := false
var _mod_skip := false
var _rh := PackedFloat32Array()
var _rw := PackedFloat32Array()
var _bh := PackedFloat32Array()
## Маска для растительности (узлы сетки рельефа): 0 — свободно, 1 — лётное поле (только трава), 2 — покрытия/постройки.
var _mask := PackedByteArray()
var _blocked: Array[Rect2] = []
var radar_rot: Node3D
var radar_alive := true


# ------------------------------------------------------------------ параметры
func _configure() -> void:
	map_key = "airfield"
	title = "Аэродром «Северный»"
	size = 1575.0
	cell = 3.0
	chunk = 105
	play_half = 715.0
	outer_half = 2600.0
	outer_cell = 21.0
	lod_dist = 300.0
	map_seed = 20261125
	sky_file = "res://assets/sky/sky2_2k.hdr"
	# солнце HDRI низковато (8°) — свет чуть выше, азимут тот же
	sun_dir = Vector3(-0.6, 0.3, 0.74).normalized()
	orbit_center = Vector3(0, 6, -30)
	orbit_radius = 430.0
	orbit_height = 95.0
	backdrop_color = Color(0.45, 0.47, 0.42)
	nav_aabb = AABB(Vector3(-play_half, -40, -play_half), Vector3(play_half * 2.0, 240, play_half * 2.0))
	spawn_max_h = 45.0
	site_points = [Vector3(40, -55, 45), Vector3(TOWER.x, TOWER.y, 30), Vector3(RADAR.x, RADAR.y, 60),
		Vector3(VILLAGE.x, VILLAGE.y, 80), Vector3(LZ.x, LZ.y, 30), Vector3(KPP.x, KPP.y, 30), Vector3(FUEL.x, FUEL.y, 50),
		Vector3(300, 132, 20), Vector3(-440, 132, 20), Vector3(SPAWN.x, SPAWN.y, 0)]


func _setup_noise() -> void:
	noise_a.seed = 31
	noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_a.frequency = 0.0035
	noise_a.fractal_octaves = 4
	noise_b.seed = 77
	noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_b.frequency = 0.02
	noise_b.fractal_octaves = 2
	noise_c.seed = 5
	noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_c.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_c.frequency = 0.0013
	noise_c.fractal_octaves = 5


func _terrain_tex() -> Dictionary:
	return {"a": "aerial_grass_rock", "b": "forrest_ground_01", "r": "rock_boulder_dry", "tint": Vector3(0.9, 0.92, 0.84),
		"grass": Vector3(0.3, 0.37, 0.15), "grass_amt": 0.2, "grass_vert": 1.0}


## Вечер: тёплое низкое солнце, холодные тени, заметная воздушная перспектива (горы вдали).
func _tune_environment() -> void:
	env.tonemap_exposure = 1.06
	env.adjustment_contrast = 1.17
	env.adjustment_saturation = 1.12
	env.ambient_light_color = Color(0.58, 0.64, 0.76)
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_energy = 0.95
	env.fog_light_color = Color(0.74, 0.74, 0.76)
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter = 0.3
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.45


# ------------------------------------------------------------------ рельеф
func _river_z(x: float) -> float:
	return 215.0 + 28.0 * sin(x / 160.0 + 0.4) + 10.0 * sin(x / 57.0 + 1.3)


func _gully_x(z: float) -> float:
	return 300.0 + 25.0 * sin(z / 70.0)


func base_height(x: float, z: float) -> float:
	var na := noise_a.get_noise_2d(x, z)
	# дно долины: пологие увалы
	var h := 3.0 + na * 3.5 + noise_b.get_noise_2d(x, z) * 0.5
	# северный кряж: гребень z ≈ −575…−610, седловина у x = −75 (лесная дорога)
	var crest_z := -590.0 + 35.0 * sin(x / 210.0 + 0.7)
	var saddle := 1.0 - 0.55 * exp(-pow((x + 75.0) / 95.0, 2.0))
	var tn := smoothstep(-345.0, crest_z, z)
	var crest_h := (70.0 + 20.0 * noise_a.get_noise_2d(x * 0.5, 900.0)) * saddle
	h += crest_h * tn + noise_a.get_noise_2d(x * 1.7, z * 1.7) * 9.0 * tn
	h -= 22.0 * smoothstep(crest_z, crest_z - 160.0, z)
	# овраг с кряжа к долине
	var gw := smoothstep(-300.0, -360.0, z) * smoothstep(-700.0, -640.0, z)
	h -= 9.0 * gw * (1.0 - smoothstep(2.0, 24.0, absf(x - _gully_x(z))))
	# южные холмы
	var ts := smoothstep(290.0, 620.0, z)
	h += ts * (40.0 + 16.0 * noise_a.get_noise_2d(x * 0.8 + 500.0, z * 0.8))
	# плато зенитной позиции
	var dr2 := Vector2(x - RADAR.x, z - RADAR.y).length_squared()
	h += 13.0 * exp(-dr2 / (2.0 * 48.0 * 48.0))
	# русло (сухой ручей): плоское дно ~10 м, крутые берега
	var dr := absf(z - _river_z(x))
	h -= 5.5 * (1.0 - smoothstep(5.0, 17.0, dr))
	# горы за игровой зоной (видны как дальние горы); долина вытянута с запада на восток
	var r := Vector2(x * 0.8, z).length()
	var o := smoothstep(740.0, 1500.0, r)
	h += o * o * (330.0 + 170.0 * noise_c.get_noise_2d(x, z))
	return h


## Высота с площадками + валы + выровненное полотно дорог (плавный продольный уклон, без поперечного).
func height_fn(x: float, z: float) -> float:
	var h := super.height_fn(x, z)
	if _mod_skip:
		return h
	if not _mod_ready:
		_build_mods()
	var fx := (x + size * 0.5) / cell
	var fz := (z + size * 0.5) / cell
	if fx < 0.0 or fz < 0.0 or fx > n or fz > n:
		return h
	var ix := mini(int(fx), n - 1)
	var iz := mini(int(fz), n - 1)
	var tx := fx - ix
	var tz := fz - iz
	var w := n + 1
	var ks := [iz * w + ix, iz * w + ix + 1, (iz + 1) * w + ix, (iz + 1) * w + ix + 1]
	var bs := [(1.0 - tx) * (1.0 - tz), tx * (1.0 - tz), (1.0 - tx) * tz, tx * tz]
	var bh := 0.0
	var rw := 0.0
	var rhw := 0.0
	for i in 4:
		var k: int = ks[i]
		var b: float = bs[i]
		bh += _bh[k] * b
		rw += _rw[k] * b
		rhw += _rh[k] * _rw[k] * b
	h += bh
	if rw > 0.001:
		h = lerpf(h, rhw / rw, rw)
	return h


## Ключ кэша рельефа: базовый (без добавок — их расчёт нужен только при пересчёте) + валы + версия добавок.
func terrain_key() -> String:
	_mod_skip = true
	var k := super.terrain_key()
	_mod_skip = false
	return str(hash(k + "|" + str(_berms) + "|" + MODS_VER))


func _pad_w(x: float, z: float) -> float:
	var best := 0.0
	for p in pads:
		var c: Vector2 = p.c
		var half: Vector2 = p.half
		var dx := maxf(absf(x - c.x) - half.x, 0.0)
		var dz := maxf(absf(z - c.y) - half.y, 0.0)
		best = maxf(best, 1.0 - smoothstep(0.0, float(p.m), sqrt(dx * dx + dz * dz)))
	return best


## Валы и профиль дорог «штампуются» в узлы сетки (только при пересчёте рельефа).
func _build_mods() -> void:
	_mod_ready = true
	var w := n + 1
	var half := size * 0.5
	_rh.resize(w * w)
	_rw.resize(w * w)
	_bh.resize(w * w)
	_rh.fill(0.0)
	_rw.fill(0.0)
	_bh.fill(0.0)
	for bm in _berms:
		var a: Vector2 = bm[0]
		var b: Vector2 = bm[1]
		var hh: float = bm[2]
		var top: float = bm[3]
		var base: float = bm[4]
		var x0 := maxi(0, int(floor((minf(a.x, b.x) - base + half) / cell)))
		var x1 := mini(n, int(ceil((maxf(a.x, b.x) + base + half) / cell)))
		var z0 := maxi(0, int(floor((minf(a.y, b.y) - base + half) / cell)))
		var z1 := mini(n, int(ceil((maxf(a.y, b.y) + base + half) / cell)))
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				var p := Vector2(ix * cell - half, iz * cell - half)
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
				var v := hh * (1.0 - smoothstep(top, base, d))
				var k := iz * w + ix
				if v > _bh[k]:
					_bh[k] = v
	var reach := 13.0
	for r in roads:
		var line: PackedVector2Array = r
		# точки через 4 м и высоты рельефа под ними
		var pts := PackedVector2Array()
		for i in line.size() - 1:
			var seg := line[i + 1] - line[i]
			var cnt := maxi(1, int(ceil(seg.length() / 4.0)))
			for j in cnt:
				pts.append(line[i] + seg * (float(j) / cnt))
		pts.append(line[line.size() - 1])
		var hs := PackedFloat32Array()
		hs.resize(pts.size())
		for i in pts.size():
			hs[i] = super.height_fn(pts[i].x, pts[i].y)
		# сглаживание (окно ±20 м) и ограничение уклона 9%
		for pass_i in 3:
			var tmp := hs.duplicate()
			for i in pts.size():
				var acc := 0.0
				var cntw := 0
				for j in range(maxi(0, i - 5), mini(pts.size(), i + 6)):
					acc += tmp[j]
					cntw += 1
				hs[i] = acc / cntw
		for i in range(1, pts.size()):
			hs[i] = clampf(hs[i], hs[i - 1] - 0.36, hs[i - 1] + 0.36)
		for i in range(pts.size() - 2, -1, -1):
			hs[i] = clampf(hs[i], hs[i + 1] - 0.36, hs[i + 1] + 0.36)
		for i in pts.size() - 1:
			var a2 := pts[i]
			var b2 := pts[i + 1]
			var x0 := maxi(0, int(floor((minf(a2.x, b2.x) - reach + half) / cell)))
			var x1 := mini(n, int(ceil((maxf(a2.x, b2.x) + reach + half) / cell)))
			var z0 := maxi(0, int(floor((minf(a2.y, b2.y) - reach + half) / cell)))
			var z1 := mini(n, int(ceil((maxf(a2.y, b2.y) + reach + half) / cell)))
			var sl := a2.distance_squared_to(b2)
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var p := Vector2(ix * cell - half, iz * cell - half)
					var t := 0.0 if sl < 0.0001 else clampf((p - a2).dot(b2 - a2) / sl, 0.0, 1.0)
					var d := p.distance_to(a2.lerp(b2, t))
					var wt := 1.0 - smoothstep(4.5, reach, d)
					var k := iz * w + ix
					if wt > _rw[k]:
						_rw[k] = wt
						_rh[k] = lerpf(hs[i], hs[i + 1], t)
	# на площадках (лётное поле, плато) дорога не меняет высоту — там и так ровно
	for k in w * w:
		if _rw[k] > 0.0:
			var px := (k % w) * cell - half
			var pz := (k / w) * cell - half
			_rw[k] *= 1.0 - _pad_w(px, pz)


## Ломаная со скруглёнными углами (радиус до r): машинам без резких поворотов.
func _rounded(pts: Array, r := 18.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		var p0: Vector2 = pts[i - 1]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var la := p0.distance_to(p1)
		var lb := p1.distance_to(p2)
		var cut := minf(r, minf(la, lb) * 0.45)
		var s := p1 + (p0 - p1).normalized() * cut
		var e := p1 + (p2 - p1).normalized() * cut
		for k in 5:
			var t := k / 4.0
			out.append(s.lerp(p1, t).lerp(p1.lerp(e, t), t))
	out.append(pts[pts.size() - 1])
	return out


func _setup_pads() -> void:
	var ring := [Vector2(-520, -205), Vector2(520, -205), Vector2(520, 110), Vector2(-520, 110), Vector2(-520, -205), Vector2(520, -205)]
	var ring_line := _rounded(ring, 20.0)
	# замкнутое кольцо: от начала первой дуги до конца четвёртой и снова к первой
	var ring_loop := ring_line.slice(1, 21)
	ring_loop.append(ring_line[1])
	roads = [
		# долинная дорога севернее аэродрома (с запада на восток)
		_rounded([Vector2(-787, -302), Vector2(-600, -290), Vector2(-450, -272), Vector2(-300, -264), Vector2(-120, -262),
			Vector2(150, -262), Vector2(350, -268), Vector2(520, -285), Vector2(640, -300), Vector2(787, -312)], 40.0),
		# КПП
		_rounded([Vector2(150, -262), Vector2(150, -232), Vector2(150, -205)]),
		# кольцевая внутри забора (северная часть — асфальт сервисной дороги)
		ring_loop,
		# к перрону и к складу ГСМ
		PackedVector2Array([Vector2(110, -205), Vector2(110, -122)]),
		PackedVector2Array([Vector2(400, -205), Vector2(400, -176)]),
		# южные ворота → брод → плато РЛС
		_rounded([Vector2(300, 110), Vector2(300, 132), Vector2(305, 170), Vector2(312, 215), Vector2(322, 262), Vector2(330, 296)], 25.0),
		# юго-западные ворота → брод → деревня (улица)
		_rounded([Vector2(-440, 110), Vector2(-440, 132), Vector2(-440, 180), Vector2(-430, 225), Vector2(-405, 275),
			Vector2(-370, 315), Vector2(-320, 350), Vector2(-280, 375)], 25.0),
		# из деревни на запад по долине
		_rounded([Vector2(-405, 275), Vector2(-470, 284), Vector2(-560, 292), Vector2(-650, 300), Vector2(-787, 306)], 30.0),
		# лесная дорога через седловину кряжа
		_rounded([Vector2(-120, -262), Vector2(-130, -330), Vector2(-110, -420), Vector2(-40, -480), Vector2(-20, -530),
			Vector2(-70, -590), Vector2(-75, -650), Vector2(-60, -787)], 30.0),
		# отворот к поляне эвакуации
		_rounded([Vector2(-110, -420), Vector2(-200, -440), Vector2(-320, -447), Vector2(-405, -440)], 30.0),
	]
	pads = [
		{"c": Vector2(0, -50), "half": Vector2(545, 168), "m": 60.0, "h": H0},
		{"c": RADAR, "half": Vector2(32, 27), "m": 34.0, "h": base_height(RADAR.x, RADAR.y) - 0.5},
		{"c": LZ, "half": Vector2(14, 14), "m": 24.0, "h": base_height(LZ.x, LZ.y)},
		{"c": SPAWN, "half": Vector2(5, 5), "m": 12.0, "h": base_height(SPAWN.x, SPAWN.y)},
	]
	# капониры: П-образные валы, открыты на юг (к рулёжке)
	_berms = []
	for cx in REV_XS:
		var x: float = cx
		_berms.append([Vector2(x - 19, -87.5), Vector2(x + 19, -87.5), 4.0, 1.2, 6.5])
		_berms.append([Vector2(x - 19, -87.5), Vector2(x - 19, -50), 4.0, 1.2, 6.5])
		_berms.append([Vector2(x + 19, -87.5), Vector2(x + 19, -50), 4.0, 1.2, 6.5])
	# обвалование склада ГСМ, въезд с севера (от сервисной дороги)
	_berms.append([Vector2(345, -190), Vector2(386, -190), 3.5, 1.0, 6.5])
	_berms.append([Vector2(345, -190), Vector2(345, -130), 3.5, 1.0, 6.5])
	_berms.append([Vector2(415, -190), Vector2(415, -130), 3.5, 1.0, 6.5])
	_berms.append([Vector2(345, -130), Vector2(415, -130), 3.5, 1.0, 6.5])
	# брустверы зенитных установок на плато (открыты к центру позиции)
	for aa in _aa_spots():
		var c: Vector2 = aa
		var to_c := (RADAR - c).angle()
		for k in 3:
			var a0 := to_c + PI * 0.45 + k * PI * 0.37
			var a1 := a0 + PI * 0.37
			_berms.append([c + Vector2(cos(a0), sin(a0)) * 7.5, c + Vector2(cos(a1), sin(a1)) * 7.5, 1.6, 0.6, 3.0])


func _aa_spots() -> Array:
	return [Vector2(RADAR.x - 25, RADAR.y - 15), Vector2(RADAR.x + 24, RADAR.y + 16)]


func _forest(x: float, z: float) -> float:
	var f := smoothstep(-360.0, -430.0, z + 28.0 * noise_a.get_noise_2d(x * 2.0, 50.0))
	f = maxf(f, smoothstep(330.0, 420.0, z) * smoothstep(-0.15, 0.2, noise_a.get_noise_2d(x * 1.6 + 400.0, z * 1.6)))
	f = maxf(f, smoothstep(0.42, 0.6, noise_a.get_noise_2d(x * 2.4 - 700.0, z * 2.4 + 300.0)) * 0.9)
	# поляны
	f *= smoothstep(-0.6, -0.35, noise_b.get_noise_2d(x * 0.22, z * 0.22))
	# лётное поле с полосой отчуждения, деревня, русло
	var dx := maxf(absf(x) - FENCE_X, 0.0)
	var dz := maxf(maxf(FENCE_N - z, z - FENCE_S), 0.0)
	f *= smoothstep(35.0, 70.0, sqrt(dx * dx + dz * dz)) if absf(x) < FENCE_X + 70.0 and z > FENCE_N - 70.0 and z < FENCE_S + 70.0 else 1.0
	f *= smoothstep(60.0, 95.0, Vector2(x, z).distance_to(VILLAGE))
	f *= smoothstep(10.0, 18.0, absf(z - _river_z(x)))
	return f


## Цвет вершины рельефа: r — лесная подстилка, g — скала/галька, b — дорога/двор, a — трава.
func _vertex_color(x: float, z: float, nrm: Vector3, rd: float) -> Color:
	var rock := smoothstep(0.84, 0.64, nrm.y)
	var bed := 1.0 - smoothstep(4.0, 11.0, absf(z - _river_z(x)))
	rock = maxf(rock, bed * 0.55)
	var fo := _forest(x, z)
	var alt := clampf(fo * 0.85 + smoothstep(0.1, 0.6, noise_b.get_noise_2d(x * 0.4 + 300.0, z * 0.4)) * 0.3, 0.0, 1.0)
	var road := 1.0 - smoothstep(2.2, 5.0, rd)
	var yard := _yard_weight(x, z)
	var grass := clampf((1.0 - alt) * (1.0 - rock) * (1.0 - maxf(road, yard)), 0.0, 1.0)
	return Color(alt, rock, maxf(road, yard), grass)


## Утоптанная земля: дворы служебной зоны, у склада, на плато РЛС, в деревне.
func _yard_weight(x: float, z: float) -> float:
	var y := 0.0
	if x > -300.0 and x < 450.0 and z > -215.0 and z < -120.0:
		y = 0.3
	y = maxf(y, (1.0 - smoothstep(20.0, 40.0, Vector2(x, z).distance_to(RADAR))) * 0.35)
	y = maxf(y, (1.0 - smoothstep(40.0, 75.0, Vector2(x, z).distance_to(VILLAGE))) * 0.18)
	return y


# ------------------------------------------------------------------ геометрия: помощники
func _block(r: Rect2) -> void:
	_blocked.append(r)


func _lbox(g: Geo, mat: String, xf: Transform3D, c: Vector3, s: Vector3, collide := false, rot := Basis()) -> void:
	g.box_xf(mat, Transform3D(xf.basis * rot, xf * c), s, collide)


func _lcyl(g: Geo, mat: String, xf: Transform3D, c: Vector3, axis: Basis, r: float, h: float, segs := 10, collide := false, caps := true, r_top := -1.0) -> void:
	g.cyl(mat, Transform3D(xf.basis * axis, xf * c), r, h, segs, collide, caps, r_top)


## Плоская деталь (крыло, стабилизатор) по контуру в плане (x, z) толщиной thick на высоте y.
func _plate(g: Geo, mat: String, xf: Transform3D, poly: Array, y: float, thick: float) -> void:
	var prof := PackedVector2Array()
	for p in poly:
		prof.append(p)
	var b := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
	Geo.extrude(g._st(mat), prof, thick * 0.5, xf * Transform3D(b, Vector3(0, y, 0)))


## Вертикальная деталь (киль) по контуру (z, y) толщиной thick, смещённая по x.
func _fin(g: Geo, mat: String, xf: Transform3D, poly: Array, x: float, thick: float) -> void:
	var prof := PackedVector2Array()
	for p in poly:
		prof.append(p)
	Geo.extrude(g._st(mat), prof, thick * 0.5, xf * Transform3D(Basis(), Vector3(x, 0, 0)))


func _mirror(poly: Array) -> Array:
	var out: Array = []
	for p in poly:
		var v: Vector2 = p
		out.append(Vector2(-v.x, v.y))
	return out


const FWD := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   # ось Y цилиндра -> −Z (нос)
const SIDE := Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))  # ось Y цилиндра -> +X (колёса)


## Бочки из цилиндров (в общий меш, без отдельных вызовов отрисовки).
func _drums(g: Geo, x: float, z: float, count: int, y: float) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var r := 0.0 if i == 0 else rng.randf_range(0.65, 1.0)
		var mat := "green" if rng.randf() < 0.6 else "rust"
		g.cyl(mat, Transform3D(Basis(), Vector3(x + cos(a + i) * r, y + 0.45, z + sin(a + i) * r)), 0.3, 0.9, 10, true)
	cover(x + 1.4, z, y)
	cover(x - 1.4, z, y)
	cover(x, z + 1.4, y)
	cover(x, z - 1.4, y)


# ------------------------------------------------------------------ постройки
func _build_sites() -> void:
	_build_pavement()
	await get_tree().process_frame
	_build_jets()
	_build_center()
	await get_tree().process_frame
	_build_west()
	_build_east()
	await get_tree().process_frame
	_build_perimeter()
	_build_radar()
	await get_tree().process_frame
	_build_village()
	_build_bld_district()
	_build_lz()
	_build_field_cover()
	_define_vehicles()
	spawn_point = Vector3(SPAWN.x, float(pads[3].h) + 0.2, SPAWN.y)


## ВПП, рулёжки, перрон, капониры, плац, сервисная дорога — один меш (5 материалов), без теней и без затенения у земли.
func _build_pavement() -> void:
	var g := Geo.new()
	g.cast_shadows = false
	var y := H0
	# --- ВПП: бетонные плиты 7.5 x 7 м
	var rt := y + 0.07
	_slab(g, "floor", Rect2(-RWY_L, RWY_Z - RWY_W, RWY_L * 2.0, RWY_W * 2.0), rt)
	_block(Rect2(-RWY_L - 4, RWY_Z - RWY_W - 3, RWY_L * 2.0 + 8, RWY_W * 2.0 + 6))
	var i := 1
	while -RWY_L + i * 7.5 < RWY_L:
		g.box(C_SEAM, Vector3(-RWY_L + i * 7.5, rt + 0.004, RWY_Z), Vector3(0.1, 0.02, RWY_W * 2.0), 0.0, false)
		i += 1
	for o in [-14.0, -7.0, 7.0, 14.0]:
		g.box(C_SEAM, Vector3(0, rt + 0.004, RWY_Z + o), Vector3(RWY_L * 2.0, 0.02, 0.1), 0.0, false)
	# разметка: кромки, осевая, «зебра» порогов, зоны прицеливания и касания, номера
	var my := rt + 0.008
	for s in [-1.0, 1.0]:
		g.box(C_WHITE, Vector3(0, my, RWY_Z + s * (RWY_W - 1.0)), Vector3(RWY_L * 2.0 - 4.0, 0.02, 0.9), 0.0, false)
	var x := -RWY_L + 90.0
	while x + 30.0 < RWY_L - 90.0:
		g.box(C_WHITE, Vector3(x + 15.0, my, RWY_Z), Vector3(30.0, 0.02, 0.9), 0.0, false)
		x += 50.0
	for end in [-1.0, 1.0]:
		var ex: float = end * RWY_L
		var inward: float = -end
		for k in 7:
			for s in [-1.0, 1.0]:
				g.box(C_WHITE, Vector3(ex + inward * 21.0, my, RWY_Z + s * (3.0 + k * 2.4)), Vector3(30.0, 0.02, 1.8), 0.0, false)
		for s in [-1.0, 1.0]:
			g.box(C_WHITE, Vector3(ex + inward * 322.0, my, RWY_Z + s * 8.0), Vector3(45.0, 0.02, 7.0), 0.0, false)
			for k in 3:
				g.box(C_WHITE, Vector3(ex + inward * 160.0, my, RWY_Z + s * (5.0 + k * 2.6)), Vector3(22.5, 0.02, 1.8), 0.0, false)
		# огни по кромкам (белые столбики)
		var lx := -RWY_L
		while lx <= RWY_L:
			g.box(C_WHITE, Vector3(lx, y + 0.2, RWY_Z + end * (RWY_W + 1.2)), Vector3(0.22, 0.4, 0.22), 0.0, false)
			lx += 60.0
	# номера: с запада «09» (заход на восток), с востока «27»
	_digits(g, C_WHITE, "09", Vector2(-RWY_L + 45.0, RWY_Z), Vector2(1, 0), my)
	_digits(g, C_WHITE, "27", Vector2(RWY_L - 45.0, RWY_Z), Vector2(-1, 0), my)
	# --- рулёжка и соединения (асфальт), жёлтая осевая
	var tt := y + 0.05
	_slab(g, "asphalt", Rect2(-TWY_L - 9.0, TWY_Z - TWY_W, TWY_L * 2.0 + 18.0, TWY_W * 2.0), tt)
	_block(Rect2(-TWY_L - 12, TWY_Z - TWY_W - 3, TWY_L * 2.0 + 24, TWY_W * 2.0 + 6))
	g.box(C_YELLOW, Vector3(0, tt + 0.008, TWY_Z), Vector3(TWY_L * 2.0, 0.02, 0.3), 0.0, false)
	for cx in CONN_XS:
		var c: float = cx
		var z0 := TWY_Z + TWY_W
		var z1 := RWY_Z - RWY_W
		_slab(g, "asphalt", Rect2(c - 9.0, z0, 18.0, z1 - z0), tt)
		_block(Rect2(c - 12, z0, 24, z1 - z0))
		g.box(C_YELLOW, Vector3(c, tt + 0.008, (z0 + z1) * 0.5), Vector3(0.3, 0.02, z1 - z0), 0.0, false)
		for zz in [z1 - 8.0, z1 - 9.0]:
			g.box(C_YELLOW, Vector3(c, tt + 0.008, zz), Vector3(18.0, 0.02, 0.3), 0.0, false)
	# --- перрон (бетон, швы 7.5 м), линии заруливания
	var at := y + 0.06
	_slab(g, "floor", APRON, at)
	_block(APRON.grow(3.0))
	var sx := APRON.position.x + 7.5
	while sx < APRON.end.x:
		g.box(C_SEAM, Vector3(sx, at + 0.004, APRON.get_center().y), Vector3(0.1, 0.02, APRON.size.y), 0.0, false)
		sx += 7.5
	var sz := APRON.position.y + 7.5
	while sz < APRON.end.y:
		g.box(C_SEAM, Vector3(APRON.get_center().x, at + 0.004, sz), Vector3(APRON.size.x, 0.02, 0.1), 0.0, false)
		sz += 7.5
	for jx in JET_XS:
		g.box(C_YELLOW, Vector3(jx, at + 0.008, -29.0), Vector3(0.3, 0.02, 26.0), 0.0, false)
	g.box(C_YELLOW, Vector3(TRANSPORT.x, at + 0.008, -33.0), Vector3(0.3, 0.02, 34.0), 0.0, false)
	g.box(C_YELLOW, Vector3(40.0, at + 0.008, -63.0), Vector3(60.0, 0.02, 0.3), 0.0, false)
	# вертолётная площадка: круг и «Н»
	for k in 20:
		var a := TAU * k / 20.0
		g.box(C_WHITE, Vector3(HELI.x + cos(a) * 9.0, at + 0.008, HELI.y + sin(a) * 9.0), Vector3(0.5, 0.02, 2.9), -a, false)
	g.box(C_WHITE, Vector3(HELI.x - 2.0, at + 0.008, HELI.y), Vector3(0.8, 0.02, 6.0), 0.0, false)
	g.box(C_WHITE, Vector3(HELI.x + 2.0, at + 0.008, HELI.y), Vector3(0.8, 0.02, 6.0), 0.0, false)
	g.box(C_WHITE, Vector3(HELI.x, at + 0.008, HELI.y), Vector3(3.2, 0.02, 0.8), 0.0, false)
	# --- капониры: площадки и выезды на рулёжку
	for cx in REV_XS:
		var c2: float = cx
		_slab(g, "asphalt", Rect2(c2 - 12.0, -80.0, 24.0, 34.0), tt)
		_slab(g, "asphalt", Rect2(c2 - 7.0, -46.0, 14.0, 30.0), tt)
		_block(Rect2(c2 - 14.0, -82.0, 28.0, 68.0))
		g.box(C_YELLOW, Vector3(c2, tt + 0.008, -40.0), Vector3(0.3, 0.02, 48.0), 0.0, false)
	# --- плац у штаба, сервисная дорога, площадка склада ГСМ
	_slab(g, "asphalt", Rect2(135, -150, 30, 20), tt)
	_block(Rect2(133, -152, 34, 24))
	_slab(g, "asphalt", Rect2(-470, -208.5, 940, 7), tt)
	_block(Rect2(-472, -210, 944, 10))
	_slab(g, "floor", Rect2(352, -183, 56, 46), at)
	_block(Rect2(340, -196, 80, 72))
	Geo.ground_fn = Callable()
	g.finish(self, "pavement")
	Geo.ground_fn = ground


func _slab(g: Geo, mat: String, r: Rect2, top: float, thick := 0.3) -> void:
	g.box(mat, Vector3(r.get_center().x, top - thick * 0.5, r.get_center().y), Vector3(r.size.x, thick, r.size.y))


## Номер ВПП «семисегментными» цифрами 4.5 x 9 м. up — направление «вверх» цифры (по ходу посадки).
func _digits(g: Geo, mat: String, txt: String, origin: Vector2, up: Vector2, y: float) -> void:
	const SEG := {"0": "abcdef", "2": "abged", "7": "abc", "9": "abcdfg"}
	var right := Vector2(-up.y, up.x)
	var wd := 4.5
	var ht := 9.0
	var th := 1.0
	for di in txt.length():
		var u0 := -6.0 if di == 0 else 1.5
		var segs: String = SEG.get(txt[di], "")
		for s in segs:
			# [u центр, v центр, длина по u, длина по v]
			var r: Array = {"a": [wd * 0.5, ht, wd, th], "b": [wd, ht * 0.75, th, ht * 0.5], "c": [wd, ht * 0.25, th, ht * 0.5],
				"d": [wd * 0.5, 0.0, wd, th], "e": [0.0, ht * 0.25, th, ht * 0.5], "f": [0.0, ht * 0.75, th, ht * 0.5],
				"g": [wd * 0.5, ht * 0.5, wd, th]}[s]
			var p := origin + right * (u0 + float(r[0])) + up * float(r[1])
			var su: float = r[2]
			var sv: float = r[3]
			var size_x := sv if absf(up.x) > 0.5 else su
			var size_z := su if absf(up.x) > 0.5 else sv
			g.box(mat, Vector3(p.x, y, p.y), Vector3(size_x, 0.02, size_z), 0.0, false)


# ------------------------------------------------------------------ самолёты
## Штурмовик (~16 м): фюзеляж, стреловидные крылья, киль, шасси. Нос по локальной −Z, начало — земля под центром.
func _jet(g: Geo, pos: Vector3, yaw: float, body := C_JET, collide := true, stores := true) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	_lcyl(g, body, xf, Vector3(0, 2.0, 0.6), FWD, 0.82, 10.0, 10)
	_lcyl(g, body, xf, Vector3(0, 2.0, -6.2), FWD, 0.82, 3.6, 10, false, false, 0.1)
	_lcyl(g, body, xf, Vector3(0, 2.0, 6.6), FWD, 0.6, 2.0, 10, false, false, 0.82)
	_lcyl(g, C_DARK, xf, Vector3(0, 2.0, 7.9), FWD, 0.55, 0.6, 10)
	for s in [-1.0, 1.0]:
		_lbox(g, body, xf, Vector3(s * 1.0, 1.85, -1.2), Vector3(0.6, 1.0, 4.2))
		_lbox(g, C_DARK, xf, Vector3(s * 1.0, 1.85, -3.32), Vector3(0.48, 0.8, 0.06))
	g.sphere(C_GLASS, xf * Transform3D(Basis(), Vector3(0, 2.72, -3.6)), Vector3(0.5, 0.48, 1.6), 10, 6)
	var wing := [Vector2(0.7, -1.6), Vector2(5.9, 2.4), Vector2(5.9, 3.5), Vector2(0.7, 4.2)]
	_plate(g, body, xf, wing, 1.75, 0.16)
	_plate(g, body, xf, _mirror(wing), 1.75, 0.16)
	var stab := [Vector2(0.7, 5.4), Vector2(3.3, 7.3), Vector2(3.3, 8.0), Vector2(0.7, 7.9)]
	_plate(g, body, xf, stab, 2.1, 0.12)
	_plate(g, body, xf, _mirror(stab), 2.1, 0.12)
	_fin(g, body, xf, [Vector2(4.6, 2.6), Vector2(7.4, 6.3), Vector2(8.3, 6.3), Vector2(8.0, 2.6)], 0.0, 0.14)
	# шасси
	_lcyl(g, C_DARK, xf, Vector3(0, 0.85, -4.8), Basis(), 0.07, 1.0, 6)
	_lcyl(g, C_DARK, xf, Vector3(0, 0.33, -4.8), SIDE, 0.33, 0.22, 10)
	for s in [-1.0, 1.0]:
		_lcyl(g, C_DARK, xf, Vector3(s * 1.5, 0.9, 1.4), Basis(), 0.08, 1.0, 6)
		_lcyl(g, C_DARK, xf, Vector3(s * 1.6, 0.42, 1.4), SIDE, 0.42, 0.3, 10)
		if stores:
			_lcyl(g, C_DARK, xf, Vector3(s * 3.3, 1.38, 1.4), FWD, 0.2, 2.6, 8, false, true)
			_lbox(g, C_DARK, xf, Vector3(s * 3.3, 1.6, 1.4), Vector3(0.08, 0.22, 1.2))
	if collide:
		g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 2.0, 0.1)), Vector3(1.8, 1.7, 16.0))
		g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 1.75, 1.5)), Vector3(11.8, 0.25, 4.0))
		g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 4.4, 7.2)), Vector3(0.3, 3.6, 2.6))
	for c in [Vector3(4.0, 0, -2.0), Vector3(-4.0, 0, -2.0), Vector3(2.0, 0, 6.5), Vector3(-2.0, 0, 6.5)]:
		cover_points.append(xf * c)


## Военно-транспортный самолёт (~34 м): высокоплан, 4 винтовых двигателя, Т-образное оперение.
func _transport(g: Geo, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var b := C_OLIVE
	_lcyl(g, b, xf, Vector3(0, 3.3, 0), FWD, 1.9, 22.0, 14, false, false)
	g.sphere(b, xf * Transform3D(Basis(), Vector3(0, 3.3, -11.0)), Vector3(1.9, 1.9, 3.5), 14, 7)
	_lbox(g, C_GLASS, xf, Vector3(0, 4.35, -12.5), Vector3(2.4, 0.6, 1.0), false, Basis(Vector3.RIGHT, 0.5))
	_lcyl(g, b, xf, Vector3(0, 4.0, 15.0), Basis(Vector3.RIGHT, -0.14) * FWD, 0.5, 8.2, 14, false, true, 1.9)
	var wing := [Vector2(0.0, -2.5), Vector2(19.0, -1.2), Vector2(19.0, 1.0), Vector2(0.0, 2.0)]
	_plate(g, b, xf, wing, 5.3, 0.4)
	_plate(g, b, xf, _mirror(wing), 5.3, 0.4)
	_lbox(g, b, xf, Vector3(0, 5.1, -0.2), Vector3(3.0, 0.6, 4.5))
	for ex in [-10.5, -5.5, 5.5, 10.5]:
		_lcyl(g, b, xf, Vector3(ex, 4.8, -1.6), FWD, 0.55, 4.4, 10, false, true, 0.4)
		_lcyl(g, C_DARK, xf, Vector3(ex, 4.8, -3.95), FWD, 0.18, 0.4, 8)
		for a in [0.4, 0.4 + PI * 0.5]:
			_lbox(g, C_DARK, xf, Vector3(ex, 4.8, -4.05), Vector3(0.22, 3.6, 0.06), false, Basis(Vector3.BACK, a))
	_fin(g, b, xf, [Vector2(13.0, 5.0), Vector2(17.5, 11.0), Vector2(19.5, 11.0), Vector2(19.0, 5.0)], 0.0, 0.3)
	var stab := [Vector2(0.0, 16.6), Vector2(6.5, 18.0), Vector2(6.5, 19.4), Vector2(0.0, 19.6)]
	_plate(g, b, xf, stab, 10.9, 0.25)
	_plate(g, b, xf, _mirror(stab), 10.9, 0.25)
	for s in [-1.0, 1.0]:
		_lbox(g, b, xf, Vector3(s * 2.0, 1.6, 0.0), Vector3(1.0, 1.6, 6.0))
		for wz in [-1.5, 1.5]:
			_lcyl(g, C_DARK, xf, Vector3(s * 2.0, 0.6, wz), SIDE, 0.6, 0.5, 12)
	_lcyl(g, C_DARK, xf, Vector3(0, 1.2, -9.5), Basis(), 0.1, 1.4, 6)
	_lcyl(g, C_DARK, xf, Vector3(0, 0.5, -9.5), SIDE, 0.5, 0.4, 10)
	g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 3.3, 2.0)), Vector3(3.8, 3.8, 34.0))
	g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 5.3, -0.2)), Vector3(38.0, 0.4, 4.5))
	g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 8.0, 17.0)), Vector3(0.4, 6.0, 5.0))
	for c in [Vector3(3.2, 0, -6), Vector3(-3.2, 0, -6), Vector3(3.2, 0, 8), Vector3(-3.2, 0, 8)]:
		cover_points.append(xf * c)


## Вертолёт: фюзеляж-капля, хвостовая балка, 5 лопастей, крылышки с блоками НАР, полозья.
func _heli(g: Geo, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var b := C_OLIVE
	g.sphere(b, xf * Transform3D(Basis(), Vector3(0, 2.0, 0)), Vector3(1.35, 1.35, 3.6), 12, 7)
	g.sphere(C_GLASS, xf * Transform3D(Basis(), Vector3(0, 2.45, -2.5)), Vector3(1.0, 0.85, 1.3), 10, 6)
	_lcyl(g, b, xf, Vector3(0, 2.45, 6.6), FWD, 0.22, 7.6, 8, false, true, 0.55)
	_fin(g, b, xf, [Vector2(9.6, 2.2), Vector2(10.8, 4.4), Vector2(11.4, 4.4), Vector2(10.7, 2.2)], 0.0, 0.12)
	_lbox(g, C_DARK, xf, Vector3(0.25, 3.6, 10.9), Vector3(0.05, 2.0, 0.18))
	_lbox(g, b, xf, Vector3(0, 3.35, 0.3), Vector3(1.3, 0.8, 3.2))
	_lcyl(g, C_DARK, xf, Vector3(0, 4.0, 0), Basis(), 0.15, 0.7, 8)
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		var c := Vector3(cos(a) * 3.8, 4.32, sin(a) * 3.8)
		_lbox(g, C_DARK, xf, c, Vector3(7.4, 0.05, 0.5), false, Basis(Vector3.UP, -a))
	_lbox(g, b, xf, Vector3(0, 1.9, 0.4), Vector3(3.8, 0.12, 1.0))
	for s in [-1.0, 1.0]:
		_lcyl(g, C_DARK, xf, Vector3(s * 1.8, 1.6, 0.4), FWD, 0.26, 1.6, 8)
		_lbox(g, C_DARK, xf, Vector3(s * 1.15, 0.08, 0.0), Vector3(0.12, 0.12, 4.6))
		for zz in [-1.2, 1.4]:
			_lbox(g, C_DARK, xf, Vector3(s * 1.0, 0.45, zz), Vector3(0.08, 0.8, 0.08), false, Basis(Vector3.BACK, s * 0.35))
	g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 2.0, 0)), Vector3(2.6, 2.6, 7.2))
	g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 2.45, 7.0)), Vector3(0.8, 0.9, 7.0))
	for c in [Vector3(2.2, 0, -1), Vector3(-2.2, 0, -1), Vector3(0, 0, 4.5)]:
		cover_points.append(xf * c)


## Цель: три штурмовика на перроне (свой меш — после подрыва обгорают).
func _build_jets() -> void:
	var g := Geo.new()
	for jx in JET_XS:
		_jet(g, Vector3(jx, H0 + 0.06, JET_Z), PI)
	var mi := g.finish(self, "jets_target")
	_burn["jets"] = [mi]
	objectives["jets"] = Vector3(40.0, H0 + 0.9, JET_Z + 9.6)
	blast_fx["jets"] = {"fires": [[Vector3(-18, 0.8, -9), 2.0], [Vector3(0, 0.8, -9), 2.2], [Vector3(18, 0.8, -9), 2.0]],
		"blasts": [[0.6, Vector3(-18, 1.5, -10)], [1.3, Vector3(18, 1.5, -10)], [2.1, Vector3(0, 2.0, -12)]]}


# ------------------------------------------------------------------ центр: ангары, КДП, перрон
func _build_center() -> void:
	var g := Geo.new()
	var y := H0
	for hx in HANGAR_XS:
		_hangar(g, hx, -120.0, 40.0, 50.0, 14.0, y)
	# в ангарах: штурмовик на обслуживании, грузовики, ящики
	_jet(g, Vector3(HANGAR_XS[0], y + 0.08, -147.0), PI, C_JET, true, false)
	for s in [-1.0, 1.0]:
		g.box("plate_dark", Vector3(HANGAR_XS[0] + s * 7.0, y + 0.6, -136.0), Vector3(1.2, 1.1, 2.0))
	_truck(g, HANGAR_XS[1] - 8.0, -148.0, 0.0, y + 0.08)
	_truck(g, HANGAR_XS[1] + 7.0, -150.0, 0.1, y + 0.08)
	for c in [[HANGAR_XS[2] - 10.0, -160.0, 1.3], [HANGAR_XS[2] - 8.5, -160.4, 1.1], [HANGAR_XS[2] + 9.0, -158.0, 1.2], [HANGAR_XS[2] + 10.5, -157.0, 1.0]]:
		_crate(g, c[0], c[1], c[2], rng.randf_range(-0.3, 0.3), y + 0.08)
	_container(g, HANGAR_XS[2] - 6.0, -140.0, PI * 0.5, "container_green", y + 0.08)
	_ammo_crate(HANGAR_XS[1] + 14.0, -128.0, y + 0.08, 0.3)
	_build_tower(g, y)
	# дежурное здание у КДП
	_building(g, 68.0, -140.0, 14.0, 9.0, 3.4, "plaster", {"s": [win(2.0), door(6.0), win(10.0)], "n": [win(3.0), win(9.0)],
		"w": [win(3.5)], "e": [door(3.5)]}, y)
	_block(Rect2(60, -146, 30, 13))
	_ammo_crate(64.0, -137.5, y + 0.08, 0.1)
	# транспортник, вертолёт, техника обслуживания на перроне
	_transport(g, Vector3(TRANSPORT.x, y + 0.06, TRANSPORT.y), PI)
	_heli(g, Vector3(HELI.x, y + 0.06, HELI.y), PI * 0.8)
	_tanker(g, 76.0, -44.0, 0.3, y + 0.06)
	_truck(g, -40.0, -95.0, 1.4, y + 0.06)
	for p in [[10.0, -70.0], [70.0, -72.0], [128.0, -40.0]]:
		g.box("green", Vector3(p[0], y + 0.5, p[1]), Vector3(1.6, 0.7, 2.8), 0.2)
		for s in [-0.7, 0.7]:
			g.cyl(C_DARK, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(p[0] + s, y + 0.25, p[1] - 0.8)), 0.25, 0.15, 8, false)
	for b in [[0.0, -40.0, 0.0], [5.0, -40.0, 0.1], [84.0, -38.0, 0.0], [-60.0, -30.0, 1.5], [-150.0, -35.0, 0.3], [200.0, -50.0, 1.3]]:
		_barrier(g, b[0], b[1], b[2], y + 0.06)
	_sandbags(g, Vector2(-8.0, -82.0), Vector2(-3.0, -82.0), y + 0.06)
	_sandbags(g, Vector2(-8.0, -82.0), Vector2(-8.0, -78.0), y + 0.06)
	_sandbags(g, Vector2(96.0, -100.0), Vector2(101.0, -100.0), y + 0.06)
	_drums(g, 92.0, -60.0, 4, y + 0.06)
	_drums(g, -100.0, -100.0, 3, y + 0.06)
	_crate(g, 120.0, -100.0, 1.2, 0.2, y + 0.06)
	_crate(g, 121.4, -100.3, 1.0, -0.1, y + 0.06)
	# ветроуказатель
	g.cyl("plate_dark", Transform3D(Basis(), Vector3(20.0, y + 3.0, 100.0)), 0.07, 6.0, 6, true)
	g.cyl("#d9672a", Transform3D(Basis(Vector3.BACK, PI * 0.5 - 0.12), Vector3(21.3, y + 5.6, 100.0)), 0.18, 2.6, 8, false, false, 0.38)
	# огни подхода за торцами ВПП
	for end in [-1.0, 1.0]:
		var ex: float = end * (RWY_L + 15.0)
		while absf(ex) < FENCE_X - 8.0:
			g.cyl("plate_dark", Transform3D(Basis(), Vector3(ex, y + 1.0, RWY_Z)), 0.06, 2.0, 6, false)
			g.box(C_WHITE, Vector3(ex, y + 2.05, RWY_Z), Vector3(0.3, 0.12, 0.3), 0.0, false)
			if int(absf(ex)) % 30 < 15:
				g.box("plate_dark", Vector3(ex, y + 1.9, RWY_Z), Vector3(0.12, 0.1, 9.0), 0.0, false)
			ex += end * 15.0
	for lp in [[-105.0, -118.0], [-55.0, -118.0], [0.0, -118.0], [45.0, -118.0], [120.0, -112.0], [210.0, -118.0]]:
		_lamp(g, lp[0], lp[1], y, PI)
	g.finish(self, "center")


## Арочный ангар: свод из гофролиста вдоль Z, задняя стена с дверью, фронт (z = front) открыт.
func _hangar(g: Geo, cx: float, front: float, w: float, d: float, h: float, y: float) -> void:
	var zc := front - d * 0.5
	var hw := w * 0.5
	var segs := 14
	g.box("floor", Vector3(cx, y + 0.04, zc), Vector3(w - 0.4, 0.08, d))
	_block(Rect2(cx - hw - 2.0, front - d - 2.0, w + 4.0, d + 4.0))
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector2(cos(a0) * hw, sin(a0) * h)
		var p1 := Vector2(cos(a1) * hw, sin(a1) * h)
		var mid := (p0 + p1) * 0.5
		var ln := p0.distance_to(p1)
		var ang := atan2(p1.y - p0.y, p1.x - p0.x)
		g.box("iron", Vector3(cx + mid.x, y + mid.y, zc), Vector3(ln + 0.06, 0.16, d), 0.0, true, 0.0, ang)
		# рёбра свода и бетонный портал
		for rz in [front - 0.3, zc, front - d + 0.3]:
			var mat := "concrete" if rz == front - 0.3 else "plate_dark"
			var th := 0.7 if rz == front - 0.3 else 0.3
			g.box(mat, Vector3(cx + mid.x * 1.02, y + mid.y * 1.02, rz), Vector3(ln + 0.1, th, 0.6), 0.0, false, 0.0, ang)
	# задняя стена — полукруг с дверью (профиль выдавлен по Z)
	var prof := PackedVector2Array()
	for i in segs + 1:
		var a := PI * i / segs
		prof.append(Vector2(cos(a) * (hw - 0.1), sin(a) * (h - 0.1)))
	prof.append(Vector2(-1.2, 0.0))
	prof.append(Vector2(-1.2, 2.3))
	prof.append(Vector2(1.2, 2.3))
	prof.append(Vector2(1.2, 0.0))
	# extrude: профиль.x -> мир −x (зеркально, полукруг симметричен), профиль.y -> y, толщина по z
	Geo.extrude(g._st("iron"), prof, 0.12, Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3(cx, y, front - d + 0.15)))
	for k in 8:
		var xa := -hw + (k + 0.5) * (w / 8.0)
		if absf(xa) < 2.0:
			continue
		var hh := h * sqrt(maxf(0.0, 1.0 - pow((absf(xa) + w / 16.0) / hw, 2.0)))
		g.collider("sheet", Transform3D(Basis(), Vector3(cx + xa, y + hh * 0.5, front - d + 0.15)), Vector3(w / 8.0, hh, 0.25))
	g.collider("sheet", Transform3D(Basis(), Vector3(cx, y + (h + 2.3) * 0.5, front - d + 0.15)), Vector3(4.0, h - 2.3, 0.25))
	for c in [Vector2(cx - hw + 2.0, front + 1.5), Vector2(cx + hw - 2.0, front + 1.5), Vector2(cx - hw + 3.0, zc), Vector2(cx + hw - 3.0, zc)]:
		cover_points.append(Vector3(c.x, y, c.y))


## КДП: бетонная башня 6x6, внешняя стальная лестница (3 марша), застеклённая кабина на 12.5 м.
func _build_tower(g: Geo, y: float) -> void:
	var cx := TOWER.x
	var cz := TOWER.y
	var fl := y + 10.5
	g.box("concrete", Vector3(cx, y + 5.2, cz), Vector3(6.0, 10.4, 6.0))
	for k in 3:
		g.box(C_GLASS, Vector3(cx, y + 2.5 + k * 3.0, cz + 3.02), Vector3(1.2, 1.0, 0.06), 0.0, false)
	_block(Rect2(cx - 6, cz - 6, 14, 12))
	# лестница: колонны A (x+4.9) и B (x+6.2), марши по 3.5 м
	var ax := cx + 5.2
	var bx := cx + 6.5
	g.stairs("plate_dark", Vector3(ax, y, cz + 6.0), 0.0, 1.2, 3.5, 5.5)
	g.box("plate_dark", Vector3(cx + 5.05, y + 3.4, cz - 0.5), Vector3(4.1, 0.2, 2.0))
	g.stairs("plate_dark", Vector3(bx, y + 3.5, cz - 1.5), PI, 1.2, 3.5, 5.5)
	g.box("plate_dark", Vector3(cx + 5.05, y + 6.9, cz + 5.0), Vector3(4.1, 0.2, 2.0))
	g.stairs("plate_dark", Vector3(ax, y + 7.0, cz + 4.0), 0.0, 1.2, 3.5, 5.5)
	g.box("plate_dark", Vector3(cx + 5.3, fl - 0.1, cz - 2.5), Vector3(3.6, 0.2, 2.0))
	# опоры площадок и перила (без коллизии) + невидимые перила снаружи
	for p in [[cx + 7.15, cz - 1.4], [cx + 7.15, cz + 5.9], [cx + 7.15, cz - 3.4]]:
		g.box("plate_dark", Vector3(p[0], y + 5.2, p[1]), Vector3(0.12, 10.4, 0.12), 0.0, false)
	for k in 3:
		g.box("plate_dark", Vector3(cx + 7.2, y + 1.0 + k * 3.5 + 1.75, cz + 1.5), Vector3(0.05, 0.05, 9.0), 0.0, false, 0.0, 0.0)
	g.collider("metal", Transform3D(Basis(), Vector3(cx + 7.25, y + 7.0, cz + 1.0)), Vector3(0.1, 14.0, 10.0))
	# кабина 9x9: парапет с дверью на восток, остекление (без коллизии — снайпер видит сквозь), крыша
	var h0 := fl
	g.box("concrete", Vector3(cx, fl - 0.15, cz), Vector3(9.0, 0.3, 9.0))
	var c00 := Vector3(cx - 4.5, h0, cz - 4.5)
	var c10 := Vector3(cx + 4.5, h0, cz - 4.5)
	var c01 := Vector3(cx - 4.5, h0, cz + 4.5)
	var c11 := Vector3(cx + 4.5, h0, cz + 4.5)
	g.wall("concrete", c00, c10, 1.0, 0.2)
	g.wall("concrete", c01, c11, 1.0, 0.2)
	g.wall("concrete", c00, c01, 1.0, 0.2)
	g.wall("concrete", c10, c11, 1.0, 0.2, [[1.2, 2.6, 0.0, 1.0]])
	g.box("plate_dark", Vector3(cx + 4.5, h0 + 1.15, cz - 3.3), Vector3(0.2, 2.3, 0.08), 0.0, true)
	g.box("plate_dark", Vector3(cx + 4.5, h0 + 1.15, cz - 1.9), Vector3(0.2, 2.3, 0.08), 0.0, true)
	for s in [[Vector3(cx, 0, cz - 4.55), Vector3(9.0, 0, 0.06)], [Vector3(cx, 0, cz + 4.55), Vector3(9.0, 0, 0.06)],
			[Vector3(cx - 4.55, 0, cz), Vector3(0.06, 0, 9.0)], [Vector3(cx + 4.55, 0, cz + 1.3), Vector3(0.06, 0, 6.4)], [Vector3(cx + 4.55, 0, cz - 3.9), Vector3(0.06, 0, 1.2)]]:
		var c: Vector3 = s[0]
		var sz: Vector3 = s[1]
		g.box(C_GLASS, Vector3(c.x, h0 + 1.95, c.z), Vector3(sz.x, 1.9, sz.z), 0.0, false)
	g.box(C_GLASS, Vector3(cx + 4.55, h0 + 2.6, cz - 2.6), Vector3(0.06, 0.6, 1.4), 0.0, false)
	for k in 7:
		var t := -4.5 + k * 1.5
		for mp in [Vector3(cx + t, 0, cz - 4.58), Vector3(cx + t, 0, cz + 4.58), Vector3(cx - 4.58, 0, cz + t), Vector3(cx + 4.58, 0, cz + t)]:
			g.box("plate_dark", Vector3(mp.x, h0 + 1.95, mp.z), Vector3(0.1, 1.9, 0.1), 0.0, false)
	g.box("concrete", Vector3(cx, h0 + 3.05, cz), Vector3(10.0, 0.3, 10.0))
	g.cyl("plate_dark", Transform3D(Basis(), Vector3(cx - 2.5, h0 + 5.2, cz - 2.5)), 0.06, 4.0, 6, false)
	g.sphere("#cfcfc8", Transform3D(Basis(), Vector3(cx + 2.0, h0 + 3.7, cz + 2.0)), Vector3(0.8, 0.8, 0.8), 10, 5)
	# пульт и документы
	g.box("wood_dark", Vector3(cx - 1.0, h0 + 0.78, cz - 3.6), Vector3(6.0, 0.08, 1.0))
	g.box("plate_dark", Vector3(cx - 1.0, h0 + 0.38, cz - 3.75), Vector3(6.0, 0.74, 0.7))
	g.box(C_GLASS, Vector3(cx - 2.5, h0 + 1.05, cz - 3.95), Vector3(0.6, 0.45, 0.06), 0.0, false, -0.2)
	g.box(C_GLASS, Vector3(cx - 0.5, h0 + 1.05, cz - 3.95), Vector3(0.6, 0.45, 0.06), 0.0, false, -0.2)
	_make_intel(Vector3(cx + 1.2, h0 + 0.83, cz - 3.5))
	for c in [Vector3(cx - 3.2, h0, cz + 3.2), Vector3(cx + 3.2, h0, cz + 3.2), Vector3(cx - 3.2, h0, cz - 2.0)]:
		cover_points.append(c)


## Бензовоз: шасси и кабина как у грузовика, вместо кузова — цистерна.
func _tanker(g: Geo, x: float, z: float, yaw: float, base_y: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, base_y, z))
	_lbox(g, "green", xf, Vector3(0, 0.95, 0), Vector3(2.2, 0.3, 6.6))
	_lbox(g, "green", xf, Vector3(0, 1.95, -2.2), Vector3(2.3, 1.7, 1.9))
	_lbox(g, "green", xf, Vector3(0, 1.5, -3.55), Vector3(2.0, 0.8, 0.9))
	_lbox(g, "plate_dark", xf, Vector3(0, 2.2, -3.17), Vector3(1.9, 0.75, 0.04))
	_lcyl(g, "plate", xf, Vector3(0, 2.1, 1.2), FWD, 1.05, 4.2, 14)
	_lbox(g, "plate_dark", xf, Vector3(0, 3.2, 1.2), Vector3(0.6, 0.15, 0.8))
	for wz in [-2.5, 0.6, 2.1]:
		for wx in [-1.05, 1.05]:
			_lcyl(g, C_DARK, xf, Vector3(wx, 0.52, wz), SIDE, 0.52, 0.34, 12)
	g.collider("metal", xf * Transform3D(Basis(), Vector3(0, 1.7, 0)), Vector3(2.4, 3.0, 6.8))
	for c in [Vector3(1.9, 0, 0), Vector3(-1.9, 0, 0), Vector3(0, 0, 4.1), Vector3(0, 0, -4.4)]:
		cover_points.append(xf * c)


# ------------------------------------------------------------------ запад: капониры, автопарк
func _build_west() -> void:
	var g := Geo.new()
	var y := H0
	# капониры: два штурмовика, бензовоз, вертолёт
	_jet(g, Vector3(REV_XS[0], y + 0.05, -66.0), PI, "#5f6a5a")
	_jet(g, Vector3(REV_XS[1], y + 0.05, -66.0), PI)
	_tanker(g, REV_XS[2] + 2.0, -66.0, 0.15, y + 0.05)
	_drums(g, REV_XS[2] - 7.0, -74.0, 5, y + 0.05)
	_crate(g, REV_XS[2] - 8.0, -60.0, 1.2, 0.2, y + 0.05)
	_heli(g, Vector3(REV_XS[3], y + 0.05, -64.0), PI)
	for cx in REV_XS:
		var c: float = cx
		g.box("concrete", Vector3(c, y + 1.4, -80.6), Vector3(22.0, 2.8, 0.4))
		_sandbags(g, Vector2(c - 13.0, -42.0), Vector2(c - 9.0, -42.0), y)
		cover_points.append(Vector3(c - 12.0, y, -48.0))
		cover_points.append(Vector3(c + 12.0, y, -48.0))
	_ammo_crate(REV_XS[1] + 9.0, -78.0, y + 0.05, 0.0)
	# автопарк: навес на столбах, грузовики, мастерская
	var px := -250.0
	var pz := -175.0
	g.box("iron", Vector3(px, y + 4.6, pz), Vector3(43.0, 0.12, 13.0), 0.0, true, 0.06)
	for k in 8:
		for s in [-1.0, 1.0]:
			g.box("rust", Vector3(px - 21.0 + k * 6.0, y + 2.3, pz + s * 6.0), Vector3(0.18, 4.6, 0.18))
	g.wall("iron", Vector3(px - 21.5, y, pz - 6.4), Vector3(px + 21.5, y, pz - 6.4), 4.3, 0.12)
	for k in 3:
		_truck(g, px - 13.0 + k * 12.0, pz + 0.5, 0.0, y)
	_tanker(g, px + 24.0 + 6.0, pz + 2.0, 0.4, y)
	_building(g, -200.0, -175.0, 20.0, 14.0, 5.5, "iron", {"s": [[6.0, 13.0, 0.0, 4.5]], "e": [door(5.0)], "w": [win(4.0), win(9.0)]}, y, "iron", 0.14)
	_block(Rect2(-274, -184, 86, 18))
	_crate(g, -203.0, -177.0, 1.3, 0.2, y + 0.08)
	_crate(g, -201.5, -177.3, 1.1, -0.1, y + 0.08)
	_drums(g, -192.0, -172.0, 3, y + 0.08)
	_prop("portable_generator", Vector3(-206.0, y + 0.08, -171.0), 0.4, "box", "metal")
	# водонапорная башня
	var wx := -300.0
	var wz := -190.0
	for sx in [-1.6, 1.6]:
		for sz in [-1.6, 1.6]:
			g.box("rust", Vector3(wx + sx, y + 6.5, wz + sz), Vector3(0.25, 13.0, 0.25))
	for k in 3:
		g.box("rust", Vector3(wx, y + 3.0 + k * 3.5, wz - 1.6), Vector3(3.4, 0.1, 0.1), 0.0, false, 0.0, 0.8 if k % 2 == 0 else -0.8)
		g.box("rust", Vector3(wx, y + 3.0 + k * 3.5, wz + 1.6), Vector3(3.4, 0.1, 0.1), 0.0, false, 0.0, -0.8 if k % 2 == 0 else 0.8)
	g.cyl("green", Transform3D(Basis(), Vector3(wx, y + 15.5, wz)), 3.0, 5.0, 16, true)
	g.cyl("plate_dark", Transform3D(Basis(), Vector3(wx, y + 18.4, wz)), 3.1, 0.8, 16, false, true, 0.4)
	_block(Rect2(wx - 4, wz - 4, 8, 8))
	_tower(g, -540.0, -215.0, false)
	_tower(g, -540.0, 115.0, true)
	for lp in [[-430.0, -200.0], [-350.0, -200.0], [-270.0, -200.0], [-190.0, -200.0], [-110.0, -200.0], [-30.0, -200.0]]:
		_lamp(g, lp[0], lp[1], y, 0.0)
	g.finish(self, "west")


# ------------------------------------------------------------------ восток: штаб, казармы, склад ГСМ, КПП
func _build_east() -> void:
	var g := Geo.new()
	var y := H0
	# --- штаб (2 этажа), лестница у западной стены
	var hx := HQ.x
	var hz := HQ.y
	_building(g, hx, hz, 22.0, 12.0, 3.2, "plaster_tan",
		{"s": [win(2.0), win(6.0), door(10.0), win(14.0), win(18.0)], "n": [win(3.0), win(9.0), win(15.0)], "e": [door(5.0)], "w": [win(7.0)]},
		y, "floor", 0.3, true, false)
	g.box("floor", Vector3(hx + 1.75, y + 3.1, hz), Vector3(18.5, 0.2, 12.0))
	g.box("floor", Vector3(hx - 9.25, y + 3.1, hz - 3.0), Vector3(3.5, 0.2, 6.0))
	g.stairs("floor", Vector3(hx - 9.5, y, hz + 5.0), 0.0, 1.8, 3.2, 4.8)
	g.box("wood_dark", Vector3(hx - 7.45, y + 3.7, hz + 2.6), Vector3(0.08, 1.0, 5.2))
	_building(g, hx, hz, 22.0, 12.0, 3.0, "plaster_tan",
		{"s": [win(2.0), win(6.0), win(10.0), win(14.0), win(18.0)], "n": [win(3.0), win(9.0), win(15.0)], "e": [win(5.0)], "w": [win(4.0), win(8.0)]},
		y + 3.2, "concrete", 0.3, false, true)
	for s in [[hx, hz - 6.1, 22.5, 0.2], [hx, hz + 6.1, 22.5, 0.2], [hx - 11.1, hz, 0.2, 12.4], [hx + 11.1, hz, 0.2, 12.4]]:
		g.box("concrete", Vector3(s[0], y + 6.65, s[1]), Vector3(s[2], 0.5, s[3]))
	g.box("wood_dark", Vector3(hx + 4.0, y + 0.76, hz - 3.5), Vector3(2.4, 0.08, 1.0))
	g.box("wood_dark", Vector3(hx + 4.0, y + 0.38, hz - 3.5), Vector3(2.2, 0.72, 0.8), 0.0, false)
	g.box("wood_dark", Vector3(hx + 6.0, y + 3.95, hz - 3.5), Vector3(1.8, 0.08, 0.9))
	_prop("steel_frame_shelves_01", Vector3(hx + 9.5, y + 0.08, hz - 4.6), 0.0, "box", "metal", 0.1)
	_ammo_crate(hx - 4.0, hz - 4.0, y + 0.08, 0.2)
	_block(Rect2(hx - 13, hz - 8, 26, 16))
	# флагшток на плацу
	g.cyl("plate_dark", Transform3D(Basis(), Vector3(150.0, y + 5.0, -134.0)), 0.07, 10.0, 6, true)
	g.box("#8a2a22", Vector3(151.0, y + 9.3, -134.0), Vector3(2.0, 1.2, 0.03), 0.0, false)
	# --- казармы и столовая
	_building(g, 215.0, -150.0, 30.0, 10.0, 3.2, "plaster", {"s": [door(3.0), win(7.0), win(11.0), door(15.0), win(19.0), win(23.0), door(26.0)],
		"n": [win(4.0), win(10.0), win(16.0), win(22.0)], "e": [win(4.0)], "w": [win(4.0)]}, y)
	_building(g, 215.0, -185.0, 30.0, 10.0, 3.2, "plaster", {"n": [door(3.0), win(7.0), win(11.0), door(15.0), win(19.0), win(23.0), door(26.0)],
		"s": [win(4.0), win(10.0), win(16.0), win(22.0)], "e": [win(4.0)]}, y)
	_building(g, 265.0, -168.0, 14.0, 12.0, 3.4, "plaster_tan", {"s": [win(2.0), door(6.0), win(10.0)], "w": [door(5.0)], "n": [win(5.0)]}, y)
	_block(Rect2(198, -192, 76, 48))
	_sandbags(g, Vector2(188.0, -140.0), Vector2(192.0, -140.0), y)
	_sandbags(g, Vector2(240.0, -168.0), Vector2(240.0, -164.0), y)
	_drums(g, 276.0, -160.0, 3, y)
	_truck(g, 245.0, -132.0, 1.4, y)
	# --- склад ГСМ: 4 резервуара в обваловании, трубопровод, насосная, бензовозы
	var gt := Geo.new()
	for t in [Vector2(366, -171), Vector2(394, -171), Vector2(366, -149), Vector2(394, -149)]:
		gt.cyl("green", Transform3D(Basis(), Vector3(t.x, y + 4.56, t.y)), 6.0, 9.0, 22, true)
		gt.cyl("plate_dark", Transform3D(Basis(), Vector3(t.x, y + 9.45, t.y)), 6.1, 0.8, 22, false, true, 1.2)
		for k in 2:
			gt.box("rust", Vector3(t.x + 6.08, y + 4.6, t.y - 0.3 + k * 0.6), Vector3(0.06, 9.0, 0.06), 0.0, false)
	_burn["fuel"] = [gt.finish(self, "fuel_tanks")]
	objectives["fuel"] = Vector3(380.0, y + 1.0, -160.0)
	blast_fx["fuel"] = {"fires": [[Vector3(-14, 1.0, -11), 2.4], [Vector3(14, 1.0, -11), 2.4], [Vector3(-14, 1.0, 11), 2.4], [Vector3(14, 1.0, 11), 2.4]],
		"blasts": [[0.5, Vector3(-14, 4, -11)], [1.1, Vector3(14, 4, 11)], [1.8, Vector3(14, 4, -11)], [2.4, Vector3(-14, 4, 11)]]}
	g.cyl("rust", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(380.0, y + 0.7, -160.0)), 0.18, 44.0, 8, false)
	g.cyl("rust", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(380.0, y + 0.7, -168.0)), 0.18, 16.0, 8, false)
	_building(g, 432.0, -195.0, 8.0, 6.0, 3.0, "plaster", {"w": [door(2.0)], "s": [win(3.0)]}, y, "iron")
	_block(Rect2(426, -200, 12, 10))
	_tanker(g, 392.0, -138.5, PI * 0.5, y + 0.06)
	_drums(g, 356.0, -138.0, 5, y + 0.06)
	_ammo_crate(372.0, -139.0, y + 0.06, 0.0)
	_lamp(g, 386.0, -196.0, y, PI * 0.5)
	# --- КПП: проходная, шлагбаум, блоки «змейкой», мешки
	var kx := KPP.x
	var kz := KPP.y
	_bld(g, "booth", kx + 12.0, kz + 6.0, -PI * 0.5)
	_bld(g, "booth", kx - 12.0, kz - 3.0, PI * 0.5)
	g.box("rust", Vector3(kx - 6.5, y + 0.6, kz - 3.0), Vector3(0.25, 1.2, 0.25))
	g.box(C_WHITE, Vector3(kx - 1.0, y + 1.1, kz - 3.0), Vector3(11.0, 0.12, 0.12), 0.0, false)
	for k in 5:
		g.box("#a8322a", Vector3(kx - 5.0 + k * 2.2, y + 1.1, kz - 3.0), Vector3(1.0, 0.13, 0.13), 0.0, false)
	for b in [[kx - 3.0, kz - 14.0, 0.0], [kx + 3.0, kz - 20.0, 0.0], [kx - 3.0, kz - 26.0, 0.0]]:
		_barrier(g, b[0], b[1], b[2], ground(b[0], b[1]) - 0.05)
	_sandbags(g, Vector2(kx - 12.0, kz - 7.0), Vector2(kx - 7.0, kz - 7.0), ground(kx - 9.5, kz - 7.0) - 0.05)
	_sandbags(g, Vector2(kx + 7.0, kz - 7.0), Vector2(kx + 12.0, kz - 7.0), ground(kx + 9.5, kz - 7.0) - 0.05)
	_tower(g, 540.0, -215.0, false)
	_tower(g, 540.0, 115.0, true)
	for lp in [[60.0, -200.0], [140.0, -200.0], [220.0, -200.0], [300.0, -200.0], [460.0, -200.0]]:
		_lamp(g, lp[0], lp[1], y, 0.0)
	# пулемётное гнездо у долинной дороги на востоке
	_nest(g, 600.0, -280.0, atan2(600.0, -280.0))
	_cover_spots.append(Vector3(600.0, -280.0, 7.0))
	g.finish(self, "east")


# ------------------------------------------------------------------ забор
## Периметр: север — бетонные плиты (не простреливаются), остальное — сетка. Ворота и проломы.
func _build_perimeter() -> void:
	var g := Geo.new()
	g.cast_shadows = false
	var gaps_n := [[KPP.x - 6.0, KPP.x + 6.0], [-358.0, -350.0], [300.0, 308.0]]
	var gaps_s := [[294.0, 306.0], [-446.0, -434.0], [-160.0, -152.0], [450.0, 458.0]]
	var gaps_w := [[-70.0, -62.0]]
	var gaps_e := [[30.0, 38.0]]
	_fence_line(g, Vector2(-FENCE_X, FENCE_N), Vector2(FENCE_X, FENCE_N), gaps_n, true)
	_fence_line(g, Vector2(-FENCE_X, FENCE_S), Vector2(FENCE_X, FENCE_S), gaps_s, false)
	_fence_line(g, Vector2(-FENCE_X, FENCE_N), Vector2(-FENCE_X, FENCE_S), gaps_w, false)
	_fence_line(g, Vector2(FENCE_X, FENCE_N), Vector2(FENCE_X, FENCE_S), gaps_e, false)
	# ворота: столбы и шлагбаумы на юге
	for gx in [300.0, -440.0]:
		var by := ground(gx, FENCE_S)
		for s in [-6.3, 6.3]:
			g.box("concrete", Vector3(gx + s, by + 1.5, FENCE_S), Vector3(0.5, 3.0, 0.5))
		g.box(C_WHITE, Vector3(gx - 1.0, by + 1.1, FENCE_S + 1.0), Vector3(10.0, 0.12, 0.12), 0.0, false)
		_sandbags(g, Vector2(gx + 8.0, FENCE_S - 5.0), Vector2(gx + 12.0, FENCE_S - 5.0), by - 0.05)
	g.finish(self, "perimeter")


func _fence_line(g: Geo, a: Vector2, b: Vector2, gaps: Array, concrete: bool) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var yaw := atan2(-dir.y, dir.x)
	var step := 6.0 if concrete else 12.0
	var t := 0.0
	while t < length - 0.01:
		var t1 := minf(t + step, length)
		var open := false
		for gp in gaps:
			var g0: float = gp[0]
			var g1: float = gp[1]
			# зазоры задаются в мировых координатах вдоль линии (x для широтных, z для меридиональных)
			var u0 := (g0 - (a.x if absf(dir.x) > 0.5 else a.y)) * (dir.x if absf(dir.x) > 0.5 else dir.y)
			var u1 := (g1 - (a.x if absf(dir.x) > 0.5 else a.y)) * (dir.x if absf(dir.x) > 0.5 else dir.y)
			if minf(u0, u1) < t1 and maxf(u0, u1) > t:
				open = true
		if not open:
			var p0 := a + dir * t
			var p1 := a + dir * t1
			var by := minf(ground(p0.x, p0.y), ground(p1.x, p1.y)) - 0.08
			if concrete:
				var mid := (p0 + p1) * 0.5
				g.box("concrete", Vector3(mid.x, by + 1.3, mid.y), Vector3(t1 - t - 0.06, 2.6, 0.18), yaw)
				g.box("concrete", Vector3(p0.x, by + 1.45, p0.y), Vector3(0.3, 2.9, 0.3), yaw)
				g.box("plate_dark", Vector3(mid.x, by + 2.75, mid.y), Vector3(t1 - t, 0.04, 0.04), yaw, false)
			else:
				_fence(g, p0, p1, by, 2.4)
				g.box("plate_dark", Vector3((p0.x + p1.x) * 0.5, by + 2.62, (p0.y + p1.y) * 0.5), Vector3(t1 - t, 0.03, 0.03), yaw, false, 0.0, 0.0)
		t = t1


# ------------------------------------------------------------------ зенитная позиция и РЛС
func _build_radar() -> void:
	var g := Geo.new()
	var y: float = pads[1].h
	var c := RADAR
	_block(Rect2(c.x - 34, c.y - 29, 68, 58))
	# зенитные установки в брустверах
	for aa in _aa_spots():
		var p: Vector2 = aa
		var o := (p - c).normalized()
		_aa_gun(g, Vector3(p.x, ground(p.x, p.y), p.y), atan2(-o.x, -o.y))
	# пусковая установка ЗРК на шасси
	var lxf := Transform3D(Basis(Vector3.UP, 0.5), Vector3(c.x + 20.0, y, c.y - 15.0))
	_lbox(g, "green", lxf, Vector3(0, 1.1, 0), Vector3(2.6, 0.8, 9.0))
	_lbox(g, "green", lxf, Vector3(0, 2.1, -3.6), Vector3(2.5, 1.6, 2.2))
	for wz in [-3.6, -1.8, 2.0, 3.6]:
		for wx in [-1.15, 1.15]:
			_lcyl(g, C_DARK, lxf, Vector3(wx, 0.55, wz), SIDE, 0.55, 0.4, 12)
	for tx in [-0.5, 0.5]:
		for ty in [0.0, 0.75]:
			_lcyl(g, "green", lxf, Vector3(tx, 2.6 + ty + 1.0, 1.6), Basis(Vector3.RIGHT, 0.45) * FWD, 0.34, 6.0, 10)
	g.collider("metal", lxf * Transform3D(Basis(), Vector3(0, 2.0, 0)), Vector3(2.8, 4.0, 9.2))
	# командный пункт: контейнер, маскировочная сеть, мешки
	_container(g, c.x - 20.0, c.y + 20.0, 0.1, "container_green", y)
	g.box("canvas", Vector3(c.x - 20.0, y + 3.3, c.y + 22.5), Vector3(10.0, 0.05, 8.0), 0.1, false, 0.12)
	for p2 in [Vector2(-24.5, 26.0), Vector2(-15.5, 26.0)]:
		g.box("wood_dark", Vector3(c.x + p2.x, y + 1.5, c.y + p2.y), Vector3(0.12, 3.0, 0.12))
	_sandbags(g, Vector2(c.x - 26.0, c.y + 14.0), Vector2(c.x - 14.0, c.y + 14.0), y)
	_sandbags(g, Vector2(c.x + 6.0, c.y - 8.0), Vector2(c.x + 10.0, c.y - 8.0), y)
	_sandbags(g, Vector2(c.x - 8.0, c.y + 9.0), Vector2(c.x - 4.0, c.y + 9.0), y)
	_drums(g, c.x + 14.0, c.y + 18.0, 4, y)
	_crate(g, c.x + 10.0, c.y + 22.0, 1.2, 0.2, y)
	_crate(g, c.x + 11.4, c.y + 22.2, 1.0, 0.5, y)
	_prop("portable_generator", Vector3(c.x - 6.0, y, c.y + 4.0), 0.8, "box", "metal")
	_ammo_crate(c.x - 12.0, c.y + 17.0, y, 0.4)
	for b in [[c.x + 2.0, c.y - 24.0, 0.0], [c.x - 10.0, c.y - 22.0, 0.3]]:
		_barrier(g, b[0], b[1], b[2], y)
	g.finish(self, "radar_site")
	# --- цель: машина РЛС (кузов с аппаратурой) и вращающаяся антенна
	var rg := Geo.new()
	var rxf := Transform3D(Basis(), Vector3(c.x, y, c.y))
	_lbox(rg, "green", rxf, Vector3(0, 1.1, 0), Vector3(2.5, 0.8, 9.0))
	_lbox(rg, "green", rxf, Vector3(0, 2.1, -3.6), Vector3(2.5, 1.6, 2.2))
	_lbox(rg, C_GLASS, rxf, Vector3(0, 2.45, -4.72), Vector3(2.3, 0.6, 0.05))
	_lbox(rg, "green", rxf, Vector3(0, 2.7, 1.3), Vector3(2.5, 2.4, 5.4))
	_lbox(rg, "plate_dark", rxf, Vector3(0, 2.4, 4.02), Vector3(0.9, 1.9, 0.05))
	for wz in [-3.6, -1.8, 2.0, 3.6]:
		for wx in [-1.15, 1.15]:
			_lcyl(rg, C_DARK, rxf, Vector3(wx, 0.55, wz), SIDE, 0.55, 0.4, 12)
	_lcyl(rg, "plate_dark", rxf, Vector3(0, 5.6, 1.6), Basis(), 0.2, 3.5, 8)
	rg.collider("metal", rxf * Transform3D(Basis(), Vector3(0, 1.9, 0)), Vector3(2.6, 3.6, 9.2))
	var rmi := rg.finish(self, "radar_target")
	radar_rot = Node3D.new()
	radar_rot.name = "radar_antenna"
	radar_rot.position = Vector3(c.x, y + 7.35, c.y + 1.6)
	add_child(radar_rot)
	var ag := Geo.new()
	ag.cast_shadows = false
	var axf := Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 1.2, 0.2))
	_lbox(ag, "plate", axf, Vector3.ZERO, Vector3(7.0, 2.2, 0.15))
	for k in 6:
		_lbox(ag, "plate_dark", axf, Vector3(-3.0 + k * 1.2, 0, 0.12), Vector3(0.08, 2.2, 0.1))
	_lbox(ag, "plate_dark", Transform3D(), Vector3(0, 0.3, 0), Vector3(1.0, 0.5, 1.0))
	_lbox(ag, "plate_dark", Transform3D(), Vector3(0, 0.9, -0.6), Vector3(0.1, 0.1, 1.6), false, Basis(Vector3.RIGHT, 0.6))
	var ami := ag.finish(radar_rot, "antenna")
	_burn["radar"] = [rmi, ami]
	objectives["radar"] = Vector3(c.x, y + 1.3, c.y + 5.2)
	blast_fx["radar"] = {"fires": [[Vector3(0, 1.5, -3.5), 1.6], [Vector3(0, 0.3, 0.5), 1.2]], "blasts": [[0.7, Vector3(0, 3.0, -4.0)]]}


## Спаренная зенитная установка: тумба, люлька, два ствола под углом.
func _aa_gun(g: Geo, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	_lcyl(g, "rust", xf, Vector3(0, 0.25, 0), Basis(), 1.0, 0.5, 12, true)
	_lbox(g, "green", xf, Vector3(0, 0.9, 0), Vector3(1.6, 0.9, 1.6), true)
	_lbox(g, "green", xf, Vector3(0, 1.65, 0.1), Vector3(1.2, 0.7, 1.5))
	for s in [-0.35, 0.35]:
		var e := 0.6
		var dir := Vector3(0, sin(e), -cos(e))
		_lcyl(g, C_DARK, xf, Vector3(s, 1.8, -0.2) + dir * 2.0, Basis(Vector3.RIGHT, e) * FWD, 0.07, 4.0, 6)
		_lcyl(g, "green", xf, Vector3(s, 1.8, -0.2) + dir * 0.5, Basis(Vector3.RIGHT, e) * FWD, 0.14, 1.0, 8)
	for s in [-0.9, 0.9]:
		_lbox(g, "plate_dark", xf, Vector3(s, 1.3, 0.6), Vector3(0.4, 0.08, 0.4))
	_lbox(g, "wood", xf, Vector3(2.2, 0.35, 1.2), Vector3(1.0, 0.7, 0.6), true)
	cover_points.append(xf * Vector3(0, 0, 2.2))


# ------------------------------------------------------------------ деревня
func _build_village() -> void:
	var g := Geo.new()
	var street := [Vector2(-430, 225), Vector2(-405, 275), Vector2(-370, 315), Vector2(-320, 350), Vector2(-280, 375)]
	var mats := [["wood", "iron"], ["plaster", "rust"], ["wood", "rust"], ["plaster_tan", "iron"], ["wood_dark", "iron"]]
	var k := 0
	for i in street.size() - 1:
		var a: Vector2 = street[i]
		var b: Vector2 = street[i + 1]
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var length := a.distance_to(b)
		var t := 14.0
		while t < length - 8.0:
			for side: float in [-1.0, 1.0]:
				if (k + int(side > 0.0)) % 5 == 4:
					continue
				var c := a + dir * t + nrm * side * rng.randf_range(16.0, 19.0)
				var to_street := -nrm * side
				var yaw := atan2(to_street.x, to_street.y)
				var w := rng.randf_range(7.0, 9.0)
				var d := rng.randf_range(6.0, 7.5)
				var m: Array = mats[k % mats.size()]
				if k == 3:
					_bld(g, "ruin", c.x, c.y, yaw + PI)
				else:
					var kinds := ["house_fence", "house2", "house", "shop", "house_fence"]
					_bld(g, kinds[k % 5], c.x, c.y, yaw)
					if k == 1:
						var ap := _lw(c.x, c.y, yaw, -w * 0.3, -d * 0.2)
						_ammo_crate(ap.x, ap.y, ground(ap.x, ap.y) + 0.45, yaw)
				# палисадник вдоль улицы с калиткой
				var fa := c + to_street * (d * 0.5 + 5.0) - dir * 7.0
				var fb := c + to_street * (d * 0.5 + 5.0) + dir * 7.0
				_wood_fence(g, fa, fa.lerp(fb, 0.42))
				_wood_fence(g, fa.lerp(fb, 0.58), fb)
				# сарай за домом
				if k % 2 == 0:
					var sc := c - to_street * (d * 0.5 + 6.0) + dir * rng.randf_range(-3.0, 3.0)
					_bld(g, "shed", sc.x, sc.y, yaw)
				k += 1
			t += rng.randf_range(26.0, 32.0)
	# колодец у перекрёстка
	var wp := Vector2(-397.0, 300.0)
	var wy := ground(wp.x, wp.y)
	g.cyl("concrete", Transform3D(Basis(), Vector3(wp.x, wy + 0.4, wp.y)), 0.75, 0.8, 12, true)
	for s in [-0.7, 0.7]:
		g.box("wood_dark", Vector3(wp.x + s, wy + 1.2, wp.y), Vector3(0.1, 1.8, 0.1), 0.0, false)
	g.box("rust", Vector3(wp.x, wy + 2.2, wp.y), Vector3(1.8, 0.06, 1.4), 0.0, false, 0.0, 0.3)
	g.finish(self, "village")


## Деревенский дом: цоколь по рельефу, стены с окнами и дверью к улице, двускатная крыша, труба.
func _house(g: Geo, c: Vector2, yaw: float, w: float, d: float, wall: String, roof: String, h := 2.8, rise := 1.7) -> float:
	var corners := [_lw(c.x, c.y, yaw, -w * 0.5, -d * 0.5), _lw(c.x, c.y, yaw, w * 0.5, -d * 0.5),
		_lw(c.x, c.y, yaw, w * 0.5, d * 0.5), _lw(c.x, c.y, yaw, -w * 0.5, d * 0.5)]
	var hi := ground(c.x, c.y)
	var lo := hi
	for q in corners:
		var p: Vector2 = q
		hi = maxf(hi, ground(p.x, p.y))
		lo = minf(lo, ground(p.x, p.y))
	var by := hi + 0.3
	g.box("concrete", Vector3(c.x, (lo - 0.3 + by) * 0.5, c.y), Vector3(w + 0.3, by - lo + 0.3, d + 0.3), yaw)
	_block(Rect2(c.x - maxf(w, d) * 0.7, c.y - maxf(w, d) * 0.7, maxf(w, d) * 1.4, maxf(w, d) * 1.4))
	var p00: Vector2 = corners[0]
	var p10: Vector2 = corners[1]
	var p11: Vector2 = corners[2]
	var p01: Vector2 = corners[3]
	var big := w > 5.0
	var front := [win(0.8), door(w * 0.5 - 0.6, 1.2), win(w - 2.1)] if big else [door(w * 0.5 - 0.6, 1.2)]
	var back := [win(w * 0.5 - 0.65)] if big else []
	var sides := [win(d * 0.5 - 0.65)] if big else []
	g.wall(wall, Vector3(p01.x, by, p01.y), Vector3(p11.x, by, p11.y), h, 0.22, front)
	g.wall(wall, Vector3(p00.x, by, p00.y), Vector3(p10.x, by, p10.y), h, 0.22, back)
	g.wall(wall, Vector3(p00.x, by, p00.y), Vector3(p01.x, by, p01.y), h, 0.22, sides)
	g.wall(wall, Vector3(p10.x, by, p10.y), Vector3(p11.x, by, p11.y), h, 0.22, sides)
	_frames(g, Vector3(p01.x, by, p01.y), Vector3(p11.x, by, p11.y), front, 0.22, "wood_dark")
	_frames(g, Vector3(p00.x, by, p00.y), Vector3(p10.x, by, p10.y), back, 0.22, "wood_dark")
	# крыльцо, если пол высоко над землёй у двери
	var dp := _lw(c.x, c.y, yaw, 0.0, d * 0.5 + 0.6)
	var step := by - ground(dp.x, dp.y)
	if step > 0.35:
		g.stairs("wood", Vector3(dp.x, by - step, dp.y) + Basis(Vector3.UP, yaw) * Vector3(0, 0, step * 1.4 - 0.3), yaw, 1.4, step, step * 1.4)
	# двускатная крыша (конёк вдоль ширины)
	var ang := atan2(rise, d * 0.5)
	var sl := sqrt(rise * rise + d * d * 0.25) + 0.45
	for s in [-1.0, 1.0]:
		var rc := _lw(c.x, c.y, yaw, 0.0, s * d * 0.25)
		g.box(roof, Vector3(rc.x, by + h + rise * 0.5 + 0.08, rc.y), Vector3(w + 0.6, 0.1, sl), yaw, true, s * ang)
	var st := g._st(wall)
	for s in [-1.0, 1.0]:
		var ea := _lw(c.x, c.y, yaw, s * w * 0.5, -d * 0.5)
		var eb := _lw(c.x, c.y, yaw, s * w * 0.5, d * 0.5)
		var ec := _lw(c.x, c.y, yaw, s * w * 0.5, 0.0)
		var nv := Basis(Vector3.UP, yaw) * Vector3(s, 0, 0)
		var va := Vector3(ea.x, by + h, ea.y)
		var vb := Vector3(eb.x, by + h, eb.y)
		var vc := Vector3(ec.x, by + h + rise, ec.y)
		Geo.tri(st, va, vb, vc, nv, 1.0)
		Geo.tri(st, va, vb, vc, -nv, 1.0)
	if big:
		var ch := _lw(c.x, c.y, yaw, w * 0.25, -d * 0.15)
		g.box("concrete", Vector3(ch.x, by + h + rise * 0.8, ch.y), Vector3(0.6, 1.8, 0.6), yaw, false)
		g.box("wood_dark", Vector3(c.x, by + 0.75, c.y), Vector3(1.6, 0.06, 0.9), yaw, false)
	for q in corners:
		var p2: Vector2 = q
		var o := (p2 - c).normalized() * 1.1
		cover_points.append(Vector3(p2.x + o.x, ground(p2.x + o.x, p2.y + o.y), p2.y + o.y))
	return by


## Дощатый забор 1.2 м (простреливается).
func _wood_fence(g: Geo, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var dir := (b - a) / length
	var yaw := atan2(-dir.y, dir.x)
	var segs := maxi(1, int(ceil(length / 3.0)))
	for i in segs:
		var p0 := a + dir * (length * i / segs)
		var p1 := a + dir * (length * (i + 1) / segs)
		var mid := (p0 + p1) * 0.5
		var by := minf(ground(p0.x, p0.y), ground(p1.x, p1.y)) - 0.1
		g.box("wood_dark", Vector3(mid.x, by + 0.65, mid.y), Vector3(length / segs, 1.2, 0.06), yaw)
		g.box("wood_dark", Vector3(p0.x, by + 0.7, p0.y), Vector3(0.1, 1.4, 0.1), yaw, false)


# ------------------------------------------------------------------ эвакуация
func _build_lz() -> void:
	var y: float = pads[2].h
	objectives["lz"] = Vector3(LZ.x, y, LZ.y)
	var g := Geo.new()
	for a in 4:
		var ang := a * PI * 0.5 + 0.4
		g.box(C_WHITE, Vector3(LZ.x + cos(ang) * 6.0, y + 0.03, LZ.y + sin(ang) * 6.0), Vector3(2.4, 0.04, 0.5), -ang, false)
	_crate(g, LZ.x - 8.0, LZ.y + 5.0, 1.2, 0.2, y)
	_crate(g, LZ.x + 7.0, LZ.y - 7.0, 1.3, 0.6, y)
	_sandbags(g, Vector2(LZ.x + 4.0, LZ.y + 9.0), Vector2(LZ.x + 9.0, LZ.y + 9.0), y)
	_ammo_crate(LZ.x - 6.0, LZ.y - 6.0, y, 0.8)
	g.finish(self, "lz")


# ------------------------------------------------------------------ укрытия в поле
## Лётное поле открыто — на траве между полосами и у забора стоят гнёзда/блоки/ящики (вручную),
## на подходах снаружи — случайные укрытия (свой ГСЧ). Один меш на все.
func _build_field_cover() -> void:
	var saved := rng.state
	rng.seed = 92611
	var g := Geo.new()
	var y := H0
	var inside := [[-380.0, 96.0, 0], [-200.0, 96.0, 1], [-40.0, 95.0, 3], [120.0, 96.0, 4], [260.0, 95.0, 0], [420.0, 96.0, 1],
		[-320.0, 20.0, 1], [-60.0, 18.0, 0], [80.0, 24.0, 4], [300.0, 20.0, 1], [-490.0, -120.0, 3], [495.0, -112.0, 0]]
	for s in inside:
		var x: float = s[0]
		var z: float = s[1]
		var yaw := PI if z > RWY_Z else 0.0
		match int(s[2]):
			0:
				_nest(g, x, z, yaw)
			1:
				for k2 in 3:
					_barrier(g, x - 3.2 + k2 * 3.2, z + rng.randf_range(-0.6, 0.6), rng.randf_range(-0.25, 0.25), y)
			3:
				_wreck(g, x, z, rng.randf() * TAU)
			4:
				_field_crates(g, x, z, yaw)
		_cover_spots.append(Vector3(x, z, 6.0))
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 600:
		tries += 1
		var x2 := rng.randf_range(-660.0, 660.0)
		var z2 := rng.randf_range(-380.0, 320.0)
		var dx := maxf(absf(x2) - FENCE_X, 0.0)
		var dz := maxf(maxf(FENCE_N - z2, z2 - FENCE_S), 0.0)
		var dout := sqrt(dx * dx + dz * dz)
		if dout < 25.0 or dout > 170.0 or road_dist(x2, z2) < 9.0 or absf(z2 - _river_z(x2)) < 18.0:
			continue
		if not _cover_ok(x2, z2, 30.0, 6.0):
			continue
		var span := maxf(absf(ground(x2 + 3.5, z2) - ground(x2 - 3.5, z2)), absf(ground(x2, z2 + 3.5) - ground(x2, z2 - 3.5)))
		if span > 0.7:
			continue
		var bad := false
		for cs in _cover_spots:
			if Vector2(x2, z2).distance_to(Vector2(cs.x, cs.y)) < 45.0:
				bad = true
		if bad:
			continue
		# «лицом» к аэродрому
		var yaw2 := atan2(x2 - clampf(x2, -FENCE_X, FENCE_X), z2 - clampf(z2, FENCE_N, FENCE_S))
		match placed % 4:
			0:
				_nest(g, x2, z2, yaw2)
			1:
				_ruin(g, x2, z2, yaw2)
			2:
				_wreck(g, x2, z2, yaw2 + rng.randf_range(-0.9, 0.9))
			3:
				for k3 in 3:
					var p := _lw(x2, z2, yaw2, -3.2 + k3 * 3.2, rng.randf_range(-0.8, 0.8))
					_barrier(g, p.x, p.y, yaw2 + rng.randf_range(-0.25, 0.25), ground(p.x, p.y) - 0.05)
		_cover_spots.append(Vector3(x2, z2, 7.5))
		placed += 1
	g.finish(self, "field_cover")
	field_cover_count = inside.size() + placed
	rng.state = saved


# ------------------------------------------------------------------ природа
func _mask_at(x: float, z: float) -> int:
	if _mask.is_empty():
		return 0
	var ix := clampi(int(round((x + size * 0.5) / cell)), 0, n)
	var iz := clampi(int(round((z + size * 0.5) / cell)), 0, n)
	return _mask[iz * (n + 1) + ix]


func _build_mask() -> void:
	var w := n + 1
	var half := size * 0.5
	_mask.resize(w * w)
	_mask.fill(0)
	var rects: Array = [[Rect2(-FENCE_X, FENCE_N, FENCE_X * 2.0, FENCE_S - FENCE_N), 1]]
	for b in _blocked:
		rects.append([b, 2])
	for i in range(1, pads.size()):
		var p: Dictionary = pads[i]
		var c: Vector2 = p.c
		var hf: Vector2 = p.half
		rects.append([Rect2(c - hf - Vector2(4, 4), hf * 2.0 + Vector2(8, 8)), 2])
	for rv in rects:
		var r: Rect2 = rv[0]
		var v: int = rv[1]
		var x0 := maxi(0, int(floor((r.position.x + half) / cell)))
		var x1 := mini(n, int(ceil((r.end.x + half) / cell)))
		var z0 := maxi(0, int(floor((r.position.y + half) / cell)))
		var z1 := mini(n, int(ceil((r.end.y + half) / cell)))
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				var k := iz * w + ix
				if v > _mask[k]:
					_mask[k] = v


func _hash01(x: float, z: float) -> float:
	var s := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return s - floorf(s)


## Быстрая проверка места под растительность (вызывается сотни тысяч раз из _scatter_mm):
## маска покрытий/построек, дороги, укрытия. Кусты — по плотности (опушки, берега, деревня).
func _free_spot(x: float, z: float, margin := 2.0) -> bool:
	if absf(x) > size * 0.5 - 4.0 or absf(z) > size * 0.5 - 4.0:
		return false
	var cls := _mask_at(x, z)
	if cls == 2:
		return false
	if road_dist(x, z) <= 4.5:
		return false
	for cs in _cover_spots:
		if absf(x - cs.x) < cs.z + margin and absf(z - cs.y) < cs.z + margin:
			return false
	if margin >= 1.4:
		if cls == 1:
			return false
		var f := _forest(x, z)
		var dens := 0.05 + 0.6 * (1.0 - absf(f - 0.45) * 2.2) + 0.5 * (1.0 - smoothstep(14.0, 30.0, absf(z - _river_z(x))))
		return _hash01(x, z) < dens
	return true


func _build_nature() -> void:
	_build_mask()
	_scatter_mm(_cross_mesh(0.95, 0.62), Mats.foliage("grass"), 150, 0.7, 1.5, 85.0, 1, 0.5)
	_scatter_mm(_cross_mesh(0.95, 0.62), Mats.foliage("grass"), 170, 0.6, 1.3, 55.0, 2, 0.5)
	_scatter_mm(_cross_mesh(1.7, 1.4, 3), Mats.foliage("shrub"), 14, 0.7, 1.5, 240.0, 0, 1.5)
	var saved: int = rng.state
	rng.seed = 777
	_scatter_mm(_cross_mesh(0.6, 0.38), Mats.foliage("grass"), 80, 0.6, 1.1, 38.0, 0, 0.5)
	var peb_mat := (Mats.get_mat("rock") as BaseMaterial3D).duplicate() as BaseMaterial3D
	peb_mat.uv1_scale = Vector3(1, 1, 1)
	peb_mat.normal_enabled = false
	_scatter_mm(_pebble_mesh(), peb_mat, 110, 0.05, 0.16, 30.0, 0, 0.3)
	rng.state = saved
	_build_rocks()
	_build_pines()
	_build_broadleaf()


## Валуны: на склонах, в русле и на кряже; склеены кусками по 315 м (крупные/мелкие отдельно).
func _build_rocks() -> void:
	var rock_mat := (Mats.get_mat("rock") as BaseMaterial3D).duplicate() as BaseMaterial3D
	rock_mat.uv1_scale = Vector3(1, 1, 1)
	Mats._normal_mats.append(rock_mat)
	var rocks := [_rock_mesh(1), _rock_mesh(2), _rock_mesh(3)]
	var rbody := StaticBody3D.new()
	rbody.collision_layer = Game.L_WORLD
	rbody.collision_mask = 0
	rbody.set_meta("surf", "concrete")
	add_child(rbody)
	var chunks := {}
	var placed := 0
	var tries := 0
	var cs := chunk * cell
	while placed < 900 and tries < 16000:
		tries += 1
		var x := rng.randf_range(-size * 0.5 + 10.0, size * 0.5 - 10.0)
		var z := rng.randf_range(-size * 0.5 + 10.0, size * 0.5 - 10.0)
		if _mask_at(x, z) != 0 or road_dist(x, z) < 6.0:
			continue
		var slope := maxf(absf(ground(x + 3.0, z) - ground(x - 3.0, z)), absf(ground(x, z + 3.0) - ground(x, z - 3.0))) / 6.0
		var bed := 1.0 - smoothstep(6.0, 20.0, absf(z - _river_z(x)))
		var want := 0.08 + smoothstep(0.15, 0.5, slope) * 0.8 + bed * 0.6 + _forest(x, z) * 0.15
		if rng.randf() > want:
			continue
		var bad := false
		for sp in site_points:
			if Vector2(x, z).distance_to(Vector2(sp.x, sp.y)) < sp.z * 0.6:
				bad = true
		for cv in _cover_spots:
			if Vector2(x, z).distance_to(Vector2(cv.x, cv.y)) < cv.z + 3.0:
				bad = true
		if bad:
			continue
		var s := rng.randf_range(0.35, 1.0) if rng.randf() < 0.6 else rng.randf_range(1.2, 2.8)
		if not road_clear(x, z, s * 0.8):
			continue
		var rmesh: ArrayMesh = rocks[rng.randi() % 3]
		var rpos := Vector3(x, ground(x, z) + s * 0.12, z)
		var rrot := Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		var rsc := Vector3(s, s * rng.randf_range(0.7, 1.1), s * rng.randf_range(0.8, 1.2))
		var key := [Vector2i(int(floor((x + size * 0.5) / cs)), int(floor((z + size * 0.5) / cs))), s > 0.9]
		if not chunks.has(key):
			var st0 := SurfaceTool.new()
			st0.begin(Mesh.PRIMITIVE_TRIANGLES)
			chunks[key] = st0
		(chunks[key] as SurfaceTool).append_from(rmesh, 0, Transform3D(Basis.from_euler(rrot) * Basis.from_scale(rsc), rpos))
		if s > 0.9 and absf(x) < play_half + 5.0 and absf(z) < play_half + 5.0:
			var shp := CollisionShape3D.new()
			var sp2 := SphereShape3D.new()
			sp2.radius = s * 0.78
			shp.shape = sp2
			shp.position = rpos - Vector3(0, s * 0.1, 0)
			rbody.add_child(shp)
			if s > 1.3:
				for a in 4:
					cover(x + cos(a * PI * 0.5) * (s + 0.7), z + sin(a * PI * 0.5) * (s + 0.7))
		placed += 1
	for key3 in chunks:
		var rmi := MeshInstance3D.new()
		rmi.mesh = (chunks[key3] as SurfaceTool).commit()
		rmi.material_override = rock_mat
		if not key3[1]:
			rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rmi)
		veg_ranges.append([rmi, 420.0 if key3[1] else 200.0])


## Ель: ствол и два конуса хвои одним мешем (цвет вершин: ствол бурый, низ кроны темнее) — один вызов на кусок леса.
func _pine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# [y низа, y верха, радиус низа, радиус верха, сегменты, цвет низа, цвет верха]
	var parts := [[0.0, 2.2, 0.24, 0.16, 5, Color(0.42, 0.3, 0.22), Color(0.42, 0.3, 0.22)],
		[1.4, 7.2, 2.4, 0.0, 7, Color(0.62, 0.62, 0.6), Color(1.0, 1.0, 0.95)],
		[4.6, 10.2, 1.65, 0.0, 7, Color(0.75, 0.75, 0.72), Color(1.08, 1.08, 1.0)]]
	for prt in parts:
		var y0: float = prt[0]
		var y1: float = prt[1]
		var r0: float = prt[2]
		var r1: float = prt[3]
		var sg: int = prt[4]
		var c0: Color = prt[5]
		var c1: Color = prt[6]
		var slope := (r0 - r1) / (y1 - y0)
		for i in sg:
			var a0 := TAU * i / sg
			var a1 := TAU * (i + 1) / sg
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var n0 := (d0 + Vector3(0, slope, 0)).normalized()
			var n1 := (d1 + Vector3(0, slope, 0)).normalized()
			var nm := ((d0 + d1) * 0.5 + Vector3(0, slope, 0)).normalized()
			var b0 := d0 * r0 + Vector3(0, y0, 0)
			var b1 := d1 * r0 + Vector3(0, y0, 0)
			var t0 := d0 * r1 + Vector3(0, y1, 0)
			var t1 := d1 * r1 + Vector3(0, y1, 0)
			var tris := [[b0, n0, c0, Vector2(a0 * 0.6, y0 * 0.4)], [b1, n1, c0, Vector2(a1 * 0.6, y0 * 0.4)], [t1, n1 if r1 > 0.0 else nm, c1, Vector2(a1 * 0.6, y1 * 0.4)],
				[t0, n0 if r1 > 0.0 else nm, c1, Vector2(a0 * 0.6, y1 * 0.4)]]
			var quads := [[0, 1, 2], [0, 2, 3]] if r1 > 0.0 else [[0, 1, 2]]
			for q in quads:
				var va: Array = tris[q[0]]
				var vb: Array = tris[q[1]]
				var vc: Array = tris[q[2]]
				var pa: Vector3 = va[0]
				var pb: Vector3 = vb[0]
				var pc: Vector3 = vc[0]
				var order := [va, vb, vc]
				if (pb - pa).cross(pc - pa).dot(nm) > 0.0:
					order = [va, vc, vb]
				for v in order:
					st.set_normal(v[1])
					st.set_color(v[2])
					st.set_uv(v[3])
					st.add_vertex(v[0])
	return st.commit()


func _build_pines() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/gen/pine.png")
	mat.albedo_color = Color(0.78, 0.86, 0.74)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := _pine_mesh()
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	body.set_meta("surf", "wood")
	add_child(body)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.3
	trunk.height = 4.0
	var cs := chunk * cell
	var groups := {}
	var step := 9.0
	var cnt := int(size / step)
	var total := 0
	for iz in cnt:
		for ix in cnt:
			var x := -size * 0.5 + (ix + 0.5) * step + rng.randf_range(-3.5, 3.5)
			var z := -size * 0.5 + (iz + 0.5) * step + rng.randf_range(-3.5, 3.5)
			if absf(x) > size * 0.5 - 3.0 or absf(z) > size * 0.5 - 3.0:
				continue
			var f := _forest(x, z)
			if f < 0.05:
				continue
			# рощи и просеки: низкочастотный шум режет ковёр на пятна, внутри пятна — густо, между — просветы
			var cl := noise_b.get_noise_2d(x * 0.8 + 123.0, z * 0.8 - 57.0)
			var clump := smoothstep(0.0, 0.3, cl)
			if rng.randf() > f * (0.1 + 0.75 * clump):
				continue
			if _mask_at(x, z) != 0 or road_dist(x, z) < 7.0:
				continue
			var bad := false
			for sp in site_points:
				if Vector2(x, z).distance_to(Vector2(sp.x, sp.y)) < sp.z * 0.7:
					bad = true
			for cv in _cover_spots:
				if absf(x - cv.x) < cv.z + 4.0 and absf(z - cv.y) < cv.z + 4.0:
					bad = true
			if bad:
				continue
			var s := rng.randf_range(0.75, 1.45)
			var gy := ground(x, z)
			var key := Vector2i(int(floor((x + size * 0.5) / cs)), int(floor((z + size * 0.5) / cs)))
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s)), Vector3(x, gy - 0.15, z)))
			total += 1
			if absf(x) < play_half + 3.0 and absf(z) < play_half + 3.0:
				var shp := CollisionShape3D.new()
				shp.shape = trunk
				shp.position = Vector3(x, gy + 2.0, z)
				body.add_child(shp)
				if total % 3 == 0:
					cover(x + 0.9, z)
	for key in groups:
		var xfs: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.name = "pines"
		add_child(mmi)
		veg_ranges.append([mmi, 520.0])
	print("ели: ", total)


## Лиственные деревья: сады в деревне, берега русла, рощи в долине.
func _build_broadleaf() -> void:
	var tg := Geo.new()
	var crown := _cross_mesh(4.6, 3.2, 3)
	var crowns: Array = []
	var tries := 0
	var count := 0
	while count < 320 and tries < 9000:
		tries += 1
		var x := rng.randf_range(-size * 0.5 + 15.0, size * 0.5 - 15.0)
		var z := rng.randf_range(-size * 0.5 + 15.0, size * 0.5 - 15.0)
		var want := 0.0
		var dv := Vector2(x, z).distance_to(VILLAGE)
		want = maxf(want, (1.0 - smoothstep(60.0, 110.0, dv)) * 0.5)
		var dr := absf(z - _river_z(x))
		want = maxf(want, (smoothstep(12.0, 16.0, dr) - smoothstep(26.0, 40.0, dr)) * 0.25)
		want = maxf(want, smoothstep(0.3, 0.5, noise_a.get_noise_2d(x * 2.4 - 700.0, z * 2.4 + 300.0)) * 0.3 * (1.0 - _forest(x, z)))
		if rng.randf() > want:
			continue
		if _mask_at(x, z) != 0 or road_dist(x, z) < 6.0:
			continue
		var bad := false
		for cv in _cover_spots:
			if absf(x - cv.x) < cv.z + 4.0 and absf(z - cv.y) < cv.z + 4.0:
				bad = true
		if bad:
			continue
		var gy := ground(x, z)
		var th := rng.randf_range(2.6, 4.2)
		tg.cyl("bark", Transform3D(Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08)), Vector3(x, gy + th * 0.5 - 0.1, z)), 0.2, th, 8, true, false, 0.12)
		var c2 := rng.randf_range(0.8, 1.3)
		crowns.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(c2, c2, c2)), Vector3(x, gy + th - 0.9, z)))
		crowns.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(c2 * 0.7, c2 * 0.75, c2 * 0.7)), Vector3(x + 0.3, gy + th + 0.5, z - 0.2)))
		cover(x + 0.8, z)
		count += 1
	tg.finish(self, "trees")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = crown
	mm.instance_count = crowns.size()
	for i in crowns.size():
		mm.set_instance_transform(i, crowns[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Mats.foliage("foliage")
	add_child(mmi)
	veg_ranges.append([mmi, 900.0])


# ------------------------------------------------------------------ задачи
func mission_objectives() -> Array:
	return [
		{"id": "jets", "title": "Подорвать штурмовики на перроне", "pos": objectives.jets, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "radar", "title": "Уничтожить РЛС зенитной позиции", "pos": objectives.radar, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "fuel", "title": "Подорвать склад ГСМ (резервуары на востоке)", "pos": objectives.fuel, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "intel", "title": "Забрать полётные документы на КДП", "pos": objectives.intel, "done": false, "prompt": "Забрать документы", "hold": 1.2, "armed": false},
		{"id": "lz", "title": "Выйти к точке эвакуации в лесу", "pos": objectives.lz, "done": false, "locked": true, "prompt": "", "hold": 0.0, "armed": false},
	]


func briefing() -> String:
	return "Аэродром «Северный» прикрывает зенитная позиция на южном плато. Вы выходите к нему с края долины.\n\n" \
		+ "• Подорвать три штурмовика на перроне\n• Уничтожить РЛС зенитной позиции за руслом\n" \
		+ "• Подорвать резервуары склада ГСМ в восточной части базы\n• Забрать полётные документы в кабине КДП (лестница снаружи башни)\n• Выйти к точке эвакуации на лесной поляне на севере"


func _process(delta: float) -> void:
	if radar_rot and radar_alive:
		radar_rot.rotate_y(delta * 1.1)


func destroy_objective(key: String) -> void:
	var burnt := Mats.flat(Color(0.05, 0.045, 0.04), 0.95)
	if key == "radar":
		radar_alive = false
		radar_rot.rotation = Vector3(0.7, radar_rot.rotation.y, 0.4)
		radar_rot.position.y -= 2.5
	elif key == "intel":
		intel_node.visible = false
	for nd in _burn.get(key, []):
		(nd as GeometryInstance3D).material_override = burnt


## Точки обзора для замера и скриншотов.
func bench_views() -> Array:
	return [
		["ВПП с запада", Vector3(-530, 0, 75), Vector3(0, 2, 62)],
		["перрон, штурмовики", Vector3(-10, 0, -10), Vector3(40, 2, -55)],
		["ангары", Vector3(-10, 0, -95), Vector3(-90, 6, -150)],
		["КДП вблизи", Vector3(110, 0, -105), Vector3(83, 9, -140)],
		["с кряжа на аэродром", Vector3(-60, 0, -470), Vector3(60, 0, -60)],
		["склад ГСМ и штаб", Vector3(300, 0, -95), Vector3(380, 3, -160)],
		["РЛС на плато", Vector3(280, 0, 250), Vector3(330, 5, 322)],
		["деревня", Vector3(-440, 0, 240), Vector3(-360, 2, 330)],
		["с юга на долину", Vector3(40, 0, 470), Vector3(0, 20, -300)],
		["штаб полка и общежитие", Vector3(-20, 0, -140), Vector3(0, 4, -185)],
		["гаражи и склад", Vector3(-370, 0, -135), Vector3(-370, 3, -170)],
		["КПП", Vector3(150, 0, -200), Vector3(150, 2, -235)],
	]


# ------------------------------------------------------------------ здания (Bld)
## Ставит здание Bld на землю, регистрирует точки укрытий для ИИ, площадь — в блокировки растительности.
func _bld(g: Geo, kind: String, x: float, z: float, yaw: float, base_y := -1000.0) -> Dictionary:
	var out := {}
	var gy := ground(x, z) if base_y < -999.0 else base_y
	var info: Dictionary = Bld.build(kind, g, rng, Vector3(x, gy, z), yaw, out)
	var ext := maxf(float(info.get("w", 8.0)), float(info.get("d", 8.0))) * 0.5 + 2.0
	_block(Rect2(x - ext, z - ext, ext * 2.0, ext * 2.0))
	for cp in out.get("cover", []):
		cover_points.append(cp)
	return info


## Служебный район на Bld: штаб полка, общежитие, гаражи, склады, сараи, руины — один Geo.
func _build_bld_district() -> void:
	var g := Geo.new()
	var y := H0
	_bld(g, "hq", 20.0, -182.0, 0.0, y)
	_bld(g, "block", -60.0, -188.0, 0.0, y)
	_bld(g, "garages", -350.0, -170.0, 0.0, y)
	_bld(g, "garages", -420.0, -170.0, 0.0, y)
	_bld(g, "warehouse", 305.0, -168.0, 0.0, y)
	_bld(g, "warehouse", -140.0, -190.0, 0.0, y)
	_bld(g, "shed", 330.0, -118.0, PI * 0.5, y)
	_bld(g, "shed", -380.0, -190.0, 0.0, y)
	_bld(g, "shed", 120.0, -190.0, 0.0, y)
	# руины на подступах: разбитые корпуса за забором и на склоне
	for rp in [[-480.0, 200.0, 0.5], [120.0, 190.0, 3.4], [-620.0, -120.0, 1.2], [620.0, -60.0, -1.6], [220.0, 350.0, 2.2]]:
		_bld(g, "ruin", rp[0], rp[1], rp[2])
	g.finish(self, "bld_district")


# ------------------------------------------------------------------ машины
## Стоянки и патрули (сами машины ставит Level.spawn_vehicles). Индексы дорог — по порядку roads в _setup_pads:
## 0 долинная, 1 КПП, 2 кольцо внутри забора, 3 к перрону, 4 к складу ГСМ, 5 к РЛС, 6 к деревне, 7 запад, 8 лесная, 9 к поляне.
func _define_vehicles() -> void:
	var r := RADAR
	var v := VILLAGE
	vehicle_spots = [
		# КПП и плац
		[Vector3(KPP.x - 14.0, 0, KPP.y + 22.0), 1.57, "mil"], [Vector3(HQ.x + 22.0, 0, HQ.y + 36.0), 0.0, "mil"],
		[Vector3(190, 0, -128), 1.57, "mil"], [Vector3(250, 0, -128), 1.57, "mil"],
		# автопарк и ангары
		[Vector3(-240, 0, -150), 0.0, "mil"], [Vector3(-200, 0, -150), 0.0, "mil"], [Vector3(-160, 0, -150), 3.1, "any"],
		[Vector3(-110, 0, -115), 1.57, "mil"], [Vector3(-20, 0, -118), 1.57, "mil"],
		# перрон и КДП
		[Vector3(100, 0, -112), 0.0, "mil"], [Vector3(125, 0, -78), 1.57, "mil"], [Vector3(-60, 0, -30), 0.3, "mil"],
		# склад ГСМ: у обвалования
		[Vector3(330, 0, -150), 1.57, "mil"], [Vector3(440, 0, -140), 0.0, "mil"], [Vector3(405, 0, -203), 1.57, "mil"],
		# ворота и плато РЛС
		[Vector3(304, 0, 150), 0.0, "mil"], [Vector3(-436, 0, 150), 0.0, "mil"],
		[Vector3(r.x - 40.0, 0, r.y + 12.0), 1.2, "mil"], [Vector3(r.x + 30.0, 0, r.y + 30.0), 3.0, "mil"],
		# деревня: гражданские на улице и во дворах
		[Vector3(v.x - 40.0, 0, v.y - 12.0), 0.9, "civ"], [Vector3(v.x + 10.0, 0, v.y + 22.0), -1.5, "civ"],
		[Vector3(v.x + 40.0, 0, v.y + 12.0), 0.6, "civ"], [Vector3(v.x - 10.0, 0, v.y - 40.0), 0.0, "any"],
		# брошенные на долинной дороге и в лесу
		[Vector3(-300, 0, -258), 1.57, "civ"], [Vector3(250, 0, -262), 1.5, "civ"], [Vector3(-120, 0, -330), 0.3, "any"],
		[Vector3(-250, 0, -443), 1.57, "any"],
	]
	vehicle_patrols = [[2, 2], [2, 3], [0, 2], [6, 2]]
	if "--novehicles" in OS.get_cmdline_user_args():
		vehicle_spots = []
		vehicle_patrols = []


# ------------------------------------------------------------------ противники
func _define_enemies() -> void:
	var y := H0
	# перрон: штурмовики (цель), транспортник, вертолёт
	_e(31.0, -40.0, 180)
	_e(49.0, -38.0, 160)
	_e(40.0, -70.0, 0, 1)
	_e(12.0, -56.0, 90)
	_e(0.0, -28.0, 90, 0, [[0.0, -28.0], [92.0, -28.0], [92.0, -92.0], [0.0, -92.0]])
	_e(150.0, -45.0, 180)
	_e(-106.0, -48.0, 135)
	_e(-160.0, -110.0, 90, 0, [[-160.0, -110.0], [-160.0, -26.0], [-60.0, -26.0], [-60.0, -110.0]])
	# ангары
	_e(-142.0, -130.0, 160)
	_e(-80.0, -128.0, 180, 1)
	_e(-70.0, -160.0, 200)
	_e(-30.0, -142.0, 180)
	_e(-55.0, -150.0, 90)
	# КДП: кабина (снайпер), площадка лестницы, у основания
	_e(TOWER.x - 1.0, TOWER.y + 2.0, 180, 2, [], y + 10.55, true)
	_e(TOWER.x + 5.6, TOWER.y - 0.5, 90, 0, [], y + 3.55, true)
	_e(70.0, -131.0, 180)
	_e(95.0, -126.0, 150)
	# штаб, плац, казармы, столовая
	_e(150.0, -160.0, 180)
	_e(144.0, -168.0, 180)
	_e(156.0, -172.0, 180, 1, [], y + 3.25, true)
	_e(150.0, -140.0, 180, 1)
	_e(205.0, -143.0, 180)
	_e(225.0, -193.0, 0)
	_e(265.0, -160.0, 180)
	# склад ГСМ
	_e(400.0, -182.0, 0)
	_e(380.0, -150.0, 180)
	_e(335.0, -115.0, 90, 0, [[335.0, -115.0], [430.0, -115.0], [430.0, -212.0], [335.0, -212.0]])
	# штаб полка, общежитие, гаражи, склады
	_e(20.0, -170.0, 0)
	_e(8.0, -190.0, 180, 1)
	_e(-60.0, -176.0, 0)
	_e(-350.0, -158.0, 0)
	_e(305.0, -152.0, 0, 1)
	_e(-140.0, -178.0, 0)
	_e(-70.0, -150.0, 90, 0, [[-70.0, -150.0], [30.0, -150.0], [30.0, -170.0], [-70.0, -170.0]])
	# КПП
	_e(KPP.x - 4.0, KPP.y - 10.0, 0)
	_e(KPP.x + 8.0, KPP.y - 9.0, 20, 1)
	_e(KPP.x + 12.0, KPP.y + 6.0, 0)
	# автопарк, водокачка
	_e(-250.0, -164.0, 180)
	_e(-200.0, -164.0, 180)
	_e(-300.0, -180.0, 0)
	# капониры
	_e(-400.0, -40.0, 180)
	_e(-350.0, -40.0, 180, 1)
	_e(-292.0, -54.0, 180)
	_e(-420.0, -30.0, 90, 0, [[-420.0, -30.0], [-230.0, -30.0]])
	# вышки по углам (снайперы)
	_e(-540.0, -215.0, 135, 2, [], y + 5.0, true)
	_e(540.0, -215.0, -135, 2, [], y + 5.0, true)
	_e(-540.0, 115.0, 45, 2, [], y + 5.0, true)
	_e(540.0, 115.0, -45, 2, [], y + 5.0, true)
	# патрули по кольцевой дороге
	var ring := [[-520.0, -205.0], [520.0, -205.0], [520.0, 110.0], [-520.0, 110.0]]
	_e(-520.0, -205.0, 90, 0, ring)
	_e(520.0, 110.0, -90, 1, ring)
	# ворота
	_e(296.0, 140.0, 180)
	_e(306.0, 126.0, 160)
	_e(-436.0, 140.0, 180)
	# зенитная позиция с РЛС
	var c := RADAR
	_e(c.x - 8.0, c.y - 10.0, 180)
	_e(c.x + 10.0, c.y - 10.0, 200, 1)
	_e(c.x - 25.0, c.y - 5.0, 180)
	_e(c.x + 24.0, c.y + 6.0, 160)
	_e(c.x - 14.0, c.y + 24.0, 180)
	_e(c.x, c.y + 50.0, 180, 2)
	_e(c.x - 38.0, c.y - 34.0, 90, 0, [[c.x - 38.0, c.y - 34.0], [c.x + 38.0, c.y - 34.0], [c.x + 38.0, c.y + 33.0], [c.x - 38.0, c.y + 33.0]])
	# деревня
	_e(-398.0, 284.0, 180)
	_e(-372.0, 322.0, 135)
	_e(-326.0, 356.0, 180, 1)
	_e(-430.0, 230.0, 0, 0, [[-430.0, 230.0], [-405.0, 275.0], [-370.0, 315.0], [-320.0, 350.0], [-280.0, 375.0]])
	# поляна эвакуации и лес на кряже
	_e(LZ.x + 15.0, LZ.y + 15.0, 200)
	_e(LZ.x - 18.0, LZ.y - 12.0, 160, 1)
	_e(-125.0, -300.0, 0, 0, [[-125.0, -300.0], [-110.0, -420.0], [-40.0, -480.0], [-110.0, -420.0]])
	_e(-240.0, -470.0, 160, 2)
	# пулемётное гнездо у долинной дороги на востоке
	_e(600.0, -283.0, 225)
	_e(606.0, -276.0, 235, 1)
