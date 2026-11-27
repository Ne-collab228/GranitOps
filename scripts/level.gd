class_name Level
extends Node3D
## Базовая карта: рельеф (большие карты — куски с двумя LOD, запечённый кэш TerrainData, дальние горы),
## окружение, помощники построек, растительность, навигация кусками, точки появления.
## Конкретные карты — наследники (scripts/map_*.gd), список — Level.MAPS.

signal progress(text: String)

const H0 := 2.0
# направление НА солнце (вычислено по HDRI) — см. tools/sun.gd
const SUN_DIR := Vector3(-0.377, 0.741, 0.556)
## Расстояние до дорог в кэше обрезается сверху (дальше никому не нужно).
const ROAD_MAX := 30.0
## Навигация кусками: ширина полосы соседей при запекании (края кусков совпадают и сшиваются).
const NAV_BORDER := 4.0
## Карты: [скрипт, название, подпись (необязательно)]. Индекс — Settings.data.map.
const MAPS := [
	["res://scripts/map_valley.gd", "Долина «Гранит»", "1,2 км, опорная база и деревни, 6 целей"],
	["res://scripts/map_airfield.gd", "Аэродром «Северный»", "1,4 км, взлётка и зенитная позиция, 5 целей"],
	["res://scripts/map_pass.gd", "Перевал «Седло»", "1,2 км, серпантин, мост и застава, 4 цели"],
]

var rng := RandomNumberGenerator.new()
var noise_a := FastNoiseLite.new()
var noise_b := FastNoiseLite.new()
var pads: Array = []
var roads: Array = []
var hgrid := PackedFloat32Array()
var tdata: TerrainData
var cover_points := PackedVector3Array()
## Опорные точки укрытий в поле: (x, z, радиус) — растительность и камни их обходят.
var _cover_spots: Array[Vector3] = []
var field_cover_count := 0
var cover_claims := {}
var enemy_spawns: Array = []
var objectives := {}
var ammo_points: Array = []
var spawn_point := Vector3.ZERO
var env: Environment
var sun: DirectionalLight3D
var nav_ready := false
var veg_nodes: Array = []
## [узел, базовая дальность видимости] — дальность умножается на настройку «draw»
var veg_ranges: Array = []
var terrain_mat: ShaderMaterial
var intel_node: Node3D
var _scenes := {}
var _aabbs := {}
var _props_root: Node3D

# --- рельеф (задаётся в _configure карты)
## Сторона подробной сетки рельефа, м; сетка n x n ячеек по cell м, куски по chunk ячеек (дальний LOD — шаг far_step()).
var size := 420.0
var cell := 3.0
var n := 140
var chunk := 70
## Граница игровой зоны (невидимая стена), полуширина.
var play_half := 190.0
## Дальние горы низкой детализации до этой полуширины (0 — нет, тогда старое кольцо-задник).
var outer_half := 0.0
var outer_cell := 21.0
## С какого расстояния кусок рельефа рисуется упрощённым (ячейка 2x).
var lod_dist := 230.0
## Поднять при правке рельефа, которую не ловит автоматический ключ кэша (terrain_key).
var terrain_ver := "1"
var map_key := "valley"
var map_seed := 20261111

# --- параметры карты (переопределяются в картах-наследниках)
var title := "Долина «Гранит»"
var sky_file := ""
var sun_dir := SUN_DIR
var orbit_center := Vector3(0, 5, -9)
var orbit_radius := 118.0
var orbit_height := 34.0
var backdrop_color := Color(0.5, 0.45, 0.37)
var nav_aabb := AABB(Vector3(-150, -20, -172), Vector3(292, 90, 310))
## Места, у которых нельзя ставить случайные укрытия и появляться (цели, посты): Vector3(x, z, радиус).
var site_points: Array[Vector3] = []
## Дополнительные эффекты подрыва целей: id -> {"fires": [[смещение, размер]], "blasts": [[задержка, смещение]]}
var blast_fx := {}
var _fence_shapes: Array = []
var _burn := {}


## Название и подпись карты для меню (подпись берётся из третьего элемента MAPS, если он есть).
static func map_info(id: int) -> Dictionary:
	var m: Array = MAPS[clampi(id, 0, MAPS.size() - 1)]
	return {"name": str(m[1]), "sub": str(m[2]) if m.size() > 2 else ""}


static func create(id: int) -> Level:
	var s: Script = load(MAPS[clampi(id, 0, MAPS.size() - 1)][0])
	return s.new() as Level


func _ready() -> void:
	Settings.changed.connect(apply_quality)


## Параметры карты (размер, ключ, небо…). Вызывается первым в build().
func _configure() -> void:
	pass


func _setup_noise() -> void:
	noise_a.seed = 4
	noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_a.frequency = 0.0058
	noise_a.fractal_octaves = 3
	noise_b.seed = 9
	noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_b.frequency = 0.03
	noise_b.fractal_octaves = 2


func build(bake := false) -> void:
	_configure()
	n = int(round(size / cell))
	rng.seed = map_seed
	_setup_noise()
	_props_root = Node3D.new()
	_props_root.name = "props"
	add_child(_props_root)
	Geo.ground_fn = ground

	progress.emit("Рельеф")
	await get_tree().process_frame
	_setup_pads()
	_setup_environment()
	await _build_terrain(bake)
	_build_bounds()
	# враги — до построек: укрытия в поле обходят их посты и маршруты (зависят только от рельефа)
	_define_enemies()
	progress.emit("Постройки")
	await get_tree().process_frame
	# тени районов, крупных камней и ящиков — общими клетками (Geo.shadow_sink), закрывается после природы
	Geo.shadow_sink = {}
	await _build_sites()
	_finish_fences()
	progress.emit("Растительность")
	await get_tree().process_frame
	_build_nature()
	if outer_half <= 0.0:
		_build_backdrop()
	Geo.flush_shadows(self)
	progress.emit("Навигация")
	await get_tree().process_frame
	await _setup_navigation(bake)
	apply_quality()


# ------------------------------------------------------------------ виртуальные методы карт
func _setup_pads() -> void:
	pass


func base_height(x: float, z: float) -> float:
	return noise_a.get_noise_2d(x, z) * 9.0 + 4.0


func _yard_weight(_x: float, _z: float) -> float:
	return 0.0


func _terrain_tex() -> Dictionary:
	return {"a": "sandy_gravel_02", "b": "dry_ground_rocks", "r": "rock_boulder_dry", "grass": Vector3(0.36, 0.36, 0.17), "grass_amt": 0.45}


func _tune_environment() -> void:
	pass


func _build_sites() -> void:
	pass


func _define_enemies() -> void:
	pass


func mission_objectives() -> Array:
	return []


func briefing() -> String:
	return ""


func destroy_objective(_key: String) -> void:
	pass


## Точки обзора для замера/скриншотов (-- --bench [--viewshot]): [[название, откуда (y — над землёй), куда смотреть]].
## Пусто — виды Долины из main.gd.
func bench_views() -> Array:
	return []


## Цвет вершины рельефа: r — второй слой земли, g — скала, b — дорога/двор, a — трава.
func _vertex_color(x: float, z: float, nrm: Vector3, rd: float) -> Color:
	var rock := smoothstep(0.86, 0.66, nrm.y)
	var alt := smoothstep(0.05, 0.5, noise_b.get_noise_2d(x * 0.4 + 300.0, z * 0.4))
	var road := 1.0 - smoothstep(2.2, 5.0, rd)
	return Color(alt, rock, maxf(road, _yard_weight(x, z)), 0.0)


# ------------------------------------------------------------------ рельеф
func height_fn(x: float, z: float) -> float:
	var h := base_height(x, z)
	for p in pads:
		var c: Vector2 = p.c
		var half: Vector2 = p.half
		var dx := maxf(absf(x - c.x) - half.x, 0.0)
		var dz := maxf(absf(z - c.y) - half.y, 0.0)
		var w := 1.0 - smoothstep(0.0, float(p.m), sqrt(dx * dx + dz * dz))
		h = lerpf(h, float(p.h), w)
	return h


func pad_weight(x: float, z: float, extra := 0.0) -> float:
	var best := 0.0
	for p in pads:
		var c: Vector2 = p.c
		var half: Vector2 = p.half
		var dx := maxf(absf(x - c.x) - half.x - extra, 0.0)
		var dz := maxf(absf(z - c.y) - half.y - extra, 0.0)
		best = maxf(best, 1.0 - smoothstep(0.0, 6.0, sqrt(dx * dx + dz * dz)))
	return best


## Расстояние до ближайшей дороги (из кэша — билинейно по сетке; точно — пока кэша нет).
func road_dist(x: float, z: float) -> float:
	if tdata != null and not tdata.road.is_empty():
		return _grid_lerp(tdata.road, x, z)
	return road_dist_exact(x, z)


func road_dist_exact(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := ROAD_MAX
	for r in roads:
		var line: PackedVector2Array = r
		for i in line.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
			best = minf(best, p.distance_to(q))
	return best


func _grid_lerp(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + size * 0.5) / cell, 0.0, n - 0.001)
	var fz := clampf((z + size * 0.5) / cell, 0.0, n - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var w := n + 1
	var a := lerpf(arr[iz * w + ix], arr[iz * w + ix + 1], tx)
	var b := lerpf(arr[(iz + 1) * w + ix], arr[(iz + 1) * w + ix + 1], tx)
	return lerpf(a, b, tz)


## Высота земли в точке — совпадает с треугольниками меша рельефа (LOD 0).
func ground(x: float, z: float) -> float:
	var fx := clampf((x + size * 0.5) / cell, 0.0, n - 0.001)
	var fz := clampf((z + size * 0.5) / cell, 0.0, n - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var w := n + 1
	var h00 := hgrid[iz * w + ix]
	var h10 := hgrid[iz * w + ix + 1]
	var h01 := hgrid[(iz + 1) * w + ix]
	var h11 := hgrid[(iz + 1) * w + ix + 1]
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func gpos(x: float, z: float, lift := 0.0) -> Vector3:
	return Vector3(x, ground(x, z) + lift, z)


## Ключ кэша рельефа: параметры + высоты и цвета в 81 точке + дороги и площадки.
## Любая правка рельефа/дорог/площадок меняет ключ — кэш пересчитается сам.
func terrain_key() -> String:
	var parts := PackedStringArray([map_key, terrain_ver, str(size), str(cell), str(chunk), str(far_step()), "o4", str(outer_half), str(outer_cell), str(roads), str(pads)])
	for iz in 9:
		for ix in 9:
			var x := -size * 0.5 + size * (ix + 0.37) / 9.0
			var z := -size * 0.5 + size * (iz + 0.61) / 9.0
			parts.append("%.3f" % height_fn(x, z))
			parts.append(str(_vertex_color(x, z, Vector3.UP, road_dist_exact(x, z))))
	return str(hash("|".join(parts)))


func _build_terrain(force := false) -> void:
	var key := terrain_key()
	var path := "res://assets/maps/%s_terrain.res" % map_key
	if not force and ResourceLoader.exists(path):
		var td := load(path) as TerrainData
		if td != null and td.ver == key:
			tdata = td
	if tdata == null:
		if not force:
			push_warning("кэш рельефа %s устарел или отсутствует — считаю заново (запустите -- --bake)" % map_key)
		var t0 := Time.get_ticks_msec()
		tdata = await _compute_terrain(key)
		print("рельеф %s посчитан за %d мс" % [map_key, Time.get_ticks_msec() - t0])
		if not Settings.is_mobile:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/maps"))
			ResourceSaver.save(tdata, path, ResourceSaver.FLAG_COMPRESS)
	hgrid = tdata.hgrid
	_make_terrain_mat()
	_instance_terrain()


## Шаг ячеек дальнего LOD: 2 для чётного куска, иначе 3.
func far_step() -> int:
	return 2 if chunk % 2 == 0 else 3


func _make_terrain_mat() -> void:
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://scripts/terrain.gdshader")
	var tt := _terrain_tex()
	terrain_mat.set_shader_parameter("tex_a", load("res://assets/tex/%s_diff.jpg" % tt.a))
	terrain_mat.set_shader_parameter("tex_b", load("res://assets/tex/%s_diff.jpg" % tt.b))
	terrain_mat.set_shader_parameter("tex_r", load("res://assets/tex/%s_diff.jpg" % tt.r))
	terrain_mat.set_shader_parameter("nor_a", load("res://assets/tex/%s_nor.jpg" % tt.a))
	terrain_mat.set_shader_parameter("nor_r", load("res://assets/tex/%s_nor.jpg" % tt.r))
	if tt.has("g"):
		terrain_mat.set_shader_parameter("tex_g", load("res://assets/tex/%s_diff.jpg" % tt.g))
	if tt.has("tint"):
		terrain_mat.set_shader_parameter("tint", tt.tint)
	terrain_mat.set_shader_parameter("macro", load("res://assets/gen/macro_noise.png"))
	for k in ["grass", "grass_amt", "grass_vert", "strata", "rock_dark"]:
		if tt.has(k):
			terrain_mat.set_shader_parameter("grass_col" if k == "grass" else k, tt[k])


func _instance_terrain() -> void:
	var body := StaticBody3D.new()
	body.name = "terrain"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	body.set_meta("surf", "dirt")
	add_child(body)
	for i in tdata.meshes.size():
		for lod in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = tdata.meshes[i] if lod == 0 else tdata.meshes_far[i]
			mi.material_override = terrain_mat
			mi.name = "terrain_%d_%d" % [i, lod]
			# тень от рельефа почти не видна (тени только вблизи), а проход теней стоит дорого
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if lod == 0:
				mi.visibility_range_end = lod_dist
				mi.visibility_range_end_margin = 10.0
			else:
				mi.visibility_range_begin = lod_dist
				mi.visibility_range_begin_margin = 10.0
			add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = tdata.shapes[i]
		body.add_child(cs)
	for m in tdata.outer:
		var omi := MeshInstance3D.new()
		omi.mesh = m
		omi.material_override = terrain_mat
		omi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		omi.name = "terrain_outer"
		add_child(omi)


func _compute_terrain(key: String) -> TerrainData:
	var td := TerrainData.new()
	td.ver = key
	var w := n + 1
	var half := size * 0.5
	hgrid.resize(w * w)
	for iz in w:
		for ix in w:
			hgrid[iz * w + ix] = height_fn(ix * cell - half, iz * cell - half)
		if iz % 40 == 0:
			await get_tree().process_frame
	_flatten_roads()
	td.hgrid = hgrid
	td.road = _compute_road_grid()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	normals.resize(w * w)
	colors.resize(w * w)
	for iz in w:
		for ix in w:
			var hl := hgrid[iz * w + maxi(ix - 1, 0)]
			var hr := hgrid[iz * w + mini(ix + 1, n)]
			var hd := hgrid[maxi(iz - 1, 0) * w + ix]
			var hu := hgrid[mini(iz + 1, n) * w + ix]
			var nrm := Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			normals[iz * w + ix] = nrm
			colors[iz * w + ix] = _vertex_color(ix * cell - half, iz * cell - half, nrm, td.road[iz * w + ix])
		if iz % 40 == 0:
			await get_tree().process_frame
	var chunks := n / chunk
	for cz in chunks:
		for cx in chunks:
			td.meshes.append(_chunk_mesh(cx * chunk, cz * chunk, 1, normals, colors))
			td.meshes_far.append(_chunk_mesh(cx * chunk, cz * chunk, far_step(), normals, colors))
			td.shapes.append(_chunk_shape(cx * chunk, cz * chunk))
		await get_tree().process_frame
	if outer_half > half:
		td.outer = _outer_meshes()
	return td


## Полуширина дорожного полотна, м (дальше — откос до road_half + 7 м).
var road_half := 3.6


## Дороги: полотно ровное поперёк, продольный профиль сглажен (машины не прыгают на кочках),
## по краям — плавный откос/насыпь. Меняет hgrid до построения мешей.
func _flatten_roads() -> void:
	var w := n + 1
	var half := size * 0.5
	var slope := 7.0
	var wgt := PackedFloat32Array()
	var tgt := PackedFloat32Array()
	wgt.resize(w * w)
	tgt.resize(w * w)
	for r in roads:
		var line: PackedVector2Array = r
		var pts := PackedVector2Array()
		for i in line.size() - 1:
			var steps := maxi(1, int(line[i].distance_to(line[i + 1]) / 4.0))
			for k in steps:
				pts.append(line[i].lerp(line[i + 1], float(k) / steps))
		pts.append(line[line.size() - 1])
		var hs := PackedFloat32Array()
		for p in pts:
			hs.append(ground(p.x, p.y))
		# сглаживание окном ±6 точек (±24 м), два прохода
		for _pass in 2:
			var sm := hs.duplicate()
			for i in hs.size():
				var s := 0.0
				var c := 0
				for k in range(maxi(0, i - 6), mini(hs.size(), i + 7)):
					s += hs[k]
					c += 1
				sm[i] = s / c
			hs = sm
		var reach := road_half + slope
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var len2 := maxf(ab.length_squared(), 0.0001)
			var x0 := maxi(0, int(floor((minf(a.x, b.x) - reach + half) / cell)))
			var x1 := mini(n, int(ceil((maxf(a.x, b.x) + reach + half) / cell)))
			var z0 := maxi(0, int(floor((minf(a.y, b.y) - reach + half) / cell)))
			var z1 := mini(n, int(ceil((maxf(a.y, b.y) + reach + half) / cell)))
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var p := Vector2(ix * cell - half, iz * cell - half)
					var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
					var d := p.distance_to(a + ab * t)
					if d > reach:
						continue
					var k2 := 1.0 - smoothstep(road_half, reach, d)
					var gi := iz * w + ix
					if k2 > wgt[gi]:
						wgt[gi] = k2
						tgt[gi] = lerpf(hs[i], hs[i + 1], t)
	for gi in w * w:
		if wgt[gi] > 0.0:
			hgrid[gi] = lerpf(hgrid[gi], tgt[gi], wgt[gi])


## Расстояние до дорог в узлах сетки: каждый отрезок «штампует» свою окрестность.
func _compute_road_grid() -> PackedFloat32Array:
	var w := n + 1
	var half := size * 0.5
	var rg := PackedFloat32Array()
	rg.resize(w * w)
	rg.fill(ROAD_MAX)
	for r in roads:
		var line: PackedVector2Array = r
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var x0 := maxi(0, int(floor((minf(a.x, b.x) - ROAD_MAX + half) / cell)))
			var x1 := mini(n, int(ceil((maxf(a.x, b.x) + ROAD_MAX + half) / cell)))
			var z0 := maxi(0, int(floor((minf(a.y, b.y) - ROAD_MAX + half) / cell)))
			var z1 := mini(n, int(ceil((maxf(a.y, b.y) + ROAD_MAX + half) / cell)))
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var p := Vector2(ix * cell - half, iz * cell - half)
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
					var k := iz * w + ix
					if d < rg[k]:
						rg[k] = d
	return rg


## Кусок рельефа с шагом step ячеек и «юбкой» по краю (закрывает щели между кусками разной детализации).
func _chunk_mesh(x0: int, z0: int, step: int, normals: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var w := n + 1
	var half := size * 0.5
	var cnt := chunk / step
	var cw := cnt + 1
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for jz in cw:
		for jx in cw:
			var gi := (z0 + jz * step) * w + x0 + jx * step
			verts.append(Vector3((x0 + jx * step) * cell - half, hgrid[gi], (z0 + jz * step) * cell - half))
			nrm.append(normals[gi])
			col.append(colors[gi])
	for jz in cnt:
		for jx in cnt:
			var i00 := jz * cw + jx
			var i10 := i00 + 1
			var i01 := i00 + cw
			var i11 := i01 + 1
			idx.append_array([i00, i10, i11, i00, i11, i01])
	# юбка: край опущен на 4 м, обе стороны (порядок обхода не важен)
	var border: Array = []
	for j in cnt:
		border.append([j, j + 1])
		border.append([cnt * cw + j, cnt * cw + j + 1])
		border.append([j * cw, (j + 1) * cw])
		border.append([j * cw + cnt, (j + 1) * cw + cnt])
	for e in border:
		var a: int = e[0]
		var b: int = e[1]
		var base := verts.size()
		verts.append(verts[a] - Vector3(0, 4.0, 0))
		verts.append(verts[b] - Vector3(0, 4.0, 0))
		nrm.append(nrm[a])
		nrm.append(nrm[b])
		col.append(col[a])
		col.append(col[b])
		idx.append_array([a, b, base + 1, a, base + 1, base, a, base + 1, b, a, base, base + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _chunk_shape(x0: int, z0: int) -> ConcavePolygonShape3D:
	var w := n + 1
	var half := size * 0.5
	var faces := PackedVector3Array()
	faces.resize(chunk * chunk * 6)
	var k := 0
	for jz in chunk:
		for jx in chunk:
			var ix := x0 + jx
			var iz := z0 + jz
			var p00 := Vector3(ix * cell - half, hgrid[iz * w + ix], iz * cell - half)
			var p10 := Vector3(p00.x + cell, hgrid[iz * w + ix + 1], p00.z)
			var p01 := Vector3(p00.x, hgrid[(iz + 1) * w + ix], p00.z + cell)
			var p11 := Vector3(p00.x + cell, hgrid[(iz + 1) * w + ix + 1], p00.z + cell)
			faces[k] = p00
			faces[k + 1] = p10
			faces[k + 2] = p11
			faces[k + 3] = p00
			faces[k + 4] = p11
			faces[k + 5] = p01
			k += 6
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


## Дальние горы вокруг подробной сетки: та же функция высоты, ячейка outer_cell, 4 куска по сторонам света.
func _outer_meshes() -> Array[ArrayMesh]:
	var half := size * 0.5
	var cnt := int(round(outer_half * 2.0 / outer_cell))
	var cw := cnt + 1
	var hs := PackedFloat32Array()
	hs.resize(cw * cw)
	for iz in cw:
		for ix in cw:
			hs[iz * cw + ix] = height_fn(ix * outer_cell - outer_half, iz * outer_cell - outer_half)
	var groups := {}
	for iz in cnt:
		for ix in cnt:
			var cx := ix * outer_cell - outer_half + outer_cell * 0.5
			var cz := iz * outer_cell - outer_half + outer_cell * 0.5
			# ячейки внутри подробной сетки пропускаем
			if absf(cx) < half and absf(cz) < half:
				continue
			var gk := int(floor((atan2(cz, cx) + PI) / TAU * 4.0)) % 4
			if not groups.has(gk):
				groups[gk] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
			# Packed-массивы копируются при чтении из Array — копим в локальные и кладём обратно
			var gv: PackedVector3Array = groups[gk][0]
			var gn: PackedVector3Array = groups[gk][1]
			var gc: PackedColorArray = groups[gk][2]
			var quad := [[ix, iz], [ix + 1, iz], [ix + 1, iz + 1], [ix, iz], [ix + 1, iz + 1], [ix, iz + 1]]
			for q in quad:
				var qx: int = q[0]
				var qz: int = q[1]
				var x := qx * outer_cell - outer_half
				var z := qz * outer_cell - outer_half
				var hl := hs[qz * cw + maxi(qx - 1, 0)]
				var hr := hs[qz * cw + mini(qx + 1, cnt)]
				var hd := hs[maxi(qz - 1, 0) * cw + qx]
				var hu := hs[mini(qz + 1, cnt) * cw + qx]
				var nv := Vector3(hl - hr, 2.0 * outer_cell, hd - hu).normalized()
				# на краю подробной сетки опускаем на 1 м: дальняя сетка не вылезает поверх ближней
				var edge := absf(x) <= half + 0.01 and absf(z) <= half + 0.01
				gv.append(Vector3(x, hs[qz * cw + qx] - (1.0 if edge else 0.0), z))
				gn.append(nv)
				gc.append(_vertex_color(x, z, nv, ROAD_MAX))
			groups[gk] = [gv, gn, gc]
	var out: Array[ArrayMesh] = []
	for gk in groups:
		var g: Array = groups[gk]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g[0]
		arrays[Mesh.ARRAY_NORMAL] = g[1]
		arrays[Mesh.ARRAY_COLOR] = g[2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.append(mesh)
	return out


## Невидимая граница игровой зоны (слой забора: люди и машины упираются, пули и взгляд проходят).
func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "bounds"
	body.collision_layer = Game.L_FENCE
	body.collision_mask = 0
	add_child(body)
	var l := play_half * 2.0 + 4.0
	for s in [[Vector3(0, 0, -play_half - 1.0), Vector3(l, 400, 2)], [Vector3(0, 0, play_half + 1.0), Vector3(l, 400, 2)],
			[Vector3(-play_half - 1.0, 0, 0), Vector3(2, 400, l)], [Vector3(play_half + 1.0, 0, 0), Vector3(2, 400, l)]]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = s[1]
		cs.shape = b
		cs.position = s[0]
		body.add_child(cs)


# ------------------------------------------------------------------ окружение
func _setup_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	var hi: bool = int(Settings.data.quality) >= 2 and not Settings.is_mobile
	# sky_4k.hdr исключён из экспорта (APK), поэтому берём 4k только если файл реально доступен (запуск из редактора)
	var sky_path := sky_file if sky_file != "" else "res://assets/sky/sky_2k.hdr"
	if sky_file == "" and hi and ResourceLoader.exists("res://assets/sky/sky_4k.hdr"):
		sky_path = "res://assets/sky/sky_4k.hdr"
	pm.panorama = load(sky_path)
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_256 if hi else Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY if hi else Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.9
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.66, 0.62, 0.56)
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.95
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.69, 0.73, 0.81)
	env.fog_light_energy = 1.0
	# лёгкая дымка: сильный туман «съедал» противников на дальних дистанциях
	env.fog_density = 0.0005
	env.fog_sun_scatter = 0.1
	env.fog_aerial_perspective = 0.12
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.09
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_blend_splits = false
	add_child(sun)
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP)
	_tune_environment()


func apply_quality() -> void:
	if env == null:
		return
	var d: Dictionary = Settings.data
	var sh: int = int(d.shadows)
	sun.shadow_enabled = sh > 0
	sun.directional_shadow_max_distance = Settings.shadow_distance()
	# слоёв теней: низкое — 1, среднее/высокое — 2, ультра — 4 (каждый слой — свой проход отрисовки)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if sh >= 4 else (
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL)
	sun.directional_shadow_blend_splits = sh >= 4
	env.glow_enabled = bool(d.glow)
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = bool(d.ssao) and Settings.is_rd
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	if terrain_mat:
		terrain_mat.set_shader_parameter("use_normal", 1.0 if d.normal_maps else 0.0)
		terrain_mat.set_shader_parameter("use_far", 1.0 if int(d.quality) >= 1 else 0.0)
	Mats.apply_quality()
	var veg: int = int(d.veg)
	for v in veg_nodes:
		var node: GeometryInstance3D = v[0]
		node.visible = veg >= int(v[1])
	var dk: float = float(d.draw) if int(d.quality) >= 2 else float(d.draw) * 0.7
	for v in veg_ranges:
		(v[0] as GeometryInstance3D).visibility_range_end = float(v[1]) * dk
		if v.size() > 2:
			# дальний LOD деревьев: начало совпадает с концом ближнего
			(v[0] as GeometryInstance3D).visibility_range_begin = float(v[2]) * dk
	for c in _props_root.get_children():
		var mis: Array = Mats.mesh_instances(c)
		var sz := 0.0
		for mi in mis:
			sz = maxf(sz, (mi as MeshInstance3D).get_aabb().size.length() * (c as Node3D).scale.x)
		# мелочь (ящики, канистры) не видна уже за 60–80 м, а вызов отрисовки съедает
		var far := clampf(sz * 55.0, 60.0, 170.0) * float(d.draw)
		for mi in mis:
			(mi as MeshInstance3D).visibility_range_end = far
			if sz < 1.2:
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ помощники
func cover(x: float, z: float, y := -1000.0) -> void:
	cover_points.append(Vector3(x, ground(x, z) if y < -999.0 else y, z))


## Пропсы, чья тень заменяется простой формой (Geo.sink_box): модель -> цилиндр (true) или коробка (false).
const PROXY_SHADOW := {"old_military_crate": false, "wooden_crate_01": false, "wooden_crate_02": false,
	"ammo_box": false, "utility_box_01": false, "portable_generator": false, "Barrel_01": true, "Barrel_02": true,
	"barrel_03": true, "propane_tank": true, "metal_jerrycan_green": false}


func _prop(model: String, pos: Vector3, yaw := 0.0, collide := "box", surf := "metal", scale := 1.0) -> Node3D:
	var flat_path := "res://assets/models_flat/%s.res" % model
	if not _scenes.has(model) and ResourceLoader.exists(flat_path):
		# заранее склеенная модель с LOD (tools/flatten_props.gd)
		var fm: ArrayMesh = load(flat_path)
		var holder := MeshInstance3D.new()
		holder.mesh = fm
		Mats.register_scene(holder)
		holder.free()
		_scenes[model] = fm
		_aabbs[model] = fm.get_aabb()
	if not _scenes.has(model):
		# запасной путь: склейка на лету (без LOD) — если модель добавили, а tools/flatten_props.gd не запустили
		push_warning("нет %s — запустите tools/flatten_props.gd" % flat_path)
		var ps: PackedScene = load("res://assets/models/%s/%s.gltf" % [model, model])
		var probe: Node3D = ps.instantiate()
		Mats.register_scene(probe)
		# Модели Poly Haven собраны из частей (ящик с патронами — 5 узлов: корпус, ручка, защёлка, кольца),
		# и каждая часть — отдельный вызов отрисовки. Склеиваем модель в один меш: по поверхности на материал.
		var by_mat := {}
		for mi in Mats.mesh_instances(probe):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var xf := Transform3D()
			var n: Node = m
			while n != probe and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for si in m.mesh.get_surface_count():
				var mat: Material = m.get_surface_override_material(si)
				if mat == null:
					mat = m.mesh.surface_get_material(si)
				if not by_mat.has(mat):
					var st0 := SurfaceTool.new()
					st0.begin(Mesh.PRIMITIVE_TRIANGLES)
					by_mat[mat] = st0
				(by_mat[mat] as SurfaceTool).append_from(m.mesh, si, xf)
		var flat := ArrayMesh.new()
		for mat in by_mat:
			(by_mat[mat] as SurfaceTool).commit(flat)
			flat.surface_set_material(flat.get_surface_count() - 1, mat)
		_scenes[model] = flat
		_aabbs[model] = flat.get_aabb()
		probe.free()
	var node := Node3D.new()
	node.name = model
	var fmi := MeshInstance3D.new()
	fmi.mesh = _scenes[model] as ArrayMesh
	node.add_child(fmi)
	node.position = pos
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale
	_props_root.add_child(node)
	# ящики, бочки, баллоны: тень — коробкой/цилиндром в общих клетках теней, а не своим вызовом в каждом слое
	if PROXY_SHADOW.has(model) and Geo.sink_box(node.global_transform, _aabbs[model], PROXY_SHADOW[model]):
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if collide != "":
		var bb: AABB = _aabbs[model]
		var body := StaticBody3D.new()
		body.collision_layer = Game.L_WORLD
		body.collision_mask = 0
		body.set_meta("surf", surf)
		var cs := CollisionShape3D.new()
		if collide == "cyl":
			var c := CylinderShape3D.new()
			c.radius = maxf(bb.size.x, bb.size.z) * 0.5
			c.height = bb.size.y
			cs.shape = c
		else:
			var b := BoxShape3D.new()
			b.size = bb.size
			cs.shape = b
		cs.position = bb.get_center()
		body.add_child(cs)
		node.add_child(body)
	return node


func _sandbags(g: Geo, a: Vector2, b: Vector2, base_y: float, rows := 4) -> void:
	var d := b - a
	var length := d.length()
	var dir := d / length
	var yaw := atan2(-dir.y, dir.x)
	var count := int(length / 0.62)
	for r in rows:
		var shift := 0.31 if r % 2 == 1 else 0.0
		for i in count:
			var t := (i + 0.5) * 0.62 + shift
			if t > length:
				continue
			var p := a + dir * t
			g.box("sandbag", Vector3(p.x, base_y + 0.095 + r * 0.185, p.y),
				Vector3(0.6, 0.2, 0.34 + rng.randf_range(-0.03, 0.03)), yaw + rng.randf_range(-0.07, 0.07), false)
	var mid := (a + b) * 0.5
	g.collider("dirt", Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, base_y + rows * 0.0925, mid.y)), Vector3(length, rows * 0.185, 0.4))
	var nrm := Vector2(-dir.y, dir.x)
	var steps := maxi(1, int(length / 1.6))
	for i in steps:
		var p2 := a + dir * ((i + 0.5) * length / steps)
		for side in [-0.8, 0.8]:
			cover_points.append(Vector3(p2.x + nrm.x * side, base_y, p2.y + nrm.y * side))


func _barrier(g: Geo, x: float, z: float, yaw: float, base_y: float) -> void:
	var rot := Basis(Vector3.UP, yaw)
	g.box("concrete", Vector3(x, base_y + 0.15, z), Vector3(2.4, 0.3, 0.62), yaw, false)
	g.box("concrete", Vector3(x, base_y + 0.45, z), Vector3(2.4, 0.3, 0.42), yaw, false)
	g.box("concrete", Vector3(x, base_y + 0.75, z), Vector3(2.4, 0.3, 0.24), yaw, false)
	g.collider("concrete", Transform3D(rot, Vector3(x, base_y + 0.45, z)), Vector3(2.4, 0.9, 0.45))
	for side in [-0.75, 0.75]:
		var p := Vector3(x, base_y, z) + rot * Vector3(0, 0, side)
		cover_points.append(p)


func _container(g: Geo, x: float, z: float, yaw: float, mat: String, base_y: float) -> void:
	g.box(mat, Vector3(x, base_y + 1.3, z), Vector3(6.06, 2.6, 2.44), yaw)
	var rot := Basis(Vector3.UP, yaw)
	for c in [Vector3(3.6, 0, 1.0), Vector3(3.6, 0, -1.0), Vector3(-3.6, 0, 1.0), Vector3(-3.6, 0, -1.0), Vector3(0, 0, 1.9), Vector3(0, 0, -1.9)]:
		cover_points.append(Vector3(x, base_y, z) + rot * c)


func _crate(g: Geo, x: float, z: float, size: float, yaw: float, base_y: float) -> void:
	var c := Vector3(x, base_y + size * 0.5, z)
	g.box("wood", c, Vector3(size, size, size), yaw)
	var rot := Basis(Vector3.UP, yaw)
	var e := size * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box_xf("wood_dark", Transform3D(rot, c + rot * Vector3(sx * e, 0, sz * e)), Vector3(0.09, size + 0.02, 0.09), false)
	for sy in [-1.0, 1.0]:
		g.box_xf("wood_dark", Transform3D(rot, c + Vector3(0, sy * (e - 0.04), 0)), Vector3(size + 0.03, 0.08, size + 0.03), false)
	if size > 0.9:
		for o in [Vector3(e + 0.7, 0, 0), Vector3(-e - 0.7, 0, 0), Vector3(0, 0, e + 0.7), Vector3(0, 0, -e - 0.7)]:
			cover_points.append(Vector3(x, base_y, z) + rot * o)


func _barrels(x: float, z: float, count: int, base_y: float) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var r := 0.0 if i == 0 else rng.randf_range(0.6, 1.0) * (0.75 if count < 4 else 1.1)
		var model: String = ["Barrel_01", "Barrel_02", "barrel_03"][rng.randi() % 3]
		_prop(model, Vector3(x + cos(a + i) * r, base_y, z + sin(a + i) * r), rng.randf() * TAU, "cyl", "metal")
	cover(x + 1.4, z, base_y)
	cover(x - 1.4, z, base_y)
	cover(x, z + 1.4, base_y)
	cover(x, z - 1.4, base_y)


## Прямоугольное здание. openings: {"s": [...], "n": [...], "w": [...], "e": [...]} — проёмы [от, до, низ, верх].
func _building(g: Geo, cx: float, cz: float, w: float, d: float, h: float, mat: String, openings: Dictionary,
		base_y := H0, roof_mat := "concrete", thick := 0.3, with_floor := true, with_roof := true) -> void:
	var x0 := cx - w * 0.5
	var x1 := cx + w * 0.5
	var z0 := cz - d * 0.5
	var z1 := cz + d * 0.5
	if with_floor:
		g.box("floor", Vector3(cx, base_y + 0.04, cz), Vector3(w, 0.08, d))
	g.wall(mat, Vector3(x0, base_y, z1), Vector3(x1, base_y, z1), h, thick, openings.get("s", []))
	g.wall(mat, Vector3(x0, base_y, z0), Vector3(x1, base_y, z0), h, thick, openings.get("n", []))
	g.wall(mat, Vector3(x0, base_y, z0), Vector3(x0, base_y, z1), h, thick, openings.get("w", []))
	g.wall(mat, Vector3(x1, base_y, z0), Vector3(x1, base_y, z1), h, thick, openings.get("e", []))
	var trim := "plate_dark" if mat == "iron" else "wood_dark"
	_frames(g, Vector3(x0, base_y, z1), Vector3(x1, base_y, z1), openings.get("s", []), thick, trim)
	_frames(g, Vector3(x0, base_y, z0), Vector3(x1, base_y, z0), openings.get("n", []), thick, trim)
	_frames(g, Vector3(x0, base_y, z0), Vector3(x0, base_y, z1), openings.get("w", []), thick, trim)
	_frames(g, Vector3(x1, base_y, z0), Vector3(x1, base_y, z1), openings.get("e", []), thick, trim)
	if with_roof:
		g.box(roof_mat, Vector3(cx, base_y + h + 0.1, cz), Vector3(w + 0.5, 0.2, d + 0.5))
		if w >= 7.0 and d >= 7.0:
			# надстройки на крыше: вентиляция и труба
			var ry := base_y + h + 0.2
			g.box("plate", Vector3(cx - w * 0.22, ry + 0.35, cz + d * 0.15), Vector3(1.3, 0.7, 0.9), 0.0, false)
			g.box("plate_dark", Vector3(cx - w * 0.22, ry + 0.72, cz + d * 0.15), Vector3(1.0, 0.06, 0.7), 0.0, false)
			g.cyl("rust", Transform3D(Basis(), Vector3(cx + w * 0.3, ry + 0.5, cz - d * 0.2)), 0.14, 1.0, 8, false)
			g.cyl("rust", Transform3D(Basis(), Vector3(cx + w * 0.3, ry + 1.03, cz - d * 0.2)), 0.2, 0.06, 8, false)
	if with_floor:
		for c in [Vector2(x0 - 0.8, z0 - 0.8), Vector2(x1 + 0.8, z0 - 0.8), Vector2(x0 - 0.8, z1 + 0.8), Vector2(x1 + 0.8, z1 + 0.8)]:
			cover_points.append(Vector3(c.x, base_y, c.y))


## Наличники, подоконники и перемычки вокруг проёмов стены (без коллизий).
func _frames(g: Geo, a: Vector3, b: Vector3, openings: Array, thick: float, mat: String) -> void:
	var d := b - a
	var dir := Vector3(d.x, 0, d.z).normalized()
	var yaw := atan2(-dir.z, dir.x)
	for o in openings:
		var t0: float = o[0]
		var t1: float = o[1]
		var y0: float = o[2]
		var y1: float = o[3]
		var mid := a + dir * ((t0 + t1) * 0.5)
		g.box(mat, mid + Vector3(0, y1 + 0.05, 0), Vector3(t1 - t0 + 0.24, 0.1, thick + 0.08), yaw, false)
		for t in [t0, t1]:
			g.box(mat, a + dir * t + Vector3(0, (y0 + y1) * 0.5, 0), Vector3(0.09, y1 - y0, thick + 0.08), yaw, false)
		if y0 > 0.05:
			g.box("concrete", mid + Vector3(0, y0 - 0.03, 0), Vector3(t1 - t0 + 0.3, 0.07, thick + 0.2), yaw, false)


## Сетчатый забор от a до b: пули и взгляд проходят, люди — нет.
func _fence(g: Geo, a: Vector2, b: Vector2, base_y: float, h := 2.3) -> void:
	var d := b - a
	var length := d.length()
	var dir := d / length
	var yaw := atan2(-dir.y, dir.x)
	var mid := (a + b) * 0.5
	g.box("fence", Vector3(mid.x, base_y + h * 0.5, mid.y), Vector3(length, h, 0.02), yaw, false)
	g.box("plate_dark", Vector3(mid.x, base_y + h, mid.y), Vector3(length, 0.05, 0.05), yaw, false)
	var n := maxi(1, int(round(length / 3.0)))
	for i in n + 1:
		var p := a + dir * (length * i / n)
		g.cyl("plate_dark", Transform3D(Basis(), Vector3(p.x, base_y + h * 0.5 + 0.05, p.y)), 0.04, h + 0.1, 6, false)
	var s := BoxShape3D.new()
	s.size = Vector3(length, h, 0.12)
	_fence_shapes.append([s, Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, base_y + h * 0.5, mid.y))])


func _finish_fences() -> void:
	if _fence_shapes.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "fences"
	body.collision_layer = Game.L_FENCE
	body.collision_mask = 0
	body.set_meta("surf", "sheet")
	add_child(body)
	for pair in _fence_shapes:
		var cs := CollisionShape3D.new()
		cs.shape = pair[0]
		cs.transform = pair[1]
		body.add_child(cs)


## Фонарный столб со светящимся плафоном.
func _lamp(g: Geo, x: float, z: float, base_y: float, yaw := 0.0) -> void:
	var rot := Basis(Vector3.UP, yaw)
	g.cyl("plate_dark", Transform3D(Basis(), Vector3(x, base_y + 2.6, z)), 0.07, 5.2, 6, true)
	g.box_xf("plate_dark", Transform3D(rot, Vector3(x, base_y + 5.15, z) + rot * Vector3(0, 0, -0.6)), Vector3(0.08, 0.08, 1.3), false)
	g.box_xf("!ffe2a0", Transform3D(rot, Vector3(x, base_y + 5.08, z) + rot * Vector3(0, 0, -1.1)), Vector3(0.22, 0.07, 0.5), false)


## Ноутбук с разведданными.
func _make_intel(pos: Vector3) -> void:
	intel_node = Node3D.new()
	add_child(intel_node)
	intel_node.position = pos
	var lap := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.36, 0.02, 0.25)
	lap.mesh = lb
	lap.material_override = Mats.flat(Color(0.08, 0.08, 0.09), 0.5, 0.6)
	intel_node.add_child(lap)
	var scr := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.36, 0.24, 0.012)
	scr.mesh = sb
	scr.position = Vector3(0, 0.12, -0.13)
	scr.rotation.x = -0.25
	scr.material_override = Mats.emissive(Color(0.35, 0.7, 0.95), 1.4)
	intel_node.add_child(scr)
	objectives["intel"] = pos


## Армейский ящик, у которого пополняется боезапас.
func _ammo_crate(x: float, z: float, base_y: float, yaw := 0.0) -> void:
	_prop("old_military_crate", Vector3(x, base_y, z), yaw, "box", "wood")
	_prop("ammo_box", Vector3(x - 0.1, base_y + 0.32, z - 0.1), yaw + 0.5, "", "metal", 1.4)
	ammo_points.append(Vector3(x, base_y + 0.42, z))


static func door(t: float, wd := 1.5) -> Array:
	return [t, t + wd, 0.0, 2.15]


static func win(t: float, wd := 1.3) -> Array:
	return [t, t + wd, 1.0, 2.15]


func _tower(g: Geo, x: float, z: float, stairs_from_north: bool, base_y := H0) -> void:
	var top := base_y + 5.0
	for sx in [-1.5, 1.5]:
		for sz in [-1.5, 1.5]:
			g.box("wood_dark", Vector3(x + sx, base_y + 3.7, z + sz), Vector3(0.22, 7.4, 0.22))
	for s in [-1.5, 1.5]:
		g.box("wood_dark", Vector3(x + s, base_y + 2.5, z), Vector3(0.1, 0.16, 4.4), 0.0, false, 0.9)
		g.box("wood_dark", Vector3(x, base_y + 2.5, z + s), Vector3(4.4, 0.16, 0.1), 0.0, false, 0.0, 0.9)
	g.box("wood", Vector3(x, top - 0.08, z), Vector3(3.5, 0.16, 3.5))
	var gap_z := -1.7 if stairs_from_north else 1.7
	for side in [-1.7, 1.7]:
		g.box("wood", Vector3(x + side, top + 0.5, z), Vector3(0.08, 1.0, 3.5))
		if side != gap_z:
			g.box("wood", Vector3(x, top + 0.5, z + side), Vector3(3.5, 1.0, 0.08))
		else:
			g.box("wood", Vector3(x - 1.15, top + 0.5, z + side), Vector3(1.2, 1.0, 0.08))
			g.box("wood", Vector3(x + 1.15, top + 0.5, z + side), Vector3(1.2, 1.0, 0.08))
	g.box("iron", Vector3(x, top + 2.4, z), Vector3(4.2, 0.08, 4.2), 0.0, true, 0.06)
	if stairs_from_north:
		g.stairs("wood", Vector3(x, base_y, z - 1.75 - 7.0), PI, 1.0, 5.0, 7.0)
	else:
		g.stairs("wood", Vector3(x, base_y, z + 1.75 + 7.0), 0.0, 1.0, 5.0, 7.0)


func _truck(g: Geo, x: float, z: float, yaw: float, base_y: float) -> void:
	var rot := Basis(Vector3.UP, yaw)
	var o := Vector3(x, base_y, z)
	var parts := [
		["green", Vector3(0, 0.95, 0), Vector3(2.2, 0.3, 6.6)],
		["green", Vector3(0, 1.95, -2.2), Vector3(2.3, 1.7, 1.9)],
		["green", Vector3(0, 1.5, -3.55), Vector3(2.0, 0.8, 0.9)],
		["wood_dark", Vector3(0, 1.3, 1.1), Vector3(2.4, 0.4, 4.2)],
		["canvas", Vector3(0, 2.35, 1.1), Vector3(2.4, 1.7, 4.2)],
		["plate_dark", Vector3(0, 2.2, -3.17), Vector3(1.9, 0.75, 0.04)],
	]
	for p in parts:
		g.box_xf(p[0], Transform3D(rot, o + rot * p[1]), p[2], false)
	g.collider("metal", Transform3D(rot, o + rot * Vector3(0, 1.7, 0)), Vector3(2.4, 3.0, 6.8))
	for wz in [-2.5, 0.6, 2.1]:
		for wx in [-1.05, 1.05]:
			g.cyl("#1a1a19", Transform3D(rot * Basis(Vector3.FORWARD, PI * 0.5), o + rot * Vector3(wx, 0.52, wz)), 0.52, 0.34, 12, false)
	for c in [Vector3(1.9, 0, 0), Vector3(-1.9, 0, 0), Vector3(0, 0, 4.1), Vector3(0, 0, -4.4)]:
		cover_points.append(o + rot * c)


# ------------------------------------------------------------------ укрытия в поле


## Высота под укрытием одной отметки: минимум по площадке (+0.1) — край не висит над склоном.
func _ground_min(x: float, z: float, r: float) -> float:
	var m := ground(x, z)
	for o in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
		m = minf(m, ground(x + o.x, z + o.y))
	return m + 0.1


## Место под укрытие: не на дороге, не на площадке базы/объекта, внутри области навигации,
## не на посту врага и не на маршруте патруля.
func _cover_ok(x: float, z: float, sites_r: float, enemy_r: float) -> bool:
	var lim := play_half - 8.0
	if absf(x) > lim or absf(z) > lim or road_dist(x, z) < 6.0 or pad_weight(x, z, 6.0) > 0.05:
		return false
	var na := nav_aabb.grow(-8.0)
	if x < na.position.x or x > na.end.x or z < na.position.z or z > na.end.z:
		return false
	for sp0 in site_points:
		if Vector2(x, z).distance_to(Vector2(sp0.x, sp0.y)) < sites_r + sp0.z:
			return false
	for sp in enemy_spawns:
		var pos: Vector3 = sp.pos
		if Vector2(x, z).distance_to(Vector2(pos.x, pos.z)) < enemy_r + 4.0:
			return false
		var pts: PackedVector3Array = sp.route
		for k in pts.size():
			var a := Vector2(pts[k].x, pts[k].z)
			var b := Vector2(pts[(k + 1) % pts.size()].x, pts[(k + 1) % pts.size()].z)
			if Vector2(x, z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(x, z), a, b)) < enemy_r + 4.0:
				return false
	return true


## Локальные координаты укрытия (вправо, назад от базы) → мировые x, z.
func _lw(x: float, z: float, yaw: float, lx: float, lz: float) -> Vector2:
	var b := Basis(Vector3.UP, yaw)
	var v := b * Vector3(lx, 0, lz)
	return Vector2(x + v.x, z + v.z)


## Пулемётное гнездо из мешков: П-образное, открыто назад (от базы).
func _nest(g: Geo, x: float, z: float, yaw: float) -> void:
	var y := _ground_min(x, z, 3.0) - 0.1
	var fl := _lw(x, z, yaw, -2.2, -1.2)
	var fr := _lw(x, z, yaw, 2.2, -1.2)
	var bl := _lw(x, z, yaw, -2.6, 1.4)
	var br := _lw(x, z, yaw, 2.6, 1.4)
	_sandbags(g, fl, fr, y, 5)
	_sandbags(g, fl, bl, y, 4)
	_sandbags(g, fr, br, y, 4)


## Руины: стена 6 м с проломом-окном (подоконник 1 м — стрелять с колена/стоя) и короткая боковая стена.
func _ruin(g: Geo, x: float, z: float, yaw: float) -> void:
	var y := _ground_min(x, z, 3.4) - 0.2
	var t := 0.32
	# куски передней стены: [центр по X, ширина, высота]
	for seg in [[-2.4, 1.6, 2.5 + rng.randf_range(-0.3, 0.2)], [-0.9, 1.4, 1.0], [0.6, 1.6, 2.2 + rng.randf_range(-0.4, 0.3)], [2.2, 1.6, 1.3 + rng.randf_range(0.0, 0.6)]]:
		var c := _lw(x, z, yaw, seg[0], 0.0)
		g.box("concrete", Vector3(c.x, y + float(seg[2]) * 0.5, c.y), Vector3(seg[1], seg[2], t), yaw)
	# перемычка над окном у одного из вариантов
	if rng.randf() < 0.5:
		var c2 := _lw(x, z, yaw, -0.9, 0.0)
		g.box("concrete", Vector3(c2.x, y + 2.25, c2.y), Vector3(1.4, 0.3, t), yaw)
	# боковая стена назад
	var s := _lw(x, z, yaw, -3.2 + t * 0.5, 1.6)
	g.box("concrete", Vector3(s.x, y + 0.75, s.y), Vector3(t, 1.5, 3.2), yaw)
	# обломки у стены
	for k in 4:
		var d := _lw(x, z, yaw, rng.randf_range(-3.0, 3.0), rng.randf_range(-1.6, 1.6))
		var sz := rng.randf_range(0.3, 0.7)
		g.box("concrete", Vector3(d.x, ground(d.x, d.y) + sz * 0.3, d.y), Vector3(sz, sz * 0.6, sz * 0.8), rng.randf() * TAU, false, rng.randf_range(-0.3, 0.3))
	for lx in [-2.4, -0.9, 0.6, 2.2]:
		var cp := _lw(x, z, yaw, lx, 0.9)
		cover_points.append(Vector3(cp.x, ground(cp.x, cp.y), cp.y))


## Сгоревшая машина (без колёс, просела на землю) — крепкое укрытие от пуль.
func _wreck(g: Geo, x: float, z: float, yaw: float) -> void:
	var y := _ground_min(x, z, 2.3) - 0.15
	var tilt := rng.randf_range(-0.06, 0.06)
	g.box("rust", Vector3(x, y + 0.55, z), Vector3(1.9, 0.75, 4.4), yaw, true, tilt, tilt * 0.5)
	var cab := _lw(x, z, yaw, 0.0, 0.3)
	g.box("rust", Vector3(cab.x, y + 1.2, cab.y), Vector3(1.7, 0.6, 2.1), yaw, false, tilt)
	var hood := _lw(x, z, yaw, 0.0, -1.7)
	g.box("rust", Vector3(hood.x, y + 0.98, hood.y), Vector3(1.8, 0.14, 1.0), yaw, false, -0.12)
	for c in [Vector3(1.6, 0, 0), Vector3(-1.6, 0, 0), Vector3(0, 0, 2.9), Vector3(0, 0, -2.9)]:
		var p := _lw(x, z, yaw, c.x, c.z)
		cover_points.append(Vector3(p.x, ground(p.x, p.y), p.y))


## Штабель ящиков в поле (дерево простреливается).
func _field_crates(g: Geo, x: float, z: float, yaw: float) -> void:
	var y := ground(x, z) - 0.05
	for k in 3:
		var sz := rng.randf_range(0.9, 1.2)
		var p := _lw(x, z, yaw, -1.2 + k * 1.15, rng.randf_range(-0.2, 0.2))
		var gy := ground(p.x, p.y) - 0.05
		g.box("wood", Vector3(p.x, gy + sz * 0.5, p.y), Vector3(sz, sz, sz), yaw + rng.randf_range(-0.2, 0.2))
	var top := _lw(x, z, yaw, -0.6, 0.0)
	g.box("wood", Vector3(top.x, y + 1.45, top.y), Vector3(0.9, 0.9, 0.9), yaw + 0.4)
	for o in [Vector2(0, 1.4), Vector2(0, -1.4), Vector2(2.6, 0), Vector2(-2.6, 0)]:
		var cp := _lw(x, z, yaw, o.x, o.y)
		cover_points.append(Vector3(cp.x, ground(cp.x, cp.y), cp.y))


# ------------------------------------------------------------------ база


# ------------------------------------------------------------------ блокпост


# ------------------------------------------------------------------ РЛС


# ------------------------------------------------------------------ природа
func _free_spot(x: float, z: float, margin := 2.0) -> bool:
	if absf(x) > size * 0.5 - 4.0 or absf(z) > size * 0.5 - 4.0:
		return false
	for cs in _cover_spots:
		if Vector2(x, z).distance_to(Vector2(cs.x, cs.y)) < cs.z + margin:
			return false
	if pad_weight(x, z, margin) > 0.05:
		return false
	return road_dist(x, z) > 4.5


func _cross_mesh(w: float, h: float, planes := 2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in planes:
		var a := PI * i / planes
		var d := Vector3(cos(a), 0, sin(a)) * (w * 0.5)
		var pts := [-d, d, d + Vector3(0, h, 0), -d + Vector3(0, h, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])
	return st.commit()


func _scatter_mm(mesh: Mesh, mat: Material, per_chunk: int, smin: float, smax: float, vis_end: float, min_veg: int, margin: float) -> void:
	# куски ~60 м: дальние отсекаются по дальности видимости; плотность на м² как на старой карте 420 м
	var chunks := maxi(7, int(round(size / 60.0)))
	var cs := size / chunks
	per_chunk = int(round(per_chunk * cs * cs / 3600.0))
	for cz in chunks:
		for cx in chunks:
			var xfs: Array = []
			for i in per_chunk:
				var x := -size * 0.5 + (cx + rng.randf()) * cs
				var z := -size * 0.5 + (cz + rng.randf()) * cs
				if not _free_spot(x, z, margin):
					continue
				var s := rng.randf_range(smin, smax)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
				xfs.append(Transform3D(b, Vector3(x, ground(x, z) - 0.03, z)))
			if xfs.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 8.0
			add_child(mmi)
			veg_nodes.append([mmi, min_veg])
			veg_ranges.append([mmi, vis_end])


## Галька: грубая сфера, сплюснутая и помятая шумом (~40 треугольников).
func _pebble_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		verts[i] = Vector3(v.x * (1.0 + 0.25 * sin(v.z * 5.0)), v.y * 0.55, v.z * (1.0 + 0.2 * cos(v.x * 4.0)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	st.generate_normals()
	return st.commit()


func _rock_mesh(seed_v: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 7
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.frequency = 0.9
	for i in verts.size():
		var v := verts[i]
		var dir := v.normalized()
		var k := 1.0 + nz.get_noise_3dv(dir * 1.3) * 0.55 + nz.get_noise_3dv(dir * 4.0) * 0.12
		verts[i] = Vector3(dir.x * k, dir.y * k * 0.72, dir.z * k)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_uv(uvs[i] * 2.0)
		st.set_smooth_group(0)
		st.add_vertex(verts[i])
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _build_nature() -> void:
	_build_veg_ground()
	# мелкие детали у ног на всех пресетах (своё зерно — не сбивает расстановку камней/деревьев/укрытий):
	# редкие сухие пучки травы и галька в радиусе ~35 м
	var saved: int = rng.state
	rng.seed = 777
	_scatter_mm(_cross_mesh(0.6, 0.38), Mats.foliage("grass"), 80, 0.6, 1.1, 38.0, 0, 0.5)
	var peb_mat := (Mats.get_mat("rock") as BaseMaterial3D).duplicate() as BaseMaterial3D
	peb_mat.uv1_scale = Vector3(1, 1, 1)
	peb_mat.normal_enabled = false
	_scatter_mm(_pebble_mesh(), peb_mat, 110, 0.05, 0.16, 30.0, 0, 0.3)
	rng.state = saved

	var rock_mat := (Mats.get_mat("rock") as BaseMaterial3D).duplicate() as BaseMaterial3D
	rock_mat.uv1_scale = Vector3(1, 1, 1)
	Mats._normal_mats.append(rock_mat)
	var rocks := [_rock_mesh(1), _rock_mesh(2), _rock_mesh(3)]
	var rbody := StaticBody3D.new()
	rbody.collision_layer = Game.L_WORLD
	rbody.collision_mask = 0
	rbody.set_meta("surf", "concrete")
	add_child(rbody)
	var rock_chunks := {}
	var placed := 0
	var tries := 0
	var area_k := size * size / (420.0 * 420.0)
	while placed < int(120 * area_k) and tries < int(2000 * area_k):
		tries += 1
		var x := rng.randf_range(-size * 0.5 + 10.0, size * 0.5 - 10.0)
		var z := rng.randf_range(-size * 0.5 + 10.0, size * 0.5 - 10.0)
		if not _free_spot(x, z, 3.0):
			continue
		var s := rng.randf_range(0.35, 1.0) if rng.randf() < 0.6 else rng.randf_range(1.2, 2.6)
		var rmesh: ArrayMesh = rocks[rng.randi() % 3]
		var rpos := Vector3(x, ground(x, z) + s * 0.12, z)
		var rrot := Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		var rsc := Vector3(s, s * rng.randf_range(0.7, 1.1), s * rng.randf_range(0.8, 1.2))
		var ck := Vector2i(int(floor((x + size * 0.5) / 105.0)), int(floor((z + size * 0.5) / 105.0)))
		var big := s > 0.9
		var key2 := [ck, big]
		if not rock_chunks.has(key2):
			var st0 := SurfaceTool.new()
			st0.begin(Mesh.PRIMITIVE_TRIANGLES)
			rock_chunks[key2] = st0
		(rock_chunks[key2] as SurfaceTool).append_from(rmesh, 0, Transform3D(Basis.from_euler(rrot) * Basis.from_scale(rsc), rpos))
		if s > 0.9:
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = s * 0.78
			cs.shape = sp
			cs.position = rpos - Vector3(0, s * 0.1, 0)
			rbody.add_child(cs)
			if s > 1.3:
				for a in 4:
					cover(x + cos(a * PI * 0.5) * (s + 0.7), z + sin(a * PI * 0.5) * (s + 0.7))
		placed += 1
	for key3 in rock_chunks:
		var rmi := MeshInstance3D.new()
		rmi.mesh = (rock_chunks[key3] as SurfaceTool).commit()
		rmi.material_override = rock_mat
		# мелкие камни: без тени и ближе граница видимости; тени крупных — в общих клетках теней
		if not key3[1] or Geo.sink_mesh(rmi.mesh):
			rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rmi)
		veg_ranges.append([rmi, 360.0 if key3[1] else 200.0])

	_build_veg_trees()


func _build_backdrop() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 72
	var rings := [[250.0, -12.0, 0.0], [330.0, 34.0, 26.0], [620.0, 70.0, 70.0], [1500.0, -20.0, 0.0]]
	var pts: Array = []
	for r in rings:
		var row: Array = []
		for i in segs:
			var a := TAU * i / segs
			var hgt: float = r[1] + (noise_a.get_noise_2d(cos(a) * 900.0 + r[0], sin(a) * 900.0) * 0.5 + 0.5) * r[2]
			row.append(Vector3(cos(a) * r[0], hgt, sin(a) * r[0]))
		pts.append(row)
	for ri in rings.size() - 1:
		for i in segs:
			var j := (i + 1) % segs
			var a0: Vector3 = pts[ri][i]
			var b0: Vector3 = pts[ri][j]
			var c0: Vector3 = pts[ri + 1][j]
			var d0: Vector3 = pts[ri + 1][i]
			for v in [a0, c0, b0, a0, d0, c0]:
				st.set_smooth_group(0)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = backdrop_color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ растительность Veg (карточки, MultiMesh)
## Состав деревьев карты: вид -> вес. Карта может переопределить в _configure.
var tree_mix := {"broadleaf": 0.34, "searsia": 0.3, "fir": 0.24, "dead": 0.12}
## Доля площади под рощами (0..1) и плотность деревьев (1 — шаг сетки 8 м).
var grove_share := 0.3
var tree_density := 0.8
## Выше этой отметки деревья не растут (граница леса).
var tree_max_h := 40.0
var veg_cell_grass := 22.0
var veg_cell_tree := 45.0


func _veg_noise(seed_add: int, freq: float) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.seed = map_seed + seed_add
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = freq
	nz.fractal_octaves = 2
	return nz


func _veg_tint(r: RandomNumberGenerator, amp: float) -> Color:
	var k := 1.0 + r.randf_range(-amp, amp)
	return Veg.inst_color(Color(k, k * r.randf_range(0.97, 1.03), k * r.randf_range(0.95, 1.03)), 0, 1)


func _veg_mm(info: Dictionary, xfs: Array, cols: Array, vis_end: float, vis_begin := 0.0, shadow := false, min_veg := 0) -> void:
	var mmi := Veg.multimesh(info, xfs, cols)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_begin = vis_begin
	mmi.visibility_range_begin_margin = 4.0 if vis_begin > 0.0 else 0.0
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_end_margin = 4.0
	add_child(mmi)
	veg_nodes.append([mmi, min_veg])
	if vis_begin > 0.0:
		veg_ranges.append([mmi, vis_end, vis_begin])
	else:
		veg_ranges.append([mmi, vis_end])


## Трава кусками veg_cell_grass м (дальность 45 м) и кусты кусками veg_cell_tree м. Свой ГСЧ — расстановка остального не меняется.
func _build_veg_ground() -> void:
	var vr := RandomNumberGenerator.new()
	vr.seed = map_seed * 7 + 11
	var dry := _veg_noise(101, 0.006)
	var meadow := _veg_noise(102, 0.011)
	var grove := _veg_noise(103, 0.0045)
	var lim := minf(size * 0.5 - 6.0, play_half + 40.0)
	var gi := Veg.grass()
	var cs := veg_cell_grass
	var nc := int(ceil(lim * 2.0 / cs))
	for cz in nc:
		for cx in nc:
			var x0 := -lim + cx * cs
			var z0 := -lim + cz * cs
			var dens := clampf(0.55 + meadow.get_noise_2d(x0 + cs * 0.5, z0 + cs * 0.5) * 1.1, 0.12, 1.0)
			var cnt := int(64.0 * dens)
			var xfs: Array = []
			var cols: Array = []
			for i in cnt:
				var x := x0 + vr.randf() * cs
				var z := z0 + vr.randf() * cs
				if not _free_spot(x, z, 0.6):
					continue
				var dv := dry.get_noise_2d(x, z)
				var variant := 0
				var rv := vr.randf()
				if rv < 0.07:
					variant = 3
				elif dv > 0.18:
					variant = 1 if rv < 0.75 else 2
				elif dv > -0.05:
					variant = 2
				var sc := vr.randf_range(0.75, 1.35)
				var b := Basis(Vector3.UP, vr.randf() * TAU).scaled(Vector3(sc, sc * vr.randf_range(0.8, 1.3), sc))
				xfs.append(Transform3D(b, Vector3(x, ground(x, z) - 0.03, z)))
				var kk := vr.randf_range(0.9, 1.08)
				cols.append(Veg.inst_color(Color(kk, kk, kk), variant))
			if xfs.size() > 3:
				_veg_mm(gi, xfs, cols, float(gi.vis_end), 0.0, false, 1)
	# кусты: куски по 70 м, один вид на кусок (вызовы отрисовки), у рощ чаще, дальность до 90 м
	var kinds: Array = Veg.SHRUBS
	var cs2 := 70.0
	var nc2 := int(ceil(lim * 2.0 / cs2))
	for cz in nc2:
		for cx in nc2:
			var x0 := -lim + cx * cs2
			var z0 := -lim + cz * cs2
			var gn := grove.get_noise_2d(x0 + cs2 * 0.5, z0 + cs2 * 0.5)
			var cnt := int(vr.randf_range(8.0, 16.0) + maxf(gn, 0.0) * 50.0)
			var si := Veg.shrub(String(kinds[vr.randi() % kinds.size()]))
			var xfs: Array = []
			var cols: Array = []
			for i in cnt:
				var x := x0 + vr.randf() * cs2
				var z := z0 + vr.randf() * cs2
				if not _free_spot(x, z, 1.5):
					continue
				var sc := vr.randf_range(0.8, 1.5)
				xfs.append(Transform3D(Basis(Vector3.UP, vr.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(x, ground(x, z) - 0.03, z)))
				cols.append(_veg_tint(vr, 0.1))
			if xfs.size() >= 3:
				_veg_mm(si, xfs, cols, minf(float(si.vis_end), 90.0), 0.0, false, 0)


## Деревья: рощи по шуму и лесополосы вдоль дорог. Два LOD (ближний до ~80 м, дальний до 260 м) на одних и тех же
## преобразованиях, куски veg_cell_tree м, не больше 2 видов на кусок (вызовы отрисовки). Ствол — коллизия, часть стволов — укрытия.
func _build_veg_trees() -> void:
	var vr := RandomNumberGenerator.new()
	vr.seed = map_seed * 13 + 5
	var grove := _veg_noise(103, 0.0045)
	var lim := minf(size * 0.5 - 8.0, play_half + 30.0)
	var cs := veg_cell_tree
	var kinds: Array = tree_mix.keys()
	var wsum := 0.0
	for k in kinds:
		wsum += float(tree_mix[k])
	var chunks := {}
	var spots: Array = []
	var step := 8.0 / sqrt(tree_density)
	var thr := lerpf(0.5, -0.25, grove_share)
	var gx := -lim
	while gx < lim:
		var gz := -lim
		while gz < lim:
			var x := gx + vr.randf() * step
			var z := gz + vr.randf() * step
			var gn := grove.get_noise_2d(x, z)
			if gn > thr and vr.randf() < smoothstep(thr, thr + 0.3, gn) * 0.95:
				spots.append(Vector3(x, z, gn))
			gz += step
		gx += step
	# лесополосы вдоль дорог: ряд деревьев по обе стороны с шагом ~7 м, «включаются» шумом участками
	for r in roads:
		var pts: PackedVector2Array = r
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ln := a.distance_to(b)
			var dir := (b - a) / maxf(ln, 0.01)
			var nrm := Vector2(-dir.y, dir.x)
			var t := 0.0
			while t < ln:
				t += 6.0 + vr.randf() * 3.0
				var c := a + dir * t
				if grove.get_noise_2d(c.x * 2.3 + 500.0, c.y * 2.3) < -0.05:
					continue
				for side in [-1.0, 1.0]:
					if vr.randf() < 0.35:
						continue
					var off: float = side * vr.randf_range(7.5, 11.5)
					spots.append(Vector3(c.x + nrm.x * off, c.y + nrm.y * off, 1.0))
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	body.set_meta("surf", "wood")
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = 0.28
	shape.height = 3.0
	var count := 0
	for sp in spots:
		var x: float = sp.x
		var z: float = sp.y
		if absf(x) > lim or absf(z) > lim or not _free_spot(x, z, 2.5) or road_dist(x, z) < 5.5:
			continue
		var gy := ground(x, z)
		if gy > tree_max_h:
			continue
		if absf(ground(x + 2.0, z) - ground(x - 2.0, z)) > 2.2 or absf(ground(x, z + 2.0) - ground(x, z - 2.0)) > 2.2:
			continue
		# вид — по весам, но в основном общий на кусок: соседние деревья одного вида
		var ck := Vector2i(int(floor((x + lim) / cs)), int(floor((z + lim) / cs)))
		var h := float(absi(hash(ck)) % 1000) / 1000.0
		var rv := vr.randf()
		var kind := String(kinds[0])
		var acc := 0.0
		var pick := (h if rv < 0.7 else rv) * wsum
		for k in kinds:
			acc += float(tree_mix[k])
			if pick <= acc:
				kind = String(k)
				break
		if gy > 22.0 and kind == "broadleaf":
			kind = "searsia"
		var sc := vr.randf_range(0.8, 1.25)
		var xf := Transform3D(Basis(Vector3.UP, vr.randf() * TAU).scaled(Vector3(sc, sc * vr.randf_range(0.9, 1.15), sc)), Vector3(x, gy - 0.1, z))
		if not chunks.has(ck):
			chunks[ck] = {}
		if not (chunks[ck] as Dictionary).has(kind):
			(chunks[ck] as Dictionary)[kind] = []
		((chunks[ck] as Dictionary)[kind] as Array).append(xf)
		var cs3 := CollisionShape3D.new()
		cs3.shape = shape
		cs3.position = Vector3(x, gy + 1.4, z)
		body.add_child(cs3)
		count += 1
		if count % 3 == 0:
			cover(x + 0.7, z)
	for ck in chunks:
		var per: Dictionary = chunks[ck]
		var ks: Array = per.keys()
		# один вид на кусок (вызовы отрисовки): всё — в самый частый
		if ks.size() > 1:
			ks.sort_custom(func(p, q): return (per[p] as Array).size() > (per[q] as Array).size())
			for extra in ks.slice(1):
				(per[ks[0]] as Array).append_array(per[extra])
				per.erase(extra)
			ks = ks.slice(0, 1)
		for kind in ks:
			var xfs: Array = per[kind]
			var cols: Array = []
			for i in xfs.size():
				cols.append(_veg_tint(vr, 0.08))
			var near := Veg.tree(String(kind), 0)
			var far := Veg.tree(String(kind), 1)
			var d_near := minf(float(near.vis_end), 65.0)
			_veg_mm(near, xfs, cols, d_near, 0.0, true, 0)
			_veg_mm(far, xfs, cols, 260.0, d_near, false, 0)


# ------------------------------------------------------------------ противники
func _e(x: float, z: float, yaw_deg: float, kind := 0, route := [], y := -1000.0, hold := false) -> void:
	var pos := Vector3(x, (ground(x, z) if y < -999.0 else y) + 0.05, z)
	var pts := PackedVector3Array()
	for r in route:
		pts.append(Vector3(r[0], ground(r[0], r[1]), r[1]))
	enemy_spawns.append({"pos": pos, "yaw": deg_to_rad(yaw_deg), "kind": kind, "route": pts, "hold": hold})


# ------------------------------------------------------------------ навигация
## Навигация кусками по chunk*cell м (на большой карте одна сетка навигации пеклась бы минутами и не влезла бы
## в память): каждый кусок печётся с полосой соседей NAV_BORDER — края совпадают, сервер их сшивает.
## Куски лежат в res://assets/nav/<карта>/<i>.res, перепекать после ЛЮБОЙ правки геометрии (-- --bake).
var nav_tiles: Array[AABB] = []


func _nav_template() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.2
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 42.0
	nm.region_min_size = 8.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.L_WORLD | Game.L_FENCE
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	return nm


func _setup_navigation(bake: bool) -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.25)
	NavigationServer3D.map_set_cell_height(map, 0.2)
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(map, 0.01)
	var ts := chunk * cell
	nav_tiles.clear()
	var x0 := floorf(nav_aabb.position.x / ts) * ts
	var z0 := floorf(nav_aabb.position.z / ts) * ts
	var x := x0
	while x < nav_aabb.end.x:
		var z := z0
		while z < nav_aabb.end.z:
			var t := AABB(Vector3(x, nav_aabb.position.y, z), Vector3(ts, nav_aabb.size.y, ts)).intersection(nav_aabb)
			if t.size.x > 1.0 and t.size.z > 1.0:
				nav_tiles.append(t)
			z += ts
		x += ts
	var dir := "res://assets/nav/%s" % map_key
	var have := not bake
	if have:
		for i in nav_tiles.size():
			if not ResourceLoader.exists("%s/%d.res" % [dir, i]):
				have = false
				break
	if have:
		for i in nav_tiles.size():
			var region := NavigationRegion3D.new()
			region.navigation_mesh = load("%s/%d.res" % [dir, i])
			add_child(region)
		nav_ready = true
		if "--navtest" in OS.get_cmdline_user_args():
			_nav_selftest()
		return
	if not bake:
		push_warning("нет навигации %s — пеку на лету (запустите -- --bake)" % map_key)
	var nm0 := _nav_template()
	nm0.filter_baking_aabb = nav_aabb.grow(NAV_BORDER)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm0, src, self)
	if bake:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var polys := 0
	for i in nav_tiles.size():
		var nm := _nav_template()
		nm.filter_baking_aabb = nav_tiles[i].grow(NAV_BORDER)
		nm.border_size = NAV_BORDER
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
		nm.filter_baking_aabb = AABB()
		_nav_clean(nm)
		polys += nm.get_polygon_count()
		if bake:
			ResourceSaver.save(nm, "%s/%d.res" % [dir, i], ResourceSaver.FLAG_COMPRESS)
		var region := NavigationRegion3D.new()
		region.navigation_mesh = nm
		add_child(region)
		if i % 4 == 3:
			progress.emit("Навигация %d%%" % (100 * (i + 1) / nav_tiles.size()))
			await get_tree().process_frame
	print("navmesh %s: %d кусков, %d полигонов" % [map_key, nav_tiles.size(), polys])
	nav_ready = true
	if "--navtest" in OS.get_cmdline_user_args():
		_nav_selftest()


## Вершины на сетку (края соседних кусков совпадают точно) и чистка вырожденных полигонов:
## после привязки к сетке Recast-полигоны схлопываются в «шипы» (ребро a-b-a), и сервер навигации
## ругается «More than 2 edges tried to occupy the same map rasterization space».
func _nav_clean(nm: NavigationMesh) -> void:
	var src := nm.vertices
	var verts := PackedVector3Array()
	var index := {}
	var remap := PackedInt32Array()
	remap.resize(src.size())
	for k in src.size():
		var v: Vector3 = src[k].snappedf(0.025)
		var key := Vector3i((v / 0.025).round())
		if not index.has(key):
			index[key] = verts.size()
			verts.append(v)
		remap[k] = index[key]
	var polys: Array[PackedInt32Array] = []
	for p in nm.get_polygon_count():
		var ids: Array[int] = []
		for i in nm.get_polygon(p):
			var id: int = remap[i]
			if ids.is_empty() or ids[ids.size() - 1] != id:
				ids.append(id)
		if ids.size() > 1 and ids[0] == ids[ids.size() - 1]:
			ids.pop_back()
		# убрать шипы: вершина, у которой соседи совпадают
		var changed := true
		while changed and ids.size() >= 3:
			changed = false
			for k in ids.size():
				if ids[(k + ids.size() - 1) % ids.size()] == ids[(k + 1) % ids.size()]:
					ids.remove_at(k)
					changed = true
					break
		if ids.size() < 3:
			continue
		var area := 0.0
		for k in ids.size():
			var a: Vector3 = verts[ids[k]]
			var b: Vector3 = verts[ids[(k + 1) % ids.size()]]
			area += a.x * b.z - b.x * a.z
		if absf(area) < 0.01:
			continue
		polys.append(PackedInt32Array(ids))
	_nav_drop_overlaps(verts, polys)
	nm.clear()
	nm.vertices = verts
	for pl in polys:
		nm.add_polygon(pl)


## Перекрывающиеся полигоны (ребро занято больше чем двумя или двумя в одном направлении): из конфликтующих
## убираем самый мелкий — остальные покрывают то же место, а сервер перестаёт сообщать об ошибках рёбер.
func _nav_drop_overlaps(verts: PackedVector3Array, polys: Array[PackedInt32Array]) -> void:
	for _pass in 4:
		var use := {}
		for pi in polys.size():
			var pl := polys[pi]
			for k in pl.size():
				var a := pl[k]
				var b := pl[(k + 1) % pl.size()]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not use.has(key):
					use[key] = []
				use[key].append([pi, a < b])
		var drop := {}
		for key in use:
			var l: Array = use[key]
			var bad := l.size() > 2
			if l.size() == 2 and l[0][1] == l[1][1]:
				bad = true
			if not bad:
				continue
			var worst := -1
			var worst_area := INF
			for e in l:
				if drop.has(e[0]):
					worst = -2
					break
				var pl := polys[e[0]]
				var area := 0.0
				for k in pl.size():
					var va := verts[pl[k]]
					var vb := verts[pl[(k + 1) % pl.size()]]
					area += va.x * vb.z - vb.x * va.z
				area = absf(area)
				if area < worst_area:
					worst_area = area
					worst = e[0]
			if worst >= 0:
				drop[worst] = true
		if drop.is_empty():
			return
		var keep: Array[PackedInt32Array] = []
		for pi in polys.size():
			if not drop.has(pi):
				keep.append(polys[pi])
		polys.assign(keep)


## `-- --navtest`: путь между центрами соседних кусков (через границу) — проверка, что куски сшиты.
func _nav_selftest() -> void:
	var map := get_world_3d().navigation_map
	for _f in 1500:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_closest_point(map, nav_tiles[0].get_center()) != Vector3.ZERO:
			break
	var cs: Array[Vector3] = []
	for t in nav_tiles:
		var c := t.get_center()
		cs.append(NavigationServer3D.map_get_closest_point(map, Vector3(c.x, 0.0, c.z)))
	var ok := 0
	var fail := 0
	for i in nav_tiles.size():
		for j in range(i + 1, nav_tiles.size()):
			if cs[i].distance_to(cs[j]) > chunk * cell * 1.1:
				continue
			var path := NavigationServer3D.map_get_path(map, cs[i], cs[j], true)
			if path.size() > 1 and path[path.size() - 1].distance_to(cs[j]) < 3.0:
				ok += 1
			else:
				fail += 1
				print("NAVTEST нет пути ", i, " -> ", j)
	print("NAVTEST %s: путей через границы кусков ок %d, нет %d" % [map_key, ok, fail])


# ------------------------------------------------------------------ случайная точка появления
## Высота, выше которой не появляемся (гребни и горы у края).
var spawn_max_h := 30.0


## Точки по краю игровой зоны: пологий склон, далеко от противников и целей, не в камне/дереве.
## Возвращает [позиция, yaw лицом к центру карты]. Для сетевой игры отряд появляется вместе в одной точке.
func random_spawn() -> Array:
	var cands: Array = [spawn_point]
	var space := get_world_3d().direct_space_state
	var lim := play_half - 6.0
	for i in 64:
		var a := TAU * i / 64.0
		for rk in [0.88, 0.8]:
			var x: float = cos(a) * play_half * float(rk)
			var z: float = sin(a) * play_half * float(rk)
			if absf(x) > lim or absf(z) > lim:
				continue
			var gy := ground(x, z)
			var slope := maxf(absf(ground(x + 2.0, z) - ground(x - 2.0, z)), absf(ground(x, z + 2.0) - ground(x, z - 2.0))) / 4.0
			if slope > 0.3 or gy > spawn_max_h:
				continue
			var p := Vector3(x, gy, z)
			var ok := true
			for sp in enemy_spawns:
				if Vector2(x, z).distance_to(Vector2((sp.pos as Vector3).x, (sp.pos as Vector3).z)) < 80.0:
					ok = false
					break
				for rp in (sp.route as PackedVector3Array):
					if Vector2(x, z).distance_to(Vector2(rp.x, rp.z)) < 70.0:
						ok = false
						break
				if not ok:
					break
			for k in objectives:
				var op: Vector3 = objectives[k]
				if Vector2(x, z).distance_to(Vector2(op.x, op.z)) < 70.0:
					ok = false
			if not ok:
				continue
			# сверху вниз: луч должен упасть на землю, а не на камень/крышу; и рядом не должно быть препятствий
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 40, 0), p - Vector3(0, 5, 0), Game.L_WORLD)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or absf((hit.position as Vector3).y - gy) > 0.3:
				continue
			var sh := PhysicsShapeQueryParameters3D.new()
			var sph := SphereShape3D.new()
			sph.radius = 1.2
			sh.shape = sph
			sh.transform = Transform3D(Basis(), p + Vector3(0, 1.5, 0))
			sh.collision_mask = Game.L_WORLD
			if not space.intersect_shape(sh, 1).is_empty():
				continue
			cands.append(p + Vector3(0, 0.2, 0))
	var pos: Vector3 = cands[randi() % cands.size()]
	var d := Vector3(orbit_center.x - pos.x, 0, orbit_center.z - pos.z)
	return [pos, atan2(-d.x, -d.z)]


# ------------------------------------------------------------------ машины
## Стоянки: [Vector3(x, 0, z), yaw, "mil" | "civ" | "any"] — на каждой с вероятностью vehicle_fill
## случайная модель подходящего типа (проверка, что место свободно; иначе сдвиг до 4 м).
var vehicle_spots: Array = []
var vehicle_fill := 0.7
## Патрули на машинах: [индекс дороги в roads, размер экипажа].
var vehicle_patrols: Array = []


func spawn_vehicles(parent: Node) -> void:
	var r := RandomNumberGenerator.new()
	if Game.test_mode():
		r.seed = 4242
	else:
		r.randomize()
	for s in vehicle_spots:
		if r.randf() > vehicle_fill:
			continue
		var kinds: Array = VehDefs.military() if s[2] == "mil" else (VehDefs.civil() if s[2] == "civ" else VehDefs.ids())
		var p: Vector3 = s[0]
		_place_vehicle(parent, kinds[r.randi() % kinds.size()], r.randi(), p.x, p.z, float(s[1]), r)
	# свободная машина у точки появления игрока — на большой карте до целей далеко
	var pl: Player = Game.player
	if pl and size > 800.0:
		var away := Vector3(orbit_center.x - pl.global_position.x, 0, orbit_center.z - pl.global_position.z).normalized()
		var side := away.cross(Vector3.UP)
		for k in 6:
			var c := pl.global_position + side * (7.0 + k * 2.0) * (1.0 if k % 2 == 0 else -1.0) + away * 3.0
			var ids := VehDefs.ids()
			if _place_vehicle(parent, ids[r.randi() % ids.size()], r.randi(), c.x, c.z, atan2(-away.x, -away.z), r, 0.0) != null:
				break
	for pt in vehicle_patrols:
		var road: PackedVector2Array = roads[int(pt[0])]
		var path := PackedVector3Array()
		for i in road.size() - 1:
			var steps := maxi(1, int(road[i].distance_to(road[i + 1]) / 10.0))
			for k in steps:
				var q := road[i].lerp(road[i + 1], float(k) / steps)
				path.append(Vector3(q.x, ground(q.x, q.y), q.y))
		var last := road[road.size() - 1]
		path.append(Vector3(last.x, ground(last.x, last.y), last.y))
		var start := r.randi_range(0, path.size() - 2)
		var dir := path[start + 1] - path[start]
		var mil := VehDefs.military()
		var v := _place_vehicle(parent, mil[r.randi() % mil.size()], r.randi(), path[start].x, path[start].z, atan2(-dir.x, -dir.z), r, 0.0)
		if v == null:
			continue
		var crew: Array = []
		for c in int(pt[1]):
			crew.append({"pos": Vector3.ZERO, "yaw": 0.0, "kind": 1 if c == 0 and r.randf() < 0.5 else 0, "route": PackedVector3Array(), "hold": false})
		v.start_ai(path, crew, start + 1)


## Ставит машину на землю (по склону), если место свободно (иначе пробует сдвиги до jitter м). null — не влезла.
func _place_vehicle(parent: Node, id: String, color: int, x: float, z: float, yaw: float, r: RandomNumberGenerator, jitter := 4.0) -> Vehicle:
	var m: VehicleModel = load("res://assets/vehicles/%s.res" % id)
	var bb := m.body_aabb
	var space := get_world_3d().direct_space_state
	for t in 6:
		var px := x + (r.randf_range(-jitter, jitter) if t > 0 else 0.0)
		var pz := z + (r.randf_range(-jitter, jitter) if t > 0 else 0.0)
		if absf(px) > play_half - 4.0 or absf(pz) > play_half - 4.0:
			continue
		var gy := ground(px, pz)
		var nrm := Vector3(ground(px - 1.0, pz) - ground(px + 1.0, pz), 2.0, ground(px, pz - 1.0) - ground(px, pz + 1.0)).normalized()
		if nrm.y < 0.88:
			continue
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		fwd = (fwd - nrm * fwd.dot(nrm)).normalized()
		var basis := Basis.looking_at(fwd, nrm)
		var xf := Transform3D(basis, Vector3(px, gy + 0.05, pz))
		# место свободно: коробка кузова (приподнятая над землёй) ни с чем не пересекается
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(bb.size.x + 0.4, maxf(0.4, bb.end.y - 0.6), bb.size.z + 0.4)
		q.shape = box
		q.transform = xf * Transform3D(Basis(), Vector3(0, 0.6 + box.size.y * 0.5, bb.get_center().z))
		q.collision_mask = Game.L_WORLD | Game.L_FENCE
		if not space.intersect_shape(q, 1).is_empty():
			continue
		var v := Vehicle.new()
		v.setup(id, color, xf)
		parent.add_child(v)
		Game.vehicles.append(v)
		return v
	return null


# ------------------------------------------------------------------ картинка карты (мини-карта и полная карта)
const MAP_TEX := 768


## Полуширина области, которую охватывает картинка карты (север вверху, центр — начало координат).
func map_half() -> float:
	return play_half + 16.0


static func map_tex_path(key: String) -> String:
	return "res://assets/maps/%s_map.res" % key


## Запекает картинку карты в assets/maps/<ключ>_map.res: рельеф с затенением, дороги/дворы, коробки коллизий построек.
## Работает для любой карты-наследника (ground(), _vertex_color(), roads, коллизии из дерева сцены).
## Вызывается из режима --bake после build().
func bake_map_image() -> void:
	var t0 := Time.get_ticks_msec()
	var T := MAP_TEX
	var half := map_half()
	var step := half * 2.0 / T
	var W := T + 2
	var hs := PackedFloat32Array()
	hs.resize(W * W)
	var hmin := INF
	var hmax := -INF
	for j in W:
		for i in W:
			var h := ground((i - 0.5) * step - half, (j - 0.5) * step - half)
			hs[j * W + i] = h
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
	var img := Image.create(T, T, false, Image.FORMAT_RGB8)
	var L := sun_dir.normalized()
	var low := Color(0.40, 0.44, 0.29)
	var mid := Color(0.58, 0.54, 0.38)
	var high := Color(0.70, 0.67, 0.58)
	var rock := Color(0.50, 0.48, 0.45)
	var road_c := Color(0.80, 0.76, 0.64)
	for j in T:
		for i in T:
			var k := (j + 1) * W + (i + 1)
			var dx := (hs[k + 1] - hs[k - 1]) / (2.0 * step)
			var dz := (hs[k + W] - hs[k - W]) / (2.0 * step)
			var nrm := Vector3(-dx, 1.0, -dz).normalized()
			var shade := clampf(0.62 + (nrm.dot(L) - L.y) * 1.7, 0.25, 1.25)
			var tn := clampf((hs[k] - hmin) / maxf(hmax - hmin, 1.0), 0.0, 1.0)
			var col := low.lerp(mid, smoothstep(0.0, 0.5, tn)).lerp(high, smoothstep(0.5, 1.0, tn))
			col = col.lerp(rock, smoothstep(0.86, 0.66, nrm.y))
			var wx := (i + 0.5) * step - half
			var wz := (j + 0.5) * step - half
			var vc := _vertex_color(wx, wz, nrm, road_dist(wx, wz))
			col = col.lerp(road_c, clampf(vc.b, 0.0, 1.0) * 0.85)
			img.set_pixel(i, j, Color(col.r * shade, col.g * shade, col.b * shade))
	# постройки и укрытия: коробки коллизий выше человеческого роста
	var boxes := 0
	var wall_c := Color(0.22, 0.2, 0.19)
	var stack: Array = [self]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for ch in nd.get_children():
			stack.append(ch)
		if not (nd is StaticBody3D) or (nd as StaticBody3D).collision_layer & Game.L_WORLD == 0:
			continue
		for cs in nd.get_children():
			if not (cs is CollisionShape3D) or not ((cs as CollisionShape3D).shape is BoxShape3D):
				continue
			var xf: Transform3D = (cs as CollisionShape3D).global_transform
			var bs: Vector3 = ((cs as CollisionShape3D).shape as BoxShape3D).size
			var bb := xf * AABB(-bs * 0.5, bs)
			if bb.size.y < 2.4 or bb.end.y < ground(xf.origin.x, xf.origin.z) + 2.2:
				continue
			boxes += 1
			var inv := xf.affine_inverse()
			var i0 := clampi(int(floor((bb.position.x + half) / step)), 0, T - 1)
			var i1 := clampi(int(floor((bb.end.x + half) / step)), 0, T - 1)
			var j0 := clampi(int(floor((bb.position.z + half) / step)), 0, T - 1)
			var j1 := clampi(int(floor((bb.end.z + half) / step)), 0, T - 1)
			for jj in range(j0, j1 + 1):
				for ii in range(i0, i1 + 1):
					var lp: Vector3 = inv * Vector3((ii + 0.5) * step - half, xf.origin.y, (jj + 0.5) * step - half)
					if absf(lp.x) <= bs.x * 0.5 + step * 0.45 and absf(lp.z) <= bs.z * 0.5 + step * 0.45:
						img.set_pixel(ii, jj, wall_c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var err := ResourceSaver.save(tex, map_tex_path(map_key))
	print("карта %s: %dx%d, коробок построек %d, сохранение=%d, %d мс" % [map_key, T, T, boxes, err, Time.get_ticks_msec() - t0])
	img.save_png("user://map_%s.png" % map_key)


# ------------------------------------------------------------------ тепловизор
var _thermal_saved := {}


## Мир для тепловизора: без неба и бликов, тусклое солнце — фон «холодный», солдаты (излучение) — «горячие».
func set_thermal(on: bool) -> void:
	if env == null:
		return
	if on:
		_thermal_saved = {"bg": env.background_mode, "amb": env.ambient_light_source, "ae": env.ambient_light_energy,
			"ac": env.ambient_light_color, "fog": env.fog_enabled, "glow": env.glow_enabled, "sun": sun.light_energy,
			"refl": env.reflected_light_source}
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.05, 0.05, 0.05)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.5, 0.5)
		env.ambient_light_energy = 0.32
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.fog_enabled = false
		env.glow_enabled = false
		sun.light_energy = 0.4
	elif not _thermal_saved.is_empty():
		env.background_mode = _thermal_saved.bg
		env.ambient_light_source = _thermal_saved.amb
		env.ambient_light_energy = _thermal_saved.ae
		env.ambient_light_color = _thermal_saved.ac
		env.reflected_light_source = _thermal_saved.refl
		env.fog_enabled = _thermal_saved.fog
		env.glow_enabled = _thermal_saved.glow
		sun.light_energy = _thermal_saved.sun
